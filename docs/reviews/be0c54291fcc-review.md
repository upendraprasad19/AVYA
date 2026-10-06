---
reviewed_at: 2026-09-22T00:00:00+05:30
staged_against: be0c54291fcc
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [integration-focus, writer_reader_drift, guard_without_its_mirror]
findings_count: 1
verdict: accepted
---

# Code Review — be0c54291fcc

**Note:** originally staged against `ee6c346ffd80`; renamed after fixing this
review's own Finding 1 shifted the staging hash (fixing the citation drift
touched `docs/sot_registry.yaml` and the diagnose-doc, neither excluded from
the hash) — the hash-fixed-point class this skill's own tuning history already
documents extensively. No review content below changed as a result of the
rename, only the filename/frontmatter/header.

## Scope note

This is a merge-integration review of two already-individually-reviewed branches
(`claude/food-logging-observations-126ab3` — accepted at
`docs/reviews/b87e8a1f3f2a-review.md` — merging in `main`, which already contains
`claude/strange-merkle-c2d0b9` via PR #32, accepted at
`docs/reviews/f81f7ae899e1-review.md`). Per the dispatch brief, internal
correctness of either half was NOT re-reviewed from scratch; only the interaction
surface between the two changesets was investigated. Topology confirmed via
`git rev-parse --git-path MERGE_HEAD` → `81b7e230…` (= PR #32 / `main`, i.e.
Branch B) and `git merge-base HEAD MERGE_HEAD` → `95e93606` (Branch A's own
divergence point, also present verbatim in Branch A's own history).

## Highest-priority focus: `supabase/functions/daily-snapshot/index.ts`

**Branch B's entire contribution to this file, isolated via
`git show 0dcab614 -- supabase/functions/daily-snapshot/index.ts`, is exactly one
line:** `retries: 2, // f7a2c9` added at line 155, inside `extractCoachingNotes()`
(the Gemini coaching-notes-extraction call) — nowhere near the merge-safe upsert
logic. `geminiChat`'s `retries?: number` parameter is genuinely implemented in
`_shared/gemini.ts` (a real retry loop, not a dead/ignored field), so this is a
functionally valid, self-contained addition.

1. **Branch A's `mergeSnapshotJson` read-modify-write is fully intact post-merge.**
   Read the complete current file (479 lines): the `DISABLE_SNAPSHOT_MERGE_SAFE_UPSERT`
   kill-switch, the `.maybeSingle()` pre-read, the `mergeSnapshotJson(existingRow?.snapshot_json, snapshot_json)`
   call, and the upsert of `mergedSnapshotJson` (not the raw `snapshot_json`) are all
   present, contiguous, and unmodified by Branch B. Clean.
2. **Branch B does not reintroduce a wholesale-replace or bypass the merge-safe path.**
   Its one-line change is in a different function entirely (coaching-notes
   extraction, not the snapshot upsert). Confirmed by diffing Branch A's HEAD
   against Branch B's tip for this file (`git diff HEAD...MERGE_HEAD -- …`) — the
   only hunk is the `retries: 2` addition. Clean.
3. **No second client-side snapshot field with the `fitness_summary` shape.**
   Branch A's `fitness_summary` strip (`sync_service.dart:1211`,
   `snapshot.remove('fitness_summary')`) is untouched — `lib/core/services/sync_service.dart`
   and `lib/features/ai_coach/services/ai_snapshot_builder.dart` (the shared
   `buildAiContext()` builder) are **absent from the merge diff entirely** — Branch
   B touches neither file (confirmed via `git diff --cached --stat -- '**/sync_service.dart'`
   equivalents and the full 79-file stat listing). Branch B's other `lib/`
   changes (`ai_coach_provider.dart`, `coach_interaction_repository.dart`,
   `ai_coach/screens/ai_coach/screen.dart`, `nutrition_provider.dart`) were grepped
   for `user_daily_snapshots|compileDailySnapshot|pushSnapshot|snapshot_json` —
   the only hit is `nutrition_provider.dart:1342`'s pre-existing
   `unawaited(SyncService.instance.pushSnapshot())` call (triggers a sync, adds no
   new field to the payload). Clean.

## Finding 1 — P2 — writer_reader_drift (citation drift, merge-caused)

- **file:line:**
  - `docs/diagnoses/2026-09-21-morning-alert-snapshot-clobber-d8a2f6.md` (frontmatter `writers:` list, the `daily-snapshot/index.ts` entry: `line_range: "339-397"`, prose citing `:356`, `:362`, `:383`, `:396`)
  - `docs/sot_registry.yaml:860` (`daily_snapshot_server_key_preservation` concept, `daily-snapshot/index.ts` writer entry: `line_range: 339-397`, prose citing `:356`, `:362`, `:383`, `:396`)
- **claim:** These two files (both authored by Branch A, both describing the SAME
  fix) cite four specific line numbers plus a line range inside
  `supabase/functions/daily-snapshot/index.ts`. All five were verified **exactly
  accurate** against Branch A's own pre-merge tip. Branch B's single-line insertion
  at line 155 of this same file (see above — unrelated to this concept, in a
  different function) shifts every line below it down by exactly one. Post-merge,
  all five citations now point one line too early.
- **verification:** Compared `git show HEAD:supabase/functions/daily-snapshot/index.ts`
  (Branch A, pre-merge) against the current merged file on disk via `grep -n` on
  the exact cited constructs:
  | construct | cited as | HEAD (pre-merge) actual | merged-tree actual |
  |---|---|---|---|
  | `const mergeSafeDisabled =` (kill-switch) | `:356` | **356** ✓ | **357** (drifted) |
  | `const { data: existingRow… } =` (pre-read) | `:362` | **362** ✓ | **363** (drifted) |
  | `mergedSnapshotJson = mergeSnapshotJson(` | `:383` | **383** ✓ | **384** (drifted) |
  | `snapshot_json: mergedSnapshotJson,` (upsert body) | `:396` | **396** ✓ | **397** (drifted) |
  | block range | `339-397` | matches 339 (`getTodayIST()` call) … 397 | now 340…398 |

  All four exact matches at HEAD, all four off-by-one post-merge — confirms the
  drift is caused specifically by combining the two branches, not a pre-existing
  inaccuracy. (Two OTHER citations in the same two files —
  `sot_registry.yaml`'s `:373` for the `existingRowError` console.error, and the
  diagnose-doc's `ist_handling: line: 338` for the `getTodayIST()` call site —
  were **already** inaccurate in Branch A's own pre-merge HEAD, independent of
  this merge, so they are noted here for completeness but excluded from this
  finding's claim and left to Branch A's own process.)

  Checked whether a gate would catch this before it lands: `scripts/check_sot_registry_parity.dart`'s
  header documents that it verifies `line_range: N-M` is **in-bounds** (file has
  ≥ M lines) and that a bare `line: N` + `method:`/`fn:` entry has the named
  SYMBOL present **somewhere** in the file — it does not appear to parse or verify
  the free-text `:NNN` sub-references embedded inside `notes:`/method prose
  strings (its regex only captures the structured `line_range:` field). Both
  files' `line_range` values remain in-bounds after the shift (the file only grew
  by one line), so this would **not** fail the commit gate — it lands silently.
- **suggested-fix:** Bump the five citations in both files by +1: `:356`→`:357`,
  `:362`→`:363`, `:383`→`:384`, `:396`→`:397`, and `line_range: "339-397"` /
  `line_range: 339-397` → `340-398`. Since neither citation is gate-enforced at
  the sub-string level, this needs a manual edit in this merge commit (or a fast
  follow-up) rather than relying on a gate to force it.
- **status:** fixed — all five bumped in both files, each re-verified against
  the live merged file via `sed -n '<N>p'` before accepting (357/363/384/397,
  range 340-398). While in the same lines, also corrected the two pre-existing
  (not merge-caused, flagged above as out-of-scope) imprecise citations this
  same session's own earlier fix-round had introduced: `sot_registry.yaml`'s
  `:373` → `:378` (now points at the actual `console.error(` call, not the
  comment above it) and the diagnose-doc's `ist_handling: line: 338` → `340`
  (the real `getTodayIST()` call site). `check_sot_registry_parity.dart` and
  `validate_diagnose_doc.dart` both PASS post-fix.

## Secondary overlap checks

- **`docs/sot_registry.yaml` duplicate/contradictory concepts:** `grep -oE '^\s*- concept:\s*\S+' | sort | uniq -d` → empty. 147 total concepts, zero duplicate concept names. The `daily_snapshot_server_key_preservation` entry (the one both branches' work concentrates around) appears exactly once, with Branch A's three writers (`snapshot_merge.ts`, `daily-snapshot/index.ts`, `sync_service.dart`) — no competing/duplicate entry from Branch B. Clean apart from Finding 1's citation drift.
- **`lib/core/services/CLAUDE.md`:** diff is a single new 13-line paragraph (A3-follow re-audit note about `unawaited(SyncService.instance…)` call sites) with no line-number citations into any file Branch B touched (`sync_service.dart:1110`, `onboarding_provider.dart:701` — both confirmed absent from Branch B's diff). The separate pre-existing "3rd instance" pitfall row describing the `fitness_summary`/`daily-snapshot` mechanism narratively names files but cites no line numbers, so it isn't subject to Finding 1's drift. Clean.
- **`docs/audit/open_issues.md` — dropped/duplicated `## OI-N` entries:** `grep -oE '^## OI-[0-9]+' | sort | uniq -d` → empty (no duplicate numbers). Raw header count is **149**, not "in the 130s" as expected going in — investigated the gap: `docs/audit/OPEN_INDEX.md`'s actual per-entry table rows (`^\| OI-[0-9]+ \|`, not just any `OI-N` occurrence, which over-counts due to in-prose cross-references like "Blocked on: OI-52") number exactly **138**, matching the file's own "**138 open**" header. The 11-entry gap (OI-153, 155, 162, 172, 176, 181, 183, 189, 195, 204, 223) is fully explained: every one of the 11 carries `**Status**: CLOSED` in its body — they're closed issues awaiting the periodic archival-to-`closed_issues.md` sweep this repo already does batches of (per root CLAUDE.md's note on the 2026-08-30 archival of 27 entries), not a merge artifact. Not a bug; the hand-resolution of this file's real conflict did not duplicate or drop anything.
- **`.claude/skills/code-review/SKILL.md` §7 Tuning history coherence:** Both branches' newest entries are present, well-formed, and readable in sequence — Branch B's 2026-09-21 catastrophic entry (lines 251-347) immediately followed by Branch A's 2026-09-21(b) platform entry (lines 348-387, which **already documents this exact merge's fitness_summary finding** from Branch A's own prior B-pass — confirms that check independently), then Branch A's 2026-09-20(a) entry, seaming cleanly into the pre-existing chronological history below. No truncated sentences or orphaned text at either seam. One label oddity noted — two "2026-09-19 (c)" entries (`oi204-delta-sync` at ~444, a second topic at ~551) — but verified via `git show <merge-base>/<HEAD>/<MERGE_HEAD>` that this exact duplicate label already existed identically in all three trees before this merge; it predates both branches' divergence and is out of this review's scope.

## Out-of-scope observation (not an integration bug, noted for awareness only)

While tracing the `retries: 2, // f7a2c9` comment, found that two of Branch B's
own new diagnose-docs — `docs/diagnoses/2026-09-21-ai-failure-telemetry-gap-oi226-f7a2c9.md`
and `docs/diagnoses/2026-09-21-nutrition-ai-missing-backoff-retry-f7a2c9.md` —
share the identical `bug_id: f7a2c9` despite describing two distinct bugs (A5/OI-226
telemetry gap vs. A2b's 9-call-site retry fix). `docs/diagnoses/INDEX.md` already
carries both under the same id with no collision detection. This originates
entirely inside Branch B's own commit `0dcab614` and would exist even without
Branch A in the picture, so it is outside this review's integration-only mandate
and is not counted as a finding here — flagging only so it isn't lost.

## Founder triage notes

Self-triaged in-session per §4.3 (self-initiated ≥account review before merge)
— the single P2 finding was mechanical citation drift with a clear, precisely
verified fix (both gates re-run and green post-fix); no design judgment call
for the founder to make here. Flagging for awareness: this merge combines
`claude/food-logging-observations-126ab3` with `main` (which already contains
`claude/strange-merkle-c2d0b9` / PR #32) to resolve PR #31's merge conflict.
