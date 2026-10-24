---
bug_id: e1b7d4
date: 2026-07-28
batch: enforcement-infra
status: fixed
blast_radius: platform
symptom: >
  `main` went red twice in 25 CI runs on commits that touched no Deno code,
  both times with `Import 'https://esm.sh/@supabase/supabase-js@2.39.0' failed:
  522` at clean-orphan-media/index.ts:2. 522 is a Cloudflare origin timeout —
  an upstream CDN blip, reported as a test failure.
concept: ci_remote_dependency_resilience
sot_registry_entry: not_applicable
writers: >
  .github/workflows/test.yml job `deno-edge-functions` (the two steps that
  resolve remote modules); supabase/functions/clean-orphan-media/index.ts:2
  (the lone import of the outlier version)
readers: >
  GitHub Actions is the consumer — a red `Test & Analyze` blocks the merge and,
  per CLAUDE.md rule 20, is a P0 that stops the batch
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: not_applicable
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >
  a CI step that resolves remote modules with no retry; a version pinned in
  exactly one file while the rest of the tree standardises elsewhere; a
  hand-rolled cache at a guessed DENO_DIR when the setup action provides one;
  committing deno.lock, which .gitignore:129 records a deliberate decision
  against
proposed_fix: >
  Move the lone 2.39.0 import to 2.39.3 (36-file standard), enable
  denoland/setup-deno@v2's own module cache keyed on the EF tree, and retry both
  Deno steps 3× with backoff so a transient fetch failure is not reported as a
  test result.
regression_test_planned: >
  No unit test — the failure mode is a network condition, not a code path. The
  acceptance evidence is CI itself: the Deno job green, its log showing a cache
  hit rather than a Download storm on a second run, and no `2.39.0` import left
  in the tree.
touched_layers_checked:
  - { tier: 1_client_code, status: not_applicable, evidence: "no lib/ change" }
  - { tier: 2_hive, status: not_applicable, evidence: "no Hive surface" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema change" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no data touched" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: verified, evidence: "clean-orphan-media/index.ts changed in git; live function still runs the 2.39.0 bundle and works. Stated divergence, NOT an unstated residual — a redeploy is optional here and needs its own explicit go per §4.3." }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron schedule change" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: fixed_in_this_batch, evidence: "esm.sh is the external service that failed. Both failing runs read from the real logs: 30227648313 (2c4cbddd, 2026-07-27T00:32) and 30372950675 (93f6fe41, 2026-07-28T15:21) — identical URL, identical file:line. 2.39.0 had exactly ONE consumer; 2.39.3 (36 files), 2.42.0 and 2.45.4 all fetched successfully in the SAME runs, so the outlier was cold at the CDN edge." }
  - { tier: 12_client_server_contract, status: verified, evidence: "grep for a live `from 'https://esm.sh/@supabase/supabase-js@2.39.0'` import returns nothing; workflow YAML re-parsed with a YAML loader — 6 jobs, setup-deno carries cache: true + cache-hash, both Deno steps carry the retry loop." }
impact_analysis: >
  CI configuration plus a one-line dependency bump; no product behaviour. The
  retry can only turn a red into a green where the failure was transient — after
  3 attempts it still fails, and the error message says explicitly that a
  3-attempt failure is real, not a blip. Risk is a genuinely broken type-check
  taking ~45s longer to report. The version move is patch-level within the same
  minor. Deliberately did NOT touch the 2.42.0 or 2.45.4 refs: moving those to
  2.39.3 would be a DOWNGRADE, and neither has ever failed.
---

# CI kept going red because of somebody else's CDN

## What happened

Two of the last 25 `main` runs failed identically:

```
error: Import 'https://esm.sh/@supabase/supabase-js@2.39.0' failed: 522
    at supabase/functions/clean-orphan-media/index.ts:2:46
```

`93f6fe41` was a docs-only commit — three markdown files and a JS config map.
`deno check` reads none of them. The failure had nothing to do with either
commit; both simply had the bad luck to run while esm.sh's origin was timing
out.

## Why that URL and not the other fifty

The same run successfully downloaded `supabase-js@2.39.3`, `@2.42.0`, `@2.45.4`
and ~50 modules from `deno.land`. Only `2.39.0` failed, and it failed the same
way 39 hours earlier.

`2.39.0` is imported by **exactly one file in the repo**. `2.39.3` is imported
by 36. A version nobody requests is cold at the CDN edge; a popular one is warm.
That makes consolidating the outlier a real fix rather than a cosmetic tidy — it
deletes the cold URL from the tree entirely.

## Three changes, each closing a different part of it

1. **The outlier is gone.** `clean-orphan-media` now imports `2.39.3`.
   Deliberately not touching `2.42.0` (1 ref) or `2.45.4` (3 refs) — moving
   those to `2.39.3` would be a *downgrade*, and neither has ever failed.
2. **The module cache is on.** `denoland/setup-deno@v2` ships its own `cache`
   input; an earlier draft of this fix hand-rolled an `actions/cache` step at a
   guessed `~/.cache/deno`, which independent review flagged as reinventing the
   action's own mechanism. `cache-hash` normally defaults to hashing
   `deno.lock`, which is deliberately untracked here, so the EF tree is hashed
   instead. This is what makes an outage survivable: Deno does not re-fetch a
   cached, version-pinned remote URL without `--reload`.
3. **Both Deno steps retry 3× with backoff.** The general case: any of ~50
   remote modules can blip, and a transient fetch failure is not a test result.

## What was deliberately NOT done

An earlier draft proposed un-ignoring and committing `deno.lock` to get a stable
cache key. The comment directly above `.gitignore:129` records a decision from
**2026-07-27** not to track it — the suite "is green with no lockfile, so
tracking one would only add a lock-mismatch failure surface with nothing
depending on it." I had cited that line number as evidence while never reading
the four lines above it. The cache key needs no lockfile, so there was nothing
to trade.

## Residual, stated

Git and the deployed `clean-orphan-media` bundle now differ by one import line.
The live function works fine on `2.39.0`, so a redeploy is optional — but after
OI-47 sat merged-and-undeployed for a day while the board called it done, an
optional step gets *written down* rather than assumed. It needs its own explicit
go per §4.3.

## The class

`feedback_mistake_remote_dep_rot` records the same shape: a pinned remote URL
that can vanish or time out upstream, turning an unrelated commit red. That memory
says prefer `npm:`/`jsr:` specifiers. 71 Edge Function files still import via
`https://` URLs against 24 using `npm:`/`jsr:` — this batch buys resilience
(cache + retry) rather than converting them, because a 71-file specifier sweep
is a different change with a different risk profile and belongs in its own
reviewed unit, not bolted onto a CI fix.
