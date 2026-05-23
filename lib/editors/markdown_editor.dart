/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'package:flutter/material.dart';
import 'package:gitjournal/core/folder/notes_folder.dart';
import 'package:gitjournal/core/image.dart' as core;
import 'package:gitjournal/core/image.dart';
import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/core/notes/note.dart';
import 'package:gitjournal/editors/common.dart' as gj;
import 'package:gitjournal/editors/editor_scroll_view.dart';
import 'package:gitjournal/editors/heuristics.dart';
import 'package:gitjournal/editors/markdown_toolbar.dart';
import 'package:gitjournal/editors/note_body_editor.dart';
import 'package:gitjournal/editors/note_title_editor.dart';
import 'package:gitjournal/editors/undo_redo.dart';
import 'package:gitjournal/editors/utils/disposable_change_notifier.dart';
import 'package:gitjournal/error_reporting.dart';
import 'package:gitjournal/logger/logger.dart';
import 'package:gitjournal/settings/app_config.dart';
import 'package:gitjournal/utils/utils.dart';
import 'package:provider/provider.dart';
import 'package:appflowy_editor/appflowy_editor.dart' as af;

import 'controllers/rich_text_controller.dart';

class MarkdownEditor extends StatefulWidget implements gj.Editor {
  final Note note;
  final NotesFolder parentFolder;
  final bool noteModified;

  @override
  final gj.EditorCommon common;

  final bool editMode;
  final String? highlightString;
  final ThemeData theme;

  const MarkdownEditor({
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
  MarkdownEditorState createState() {
    return MarkdownEditorState();
  }
}

class MarkdownEditorState extends State<MarkdownEditor>
    with DisposableChangeNotifier
    implements gj.EditorState {
  late Note _note;
  late TextEditingController _textController;
  late TextEditingController _titleTextController;
  late UndoRedoStack _undoRedoStack;

  late EditorHeuristics _heuristics;

  late bool _noteModified;

  late ScrollController _scrollController;

  final _bodyEditorKey = GlobalKey();

  // AppFlowy Editor
  af.EditorState? _appFlowyEditorState;

  @override
  void initState() {
    super.initState();
    _note = widget.note;
    _noteModified = widget.noteModified;

    _textController = buildController(
      text: _note.body,
      highlightText: widget.highlightString,
      theme: widget.theme,
    );
    _titleTextController = buildController(
      text: _note.title ?? "",
      highlightText: widget.highlightString,
      theme: widget.theme,
    );
    _heuristics = EditorHeuristics(text: _note.body);

    _scrollController = ScrollController(keepScrollOffset: false);
    _undoRedoStack = UndoRedoStack();

    // Initialize AppFlowy Editor
    _initAppFlowyEditor();
  }

  void _initAppFlowyEditor() {
    final document = _markdownToDocument(_note.body);
    _appFlowyEditorState = af.EditorState(document: document);
  }

  af.Document _markdownToDocument(String markdown) {
    // Simple markdown parser for AppFlowy
    final document = af.Document.blank();
    final lines = markdown.split('\n');
    
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        _insertNode(document, af.paragraphNode(text: ''));
      } else if (trimmed.startsWith('# ')) {
        _insertNode(document, af.headingNode(level: 1, text: trimmed.substring(2)));
      } else if (trimmed.startsWith('## ')) {
        _insertNode(document, af.headingNode(level: 2, text: trimmed.substring(3)));
      } else if (trimmed.startsWith('### ')) {
        _insertNode(document, af.headingNode(level: 3, text: trimmed.substring(4)));
      } else if (trimmed.startsWith('- [ ] ')) {
        _insertNode(document, af.todoListNode(text: trimmed.substring(6), checked: false));
      } else if (trimmed.startsWith('- [x] ') || trimmed.startsWith('- [X] ')) {
        _insertNode(document, af.todoListNode(text: trimmed.substring(6), checked: true));
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        _insertNode(document, af.bulletedListNode(text: trimmed.substring(2)));
      } else if (RegExp(r'^\d+\.\s').hasMatch(trimmed)) {
        final text = trimmed.replaceFirst(RegExp(r'^\d+\.\s'), '');
        _insertNode(document, af.numberedListNode(text: text));
      } else if (trimmed.startsWith('> ')) {
        _insertNode(document, af.quoteNode(text: trimmed.substring(2)));
      } else {
        _insertNode(document, af.paragraphNode(text: trimmed));
      }
    }
    
    return document;
  }

  void _insertNode(af.Document document, af.Node node) {
    final root = document.root;
    root.insert(root.children.length, [node]);
  }

  String _documentToMarkdown(af.Document document) {
    final buffer = StringBuffer();
    final root = document.root;
    
    for (final node in root.children) {
      final type = node.type;
      final delta = node.delta;
      final text = delta?.toPlainText() ?? '';
      
      switch (type) {
        case 'heading':
          final level = node.attributes['level'] ?? 1;
          buffer.writeln('${"#" * level} $text');
          break;
        case 'todo_list':
          final checked = node.attributes['checked'] ?? false;
          buffer.writeln('- [${checked ? "x" : " "}] $text');
          break;
        case 'bulleted_list':
          buffer.writeln('- $text');
          break;
        case 'numbered_list':
          buffer.writeln('1. $text');
          break;
        case 'quote':
          buffer.writeln('> $text');
          break;
        case 'code_block':
          buffer.writeln('```');
          buffer.writeln(text);
          buffer.writeln('```');
          break;
        case 'paragraph':
        default:
          if (text.isNotEmpty) {
            buffer.writeln(text);
          } else {
            buffer.writeln();
          }
          break;
      }
    }
    
    return buffer.toString().trim();
  }

  @override
  void dispose() {
    _textController.dispose();
    _titleTextController.dispose();
    _scrollController.dispose();

    super.disposeListenables();
    super.dispose();
  }

  @override
  void didUpdateWidget(MarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.noteModified != widget.noteModified) {
      _noteModified = widget.noteModified;
    }
    if (oldWidget.note != widget.note) {
      _note = widget.note;
      _textController.text = _note.body;
      _titleTextController.text = _note.title ?? "";
      // Update AppFlowy editor
      _initAppFlowyEditor();
    }
  }

  @override
  Widget build(BuildContext context) {
    var settings = context.watch<AppConfig>();
    
    // Use AppFlowy Editor in edit mode if experimental feature is enabled
    Widget editor;
    if (widget.editMode && settings.experimentalMarkdownToolbar) {
      editor = _buildAppFlowyEditor();
    } else {
      editor = _buildPlainTextEditor();
    }

    Widget? markdownToolbar;
    if (settings.experimentalMarkdownToolbar) {
      if (widget.editMode) {
        // AppFlowy has its own toolbar
        markdownToolbar = null;
      } else {
        markdownToolbar = MarkdownToolBar(
          textController: _textController,
        );
      }
    }

    return gj.EditorScaffold(
      startingNote: widget.note,
      editor: widget,
      editorState: this,
      noteModified: _noteModified,
      editMode: widget.editMode,
      parentFolder: _note.parent,
      body: editor,
      onUndoSelected: _undo,
      onRedoSelected: _redo,
      undoAllowed: _undoRedoStack.undoPossible,
      redoAllowed: _undoRedoStack.redoPossible,
      extraBottomWidget: markdownToolbar,
      findAllowed: true,
    );
  }

  Widget _buildPlainTextEditor() {
    return EditorScrollView(
      scrollController: _scrollController,
      child: Column(
        children: <Widget>[
          NoteTitleEditor(
            _titleTextController,
            _noteTitleTextChanged,
          ),
          NoteBodyEditor(
            key: _bodyEditorKey,
            textController: _textController,
            autofocus: widget.editMode,
            onChanged: _noteTextChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildAppFlowyEditor() {
    if (_appFlowyEditorState == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Title editor (keep plain text for title)
        NoteTitleEditor(
          _titleTextController,
          _noteTitleTextChanged,
        ),
        // AppFlowy Editor for body
        Expanded(
          child: af.AppFlowyEditor.standard(
            editorState: _appFlowyEditorState!,
            editorStyle: af.EditorStyle.desktop(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            header: _buildAppFlowyToolbar(),
          ),
        ),
      ],
    );
  }

  Widget _buildAppFlowyToolbar() {
    if (_appFlowyEditorState == null) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Bold
            IconButton(
              icon: const Icon(Icons.format_bold),
              onPressed: () => _appFlowyEditorState!.toggleAttribute(af.AppFlowyRichTextKeys.bold),
              tooltip: 'Bold',
            ),
            // Italic
            IconButton(
              icon: const Icon(Icons.format_italic),
              onPressed: () => _appFlowyEditorState!.toggleAttribute(af.AppFlowyRichTextKeys.italic),
              tooltip: 'Italic',
            ),
            // Underline
            IconButton(
              icon: const Icon(Icons.format_underline),
              onPressed: () => _appFlowyEditorState!.toggleAttribute(af.AppFlowyRichTextKeys.underline),
              tooltip: 'Underline',
            ),
            const VerticalDivider(),
            // H1
            IconButton(
              icon: const Text('H1', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _appFlowyEditorState!.formatNode(
                af.FormatStyle.heading,
                af.LevelAttribute(level: 1),
              ),
              tooltip: 'Heading 1',
            ),
            // H2
            IconButton(
              icon: const Text('H2', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _appFlowyEditorState!.formatNode(
                af.FormatStyle.heading,
                af.LevelAttribute(level: 2),
              ),
              tooltip: 'Heading 2',
            ),
            // H3
            IconButton(
              icon: const Text('H3', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () => _appFlowyEditorState!.formatNode(
                af.FormatStyle.heading,
                af.LevelAttribute(level: 3),
              ),
              tooltip: 'Heading 3',
            ),
            const VerticalDivider(),
            // Bullet list
            IconButton(
              icon: const Icon(Icons.format_list_bulleted),
              onPressed: () => _appFlowyEditorState!.formatNode(
                af.FormatStyle.bulletedList,
                null,
              ),
              tooltip: 'Bullet List',
            ),
            // Numbered list
            IconButton(
              icon: const Icon(Icons.format_list_numbered),
              onPressed: () => _appFlowyEditorState!.formatNode(
                af.FormatStyle.numberedList,
                null,
              ),
              tooltip: 'Numbered List',
            ),
            // Todo list
            IconButton(
              icon: const Icon(Icons.check_box_outlined),
              onPressed: () => _appFlowyEditorState!.formatNode(
                af.FormatStyle.todoList,
                null,
              ),
              tooltip: 'Todo List',
            ),
            const VerticalDivider(),
            // Quote
            IconButton(
              icon: const Icon(Icons.format_quote),
              onPressed: () => _appFlowyEditorState!.formatNode(
                af.FormatStyle.quote,
                null,
              ),
              tooltip: 'Quote',
            ),
            // Code
            IconButton(
              icon: const Icon(Icons.code),
              onPressed: () => _appFlowyEditorState!.toggleAttribute(af.AppFlowyRichTextKeys.code),
              tooltip: 'Code',
            ),
            const VerticalDivider(),
            // Undo
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: () => _appFlowyEditorState!.undo(),
              tooltip: 'Undo',
            ),
            // Redo
            IconButton(
              icon: const Icon(Icons.redo),
              onPressed: () => _appFlowyEditorState!.redo(),
              tooltip: 'Redo',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Note getNote() {
    String body;
    if (widget.editMode && _appFlowyEditorState != null) {
      // Get content from AppFlowy Editor
      body = _documentToMarkdown(_appFlowyEditorState!.document);
    } else {
      body = _textController.text.trim();
    }
    
    return _note.copyWith(
      body: body,
      title: _titleTextController.text.trim(),
      type: NoteType.Unknown,
    );
  }

  void _noteTextChanged() {
    try {
      _applyHeuristics();
    } catch (e, stackTrace) {
      Log.e("EditorHeuristics: $e");
      logExceptionWarning(e, stackTrace);
    }
    if (_noteModified && !widget.editMode) return;

    var newState = !(widget.editMode && _textController.text.trim().isEmpty);
    if (newState != _noteModified) {
      setState(() {
        _noteModified = newState;
      });
    }

    notifyListeners();
  }

  void _noteTitleTextChanged() {
    if (_noteModified && !widget.editMode) return;

    var newState =
        !(widget.editMode && _titleTextController.text.trim().isEmpty);
    if (newState != _noteModified) {
      setState(() {
        _noteModified = newState;
      });
    }

    notifyListeners();
  }

  void _applyHeuristics() {
    var editState = TextEditorState.fromValue(_textController.value);
    var es = _heuristics.textChanged(editState);
    if (es != null) {
      _textController.value = es.toValue();
    }

    var redraw = _undoRedoStack.textChanged(editState);
    if (redraw) {
      setState(() {});
    }
  }

  @override
  Future<void> addImage(String filePath) async {
    try {
      var image = await core.Image.copyIntoFs(_note.parent, filePath);
      
      if (widget.editMode && _appFlowyEditorState != null) {
        // Insert image into AppFlowy Editor
        final transaction = _appFlowyEditorState!.transaction;
        transaction.insertNode(
          _appFlowyEditorState!.selection?.end.path ?? [0],
          af.imageNode(url: image.filePath),
        );
        await _appFlowyEditorState!.apply(transaction);
        setState(() {
          _noteModified = true;
        });
      } else {
        var ts = insertImage(
          TextEditorState.fromValue(_textController.value),
          image,
          _note.fileFormat,
        );
        setState(() {
          _textController.value = ts.toValue();
          _noteModified = true;
        });
      }
    } catch (ex) {
      showErrorSnackbar(context, ex);
    }
  }

  @override
  bool get noteModified => _noteModified;

  Future<void> _undo() async {
    if (widget.editMode && _appFlowyEditorState != null) {
      _appFlowyEditorState!.undo();
    } else {
      var es = _undoRedoStack.undo();
      setState(() {
        _textController.value = es.toValue();
      });
    }
  }

  Future<void> _redo() async {
    if (widget.editMode && _appFlowyEditorState != null) {
      _appFlowyEditorState!.redo();
    } else {
      var es = _undoRedoStack.redo();
      setState(() {
        _textController.value = es.toValue();
      });
    }
  }

  @override
  gj.SearchInfo search(String? text) {
    setState(() {
      _textController = buildController(
        text: _textController.text,
        highlightText: text,
        theme: widget.theme,
      );
      _titleTextController = buildController(
        text: _titleTextController.text,
        highlightText: text,
        theme: widget.theme,
      );
    });

    return gj.SearchInfo.compute(body: _textController.text, text: text);
  }

  @override
  void scrollToResult(String text, int num) {
    setState(() {
      _textController = buildController(
        text: _textController.text,
        highlightText: text,
        theme: widget.theme,
        currentPos: num,
      );
    });

    scrollToSearchResult(
      scrollController: _scrollController,
      textController: _textController,
      textEditorKey: _bodyEditorKey,
      textStyle: NoteBodyEditor.textStyle(context),
      searchText: text,
      resultNum: num,
    );
  }
}
