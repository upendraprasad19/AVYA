# gate-integrity Implementation Plan (v2 — hardened by plan-review round 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close OI-220 (build), OI-155, OI-195 and OI-181 in one platform-tier batch: a pre-push contract sweep, a machine-checked Gate 33 allowlist with the six dormant gates given truthful runners, Gate 42 resolving every cited path, and a pre-merge absent-record warning.

**Architecture:** Four independent units with zero file overlap, each a pure-lib/runner or a small script edit plus mutation-proven tests and (for the three fixes) a diagnose-doc. Four forks build them in isolated worktrees and commit on their own branches; the coordinator cherry-picks onto `gate-integrity`, then edits the shared files (CLAUDE.md, ledger, `blast_radius.yaml`, board closures, closure YAML, plan-review record) as the single writer.

**Tech Stack:** Dart (scripts + `test/scripts/` subprocess tests), POSIX sh (`safe_merge.sh`, `pre-push.sh`), YAML (ledger, closure, blast-radius), Markdown (CLAUDE.md, playbook, board).

**Spec:** `docs/superpowers/specs/2026-09-19-gate-integrity-design.md` (v2) — every file:line below is verified there (§1, with round-1 corrections marked ⚠); every choice is argued there (§2, D1–D17). Read the spec first.

## Global Constraints

- Blast radius `platform` for the batch (pinned files); the four touched script files are pinned platform by D16 in Task 5. ×2 context-blind plan review BEFORE execution (§4.12.1); B-pass BEFORE the merge (§4.3); closure YAML `docs/audit/gate-integrity.closure.yaml` (§4.2, ≥4 units).
- Commits ONLY via `sh scripts/safe_commit.sh "<msg>"` (one positional arg). Never `--no-verify`. Never push from a unit branch.
- Every new test file that spawns a subprocess: `@Timeout(Duration(minutes: N))` + `library;` as its first two lines; `tearDown` never throws; afterwards `grep -n "timeout:" <file>` → 0 per-test overrides.
- **Every git call inside a test fixture goes through a scrubbed env** (`GIT_*`, `GITHUB_*`, `PUSH_BEFORE` removed, `includeParentEnvironment: false`) — a leaked `GIT_DIR` redirects a fixture's `git branch -D` at the REAL repo (`feedback_mistake_git_hook_env_leak`). The hermetic gate is `test/contracts/gate_e2e_env_hermetic_test.dart` (NOT under `test/scripts/`): "register" = append the new file's path to its `_helpers` const (`:34-64`); it then asserts the file's env builder strips `GIT_`/`GITHUB_`/`PUSH_BEFORE` (`:80-88`). Register ONLY fixtures that call git (Task 1's e2e); a test that spawns `dart run` alone (Task 3's) has no scrub and must NOT be registered, or the hermetic test goes red for it.
- Spawn dart in tests via `dartBinOf()` copied from `test/scripts/cron_registry_snapshot_gate_test.dart:33-57` — NEVER `Platform.resolvedExecutable`.
- Every fix commit (`fix(...)`) carries `closes-diagnose: <6-hex id>` and a diagnose-doc that passes `dart run scripts/validate_diagnose_doc.dart <path>`. Read `scripts/validate_diagnose_doc_lib.dart` first; copy the frontmatter shape of `docs/diagnoses/2026-09-18-safe-push-test-contention-window-f7a3b1.md`.
- Mutate-and-run (rule 21): each mutation must APPLY (`grep -c` the token), leave the file COMPILING, and be semantically wrong. Commit the green work FIRST, then mutate, then `git checkout -- <file>` (memory `feedback_mistake_mutation_restore_discards_uncommitted_fixes`). A zero-red mutation means "find what absorbed it".
- Ledger red-path forms (`gate_test_ledger_lib.dart:69-73`) are literal: `expect(<x>.exitCode, 1)` (the field MUST be named `exitCode`) or `expect(violations, isNotEmpty)` (the variable MUST be one of `violations|collisions|problems|findings|failures|conflicts|disagreements|unregistered`). `namesGate` requires a listed test file to CONTAIN the gate's filename.
- Run the gate loop by attempting the commit — never a hand-picked subset (§4.12.5). Never pipe `blast_radius_from_diff.dart` / `safe_commit.sh` output through `grep -v`/`head`/`tail` (§4.9).

**Execution mode (OI-220 rider 2, decided at batch start):** subagent-driven. Tasks 1–4 → one fork each, `isolation: worktree`, branch base = `gate-integrity` HEAD, commit on the fork's branch, report branch + sha(s) + mutation evidence (per mutation: what, `grep -c` proof it applied, which tests reddened) + test totals. Task 0 and Task 5 → coordinator, inline.

---

### Task 0: Preflight (coordinator)

- [ ] **Step 1** — `git branch --show-current` → `gate-integrity`; `git log --oneline -2` → spec+plan commit(s) on top of `8ffe28fb`; `git status --short` → clean after the v2 commit.
- [ ] **Step 2** — commit spec v2 + plan v2: `sh scripts/safe_commit.sh "docs(gates): spec + plan v2 for gate-integrity -- hardened by plan-review round 1 (23 findings)"`.
- [ ] **Step 3** — ×2 review: round 1 DONE (two context-blind reviewers, 23 findings, both `not-converged`; all incorporated in v2). Dispatch round 2 on THIS version (same split: registry units 220+195 / hook units 155+181), lenses per D17. Converge (only P3/mechanical) or split (§4.12.5). Only then dispatch Tasks 1–4.

---

### Task 1: OI-220 — `contract_sweep` (pre-push targeted contract tests)

**Files:**
- Create: `scripts/contract_sweep_lib.dart`, `scripts/contract_sweep.dart`
- Modify: `scripts/pre-push.sh:112-114` (wiring), `test/scripts/pre_push_analyze_always_e2e_test.dart` (hook env gains `CONTRACT_SWEEP_SKIP=1`), `docs/playbook/common-pitfalls.md` (rider 3 section)
- Test: `test/scripts/contract_sweep_lib_test.dart` (pure), `test/scripts/contract_sweep_e2e_test.dart` (temp repo + stub flutter), `test/contracts/contract_sweep_wired_test.dart` (pins the wiring line)

**Interfaces:** `buildSelection({changedPaths, registryYaml, grepResults, exists}) → SweepSelection{tests, skipped, droppedMissing, unmappedChanged, fallbackReason}`; runner flags `--warn-only`, `--dry-run`, `--range <spec>`, `--flutter-bin <path>`; env guards `CONTRACT_SWEEP_SKIP=1`, `CONTRACT_SWEEP_NESTED=1`; stdout prefix `[contract-sweep]`.

- [ ] **Step 1: Write the failing lib tests** — `test/scripts/contract_sweep_lib_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import '../../scripts/contract_sweep_lib.dart';

// Both `file:` shapes the real registry uses (896 `- file:` items, 176 `- { file: ... }` maps, 0 bare).
const _registry = '''
concepts:

  - concept: phase_adherence_rate
    domain: workout
    behavioral_test_path: test/contracts/phase_adherence_rate_test.dart  # c4d1e2 — pins the paused arm
    writers:
      - file: lib/core/services/workout_schedule_read_service.dart
        line_range: 1-40
    readers:
      - file: lib/features/train/screens/train/screen.dart
        line_range: 10-20
    ist_sites:
      - { file: lib/core/utils/ist_date.dart, line: 12 }

  - concept: subscription_cqrs
    behavioral_test_path: test/contracts/subscription_cqrs_behavioral_test.dart
    behavioral_test_path_cqrs: test/contracts/subscription_cqrs_second_test.dart
    presence_only: true # see test/sql/x.sql
    writers:
      - file: lib/core/services/subscription_service.dart
        line_range: 1-9
''';

bool _all(String _) => true;

void main() {
  group('contentReferenceKeys', () {
    test('basename with extension; parent/basename for ubiquitous names; doc-like by extension EXCEPT the contract-doc dirs; test helpers included', () {
      final keys = contentReferenceKeys([
        'lib/core/services/sync/sync_workout.dart',
        'supabase/functions/ai-proxy/index.ts',
        'lib/main.dart',
        'test/contracts/foo_test.dart',           // arm (c) territory — excluded here
        'docs/superpowers/plans/2026-09-19-x.md', // prose .md — excluded
        'CLAUDE.md',                              // prose .md — excluded (tests mention it in comments; its gates run at commit)
        'docs/audit/open_issues.md',              // .md under docs/audit/ — a DATA contract with 10 test readers → a key
        'docs/architecture/sync.md',              // .md under docs/architecture/ — 39 test readers → a key
        'test/helpers/h.dart',                    // a test HELPER is a key
        'docs/sot_registry.yaml',                 // docs/ but data — a key
      ]);
      expect(keys, {'sync_workout.dart', 'ai-proxy/index.ts', 'lib/main.dart', 'open_issues.md', 'sync.md', 'h.dart', 'sot_registry.yaml'});
    });
  });

  group('registryTestsFor', () {
    test('selects on a writer `- file:` item, a reader item, and an inline `{ file: }` map; sibling keys; comment-stripped', () {
      expect(registryTestsFor(_registry, {'lib/core/services/subscription_service.dart'}),
          ['test/contracts/subscription_cqrs_behavioral_test.dart', 'test/contracts/subscription_cqrs_second_test.dart']);
      expect(registryTestsFor(_registry, {'lib/features/train/screens/train/screen.dart'}), ['test/contracts/phase_adherence_rate_test.dart']);
      expect(registryTestsFor(_registry, {'lib/core/utils/ist_date.dart'}), ['test/contracts/phase_adherence_rate_test.dart']);
    });
    test('positive control: an unrelated change selects nothing', () {
      expect(registryTestsFor(_registry, {'lib/unrelated.dart'}), isEmpty);
    });
  });

  group('buildSelection', () {
    test('unions the arms, dedupes, sorts, skips non-dart + golden cites, drops absent files, lists unmapped', () {
      final sel = buildSelection(
        changedPaths: [
          'lib/core/services/subscription_service.dart',
          'lib/orphan.dart',
          'test/scripts/a_test.dart',
          'docs/x.md',
          'lib/shared/widgets/ward_card.dart',
        ],
        registryYaml: _registry,
        grepResults: {
          'subscription_service.dart': ['test/contracts/subscription_cqrs_behavioral_test.dart', 'test/widgets/paywall_test.dart', 'test/sql/notes.sql'],
          'orphan.dart': <String>[],
          'ward_card.dart': ['test/goldens/wardroom/ward_card_golden_test.dart'],
        },
        exists: (p) => p != 'test/contracts/subscription_cqrs_second_test.dart',
      );
      expect(sel.fallbackReason, isNull);
      expect(sel.tests, ['test/contracts/subscription_cqrs_behavioral_test.dart', 'test/scripts/a_test.dart', 'test/widgets/paywall_test.dart']);
      expect(sel.skipped, ['test/goldens/wardroom/ward_card_golden_test.dart', 'test/sql/notes.sql']);
      expect(sel.droppedMissing, ['test/contracts/subscription_cqrs_second_test.dart']);
      expect(sel.unmappedChanged, ['lib/orphan.dart']);
    });
    test('a golden-only selection runs NOTHING (a golden-only spawn exits 79 "No tests ran")', () {
      final sel = buildSelection(changedPaths: ['lib/shared/widgets/ward_card.dart'], registryYaml: _registry,
          grepResults: {'ward_card.dart': ['test/goldens/wardroom/ward_card_golden_test.dart']}, exists: _all);
      expect(sel.tests, isEmpty);
      expect(sel.skipped, ['test/goldens/wardroom/ward_card_golden_test.dart']);
    });
    test('RED PATH: unreadable registry falls back to the whole contracts subset', () {
      final sel = buildSelection(changedPaths: ['lib/a.dart'], registryYaml: null, grepResults: {'a.dart': <String>[]}, exists: _all);
      expect(sel.fallbackReason, isNotNull);
      expect(sel.tests, ['test/contracts/']);
    });
    test('RED PATH: a failed git grep (null result) falls back — uncertainty must not look like a clean sweep', () {
      final sel = buildSelection(changedPaths: ['lib/a.dart'], registryYaml: _registry, grepResults: {'a.dart': null}, exists: _all);
      expect(sel.fallbackReason, isNotNull);
      expect(sel.tests, ['test/contracts/']);
    });
    test('RED PATH: a key that was never grepped falls back', () {
      final sel = buildSelection(changedPaths: ['lib/a.dart'], registryYaml: _registry, grepResults: {}, exists: _all);
      expect(sel.fallbackReason, isNotNull);
    });
    test('docs-only change selects nothing and reports no fallback', () {
      final sel = buildSelection(changedPaths: ['docs/x.md'], registryYaml: _registry, grepResults: {}, exists: _all);
      expect(sel.fallbackReason, isNull);
      expect(sel.tests, isEmpty);
      expect(sel.unmappedChanged, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run → compile error** (`flutter test test/scripts/contract_sweep_lib_test.dart`).

- [ ] **Step 3: Write `scripts/contract_sweep_lib.dart`** (pure; no process spawns)

```dart
// scripts/contract_sweep_lib.dart
//
// Pure selection logic for scripts/contract_sweep.dart (OI-220). Three unioned
// arms pick the contract tests a push range can have broken:
//   (a) registry  — a changed path is a `file:` of a concept in
//                   docs/sot_registry.yaml → its behavioral_test_path(s)
//   (b) content   — `git grep -l -F <key> -- test/` for each changed file's
//                   basename (parent/basename for ubiquitous names)
//   (c) changed   — test/**_test.dart files in the range themselves
// Any arm whose INPUT is unreadable makes the whole selection fall back to
// the full test/contracts/ subset: uncertainty must never look like a clean
// sweep (feedback_green_check_input_set_width #47).

const ubiquitousBasenames = <String>{'index.ts', 'index.dart', 'main.dart', 'mod.ts', 'pubspec.yaml'};

bool isDartTest(String p) => p.startsWith('test/') && p.endsWith('_test.dart');
bool isGolden(String p) => p.startsWith('test/goldens/');
/// Doc-like = prose nobody tests by name: `.md`/`.txt` EXCEPT under docs/audit/
/// and docs/architecture/, whose .md files are data contracts with test readers
/// (open_issues.md → 10 tests, sync.md → 39, OPEN_INDEX.md → 5; measured
/// 2026-09-19). docs/*.yaml are never doc-like.
const _contractDocDirs = <String>['docs/audit/', 'docs/architecture/'];
bool isDocLike(String p) =>
    (p.endsWith('.md') || p.endsWith('.txt')) && !_contractDocDirs.any(p.startsWith);

String basenameOf(String p) => p.substring(p.lastIndexOf('/') + 1);

String keyFor(String p) {
  final base = basenameOf(p);
  if (!ubiquitousBasenames.contains(base)) return base;
  final parts = p.split('/');
  return parts.length >= 2 ? '${parts[parts.length - 2]}/$base' : base;
}

/// Arm (b) keys: every changed file that is neither a dart test nor doc-like.
Set<String> contentReferenceKeys(Iterable<String> changedPaths) =>
    {for (final p in changedPaths) if (!isDartTest(p) && !isDocLike(p)) keyFor(p)};

final _conceptRe = RegExp(r'^  - concept:\s*(\S+)');
// 896 `- file: x` list items + 176 `- { file: x, line: N }` inline maps; 0 bare `file:` (2026-09-19).
final _fileRe = RegExp(r'(?:^|[\s{-])file:\s*([^\s,}]+)');
final _btpRe = RegExp(r'^\s+behavioral_test_path(?:_[a-z0-9_]+)?\s*:\s*(.*)$');

String stripTrailingComment(String v) => v.replaceFirst(RegExp(r'\s+#.*$'), '').trim();

/// Arm (a): block-walk, one block per `  - concept:` heading.
List<String> registryTestsFor(String registryYaml, Set<String> changedPaths) {
  final out = <String>[];
  var hit = false;
  var paths = <String>[];
  void flush() {
    if (hit) out.addAll(paths);
    hit = false;
    paths = <String>[];
  }
  for (final line in registryYaml.split('\n')) {
    if (_conceptRe.hasMatch(line)) {
      flush();
      continue;
    }
    final f = _fileRe.firstMatch(line);
    if (f != null && changedPaths.contains(f.group(1))) hit = true;
    final b = _btpRe.firstMatch(line);
    if (b != null) {
      final v = stripTrailingComment(b.group(1)!);
      if (v.isNotEmpty && v != '""' && v != "''") paths.add(v);
    }
  }
  flush();
  return out;
}

Set<String> changedTestFiles(Iterable<String> changedPaths) => changedPaths.where(isDartTest).toSet();

class SweepSelection {
  final List<String> tests;
  final List<String> skipped;         // non-dart cites + goldens (pre-push never runs goldens)
  final List<String> droppedMissing;  // selected but absent on disk (three-dot + a deleted test)
  final List<String> unmappedChanged; // changed files no arm could map to a test
  final String? fallbackReason;
  const SweepSelection({
    required this.tests,
    required this.skipped,
    required this.droppedMissing,
    required this.unmappedChanged,
    this.fallbackReason,
  });
  static const fallbackTarget = 'test/contracts/';
}

/// [grepResults]: key → matching test files; `null` = that grep FAILED (exit >= 2);
/// a key that is absent from the map was never grepped. Both fall back.
SweepSelection buildSelection({
  required List<String> changedPaths,
  required String? registryYaml,
  required Map<String, List<String>?> grepResults,
  required bool Function(String path) exists,
}) {
  SweepSelection fallback(String why) => SweepSelection(
      tests: const [SweepSelection.fallbackTarget], skipped: const [], droppedMissing: const [],
      unmappedChanged: const [], fallbackReason: why);
  if (registryYaml == null) return fallback('docs/sot_registry.yaml unreadable');
  final keys = contentReferenceKeys(changedPaths);
  for (final k in keys) {
    if (!grepResults.containsKey(k)) return fallback('git grep not run for key `$k`');
    if (grepResults[k] == null) return fallback('git grep failed for key `$k`');
  }
  final selected = <String>{}
    ..addAll(registryTestsFor(registryYaml, changedPaths.toSet()))
    ..addAll(changedTestFiles(changedPaths));
  final keyHit = <String, bool>{for (final k in keys) k: grepResults[k]!.isNotEmpty};
  for (final k in keys) {
    selected.addAll(grepResults[k]!);
  }
  final runnable = <String>[];
  final skipped = <String>[];
  final dropped = <String>[];
  for (final f in selected) {
    if (!isDartTest(f) || isGolden(f)) {
      skipped.add(f);
    } else if (!exists(f)) {
      dropped.add(f);
    } else {
      runnable.add(f);
    }
  }
  final unmapped = <String>[];
  for (final p in changedPaths) {
    if (isDartTest(p) || isDocLike(p)) continue;
    final registryHit = registryTestsFor(registryYaml, {p}).isNotEmpty;
    if (!registryHit && keyHit[keyFor(p)] != true) unmapped.add(p);
  }
  return SweepSelection(
    tests: runnable..sort(),
    skipped: skipped..sort(),
    droppedMissing: dropped..sort(),
    unmappedChanged: unmapped..sort(),
  );
}
```

- [ ] **Step 4: Run the lib tests → green.** Hand-trace: every expectation in Step 1 must come out verbatim (round 1 caught the v1 lib returning `[]` for the registry arm — trace, do not assume).

- [ ] **Step 5: Write the failing e2e** — `test/scripts/contract_sweep_e2e_test.dart`

```dart
@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// dartBinOf() — copy verbatim from test/scripts/cron_registry_snapshot_gate_test.dart:33-57

/// Hermetic env for EVERY subprocess in this file (fixture git calls included):
/// a leaked GIT_DIR would point a fixture's `git branch -D` at the REAL repo.
Map<String, String> _env({String record = '', String stubExit = '0', Map<String, String> extra = const {}}) {
  final env = Map<String, String>.from(Platform.environment)
    ..removeWhere((k, _) {
      final u = k.toUpperCase();
      return u.startsWith('GIT_') || u.startsWith('GITHUB_') || u == 'PUSH_BEFORE';
    });
  env['SWEEP_RECORD'] = record;
  env['SWEEP_STUB_EXIT'] = stubExit;
  env.addAll(extra);
  return env;
}

ProcessResult _git(List<String> args, String cwd) => Process.runSync('git', args, workingDirectory: cwd,
    environment: _env(), includeParentEnvironment: false, runInShell: true);

class _Repo {
  late String dir;    // the clone (HEAD has one unpushed commit = the "push range")
  late String stub;   // stub flutter path (flutter.bat on Windows)
  late String record; // where the stub writes its argv
}

// Stub: Windows → flutter.bat: "@echo off\r\necho %* > \"%SWEEP_RECORD%\"\r\nexit /b %SWEEP_STUB_EXIT%\r\n"
//       else    → flutter (chmod +x): "#!/bin/sh\necho \"$@\" > \"$SWEEP_RECORD\"\nexit \"$SWEEP_STUB_EXIT\"\n"

void main() {
  final repoRoot = Directory.current.path;
  final runner = '$repoRoot/scripts/contract_sweep.dart';
  final dartBin = dartBinOf();
  late _Repo r;

  setUp(() {
    // 1. bare origin + clone; git config user.* in the clone.
    // 2. On main, commit + push: lib/a.dart; lib/lonely.dart (NO test references it);
    //    test/contracts/a_test.dart (contains `import 'package:x/a.dart';`);
    //    test/contracts/a_registry_test.dart; docs/sot_registry.yaml with ONE concept:
    //      - concept: a_concept / behavioral_test_path: test/contracts/a_registry_test.dart
    //        writers: - file: lib/a.dart
    // 3. SECOND commit on main (NOT pushed): edit lib/a.dart AND lib/lonely.dart. This is origin/main...HEAD.
    // 4. write the stub; r.record = '<tmp>/argv.txt'.
  });
  tearDown(() { try { Directory(r.dir).deleteSync(recursive: true); } catch (_) {} });

  ProcessResult run(List<String> extra, {String stubExit = '0', Map<String, String> env = const {}}) => Process.runSync(
      dartBin, ['run', runner, '--flutter-bin', r.stub, ...extra],
      workingDirectory: r.dir, environment: _env(record: r.record, stubExit: stubExit, extra: env),
      includeParentEnvironment: false, runInShell: true);

  test('selects the registry test AND the importing test; reports lonely.dart as unmapped; spawns flutter with them', () {
    final res = run([]);
    expect(res.exitCode, 0, reason: '${res.stdout}${res.stderr}');
    final argv = File(r.record).readAsStringSync();
    expect(argv, contains('test/contracts/a_test.dart'));
    expect(argv, contains('test/contracts/a_registry_test.dart'));
    expect(argv, contains('--exclude-tags golden'));
    expect(res.stdout, contains('unmapped lib/lonely.dart'));
  });
  test('RED PATH: a failing flutter run fails the sweep', () {
    final res = run([], stubExit: '1');
    expect(res.exitCode, 1, reason: '${res.stdout}${res.stderr}');
  });
  test('--warn-only turns that failure into exit 0 and names the verdict', () {
    final res = run(['--warn-only'], stubExit: '1');
    expect(res.exitCode, 0);
    expect('${res.stdout}${res.stderr}', contains('WARN: flutter test exit 1'));
  });
  test('--dry-run prints the selection and never spawns flutter', () {
    final res = run(['--dry-run']);
    expect(res.exitCode, 0);
    expect(File(r.record).existsSync(), isFalse);
    expect(res.stdout, contains('test/contracts/a_test.dart'));
  });
  test('RED PATH: an unresolvable origin/main falls back to the whole contracts subset', () {
    _git(['branch', '-D', '-r', 'origin/main'], r.dir);
    final res = run([]);
    expect(res.exitCode, 0, reason: '${res.stdout}${res.stderr}');
    expect('${res.stdout}${res.stderr}', contains('fallback'));
    expect(File(r.record).readAsStringSync(), contains('test/contracts/'));
  });
  test('CONTRACT_SWEEP_SKIP=1 skips before any git or flutter work', () {
    final res = run([], env: {'CONTRACT_SWEEP_SKIP': '1'});
    expect(res.exitCode, 0);
    expect(res.stdout, contains('skipped'));
    expect(File(r.record).existsSync(), isFalse);
  });
  test('CONTRACT_SWEEP_NESTED=1 (set by the sweep on its own flutter spawn) skips — the recursion guard', () {
    final res = run([], env: {'CONTRACT_SWEEP_NESTED': '1'});
    expect(res.exitCode, 0);
    expect(res.stdout, contains('nested'));
    expect(File(r.record).existsSync(), isFalse);
  });
}
```

- [ ] **Step 6: Run → fails** (runner missing). Then register the file in `test/contracts/gate_e2e_env_hermetic_test.dart`'s `_helpers` const (`:34-64`) and run that test → green (it checks `_env()` strips the three families).

- [ ] **Step 7: Write `scripts/contract_sweep.dart`**

```dart
// scripts/contract_sweep.dart
//
// Pre-push targeted SoT contract sweep (OI-220). NOT a check_* gate: the
// pre-commit + CI loops enumerate check_*.dart and would spawn flutter test
// at every commit. Wired ONLY in scripts/pre-push.sh, above the full suite,
// for every tier (pinned by test/contracts/contract_sweep_wired_test.dart).
// Mutation-proven per rule 21 (plan-review record docs/plan-reviews/
// gate-integrity.md) — rule 24's ledger enumerates check_* only
// (gate_test_ledger_lib.dart:135-139) and would reject this key.
//
// Usage:
//   dart run scripts/contract_sweep.dart [--warn-only] [--dry-run]
//       [--range <spec>] [--flutter-bin <path>]
// Env guards (checked FIRST): CONTRACT_SWEEP_SKIP=1 -> exit 0 untouched;
//   CONTRACT_SWEEP_NESTED=1 -> exit 0 (set by this runner on the flutter it
//   spawns, so a test that runs the real pre-push hook cannot recurse).
// Exit: 0 when the selected tests pass (or --warn-only / --dry-run / nothing
// selected / flutter exit 79 "No tests ran"); otherwise flutter test's exit
// code. Any internal error selects the FULL test/contracts/ subset (fail-safe
// to more testing, never none).

import 'dart:io';
import 'contract_sweep_lib.dart';

const _tag = '[contract-sweep]';
const _defaultRange = 'origin/main...HEAD';

Map<String, String> _spawnEnv() => Map<String, String>.from(Platform.environment)
  ..removeWhere((k, _) => k.toUpperCase().startsWith('GIT_'))
  ..['TZ'] = 'Asia/Kolkata'
  ..['CONTRACT_SWEEP_NESTED'] = '1';

String? _arg(List<String> args, String flag) {
  final i = args.indexOf(flag);
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}

/// null => git failed (fallback). `git grep` exit 1 means NO MATCH (it is also
/// what a nonexistent pathspec dir returns — harmless here: cwd is the repo root
/// and `test/` exists); exit >= 2 or 128 is a real failure.
List<String>? _gitLines(List<String> a, {bool noMatchIsEmpty = false}) {
  final r = Process.runSync('git', a, runInShell: true);
  if (r.exitCode == 0) {
    return (r.stdout as String).split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  }
  if (noMatchIsEmpty && r.exitCode == 1) return const [];
  return null;
}

int _spawn(List<String> files, String flutterBin) {
  final r = Process.runSync(flutterBin, ['test', ...files, '--exclude-tags', 'golden'],
      environment: _spawnEnv(), includeParentEnvironment: false, runInShell: true);
  stdout.write(r.stdout);
  stderr.write(r.stderr);
  if (r.exitCode == 79) {
    stdout.writeln('$_tag flutter reported "No tests ran" (exit 79) -- treated as nothing to run.');
    return 0;
  }
  return r.exitCode;
}

void main(List<String> args) {
  final env = Platform.environment;
  if (env['CONTRACT_SWEEP_SKIP'] == '1') {
    stdout.writeln('$_tag skipped (CONTRACT_SWEEP_SKIP=1).');
    exit(0);
  }
  if (env['CONTRACT_SWEEP_NESTED'] == '1') {
    stdout.writeln('$_tag skipped -- nested inside a sweep-spawned flutter test (recursion guard).');
    exit(0);
  }
  final warnOnly = args.contains('--warn-only');
  final flutterBin = _arg(args, '--flutter-bin') ?? 'flutter';
  try {
    exit(_run(args, warnOnly: warnOnly, flutterBin: flutterBin));
  } catch (e, st) {
    stderr.writeln('$_tag internal error: $e\n$st');
    stderr.writeln('$_tag fallback: running ${SweepSelection.fallbackTarget} (fail-safe to MORE testing).');
    final code = _spawn(const [SweepSelection.fallbackTarget], flutterBin);
    exit(warnOnly ? 0 : code);
  }
}

int _run(List<String> args, {required bool warnOnly, required String flutterBin}) {
  final dryRun = args.contains('--dry-run');
  final range = _arg(args, '--range') ?? _defaultRange;

  final changed = _gitLines(['-c', 'core.quotePath=false', 'diff', '--no-renames', '--name-only', range]);
  final registryFile = File('docs/sot_registry.yaml');
  final registry = registryFile.existsSync() ? registryFile.readAsStringSync() : null;

  final SweepSelection sel;
  if (changed == null) {
    sel = buildSelection(changedPaths: const [], registryYaml: null, grepResults: const {}, exists: (_) => true);
    stdout.writeln('$_tag fallback: `git diff --name-only $range` failed (origin/main unresolvable?) -> ${SweepSelection.fallbackTarget}');
  } else {
    final keys = contentReferenceKeys(changed);
    final grep = <String, List<String>?>{
      for (final k in keys) k: _gitLines(['grep', '-l', '-F', k, '--', 'test/'], noMatchIsEmpty: true),
    };
    sel = buildSelection(changedPaths: changed, registryYaml: registry, grepResults: grep, exists: (p) => File(p).existsSync());
    if (sel.fallbackReason != null) stdout.writeln('$_tag fallback: ${sel.fallbackReason} -> ${SweepSelection.fallbackTarget}');
  }

  stdout.writeln('$_tag range=$range changed=${changed?.length ?? '?'} selected=${sel.tests.length}');
  for (final t in sel.tests) stdout.writeln('$_tag   run  $t');
  for (final s in sel.skipped) stdout.writeln('$_tag   skip $s (not a dart test, or a golden)');
  for (final d in sel.droppedMissing) stdout.writeln('$_tag   dropped $d (selected but absent on disk)');
  for (final u in sel.unmappedChanged) stdout.writeln('$_tag   unmapped $u (no registry concept and no test references its basename)');

  if (sel.tests.isEmpty) {
    stdout.writeln('$_tag nothing selected -- OK');
    return 0;
  }
  if (dryRun) {
    stdout.writeln('$_tag dry-run -- not spawning flutter');
    return 0;
  }
  final code = _spawn(sel.tests, flutterBin);
  if (code == 0) {
    stdout.writeln('$_tag OK -- ${sel.tests.length} file(s) green.');
    return 0;
  }
  stderr.writeln('$_tag ${warnOnly ? 'WARN' : 'FAIL'}: flutter test exit $code on ${sel.tests.length} selected file(s).');
  return warnOnly ? 0 : code;
}
```

- [ ] **Step 8: Run both files → green.** `flutter analyze scripts/contract_sweep.dart scripts/contract_sweep_lib.dart test/scripts/contract_sweep_lib_test.dart test/scripts/contract_sweep_e2e_test.dart` → 0 warnings (infos about `curly_braces_in_flow_control_structures` are acceptable only if `analysis_options.yaml` lists them as info; fix if warning).

- [ ] **Step 9: Wire pre-push + kill switch in the analyze e2e + the contract pin.**
  (a) Insert after `scripts/pre-push.sh:112`:

```sh

# Targeted SoT contract sweep (OI-220) -- runs for EVERY tier, above the full
# suite, so a contract regression surfaces in ~2 min instead of after a full
# run. `--warn-only || true` is the §4.11 baseline: the flip to hard-fail
# (after one clean batch) removes BOTH tokens. The Dart runner owns the
# `flutter test` spawn -- a literal `flutter test` on this line would be
# pinned to CI's invocation by test/scripts/pre_push_matches_ci_invocation_test.dart.
# Guards: CONTRACT_SWEEP_SKIP=1 / CONTRACT_SWEEP_NESTED=1 (see the runner header).
echo "[pre-push] contract sweep (targeted SoT contract tests, warn-only baseline)..."
"$DART_BIN" run scripts/contract_sweep.dart --warn-only || true
```

  (b) `test/scripts/pre_push_analyze_always_e2e_test.dart` — in the env its hook runner builds (`:57` copies `Platform.environment`; `_cleanEnv()` at `:56-65` strips only `GIT_*/GITHUB_*/PUSH_BEFORE/PRE_PUSH_FULL`, so the switch survives), add `env['CONTRACT_SWEEP_SKIP'] = '1';` with a 3-line comment: this test pins analyze placement; on Windows the sweep's Dart spawn resolves the REAL flutter (cmd.exe cannot run an extensionless PATH stub) and would select this very test → recursion. THEN add one behavioural assertion to its existing `prePushFull: true` scenario: `expect(r.stdout, contains('[contract-sweep] skipped'))` — this proves the hook REACHES the sweep line before `run_full_suite()`'s `exit 0` on a real run, which the source-order pin in (c) cannot (an `if false; then … fi` wrapper would pass (c)).
  (c) `test/contracts/contract_sweep_wired_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Pins the OI-220 wiring: no ledger entry covers scripts/contract_sweep.dart
/// (it is not a check_* gate), so without this a "tidy" could un-wire it green.
void main() {
  test('pre-push.sh invokes contract_sweep.dart on a live line below analyze and above run_full_suite', () {
    final lines = File('scripts/pre-push.sh').readAsLinesSync();
    int idx(bool Function(String) p) => lines.indexWhere((l) => !l.trim().startsWith('#') && p(l));
    final analyze = idx((l) => l.contains('flutter analyze --no-fatal-infos'));
    final sweep = idx((l) => l.contains('run scripts/contract_sweep.dart'));
    final suite = idx((l) => l.contains('run_full_suite()'));
    expect(analyze, greaterThanOrEqualTo(0));
    expect(sweep, greaterThan(analyze), reason: 'the sweep runs after the unconditional analyze');
    expect(suite, greaterThan(sweep), reason: 'the sweep runs for every tier, above the full-suite block');
    expect(lines[sweep], contains(r'"$DART_BIN" run'), reason: 'resolved via _dart_bin.sh, not bare dart');
  });
}
```

  Then run: `flutter test test/scripts/pre_push_matches_ci_invocation_test.dart test/contracts/hook_gate_placement_test.dart test/scripts/pre_push_analyze_always_e2e_test.dart test/scripts/dart_bin_resolver_test.dart test/contracts/contract_sweep_wired_test.dart` → green.

- [ ] **Step 10: Rider 3 — playbook section.** Append to `docs/playbook/common-pitfalls.md` a section `## Riverpod-3 widget-harness pitfalls (2026-09-19)` written from the CODE of `test/widgets/compass_redesign_test.dart`: GoogleFonts warmup (header `:1-20`), `tester.runAsync` for real I/O (`:647-650`), empty-box seeding (`:299-300`), and `UncontrolledProviderScope` — read its usage; describe the trap it avoids or omit it and say "not documented in source" in the commit body. Cite the line ranges you read. Match the file's section style (`:63-99` is the template).

- [ ] **Step 11: Mutate and run** (commit Steps 1–10 first; `grep -c` each token before/after):
  1. lib `buildSelection`: `if (grepResults[k] == null) return fallback(...)` → `if (grepResults[k] == null) continue;` → expected red: "failed git grep falls back" (1).
  2. lib `registryTestsFor`: `if (f != null && changedPaths.contains(f.group(1))) hit = true;` → `if (f != null && false) hit = true;` → expected red: the three-shape registry test + the union test = 2 (the positive-control test asserts `isEmpty` and CANNOT redden under this mutation — measured by round 2).
  3. lib: `if (!isDartTest(f) || isGolden(f))` → `if (!isDartTest(f))` → expected red: golden-only test + the union test's `skipped`/`tests` assertions (≥2).
  4. runner: `return warnOnly ? 0 : code;` → `return 0;` → expected red: e2e "failing flutter run fails the sweep" (1).
  5. runner: `noMatchIsEmpty: true` → `false` → `lonely.dart` has no match → grep exit 1 → null → fallback → expected red: the first e2e (argv contains `test/contracts/` instead of the two files; `unmapped` line absent) AND the `--dry-run` test (its stdout no longer lists `a_test.dart`) = 2 (measured by round 2).
  6. runner: delete the `CONTRACT_SWEEP_NESTED` guard block → expected red: the recursion-guard e2e (1).

- [ ] **Step 12: Commit**

```bash
git add scripts/contract_sweep.dart scripts/contract_sweep_lib.dart scripts/pre-push.sh test/scripts/contract_sweep_lib_test.dart test/scripts/contract_sweep_e2e_test.dart test/contracts/contract_sweep_wired_test.dart test/scripts/pre_push_analyze_always_e2e_test.dart test/contracts/gate_e2e_env_hermetic_test.dart docs/playbook/common-pitfalls.md
sh scripts/safe_commit.sh "feat(gates): contract_sweep -- pre-push targeted SoT contract tests, warn-only baseline (OI-220)

Three unioned arms (registry / content-reference / changed tests) over the
three-dot origin/main...HEAD range; any unreadable input or internal error
falls back to the whole test/contracts/ subset. Goldens and absent paths are
never spawned. Recursion guard (CONTRACT_SWEEP_NESTED) + kill switch
(CONTRACT_SWEEP_SKIP); pre_push_analyze_always_e2e sets the switch. Wired
in pre-push.sh above the full suite for every tier, pinned by
test/contracts/contract_sweep_wired_test.dart. Not a check_* gate by design.

Mutation-proven: 6 mutations, <N> tests reddened (per-mutation counts in the
plan-review record). Tests: test/scripts/contract_sweep_lib_test.dart,
test/scripts/contract_sweep_e2e_test.dart, test/contracts/contract_sweep_wired_test.dart.

Rider: docs/playbook/common-pitfalls.md riverpod-3 widget-harness section."
```

Report back: branch, sha, per-mutation reds, test totals, and whether the e2e ran inside `flutter test test/scripts/` once (contention check).

---

### Task 2: OI-155 — typed, machine-checked Gate 33 allowlist + the six dormant gates

**Files:**
- Modify: `scripts/gate_scripts_wired_lib.dart` (runner types + predicates), `scripts/check_gate_scripts_wired.dart` (`:37-82` typed allowlist; `:178-191` loop; stale-key mirror), `scripts/pre-commit.sh` (`:337` skip line deleted; `:134-136,:310-312` "14 case-skipped" prose recounted), `.github/workflows/test.yml` (two skip lines deleted: unawaited + snapshot_contract), `docs/audit/open_issues.md` (ONE appended entry via `mint_oi.sh`)
- Test: `test/scripts/gate_scripts_wired_runners_test.dart` (new, pure; header names `check_gate_scripts_wired.dart`)
- Create: `docs/diagnoses/2026-09-19-six-gates-run-nowhere-allowlist-prose-<id>.md`

**Interfaces (lib):** `enum RunnerKind { file, loop, manual }`; `class GateRunner { kind, target, reason }` with const factories `.file(path, reason)`, `.loop('preCommit'|'ci', reason)`, `.manual('OI-NNN', reason)`; `bool invokesGate(String content, String gate)`; `List<String> runnerViolations({required String gate, required List<GateRunner> runners, required String? Function(String path) read, required Set<String> Function(String content) caseSkipsOf, required Map<String, String>? boardStatuses})`; `List<String> staleAllowlistViolations(Set<String> gatesOnDisk, Iterable<String> allowlistKeys)`.

- [ ] **Step 1: §4.1.5 grep** — `grep -n "gate_scripts_wired\|allowlist\|Gate 33" docs/diagnoses/INDEX.md`; read matches; `a9f2c6` (closes-oi bare-invocation misclassification, allowlist comment `:81`) goes in `related_bugs:`.

- [ ] **Step 2: Mint the migrations_live OI** (network needed — `mint_oi.sh` does `git fetch` + `gh api` and refuses offline; any branch; it `cd`s to the toplevel itself): `sh scripts/mint_oi.sh "check_migrations_live cannot pass by construction: 125/139 local migrations never registered live (75 founder raw-SQL applies) -- retire in favour of Gate 14 or redesign the matcher"`. Then write the board entry (append, per the board's own section shape at `open_issues.md:1-40`; the stub carries Status/Blocked on/Verified so `build_oi_index.dart` does not fail closed): Status OPEN; Blocked on: FOUNDER — retire or redesign the matcher against `backups/applied_migrations.json`'s raw-SQL history. **Retire checklist, complete:** delete `scripts/check_migrations_live.dart`; its `gate_test_ledger.yaml` entry; its `_allowList` entry; its case-skip line in `pre-commit.sh` (`:333`) and `test.yml`; the assertion that the file EXISTS at `test/contracts/phase_c_oi_closures_test.dart:81-85`; and the by-hand invocation at `docs/runbooks/restore-drill.md:63`. Verified: 2026-09-19 with the exact run (exit 1, `local migrations: 139, live migrations: 130`, `125 NOT applied live`, 14/139 prefix matches, header `:27-32` admits the heuristic, `grep -ic 14b build-apk.md` → 0; its ONLY documented runner is by hand via the restore-drill runbook, where it fails); recommendation RETIRE (Gate 14 `check_migrations_applied.dart` + the ledger already own "applied live"). Record the number as `OI-NEW` below.

- [ ] **Step 3: Write the failing lib tests** — `test/scripts/gate_scripts_wired_runners_test.dart`

```dart
// Red-path tests for check_gate_scripts_wired.dart (Gate 33)'s typed allowlist —
// the file name is stated here so the rule-24 ledger's `namesGate` check resolves.
import 'package:flutter_test/flutter_test.dart';
import '../../scripts/gate_scripts_wired_lib.dart';

const _preCommit = '''
for GATE in scripts/check_*.dart; do
  case "\$GATE_NAME" in
    check_skipped.dart|\\
    check_other.dart)
      continue ;;
  esac
done
# dart run scripts/check_commented.dart   <- a comment is not a runner
Run check_prose.dart before every release.   <- prose naming a gate is not a runner
"\$DART_BIN" run scripts/check_explicit.dart
''';

const _statuses = <String, String>{'OI-165': 'OPEN', 'OI-77': 'IN_PROGRESS', 'OI-9': 'CLOSED'};

void main() {
  String? read(String p) => p == 'scripts/pre-commit.sh' ? _preCommit : null;
  Set<String> skips(String c) => extractCaseSkips(c, caseSkipRegex);
  List<String> check(String gate, GateRunner r, {Map<String, String>? statuses = _statuses}) =>
      runnerViolations(gate: gate, runners: [r], read: read, caseSkipsOf: skips, boardStatuses: statuses);

  group('invokesGate', () {
    test('comment-only mention is NOT an invocation', () => expect(invokesGate(_preCommit, 'check_commented.dart'), isFalse));
    test('prose naming the gate WITHOUT the invocation shape is NOT an invocation', () => expect(invokesGate(_preCommit, 'check_prose.dart'), isFalse));
    test('prose CARRYING the invocation shape (`run scripts/<gate>`) DOES count -- a skill doc is executed by reading it', () =>
        expect(invokesGate('Then run `dart run scripts/check_doc.dart --record` before the upload.\n', 'check_doc.dart'), isTrue));
    test('case-skip line is NOT an invocation', () => expect(invokesGate(_preCommit, 'check_skipped.dart'), isFalse));
    test('`run scripts/<gate>` on a live line IS', () => expect(invokesGate(_preCommit, 'check_explicit.dart'), isTrue));
  });

  group('runnerViolations', () {
    test('file runner satisfied by a live invocation', () => expect(check('check_explicit.dart', GateRunner.file('scripts/pre-commit.sh', 'x')), isEmpty));
    test('RED PATH: file runner whose only mention is a comment', () {
      final violations = check('check_commented.dart', GateRunner.file('scripts/pre-commit.sh', 'x'));
      expect(violations, isNotEmpty);
    });
    test('RED PATH: file runner whose only mention is prose', () {
      final violations = check('check_prose.dart', GateRunner.file('scripts/pre-commit.sh', 'x'));
      expect(violations, isNotEmpty);
    });
    test('RED PATH: file runner naming an unreadable file', () {
      final violations = check('check_x.dart', GateRunner.file('.claude/commands/missing.md', 'x'));
      expect(violations, isNotEmpty);
    });
    test('loop runner satisfied when the loop file does not case-skip the gate', () => expect(check('check_explicit.dart', GateRunner.loop('preCommit', 'x')), isEmpty));
    test('RED PATH: loop runner for a gate the loop case-skips', () {
      final violations = check('check_skipped.dart', GateRunner.loop('preCommit', 'x'));
      expect(violations, isNotEmpty);
    });
    test('manual runner satisfied by an OPEN OI', () => expect(check('check_live.dart', GateRunner.manual('OI-165', 'x')), isEmpty));
    test('manual runner satisfied by an IN_PROGRESS OI (the session about to fix it must not be blocked)', () =>
        expect(check('check_live.dart', GateRunner.manual('OI-77', 'x')), isEmpty));
    test('RED PATH: manual runner citing a CLOSED OI fails -- the forcing function', () {
      final violations = check('check_live.dart', GateRunner.manual('OI-9', 'x'));
      expect(violations, isNotEmpty);
      expect(violations.single, contains('CLOSED'));
    });
    test('RED PATH: manual runner citing an OI on neither board fails', () {
      final violations = check('check_live.dart', GateRunner.manual('OI-9999', 'x'));
      expect(violations, isNotEmpty);
    });
    test('RED PATH: manual runner with an unreadable board fails CLOSED', () {
      final violations = check('check_live.dart', GateRunner.manual('OI-165', 'x'), statuses: null);
      expect(violations, isNotEmpty);
      expect(violations.single, contains('unreadable'));
    });
  });

  group('staleAllowlistViolations', () {
    test('an allowlist key with no script on disk is a violation (mirror of the ledger gate)', () {
      final violations = staleAllowlistViolations({'check_a.dart'}, ['check_a.dart', 'check_gone.dart']);
      expect(violations, isNotEmpty);
      expect(violations.single, contains('check_gone.dart'));
    });
    test('no stale keys, no violations', () => expect(staleAllowlistViolations({'check_a.dart'}, ['check_a.dart']), isEmpty));
  });
}
```

- [ ] **Step 4: Run → fails.** Confirm `extractCaseSkips(_preCommit, caseSkipRegex)` yields `{check_skipped.dart, check_other.dart}` against the REAL `caseSkipRegex` (read `scripts/gate_scripts_wired_lib.dart`); adjust the fixture's whitespace to match if not.

- [ ] **Step 5: Implement in `scripts/gate_scripts_wired_lib.dart`** (keep `extractCaseSkips` + `caseSkipRegex` untouched):

```dart
enum RunnerKind { file, loop, manual }

class GateRunner {
  final RunnerKind kind;
  final String target; // file path | 'preCommit' / 'ci' | 'OI-NNN'
  final String reason;
  const GateRunner._(this.kind, this.target, this.reason);
  const GateRunner.file(String path, String reason) : this._(RunnerKind.file, path, reason);
  const GateRunner.loop(String loop, String reason) : this._(RunnerKind.loop, loop, reason);
  const GateRunner.manual(String oi, String reason) : this._(RunnerKind.manual, oi, reason);
}

const loopFiles = <String, String>{'preCommit': 'scripts/pre-commit.sh', 'ci': '.github/workflows/test.yml'};

/// True iff some non-comment line INVOKES the gate: `run scripts/<gate>`.
/// A comment, a prose sentence, or a case-skip entry naming the gate is not an
/// invocation — the free-prose "runs in X" class OI-155 exists to kill. All 8
/// live invocation lines in the repo carry this shape (2026-09-19).
bool invokesGate(String content, String gate) {
  final needle = 'run scripts/$gate';
  for (final raw in content.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('#')) continue;
    if (line.contains(needle)) return true;
  }
  return false;
}

/// [boardStatuses] = mergedBoardStatuses(open, closed) — `null` means the open
/// board was unreadable, which fails CLOSED (a manual runner cannot be verified).
List<String> runnerViolations({
  required String gate,
  required List<GateRunner> runners,
  required String? Function(String path) read,
  required Set<String> Function(String content) caseSkipsOf,
  required Map<String, String>? boardStatuses,
}) {
  final out = <String>[];
  if (runners.isEmpty) out.add('$gate: allowlist entry declares no runner');
  for (final r in runners) {
    switch (r.kind) {
      case RunnerKind.file:
        final c = read(r.target);
        if (c == null) {
          out.add('$gate: runner file ${r.target} is unreadable');
        } else if (!invokesGate(c, gate)) {
          out.add('$gate: ${r.target} never invokes it (`run scripts/$gate` on a non-comment line)');
        }
      case RunnerKind.loop:
        final path = loopFiles[r.target];
        final c = path == null ? null : read(path);
        if (c == null) {
          out.add('$gate: loop `${r.target}` is not a known loop or its file is unreadable');
        } else if (!c.contains('scripts/check_*.dart')) {
          out.add('$gate: $path has no dynamic check_* loop');
        } else if (caseSkipsOf(c).contains(gate)) {
          out.add('$gate: declared loop:${r.target} but $path case-skips it');
        }
      case RunnerKind.manual:
        if (!RegExp(r'^OI-\d+$').hasMatch(r.target)) {
          out.add('$gate: manual runner must cite OI-NNN, got `${r.target}`');
        } else if (boardStatuses == null) {
          out.add('$gate: manual:${r.target} but the OI board is unreadable (fail CLOSED)');
        } else {
          final status = boardStatuses[r.target];
          if (status == null) {
            out.add('$gate: manual:${r.target} names no OI on either board');
          } else if (status == 'CLOSED') {
            out.add('$gate: manual:${r.target} is CLOSED -- give the gate a real runner or re-file the blocker');
          }
        }
    }
  }
  return out;
}

/// Mirror of gate_test_ledger_lib.dart:270-276: an entry for a gate that no
/// longer exists is stale bookkeeping (the retire path of OI-101 / OI-NEW).
List<String> staleAllowlistViolations(Set<String> gatesOnDisk, Iterable<String> allowlistKeys) => [
      for (final k in allowlistKeys)
        if (!gatesOnDisk.contains(k)) '$k: allowlist entry but no scripts/$k on disk (stale -- delete the entry)',
    ];
```

(If `analysis_options.yaml` enforces `switch` exhaustiveness with `break`s, add them; the enum is exhaustive.)

- [ ] **Step 6: Run lib tests → green.**

- [ ] **Step 7: Rewrite `check_gate_scripts_wired.dart`.** (a) `_allowList` (`:37-82`) becomes `const _allowList = <String, List<GateRunner>>{ … }` with EXACTLY these 13 entries (14 today minus `snapshot_contract`) (keys stay single-quoted with the trailing colon — `apk_release_signed_gate_test.dart:89-91` greps `'check_apk_release_signed.dart':` verbatim; `gate_wiring_args_required_test.dart` slices the map to its first `};`):

```dart
  'check_apk_size_within_bounds.dart': [GateRunner.file('.claude/commands/build-apk.md', 'Needs an APK; /build-apk Gate 13.')],
  'check_apk_release_signed.dart': [GateRunner.file('.claude/commands/build-apk.md', 'Needs an APK + apksigner + JDK; /build-apk Gate 48.')],
  'check_hooks_installed.dart': [GateRunner.loop('preCommit', 'CI runners never run setup-hooks.sh, so .git/hooks is absent there by design; case-skipped in test.yml only.')],
  'check_plan_review_record_exists.dart': [GateRunner.file('.github/workflows/test.yml', 'P1.A keystone (§4.12) -- dedicated `plan-review-record` CI job (fetch-depth:0); the shallow loops case-skip it.')],
  'check_unawaited_has_error_sink.dart': [GateRunner.loop('ci', 'ADVISORY (exit 0 by design, --strict to fail). CI\'s log is its only reader: pre-commit.sh:368 runs every gate as >/dev/null 2>&1, so it stays case-skipped there -- a 1.7 s no-op nobody can read.')],
  'check_razorpay_key_flavor.dart': [GateRunner.file('.claude/commands/build-apk.md', '.env.prod is gitignored; runs locally before a prod release only.')],
  'check_migrations_live.dart': [GateRunner.manual('OI-NEW', 'Cannot pass by construction: 125/139 local migrations were applied raw by the founder and never registered live (measured 2026-09-19). Its only documented runner is by hand (docs/runbooks/restore-drill.md:63), where it fails. Retire-or-redesign is the founder\'s call.')],
  'check_onconflict_live_arbiter.dart': [GateRunner.manual('OI-165', 'Live rollback-txn SQL via Management API; 403s with the current PAT. No automated runner until OI-165 names the token.')],
  'check_two_user_cross_account.dart': [GateRunner.manual('OI-165', 'Wrapper over check_onconflict_live_arbiter.dart; inherits its 403. Documented by-hand runner: docs/runbooks/restore-drill.md:71.')],
  'check_regression_catalog.dart': [GateRunner.file('scripts/pre-commit.sh', 'Explicit merge-commit invocation, not the auto-loop.')],
  'check_test_runtime_budget.dart': [GateRunner.manual('OI-101', 'Spawns the FULL `flutter test --reporter json`; re-arm-or-delete is OI-101 (founder scope call).')],
  'check_no_deferral_euphemism.dart': [GateRunner.file('scripts/pre-commit.sh', 'Scans the STAGED diff -- meaningful only at pre-commit; explicit invocation after the loop.')],
  'check_closes_oi_cited.dart': [GateRunner.file('scripts/commit-msg.sh', 'Commit-msg gate; takes the message file as its REQUIRED argument (a9f2c6).')],
```

(`check_snapshot_contract.dart` gets NO entry — it runs in both loops.) Keep the historical comments (`:48-57`). (b) Define, AFTER the `_allowList` map closes, a plain top-level function — NOT a closure ending in `};` above the map, because `test/contracts/gate_wiring_args_required_test.dart:66-67` slices the file from `const _allowList` to the FIRST `};` in the file: `String? _readOrNull(String path) { final f = File(path); return f.existsSync() ? f.readAsStringSync() : null; }`. In `main()`: build `boardStatuses` = `mergedBoardStatuses(...)` from `scripts/oi_closure_lib.dart:73-79` (read its parameter names; `check_closes_oi_performed.dart:38` already imports that lib the same way; pass the two board files' contents; if `docs/audit/open_issues.md` is unreadable pass `null`). Replace `:179`'s `continue` with: `if (_allowList.containsKey(script)) { unwired.addAll(runnerViolations(gate: script, runners: _allowList[script]!, read: _readOrNull, caseSkipsOf: (c) => extractCaseSkips(c, caseSkipRegex), boardStatuses: boardStatuses)); continue; }`. Replace `preCommitContent.contains(script)` / `workflowContent.contains(script)` at `:180,:182` with `invokesGate(...)`. After the loop add `unwired.addAll(staleAllowlistViolations(allChecks.toSet(), _allowList.keys));`. Keep `--warn-only` semantics (`:137`, `:241`) exactly.

- [ ] **Step 8: Un-dormant** — delete `check_snapshot_contract.dart|\` at `pre-commit.sh:337` and BOTH `check_unawaited_has_error_sink.dart|\` and `check_snapshot_contract.dart|\` from `test.yml`'s case block (`:236-249`). Recount and fix the "14 case-skipped" prose at `pre-commit.sh:134-136` and `:310-312` AND `test.yml`'s arm comment ("Other 4: require live DB / merge context / build artifact." — recount after the two deletions). Run `dart run scripts/check_snapshot_contract.dart; echo $?` → 0.

- [ ] **Step 9: Run the gate on the real tree** — `dart run scripts/check_gate_scripts_wired.dart; echo $?` → PASS, exit 0 (an entry failing means the ENTRY is wrong). Then `flutter test test/contracts/gate_wiring_args_required_test.dart test/contracts/apk_release_signed_gate_test.dart test/scripts/gate_scripts_wired_runners_test.dart` → green.

- [ ] **Step 10: Mutate and run** (commit Steps 1–9 first; `grep -c` each):
  1. lib `invokesGate` body → `return content.contains(gate);` → expected red: comment/prose/case-skip `invokesGate` tests (3) + the comment + prose runnerViolations red paths (2) = 5.
  2. lib manual branch: `status == 'CLOSED'` → `status == 'NEVER'` → expected red: the CLOSED test (1).
  3. lib: delete the `out.add(...)` in the `boardStatuses == null` branch (keep the `else if` chain compiling by making the branch body empty `{}`) → expected red: the unreadable test (1).
  4. lib `staleAllowlistViolations` → `=> const []` → expected red: its red-path test (1).
  5. lib loop branch: delete the `caseSkipsOf(c).contains(gate)` arm → expected red: the loop red path (1).
  Also prove the REAL gate catches the class: edit one `manual` target to `'OI-9999'` → `dart run scripts/check_gate_scripts_wired.dart` → FAIL exit 1 naming it; restore.

- [ ] **Step 11: Diagnose-doc** (validator first). Writer = `_allowList` prose (`check_gate_scripts_wired.dart:37-82`); reader = NONE (that is the bug) → now `runnerViolations`. `related_bugs:` a9f2c6. `touched_layers_checked`: tier 1 `fixed_in_this_batch`; tiers 2–12 `not_applicable` with one-line reasons. State that 4 of 6 are `manual:` and why each (OI-165 ×2, OI-101, OI-NEW). Validate.

- [ ] **Step 12: Commit**

```bash
git add scripts/gate_scripts_wired_lib.dart scripts/check_gate_scripts_wired.dart scripts/pre-commit.sh .github/workflows/test.yml docs/audit/open_issues.md test/scripts/gate_scripts_wired_runners_test.dart docs/diagnoses/<file>
sh scripts/safe_commit.sh "fix(gates): Gate 33 allowlist declares typed runners and is machine-checked; the six dormant gates get truthful ones (OI-155)

snapshot_contract runs in both loops (skip lines removed; passes today).
unawaited_has_error_sink -> loop:ci (advisory; pre-commit's >/dev/null loop
has no reader). migrations_live -> manual:OI-<NEW> -- it cannot pass by
construction (125/139 never registered live). onconflict_live_arbiter +
two_user_cross_account -> manual:OI-165 (403). test_runtime_budget ->
manual:OI-101. A manual runner must cite an OPEN/IN_PROGRESS OI on the
merged boards, so closing that OI turns this gate red until the gate gets a
real runner; a stale allowlist key is a violation; wiring inference now
requires an invocation, not a mention.

Mutation-proven: 5 mutations, <M> tests reddened. Tests:
test/scripts/gate_scripts_wired_runners_test.dart.

closes-diagnose: <id>"
```

Report back: branch, sha, OI-NEW number, per-mutation reds, the gate's PASS line, the exact skip lines removed and the recounted prose.

---

### Task 3: OI-195 — Gate 42 resolves every cited path

**Files:**
- Modify: `scripts/check_sot_behavioral_test_paths.dart` (`:104-105` key regexes; `:103-114` value branch; new `presence_only` scan; `:128-129` problems; `:146-164` report; tally)
- Test: `test/scripts/sot_behavioral_test_paths_gate_test.dart` (new, subprocess fixture; record field named `exitCode`)
- Create: `docs/diagnoses/2026-09-19-gate42-never-resolves-cited-test-path-<id>.md`

- [ ] **Step 1: §4.1.5 grep** — `grep -n "behavioral_test_path\|Gate 42\|presence_only" docs/diagnoses/INDEX.md`; cite matches (rule 21's `user_full_name` case is a known relative).

- [ ] **Step 2: Write the failing test** — `test/scripts/sot_behavioral_test_paths_gate_test.dart` (precedent `claude_md_citations_letter_suffix_test.dart:29-66`; `dartBinOf()` from `cron_registry_snapshot_gate_test.dart:33-57`):

```dart
@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// dartBinOf() — copy verbatim from test/scripts/cron_registry_snapshot_gate_test.dart:33-57

String _registry({required String path, String extra = ''}) => '''
concepts:

  - concept: alpha
    domain: workout
    behavioral_test_path: $path  # a1b2c3 — trailing comment must be stripped
    writers:
      - file: lib/a.dart
        line_range: 1-5
$extra
''';

void main() {
  late String gate;
  late Directory fx;
  final dartBin = dartBinOf();

  setUpAll(() {
    gate = '${Directory.current.path}/scripts/check_sot_behavioral_test_paths.dart';
    expect(File(gate).existsSync(), isTrue);
  });
  setUp(() {
    fx = Directory.systemTemp.createTempSync('gate42_');
    Directory('${fx.path}/docs').createSync(recursive: true);
    Directory('${fx.path}/test/contracts').createSync(recursive: true);
    File('${fx.path}/test/contracts/real_test.dart').writeAsStringSync('void main() {}\n');
  });
  tearDown(() { try { fx.deleteSync(recursive: true); } catch (_) {} });

  // The record field is `exitCode` ON PURPOSE: gate_test_ledger_lib.dart:69-73
  // accepts `exitCode,\s*1` as a red-path form; `code` does not count.
  ({int exitCode, String out}) run([List<String> extra = const []]) {
    final r = Process.runSync(dartBin, ['run', gate, ...extra], workingDirectory: fx.path, runInShell: true);
    return (exitCode: r.exitCode, out: '${r.stdout}${r.stderr}');
  }
  void write(String yaml) => File('${fx.path}/docs/sot_registry.yaml').writeAsStringSync(yaml);

  test('an existing path (with a trailing comment) passes', () {
    write(_registry(path: 'test/contracts/real_test.dart'));
    final r = run();
    expect(r.exitCode, 0, reason: r.out);
  });
  test('RED PATH: a behavioral_test_path that does not exist fails strict', () {
    write(_registry(path: 'test/contracts/ghost_test.dart'));
    final r = run();
    expect(r.exitCode, 1, reason: r.out);
    expect(r.out, contains('ghost_test.dart'));
  });
  test('--warn-only downgrades the same miss to exit 0 and still NAMES it', () {
    write(_registry(path: 'test/contracts/ghost_test.dart'));
    final r = run(['--warn-only']);
    expect(r.exitCode, 0, reason: r.out);
    expect(r.out, contains('ghost_test.dart'));
  });
  test('RED PATH: a sibling behavioral_test_path_<suffix> key is resolved too', () {
    write(_registry(path: 'test/contracts/real_test.dart', extra: '    behavioral_test_path_cqrs: test/contracts/missing_second_test.dart'));
    final r = run();
    expect(r.exitCode, 1, reason: r.out);
    expect(r.out, contains('missing_second_test.dart'));
  });
  test('RED PATH: presence_only trailing prose citing a repo path that does not exist fails', () {
    write('''
concepts:

  - concept: beta
    presence_only: true # covered by test/sql/nope.sql
    writers:
      - file: lib/b.dart
        line_range: 1-2
''');
    final r = run();
    expect(r.exitCode, 1, reason: r.out);
    expect(r.out, contains('test/sql/nope.sql'));
  });
  test('RED PATH: presence_only_reason block scalar citing a path that does not exist fails', () {
    write('''
concepts:

  - concept: gamma
    presence_only: true
    presence_only_reason: |
      Static concept; pinned by docs/nope/absent.yaml instead.
    writers:
      - file: lib/c.dart
        line_range: 1-2
''');
    final r = run();
    expect(r.exitCode, 1, reason: r.out);
    expect(r.out, contains('docs/nope/absent.yaml'));
  });
  test('presence_only_reason block citing an existing path (with trailing punctuation) passes', () {
    write('''
concepts:

  - concept: delta
    presence_only: true
    presence_only_reason: |
      Static concept; pinned by test/contracts/real_test.dart.
    writers:
      - file: lib/d.dart
        line_range: 1-2
''');
    final r = run();
    expect(r.exitCode, 0, reason: r.out);
  });
}
```

- [ ] **Step 3: Run → the RED PATH tests fail** (exit 0 today); the pass tests pass.

- [ ] **Step 4: Implement** in `check_sot_behavioral_test_paths.dart`:
  - Widen the key regexes at `:104-105` to `behavioral_test_path(?:_[a-z0-9_]+)?`.
  - One helper: `String? _missingOnDisk(String path) => File('${Directory.current.path}/$path').existsSync() ? null : path;`
  - In the value branch: `final path = value.replaceFirst(RegExp(r'\s+#.*$'), '').trim();` and, when the existing validity test passes, `if (_missingOnDisk(path) != null) missingFiles.add('$currentConcept: behavioral_test_path `$path` does not exist (registry line $lineNo)');` — declare `final missingFiles = <String>[];` beside the other sinks; track `lineNo`.
  - `presence_only` scan: on `^\s+presence_only\s*:\s*true` take the trailing `#` comment text; on `^\s+presence_only_reason\s*:\s*[|>]` (literal OR folded block) collect every following line that is MORE indented than the key (stop at the first line that is not; the real block at `:6082` has key indent 4, body 6, and stops at `description:`); for each text, every match of `RegExp(r'\b(test|docs|scripts|supabase|lib)/[A-Za-z0-9_./-]+')` with trailing `.,;)` trimmed must pass `_missingOnDisk`, else `missingFiles.add('$currentConcept: presence_only cites `$p` which does not exist')`. Count EVERY `presence_only: true` line for the tally and say how many also carry a behavioral path.
  - `problems = [...staleRequired, ...missing, ...missingFiles]` at `:128-129`; a `[file-missing]` report block mirroring `check_sot_registry_parity.dart:151-155`.
  - Run on the REAL registry: `dart run scripts/check_sot_behavioral_test_paths.dart; echo $?` → PASS, exit 0, tally re-derived (`grep -cE '^\s+presence_only:\s*true' docs/sot_registry.yaml` → 17).

- [ ] **Step 5: Run the new test → green.** `flutter analyze scripts/check_sot_behavioral_test_paths.dart test/scripts/sot_behavioral_test_paths_gate_test.dart` → 0 warnings.

- [ ] **Step 6: Mutate and run** (commit first): (1) `_missingOnDisk` → `=> null` (one helper backs BOTH sinks, so this reddens every RED PATH test AND the `--warn-only … still NAMES it` test: 5, measured by round 2); (2) narrow the key regex back to `behavioral_test_path\s*:` → the sibling-key test (1); (3) drop the comment-strip → the passing trailing-comment test (1); (4) make the block-scalar collector stop immediately (collect zero lines) → the `presence_only_reason` RED test (1). Record counts.

- [ ] **Step 7: Diagnose-doc** (validator first). Writer = `docs/sot_registry.yaml` `behavioral_test_path:` values (140 concepts); reader = Gate 42 `:103-114`, which read the field's SHAPE, never the file. Tier 1 `fixed_in_this_batch`; others `not_applicable`.

- [ ] **Step 8: Commit**

```bash
git add scripts/check_sot_behavioral_test_paths.dart test/scripts/sot_behavioral_test_paths_gate_test.dart docs/diagnoses/<file>
sh scripts/safe_commit.sh "fix(gates): Gate 42 resolves every cited behavioral_test_path and presence_only citation on disk (OI-195)

Comment-stripped values, sibling behavioral_test_path_<suffix> keys, and
repo-shaped paths inside presence_only prose / presence_only_reason blocks
must exist; strict -> exit 1, --warn-only -> exit 0 and still names the
miss. Tally counts every presence_only: true line (17; 10 also carry a
behavioral path).

Mutation-proven: 4 mutations, <M> tests reddened. Tests:
test/scripts/sot_behavioral_test_paths_gate_test.dart.

closes-diagnose: <id>"
```

Report back: branch, sha, per-mutation reds, the real-registry PASS line.

---

### Task 4: OI-181 — `safe_merge.sh` warns on an ABSENT plan-review record

**Files:**
- Modify: `scripts/safe_merge.sh` (insert after `:231`'s `fi` + its `# ----` line, before `:234`)
- Test: `test/scripts/safe_merge_test.dart` (two helpers + 3 tests)
- Create: `docs/diagnoses/2026-09-19-safe-merge-silent-on-absent-record-<id>.md`

- [ ] **Step 1: §4.1.5 grep** — `grep -n "safe_merge\|plan-review record" docs/diagnoses/INDEX.md`. `related_bugs:` = `c9f4e1` ONLY (18 safe_merge mentions; verify it resolves in INDEX). Do NOT cite `d4e9a2` — it is `2026-08-30-profile-full-name-restore-race`, which the precheck commit `ecc01876` reused as a batch id for the commit-msg gate; name `ecc01876` by sha in prose instead. `recurrence:` = third merge-without-record instance (`dcb94a93` 2026-09-10; `0768a0ce` 2026-09-18; the 2026-08-30 unwind CLAUDE.md §7 records). Residues to STATE in the doc (not fix): the precheck fires only on the `safe_merge.sh` path — `gh pr merge` (used 2026-09-16 when the sandbox blocked the primary) and a raw `git merge` bypass it; an `origin/foo` branch spelling is silent (same as the existing bpass precheck); pre-merge the classifier's content rule reads the WORKING TREE (`blast_radius_content_rules_lib.dart:58-62`), so a branch's SECURITY DEFINER migration classifies `platform`, not `catastrophic` — still ≥ account, the warning fires, the tier in the message can understate.

- [ ] **Step 2: Write the failing tests** — append to `test/scripts/safe_merge_test.dart` (read `:1-60`, the `_run(exe, args, cwd)` helper at `:33-42` — it is the ONLY helper; every git call is `_run('git', …)` — and `makeFeatureBranch`'s definition, which the new helper mirrors):

```dart
  /// The absent-record precheck classifies `refs/heads/main...BRANCH`; the
  /// fixture needs the real classifier to do so (copyScripts copies only
  /// safe_merge.sh + _git_lock.sh — see :52-57). Idempotent: a second call is a no-op.
  void installClassifier(String primary) {
    if (File('$primary/docs/blast_radius.yaml').existsSync()) return;
    final srcRoot = Directory.current.path;
    for (final rel in [
      'scripts/blast_radius_from_diff.dart',
      'scripts/blast_radius_content_rules_lib.dart',
      'scripts/_dart_bin.sh',
      'docs/blast_radius.yaml',
    ]) {
      final dst = File('$primary/$rel')..parent.createSync(recursive: true);
      dst.writeAsBytesSync(File('$srcRoot/$rel').readAsBytesSync());
    }
    _run('git', ['add', '-A'], primary);
    _run('git', ['commit', '-q', '-m', 'fixture: classifier'], primary);
    _run('git', ['push', '-q', 'origin', 'main'], primary);
  }

  /// A branch off main that adds ONE file at [path] and no plan-review record.
  /// Same shape as makeFeatureBranch (:103-110): `-B <name> main` (explicit
  /// start point, never the current HEAD), parameterising only the path.
  String makeBranchAdding(String primary, String name, String path) {
    _run('git', ['checkout', '-q', '-B', name, 'main'], primary);
    File('$primary/$path')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('-- probe\n');
    _run('git', ['add', '-A'], primary);
    _run('git', ['commit', '-qm', 'branch: $name'], primary);
    _run('git', ['checkout', '-q', 'main'], primary);
    return name;
  }

  test('RED PATH: warns when a >= account branch has NO plan-review record', () {
    installClassifier(primary);
    final branch = makeBranchAdding(primary, 'no-record-platform', 'supabase/migrations/900_probe.sql');
    final r = _run('sh', ['scripts/safe_merge.sh', branch], primary);
    expect(r.exitCode, 0, reason: 'advisory: ${r.stdout}${r.stderr}');
    expect('${r.stdout}${r.stderr}', contains('NO plan-review record'));
  });
  test('stays silent for a feature-tier branch with no record even with the classifier present', () {
    installClassifier(primary);
    final branch = makeBranchAdding(primary, 'no-record-feature-classified', 'feature-only.txt');
    final r = _run('sh', ['scripts/safe_merge.sh', branch], primary);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect('${r.stdout}${r.stderr}', isNot(contains('NO plan-review record')));
  });
  test('three-dot: a platform-tier change that landed on MAIN after the branch was cut does not warn', () {
    installClassifier(primary);
    final branch = makeBranchAdding(primary, 'cut-before-main-moved', 'feature.txt');
    File('$primary/supabase/migrations/901_main_only.sql')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('-- landed on main after the cut\n');
    _run('git', ['add', '-A'], primary);
    _run('git', ['commit', '-q', '-m', 'main: migration'], primary);
    _run('git', ['push', '-q', 'origin', 'main'], primary);
    final r = _run('sh', ['scripts/safe_merge.sh', branch], primary);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect('${r.stdout}${r.stderr}', isNot(contains('NO plan-review record')),
        reason: 'two-dot would classify main-only changes as the branch\'s');
  });
```

- [ ] **Step 3: Run → the RED PATH test fails** (no warning today); the other two pass vacuously — expected; mutations 2/3 exist for exactly that.

- [ ] **Step 4: Insert the block** after `scripts/safe_merge.sh:231-232`, before `echo "[safe_merge] main is caught up …"`:

```sh
# ABSENT-RECORD PRECHECK (OI-181) -- advisory; every failure path stays silent.
# Mirrors check_plan_review_record_exists.dart:617-620 + :790-796: a record is
# required iff the branch's blast-radius is >= account. Three-dot (merge-base)
# because the merge commit does not exist yet; refs/heads/ on BOTH sides
# because a same-named tag resolves first (see the tag test above);
# --no-renames + quotePath=false mirror the gate's own diff flags (:309-315).
# The gate's exemptions (dependabot manifest-only, bare version bump) are
# deliberately NOT mirrored: 0768a0ce was a version bump and the gate failed it.
if [ -z "${_REC_CONTENT:-}" ] \
   && git rev-parse --verify --quiet "refs/heads/${BRANCH}" >/dev/null 2>&1 \
   && [ -r "$REPO_ROOT/scripts/blast_radius_from_diff.dart" ] \
   && [ -r "$REPO_ROOT/docs/blast_radius.yaml" ]; then
  _PRE_DART="dart"
  if [ -r "$REPO_ROOT/scripts/_dart_bin.sh" ] && sh -n "$REPO_ROOT/scripts/_dart_bin.sh" 2>/dev/null; then
    . "$REPO_ROOT/scripts/_dart_bin.sh" || true
    _PRE_DART="$(resolve_dart_bin 2>/dev/null || echo dart)"
  fi
  _PRE_PATHS="$(git -c core.quotePath=false diff --no-renames --name-only "refs/heads/main...refs/heads/${BRANCH}" 2>/dev/null || true)"
  _PRE_TIER=""
  if [ -n "$_PRE_PATHS" ]; then
    _PRE_TIER="$(printf '%s\n' "$_PRE_PATHS" \
      | "$_PRE_DART" run scripts/blast_radius_from_diff.dart - 2>/dev/null \
      | grep -oE 'Blast-radius: (feature|account|platform|catastrophic)' \
      | tail -1 | awk '{print $2}' || true)"
    if [ -z "${_PRE_TIER:-}" ]; then
      # Bad news vs no news: paths changed but the classifier produced nothing.
      echo "[safe_merge] NOTE: could not classify '$BRANCH' (classifier produced no tier) -- the absent-record precheck is inconclusive, not clean." >&2
    fi
  fi
  case "${_PRE_TIER:-}" in
    account|platform|catastrophic)
      echo "[safe_merge] WARNING: '$BRANCH' is blast-radius=$_PRE_TIER (>= account) but has NO plan-review record at $_REC on that branch." >&2
      echo "  CI's keystone gate reads the record AT THE MERGE COMMIT, so merging now means the" >&2
      echo "  only repair is unwinding this merge (it cost exactly that on 2026-08-30, 2026-09-10, 2026-09-18)." >&2
      echo "  Write docs/plan-reviews/${_REC_SLUG}.md on '$BRANCH' FIRST (CLAUDE.md §4.12.3)." >&2
      echo "  (Advisory only -- proceeding. CI is the authoritative gate.)" >&2
      ;;
  esac
fi
```

`sh -n scripts/safe_merge.sh` → clean.

- [ ] **Step 5: Run the whole file** — `flutter test test/scripts/safe_merge_test.dart` → 15/15. `:426` stays green.

- [ ] **Step 6: Mutate and run** (commit first; `grep -c`): (1) delete the whole block → RED PATH (1); (2) `account|platform|catastrophic)` → `*)` → feature-silent + three-dot (2); (3) `main...refs` → `main..refs` → three-dot (1). Record counts.

- [ ] **Step 7: Diagnose-doc** (validator first). Writer = the branch author (record on the branch); reader = `safe_merge.sh:208` (`if [ -n "$_REC_CONTENT" ]` — reads presence only to decide whether to LOOK, never to warn); mirror = keystone `:790-796`. `recurrence:` third instance. Tier 1 `fixed_in_this_batch`; others `not_applicable`.

- [ ] **Step 8: Commit**

```bash
git add scripts/safe_merge.sh test/scripts/safe_merge_test.dart docs/diagnoses/<file>
sh scripts/safe_commit.sh "fix(merge): safe_merge warns BEFORE the merge when a >= account branch has no plan-review record (OI-181)

Classifies refs/heads/main...refs/heads/BRANCH (three-dot) with the real
classifier and mirrors the keystone gate's >= account threshold; advisory,
every failure path silent except a NOTE when the classifier yields nothing.
Third instance of merge-without-record (2026-08-30, 09-10, 09-18).

Mutation-proven: 3 mutations, <M> tests reddened. Tests:
test/scripts/safe_merge_test.dart (+3, now 15).

closes-diagnose: <id>"
```

Report back: branch, sha, per-mutation reds, `safe_merge_test.dart` total.

---

### Task 5: Integration (coordinator, inline)

**Files:** `docs/blast_radius.yaml`, `CLAUDE.md`, `docs/audit/gate_test_ledger.yaml`, `docs/audit/open_issues.md` (in-place status flips), `docs/audit/gate-integrity.closure.yaml`, `docs/plan-reviews/gate-integrity.md`, `docs/reviews/<sha>-bpass.md`, `.claude/skills/code-review/SKILL.md` (tuning entry).

- [ ] **Step 1: Cherry-pick** each fork's commit(s) onto `gate-integrity`, Task 1 → 4 (`git cherry-pick <sha>`). A CLEAN pick runs NO `pre-commit`/`commit-msg` hook (probed by round 2: only `prepare-commit-msg` + `post-commit` fire; the `CHERRY_PICK_HEAD` exemptions at `check_commit_from_worktree.dart:76-81` / `check_closes_oi_cited.dart:126-130` exist for the CONFLICT path, where `git cherry-pick --continue` DOES run both). The gates ran on each branch; Step 8's commit is the first gate run over the UNION. **Expect a conflict on `docs/diagnoses/INDEX.md` on the 2nd and 3rd fix units** — each fork's pre-commit regenerates and stages it (`pre-commit.sh:183-191`) and the chronological table is latest-first, so three same-day rows insert at the same line. Never hand-merge a generated index: `"$DART_BIN" run scripts/build_bug_index.dart && git add docs/diagnoses/INDEX.md && git cherry-pick --continue` (the `--continue` pays the ~98 s loop; same recipe for `OPEN_INDEX.md` / `GATE_INDEX.md` if they ever collide). `git log --oneline -7` → spec v1, spec v2, 4 units.
- [ ] **Step 2: Verify one mutation per unit yourself** (the cheapest listed) — trust but verify (§4.9 subagent-numeric rule). Record the observed reds.
- [ ] **Step 3: `docs/blast_radius.yaml` (D16)** — beside the `scripts/pre-push.sh` pin (`:164`), add `platform` pins for `scripts/contract_sweep.dart`, `scripts/contract_sweep_lib.dart`, `scripts/gate_scripts_wired_lib.dart`, `scripts/check_sot_behavioral_test_paths.dart`, AND the two libs Gate 33's `manual:` verdicts now depend on — `scripts/oi_closure_lib.dart`, `scripts/check_closes_oi_cited.dart` (both `feature` today). Verify: `printf '%s\n' <each> | dart run scripts/blast_radius_from_diff.dart -` → platform ×6; `dart run scripts/check_blast_radius_coverage.dart` → PASS.
- [ ] **Step 4: Ledger** — promote `check_gate_scripts_wired.dart` (`gate_test_ledger.yaml:343`; `test_path:` = [`test/scripts/gate_scripts_wired_runners_test.dart`, `test/contracts/gate_wiring_args_required_test.dart`]) and `check_sot_behavioral_test_paths.dart` (`:486-487`; `test_path:` = [`test/scripts/sot_behavioral_test_paths_gate_test.dart`]) to `mutation_proven: true` + `evidence:` (what was neutered, observed reds) — shape from `:596-`. `dart run scripts/check_gate_test_ledger.dart` → PASS.
- [ ] **Step 5: CLAUDE.md** (D15): §0 pre-push row (the sweep step, warn-only, guards; and re-derive the gate counts — `ls scripts/check_*.dart | wc -l`, the case-skipped count after D8); §4.1.5 item 6 — *"Value-semantics grep (pre-work): a batch that changes a stored value's MEANING sweeps `test/` AND `supabase/functions/` for that value BEFORE coding (codified 2026-09-18 in code-review tuning; #47)."*; §4.12.7 — *"Execution mode (subagent vs inline) is decided and written into the plan at batch START, never mid-batch (OI-220 rider 2)."*; rule 21 — Gate 42 "STRICT by default and now RESOLVES every cited path on disk (OI-195, 2026-09-19)" + replace "6 entries carry it today" with exactly: "17 concepts carry `presence_only: true`, 10 of which also cite a behavioral path (`grep -cE '^\s+presence_only:\s*true' docs/sot_registry.yaml`)"; §7 — new row for `contract_sweep` (arms, fallback, guards, warn-only until the flip, not a check_*, pinned by `contract_sweep_wired_test.dart`, rule-21 mutation counts) and the safe_merge row (absent-record precheck; `safe_merge_test.dart` count re-run). Then `dart run scripts/check_claude_md_citations.dart` → PASS.
- [ ] **Step 6: Board** — flip OI-155, OI-195, OI-181 IN PLACE to `- **Status**: CLOSED · 2026-09-19 · diagnose <id> · commit <sha>` (do NOT move them; six CLOSED entries already sit on the open board). OI-220 stays OPEN: rewrite `Blocked on:` to the flip criterion, add a `Shipped:` line (warn-only, commit sha), and replace its "rule-24 ledger entry" sentence with the D1/D5 trust model. The commit carrying the three flips MUST have `closes-oi: OI-155`, `closes-oi: OI-195`, `closes-oi: OI-181` lines.
- [ ] **Step 7: Closure YAML** `docs/audit/gate-integrity.closure.yaml` — read `scripts/validate_audit_closure.dart:1-60` FIRST; shape from `unitb-deload-reason.closure.yaml`. Entries: U1 OI-220 build (`closed_in_commit`, `commit: gate-integrity@branch`, `notes:` shipped warn-only; flip tracked on OI-220 with its criterion), U2 OI-155 (`closed_in_commit`; note 4 of 6 `manual:`), U3 OI-195, U4 OI-181 (`closed_in_commit`), U5 migrations_live retire-or-redesign (`blocked_on_user`, `reason:` founder call, OI-NEW), plus one entry per B-pass finding after Step 9. `closed_count:` recomputed. `dart run scripts/validate_audit_closure.dart --strict` → PASS.
- [ ] **Step 8: Commit** Steps 3–7 as `docs(gates): blast-radius pins, ledger promotions, CLAUDE.md riders, board + closure ledger for gate-integrity` with the three `closes-oi:` lines. The commit IS the gate loop.
- [ ] **Step 9: B-pass** — `/code-review` on the branch (platform ⇒ mandatory, self-initiated). Fix findings in-branch; add each to the closure YAML; the skill-tuning gate requires a same-dated entry in `.claude/skills/code-review/SKILL.md` (queue: the non-`check_*` runner trap; the `- file:` regex compose-from-memory miss; the Windows cmd.exe-vs-PATH-stub recursion).
- [ ] **Step 10: Plan-review record** `docs/plan-reviews/gate-integrity.md` — READ `memory/feedback_gates_unsatisfiable_at_merge.md` + `feedback_plan_review_record_frontmatter_format.md` first. Frontmatter: `branch: gate-integrity`, `review_rounds: 2`, `mechanical_only: false`, `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted`, `bpass_review: docs/reviews/<file>`, `tier: standard`, `date: 2026-09-19`. Body: both rounds' findings + fixes, the four mutation ledgers (unit × mutation × observed reds), and the rule-21 proof for `contract_sweep`. Commit it on the branch BEFORE the merge; `sh scripts/safe_merge.sh gate-integrity` from the primary will preview both prechecks — the new one must be SILENT for this branch.
- [ ] **Step 11: Full-suite scope** — run the new/extended test files inside `flutter test test/scripts/` once (contention check). The merge to `main` and the push run pre-push at platform tier (full `flutter test`, and the new sweep in warn-only) + CI. **Ask the founder before `safe_merge.sh` + `safe_push.sh`.**
- [ ] **Step 12: §5 close-out** — retrospective `project_gate_integrity_2026_09_19.md`; in-flight memory → archived line; worktree retirement dry-run; context-artifact budget check; skill self-evolution answered.
