---
branch: cron-secret-auth
date: 2026-07-26
blast_radius: catastrophic
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/a3ff9571fbc9-review.md
hermes: accepted
hermes_report: docs/audit/2026-07-26-hermes-cron-secret-auth.md
---

# Plan-review record — Batch 0 / restore cron auth (catastrophic)

Keystone record for the §4.12 merge gate.

⚠ **Tier corrected 2026-07-26, B-pass finding 1.** This record originally self-declared
`platform` and concluded "no Hermes needed". That was wrong twice over:
`docs/blast_radius.yaml` lists `supabase/functions/_shared/cron_auth.ts` as **catastrophic by path
alone**, and separately a content rule escalates `107` and `109` to catastrophic because they define
`SECURITY DEFINER` functions. `dart run scripts/blast_radius_from_diff.dart` on the staged diff
prints `Blast-radius: catastrophic`.

That matters beyond bookkeeping: `check_plan_review_record_exists.dart` does **not** trust this
field — it recomputes the tier from `HEAD^1...HEAD^2` at merge time and would have rejected the
merge. Catastrophic requires BOTH `bpass: accepted` and `hermes: accepted`.

Sharper still: the migrations were **already applied to production** while this record understated
the tier. The apply itself was founder-authorised and is verified working, but it shipped ahead of
the review depth its own tier mandates. Recorded here rather than quietly corrected.

## Scope

Every cron-dispatched Edge Function had returned HTTP 401 on every tick for ~8 weeks. Fix moves the
fleet from an unreachable JWT-verify gate onto a shared-secret gate.

- `107_cron_secret_auth.sql` — new `private.cron_get_secret()` accessor (raises on missing secret);
  ACL hardening on both Vault accessors; repoints **16** `verify_jwt=false` cron jobs; repoints the
  `dispatch_proactive_coach_promotion` trigger function.
- `108_cron_secret_auth_verify_jwt_jobs.sql` — the 2 `verify_jwt=true` jobs, gated on a deploy + two
  gateway-flag flips.
- `109_cron_silence_alert_and_log_cleanup.sql` — creates the missing `cleanup_cron_call_log()`;
  adds absence-based `alert_cron_silence`.
- `_shared/cron_auth.ts` — rewritten to a pure shared secret; dead JWT branch and the
  `deno.land/x/jose` dependency removed.
- `compute-coach-signals/index.ts` — auth gate + telemetry added (it had neither).
- `cron_auth_adoption_test.dart`, `cron_telemetry_adoption_test.dart` — both newly-gated slugs added;
  a broken regex fixed.
- `cron_auth_no_reserved_prefix_env_test.dart` — new regression guard.

Diagnose-doc: `c3f8a1`. Recurrence of `5a65bd`.

## Ground truth verified (live, project `dedsavbjuwgarrhphgnl`)

Every number below was confirmed by direct query, not taken from a subagent summary:

- 401s across `streak-guardian`, `workout-window-closing`, `protein-gap-alert`, `expiry-reminder`,
  `plateau-alert`, `i-see-you-callout`, `compute-admin-metrics-daily`, `pr-detection` (~40×/day).
- Vault `service_role_key` decodes valid: HS256, `role: service_role`, `ref` correct, exp 2036 —
  so the token both prior fixes chased was never the defect.
- `SUPABASE_JWT_SECRET` absent from custom AND default secret lists; dashboard rejects the name;
  Supabase docs confirm the reserved prefix is a platform limit.
- 22 cron jobs, all `username=postgres`; 17 on the Vault accessor, 1 on the NULL-returning
  `app.settings.service_role_key`; 18 HTTP total; 16 selected after excluding the 2 `verify_jwt=true`.
- `cron_call_log`: 6 rows, all predating the 7-day retention window; jobid 23 failed 70×.
- `coach_memory.signals_computed_at` max = 5s after jobid 8's dispatch (proving it works today).
- `admin_metrics_daily`: 0 rows despite 13 dispatches.

## Round 1 — 12 findings, 2 blocking

**P0 — a uniform repoint would have broken the only working cron job.** `verify_jwt` is not uniform.
`compute-coach-signals` is `verify_jwt=true` with **no module gate**, so the service_role JWT clears
the gateway and it simply runs — it is the sole survivor of the outage. An opaque token dies at the
gateway, so repointing it would have killed it. `compute-admin-metrics-daily` is also
`verify_jwt=true` and would have stayed broken. Worse, the original `n <> 18` guard would have
reported full success on 16-fixed/1-regressed/1-untouched.

**P1 — the `proactive-coach-promotion` trigger was missed entirely.** It calls the same accessor but
is not a `cron.job` row, so the loop could never see it.

Also: not idempotent; `n` counted matches rather than changes; `'Bearer ' || NULL` is NULL not
`'Bearer '`; the Vault secret is weak; `CRON_REGISTRY.md` would go stale with Gate 31 blind to it.

**Applied:** split into 107 (16 jobs + trigger) and 108 (the 2, post-flip); exclusion made semantic
rather than by hardcoded jobid; no-op detection; idempotency counter; factual corrections. Also
reverted a `search_path TO ''` "hardening" I had added mid-fix, which would have risked breaking
Vault decryption to address a P3 nit.

## Round 2 — on the hardened plan, 10 findings, 1 blocking

Round 2 independently re-verified the round-1 correction against live `cron.job` (16 selected, 2
excluded, no off-by-one in the counter across fresh / re-run / post-108 states) and confirmed it
complete — no third `verify_jwt` case hiding.

**P0 — the batch cannot be committed as authored.** `applied_migrations_parity_test.dart` fails: the
manifest ends at 106. Not fixable by appending three entries, because that file is an *applied* audit
log and 108 cannot be applied until the deploy and flag flips are done. Resolution is a commit/apply
interleave, recorded below.

**P1 — 109 would have destroyed the incident's own evidence.** All 6 `cron_call_log` rows predate the
7-day window, so the first successful cleanup tick after 109 creates the function would wipe the
table — and the new alert would then report "no cron execution has EVER succeeded", which is false.
Fixed: the delete now always spares the most recent success row.

**P1 — the newly-gated functions had no test coverage.** Both adoption lists are hardcoded, so 92/92
passed *because* the new slugs were absent. Added both; the suite is now 107 assertions.

**P1 — no regression test, and one planned test contradicted what shipped.**
`cron_telemetry_logs_before_auth_gate_test.dart` would have asserted the very reorder 109 rejects.
Dropped it; wrote `cron_auth_no_reserved_prefix_env_test.dart` instead, which fails on pre-fix source.

**P2 — the accessor reproduced the NULL-propagation shape the migration itself indicts.** Now raises.

**P2 — severity calibration.** A total outage opened at `info` for its first six hours. Now `warn`
at 2h, `critical` at 6h.

**P2 — four diagnose-doc statements contradicted the migrations**, including one instructing a future
reader to build the vulnerability 109 exists to avoid. All corrected.

## Convergence

Round 2 surfaced no new *design* defect — its P0 is a process/sequencing issue and its P1s are
correctness bugs in newly-added files that round 1 never saw. The core approach (shared secret,
16+2 split, absence alert) survived both rounds unchanged and was independently re-verified against
live state in round 2. Converged.

## Apply order (hard dependencies — one sitting, not a sequence of batches)

1. ~~Regenerate `CRON_SECRET` strongly in both Vault and Edge secrets.~~ **Founder decision
   2026-07-26: apply with the existing secret and rotate later.** Recorded as an accepted risk in
   107's header — the value is 20 chars, letters only, contains a dictionary word, and becomes the
   sole gate on `verify_jwt=false` endpoints including `clean-orphan-media` (deletes Storage).
   Rotation needs no migration and no redeploy: update the Vault row and the Edge secret to the same
   new value; both are read at call time.
2. Apply 107 + 109 → record in `backups/applied_migrations.json` → commit A.
3. Deploy `compute-coach-signals` (gate lands while `verify_jwt` is still true → double-protected).
4. Flip `verify_jwt` → false on `compute-coach-signals` and `compute-admin-metrics-daily`.
5. Apply 108 → record → commit B.
6. Positive smoke: POST a `verify_jwt=false` cron function with the secret, expect 200; confirm
   `cron_call_log` receives rows and `coach_memory.signals_computed_at` advances on the next tick.

Consider `cron.alter_job(8, active := false)` before step 3 and re-enabling after step 6 — between
the deploy and the repoint, jobid 8 is dead and, because the gate precedes telemetry, that loss
writes no row.
