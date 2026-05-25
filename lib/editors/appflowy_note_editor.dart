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

/// A standalone WYSIWYG Markdown Editor using AppFlowy Editor
/// Based on obsidian-git implementation
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
  StreamSubscription? _transactionSub;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _isModified = widget.noteModified;
    _titleController = TextEditingController(text: _note.title ?? '');

    // Use markdownToDocument from appflowy_editor (same as obsidian-git)
    final document = markdownToDocument(_note.body);
    _editorState = EditorState(document: document);

    // Listen for changes with debounced save
    _transactionSub = _editorState.transactionStream.listen((_) {
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
    _transactionSub?.cancel();
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
      final document = markdownToDocument(_note.body);
      _editorState = EditorState(document: document);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
          // Toolbar
          if (widget.editMode) _buildToolbar(colorScheme),
          const Divider(height: 1),
          // Editor - using desktop style like obsidian-git
          Expanded(
            child: _buildEditor(colorScheme),
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

  Widget _buildEditor(ColorScheme colorScheme) {
    return AppFlowyEditor(
      editorState: _editorState,
      editable: widget.editMode,
      autoFocus: widget.editMode,
      // Use desktop style like obsidian-git
      editorStyle: EditorStyle.desktop(
        padding: const EdgeInsets.all(16),
        cursorColor: colorScheme.primary,
        selectionColor: colorScheme.primaryContainer.withOpacity(0.4),
        textStyleConfiguration: TextStyleConfiguration(
          text: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 16,
            height: 1.5,
          ),
          bold: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
          italic: TextStyle(
            color: colorScheme.onSurface,
            fontStyle: FontStyle.italic,
          ),
          underline: TextStyle(
            color: colorScheme.onSurface,
            decoration: TextDecoration.underline,
          ),
          strikethrough: TextStyle(
            color: colorScheme.onSurface,
            decoration: TextDecoration.lineThrough,
          ),
          code: TextStyle(
            color: colorScheme.primary,
            backgroundColor: colorScheme.primaryContainer.withOpacity(0.3),
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
      ),
      // Use standard block component builders like obsidian-git
      blockComponentBuilders: standardBlockComponentBuilderMap,
      characterShortcutEvents: standardCharacterShortcutEvents,
      commandShortcutEvents: standardCommandShortcutEvents,
    );
  }

  Widget _buildToolbar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Headings
            _buildToolbarButton(
              icon: Icons.title,
              tooltip: 'Heading H1',
              onPressed: () => _insertHeading(1),
            ),
            _buildToolbarButton(
              icon: Icons.format_size,
              tooltip: 'Heading H2',
              onPressed: () => _insertHeading(2),
            ),
            _buildToolbarButton(
              icon: Icons.format_size,
              tooltip: 'Heading H3',
              onPressed: () => _insertHeading(3),
              iconSize: 18,
            ),
            _buildDivider(colorScheme),
            // Formatting
            _buildToolbarButton(
              icon: Icons.format_bold,
              tooltip: 'Bold',
              onPressed: _toggleBold,
            ),
            _buildToolbarButton(
              icon: Icons.format_italic,
              tooltip: 'Italic',
              onPressed: _toggleItalic,
            ),
            _buildToolbarButton(
              icon: Icons.format_underlined,
              tooltip: 'Underline',
              onPressed: _toggleUnderline,
            ),
            _buildToolbarButton(
              icon: Icons.strikethrough_s,
              tooltip: 'Strikethrough',
              onPressed: _toggleStrikethrough,
            ),
            _buildDivider(colorScheme),
            // Lists
            _buildToolbarButton(
              icon: Icons.format_list_bulleted,
              tooltip: 'Bullet List',
              onPressed: _insertBulletList,
            ),
            _buildToolbarButton(
              icon: Icons.format_list_numbered,
              tooltip: 'Numbered List',
              onPressed: _insertNumberedList,
            ),
            _buildToolbarButton(
              icon: Icons.check_box_outlined,
              tooltip: 'Todo List',
              onPressed: _insertTodoList,
            ),
            _buildDivider(colorScheme),
            // Blocks
            _buildToolbarButton(
              icon: Icons.format_quote,
              tooltip: 'Quote',
              onPressed: _insertQuote,
            ),
            _buildToolbarButton(
              icon: Icons.code,
              tooltip: 'Code Block',
              onPressed: _insertCodeBlock,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbarButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    double iconSize = 20,
  }) {
    return IconButton(
      icon: Icon(icon, size: iconSize),
      tooltip: tooltip,
      onPressed: onPressed,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }

  Widget _buildDivider(ColorScheme colorScheme) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: colorScheme.outlineVariant.withOpacity(0.5),
    );
  }

  // Toolbar actions
  void _insertHeading(int level) {
    final selection = _editorState.selection;
    if (selection == null) return;

    final node = _editorState.getNodeAtPath(selection.end.path);
    if (node == null) return;

    final transaction = _editorState.transaction;
    transaction.insertNode(
      selection.end.path,
      headingNode(level: level, text: ''),
    );
    transaction.deleteNode(node);
    _editorState.apply(transaction);
  }

  void _toggleBold() {
    _editorState.toggleAttribute(BuiltInAttributeKey.bold);
  }

  void _toggleItalic() {
    _editorState.toggleAttribute(BuiltInAttributeKey.italic);
  }

  void _toggleUnderline() {
    _editorState.toggleAttribute(BuiltInAttributeKey.underline);
  }

  void _toggleStrikethrough() {
    _editorState.toggleAttribute(BuiltInAttributeKey.strikethrough);
  }

  void _insertBulletList() {
    _editorState.toggleAttribute(BuiltInAttributeKey.bulletedList);
  }

  void _insertNumberedList() {
    _editorState.toggleAttribute(BuiltInAttributeKey.numberList);
  }

  void _insertTodoList() {
    _editorState.toggleAttribute(BuiltInAttributeKey.checkbox);
  }

  void _insertQuote() {
    _editorState.toggleAttribute(BuiltInAttributeKey.quote);
  }

  void _insertCodeBlock() {
    _editorState.toggleAttribute(BuiltInAttributeKey.code);
  }

  @override
  Note getNote() {
    // Use documentToMarkdown from appflowy_editor
    final body = documentToMarkdown(_editorState.document);
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
    // Image insertion not yet supported
  }

  @override
  gj.SearchInfo search(String? text) {
    return gj.SearchInfo.compute(body: _note.body, text: text);
  }

  @override
  void scrollToResult(String text, int num) {
    // Search scroll not yet supported
  }
}
