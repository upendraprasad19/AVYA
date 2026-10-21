---
reviewed_at: 2026-10-21T17:40:00+05:30
staged_against: 932ed0c3aa7d
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [merge_integration_overlap, writer_reader_drift, blast_radius_mismatch, missing_input]
findings_count: 1
verdict: accepted
---

# Merge-Integration Review — 932ed0c3aa7d (merge of origin/main `d483a800` into `swap-move-design`)

Reviewed staged merge `932ed0c3aa7d`; this file is named by the post-fix staged hash `5f87f83a044d`
(the P3 label fix and a context-budget re-record moved it). Scope, per the `15d43fd9-merge-review.md`
precedent: only whether COMBINING two already-reviewed sides broke something. Ours = `8d53d25b`
(in-workout ⇄/⇅ move, account; `215812fec86a-review.md`). Theirs = PR #139 `oi341-piece-b2-door`
(payments Edge Functions, catastrophic; `64b21cb79f3c-review.md` + hermes). Base `7ff9542b`.

The merge is catastrophic only because theirs is: the gate hashes the whole merged-in diff.

## Context established before reviewing
- Ours 32 files, theirs 34; 5 changed on both sides: `tuning-history.md`, `OPEN_INDEX.md`,
  `open_issues.md` (hand-resolved), `naming_conventions.md`, `sot_registry.yaml` (auto-merged).
- Theirs touches no `lib/`, `test/`, `pubspec`, `android`, `scripts/` file: no code-level overlap.
- No unmerged index entries; no conflict markers in staged content.

## Finding 1 — P3 — missing_input
- **file:line:** docs/audit/open_issues.md (OI-372 `Verified` line)
- **claim:** provenance named the pre-merge main `7ff9542b`; after this merge it is `d483a800`.
- **verification:** `grep -c 'merged with origin/main \`d483a800\`' docs/audit/open_issues.md` → 1
- **status:** accepted — fixed in the merge commit. The cited code facts sit in files theirs does
  not touch, so they stay valid.

## Lenses that returned clean
- Hand resolutions: unique `## OI-N` headings (OI-366/367 theirs, then OI-372 ours); OPEN_INDEX
  anchors equal the real heading lines; both 2026-10-21 tuning entries present once each.
- `sot_registry.yaml`: no duplicate `concept:` key; no `line_range` edited by both sides; theirs'
  ranges are only in `supabase/functions/**`, so ours' `train_provider.dart` ranges are unshifted.
- `naming_conventions.md`: both sides' rows kept; the one repeated term ("gate") predates the merge.
- `blast_radius.yaml`: only theirs changed it (adds `create-razorpay-order/**` catastrophic); no
  file ours touched changed tier.
- Self-numbered files: no new collision (the one repeated diagnose id predates the merge).
- Context budgets: merged sizes within the soft band; re-recorded in this commit.

## Founder triage notes
Author triage: 1 P3, fixed. Each side keeps its own plan-review record and B-pass.
