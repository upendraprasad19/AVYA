---
bug_id: c3f9a7
date: 2026-08-13
batch: supabase-test-http
status: fixed
blast_radius: feature
symptom: >-
  The merge-commit regression walk (`scripts/check_regression_catalog.dart`)
  fails intermittently with a DIFFERENT number of failures each run — measured
  11, 7, 8, then 4 across four attempts on the same tree — blocking every merge
  commit. Every single failure is `TimeoutException after 0:00:30`; across all
  four runs there were ZERO assertion failures. The same test files run alone
  pass 38/38. Because the count varies and the tests are green in isolation, the
  natural reading is "flaky infrastructure, retry it", which is how a real red
  would get waved through.
concept: subprocess_test_timeout_under_suite_parallelism
sot_registry_entry: not_applicable
writers:
  - "scripts/check_regression_catalog.dart:56-64 — the WRITER of the load
     condition. Invokes `Process.run('flutter', ['test', ...dartPaths])` with NO
     `--concurrency` argument, so `flutter test` self-parallelises across the
     recent-window file list using its CPU-count default."
readers:
  - "test/contracts/git_safety_hook_integration_test.dart:115,122,128,191,197,204,223,237
     (pre-fix) — 8 tests declaring `Timeout(Duration(seconds: 30))`, plus :185 at
     60s. All 9 spawn real subprocesses."
  - "test/contracts/review_gate_staged_content_not_working_tree_test.dart (pre-fix)
     — 4 tests, 8 subprocess spawns, and NO timeout declaration at all, so all
     four inherited the package:test 30s default."
  - "test/contracts/blast_radius_content_rule_wired_all_scripts_test.dart:235 —
     already carried an explicit 120s for exactly this reason. Its 9 sibling
     tests inherited the 30s default."
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/contracts/git_safety_hook_integration_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >-
  Surveyed every test file that spawns a subprocess for its declared timeout.
  The repo's own convention for this class is already GENEROUS —
  test/scripts/claude_md_citations_letter_suffix_test.dart:29 uses
  `@Timeout(Duration(minutes: 3))` and test/scripts/gate_input_family_e2e_test.dart:27
  uses `minutes: 8`. Only 9 test files in test/ declare `@Timeout` at all. The
  30s values were the outliers for this workload, not the raise. Stated as
  known-exposure across the three files that actually failed, NOT a full census
  of every subprocess test in the suite.
proposed_fix: >-
  Raise the timeout to 2 minutes for the three subprocess-heavy contract files:
  9 per-test declarations in git_safety_hook_integration_test.dart (per-test
  values override a library annotation, so they had to be edited individually),
  and a library-level `@Timeout(Duration(minutes: 2))` on the other two so that
  a future subprocess test added there inherits it rather than rediscovering
  this. No assertion, fixture, or subprocess invocation is touched — only how
  long the harness waits.
regression_test_planned: >-
  None added, deliberately, and this is the honest limit of this fix. A test
  that proves "this test does not time out under suite-wide parallelism" would
  have to reproduce the whole loaded suite, which is precisely the expensive,
  nondeterministic condition being fixed. What IS checkable is the invariant
  that these files declare a non-default timeout, and that is visible in the
  source with a comment naming this bug id. Recorded as a limitation rather than
  papered over with a test that would pass whether or not the fix were present.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "All three files pass 38/38 with default parallelism after the change (exit 0). NOTE the input-set limit: three files together is a far lighter load than the full regression catalog that actually failed, so this proves the change breaks nothing — the catalog run at commit time is the real verification." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "The decisive evidence is what did NOT vary: across four failing runs (11/7/8/4 failures) every failure was TimeoutException and ZERO were assertion failures. A timeout raise can only turn a test green if its assertions were already passing and the clock ran out. Had even one been an Expected/Actual mismatch, this fix would have been wrong. Isolated serial run before any change: 38/38 pass, proving the assertions themselves are sound." }
impact_analysis: >-
  Two independent things had to be true for this to bite, and both were: the
  runner assumes it owns the machine (no concurrency bound), and CLAUDE.md §4.13
  mandates one worktree per session with sessions genuinely running in parallel
  — three were committing simultaneously when this was first hit. But the fourth
  attempt failed on a fully quiet machine (0 locks, 0 dart processes), which
  proves other sessions merely make it worse; the suite's own parallelism is
  sufficient to trigger it alone. That distinction matters: "wait for a quiet
  machine" is not a fix.
  The real cost is not the lost time. It is that a gate which reddens under load
  teaches its reader to discount red, and this one blocks merges specifically —
  the highest-stakes commit type, where §4.4 rule 20 forbids `--no-verify` and a
  reader under pressure most needs the signal to mean what it says. Same family
  as the two other signals hit the same day: a SIGKILLed gate printing the same
  `GATE FAIL` as a violated one, and `safe_commit.sh` logging to a fixed /tmp
  path shared across concurrent sessions.
related_bugs:
  - "d4f9b2 (2026-08-11) and a7e3c1 (2026-08-12) — same class one level up: a
     signal that cannot distinguish 'I could not complete' from 'this is broken'.
     There an empty ls-remote meant both 'ref absent' and 'probe failed', and a
     400 from a local mock was indistinguishable from a 400 from Supabase. Here a
     30s timeout is indistinguishable from a violated contract."
recurrence: >-
  Not a recurrence of any indexed bug — grepped docs/diagnoses/INDEX.md for
  TimeoutException / regression catalog / subprocess timeout: zero matches.
  Noted explicitly so a future audit can verify this was checked rather than
  assumed. It IS the third instance in three days of the broader
  bad-news-vs-no-news class (see related_bugs).
---

# A 30s timeout and a broken contract printed the same red

## What happened

Five consecutive merge attempts failed in the merge-commit regression walk, reporting
**11, then 7, then 8, then 4** failures on an unchanged tree. Every failure was
`TimeoutException after 0:00:30`. Not one was an assertion failure.

All of them landed in three files, and all three spawn real subprocesses — `git` plus
`dart run`, where every `dart run` boots a fresh VM (slow on Windows).

## Why the varying count is the diagnosis

A real regression fails the same way every time. A count that moves 11 → 7 → 8 → 4 on
identical code is measuring the machine, not the code. Running the same three files alone,
serially: **38/38 pass**.

## Mechanism

`check_regression_catalog.dart:56` runs:

```dart
Process.run('flutter', ['test', ...dartPaths], runInShell: true)
```

No `--concurrency`. `flutter test` therefore parallelises across the recent-window file
list at its CPU-count default. Stack subprocess-spawning tests against that and 30 seconds
is not enough to boot a VM, run a git fixture, and assert.

The first three failures happened while three sessions were committing at once, which
suggested cross-session contention. **The fourth failed on a completely quiet machine —
zero git locks, zero dart processes.** So concurrent sessions make it worse but are not
required. That kills "just wait for a quiet window" as a remedy.

## The fix, and why it is not a gate weakening

Timeout raised to 2 minutes across the three files. **No assertion, fixture, or subprocess
call is touched.**

The safeguard is in the evidence: across four failing runs there were **zero assertion
failures**. A timeout raise can only green a test whose assertions already passed and whose
clock ran out. Had even one failure been an `Expected/Actual` mismatch, this fix would have
been wrong — and it would have been visible.

The repo also already grants this class 3 and 8 minutes
(`claude_md_citations_letter_suffix_test.dart:29`, `gate_input_family_e2e_test.dart:27`).
30s was the anomaly.

## What is NOT fixed here

`check_regression_catalog.dart` still runs unbounded. Bounding it addresses the cause
rather than the symptom, but it slows every merge commit and touches gate machinery, so it
wants its own analysis rather than being folded into a batch about an HTTP mock. Filed on
the board with this diagnose id attached.
