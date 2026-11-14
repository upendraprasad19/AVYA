// test/contracts/spawn_sites_guard_test.dart
//
// The strict site guards G1-G5 (PR 2 of batch spawn-tests-env-and-stderr; plan
// docs/plans/spawn-tests-pr2-migrate-remaining.md section 3). They replace the
// hand-enumerated token list of gate_e2e_env_hermetic_test.dart ("presence only", exactly as
// wide as someone remembers to make it).
//
// Reads files with `Directory.listSync` and spawns NOTHING, so it stays out of its own G1.
// `_reportOnly` is the D5 switch: committed FIRST in report mode (CLAUDE.md 4.11(1): detection
// in place before the first refactor commit), flipped to strict by the commit that applies the
// last unit patch. In report mode the real-tree check prints every violation and fails nothing;
// the synthetic mutant tests below are strict from the start.
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/spawn_sites_scan.dart';

const bool _reportOnly = false;

const String _guardPath = 'test/contracts/spawn_sites_guard_test.dart';
const String _helperPath = 'test/helpers/spawn.dart';

/// The one other file that may MENTION the marker text (it defines the constant).
const String _markerDefinerPath = 'test/helpers/spawn_sites_scan.dart';

/// G1(a): files allowed raw `Process.run|runSync|start(`, with the exact count.
const Map<String, int> _allowRawSpawn = <String, int>{
  _helperPath: 3,
  'test/contracts/spawn_helper_test.dart': 1,
};

/// G1(c): `ProcessStartMode` only in the helper.
const Map<String, int> _allowStartMode = <String, int>{_helperPath: 2};

/// G2: whole-parent `Platform.environment` uses in spawn-using files; reason is one of the
/// CLOSED set helper | seam | scan (derived from a report-mode run over the migrated tree).
const Map<String, ({int count, String reason})> _allowWholeMap = <String, ({int count, String reason})>{
  _helperPath: (count: 1, reason: 'helper'),
  'test/scripts/contract_sweep_e2e_test.dart': (count: 1, reason: 'seam'),
  // two poisoned-parent maps ({...Platform.environment, 'ALLOW_RAW_GIT': '1'} and the FOUNDER_APPROVED_NO_VERIFY twin)
  // handed to runHook(parentEnv:) -> parentEnvironment:, never to extraEnv
  'test/contracts/git_safety_hook_integration_test.dart': (count: 2, reason: 'seam'),
};
const Set<String> _wholeMapReasons = <String>{'helper', 'seam', 'scan'};

/// G3: files allowed `extra` unmatched `startSpawn(` calls (fire-and-forget, kill tests,
/// two-branch code, a helper test driving startSpawn directly). The helper itself is exempt.
const Map<String, ({int extra, String reason})> _allowExtraStart = <String, ({int extra, String reason})>{
  'test/contracts/spawn_helper_test.dart': (
    extra: 1,
    reason: "the helper's own test drives startSpawn directly and reports through reportSpawn(... report: reports.add)"
  ),
};

/// G5: the 12 gate e2e files the retired token list used to name. Each must exist and spawn
/// through the helper, so none can silently drop its spawn or leave the guard's reach.
const List<String> _formerGateE2eFiles = <String>[
  'test/scripts/plan_review_record_gate_e2e_test.dart',
  'test/scripts/gate_input_family_e2e_test.dart',
  'test/scripts/worktree_config_integrity_e2e_test.dart',
  'test/scripts/retire_worktree_e2e_test.dart',
  'test/scripts/gate_index_e2e_test.dart',
  'test/scripts/gate_index_fresh_e2e_test.dart',
  'test/scripts/new_worktree_base_test.dart',
  'test/scripts/pre_push_analyze_always_e2e_test.dart',
  'test/scripts/pre_commit_lean_path_e2e_test.dart',
  'test/scripts/no_conflict_markers_test.dart',
  'test/scripts/contract_sweep_e2e_test.dart',
  'test/contracts/sot_registry_citations_test.dart',
];

/// Every violation of G1-G4 and the marker rule over [files] (path -> source), in path order.
List<String> spawnSiteViolations(Map<String, String> files) {
  final out = <String>[];
  final paths = files.keys.toList()..sort();
  for (final path in paths) {
    final scan = scanSpawnSource(files[path]!, isGuardFile: path == _guardPath);
    final rawAllowed = _allowRawSpawn[path] ?? 0;
    if (scan.rawSpawns != rawAllowed) {
      out.add('G1a $path: ${scan.rawSpawns} raw Process.run|runSync|start call(s), allowed $rawAllowed');
    }
    if (scan.aliasRefs != 0) out.add('G1b $path: ${scan.aliasRefs} tear-off/alias of a Process spawn member');
    final modeAllowed = _allowStartMode[path] ?? 0;
    if (scan.startModeUses != modeAllowed) {
      out.add('G1c $path: ProcessStartMode used ${scan.startModeUses}x, allowed $modeAllowed');
    }
    if (scan.usesHelper) {
      final wm = _allowWholeMap[path];
      if (scan.wholeMapReads != (wm?.count ?? 0)) {
        out.add('G2 $path: ${scan.wholeMapReads} whole-parent Platform.environment use(s), allowed ${wm?.count ?? 0}');
      }
      if (path != _helperPath) {
        final extra = _allowExtraStart[path]?.extra ?? 0;
        if (scan.unmatchedStarts != extra) {
          out.add('G3 $path: ${scan.unmatchedStarts} startSpawn call(s) with no later reportSpawn, allowed $extra');
        }
      }
      if (scan.resolvedExecutable != 0) {
        out.add('G4b $path: Platform.resolvedExecutable in a spawn-using file (resolves to flutter_tester)');
      }
    }
    if (path != _helperPath && scan.whichDart != 0) {
      out.add('G4a $path: ${scan.whichDart} local dart locator(s) (use dartBin())');
    }
    if (path != _guardPath && path != _markerDefinerPath && scan.markerLines != 0) {
      out.add('MARKER $path: the quote marker is honoured only in the guard file');
    }
  }
  for (final e in _allowRawSpawn.keys) {
    if (!files.containsKey(e) && files.length > 5) out.add('STALE G1a allow-list entry $e names no file');
  }
  for (final e in _allowWholeMap.entries) {
    if (!_wholeMapReasons.contains(e.value.reason)) out.add('G2 allow-list reason "${e.value.reason}" for ${e.key} is not helper|seam|scan');
  }
  return out;
}

List<String> formerGateFileViolations(Map<String, String?> sources) {
  final out = <String>[];
  for (final p in _formerGateE2eFiles) {
    final src = sources[p];
    if (src == null) {
      out.add('G5 $p does not exist');
    } else if (!scanSpawnSource(src).usesHelper) {
      out.add('G5 $p does not spawn through the helper');
    }
  }
  return out;
}

Map<String, String> _realTestTree() {
  final out = <String, String>{};
  for (final f in Directory('test').listSync(recursive: true).whereType<File>()) {
    if (f.path.endsWith('.dart')) out[f.path.replaceAll(r'\', '/')] = f.readAsStringSync();
  }
  return out;
}

void main() {
  group('real tree', () {
    test('G1-G4 and the marker rule over every test/**/*.dart (${_reportOnly ? 'REPORT MODE: prints, fails nothing' : 'strict'})', () {
      final v = spawnSiteViolations(_realTestTree());
      if (_reportOnly) {
        // ignore: avoid_print
        print('spawn_sites_guard report: ${v.length} violation(s)\n${v.join('\n')}');
      } else {
        expect(v, isEmpty, reason: v.join('\n'));
      }
    });

    test('G5 the twelve former gate e2e files exist and spawn through the helper', () {
      final sources = {for (final p in _formerGateE2eFiles) p: File(p).existsSync() ? File(p).readAsStringSync() : null};
      final v = formerGateFileViolations(sources);
      if (_reportOnly) {
        // ignore: avoid_print
        print('spawn_sites_guard G5 report: ${v.length} violation(s)\n${v.join('\n')}');
      } else {
        expect(v, isEmpty, reason: v.join('\n'));
      }
    });

    test('the quote marker appears on exactly the expected number of lines of this file', () {
      final n = File(_guardPath).readAsLinesSync().where((l) => l.contains(spawnGuardQuoteMarker)).length;
      expect(n, _expectedMarkerLines);
    });
  });

  group('synthetic mutants (strict)', () {
    const clean = "import '../helpers/spawn.dart';\nvoid main() { runSpawn('git', ['status'], why: 'x'); }\n";
    Map<String, String> one(String src, [String path = 'test/x_test.dart']) => {path: src};

    test('a clean spawn-using file has no violation', () {
      expect(spawnSiteViolations(one(clean)), isEmpty);
    });

    test('G1a: a raw Process.runSync is flagged; in a comment, a string or a regex literal it is NOT', () {
      expect(spawnSiteViolations(one('void main() { Process.runSync("a", []); }')).join(), contains('G1a'));
      expect(spawnSiteViolations(one('// Process.runSync(a)\nvoid main() {}')), isEmpty);
      expect(spawnSiteViolations(one("final s = 'Process.runSync(a)';")), isEmpty);
      expect(spawnSiteViolations(one(r"final r = RegExp(r'Process\.runSync\(');")), isEmpty);
    });

    test('G1a: a raw spawn inside a string interpolation is flagged (blankDart does not follow it)', () {
      final src = "final s = 'x \${Process.runSync('a', []).stdout}';"; // spawn-guard-quote
      expect(spawnSiteViolations(one('void main() {}\n$src')).join(), contains('G1a'));
    });

    test('G1a: the allow-list count is exact in both directions', () {
      expect(spawnSiteViolations({_helperPath: 'Process.runSync(a); Process.run(b); Process.start(c);'}).join(), isNot(contains('G1a')));
      expect(spawnSiteViolations({_helperPath: 'Process.runSync(a); Process.run(b);'}).join(), contains('G1a'));
      expect(spawnSiteViolations({_helperPath: 'Process.runSync(a); Process.run(b); Process.start(c); Process.run(d);'}).join(), contains('G1a'));
    });

    test('G1b: a tear-off or alias is flagged; G1c: ProcessStartMode outside the helper is flagged', () {
      expect(spawnSiteViolations(one('final run = Process.runSync;')).join(), contains('G1b'));
      expect(spawnSiteViolations(one('final m = ProcessStartMode.detached;')).join(), contains('G1c'));
    });

    test('G2: a whole-map spread in a spawn-using file is flagged, a hoisted copy too; an indexed read is not', () {
      expect(spawnSiteViolations(one("$clean final e = {...Platform.environment};")).join(), contains('G2'));
      expect(spawnSiteViolations(one("$clean final base = {...Platform.environment}; final x = runSpawn('a', [], why: 'w', extraEnv: base);")).join(), contains('G2'));
      expect(spawnSiteViolations(one("$clean final p = Platform.environment['PATH'];")), isEmpty);
      expect(spawnSiteViolations(one("$clean final s = '\$stub:\${Platform.environment['PATH']}';")), isEmpty);
      final inInterp = "$clean final s = '\${Platform.environment}';"; // spawn-guard-quote
      expect(spawnSiteViolations(one(inInterp)).join(), contains('G2'));
    });

    test('G2: a file that does not use the helper is outside G2', () {
      expect(spawnSiteViolations(one('final e = {...Platform.environment};')), isEmpty);
    });

    test('G3: a startSpawn with no later reportSpawn is flagged; one report for two starts is flagged; a report BEFORE its start is flagged', () {
      const imp = "import '../helpers/spawn.dart';\n";
      expect(spawnSiteViolations(one("${imp}Future<void> f() async { await startSpawn('a', []); }")).join(), contains('G3'));
      expect(spawnSiteViolations(one("${imp}Future<void> f() async { await startSpawn('a', []); await startSpawn('b', []); reportSpawn(0, '', '', 'w'); }")).join(), contains('G3'));
      expect(spawnSiteViolations(one("${imp}Future<void> f() async { reportSpawn(0, '', '', 'w'); await startSpawn('a', []); }")).join(), contains('G3'));
      expect(spawnSiteViolations(one("${imp}Future<void> f() async { await startSpawn('a', []); reportSpawn(0, '', '', 'w'); }")), isEmpty);
    });

    test('G4a: a hand-rolled which/where dart locator is flagged, a which git is not; G4b: resolvedExecutable in a spawn-using file', () {
      final loc = "$clean final r = ['which', 'dart'];"; // spawn-guard-quote
      expect(spawnSiteViolations(one(loc)).join(), contains('G4a'));
      final git = "$clean final r = ['which', 'git'];"; // spawn-guard-quote
      expect(spawnSiteViolations(one(git)), isEmpty);
      expect(spawnSiteViolations(one('$clean final e = Platform.resolvedExecutable;')).join(), contains('G4b'));
    });

    test('the marker: honoured only in the guard file; elsewhere it is itself a violation', () {
      final v = spawnSiteViolations(one('void main() { Process.runSync("a", []); } // spawn-guard-quote'));
      expect(v.join(), contains('MARKER'));
      expect(v.join(), contains('G1a'), reason: 'the marker must not exempt a file that is not the guard');
    });

    test('G5: a missing or rewritten former file is flagged', () {
      final ok = {for (final p in _formerGateE2eFiles) p: clean};
      expect(formerGateFileViolations(ok), isEmpty);
      expect(formerGateFileViolations({...ok, _formerGateE2eFiles.first: null}).join(), contains('does not exist'));
      expect(formerGateFileViolations({...ok, _formerGateE2eFiles.first: 'void main() {}'}).join(), contains('does not spawn'));
    });

    test('allow-list integrity: every G2 reason is in the closed set', () {
      for (final e in _allowWholeMap.entries) {
        expect(_wholeMapReasons, contains(e.value.reason), reason: e.key);
      }
    });
  });
}

/// Lines of this file that carry the quote marker (measured; the real-tree test pins it).
const int _expectedMarkerLines = 5;
