// scripts/check_ai_tool_dispatcher_coverage.dart
//
// Gate (E.13 — Audit 2026-05-16 framework deliverable; extended Task 27,
// day-swapper-sync-load batch, spec §5.8): every WRITE-kind AI tool
// registered server-side must have a matching `case '<intent_type>':` entry
// in `tool_dispatcher.dart` client-side, AND every tool declaring
// `requiresCapability` must have that capability string present in the
// client's `kCoachClientCapabilities` const
// (lib/features/ai_coach/services/coach_client_capabilities.dart) — an
// un-declared capability would let the server register a tool no client
// build can ever unlock.
//
// Pure logic (parseTools / checkCoverage) lives in
// ai_tool_dispatcher_coverage_lib.dart, tested directly by
// test/scripts/ai_tool_dispatcher_coverage_lib_test.dart (rule 24).
//
// Exit 0 = pass. Exit 1 = fail.
//
// Usage: dart run scripts/check_ai_tool_dispatcher_coverage.dart

import 'dart:io';

import 'ai_tool_dispatcher_coverage_lib.dart';

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

  final capsFile = File(
      '$projectRoot/lib/features/ai_coach/services/coach_client_capabilities.dart');
  final clientCapabilities = capsFile.existsSync()
      ? RegExp(r"'([a-z_]+)'")
          .allMatches(capsFile.readAsStringSync())
          .map((m) => m.group(1)!)
          .toSet()
      : <String>{};

  final filesByRelPath = <String, String>{};
  for (final entry in toolsRoot.listSync(recursive: true)) {
    if (entry is! File) continue;
    if (!entry.path.endsWith('.ts')) continue;
    final rel = entry.path.replaceAll('\\', '/').replaceFirst('$projectRoot/', '');
    if (rel.endsWith('/index.ts')) continue;
    if (rel.contains('/__tests__/')) continue;
    if (rel.contains('/types.ts')) continue;
    if (rel.contains('/registry.ts')) continue;
    filesByRelPath[rel] = entry.readAsStringSync();
  }

  final tools = parseTools(filesByRelPath);
  final result = checkCoverage(
    tools: tools,
    dispatcherSrc: dispatcherSrc,
    clientCapabilities: clientCapabilities,
  );

  if (result.unusedWriteTools.isNotEmpty) {
    stderr.writeln('\n[check_ai_tool_dispatcher_coverage] WARN — '
        '${result.unusedWriteTools.length} write tools without intent_type:');
    for (final u in result.unusedWriteTools) {
      stderr.writeln('  $u');
    }
  }

  if (!result.isViolation) {
    final writeCount = tools.where((t) => t.kind == 'write').length;
    stdout.writeln(
        '[check_ai_tool_dispatcher_coverage] PASS — all $writeCount '
        'WRITE tools have a matching dispatcher case and every '
        'requiresCapability is client-declared.');
    exit(0);
  }

  if (result.missingDispatcherCases.isNotEmpty) {
    stderr.writeln('\n[check_ai_tool_dispatcher_coverage] FAIL — '
        '${result.missingDispatcherCases.length} dispatcher cases missing:');
    for (final m in result.missingDispatcherCases) {
      stderr.writeln('  $m');
    }
    stderr.writeln('\n  Fix: add `case \'<type>\':` to '
        'tool_dispatcher.dart for each missing tool.');
  }
  if (result.uncoveredCapabilities.isNotEmpty) {
    stderr.writeln('\n[check_ai_tool_dispatcher_coverage] FAIL — '
        '${result.uncoveredCapabilities.length} capabilities not declared by the client:');
    for (final c in result.uncoveredCapabilities) {
      stderr.writeln('  $c');
    }
    stderr.writeln('\n  Fix: add the capability string to '
        'kCoachClientCapabilities (coach_client_capabilities.dart).');
  }
  exit(1);
}
