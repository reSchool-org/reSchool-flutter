package com.magisky.reschoolbeta.widgets

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService

/** на старых версиях android коллекцию строк отдаём через отдельный сервис */
class WidgetListService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        WidgetListRemoteViewsFactory(applicationContext, intent)
}

class WidgetListRemoteViewsFactory(private val context: Context, intent: Intent) : RemoteViewsService.RemoteViewsFactory {
    private val type = intent.getStringExtra("widget_type") ?: "schedule"
    @Volatile private var snapshot = WidgetSnapshot(context, type)
    override fun onCreate() { snapshot = WidgetSnapshot(context, type) }
    override fun onDataSetChanged() { snapshot = WidgetSnapshot(context, type) }
    override fun onDestroy() {}
    override fun getCount() = snapshot.items.size
    override fun getViewAt(position: Int): RemoteViews? {
        val current = snapshot
        return current.items.getOrNull(position)?.let { current.row(context, it) }
    }
    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount() = 1
    override fun getItemId(position: Int) = position.toLong()
    override fun hasStableIds() = false
}
