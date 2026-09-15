package com.magisky.reschoolbeta.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import com.magisky.reschoolbeta.MainActivity
import com.magisky.reschoolbeta.R
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

internal fun JSONObject.text(key: String): String = if (isNull(key)) "" else optString(key, "")

internal class WidgetSnapshot(context: Context, val type: String, now: Date = Date()) {
    private val preferences = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
    private fun read(key: String) = runCatching { JSONObject(preferences.getString(key, "{}") ?: "{}") }.getOrDefault(JSONObject())
    val config = read("widget_config")
    private val raw = read("widget_${type}_data")
    val enabled = config.optBoolean("${type}Enabled", true)
    private val localToday = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(now)
    private val schedule = if (type == "schedule") raw else read("widget_schedule_data")
    private val calendarDays: List<JSONObject> = run {
        val days = schedule.optJSONArray("days")
        val result = (0 until (days?.length() ?: 0)).mapNotNull { days?.optJSONObject(it) }.toMutableList()
        if (schedule.text("dateISO").isNotEmpty() && result.none { it.text("dateISO") == schedule.text("dateISO") }) {
            result.add(schedule)
        }
        result.sortedBy { it.text("dateISO") }
    }
    private val currentDay = calendarDays.firstOrNull { day ->
        if (!day.isNull("dayStartMs") && !day.isNull("dayEndMs")) {
            now.time >= day.optLong("dayStartMs") && now.time < day.optLong("dayEndMs")
        } else day.text("dateISO") == localToday
    }
    private val today = currentDay?.text("dateISO") ?: localToday
    private fun hasLessons(day: JSONObject): Boolean {
        val lessons = day.optJSONArray("lessons")
        return (0 until (lessons?.length() ?: 0)).any { lessons?.optJSONObject(it)?.optBoolean("isPlaceholder", false) == false }
    }
    private val schoolEnded = currentDay?.let {
        hasLessons(it) && !it.isNull("schoolEndMs") && now.time >= it.optLong("schoolEndMs")
    } ?: false
    val payload: JSONObject = if (type == "schedule") {
        when {
            currentDay == null -> JSONObject()
            hasLessons(currentDay) && !schoolEnded -> currentDay
            else -> calendarDays.firstOrNull { it.text("dateISO") > today && hasLessons(it) } ?: JSONObject()
        }
    } else raw
    val items: List<JSONObject>
    val colors: JSONObject
    val subtitle: String
    val emptyMessage: String
    val updated: String

    init {
        val key = when (type) { "schedule" -> "lessons"; "homework" -> "items"; else -> "grades" }
        val array = payload.optJSONArray(key)
        val limit = when (type) {
            "homework" -> config.optInt("homeworkItemsCount", 5).coerceIn(1, 20)
            "grades" -> config.optInt("gradesSubjectsCount", 6).coerceIn(1, 15)
            else -> 40
        }
        items = if (!enabled) emptyList() else (0 until (array?.length() ?: 0))
            .mapNotNull { array?.optJSONObject(it) }
            .filter { type != "schedule" || !it.optBoolean("isPlaceholder", false) }
            .filter { type != "homework" || if (schoolEnded) it.text("dateISO") > today else it.text("dateISO") >= today }
            .take(limit)
        val appearance = read("widget_appearance")
        val systemDark = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        val dark = when (appearance.text("mode")) { "dark" -> true; "light" -> false; else -> systemDark }
        colors = appearance.optJSONObject(if (dark) "dark" else "light") ?: JSONObject(
            if (dark) """{"background":4279966495,"surface":4280558891,"text":4293190377,"secondary":4291151568,"accent":4289382399}"""
            else """{"background":4294703359,"surface":4293979638,"text":4279966495,"secondary":4282730063,"accent":4280119275}"""
        )
        subtitle = if (!enabled) "Выключен в настройках" else when (type) {
            "schedule" -> payload.text("date")
            "homework" -> "Ближайшие задания"
            else -> payload.text("periodName")
        }
        emptyMessage = when {
            !enabled -> "Включите виджет в приложении"
            raw.text("lastUpdated").isEmpty() || (type == "schedule" && payload.length() == 0) -> "Откройте приложение для обновления"
            type == "schedule" -> "Сегодня уроков нет"
            type == "homework" -> "Ближайших заданий нет"
            else -> "Пока нет оценок"
        }
        updated = runCatching {
            val time = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.ROOT).parse(raw.text("lastUpdated"))!!
            "Обновлено " + SimpleDateFormat(if (raw.text("lastUpdated").startsWith(today)) "HH:mm" else "d MMM, HH:mm", Locale("ru")).format(time)
        }.getOrDefault("")
    }

    fun color(key: String): Int = colors.optLong(key).toInt()

    fun row(context: Context, item: JSONObject): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_list_item)
        views.setInt(R.id.row_background, "setColorFilter", color("surface"))
        views.setTextViewText(R.id.row_title, item.text("subject"))
        views.setTextColor(R.id.row_title, color("text"))
        views.setTextColor(R.id.row_detail, color("secondary"))
        views.setTextColor(R.id.row_meta, color("secondary"))
        views.setTextColor(R.id.row_badge, color("accent"))
        val detail: String
        val meta: String
        val badge: String
        when (type) {
            "schedule" -> {
                detail = if (config.optBoolean("showTeacherInSchedule", true)) item.text("teacher") else ""
                meta = listOf(item.text("startTime"), item.text("endTime")).filter { it.isNotEmpty() }.joinToString(" - ")
                badge = item.optInt("num").toString()
            }
            "homework" -> {
                detail = item.text("text").ifBlank { if (item.optBoolean("hasFiles")) "Задание во вложении" else "Без описания" }
                val deadline = if (config.optBoolean("showDeadlineInHomework", true)) item.text("deadline") else ""
                meta = listOf(item.text("date"), if (deadline.isNotEmpty()) "До $deadline" else "", if (item.optBoolean("hasFiles")) "Есть файлы" else "")
                    .filter { it.isNotEmpty() }.joinToString(" · ")
                badge = ""
            }
            else -> {
                detail = item.text("rating")
                meta = ""
                badge = item.text("average").ifBlank { "-" }
            }
        }
        views.setTextViewText(R.id.row_detail, detail)
        views.setViewVisibility(R.id.row_detail, if (detail.isEmpty()) View.GONE else View.VISIBLE)
        views.setTextViewText(R.id.row_meta, meta)
        views.setViewVisibility(R.id.row_meta, if (meta.isEmpty()) View.GONE else View.VISIBLE)
        views.setTextViewText(R.id.row_badge, badge)
        views.setViewVisibility(R.id.row_badge, if (badge.isEmpty()) View.GONE else View.VISIBLE)
        views.setOnClickFillInIntent(R.id.widget_row, Intent())
        return views
    }
}

abstract class SchoolWidgetProvider(private val type: String) : AppWidgetProvider() {
    override fun onDisabled(context: Context) {
        es.antonborri.home_widget.HomeWidgetScheduler.cancel(context, javaClass.name)
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val snapshot = WidgetSnapshot(context, type)
        ids.forEach { id ->
            manager.updateAppWidget(id, render(context, id, snapshot))
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) manager.notifyAppWidgetViewDataChanged(id, R.id.widget_list_view)
        }
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        onUpdate(context, manager, intArrayOf(id))
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action in listOf(Intent.ACTION_DATE_CHANGED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_CONFIGURATION_CHANGED)) {
            val manager = AppWidgetManager.getInstance(context)
            onUpdate(context, manager, manager.getAppWidgetIds(ComponentName(context, javaClass)))
        }
    }

    internal fun render(context: Context, id: Int, snapshot: WidgetSnapshot): RemoteViews {
        val layout = when (type) { "schedule" -> R.layout.schedule_widget; "homework" -> R.layout.homework_widget; else -> R.layout.grades_widget }
        val compact = AppWidgetManager.getInstance(context).getAppWidgetOptions(id)
            .getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 210) < 180
        val views = RemoteViews(context.packageName, layout)
        views.setInt(R.id.widget_background, "setColorFilter", snapshot.color("background"))
        views.setInt(R.id.widget_icon, "setColorFilter", snapshot.color("accent"))
        views.setTextColor(R.id.widget_title, snapshot.color("text"))
        for (viewId in listOf(R.id.widget_subtitle, R.id.widget_empty_text, R.id.widget_last_updated)) {
            views.setTextColor(viewId, snapshot.color("secondary"))
        }
        views.setTextViewText(R.id.widget_subtitle, snapshot.subtitle)
        views.setViewVisibility(R.id.widget_subtitle, if (snapshot.subtitle.isEmpty() || compact) View.GONE else View.VISIBLE)
        views.setTextViewText(R.id.widget_empty_text, snapshot.emptyMessage)
        views.setTextViewText(R.id.widget_last_updated, snapshot.updated)
        views.setViewVisibility(R.id.widget_last_updated, if (snapshot.updated.isEmpty() || !snapshot.enabled || compact) View.GONE else View.VISIBLE)
        views.setEmptyView(R.id.widget_list_view, R.id.widget_empty_text)
        views.setViewVisibility(R.id.widget_list_view, if (snapshot.items.isEmpty()) View.GONE else View.VISIBLE)
        views.setViewVisibility(R.id.widget_empty_text, if (snapshot.items.isEmpty()) View.VISIBLE else View.GONE)

        // на android 12 передаём шапку и строки вместе, чтобы не ждать отдельный сервис и кеш лаунчера
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val items = RemoteViews.RemoteCollectionItems.Builder().setHasStableIds(false).setViewTypeCount(1)
            snapshot.items.forEachIndexed { index, item -> items.addItem(index.toLong(), snapshot.row(context, item)) }
            views.setRemoteAdapter(R.id.widget_list_view, items.build())
        } else {
            val service = Intent(context, WidgetListService::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id).putExtra("widget_type", type)
                .setData(Uri.parse("reschool-widget://$type/$id"))
            views.setRemoteAdapter(R.id.widget_list_view, service)
        }
        val launch = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW).setData(Uri.parse("reschool://widget/$type"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val click = PendingIntent.getActivity(context, id, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        views.setOnClickPendingIntent(R.id.widget_container, click)
        val templateFlags = PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        views.setPendingIntentTemplate(R.id.widget_list_view, PendingIntent.getActivity(context, id + 100000, launch, templateFlags))
        return views
    }
}
