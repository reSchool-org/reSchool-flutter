package es.antonborri.home_widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.SharedPreferences

abstract class HomeWidgetProvider : AppWidgetProvider() {

  /** при первом экземпляре виджета восстанавливаем потерянный будильник, текущее состояние система уже нарисовала */
  override fun onEnabled(context: Context) {
    super.onEnabled(context)
    HomeWidgetScheduler.pruneAndArmNext(context, javaClass.name, catchUp = false)
  }

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
  ) {
    super.onUpdate(context, appWidgetManager, appWidgetIds)
    onUpdate(context, appWidgetManager, appWidgetIds, HomeWidgetPlugin.getData(context))
  }

  abstract fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  )
}
