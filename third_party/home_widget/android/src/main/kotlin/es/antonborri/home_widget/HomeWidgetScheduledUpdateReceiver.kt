package es.antonborri.home_widget

import android.app.AlarmManager
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent

/** приложение само регистрирует получатель и разрешение загрузки; после перезапуска, обновления или возврата разрешения восстанавливаем будильники */
class HomeWidgetScheduledUpdateReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    when (intent.action) {
      HomeWidgetScheduler.ACTION_SCHEDULED_UPDATE -> {
        val providerClassName =
            intent.getStringExtra(HomeWidgetScheduler.EXTRA_PROVIDER_CLASS_NAME) ?: return
        if (updateWidget(context, providerClassName)) {
          HomeWidgetScheduler.pruneAndArmNext(context, providerClassName, catchUp = false)
        } else {
          HomeWidgetScheduler.cancel(context, providerClassName)
        }
      }
      Intent.ACTION_BOOT_COMPLETED,
      Intent.ACTION_MY_PACKAGE_REPLACED,
      AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED -> {
        HomeWidgetScheduler.rescheduleAll(context)
      }
    }
  }

  companion object {
    /** без экземпляров виджета сохраняем времена без рассылки; если класс исчез, возвращаем false и удаляем расписание */
    internal fun updateWidget(context: Context, providerClassName: String): Boolean {
      val javaClass =
          try {
            Class.forName(providerClassName)
          } catch (classException: ClassNotFoundException) {
            // после создания расписания виджет удалили или переименовали
            return false
          }
      val ids: IntArray =
          AppWidgetManager.getInstance(context.applicationContext)
              .getAppWidgetIds(ComponentName(context.applicationContext, javaClass))
      if (ids.isEmpty()) {
        return true
      }
      val updateIntent = Intent(context.applicationContext, javaClass)
      updateIntent.action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
      updateIntent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
      updateIntent.putExtra(HomeWidgetPlugin.TRIGGERED_FROM_HOME_WIDGET, true)
      context.sendBroadcast(updateIntent)
      return true
    }
  }
}
