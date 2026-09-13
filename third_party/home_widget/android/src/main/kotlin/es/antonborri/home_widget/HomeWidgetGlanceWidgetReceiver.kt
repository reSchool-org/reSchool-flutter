package es.antonborri.home_widget

import android.appwidget.AppWidgetManager
import android.content.Context
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.state.updateAppWidgetState
import kotlinx.coroutines.runBlocking

abstract class HomeWidgetGlanceWidgetReceiver<T : GlanceAppWidget> : GlanceAppWidgetReceiver() {

  abstract override val glanceAppWidget: T

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
    runBlocking {
      appWidgetIds.forEach {
        val glanceId = GlanceAppWidgetManager(context).getGlanceIdBy(it)
        glanceAppWidget.apply {
          if (this.stateDefinition is HomeWidgetGlanceStateDefinition) {
            updateAppWidgetState<HomeWidgetGlanceState>(
                context = context,
                this.stateDefinition as HomeWidgetGlanceStateDefinition,
                glanceId,
            ) { currentState ->
              currentState
            }
          }
          update(context, glanceId)
        }
      }
    }
  }
}
