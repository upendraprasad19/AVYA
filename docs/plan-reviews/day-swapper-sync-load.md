---
branch: day-swapper-sync-load
plan: docs/superpowers/plans/2026-09-26-day-swapper-sync-load.md
spec: docs/superpowers/specs/2026-09-26-day-swapper-design.md
review_rounds: 3
ground_truth_verified: true
verdict: converged
blast_radius: catastrophic
bpass: accepted
bpass_review: docs/reviews/day-swapper-sync-load-bpass.md
hermes: accepted
hermes_report: docs/audit/2026-09-28-hermes-day-swapper-sync-load.md
---

# Plan review — day swapper + sync-load (OI-237)

## Blast radius (Task 31, CLAUDE.md §4.9 bare `-` form)

Two runs, batch tier is the higher:
- `git diff --name-only origin/main...HEAD | dart run scripts/blast_radius_from_diff.dart -`
  (written files, base `origin/main` 7cb4eb78) → `platform`.
- The migration file classified where it exists (U1's worktree at the time, copied into a scratch
  worktree for this run since it is untracked by design until Task 34):
  `printf '%s\n' supabase/migrations/149_sync_noop_suppress_completed_guard_sync_epoch.sql | dart run
  scripts/blast_radius_from_diff.dart -` → `catastrophic` (the content rule substring-matches
  "SECURITY DEFINER" inside the migration's own header, in a sentence that says the guard function
  is NOT `SECURITY DEFINER` — see ruling in `.superpowers/sdd/2026-09-26-day-swapper-sync-load/progress.md`.
  Accepted as-is per that ruling: the SQL is not reworded to dodge the classifier).
- **Batch blast_radius: `catastrophic`.** Task 33 runs `/hermes-pass` and the plan-review record
  needs `hermes: accepted` before the merge (`check_plan_review_record_exists.dart` requires it at
  the `catastrophic` tier).

`bpass:` / `bpass_review:` and `hermes:` / `hermes_report:` were added by Task 33 once the
implementation existed (see "Post-implementation reviews" at the end).

**Method.** Every round was context-blind. Reviewers ran on Sonnet, at most four at once. The plan
is 1.37 MB, so each round was split into eight slices: Wave 0; U1–U3; U4; Tasks 13–16; Tasks 17–20;
Tasks 21–23; U5 + U6; Wave 3. Each slice carried the shared header (Global Constraints, §13
verification table, deviations, file ownership, execution model). Reviewers were told to verify
every claim against the code, `backups/live_schema_columns.json` and the gate scripts, never
against plan prose. Compile-class nits were out of scope. No live SQL was run by any reviewer.

## Round 1 — the drafted plan (16 findings: 2 P0, 8 P1, 6 P2)

Material findings, all fixed in the plan:
- **Task 29 cited three files no task creates** (P0 ×2, P1): two `day_swap_engine` reader rows and
  the invariant test path. Rewritten to the real Task 22/24/25/26 files. The same wrong test path
  sat in diagnose docs `d5a1e7` and `b6e1c8`, and was fixed there too; all six docs re-validated.
- **Task 16 wlog fingerprint could contain `DateTime.now()`** (P1): `_resolveCompletedAt`'s last
  resort made an unchanged row push on every pass. The resolver was split into
  `_resolveCompletedAtOrNull`, and unresolvable timestamps are now omitted.
- **Task 15 resolved the cloud template id before the skip** (P1): this violated spec §5.9/§14 and
  cost a SELECT per template per pass. The fingerprint now covers the LOCAL template ref, and
  resolution runs inside the push. Three cases are now explicit (recorded as D19).
- **Task 20's restore kill switch also disabled the `sync_epoch` lever** (P1): the two now work
  independently.
- **Task 21's `swap_merge_conflict` fired for completed rows** (P1): it now fires only for rows
  where something was discarded.
- **Task 26/27/28 test and citation defects** (P1 ×3): a `.notifier` on a plain Provider, a
  `String` passed as a `DateTime`, and a 1000-line citation drift.
- **Allowance replies can land out of order** (P2). Its round-1 fix was replaced in round 2.
- **Migration 148 (numbered 145 at round-1 time) was contested:** the in-flight templates batch
  (OI-252) held an uncommitted `145_workout_templates_stable_delete.sql` under the SAME number this
  batch's migration used at round 1. Task 1 Step 3 checked for it then; the collision recurred twice
  more as other batches landed 145/146/147 on `main` first (147 taken by
  `147_alert_client_errors_spike_breadth.sql`), so this migration became **148**, and then **149** at apply time: the live database already held
  `148_coach_extraction_locked_fields` from a branch not yet on `main`, which no tree-side check
  could see (`149_sync_noop_suppress_completed_guard_sync_epoch.sql`, ruling 2026-09-28,
  `.superpowers/sdd/2026-09-26-day-swapper-sync-load/wave3-carry.md`). This was found by the
  coordinator, not a reviewer.

## Round 2 — the hardened plan (21 findings: 1 P0, 7 P1, 13 P2)

Reviewers received the list of round-1 corrections and attacked them first. Two corrections had
introduced defects, both caught here:
- The Task 20 epoch fix made its sibling kill-switch test expect 2 fetches while the code made 3.
  The test now splits the fetches by `select=`.
- The round-1 allowance guard was a high-water mark, which would block a legitimate LOWER server
  count (an admin correction) for the rest of the week. It is now a per-request sequence, so only
  the newest in-flight reply writes.

New material findings, all fixed:
- **Task 29 `restore_type_derivation`** (P0): its prose contained a `hive_key_prefix: ""`
  literal, which Gate 9's regex reads as a non-empty prefix.
- **Migration 148's guard function was `public`** (P1): it moved to the `private` schema with a
  pinned `search_path`, following migrations 133 and 138. A post-apply `pg_namespace` check and a
  contract assertion were added.
- **Task 34 had no action when 148 is taken at apply time** (P1): a corrective procedure now keeps
  the founder go intact.
- **Task 27 widget test rendered free-tier copy** (P1): it now has a PRO override. The missing
  allowance import was also fixed (P1).
- **Task 1 Step 3 edited a diagnose doc not yet copied in** (P1): the edit now happens at the
  source.
- **Task 11 mutation list never exercised the new guard** (P1): mutations 8 and 9 were added.
- P2s taken: exlog `aborted` breaks and an exlog sink guard (matching nlog), D19, the harness
  filter warning, `repairRow` reuse, a `water_logs` trigger-limit note, and client-capabilities
  truncation documented.

## Round 3 — only the round-2 corrections (3 findings: 0 P0, 1 P1, 2 P2)

- **P1:** the apply-time rename used `git mv` on a file that is still untracked. Plain `mv` now.
- **P2:** the new exlog sink guard had no test. A test (owner switch after the summary write) and
  mutation 5 were added.
- **P2:** the `private` schema placement is now pinned by the migration contract test.
- Everything else was verified clean, including a step-by-step trace of the allowance sequence
  guard through Dart's synchronous-until-first-await semantics.

## Convergence

The round-3 findings were mechanical or test coverage only, with no new design issue. Rounds 2
and 3 each surfaced fewer and smaller findings than the round before (16 → 21 mostly-P2 → 3), so
the plan did not need to be split (§4.12.1). Review files: `review/r1_*.md`, `r2_*.md`, `r3_*.md` in
the planning session's scratchpad, and the correction lists `r1_changes.md` / `r2_changes.md`.

## Post-implementation reviews

- **B-pass (Task 33):** four context-blind Sonnet reviewers, 12 findings (0 P0, 4 P1, 5 P2,
  3 P3), 0 false alarms; 10 fixed in `2675345b`, 2 verified clean. Verdict accepted:
  `docs/reviews/day-swapper-sync-load-bpass.md`.
- **Hermes E-pass (Task 33, catastrophic tier):** seven Sonnet seats. The skill names Opus, but the
  founder's standing rule is Sonnet only, so Sonnet was used and the deviation is recorded in the
  report. 20 findings, 18 unique, all terminal in the closure ledger. Verdict accepted:
  `docs/audit/2026-09-28-hermes-day-swapper-sync-load.md`.
- **Merge resolution (origin/main 7cb4eb78, merge commit `735becbf`):** main moved 31 commits past
  the branch base while the batch ran. It was merged before remediation closed, so the fixes
  target the code that ships. One context-blind reviewer read the resolution against both parents:
  4 findings, all fixed (F1 in the merge commit, F2–F4 under diagnose `a3e7d9`). Verdict accepted:
  `docs/reviews/33fb1d332932-review.md`.
