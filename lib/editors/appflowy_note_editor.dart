// SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
//
// SPDX-License-Identifier: AGPL-3.0-or-later
// TAG: AppFlowy Editor Support v2
// Features: WYSIWYG editing, Tables, Bullet/Numbered lists, Checkboxes, Headings
// Build: 61
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
  String _originalMarkdown = '';  // 保存原始 Markdown，用于未修改时恢复
  VoidCallback? _selectionListener;
  bool _isInTable = false;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _isModified = widget.noteModified;
    _titleController = TextEditingController(text: _note.title ?? '');

    _originalMarkdown = _note.body;  // 保存原始 Markdown
    final document = markdownToDocument(_note.body);
    _editorState = EditorState(document: document);

    // 监听 transaction 用于标记修改
    _transactionSub = _editorState.transactionStream.listen((_) {
      if (!_isModified) {
        setState(() {
          _isModified = true;
        });
        notifyListeners();
      }
    });

    // 监听 selection 变化用于切换工具栏
    _selectionListener = () {
      _updateTableState();
    };
    _editorState.selectionNotifier.addListener(_selectionListener!);
  }

  void _updateTableState() {
    if (!mounted) return;
    
    final wasInTable = _isInTable;
    _isInTable = _isSelectionInTable();
    
    if (wasInTable != _isInTable) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _transactionSub?.cancel();
    if (_selectionListener != null) {
      _editorState.selectionNotifier.removeListener(_selectionListener!);
    }
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

  /// Check if current selection is inside a table
  bool _isSelectionInTable() {
    final sel = _editorState.selection;
    if (sel == null) return false;
    Node? current = _editorState.getNodeAtPath(sel.start.path);
    while (current != null) {
      if (current.type == TableBlockKeys.type) {
        return true;
      }
      current = current.parent;
    }
    return false;
  }

  /// Find table node from current selection
  Node? _findTableNode() {
    final sel = _editorState.selection;
    if (sel == null) return null;
    for (int i = sel.start.path.length - 1; i >= 0; i--) {
      final path = sel.start.path.sublist(0, i + 1);
      final node = _editorState.getNodeAtPath(path);
      if (node != null && node.type == TableBlockKeys.type) {
        return node;
      }
    }
    return null;
  }

  /// Get cell position in table
  MapEntry<int, int>? _getTableCellPosition() {
    final sel = _editorState.selection;
    if (sel == null) return null;
    if (sel.start.path.length < 3) return null;
    final colIndex = sel.start.path[sel.start.path.length - 2];
    final rowIndex = sel.start.path[sel.start.path.length - 1];
    return MapEntry(rowIndex, colIndex);
  }

  @override
  @override
  Note getNote() {
    // 如果没有修改，返回原始 Markdown（避免被规范化）
    if (!_isModified) {
      return _note.copyWith(
        body: _originalMarkdown,
        title: _titleController.text.trim(),
        type: NoteType.Unknown,
      );
    }
    // 有修改时才从编辑器获取内容
    final body = documentToMarkdown(_editorState.document);
    return _note.copyWith(
      body: body,
      title: _titleController.text.trim(),
      type: NoteType.Unknown,
    );
  }

  @override
  Future<void> addImage(String filePath) async {
    // TODO: Implement image insertion
  }

  @override
  bool get noteModified => _isModified;

  @override
  gj.SearchInfo search(String? text) {
    // TODO: Implement search
    return gj.SearchInfo();
  }

  @override
  void scrollToResult(String text, int num) {
    // TODO: Implement scroll to result
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
      showMagnifier: false,
      editorStyle: EditorStyle.mobile(
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
    return Material(
      color: colorScheme.surfaceContainerLow,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _isInTable
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
        onPressed: () => _toggleHeading(1),
      ),
      _buildToolbarButton(
        icon: Icons.format_size,
        tooltip: 'Heading H2',
        onPressed: () => _toggleHeading(2),
      ),
      _buildToolbarButton(
        icon: Icons.format_size,
        tooltip: 'Heading H3',
        onPressed: () => _toggleHeading(3),
        iconSize: 18,
      ),
      _buildDivider(colorScheme),
      _buildToolbarButton(
        icon: Icons.format_bold,
        tooltip: 'Bold',
        onPressed: () => _editorState.toggleAttribute(BuiltInAttributeKey.bold),
      ),
      _buildToolbarButton(
        icon: Icons.format_italic,
        tooltip: 'Italic',
        onPressed: () => _editorState.toggleAttribute(BuiltInAttributeKey.italic),
      ),
      _buildToolbarButton(
        icon: Icons.format_underlined,
        tooltip: 'Underline',
        onPressed: () => _editorState.toggleAttribute(BuiltInAttributeKey.underline),
      ),
      _buildToolbarButton(
        icon: Icons.strikethrough_s,
        tooltip: 'Strikethrough',
        onPressed: () => _editorState.toggleAttribute(BuiltInAttributeKey.strikethrough),
      ),
      _buildDivider(colorScheme),
      _buildToolbarButton(
        icon: Icons.format_list_bulleted,
        tooltip: 'Bullet List',
        onPressed: () => _toggleBlockType(BulletedListBlockKeys.type),
      ),
      _buildToolbarButton(
        icon: Icons.format_list_numbered,
        tooltip: 'Numbered List',
        onPressed: () => _toggleBlockType(NumberedListBlockKeys.type),
      ),
      _buildToolbarButton(
        icon: Icons.check_box_outlined,
        tooltip: 'Todo List',
        onPressed: () => _toggleTodoList(),
      ),
      _buildDivider(colorScheme),
      _buildToolbarButton(
        icon: Icons.format_quote,
        tooltip: 'Quote',
        onPressed: () => _toggleBlockType(QuoteBlockKeys.type),
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
        icon: Icons.table_chart,
        tooltip: 'Table: Add Row Below',
        onPressed: _tableAddRow,
      ),
      _buildToolbarButton(
        icon: Icons.view_column,
        tooltip: 'Table: Add Column Right',
        onPressed: _tableAddColumn,
      ),
      _buildDivider(colorScheme),
      _buildToolbarButton(
        icon: Icons.delete_outline,
        tooltip: 'Table: Delete Row',
        onPressed: _tableDeleteRow,
      ),
      _buildToolbarButton(
        icon: Icons.delete_sweep,
        tooltip: 'Table: Delete Column',
        onPressed: _tableDeleteColumn,
      ),
      _buildDivider(colorScheme),
      _buildToolbarButton(
        icon: Icons.content_copy,
        tooltip: 'Table: Duplicate Row',
        onPressed: _tableDuplicateRow,
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

  /// Toggle block type using formatNode
  void _toggleBlockType(String targetType) {
    final selection = _editorState.selection;
    if (selection == null) {
      debugPrint('No selection available');
      return;
    }
    final node = _editorState.getNodeAtPath(selection.start.path);
    if (node == null) {
      debugPrint('No node at selection');
      return;
    }
    final newType = node.type == targetType ? ParagraphBlockKeys.type : targetType;
    debugPrint('Toggling block: ${node.type} -> $newType at path ${selection.start.path}');
    _editorState.formatNode(
      selection,
      (node) => node.copyWith(type: newType),
    );
  }

  /// Toggle todo list with checked attribute
  void _toggleTodoList() {
    final selection = _editorState.selection;
    if (selection == null) {
      debugPrint('No selection available');
      return;
    }
    final node = _editorState.getNodeAtPath(selection.start.path);
    if (node == null) {
      debugPrint('No node at selection');
      return;
    }
    final isTodo = node.type == TodoListBlockKeys.type;
    final newType = isTodo ? ParagraphBlockKeys.type : TodoListBlockKeys.type;
    debugPrint('Toggling todo: ${node.type} -> $newType');
    if (isTodo) {
      _editorState.formatNode(
        selection,
        (node) => node.copyWith(type: newType),
      );
    } else {
      _editorState.formatNode(
        selection,
        (node) => node.copyWith(
          type: newType,
          attributes: {
            ...node.attributes,
            TodoListBlockKeys.checked: false,
          },
        ),
      );
    }
  }

  /// Toggle heading level
  void _toggleHeading(int level) {
    final selection = _editorState.selection;
    if (selection == null) {
      debugPrint('No selection available');
      return;
    }
    final node = _editorState.getNodeAtPath(selection.start.path);
    if (node == null) {
      debugPrint('No node at selection');
      return;
    }
    final isHeading = node.type == HeadingBlockKeys.type;
    final currentLevel = node.attributes[HeadingBlockKeys.level] ?? 1;
    final shouldToggleOff = isHeading && currentLevel == level;
    final newType = shouldToggleOff ? ParagraphBlockKeys.type : HeadingBlockKeys.type;
    final newAttributes = shouldToggleOff
        ? <String, dynamic>{}
        : {...node.attributes, HeadingBlockKeys.level: level};
    debugPrint('Toggling heading: ${node.type} -> $newType level $level');
    _editorState.formatNode(
      selection,
      (node) => node.copyWith(
        type: newType,
        attributes: newAttributes,
      ),
    );
  }

  // --- Table Operations ---
  void _showInsertTableDialog() {
    showDialog(
      context: context,
      builder: (context) => _InsertTableDialog(
        onInsert: _insertTable,
      ),
    );
  }

  void _insertTable(int rows, int cols) {
    final sel = _editorState.selection;
    final lastPath = [_editorState.document.root.children.length - 1];
    final insertPath = sel?.end.path ?? lastPath;
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
    debugPrint('Inserted table ${rows}x$cols');
  }

  void _tableAddRow() {
    final tableNode = _findTableNode();
    final cellPos = _getTableCellPosition();
    if (tableNode == null || cellPos == null) {
      debugPrint('No table or cell position found');
      return;
    }
    final transaction = _editorState.transaction;
    final newRow = tableNode.children[cellPos.value].copyWith();
    transaction.insertNode(
      tableNode.children[cellPos.value].path.next,
      newRow,
    );
    _editorState.apply(transaction);
    debugPrint('Added row at index ${cellPos.value}');
  }

  void _tableAddColumn() {
    final tableNode = _findTableNode();
    if (tableNode == null) {
      debugPrint('No table found');
      return;
    }
    final cellPos = _getTableCellPosition();
    if (cellPos == null) {
      debugPrint('No cell position found');
      return;
    }
    final transaction = _editorState.transaction;
    for (final row in tableNode.children) {
      final newCell = tableCellNode('', row.attributes[TableCellBlockKeys.rowPosition] as int? ?? 0, cellPos.key);
      transaction.insertNode(
        row.children[cellPos.key].path.next,
        newCell,
      );
    }
    _editorState.apply(transaction);
    debugPrint('Added column at index ${cellPos.key}');
  }

  void _tableDeleteRow() {
    final tableNode = _findTableNode();
    final cellPos = _getTableCellPosition();
    if (tableNode == null || cellPos == null) {
      debugPrint('No table or cell position found');
      return;
    }
    final transaction = _editorState.transaction;
    transaction.deleteNode(tableNode.children[cellPos.value]);
    _editorState.apply(transaction);
    debugPrint('Deleted row at index ${cellPos.value}');
  }

  void _tableDeleteColumn() {
    final tableNode = _findTableNode();
    if (tableNode == null) {
      debugPrint('No table found');
      return;
    }
    final cellPos = _getTableCellPosition();
    if (cellPos == null) {
      debugPrint('No cell position found');
      return;
    }
    final transaction = _editorState.transaction;
    for (final row in tableNode.children) {
      transaction.deleteNode(row.children[cellPos.key]);
    }
    _editorState.apply(transaction);
    debugPrint('Deleted column at index ${cellPos.key}');
  }

  void _tableDuplicateRow() {
    final tableNode = _findTableNode();
    final cellPos = _getTableCellPosition();
    if (tableNode == null || cellPos == null) {
      debugPrint('No table or cell position found');
      return;
    }
    final rowToCopy = tableNode.children[cellPos.value];
    final transaction = _editorState.transaction;
    final newRow = rowToCopy.copyWith();
    transaction.insertNode(rowToCopy.path.next, newRow);
    _editorState.apply(transaction);
    debugPrint('Duplicated row at index ${cellPos.value}');
  }
}

// --- Insert Table Dialog ---
class _InsertTableDialog extends StatefulWidget {
  final Function(int rows, int cols) onInsert;

  const _InsertTableDialog({required this.onInsert});

  @override
  _InsertTableDialogState createState() => _InsertTableDialogState();
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
              Expanded(
                child: Slider(
                  value: _rows.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: _rows.toString(),
                  onChanged: (value) {
                    setState(() {
                      _rows = value.toInt();
                    });
                  },
                ),
              ),
              Text(_rows.toString()),
            ],
          ),
          Row(
            children: [
              const Text('Columns:'),
              Expanded(
                child: Slider(
                  value: _cols.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: _cols.toString(),
                  onChanged: (value) {
                    setState(() {
                      _cols = value.toInt();
                    });
                  },
                ),
              ),
              Text(_cols.toString()),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            widget.onInsert(_rows, _cols);
            Navigator.pop(context);
          },
          child: const Text('Insert'),
        ),
      ],
    );
  }
}
