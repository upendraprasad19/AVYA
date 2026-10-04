---
reviewed_at: 2026-08-11T22:05:00+05:30
staged_against: 71fcdac3b4b9
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 2
verdict: accepted
---

# Code Review — 71fcdac3b4b9

B-pass over the commit-time gate cost split (ADR-0018): `flutter analyze` + `flutter test
test/contracts/` moved off `scripts/pre-commit.sh`; unconditional `flutter analyze` added to
`scripts/pre-push.sh` above every early exit.

Dispatched context-blind to a fresh Sonnet agent per `.claude/skills/code-review/SKILL.md` §3.
Both findings below were **independently reproduced by the author before being acted on** —
subagent claims are hypotheses until the mutation is re-run locally
(`feedback_audit_verifier_cannot_trust_own_subagent`).

## Finding 1 — P1 — guard_without_its_mirror

- **file:line:** `test/contracts/hook_gate_placement_test.dart:37` (the `_flutterCall` regex)
- **claim:** The pre-commit half was pinned only by a SOURCE GREP, which cannot see through
  indirection. Re-introducing the regression via a variable-built subcommand in the `else`
  branch — `_sub="ana""lyze"; flutter "$_sub" --no-fatal-infos` — runs `flutter analyze` on
  every commit and leaves the entire suite **GREEN**. No regex closes this class; only observing
  the actual invocation does. This is the third distinct escape found in this guard (round 1:
  calls restored into the `else` body; round 2: `flutter  analyze` double-spaced), and unlike
  those two it is not fixable by tightening the matcher.
- **verification:**
  ```
  # with the indirect call in the else branch of scripts/pre-commit.sh:
  flutter test test/contracts/hook_gate_placement_test.dart      # +8: All tests passed  (blind)
  flutter test test/scripts/pre_commit_lean_path_e2e_test.dart   # +3 -1: Got: [analyze --no-fatal-infos]
  ```
- **suggested-fix:** add a RUNTIME e2e test that executes the real hook with a stub `flutter` on
  PATH and asserts the default path invokes nothing.
- **status:** accepted — fixed in-batch. New file
  `test/scripts/pre_commit_lean_path_e2e_test.dart` (4 tests), registered in
  `test/contracts/gate_e2e_env_hermetic_test.dart`. It runs in ~2s per scenario because the stub
  `dart` exits 1, aborting the hook at its first gate — which sits below the hatch chain, so the
  chain has already executed. The three hatch scenarios double as the premise guard that makes
  the default path's empty log evidence rather than a vacuous pass. **Mutation-proven: the
  indirect call reddens it while the grep stays green** (output above).

## Finding 2 — P2 — blast_radius_mismatch

- **file:line:** `docs/blast_radius.yaml:31` (platform `requires:`) vs the batch as a whole
- **claim:** Platform tier requires `[regression_test, behavioral_test_path, code_review_b_pass,
  feature_flag]`. The first three are satisfied; **`feature_flag` is not addressed anywhere** in
  the diff. Note the keystone gate `check_plan_review_record_exists.dart` never reads
  `feature_flag`, so this is a registry-level requirement with no machine enforcement — it can
  pass CI while being unmet, which is precisely why it needs a written disposition.
- **verification:** `grep -n "feature_flag" docs/blast_radius.yaml scripts/check_plan_review_record_exists.dart`
- **suggested-fix:** either ship dark behind a default-OFF flag (§4.12.4), or record an explicit
  founder-ratified disposition explaining why not.
- **status:** accepted — resolved as a **documented deviation, not a claim of compliance**.
  ADR-0018 gained an *"On platform tier's `feature_flag` requirement"* section: ship-dark was
  considered and rejected (the saving *is* the change, so a dark ship buys nothing until a flip
  that needs the full ×2 review anyway); `PRE_COMMIT_LEGACY=1` is a rollback switch, explicitly
  NOT a §4.6 feature flag, and the section says so; and the failure mode here is weaker gating,
  not user-data corruption — no `lib/` runtime path is touched.

## Lens coverage

1. **writer_reader_drift** — CLEAN. `git diff --cached | grep -in "hive\|supabase\.\|\.from('"`
   returns only unmodified context lines. No Hive or Supabase code paths in the diff; it is shell
   hooks, CI YAML, docs and tests.
2. **function_exception_swallow** — CLEAN. `git diff --cached | grep -in "functions.invoke"` → 0
   matches.
3. **blast_radius_mismatch** — tier confirmed `platform` via
   `git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -`. Three of
   four `requires:` satisfied; the fourth is Finding 2. The diff changes no tier assignment and
   does not touch `blast_radius_from_diff.dart`.
4. **secrets_in_tree** — CLEAN.
   `git diff --cached | grep -inE "sk-|rzp_live_|AKIA[0-9A-Z]{16}|-----BEGIN|api[_-]?key\s*=|password\s*=|secret\s*=|token\s*="`
   → 0 matches.
5. **unawaited_no_error_sink** — CLEAN. `git diff --cached | grep -in "unawaited("` → 0 matches.
6. **guard_without_its_mirror** — the load-bearing lens for this diff; six mutations attempted
   (table below). One escape → Finding 1. One asymmetry noted and NOT filed: `pre-push.sh`'s
   `PRE_PUSH_FULL` has no malformed-value warning mirroring the new `PRE_COMMIT_*` warning loop.
   Judged P3 and left alone deliberately — the failure mode is a silent fallback to the *tiered*
   behaviour (the safe default), not a cost regression, and adding a second warning loop to a
   hook whose whole point is now speed is not obviously worth it. Recorded so it is a decision
   rather than an oversight.

## Additional checks (outside the 6 lenses)

- `sh -n` clean on `pre-commit.sh`, `pre-push.sh`, `setup-hooks.sh`. No bashisms.
- `eval "_v=\${$_hatch:-}"` probed with a payload containing `$(touch …)`: no injection —
  assignment-context parameter expansion is not re-evaluated. Also `set -e`-safe (the `[ … ]`
  test is a condition, so a false result does not abort).
- Hatch matrix verified live for all five permutations (none / LEGACY / FULL / both / `=true`):
  default silent, both-set yields FULL (the stronger gate), `=true` warns and stays lean.
- Factual claims re-verified against live state: `git ls-remote --heads origin` = 29 (28
  non-main); `gh pr list --state open` = 8; `test.yml` triggers = `push:[main,develop]` +
  `pull_request:[main,develop]`; `ls scripts/check_*.dart` = 86. All match what the diff asserts.
- Gates green against the staged tree: 32, 33 (96 scripts covered), 40, `validate_adr` on both
  changed ADRs, `check_doc_internal_consistency`, `check_no_deferral_euphemism`,
  `check_blast_radius_coverage`.
- All four index generators re-run → byte-identical to what is staged; no missing regen.

## Mutations attempted

| Mutation | Tests run | Result |
|---|---|---|
| Restore both flutter calls into the pre-commit `else` body, in place | hook_gate_placement | RED — caught |
| Unguarded `flutter analyze` above the hatch chain | hook_gate_placement | RED — caught |
| `flutter  analyze` (double space) in the `else` body | hook_gate_placement | RED — caught |
| **Indirect: `_sub="ana""lyze"; flutter "$_sub"` in the `else` body** | hook_gate_placement | **GREEN — escaped → Finding 1** |
| Same, after the fix | pre_commit_lean_path_e2e | RED — caught (`Got: [analyze --no-fatal-infos]`) |
| Move pre-push analyze fully below the feature-tier skip | hook_gate_placement + pre_push_analyze_always_e2e | RED — 3 caught (incl. `Got: []`) |
| Move pre-push analyze into the feature-tier branch only | hook_gate_placement + pre_push_analyze_always_e2e | RED — 2 caught |

## Founder triage notes

Both findings accepted and fixed in-batch per `feedback_no_deferrals.md`; nothing carried
forward. False-alarm rate 0/2.

The standout is Finding 1's class. Three separate escapes were found in one guard across three
review passes, and each fix was defeated by the next pass — a textbook
`feedback_mistake_guard_without_its_mirror` run (now 9 instances). The lesson that generalises:
**a source-grep guard is bounded by what its author can imagine writing.** The runtime test was
available the whole time and was skipped on a cost assumption (~22s) that turned out to be wrong
once the abort trick was found (~2s). Reach for the behavioural test first and only fall back to
a grep when execution genuinely cannot be observed.
