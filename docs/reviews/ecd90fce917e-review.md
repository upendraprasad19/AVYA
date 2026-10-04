---
reviewed_at: 2026-09-22T17:39:18+05:30
staged_against: ecd90fce917e
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 3
verdict: accepted
---

# Code Review — ecd90fce917e

**Scope note:** this is a merge-integration review of `claude/next-aab-decision-d1227b` (own diagnose
`e8b4a1`, own review `docs/reviews/571c997e56b5-review.md`, accepted) merging `origin/main`, which
already contains `claude/strange-merkle-c2d0b9` (reviews `f81f7ae899e1`, `be0c54291fcc`, accepted) and
`claude/food-logging-observations-126ab3` (reviews `b87e8a1f3f2a`, `be6f5e9ed80e`, accepted). Per
`.claude/skills/code-review/SKILL.md`'s 2026-09-22 precedent, this review is scoped to **whether
combining these two changesets broke something neither branch's own review could see** — not a
re-audit of either branch's internal correctness. `ours` = 18 files this branch's own commits touched
(diff `5e01a34e..HEAD`); `theirs` = 97 files `origin/main` brought in (diff `5e01a34e..MERGE_HEAD`);
the intersection (files touched on BOTH sides) is exactly: `.claude/skills/code-review/SKILL.md`,
`CLAUDE.md`, `backups/applied_migrations.json`, `docs/audit/OPEN_INDEX.md`, `docs/audit/open_issues.md`,
`docs/diagnoses/INDEX.md`, `docs/sot_registry.yaml`, `lib/core/constants/app_constants.dart`,
`pubspec.yaml` — this is where a merge-only bug can hide, and where review effort was concentrated.

## Finding 1 — P1 — writer_reader_drift / asserted_fixture_value
- **file:line:** `supabase/migrations/141_disk_io_audit_cleanup_batch.sql` (the inlined
  `alert_cron_failures` INSERT inside the new `ops_alerts_30min` job, section "4b. Ops alerts", the
  `-- alert_cron_failures` sub-block) vs. `supabase/migrations/140_hermes_pass_fixes_138_139.sql`
  ("FIX 1: bound alert_cron_failures's stuck-job branch to 6 hours.")
- **claim:** Migration 140 (from `origin/main`, applied live 2026-09-21T23:44:34+05:30) fixed a real,
  already-misfiring production bug: `alert_cron_failures`'s `status='started'` stuck-job branch had no
  upper time bound, so a cron job that crashed and never called `logCronEnd` paged the founder hourly
  forever. 140's fix bounds it to `[1h, 6h)`. Migration 141 (this branch's own migration, applied live
  2026-09-22T05:38:35+05:30 — **after** 140) consolidates `alert_cron_failures` into the new
  `ops_alerts_30min` job via `cron.unschedule('alert_cron_failures')` + a fresh `cron.schedule`, but the
  inlined SQL body it uses is migration **139's original, pre-140-fix** logic — `status = 'started' AND
  started_at < now() - interval '1 hour'` with **no upper bound**, silently re-introducing the exact bug
  140 shipped to fix. This is not hypothetical: it is the live, currently-scheduled job.
  **This is exactly the "did combining these two changesets break something neither branch's own review
  could see" class** — 141's own author correctly noted in the migration's own comment that
  "`alert_cron_failures` was created live by migration 139 on a separate in-flight branch... this
  migration assumes it already exists by the time 141 runs," but was unaware 139 had **also** been
  patched by 140 on that same branch before 141 ran, because 140 didn't exist in 141's authoring context.
- **verification:**
  `mcp__ba7b5e8e...__execute_sql` on project `dedsavbjuwgarrhphgnl`:
  `SELECT jobid, jobname, schedule, active, command FROM cron.job WHERE jobname IN ('alert_cron_failures','ops_alerts_30min');`
  → only `ops_alerts_30min` (jobid 42, active=true, `*/30 * * * *`) exists; its `command` contains
  `WHERE (status = 'failed' AND started_at >= now() - interval '1 hour') OR (status = 'started' AND
  started_at < now() - interval '1 hour')` — **no** `AND started_at >= now() - interval '6 hours'`
  clause, confirming the live job has regressed to the pre-140 unbounded form.
  Separately, `SELECT count(*) FROM public.cron_call_log WHERE status='started' AND started_at < now() -
  interval '1 hour';` → 0 rows right now, so it is not actively mis-paging **at this instant**, but will
  reproduce the original incident (`public.alerts id=40`, 2026-09-21 17:30 UTC) the next time any cron
  job crashes mid-run and leaves a `'started'` row stranded (routine — 140's own diagnose describes
  exactly this happening from a single crashed 2026-09-19 04:15 UTC tick).
  **The existing regression test is blind to this**: `test/contracts/alert_cron_failures_sync_test.dart`
  reads `alerts/_thresholds.yaml`'s `cron_failures.defined_in_migration: "140_hermes_pass_fixes_138_139.sql"`
  and asserts the 6-hour bound **against that one named file only** — it never reads migration 141 or
  the live `cron.job` table, so it stays green even though the job it believes it is pinning is no
  longer the one actually running. This is the `feedback_green_check_input_set_width` class this repo's
  own memory already tracks, applied to a migration file rather than a grep.
- **suggested-fix:** Apply a new migration that re-applies the `[1h, 6h)` bound to the live
  `ops_alerts_30min` job's `alert_cron_failures` sub-block (same `cron.unschedule('ops_alerts_30min')` +
  `cron.schedule` pattern 141 already used). Separately, either point
  `alerts/_thresholds.yaml`'s `cron_failures.defined_in_migration` at whichever migration is currently
  authoritative for the live job (141, until fixed), or extend the test to also read the live-superseding
  migration when one exists, so a future consolidation of this kind cannot go green while silently
  reverting a prior fix. Update `docs/operations/CRON_REGISTRY.md`'s row for `ops_alerts_30min` to flag
  this until fixed (it currently only documents the OI-234 `alert_edge_function_health` carry-along, not
  this one).
- **status:** fixed — `supabase/migrations/143_restore_alert_cron_failures_stuck_job_bound.sql`
  drafted, restoring the `[1h, 6h)` bound to `ops_alerts_30min`'s `alert_cron_failures` sub-block
  only (the other two sub-blocks reproduced verbatim from 141). NOT yet applied live — requires
  separate explicit founder authorization per CLAUDE.md §4.3 (live prod apply needs its own go,
  independent of this batch's approval); tracked in
  `docs/diagnoses/2026-09-22-merge-integration-review-alert-cron-failures-regression-a2f6c9.md`.
  `alerts/_thresholds.yaml`'s `defined_in_migration` repointed at 143, and
  `test/contracts/alert_cron_failures_sync_test.dart` widened with a new test that scans all
  migrations for the alert-emitting literal and requires the YAML to name the numerically last
  one — mutation-proven (reverting the pointer to 140 reddens it, naming 143 as the fix).
  `docs/operations/CRON_REGISTRY.md` updated.

## Finding 2 — P1 — missing_input (build/encoding integrity)
- **file:line:** `lib/core/constants/app_constants.dart:1`, `pubspec.yaml:1` (whole-file corruption, ~13
  and ~6 affected comment lines respectively)
- **claim:** The currently-staged (post-merge) versions of `lib/core/constants/app_constants.dart` and
  `pubspec.yaml` carry a spurious UTF-8 BOM and double-encoded "mojibake" in every comment containing an
  em-dash, arrow, or box-drawing character (e.g. `——` → `â€"`, `──` → `â”€â”€`, `→` → `â†'`). This is **not**
  something introduced by the manual conflict resolution — it was already present on `origin/main`'s tip,
  committed directly by commit `65bee5d5` ("chore: bump versionCode 1.0.0+44 → 1.0.0+45 for APK +45",
  reachable via `refs/heads/claude/strange-merkle-c2d0b9`, 2026-09-21 06:44:13+05:30), which rewrote both
  files' comment text as if some tool in that session's pipeline read UTF-8 as Latin-1/CP1252 and
  re-saved as UTF-8, doubling the byte sequences. Because this branch's own commit `2095dba7` touched
  only the single `appVersion` line (no line-count change, no encoding change) and both sides happened to
  bump the version to the *identical* value `1.0.0+45`, git's 3-way merge saw no line-level conflict and
  silently took `origin/main`'s corrupted version for every other line — so the corruption is landing in
  this merge commit undetected, since nothing flagged it as a conflict.
- **verification:**
  `file lib/core/constants/app_constants.dart pubspec.yaml` → both report "Unicode text, UTF-8 (with
  BOM) text" (neither had a BOM before `65bee5d5`: `git show a4eb42ab:lib/core/constants/app_constants.dart
  | head -c 4 | xxd` has no `efbb bf` prefix).
  `grep -c "â€" lib/core/constants/app_constants.dart pubspec.yaml` → 13 and 6 matches respectively in the
  currently staged tree.
  `git log MERGE_HEAD --oneline -- pubspec.yaml | head -3` → `65bee5d5` is the commit that introduced it
  (`git show 65bee5d5 -- pubspec.yaml` confirms the diff origin).
  Comments are the only thing affected (code/config statements themselves are unchanged), so this will
  not fail `flutter analyze` (Dart tolerates a leading BOM) — but a stray BOM inside `pubspec.yaml` is
  more of an open question for `package:yaml`/`flutter pub get`, and either way this is dead-weight
  corruption nobody should be committing forward silently.
- **suggested-fix:** Re-save both files as UTF-8 without BOM and restore the original characters
  (`git show a4eb42ab:<path>` is the last known-clean version of each, modulo the version-string bump).
  Consider adding a lightweight pre-commit check (BOM sniff + a mojibake-signature grep such as `â€` /
  `â”€` / `â†'`) since nothing in the current 96-gate suite catches encoding corruption — this is a real
  gap the `missing_input` lens exists to name.
- **status:** fixed — both files restored from `git show a4eb42ab:<path>` (last known-clean
  content), with the `1.0.0+45` version bump re-applied as the only intended diff. `diff` against
  the clean commit confirms the version line is now the ONLY difference in either file; `grep -c
  "â€"` returns 0 for both; no BOM byte prefix remains. The suggested pre-commit BOM/mojibake
  sniff gate was NOT added — a one-off provenance defect in `origin/main`'s own history rather than
  a recurring class in this repo, so a new gate was judged not warranted; noted here rather than
  silently dropped.

## Finding 3 — P3 — blast_radius_mismatch (informational / process)
- **file:line:** `pubspec.yaml:19` / `lib/core/constants/app_constants.dart:120` (`appVersion`)
- **claim:** This branch's own commit `2095dba7` and `origin/main`'s commit `65bee5d5` independently
  bumped `1.0.0+44` → `1.0.0+45` for two unrelated purposes (this branch: incidental bump attached to the
  disk-IO fix commit; main: "for APK +45"). Because the disk-IO-fix branch carries **zero** `lib/`
  changes other than that one version line, the merged app content is identical either way and this
  does not corrupt what a build of `+45` would contain — but it does mean the versionCode's git history
  now has two independent "reasons," and no `apk_sizes.json`/`build-apk` commit for `+45` was found in
  history (`git log MERGE_HEAD --oneline --all | grep -i "apk +45"` returns only the bump commit itself),
  so `+45` does not appear to have been built/uploaded to Play Console yet.
- **verification:** `git log MERGE_HEAD --oneline -- pubspec.yaml | head -2` and
  `git log HEAD --oneline -- pubspec.yaml | head -2` both show an independent `+44→+45` bump commit on
  each side reachable from the merge; `git log --all --oneline | grep -i "record apk 1.0.0+45"` → no
  match.
- **suggested-fix:** No action required before this commit lands. Flag for whoever runs the next
  `/build-apk`: CLAUDE.md's own documented Gate-2-blind-spot pitfall
  (`feedback_mistake_versioncode_gate2_blind_spot.md`) applies here — Gate 2.5 (commit `cb519d51`)
  should catch a reused/already-built versionCode, but worth a manual double-check given this collision
  is unusual (two branches, not two commits on one linear history).
- **status:** acknowledged — informational only, no code/content change required before this
  commit lands per the finding's own suggested-fix. Flagged for whoever next runs `/build-apk`
  against `+45`; Gate 2.5 (`feedback_mistake_versioncode_gate2_blind_spot.md`) is the existing
  mechanism expected to catch a reused/already-built versionCode.

## Checked and clean

- **Conflict-marker sweep (task 3a):** `git diff --cached | grep -n "^[<=>]\{7\}"` — 0 matches across the
  entire staged diff. No residual `<<<<<<<`/`=======`/`>>>>>>>` markers anywhere.
- **`backups/applied_migrations.json` structural integrity:** valid JSON (148 entries), no duplicate
  migration numbers, chronological order preserved (`138`@`2026-09-21T...` → `139` → `140` →
  `141`@`2026-09-22T05:38:35` → `142`@`2026-09-22T10:00:10`), both sides' entries fully present
  (verified by reading the last 5 entries' full `note` fields — none truncated).
- **`docs/audit/open_issues.md` structural integrity:** 153 `## OI-NNN` headers, zero duplicate OI
  numbers repo-wide (`grep -oE '^## OI-[0-9]+' | sort | uniq -c | awk '$1>1'` → empty). Both branches'
  new entries (OI-234..237 from this branch, OI-238..239 from main) present in correct numeric order
  with full bodies, not truncated.
- **`.claude/skills/code-review/SKILL.md` tuning-history integrity:** both sides' dated entries present
  (this branch contributes nothing new here — the file only appears in the overlap because main's batch
  appended entries near where a prior entry already existed); no duplication, no truncation, section
  structure (`## 7. Tuning history`) intact.
- **`docs/sot_registry.yaml` citation-shift check (task 3b), the precedent bug class:** this branch's
  own edit to this file is a single one-line citation update (`backups/live_cron_jobs.json` line_range
  `5-34` → `5-31`, reflecting this branch's own cron consolidation) — verified the file is still exactly
  31 lines, citation accurate. Checked the reverse direction too (main's edits shifting citations INTO
  files this branch also touched): `docs/sot_registry.yaml` has exactly one pre-existing citation into
  `lib/core/constants/app_constants.dart` (`freeAiTextLogsPerDay`, line_range `76-79`, unrelated to any
  hunk either side touched) — verified still accurate (`sed -n '76,79p'` matches). Main's 6
  `docs/sot_registry.yaml` hunks (`@@` at lines 541, 702, 842, 1725, 10261, 11578 post-merge) don't
  overlap any citation into a file this branch also edited, and this branch's only file-content edit
  (the one-line `appVersion` bump) preserved line count exactly, so no shift is possible from that side
  either.
- **Migration interaction, table/index overlap (task 3c):** migrations 138/139/140 (subscriptions
  trigger + alert_cron_failures + its own hermes-pass fix) touch `public.subscriptions` and
  `public.cron_call_log`/`public.alerts`; migration 141/142 touch `memory_embeddings`,
  `readiness_daily`, `ai_coach_interactions`, `nutrition_log_items`, and pg_cron job definitions —
  no direct table/column collision. The one **functional** interaction (141's cron consolidation
  swallowing 139/140's job) is Finding 1 above. Confirmed 141's own comment explicitly anticipated and
  correctly handled the *existence* ordering (139 already live by the time 141 ran, `cron.unschedule`
  didn't error) — the gap is specifically that it forked 139's original body, not 140's patched one.
- **Auto-generated files (task 3d):** `docs/audit/OPEN_INDEX.md` (142 `| OI-` rows) and
  `docs/diagnoses/INDEX.md` (1896 table rows) are both structurally valid (intact headers, no truncation)
  but currently stale relative to the just-merged `open_issues.md` (153 `## OI-` headers) and
  `docs/diagnoses/` (530 files on disk) — exactly as expected per the task brief, since
  `scripts/pre-commit.sh` regenerates both from source on any commit touching the board/diagnoses dir.
  Low severity, self-healing at actual commit time; not a structural break.
- **`secrets_in_tree`:** `git diff --cached -G'sk-|rzp_live_|AKIA|BEGIN (RSA|EC|OPENSSH|PGP)? ?PRIVATE KEY|api[_-]?key.{0,5}=.{0,5}[A-Za-z0-9]{20,}'` over the full staged diff — no matches, consistent with the
  food-logging-observations batch's own prior grep of the same shape.
- **`function_exception_swallow` / `unawaited_no_error_sink` / `guard_without_its_mirror` on the merge
  interaction surface specifically:** no new interaction code was introduced by the merge itself (the
  merge is documentation/migration/version-file territory, not application logic) other than the
  `ops_alerts_30min` cron body, which is covered by Finding 1. No additional instances found scoped to
  the 9-file overlap set.

## Founder triage notes

All 3 findings triaged same-day. Finding 1 (P1, live regression) and Finding 2
(P1, encoding corruption) fixed in this batch per `docs/diagnoses/2026-09-22-
merge-integration-review-alert-cron-failures-regression-a2f6c9.md`. Finding
1's live migration apply is the ONE piece still outstanding — it needs its own
explicit go from the founder per CLAUDE.md §4.3, separate from this batch's
approval, before `mcp__supabase__apply_migration` runs against production.
Finding 3 (P3, informational) needs no action now; flagged for the next
`/build-apk`.

