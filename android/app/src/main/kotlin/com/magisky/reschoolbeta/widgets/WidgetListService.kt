package com.magisky.reschoolbeta.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.magisky.reschoolbeta.R
import org.json.JSONArray
import org.json.JSONObject
import java.util.ArrayList

class WidgetListService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return WidgetListRemoteViewsFactory(this.applicationContext, intent)
    }
}

class WidgetListRemoteViewsFactory(private val context: Context, intent: Intent) : RemoteViewsService.RemoteViewsFactory {
    private val widgetType = intent.getStringExtra("widget_type") ?: ""
    private var data = ArrayList<JSONObject>()

    override fun onCreate() {
    }

    override fun onDataSetChanged() {
        initData()
    }

    private fun initData() {
        data.clear()

        val sharedPref = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val jsonString: String? = when (widgetType) {
            "schedule" -> sharedPref.getString("widget_schedule_data", null)
            "homework" -> sharedPref.getString("widget_homework_data", null)
            "grades" -> sharedPref.getString("widget_grades_data", null)
            else -> null
        }

        if (jsonString != null) {
            try {
                val jsonObj = JSONObject(jsonString)
                val itemsArray: JSONArray? = when (widgetType) {
                    "schedule" -> jsonObj.optJSONArray("lessons")
                    "homework" -> jsonObj.optJSONArray("items")
                    "grades" -> jsonObj.optJSONArray("grades")
                    else -> null
                }

                if (itemsArray != null) {
                    for (i in 0 until itemsArray.length()) {
                        data.add(itemsArray.getJSONObject(i))
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    override fun onDestroy() {
        data.clear()
    }

    override fun getCount(): Int {
        return data.size
    }

    override fun getViewAt(position: Int): RemoteViews {
        if (position >= data.size) return RemoteViews(context.packageName, R.layout.schedule_widget_item)

        val item = data[position]

        return when (widgetType) {
            "schedule" -> {
                val views = RemoteViews(context.packageName, R.layout.schedule_widget_item)
                views.setTextViewText(R.id.lesson_name, item.optString("subject", "Урок"))

                val startTime = item.optString("startTime", "")
                val endTime = item.optString("endTime", "")
                val timeStr = if (startTime.isNotEmpty()) "$startTime - $endTime" else ""

                views.setTextViewText(R.id.lesson_time, timeStr)

                val teacherStr = item.optString("teacher", "")
                if (teacherStr.isNotEmpty()) {
                    views.setTextViewText(R.id.lesson_room, teacherStr)
                    views.setViewVisibility(R.id.lesson_room, View.VISIBLE)
                } else {
                    views.setViewVisibility(R.id.lesson_room, View.GONE)
                }

                views
            }
            "homework" -> {
                val views = RemoteViews(context.packageName, R.layout.homework_widget_item)
                views.setTextViewText(R.id.homework_subject, item.optString("subject", "Предмет"))
                views.setTextViewText(R.id.homework_text, item.optString("text", "Задание"))

                val deadline = item.optString("deadline", "")
                if (deadline.isNotEmpty()) {
                    views.setTextViewText(R.id.homework_deadline, "До: $deadline")
                    views.setViewVisibility(R.id.homework_deadline, View.VISIBLE)
                } else {
                    views.setViewVisibility(R.id.homework_deadline, View.GONE)
                }

                views
            }
            "grades" -> {
                val views = RemoteViews(context.packageName, R.layout.grades_widget_item)
                views.setTextViewText(R.id.grade_subject, item.optString("subject", "Предмет"))
                views.setTextViewText(R.id.grade_value, item.optString("average", "-"))
                views
            }
            else -> RemoteViews(context.packageName, R.layout.schedule_widget_item)
        }
    }

    override fun getLoadingView(): RemoteViews? {
        return null
    }

    override fun getViewTypeCount(): Int {
        return 3
    }

    override fun getItemId(position: Int): Long {
        return position.toLong()
    }

    override fun hasStableIds(): Boolean {
        return true
    }
}