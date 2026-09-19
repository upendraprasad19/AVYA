# gate-integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close OI-220 (build), OI-155, OI-195 and OI-181 in one platform-tier batch: a pre-push contract sweep, a machine-checked Gate 33 allowlist with the six dormant gates given real runners, Gate 42 resolving every cited path, and a pre-merge absent-record warning.

**Architecture:** Four independent units with zero file overlap, each a pure-lib/runner or a small script edit plus a mutation-proven test and (for the three fixes) a diagnose-doc. Four forks build them in isolated worktrees and commit on their own branches; the coordinator cherry-picks onto `gate-integrity`, then edits the shared files (CLAUDE.md, ledger, board, closure YAML, plan-review record) as the single writer.

**Tech Stack:** Dart (scripts + `test/scripts/` subprocess tests), POSIX sh (`safe_merge.sh`, `pre-push.sh`), YAML (ledger, closure), Markdown (CLAUDE.md, build-apk.md, playbook).

**Spec:** `docs/superpowers/specs/2026-09-19-gate-integrity-design.md` — every file:line below is verified there (§1); every choice is argued there (§2). Read the spec first.

## Global Constraints

- Blast radius `platform` for every unit; the batch is L-tier (CLAUDE.md riders). ×2 context-blind plan review BEFORE execution (§4.12.1); B-pass BEFORE the merge (§4.3); closure YAML `docs/audit/gate-integrity.closure.yaml` (§4.2, ≥4 units).
- Commits ONLY via `sh scripts/safe_commit.sh "<msg>"` (one positional arg — a flag becomes the message, §4.9). Never `--no-verify`. Never push from a unit branch.
- Every new test file that spawns a subprocess carries `@Timeout(Duration(minutes: N))` + `library;` as its first two lines and a `tearDown` that never throws (§4.9). Grep the file for `timeout:` afterwards — a per-test override defeats the file annotation.
- Spawn dart in tests via the `dartBinOf()` helper copied from `test/scripts/cron_registry_snapshot_gate_test.dart:33-57` — NEVER `Platform.resolvedExecutable` (hangs under `flutter test`).
- Every fix commit (`fix(gates): …`) carries `closes-diagnose: <6-hex id>` and a diagnose-doc that passes `dart run scripts/validate_diagnose_doc.dart <path>`. READ THE VALIDATOR (`scripts/validate_diagnose_doc_lib.dart`) before drafting the doc; copy the frontmatter shape of `docs/diagnoses/2026-09-18-safe-push-test-contention-window-f7a3b1.md`.
- Mutate-and-run (rule 21): every mutation must leave the file COMPILING and semantically wrong; confirm it APPLIED (`grep -c` the token); record what was mutated and how many tests reddened. A zero-red mutation means "go find out what absorbed it", not "already covered".
- Run `sh scripts/pre-commit.sh`'s loop by attempting the commit — never a hand-picked gate subset (§4.12.5).
- Filters narrow the input set: prefer `git grep` for does-this-still-exist; never pipe `blast_radius_from_diff.dart` or `safe_commit.sh` output through `grep -v`/`head`/`tail` (§4.9).

**Execution mode (OI-220 rider 2, decided at batch start):** subagent-driven. Tasks 1–4 → one fork each, `isolation: worktree`, branch base `gate-integrity`, commit on the fork's branch, report branch name + commit sha(s) + mutation evidence + test counts. Task 0 and Task 5 → coordinator, inline.

---

### Task 0: Preflight (coordinator)

**Files:** `docs/superpowers/specs/2026-09-19-gate-integrity-design.md`, this plan.

- [ ] **Step 1: Confirm worktree + base**

```
git -C ".claude/worktrees/gate-integrity" branch --show-current   # gate-integrity
git -C ".claude/worktrees/gate-integrity" log --oneline -1         # 8ffe28fb
git -C ".claude/worktrees/gate-integrity" status --short           # spec + plan untracked only
```

- [ ] **Step 2: Commit spec + plan**

```bash
cd ".claude/worktrees/gate-integrity"
git add docs/superpowers/specs/2026-09-19-gate-integrity-design.md docs/superpowers/plans/2026-09-19-gate-integrity.md
sh scripts/safe_commit.sh "docs(gates): spec + plan for gate-integrity (OI-220/155/195/181)"
```

Expected: `OK -- HEAD advanced`; `git log -1 --format=%s` shows that subject.

- [ ] **Step 3: ×2 plan review** — dispatch round 1 (context-blind, `docs/agent_brief_preamble.md` prefixed, lenses L1 correctness / L7 test-discrimination / L31 fail-safe / L54 context-artifact cost); harden the plan; dispatch round 2 on the HARDENED plan; converge or split (§4.12.5). Only then dispatch Tasks 1–4.

---

### Task 1: OI-220 — `contract_sweep` (pre-push targeted contract tests)

**Files:**
- Create: `scripts/contract_sweep_lib.dart` (pure selection)
- Create: `scripts/contract_sweep.dart` (runner: git + registry + spawn)
- Modify: `scripts/pre-push.sh:112-114` (wiring line + comment)
- Modify: `docs/playbook/common-pitfalls.md` (append the riverpod-3 widget-harness section — rider 3)
- Test: `test/scripts/contract_sweep_lib_test.dart` (pure), `test/scripts/contract_sweep_e2e_test.dart` (real temp repo + stub flutter)

**Interfaces:**
- Produces: `buildSelection(...)` → `SweepSelection` (below); runner flags `--warn-only`, `--dry-run`, `--range <a>..<b>`, `--flutter-bin <path>`; stdout lines prefixed `[contract-sweep]`.
- Consumed by: `scripts/pre-push.sh` (Task 1 Step 9) and, later, the OI-220 flip commit (removes `--warn-only || true`).

- [ ] **Step 1: Write the failing lib tests** — `test/scripts/contract_sweep_lib_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import '../../scripts/contract_sweep_lib.dart';

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

  - concept: subscription_cqrs
    behavioral_test_path: test/contracts/subscription_cqrs_behavioral_test.dart
    behavioral_test_path_cqrs: test/contracts/subscription_cqrs_second_test.dart
    presence_only: true # see test/sql/x.sql
    writers:
      - file: lib/core/services/subscription_service.dart
        line_range: 1-9
''';

void main() {
  group('contentReferenceKeys', () {
    test('basename with extension for ordinary files; parent/basename for ubiquitous names', () {
      final keys = contentReferenceKeys([
        'lib/core/services/sync/sync_workout.dart',
        'supabase/functions/ai-proxy/index.ts',
        'lib/main.dart',
        'test/contracts/foo_test.dart', // arm (c) territory — excluded here
        'docs/audit/open_issues.md',    // docs — excluded
      ]);
      expect(keys, {'sync_workout.dart', 'ai-proxy/index.ts', 'lib/main.dart'});
    });
  });

  group('registryTestsFor', () {
    test('selects the concept whose writer OR reader file changed, including sibling keys, comment-stripped', () {
      final tests = registryTestsFor(_registry, {'lib/core/services/subscription_service.dart'});
      expect(tests, ['test/contracts/subscription_cqrs_behavioral_test.dart', 'test/contracts/subscription_cqrs_second_test.dart']);
      final byReader = registryTestsFor(_registry, {'lib/features/train/screens/train/screen.dart'});
      expect(byReader, ['test/contracts/phase_adherence_rate_test.dart']);
    });
    test('positive control: an unrelated change selects nothing', () {
      expect(registryTestsFor(_registry, {'lib/unrelated.dart'}), isEmpty);
    });
  });

  group('buildSelection', () {
    test('unions the three arms, dedupes, sorts, skips non-dart cites, lists unmapped files', () {
      final sel = buildSelection(
        changedPaths: ['lib/core/services/subscription_service.dart', 'lib/orphan.dart', 'test/scripts/a_test.dart', 'docs/x.md'],
        registryYaml: _registry,
        grepResults: {
          'subscription_service.dart': ['test/contracts/subscription_cqrs_behavioral_test.dart', 'test/widgets/paywall_test.dart', 'test/sql/notes.sql'],
          'orphan.dart': <String>[],
        },
      );
      expect(sel.fallbackReason, isNull);
      expect(sel.tests, [
        'test/contracts/subscription_cqrs_behavioral_test.dart',
        'test/contracts/subscription_cqrs_second_test.dart',
        'test/scripts/a_test.dart',
        'test/widgets/paywall_test.dart',
      ]);
      expect(sel.skippedNonDart, ['test/sql/notes.sql']);
      expect(sel.unmappedChanged, ['lib/orphan.dart']);
    });
    test('RED PATH: unreadable registry falls back to the whole contracts subset', () {
      final sel = buildSelection(changedPaths: ['lib/a.dart'], registryYaml: null, grepResults: {'a.dart': <String>[]});
      expect(sel.fallbackReason, isNotNull);
      expect(sel.tests, ['test/contracts/']);
    });
    test('RED PATH: a failed git grep (null result) falls back — uncertainty must not look like a clean sweep', () {
      final sel = buildSelection(changedPaths: ['lib/a.dart'], registryYaml: _registry, grepResults: {'a.dart': null});
      expect(sel.fallbackReason, isNotNull);
      expect(sel.tests, ['test/contracts/']);
    });
    test('docs-only change selects nothing and reports no fallback', () {
      final sel = buildSelection(changedPaths: ['docs/x.md'], registryYaml: _registry, grepResults: {});
      expect(sel.fallbackReason, isNull);
      expect(sel.tests, isEmpty);
      expect(sel.unmappedChanged, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails** — `flutter test test/scripts/contract_sweep_lib_test.dart` → compile error (lib missing).

- [ ] **Step 3: Write `scripts/contract_sweep_lib.dart`** (pure — no `dart:io` process calls; `dart:io` only if you need `Platform.pathSeparator`, and you do not)

```dart
// scripts/contract_sweep_lib.dart
//
// Pure selection logic for scripts/contract_sweep.dart (OI-220). Three unioned
// arms pick the contract tests a push range can have broken:
//   (a) registry  — changed path is a writer/reader `file:` of a concept in
//                   docs/sot_registry.yaml → its behavioral_test_path(s)
//   (b) content   — `git grep -l -F <key> -- test/` for each changed non-test
//                   file's basename (parent/basename for ubiquitous names)
//   (c) changed   — test/**_test.dart files in the range themselves
// Any arm whose INPUT is unreadable makes the whole selection fall back to
// the full test/contracts/ subset: uncertainty must never look like a clean
// sweep (feedback_green_check_input_set_width #47).

const ubiquitousBasenames = <String>{
  'index.ts', 'index.dart', 'main.dart', 'mod.ts', 'CLAUDE.md', 'README.md', 'pubspec.yaml',
};

const _docLike = <String>{'.md', '.txt'};

bool _isTest(String p) => p.startsWith('test/') && p.endsWith('_test.dart');
bool _isDocLike(String p) =>
    p.startsWith('docs/') || p.startsWith('memory/') || _docLike.any(p.endsWith);

String _basename(String p) => p.substring(p.lastIndexOf('/') + 1);

/// Arm (b) keys. Excludes tests (arm c) and doc-like files (no contract reads them by name).
Set<String> contentReferenceKeys(Iterable<String> changedPaths) {
  final keys = <String>{};
  for (final p in changedPaths) {
    if (p.startsWith('test/') || _isDocLike(p)) continue;
    final base = _basename(p);
    if (ubiquitousBasenames.contains(base)) {
      final parts = p.split('/');
      keys.add(parts.length >= 2 ? '${parts[parts.length - 2]}/$base' : base);
    } else {
      keys.add(base);
    }
  }
  return keys;
}

final _conceptRe = RegExp(r'^  - concept:\s*(\S+)');
final _fileRe = RegExp(r'^\s+file:\s*(\S+)');
final _btpRe = RegExp(r'^\s+behavioral_test_path(?:_[a-z0-9_]+)?\s*:\s*(.*)$');

String stripTrailingComment(String v) => v.replaceFirst(RegExp(r'\s+#.*$'), '').trim();

/// Arm (a). Block-walk mirrors check_sot_behavioral_test_paths.dart:66-113.
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
    if (_conceptRe.hasMatch(line)) { flush(); continue; }
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

Set<String> changedTestFiles(Iterable<String> changedPaths) => changedPaths.where(_isTest).toSet();

class SweepSelection {
  final List<String> tests;
  final List<String> skippedNonDart;
  final List<String> unmappedChanged;
  final String? fallbackReason;
  const SweepSelection({required this.tests, required this.skippedNonDart, required this.unmappedChanged, this.fallbackReason});
  static const fallbackTarget = 'test/contracts/';
}

/// [grepResults]: key → matching test files, or null when that grep FAILED
/// (exit >= 2). A missing key is treated as "not run" and also falls back.
SweepSelection buildSelection({
  required List<String> changedPaths,
  required String? registryYaml,
  required Map<String, List<String>?> grepResults,
}) {
  SweepSelection fallback(String why) => SweepSelection(
      tests: const [SweepSelection.fallbackTarget], skippedNonDart: const [], unmappedChanged: const [], fallbackReason: why);
  if (registryYaml == null) return fallback('docs/sot_registry.yaml unreadable');
  final keys = contentReferenceKeys(changedPaths);
  for (final k in keys) {
    if (!grepResults.containsKey(k)) return fallback('git grep not run for key `$k`');
    if (grepResults[k] == null) return fallback('git grep failed for key `$k`');
  }
  final selected = <String>{}..addAll(registryTestsFor(registryYaml, changedPaths.toSet()))..addAll(changedTestFiles(changedPaths));
  final perKeyHits = <String, bool>{for (final k in keys) k: false};
  for (final k in keys) {
    for (final f in grepResults[k]!) { selected.add(f); perKeyHits[k] = true; }
  }
  final tests = selected.where(_isTest).toList()..sort();
  final skipped = selected.where((f) => !_isTest(f)).toList()..sort();
  final unmapped = <String>[];
  for (final p in changedPaths) {
    if (p.startsWith('test/') || _isDocLike(p)) continue;
    final base = _basename(p);
    final key = ubiquitousBasenames.contains(base) ? contentReferenceKeys([p]).first : base;
    final registryHit = registryTestsFor(registryYaml, {p}).isNotEmpty;
    if (!registryHit && perKeyHits[key] != true) unmapped.add(p);
  }
  return SweepSelection(tests: tests, skippedNonDart: skipped, unmappedChanged: unmapped..sort());
}
```

- [ ] **Step 4: Run the lib tests** — `flutter test test/scripts/contract_sweep_lib_test.dart` → all green. Fix the lib, not the tests, until the assertions above hold verbatim.

- [ ] **Step 5: Write the failing e2e test** — `test/scripts/contract_sweep_e2e_test.dart`

Shape (fill every body; the `dartBinOf()` helper is copied verbatim from `cron_registry_snapshot_gate_test.dart:33-57`):

```dart
@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// dartBinOf() — copy from test/scripts/cron_registry_snapshot_gate_test.dart:33-57

/// Fixture: bare origin + clone with `main`, a lib file, a test that imports
/// it by package path, a minimal docs/sot_registry.yaml, and a stub `flutter`
/// that records its argv to $SWEEP_RECORD and exits $SWEEP_STUB_EXIT.
class _Repo { late String dir; late String stub; late String record; }

Map<String, String> _env({required String record, required String stubExit}) {
  final env = Map<String, String>.from(Platform.environment)
    ..removeWhere((k, _) => k.toUpperCase().startsWith('GIT_'));
  env['SWEEP_RECORD'] = record;
  env['SWEEP_STUB_EXIT'] = stubExit;
  return env;
}

// Stub: Windows → flutter.bat: "@echo off\r\necho %* > \"%SWEEP_RECORD%\"\r\nexit /b %SWEEP_STUB_EXIT%\r\n"
//       else    → flutter (chmod +x): "#!/bin/sh\necho \"$@\" > \"$SWEEP_RECORD\"\nexit \"$SWEEP_STUB_EXIT\"\n"

void main() {
  final repoRoot = Directory.current.path;
  final runner = '$repoRoot/scripts/contract_sweep.dart';
  final dartBin = dartBinOf();
  late _Repo r;

  setUp(() { /* build fixture: git init bare origin; clone; commit lib/a.dart + test/contracts/a_test.dart (imports package:x/a.dart) + docs/sot_registry.yaml (concept citing lib/a.dart → test/contracts/a_registry_test.dart, which also exists); push main; then a SECOND commit on main changing lib/a.dart (this is the "push range" origin/main..HEAD — do NOT push it). */ });
  tearDown(() { try { Directory(r.dir).deleteSync(recursive: true); } catch (_) {} });

  ProcessResult run(List<String> extra, {String stubExit = '0'}) => Process.runSync(
      dartBin, ['run', runner, '--flutter-bin', r.stub, ...extra],
      workingDirectory: r.dir, environment: _env(record: r.record, stubExit: stubExit),
      includeParentEnvironment: false, runInShell: true);

  test('selects the registry test AND the importing test for the changed lib file, and spawns flutter with them', () {
    final res = run([]);
    expect(res.exitCode, 0, reason: '${res.stdout}${res.stderr}');
    final argv = File(r.record).readAsStringSync();
    expect(argv, contains('test/contracts/a_test.dart'));
    expect(argv, contains('test/contracts/a_registry_test.dart'));
    expect(argv, contains('--exclude-tags golden'));
  });
  test('RED PATH: a failing flutter run fails the sweep', () {
    final res = run([], stubExit: '1');
    expect(res.exitCode, 1, reason: '${res.stdout}${res.stderr}');
  });
  test('--warn-only turns that same failure into exit 0 and still prints the verdict', () {
    final res = run(['--warn-only'], stubExit: '1');
    expect(res.exitCode, 0);
    expect('${res.stdout}${res.stderr}', contains('WARN'));
  });
  test('--dry-run prints the selection and never spawns flutter', () {
    final res = run(['--dry-run']);
    expect(res.exitCode, 0);
    expect(File(r.record).existsSync(), isFalse);
    expect(res.stdout, contains('test/contracts/a_test.dart'));
  });
  test('RED PATH: an unresolvable origin/main falls back to the whole contracts subset', () {
    Process.runSync('git', ['branch', '-D', '-r', 'origin/main'], workingDirectory: r.dir, runInShell: true);
    Process.runSync('git', ['remote', 'remove', 'origin'], workingDirectory: r.dir, runInShell: true);
    final res = run([]);
    expect(res.exitCode, 0, reason: '${res.stdout}${res.stderr}');
    expect('${res.stdout}${res.stderr}', contains('fallback'));
    expect(File(r.record).readAsStringSync(), contains('test/contracts/'));
  });
}
```

- [ ] **Step 6: Run it to verify it fails** — `flutter test test/scripts/contract_sweep_e2e_test.dart` → fails (runner missing).

- [ ] **Step 7: Write `scripts/contract_sweep.dart`**

```dart
// scripts/contract_sweep.dart
//
// Pre-push targeted SoT contract sweep (OI-220). NOT a check_* gate: the
// pre-commit + CI loops enumerate check_*.dart and would spawn flutter test
// at every commit. Wired ONLY in scripts/pre-push.sh, above the full suite,
// for every tier. Mutation-proven per rule 21 (see the plan-review record
// docs/plan-reviews/gate-integrity.md) — rule 24's ledger enumerates check_*
// only (gate_test_ledger_lib.dart:135-139) and would reject this key.
//
// Usage:
//   dart run scripts/contract_sweep.dart [--warn-only] [--dry-run]
//       [--range <a>..<b>] [--flutter-bin <path>]
// Exit: 0 when the selected tests pass (or --warn-only / --dry-run / nothing
// selected); otherwise flutter test's exit code. An internal error selects
// the FULL test/contracts/ subset (fail-safe to more testing, never none).

import 'dart:io';
import 'contract_sweep_lib.dart';

const _tag = '[contract-sweep]';

Map<String, String> _cleanEnv() => Map<String, String>.from(Platform.environment)
  ..removeWhere((k, _) => k.toUpperCase().startsWith('GIT_'))
  ..['TZ'] = 'Asia/Kolkata';

String? _arg(List<String> args, String flag) {
  final i = args.indexOf(flag);
  return (i >= 0 && i + 1 < args.length) ? args[i + 1] : null;
}

/// null ⇒ git failed (fallback). Exit 1 from `git grep` means NO MATCH, not failure.
List<String>? _gitLines(List<String> a, {bool noMatchIsEmpty = false}) {
  final r = Process.runSync('git', a, runInShell: true);
  if (r.exitCode == 0) {
    return (r.stdout as String).split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  }
  if (noMatchIsEmpty && r.exitCode == 1) return const [];
  return null;
}

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final dryRun = args.contains('--dry-run');
  final range = _arg(args, '--range') ?? 'origin/main..HEAD';
  final flutterBin = _arg(args, '--flutter-bin') ?? 'flutter';

  final changed = _gitLines(['diff', '--name-only', range]);
  final registryFile = File('docs/sot_registry.yaml');
  final registry = registryFile.existsSync() ? registryFile.readAsStringSync() : null;

  final SweepSelection sel;
  if (changed == null) {
    sel = buildSelection(changedPaths: const [], registryYaml: null, grepResults: const {});
    stdout.writeln('$_tag fallback: `git diff --name-only $range` failed (origin/main unresolvable?) -> ${SweepSelection.fallbackTarget}');
  } else {
    final keys = contentReferenceKeys(changed);
    final grep = <String, List<String>?>{for (final k in keys) k: _gitLines(['grep', '-l', '-F', k, '--', 'test/'], noMatchIsEmpty: true)};
    sel = buildSelection(changedPaths: changed, registryYaml: registry, grepResults: grep);
    if (sel.fallbackReason != null) stdout.writeln('$_tag fallback: ${sel.fallbackReason} -> ${SweepSelection.fallbackTarget}');
  }

  stdout.writeln('$_tag range=$range changed=${changed?.length ?? '?'} selected=${sel.tests.length}');
  for (final t in sel.tests) stdout.writeln('$_tag   run  $t');
  for (final s in sel.skippedNonDart) stdout.writeln('$_tag   skip $s (not a dart test)');
  for (final u in sel.unmappedChanged) stdout.writeln('$_tag   unmapped $u (no registry concept and no test references its basename)');

  if (sel.tests.isEmpty) { stdout.writeln('$_tag nothing selected -- OK'); exit(0); }
  if (dryRun) { stdout.writeln('$_tag dry-run -- not spawning flutter'); exit(0); }

  final r = Process.runSync(flutterBin, ['test', ...sel.tests, '--exclude-tags', 'golden'],
      environment: _cleanEnv(), includeParentEnvironment: false, runInShell: true);
  stdout.write(r.stdout);
  stderr.write(r.stderr);
  if (r.exitCode == 0) { stdout.writeln('$_tag OK -- ${sel.tests.length} file(s) green.'); exit(0); }
  final verdict = '$_tag ${warnOnly ? 'WARN' : 'FAIL'}: flutter test exit ${r.exitCode} on ${sel.tests.length} selected file(s).';
  stderr.writeln(verdict);
  exit(warnOnly ? 0 : r.exitCode);
}
```

⚠ `includeParentEnvironment: false` + `_cleanEnv()` keeps `PATH` (copied from the parent) so `flutter` still resolves; the stub test relies on `SWEEP_RECORD`/`SWEEP_STUB_EXIT` surviving the copy — they do, only `GIT_*` is removed.

- [ ] **Step 8: Run both test files** → green. Then `flutter analyze scripts/contract_sweep.dart scripts/contract_sweep_lib.dart test/scripts/contract_sweep_lib_test.dart test/scripts/contract_sweep_e2e_test.dart` → 0 warnings (analyzer warnings fail the push).

- [ ] **Step 9: Wire pre-push** — insert after `scripts/pre-push.sh:112` (`flutter analyze --no-fatal-infos`) and before the `# The local full suite MUST be invoked…` comment:

```sh

# Targeted SoT contract sweep (OI-220) -- runs for EVERY tier, above the full
# suite, so a contract regression surfaces in ~2 min instead of after a full
# run. `--warn-only || true` is the §4.11 baseline: the flip to hard-fail
# (after one clean batch) removes BOTH tokens. The Dart runner owns the
# `flutter test` spawn -- a literal `flutter test` on this line would be
# pinned to CI's invocation by test/scripts/pre_push_matches_ci_invocation_test.dart.
echo "[pre-push] contract sweep (targeted SoT contract tests, warn-only baseline)..."
"$DART_BIN" run scripts/contract_sweep.dart --warn-only || true
```

Then run the two pinning tests: `flutter test test/scripts/pre_push_matches_ci_invocation_test.dart test/contracts/hook_gate_placement_test.dart test/scripts/pre_push_analyze_always_e2e_test.dart test/scripts/dart_bin_resolver_test.dart` → green.

- [ ] **Step 10: Rider 3 — playbook section.** Append to `docs/playbook/common-pitfalls.md` a section `## Riverpod-3 widget-harness pitfalls (2026-09-19)` written from the CODE of `test/widgets/compass_redesign_test.dart`: GoogleFonts warmup (header `:1-20`), `tester.runAsync` for real I/O (`:647-650`), empty-box seeding (`:299-300`), and `UncontrolledProviderScope` — read how the file uses it and describe the trap it avoids; if the code shows no trap, omit it and say "not documented in source" in the commit body. Cite `test/widgets/compass_redesign_test.dart` line ranges you read. Match the existing section style (`:63-99` is the template).

- [ ] **Step 11: Mutate and run** (each must APPLY — `grep -c` the token — and leave the file compiling):
  1. `contract_sweep_lib.dart`: in `buildSelection`, replace `if (grepResults[k] == null) return fallback(...)` with `if (grepResults[k] == null) continue;` → expected red: the "failed git grep falls back" lib test (1).
  2. `contract_sweep_lib.dart`: `registryTestsFor` — change `_fileRe` to only match writers by requiring `writers` context, i.e. delete the `readers` hit path by making `if (f != null && changedPaths.contains(f.group(1))) hit = true;` read `if (f != null && false) hit = true;` → expected red: both registry tests + the union test (≥2).
  3. `contract_sweep.dart`: `exit(warnOnly ? 0 : r.exitCode)` → `exit(0)` → expected red: e2e "failing flutter run fails the sweep" (1).
  4. `contract_sweep.dart`: `noMatchIsEmpty: true` → `false` on the grep call → every key without a match now falls back → expected red: the e2e selection test's argv assertion (it would contain `test/contracts/` instead of the two files) (≥1).
  Restore after each (`git checkout -- <file>` is safe here ONLY because nothing else in the file is uncommitted — commit Steps 1–10 first, then mutate; memory `feedback_mistake_mutation_restore_discards_uncommitted_fixes`).

- [ ] **Step 12: Commit** (subject is `feat`, no diagnose-doc):

```bash
git add scripts/contract_sweep.dart scripts/contract_sweep_lib.dart scripts/pre-push.sh test/scripts/contract_sweep_lib_test.dart test/scripts/contract_sweep_e2e_test.dart docs/playbook/common-pitfalls.md
sh scripts/safe_commit.sh "feat(gates): contract_sweep -- pre-push targeted SoT contract tests, warn-only baseline (OI-220)

Three unioned arms (registry / content-reference / changed tests); any
unreadable input falls back to the whole test/contracts/ subset. Wired in
pre-push.sh above the full suite for every tier. Not a check_* gate by
design (loop enumeration; ledger enumerates check_* only).

Mutation-proven: 4 mutations, <N> tests reddened (details in the
plan-review record). Tests: test/scripts/contract_sweep_lib_test.dart,
test/scripts/contract_sweep_e2e_test.dart.

Rider: docs/playbook/common-pitfalls.md riverpod-3 widget-harness section."
```

Report back: branch, sha, exact mutation counts, `flutter test test/scripts/contract_sweep_*` totals, whether the e2e ran inside a wider run (`flutter test test/scripts/`) once.

---

### Task 2: OI-155 — typed, machine-checked Gate 33 allowlist + the six dormant gates

**Files:**
- Modify: `scripts/gate_scripts_wired_lib.dart` (add runner types + predicates)
- Modify: `scripts/check_gate_scripts_wired.dart:37-82` (typed allowlist), `:180-183` (live-line inference), and the loop that checks entries
- Modify: `scripts/pre-commit.sh:331,337` (delete two skip lines), `.github/workflows/test.yml` skip block (delete the same two)
- Modify: `.claude/commands/build-apk.md` (add Gate 14b section after Gate 14 at `:231-235`)
- Test: `test/scripts/gate_scripts_wired_runners_test.dart` (new, pure)
- Create: `docs/diagnoses/2026-09-19-six-gates-run-nowhere-allowlist-prose-<id>.md`

**Interfaces:**
- Produces (in the lib): `enum RunnerKind { file, loop, manual }`, `class GateRunner { final RunnerKind kind; final String target; final String reason; }` with const factories `GateRunner.file(path, reason)`, `GateRunner.loop('preCommit'|'ci', reason)`, `GateRunner.manual('OI-NNN', reason)`; `bool mentionsOnLiveLine(String content, String needle)`; `bool oiIsOpen(String boardText, String oiId)`; `List<String> runnerViolations({required String gate, required List<GateRunner> runners, required String? Function(String path) read, required Set<String> Function(String content) caseSkipsOf, required String? boardText})` — returns `[]` when EVERY runner is satisfied.

- [ ] **Step 1: §4.1.5 bug-history grep** — `grep -n "gate_scripts_wired\|allowlist\|runs nowhere\|Gate 33" docs/diagnoses/INDEX.md`; read matches; cite in `related_bugs:` (a9f2c6 is the known prior: the closes-oi bare-invocation misclassification recorded in the allowlist comment at `:81`).

- [ ] **Step 2: Write the failing lib tests** — `test/scripts/gate_scripts_wired_runners_test.dart`

```dart
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
"\$DART_BIN" run scripts/check_explicit.dart
''';

const _board = '''
## OI-165 — the arbiter 403s
- **Status**: OPEN
## OI-101 — runtime budget
- **Status**: CLOSED
''';

void main() {
  group('mentionsOnLiveLine', () {
    test('a comment-only mention is NOT live', () => expect(mentionsOnLiveLine(_preCommit, 'check_commented.dart'), isFalse));
    test('a case-skip line is NOT live', () => expect(mentionsOnLiveLine(_preCommit, 'check_skipped.dart'), isFalse));
    test('an explicit invocation IS live', () => expect(mentionsOnLiveLine(_preCommit, 'check_explicit.dart'), isTrue));
  });
  group('oiIsOpen', () {
    test('OPEN heading', () => expect(oiIsOpen(_board, 'OI-165'), isTrue));
    test('CLOSED heading', () => expect(oiIsOpen(_board, 'OI-101'), isFalse));
    test('absent heading', () => expect(oiIsOpen(_board, 'OI-999'), isFalse));
  });
  group('runnerViolations', () {
    String? read(String p) => p == 'scripts/pre-commit.sh' ? _preCommit : null;
    Set<String> skips(String c) => extractCaseSkips(c, caseSkipRegex);
    test('file runner satisfied by a live line', () {
      expect(runnerViolations(gate: 'check_explicit.dart', runners: [GateRunner.file('scripts/pre-commit.sh', 'x')], read: read, caseSkipsOf: skips, boardText: _board), isEmpty);
    });
    test('RED PATH: file runner whose only mention is a comment', () {
      final violations = runnerViolations(gate: 'check_commented.dart', runners: [GateRunner.file('scripts/pre-commit.sh', 'x')], read: read, caseSkipsOf: skips, boardText: _board);
      expect(violations, isNotEmpty);
    });
    test('RED PATH: file runner naming a file that does not exist', () {
      final violations = runnerViolations(gate: 'check_x.dart', runners: [GateRunner.file('.claude/commands/missing.md', 'x')], read: read, caseSkipsOf: skips, boardText: _board);
      expect(violations, isNotEmpty);
    });
    test('loop runner satisfied when the gate is absent from that file\'s case-skips', () {
      expect(runnerViolations(gate: 'check_explicit.dart', runners: [GateRunner.loop('preCommit', 'x')], read: read, caseSkipsOf: skips, boardText: _board), isEmpty);
    });
    test('RED PATH: loop runner for a gate the loop case-skips', () {
      final violations = runnerViolations(gate: 'check_skipped.dart', runners: [GateRunner.loop('preCommit', 'x')], read: read, caseSkipsOf: skips, boardText: _board);
      expect(violations, isNotEmpty);
    });
    test('manual runner satisfied by an OPEN OI', () {
      expect(runnerViolations(gate: 'check_live.dart', runners: [GateRunner.manual('OI-165', 'x')], read: read, caseSkipsOf: skips, boardText: _board), isEmpty);
    });
    test('RED PATH: manual runner citing a CLOSED OI must fail -- that is the forcing function', () {
      final violations = runnerViolations(gate: 'check_live.dart', runners: [GateRunner.manual('OI-101', 'x')], read: read, caseSkipsOf: skips, boardText: _board);
      expect(violations, isNotEmpty);
    });
    test('RED PATH: manual runner when the board is unreadable fails CLOSED', () {
      final violations = runnerViolations(gate: 'check_live.dart', runners: [GateRunner.manual('OI-165', 'x')], read: read, caseSkipsOf: skips, boardText: null);
      expect(violations, isNotEmpty);
    });
  });
}
```

- [ ] **Step 3: Run → fails** (symbols missing).

- [ ] **Step 4: Implement in `scripts/gate_scripts_wired_lib.dart`** (read the file first; keep `extractCaseSkips` + `caseSkipRegex` untouched):

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

/// True iff some line contains [needle] and is neither a comment (`#`-led,
/// after trimming) nor a case-skip line (`needle|\` / `needle)`).
bool mentionsOnLiveLine(String content, String needle) {
  for (final raw in content.split('\n')) {
    final line = raw.trim();
    if (!line.contains(needle)) continue;
    if (line.startsWith('#')) continue;
    if (RegExp(RegExp.escape(needle) + r'\s*(\|\\?|\))\s*$').hasMatch(line)) continue;
    return true;
  }
  return false;
}

final _oiHeading = RegExp(r'^## (OI-\d+) —', multiLine: true);

bool oiIsOpen(String boardText, String oiId) {
  final matches = _oiHeading.allMatches(boardText).toList();
  for (var i = 0; i < matches.length; i++) {
    if (matches[i].group(1) != oiId) continue;
    final end = i + 1 < matches.length ? matches[i + 1].start : boardText.length;
    final block = boardText.substring(matches[i].start, end);
    return RegExp(r'^- \*\*Status\*\*:\s*OPEN', multiLine: true).hasMatch(block);
  }
  return false;
}

List<String> runnerViolations({
  required String gate,
  required List<GateRunner> runners,
  required String? Function(String path) read,
  required Set<String> Function(String content) caseSkipsOf,
  required String? boardText,
}) {
  final out = <String>[];
  if (runners.isEmpty) out.add('$gate: allowlist entry declares no runner');
  for (final r in runners) {
    switch (r.kind) {
      case RunnerKind.file:
        final c = read(r.target);
        if (c == null) { out.add('$gate: runner file ${r.target} is unreadable'); break; }
        if (!mentionsOnLiveLine(c, gate)) out.add('$gate: ${r.target} never names it on a live (non-comment, non-case-skip) line');
        break;
      case RunnerKind.loop:
        final path = loopFiles[r.target];
        final c = path == null ? null : read(path);
        if (c == null) { out.add('$gate: loop `${r.target}` is not a known loop or its file is unreadable'); break; }
        if (!c.contains('scripts/check_*.dart')) { out.add('$gate: ${path} has no dynamic check_* loop'); break; }
        if (caseSkipsOf(c).contains(gate)) out.add('$gate: declared loop:${r.target} but $path case-skips it');
        break;
      case RunnerKind.manual:
        if (!RegExp(r'^OI-\d+$').hasMatch(r.target)) { out.add('$gate: manual runner must cite OI-NNN, got `${r.target}`'); break; }
        if (boardText == null) { out.add('$gate: manual:${r.target} but docs/audit/open_issues.md is unreadable (fail CLOSED)'); break; }
        if (!oiIsOpen(boardText, r.target)) out.add('$gate: manual:${r.target} but that OI is not OPEN on the board -- give the gate a real runner or re-file');
        break;
    }
  }
  return out;
}
```

- [ ] **Step 5: Run lib tests → green.**

- [ ] **Step 6: Rewrite `check_gate_scripts_wired.dart:37-82`** as `const _allowList = <String, List<GateRunner>>{ … }` with EXACTLY these entries (delete `check_unawaited_has_error_sink.dart` and `check_snapshot_contract.dart` — they get no entry):

```dart
  'check_apk_size_within_bounds.dart': [GateRunner.file('.claude/commands/build-apk.md', 'Needs an APK; /build-apk Gate 13.')],
  'check_apk_release_signed.dart': [GateRunner.file('.claude/commands/build-apk.md', 'Needs an APK + apksigner + JDK; /build-apk Gate 48.')],
  'check_hooks_installed.dart': [GateRunner.loop('preCommit', 'CI runners never run setup-hooks.sh, so .git/hooks is absent there by design; case-skipped in test.yml only.')],
  'check_plan_review_record_exists.dart': [GateRunner.file('.github/workflows/test.yml', 'P1.A keystone (§4.12) — dedicated `plan-review-record` CI job (fetch-depth:0); the shallow loops case-skip it.')],
  'check_razorpay_key_flavor.dart': [GateRunner.file('.claude/commands/build-apk.md', '.env.prod is gitignored; runs locally before a prod release only.')],
  'check_migrations_live.dart': [GateRunner.file('.claude/commands/build-apk.md', 'Management-API read of applied migrations; PAT file is absent in worktrees + CI (exits 0 SKIP); /build-apk Gate 14b.')],
  'check_onconflict_live_arbiter.dart': [GateRunner.manual('OI-165', 'Live rollback-txn SQL via Management API; 403s with the current PAT (OI-165). Runs nowhere until that OI names the token.')],
  'check_two_user_cross_account.dart': [GateRunner.manual('OI-165', 'Wrapper over check_onconflict_live_arbiter.dart; inherits its 403 (OI-165).')],
  'check_regression_catalog.dart': [GateRunner.file('scripts/pre-commit.sh', 'Explicit merge-commit invocation, not the auto-loop.')],
  'check_test_runtime_budget.dart': [GateRunner.manual('OI-101', 'Spawns the FULL `flutter test --reporter json`; re-arm-or-delete is OI-101 (founder scope call).')],
  'check_no_deferral_euphemism.dart': [GateRunner.file('scripts/pre-commit.sh', 'Scans the STAGED diff — meaningful only at pre-commit; explicit invocation after the loop.')],
  'check_closes_oi_cited.dart': [GateRunner.file('scripts/commit-msg.sh', 'Commit-msg gate; takes the message file as its REQUIRED argument (a9f2c6).')],
```

Then in `main()`: read `docs/audit/open_issues.md` (null if absent); replace the `if (_allowList.containsKey(script)) continue;` at `:179` with: if allowlisted → `unwired.addAll(runnerViolations(gate: script, runners: _allowList[script]!, read: (p) { final f = File(p); return f.existsSync() ? f.readAsStringSync() : null; }, caseSkipsOf: (c) => extractCaseSkips(c, caseSkipRegex), boardText: board)); continue;`. Replace `preCommitContent.contains(script)` / `workflowContent.contains(script)` at `:180,:182` with `mentionsOnLiveLine(preCommitContent, script)` / `mentionsOnLiveLine(workflowContent, script)`. Keep the `--warn-only` flag semantics exactly as they are (`:137`, `:241`).

- [ ] **Step 7: Un-dormant the two loop gates** — delete `check_unawaited_has_error_sink.dart|\` (`pre-commit.sh:331`) and `check_snapshot_contract.dart|\` (`:337`); delete the same two lines from the `test.yml` case block (`:236-249` region). Run `dart run scripts/check_unawaited_has_error_sink.dart; echo $?` and `dart run scripts/check_snapshot_contract.dart; echo $?` → both 0 (they will now run in every gate loop).

- [ ] **Step 8: build-apk Gate 14b** — after Gate 14 (`.claude/commands/build-apk.md:231-235`), add a `### Gate 14b — live migration parity (check_migrations_live)` section in the same shape as Gate 14, invoking `dart run scripts/check_migrations_live.dart` and stating: reads `supabase/.supabase/supabase access token.txt`; exits 0 SKIP when absent; run from the PRIMARY worktree (the token file is not copied into worktrees). Confirm `grep -c "check_migrations_live" .claude/commands/build-apk.md` → ≥1 on a non-comment line.

- [ ] **Step 9: Run the gate on the real tree** — `dart run scripts/check_gate_scripts_wired.dart; echo $?` → `PASS`, exit 0. If any entry fails, the ENTRY is wrong, not the check — fix the entry.

- [ ] **Step 10: Mutate and run** (commit Steps 1–9 first):
  1. lib: `mentionsOnLiveLine` body → `return content.contains(needle);` → expected red: 2 (`comment-only`, `case-skip`) + the two runnerViolations comment/loop red paths (≥3).
  2. lib: `oiIsOpen` → `return true;` → expected red: `CLOSED heading`, `absent heading`, the CLOSED-OI red path (3).
  3. lib: `RunnerKind.manual` branch `if (boardText == null)` → `if (false)` → expected red: the fail-CLOSED test (1) (verify the file still compiles: `boardText` is nullable so `oiIsOpen(boardText!, …)` — use `boardText ?? ''` in the mutant to keep it compiling).
  Also confirm the REAL gate would catch the class: temporarily edit `_allowList` to `GateRunner.manual('OI-101', …)` for a gate while OI-101 is OPEN on the board → PASS; then change the target to an OI that is CLOSED on the board (pick one from `docs/audit/closed_issues.md` — note `oiIsOpen` reads only `open_issues.md`, so a closed number is simply absent → violation) → FAIL exit 1. Restore.

- [ ] **Step 11: Diagnose-doc** — read `scripts/validate_diagnose_doc_lib.dart` first; copy the frontmatter of `docs/diagnoses/2026-09-18-safe-push-test-contention-window-f7a3b1.md`; `bug_id` = 6 hex you generate (`openssl rand -hex 3` or equivalent) and confirm `ls docs/diagnoses/ | grep <id>` → 0 first; `touched_layers_checked` rows: tier 1 client code `fixed_in_this_batch` (the gate + lib), tiers 3-12 `not_applicable` with one-line reasons, tier 12 client→server `not_applicable`. Writer/reader: writer = `_allowList` prose (`check_gate_scripts_wired.dart:37-82`), reader = nobody (that is the bug) → now `runnerViolations`. Validate: `dart run scripts/validate_diagnose_doc.dart docs/diagnoses/<file>` → OK.

- [ ] **Step 12: Commit**

```bash
git add scripts/gate_scripts_wired_lib.dart scripts/check_gate_scripts_wired.dart scripts/pre-commit.sh .github/workflows/test.yml .claude/commands/build-apk.md test/scripts/gate_scripts_wired_runners_test.dart docs/diagnoses/<file>
sh scripts/safe_commit.sh "fix(gates): Gate 33 allowlist declares typed runners and is machine-checked; the six dormant gates get real ones (OI-155)

unawaited_has_error_sink + snapshot_contract run in both loops (skip lines
removed; both exit 0 today). migrations_live -> /build-apk Gate 14b (new
section). onconflict_live_arbiter + two_user_cross_account -> manual:OI-165
(403 today). test_runtime_budget -> manual:OI-101. A manual runner must cite
an OPEN OI, so closing that OI turns this gate red until the gate gets a real
runner. Wiring inference now ignores comment-only mentions.

Mutation-proven: <N> mutations, <M> tests reddened (details in the
plan-review record). Tests: test/scripts/gate_scripts_wired_runners_test.dart.

closes-diagnose: <id>"
```

Report back: branch, sha, mutation counts, the gate's PASS line on the real tree, and the exact skip lines removed.

---

### Task 3: OI-195 — Gate 42 resolves every cited path

**Files:**
- Modify: `scripts/check_sot_behavioral_test_paths.dart:103-114` (value branch), `:128-129` (problems), `:146-164` (report), tally
- Test: `test/scripts/sot_behavioral_test_paths_gate_test.dart` (new, subprocess fixture)
- Create: `docs/diagnoses/2026-09-19-gate42-never-resolves-cited-test-path-<id>.md`

- [ ] **Step 1: §4.1.5 grep** — `grep -n "behavioral_test_path\|Gate 42\|presence_only" docs/diagnoses/INDEX.md`; cite matches (rule 21's `user_full_name` case is a known relative: Gate 42 green on a path that never executed the new code).

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

  ({int code, String out}) run([List<String> extra = const []]) {
    final r = Process.runSync(dartBin, ['run', gate, ...extra], workingDirectory: fx.path, runInShell: true);
    return (code: r.exitCode, out: '${r.stdout}${r.stderr}');
  }
  void write(String yaml) => File('${fx.path}/docs/sot_registry.yaml').writeAsStringSync(yaml);

  test('an existing path (with a trailing comment) passes', () {
    write(_registry(path: 'test/contracts/real_test.dart'));
    final r = run();
    expect(r.code, 0, reason: r.out);
  });
  test('RED PATH: a behavioral_test_path that does not exist fails strict', () {
    write(_registry(path: 'test/contracts/ghost_test.dart'));
    final r = run();
    expect(r.code, 1, reason: r.out);
    expect(r.out, contains('ghost_test.dart'));
  });
  test('--warn-only downgrades the same miss to exit 0 with WARN', () {
    write(_registry(path: 'test/contracts/ghost_test.dart'));
    final r = run(['--warn-only']);
    expect(r.code, 0, reason: r.out);
    expect(r.out, contains('WARN'));
  });
  test('RED PATH: a sibling behavioral_test_path_<suffix> key is resolved too', () {
    write(_registry(path: 'test/contracts/real_test.dart', extra: '    behavioral_test_path_cqrs: test/contracts/missing_second_test.dart'));
    final r = run();
    expect(r.code, 1, reason: r.out);
  });
  test('RED PATH: presence_only prose citing a repo path that does not exist fails', () {
    write('''
concepts:

  - concept: beta
    presence_only: true # covered by test/sql/nope.sql
    writers:
      - file: lib/b.dart
        line_range: 1-2
''');
    final r = run();
    expect(r.code, 1, reason: r.out);
    expect(r.out, contains('test/sql/nope.sql'));
  });
  test('presence_only_reason block scalar citing an existing path passes', () {
    write('''
concepts:

  - concept: gamma
    presence_only: true
    presence_only_reason: |
      Static concept; pinned by test/contracts/real_test.dart instead.
    writers:
      - file: lib/c.dart
        line_range: 1-2
''');
    final r = run();
    expect(r.code, 0, reason: r.out);
  });
}
```

- [ ] **Step 3: Run → the two/three RED PATH tests fail** (exit 0 today), the pass tests pass.

- [ ] **Step 4: Implement** in `check_sot_behavioral_test_paths.dart`:
  - Widen the key regexes at `:103-104` to `behavioral_test_path(?:_[a-z0-9_]+)?`.
  - After computing `value`, `final path = value.replaceFirst(RegExp(r'\s+#.*$'), '').trim();` and, when the existing validity test passes, `if (!File('${Directory.current.path}/$path').existsSync()) missingFiles.add('$currentConcept: behavioral_test_path `$path` does not exist (registry line $lineNo)');` — declare `final missingFiles = <String>[];` beside the other sinks and track the line number in the loop.
  - Add a `presence_only` scan: on a line matching `^\s+presence_only\s*:\s*true` take the trailing comment; on `^\s+presence_only_reason\s*:\s*\|` collect the following more-indented lines; for each collected text, every match of `RegExp(r'\b(test|docs|scripts|supabase|lib)/[A-Za-z0-9_./-]+')` must exist, else `missingFiles.add('$currentConcept: presence_only cites `$p` which does not exist')`. Count EVERY `presence_only: true` line for the tally (fix the "7 carry" undercount).
  - `problems = [...staleRequired, ...missing, ...missingFiles]` at `:128-129`; add a `[file-missing]` block to the report at `:146-164` mirroring the parity gate's wording (`check_sot_registry_parity.dart:151-155`).
  - Run the gate on the REAL registry: `dart run scripts/check_sot_behavioral_test_paths.dart; echo $?` → PASS, exit 0, and the PASS line now says `17 carry presence_only: true` (re-derive with `grep -cE '^\s+presence_only:\s*true' docs/sot_registry.yaml`).

- [ ] **Step 5: Run the new test → all green.** `flutter analyze scripts/check_sot_behavioral_test_paths.dart test/scripts/sot_behavioral_test_paths_gate_test.dart` → 0 warnings.

- [ ] **Step 6: Mutate and run** (commit first): (1) delete the `existsSync` call (make it `if (false)`) → expected red: 3 RED PATH tests; (2) narrow the key regex back to `behavioral_test_path\s*:` → expected red: the sibling-key test (1); (3) drop the comment-strip → expected red: the passing trailing-comment test (1, it would now FAIL to find `real_test.dart  # …`). Record counts.

- [ ] **Step 7: Diagnose-doc** (validator first; frontmatter from the 2026-09-18 doc). Writer = `docs/sot_registry.yaml` `behavioral_test_path:` values (140 concepts); reader = Gate 42 `:103-114`, which read the field's SHAPE, never the file. `touched_layers_checked`: tier 1 `fixed_in_this_batch`; others `not_applicable`.

- [ ] **Step 8: Commit**

```bash
git add scripts/check_sot_behavioral_test_paths.dart test/scripts/sot_behavioral_test_paths_gate_test.dart docs/diagnoses/<file>
sh scripts/safe_commit.sh "fix(gates): Gate 42 resolves every cited behavioral_test_path and presence_only citation on disk (OI-195)

Comment-stripped values, sibling behavioral_test_path_<suffix> keys, and
repo-shaped paths inside presence_only prose / presence_only_reason blocks
must exist; strict -> exit 1, --warn-only -> exit 0. Tally now counts every
presence_only: true line (17, not 7).

Mutation-proven: 3 mutations, <M> tests reddened. Tests:
test/scripts/sot_behavioral_test_paths_gate_test.dart.

closes-diagnose: <id>"
```

Report back: branch, sha, mutation counts, the real-registry PASS line.

---

### Task 4: OI-181 — `safe_merge.sh` warns on an ABSENT plan-review record

**Files:**
- Modify: `scripts/safe_merge.sh` (insert after `:231`, before `:234`)
- Test: `test/scripts/safe_merge_test.dart` (add a fixture helper + 3 tests)
- Create: `docs/diagnoses/2026-09-19-safe-merge-silent-on-absent-record-<id>.md`

- [ ] **Step 1: §4.1.5 grep** — `grep -n "safe_merge\|plan-review record\|merge-without-record" docs/diagnoses/INDEX.md`; the 2026-08-30 precheck diagnose and OI-181's cited instances (`dcb94a93`, `0768a0ce`) go in `related_bugs:` / `recurrence:` (third instance).

- [ ] **Step 2: Write the failing tests** — append to `test/scripts/safe_merge_test.dart` (read `:1-60` and `:278-298` first; reuse `makeFeatureBranch`, `_run`, the fixture globals). Add a helper that copies the classifier into the fixture and commits it on `main`:

```dart
  /// The absent-record precheck classifies `main...BRANCH`; the fixture needs
  /// the real classifier + registry to do so (copyScripts copies only
  /// safe_merge.sh + _git_lock.sh — see :52-57).
  void installClassifier(String primary) {
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
    _git(['add', '-A'], primary);
    _git(['commit', '-q', '-m', 'fixture: classifier'], primary);
    _git(['push', '-q', 'origin', 'main'], primary);
  }

  /// A branch that adds ONE file at [path] and no plan-review record.
  /// Mirror the file's existing `makeFeatureBranch` (used at :429) line for
  /// line — same checkout/commit/checkout-main sequence and the same git
  /// helper it calls — parameterising only the added path.
  String makeBranchAdding(String primary, String name, String path) {
    // git checkout -b <name>; write <path> (createSync(recursive: true));
    // git add -A; git commit -q -m 'branch: <name>'; git checkout main; return name
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
    // main moves: a migration lands on main AFTER the cut
    File('$primary/supabase/migrations/901_main_only.sql').createSync(recursive: true);
    _git(['add', '-A'], primary); _git(['commit', '-q', '-m', 'main: migration'], primary); _git(['push', '-q', 'origin', 'main'], primary);
    final r = _run('sh', ['scripts/safe_merge.sh', branch], primary);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect('${r.stdout}${r.stderr}', isNot(contains('NO plan-review record')), reason: 'two-dot would classify main-only changes as the branch\'s');
  });
```

- [ ] **Step 3: Run → the RED PATH test fails** (no warning today); the other two pass vacuously — that is expected and is exactly why mutation 2/3 below exist.

- [ ] **Step 4: Insert the block** after `scripts/safe_merge.sh:231` (`fi`) and its `# ------` line, before `echo "[safe_merge] main is caught up …"`:

```sh
# ABSENT-RECORD PRECHECK (OI-181) -- advisory; every failure path stays silent.
# Mirrors check_plan_review_record_exists.dart:617-620 + :790-796: a record is
# required iff the branch's blast-radius is >= account. Three-dot (merge-base)
# because the merge commit does not exist yet; --no-renames + quotePath=false
# mirror the gate's own diff flags (its :309-315). The gate's exemptions
# (dependabot manifest-only, bare version bump) are deliberately NOT mirrored:
# 0768a0ce was a version bump and the gate still failed it.
if [ -z "${_REC_CONTENT:-}" ] \
   && git rev-parse --verify --quiet "refs/heads/${BRANCH}" >/dev/null 2>&1 \
   && [ -r "$REPO_ROOT/scripts/blast_radius_from_diff.dart" ] \
   && [ -r "$REPO_ROOT/docs/blast_radius.yaml" ]; then
  _PRE_DART="dart"
  if [ -r "$REPO_ROOT/scripts/_dart_bin.sh" ] && sh -n "$REPO_ROOT/scripts/_dart_bin.sh" 2>/dev/null; then
    . "$REPO_ROOT/scripts/_dart_bin.sh" || true
    _PRE_DART="$(resolve_dart_bin 2>/dev/null || echo dart)"
  fi
  _PRE_PATHS="$(git -c core.quotePath=false diff --no-renames --name-only "main...refs/heads/${BRANCH}" 2>/dev/null || true)"
  _PRE_TIER=""
  if [ -n "$_PRE_PATHS" ]; then
    _PRE_TIER="$(printf '%s\n' "$_PRE_PATHS" \
      | "$_PRE_DART" run scripts/blast_radius_from_diff.dart - 2>/dev/null \
      | grep -oE 'Blast-radius: (feature|account|platform|catastrophic)' \
      | tail -1 | awk '{print $2}' || true)"
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

`sh -n scripts/safe_merge.sh` → clean. Note `. "$REPO_ROOT/scripts/_dart_bin.sh"` is a SOURCE, not an execution — the file's `case "$0"` guard does not fire when sourced.

- [ ] **Step 5: Run the whole file** — `flutter test test/scripts/safe_merge_test.dart` → 15/15 (12 + 3). The pre-existing `:426` silence test must stay green.

- [ ] **Step 6: Mutate and run** (commit first; confirm each with `grep -c`): (1) delete the whole block → expected red: RED PATH (1); (2) `account|platform|catastrophic)` → `*)` → expected red: feature-silent + three-dot (2); (3) `main...refs` → `main..refs` → expected red: three-dot (1). Record counts.

- [ ] **Step 7: Diagnose-doc** (validator first). Writer = the branch author (record on the branch); reader = `safe_merge.sh:208` (`if [ -n "$_REC_CONTENT" ]` — reads presence only to decide whether to LOOK, never to warn); mirror = keystone gate `:790-796`. `recurrence:` third instance. `touched_layers_checked`: tier 1 `fixed_in_this_batch`; others `not_applicable`.

- [ ] **Step 8: Commit**

```bash
git add scripts/safe_merge.sh test/scripts/safe_merge_test.dart docs/diagnoses/<file>
sh scripts/safe_commit.sh "fix(merge): safe_merge warns BEFORE the merge when a >= account branch has no plan-review record (OI-181)

Classifies main...BRANCH (three-dot) with the real classifier and mirrors the
keystone gate's >= account threshold; advisory, every failure path silent.
Third instance of merge-without-record (2026-08-30, 09-10, 09-18).

Mutation-proven: 3 mutations, <M> tests reddened. Tests:
test/scripts/safe_merge_test.dart (+3, now 15).

closes-diagnose: <id>"
```

Report back: branch, sha, mutation counts, `safe_merge_test.dart` total.

---

### Task 5: Integration (coordinator, inline)

**Files:** `CLAUDE.md`, `docs/audit/gate_test_ledger.yaml`, `docs/audit/open_issues.md`, `docs/audit/gate-integrity.closure.yaml`, `docs/plan-reviews/gate-integrity.md`, `docs/reviews/<sha>-bpass.md`, `.claude/skills/code-review/SKILL.md` (tuning entry, gated).

- [ ] **Step 1: Cherry-pick** each fork's commit(s) onto `gate-integrity` in order Task 1 → 4 (`git cherry-pick <sha>`; cherry-pick runs no pre-commit hook — the gates already ran on each branch; `check_commit_from_worktree` exempts `CHERRY_PICK_HEAD`). `git log --oneline -6` shows spec + 4 unit commits.
- [ ] **Step 2: Verify each fork's mutation claims** by re-running ONE mutation per unit yourself (the cheapest one listed) — trust but verify (§4.9 subagent-numeric rule).
- [ ] **Step 3: Ledger** — promote `check_gate_scripts_wired.dart` (`gate_test_ledger.yaml:343`) and `check_sot_behavioral_test_paths.dart` (`:486-487`) from `grandfathered:` to `mutation_proven: true` + `test_path:` (LIST) + `evidence:` (what was neutered, counts) — shape from `:596-`. Run `dart run scripts/check_gate_test_ledger.dart` → PASS. `GATE_INDEX.md` regenerates at commit.
- [ ] **Step 4: CLAUDE.md** (D15): §0 pre-push row → add the sweep step and its warn-only state; §4.1.5 → item 6: *"Value-semantics grep (pre-work): a batch that changes a stored value's MEANING sweeps `test/` AND `supabase/functions/` for that value BEFORE coding (codified 2026-09-18 in code-review tuning; #47)."*; §4.12.7 → *"Execution mode (subagent vs inline) is decided and written into the plan at batch START, never mid-batch (OI-220 rider 2)."*; rule 21 → Gate 42 "STRICT by default and now RESOLVES every cited path on disk (OI-195, 2026-09-19)" + replace "6 entries carry it today" with the re-derived count and the command; §7 → new row for `contract_sweep` (what it selects, warn-only until the flip, not a check_*, mutation-proven per rule 21 with counts) and update the safe_merge row (absent-record precheck + `safe_merge_test.dart` count re-run, not eyeballed). Then `dart run scripts/check_claude_md_citations.dart` + `check_no_deferral_euphemism.dart --help` (it runs on the staged diff at commit).
- [ ] **Step 5: Board** — OI-155, OI-195, OI-181 → `- **Status**: CLOSED` with a one-line closing note each (move to `closed_issues.md` per the board's convention — read `open_issues.md:1-40` for it); OI-220 stays OPEN, `Blocked on:` rewritten to the flip criterion (D6) and a `Shipped:` line naming the commit. The commit carrying the status flips MUST have `closes-oi: OI-155`, `closes-oi: OI-195`, `closes-oi: OI-181` lines (`check_closes_oi_cited.dart`).
- [ ] **Step 6: Closure YAML** `docs/audit/gate-integrity.closure.yaml` — read `scripts/validate_audit_closure.dart:1-60` FIRST; shape from `unitb-deload-reason.closure.yaml`; entries: U1 OI-220 build (`closed_in_commit`, `commit: gate-integrity@branch`, `notes:` "shipped warn-only per §4.11/OI-220's own criterion; flip tracked on OI-220"), U2 OI-155 (`closed_in_commit`), U3 OI-195 (`closed_in_commit`), U4 OI-181 (`closed_in_commit`), plus one entry per B-pass finding after Step 8; `closed_count:` recomputed. `dart run scripts/validate_audit_closure.dart --strict` → PASS.
- [ ] **Step 7: Gate loop** — commit Steps 3–6 as `docs(gates): ledger promotions, CLAUDE.md riders, board + closure ledger for gate-integrity` with the three `closes-oi:` lines. The commit IS the gate loop (§4.12.5).
- [ ] **Step 8: B-pass** — `/code-review` on the branch (platform ⇒ mandatory, self-initiated). Fix findings in-branch; add each to the closure YAML; the skill-tuning gate requires a same-dated entry in `.claude/skills/code-review/SKILL.md`.
- [ ] **Step 9: Plan-review record** `docs/plan-reviews/gate-integrity.md` — READ `memory/feedback_gates_unsatisfiable_at_merge.md` + `feedback_plan_review_record_frontmatter_format.md` first. Frontmatter: `branch: gate-integrity`, `review_rounds: 2`, `mechanical_only: false`, `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted`, `bpass_review: docs/reviews/<file>`, `tier: standard`, `date: 2026-09-19`. Body: rounds, findings, fixes, the four mutation ledgers (unit × mutation × reds). Commit it on the branch BEFORE the merge; `sh scripts/safe_merge.sh gate-integrity` from the primary will now preview both the absent-record and the `bpass_review` checks — the new precheck must be SILENT for this branch.
- [ ] **Step 10: Full-suite scope** — the merge to `main` and push run pre-push at platform tier (full `flutter test`) + CI. Run the four new/extended test files inside `flutter test test/scripts/` once before the push (contention check, §4.9). Ask the founder before `safe_merge.sh` + `safe_push.sh`.
- [ ] **Step 11: §5 close-out** — retrospective `project_gate_integrity_2026_09_19.md`; in-flight memory → archived line; worktree retirement dry-run; context-artifact budget check; skill self-evolution answered.
