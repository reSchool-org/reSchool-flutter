package dev.fluttercommunity.workmanager

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.WorkInfo
import androidx.work.WorkManager
import dev.fluttercommunity.workmanager.pigeon.WorkmanagerFlutterApi
import io.flutter.plugin.common.BinaryMessenger
import java.util.Collections

/** прогресс читаем из базы workmanager, чтобы после перезапуска приложение сразу получило последнее сохранённое состояние */
object ProgressUpdateCoordinator {
    /** при отсутствии слушателя messenger равен null и наблюдение не запускается */
    @Volatile
    private var appMessenger: BinaryMessenger? = null

    private val observedUniqueNames = Collections.synchronizedSet(mutableSetOf<String>())

    /** привязку обновляем на движке приложения при смене слушателя прогресса */
    fun setAppMessenger(
        enabled: Boolean,
        messenger: BinaryMessenger,
    ) {
        appMessenger = if (enabled) messenger else null
    }

    /** без messenger приложения прогресс некому передавать, наблюдение не регистрируем */
    fun onProgressReported(
        context: Context?,
        uniqueName: String,
    ) {
        val messenger = appMessenger ?: return
        if (!observedUniqueNames.add(uniqueName)) {
            return
        }

        val workManager = WorkManager.getInstance(context?.applicationContext ?: return)

        // наблюдатель livedata регистрируется только в главном потоке
        Handler(Looper.getMainLooper()).post {
            workManager.getWorkInfosForUniqueWorkLiveData(uniqueName).observeForever { workInfos ->
                val running = workInfos?.firstOrNull { it.state == WorkInfo.State.RUNNING } ?: return@observeForever
                val progress = running.progress
                if (progress.keyValueMap.isEmpty()) {
                    return@observeForever
                }

                val currentMessenger = appMessenger ?: return@observeForever
                val decodedProgress = decodePayload(progress.keyValueMap)
                WorkmanagerFlutterApi(currentMessenger)
                    .onProgressUpdate(uniqueName, decodedProgress as Map<String?, Any?>) {
                        // подтверждение dart здесь не требует дополнительных действий
                    }
            }
        }
    }
}
