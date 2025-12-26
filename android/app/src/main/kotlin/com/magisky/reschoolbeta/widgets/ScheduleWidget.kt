package com.magisky.reschoolbeta.widgets

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.app.PendingIntent
import android.net.Uri
import android.view.View
import com.magisky.reschoolbeta.R
import org.json.JSONObject

class ScheduleWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.schedule_widget)

            val intent = Intent(context, WidgetListService::class.java)
            intent.putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            intent.putExtra("widget_type", "schedule")
            intent.data = Uri.parse(intent.toUri(Intent.URI_INTENT_SCHEME))

            views.setRemoteAdapter(R.id.widget_list_view, intent)
            views.setEmptyView(R.id.widget_list_view, R.id.widget_empty_text)

            val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            val jsonData = prefs.getString("widget_schedule_data", null)

            if (jsonData != null) {
                try {
                    val data = JSONObject(jsonData)
                    val date = data.optString("date", "")
                    views.setTextViewText(R.id.widget_last_updated, date)

                    val lessons = data.optJSONArray("lessons")
                    if (lessons == null || lessons.length() == 0) {
                         views.setViewVisibility(R.id.widget_empty_text, View.VISIBLE)
                         views.setViewVisibility(R.id.widget_list_view, View.GONE)
                    } else {
                         views.setViewVisibility(R.id.widget_empty_text, View.GONE)
                         views.setViewVisibility(R.id.widget_list_view, View.VISIBLE)
                    }

                } catch (e: Exception) {
                    views.setTextViewText(R.id.widget_last_updated, "Ошибка")
                }
            } else {
                views.setTextViewText(R.id.widget_last_updated, "")
            }

            val appIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (appIntent != null) {
                val pendingIntent = PendingIntent.getActivity(
                    context, 0, appIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)

                views.setPendingIntentTemplate(R.id.widget_list_view, pendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_list_view)
        }
    }
}