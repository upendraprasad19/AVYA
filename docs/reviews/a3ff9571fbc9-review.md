---
reviewed_at: 2026-07-26T12:35:00+05:30
staged_against: cron-secret-auth (catastrophic)
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 3
verdict: accepted
---

# Code Review (B-pass) — cron-secret-auth

Fresh Sonnet reviewer, no conversation context. Diff: restore cron auth after ~8 weeks of
fleet-wide 401s. Escalated to catastrophic by the gate (`_shared/cron_auth.ts` is catastrophic by
path; migrations 107/109/110 by SECURITY DEFINER content rule).

## Finding 1 — P1 — blast_radius_mismatch
- **file:line:** `docs/plan-reviews/cron-secret-auth.md:4`
- **claim:** The record self-declared `blast_radius: platform` and concluded "not catastrophic → no
  Hermes". `dart run scripts/blast_radius_from_diff.dart` on the staged diff prints
  `Blast-radius: catastrophic`. `check_plan_review_record_exists.dart` does not trust the declared
  field — it recomputes from `HEAD^1...HEAD^2` and would have rejected the merge. Catastrophic
  requires BOTH `bpass: accepted` and `hermes: accepted`. Sharper: the migrations were already
  applied to production while the record understated the tier.
- **verification:** `dart run scripts/blast_radius_from_diff.dart`
- **status:** **fixed** — corrected to `catastrophic`, Hermes pass run
  (`docs/audit/2026-07-26-hermes-cron-secret-auth.md`), and the understatement recorded in the
  record itself rather than quietly amended.

## Finding 2 — P2 — doc-accuracy
- **file:line:** `docs/diagnoses/2026-07-26-cron-auth-jwt-secret-unreachable-c3f8a1.md:5`
- **claim:** `status: fix_authored_awaiting_apply` contradicted `backups/applied_migrations.json`
  in the same commit, which timestamps all three migrations as applied. Live state confirms the fix
  shipped. That status value appears exactly once across ~380 diagnose-docs; the convention for
  completed work is `fixed`. A future audit filtering for unshipped work would misread it.
- **verification:** `grep -n "^status:" docs/diagnoses/…c3f8a1.md` vs the manifest entry
- **status:** **fixed** — now `status: fixed`.

## Finding 3 — P2 — secrets-comparison
- **file:line:** `supabase/functions/_shared/cron_auth.ts:95`
- **claim:** `if (token !== cronSecret)` is a non-constant-time comparison. The file's own docstring
  states this is the ONLY gate in front of 16 publicly-reachable endpoints driving push sends,
  Gemini spend and Storage deletion, and migration 107 records the live secret as low-entropy by
  accepted risk. `!==` short-circuits on the first differing character; a weak secret plus a timing
  oracle is worse than either alone. Carried forward from the pre-rewrite version — not a new
  regression, but the rewrite was the natural point to close it.
- **verification:** `grep -n "token !== cronSecret" supabase/functions/_shared/cron_auth.ts`
- **status:** **fixed** — replaced with `timingSafeEqual`, hashing both sides to fixed 32-byte
  digests and comparing with a full-length XOR accumulate. Hermes L21 independently verified it is
  sound and fail-closed.

## Lens coverage

- **writer_reader_drift — clean.** Verified against live DB, not just source: the Vault row name vs
  `private.cron_get_secret()`'s read; `cron_call_log` columns written by `cron_telemetry.ts` vs read
  by 109's alert; `public.alerts` columns vs the INSERT list; the trigger repoint; all 23 `cron.job`
  rows classified by accessor. No drift.
- **function_exception_swallow — clean.** Zero new invoke/rpc/fetch call sites. `logCronStart` has
  exactly two reachable exits, both calling `logCronEnd`; the per-user catch continues the loop
  rather than returning. Live: 28/28 rows `success`, none stuck in `started`.
- **blast_radius_mismatch — Finding 1.** Substantively the change is sound: rollback documented and
  real for every migration; no privilege widening (`has_function_privilege` false for
  anon/authenticated on all three functions); the documented a9d3f1 public-schema grant trap is
  correctly handled with an explicit `REVOKE … FROM anon, authenticated`; `search_path` pinned.
- **secrets_in_tree — clean.** No credential-shaped literal. `cron_secret` appears only as a Vault
  row *name*, never a value, honouring the migration's own instruction.
- **unawaited_no_error_sink — clean.** Zero `unawaited(` and zero floating `.then(` introduced.

## Additional verification performed

- Pulled the **actual deployed bundle** for `streak-guardian` (not redeployed by this batch) and
  confirmed its bundled `cron_auth.ts` is the old version whose `CRON_SECRET` branch runs *before*
  the dead JWT branch — proving the ~15 un-redeployed functions keep working with no fleet-wide
  redeploy. Verified rather than assumed.
- Confirmed `cron.schedule` upserts by name in pg_cron 1.6.4, so re-running a migration neither
  duplicates nor errors; live `GROUP BY jobname HAVING count(*)>1` returns zero rows.
- Probed the new regression test's regex: 77 real matches in-tree, and it genuinely fails against
  reconstructed pre-fix source. Not vacuous.
- Re-ran the suites and gates rather than reading them: 110 contract tests pass, diagnose-doc
  validator passes, Gate 31 passes, migration parity passes, and the recorded sha256 hashes verify
  byte-exact against the on-disk migration files.

## Triage

All three findings **accepted and fixed in-batch**. No false alarms. Verdict: **accepted**.
