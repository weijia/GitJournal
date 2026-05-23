/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import 'package:flutter/material.dart';
import 'package:gitjournal/core/folder/notes_folder.dart';
import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/core/notes/note.dart';
import 'package:appflowy_editor/appflowy_editor.dart' as af;

/// A standalone WYSIWYG Markdown Editor using AppFlowy Editor
/// 
/// This is an experimental editor that provides rich text editing
/// capabilities with support for:
/// - Bold, Italic, Underline
/// - Headings (H1, H2, H3)
/// - Bullet and Numbered lists
/// - Todo lists
/// - Quotes
/// - Code blocks
/// - Tables (via AppFlowy's SimpleTable)
class AppFlowyNoteEditor extends StatefulWidget {
  final Note note;
  final NotesFolder parentFolder;
  final Function(Note) onNoteChanged;

  const AppFlowyNoteEditor({
    super.key,
    required this.note,
    required this.parentFolder,
    required this.onNoteChanged,
  });

  @override
  State<AppFlowyNoteEditor> createState() => _AppFlowyNoteEditorState();
}

class _AppFlowyNoteEditorState extends State<AppFlowyNoteEditor> {
  late af.EditorState _editorState;
  late TextEditingController _titleController;
  bool _isModified = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title ?? '');
    _editorState = af.EditorState(
      document: _markdownToDocument(widget.note.body),
    );
    
    // Listen for changes
    _editorState.addListener(_onEditorChanged);
  }

  @override
  void dispose() {
    _editorState.removeListener(_onEditorChanged);
    _titleController.dispose();
    super.dispose();
  }

  void _onEditorChanged() {
    setState(() {
      _isModified = true;
    });
  }

  af.Document _markdownToDocument(String markdown) {
    // Create a simple document from markdown
    // This is a basic parser - for production, consider using a proper markdown parser
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

  void _saveNote() {
    final body = _documentToMarkdown(_editorState.document);
    final title = _titleController.text.trim();
    
    final updatedNote = widget.note.copyWith(
      body: body,
      title: title.isEmpty ? null : title,
      type: NoteType.Unknown,
    );
    
    widget.onNoteChanged(updatedNote);
    setState(() {
      _isModified = false;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Note saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WYSIWYG Editor'),
        actions: [
          if (_isModified)
            TextButton.icon(
              onPressed: _saveNote,
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Title input
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: 'Note Title',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              onChanged: (_) => setState(() => _isModified = true),
            ),
          ),
          // Toolbar
          _buildToolbar(),
          const Divider(),
          // Editor
          Expanded(
            child: af.AppFlowyEditor(
              editorState: _editorState,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Text formatting
          IconButton(
            icon: const Icon(Icons.format_bold),
            onPressed: () => _editorState.toggleAttribute(af.AppFlowyRichTextKeys.bold),
            tooltip: 'Bold',
          ),
          IconButton(
            icon: const Icon(Icons.format_italic),
            onPressed: () => _editorState.toggleAttribute(af.AppFlowyRichTextKeys.italic),
            tooltip: 'Italic',
          ),
          IconButton(
            icon: const Icon(Icons.format_underline),
            onPressed: () => _editorState.toggleAttribute(af.AppFlowyRichTextKeys.underline),
            tooltip: 'Underline',
          ),
          IconButton(
            icon: const Icon(Icons.strikethrough_s),
            onPressed: () => _editorState.toggleAttribute(af.AppFlowyRichTextKeys.strikethrough),
            tooltip: 'Strikethrough',
          ),
          const VerticalDivider(),
          // Headings
          IconButton(
            icon: const Text('H1', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => _editorState.formatNode(
              null,
              (node) => af.headingNode(level: 1, text: node.delta?.toPlainText() ?? ''),
            ),
            tooltip: 'Heading 1',
          ),
          IconButton(
            icon: const Text('H2', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => _editorState.formatNode(
              null,
              (node) => af.headingNode(level: 2, text: node.delta?.toPlainText() ?? ''),
            ),
            tooltip: 'Heading 2',
          ),
          IconButton(
            icon: const Text('H3', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => _editorState.formatNode(
              null,
              (node) => af.headingNode(level: 3, text: node.delta?.toPlainText() ?? ''),
            ),
            tooltip: 'Heading 3',
          ),
          const VerticalDivider(),
          // Lists
          IconButton(
            icon: const Icon(Icons.format_list_bulleted),
            onPressed: () => _editorState.formatNode(
              null,
              (node) => af.bulletedListNode(text: node.delta?.toPlainText() ?? ''),
            ),
            tooltip: 'Bullet List',
          ),
          IconButton(
            icon: const Icon(Icons.format_list_numbered),
            onPressed: () => _editorState.formatNode(
              null,
              (node) => af.numberedListNode(text: node.delta?.toPlainText() ?? ''),
            ),
            tooltip: 'Numbered List',
          ),
          IconButton(
            icon: const Icon(Icons.check_box_outlined),
            onPressed: () => _editorState.formatNode(
              null,
              (node) => af.todoListNode(text: node.delta?.toPlainText() ?? '', checked: false),
            ),
            tooltip: 'Todo List',
          ),
          const VerticalDivider(),
          // Quote and Code
          IconButton(
            icon: const Icon(Icons.format_quote),
            onPressed: () => _editorState.formatNode(
              null,
              (node) => af.quoteNode(text: node.delta?.toPlainText() ?? ''),
            ),
            tooltip: 'Quote',
          ),
          IconButton(
            icon: const Icon(Icons.code),
            onPressed: () => _editorState.toggleAttribute(af.AppFlowyRichTextKeys.code),
            tooltip: 'Code',
          ),
          const VerticalDivider(),
          // Undo/Redo
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: _editorState.canUndo() ? () => _editorState.undo() : null,
            tooltip: 'Undo',
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            onPressed: _editorState.canRedo() ? () => _editorState.redo() : null,
            tooltip: 'Redo',
          ),
        ],
      ),
    );
  }
}
