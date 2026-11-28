---
reviewed_at: 2026-09-03T11:51:00+05:30
staged_against: db5584050b6b
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value, modelled_on_is_a_checkable_claim, stale_or_wrong_citation]
findings_count: 3
verdict: accepted
---

# Code Review — db5584050b6b

Tech-debt audit 2026-09-02, **Slice A** (findings CODE-6, CODE-8; diagnoses `f2b9d4`, `e4d1b7`).
Fresh context-blind Sonnet subagent. **3 findings — 0 P0, 1 P1, 1 P2, 1 P3; 0 false_alarm.**

## Finding 1 — P1 — stale_or_wrong_citation
- **file:line:** `docs/sot_registry.yaml` (`ai_coach_pro_entitlement` → `writers:`) and
  `docs/diagnoses/2026-09-03-checkpro-silent-downgrade-of-paying-user-f2b9d4.md` (`writers:`)
- **claim:** Both cited `supabase/migrations/052_subscriptions_rls_lockdown.sql:82-85` as the WRITER
  for the subscriptions concept. Those lines are a **comment block** about the
  `razorpay_payment_id` constraint; the file contains no `INSERT` at all. The real writers are
  `supabase/functions/verify-payment/index.ts:505-517` and
  `supabase/functions/razorpay-webhook/index.ts:572-584`, both
  `.from("subscriptions").insert({ user_id, plan, status: "active", … })`.
- **verification:** `sed -n '82,85p' supabase/migrations/052_subscriptions_rls_lockdown.sql`
  (prints `-- Part 3: regression — UNIQUE on razorpay_payment_id …`);
  `grep -n 'from("subscriptions")' supabase/functions/verify-payment/index.ts supabase/functions/razorpay-webhook/index.ts`
- **why no gate caught it:** `check_sot_registry_parity.dart` treats a prose `method:` value as
  unresolvable and SKIPS the symbol check, so only file-exists + line-in-bounds were verified — both
  trivially true of a comment. `check_sot_registry_citations.dart` only resolves that the concept
  NAME exists. `validate_diagnose_doc.dart` is schema-only. This was a live §4.1 violation
  ("every fix must NAME writer(s) + reader(s) by file:line") invisible to all three.
- **suggested-fix:** repoint both to the two Edge Function writers; keep migration 052/094 cited as
  EVIDENCE for the no-UNIQUE-on-`user_id` claim, which is accurate in that role.
- **status:** **fixed** — both files repointed to `verify-payment:505-517` +
  `razorpay-webhook:572-584`; migration 052 now appears only in the tier-3 evidence prose. The SoT
  entry carries an inline note recording the correction and why no gate saw it.

## Finding 2 — P2 — blast_radius_mismatch
- **file:line:** `docs/blast_radius.yaml:23-25`
- **claim:** `platform` tier's `requires:` is
  `[regression_test, behavioral_test_path, code_review_b_pass, feature_flag]`. This diff satisfies
  the first three and ships **no feature flag / kill switch**.
- **verification:** `sed -n '23,25p' docs/blast_radius.yaml`;
  `git diff --cached -- supabase/functions/ | grep -iE "flag|kDebugMode|RemoteConfig|kill.?switch"` → 0 matches
- **reviewer's own note, which is the right framing:** both fixes convert a fail-**open** path to
  fail-**closed**. A literal kill switch reverting to the old code would re-open the exact hole being
  closed. That may make `feature_flag` inapplicable — but nothing recorded that judgment.
- **status:** **answered in the plan-review record** for branch `techdebt-audit-sep02`, which states
  explicitly why a kill switch is not applicable to a fail-open→fail-closed correction rather than
  leaving it implicit. Not silently waived.

## Finding 3 — P3 — asserted_fixture_value (gate self-report)
- **file:line:** `scripts/check_sot_behavioral_test_paths.dart:78-86`
- **claim:** Gate 42's PASS message under-counts `presence_only: true` concepts — prints
  `7 carry presence_only` while `grep -c "presence_only: true" docs/sot_registry.yaml` → **12**.
  Cause: the classifier is `if (hasBehavioralPath) … else if (hasPresenceOnly) …`, so a concept
  carrying BOTH fields (which is the correct, documented pattern, and what this diff's two new
  entries use) is bucketed as behavioral for reporting.
- **verification:** `grep -c "presence_only: true" docs/sot_registry.yaml` vs
  `dart run scripts/check_sot_behavioral_test_paths.dart`
- **scope:** **pre-existing gate behaviour, not introduced by this diff**, and it does not affect the
  PASS/FAIL verdict — only the printed tally. Surfaced because this diff's entries use the dual-field
  pattern. Same "stale count nobody re-derives" class the parent audit is about (cf. CLAUDE.md §0's
  own warning, and rule 21's "6 entries carry it today" which is likewise wrong — it is 12).
- **status:** **tracked as OI-161**, the board entry that already covers blind spots in this repo's
  own observability and discipline gates. Not fixed here: it is a platform-tier gate edit unrelated
  to Slice A's correctness, and folding it in would re-widen the slice that was deliberately narrowed
  after two review rounds.

## Lenses that returned clean

- **writer_reader_drift** — channel strings matched exactly: writer stamps `channel: "weekly_report"`,
  reader filters `.eq("channel", "weekly_report")`; `grep -n weekly_report` returns exactly those 2
  hits. `ai_coach_pro_entitlement` reader's filter columns (`status`, `end_date`) match what the real
  writers populate. The only defect was the writer CITATION (Finding 1), not the runtime contract.
- **function_exception_swallow** — every new `await supabase…`/`await client…` destructures and logs.
  `reportLogError` deliberately does not propagate into the HTTP response: the report was already
  generated, so failing the response would waste a completed Gemini call while protecting nothing.
- **secrets_in_tree** — full 2051-line staged diff grepped for `sk-`, `rzp_live_`, `AKIA`,
  `-----BEGIN`, `service_role`, api-key shapes → 0 matches.
- **unawaited_no_error_sink** — `git diff --cached -- supabase/functions/ | grep -n "unawaited("` → 0.
- **guard_without_its_mirror** — the deepest pass. (1) Proved by boolean algebra that
  `if (!hasPro && !isFirstReport)` can never fire for a genuine PRO user regardless of
  `previousReportError`, because `hasPro` comes from an independent unchanged query and short-circuits
  the `&&`. (2) Proved `.order().limit(1)` is behaviour-identical for the 0-row and 1-row cases; only
  the ≥2-row case changes, from a synthesised PGRST116 to picking the newest row. (3) **Mutated to the
  real pre-fix `HEAD` content** of both files (not a synthetic mutation) → **7 of 9 assertions redden**;
  the 2 that stay green correctly pin invariants this diff did not touch. Tree restored and verified
  clean, disclosed by the reviewer.
- **missing_input** — all 8 insert columns present in `backups/live_schema_columns.json`; the only
  NOT NULLs (`user_id`, `user_message`) are both supplied; `check_schema_column_refs.dart` → 841 refs,
  0 drift. The sibling function that DOES have the phantom-column bug is already tracked as OI-162.
- **asserted_fixture_value** — covered by the pre-fix mutation run: none of the 9 assertions would pass
  if the feature did nothing.
- **modelled_on_is_a_checkable_claim** — diffed `weekly-report:75-83` against `ai-proxy:101-109`
  directly: identical filter chain. Confirmed from the diff hunk that weekly-report's `.order()/.limit()`
  **predates** this change, so it is a genuine pre-existing reference pattern, not a claim invented
  after the fact.

## Founder triage notes

All three findings resolved before merge: 1 fixed in-batch, 1 answered explicitly in the plan-review
record, 1 tracked on the board as a pre-existing gate defect. No finding was waived silently.
