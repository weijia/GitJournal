/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'package:flutter/material.dart';
import 'package:gitjournal/utils/debug_nav_observer.dart';

/// A wrapper that was previously a floating debug overlay.
/// The overlay panel is now hidden, but the widget is kept so that
/// the post-frame setState callback (which triggers a rebuild after
/// the first frame) still runs — this is needed for the _AutoRemoveRoute
/// to work correctly when the app is launched from a widget.
class DebugOverlay extends StatefulWidget {
  final Widget child;

  const DebugOverlay({super.key, required this.child});

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  @override
  void initState() {
    super.initState();
    // Schedule a rebuild after the first frame. This extra rebuild
    // is essential for the widget deep-link flow: it ensures the
    // Navigator re-renders after _AutoRemoveRoute removes itself
    // and after the repo switch triggers notifyListeners().
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    // Debug overlay panel is hidden — just return the child.
    return widget.child;
  }
}
