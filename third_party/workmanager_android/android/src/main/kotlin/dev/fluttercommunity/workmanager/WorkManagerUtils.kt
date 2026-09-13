package dev.fluttercommunity.workmanager

import android.content.Context
import android.net.Uri
import android.os.Build
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import dev.fluttercommunity.workmanager.pigeon.TaskStatus
import dev.fluttercommunity.workmanager.pigeon.WorkState
import java.util.concurrent.TimeUnit

const val DEFAULT_INITIAL_DELAY_SECONDS = 0L

val defaultOneOffExistingWorkPolicy = ExistingWorkPolicy.KEEP
val defaultPeriodExistingWorkPolicy = ExistingPeriodicWorkPolicy.UPDATE
val defaultConstraints: Constraints = Constraints.NONE
val defaultOutOfQuotaPolicy: OutOfQuotaPolicy? = null

/** flex задаём только явно, иначе первый запуск сдвинется относительно initialDelay */
internal fun createPeriodicWorkRequest(
    taskName: String,
    inputData: Map<String, Any?>?,
    foregroundServiceConfig: dev.fluttercommunity.workmanager.pigeon.ForegroundServiceConfig? = null,
    uniqueName: String? = null,
    frequencySeconds: Long,
    flexIntervalSeconds: Long?,
    initialDelaySeconds: Long?,
    constraints: Constraints,
    backoffPolicy: dev.fluttercommunity.workmanager.pigeon.BackoffPolicyConfig?,
    tag: String?,
): PeriodicWorkRequest {
    val builder =
        if (flexIntervalSeconds != null) {
            PeriodicWorkRequest
                .Builder(
                    BackgroundWorker::class.java,
                    frequencySeconds,
                    TimeUnit.SECONDS,
                    flexIntervalSeconds,
                    TimeUnit.SECONDS,
                )
        } else {
            PeriodicWorkRequest
                .Builder(
                    BackgroundWorker::class.java,
                    frequencySeconds,
                    TimeUnit.SECONDS,
                )
        }
    return builder
        .setInputData(buildTaskInputData(taskName, inputData, foregroundServiceConfig, uniqueName))
        .setInitialDelay(
            initialDelaySeconds ?: DEFAULT_INITIAL_DELAY_SECONDS,
            TimeUnit.SECONDS,
        ).setConstraints(constraints)
        .apply {
            backoffPolicy?.let { backoffConfig ->
                if (backoffConfig.backoffPolicy != null && backoffConfig.backoffDelayMillis != null) {
                    setBackoffCriteria(
                        backoffConfig.backoffPolicy.toAndroidBackoffPolicy(),
                        backoffConfig.backoffDelayMillis.toLong(),
                        TimeUnit.MILLISECONDS,
                    )
                }
            }
        }.apply {
            tag?.let(::addTag)
            // политика исчерпания квоты не применяется к периодическим задачам
        }.build()
}

/** состояние BLOCKED передаём как SCHEDULED, время завершения на android всегда null */
internal fun androidx.work.WorkInfo.toWorkInfoData(uniqueName: String): dev.fluttercommunity.workmanager.pigeon.WorkInfoData {
    val workState =
        when (state) {
            androidx.work.WorkInfo.State.ENQUEUED, androidx.work.WorkInfo.State.BLOCKED -> WorkState.SCHEDULED
            androidx.work.WorkInfo.State.RUNNING -> WorkState.RUNNING
            androidx.work.WorkInfo.State.SUCCEEDED -> WorkState.SUCCEEDED
            androidx.work.WorkInfo.State.FAILED -> WorkState.FAILED
            androidx.work.WorkInfo.State.CANCELLED -> WorkState.CANCELLED
        }
    return dev.fluttercommunity.workmanager.pigeon.WorkInfoData(
        uniqueName = uniqueName,
        state = workState,
        isPeriodic = periodicityInfo != null,
        taskName = outputData.getString(BackgroundWorker.DART_TASK_KEY),
        tags = tags.sorted().map { it as String? },
        lastFinishedAtMillis = null,
    )
}

private fun dev.fluttercommunity.workmanager.pigeon.ExistingWorkPolicy.toAndroidWorkPolicy(): ExistingWorkPolicy =
    when (this) {
        dev.fluttercommunity.workmanager.pigeon.ExistingWorkPolicy.APPEND -> ExistingWorkPolicy.APPEND_OR_REPLACE
        dev.fluttercommunity.workmanager.pigeon.ExistingWorkPolicy.KEEP -> ExistingWorkPolicy.KEEP
        dev.fluttercommunity.workmanager.pigeon.ExistingWorkPolicy.REPLACE -> ExistingWorkPolicy.REPLACE
        dev.fluttercommunity.workmanager.pigeon.ExistingWorkPolicy.UPDATE -> ExistingWorkPolicy.APPEND_OR_REPLACE
    }

private fun dev.fluttercommunity.workmanager.pigeon.ExistingPeriodicWorkPolicy.toAndroidPeriodicWorkPolicy(): ExistingPeriodicWorkPolicy =
    when (this) {
        dev.fluttercommunity.workmanager.pigeon.ExistingPeriodicWorkPolicy.KEEP -> ExistingPeriodicWorkPolicy.KEEP
        dev.fluttercommunity.workmanager.pigeon.ExistingPeriodicWorkPolicy.REPLACE -> ExistingPeriodicWorkPolicy.REPLACE
        dev.fluttercommunity.workmanager.pigeon.ExistingPeriodicWorkPolicy.UPDATE -> ExistingPeriodicWorkPolicy.UPDATE
    }

private fun dev.fluttercommunity.workmanager.pigeon.OutOfQuotaPolicy.toAndroidOutOfQuotaPolicy(): OutOfQuotaPolicy =
    when (this) {
        dev.fluttercommunity.workmanager.pigeon.OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST ->
            OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST
        dev.fluttercommunity.workmanager.pigeon.OutOfQuotaPolicy.DROP_WORK_REQUEST -> OutOfQuotaPolicy.DROP_WORK_REQUEST
    }

internal fun dev.fluttercommunity.workmanager.pigeon.Constraints.toAndroidConstraints(): Constraints {
    val builder = Constraints.Builder()

    networkType?.let { builder.setRequiredNetworkType(it.toAndroidNetworkType()) }
    requiresBatteryNotLow?.let { builder.setRequiresBatteryNotLow(it) }
    requiresCharging?.let { builder.setRequiresCharging(it) }
    requiresDeviceIdle?.let {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            builder.setRequiresDeviceIdle(it)
        }
    }
    requiresStorageNotLow?.let { builder.setRequiresStorageNotLow(it) }
    contentUriTriggers?.forEach { trigger ->
        trigger?.let {
            if (isContentUriTriggerSupported()) {
                builder.addContentUriTrigger(Uri.parse(it.uri), it.triggerForDescendants)
            }
        }
    }

    return builder.build()
}

/** до android 7 триггеры content uri молча игнорируются системой */
internal fun isContentUriTriggerSupported(sdkInt: Int = Build.VERSION.SDK_INT): Boolean = sdkInt >= Build.VERSION_CODES.N

private fun dev.fluttercommunity.workmanager.pigeon.NetworkType.toAndroidNetworkType(): NetworkType =
    when (this) {
        dev.fluttercommunity.workmanager.pigeon.NetworkType.CONNECTED -> NetworkType.CONNECTED
        dev.fluttercommunity.workmanager.pigeon.NetworkType.METERED -> NetworkType.METERED
        dev.fluttercommunity.workmanager.pigeon.NetworkType.NOT_REQUIRED -> NetworkType.NOT_REQUIRED
        dev.fluttercommunity.workmanager.pigeon.NetworkType.NOT_ROAMING -> NetworkType.NOT_ROAMING
        dev.fluttercommunity.workmanager.pigeon.NetworkType.UNMETERED -> NetworkType.UNMETERED
        dev.fluttercommunity.workmanager.pigeon.NetworkType.TEMPORARILY_UNMETERED -> {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                NetworkType.TEMPORARILY_UNMETERED
            } else {
                NetworkType.UNMETERED
            }
        }
    }

private fun dev.fluttercommunity.workmanager.pigeon.BackoffPolicy.toAndroidBackoffPolicy(): BackoffPolicy =
    when (this) {
        dev.fluttercommunity.workmanager.pigeon.BackoffPolicy.EXPONENTIAL -> BackoffPolicy.EXPONENTIAL
        dev.fluttercommunity.workmanager.pigeon.BackoffPolicy.LINEAR -> BackoffPolicy.LINEAR
    }

private fun Map<String?, Any?>.filterNotNullKeys(): Map<String, Any> =
    this
        .mapNotNull { (key, value) ->
            if (key != null && value != null) key to value else null
        }.toMap()

internal fun createOneOffWorkRequest(request: dev.fluttercommunity.workmanager.pigeon.OneOffTaskRequest): OneTimeWorkRequest {
    val builder =
        OneTimeWorkRequest
            .Builder(BackgroundWorker::class.java)
            .setInputData(
                buildTaskInputData(
                    request.taskName,
                    request.inputData?.filterNotNullKeys(),
                    request.foregroundServiceConfig,
                    request.uniqueName,
                ),
            ).setInitialDelay(
                request.initialDelaySeconds ?: DEFAULT_INITIAL_DELAY_SECONDS,
                TimeUnit.SECONDS,
            ).setConstraints(
                request.constraints?.toAndroidConstraints() ?: defaultConstraints,
            ).apply {
                request.backoffPolicy?.let { backoffConfig ->
                    if (backoffConfig.backoffPolicy != null && backoffConfig.backoffDelayMillis != null) {
                        setBackoffCriteria(
                            backoffConfig.backoffPolicy.toAndroidBackoffPolicy(),
                            backoffConfig.backoffDelayMillis.toLong(),
                            TimeUnit.MILLISECONDS,
                        )
                    }
                }
            }.apply {
                request.tag?.let(::addTag)
                if (request.expedited == true) {
                    setExpedited(
                        request.outOfQuotaPolicy?.toAndroidOutOfQuotaPolicy()
                            ?: OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST,
                    )
                }
            }
    return builder.build()
}

class WorkManagerWrapper(
    val context: Context,
) {
    private val workManager = WorkManager.getInstance(context)

    fun enqueueOneOffTask(request: dev.fluttercommunity.workmanager.pigeon.OneOffTaskRequest) {
        try {
            if (request.expedited == true) {
                // на android 14 срочные задачи используют shortService, проверяем, что приложение не удалило её разрешение
                requireForegroundServicePermission(
                    context,
                    // в sdk нет константы этого разрешения, поэтому используем строку из манифеста
                    "android.permission.FOREGROUND_SERVICE_SHORT_SERVICE",
                    "expedited work (setExpedited)",
                    "FOREGROUND_SERVICE_SHORT_SERVICE is declared by the plugin by default; " +
                        "keep it if you use expedited work (see the workmanager_android " +
                        "README, issue #725).",
                )
            }
            val oneOffTaskRequest = createOneOffWorkRequest(request)
            workManager.enqueueUniqueWork(
                request.uniqueName,
                request.existingWorkPolicy?.toAndroidWorkPolicy()
                    ?: defaultOneOffExistingWorkPolicy,
                oneOffTaskRequest,
            )

            val taskInfo =
                TaskDebugInfo(
                    taskName = request.taskName,
                    uniqueName = request.uniqueName,
                    inputData = request.inputData?.filterNotNullKeys(),
                    startTime = System.currentTimeMillis(),
                )
            WorkmanagerDebug.onTaskStatusUpdate(context, taskInfo, TaskStatus.SCHEDULED)
        } catch (e: Exception) {
            throw e
        }
    }

    fun enqueuePeriodicTask(request: dev.fluttercommunity.workmanager.pigeon.PeriodicTaskRequest) {
        val periodicTaskRequest =
            createPeriodicWorkRequest(
                taskName = request.taskName,
                inputData = request.inputData?.filterNotNullKeys(),
                foregroundServiceConfig = request.foregroundServiceConfig,
                uniqueName = request.uniqueName,
                frequencySeconds = request.frequencySeconds,
                flexIntervalSeconds = request.flexIntervalSeconds,
                initialDelaySeconds = request.initialDelaySeconds,
                constraints = request.constraints?.toAndroidConstraints() ?: defaultConstraints,
                backoffPolicy = request.backoffPolicy,
                tag = request.tag,
            )
        workManager.enqueueUniquePeriodicWork(
            request.uniqueName,
            request.existingWorkPolicy?.toAndroidPeriodicWorkPolicy()
                ?: defaultPeriodExistingWorkPolicy,
            periodicTaskRequest,
        )

        val taskInfo =
            TaskDebugInfo(
                taskName = request.taskName,
                uniqueName = request.uniqueName,
                inputData = request.inputData?.filterNotNullKeys(),
                startTime = System.currentTimeMillis(),
            )
        WorkmanagerDebug.onTaskStatusUpdate(context, taskInfo, TaskStatus.SCHEDULED)
    }

    fun getWorkInfoByUniqueName(uniqueWorkName: String) = workManager.getWorkInfosForUniqueWork(uniqueWorkName)

    fun cancelByUniqueName(uniqueWorkName: String) = workManager.cancelUniqueWork(uniqueWorkName)

    fun cancelByTag(tag: String) = workManager.cancelAllWorkByTag(tag)

    fun cancelAll() = workManager.cancelAllWork()
}
