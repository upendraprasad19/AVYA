// scripts/check_generic_error_telemetry.dart
//
// Gate 15 — every user-facing generic error message in lib/ must be
// preceded (within ~10 lines, same catch block) by an ErrorTelemetry
// or _reportSyncFailure call, so silent failures leave a breadcrumb in
// client_errors.
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

void main() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('[Gate 15] FAIL: lib/ does not exist');
    exit(1);
  }

  final baseline = _loadBaseline();
  final violations = <String>[];
  final grandfathered = <String>[];
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

  if (violations.isEmpty) {
    if (grandfathered.isNotEmpty) {
      stdout.writeln('[Gate 15] PASS — no NEW generic-error catch blocks '
          'without telemetry. Tracked debt: ${grandfathered.length} '
          'pre-existing violations (see backups/generic_error_telemetry_'
          'baseline.txt). Reduce over time.');
    } else {
      stdout.writeln('[Gate 15] PASS — every generic-error catch block has '
          'telemetry within 30 lines.');
    }
    exit(0);
  }

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
  exit(1);
}
