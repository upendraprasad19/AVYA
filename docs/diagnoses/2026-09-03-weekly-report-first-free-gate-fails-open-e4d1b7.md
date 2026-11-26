---
bug_id: e4d1b7
date: 2026-09-03
batch: techdebt-audit-sep02
status: fixed
blast_radius: platform
symptom: |
  A PostgREST failure on ONE count query hands a FREE user an unbounded
  Gemini 2.5 Pro weekly report — the most expensive model call in the app.

  `weekly-report/index.ts` gates ongoing reports on "has the user ever
  generated one before":

      const { count: previousReportCount } = await supabase   // :86 pre-fix
        .from("ai_coach_interactions")
        .select("id", { count: "exact", head: true })
        .eq("user_id", targetUserId)
        .eq("channel", "weekly_report");

      const isFirstReport = (previousReportCount ?? 0) === 0;      // :92
      const hasPro = subscription && !subError;                    // :93

      if (!hasPro && !isFirstReport) { return 403 NOT_PRO; }       // :95

  `error` is never destructured. On any transient failure `count` is null,
  so `(null ?? 0) === 0` evaluates TRUE, `isFirstReport` is true, the gate
  does not fire, and the report is generated for a non-PRO user. There is no
  log, so the grant is invisible.

  ⚠ The mirror was ALREADY PRESENT eleven lines above: the sibling
  subscription query at `:75` destructures `error: subError` and `:93` uses
  it. Same function, same author, guard applied to one read and not the
  other — `feedback_mistake_guard_without_its_mirror.md`.

  SECOND HALF — the writer. `:559` is the SOLE writer for that count:

      await supabase.from("ai_coach_interactions").insert({ … });

  Its result was discarded. supabase-js RESOLVES (never rejects) on a
  PostgREST error, so the outer try/catch cannot see a failure either. If
  this insert ever fails silently, `previousReportCount` stays 0 FOREVER and
  the gate is permanently open for that user — fixing the reader alone would
  have left that live.

  Found by the 2026-09-02 tech-debt audit (finding CODE-8). Not founder-
  reported: this is a latent gate, and the app is pre-launch (8 coach
  interactions in prod since May), so no exploitation has occurred.
concept: weekly_report_pro_gate
sot_registry_entry: weekly_report_pro_gate
writers:
  - file: supabase/functions/weekly-report/index.ts
    method: serve handler — report-log insert
    line: 587
readers:
  - file: supabase/functions/weekly-report/index.ts
    method_or_widget: serve handler — first-free-report gate
    line: 93
hive_key_prefix: "n/a — Edge Function gate; no Hive surface"
hive_key_formula: "n/a — server-side only"
sync_methods: []
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: [user_id, snapshot_id, channel, user_message, ai_response, model_used, tokens_used, created_at]
contract_test_path: test/contracts/weekly_report_pro_gate_writer_to_reader_test.dart
ist_handling: "n/a — no date key, cloud date column, or counter reset touched by this fix"
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: |
  n/a for this fix — the handler already asserts `targetUserId !== userId`
  → 403 at :70-72, above both reads. This change does not alter that path.
forbidden_patterns_checked:
  - pattern: "count:\\s*previousReportCount\\s*\\}\\s*="
    absent: true
  - pattern: "isFirstReport\\s*=\\s*\\(previousReportCount"
    absent: true
proposed_fix: |
  Destructure `error` on BOTH the reader and the writer.

  Reader: on error set `isFirstReport = false` — DENY rather than grant —
  and log with the user id. Denying a report is recoverable; an unbounded
  Gemini 2.5 Pro call is not.

  Writer: capture `error: reportLogError` and log a failure loudly, naming
  the consequence ("the first-free-report gate stays open until this is
  fixed") so the log is actionable rather than decorative.
regression_test_planned: |
  test/contracts/weekly_report_pro_gate_writer_to_reader_test.dart — 4
  this bug: the count read destructures its error; `isFirstReport` uses the
  fail-closed ternary rather than the bare `(previousReportCount ?? 0) === 0`;
  and the report-log insert destructures `reportLogError`.

  MUTATION PROOF (rule 21) — TWO mutations, applied ONE AT A TIME so each is
  known to redden its OWN assertion rather than only failing collectively:

    M1 READER — restored the exact pre-fix line
       `const isFirstReport = (previousReportCount ?? 0) === 0;`
       Applied-check: `grep -c 'previousReportError$'` → 0. Result: 3 passed,
       1 FAILED (the fail-closed assertion).
    M2 WRITER — restored the discarded insert result
       (`await supabase.from(...).insert({` with no destructure).
       Applied-check: `grep -c 'error: reportLogError } = await'` → 0.
       Result: 3 passed, 1 FAILED (the writer assertion).

  Restoring both returned 9/9 green across this file and its sibling.

  ⚠ HONEST SCOPE: these are SOURCE-GREP assertions and prove PRESENCE, not
  runtime behaviour. A behavioral Deno test is not reachable — the function
  is `serve(async (req) => {…})` with no exports, and there is no Deno on the
  dev machine. CI's `deno check` is the compile proof. The SoT entry is
  marked `presence_only:` for that reason. The mutation was run LOCALLY
  against the Dart contract test, NOT against a live Edge Function.
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "Server-side Edge Function only; no lib/ change in this fix." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive surface in this path." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "All 8 insert columns confirmed present in backups/live_schema_columns.json -> ai_coach_interactions. NOT NULL user_message IS supplied at :563 - unlike the sibling delete-account insert (OI-162), which omits it and therefore always fails." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Live channel census 2026-09-03: in_app_orphan 57, app_event 30, food_text_analysis 25, app 8, in_app 5, promotion_ceremony 5. weekly_report is ABSENT - either the feature is unused in prod or this writer is ALSO failing invisibly. RECORDED AS OPEN; the error log added here is what settles it on first use." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this fix." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "Code fixed in this commit; the deployed bundle still carries the defect. Redeploy requires explicit founder authorization per section 4.3, not given at time of writing - so this tier is not yet assertable rather than skipped." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "weekly-report is client-invoked, not cron-dispatched; no cron reads this gate." }
  - { tier: 8, name: rls_policies, status: verified, evidence: "Function uses the service-role client so RLS is bypassed by design; the user-scope assertion at :70-72 is the actual guard and is unchanged by this fix." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No storage bucket or object touched in this path." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret added, rotated, or read differently." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "Gemini is called only AFTER the gate; this fix changes who reaches it, not how it is called." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Response shape unchanged. The only new externally-visible behaviour is a 403 NOT_PRO in a case that previously returned a report - the intended correction." }
impact_analysis: |
  Who is affected, precisely: a NON-PRO user whose weekly-report count query
  fails. Pre-fix they received an unbounded Gemini 2.5 Pro report; post-fix
  they receive 403 NOT_PRO.

  ⚠ COMPOUND CASE, stated because it is a real cost of this fix: if the
  subscription query ALSO fails, `hasPro` is falsy AND `isFirstReport` is now
  false, so a GENUINE PRO user receives 403 NOT_PRO where pre-fix the null
  count would have let them through as "first report". That trade is
  deliberate — a denied report is recoverable and now logged with the user
  id, whereas an unbounded Pro call is neither. The two new console.error
  lines are what make such a 403 attributable instead of mysterious.

  BLAST RADIUS — corrected before commit. This doc first claimed `account`
  by eyeballing "one Edge Function's gate". The tool disagrees:
  `blast_radius_from_diff.dart` returns **platform** for these two EF files
  ALONE, because supabase/functions/ is pinned platform in
  docs/blast_radius.yaml regardless of how narrow the edit looks. Recorded
  rather than silently amended, because "a tier I estimated" and "a tier the
  classifier computed" are different claims and only one of them gates the
  review requirement (platform ⇒ bpass: accepted, §4.12.3).
related_bugs: [c8f229, 9d12af]
recurrence: |
  RECURRENCE — third instance of the fail-open-guard class.

  c8f229 (2026-05-17): verify-payment's ownership check was
  `if (notesUserId && notesUserId !== userId) { return 403; }` — fail-open
  when `payment.notes.user_id` was absent. Fixed by adding an explicit
  missing-field guard that DENIES, pinned by
  test/contracts/verify_payment_notes_user_id_required_test.dart. This fix
  applies the same known-good pattern (§4.1.5 point 4): deny on the
  can't-tell path, and pin it with a contract test.

  9d12af (2026-05-16): log-client-error's rate limit dropped events silently
  past threshold — "Hidden observability bug, silent for an unknown number of
  days". Same shape as the missing log here.

  The distinguishing feature of THIS instance is that the correct guard was
  already present in the same function, eleven lines above, on the sibling
  query. The class is therefore not "we forgot the pattern" but "we applied
  it to one of two reads" — the guard-without-its-mirror class, now at 21
  recorded instances.
---

# weekly-report's first-free-report gate fails OPEN on a count-query error

See frontmatter for the full analysis. Summary of the change:

| Site | Before | After |
|---|---|---|
| `:86` reader | `const { count: previousReportCount } = …` | destructures `error: previousReportError`, logs it |
| `:92` decision | `(previousReportCount ?? 0) === 0` | `previousReportError ? false : (previousReportCount ?? 0) === 0` |
| `:559` writer | `await supabase…insert({…})`, result discarded | destructures `error: reportLogError`, logs the consequence |

**Deploy status:** NOT deployed. Requires explicit founder authorization (§4.3).
