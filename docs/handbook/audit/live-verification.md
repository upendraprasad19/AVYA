---
title: Audit findings require live verification before action
category: audit
source_memory: feedback_audit_findings_require_live_verification.md
last_reviewed: 2026-05-28
---

# Audit findings require live verification before action

## The rule

Multi-agent audits do well on inventory (what tables exist, what counts), poorly on causal claims (what code does, why a value is NULL). Treat their causal claims as hypotheses, not findings.

Never apply an audit finding without:

- (a) The verifying SQL / file:line cited in the fix commit or diagnose-doc, OR
- (b) A clean repro that matches the audit's description.

## How to verify before acting

1. **Schema claims** ("column X exists on table Y"): `SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name=Y;` — costs 1 MCP call.

2. **Code-path claims** ("function F reads Z"): Read the cited file:line. Always.

3. **Telemetry claims** ("N errors in 24h"): grep `client_errors` directly with the cited op_type. Confirm the timestamp window — old errors may be stale by the time you read the audit.

4. **Cron/runtime claims** ("function never ran successfully"): check `net._http_response` for the status_code distribution; check the relevant cloud column for the side-effect the function should have produced.

5. **Index-arbiter / ON CONFLICT claims**: run `INSERT ... ON CONFLICT (...) DO UPDATE` inside `BEGIN ... ROLLBACK` against the live schema. Verify the index is non-partial OR all arbiter columns are NOT NULL. See [`partial-unique-arbiter.md`](../bug-classes/partial-unique-arbiter.md).

If the audit cites a code path that's already correct, mark the finding CLOSED as false alarm in the consolidated report. Document the verification SQL so the next person doesn't re-investigate.

## Pair the survey with a second reader

Master Audit found 18 items a single audit missed (including a Vault root cause — the single biggest finding of the day). Codex found 5 items Master missed. **Neither alone catches everything.** Run BOTH passes, dedupe + verify, then act.

This generalizes to ALL multi-agent surveys (audits, code reviews, security passes): always pair the survey with a second independent reader before acting on any individual finding.

## Instances

Real false-positive rate on a 4-agent parallel Master Audit producing 21 findings: 3 of 21 (~14%) were false positives.

- P1-A claimed `_restoreCoachMemory` queries the wrong column. Reality: code already SELECTed the correct column; the apparent legacy reference was the Hive key (intentional back-compat).
- P1-B claimed a sync ordering issue. Reality: already fixed in a prior batch; the cited FK violations were all from BEFORE the fix landed.
- P1-F claimed `user_profile.terms_accepted_at` columns were MISSING. Reality: columns exist on `users` (not `user_profile`). The audit conflated table names.

Each false positive cost 2-5 minutes to disprove. Saved hours of wasted code edits by verifying first.

A separate audit cited "23 successful runs of <function>" with "upsert silently failing" — actually `signals_computed_at` was NULL because cron sent Bearer null pre-Vault. The function never ran successfully. The audit saw symptoms (NULL field) but inferred the wrong cause (RLS).

## References

- Related: [`verifier-cannot-trust-subagent.md`](verifier-cannot-trust-subagent.md), [`lens-methodology.md`](lens-methodology.md), [`audit-closure-yaml.md`](audit-closure-yaml.md).
