// scripts/check_generic_error_telemetry.dart
//
// Gate: 15
//
// Gate 15 — every user-facing generic error message in lib/ must be
// preceded (within ~10 lines, same catch block) by an ErrorTelemetry
// or _reportSyncFailure call, so silent failures leave a breadcrumb in
// client_errors.
//
// Audit 2026-05-16 / E.14.D extension — additionally bans NEW generic
// numbered op_types (`reason: 'sync_service_catch_5'`, `'_for_25'`,
// etc.) from `ErrorTelemetry.recordNonFatal` / `logEvent` calls. The
// audit P2-G class: numbered catch-block labels defeat triage because
// the line number drifts and the label tells you nothing about what
// the failure actually was.
//
// Pattern rules (case-sensitive):
//   - `reason:`/`opType:` value matching `_catch_\d+$` (e.g. `sync_service_catch_5`)
//   - `reason:`/`opType:` value matching `_for$`        (literal `sync_service_for`)
//   - `reason:`/`opType:` value matching `_for_\d+$`    (e.g. `sync_service_for_25`)
//   - `reason:`/`opType:` value matching `_if_\d+$`     (extension — same shape)
//   - `reason:`/`opType:` value matching `_if$`         (extension — same shape)
//
// Pre-existing violations are tracked in
// `backups/generic_op_type_baseline.txt` (same shape as the generic-
// phrase baseline above) and grandfathered through. The gate fails on
// any NEW occurrence.
//
// Codifies APK Test #15.1 / Bug D — ai-media-proxy photo upload silently
// fell through to "Sorry, I couldn't analyse that photo." with ZERO
// telemetry, leaving us blind to the actual reject reason. The audit-
// batch H-42 telemetry retrofit covered many failure paths but missed
// this generic else-branch. This gate prevents recurrence.
//
// Phrases the gate flags as "generic" (need telemetry above):
//   - "Sorry,"            (canonical apology copy)
//   - "Something went wrong"
//   - "temporarily unavailable"
//   - "couldn't analyse"
//   - "couldn't load"
//   - "Could not"          (case-sensitive)
//   - "Failed to"          (Title case start, suggests generic copy)
//
// For each match in lib/**/*.dart, look back up to 30 lines for any of:
//   - ErrorTelemetry.logEvent(
//   - ErrorTelemetry.recordNonFatal(
//   - _reportSyncFailure(
//   - log-client-error      (HTTP path, less common but valid)
// AND the surrounding context must be a catch block (look back for
// `catch (` within those 30 lines).
//
// If a match has none of those telemetry calls within the catch, fail
// the gate. Exit 1.
//
// Exclusions:
//   - tests/, integration_test/, supabase/functions/ — gate is for lib/ only
//   - inline strings inside comments
//   - strings used as identifiers (param names, not user-facing copy)
//
// Usage: dart run scripts/check_generic_error_telemetry.dart

import 'dart:io';

const _genericPhrases = [
  "'Sorry,",
  '"Sorry,',
  "'Something went wrong",
  '"Something went wrong',
  "'temporarily unavailable",
  '"temporarily unavailable',
  "couldn't analyse",
  "couldn't load",
  "'Could not ",
  '"Could not ',
  "'Failed to ",
  '"Failed to ',
];

const _telemetryMarkers = [
  'ErrorTelemetry.logEvent(',
  'ErrorTelemetry.recordNonFatal(',
  '_reportSyncFailure(',
  'log-client-error',
];

// Files that legitimately carry the phrases as data (test fixtures,
// schema docs) without needing telemetry around them.
const _allowedPaths = <String>{
  // Comments-only references in legitimate copy — empty for now; add as
  // the gate uncovers exceptions.
};

// Generic numbered op_type detector — E.14.D.
//
// Matches `reason: '...'` or `opType: '...'` where the quoted value
// ends in one of the banned suffix patterns. Captures the full op_type
// so it can be reported.
final RegExp _genericOpTypeRegex = RegExp(
  r'''(?:reason|opType):\s*['"]([A-Za-z_][A-Za-z0-9_]*?'''
  r'''(?:_catch_\d+|_for|_for_\d+|_if|_if_\d+))['"]''',
);

/// Returns the offending op_type string when the line carries a banned
/// generic-numbered op_type. Null otherwise.
String? _scanLineForGenericOpType(String line) {
  // Skip comment lines — pattern docs in module comments are fine.
  final trimmed = line.trim();
  if (trimmed.startsWith('//') || trimmed.startsWith('*')) return null;
  final m = _genericOpTypeRegex.firstMatch(line);
  return m?.group(1);
}

// Baseline of known pre-existing violations (technical debt). Each
// entry is `<relative-path>:<phrase>` (line number omitted — line
// numbers drift; phrase + path is enough to identify). Gate 15 ignores
// these and only fails on NEW violations. Reduce the baseline over
// time as the underlying catch blocks get retrofitted with telemetry.
//
// Source of truth: backups/generic_error_telemetry_baseline.txt
Set<String> _loadBaseline() {
  final f = File('backups/generic_error_telemetry_baseline.txt');
  if (!f.existsSync()) return <String>{};
  final out = <String>{};
  for (final raw in f.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    // Format `path:line:phrase` — drop the line number, keep `path::phrase`.
    final parts = line.split(':');
    if (parts.length < 3) continue;
    final path = parts[0];
    final phrase = parts.sublist(2).join(':').trim();
    out.add('$path::$phrase');
  }
  return out;
}

/// Pre-existing op_type baseline (E.14.D). Each entry is
/// `<relative-path>::<op_type>` — line number stripped. Gate ignores
/// matches in this set so the existing ~45 generic numbered op_types
/// in lib/core/services/sync/ don't break the build. New code must use
/// semantic op_type names.
///
/// Source of truth: backups/generic_op_type_baseline.txt
Set<String> _loadOpTypeBaseline() {
  final f = File('backups/generic_op_type_baseline.txt');
  if (!f.existsSync()) return <String>{};
  final out = <String>{};
  for (final raw in f.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    // Format `path::op_type` (line-number-free) for stability across edits.
    out.add(line);
  }
  return out;
}

void main() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('[Gate 15] FAIL: lib/ does not exist');
    exit(1);
  }

  final baseline = _loadBaseline();
  final opTypeBaseline = _loadOpTypeBaseline();
  final violations = <String>[];
  final grandfathered = <String>[];
  final opTypeViolations = <String>[];
  final opTypeGrandfathered = <String>[];
  final files = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    final relPath = file.path.replaceAll('\\', '/');
    if (_allowedPaths.contains(relPath)) continue;

    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // E.14.D — generic op_type scan (independent of generic-phrase
      // scan below; this scan does NOT require a catch-block context
      // because the offending shape is the literal op_type itself).
      final genericOp = _scanLineForGenericOpType(line);
      if (genericOp != null) {
        final key = '$relPath::$genericOp';
        final row = '$relPath:${i + 1}  op_type "$genericOp" '
            '(matches E.14.D ban: _catch_N / _for / _for_N / _if / _if_N)';
        if (opTypeBaseline.contains(key)) {
          opTypeGrandfathered.add(row);
        } else {
          opTypeViolations.add(row);
        }
      }
      // Skip comment lines.
      final trimmed = line.trim();
      if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;

      // Look for any generic phrase.
      final matchedPhrase =
          _genericPhrases.firstWhere(line.contains, orElse: () => '');
      if (matchedPhrase.isEmpty) continue;

      // Search back up to 30 lines for a catch block + telemetry.
      final lookbackStart = (i - 30).clamp(0, lines.length);
      final lookbackWindow = lines.sublist(lookbackStart, i + 1);
      final windowText = lookbackWindow.join('\n');

      // Is this inside a catch block?
      final inCatch = windowText.contains('catch (') ||
          windowText.contains('on FunctionException catch') ||
          windowText.contains('on PostgrestException catch');
      if (!inCatch) {
        // Not in a catch block — might be info copy / placeholder / dialog
        // text. Allow.
        continue;
      }

      // Look for telemetry in the same catch block.
      final hasTelemetry = _telemetryMarkers.any(windowText.contains);
      if (!hasTelemetry) {
        // Normalize phrase for baseline matching (strip leading quote, trim).
        final phraseClean =
            matchedPhrase.replaceAll("'", '').replaceAll('"', '').trim();
        // Baseline keys are `<path>::<phrase>`. The baseline phrase
        // column may be a truncated prefix (e.g. "Failed to" instead of
        // "Failed to load profile"); accept any baseline phrase that's
        // a prefix of the current match.
        final isGrandfathered = baseline.any((bKey) {
          if (!bKey.startsWith('$relPath::')) return false;
          final bPhrase = bKey.substring('$relPath::'.length);
          return phraseClean.startsWith(bPhrase) ||
              bPhrase.startsWith(phraseClean);
        });

        final row = '$relPath:${i + 1}  '
            'phrase "$phraseClean" '
            'in catch block without ErrorTelemetry call within 30 lines';

        if (isGrandfathered) {
          grandfathered.add(row);
        } else {
          violations.add(row);
        }
      }
    }
  }

  final hasGenericPhraseFails = violations.isNotEmpty;
  final hasGenericOpTypeFails = opTypeViolations.isNotEmpty;
  if (!hasGenericPhraseFails && !hasGenericOpTypeFails) {
    final notes = <String>[];
    if (grandfathered.isNotEmpty) {
      notes.add('${grandfathered.length} grandfathered generic-phrase entries');
    }
    if (opTypeGrandfathered.isNotEmpty) {
      notes.add(
          '${opTypeGrandfathered.length} grandfathered generic op_types (E.14.D)');
    }
    if (notes.isEmpty) {
      stdout.writeln('[Gate 15] PASS — no generic-error copy without telemetry '
          'and no generic numbered op_types.');
    } else {
      stdout.writeln(
          '[Gate 15] PASS — no NEW violations. Tracked debt: ${notes.join(", ")}.');
    }
    exit(0);
  }

  if (hasGenericPhraseFails) {
    stderr.writeln(
        '[Gate 15] FAIL — ${violations.length} generic-error catch block(s) '
        'without telemetry:');
    for (final v in violations) {
      stderr.writeln('  $v');
    }
    stderr.writeln('');
    stderr.writeln(
        'Fix: add `unawaited(ErrorTelemetry.logEvent("<op_type>", '
        'message: errStr))` or `_reportSyncFailure(...)` inside the catch '
        'block. Generic apology copy without telemetry leaves ops blind to '
        'the actual failure mode. See APK Test #15.1 / Bug D diagnose-doc.');
  }
  if (hasGenericOpTypeFails) {
    stderr.writeln('');
    stderr.writeln(
        '[Gate 15 / E.14.D] FAIL — ${opTypeViolations.length} new generic '
        'numbered op_type(s):');
    for (final v in opTypeViolations) {
      stderr.writeln('  $v');
    }
    stderr.writeln('');
    stderr.writeln(
        'Fix: replace the numbered label with a semantic op_type that names '
        'the failure mode (e.g. "upsert_user_profile_failed", '
        '"restore_weight_logs_failed"). Numbered catch labels defeat triage '
        'because the line number drifts. Audit 2026-05-16 / E.14.D.');
  }
  exit(1);
}
