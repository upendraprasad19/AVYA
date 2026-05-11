// scripts/check_id_injection_on_get.dart
//
// Gate 16 — repository methods that return List<Map<...>> from a Hive
// `box.get(key)` must inject the key as `id` on the returned map.
//
// Codifies APK Test #15.1 / Bug F. The Test #6 WriteService rewrite
// stopped writing an `id` value field — id IS the Hive key. Reader
// methods that returned the value map directly without re-injecting
// the key silently dropped consumers' `where(log['id'] is String)`
// filters. Bug latent for 4 weeks until founder hit Edit Workout Log
// path on a WriteService-written log.
//
// Gate scope — lib/**/*_repository.dart files only. For each method
// that returns `List<Map<...>>` (or similar) AND contains a
// `box.get(<id>)` pattern, require either:
//
//   1. Within the method body, a `m['id'] = id` or `map['id'] = key`
//      assignment near the box.get site, OR
//   2. The method documentation comment carries an explicit
//      `// gate16-exempt: <reason>` annotation justifying why the key
//      is intentionally dropped (e.g. a stripped projection).
//
// Detection is heuristic — looks for `box.get(` followed by `Map<` /
// `Map.from(` patterns without an `id` assignment within ~15 lines.
//
// Like Gate 15, supports a baseline file
// `backups/id_injection_on_get_baseline.txt` for grandfathering
// pre-existing patterns. New violations hard-fail.
//
// Usage: dart run scripts/check_id_injection_on_get.dart

import 'dart:io';

Set<String> _loadBaseline() {
  final f = File('backups/id_injection_on_get_baseline.txt');
  if (!f.existsSync()) return <String>{};
  final out = <String>{};
  for (final raw in f.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    out.add(line);
  }
  return out;
}

void main() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln('[Gate 16] FAIL: lib/ does not exist');
    exit(1);
  }

  final baseline = _loadBaseline();
  final violations = <String>[];
  final grandfathered = <String>[];

  final repoFiles = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('_repository.dart'));

  for (final file in repoFiles) {
    final relPath = file.path.replaceAll('\\', '/');
    final lines = file.readAsLinesSync();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // Match a `box.get(<key-var>)` pattern (Hive read).
      final getMatch = RegExp(
              r'\b(?:\w+Box|workoutBox|userBox|coachBox|nutritionBox|customBox|healthBox|notificationsBox|configBox|syncBox)\.get\(\s*(\w+)\s*\)')
          .firstMatch(line);
      if (getMatch == null) continue;

      final keyVar = getMatch.group(1)!;
      // Look forward ~15 lines for id injection OR exemption marker.
      final windowEnd = (i + 15).clamp(0, lines.length);
      final window = lines.sublist(i, windowEnd).join('\n');

      // Exempt? Look for the explicit annotation.
      if (window.contains('// gate16-exempt:')) continue;

      // Look back 8 lines too — annotation might be on the method
      // doc above.
      final lookbackStart = (i - 8).clamp(0, lines.length);
      final lookbackWindow = lines.sublist(lookbackStart, i).join('\n');
      if (lookbackWindow.contains('// gate16-exempt:')) continue;

      // Look for `m['id'] = <keyVar>` or `map['id'] = <keyVar>` or similar.
      final injectionPattern = RegExp(
          r"(?:m|map|entry|raw|cur)\['id'\]\s*=\s*$keyVar\b"
              .replaceAll(r'$keyVar', RegExp.escape(keyVar)));
      // Also accept generic `<anyvar>['id'] = key` since some methods
      // use different local names (e.g. `final cur = ...; cur['id'] = key`).
      final genericInjection = RegExp(
          r"\['id'\]\s*=\s*(?:" + RegExp.escape(keyVar) + r"|key|id)\b");
      if (injectionPattern.hasMatch(window) ||
          genericInjection.hasMatch(window)) continue;

      // Heuristic — does the surrounding code even surface this map to a
      // consumer? Skip if next few lines obviously return/cast to a
      // simpler type (e.g. just reading a single field).
      // We require the pattern `Map<` or `.from(` within the window to
      // believe this is a map-shape return.
      final isMapShape =
          window.contains('Map<') || window.contains('Map.from(');
      if (!isMapShape) continue;

      final key = '$relPath:${i + 1}';
      final row = '$key  box.get($keyVar) returns Map without id '
          'injection within 15 lines';
      if (baseline.contains(key)) {
        grandfathered.add(row);
      } else {
        violations.add(row);
      }
    }
  }

  if (violations.isEmpty) {
    if (grandfathered.isNotEmpty) {
      stdout.writeln('[Gate 16] PASS — no NEW box.get returns missing id '
          'injection. Tracked debt: ${grandfathered.length} pre-existing '
          'patterns (see backups/id_injection_on_get_baseline.txt). '
          'Reduce over time.');
    } else {
      stdout.writeln('[Gate 16] PASS — every repository box.get(key) → '
          'Map shape injects key as id on the returned map.');
    }
    exit(0);
  }

  stderr.writeln(
      '[Gate 16] FAIL — ${violations.length} repository box.get(...) '
      'return(s) without id injection:');
  for (final v in violations) {
    stderr.writeln('  $v');
  }
  stderr.writeln('');
  stderr.writeln(
      'Fix: after `final raw = box.get(id)`, do `final m = Map<String, '
      "dynamic>.from(raw); m['id'] = id; logs.add(m);`. The Hive key is "
      'the id; downstream consumers (Edit sheets, receipts, sync) rely '
      'on it. See APK Test #15.1 / Bug F diagnose-doc + '
      'memory/feedback_id_must_be_injected_on_get.md.');
  stderr.writeln('');
  stderr.writeln(
      'If the missing id is intentional (e.g. a stripped projection), '
      'annotate the method with `// gate16-exempt: <reason>` within '
      '8 lines above the box.get call.');
  exit(1);
}
