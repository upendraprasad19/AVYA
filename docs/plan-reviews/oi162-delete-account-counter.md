---
branch: oi162-delete-account-counter
date: 2026-09-05
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/303c57af-review.md
---

# Plan-review record — OI-162 slice 1, the usage-counter ledger (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

⚠ **This file did not exist until the B-pass asked for it**, despite three plan-review rounds
and two review documents already sitting in the branch. Producing review artifacts is not the
same as producing THE artifact the gate reads — it is branch-keyed, needs `---` frontmatter,
and is checked at the merge commit in CI, where the repair is a `git reset --hard` unwind.
Recorded here rather than quietly fixed.

**Tier: `platform`, computed against the REAL file with content.** That distinction is the
subject of round 1's first blocking finding: `blast_radius_from_diff.dart` was run against a
path that did not exist on disk, so the `SECURITY DEFINER` content rule had nothing to read
and failed open to the path tier. Re-run after the migration existed:
`printf '%s\n' supabase/migrations/128_usage_counters.sql | dart run scripts/blast_radius_from_diff.dart -`
→ `Blast-radius: platform`. Not catastrophic ⇒ no Hermes pass.

## Review rounds

| Round | Scope | Verdict | Findings |
|---|---|---|---|
| 1 | the all-at-once design (`docs/audit/oi162-plan.md`) | **NOT CONVERGED** | 8 blocking |
| 1 (slice 1) | `oi162-slice1-plan.md` v1 | **NOT CONVERGED** | 2 blocking, 2 major, 4 minor |
| 2 | v2, hardened | **NOT CONVERGED** | 0 blocking, 2 major, 2 minor |
| 3 | v3, narrow confirmation | **CONVERGED** | 1 minor (fixed) |
| B-pass | the implementation @ `303c57af` | **accepted** | 7 (1 P1, 3 P2, 3 P3), 0 false_alarm |

Every finding from every round has a written disposition in
`docs/plan-reviews/oi162-round1-findings.md` — written because round 1's findings had existed
only in conversation, so a reviewer could not check the claim that they were all handled.

## The two decisions that shaped this slice

**Splitting.** The all-at-once plan drew 8 blocking findings, six of which were properties of
the CALL SITES rather than of the table. Slice 1 therefore lands the ledger with **zero call
sites**, which dissolves those six, drops the tier from `catastrophic` to `platform`, and
leaves the remaining work in units small enough to review. Slices 2-4 are enumerated with the
findings each owns.

**`SECURITY INVOKER`, not DEFINER.** Round 1's two blockers were both mine and both dissolved
by this one change: there is no DEFINER-mode function to escalate the tier, and EXECUTE can be
granted freely because **the guard is RLS, not the grant**. A function that cannot write is
not an escalation surface no matter who calls it. This is strictly stronger than the
revoke-based design it replaced, and it was verified by execution rather than argued.

## Ground truth verified

All against `dedsavbjuwgarrhphgnl`, before and after the apply:

- **Design, pre-apply, in a rolled-back transaction:** `service_role` writes and returns 1;
  `authenticated` and `anon` both refused `42501` **while holding EXECUTE**; 19 concurrent
  calls on one key returned exactly 1…19 with no lost updates.
- **Post-apply:** CASCADE FK (`confdeltype=c`), composite PK, `relrowsecurity` true with
  **0 policies**, both functions `prosecdef=false`, cron `usage_counters_retention_daily`
  active at 03:45 UTC owned by `postgres`.
- **Behaviour on the real objects:** 1, 2, 3 then `-1`; `p_limit = 0` returns `-1` on the
  FIRST call; retention deletes a stale windowed row and **keeps** the `'epoch'` row.
- **Cleanliness:** `usage_counters` re-confirmed at 0 rows; no probe objects left.
- **Ledger integrity:** the migration's sha256 matches
  `backups/applied_migrations.json` exactly (`36bb9ae7…`), re-verified after every mutation
  run — using `cp` to restore, never `git checkout`, for the reason in the B-pass finding 6.

## `feature_flag` — answered, not waived

`docs/blast_radius.yaml`'s platform tier lists `feature_flag` in `requires:`. No gate reads
it, so this is a written answer rather than a compliance claim.

**Inapplicable, and unusually clearly so: this slice has no behaviour to flag.** Nothing calls
`consume_quota`; no user-visible path changes; the kill switch for the whole thing is the
commented rollback block at the foot of the migration, which is safe to run in full while no
call site exists. The flag question becomes real in slice 2, where the first trigger starts
reading the new ledger — and that is exactly where §4.6 says the gate belongs.

## Residue

**None deferred.** All 8 + 8 + 6 + 1 + 7 findings across five review passes are closed, fixed,
or recorded as named invariants with the slice that owns them. Two invariants the database
does NOT enforce are written into the SoT entry where slices 2-4 will read them: one
`quota_key` means one call site and one limit literal; and the 7-day retention cutoff must be
raised by any slice introducing a window longer than a day.

**Owed at merge:** the `project_*.md` retrospective (§5), plus the OI board moving to reflect
that slice 1 has landed.

**Full-suite scope:** not run at time of writing. Targeted green = 30 tests across the four
batch files, `flutter analyze` clean on the new files, and the complete pre-commit gate loop
including Gate 9, Gate 31, Gate 42, SoT parity and the schema-column snapshot. Pre-push
(≥account) and CI are the full-suite gates and neither has executed.
