package dev.fluttercommunity.workmanager

import dev.fluttercommunity.workmanager.pigeon.ContinuedProcessingTaskRequest
import dev.fluttercommunity.workmanager.pigeon.HealthResearchTaskRequest
import dev.fluttercommunity.workmanager.pigeon.InitializeRequest
import dev.fluttercommunity.workmanager.pigeon.OneOffTaskRequest
import dev.fluttercommunity.workmanager.pigeon.PeriodicTaskRequest
import dev.fluttercommunity.workmanager.pigeon.ProcessingTaskRequest
import dev.fluttercommunity.workmanager.pigeon.WorkInfoData
import dev.fluttercommunity.workmanager.pigeon.WorkmanagerHostApi
import io.flutter.embedding.engine.plugins.FlutterPlugin

private const val INIT_REQUIRED =
    "You have not properly initialized the Flutter WorkManager Package. " +
        "You should ensure you have called the 'initialize' function first!"

/** pigeon связывает типизированный api workmanager с android */
class WorkmanagerPlugin :
    FlutterPlugin,
    WorkmanagerHostApi {
    private var workManagerWrapper: WorkManagerWrapper? = null
    private lateinit var preferenceManager: SharedPreferenceHelper

    private var currentDispatcherHandle: Long = -1L

    /** привязка движка нужна для передачи прогресса приложению */
    private var pluginBinding: FlutterPlugin.FlutterPluginBinding? = null

    /** воркер привязан только к плагину своего движка, плагин приложения остаётся без воркера */
    private var boundWorker: BackgroundWorker? = null

    internal fun bindWorker(worker: BackgroundWorker) {
        boundWorker = worker
    }

    /** поздняя очистка старого воркера не должна снимать привязку его замены */
    internal fun unbindWorker(worker: BackgroundWorker) {
        if (boundWorker === worker) {
            boundWorker = null
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        pluginBinding = binding
        preferenceManager =
            SharedPreferenceHelper(
                binding.applicationContext,
                object : SharedPreferenceHelper.DispatcherHandleListener {
                    override fun onDispatcherHandleChanged(handle: Long) {
                        currentDispatcherHandle = handle
                    }
                },
            )
        workManagerWrapper = WorkManagerWrapper(binding.applicationContext)
        WorkmanagerHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        WorkmanagerHostApi.setUp(binding.binaryMessenger, null)
        workManagerWrapper = null
        pluginBinding = null
    }

    override fun initialize(
        request: InitializeRequest,
        callback: (Result<Unit>) -> Unit,
    ) {
        try {
            val handle = request.callbackHandle

            preferenceManager.saveCallbackDispatcherHandleKey(handle)

            currentDispatcherHandle = handle

            // прогресс отправляем через messenger движка, который инициализировал плагин приложения
            pluginBinding?.let {
                ProgressUpdateCoordinator.setAppMessenger(enabled = true, messenger = it.binaryMessenger)
            }

            callback(Result.success(Unit))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    override fun registerOneOffTask(
        request: OneOffTaskRequest,
        callback: (Result<Unit>) -> Unit,
    ) {
        if (currentDispatcherHandle == -1L) {
            callback(Result.failure(Exception(INIT_REQUIRED)))
            return
        }

        try {
            workManagerWrapper!!.enqueueOneOffTask(request = request)
            callback(Result.success(Unit))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    override fun registerPeriodicTask(
        request: PeriodicTaskRequest,
        callback: (Result<Unit>) -> Unit,
    ) {
        if (currentDispatcherHandle == -1L) {
            callback(Result.failure(Exception(INIT_REQUIRED)))
            return
        }

        try {
            workManagerWrapper!!.enqueuePeriodicTask(request = request)
            callback(Result.success(Unit))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    override fun registerProcessingTask(
        request: ProcessingTaskRequest,
        callback: (Result<Unit>) -> Unit,
    ) {
        // такие задачи поддерживаются только на ios
        callback(Result.failure(UnsupportedOperationException("Processing tasks are not supported on Android")))
    }

    override fun registerHealthResearchTask(
        request: HealthResearchTaskRequest,
        callback: (Result<Unit>) -> Unit,
    ) {
        // исследовательские задачи доступны только с ios 17
        callback(
            Result.failure(
                UnsupportedOperationException(
                    "Health research tasks are not supported on Android",
                ),
            ),
        )
    }

    override fun registerContinuedProcessingTask(
        request: ContinuedProcessingTaskRequest,
        callback: (Result<Unit>) -> Unit,
    ) {
        // продолженные задачи доступны только с ios 26
        callback(
            Result.failure(
                UnsupportedOperationException(
                    "Continued processing tasks are not supported on Android",
                ),
            ),
        )
    }

    override fun cancelByUniqueName(
        uniqueName: String,
        callback: (Result<Unit>) -> Unit,
    ) {
        try {
            workManagerWrapper!!.cancelByUniqueName(uniqueName)
            callback(Result.success(Unit))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    override fun cancelByTag(
        tag: String,
        callback: (Result<Unit>) -> Unit,
    ) {
        try {
            workManagerWrapper!!.cancelByTag(tag)
            callback(Result.success(Unit))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    override fun cancelAll(callback: (Result<Unit>) -> Unit) {
        try {
            workManagerWrapper!!.cancelAll()
            callback(Result.success(Unit))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    override fun isScheduledByUniqueName(
        uniqueName: String,
        callback: (Result<Boolean>) -> Unit,
    ) {
        try {
            val workInfos = workManagerWrapper!!.getWorkInfoByUniqueName(uniqueName).get()
            val scheduled =
                workInfos.isNotEmpty() &&
                    workInfos.all { it.state == androidx.work.WorkInfo.State.ENQUEUED || it.state == androidx.work.WorkInfo.State.RUNNING }
            callback(Result.success(scheduled))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    override fun printScheduledTasks(callback: (Result<String>) -> Unit) {
        // на android не поддерживается
        callback(Result.failure(UnsupportedOperationException("printScheduledTasks is not supported on Android")))
    }

    override fun getWorkInfoByUniqueName(
        uniqueName: String,
        callback: (Result<WorkInfoData?>) -> Unit,
    ) {
        try {
            val workInfos = workManagerWrapper!!.getWorkInfoByUniqueName(uniqueName).get()
            // имя ведёт к цепочке задач, берём её начало; пустая цепочка после отмены означает отсутствие записи
            callback(Result.success(workInfos.firstOrNull()?.toWorkInfoData(uniqueName)))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    override fun reportProgress(
        progress: Map<String?, Any?>?,
        callback: (Result<Unit>) -> Unit,
    ) {
        val worker = boundWorker
        if (worker == null) {
            // прогресс вне работающей задачи игнорируем, чтобы общий для платформ обработчик не падал
            callback(Result.success(Unit))
            return
        }
        worker.reportProgress(progress)
        callback(Result.success(Unit))
    }

    override fun notifyBackgroundChannelInitialized(callback: (Result<Unit>) -> Unit) {
        val worker = boundWorker
        if (worker != null) {
            // сигнал dart относится к движку этого плагина, без привязанного воркера выполнять нечего
            worker.onDartBackgroundChannelInitialized()
        }
        callback(Result.success(Unit))
    }

    override fun setProgressListener(
        enabled: Boolean,
        callback: (Result<Unit>) -> Unit,
    ) {
        // слушатель прогресса всегда привязывается к движку приложения
        pluginBinding?.let {
            ProgressUpdateCoordinator.setAppMessenger(enabled = enabled, messenger = it.binaryMessenger)
        }
        callback(Result.success(Unit))
    }
}
