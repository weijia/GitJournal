/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

package io.gitjournal.gitjournal

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

class RepoWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val title = widgetData.getString("title", null)
            ?: context.getString(R.string.widget_repo_default_title)
        val subtitle = widgetData.getString("subtitle", null)
            ?: context.getString(R.string.widget_repo_default_subtitle)
        val repoId = widgetData.getString("repo_id", null)

        for (appWidgetId in appWidgetIds) {
            val views = buildRemoteViews(
                context,
                appWidgetManager,
                appWidgetId,
                title,
                subtitle,
                repoId
            )
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: android.os.Bundle
    ) {
        // Re-render the widget so title visibility adapts to the new size
        val widgetData = context.getSharedPreferences(
            "HomeWidgetPreferences", Context.MODE_PRIVATE
        )
        val title = widgetData.getString("title", null)
            ?: context.getString(R.string.widget_repo_default_title)
        val subtitle = widgetData.getString("subtitle", null)
            ?: context.getString(R.string.widget_repo_default_subtitle)
        val repoId = widgetData.getString("repo_id", null)

        val views = buildRemoteViews(
            context,
            appWidgetManager,
            appWidgetId,
            title,
            subtitle,
            repoId,
            options = newOptions
        )
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun buildRemoteViews(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        title: String,
        subtitle: String,
        repoId: String?,
        options: android.os.Bundle? = null
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_repo)

        // Set text on both views (they are gone by default in the 1x1 layout)
        views.setTextViewText(R.id.widget_title, title)
        views.setTextViewText(R.id.widget_subtitle, subtitle)

        // Determine if we have enough space to show the title.
        // When the widget is resized beyond ~100dp (roughly 2x2), show the title.
        val showTitle = if (options != null) {
            val minWidth = options.getInt(
                AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0
            )
            val minHeight = options.getInt(
                AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0
            )
            minWidth >= 100 || minHeight >= 140
        } else {
            // On initial placement (1x1), keep text hidden
            false
        }

        views.setViewVisibility(
            R.id.widget_title,
            if (showTitle) android.view.View.VISIBLE else android.view.View.GONE
        )
        views.setViewVisibility(
            R.id.widget_subtitle,
            if (showTitle) android.view.View.VISIBLE else android.view.View.GONE
        )

        // Set click intent
        val uri = if (repoId != null) {
            Uri.parse("gitjournal://repo/$repoId")
        } else {
            null
        }

        val pendingIntent = HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            uri
        )
        views.setOnClickPendingIntent(R.id.widget_container, pendingIntent)

        return views
    }
}
