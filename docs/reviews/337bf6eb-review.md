---
reviewed_at: 2026-08-01T00:00:00+05:30
staged_against: d229c012..HEAD (cda5b62c, 017014f1, 337bf6eb)
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh, context-blind)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 2
verdict: accepted
---

# Code Review (B-pass) — oi79-paged-cron-reads

All five lenses returned clean. Zero P0/P1. Two P2s, both process/tooling rather than
correctness in the shipped read-paging logic.

## Lens results

- **writer_reader_drift — CLEAN.** Every caller whose result shape changed from `{data, error}`
  to bare-array-or-throw was checked. `notification_prefs.ts:84-113` (first-row-per-user
  reduction) and `weekly-recap-ready:176-235` (`Promise.allSettled`, `.value` used directly, not
  `.value.data`) both consume the new shape correctly — no `.data` left dangling on an array.
  `evaluate-rank-promotions`' `fetchInChunks` deliberately re-wraps the throw into the old
  `{data,error}` shape so its 3 call sites are untouched; verified it does exactly that.
- **function_exception_swallow — CLEAN.** In every checked function a `paged_fetch` throw reaches
  the outer catch and ends the tick as `logCronEnd(..., "failed")`, never a 200 reported as
  success. `protein-gap-alert`'s inner catches at :315/:334 are scoped to the per-user Gemini/push
  calls, not the batch reads. `weekly-recap-ready`'s `Promise.allSettled` degrade-to-empty-map is
  a pre-existing deliberate design for a supplementary lookup, not a newly swallowed exception.
- **blast_radius_mismatch — CLEAN.** Diagnose-doc and ledger both self-declare `platform`; tier 6
  explicitly records the fleet as NOT yet deployed and requiring separate §4.3 authorization —
  correct treatment, not a silent deploy.
- **secrets_in_tree — CLEAN.** No credential-shaped literal in the diff.
- **unawaited_no_error_sink — CLEAN.** The only `unawaited(` hit in the diff is prose inside the
  diagnose-doc; no floating promises added.

## Finding 1 — P2 — off-schema `touched_layers_checked` status

- **file:line:** `docs/diagnoses/2026-08-01-unbounded-cron-reads-d3f7b2.md:94`
- **claim:** `status: pending_explicit_authorization` is not in CLAUDE.md §6's enum
  (`verified` / `fixed_in_this_batch` / `not_applicable` / `deferred`). Content legitimate, value
  off-schema. The validator passes it, confirming it does not enforce the enum.
- **verification:** `dart run scripts/validate_diagnose_doc.dart docs/diagnoses/2026-08-01-unbounded-cron-reads-d3f7b2.md`
- **status:** **accepted — fixed.** Rewritten to `status: verified`, stating the *verified delta*
  (16 functions differ between git and the deployed fleet, so the fix is inert in production).
  `not_applicable` would have been false; `deferred` both false and a banned semantic (§4.2).
- **Knock-on:** chasing this produced a material deploy-scope correction — the set is **16**, not
  15: the changed directories plus `proactive-coach-promotion` (imports the genuinely-changed
  `notification_prefs.ts`), while `ai-proxy` is excluded because its only changed dependency is a
  three-comment-line diff in `memory_retrieval.ts`.

## Finding 2 — P2 — blast radius could not be re-derived

- **file:line:** n/a — `scripts/blast_radius_from_diff.dart`
- **claim:** stdin-piped classification printed no `Blast-radius:` line, so `platform` could not be
  independently corroborated.
- **status:** **false_alarm — invocation, not tool.** The stdin form requires a trailing `-`
  (`… | dart run scripts/blast_radius_from_diff.dart -`); without it the script reads
  `git diff --cached`, empty after committing, and correctly prints nothing. Re-run correctly:
  `Blast-radius: platform`. Noted because the same footgun produced three wrong readings this
  batch — two mine, one the reviewer's.

## Author claims the reviewer independently verified as true

- 316 Deno tests, 0 failed.
- Gate scans 39 files, 5 waived — exact match including the 5 waiver sites.
- Closure ledger: 41 `id:` entries, 41 `terminal_state:`, zero real `deferred:` keys (the one
  occurrence is inside a comment describing the policy). Gate 40 PASS.
- Line citations spot-checked: `notification_prefs.ts:106`, `streak-guardian:177`,
  `workout-window-closing:233`, and the `rank_engine` waiver's 728-row figure all match code.
