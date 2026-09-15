package com.magisky.reschoolbeta.widgets

import android.appwidget.AppWidgetHostView
import android.appwidget.AppWidgetProviderInfo
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import com.magisky.reschoolbeta.R
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30, 35], qualifiers = "xhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SchoolWidgetTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val today get() = SimpleDateFormat("yyyy-MM-dd", Locale.ROOT).format(Date())
    private val prefs get() = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)

    @Before fun reset() { prefs.edit().clear().commit() }
    private fun save(key: String, value: JSONObject) { prefs.edit().putString(key, value.toString()).commit() }
    private fun item() = JSONObject().put("subject", "Математика").put("num", 1)
        .put("teacher", "Иванова А. П.").put("startTime", "08:30").put("endTime", "09:15")
        .put("date", "14 сент.").put("dateISO", today).put("deadline", JSONObject.NULL)
        .put("text", "Решить задачи 15-20 из учебника").put("average", "4,8")
    private fun payload(key: String, items: JSONArray) = JSONObject().put(key, items)
        .put("date", "14 сентября").put("dateISO", today).put("periodName", "1 четверть")
        .put("lastUpdated", today + "T08:00:00.000000")

    @Test fun allProvidersInflateAndOpenTheirOwnTab() {
        val manager = AppWidgetManager.getInstance(context)
        val providers = listOf(ScheduleWidget::class.java, HomeworkWidget::class.java, GradesWidget::class.java)
        val types = listOf("schedule", "homework", "grades")
        val keys = listOf("lessons", "items", "grades")
        providers.forEachIndexed { index, provider ->
            val type = types[index]
            save("widget_${type}_data", payload(keys[index], JSONArray().put(item())))
            val id = shadowOf(manager).createWidget(provider, R.layout.schedule_widget)
            val view = shadowOf(manager).getViewFor(id)
            assertNotNull(view.findViewById<View>(R.id.widget_list_view))
            assertEquals(View.GONE, view.findViewById<View>(R.id.widget_empty_text).visibility)
            assertTrue(view.findViewById<View>(R.id.widget_container).performClick())
            assertEquals("reschool://widget/$type", shadowOf(RuntimeEnvironment.getApplication()).nextStartedActivity.data.toString())
        }
    }

    @Test fun legacyFactoryLoadsImmediatelyAndReplacesTheWholeSnapshot() {
        save("widget_homework_data", payload("items", JSONArray().put(item())))
        val factory = WidgetListRemoteViewsFactory(context, Intent().putExtra("widget_type", "homework"))
        factory.onCreate()
        assertEquals(1, factory.count)
        val row = factory.getViewAt(0)!!.apply(context, FrameLayout(context))
        assertFalse(row.findViewById<TextView>(R.id.row_meta).text.contains("null"))
        assertFalse(factory.hasStableIds())
        prefs.edit().putString("widget_homework_data", "broken json").commit()
        factory.onDataSetChanged()
        assertEquals(0, factory.count)
        assertNull(factory.getViewAt(-1))
        assertNull(factory.getViewAt(0))
    }

    @Test fun scheduleUsesTodayFromCachedWeekAndNeverShowsOldLessonsAsToday() {
        val previous = payload("lessons", JSONArray().put(item())).put("dateISO", "2000-01-01")
        save("widget_schedule_data", previous)
        assertTrue(WidgetSnapshot(context, "schedule").items.isEmpty())
        previous.put("days", JSONArray().put(payload("lessons", JSONArray().put(item()))))
        save("widget_schedule_data", previous)
        assertEquals(1, WidgetSnapshot(context, "schedule").items.size)
        save("widget_config", JSONObject().put("scheduleEnabled", false))
        assertTrue(WidgetSnapshot(context, "schedule").items.isEmpty())
    }

    @Test fun lastBellHidesTodaysHomeworkAndSkipsWeekend() {
        fun instant(value: String) = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.ROOT).parse(value)!!
        fun day(key: String, end: String?, lessons: JSONArray): JSONObject =
            payload("lessons", lessons).put("dateISO", key).put("date", key)
                .put("dayStartMs", instant("$key 00:00:00").time)
                .put("dayEndMs", instant("$key 00:00:00").time + 86400000)
                .put("schoolEndMs", end?.let { instant("$key $it").time } ?: JSONObject.NULL)
        val saturday = day("2026-09-19", "11:45:30", JSONArray().put(item()).put(item().put("num", 3)))
        val sunday = day("2026-09-20", null, JSONArray())
        val monday = day("2026-09-21", "09:15:00", JSONArray().put(item().put("subject", "Физика")))
        save("widget_schedule_data", JSONObject(saturday.toString()).put("days", JSONArray().put(saturday).put(sunday).put(monday)))
        save("widget_homework_data", payload("items", JSONArray()
            .put(item().put("dateISO", "2026-09-19"))
            .put(item().put("dateISO", "2026-09-21"))))
        // ДЗ должно переключаться и без включённого виджета расписания.
        save("widget_config", JSONObject().put("scheduleEnabled", false))
        for (time in listOf("07:00:00", "10:00:00", "11:45:29")) {
            val now = instant("2026-09-19 $time")
            assertEquals(2, WidgetSnapshot(context, "homework", now).items.size)
        }
        val end = instant("2026-09-19 11:45:30")
        assertEquals("2026-09-21", WidgetSnapshot(context, "homework", end).items.single().text("dateISO"))
        save("widget_config", JSONObject())
        assertEquals("2026-09-19", WidgetSnapshot(context, "schedule", instant("2026-09-19 11:45:29")).payload.text("dateISO"))
        assertEquals("2026-09-21", WidgetSnapshot(context, "schedule", end).payload.text("dateISO"))
        assertEquals("2026-09-21", WidgetSnapshot(context, "schedule", instant("2026-09-20 12:00:00")).payload.text("dateISO"))
        assertEquals("2026-09-21", WidgetSnapshot(context, "schedule", instant("2026-09-21 08:00:00")).payload.text("dateISO"))
    }

    @Test fun missingBellTimeKeepsTodaysHomeworkAndSchedule() {
        val end = Date()
        val day = payload("lessons", JSONArray().put(item()))
            .put("dayStartMs", end.time - 1000).put("dayEndMs", end.time + 1000)
            .put("schoolEndMs", JSONObject.NULL)
        save("widget_schedule_data", day)
        save("widget_homework_data", payload("items", JSONArray().put(item())))
        assertEquals(1, WidgetSnapshot(context, "homework", end).items.size)
        assertEquals(1, WidgetSnapshot(context, "schedule", end).items.size)
        prefs.edit().remove("widget_schedule_data").commit()
        assertEquals(1, WidgetSnapshot(context, "homework", end).items.size)
    }

    @Test fun limitsAndTeacherPreferenceApplyWithoutAnotherDataFetch() {
        save("widget_schedule_data", payload("lessons", JSONArray().put(item())))
        save("widget_homework_data", payload("items", JSONArray().put(item()).put(item())))
        save("widget_config", JSONObject().put("showTeacherInSchedule", false).put("homeworkItemsCount", 1))
        val snapshot = WidgetSnapshot(context, "schedule")
        val row = snapshot.row(context, snapshot.items.first()).apply(context, FrameLayout(context))
        assertEquals(View.GONE, row.findViewById<View>(R.id.row_detail).visibility)
        assertEquals(1, WidgetSnapshot(context, "homework").items.size)
    }

    @Test fun resizingToMinimumKeepsRoomForContent() {
        save("widget_homework_data", payload("items", JSONArray().put(item())))
        val manager = AppWidgetManager.getInstance(context)
        val id = shadowOf(manager).createWidget(HomeworkWidget::class.java, R.layout.homework_widget)
        val options = android.os.Bundle().apply { putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 140) }
        manager.updateAppWidgetOptions(id, options)
        HomeworkWidget().onAppWidgetOptionsChanged(context, manager, id, options)
        val view = shadowOf(manager).getViewFor(id)
        assertEquals(View.GONE, view.findViewById<View>(R.id.widget_subtitle).visibility)
        assertEquals(View.GONE, view.findViewById<View>(R.id.widget_last_updated).visibility)
        assertEquals(View.VISIBLE, view.findViewById<View>(R.id.widget_list_view).visibility)
    }

    @Test fun actualRemoteViewsRenderForVisualReview() {
        if (Build.VERSION.SDK_INT != 35) return
        val manager = AppWidgetManager.getInstance(context)
        val providers = listOf(ScheduleWidget::class.java, HomeworkWidget::class.java, GradesWidget::class.java)
        val types = listOf("schedule", "homework", "grades")
        val keys = listOf("lessons", "items", "grades")
        for (mode in listOf("light", "dark")) {
            save("widget_appearance", JSONObject().put("mode", mode))
            providers.forEachIndexed { index, provider ->
                val items = JSONArray().put(item()).put(item().put("subject", "Русский язык").put("num", 2).put("average", "4,2"))
                save("widget_${types[index]}_data", payload(keys[index], items))
                val id = shadowOf(manager).createWidget(provider, R.layout.schedule_widget)
                val view = AppWidgetHostView(context)
                view.setAppWidget(id, manager.getAppWidgetInfo(id) ?: AppWidgetProviderInfo())
                val widget = provider.getDeclaredConstructor().newInstance()
                val root = widget.render(context, id, WidgetSnapshot(context, types[index])).apply(context, view)
                view.addView(root)
                val list = view.findViewById<android.widget.ListView>(R.id.widget_list_view)
                assertNotNull("The collection must bind to the launcher host", list.adapter)
                assertEquals(2, list.adapter.count)
                org.robolectric.shadows.ShadowLooper.idleMainLooper()
                view.measure(View.MeasureSpec.makeMeasureSpec(640, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(420, View.MeasureSpec.EXACTLY))
                view.layout(0, 0, 640, 420)
                assertTrue(list.performItemClick(list.getChildAt(0), 0, 0))
                assertEquals("reschool://widget/${types[index]}", shadowOf(RuntimeEnvironment.getApplication()).nextStartedActivity.data.toString())
                val bitmap = Bitmap.createBitmap(640, 420, Bitmap.Config.ARGB_8888)
                view.draw(Canvas(bitmap))
                val dir = File(requireNotNull(System.getProperty("widget.previewDir"))).apply { mkdirs() }
                File(dir, "${types[index]}-$mode.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            }
        }
    }
}
