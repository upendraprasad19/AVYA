---
branch: oi-245-246-restore-fixes
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/82620b20f504-review.md
tier: platform
date: 2026-09-29
---

# Plan review — oi-245-246-restore-fixes

**Scope:** two independent bug fixes. **OI-245**: restored PRO photo-coach
turns (a Hive row synced back down after a reinstall/restore) were replayed
to Gemini as plain text instead of the original `[Photo: ...]`/`[Video:
...]` marker prefix, because `sync_coach.dart`'s mode-derivation logic never
recognized a restored row's shape — fixed in `sync_coach.dart` +
`test/contracts/coach_restored_media_mode_writer_to_reader_test.dart`.
**OI-246**: deleted `workout_log_exercises` rows could reappear after a
cloud restore, because migration 150's rename-on-delete trigger
(mirroring the already-shipped `workout_templates` pattern, migration
145/146) was `BEFORE UPDATE`-only, and a client upsert for a natural key
with no existing cloud row lands as a plain INSERT, which the trigger never
saw — fixed with migration 151 (extends the trigger to `BEFORE INSERT OR
UPDATE`, mirroring migration 146's own fix for the sibling table one day
earlier), a new `PendingExlogDeletes` local-delete-tracking service, changes
to `sync_workout.dart`/`workout_write_service.dart`/`sync_service.dart`, and
a follow-on fix in two Edge Functions (`weekly-recalc`, `pr-detection`) whose
own value-semantics depended on `exercise_id` never carrying a delete-suffix.
Both migrations 150 and 151 are already LIVE on prod, each applied only
after explicit, separate founder authorization per CLAUDE.md §4.3 (plan
approval ≠ deploy approval) and independently live-verified before AND after
apply (reproduced the bug in a `BEGIN...ROLLBACK` transaction against 150
alone before drafting 151; reproduced the fix the same way after applying
it). The two Edge Function code fixes (`weekly-recalc`, `pr-detection`) are
code-complete in this worktree but **NOT YET DEPLOYED** — deploying either
is a separate live action requiring its own explicit founder authorization,
not yet requested.

**Blast radius: platform.** Confirmed live, repeatedly, via
`dart run scripts/blast_radius_from_diff.dart` (no args, reads the cached
diff) → `Blast-radius: platform` (touches `supabase/migrations/**` and
`lib/core/services/sync/**`, both platform-tier per `docs/blast_radius.yaml`).

## Round summary (2 independent context-blind plan-review rounds, plus a self-triggered B-pass — 3 total)

- **Round 1**: found the batch's own bug-history lookup had missed a direct
  precedent — migration 150's trigger was `BEFORE UPDATE`-only, the EXACT
  SAME gap diagnose `f4a8c2` (2026-09-27) had already found and fixed for
  `workout_templates` via migration 146, one day before migration 150 was
  even drafted. Live-reproduced the bug in a rollback-wrapped transaction
  against 150 alone (a tombstone-shaped INSERT — the drain's own UPSERT
  being the FIRST cloud write for a natural key — left `exercise_id`
  unsuffixed, silently dropping a subsequent re-log's data), then drafted
  and live-verified migration 151 mirroring 146's fix exactly before
  requesting authorization to apply it. Also found a P2 internal
  contradiction in the diagnose-doc's own `touched_layers_checked` tier 5
  field (stale before the live-apply evidence was added). Both fixed in the
  same round.
- **Round 2**: independently re-verified round 1's fixes from scratch
  against live code and live Supabase state (not taken on faith) and found
  no new P1s — migration 151 is correct and live-verified. Found one genuine
  new defect: `weekly-recalc/index.ts` grouped `workout_log_exercises` rows
  by `exercise_id ?? exercise_name` with no `deleted_at` filter, so a log
  deleted within the trailing 4-week scoring window fragmented into its own
  bogus single-entry "exercise" (inflating the variety score) instead of
  merging correctly — a genuine regression this batch's own exercise_id-
  suffix design introduced, squarely inside the CLAUDE.md §4.1.5
  value-semantics sweep this batch's own bug-history step should have run
  against `supabase/functions/` and did not. Fixed via a pure extracted
  `excludeDeletedLogs` predicate, mutation-proven. Also found and fixed two
  trivial citation gaps (a `sot_registry.yaml` line-range split; a missing
  parity-test assertion for a second `[Photo:` insert call site in
  `ai-media-proxy/index.ts`) and correctly scoped FIVE other un-patched
  `workout_log_exercises` readers as out-of-scope, filing **OI-269** — a
  characterization the round-3 B-pass below found was wrong for one of the
  five (see below).
- **Round 3 (self-triggered B-pass, CLAUDE.md §4.3 — a separate, mandatory
  step from the ×2 rounds above, not the same requirement)**: two agents,
  split lens set (reviewer A: writer_reader_drift, function_exception_swallow,
  blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink,
  missing_input — the latter with live read-only Postgres MCP verification;
  reviewer B: guard_without_its_mirror, asserted_fixture_value, mutation
  testing). Reviewer B found 0 defects, independently re-running every
  mutation-proof claim in both diagnose-docs and reproducing each exactly.
  Reviewer A found 2 real findings, both fixed: (1) round 2's own "5 readers,
  all unchanged" characterization was wrong for `pr-detection` specifically —
  its push-notification composer renders `exercise_id` with no
  `exercise_name` fallback, so the exercise_id-suffix design would leak an
  internal id fragment into a real user-facing push for any PR deleted
  inside the ~20-minute cron window, a genuinely new regression
  mischaracterized as out-of-scope; fixed by mirroring the identical
  `excludeDeletedLogs` pattern (`pr-detection/live_pr_filter.ts`'s
  `excludeDeletedPrs`), mutation-proven, OI-269 corrected. (2) platform
  tier's unenforced `feature_flag` requirement was unmet and undiscussed for
  3 new sync-domain code paths; resolved by documenting the exemption
  (rather than adding a switch that would re-open the exact data-corruption
  bug this batch exists to close) after confirming the established sibling
  mechanism this batch's own code mirrors (`_drainPendingTemplateDeletes`,
  OI-252, already live for weeks) has the identical gap.
  Review: `docs/reviews/82620b20f504-review.md` (`verdict: accepted`).

## Corrected full-suite re-run finding (self-caught, not from either review round)

Neither plan-review round nor the B-pass ran `flutter test` (a documented,
repeating gap per CLAUDE.md §4.12.5). A CORRECTED full-suite re-run
(`TZ=Asia/Kolkata flutter test test/ --exclude-tags golden` — the wrong
environment on a prior in-session attempt, missing both the TZ pin and the
golden exclusion, could not be trusted) surfaced one real regression this
batch introduced that no review round could see: `_drainPendingExlogDeletes`
(new this batch) shares its exact upsert-marker literal text with a
PRE-EXISTING, untouched test file's (`sync_natural_key_guard_test.dart`)
source-grep anchor for an unrelated guard — `indexOf`'s first-match behavior
silently re-anchored the test's lookback window onto the new, unrelated
code. Fixed by extending the marker with a trailing newline, exploiting a
genuine structural difference between the two call shapes (inline-map vs.
named-variable upsert), mutation-proven in both directions. Documented as a
new ("fifth") variant of an already-tracked CLAUDE.md §4.9 pitfall row, and
as a new bug-class entry (§2.77, renumbered from §2.74 during the origin/main
merge-reconciliation after a genuine collision with an unrelated origin/main
entry that independently claimed §2.74 the same week) in
`.claude/skills/debugging/SKILL.md`.

## Ground truth verification (this record's own, not just the reviewers')

Every writer/reader pair named in both diagnose-docs was independently
confirmed against the real files and, where a live claim was made, against
live Supabase state directly (`information_schema.columns`, `pg_trigger`,
`pg_get_functiondef`-equivalent live queries) — not trusted from any
subagent's prose. Specifically re-verified: migration 151's trigger fires
`BEFORE INSERT OR UPDATE` (`pg_trigger.tgtype=23`) live on prod; both
migrations' recorded sha256 hashes in `backups/applied_migrations.json`
byte-match the files on disk (an initial hand-typed hash for 151 was caught
truncated by one character earlier in this batch and fixed by computing the
hash programmatically rather than transcribing terminal output); the
`i-see-you-callout`/`weekly-report`/`getProgressSummary.ts` readers OI-269
still tracks were each individually confirmed (not assumed) to be safe from
`pr-detection`'s specific display-corruption defect.

## Verification state at record time

- Full pre-commit gate loop (`sh scripts/pre-commit.sh`): green, including
  Gate 40, Gate-SDB, Gate-DEU, and the tech-debt audit bundle. Blast-radius
  printed `platform` on every run.
- `flutter analyze lib/` (whole-tree): 45 pre-existing `info`-level issues,
  0 warnings/errors, 0 new issues introduced by this batch (ran in 3.6s).
  No `lib/` files were touched by the round-3 B-pass fixes (both were
  `supabase/functions/` code), so this figure is unchanged from earlier in
  the batch.
- Targeted `flutter test` re-run after the round-3 fixes
  (`TZ=Asia/Kolkata flutter test test/contracts/coach_restored_media_mode_writer_to_reader_test.dart
  test/contracts/exlog_tombstone_delete_writer_to_reader_test.dart
  test/contracts/sync_natural_key_guard_test.dart`): 33/33 green.
- A full corrected `flutter test test/ --exclude-tags golden` run (before
  the round-3 fixes, which touched no `lib/`/`test/` file) reported 6686
  passed, 9 skipped, 0 failed — see the diagnose-doc's own "Verification"
  section for the exact log.
- Both new/touched Deno test files (`weekly-recalc/index_test.ts`,
  `pr-detection/index_test.ts`) type-check clean
  (`deno check --node-modules-dir=none`) and pass in full (5/5 and 11/11
  respectively).
- **Runtime verified on device: NOT PERFORMED.** This environment (a
  headless VPS worktree) has no physical device or emulator access. Every
  claim above is code-read + live-Postgres-query + automated-test
  verification; none of it is a substitute for an on-device run, and this
  is disclosed rather than silently skipped.

## Out-of-scope discoveries, filed rather than fixed

- **OI-269** (corrected in round 3): `workout_log_exercises` readers that
  don't filter `deleted_at` — originally 5, now 4 after `pr-detection` was
  fixed in round 3 (`weekly-recalc` was already fixed in round 2).
- **OI-270**: `PendingTemplateDeletes` shares `PendingExlogDeletes`'s
  originally-found-and-fixed const-list mutation crash (identical
  `return const []` shape, unfixed in the pre-existing sibling class) —
  confirmed still present by round 3's reviewer B, reproduced live in a
  scratch script.
- **OI-218** (pre-existing, referenced not created by this batch): the
  sibling symptom on `moveExerciseLogs`'s from-date row — same missing
  delete-tombstone protocol, different call site, out of this batch's
  approved OI-245/OI-246 scope.
