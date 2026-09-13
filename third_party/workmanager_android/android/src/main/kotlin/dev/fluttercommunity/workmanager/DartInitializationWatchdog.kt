package dev.fluttercommunity.workmanager

import android.os.Handler
import java.util.concurrent.atomic.AtomicBoolean

/** таймаут срабатывает один раз после arm, чтобы потерянный сигнал dart не оставил задачу в RUNNING */
internal class DartInitializationWatchdog(
    private val handler: Handler,
    private val timeoutMillis: Long,
    private val timeoutAction: () -> Unit,
) {
    private val armed = AtomicBoolean(false)
    private val timeoutRunnable =
        Runnable {
            if (armed.compareAndSet(true, false)) {
                timeoutAction()
            }
        }

    /** повторный arm не перезапускает уже работающий таймер */
    fun arm() {
        if (armed.compareAndSet(false, true)) {
            handler.postDelayed(timeoutRunnable, timeoutMillis)
        }
    }

    /** повторный disarm безопасен и после срабатывания */
    fun disarm() {
        if (armed.compareAndSet(true, false)) {
            handler.removeCallbacks(timeoutRunnable)
        }
    }
}
