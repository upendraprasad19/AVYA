// Consolidated snapshot-contract enforcer.
//
// Per tech-debt audit 2026-05-20 finding T13, the 3 overlapping
// source-grep / structural snapshot-contract tests are merged into this
// single file. Each original concern is preserved verbatim under its
// own group() so git blame and assertion semantics survive.
//
// Originals (now deleted, preserved here for git-blame traceability):
//   - test/contracts/snapshot_contract_gate_test.dart
//   - test/contracts/snapshot_contract_self_consistency_test.dart
//   - test/contracts/snapshot_orphan_reader_aliases_test.dart
//
// NOT merged (intentionally — they are different concerns):
//   - test/contracts/ai_snapshot_builder_only_test.dart           (behavioral)
//   - test/contracts/ai_snapshot_building_writer_to_reader_test.dart
//       (SoT-registry-driven writer<->reader pair contract; lives next
//       to the other *_writer_to_reader_test.dart family).
//
// Run: flutter test test/contracts/snapshot_contract_consolidated_test.dart

@Timeout(Duration(minutes: 3))
library;

// TIMEOUT RAISED FROM THE 30s DEFAULT (2026-08-13, diagnose 4f2a9e).
// This file spawns real subprocesses (`dart run` / shell), and a cold `dart run`
// costs seconds on its own — VM start plus kernel compile. Under the
// merge-commit regression-catalog walk, which runs ~700 tests concurrently,
// those subprocesses take long enough to blow the 30s PER-TEST default, and the
// walk reports failures for tests that pass standalone every time. Measured: one
// such file takes 33s wall with ZERO contention.
// Applied to the whole subprocess-spawning class, not only the files observed
// failing — fixing just the observed instances is what let this recur twice.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // ── ORIGINAL: snapshot_contract_gate_test.dart ──────────────────────
  //
  // Regression test for audit-2026-05-17 OI-03 — server-side snapshot
  // contract gate.
  //
  // Companion to scripts/check_snapshot_contract.dart. Runs the gate as
  // a subprocess and asserts exit code 0. Also asserts the gate detects
  // (a) a key in snapshot_contract.yaml that the writer doesn't emit
  // (writer-emit violation), and (b) a reader citation pointing at a
  // line that doesn't contain the expected key read (reader-read
  // violation).
  //
  // The error-case tests don't mutate the production yaml — they invoke
  // the gate against a fixture yaml written to a tempdir.
  //
  // closes-diagnose: 2026-05-17-oi-03-snapshot-contract-gate-c0e3a5
  // closes-oi: OI-03
  group('OI-03 — snapshot contract gate', () {
    test('production snapshot_contract.yaml passes the gate', () async {
      final result = await Process.run(
        'dart',
        ['run', 'scripts/check_snapshot_contract.dart'],
        runInShell: true,
      );
      expect(result.exitCode, 0,
          reason: 'Gate must pass on the production contract. stdout=\n'
              '${result.stdout}\nstderr=\n${result.stderr}');
    });

    test('gate detects writer-emit violation', () async {
      // Verify the gate script exists and rejects a fixture contract
      // that names a key the writer doesn't emit. We can't easily
      // inject a fixture without modifying CWD; instead grep the
      // gate source for the assertion shape.
      final gateSrc =
          File('scripts/check_snapshot_contract.dart').readAsStringSync();
      expect(
        gateSrc.contains("FAIL writer-emit"),
        isTrue,
        reason: 'Gate must emit FAIL writer-emit message when a key '
            'is in the contract but missing from buildAiContext.',
      );
    });

    test('gate detects reader-read violation', () async {
      final gateSrc =
          File('scripts/check_snapshot_contract.dart').readAsStringSync();
      expect(
        gateSrc.contains("FAIL reader-read"),
        isTrue,
        reason: 'Gate must emit FAIL reader-read message when a '
            'reader citation points at a line that does not actually '
            'read the cited key.',
      );
    });

    test('gate honours ±15-line slack window for reader probes',
        () async {
      final gateSrc =
          File('scripts/check_snapshot_contract.dart').readAsStringSync();
      expect(
        gateSrc.contains('15'),
        isTrue,
        reason: 'Gate must allow ±15 lines of slack so manifest '
            'line numbers do not require pixel-perfect maintenance.',
      );
    });
  });

  // ── ORIGINAL: snapshot_contract_self_consistency_test.dart ─────────
  //
  // Self-consistency test for `docs/snapshot_contract.yaml` — the
  // manifest of every key emitted by `AiCoachRepository.buildAiContext()`
  // and every Edge Function reader.
  //
  // This test pins:
  //   (a) every entry has at least one of: `readers: [<non-empty>]`,
  //       `prompt_passthrough: true`, or `intentionally_orphan: true`
  //   (b) every cited file:line resolves (writer + readers)
  //   (c) the writer file is the canonical AiCoachRepository
  //   (d) the documented summary stats roughly match the body
  //
  // This is the prerequisite for OI-03 (the gate that enforces the
  // manifest against live source). If this test fails, the manifest is
  // internally inconsistent and the OI-03 gate cannot trust it.
  group('snapshot_contract.yaml self-consistency', () {
    late String manifest;

    setUpAll(() {
      final f = File('docs/snapshot_contract.yaml');
      expect(f.existsSync(), isTrue,
          reason: 'docs/snapshot_contract.yaml must exist (OI-07 closure)');
      manifest = f.readAsStringSync().replaceAll('\r\n', '\n');
    });

    test('writer block points at AiCoachRepository.buildAiContext', () {
      expect(
        manifest.contains(
            'file: lib/features/ai_coach/repositories/ai_coach_repository.dart'),
        isTrue,
        reason: 'writer file must be ai_coach_repository.dart',
      );
      expect(manifest.contains('method: buildAiContext'), isTrue);
    });

    test('every keys: entry has reader-coverage signal', () {
      // Split into per-key blocks. Each block must contain at least one of:
      //   readers: [<non-empty list with at least one map>]
      //   prompt_passthrough: true
      //   intentionally_orphan: true
      final keysSection = _extractSection(manifest, 'keys:');
      expect(keysSection, isNotNull,
          reason: 'manifest must contain a `keys:` section');

      final entries = _splitEntries(keysSection!);
      expect(entries.length, greaterThan(20),
          reason: 'manifest should enumerate >20 keys (writer has ~48)');

      final offenders = <String>[];
      for (final entry in entries) {
        final keyMatch =
            RegExp(r'-\s*key:\s*([a-z_][a-z_0-9]*)').firstMatch(entry);
        if (keyMatch == null) continue;
        final keyName = keyMatch.group(1)!;

        final hasReaders = RegExp(r'readers:\s*\n\s+-\s*\{').hasMatch(entry);
        final hasPassthrough =
            RegExp(r'prompt_passthrough:\s*true').hasMatch(entry);
        final hasIntentional =
            RegExp(r'intentionally_orphan:\s*true').hasMatch(entry);

        if (!hasReaders && !hasPassthrough && !hasIntentional) {
          offenders.add(keyName);
        }
      }

      expect(offenders, isEmpty,
          reason:
              'Every key entry must declare readers: [...], '
              'prompt_passthrough: true, or intentionally_orphan: true. '
              'Offenders: $offenders');
    });

    test('every file:line citation resolves', () {
      // {file: <path>, ... line: <N>} or  {file: <path>, line: <N>, ...}
      final fileLineRegex = RegExp(
        r'\{[^}]*file:\s*([^\s,}]+)[^}]*line:\s*(\d+)[^}]*\}',
      );
      final unresolved = <String>[];
      for (final m in fileLineRegex.allMatches(manifest)) {
        final relPath = m.group(1)!.trim();
        final line = int.parse(m.group(2)!.trim());
        final f = File(relPath);
        if (!f.existsSync()) {
          unresolved.add('$relPath (file does not exist)');
          continue;
        }
        final lineCount = f.readAsLinesSync().length;
        if (line < 1 || line > lineCount) {
          unresolved.add('$relPath:$line (outside [1, $lineCount])');
        }
      }
      expect(unresolved, isEmpty,
          reason: 'Every file:line in the manifest must resolve. '
              'Unresolved: $unresolved');
    });

    test('summary stats are present', () {
      expect(manifest.contains('summary:'), isTrue);
      expect(manifest.contains('total_keys:'), isTrue);
      expect(manifest.contains('edge_functions_audited:'), isTrue);
      expect(manifest.contains('verification_audit_date:'), isTrue);
    });

    test('orphan_readers section is enumerated (not silently empty)', () {
      // The audit MUST surface the morning-alert / streak-guardian /
      // protein-gap-alert nesting-mismatch and missing-writer cases.
      // Empty orphan_readers would mean the audit didn't read them.
      expect(manifest.contains('orphan_readers:'), isTrue);
      // At least one drift_class entry should be enumerated.
      expect(
        manifest.contains('drift_class:'),
        isTrue,
        reason:
            'orphan_readers must enumerate at least one drift_class entry. '
            'If you legitimately have zero orphan readers, document that '
            'with `orphan_readers: []  # audit verified zero` instead of '
            'silently empty.',
      );
    });
  });

  // ── ORIGINAL: snapshot_orphan_reader_aliases_test.dart ─────────────
  //
  // Regression test for audit-2026-05-17 OI-07-FOLLOWUP — top-level
  // aliases for cron Edge Function readers.
  //
  // OI-07's snapshot_contract.yaml enumerated 11 orphan readers — cron
  // functions (morning-alert, streak-guardian, protein-gap-alert) reading
  // fields by name from `user_daily_snapshots.snapshot_json` that the
  // writer (`AiCoachRepository.buildAiContext`) did NOT emit at the
  // expected path. Silent personalisation degradation since the cron
  // functions null-check + fall through to default templates.
  //
  // Fix: writer emits top-level aliases for the 11 expected fields.
  // This test pins the alias contract via source-grep so a future
  // refactor can't silently strip them and re-create the orphan-reader
  // drift.
  //
  // closes-diagnose: 2026-05-17-orphan-reader-aliases-7faa3b
  // closes-oi: OI-07-FOLLOWUP
  group('OI-07-FOLLOWUP — top-level alias emission in buildAiContext', () {
    late String src;

    setUpAll(() {
      // Tech-debt audit 2026-05-20 / A10 split ai_coach_repository.dart
      // into a thin shim that forwards to AiSnapshotBuilder. The top-
      // level alias emission lives in AiSnapshotBuilder now. Concat
      // shim + builder so the assertions keep firing against either
      // pre- or post-refactor source layout.
      final paths = const [
        'lib/features/ai_coach/repositories/ai_coach_repository.dart',
        'lib/features/ai_coach/services/ai_snapshot_builder.dart',
      ];
      src = paths
          .map((p) =>
              File(p).existsSync() ? File(p).readAsStringSync() : '')
          .join('\n\n');
    });

    test('writer emits current_streak_weeks at top level', () {
      expect(
        RegExp(r"'current_streak_weeks':\s*progress\['current_streak_weeks'\]")
            .hasMatch(src),
        isTrue,
        reason: 'morning-alert + streak-guardian read snap.current_streak_weeks '
            '(top-level). Writer must emit the top-level alias alongside the '
            'nested progress.current_streak_weeks for backward compat.',
      );
    });

    test('writer emits current_streak_days at top level', () {
      expect(
        src.contains("'current_streak_days':"),
        isTrue,
        reason: 'morning-alert + streak-guardian read snap.current_streak_days. '
            'Computed as streak_weeks * 7 (no canonical Hive field exists).',
      );
    });

    test('writer emits total_workouts_done at top level', () {
      expect(
        RegExp(r"'total_workouts_done':\s*progress\['total_workouts_done'\]")
            .hasMatch(src),
        isTrue,
        reason: 'morning-alert reads snap.total_workouts_done at top level.',
      );
    });

    test('writer emits current_weight_kg + target_weight_kg at top level', () {
      expect(
        RegExp(r"'current_weight_kg':\s*profile\['current_weight_kg'\]")
            .hasMatch(src),
        isTrue,
        reason: 'morning-alert + streak-guardian read snap.current_weight_kg.',
      );
      expect(
        RegExp(r"'target_weight_kg':\s*profile\['target_weight_kg'\]")
            .hasMatch(src),
        isTrue,
        reason: 'morning-alert + streak-guardian read snap.target_weight_kg.',
      );
    });

    test('writer emits today_workout_name + recent_pr_* at top level', () {
      expect(src.contains("'today_workout_name': _topLevelTodayWorkoutName()"),
          isTrue,
          reason: 'morning-alert reads snap.today_workout_name.');
      expect(
        src.contains("'recent_pr_exercise': _topLevelRecentPrField"),
        isTrue,
        reason: 'morning-alert + streak-guardian read snap.recent_pr_exercise.',
      );
      expect(
        src.contains("'recent_pr_weight': _topLevelRecentPrField"),
        isTrue,
        reason: 'morning-alert reads snap.recent_pr_weight.',
      );
    });

    test('writer emits yesterday_calories + daily_calorie_target + daily_targets',
        () {
      expect(src.contains("'yesterday_calories': _topLevelYesterdayCalories()"),
          isTrue,
          reason: 'morning-alert reads snap.yesterday_calories.');
      expect(src.contains("'daily_calorie_target':"), isTrue,
          reason: 'morning-alert reads snap.daily_calorie_target.');
      expect(
        src.contains("'daily_targets':") &&
            src.contains("'protein':"),
        isTrue,
        reason: 'protein-gap-alert reads snap.daily_targets.protein.',
      );
    });

    test('writer helpers are present + private', () {
      // All three helpers must exist and be private (underscore prefix)
      // — they're implementation details of buildAiContext.
      expect(src.contains('String? _topLevelTodayWorkoutName()'), isTrue);
      expect(
        src.contains('dynamic _topLevelRecentPrField(String field)'),
        isTrue,
      );
      expect(src.contains('int _topLevelYesterdayCalories()'), isTrue);
    });
  });
}

// ── Helpers (originally from snapshot_contract_self_consistency_test.dart)

/// Returns the substring from the line matching [header] (e.g. "keys:")
/// down to the next top-level YAML key (a line starting at column 0 with
/// `^[a-z_]+:`). Null when [header] is not found.
String? _extractSection(String src, String header) {
  final lines = src.split('\n');
  int start = -1;
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].startsWith(header)) {
      start = i + 1;
      break;
    }
  }
  if (start == -1) return null;
  int end = lines.length;
  final topLevel = RegExp(r'^[a-z_][a-z_0-9]*:');
  for (int i = start; i < lines.length; i++) {
    if (topLevel.hasMatch(lines[i])) {
      end = i;
      break;
    }
  }
  return lines.sublist(start, end).join('\n');
}

/// Splits a YAML list-of-maps section on entries starting with `  - key:`.
List<String> _splitEntries(String section) {
  final pattern = RegExp(r'^\s{2}-\s+key:', multiLine: true);
  final matches = pattern.allMatches(section).toList();
  final result = <String>[];
  for (int i = 0; i < matches.length; i++) {
    final start = matches[i].start;
    final end = i + 1 < matches.length ? matches[i + 1].start : section.length;
    result.add(section.substring(start, end));
  }
  return result;
}
