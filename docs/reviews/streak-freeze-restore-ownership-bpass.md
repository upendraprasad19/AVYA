---
reviewed_at: 2026-10-06T16:00:00+05:30
staged_against: claude/avya-streak-data-check-b506de (index only, nothing committed) vs HEAD f749cda3
blast_radius: platform
reviewer: fresh-context-blind-agents (Sonnet; three reviewers on one staged diff: B = Unit 1 code, A = Unit 2 code, C = documents and claims; read-only, no command beyond git diff/show/grep, Read, Grep, Glob)
lens_set: [guard_without_its_mirror, writer_reader_drift, asserted_fixture_value, missing_input, blast_radius_mismatch, doc_code_drift, unverified_evidence, terminal_state_fit]
findings_count: 25
verdict: accepted
---

# Code Review (B-pass) — streak decay persists after THIS account's restore settles; a stale cloud row stops overwriting freeze state (`claude/avya-streak-data-check-b506de`)

Scope: Unit 1 (diagnose `b4e7a1`): per-account restore-settled marker (`SyncService.restoreSettledForCurrentUser`,
`shouldSettleRestoreMarker`, `restoreFromCloudForUser` wrapper), zone-scoped `RestoreFailureCollector`, the 8-op allowlist
`kStreakCriticalRestoreOpTypes`, `DayRolloverObserver.reckonAndNotifyAfterRestore`, the Home override, the kill switch
`disable_streak_reckon_user_gate`. Unit 2 (diagnose `c9d2f6`): `UserRepository._mergeFreezeFamily` post-pass,
`ProgressMergeResult.scheduleFreezeSyncUp`, the owner guard, `syncFreezes` reading `_liveUserId`, `current_streak_weeks` as a
fourth monotonic field (founder decision A), kill switch `disable_progress_freeze_merge`. Plus the SoT registry, naming
conventions, nested CLAUDE.md rows, bug class 2.91, the closure ledger and the plan. Self-attested (rule 21): the mutation
driver is a scratch script, not in the repo.

Three reviewers, each context-blind, each told to find bugs rather than validate. The coordinator re-read every cited
file:line before accepting a finding; a reviewer's suggested fix was treated as a separate claim from its finding.

## Findings (25: 0 P0, 0 P1, 6 P2, 19 P3) and what happened to each

### Reviewer B (Unit 1: 1 P2, 3 P3)

| # | sev | finding | disposition |
|---|---|---|---|
| B1 | P2 `guard_without_its_mirror` | `PlanIntegrityReconciler.reconcile` writes `schedule_*` rows AFTER the marker settled and outside any collector zone, through a ghost-day lookup (`_deletedTemplateCloudIds`) that fails EMPTY; a failed lookup resurrects a deleted template's day as a past planned row and the reckon then debits freezes for good | **fixed** — tri-state lookup (`null` = could not answer), `filterGhostScheduleEntries` skips template days on `null`; behavioral T5 + T11; mutations MB1 (1 red), MB2 (1 red) |
| B2 | P3 coverage | only 6 of 8 allowlisted ops were driven through the funnel behaviourally | **fixed** — T7 now drives `workout_logs`, `workout_schedule_completions` and `user_progress` 500s through the real wrapper; mutations MB3a/b/c (2/1/3 red) |
| B3 | P3 ordering | the marker clear was the LAST statement of `_onUserChanged`; a throw above it leaves A's marker open for A -> B -> A | **fixed** — clear moved to the first statement; T3b + a T9 ordering pin; mutation MB4 (1 red) |
| B4 | P3 liveness | one failure sink spans the single-call attempt AND the legacy fallback, so a faulted single-call pass holds the marker closed although legacy restored the op | **fixed** — `RestoreFailureCollector.clear()` on the single-call fault branch before the legacy Step A; T1; mutations MB5a (1 red), MB5b (1 red) |

### Reviewer A (Unit 2: 1 P2, 5 P3)

| # | sev | finding | disposition |
|---|---|---|---|
| A1 | P2 `guard_without_its_mirror` | a local first-PRO grant `{3,W,flag T}` meeting a stale cloud `{1,W,flag F}` was clamped to 1 by the same-week rule while the flag was written TRUE, blocking `grantFirstProFreezes` for good and pushing the lost count over a cloud that might already hold the grant | **fixed** — an EATEN grant leaves the flag at the cloud's value and schedules no push; a surviving grant is claimed and pushed; Group A "a LOCAL grant the cloud has not seen"; mutations MC1 (2 red), MC2 (1 red) |
| A2 | P3 `asserted_fixture_value` | the asymmetric carry kept the local NEWER refill stamp (dropping that week's +1) and could refund a local consume the cloud ledger had not seen | **fixed** — carried count is the cloud's minus every local used date the cloud has not seen, and the cloud's OLDER stamp is adopted; mutations MC3 (2 red), MC4 (3 red) |
| A3 | P3 `guard_without_its_mirror` | the sole-writer contract for `streak_freezes_available` matched only a map-literal key, so index assignment (this unit's post-pass) was invisible | **fixed** — the test also flags index assignment and allowlists the two legitimate files by name; mutation MC6 (1 red) |
| A4 | P3 stale citations | new comments cited HEAD line numbers that the same diff moves; a test header said "3" fields; an OI-150 group lost its header | **fixed** — citations replaced by symbol names, counts corrected to 4, header restored |
| A5 | P3 `guard_without_its_mirror` | the client treats weeks as monotonic on restore but the push RPC (migration 115) is a bare COALESCE for it and `last_streak_week` is local-only | **terminal: `blocked_on_user`** (`WEEKS-PUSH-RPC`) — both halves need a migration and a live apply; recorded in `lib/core/services/CLAUDE.md` and `services-detail.md` so it is not rediscovered. Not introduced by this batch (the re-count happens identically under the pre-fix cloud-wins restore) |
| A6 | P3 coverage | the sign-in hydrate push had presence-only coverage | **fixed** — two behavioral tests drive `AuthSessionBootstrapper.hydrateFromCloud` through `SyncHarness` (stale row -> exactly the merged RPC; equal row -> none); mutation MC5 (2 red) |

### Reviewer C (documents and claims: 4 P2, 11 P3)

| # | sev | finding | disposition |
|---|---|---|---|
| C1 | P2 | the CONTINUE escape leaves the restoring screen while the restore runs and `_goHome` returns early, so that cohort could settle the marker and never reckon the idle-day debit; the ledger had no entry and F1 read as fully closed | **fixed in code** (not just disclosed) — `healAfterRestoreWhenSucceeded` attached by `_onContinueAnyway`; T12; mutations MB6 (1 red), MB7 (1 red) |
| C2 | P2 | `LAST-WORKOUT-DATE` was `verified_clean` on a wrong premise (the local value is read as the push payload, migration 115 is a bare COALESCE for it, the rank gate reads it) | **corrected** to `blocked_on_user`: needs a NEW date-max merge path outside the founder-approved scope |
| C3 | P2 | `LIVENESS` was `closed_in_commit` though it is an accepted trade-off; `CURRENT-STREAK-DAYS` is repaired only when the marker settles; F5's Home snackbar has only a presence pin | **corrected** — `LIVENESS` is `verified_clean` as a recorded decision, `CURRENT-STREAK-DAYS` says "conditional on settle", F5 states its honest limit and the owed device check |
| C4 | P2 | the "228 passed, 0 failed" line in both diagnose docs had no retained log, and the only full-suite log ended red | **fixed** — replaced by the real final-tree numbers (see Execution evidence below) |
| C5 | P3 | "K1 ... 4 red of 46" (46 passed + 4 failed = 50 tests) | **fixed** — "4 red of 50" |
| C6 | P3 | the doc said each settle clause has its own killer, but five conjuncts were mutated only three times | **fixed** — mutations N6d (`result.succeeded` dropped, 2 red) and N6e (`uid != null` dropped, 1 red) added; all five now have a killer |
| C7 | P3 | a citation named `_kickoffRestore` for a line that is in `_goHome` | **fixed** |
| C8 | P3 | SoT registry/naming contradictions: "unchanged" on a file that gained 7 tests; a "streak counters reset" sentence next to the monotonic weeks field; an unconditional "tick no longer gates" under a kill switch | **fixed**, three rewordings |
| C9 | P3 | the two kill switches were labelled "fails open" and "fail-closed" for identical behaviour | **fixed** in `naming_conventions.md` and the c9d2f6 diagnose doc (a final comment in `sync_flags.dart` and the plan are reworded in the same batch) |
| C10 | P3 | stale cites and counts (comment cites, plan title v4/v5, "other six" vs seven, OI-279 cites, `home/CLAUDE.md` row 53) | **fixed** each |
| C11 | P3 | an `upstream_blocked` entry whose blocker was self-chosen scope (EF caps bundled with the empty-answer half) | **fixed** — split into `RESIDUAL-EMPTY-ANSWER` (`upstream_blocked`, OI-293) and `RESIDUAL-EF-CAPS` (`blocked_on_user`: an Edge Function deploy) |
| C12 | P3 | tier 6 "verified" on a repo read only; wrong migration numbers in tier 3 | **fixed** — "REPO READ ONLY"; 048 (NOT NULL) and 072 (CHECK 0..3) |
| C13 | P3 | "nothing resets it" for weeks (onboarding and the default progress seed 0); item 8 without writer/reader file:line | **fixed** — "no runtime reset" plus the writers and readers |
| C14 | P3 | F4 stated a phantom-grant mechanism as fact; `FOUNDER-LEDGER-ONE-SHORT` is `verified_clean` while its own notes say it is not clean | **fixed** — F4 hedged ("WHICH merge undid the 3 is UNVERIFIED"); the ledger entry says the state is a recorded decision |
| C15 | P3 | "one commit per unit" cannot be done from one index blob (six files carry both units); the scratchpad draft plan-review record was stale | **noted for commit time** — the units are split with hunk-level staging; the draft record was rewritten (weeks decision made, one-freeze repair declined) |

## What the reviewers checked and found clean

Unit 1: collector spellings equal the allowlist exactly in both restore paths; zone semantics; the settle decision fails
closed on a null uid / live uid / owner; `_onUserChanged` is the only path that clears; reckon ordering (tick bumped
LAST); the three gate callers; the Home notice cannot double-fire; CQRS purity of the getter. Unit 2: every
`mergeFreezeProgress` case hand-computed, count always within 0..3; `scheduleFreezeSyncUp` cannot stay true after a
successful push (no push loop); order independence; kill switches restore pre-fix behaviour; owner guard precedes the
write and the push; `syncFreezes` identity equals the singleton in production; about 20 Group A expectations
recomputed; the fixtures are truthful; weeks has no legitimate downward writer. Documents: every `file:line` in both
diagnose docs resolves; SoT ranges correct; allowlist identical in code and four docs; test and mutation counts match
their logs.

## Triage summary

- 20 findings fixed in this batch (B1-B4, A1-A4, A6, C1, C4-C10, C12-C14): a behavioral test for each code finding,
  and every new protection mutated (Unit 1: 12 mutations, 1-3 red each; Unit 2: 5 mutations plus the sole-writer one,
  1-3 red each; every restore verified by hash).
- 3 findings corrected the closure ledger itself (C2, C3, C11); C2 and C11 left two items at their true terminal state
  `blocked_on_user` (`LAST-WORKOUT-DATE`: widen this batch or its own unit; `RESIDUAL-EF-CAPS`: an Edge Function deploy go).
- 1 finding (A5, `WEEKS-PUSH-RPC`) is `blocked_on_user`: a migration plus a live apply go. None of the three is a deferral:
  each needs a production action or a scope decision that is the founder's.
- 1 process note (C15) carried to commit time (hunk-level staging for the two units).
- 0 false alarms.

## Execution evidence (final tree)

- `flutter analyze --no-fatal-infos` (whole project, so the test directory is covered): 356 infos, 0 warnings, 0 errors.
- Full suite on the final staged tree, `TZ=Asia/Kolkata flutter test test/ --exclude-tags golden` (the CI selection;
  golden tests are platform-specific and run locally only): **7854 passed, 9 skipped, 0 failed**, exit 0, 40 min. The
  earlier full-suite log (before the B-pass fixes) ended red with 2 failures and was never reported as green; the number
  above is from a fresh run after every B-pass fix.
- Pre-commit gate loop (every `scripts/check_*.dart` gate, index regeneration, Gate 40 closure ledger, SoT registry
  parity, Gates 9 and 42): OK on the staged tree.
- Re-run after the last wording edits: the eight test files that read the edited files (197 tests) pass, and both
  diagnose docs validate (`validate_diagnose_doc.dart`).

## Not done by this review, stated plainly

No commit, push, APK build, migration apply, Edge Function deploy or production write was made. The two things only a
person can confirm remain owed: a phone check that an idle-day freeze debit persists with its Home notice, and that the
Home streak and the freeze chip agree after a cold start (CLAUDE.md section 5, runtime verification).

## Verdict

Accepted. Every P2 was a real defect of the batch's own design or a ledger that claimed more than the evidence, and each
was fixed or re-stated at its true terminal state.
