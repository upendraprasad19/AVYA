---
branch: claude/work-session-3rqcp5
date: 2026-08-07
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/62ab8735369f-review.md
---

# Plan-review record — OI backlog Unit 1 (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).
Platform tier because the branch edits root `CLAUDE.md` and
`supabase/functions/**` (`docs/blast_radius.yaml`), so it carries a B-pass. Not
catastrophic → no Hermes required.

## Scope

Three backlog items, one surface each:

- **OI-76** — the Profile notification subtitle counted PRO-locked keys a free
  user cannot toggle; the locked rows opened the paywall under a feature *id*
  where every sibling call site passes a display string; and (found while fixing
  those) all three Settings entry points pushed the route bare, defaulting a
  paying PRO user to `isPro: false` and showing them a lock.
- **OI-75** — `notification_preferences` had no `docs/sot_registry.yaml` entry.
- **OI-82** — `promote-community-item` called a Postgres RPC that has never
  existed, behind a guard that could not fire.

Diagnose-docs `a7e3d1` and `d5b8c2`; ledger
`docs/audit/oi_unit1_backlog.closure.yaml` (15/15 terminal); tests
`notification_pro_key_scoping_test.dart`, `paywall_feature_label_test.dart`,
`promote_community_vote_tally_test.dart`.

## Review round 1 — independent, context-blind

Dispatched against the ORIGINAL plan, which proposed all 7 actionable backlog
items in one session. It refuted or materially corrected claims on **six of the
seven**. The load-bearing catches:

- **OI-78 would have silently destroyed test coverage.** The plan asserted (from
  the board) that all three functions had a sole `service_role` caller.
  `test/edge_functions/pgvector_test.dart:83/151/191` signs in with
  `signInWithPassword` (role `authenticated`) and calls `match_memories`.
  Revoking `authenticated` makes Postgres return *"permission denied for function
  match_memories"* — and that test's catch matches on
  `e.toString().contains('function')`, which that message satisfies, so it would
  call `markTestSkipped`. CI green, three live-DB tests silently gone.
- **The §4.13 worktree exemption in the plan was invalid.** `git rev-parse
  --git-dir` == `--git-common-dir` — the primary worktree, exactly what
  `check_commit_from_worktree.dart` tests for. §4.13 pt 5 rejects the plan's
  "isolated single session" argument by name.
- **Four required artifacts were missing** from the plan: the closure ledger,
  `closes-oi:` citations, per-fix diagnose-docs, and the plan-review record you
  are reading.
- **The Flutter version was unpinned** ("stable"), where CI pins `3.41.4`.

## Review round 2 — independent, on the hardened plan

Ran against the post-round-1 plan, per §4.12.1 (corrections can introduce their
own defects). It disagreed with round 1 on one material point and was right:

- Round 1 called OI-78 a **production-breakage P0**. Round 2 enumerated every
  caller and established all three *production* callers are `service_role`; the
  real damage is the silent test-coverage loss, not an outage. Round 2's framing
  was adopted.
- Round 2 additionally measured **OI-91 as `platform`, not `feature`** (it touches
  `supabase/migrations/*.sql`, `_shared/**` and `scripts/`), and found its
  section-number mapping covers only 4 of the 10 numbers actually present.
- Round 2 caught that **Gate 42 is strict**, so OI-75's planned bare registry
  entry would have failed pre-commit — and that root `CLAUDE.md` §4.4 r21 still
  described the old WARN behaviour, which is *why* the plan proposed it. That
  stale rule text is corrected on this branch.

**Convergence:** the two rounds surfacing new material issues across six of seven
items is precisely §4.12.1's stated signal that the unit is too large. The scope
was cut to the three feature-tier items that are fully verifiable in this
environment, and the remainder given explicit terminal states in the ledger —
`upstream_blocked` with a named `blocker:` and `reopen_when:`, or
`blocked_on_user` with a `reason:`. No item is deferred; §4.2 bans that,
euphemisms included.

## Ground-truth verification

Every claim acted on was re-derived rather than inherited from the board:

| Claim | How verified |
|---|---|
| `community_votes_summary` does not exist | LIVE `pg_proc` across all schemas on `dedsavbjuwgarrhphgnl`, 2026-08-07 → 0 rows. The board's evidence was 2026-08-01; re-checked today. |
| The community surface is dormant | LIVE counts → 0 approve votes, 0 approved items, 0 promoted rows. This is why the closure claims a diagnosability fix, not a user-visible one. |
| `notification_preferences` has 6 EF readers | **FALSE — it is 10.** Six via `_shared/notification_prefs.ts`, four reading `snapshot_json` inline. Re-derived by grep. |
| §4.4 r19 keys server-side verification off the paywall id | **FALSE.** `showPaywallSheet` is display + telemetry only; r19 keys off `gateAndVerify`'s positional arg. Both appear together at `profile_content.dart:345-349`. |
| OI-88's allow-list entry needs removing | **FALSE — already removed 2026-08-05.** `check_god_screen_max_lines.dart:41-47` no longer lists the file. |
| Batch is `feature` tier | **FALSE — `platform`.** Measured with `blast_radius_from_diff.dart`, which also revealed that touching migration 101 for a one-line comment escalates to `catastrophic` (whole-file content rule matches its pre-existing "SECURITY DEFINER" text). That edit was backed out and folded into the OI-78 unit. |

Each fix was **negative-controlled by execution** — reverted, observed to fail,
restored, observed to pass — not asserted. Two defects in this batch's own work
were caught by the repo's gates and fixed: two out-of-bounds `line_range`
citations in the new registry entry (`sot_registry_completeness_test.dart`), and
a `sync_methods`/`restore_methods` list naming repository methods where Gate 11
requires `sync_service.dart` fan-out methods.

## Findings filed rather than absorbed

- **OI-96** — community promotion has two mechanisms (this cron and a cloud-only
  SECURITY DEFINER trigger, both threshold 10) and the trigger appears to starve
  the cron's copy step. Recorded UNPROVEN: with 0 votes ever cast it has never
  executed.
- **OI-97** — five PaywallSheet labels fall through to generic copy, including a
  `'Weekly AI Report'` / `'AI Weekly Report'` word-order near-miss.
- **OI-98** — `notification_preferences` is push-only. Nothing reads it back, so a
  reinstall emits all-enabled and **overwrites** the server's stored copy. Found
  because Gate 11 demanded a `restore_methods:` list and there was nothing
  truthful to put in it.

## Tooling defect fixed on this branch

`scripts/pre-commit.sh` and `scripts/pre-push.sh` invoked `flutter` while git's
hook environment leaked `GIT_DIR`/`GIT_WORK_TREE`. Those override even `git -C`,
so `flutter` — which derives its version by running `git -C "$FLUTTER_ROOT"` —
read THIS repo instead of the SDK, reported `0.0.0-unknown`, and failed
dependency resolution with *"depends on integration_test from sdk which doesn't
exist"*: a message pointing at `pubspec.yaml` rather than the actual cause. Both
hooks now wrap `flutter` in `env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE`,
scoped to flutter alone so the git-dependent gates keep the real environment.
This is the documented `feedback_mistake_git_hook_env_leak` class, which the
repo had already hit in test code but not in the hooks themselves.
