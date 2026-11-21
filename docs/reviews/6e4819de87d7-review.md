---
reviewed_at: 2026-09-28T15:40:00+05:30
staged_against: 6e4819de87d7
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [merge_resolution, writer_reader_drift, ledger_integrity, guard_without_its_mirror, asserted_fixture_value, missing_input]
findings_count: 1
verdict: accepted
---

# Code Review — 6e4819de87d7 (merge of origin/main b7239acf into day-swapper-sync-load)

Origin/main moved 9 commits (single-owner-a2b: coach-extraction locked fields, migration 148,
metered daily-snapshot extraction, a founder-digest change). Merged before the Task 34 Edge
Function deploys, because main's `_shared/founder_digest_content.ts` and `_shared/coach_memory.ts`
changes sit inside the bundles this branch deploys, and a deploy from the unmerged branch would
have reverted them in prod.

Eight conflicts: `sync_coach.dart` (kept the branch side: it removed the `now()` fallback main had
made UTC, and derives `created_at` from the Hive key as UTC), the two JSON ledgers (148 then 149;
combined snapshot meta), `sot_registry.yaml` / `open_issues.md` / code-review `SKILL.md` (both
sides' appends kept), and the two generated indexes (regenerated).

One context-blind Sonnet reviewer checked all nine resolution areas live (JSON validity and entry
arithmetic, sha256 of both migrations against the ledger, column-set union, concept and OI-heading
dedup, regenerated indexes byte-identical, `deno check`, `dart analyze` on the `sync_service`
library, gate G2 run directly on the merged tree).

## Finding 1 — P2 — writer_reader_drift (stale prose count after a clean auto-merge)
- **file:line:** supabase/functions/_shared/founder_digest_content.ts (DIGEST_KEYS doc comment)
- **claim:** main bumped the comment to "eleven sections" / "7 of 11" when it added
  `coach_extraction`; the branch independently appended `day_swap`. No textual conflict, so the
  count went stale: 12 keys, 7 with `cap`.
- **verification:** `awk 'NR>=77 && NR<=110' supabase/functions/_shared/founder_digest_content.ts | grep -c 'key: "'` → 12; `grep -c 'cap: [0-9]'` → 7
- **status:** fixed — "twelve sections", "7 of 12" (coordinator re-counted).

## Gate-found at commit time (after the review)
- `check_sot_registry_parity` failed on main's new `coach_extraction_locked_fields` reader
  citation `ai_snapshot_builder.dart:999-1008`: the branch's additions to that file moved
  `_getCoachMemoryForContext` to 1011-1020. Repointed to the exact span; gate PASS. Same shape as
  Finding 1: a clean auto-merge of two correct sides leaves a line citation stale.

## Incidental, verified, not introduced by this merge
- `backups/applied_migrations.json` carries 145 and 146 twice each: identical at merge base, main
  and branch — the already-filed OI-258.
- `docs/sot_registry.yaml` is not valid YAML: 35 parse errors, present at the merge base
  (first at `c854332b`). No consumer uses a YAML parser — every gate reads it line-wise, and
  several invalid lines are regex `pattern:` strings gates consume verbatim, so a quoting fix is a
  gate-semantics change. Tracked as its own OI rather than changed inside a merge.

## Founder triage notes
One docs-only finding, fixed before commit. Resolution sound.
