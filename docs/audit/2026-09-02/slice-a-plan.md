# Slice A — unchecked PostgREST results at gating decisions (v3, narrowed; CONVERGED)

- **Branch:** `techdebt-audit-sep02`
- **Parent:** tech-debt audit 2026-09-02 (`remediation-plan.md` §11)
- **Findings:** **CODE-6, CODE-8** — 2 items ⇒ under §4.2's ≥4 threshold, so per-fix diagnose-doc +
  TodoWrite discipline; **no `.closure.yaml` owed for this slice**.
- **Blast radius:** ≥`account` ⇒ plan-review record + self-initiated B-pass before merge (§4.3, §4.12.3)
- **Review status:** round 1 (3 BLOCKING) → round 2 (4 BLOCKING, 3 inside round 1's corrections) →
  **narrowed** → confirmation round: **`converged — safe to implement`**, 1 blocking doc-consistency
  fix (applied in this version).

---

## 0. What moved out, and why (§4.12.1 split, applied twice)

**CODE-7 + INFRA-14 → OI-162 (P1, security).** Round 2 proved CODE-7's corrected fix is a trap:
making the insert succeed introduces a NEW channel value, and `rolling-context/index.ts:351` filters
by `.neq("channel","app_event")` — a **denylist**, deliberately (`:347-350`). Its header (`:332-344`)
records the Hermes P1-E/P1-F incident of 2026-08-20 where exactly this embedded non-conversation rows
into `memory_embeddings` as `source_type='conversation'`, reaching ai-proxy's **SYSTEM prompt**, after
which the delete at `:466-472` removed them. Here that would leak `request_id=<hex>` into the model
**and** delete the rows the rate limit counts. It needs OI-153's channel-reader enumeration first.
INFRA-14 is that class's gate and travels with it (its naive spec measured 12 violations, **10 false
positives** from nested JSONB keys, and it cannot see the NOT NULL half at all).

**Confirmation review verified the two remainders are independent of both.** Different file for
CODE-7, no shared symbol. The only new column reference either fix adds is `.order("end_date")` —
`check_schema_column_refs.dart:59` already includes `'order'` in its filter-method set and `end_date`
is in the `subscriptions` snapshot, so it is validated **by the gate as it exists today**. INFRA-14
extends insert-map key extraction; neither fix adds an insert key.

## 1. §4.1.5 recurrence

| Prior bug | Relationship |
|---|---|
| **`c8f229`** (2026-05-17) | verify-payment ownership check *fail-open* when a field was absent — **CODE-8's shape**. Known-good pattern: fail closed + `test/contracts/verify_payment_notes_user_id_required_test.dart`. |
| **`9d12af`** (2026-05-16) | *"Hidden observability bug — silent for an unknown number of days"* on a rate-limit path — **CODE-6's shape** (a gating decision going wrong with no log). |

(`7ad009` moves to OI-162 with CODE-7.)

## 2. The two fixes

### CODE-6 — `checkPro` downgrades a paying user invisibly
- **Reader (the decision):** `supabase/functions/ai-proxy/index.ts:88-95` —
  `.eq("user_id",…).eq("status","active").gt("end_date",…).maybeSingle()`, then `return data !== null`,
  wrapped in `catch (_) { return false; }`. **Consumer:** `toolCtx.isPro` — false hides every PRO tool.
- **Defects:** (a) no `.order("end_date",{ascending:false}).limit(1)`, which its sibling
  `weekly-report/index.ts:74-84` **does** have — and there is **no UNIQUE on `subscriptions(user_id)`**
  (only `razorpay_payment_id`, migrations 052/094), so two overlapping active rows (a renewal bought
  before the old `end_date`) make `maybeSingle()` synthesise PGRST116 ⇒ `data` null ⇒ PRO lost;
  (b) `error` is never destructured and the catch is silent, so it is invisible.
- **Fix:** mirror the sibling's `.order().limit(1)`; destructure `error`; log it with the request id.
  **KEEP the fail-closed `return false`** — `:79-81` documents it as deliberate
  (*"cheaper to incorrectly gate a PRO user than to leak unlimited chat to a free user"*).
- **Behaviour-neutrality (confirmed):** for 0 rows `maybeSingle()` → `{data:null,error:null}`, and for
  1 row the result is identical. Only the ≥2-row case changes — from fail-closed to newest-row.

### CODE-8 — free user can obtain unlimited Gemini 2.5 Pro reports
- **Reader:** `weekly-report/index.ts:86` — `const { count: previousReportCount } = await supabase…`,
  **no `error` destructure** ⇒ on failure `count` is null ⇒ `:92` `isFirstReport = true` ⇒ `:95`
  `if (!hasPro && !isFirstReport)` does not fire ⇒ report generated.
- ⚠ **The mirror already exists at `:75`** — `const { data: subscription, error: subError }`. Same
  function, same author, mirror not applied: `feedback_mistake_guard_without_its_mirror.md`.
- **Writer:** `:559-568` — `await supabase.from("ai_coach_interactions").insert({…})`, result
  discarded. This is the **sole writer** for the reader at `:86`; if it fails silently,
  `previousReportCount` stays 0 forever and the fail-open is permanent. Its payload IS well-formed
  (all 8 columns exist; NOT NULL `user_message` supplied at `:563`) — unlike CODE-7's.
- **Fix:** destructure `error` on both; on reader error treat `isFirstReport` as **false** (deny) and
  log; log a writer failure distinctly.
- **Denial is real (confirmed):** `:95` returns 403 immediately and `isFirstReport` appears nowhere
  else (`:86, :92, :95` only). **No wrongful PRO denial:** `hasPro` (`:93`) is computed from an
  independent query, so a healthy PRO user passes regardless of the count read.
- ⚠ **C-3 — state the compound case in the diagnose-doc:** if BOTH reads fail, a paying PRO user gets
  `403 NOT_PRO`, where today the null count would have let them through as "first report". The trade
  is still correct (deny beats giving away Gemini 2.5 Pro), but the error copy and the log must make a
  403 storm attributable.
- ⚠ **C-2 — open question to record, not assume:** `weekly_report` does not appear in the prod channel
  census taken during this audit. Either the feature is unused, or the `:559` writer is ALSO failing
  for a reason no schema check can see. The added error log is exactly what settles it; the
  diagnose-doc must record this as open rather than assuming the writer works.

## 3. Rule 21 — honest attestation, because a behavioral test is not reachable here

Both files are `serve(async (req) => {...})` (`ai-proxy:175`, `weekly-report:32`) with **no exports**;
`checkPro` is module-private inside the closure, and `ai-proxy:66-67` reads `Deno.env.get(...)!` at
module load. There is no importable surface, and `find supabase/functions -name "*.test.ts"` returns
only files under `_shared/`. **There is no Deno on this machine.**

So a behavioral Deno test is not merely "CI-only" — it needs an extraction this slice does not scope,
and inventing one would be scope creep dressed as rigour.

**Attestation:** Dart source-grep contract tests under `test/contracts/`, marked `presence_only:` in
the SoT registry with that reason (the documented Deno-EF exception rule 21 already carries), plus
CI's `deno check` (`test.yml:176`) as the compile proof. **The diagnose-docs must say the mutation was
NOT run locally and why** — claiming otherwise would be precisely the false confidence rule 21 exists
to prevent.

## 4. Sequencing

1. **CODE-8** — reader + writer (clearest fix, closest to `c8f229`'s precedent).
2. **CODE-6** — `.order().limit(1)` + destructure + log.
3. Contract tests + 2 diagnose-docs (`related_bugs:` `c8f229`, `9d12af`; `recurrence:` noted).
4. Self-initiated `/code-review` B-pass (§4.3), plan-review record (§4.12.3), `--no-ff` merge.

No new gate ships in this slice — `check_ef_limit_fails_closed.dart` was rescoped and then moved out
with INFRA-14, so §4.11's gate-before-refactor obligation does not attach to these two fixes.

## 5. Founder authorization still required (§4.3)

Deploys of `ai-proxy` and `weekly-report`. **Plan approval ≠ deploy approval.**
⚠ `ai-proxy` is `verify_jwt=false` **deliberately** (`ai-proxy/index.ts:26-27`); a runbook command
"correcting" it to `true` would 401 every user, and `deploy_via_api.js:669` tolerates 401 so the
deploy would still print HEALTHY.
