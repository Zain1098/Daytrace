package com.daytrace.daytrace

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class DayTraceWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.daytrace_home_widget)
            views.setOnClickPendingIntent(R.id.widget_quick_add, quickAddIntent(context))
            views.setOnClickPendingIntent(R.id.widget_open_app, openAppIntent(context))
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun quickAddIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        quickAddRequestCode,
        Intent(context, MainActivity::class.java).apply {
            putExtra(MainActivity.extraQuickAdd, true)
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun openAppIntent(context: Context): PendingIntent = PendingIntent.getActivity(
        context,
        openAppRequestCode,
        Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private companion object {
        const val quickAddRequestCode = 4301
        const val openAppRequestCode = 4302
    }
}
