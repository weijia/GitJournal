/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gitjournal/core/folder/notes_folder.dart';
import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/core/notes/note.dart';
import 'package:gitjournal/editors/common.dart' as gj;
import 'package:gitjournal/editors/utils/disposable_change_notifier.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

/// Debug log buffer shared across the app
final List<String> _debugLogs = [];

void _log(String message) {
  final timestamp = DateTime.now().toIso8601String().substring(11, 23);
  final line = '[$timestamp] $message';
  _debugLogs.add(line);
  if (_debugLogs.length > 200) _debugLogs.removeAt(0);
  debugPrint(line);
}

/// A standalone WYSIWYG Markdown Editor using AppFlowy Editor
class AppFlowyNoteEditor extends StatefulWidget implements gj.Editor {
  final Note note;
  final NotesFolder parentFolder;
  final bool noteModified;

  @override
  final gj.EditorCommon common;

  final bool editMode;
  final String? highlightString;
  final ThemeData theme;

  const AppFlowyNoteEditor({
    super.key,
    required this.note,
    required this.parentFolder,
    required this.noteModified,
    required this.editMode,
    required this.highlightString,
    required this.theme,
    required this.common,
  });

  @override
  AppFlowyNoteEditorState createState() => AppFlowyNoteEditorState();
}

class AppFlowyNoteEditorState extends State<AppFlowyNoteEditor>
    with DisposableChangeNotifier
    implements gj.EditorState {
  EditorState? _editorState;
  late TextEditingController _titleController;
  bool _isModified = false;
  late Note _note;
  late AppFlowyEditorMarkdownCodec _markdownCodec;
  StreamSubscription? _transactionSub;
  bool _showDebug = false;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _isModified = widget.noteModified;
    _titleController = TextEditingController(text: _note.title ?? '');
    _markdownCodec = AppFlowyEditorMarkdownCodec();

    _log('initState called');
    _log('editMode: ${widget.editMode}');
    _log('noteModified: ${widget.noteModified}');
    _log('note body length: ${_note.body.length}');

    try {
      final document = _markdownCodec.decode(_note.body);
      _log('Document decoded successfully, root children: ${document.root.children.length}');

      _editorState = EditorState(document: document);
      _log('EditorState created');

      _transactionSub = _editorState!.transactionStream.listen((event) {
        _log('Transaction event received');
        if (!_isModified) {
          _log('Setting _isModified = true');
          setState(() {
            _isModified = true;
          });
          notifyListeners();
        }
      });

      _log('initState completed successfully');
    } catch (e, st) {
      _log('ERROR in initState: $e');
      _log('Stack: $st');
    }
  }

  @override
  void dispose() {
    _log('dispose called');
    _transactionSub?.cancel();
    _titleController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AppFlowyNoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _log('didUpdateWidget called');
    if (oldWidget.noteModified != widget.noteModified) {
      _isModified = widget.noteModified;
    }
    if (oldWidget.note != widget.note) {
      _note = widget.note;
      _titleController.text = _note.title ?? '';
      try {
        final document = _markdownCodec.decode(_note.body);
        _editorState = EditorState(document: document);
        _log('EditorState recreated for new note');
      } catch (e) {
        _log('ERROR recreating EditorState: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _log('build called, editMode: ${widget.editMode}');

    final body = Stack(
      children: [
        Column(
          children: [
            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  hintText: 'Title',
                  border: InputBorder.none,
                ),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                onChanged: (_) {
                  _isModified = true;
                  notifyListeners();
                },
              ),
            ),
            const Divider(height: 1),
            // Toolbar (only in edit mode)
            if (widget.editMode) _buildToolbar(),
            const Divider(height: 1),
            // Editor
            Expanded(
              child: _buildEditor(),
            ),
          ],
        ),
        // Debug log overlay
        if (_showDebug) _buildDebugOverlay(),
      ],
    );

    return gj.EditorScaffold(
      startingNote: widget.note,
      editor: widget,
      editorState: this,
      noteModified: _isModified,
      editMode: widget.editMode,
      parentFolder: _note.parent,
      body: body,
      onUndoSelected: () {
        _log('Undo selected');
      },
      onRedoSelected: () {
        _log('Redo selected');
      },
      undoAllowed: false,
      redoAllowed: false,
      findAllowed: false,
    );
  }

  Widget _buildEditor() {
    if (_editorState == null) {
      _log('Editor: showing loading indicator (EditorState is null)');
      return const Center(child: CircularProgressIndicator());
    }

    _log('Building AppFlowyEditor widget');

    return GestureDetector(
      onTap: () {
        _log('GestureDetector onTap');
        // Dismiss any potential focus conflicts
        FocusScope.of(context).unfocus();
      },
      child: AppFlowyEditor(
        editorState: _editorState!,
        editable: widget.editMode,
        autoFocus: widget.editMode,
        editorStyle: EditorStyle.mobile(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        characterShortcutEvents: standardCharacterShortcutEvents,
        commandShortcutEvents: standardCommandShortcutEvents,
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      color: Colors.grey.shade100,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _toolbarButton(
              icon: Icons.format_bold,
              tooltip: 'Bold',
              onPressed: () {
                _log('Bold pressed');
                _editorState?.toggleAttribute(BuiltInAttributeKey.bold);
              },
            ),
            _toolbarButton(
              icon: Icons.format_italic,
              tooltip: 'Italic',
              onPressed: () {
                _log('Italic pressed');
                _editorState?.toggleAttribute(BuiltInAttributeKey.italic);
              },
            ),
            _toolbarButton(
              icon: Icons.format_underline,
              tooltip: 'Underline',
              onPressed: () {
                _log('Underline pressed');
                _editorState?.toggleAttribute(BuiltInAttributeKey.underline);
              },
            ),
            _toolbarButton(
              icon: Icons.strikethrough_s,
              tooltip: 'Strikethrough',
              onPressed: () {
                _log('Strikethrough pressed');
                _editorState?.toggleAttribute(BuiltInAttributeKey.strikethrough);
              },
            ),
            _toolbarDivider(),
            _toolbarButton(
              icon: Icons.format_list_bulleted,
              tooltip: 'Bullet List',
              onPressed: () {
                _log('Bullet list pressed');
                _editorState?.toggleAttribute(BuiltInAttributeKey.bulletedList);
              },
            ),
            _toolbarButton(
              icon: Icons.format_list_numbered,
              tooltip: 'Numbered List',
              onPressed: () {
                _log('Numbered list pressed');
                _editorState?.toggleAttribute(BuiltInAttributeKey.numberList);
              },
            ),
            _toolbarButton(
              icon: Icons.check_box_outlined,
              tooltip: 'Todo List',
              onPressed: () {
                _log('Todo list pressed');
                _editorState?.toggleAttribute(BuiltInAttributeKey.checkbox);
              },
            ),
            _toolbarDivider(),
            _toolbarButton(
              icon: Icons.format_quote,
              tooltip: 'Quote',
              onPressed: () {
                _log('Quote pressed');
                _editorState?.toggleAttribute(BuiltInAttributeKey.quote);
              },
            ),
            _toolbarButton(
              icon: Icons.code,
              tooltip: 'Code',
              onPressed: () {
                _log('Code pressed');
                _editorState?.toggleAttribute(BuiltInAttributeKey.code);
              },
            ),
            _toolbarDivider(),
            // Debug toggle button
            _toolbarButton(
              icon: Icons.bug_report,
              tooltip: 'Debug Log',
              onPressed: () {
                _log('Debug toggle pressed');
                setState(() {
                  _showDebug = !_showDebug;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugOverlay() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 200,
      child: Container(
        color: Colors.black87,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: Colors.red,
              child: Row(
                children: [
                  const Text('Debug Log', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() => _showDebug = false);
                    },
                    child: const Text('Close', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _debugLogs.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    child: Text(
                      _debugLogs[index],
                      style: TextStyle(
                        color: _debugLogs[index].contains('ERROR') ? Colors.redAccent : Colors.greenAccent,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  Widget _toolbarDivider() {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.grey.shade400,
    );
  }

  @override
  Note getNote() {
    _log('getNote called');
    if (_editorState == null) {
      _log('WARNING: getNote called but EditorState is null');
      return _note;
    }
    final body = _markdownCodec.encode(_editorState!.document);
    _log('getNote: encoded body length = ${body.length}');
    return _note.copyWith(
      body: body,
      title: _titleController.text.trim(),
      type: NoteType.Unknown,
    );
  }

  @override
  bool get noteModified => _isModified;

  @override
  Future<void> addImage(String filePath) async {
    _log('addImage called: $filePath');
  }

  @override
  gj.SearchInfo search(String? text) {
    _log('search called: $text');
    return gj.SearchInfo.compute(body: _note.body, text: text);
  }

  @override
  void scrollToResult(String text, int num) {
    _log('scrollToResult called');
  }
}
