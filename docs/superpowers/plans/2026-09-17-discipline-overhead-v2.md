# Discipline Overhead Reduction v2 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut discipline-process overhead via S/M/L fix tiers, compile-gate, review convergence shortcut, grep-pin de-brittling, and batch telemetry — without weakening the judgment layer.

**Architecture:** S-tier = feature-tier UI surfaces only (classifier-defined, no gate bypasses added); M/L unchanged. Telemetry = one pure Dart lib + thin CLI, wired into the existing Stop hook. CLAUDE.md carries the process rules; no existing gate is weakened or bypassed.

**Tech Stack:** Dart (scripts + tests), Bash (pre-commit hook line), Markdown (CLAUDE.md).

**Spec:** `docs/superpowers/specs/2026-09-17-discipline-overhead-v2-design.md` (same worktree).

**Verified integration facts (do not re-derive):**
- `docs/blast_radius.yaml:321-324` — `lib/features/{profile,train,nutrition,home}/**` = feature-tier. `lib/features/{auth,ai_coach}/**` = account-tier (246-247). ⇒ S-tier surfaces = the feature-tier four; auth/ai_coach UI fixes are M by construction. **No change to `check_plan_review_record_exists.dart` is needed or permitted in this batch.**
- `scripts/validate_diagnose_doc_lib.dart:137-152` — validator needs `touched_layers_checked:` non-empty with ≥1 `verified|fixed_in_this_batch` row. The slim 2-row form passes. **No validator change.**
- `scripts/check_plan_review_record_exists.dart:819-826` — acceptance is `review_rounds >= 2` (1 for ship_dark_build). Convergence shortcut needs NO gate change: an all-mechanical round 2 converges the record at `review_rounds: 2` + `mechanical_only: true`. The flag is data for telemetry, not a gate input.

---

### Task 0: Preflight

**Files:** none modified.

- [ ] **Step 1: Confirm worktree + clean state**

Run (worktree: `.claude/worktrees/discipline-v2`):
```
git -C ".claude/worktrees/discipline-v2" branch --show-current
git -C ".claude/worktrees/discipline-v2" status --short
```
Expected: `discipline-v2`, empty status (spec is untracked — that's fine; it gets committed in Task 1).

- [ ] **Step 2: Re-verify the chronic-seven pin sites (commit hashes are pointers, not guarantees)**

```
git log --oneline -1 f4d771d2 97fc6594 f57e8339 df6f3922 ed4d5f05 d5686216 0f9033f3
```
Expected: all 7 resolve. If any is missing, re-locate by subject grep before Task 5 and note the replacement hash in the plan margin.

- [ ] **Step 3: Commit the spec**

```bash
cd ".claude/worktrees/discipline-v2"
git add docs/superpowers/specs/2026-09-17-discipline-overhead-v2-design.md docs/superpowers/plans/2026-09-17-discipline-overhead-v2.md
sh scripts/safe_commit.sh "docs(discipline): spec + plan for S/M/L tiering (overhead v2)"
```
Expected: commit lands, pre-commit gates green.

---

### Task 1: Telemetry pure lib — `scripts/batch_process_telemetry_lib.dart`

**Files:**
- Create: `scripts/batch_process_telemetry_lib.dart`
- Test: `test/scripts/batch_process_telemetry_lib_test.dart`

The lib is pure (takes strings, returns a report object) so tests need no fixtures on disk.

- [ ] **Step 1: Write the failing test**

```dart
// test/scripts/batch_process_telemetry_lib_test.dart
import 'package:flutter_test/flutter_test.dart';
import '../../scripts/batch_process_telemetry_lib.dart';

void main() {
  group('parsePlanReviewRecord', () {
    test('reads review_rounds, mechanical_only, tier from frontmatter', () {
      final report = parsePlanReviewRecord('''
---
branch: discipline-v2
review_rounds: 2
mechanical_only: true
verdict: converged
---
prose
''');
      expect(report.reviewRounds, 2);
      expect(report.mechanicalOnly, isTrue);
    });

    test('absent mechanical_only parses false; absent rounds parses 0', () {
      final report = parsePlanReviewRecord('---\nbranch: x\nverdict: converged\n---\n');
      expect(report.reviewRounds, 0);
      expect(report.mechanicalOnly, isFalse);
    });
  });

  group('parseEscapeLedger', () {
    test('counts open escapes, zero on empty ledger', () {
      expect(parseEscapeLedger('escapes: []\n').openEscapes, 0);
      expect(
        parseEscapeLedger('escapes:\n  - bug: a1b2c3\n    status: open\n  - bug: d4e5f6\n    status: closed_with_tightening\n')
            .openEscapes,
        1,
      );
    });

    test('unreadable ledger reports null, NOT zero (bad-news-vs-no-news)', () {
      expect(parseEscapeLedger('not: a ledger').openEscapes, isNull);
    });
  });

  group('composeReport', () {
    test('renders one line per section, no exception on empty inputs', () {
      final out = composeReport(
        record: const PlanReviewStats(reviewRounds: 2, mechanicalOnly: false),
        openEscapes: 0,
        recentDiagnoseDocs: 3,
        sTierDocs: 2,
        recentReviewFiles: 4,
      );
      expect(out, contains('review_rounds=2'));
      expect(out, contains('open_s_escapes=0'));
      expect(out, contains('s_tier_fixes=2/3'));
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

```
dart run test/scripts/batch_process_telemetry_lib_test.dart
```
(also acceptable: `flutter test test/scripts/batch_process_telemetry_lib_test.dart`)
Expected: FAIL — `batch_process_telemetry_lib.dart` not found.

- [ ] **Step 3: Write the lib**

```dart
// scripts/batch_process_telemetry_lib.dart
// Pure lib for batch-close process telemetry (§4.12.6 companion).
// Reads nothing from disk — callers pass contents. Pure => testable.
// Mirror-rule note: absent ledger => null (unknown), never 0 (bad-news-vs-no-news).

class PlanReviewStats {
  final int reviewRounds;
  final bool mechanicalOnly;
  const PlanReviewStats({required this.reviewRounds, required this.mechanicalOnly});
}

PlanReviewStats parsePlanReviewRecord(String content) {
  final scope = content.startsWith('---')
      ? content.split(RegExp(r'^---\s*\$', multiLine: true))[1]
      : content;
  int? field(String k) {
    final m = RegExp('^$k:\\s*(.+)\$', multiLine: true).firstMatch(scope);
    return m == null ? null : int.tryParse(m.group(1)!.trim());
  }

  return PlanReviewStats(
    reviewRounds: field('review_rounds') ?? 0,
    mechanicalOnly: RegExp(r'^mechanical_only:\s*true', multiLine: true).hasMatch(scope),
  );
}

/// Returns open-escape count; null when the content is not a parseable ledger.
int? parseEscapeLedger(String content) {
  if (!content.contains(RegExp(r'^escapes:', multiLine: true))) return null;
  return RegExp(r'status:\s*open', multiLine: true).allMatches(content).length;
}

String composeReport({
  required PlanReviewStats record,
  required int? openEscapes,
  required int recentDiagnoseDocs,
  required int sTierDocs,
  required int recentReviewFiles,
}) {
  final esc = openEscapes == null ? 'unknown' : '$openEscapes';
  return [
    'process-telemetry: review_rounds=${record.reviewRounds} '
        'mechanical_only=${record.mechanicalOnly}',
    'process-telemetry: open_s_escapes=$esc',
    'process-telemetry: s_tier_fixes=$sTierDocs/$recentDiagnoseDocs '
        'review_files_7d=$recentReviewFiles',
  ].join('\n');
}
```

- [ ] **Step 4: Run test to verify it passes**

```
flutter test test/scripts/batch_process_telemetry_lib_test.dart
```
Expected: PASS (all groups).

- [ ] **Step 5: Mutation-proof (rule 21/24) — mutate `status:\s*open` → `status:\s*closed`, rerun**

Expected: the ledger-count test REDDENS (count becomes 0 ≠ 1). Restore, rerun green. Record mutated-what + tests-reddened in the commit message.

- [ ] **Step 6: Commit**

```bash
git add scripts/batch_process_telemetry_lib.dart test/scripts/batch_process_telemetry_lib_test.dart
sh scripts/safe_commit.sh "feat(discipline): pure telemetry lib for batch-close process stats"
```

---

### Task 2: Telemetry CLI + Stop-hook wiring

**Files:**
- Create: `scripts/batch_process_telemetry.dart`
- Modify: `scripts/batch_close_hook.dart` (one guarded call — READ IT FIRST, its contract: every error path exits 0, once-per-HEAD)
- Test: extend `test/scripts/batch_close_hook_e2e_test.dart`

- [ ] **Step 1: Read the hook.** Note where it emits the checklist and how the kill switch + error paths are structured. The call must sit AFTER checklist emission, wrapped so ANY failure prints nothing and exits 0.

- [ ] **Step 2: Write the CLI**

```dart
// scripts/batch_process_telemetry.dart
// Batch-close process telemetry printer (called by batch_close_hook.dart).
// Reads: plan-review record for the current branch, escape ledger,
// diagnose docs from the last 7 days (count + tier: s_fix count),
// review files from the last 7 days. Print-only; never throws upward.
import 'dart:io';
import 'batch_process_telemetry_lib.dart';

Future<void> main() async {
  try {
    final git = await Process.run('git', ['rev-parse', '--show-toplevel']);
    if (git.exitCode != 0) return;
    final root = (git.stdout as String).trim();
    final branch = await Process.run('git', ['branch', '--show-current']);
    final branchName = (branch.stdout as String).trim();

    final record = File(
        '$root/docs/plan-reviews/${branchName.replaceAll('/', '-')}.md');
    final stats = record.existsSync()
        ? parsePlanReviewRecord(record.readAsStringSync())
        : const PlanReviewStats(reviewRounds: 0, mechanicalOnly: false);

    final ledger = File('$root/docs/audit/s_tier_escapes.yaml');
    final escapes = ledger.existsSync()
        ? parseEscapeLedger(ledger.readAsStringSync())
        : null;

    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    int diagnose = 0, sTier = 0, reviews = 0;
    for (final dir in ['docs/diagnoses', 'docs/reviews']) {
      final d = Directory('$root/$dir');
      if (!d.existsSync()) continue;
      await for (final f in d.list()) {
        if (f is! File) continue;
        final m = await f.lastModified();
        if (m.isBefore(weekAgo)) continue;
        if (dir.endsWith('reviews')) {
          reviews++;
        } else {
          diagnose++;
          if (f.readAsStringSync().contains(RegExp(r'^tier:\s*s_fix', multiLine: true))) {
            sTier++;
          }
        }
      }
    }

    // ignore: avoid_print
    print(composeReport(
      record: stats,
      openEscapes: escapes,
      recentDiagnoseDocs: diagnose,
      sTierDocs: sTier,
      recentReviewFiles: reviews,
    ));
  } catch (_) {
    // Telemetry must never break batch close.
  }
}
```

- [ ] **Step 3: Wire into `batch_close_hook.dart`** — after checklist emission:

```dart
try {
  await Process.run(Platform.resolvedExecutable,
      ['run', 'scripts/batch_process_telemetry.dart']);
} catch (_) {}
```
(If the hook's dart resolution differs, follow the file's own existing subprocess pattern; do NOT introduce a bare `dart` — see `scripts/_dart_bin.sh` lesson. If the hook never spawns processes, resolve dart the way `pre-commit.sh` does.)

- [ ] **Step 4: Extend the e2e test** — one test asserting telemetry output appears on stdout when a record file exists in the fixture repo, and that a corrupted record still exits 0. Follow existing fixtures in `batch_close_hook_e2e_test.dart`.

- [ ] **Step 5: Run the full hook test file + mutation-proof the wiring**

```
flutter test test/scripts/batch_close_hook_e2e_test.dart
```
Mutation: delete the telemetry call → wiring test reddens. Restore → green.

- [ ] **Step 6: Commit**

```bash
git add scripts/batch_process_telemetry.dart scripts/batch_close_hook.dart test/scripts/batch_close_hook_e2e_test.dart
sh scripts/safe_commit.sh "feat(discipline): batch-close telemetry wired into Stop hook"
```

---

### Task 3: Gate-failure persistence (one line in pre-commit.sh) + regenerable-paths entry

**Files:**
- Modify: `scripts/pre-commit.sh` (gate loop)
- Modify: `scripts/retire_worktree_lib.dart` (`regenerableIgnoredPaths`)

- [ ] **Step 1: In the gate loop's failure branch, add (before `continue`/exit logic — READ the loop first):**

```bash
echo "$(date +%s) $gate_script_name" >> "$(git rev-parse --absolute-git-dir)/../.claude/.gate_failures.log" || true
```
Use the variable the loop actually has for the gate name; `|| true` mandatory (a telemetry write can never fail a commit — same rule as `safe_push.sh`'s record writes).

- [ ] **Step 2: Add `.gate_failures.log` to `regenerableIgnoredPaths` in `retire_worktree_lib.dart`** (the b4d7e9 trap: any tool writing a gitignored file into a worktree owes this list an entry, or worktrees become unretirable). Extend `retire_worktree_lib_test.dart` accordingly.

- [ ] **Step 3: Run the retire tests + a real commit to see the log line appear**

```
flutter test test/scripts/retire_worktree_lib_test.dart
```

- [ ] **Step 4: Commit**

```bash
git add scripts/pre-commit.sh scripts/retire_worktree_lib.dart test/scripts/retire_worktree_lib_test.dart
sh scripts/safe_commit.sh "feat(discipline): persist gate failures for batch telemetry"
```

---

### Task 4: CLAUDE.md edits (§4.12.6 + pitfall row + slim template) + escape ledger

**Files:**
- Modify: `CLAUDE.md` (root)
- Create: `docs/audit/s_tier_escapes.yaml`

- [ ] **Step 1: Add §4.12.6 after §4.12.5** (exact text):

```markdown
6. **S/M/L fix tiering (discipline-overhead v2, 2026-09-17).** Three fix classes:
   **S** = diff touches ONLY feature-tier UI surfaces (`lib/features/{home,train,nutrition,profile}/**`
   — the classifier, not the agent, decides; auth/ai_coach UI is account-tier ⇒ M), ≤2 files,
   diff <100 lines, not a recurrence-class bug ⇒ NO ×2 plan review, B-pass SKIPPED; analyze
   `lib/` + targeted tests + slim diagnose doc only. **M** = everything not S/L ⇒ current
   pipeline + compile-gate (flutter analyze lib/ in the worktree BEFORE every reviewer
   dispatch; reviewer briefs declare compile-class findings out of scope). **L** =
   payment/auth/sync/schema/EF/plan-engine/CLAUDE.md ⇒ current pipeline UNCHANGED.
   Auto-escalation: any gate failure, seam symbol, or diff growth ⇒ M — the classifier and
   gates decide, never the fixing agent. Convergence shortcut: a plan-review round whose
   findings are ALL mechanical/citation-class closes the record with `mechanical_only: true`
   (self-attested, same trust model as §4.12.4); §4.12.5 split-and-ship stays the escalation
   for material findings. S-tier escapes are logged in `docs/audit/s_tier_escapes.yaml`; any
   P0/P2 escaping an S-fix triggers ONE evidence-based tightening, not reflex ceremony.
   S-class APK builds accumulate on main — the founder initiates builds, never per-fix by
   default.
```

- [ ] **Step 2: Amend the diagnose-doc rule (§4.5 row + rule 22)** — append one sentence to rule 22: "S-tier fixes (§4.12.6) use the slim template: symptom, writer+reader file:line, fix, test path; `touched_layers_checked` collapses to the UI + client-code rows (validator still satisfied). Recurrence-class bugs take the full template at ANY tier."

- [ ] **Step 3: Amend the source-grep brittleness pitfall row** — append: "**Conversion-on-touch (2026-09-17): any test or file:line citation touched in a batch gets converted to behavioral or wide-window (±40 lines) form in THAT batch. No global gate — a grep-detects-grep gate would be its own brittleness.**"

- [ ] **Step 4: Create the ledger**

```yaml
# docs/audit/s_tier_escapes.yaml
# S-tier escape ledger (§4.12.6). Any P0/P2 that escaped through an S-class fix
# gets one entry with an evidence-based tightening. status: open | closed_with_tightening.
escapes: []
```

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs/audit/s_tier_escapes.yaml
sh scripts/safe_commit.sh "docs(discipline): §4.12.6 S/M/L tiering + slim diagnose + conversion-on-touch"
```

---

### Task 5: Chronic-seven sweep

**Files (re-verify each against Task 0 Step 2 hashes before editing):**
- `test/contracts/proactive_coach_promotion_test.dart` (97fc6594 class)
- `test/contracts/streak_guardian_eligibility_test.dart` (f8a3c6 class)
- `docs/snapshot_contract.yaml` (line-shift class: `future_prediction`/`morning_alert` citations)
- the readiness_sheet part-of import test (d5686216 class — locate via `git show d5686216 --stat`)
- the usage-counters ledger census test (ed4d5f05 class)
- the swap-undo snackbar test (df6f3922)
- the cron-batch manifest test (f57e8339)

**Conversion rule (mechanical, applies to each):** for each line-anchored assertion (`expect(source.substring(...))`, exact-line index, or `lines[N]`), replace with EITHER (a) a behavioral assertion (execute/parse the unit and assert semantics), OR (b) a window search (`source.contains(RegExp(...))` over the whole file, or a ±40-line slice). Delete no assertion without adding its replacement — the assertion is still true, it moved.

- [ ] **Step 1 (per file): run the file's tests green on current code FIRST** (baseline)
- [ ] **Step 2 (per file): apply the conversion rule to the line-anchored pins**
- [ ] **Step 3 (per file): run the file's tests again — green**
- [ ] **Step 4 (per file): mutation-check ONE representative conversion per file**: delete the string the wide-window assertion looks for → test reddens → restore. (Rule 21: a test this batch wrote/extended must be seen to fail.)
- [ ] **Step 5: Commit all seven together**

```bash
git add test/contracts/ docs/snapshot_contract.yaml
sh scripts/safe_commit.sh "test(contracts): de-brittle the seven chronically-repinned tests (wide-window/behavioral)"
```

---

### Task 6: OI for the device-verification follow-up (design C)

- [ ] **Step 1:** `bash scripts/mint_oi.sh` — file OI: "Device verification expansion: Patrol flows for the UI-bug cluster (toast states, text overflow, empty states, double-pop), screenshot tests, canary APK" — body cites the Sept evidence (5-obs batch, ~60% product-bug cluster is founder-visible UI) and this spec.
- [ ] **Step 2: Commit** (board + index regen is automatic via pre-commit):
```bash
git add docs/audit/open_issues.md
sh scripts/safe_commit.sh "docs(audit): file OI for device-verification expansion (discipline v2 follow-up)"
```

---

### Task 7: Self-review gates, closure ledger, ×2 review, B-pass, merge, push

- [ ] **Step 1: Run the full gate loop on the working tree** — `sh scripts/pre-commit.sh` — fix everything it names before any review dispatch (§4.12.5).
- [ ] **Step 2: Closure ledger** — this is a ≥4-unit batch: write `docs/audit/2026_09_17_discipline_v2_closures.yaml` with per-entry `terminal_state:` (all `closed_in_commit:` with commit hashes) and run `dart run scripts/validate_audit_closure.dart <path>`.
- [ ] **Step 3: Plan review ×2** — dispatch TWO context-blind reviewers on this plan + the diff (brief prefix: `docs/agent_brief_preamble.md`); fix findings; record `docs/plan-reviews/discipline-v2.md` with `review_rounds: 2`, `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted` after the B-pass.
- [ ] **Step 4: B-pass** — `/code-review` skill over the staged diff; close findings in-batch.
- [ ] **Step 5: Merge + push from the PRIMARY worktree (integration-only rule):**
```bash
cd "C:/Upendra/Claude Code/Fitness App"
sh scripts/safe_merge.sh discipline-v2
sh scripts/safe_push.sh
```
- [ ] **Step 6: §5 checklist walk** (Stop hook will prompt) — including memory retrospective (`project_discipline_v2_tiering.md` replacing the in-flight file) and worktree retirement dry-run.
