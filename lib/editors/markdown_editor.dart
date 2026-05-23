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
import 'package:gitjournal/editors/common.dart';
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
import 'package:appflowy_editor/appflowy_editor.dart';

import 'controllers/rich_text_controller.dart';

class MarkdownEditor extends StatefulWidget implements Editor {
  final Note note;
  final NotesFolder parentFolder;
  final bool noteModified;

  @override
  final EditorCommon common;

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
    implements EditorState {
  late Note _note;
  late TextEditingController _textController;
  late TextEditingController _titleTextController;
  late UndoRedoStack _undoRedoStack;

  late EditorHeuristics _heuristics;

  late bool _noteModified;

  late ScrollController _scrollController;

  final _bodyEditorKey = GlobalKey();

  // AppFlowy Editor
  EditorState? _appFlowyEditorState;

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
    _appFlowyEditorState = EditorState(document: document);
  }

  Document _markdownToDocument(String markdown) {
    // Simple markdown parser for AppFlowy
    final document = Document.blank();
    final lines = markdown.split('\n');
    
    for (final line in lines) {
      if (line.startsWith('# ')) {
        document.insert([
          [headingNode(level: 1, text: line.substring(2))]
        ]);
      } else if (line.startsWith('## ')) {
        document.insert([
          [headingNode(level: 2, text: line.substring(3))]
        ]);
      } else if (line.startsWith('### ')) {
        document.insert([
          [headingNode(level: 3, text: line.substring(4))]
        ]);
      } else if (line.startsWith('- [ ] ')) {
        document.insert([
          [todoListNode(text: line.substring(6), checked: false)]
        ]);
      } else if (line.startsWith('- [x] ') || line.startsWith('- [X] ')) {
        document.insert([
          [todoListNode(text: line.substring(6), checked: true)]
        ]);
      } else if (line.startsWith('- ') || line.startsWith('* ')) {
        document.insert([
          [bulletedListNode(text: line.substring(2))]
        ]);
      } else if (RegExp(r'^\d+\.\s').hasMatch(line)) {
        final text = line.replaceFirst(RegExp(r'^\d+\.\s'), '');
        document.insert([
          [numberedListNode(text: text)]
        ]);
      } else if (line.startsWith('> ')) {
        document.insert([
          [quoteNode(text: line.substring(2))]
        ]);
      } else if (line.startsWith('```')) {
        // Skip code block markers for now
        continue;
      } else if (line.trim().isEmpty) {
        document.insert([
          [paragraphNode(text: '')]
        ]);
      } else {
        document.insert([
          [paragraphNode(text: line)]
        ]);
      }
    }
    
    return document;
  }

  String _documentToMarkdown(Document document) {
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

    return EditorScaffold(
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
          child: AppFlowyEditor.standard(
            editorState: _appFlowyEditorState!,
            editorStyle: EditorStyle.desktop(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              textStyleConfiguration: TextStyleConfiguration(
                text: widget.theme.textTheme.bodyMedium ?? const TextStyle(fontSize: 16),
                code: widget.theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  backgroundColor: Colors.grey.shade200,
                ) ?? const TextStyle(fontFamily: 'monospace'),
              ),
            ),
            header: Padding(
              padding: const EdgeInsets.all(8.0),
              child: _buildAppFlowyToolbar(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAppFlowyToolbar() {
    if (_appFlowyEditorState == null) return const SizedBox.shrink();
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ToolbarWidget(
        editorState: _appFlowyEditorState!,
        toolbarItems: [
          // Text formatting
          ToolbarItem(
            id: 'bold',
            group: 0,
            isActive: (editorState) => editorState.selection != null,
            builder: (context, editorState, highlightColor, iconColor, tooltipColor, onHover) {
              return IconButton(
                icon: const Icon(Icons.format_bold),
                onPressed: () => editorState.toggleAttribute(AppFlowyRichTextKeys.bold),
                tooltip: 'Bold',
              );
            },
          ),
          ToolbarItem(
            id: 'italic',
            group: 0,
            isActive: (editorState) => editorState.selection != null,
            builder: (context, editorState, highlightColor, iconColor, tooltipColor, onHover) {
              return IconButton(
                icon: const Icon(Icons.format_italic),
                onPressed: () => editorState.toggleAttribute(AppFlowyRichTextKeys.italic),
                tooltip: 'Italic',
              );
            },
          ),
          ToolbarItem(
            id: 'underline',
            group: 0,
            isActive: (editorState) => editorState.selection != null,
            builder: (context, editorState, highlightColor, iconColor, tooltipColor, onHover) {
              return IconButton(
                icon: const Icon(Icons.format_underline),
                onPressed: () => editorState.toggleAttribute(AppFlowyRichTextKeys.underline),
                tooltip: 'Underline',
              );
            },
          ),
          // Headings
          ToolbarItem(
            id: 'h1',
            group: 1,
            isActive: (editorState) => editorState.selection != null,
            builder: (context, editorState, highlightColor, iconColor, tooltipColor, onHover) {
              return IconButton(
                icon: const Text('H1', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () => editorState.convertToHeading(1),
                tooltip: 'Heading 1',
              );
            },
          ),
          ToolbarItem(
            id: 'h2',
            group: 1,
            isActive: (editorState) => editorState.selection != null,
            builder: (context, editorState, highlightColor, iconColor, tooltipColor, onHover) {
              return IconButton(
                icon: const Text('H2', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () => editorState.convertToHeading(2),
                tooltip: 'Heading 2',
              );
            },
          ),
          ToolbarItem(
            id: 'h3',
            group: 1,
            isActive: (editorState) => editorState.selection != null,
            builder: (context, editorState, highlightColor, iconColor, tooltipColor, onHover) {
              return IconButton(
                icon: const Text('H3', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () => editorState.convertToHeading(3),
                tooltip: 'Heading 3',
              );
            },
          ),
          // Lists
          ToolbarItem(
            id: 'bullet_list',
            group: 2,
            isActive: (editorState) => editorState.selection != null,
            builder: (context, editorState, highlightColor, iconColor, tooltipColor, onHover) {
              return IconButton(
                icon: const Icon(Icons.format_list_bulleted),
                onPressed: () => editorState.convertToBulletedList(),
                tooltip: 'Bullet List',
              );
            },
          ),
          ToolbarItem(
            id: 'numbered_list',
            group: 2,
            isActive: (editorState) => editorState.selection != null,
            builder: (context, editorState, highlightColor, iconColor, tooltipColor, onHover) {
              return IconButton(
                icon: const Icon(Icons.format_list_numbered),
                onPressed: () => editorState.convertToNumberedList(),
                tooltip: 'Numbered List',
              );
            },
          ),
          ToolbarItem(
            id: 'todo_list',
            group: 2,
            isActive: (editorState) => editorState.selection != null,
            builder: (context, editorState, highlightColor, iconColor, tooltipColor, onHover) {
              return IconButton(
                icon: const Icon(Icons.check_box_outlined),
                onPressed: () => editorState.convertToTodoList(),
                tooltip: 'Todo List',
              );
            },
          ),
          // Quote and Code
          ToolbarItem(
            id: 'quote',
            group: 3,
            isActive: (editorState) => editorState.selection != null,
            builder: (context, editorState, highlightColor, iconColor, tooltipColor, onHover) {
              return IconButton(
                icon: const Icon(Icons.format_quote),
                onPressed: () => editorState.convertToQuote(),
                tooltip: 'Quote',
              );
            },
          ),
          ToolbarItem(
            id: 'code',
            group: 3,
            isActive: (editorState) => editorState.selection != null,
            builder: (context, editorState, highlightColor, iconColor, tooltipColor, onHover) {
              return IconButton(
                icon: const Icon(Icons.code),
                onPressed: () => editorState.toggleAttribute(AppFlowyRichTextKeys.code),
                tooltip: 'Code',
              );
            },
          ),
          // Undo/Redo
          ToolbarItem(
            id: 'undo',
            group: 4,
            isActive: (editorState) => editorState.canUndo(),
            builder: (context, editorState, highlightColor, iconColor, tooltipColor, onHover) {
              return IconButton(
                icon: const Icon(Icons.undo),
                onPressed: () => editorState.undo(),
                tooltip: 'Undo',
              );
            },
          ),
          ToolbarItem(
            id: 'redo',
            group: 4,
            isActive: (editorState) => editorState.canRedo(),
            builder: (context, editorState, highlightColor, iconColor, tooltipColor, onHover) {
              return IconButton(
                icon: const Icon(Icons.redo),
                onPressed: () => editorState.redo(),
                tooltip: 'Redo',
              );
            },
          ),
        ],
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
          _appFlowyEditorState!.selection!.end.path,
          imageNode(url: image.filePath),
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
  SearchInfo search(String? text) {
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

    return SearchInfo.compute(body: _textController.text, text: text);
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
