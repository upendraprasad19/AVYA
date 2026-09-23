// scripts/memory_write_guard_hook.dart
//
// PreToolUse(Write|Edit) WARN-ONLY hook -- discipline-v3 Phase 3, 2026-09-23.
// Adopted from ICANBEFITTER's claude-memory-write-guard.mjs.
//
// Validates memory-file writes/edits BEFORE they land, using the pure
// predicates in memory_write_guard_lib.dart, and warns via the
// hookSpecificOutput.additionalContext channel (the same channel
// discipline_hook.dart and git_safety_hook.dart use -- plain stdout on a
// PreToolUse hook is debug-log only and would be invisible).
//
// DELIBERATELY WARN-ONLY, never blocking (unlike git_safety_hook.dart, which
// DOES block): a malformed memory file is a hygiene problem, not a safety
// one, and this repo's own fail-open philosophy (§4.13.6's worktree
// retirement, discipline_hook.dart's whole contract) says a hook whose JOB is
// enforcing hygiene must never be the thing that wedges a session over it.
// The founder sees the warning and can fix it; the write is never refused.
//
// CONTRACT: this hook must NEVER break the session. On ANY error (no stdin,
// malformed JSON, unreadable target file, non-Write/Edit tool) it exits 0
// silently.
//
// Edit tool_input carries old_string/new_string, not the whole file -- to
// validate the RESULTING file (the only thing that actually matters), this
// hook reads the current on-disk content and simulates the single
// replacement Edit is about to perform, mirroring Edit's own contract
// (first occurrence only, unless replace_all).

import 'dart:convert';
import 'dart:io';

import 'memory_write_guard_lib.dart';

Future<String> _readStdin() async {
  if (stdin.hasTerminal) return '';
  return utf8.decoder.bind(stdin).join().timeout(
        const Duration(seconds: 3),
        onTimeout: () => '',
      );
}

void _warn(String context) {
  stdout.writeln(jsonEncode({
    'hookSpecificOutput': {
      'hookEventName': 'PreToolUse',
      'additionalContext': context,
    }
  }));
}

/// Reconstructs the file content Edit is ABOUT to produce, without touching
/// disk. Returns null when it cannot be determined (file unreadable,
/// old_string not found) -- callers must skip validation silently in that
/// case rather than guess.
String? _simulateEdit(String filePath, String oldString, String newString,
    bool replaceAll) {
  final file = File(filePath);
  if (!file.existsSync()) return null;
  String current;
  try {
    current = file.readAsStringSync();
  } catch (_) {
    return null;
  }
  if (!current.contains(oldString)) return null;
  return replaceAll
      ? current.replaceAll(oldString, newString)
      : current.replaceFirst(oldString, newString);
}

void main() async {
  try {
    final raw = await _readStdin();
    if (raw.trim().isEmpty) return;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['hook_event_name'] != 'PreToolUse') return;

    final toolName = (data['tool_name'] as String?) ?? '';
    if (toolName != 'Write' && toolName != 'Edit') return;

    final toolInput = data['tool_input'] as Map<String, dynamic>?;
    final filePath = (toolInput?['file_path'] as String?) ?? '';
    if (filePath.isEmpty || !isMemoryFilePath(filePath)) return;

    final String? resultingContent;
    if (toolName == 'Write') {
      resultingContent = toolInput?['content'] as String?;
    } else {
      final oldString = (toolInput?['old_string'] as String?) ?? '';
      final newString = (toolInput?['new_string'] as String?) ?? '';
      final replaceAll = (toolInput?['replace_all'] as bool?) ?? false;
      resultingContent = _simulateEdit(filePath, oldString, newString, replaceAll);
    }
    if (resultingContent == null) return;

    final issues = validateMemoryWrite(filePath, resultingContent);
    if (issues.isEmpty) return;

    final lines = issues.map((i) => '  - $i').join('\n');
    _warn(
      '⚠️ MEMORY WRITE-GUARD (advisory -- write proceeds unchanged): '
      '$filePath has ${issues.length} structural issue(s):\n$lines\n'
      'Fix in a follow-up edit if this was not intentional.',
    );
  } catch (_) {
    // Fail OPEN -- a bug in this hook must never wedge an unrelated tool call.
  }
}
