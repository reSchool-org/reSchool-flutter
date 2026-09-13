package dev.fluttercommunity.workmanager

import dev.fluttercommunity.workmanager.pigeon.TaskStatus

/** причина остановки доступна с android 12, на старых версиях возвращаем STOP_REASON_UNKNOWN */
object StopReasonUtils {
    const val STOP_REASON_UNKNOWN = 0
    const val STOP_REASON_CANCELLED_BY_APP = 3
    const val STOP_REASON_SYSTEM_IGNORED_CANCELLED_BY_APP = 4

    /** отмена приложением даёт CANCELLED, остальные остановки сохраняют прежнее состояние FAILED */
    fun toTaskStatus(stopReason: Int): TaskStatus =
        when (stopReason) {
            STOP_REASON_CANCELLED_BY_APP,
            STOP_REASON_SYSTEM_IGNORED_CANCELLED_BY_APP,
            -> TaskStatus.CANCELLED
            else -> TaskStatus.FAILED
        }
}
