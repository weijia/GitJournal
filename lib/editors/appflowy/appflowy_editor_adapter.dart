// SPDX-FileCopyrightText: 2024 GitJournal Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

/// AppFlowy Editor 适配器 - 提供 WYSIWYG Markdown 编辑体验
class AppFlowyMarkdownController {
  late final EditorState _editorState;

  AppFlowyMarkdownController({String? initialContent}) {
    final document = _markdownToDocument(initialContent ?? '');
    _editorState = EditorState(document: document);
  }

  Document _markdownToDocument(String markdown) {
    if (markdown.isEmpty) {
      return Document.blank();
    }

    final nodes = <Node>[];
    final lines = markdown.split('\n');
    var i = 0;

    while (i < lines.length) {
      final line = lines[i];

      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      // 代码块
      if (line.startsWith('```')) {
        final language = line.substring(3).trim();
        final codeLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].startsWith('```')) {
          codeLines.add(lines[i]);
          i++;
        }
        nodes.add(codeBlockNode(language: language, code: codeLines.join('\n')));
        i++;
        continue;
      }

      // 标题
      final headingMatch = RegExp(r'^(#{1,6})\s+(.+)\$').firstMatch(line);
      if (headingMatch != null) {
        final level = headingMatch.group(1)!.length;
        final content = headingMatch.group(2)!;
        nodes.add(headingNode(level: level, delta: Delta()..insert(content)));
        i++;
        continue;
      }

      // 任务列表
      final taskMatch = RegExp(r'^- \[([ xX])\]\s+(.+)\$').firstMatch(line);
      if (taskMatch != null) {
        final checked = taskMatch.group(1)!.toLowerCase() == 'x';
        final content = taskMatch.group(2)!;
        nodes.add(todoListNode(checked: checked, delta: Delta()..insert(content)));
        i++;
        continue;
      }

      // 无序列表
      if (RegExp(r'^[-*+]\s').hasMatch(line)) {
        final content = line.substring(2);
        nodes.add(bulletedListNode(delta: Delta()..insert(content)));
        i++;
        continue;
      }

      // 有序列表
      if (RegExp(r'^\d+\.\s').hasMatch(line)) {
        final match = RegExp(r'^\d+\.\s(.+)\$').firstMatch(line)!;
        final content = match.group(1)!;
        nodes.add(numberedListNode(delta: Delta()..insert(content)));
        i++;
        continue;
      }

      // 引用
      if (line.startsWith('> ')) {
        final content = line.substring(2);
        nodes.add(quoteNode(delta: Delta()..insert(content)));
        i++;
        continue;
      }

      // 分隔线
      if (RegExp(r'^(---|___|\*\*\*)\$').hasMatch(line.trim())) {
        nodes.add(dividerNode);
        i++;
        continue;
      }

      // 普通段落
      nodes.add(paragraphNode(delta: Delta()..insert(line)));
      i++;
    }

    return Document(root: pageNode(children: nodes));
  }

  String _documentToMarkdown(Document document) {
    final buffer = StringBuffer();
    final root = document.root;

    for (var i = 0; i < root.children.length; i++) {
      final node = root.children[i];
      buffer.write(_nodeToMarkdown(node));
      if (i < root.children.length - 1) {
        buffer.writeln();
      }
    }

    return buffer.toString().trim();
  }

  String _nodeToMarkdown(Node node) {
    switch (node.type) {
      case 'paragraph':
        return _deltaToPlainText(node.delta ?? Delta());
      case 'heading':
        final level = node.attributes['level'] ?? 1;
        final content = _deltaToPlainText(node.delta ?? Delta());
        return '${'#' * level} \$content';
      case 'bulleted_list':
        final content = _deltaToPlainText(node.delta ?? Delta());
        return '- \$content';
      case 'numbered_list':
        final content = _deltaToPlainText(node.delta ?? Delta());
        return '1. \$content';
      case 'todo_list':
        final checked = node.attributes['checked'] == true;
        final content = _deltaToPlainText(node.delta ?? Delta());
        return '- [${checked ? 'x' : ' '}] \$content';
      case 'quote':
        final content = _deltaToPlainText(node.delta ?? Delta());
        return '> \$content';
      case 'code_block':
        final language = node.attributes['language'] ?? '';
        final code = node.attributes['code'] ?? '';
        return '```\$language\n\$code\n```';
      case 'divider':
        return '---';
      default:
        return '';
    }
  }

  String _deltaToPlainText(Delta delta) {
    final buffer = StringBuffer();
    for (final op in delta.operations) {
      if (op is TextInsert) {
        buffer.write(op.text);
      }
    }
    return buffer.toString();
  }

  String getMarkdown() => _documentToMarkdown(_editorState.document);

  void setContent(String markdown) {
    final newDocument = _markdownToDocument(markdown);
    _editorState.document = newDocument;
  }

  EditorState get editorState => _editorState;

  void dispose() {
    _editorState.dispose();
  }
}

/// AppFlowy Editor Widget
class AppFlowyEditorWidget extends StatelessWidget {
  final AppFlowyMarkdownController controller;

  const AppFlowyEditorWidget({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(context),
        Expanded(
          child: AppFlowyEditor(
            editorState: controller.editorState,
            editorStyle: EditorStyle.desktop(
              padding: const EdgeInsets.all(16.0),
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildButton('H1', () => controller.editorState.convertBlockToHeading(level: 1)),
            _buildButton('H2', () => controller.editorState.convertBlockToHeading(level: 2)),
            _buildButton('H3', () => controller.editorState.convertBlockToHeading(level: 3)),
            const VerticalDivider(),
            IconButton(
              icon: const Icon(Icons.format_bold),
              onPressed: () => controller.editorState.toggleAttribute('bold'),
            ),
            IconButton(
              icon: const Icon(Icons.format_italic),
              onPressed: () => controller.editorState.toggleAttribute('italic'),
            ),
            const VerticalDivider(),
            IconButton(
              icon: const Icon(Icons.format_list_bulleted),
              onPressed: () => controller.editorState.convertBlockToList(ListType.bulletedList),
            ),
            IconButton(
              icon: const Icon(Icons.format_list_numbered),
              onPressed: () => controller.editorState.convertBlockToList(ListType.numberedList),
            ),
            IconButton(
              icon: const Icon(Icons.check_box_outlined),
              onPressed: () => controller.editorState.convertBlockToList(ListType.checkbox),
            ),
            const VerticalDivider(),
            IconButton(
              icon: const Icon(Icons.code),
              onPressed: () => controller.editorState.convertBlockToCodeBlock(),
            ),
            IconButton(
              icon: const Icon(Icons.format_quote),
              onPressed: () => controller.editorState.convertBlockToQuote(),
            ),
            const VerticalDivider(),
            IconButton(
              icon: const Icon(Icons.undo),
              onPressed: () => controller.editorState.undo(),
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              onPressed: () => controller.editorState.redo(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(String label, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
