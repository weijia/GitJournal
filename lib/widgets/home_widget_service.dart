/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'dart:async';

import 'package:gitjournal/logger/logger.dart';
import 'package:home_widget/home_widget.dart';
import 'package:universal_io/io.dart';

/// Service for managing home screen widgets
class HomeWidgetService {
  static const String _keyRepoId = 'repo_id';
  static const String _keyTitle = 'title';
  static const String _keySubtitle = 'subtitle';
  static const String _androidProviderName = 'RepoWidgetProvider';

  static Future<void> init() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }

    try {
      // Register interactivity callback for background widget actions
      // (not used for simple launch, but required for interactive widgets)
    } catch (e) {
      Log.e("Failed to initialize widget service", ex: e);
    }
  }

  /// Check if app was launched from a widget and return the repo ID
  static Future<String?> getInitialWidgetRepoId() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return null;
    }

    try {
      final uri = await HomeWidget.initiallyLaunchedFromHomeWidget();
      Log.i("Initial widget launch URI: $uri");

      if (uri != null &&
          uri.scheme == 'gitjournal' &&
          uri.host == 'repo' &&
          uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      }
      return null;
    } catch (e) {
      Log.e("Failed to get initial widget data", ex: e);
      return null;
    }
  }

  /// Stream of widget click events received while app is running
  static Stream<String> get widgetRepoIdStream {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const Stream.empty();
    }

    return HomeWidget.widgetClicked
        .where((uri) =>
            uri != null &&
            uri.scheme == 'gitjournal' &&
            uri.host == 'repo' &&
            uri.pathSegments.isNotEmpty)
        .map((uri) => uri!.pathSegments.first);
  }

  /// Update the widget with repo info
  static Future<void> updateRepoWidget({
    required String repoId,
    required String title,
    String? subtitle,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }

    try {
      await HomeWidget.saveWidgetData<String>(_keyRepoId, repoId);
      await HomeWidget.saveWidgetData<String>(_keyTitle, title);
      await HomeWidget.saveWidgetData<String>(
        _keySubtitle,
        subtitle ?? 'Tap to open',
      );
      await HomeWidget.updateWidget(
        name: _androidProviderName,
        androidName: _androidProviderName,
        iOSName: _androidProviderName,
      );
      Log.i("Updated widget for repo: $repoId");
    } catch (e) {
      Log.e("Failed to update widget", ex: e);
    }
  }

  /// Request to pin a repo widget on the home screen
  static Future<bool> requestPinRepoWidget({
    required String repoId,
    required String repoName,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return false;
    }

    try {
      // First save the data so the widget has content when it appears
      await HomeWidget.saveWidgetData<String>(_keyRepoId, repoId);
      await HomeWidget.saveWidgetData<String>(_keyTitle, repoName);
      await HomeWidget.saveWidgetData<String>(_keySubtitle, 'Tap to open');

      // Request to pin the widget
      await HomeWidget.requestPinWidget(
        name: _androidProviderName,
        androidName: _androidProviderName,
      );

      // Update the widget immediately (in case there were existing widgets)
      await HomeWidget.updateWidget(
        name: _androidProviderName,
        androidName: _androidProviderName,
      );

      Log.i("Requested pin widget for repo: $repoId");
      return true;
    } catch (e) {
      Log.e("Failed to request pin widget", ex: e);
      return false;
    }
  }
}
