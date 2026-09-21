/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'package:flutter/material.dart';
import 'package:gitjournal/utils/debug_nav_observer.dart';

/// A floating debug overlay that shows recent navigation events.
/// Tap to expand/collapse.  Only visible in debug builds.
class DebugOverlay extends StatefulWidget {
  final Widget child;

  const DebugOverlay({super.key, required this.child});

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    // Refresh periodically so new log entries show up
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _refresh() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Always show the child
    return Stack(
      children: [
        widget.child,
        Positioned(
          top: MediaQuery.of(context).padding.top + 4,
          left: 4,
          right: 4,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _expanded = !_expanded;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black87.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange, width: 1),
              ),
              constraints: BoxConstraints(
                maxHeight: _expanded ? 300 : 32,
              ),
              child: _expanded ? _buildExpanded() : _buildCollapsed(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCollapsed() {
    final entries = DebugNavigatorObserver.instance.logEntries;
    return Row(
      children: [
        const Icon(Icons.bug_report, color: Colors.orange, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            entries.isEmpty ? 'Debug (tap to expand)' : entries.first,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildExpanded() {
    final entries = DebugNavigatorObserver.instance.logEntries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.bug_report, color: Colors.orange, size: 16),
            const SizedBox(width: 6),
            const Text(
              'Debug Nav Log',
              style: TextStyle(
                color: Colors.orange,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: _refresh,
              child: const Icon(Icons.refresh,
                  color: Colors.white54, size: 16),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  _expanded = false;
                });
              },
              child: const Icon(Icons.close,
                  color: Colors.white54, size: 16),
            ),
          ],
        ),
        const Divider(color: Colors.white24, height: 4),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: entries.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  entries[index],
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 9,
                    fontFamily: 'monospace',
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
