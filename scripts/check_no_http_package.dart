// scripts/check_no_http_package.dart
//
// Tech-debt audit 2026-05-20 / finding D8 — source-grep gate.
//
// Pins the rule that `package:http` is NOT imported anywhere under `lib/`.
// `package:dio` is the canonical HTTP client for the app (SoT registry
// concept: `dependency_canonical_http_client`).
//
// Pre-fix state (2026-05-21):
//   - lib/core/services/ai_service.dart used `http.Client` + `http.Response`
//     + `http.ClientException` + a typed `_retryHttpColdStart`.
//   - lib/core/services/barcode_service.dart used `http.get` for Open Food
//     Facts lookups.
//
// Both migrated to `package:dio` in the same commit that lands this gate
// (per CLAUDE.md §4.11 — gates that enforce a post-state ship in the same
// commit as the refactor). After landing, the `http:` dependency is
// removed from `pubspec.yaml` and `http` remains available transitively
// for `test/edge_functions/*.dart` only (test files are out of scope —
// they invoke Edge Functions via raw HTTP for end-to-end contract tests).
//
// Detection: scan `lib/**/*.dart` for any line that imports `package:http`
// (with or without `show` / `as` clauses). Strip line comments first so
// CHANGELOG-style annotations referring to the old import don't trip
// the gate.
//
// Usage: dart run scripts/check_no_http_package.dart
//
// Exit codes:
//   0  — pass: no lib/ file imports `package:http`.
//   1  — fail: at least one lib/ file imports `package:http`.

import 'dart:io';

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('[no-http-package] FAIL: lib/ does not exist');
    exit(warnOnly ? 0 : 1);
  }

  // Pattern: `import 'package:http/...'` or `import "package:http/..."`
  // with optional whitespace, `as`/`show` clauses, etc.
  final importPattern = RegExp(
    r'''^\s*import\s+['"]package:http/[^'"]+['"]''',
  );

  final offenders = <String>[];

  for (final entity in libDir.listSync(recursive: true)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.dart')) continue;

    final relPath = entity.path.replaceAll('\\', '/');
    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      // Strip line comments — annotations describing the old shape must
      // not trip the gate.
      final idx = raw.indexOf('//');
      final line = idx >= 0 ? raw.substring(0, idx) : raw;
      if (importPattern.hasMatch(line)) {
        offenders.add('$relPath:${i + 1}: ${raw.trimRight()}');
      }
    }
  }

  final tag = warnOnly ? '[no-http-package WARN]' : '[no-http-package]';
  if (offenders.isEmpty) {
    stdout.writeln('$tag PASS — no lib/ file imports `package:http`. '
        'Dio is the canonical HTTP client (SoT: dependency_canonical_http_client).');
    exit(0);
  }

  stderr.writeln(
      '$tag FAIL — ${offenders.length} file(s) under lib/ import '
      '`package:http`:');
  for (final v in offenders) {
    stderr.writeln('  $v');
  }
  stderr.writeln('');
  stderr.writeln('Fix: migrate to `package:dio`. Import shape:');
  stderr.writeln("  import 'package:dio/dio.dart';");
  stderr.writeln('');
  stderr.writeln('Translation cheatsheet:');
  stderr.writeln('  http.Client                → Dio');
  stderr.writeln('  http.Response              → Response<dynamic>');
  stderr.writeln('  http.ClientException       → DioException (filter by .type)');
  stderr.writeln('  client.get(uri, headers:H) → dio.getUri<dynamic>(uri, options: Options(headers: H, validateStatus: (_) => true))');
  stderr.writeln('  client.post(uri, body:B)   → dio.post<dynamic>(url, data: B, options: Options(validateStatus: (_) => true))');
  stderr.writeln('  response.body              → use _bodyAsString(r) adapter (Dio auto-decodes Map/List/String depending on Content-Type)');
  stderr.writeln('');
  stderr.writeln('SoT registry entry: dependency_canonical_http_client.');
  stderr.writeln('Tech-debt audit 2026-05-20 / D8 diagnose-doc:');
  stderr.writeln('  docs/diagnoses/2026-05-21-d8-http-package-removal-*.md');
  exit(warnOnly ? 0 : 1);
}
