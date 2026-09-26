---
bug_id: f2b9d4
date: 2026-09-03
batch: techdebt-audit-sep02
status: fixed
blast_radius: platform
symptom: |
  A PAYING PRO user silently loses every PRO coach tool, and nothing anywhere
  records that it happened.

  `ai-proxy/index.ts` resolves entitlement through `checkPro()`:

      async function checkPro(client, userId): Promise<boolean> {
        try {
          const { data } = await client                        // :88 (pre-fix)
            .from("subscriptions")
            .select("status")
            .eq("user_id", userId)
            .eq("status", "active")
            .gt("end_date", new Date().toISOString())
            .maybeSingle();
          return data !== null;
        } catch (_) { return false; }                          // :96 (pre-fix)
      }

  Its result becomes `toolCtx.isPro` (call sites `:292`, `:659`); false hides
  every PRO tool.

  TWO defects, and it is important to separate them because one of them is
  NOT a bug:

  1. NOT A BUG — returning `false` on error. The docstring at :79-81 states
     the intent explicitly: "fail closed - cheaper to incorrectly gate a PRO
     user than to leak unlimited chat to a free user." That is a deliberate,
     correct trade and this fix PRESERVES it. An earlier draft of the audit
     plan proposed "fixing" it, which would have created the exact leak the
     docstring guards against.

  2. THE ACTUAL BUG — `.order("end_date", { ascending: false }).limit(1)` was
     missing. There is NO UNIQUE constraint on `subscriptions(user_id)` — the
     only subscriptions UNIQUE anywhere is `razorpay_payment_id` (migrations
     052:82-85, 094:18). So a user holding TWO overlapping active rows — the
     ordinary shape of a renewal purchased before the old `end_date` lapses —
     makes `maybeSingle()` synthesise PGRST116, `data` comes back null, and
     `checkPro` returns false. A paying customer is downgraded by a renewal.

     The mirror was already present in the sibling query:
     `weekly-report/index.ts:74-84` runs the same filter set and DOES carry
     `.order("end_date", { ascending: false }).limit(1)`.

  3. COMPOUNDING BOTH — `error` was never destructured and the catch was
     `catch (_)`, so neither failure mode logged anything. The downgrade of a
     paying user was indistinguishable from a free user being correctly
     gated. That silence is what made it un-diagnosable.

  Found by the 2026-09-02 tech-debt audit (finding CODE-6), refined by its
  review round 1 which identified the missing `.limit(1)` as the fixable
  cause behind the reported symptom.
concept: ai_coach_pro_entitlement
sot_registry_entry: ai_coach_pro_entitlement
writers:
  - file: supabase/functions/verify-payment/index.ts
    method: payment confirmation handler — subscription insert
    line: 506
  - file: supabase/functions/razorpay-webhook/index.ts
    method: webhook handler — subscription insert
    line: 573
readers:
  - file: supabase/functions/ai-proxy/index.ts
    method_or_widget: checkPro
    line: 96
hive_key_prefix: "n/a — Edge Function entitlement read; no Hive surface"
hive_key_formula: "n/a — server-side only"
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns: [user_id, status, end_date]
contract_test_path: test/contracts/ai_coach_pro_entitlement_writer_to_reader_test.dart
ist_handling: "n/a — the end_date comparison uses an absolute ISO timestamp, not an IST date key or counter reset"
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: |
  n/a for this fix — `userId` is supplied by the authenticated caller
  resolution above the call sites, and the query is `.eq("user_id", userId)`.
  This change does not widen the scope of the read.
forbidden_patterns_checked:
  - pattern: "\\{\\s*data\\s*\\}\\s*=\\s*await\\s+client"
    absent: true
  - pattern: "catch\\s*\\(_\\)\\s*\\{\\s*return\\s+false"
    absent: true
proposed_fix: |
  Add `.order("end_date", { ascending: false }).limit(1)` so the ≥2-row case
  resolves to the newest active subscription instead of erroring — matching
  the sibling query in weekly-report.

  Destructure `error` and log it, plus log in the catch. KEEP `return false`
  on both paths: fail-closed is the documented, deliberate contract and is
  NOT what was broken.
regression_test_planned: |
  test/contracts/ai_coach_pro_entitlement_writer_to_reader_test.dart — 5
  this bug, all scoped to the isolated `checkPro` body so they cannot be
  satisfied by an unrelated query elsewhere in a 1000+ line file:
  destructures `error`; carries `.order("end_date")`; carries `.limit(1)`;
  and — deliberately — STILL fails closed (≥2 `return false`, zero
  `return true`), so a future refactor cannot "fix" it into a free-tier leak.
  A fifth pins that the downgrade is logged.

  MUTATION PROOF (rule 21): removed the exact
  `.order("end_date", { ascending: false })` + `.limit(1)` lines in place —
  the REAL pre-fix defect, not a convenient mutation. Applied-check:
  `grep -c 'order("end_date", { ascending: false })'` → 0. Result: 4 passed,
  1 FAILED (the tolerates-2-active-rows assertion). Restoring returned 9/9
  green across this file and its sibling.

  ⚠ HONEST SCOPE: SOURCE-GREP assertions prove PRESENCE, not runtime
  behaviour. A behavioral Deno test is not reachable here — `checkPro` is
  module-private inside `serve(async (req) => {…})` with no exports, and
  `ai-proxy` reads `Deno.env.get(...)!` at module load; there is also no Deno
  on the dev machine. CI's `deno check` is the compile proof and the SoT
  entry is marked `presence_only:`. The mutation ran against the Dart
  contract test, NOT against a live Edge Function.
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "Server-side Edge Function only; no lib/ change in this fix." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive surface; entitlement is resolved server-side per request." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "subscriptions.user_id / status / end_date all present in backups/live_schema_columns.json. Confirmed there is NO UNIQUE on subscriptions(user_id): grep of every migration returns only razorpay_payment_id (052:82-85, 094:18), and 006:26 / 010:58-59 are non-unique indexes - which is precisely why two active rows are representable." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "No live user currently holds two overlapping active rows could NOT be established - that needs a live query this fix did not run. The defect is structural (no UNIQUE + no .limit(1)), so it does not depend on a row existing today; a renewal creates the condition." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this fix - deliberately. Adding a UNIQUE on subscriptions(user_id) would be a schema change with its own blast radius and would break legitimate historical rows." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "Code fixed in this commit; the deployed bundle still carries the defect. Redeploy requires explicit founder authorization per section 4.3, not given at time of writing - so this tier is not yet assertable rather than skipped." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "checkPro is called on the client-invoked chat path only, not from any cron job." }
  - { tier: 8, name: rls_policies, status: verified, evidence: "ai-proxy uses the service-role client; RLS is bypassed by design and the .eq(user_id) filter is the scope guard. Unchanged by this fix." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No storage access in this path." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret added, rotated, or read differently." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "Gemini is called after entitlement resolution; this fix changes which tools are offered, not how the model is called." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Response shape unchanged. A user with two active subscription rows now correctly resolves as PRO where they previously resolved as free - a correction, not a contract change." }
impact_analysis: |
  Who is affected: any PRO user with two overlapping active subscription
  rows. That is not an exotic state — it is what a renewal purchased before
  the previous term expires looks like, which is the normal renewal path.

  Pre-fix such a user silently lost every PRO coach tool with no log line
  anywhere. Post-fix they resolve correctly as PRO, and any genuine failure
  is logged with the user id.

  What this fix deliberately does NOT change: the fail-closed contract. On a
  real query error `checkPro` still returns false, and the contract test now
  pins that (≥2 `return false`, zero `return true` in the body) so a later
  refactor cannot quietly turn a safety property into a free-tier leak.

  BLAST RADIUS — corrected before commit. This doc first claimed `account`.
  `blast_radius_from_diff.dart` returns **platform** for these two EF files
  alone — ai-proxy is pinned platform in docs/blast_radius.yaml. The edit is
  genuinely narrow (no schema, no migration, no client change), but narrowness
  is not the classifier's criterion and my estimate did not get to overrule it.
related_bugs: [9d12af, c8f229]
recurrence: |
  RECURRENCE on two axes.

  Silent-gating-decision axis — 9d12af (2026-05-16): log-client-error's rate
  limit dropped events past threshold with no signal, recorded as a "Hidden
  observability bug - silent for an unknown number of days". Identical shape:
  a gating decision going the wrong way with nothing written down. The fix
  pattern applied here is the same one — make the wrong-way branch loud.

  Guard-without-its-mirror axis — the correct `.order().limit(1)` form was
  ALREADY in the codebase, in weekly-report's sibling query against the same
  table with the same filters. This is the class tracked in
  feedback_mistake_guard_without_its_mirror.md (21 instances across 9+
  sessions): a defensive pattern applied at one call site and not at its
  twin. Note that the OTHER half of this same audit slice (e4d1b7) is the
  same class INSIDE a single function. Two independent instances surfaced by
  one audit is itself the signal that the class is not being checked for
  systematically.

  c8f229 is cited as the fail-open precedent for the sibling fix (e4d1b7)
  rather than for this one; recorded here because the two shipped together
  and a future reader tracing either will find both.
---

# `checkPro` silently downgrades a paying PRO user on renewal

See frontmatter for the full analysis. Summary of the change:

| Aspect | Before | After |
|---|---|---|
| Row selection | `.maybeSingle()` with no ordering | `.order("end_date", {ascending:false}).limit(1).maybeSingle()` |
| Error handling | `const { data } = …`, `catch (_)` | destructures `error`; both paths log with the user id |
| Fail-closed contract | `return false` | **unchanged** — and now pinned by contract test |

**The trap this fix avoided:** an earlier plan draft proposed making `checkPro` not fail closed. Its docstring documents fail-closed as deliberate; changing it would have leaked unlimited chat to every free user during any Postgres blip.

**Deploy status:** NOT deployed. Requires explicit founder authorization (§4.3).
