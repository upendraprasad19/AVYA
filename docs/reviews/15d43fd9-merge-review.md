---
reviewed_at: 2026-09-23T00:00:00+05:30
staged_against: 15d43fd9
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [merge_integration_overlap, writer_reader_drift, missing_input, asserted_fixture_value, blast_radius_mismatch]
findings_count: 1
verdict: accepted
---

> **Corrected post-dispatch**: this file's frontmatter originally self-declared `catastrophic`.
> Recomputed twice (`git diff 5ba6c382 15d43fd9 | blast_radius_from_diff.dart -` → `account`;
> `git diff 15d43fd9^1 15d43fd9^2 | blast_radius_from_diff.dart -` → `account`) and grepped both
> migration ranges for `SECURITY DEFINER` (the one content-rule that forces catastrophic) — zero
> hits anywhere in this merge's diff. The value actually gating this commit was `platform`, per
> `scripts/pre-commit.sh`'s own live NOTE at commit time ("blast-radius=platform (>=account)").
> Corrected to `platform` per this skill's own lens 3 convention (a review's self-declared tier
> is a checkable claim, not scene-setting) — not itself a merge-integration defect.

# Merge-Integration Review — `15d43fd9`

Fresh, context-blind review scoped narrowly to the INTERSECTION surface of merge commit
`15d43fd9` (`merge: sync origin/main into next-aab-decision-d1227b before PR #35 merge`),
which merged `origin/main` (`1c791f72`, 25 commits) into `claude/next-aab-decision-d1227b`
(`5ba6c382`, 4 commits). Per brief: internal correctness of either side is out of scope — both
sides already went through their own review cycles. This review only asks whether COMBINING
the two changesets broke something neither side's own review could see.

## Context established before reviewing

- `origin/main`'s 25 commits: OI-batching Batches A/B/C (AI-coach fixes, `reportGeminiExhaustion`
  wiring into 5 Edge Functions, OI-238), Discipline v3 filing (OI-242), and an AAB versionCode
  ledger backfill/bump to `1.0.0+46` (`a0c46809`, `e698195c`).
- This branch's 4 commits: disk-IO-budget-exhaustion cleanup (migration 141: ivfflat retune,
  `readiness_daily` RLS auth-initplan fix, 2 dead-index drops, 9→3 pg_cron consolidation),
  migration 142 (restore `idx_nutrition_log_items_food_id`, a P1 self-caught in 141), migration
  143 (restore `alert_cron_failures`' stuck-job bound), and a docs move.
- **Load-bearing fact that reframes most of the brief's checklist**: `ad3fed06`, one of this
  branch's own 4 commits, is *itself* a merge commit (`Merge: 1108cc4c e7733cb8`) — the branch
  already merged an earlier snapshot of `origin/main` (through PR #36) mid-development, and a
  **self-triggered merge-integration B-pass at that time already found and fixed** the exact
  cross-branch regression this brief's item 1 asks about (migration 141's cron consolidation
  silently reverting migration 140's `alert_cron_failures` bound — origin/main's migration 140,
  not yet visible to 141's author at authoring time) via migration 143, plus the BOM/mojibake
  fix this brief's item 5 asks about. `15d43fd9` (the commit actually under review) only brings
  in the origin/main commits added *after* that nested merge (`e7733cb8..1c791f72`, 25 commits,
  none of which touch migrations, cron, or the two version files' content shape) — so the two
  regressions this brief primes me to hunt for were already closed one merge earlier, and the
  question for `15d43fd9` specifically is whether the *newer* origin/main commits reopen either.
  Verified they do not (below).

## Checks performed

### 1. Migration/schema overlap — CLEAN, verified

`ls supabase/migrations/` shows 141/142/143 as this branch's only migrations in that numeric
range; origin/main added none in [141,143] or touching the same cron jobs/tables. Confirmed via
`git log --oneline 15d43fd9^1..15d43fd9^2` (the 25 incoming commits) — none touch
`supabase/migrations/`. The pre-existing cross-branch cron regression (141 vs origin's 140) was
already caught and fixed in the earlier nested merge (`ad3fed06`, migration 143) with its own
diagnose-doc (`a2f6c9`) and a structural regression test
(`test/contracts/alert_cron_failures_sync_test.dart`, asserting `alerts/_thresholds.yaml`'s
`defined_in_migration` names the numerically-last migration touching the job). Verified the
*current* merged tree still reflects the fix: `alerts/_thresholds.yaml:80` reads
`defined_in_migration: "143_restore_alert_cron_failures_stuck_job_bound.sql"`, and
`docs/operations/CRON_REGISTRY.md:47,81-83` correctly cross-references OI-234, migration 141's
regression, and migration 143's fix. `backups/applied_migrations.json` cleanly gained 3 new
entries (141/142/143) with no origin-side edits in the same region to collide with.

### 2. Edge Function interaction — CLEAN, verified

Origin's `722501b8` (wires `reportGeminiExhaustion` into `weekly-report`, `ai-media-proxy`,
`assess-body-composition`, `daily-snapshot`, `rolling-context`) is purely additive telemetry —
one new function call per file, byte-identical existing responses. Checked whether any of these
5 functions read `readiness_daily`, `ai_coach_interactions_tool_calls_failed`, or
`nutrition_log_items` (the tables/indexes this branch's migration 141/142 touched): none do.
`rolling-context` does `INSERT INTO memory_embeddings` (the ivfflat-indexed table 141 retuned
`lists=100→10`), but inserts don't exercise the ivfflat index at all (it only affects
approximate-nearest-neighbor SELECT queries), so no interaction. The "`daily-snapshot`
merge-safe upsert bug" mentioned in the task brief is not among the 25 commits in this merge's
range (`git log ... -- supabase/functions/daily-snapshot/` shows only `722501b8`'s telemetry
add) — it shipped earlier (PR #31/#32, per `docs/audit/open_issues.md`'s OI-233, which cites
"the d8a2f6 merge-safe fix" as already-landed residue) and is outside this merge's diff surface
entirely, so there is nothing for this branch's changes to have interacted with here.

### 3. OI board consistency — CLEAN, verified

- No duplicate OI numbers: `grep -oE '^## OI-[0-9]+' docs/audit/open_issues.md | grep -oE
  '[0-9]+' | sort -n | uniq -d` → empty.
- OI-238 does not appear as an open entry: `grep -c "^## OI-238 —" docs/audit/open_issues.md` →
  0. It IS present in `docs/audit/closed_issues.md:3682` (the closed copy, correctly preferred
  per the brief).
- Numeric range 234–242 checked individually: 234,235,236,237,239,240,241,242 each appear
  exactly once; 238 appears zero times (expected, closed). No gaps, no duplicates.
- `docs/audit/OPEN_INDEX.md` internal consistency with `open_issues.md`: **142 rows in the index
  vs 153 `## OI-` headers in the board — an 11-entry gap.** Traced this before flagging it as a
  merge defect: `git show 15d43fd9^1:docs/audit/OPEN_INDEX.md` (branch side alone) shows the
  identical-shape gap (143 index rows / 154 headers = 11), and `git show
  15d43fd9^2:docs/audit/OPEN_INDEX.md` (origin/main alone) shows it too (137/148 = 11). The gap
  pre-dates the fork point and is byte-for-byte the same size on both parents — **this is a
  pre-existing generator behavior (or pre-existing board defect), not something the merge
  introduced or a merge-integration overlap**, so per the brief's own scoping ("do NOT re-audit
  either side's internal correctness") I am not filing it as a merge finding. Re-ran
  `dart run scripts/build_oi_index.dart` and `dart run scripts/build_bug_index.dart` against the
  current merged tree as the brief invited: both produced **zero diff** (`git status
  --porcelain` clean after each), confirming both indexes are byte-identical to what a fresh
  regeneration produces — not stale relative to their sources, merge-wise. (Whether the
  generator's exclusion of those 11 entries is itself correct is a separate, pre-existing
  question outside this review's remit.)
- No leftover conflict markers anywhere in the repo: `grep -rln '^<<<<<<<\|^=======$\|^>>>>>>>'`
  across `*.dart/*.md/*.yaml/*.sql/*.ts` returned nothing (exit 1 = no matches).

### 4. SKILL.md tuning-history internal consistency — CLEAN for the cited case; see Finding 1 for an adjacent, non-merge-caused gap

`docs/reviews/d2ce94ab0a72-review.md` exists on disk; its frontmatter reads `staged_against:
d2ce94ab0a72`, matching exactly. The SKILL.md entry at line 405 now correctly cites this current
filename and its own prose (lines 405-415) documents the rename history and states explicitly
that this correction landed "as part of that merge, 2026-09-23" — consistent with the brief.
Swept the rest of SKILL.md for other filenames-cited-but-absent-on-disk
(`comm -23` of extracted `*-review.md`/`*-bpass.md` citations against `ls docs/reviews/`):
found 6 total. Two (`5ebf78e29706-review.md`, `a4bcd634b7a7-review.md`) are the intentional
old-name breadcrumbs for the d2ce94ab0a72 entry itself (expected, harmless). Three more
(`12408db06b47-review.md`, `1486254681fb-review.md`, `016af81ca391-review.md`, SKILL.md lines
1555-1605) are explicitly self-documented as intermediate renames of a chain whose final,
on-disk name (`docs/reviews/3cd1891ee7eb-review.md`) is stated in the same paragraph and does
exist — also expected. The 6th, `eb37932a4218-review.md` (line 2532), IS presented as a live,
undecorated citation with no rename note — but tracing its git history shows it was never
present at the merge-base (`e7733cb8`) either, and is absent on BOTH parents identically. It
predates this merge's scope entirely (created 2026-08-25 per its frontmatter, a month before
either side of this merge diverged) — not something this merge broke or could have fixed. Flagged
below as Finding 1, explicitly scoped as pre-existing/out-of-merge-scope, per the brief's request
to report "any OTHER stale filename references" even when they don't implicate the merge itself.

### 5. Version files — CLEAN, verified

`pubspec.yaml` (`version: 1.0.0+46`) and `lib/core/constants/app_constants.dart` (`appVersion =
'1.0.0+46'`) agree. No BOM on either file (`head -c 6 | xxd` on both starts with real content,
not `EF BB BF`); `file` reports both as plain "Unicode text, UTF-8 text" (no BOM variant); no
`â€` mojibake sequences found. Traced why this class didn't recur: this branch's own `ad3fed06`
already fixed a BOM/mojibake corruption inherited from an earlier origin/main snapshot at
version `+45`; origin/main's subsequent bump to `+46` (`a0c46809`) is a clean two-line diff on
both files with plain ASCII content (verified via `git show a0c46809 -- pubspec.yaml
lib/core/constants/app_constants.dart`), so there was nothing corrupted left for the final merge
to reintroduce.

### 6. Generated-index consistency — CLEAN, verified (see also §3)

Re-ran both generators (`build_oi_index.dart`, `build_bug_index.dart`) against the current
merged tree; both reported success (142 OI entries, 536 bug entries) and produced **zero
uncommitted diff** — confirmed via `git status --porcelain` / `git diff --stat` before and after.
Working tree left exactly as found (clean, no residual changes committed or left staged).

## Finding 1 — P3 — merge_integration_overlap (informational; not caused by this merge)

**Claim**: `.claude/skills/code-review/SKILL.md:2532` cites `docs/reviews/eb37932a4218-review.md`
and `docs/reviews/a51a2ba9de14-review.md` as the two review artifacts for the 2026-08-25
`launch-blockers-1`/`launch-blockers-1a` catastrophic-tier entry. `a51a2ba9de14-review.md`
exists; `eb37932a4218-review.md` does not, and unlike the other stale-name cases in the same
file (lines 405-406, 1555-1605), this citation carries no "renamed to X" annotation pointing a
reader at the real file — so a reader looking this citation up today hits a dead reference with
no breadcrumb.

**Verification performed**: `git log --oneline --follow --diff-filter=A -- 
docs/reviews/eb37932a4218-review.md` → created once at `d45d7182`. `git show
15d43fd9^1:docs/reviews/eb37932a4218-review.md` and `git show
15d43fd9^2:docs/reviews/eb37932a4218-review.md` both fail (MISSING on both merge parents).
`git show $(git merge-base 15d43fd9^1 15d43fd9^2):docs/reviews/eb37932a4218-review.md` also
fails (MISSING at the merge-base). The gap therefore predates this branch's fork point entirely
and both sides of `15d43fd9` inherit it identically — it is not a merge-created or
merge-exposed defect, and no commit in this merge's 29-commit combined range touches this file
or this SKILL.md line.

**Why flagged anyway**: the task brief explicitly asked "are there any OTHER stale filename
references left... pointing at files that don't exist" — this is one, and it sits directly
adjacent (same file, same class of citation) to the bug this merge specifically fixed for
`d2ce94ab0a72`, so it's worth a name even though fixing it is not this merge's responsibility.

**Suggested fix**: find the file's final on-disk name (likely renamed under the same
hash-fixed-point convention documented elsewhere in this same file) and update line 2532 with a
rename annotation, or file it as a standalone doc-hygiene item — not blocking, not part of this
merge's remediation.

**Status**: spawned (pre-existing, predates this branch's fork by a month; not part of this
merge's remediation — spun off as a standalone task rather than blocking sign-off).

## Explicitly ruled out / checked clean with no findings

- **Numeric migration collisions** (§1) — none; only this branch added files in [141,143].
- **Cron job double-definition or drift re-introduction** (§1) — the one real cross-branch cron
  regression in this lineage was already caught and fixed one merge earlier (`ad3fed06`/143,
  predating `15d43fd9`); nothing in `15d43fd9`'s actual 25 incoming commits touches cron/RLS/
  migrations to reopen it.
- **Edge Function / table interaction between origin's Gemini-telemetry wiring and this branch's
  DB cleanup** (§2) — verified no read/write overlap on `readiness_daily`,
  `ai_coach_interactions_tool_calls_failed`, `nutrition_log_items`, or `memory_embeddings`'s
  ivfflat index between the two changesets.
- **OI board duplicate/gap/orphan numbers** (§3) — none found across the full 234-242 range or
  repo-wide.
- **Version-file corruption reintroduction** (§5) — none; both files clean, no BOM, no mojibake,
  values consistent.
- **Stale generated indexes** (§6) — none; both regenerate byte-identical to committed state.
- **Leftover conflict markers anywhere in the tree** — none, repo-wide sweep.
- **Client-code (Flutter/Hive) commits in origin's incoming range** (train exercise-log
  normalization, ai-coach rank/ETA fixes) — no overlap with this branch's Postgres-only changes;
  different layers entirely.
