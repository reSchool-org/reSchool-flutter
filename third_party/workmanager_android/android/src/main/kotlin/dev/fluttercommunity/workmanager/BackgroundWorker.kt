package dev.fluttercommunity.workmanager

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.concurrent.futures.CallbackToFutureAdapter
import androidx.work.ListenableWorker
import androidx.work.WorkerParameters
import com.google.common.util.concurrent.ListenableFuture
import dev.fluttercommunity.workmanager.pigeon.ForegroundServiceConfig
import dev.fluttercommunity.workmanager.pigeon.TaskStatus
import dev.fluttercommunity.workmanager.pigeon.WorkmanagerFlutterApi
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.view.FlutterCallbackInformation
import java.security.SecureRandom
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean

/** воркер ждёт результат flutter, прежде чем завершить фоновую задачу */
class BackgroundWorker(
    applicationContext: Context,
    private val workerParams: WorkerParameters,
) : ListenableWorker(applicationContext, workerParams) {
    private lateinit var flutterApi: WorkmanagerFlutterApi

    companion object {
        const val PAYLOAD_KEY = "dev.fluttercommunity.workmanager.INPUT_DATA"
        const val DART_TASK_KEY = "dev.fluttercommunity.workmanager.DART_TASK"

        /** таймаут превращает потерянный сигнал готовности dart в видимую ошибку вместо вечного RUNNING */
        const val DART_INITIALIZATION_TIMEOUT_MILLIS = 30_000L
    }

    private val payload
        get() = decodePayload(workerParams.inputData.keyValueMap)

    private val dartTask
        get() = workerParams.inputData.getString(DART_TASK_KEY)

    /** у старых сохранённых задач уникальное имя может отсутствовать */
    val uniqueName: String?
        get() = workerParams.inputData.getString(UNIQUE_NAME_KEY)

    private val runAttemptCount = workerParams.runAttemptCount
    private val randomThreadIdentifier = SecureRandom().nextInt()

    /** движок flutter требует главный поток, поэтому вызов onStopped из потока workmanager перенаправляем через handler */
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var engine: FlutterEngine? = null

    private var initializationWatchdog: DartInitializationWatchdog? = null

    /** повторный сигнал готовности dart не должен запускать задачу снова */
    private val taskStarted = AtomicBoolean(false)

    /** прогресс приходит в плагин движка этой задачи, привязка направляет его нужному воркеру */
    private var boundPlugin: WorkmanagerPlugin? = null

    private var startTime: Long = 0

    private var completer: CallbackToFutureAdapter.Completer<Result>? = null

    private var resolvableFuture =
        CallbackToFutureAdapter.getFuture { completer ->
            this.completer = completer
            null
        }

    private val foregroundServiceConfig: ForegroundServiceConfig? =
        decodeForegroundServiceConfig(workerParams.inputData)

    private val directExecutor = Executor { it.run() }

    override fun startWork(): ListenableFuture<Result> {
        startTime = System.currentTimeMillis()

        // поднимаем foreground службу до запуска dart, чтобы уведомление и приоритет процесса появились сразу
        val foregroundFuture =
            foregroundServiceConfig?.let { config ->
                setForegroundAsync(createForegroundInfo(applicationContext, config))
            }

        val flutterLoader: FlutterLoader = FlutterInjector.instance().flutterLoader()

        if (!flutterLoader.initialized()) {
            flutterLoader.startInitialization(applicationContext)
        }

        flutterLoader.ensureInitializationCompleteAsync(
            applicationContext,
            null,
            Handler(Looper.getMainLooper()),
        ) {
            engine = FlutterEngine(applicationContext)
            engine?.let { engine ->
                // привязываем воркер к плагину его движка для передачи прогресса
                (engine.plugins.get(WorkmanagerPlugin::class.java) as? WorkmanagerPlugin)?.let { plugin ->
                    boundPlugin = plugin
                    plugin.bindWorker(this)
                }
            }
            val callbackHandle = SharedPreferenceHelper.getCallbackHandle(applicationContext)
            val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(callbackHandle)

            if (callbackInfo == null) {
                val exception = IllegalStateException("Failed to resolve Dart callback for handle $callbackHandle")
                WorkmanagerDebug.onExceptionEncountered(applicationContext, null, exception)
                completer?.set(Result.failure())
                return@ensureInitializationCompleteAsync
            }

            val localDartTask = dartTask

            if (localDartTask == null) {
                val exception = IllegalStateException("Dart task is null")
                WorkmanagerDebug.onExceptionEncountered(applicationContext, null, exception)
                completer?.set(Result.failure())
                return@ensureInitializationCompleteAsync
            }

            val dartBundlePath = flutterLoader.findAppBundlePath()

            val taskInfo =
                TaskDebugInfo(
                    taskName = localDartTask,
                    inputData = payload,
                    startTime = startTime,
                    callbackHandle = callbackHandle,
                    callbackInfo = callbackInfo?.callbackName,
                )

            val startStatus = if (runAttemptCount > 0) TaskStatus.RETRYING else TaskStatus.STARTED
            WorkmanagerDebug.onTaskStatusUpdate(applicationContext, taskInfo, startStatus)

            engine?.let { engine ->
                flutterApi = WorkmanagerFlutterApi(engine.dartExecutor.binaryMessenger)

                engine.dartExecutor.executeDartCallback(
                    DartExecutor.DartCallback(
                        applicationContext.assets,
                        dartBundlePath,
                        callbackInfo,
                    ),
                )

                // ждём сигнал регистрации обработчиков dart; таймаут завершит задачу, если движок не запустится или сигнал потеряется
                val watchdog =
                    DartInitializationWatchdog(
                        handler = mainHandler,
                        timeoutMillis = DART_INITIALIZATION_TIMEOUT_MILLIS,
                    ) {
                        if (!isStopped) {
                            stopEngine(
                                Result.failure(),
                                "Dart engine did not initialize the background channel " +
                                    "within $DART_INITIALIZATION_TIMEOUT_MILLIS ms",
                            )
                        }
                    }
                initializationWatchdog = watchdog
                watchdog.arm()

                // до сигнала готовности ничего не отправляем в dart, иначе сообщение потеряется и задача зависнет
            }
        }

        return combineForegroundWithResult(foregroundFuture)
    }

    /** итоговый future ждёт запуск службы и завершение dart; при сбое службы задача продолжает работать в фоне */
    private fun combineForegroundWithResult(foregroundFuture: ListenableFuture<*>?): ListenableFuture<Result> {
        if (foregroundFuture == null) {
            return resolvableFuture
        }

        return CallbackToFutureAdapter.getFuture { combinedCompleter ->
            val completed = AtomicBoolean(false)
            val listener =
                Runnable {
                    if (foregroundFuture.isDone && resolvableFuture.isDone && completed.compareAndSet(false, true)) {
                        foregroundFuture.takeUnless { it.isCancelled }?.let {
                            try {
                                it.get()
                            } catch (e: Exception) {
                                WorkmanagerDebug.onExceptionEncountered(applicationContext, null, e)
                            }
                        }
                        combinedCompleter.set(resolvableFuture.get())
                    }
                }
            foregroundFuture.addListener(listener, directExecutor)
            resolvableFuture.addListener(listener, directExecutor)
            null
        }
    }

    override fun onStopped() {
        val localDartTask = dartTask
        val stopReason = workerStopReason()

        // workmanager останавливает задачу из своего потока, а flutter принимает вызовы только в главном
        // сообщаем dart об остановке до уничтожения движка, чтобы он успел сохранить состояние
        mainHandler.post {
            initializationWatchdog?.disarm()

            if (localDartTask != null && ::flutterApi.isInitialized && engine != null) {
                try {
                    flutterApi.onTaskStopped(localDartTask, stopReason.toLong()) {
                        stopEngine(null, stopReason = stopReason)
                    }
                    return@post
                } catch (e: Exception) {
                    WorkmanagerDebug.onExceptionEncountered(
                        applicationContext,
                        TaskDebugInfo(
                            taskName = localDartTask,
                            inputData = payload,
                            startTime = startTime,
                        ),
                        e,
                    )
                }
            }
            stopEngine(null, stopReason = stopReason)
        }
    }

    /** прогресс сначала сохраняем через workmanager, затем передаём приложению */
    fun reportProgress(progress: Map<String?, Any?>?) {
        val localUniqueName = uniqueName
        if (localUniqueName == null) {
            // в старой задаче нет уникального имени, поэтому прогресс не к чему привязать
            WorkmanagerDebug.onExceptionEncountered(
                applicationContext,
                TaskDebugInfo(taskName = "unknown", startTime = startTime),
                IllegalStateException("Cannot report progress for a task without a unique name"),
            )
            return
        }

        setProgressAsync(encodeProgressData(progress))
        ProgressUpdateCoordinator.onProgressReported(applicationContext, localUniqueName)
    }

    private fun stopEngine(
        result: Result?,
        errorMessage: String? = null,
        stopReason: Int = StopReasonUtils.STOP_REASON_UNKNOWN,
    ) {
        val fetchDuration = System.currentTimeMillis() - startTime

        val localDartTask = dartTask

        if (localDartTask == null) {
            val exception = IllegalStateException("Dart task is null")
            WorkmanagerDebug.onExceptionEncountered(applicationContext, null, exception)
            completer?.set(Result.failure())
            return
        }

        val taskInfo =
            TaskDebugInfo(
                taskName = localDartTask,
                inputData = payload,
                startTime = startTime,
            )

        val taskResult =
            TaskResult(
                success = result is Result.Success,
                duration = fetchDuration,
                error =
                    when (result) {
                        is Result.Failure -> errorMessage ?: "Task failed"
                        else -> null
                    },
            )

        val status =
            when (result) {
                is Result.Success -> TaskStatus.COMPLETED
                is Result.Retry -> TaskStatus.RESCHEDULED
                else -> StopReasonUtils.toTaskStatus(stopReason)
            }
        WorkmanagerDebug.onTaskStatusUpdate(applicationContext, taskInfo, status, taskResult)

        // при остановке workmanager результат уже STOPPED, повторно его не завершаем
        if (result != null) {
            this.completer?.set(result)
        }

        // снимаем привязку до уничтожения движка, чтобы поздний прогресс не попал к завершённому воркеру
        boundPlugin?.unbindWorker(this)
        boundPlugin = null

        // ссылку на движок сбрасываем сразу, уничтожаем в главном потоке; повторная очистка безопасна
        val engineToDestroy = engine
        engine = null
        if (engineToDestroy != null) {
            mainHandler.post {
                engineToDestroy.destroy()
            }
        }
    }

    /** причина остановки доступна с android 12, раньше возвращаем неизвестную причину */
    private fun workerStopReason(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            stopReason
        } else {
            StopReasonUtils.STOP_REASON_UNKNOWN
        }

    /** сигнал приходит после регистрации обработчиков dart, только теперь можно безопасно отправить задачу */
    fun onDartBackgroundChannelInitialized() {
        if (isStopped) return
        mainHandler.post {
            // после остановки игнорируем запоздалую готовность dart
            if (isStopped || engine == null) return@post
            if (taskStarted.compareAndSet(false, true)) {
                initializationWatchdog?.disarm()
                executeBackgroundTask()
            }
        }
    }

    private fun executeBackgroundTask() {
        // pigeon ожидает словарь с допускающими null ключами
        val pigeonPayload = payload.mapKeys { it.key as String? }.mapValues { it.value as Object? }

        val localDartTask = dartTask

        if (localDartTask == null) {
            val exception = IllegalStateException("Dart task is null")
            WorkmanagerDebug.onExceptionEncountered(applicationContext, null, exception)

            stopEngine(Result.failure(), exception.message)
            return
        }

        flutterApi.executeTask(localDartTask, pigeonPayload) { result ->
            when {
                result.isSuccess -> {
                    val wasSuccessful = result.getOrNull() ?: false
                    stopEngine(if (wasSuccessful) Result.success() else Result.retry())
                }
                result.isFailure -> {
                    val exception = result.exceptionOrNull()
                    // ошибки задачи dart проходят через onTaskStatusUpdate как обычные неудачи
                    stopEngine(Result.failure(), exception?.message)
                }
            }
        }
    }
}
