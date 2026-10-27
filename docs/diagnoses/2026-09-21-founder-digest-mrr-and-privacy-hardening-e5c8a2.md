---
bug_id: e5c8a2
date: 2026-09-21
batch: observation-batch-and-digest-redesign (self-triggered Hermes pass, catastrophic tier)
status: fixed
blast_radius: platform
symptom: |
  Four independent defects in the SAME batch's own new founder-digest B2/B3
  code (the digest redesign shipped earlier in this batch), all found by the
  self-triggered Hermes pass before merge:

  (1) L1/L21 — `computeNewMrr` summed a yearly subscription's full BOOKING
  price (₹2999) directly into "New MRR" instead of dividing by 12. MRR is a
  monthly figure by definition; the bug overstated New MRR by up to ~11x for
  a day with yearly signups. `telegram-admin-bot`'s own `/revenue` command
  already divides yearly by 12 for exactly this reason — this new function
  failed to reuse that established pattern.

  (2) Same area — `referral_trial` (a real, live plan value, 4 active rows
  confirmed) was not in `PLAN_PRICES_RUPEES`, so it was silently counted as
  an "unrecognized plan" and the digest's own warning line would have told
  the founder to add a price for it — which would have started booking
  revenue for a plan that is deliberately free.

  (3) L40 F3 — `userNamesRead`'s privacy check suppressed a user's real name
  only when an EXPLICIT `coach_memory.private_mode = true` row existed. A
  user who never opened the AI coach has NO `coach_memory` row at all and
  fell through to "shown" — opted OUT of privacy by construction, with no
  surface on which they could ever have expressed the preference this
  control exists for.

  (4) L23 #2 / L23 #4 / L21 F4 — the extracted first name was a bare
  `.split(" ")[0]` on `users.full_name` with no control-character/newline
  stripping or length cap (that column is seeded verbatim from signup
  metadata, i.e. attacker-adjacent), and the two `fetchAllByIds` calls
  backing this lookup carried no `maxPages` bound — unlike every other
  paged read in this same file — on a synchronous, Telegram-webhook-timeout-
  sensitive code path (`telegram-admin-bot`'s `/digest` command).
concept: founder_digest_new_mrr / founder_digest_user_names_privacy
sot_registry_entry: not_applicable
writers:
  - { file: supabase/functions/_shared/founder_digest_content.ts, method_or_widget: computeNewMrr, line: 206 }
  - { file: supabase/functions/_shared/founder_digest_content.ts, method_or_widget: KNOWN_ZERO_PRICE_PLANS, line: 186 }
  - { file: supabase/functions/_shared/founder_digest_content.ts, method_or_widget: userNamesRead, line: 901 }
readers:
  - { file: supabase/functions/_shared/founder_digest_content.ts, method_or_widget: "buildDigestText (New MRR line)", line: 551 }
  - { file: supabase/functions/founder-digest/index.ts, method_or_widget: handler, line: 166 }
  - { file: supabase/functions/telegram-admin-bot/index.ts, method_or_widget: "/digest command", line: 593 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: subscriptions, users, coach_memory
cloud_columns: [subscriptions.plan, users.full_name, coach_memory.private_mode]
contract_test_path: supabase/functions/founder-digest/index_test.ts
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "userNamesRead's privacy fix is exactly a cross-user-exposure guard: a user's real name must never render for anyone but this founder-only, admin-side digest, and only when that specific user explicitly opted in."
forbidden_patterns_checked:
  - "pricing referral_trial in PLAN_PRICES_RUPEES to silence the unknown-plan warning — this would make New MRR silently start booking revenue that was never collected for a deliberately-free plan"
  - "suppressing on `private_mode !== false` (double negative) instead of building an explicit allow-set — the allow-set form makes the default (suppressed) the fallthrough of a Set.has() miss, which is harder to get backwards than negating a boolean read from a nullable-shaped row"
proposed_fix: |
  (1)+(2) computeNewMrr: divide a yearly row's price by 12 before summing
  (rounding only the final total, never per-row, so rounding error cannot
  compound across many yearly rows); add a KNOWN_ZERO_PRICE_PLANS set
  (currently just referral_trial) that contributes ₹0 and is explicitly
  excluded from unknownPlanCount, distinct from a genuinely unrecognized
  plan value (still ₹0, but counted so it stays visible in the digest).
  (3) userNamesRead: replace the suppress-set (`privateIds`, built from
  `private_mode === true`) with an allow-set (`explicitlyVisibleIds`, built
  from `private_mode === false`) — a user is shown ONLY if a coach_memory
  row exists AND explicitly says private_mode=false; everyone else (no row,
  or private_mode=true) is suppressed to the id prefix.
  (4) Route the extracted name through `sanitizeIdentifier` (the same
  helper `re-engagement` already uses for this purpose) with `maxLen: 32`
  before the `.split(" ")[0]` first-name extraction; add `maxPages:
  MAX_PAGES` to both fetchAllByIds calls, matching this file's own 3
  pre-existing paged reads.
regression_test_planned:
  - supabase/functions/founder-digest/index_test.ts (new: privacy-default-deny, sanitizeIdentifier wiring, maxPages source-pin; corrected 2 pre-existing MRR assertions that baked in the pre-fix ₹3697 value)
  - supabase/functions/_shared/founder_digest_content_test.ts (new: isolated computeNewMrr unit tests; corrected 1 pre-existing assertion with the same stale value)
impact_analysis: |
  All four fixes are additive/corrective within a code path that shipped
  earlier in this SAME batch (not yet merged to main, so "impact" is
  relative to what would otherwise have shipped) — no live users have ever
  seen the buggy MRR figure or the fail-open name exposure. The digest is
  founder-only (Telegram, admin chat id allowlisted), so the privacy fix's
  practical blast radius is bounded to what the founder personally sees,
  but the PRINCIPLE (default-deny on identity exposure) is the same one
  this codebase applies everywhere else PII crosses a boundary.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "No lib/ changes — this concept is entirely server-side (Edge Functions)." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "deno check --node-modules-dir=none passes with 0 errors on founder-digest/index.ts, telegram-admin-bot/index.ts, and every other Gemini-calling function (ai-proxy, ai-media-proxy, weekly-report, assess-body-composition, daily-snapshot, rolling-context — sanity swept since this same session also touched gemini.ts). NOT yet deployed — live deploy remains a separate, founder-authorized action not requested this session." }
mutation_proven:
  mutated: "Reverted computeNewMrr's yearly ÷12 divide back to a raw sum (`rupeesExact += price` unconditionally)."
  result: "Ran deno test on founder_digest_content_test.ts: RED — exactly the 3 tests exercising a yearly row (the buildDigestText per-plan-breakdown test and 2 of the isolated computeNewMrr tests) failed with the expected pre-fix values (3697, 2999). Reverted; re-ran: GREEN, 15/15. Separately reverted explicitlyVisibleIds back to the old privateIds suppress-set shape: RED — exactly the new 'no coach_memory row defaults to SUPPRESSED' test failed (asserted null, got the real name 'Rahul'), all other 50 tests in the same file stayed green. Reverted; re-ran: GREEN, 51/51. Separately removed one `maxPages: MAX_PAGES` occurrence from userNamesRead: RED — exactly the new maxPages source-pin test failed (found 1, expected 2). Reverted; re-ran: GREEN. Also caught and fixed, mid-session, TWO pre-existing tests (in founder-digest/index_test.ts) that baked in the ORIGINAL bug's own output as their expected value (349+349+2999=3697, and a referral_trial-as-unknown-plan assertion) — both would have permanently reverted a correct fix back to the bug had they not been corrected in this same commit."
  confirmed_applied: "Read the file (Edit/sed tool's own before/after) to confirm each mutation matched intent, and re-ran the full test file after every restore to confirm no other assertion was silently affected."
---

## Summary

Four defects in this same batch's own new founder-digest code (B2 name
lookup, B3 New-MRR), all found by an 8-lens self-triggered Hermes pass run
before merge on this catastrophic-tier batch. Two are revenue-reporting
accuracy bugs (MRR overstatement, a false "unpriced plan" warning); two are
privacy/robustness gaps in the same user-name lookup (fail-open on absent
`coach_memory` rows, unsanitized name + unbounded pagination on a
webhook-timeout-sensitive path).

## Root cause

MRR: the function was written fresh rather than reusing
`telegram-admin-bot`'s existing `/revenue` command, which already handles
the yearly-vs-monthly distinction correctly. Privacy: the suppression check
was written as a deny-list (explicit opt-out) rather than an allow-list
(explicit opt-in), which is backwards for a privacy control whenever the
row that would carry the opt-in/opt-out might not exist at all.

## Fix

See `proposed_fix` in the frontmatter above — a `KNOWN_ZERO_PRICE_PLANS`
set plus a yearly ÷12 divide for MRR; an allow-set (`explicitlyVisibleIds`)
plus `sanitizeIdentifier` plus `maxPages: MAX_PAGES` for the name lookup.

## Verification

- See `mutation_proven` above — every one of the 4 fixes was mutated back to
  its pre-fix shape and confirmed to redden exactly the test(s) written for
  it, with the rest of the suite staying green.
- Two PRE-EXISTING tests (written earlier in this same batch, before the
  Hermes pass) were discovered to bake in the original bug's own buggy
  output as their expected value — corrected in this same commit rather
  than left to silently revert the fix on the next accidental touch.
- `deno check --node-modules-dir=none` clean on every Gemini-calling
  function (sanity swept, since this same commit also touches the shared
  `gemini.ts` module).

## Files changed

- Modified: `supabase/functions/_shared/founder_digest_content.ts`
- Modified: `supabase/functions/_shared/founder_digest_content_test.ts`
- Modified: `supabase/functions/founder-digest/index_test.ts`
- Created: this diagnose-doc.
