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
  StreamSubscription? _selectionSub;

  /// Cache the last valid selection
  Selection? _lastSelection;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _isModified = widget.noteModified;
    _titleController = TextEditingController(text: _note.title ?? '');

    final document = markdownToDocument(_note.body);
    _editorState = EditorState(document: document);

    // Track selection via transaction stream
    _selectionSub = _editorState.transactionStream.listen((_) {
      final sel = _editorState.selection;
      if (sel != null) {
        _lastSelection = sel;
      }
    });

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
    _selectionSub?.cancel();
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

  /// Get current selection or fall back to cached
  Selection? _getSelection() {
    final current = _editorState.selection;
    if (current != null) return current;
    return _lastSelection;
  }

  /// Get the last path in the document
  Path _getLastPath() {
    final node = _editorState.document.root;
    return [node.children.length - 1];
  }

  /// Find the nearest table node from the current selection
  Node? _findTableNode(Selection? sel) {
    final s = sel ?? _lastSelection;
    if (s == null) return null;
    for (int i = s.start.path.length - 1; i >= 0; i--) {
      final node = _editorState.getNodeAtPath(s.start.path.sublist(0, i + 1));
      if (node != null && node.type == TableBlockKeys.type) {
        return node;
      }
    }
    return null;
  }

  /// Get row and column position from current selection in a table
  MapEntry<int, int>? _getTableCellPosition(Selection? sel) {
    final s = sel ?? _lastSelection;
    if (s == null) return null;
    // Path structure: [..., tableIndex, colIndex, rowIndex]
    if (s.start.path.length < 3) return null;
    final colIndex = s.start.path[s.start.path.length - 2];
    final rowIndex = s.start.path[s.start.path.length - 1];
    return MapEntry(rowIndex, colIndex);
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
          _buildToolbar(colorScheme),
          const Divider(height: 1),
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
      editable: true,
      autoFocus: true,
      editorStyle: EditorStyle.desktop(
        padding: const EdgeInsets.all(16),
        cursorColor: colorScheme.primary,
        selectionColor: colorScheme.primaryContainer.withValues(alpha: 0.4),
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
            backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
            fontFamily: 'monospace',
            fontSize: 14,
          ),
        ),
      ),
      blockComponentBuilders: standardBlockComponentBuilderMap,
      characterShortcutEvents: standardCharacterShortcutEvents,
      commandShortcutEvents: standardCommandShortcutEvents,
    );
  }

  Widget _buildToolbar(ColorScheme colorScheme) {
    final isInTable = _findTableNode(null) != null;

    return Material(
      color: colorScheme.surfaceContainerLow,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: isInTable
                ? _buildTableToolbar(colorScheme)
                : _buildNormalToolbar(colorScheme),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildNormalToolbar(ColorScheme colorScheme) {
    return [
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
      _buildToolbarButton(
        icon: Icons.format_bold,
        tooltip: 'Bold',
        onPressed: () => _toggleSelectionAttribute(BuiltInAttributeKey.bold),
      ),
      _buildToolbarButton(
        icon: Icons.format_italic,
        tooltip: 'Italic',
        onPressed: () => _toggleSelectionAttribute(BuiltInAttributeKey.italic),
      ),
      _buildToolbarButton(
        icon: Icons.format_underlined,
        tooltip: 'Underline',
        onPressed: () => _toggleSelectionAttribute(BuiltInAttributeKey.underline),
      ),
      _buildToolbarButton(
        icon: Icons.strikethrough_s,
        tooltip: 'Strikethrough',
        onPressed: () => _toggleSelectionAttribute(BuiltInAttributeKey.strikethrough),
      ),
      _buildDivider(colorScheme),
      _buildToolbarButton(
        icon: Icons.format_list_bulleted,
        tooltip: 'Bullet List',
        onPressed: () => _toggleSelectionAttribute(BuiltInAttributeKey.bulletedList),
      ),
      _buildToolbarButton(
        icon: Icons.format_list_numbered,
        tooltip: 'Numbered List',
        onPressed: () => _toggleSelectionAttribute(BuiltInAttributeKey.numberList),
      ),
      _buildToolbarButton(
        icon: Icons.check_box_outlined,
        tooltip: 'Todo List',
        onPressed: () => _toggleSelectionAttribute(BuiltInAttributeKey.checkbox),
      ),
      _buildDivider(colorScheme),
      _buildToolbarButton(
        icon: Icons.format_quote,
        tooltip: 'Quote',
        onPressed: () => _toggleSelectionAttribute(BuiltInAttributeKey.quote),
      ),
      _buildToolbarButton(
        icon: Icons.code,
        tooltip: 'Code Block',
        onPressed: () => _toggleSelectionAttribute(BuiltInAttributeKey.code),
      ),
      _buildToolbarButton(
        icon: Icons.table_chart,
        tooltip: 'Insert Table',
        onPressed: _showInsertTableDialog,
      ),
    ];
  }

  List<Widget> _buildTableToolbar(ColorScheme colorScheme) {
    return [
      _buildToolbarButton(
        icon: Icons.arrow_back,
        tooltip: 'Back to Editor',
        onPressed: () {
          // Move selection out of table to show normal toolbar
          final sel = _getSelection();
          if (sel != null) {
            // Just update state to trigger rebuild - toolbar will switch
          setState(() {});
          }
        },
      ),
      _buildDivider(colorScheme),
      _buildToolbarButton(
        icon: Icons.add,
        tooltip: 'Add Row Below',
        onPressed: () => _tableAddRow(),
      ),
      _buildToolbarButton(
        icon: Icons.add_circle_outline,
        tooltip: 'Add Column Right',
        onPressed: () => _tableAddColumn(),
      ),
      _buildDivider(colorScheme),
      _buildToolbarButton(
        icon: Icons.remove,
        tooltip: 'Delete Row',
        onPressed: () => _tableDeleteRow(),
      ),
      _buildToolbarButton(
        icon: Icons.remove_circle_outline,
        tooltip: 'Delete Column',
        onPressed: () => _tableDeleteColumn(),
      ),
      _buildDivider(colorScheme),
      _buildToolbarButton(
        icon: Icons.content_copy,
        tooltip: 'Duplicate Row',
        onPressed: () => _tableDuplicateRow(),
      ),
      _buildToolbarButton(
        icon: Icons.table_chart,
        tooltip: 'Insert New Table',
        onPressed: _showInsertTableDialog,
      ),
    ];
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
      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
    );
  }

  /// Toggle attribute - works with or without text selection
  void _toggleSelectionAttribute(String attributeKey) {
    final sel = _getSelection();
    if (sel == null) {
      debugPrint('No selection available for $attributeKey');
      return;
    }

    // Restore selection first, then toggle after frame renders
    _editorState.updateSelectionWithReason(
      sel,
      reason: SelectionUpdateReason.uiEvent,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _editorState.toggleAttribute(attributeKey);
        debugPrint('Toggled $attributeKey');
      }
    });
  }

  /// Insert heading - replace current node with heading node
  void _insertHeading(int level) {
    var sel = _editorState.selection;
    if (sel == null) sel = _lastSelection;
    if (sel == null) return;

    _editorState.updateSelectionWithReason(
      sel,
      reason: SelectionUpdateReason.uiEvent,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final transaction = _editorState.transaction;
      final node = _editorState.getNodeAtPath(sel.start.path);
      if (node != null) {
        final text = node.delta?.toPlainText() ?? '';
        transaction.deleteNode(node);
        transaction.insertNode(
          sel.start.path,
          headingNode(level: level, text: text),
        );
        _editorState.apply(transaction);
      }
    });
  }

  // --- Table Operations ---

  void _showInsertTableDialog() {
    showDialog(
      context: context,
      builder: (context) => _InsertTableDialog(
        onInsert: (rows, cols) => _insertTable(rows, cols),
      ),
    );
  }

  void _insertTable(int rows, int cols) {
    final sel = _getSelection();
    final insertPath = sel?.end.path ?? _getLastPath();

    final tableData = List.generate(
      cols,
      (_) => List.generate(rows, (_) => ''),
    );

    final tableNode = TableNode.fromList(tableData);

    final transaction = _editorState.transaction;
    final currentNode = _editorState.getNodeAtPath(insertPath);

    if (currentNode != null &&
        currentNode.delta != null &&
        currentNode.delta!.isEmpty) {
      transaction.deleteNode(currentNode);
      transaction.insertNode(insertPath, tableNode.node);
    } else {
      transaction.insertNode(insertPath.next, tableNode.node);
    }

    transaction.afterSelection = Selection.collapsed(
      Position(path: insertPath + [0, 0], offset: 0),
    );

    _editorState.apply(transaction);
  }

  void _tableAddRow() {
    final tableNode = _findTableNode(null);
    final cellPos = _getTableCellPosition(null);
    if (tableNode == null || cellPos == null) return;

    TableActions.add(
      tableNode,
      cellPos.key, // rowIndex
      _editorState,
      TableDirection.row,
    );
    debugPrint('Added row after ${cellPos.key}');
  }

  void _tableAddColumn() {
    final tableNode = _findTableNode(null);
    final cellPos = _getTableCellPosition(null);
    if (tableNode == null || cellPos == null) return;

    TableActions.add(
      tableNode,
      cellPos.value, // colIndex
      _editorState,
      TableDirection.col,
    );
    debugPrint('Added column after ${cellPos.value}');
  }

  void _tableDeleteRow() {
    final tableNode = _findTableNode(null);
    final cellPos = _getTableCellPosition(null);
    if (tableNode == null || cellPos == null) return;

    final table = TableNode(node: tableNode);
    if (table.rowsLen <= 1) {
      debugPrint('Cannot delete the last row');
      return;
    }

    TableActions.delete(
      tableNode,
      cellPos.key,
      _editorState,
      TableDirection.row,
    );
    debugPrint('Deleted row ${cellPos.key}');
  }

  void _tableDeleteColumn() {
    final tableNode = _findTableNode(null);
    final cellPos = _getTableCellPosition(null);
    if (tableNode == null || cellPos == null) return;

    final table = TableNode(node: tableNode);
    if (table.colsLen <= 1) {
      debugPrint('Cannot delete the last column');
      return;
    }

    TableActions.delete(
      tableNode,
      cellPos.value,
      _editorState,
      TableDirection.col,
    );
    debugPrint('Deleted column ${cellPos.value}');
  }

  void _tableDuplicateRow() {
    final tableNode = _findTableNode(null);
    final cellPos = _getTableCellPosition(null);
    if (tableNode == null || cellPos == null) return;

    TableActions.duplicate(
      tableNode,
      cellPos.key,
      _editorState,
      TableDirection.row,
    );
    debugPrint('Duplicated row ${cellPos.key}');
  }

  // --- Editor State ---

  @override
  Note getNote() {
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
  Future<void> addImage(String filePath) async {}

  @override
  gj.SearchInfo search(String? text) {
    return gj.SearchInfo.compute(body: _note.body, text: text);
  }

  @override
  void scrollToResult(String text, int num) {}
}

class _InsertTableDialog extends StatefulWidget {
  final Function(int rows, int cols) onInsert;

  const _InsertTableDialog({required this.onInsert});

  @override
  State<_InsertTableDialog> createState() => _InsertTableDialogState();
}

class _InsertTableDialogState extends State<_InsertTableDialog> {
  int _rows = 3;
  int _cols = 3;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Insert Table'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('Rows:'),
              const SizedBox(width: 16),
              Expanded(
                child: Slider(
                  value: _rows.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: _rows.toString(),
                  onChanged: (value) {
                    setState(() {
                      _rows = value.round();
                    });
                  },
                ),
              ),
              Text('$_rows'),
            ],
          ),
          Row(
            children: [
              const Text('Cols:'),
              const SizedBox(width: 16),
              Expanded(
                child: Slider(
                  value: _cols.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: _cols.toString(),
                  onChanged: (value) {
                    setState(() {
                      _cols = value.round();
                    });
                  },
                ),
              ),
              Text('$_cols'),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.onInsert(_rows, _cols);
            Navigator.of(context).pop();
          },
          child: const Text('Insert'),
        ),
      ],
    );
  }
}
