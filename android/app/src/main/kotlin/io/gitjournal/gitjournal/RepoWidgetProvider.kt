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
        // Read shared widget data (all widgets show the same repo)
        val title = widgetData.getString("title", null)
            ?: context.getString(R.string.widget_repo_default_title)
        val subtitle = widgetData.getString("subtitle", null)
            ?: context.getString(R.string.widget_repo_default_subtitle)
        val repoId = widgetData.getString("repo_id", null)

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_repo)

            // Set text
            views.setTextViewText(R.id.widget_title, title)
            views.setTextViewText(R.id.widget_subtitle, subtitle)

            // Set click intent using HomeWidgetLaunchIntent so it works with
            // HomeWidget.initiallyLaunchedFromHomeWidget() and widgetClicked stream
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

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
