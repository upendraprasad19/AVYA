// scripts/check_gemini_retry_and_telemetry_coverage.dart
//
// A5/OI-226 (f7a2c9, 2026-09-21). See gemini_retry_coverage_lib.dart's own
// header for the full rationale (both parts, and why part (b) uses an
// explicit registry rather than a text heuristic).
//
// Part (a): every `geminiChat(` call site in supabase/functions/ passes a
// `retries:` argument. Hard-fail, zero grandfathered exemptions — A2b
// (f7a2c9) rolled `retries: 2` out to all 9 real production sites before
// this gate shipped.
//
// Part (b): every registered AI/network entry-point method in
// lib/features/ai_coach/ or lib/features/nutrition/ telemeters its own
// catch block. Hard-fail, zero grandfathered exemptions — the only 2 real
// gaps found by an exhaustive human+subagent sweep were fixed before this
// gate shipped.
//
// Usage: dart run scripts/check_gemini_retry_and_telemetry_coverage.dart

import 'dart:io';

import 'gemini_retry_coverage_lib.dart';

Map<String, String> _readTsFilesExcludingTests(String dirPath) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return {};
  final out = <String, String>{};
  for (final f in dir.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.ts')) continue;
    if (f.path.endsWith('_test.ts')) continue;
    final rel = f.path.replaceAll('\\', '/');
    out[rel] = f.readAsStringSync();
  }
  return out;
}

void main() {
  final tsFiles = _readTsFilesExcludingTests('supabase/functions');
  final retryViolations = findGeminiChatMissingRetries(tsFiles);

  // Part (b)'s scope IS the registry — read exactly those files, not a
  // recursive lib/ walk.
  final dartFiles = <String, String>{};
  for (final ep in aiNetworkEntryPoints) {
    final f = File(ep.file);
    if (f.existsSync()) dartFiles[ep.file] = f.readAsStringSync();
  }
  final telemetryViolations = findAiEntryPointsMissingTelemetry(dartFiles);

  final all = [...retryViolations, ...telemetryViolations];
  if (all.isEmpty) {
    stdout.writeln('check_gemini_retry_and_telemetry_coverage: OK '
        '(${aiNetworkEntryPoints.length} AI entry points telemetered, '
        '${tsFiles.length} Edge Function files scanned for geminiChat( '
        'retries:)');
    return;
  }
  stderr.writeln('check_gemini_retry_and_telemetry_coverage: FAILED');
  for (final v in all) {
    stderr.writeln('  - $v');
  }
  exit(1);
}
