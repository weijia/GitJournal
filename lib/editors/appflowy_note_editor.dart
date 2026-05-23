/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'package:flutter/material.dart';
import 'package:gitjournal/core/folder/notes_folder.dart';
import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/core/notes/note.dart';
import 'package:gitjournal/editors/common.dart' as gj;
import 'package:gitjournal/editors/utils/disposable_change_notifier.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

/// A standalone WYSIWYG Markdown Editor using AppFlowy Editor
///
/// Provides rich text editing with Markdown import/export support.
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
  late EditorState _editorState;
  late TextEditingController _titleController;
  bool _isModified = false;
  late Note _note;
  late AppFlowyEditorMarkdownCodec _markdownCodec;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _isModified = widget.noteModified;
    _titleController = TextEditingController(text: _note.title ?? '');
    _markdownCodec = AppFlowyEditorMarkdownCodec();

    // Parse markdown to document
    final document = _markdownCodec.decode(_note.body);
    _editorState = EditorState(document: document);

    // Listen for changes
    _editorState.transactionStream.listen((_) {
      if (!_isModified) {
        setState(() {
          _isModified = true;
        });
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AppFlowyNoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteModified != widget.noteModified) {
      _isModified = widget.noteModified;
    }
    if (oldWidget.note != widget.note) {
      _note = widget.note;
      _titleController.text = _note.title ?? '';
      final document = _markdownCodec.decode(_note.body);
      _editorState = EditorState(document: document);
    }
  }

  @override
  Widget build(BuildContext context) {
    return gj.EditorScaffold(
      startingNote: widget.note,
      editor: widget,
      editorState: this,
      noteModified: _isModified,
      editMode: widget.editMode,
      parentFolder: _note.parent,
      body: Column(
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
            child: AppFlowyEditor(
              editorState: _editorState,
              editorStyle: EditorStyle.desktop(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              characterShortcutEvents: standardCharacterShortcutEvents,
              commandShortcutEvents: standardCommandShortcutEvents,
            ),
          ),
        ],
      ),
      onUndoSelected: () {},
      onRedoSelected: () {},
      undoAllowed: false,
      redoAllowed: false,
      findAllowed: false,
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
              onPressed: () => _editorState.toggleAttribute(BuiltInAttributeKey.bold),
            ),
            _toolbarButton(
              icon: Icons.format_italic,
              tooltip: 'Italic',
              onPressed: () => _editorState.toggleAttribute(BuiltInAttributeKey.italic),
            ),
            _toolbarButton(
              icon: Icons.format_underline,
              tooltip: 'Underline',
              onPressed: () => _editorState.toggleAttribute(BuiltInAttributeKey.underline),
            ),
            _toolbarButton(
              icon: Icons.strikethrough_s,
              tooltip: 'Strikethrough',
              onPressed: () => _editorState.toggleAttribute(BuiltInAttributeKey.strikethrough),
            ),
            _toolbarDivider(),
            _toolbarButton(
              icon: Icons.format_list_bulleted,
              tooltip: 'Bullet List',
              onPressed: () => _editorState.toggleAttribute(BuiltInAttributeKey.bulletedList),
            ),
            _toolbarButton(
              icon: Icons.format_list_numbered,
              tooltip: 'Numbered List',
              onPressed: () => _editorState.toggleAttribute(BuiltInAttributeKey.numberList),
            ),
            _toolbarButton(
              icon: Icons.check_box_outlined,
              tooltip: 'Todo List',
              onPressed: () => _editorState.toggleAttribute(BuiltInAttributeKey.checkbox),
            ),
            _toolbarDivider(),
            _toolbarButton(
              icon: Icons.format_quote,
              tooltip: 'Quote',
              onPressed: () => _editorState.toggleAttribute(BuiltInAttributeKey.quote),
            ),
            _toolbarButton(
              icon: Icons.code,
              tooltip: 'Code',
              onPressed: () => _editorState.toggleAttribute(BuiltInAttributeKey.code),
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
    final body = _markdownCodec.encode(_editorState.document);
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
    // Image insertion not yet supported in AppFlowy Editor mode
  }

  @override
  gj.SearchInfo search(String? text) {
    return gj.SearchInfo.compute(body: _markdownCodec.encode(_editorState.document), text: text);
  }

  @override
  void scrollToResult(String text, int num) {
    // Search scroll not yet supported in AppFlowy Editor mode
  }
}
