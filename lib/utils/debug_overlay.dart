/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gitjournal/utils/debug_nav_observer.dart';

/// A floating debug overlay that shows recent navigation events.
/// Only visible in debug builds.
///
/// Features:
///  - Tap the collapsed bar to expand the log panel.
///  - The panel can be dismissed entirely (hidden) via the close button.
///  - When hidden, a small floating bug icon lets you bring it back.
///  - Log entries are selectable and a "copy all" button copies everything.
class DebugOverlay extends StatefulWidget {
  final Widget child;

  const DebugOverlay({super.key, required this.child});

  @override
  State<DebugOverlay> createState() => _DebugOverlayState();
}

class _DebugOverlayState extends State<DebugOverlay> {
  bool _expanded = true;
  bool _visible = true;

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

  Future<void> _copyAll() async {
    final entries = DebugNavigatorObserver.instance.logEntries;
    await Clipboard.setData(ClipboardData(text: entries.join('\n')));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debug log copied to clipboard'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Always show the child
    return Stack(
      children: [
        widget.child,
        if (_visible) _buildOverlay() else _buildReopenButton(),
      ],
    );
  }

  Widget _buildReopenButton() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 4,
      left: 4,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _visible = true;
            _expanded = true;
          });
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black87.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange, width: 1),
          ),
          child: const Icon(Icons.bug_report, color: Colors.orange, size: 18),
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    return Positioned(
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
        GestureDetector(
          onTap: () {
            setState(() {
              _visible = false;
            });
          },
          child: const Icon(Icons.close, color: Colors.white54, size: 16),
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
              onTap: _copyAll,
              child: const Icon(Icons.copy_all,
                  color: Colors.white54, size: 16),
            ),
            const SizedBox(width: 8),
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
              child: const Icon(Icons.expand_less,
                  color: Colors.white54, size: 16),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                setState(() {
                  _visible = false;
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
                child: SelectableText(
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
