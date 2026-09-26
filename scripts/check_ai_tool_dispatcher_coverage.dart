// scripts/check_ai_tool_dispatcher_coverage.dart
//
// Gate (E.13 — Audit 2026-05-16 framework deliverable):
// Every WRITE-kind AI tool registered server-side must have a matching
// `case '<intent_type>':` entry in `tool_dispatcher.dart` client-side.
//
// Logic:
//   1. Enumerate tools from supabase/functions/_shared/tools/<family>/*.ts
//      (skip index.ts and __tests__/). For each .ts file:
//        - Extract `name: "..."` (tool name)
//        - Extract `kind: "..."` (write / read)
//        - Extract `intentBuilder: (args) => ({ type: "..." })` OR
//          `type: "..."` inside intentBuilder return block
//   2. For every WRITE tool with an intent_type, source-grep
//      lib/features/ai_coach/services/tool_dispatcher.dart for the
//      literal `case '<type>':`.
//   3. Exit 1 if any are missing.
//
// Exit 0 = pass.
// Exit 1 = fail.
//
// Usage: dart run scripts/check_ai_tool_dispatcher_coverage.dart

import 'dart:io';

void main(List<String> args) async {
  final projectRoot = Directory.current.path;
  final toolsRoot =
      Directory('$projectRoot/supabase/functions/_shared/tools');
  if (!toolsRoot.existsSync()) {
    stderr.writeln('[check_ai_tool_dispatcher_coverage] ERROR: tools dir not found');
    exit(1);
  }

  final dispatcherFile = File(
      '$projectRoot/lib/features/ai_coach/services/tool_dispatcher.dart');
  if (!dispatcherFile.existsSync()) {
    stderr.writeln('[check_ai_tool_dispatcher_coverage] ERROR: tool_dispatcher.dart not found');
    exit(1);
  }

  final dispatcherSrc = dispatcherFile.readAsStringSync();

  final tools = <_ToolInfo>[];
  for (final entry in toolsRoot.listSync(recursive: true)) {
    if (entry is! File) continue;
    if (!entry.path.endsWith('.ts')) continue;
    final rel = entry.path.replaceAll('\\', '/').replaceFirst('$projectRoot/', '');
    if (rel.endsWith('/index.ts')) continue;
    if (rel.contains('/__tests__/')) continue;
    if (rel.contains('/types.ts')) continue;
    if (rel.contains('/registry.ts')) continue;

    final content = entry.readAsStringSync();

    final nameMatch = RegExp(r'name:\s*"([^"]+)"').firstMatch(content);
    final kindMatch = RegExp(r'kind:\s*"([^"]+)"').firstMatch(content);
    if (nameMatch == null || kindMatch == null) continue;

    final name = nameMatch.group(1)!;
    final kind = kindMatch.group(1)!;

    // intent type — look inside `intentBuilder` for `type: "<...>"`.
    // The pattern is repeated across the codebase as:
    //   intentBuilder: (args) => ({
    //     type: "swap_exercise",
    final intentMatch = RegExp(
      r'intentBuilder[\s\S]*?type:\s*"([^"]+)"',
    ).firstMatch(content);

    tools.add(_ToolInfo(
      file: rel,
      name: name,
      kind: kind,
      intentType: intentMatch?.group(1),
    ));
  }

  final missing = <String>[];
  final unused = <String>[];

  for (final t in tools) {
    if (t.kind != 'write') continue;
    if (t.intentType == null) {
      unused.add('${t.file} — write tool `${t.name}` has no intent_type');
      continue;
    }
    // Look for case '<type>':
    final pattern = "case '${t.intentType}':";
    if (!dispatcherSrc.contains(pattern)) {
      missing.add('${t.file} — write tool `${t.name}` intent=`${t.intentType}` '
          'has no `$pattern` in tool_dispatcher.dart');
    }
  }

  if (missing.isEmpty && unused.isEmpty) {
    final writeCount = tools.where((t) => t.kind == 'write').length;
    stdout.writeln(
        '[check_ai_tool_dispatcher_coverage] PASS — all $writeCount '
        'WRITE tools have a matching dispatcher case.');
    exit(0);
  } else {
    if (unused.isNotEmpty) {
      stderr.writeln('\n[check_ai_tool_dispatcher_coverage] WARN — '
          '${unused.length} write tools without intent_type:');
      for (final u in unused) {
        stderr.writeln('  $u');
      }
    }
    if (missing.isNotEmpty) {
      stderr.writeln('\n[check_ai_tool_dispatcher_coverage] FAIL — '
          '${missing.length} dispatcher cases missing:');
      for (final m in missing) {
        stderr.writeln('  $m');
      }
      stderr.writeln('\n  Fix: add `case \'<type>\':` to '
          'tool_dispatcher.dart for each missing tool.');
      exit(1);
    }
    exit(0);
  }
}

class _ToolInfo {
  final String file;
  final String name;
  final String kind;
  final String? intentType;
  const _ToolInfo({
    required this.file,
    required this.name,
    required this.kind,
    required this.intentType,
  });
}
