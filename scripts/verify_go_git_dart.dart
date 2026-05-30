#!/usr/bin/env dart
// SPDX-FileCopyrightText: 2024 GitJournal Contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// This script verifies that go_git_dart dependency is correctly configured
// to use the forked version with malformed mode fixes.

import 'dart:io';
import 'package:yaml/yaml.dart';

void main() {
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    stderr.writeln('ERROR: pubspec.yaml not found');
    exit(1);
  }

  final content = pubspecFile.readAsStringSync();
  final yaml = loadYaml(content);
  
  final dependencies = yaml['dependencies'] as Map?;
  if (dependencies == null) {
    stderr.writeln('ERROR: No dependencies section found');
    exit(1);
  }

  final goGitDart = dependencies['go_git_dart'];
  if (goGitDart == null) {
    stderr.writeln('ERROR: go_git_dart dependency not found');
    exit(1);
  }

  // Check if it's using the git dependency
  if (goGitDart is! Map) {
    stderr.writeln('ERROR: go_git_dart should be a git dependency');
    exit(1);
  }

  final git = goGitDart['git'];
  if (git == null) {
    stderr.writeln('ERROR: go_git_dart should be a git dependency');
    exit(1);
  }

  String url;
  if (git is String) {
    url = git;
  } else if (git is Map) {
    url = git['url']?.toString() ?? '';
  } else {
    stderr.writeln('ERROR: Invalid go_git_dart git configuration');
    exit(1);
  }

  // Verify it's using the forked version
  if (!url.contains('weijia/go_git_dart')) {
    stderr.writeln('WARNING: go_git_dart is not using the forked version with malformed mode fix');
    stderr.writeln('Current URL: $url');
    stderr.writeln('Expected: https://github.com/weijia/go_git_dart.git');
    stderr.writeln('');
    stderr.writeln('Please update pubspec.yaml to use the forked version:');
    stderr.writeln('  go_git_dart:');
    stderr.writeln('    git:');
    stderr.writeln('      url: https://github.com/weijia/go_git_dart.git');
    stderr.writeln('      ref: main');
    exit(1);
  }

  print('✓ go_git_dart is correctly configured to use forked version');
  print('  URL: $url');
  exit(0);
}
