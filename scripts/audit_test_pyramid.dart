// scripts/audit_test_pyramid.dart
//
// Track 6 of the 2026-05-28 six-industry-gap closure batch.
// Classifies every test file by layer (unit / widget / contract / integration / e2e),
// optionally joins with a `flutter test --reporter=json` run to compute per-layer
// runtime stats, and writes a markdown report.
//
// Usage:
//   # static classification only:
//   dart run scripts/audit_test_pyramid.dart
//
//   # with runtime data (run flutter test first, redirect JSON):
//   flutter test --reporter=json > test_run.json
//   dart run scripts/audit_test_pyramid.dart --runtime test_run.json
//
//   # write report to custom path:
//   dart run scripts/audit_test_pyramid.dart --runtime test_run.json --out docs/audit/2026-05-28-test-pyramid.md
//
// Classification heuristics (per file):
//   - E2E:        path starts with integration_test/
//   - Contract:   path starts with test/contracts/
//   - Integration: imports package:hive*, OR uses HiveUserSession, OR fakeAsync over async sequences, OR setUpAll opens boxes
//   - Widget:     imports package:flutter_test, calls pumpWidget, no Hive boxes / no Supabase client
//   - Unit:       everything else (pure Dart logic; no Flutter test harness)
//
// Heuristics are conservative. A test that imports BOTH widget + Hive is classified Integration.
//
// The report includes a 5-random-samples-per-category section so a human can spot-check.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

enum Layer { unit, widget, contract, integration, e2e }

class TestFile {
  final String path;
  final Layer layer;
  final List<String> signals;
  TestFile(this.path, this.layer, this.signals);
}

class RuntimeStat {
  final String testName;
  final int durationMs;
  RuntimeStat(this.testName, this.durationMs);
}

Layer classify(String path, String content) {
  // Path-based first (cheapest).
  final norm = path.replaceAll('\\', '/');
  if (norm.startsWith('integration_test/')) return Layer.e2e;
  if (norm.startsWith('test/contracts/')) return Layer.contract;

  // Signal-based.
  final imports = <String>{};
  final lines = content.split('\n');
  for (final line in lines) {
    final t = line.trim();
    if (t.startsWith('import ')) {
      final m = RegExp(r'''import\s+['"]([^'"]+)['"]''').firstMatch(t);
      if (m != null) imports.add(m.group(1)!);
    }
  }

  final importsHive = imports.any((i) => i.startsWith('package:hive'));
  final importsSupabase = imports.any((i) => i.startsWith('package:supabase'));
  final importsFlutterTest = imports.any((i) => i == 'package:flutter_test/flutter_test.dart');
  final usesHiveUserSession = content.contains('HiveUserSession');
  final usesFakeAsync = content.contains('fakeAsync(') || content.contains('FakeAsync(');
  final opensBoxesInSetup = RegExp(
    r'setUpAll\s*\([^)]*\)\s*\{[^}]*(Hive\.openBox|registerAdapter)',
    multiLine: true,
    dotAll: true,
  ).hasMatch(content);
  final callsPumpWidget = content.contains('pumpWidget(');

  // Integration: Hive + (UserSession or fakeAsync or setUpAll-boxes).
  if (importsHive || usesHiveUserSession || opensBoxesInSetup || importsSupabase) {
    return Layer.integration;
  }
  if (usesFakeAsync) {
    return Layer.integration;
  }

  // Widget: flutter_test + pumpWidget, but no Hive/Supabase.
  if (importsFlutterTest && callsPumpWidget) {
    return Layer.widget;
  }

  // Unit: pure Dart, no Flutter test harness (or has it but no widget tree).
  return Layer.unit;
}

List<String> signalsFor(String content) {
  final s = <String>[];
  if (content.contains("'package:hive")) s.add('imports hive');
  if (content.contains("'package:supabase")) s.add('imports supabase');
  if (content.contains('HiveUserSession')) s.add('HiveUserSession');
  if (content.contains('fakeAsync(') || content.contains('FakeAsync(')) s.add('fakeAsync');
  if (content.contains('pumpWidget(')) s.add('pumpWidget');
  if (RegExp(r'setUpAll\s*\(', multiLine: true).hasMatch(content)) s.add('setUpAll');
  if (content.contains('registerAdapter')) s.add('registerAdapter');
  return s;
}

List<TestFile> walk() {
  final files = <TestFile>[];
  final roots = ['test', 'integration_test'];
  for (final root in roots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('_test.dart')) continue;
      final pathNorm = entity.path.replaceAll('\\', '/');
      final relMatch = RegExp(r'(test|integration_test)/').firstMatch(pathNorm);
      final relPath = relMatch == null
          ? pathNorm
          : pathNorm.substring(relMatch.start);
      String content = '';
      try {
        content = entity.readAsStringSync();
      } catch (_) {
        // Skip unreadable.
        continue;
      }
      final layer = classify(relPath, content);
      files.add(TestFile(relPath, layer, signalsFor(content)));
    }
  }
  return files;
}

Map<Layer, List<RuntimeStat>> parseRuntime(String? runtimePath) {
  final empty = <Layer, List<RuntimeStat>>{
    for (final l in Layer.values) l: [],
  };
  if (runtimePath == null) return empty;
  final file = File(runtimePath);
  if (!file.existsSync()) {
    stderr.writeln('Runtime file not found: $runtimePath; skipping runtime stats.');
    return empty;
  }
  final result = <Layer, List<RuntimeStat>>{
    for (final l in Layer.values) l: [],
  };
  // `flutter test --reporter=json` emits one JSON per line.
  final lines = file.readAsLinesSync();
  // Build path → layer map from the same walk.
  final pathLayer = <String, Layer>{};
  for (final tf in walk()) {
    pathLayer[tf.path] = tf.layer;
  }
  // Track start times for tests (the JSON reporter emits testStart + testDone events).
  final starts = <int, int>{}; // testID → start_ms
  final ids = <int, String>{}; // testID → URL/name
  for (final line in lines) {
    if (line.isEmpty || !line.startsWith('{')) continue;
    try {
      final obj = jsonDecode(line) as Map<String, dynamic>;
      final type = obj['type'] as String?;
      if (type == 'testStart') {
        final t = obj['test'] as Map<String, dynamic>;
        final id = t['id'] as int;
        final ms = obj['time'] as int? ?? 0;
        starts[id] = ms;
        ids[id] = (t['url'] as String?) ?? (t['name'] as String? ?? 'unknown');
      } else if (type == 'testDone') {
        final id = obj['testID'] as int;
        final ms = obj['time'] as int? ?? 0;
        final startMs = starts[id] ?? ms;
        final dur = ms - startMs;
        final url = ids[id] ?? 'unknown';
        // Translate URL → relPath if it's a file:// path.
        String rel = url;
        if (url.startsWith('file:///')) {
          rel = url.replaceFirst(RegExp(r'^file:///'), '');
          // Strip cwd prefix.
          final cwd = Directory.current.path.replaceAll('\\', '/');
          if (rel.toLowerCase().startsWith(cwd.toLowerCase() + '/')) {
            rel = rel.substring(cwd.length + 1);
          } else if (rel.toLowerCase().startsWith(cwd.toLowerCase().replaceAll('c:', 'C%3A') + '/')) {
            rel = rel.substring(cwd.length + 1);
          }
          // URL-decode %20 etc.
          rel = Uri.decodeFull(rel);
        }
        final layer = pathLayer[rel];
        if (layer != null) {
          result[layer]!.add(RuntimeStat(rel, dur));
        }
      }
    } catch (_) {
      // Skip malformed.
    }
  }
  return result;
}

({double median, double p95}) percentiles(List<int> values) {
  if (values.isEmpty) return (median: 0, p95: 0);
  final sorted = [...values]..sort();
  final medianIdx = (sorted.length * 0.5).floor();
  final p95Idx = (sorted.length * 0.95).floor().clamp(0, sorted.length - 1);
  return (median: sorted[medianIdx].toDouble(), p95: sorted[p95Idx].toDouble());
}

String formatMs(num ms) {
  if (ms < 1000) return '${ms.toStringAsFixed(0)}ms';
  return '${(ms / 1000).toStringAsFixed(2)}s';
}

void main(List<String> args) {
  String? runtimePath;
  String outPath = 'docs/audit/2026-05-28-test-pyramid.md';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--runtime' && i + 1 < args.length) {
      runtimePath = args[++i];
    } else if (args[i] == '--out' && i + 1 < args.length) {
      outPath = args[++i];
    }
  }

  final files = walk();
  stdout.writeln('Classified ${files.length} test files.');

  // Per-layer counts.
  final byLayer = <Layer, List<TestFile>>{
    for (final l in Layer.values) l: [],
  };
  for (final tf in files) {
    byLayer[tf.layer]!.add(tf);
  }

  final runtime = parseRuntime(runtimePath);

  // 5 random samples per category (deterministic seed for reproducibility).
  final rng = Random(20260528);
  String randomSamples(Layer layer) {
    final pool = byLayer[layer]!;
    if (pool.isEmpty) return '_(no files)_';
    final picks = <String>[];
    final indices = <int>{};
    while (indices.length < 5 && indices.length < pool.length) {
      indices.add(rng.nextInt(pool.length));
    }
    for (final i in indices) {
      final tf = pool[i];
      final sig = tf.signals.isEmpty ? '_(no salient signals)_' : tf.signals.join(', ');
      picks.add('  - `${tf.path}` — signals: $sig');
    }
    return picks.join('\n');
  }

  // Build report.
  final buf = StringBuffer();
  buf.writeln('# Test-pyramid audit — 2026-05-28');
  buf.writeln();
  buf.writeln('> Track 6 of the six-industry-gap closure batch.');
  buf.writeln('> Generated by `scripts/audit_test_pyramid.dart`.');
  if (runtimePath != null) {
    buf.writeln('> Runtime data from `$runtimePath`.');
  } else {
    buf.writeln('> Static classification only (no runtime data joined; rerun with `--runtime <flutter-test-json>`).');
  }
  buf.writeln();
  buf.writeln('## Layer counts');
  buf.writeln();
  buf.writeln('| Layer | Count | % of total |');
  buf.writeln('|---|---:|---:|');
  final total = files.length;
  for (final l in Layer.values) {
    final n = byLayer[l]!.length;
    final pct = total > 0 ? (n / total * 100).toStringAsFixed(1) : '0.0';
    buf.writeln('| ${l.name} | $n | $pct% |');
  }
  buf.writeln('| **total** | **$total** | 100.0% |');
  buf.writeln();

  if (runtimePath != null) {
    buf.writeln('## Runtime stats per layer');
    buf.writeln();
    buf.writeln('| Layer | Tests measured | Total | Median | p95 |');
    buf.writeln('|---|---:|---:|---:|---:|');
    for (final l in Layer.values) {
      final stats = runtime[l]!;
      final totalMs = stats.fold<int>(0, (a, b) => a + b.durationMs);
      final durs = stats.map((s) => s.durationMs).toList();
      final p = percentiles(durs);
      buf.writeln('| ${l.name} | ${stats.length} | ${formatMs(totalMs)} | ${formatMs(p.median)} | ${formatMs(p.p95)} |');
    }
    buf.writeln();

    // Top 20 slowest individual tests across all layers.
    final all = <RuntimeStat>[];
    for (final l in Layer.values) {
      all.addAll(runtime[l]!);
    }
    all.sort((a, b) => b.durationMs.compareTo(a.durationMs));
    buf.writeln('## Top 20 slowest individual tests');
    buf.writeln();
    buf.writeln('| Rank | Duration | Path |');
    buf.writeln('|---:|---:|---|');
    for (var i = 0; i < min(20, all.length); i++) {
      buf.writeln('| ${i + 1} | ${formatMs(all[i].durationMs)} | `${all[i].testName}` |');
    }
    buf.writeln();
  }

  buf.writeln('## Verification samples (5 random per layer)');
  buf.writeln();
  buf.writeln('Spot-check by reading these files; if classification looks wrong, the heuristics in `scripts/audit_test_pyramid.dart` need tuning.');
  buf.writeln();
  for (final l in Layer.values) {
    buf.writeln('### ${l.name}');
    buf.writeln(randomSamples(l));
    buf.writeln();
  }

  buf.writeln('## Heuristics used');
  buf.writeln();
  buf.writeln('Implementation: `scripts/audit_test_pyramid.dart` (`classify` function).');
  buf.writeln();
  buf.writeln('| Layer | Signal |');
  buf.writeln('|---|---|');
  buf.writeln('| e2e | path starts with `integration_test/` |');
  buf.writeln('| contract | path starts with `test/contracts/` |');
  buf.writeln('| integration | imports `package:hive*` OR `package:supabase*`; uses `HiveUserSession`; calls `fakeAsync`; `setUpAll` opens boxes |');
  buf.writeln('| widget | imports `package:flutter_test` AND calls `pumpWidget` (and not classified as integration above) |');
  buf.writeln('| unit | everything else |');
  buf.writeln();
  buf.writeln('## Notes + recommendations');
  buf.writeln();
  buf.writeln('Phase 1 of this batch is data-first. No reorganization. Use the data above to inform:');
  buf.writeln('1. Whether to tier `scripts/pre-commit.sh` (unit+widget at pre-commit, contract+integration at pre-push, e2e in CI) — separate brainstorm.');
  buf.writeln('2. Whether to reorganize `test/` into layered subdirs.');
  buf.writeln('3. Whether to adopt per-layer runtime budgets (gate `check_test_runtime_budget.dart`).');
  buf.writeln('4. Top-20 slowest tests are the highest leverage for individual-test refactoring.');

  // Ensure output dir exists.
  final outFile = File(outPath);
  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(buf.toString());
  stdout.writeln('Wrote report to: $outPath');
}
