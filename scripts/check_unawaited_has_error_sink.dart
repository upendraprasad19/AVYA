// scripts/check_unawaited_has_error_sink.dart
//
// Gate: 20
//
// Gate 20: every `unawaited(...)` call in lib/ must be near (within
// the enclosing method body) at least one error sink — either:
//   - the awaited Future has `.catchError(...)` chained, OR
//   - the awaited call is inside a method that uses `ErrorTelemetry.recordNonFatal`
//     or `unawaited(ErrorTelemetry.recordNonFatal(...))`, OR
//   - the unawaited expression is itself an `ErrorTelemetry...` call.
//
// Closes OI-42 lens L28/L34 (telemetry coverage on async failure legs).
// Designed to catch the Test #16.1 D class (silent drop on telemetry
// sink itself) + Test #12.6 class (30+ silent restore failures).
//
// Heuristic — false-positive resilient via the method-body scope check.
// Limited to lib/ core paths to keep noise low.
//
// Exit 0 — gate is currently ADVISORY (audit-only mode). Findings are
//          printed but don't fail the build. Tracked as OI-44 (next
//          batch) — cleaning up the 50+ extant unawaited callsites
//          without sinks is its own scope. Strict mode (exit 1 on any
//          finding) flips on with `--strict` flag.
// Exit 1 — at least one unawaited has no visible error handling AND
//          --strict was passed

import 'dart:io';

const _scanRoots = <String>[
  'lib/core/services',
  'lib/features',
  'lib/shared',
];

void main(List<String> args) {
  final strict = args.contains('--strict');
  final findings = <String>[];
  int total = 0;
  int withSink = 0;

  for (final root in _scanRoots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();
      final path = entity.path.replaceAll('\\', '/');

      // Find each unawaited(...) call.
      final unawaitedRegex = RegExp(r'\bunawaited\s*\(');
      for (final m in unawaitedRegex.allMatches(src)) {
        total++;
        // Skip if the unawaited expression IS an error sink itself.
        final tail = src.substring(m.end,
            (m.end + 200).clamp(0, src.length));
        if (tail.contains('ErrorTelemetry')) {
          withSink++;
          continue;
        }
        if (tail.contains('.catchError(')) {
          withSink++;
          continue;
        }

        // Look back for the enclosing method body. Find the previous
        // ` {`-opening pattern from a function/method header.
        // Cheap heuristic: search the 4000-char window before this point
        // for `ErrorTelemetry.recordNonFatal` — if present, the method
        // handles errors elsewhere.
        final lookback = src.substring(
          (m.start - 4000).clamp(0, src.length),
          m.start,
        );
        if (lookback.contains('ErrorTelemetry.recordNonFatal') ||
            lookback.contains('Crashlytics.instance.recordError')) {
          withSink++;
          continue;
        }

        findings.add(
            '$path:${_lineOf(src, m.start)} — unawaited(...) without nearby error sink');
      }
    }
  }

  stdout.writeln(
      '[Gate 20] scanned $total unawaited(...) callsites; $withSink have nearby error sink');
  if (findings.isEmpty) {
    stdout.writeln('[Gate 20] PASS');
    exit(0);
  }

  // Audit-only mode by default (see file header). Use --strict in OI-44
  // follow-up to flip to fail-on-finding once the existing 50+ are
  // triaged + either fixed or allowlisted.
  if (!strict) {
    stdout.writeln(
        '[Gate 20] ADVISORY — ${findings.length} unawaited(...) without nearby error sink');
    for (final f in findings.take(20)) {
      stdout.writeln('  $f');
    }
    if (findings.length > 20) {
      stdout.writeln('  ... + ${findings.length - 20} more');
    }
    stdout.writeln(
        '[Gate 20] exit 0 (audit-only mode). Use --strict to fail on findings.');
    exit(0);
  }

  stderr.writeln('[Gate 20] STRICT — ${findings.length} unawaited without sink:');
  for (final f in findings.take(50)) {
    stderr.writeln('  $f');
  }
  if (findings.length > 50) {
    stderr.writeln('  ... + ${findings.length - 50} more');
  }
  stderr.writeln(
      '\n  Fix: add `.catchError(...)` to the awaited future, or ensure '
      'the enclosing method uses ErrorTelemetry.recordNonFatal nearby.');
  exit(1);
}

int _lineOf(String src, int idx) {
  var line = 1;
  for (var i = 0; i < idx; i++) {
    if (src[i] == '\n') line++;
  }
  return line;
}
