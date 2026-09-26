// test/scripts/memory_write_guard_hook_e2e_test.dart
//
// E2E for scripts/memory_write_guard_hook.dart — runs the REAL hook binary
// against real stdin JSON and (for the Edit path) a real file on disk.
//
// The pure lib test covers the validation logic. This covers the contract
// with the harness the lib cannot see: stdin parsing, tool_name filtering,
// the Write vs Edit tool_input shapes, the Edit-simulation-via-real-file-read
// path, and the ALWAYS-exit-0 (never block) guarantee.

@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

late final String _hook;
late final String _lib;

Future<({int exitCode, String stdout})> _run(String cwd, Map<String, dynamic> input) async {
  final p = await Process.start(
    'dart',
    ['run', 'scripts/memory_write_guard_hook.dart'],
    workingDirectory: cwd,
    runInShell: true,
  );
  p.stdin.write(jsonEncode(input));
  await p.stdin.close();
  final out = await p.stdout.transform(utf8.decoder).join();
  await p.stderr.transform(utf8.decoder).join();
  final code = await p.exitCode;
  return (exitCode: code, stdout: out);
}

Directory _sandbox() {
  final dir = Directory.systemTemp.createTempSync('memguard_e2e_');
  Directory('${dir.path}/scripts').createSync(recursive: true);
  File('${dir.path}/scripts/memory_write_guard_hook.dart')
      .writeAsStringSync(File(_hook).readAsStringSync());
  File('${dir.path}/scripts/memory_write_guard_lib.dart')
      .writeAsStringSync(File(_lib).readAsStringSync());
  return dir;
}

void main() {
  setUpAll(() {
    _hook = File('scripts/memory_write_guard_hook.dart').absolute.path;
    _lib = File('scripts/memory_write_guard_lib.dart').absolute.path;
  });

  test('Write of a malformed memory topic file warns via additionalContext, exits 0', () async {
    final dir = _sandbox();
    try {
      final result = await _run(dir.path, {
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Write',
        'tool_input': {
          'file_path': 'memory/project_x.md',
          'content': 'no frontmatter at all',
        },
      });
      expect(result.exitCode, 0);
      final decoded = jsonDecode(result.stdout) as Map<String, dynamic>;
      final context =
          (decoded['hookSpecificOutput'] as Map)['additionalContext'] as String;
      expect(context, contains('MEMORY WRITE-GUARD'));
      expect(context, contains('opening'));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('Write of a well-formed memory topic file is silent, exits 0', () async {
    final dir = _sandbox();
    try {
      final result = await _run(dir.path, {
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Write',
        'tool_input': {
          'file_path': 'memory/project_x.md',
          'content': '---\nname: x\ndescription: y\ntype: project\n---\n',
        },
      });
      expect(result.exitCode, 0);
      expect(result.stdout.trim(), isEmpty);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('Write of a non-memory file is silent regardless of content', () async {
    final dir = _sandbox();
    try {
      final result = await _run(dir.path, {
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Write',
        'tool_input': {
          'file_path': 'docs/architecture/sync.md',
          'content': 'no frontmatter here either',
        },
      });
      expect(result.exitCode, 0);
      expect(result.stdout.trim(), isEmpty);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('Edit simulates the replacement against the real on-disk file and validates the result',
      () async {
    final dir = _sandbox();
    try {
      final memDir = Directory('${dir.path}/memory')..createSync();
      final target = File('${memDir.path}/project_x.md');
      target.writeAsStringSync('---\nname: x\ndescription: y\ntype: project\n---\nOLD BODY\n');

      final result = await _run(dir.path, {
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Edit',
        'tool_input': {
          'file_path': target.path,
          'old_string': '---\nname: x\ndescription: y\ntype: project\n---\nOLD BODY\n',
          'new_string': 'no frontmatter left at all',
        },
      });
      expect(result.exitCode, 0);
      final decoded = jsonDecode(result.stdout) as Map<String, dynamic>;
      final context =
          (decoded['hookSpecificOutput'] as Map)['additionalContext'] as String;
      expect(context, contains('MEMORY WRITE-GUARD'));
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('Edit whose old_string is not found in the real file is silently skipped', () async {
    final dir = _sandbox();
    try {
      final memDir = Directory('${dir.path}/memory')..createSync();
      final target = File('${memDir.path}/project_x.md');
      target.writeAsStringSync('---\nname: x\ndescription: y\ntype: project\n---\n');

      final result = await _run(dir.path, {
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Edit',
        'tool_input': {
          'file_path': target.path,
          'old_string': 'THIS STRING IS NOT IN THE FILE',
          'new_string': 'x',
        },
      });
      expect(result.exitCode, 0);
      expect(result.stdout.trim(), isEmpty);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('a non-Write/Edit tool is silently ignored', () async {
    final dir = _sandbox();
    try {
      final result = await _run(dir.path, {
        'hook_event_name': 'PreToolUse',
        'tool_name': 'Bash',
        'tool_input': {'command': 'echo hi'},
      });
      expect(result.exitCode, 0);
      expect(result.stdout.trim(), isEmpty);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('malformed stdin never crashes the hook -- exits 0 silently', () async {
    final dir = _sandbox();
    try {
      final p = await Process.start('dart', ['run', 'scripts/memory_write_guard_hook.dart'],
          workingDirectory: dir.path, runInShell: true);
      p.stdin.write('not json at all {{{');
      await p.stdin.close();
      final out = await p.stdout.transform(utf8.decoder).join();
      final code = await p.exitCode;
      expect(code, 0);
      expect(out.trim(), isEmpty);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
