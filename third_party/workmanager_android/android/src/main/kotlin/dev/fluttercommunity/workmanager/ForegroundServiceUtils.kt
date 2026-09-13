package dev.fluttercommunity.workmanager

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.ForegroundInfo
import dev.fluttercommunity.workmanager.pigeon.ForegroundServiceConfig
import dev.fluttercommunity.workmanager.pigeon.ForegroundServiceType

// значения совпадают с dart и поддерживают старые задачи без сохранённой настройки
private const val DEFAULT_NOTIFICATION_CHANNEL_ID = "workmanager_foreground_tasks"
private const val DEFAULT_NOTIFICATION_CHANNEL_NAME = "Long-running tasks"
private const val DEFAULT_NOTIFICATION_TITLE = "Task in progress"
private const val DEFAULT_NOTIFICATION_TEXT = "Your task is still running"
private const val DEFAULT_NOTIFICATION_ID = 0

/** с android 14 тип foreground службы обязателен в манифесте и вызове, на старых версиях его не передаём */
fun createForegroundInfo(
    context: Context,
    config: ForegroundServiceConfig,
): ForegroundInfo {
    createNotificationChannel(context, config)

    val notification =
        NotificationCompat
            .Builder(context, config.notificationChannelId ?: DEFAULT_NOTIFICATION_CHANNEL_ID)
            .setContentTitle(config.notificationTitle ?: DEFAULT_NOTIFICATION_TITLE)
            .setContentText(config.notificationText ?: DEFAULT_NOTIFICATION_TEXT)
            .setSmallIcon(resolveNotificationIcon(context))
            .setOngoing(true)
            .build()

    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        ForegroundInfo(
            config.notificationId?.toInt() ?: DEFAULT_NOTIFICATION_ID,
            notification,
            resolveForegroundServiceType(context, config),
        )
    } else {
        ForegroundInfo(config.notificationId?.toInt() ?: DEFAULT_NOTIFICATION_ID, notification)
    }
}

/** каналы уведомлений доступны начиная с android 8 */
private fun createNotificationChannel(
    context: Context,
    config: ForegroundServiceConfig,
) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
        return
    }
    val channel =
        NotificationChannel(
            config.notificationChannelId ?: DEFAULT_NOTIFICATION_CHANNEL_ID,
            config.notificationChannelName ?: DEFAULT_NOTIFICATION_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        )
    context
        .getSystemService(NotificationManager::class.java)
        .createNotificationChannel(channel)
}

/** проверяем декларацию манифеста, состояние разрешения во время работы на android 16 может дать ложный отказ */
@Suppress("DEPRECATION") // новая перегрузка PackageInfoFlags требует api 33, а минимальная версия здесь 23
internal fun requireForegroundServicePermission(
    context: Context,
    permission: String,
    featureDescription: String,
    fixHint: String,
) {
    val declared =
        context
            .packageManager
            .getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
            .requestedPermissions
            ?.contains(permission) == true
    if (!declared) {
        throw IllegalStateException(
            "workmanager_android: $featureDescription requires the '$permission' permission " +
                "in the merged manifest, but it is missing. $fixHint",
        )
    }
}

private fun resolveForegroundServiceType(
    context: Context,
    config: ForegroundServiceConfig,
): Int =
    when (config.foregroundServiceType) {
        ForegroundServiceType.SHORT_SERVICE ->
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE
        else -> {
            // dataSync включается явно через настройку gradle, иначе объясняем ошибку до SecurityException на android 14
            requireForegroundServicePermission(
                context,
                android.Manifest.permission.FOREGROUND_SERVICE_DATA_SYNC,
                "foregroundServiceType=dataSync",
                "Add 'workmanager.enableDataSyncForegroundService=true' to your " +
                    "gradle.properties (see the workmanager_android README, issue #725).",
            )
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        }
    }

/** используем значок приложения или системный запасной, белый силуэт лучше виден в уведомлении */
private fun resolveNotificationIcon(context: Context): Int {
    val applicationIcon = context.applicationInfo.icon
    return if (applicationIcon != 0) applicationIcon else android.R.drawable.ic_dialog_info
}
