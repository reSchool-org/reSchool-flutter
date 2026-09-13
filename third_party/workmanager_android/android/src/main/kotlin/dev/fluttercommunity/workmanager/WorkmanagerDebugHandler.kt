package dev.fluttercommunity.workmanager

import android.content.Context
import dev.fluttercommunity.workmanager.pigeon.TaskStatus

data class TaskDebugInfo(
    val taskName: String,
    val uniqueName: String? = null,
    val inputData: Map<String, Any?>? = null,
    val startTime: Long,
    val callbackHandle: Long? = null,
    val callbackInfo: String? = null,
)

data class TaskResult(
    val success: Boolean,
    val duration: Long,
    val error: String? = null,
)

/** по умолчанию обработчики отладки ничего не делают, нужные события можно переопределить */
abstract class WorkmanagerDebug {
    companion object {
        @JvmStatic
        private var current: WorkmanagerDebug = object : WorkmanagerDebug() {}

        @JvmStatic
        fun setCurrent(handler: WorkmanagerDebug) {
            current = handler
        }

        @JvmStatic
        fun getCurrent(): WorkmanagerDebug = current

        internal fun onTaskStatusUpdate(
            context: Context,
            taskInfo: TaskDebugInfo,
            status: TaskStatus,
            result: TaskResult? = null,
        ) {
            current.onTaskStatusUpdate(context, taskInfo, status, result)
        }

        internal fun onExceptionEncountered(
            context: Context,
            taskInfo: TaskDebugInfo?,
            exception: Throwable,
        ) {
            current.onExceptionEncountered(context, taskInfo, exception)
        }
    }

    open fun onTaskStatusUpdate(
        context: Context,
        taskInfo: TaskDebugInfo,
        status: TaskStatus,
        result: TaskResult?,
    ) {
    }

    open fun onExceptionEncountered(
        context: Context,
        taskInfo: TaskDebugInfo?,
        exception: Throwable,
    ) {
    }
}
