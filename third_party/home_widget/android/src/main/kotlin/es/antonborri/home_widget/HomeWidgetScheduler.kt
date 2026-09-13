package es.antonborri.home_widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.util.Log
import org.json.JSONArray

/** храним один будильник на провайдера; получатель и права задаёт приложение, без права точного времени обновления могут задержаться */
object HomeWidgetScheduler {
  private const val TAG = "HomeWidgetScheduler"
  private const val SCHEDULE_PREFIX = "scheduledUpdates."

  const val ACTION_SCHEDULED_UPDATE = "es.antonborri.home_widget.action.SCHEDULED_UPDATE"

  const val EXTRA_PROVIDER_CLASS_NAME = "providerClassName"

  /** новые времена заменяют прежние, прошедшие пропускаем, пустой список отменяет обновления */
  fun schedule(context: Context, providerClassName: String, updateTimes: List<Long>) {
    val now = System.currentTimeMillis()
    val upcoming = updateTimes.filter { it > now }.distinct().sorted()
    if (upcoming.isEmpty()) {
      cancel(context, providerClassName)
      return
    }
    warnIfReceiverMissing(context)
    saveTimes(context, providerClassName, upcoming)
    armNext(context, providerClassName, upcoming)
  }

  /** при отмене удаляем и будильник, и сохранённые времена */
  fun cancel(context: Context, providerClassName: String) {
    cancelAlarm(context, providerClassName)
    context
        .getSharedPreferences(HomeWidgetPlugin.INTERNAL_PREFERENCES, Context.MODE_PRIVATE)
        .edit()
        .remove("$SCHEDULE_PREFIX$providerClassName")
        .apply()
  }

  /** после пропущенного будильника один раз догоняем состояние, иначе виджет останется устаревшим; уже обновивший виджет вызывающий код передаёт false */
  fun pruneAndArmNext(context: Context, providerClassName: String, catchUp: Boolean = true) {
    val times = loadTimes(context, providerClassName)
    val now = System.currentTimeMillis()
    if (
        catchUp &&
            times.any { it <= now } &&
            !HomeWidgetScheduledUpdateReceiver.updateWidget(context, providerClassName)
    ) {
      cancel(context, providerClassName)
      return
    }
    val upcoming = times.filter { it > now }
    if (upcoming.isEmpty()) {
      cancel(context, providerClassName)
      return
    }
    saveTimes(context, providerClassName, upcoming)
    armNext(context, providerClassName, upcoming)
  }

  /** система удаляет будильники при перезагрузке, обновлении и отзыве права, поэтому восстанавливаем их после этих событий */
  fun rescheduleAll(context: Context) {
    val prefs =
        context.getSharedPreferences(
            HomeWidgetPlugin.INTERNAL_PREFERENCES,
            Context.MODE_PRIVATE,
        )
    val providerClassNames =
        prefs.all.keys
            .filter { it.startsWith(SCHEDULE_PREFIX) }
            .map { it.removePrefix(SCHEDULE_PREFIX) }
    for (providerClassName in providerClassNames) {
      pruneAndArmNext(context, providerClassName)
    }
  }

  /** без получателя в манифесте будильник создастся, но никто его не получит, поэтому предупреждаем */
  private fun warnIfReceiverMissing(context: Context) {
    val component =
        ComponentName(context.applicationContext, HomeWidgetScheduledUpdateReceiver::class.java)
    try {
      context.packageManager.getReceiverInfo(component, 0)
    } catch (e: PackageManager.NameNotFoundException) {
      Log.w(
          TAG,
          "HomeWidgetScheduledUpdateReceiver is not registered in the app's AndroidManifest.xml. " +
              "Scheduled Widget updates will not be delivered. Add:\n" +
              "<uses-permission android:name=\"android.permission.RECEIVE_BOOT_COMPLETED\" />\n" +
              "<receiver android:name=\"es.antonborri.home_widget.HomeWidgetScheduledUpdateReceiver\" " +
              "android:exported=\"false\">\n" +
              "  <intent-filter>\n" +
              "    <action android:name=\"android.intent.action.BOOT_COMPLETED\" />\n" +
              "    <action android:name=\"android.intent.action.MY_PACKAGE_REPLACED\" />\n" +
              "    <action android:name=\"android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED\" />\n" +
              "  </intent-filter>\n" +
              "</receiver>",
      )
    }
  }

  private fun armNext(context: Context, providerClassName: String, upcoming: List<Long>) {
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
    val triggerAtMillis = upcoming.first()
    val pendingIntent = createPendingIntent(context, providerClassName) ?: return

    when {
      // начиная с android 12 для точного будильника нужно право SCHEDULE_EXACT_ALARM или USE_EXACT_ALARM
      Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
        if (alarmManager.canScheduleExactAlarms()) {
          alarmManager.setExactAndAllowWhileIdle(
              AlarmManager.RTC_WAKEUP,
              triggerAtMillis,
              pendingIntent,
          )
        } else {
          alarmManager.setAndAllowWhileIdle(
              AlarmManager.RTC_WAKEUP,
              triggerAtMillis,
              pendingIntent,
          )
        }
      }
      Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ->
          alarmManager.setExactAndAllowWhileIdle(
              AlarmManager.RTC_WAKEUP,
              triggerAtMillis,
              pendingIntent,
          )
      Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT ->
          alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
      else -> alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
    }
  }

  /** флаг FLAG_NO_CREATE позволяет отменить будильник, не создавая новый PendingIntent */
  private fun cancelAlarm(context: Context, providerClassName: String) {
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
    val pendingIntent =
        createPendingIntent(context, providerClassName, PendingIntent.FLAG_NO_CREATE) ?: return
    alarmManager.cancel(pendingIntent)
    pendingIntent.cancel()
  }

  /** extras не участвуют в сравнении PendingIntent, поэтому провайдера включаем в uri и код запроса */
  private fun createPendingIntent(
      context: Context,
      providerClassName: String,
      baseFlags: Int = PendingIntent.FLAG_UPDATE_CURRENT,
  ): PendingIntent? {
    val intent =
        Intent(context.applicationContext, HomeWidgetScheduledUpdateReceiver::class.java).apply {
          action = ACTION_SCHEDULED_UPDATE
          data = Uri.parse("homewidget://scheduled/$providerClassName")
          putExtra(EXTRA_PROVIDER_CLASS_NAME, providerClassName)
        }
    var flags = baseFlags
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      flags = flags or PendingIntent.FLAG_IMMUTABLE
    }
    return PendingIntent.getBroadcast(
        context.applicationContext,
        providerClassName.hashCode(),
        intent,
        flags,
    )
  }

  private fun saveTimes(context: Context, providerClassName: String, times: List<Long>) {
    val array = JSONArray()
    for (time in times) {
      array.put(time)
    }
    context
        .getSharedPreferences(HomeWidgetPlugin.INTERNAL_PREFERENCES, Context.MODE_PRIVATE)
        .edit()
        .putString("$SCHEDULE_PREFIX$providerClassName", array.toString())
        .apply()
  }

  private fun loadTimes(context: Context, providerClassName: String): List<Long> {
    val stored =
        context
            .getSharedPreferences(HomeWidgetPlugin.INTERNAL_PREFERENCES, Context.MODE_PRIVATE)
            .getString("$SCHEDULE_PREFIX$providerClassName", null) ?: return emptyList()
    return try {
      val array = JSONArray(stored)
      val times = mutableListOf<Long>()
      for (index in 0 until array.length()) {
        times.add(array.getLong(index))
      }
      times.sorted()
    } catch (e: org.json.JSONException) {
      emptyList()
    }
  }
}
