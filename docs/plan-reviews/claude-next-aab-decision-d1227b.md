---
branch: claude/next-aab-decision-d1227b
date: 2026-09-22
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/571c997e56b5-review.md
---

# Plan-review record — disk-io-audit-cleanup (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). Platform-tier
because the batch touches shared Postgres infrastructure (RLS policy, ivfflat index tuning, and
pg_cron scheduling consolidation) rather than a single feature — confirmed via
`dart run scripts/blast_radius_from_diff.dart` against the staged diff.

## Scope

A live production incident (Supabase disk-IO-budget exhaustion on project `dedsavbjuwgarrhphgnl`,
Nano/Free tier reading 91% Compute/CPU) investigated live via SQL against the running database,
not a pre-written implementation plan — the "planning" for this batch was the diagnosis +
brainstorm + per-item founder authorization cycle that happened conversationally, including
explicit `AskUserQuestion` approval for each of the two live-apply migrations (140 attempted and
withdrawn; 141 applied) and an explicit founder choice to defer the compute-tier upgrade (Fix E)
until after items A–F land. Full narrative, root-cause quantification, and per-item outcomes:
`docs/diagnoses/2026-09-22-disk-io-budget-exhaustion-e8b4a1.md`.

Six items originally scoped (A–F): (A) disable pg_cron's internal `job_run_details` logging —
BLOCKED, `cron.log_run` is a `postmaster`-context GUC, not settable via SQL, requires a full
server restart; (B) retune an oversized ivfflat index — APPLIED; (C) fix an RLS auth-initplan
warning — APPLIED; (D) drop 2 verified-dead indexes — APPLIED, then found PARTIALLY WRONG by this
review and CORRECTED via migration 142 (see Round 1); (E) compute tier upgrade —
founder-deferred spend decision, out of scope; (F) consolidate 9 pg_cron jobs into 3 — APPLIED.
B/C/D/F shipped together as migration 141; migration 142 applied same day as a follow-up.

**Update, same day**: migration 142 (Round 1's Finding 1 fix, below) has since been
founder-authorized separately in chat and applied live, closing what was originally this
record's one open item. Live-verified post-apply: `pg_indexes` confirms the restored index,
and a fresh `get_advisors` run confirms the `unindexed_foreign_keys` finding is gone. Its own
new test was mutation-proven via the scratch-copy protocol (142 is now itself immutable) —
see the diagnose-doc's Mutation proof section.

## Review rounds

**Round 1 — fresh, context-blind B-pass over the full staged diff**, dispatched per CLAUDE.md
§4.3's self-trigger requirement (no waiting to be asked). 8 findings, full detail and live
verification evidence in `docs/reviews/571c997e56b5-review.md`:

- **P1, real regression** (the most material finding): dropping `idx_nutrition_log_items_food_id`
  (item D) removed the SOLE index backing `nutrition_log_items_food_id_fkey`. `idx_scan=0` — this
  batch's own justification for dropping it — measures query-access paths only; it says nothing
  about FK-constraint-check coverage. Live `get_advisors` confirmed a new `unindexed_foreign_keys`
  finding that did not exist before 141. Checked the sibling drop
  (`idx_ai_coach_interactions_tool_calls_failed`) for the identical blind spot — verified clean,
  isolated to one index. Fixed: `supabase/migrations/142_restore_nutrition_log_items_food_id_index.sql`
  (drafted, staged, **awaiting live-apply authorization** — the one thing this record cannot close
  by itself).
- **P2 ×2, doc-only, fixed**: this doc's contract-test count was mis-stated as 9/9 when the file
  held 8 `test()` blocks (verified by actually running the suite); and a migration timestamp was
  misattributed (cited migration 138's cloud_version for `alert_cron_failures`, which is really
  migration 139's, 65 seconds later) — overstating a "~12h" gap that is really ~6h45m. Both
  corrected; the timestamp correction *strengthens* rather than undermines the section's own
  "negligible contribution" reasoning.
- **P3, doc-only, fixed**: a table row undercounted unchanged cron jobs by one (20 vs. the correct
  21 — the underlying rate arithmetic already summed 21 items; only the caption was wrong).
- **P3, real but latent, cannot retroactively fix**: none of migration 141's 9
  `cron.unschedule()` calls are guarded, and `cron.unschedule()` on a missing job name **raises a
  hard Postgres error** (independently confirmed live: `select
  cron.unschedule('definitely_does_not_exist_xyz_probe')` → `XX000`), not a silent no-op. Did not
  bite this time (all 9 targets existed at apply time) but was a genuine gap, most pointed for the
  one unschedule call the file's own comment already discloses a live cross-branch race for.
  141 is immutable post-apply, so this is documented as a lesson rather than fixed in place;
  migration 142 uses `CREATE INDEX IF NOT EXISTS` in direct response.
- **P3, considered, not applied**: whether this doc's A–F structure requires a
  `docs/audit/<batch>.closure.yaml` per §4.2's "≥4 findings/units" trigger. Decided no — that
  schema needs a `commit:` sha per `closed_in_commit` item, which cannot exist for a batch still
  staged as one pending commit — but flagged in both the review and the diagnose-doc as a
  genuinely open interpretive question rather than a closed one.
- **P4 ×2**: a cosmetic pubspec.yaml comment-placement fix, applied; and OI-235's "~93s/~116s avg"
  figures, which the reviewer flagged as unverifiable — independently re-run in Round 2 (below)
  and confirmed exactly correct, with a genuinely bimodal distribution added to the OI's
  description as a sharper clue rather than a correction.

**Round 2 — independent, context-blind, scoped re-review of the hardened diff.** Explicitly
instructed NOT to trust the "fixed" labels: re-verify every one of Round 1's 8 claimed
resolutions against live state / actual files, and separately hunt for anything the fix round
itself newly broke. All 8 resolutions **CONFIRMED CORRECT** by independent re-derivation (not by
re-reading the same claims) — including re-running the disputed OI-235 query from scratch and
reproducing 93.1s/116.0s exactly, settling Round 1's own "unverifiable" characterization as
itself mistaken. Found 3 new, purely mechanical residue items from the fix round's own rewrite —
none material, none in the actual database changes:

- A dead cross-reference: the diagnose-doc cited the B-pass review by its PRE-rename filename
  (`e100478657c7-review.md`) after the review was renamed to the final post-fix hash
  (`571c997e56b5-review.md`). Fixed.
- `backups/applied_migrations.json`'s note for migration 141 still said "9/9 passing" — technically
  wrong twice over: 141's own apply-time coverage was 8/8, and the file's now-9th test covers a
  separate, later, not-yet-applied migration (142). The ledger's free-text `note` field is
  descriptive metadata, not the hashed migration content, so correcting it does not touch the
  immutability rule. Fixed.
- The diagnose-doc's top-level `status: fixed` arguably overstated state given Fix A is open and
  migration 142 is unapplied; this repo has a precise precedent (`status: fixed_pending_live_apply`,
  `docs/diagnoses/2026-05-16-dead-columns-dropped.md`) for exactly this shape. Adopted.

All three were fixed directly (no third dispatch needed — they were individually verifiable and
correctable by direct inspection), then the full gate loop and contract-test suite were re-run
clean.

## Convergence

Round 2's findings were 100% mechanical (a stale cross-reference, a ledger-note precision issue,
a status-field precision suggestion) — none touched the actual SQL, the actual live-verified
facts, or introduced any new regression. This matches the same §4.12.1 convergence signal the
`food-logging-observations` precedent's own "Scoped final re-review" used: findings shrinking in
kind and severity round over round (Round 1: 1×P1 real regression + numeric errors; Round 2:
zero P0–P2, three sub-P3 documentation-staleness items caused by Round 1's own fix pass), not
growing or recurring. No third dispatch was needed because the three residual items were each
independently, directly verifiable and fixable without requiring further adversarial search.

## Ground truth verified

Every finding across both rounds was independently re-checked against actual repository state or
live Supabase data before being accepted or fixed — never taken on either reviewer's prose alone,
per `feedback_audit_verifier_cannot_trust_own_subagent.md`:
- The FK-index regression (Round 1's P1) was independently re-confirmed by the coordinator via
  `pg_constraint` + `pg_indexes` directly (not just re-reading the reviewer's `get_advisors`
  citation), and the mirror check (does the OTHER dropped index have the same defect?) was
  independently re-run rather than trusted from the first pass alone.
- The migration-timestamp correction (Round 1's Finding 3) was independently re-derived from
  `list_migrations`' raw version→name mapping by the coordinator, not accepted from the
  reviewer's arithmetic alone — and re-derived a THIRD time, independently, by the Round-2
  reviewer.
- The `cron.unschedule()` hard-error behavior (Round 1's Finding 5, which the reviewer explicitly
  declined to test live) was independently verified live by the coordinator with a safe,
  nonexistent-job-name probe, rather than left as an untested claim.
- OI-235's disputed numbers (Round 1 said "unverifiable"; the coordinator's fix said "confirmed
  correct") were settled by a THIRD, fully independent query in Round 2, run without reusing
  either prior query's text, landing on the exact same figures both other attempts did.
- `flutter test test/contracts/disk_io_audit_cleanup_batch_test.dart` run fresh after every edit
  round (not just once) — 9/9 green at each check; `validate_diagnose_doc.dart` run fresh after
  the `status:` field change; the full 86-gate `pre-commit.sh` loop run twice, the second time
  after fixing a real Gate-DEU failure the first full run caught (a literal, legitimate
  batch-name collision with the banned-phrase list, resolved by rewording, not by an exemption).

## Verification

- Contract test: `test/contracts/disk_io_audit_cleanup_batch_test.dart`, 9/9 green, mutation-proven
  on the ivfflat tuning value (two self-caught test bugs documented in the diagnose-doc's own
  Mutation proof section).
- `docs/reviews/571c997e56b5-review.md` — `verdict: accepted`, 8 findings, all resolved (6 fixed,
  1 mitigated-where-the-immutability-rule-allows, 1 a documented judgment call), each
  independently re-verified in Round 2.
- Full pre-commit gate loop (86 gates) green as of the final staged state, including Gate 40
  (audit closure), Gate-SDB (skipped-discipline budget), and Gate-DEU (deferral euphemism, after
  one legitimate false-positive fix).
- Working tree clean and fully staged at every checkpoint; no uncommitted drift.

## Residual, stated rather than hidden

- **Fix A** (disable `cron.log_run`) remains genuinely blocked — not a code fix, requires a
  Supabase support ticket and a brief server restart if pursued. Quantified in the diagnose-doc:
  its remaining value has shrunk from ~41.0MB/day to a projected ~18.0MB/day now that Fix F
  (cadence reduction, already live) has captured most of the same win independently.
- **Fix E** (compute tier upgrade) remains an explicit founder-deferred spend decision, unchanged
  since the original `AskUserQuestion` authorization.
- **The closure-YAML question** (Round 1 Finding 6) is left as a genuinely open interpretive
  question about §4.2's scope, not silently resolved either way — flagged for founder awareness
  rather than treated as settled.
- **OI-234, OI-235 (enhanced with live-verified bimodal detail), OI-236, OI-237** remain open by
  design — each tracks a separate, unhurried follow-up explicitly out of scope for this SQL-only
  batch.
