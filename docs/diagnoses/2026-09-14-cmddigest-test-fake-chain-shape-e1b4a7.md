---
bug_id: e1b4a7
date: 2026-09-14
batch: Task 12 - Telegram admin bot /digest command
status: fixed
blast_radius: platform
symptom: |
  cmdDigest's own test (index_test.ts) passed, but four of the five digest sections
  (windowed, lifetime, alerts, subscriptions) silently resolved to "unreadable" instead
  of the intended empty/"none" state, because makeEmptyDigestFake()'s intermediate
  filter methods (.gte()/.lt()/.eq()) returned a bare Promise instead of a chainable
  builder, and fetchAllPages calls .order()/.range() on top of that return value.
concept: fetchAllPages_chainable_builder_contract
sot_registry_entry: |
  Not applicable — this is a test-fake shape fix for an Edge Function test, not a
  writer-reader contract change. cmdDigest's own implementation was already correct;
  only its test fake was wrong.
writers:
  - { file: supabase/functions/telegram-admin-bot/index_test.ts, method_or_widget: makeEmptyDigestFake, line: 596 }
readers:
  - { file: supabase/functions/_shared/paged_fetch.ts, method_or_widget: fetchAllPages, line: 225 }
  - { file: supabase/functions/_shared/founder_digest_content.ts, method_or_widget: readDigestSections, line: 369 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: null
contract_test_path: supabase/functions/telegram-admin-bot/index_test.ts
ist_handling:
  - "Not applicable — no date keys or counters involved; gatherDigestInput's own IST windowing is unchanged and untouched by this fix."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — admin-only function, single authorized chat ID; unrelated to this test-fake fix.
forbidden_patterns_checked:
  - { pattern: "test fake that silently masks a broken read path behind an always-true assertion", absent: true }
proposed_fix: |
  Rewrite makeEmptyDigestFake() to implement the chainable builder pattern documented
  in _shared/paged_fetch_test.ts's own makeFake() helper: every intermediate method
  (.select()/.eq()/.gte()/.lt()/.not()/.lte()) returns the builder itself, and only
  the terminal method (.range()/.limit()/.maybeSingle()) resolves to a Promise. Replace
  the sole "Top users: none" assertion (always true regardless of other-section
  correctness) with explicit assertions on each section's actual rendered "none" line,
  plus an assertion that "unreadable" never appears in the output.
regression_test_planned:
  - supabase/functions/telegram-admin-bot/index_test.ts
impact_analysis: |
  Correctness only, no production behavior changed — cmdDigest's real implementation
  (delegating to gatherDigestInput/buildDigestText) was correct throughout; only the
  test's fake data source was broken, silently masking whether the delegation actually
  reads the database correctly. Before this fix, a real regression in fetchAllPages'
  contract, or in any of windowedRead/lifetimeRead/alertsRead/subscriptionsRead, would
  have gone undetected by this test.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "makeEmptyDigestFake() rewritten to the chainable builder pattern; deno check clean." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No deploy needed; cmdDigest implementation in index.ts is unchanged, only its test fake was fixed." }
  - { tier: 12, name: "Client → server contract", status: fixed_in_this_batch, evidence: "Test now proves each digest section renders its real empty-state line and never silently degrades to unreadable." }
---

## Summary

`cmdDigest`'s implementation was correct from Task 12's first commit (`cf010552`) — it
correctly delegates to `gatherDigestInput`/`buildDigestText` from
`_shared/founder_digest_content.ts`. But its own test's fake data source,
`makeEmptyDigestFake()`, returned a bare Promise from intermediate filter methods
(`.gte()`, `.lt()`, `.eq()`) instead of a chainable builder object. `fetchAllPages`
(`_shared/paged_fetch.ts:225-227`) calls `.order()` and `.range()` ON TOP of whatever
`makeQuery()` returns — so calling `.order()` on a bare Promise threw a `TypeError`,
caught by `readSection`'s try/catch and silently converted to an `{unreadable: ...}`
state. This hit `windowedRead`, `lifetimeRead`, and `subscriptionsRead` (all routed
through `fetchAllPages`) and `alertsRead` (same defect, its own `.order()`/`.limit()`
chain). Only `expiringSoonRead` — a flat `.not().gte().lte()` chain with no further
chaining — happened to resolve correctly.

The test still passed, because `buildDigestText`'s "Top users" line unconditionally
renders `"Top users: none"` whenever `perUser` is empty — true whether the other
sections are legitimately empty or silently broken. `assertStringIncludes(text, "none")`
was satisfied almost by accident.

## Fix

Rewrote `makeEmptyDigestFake()` following the chainable builder pattern already used
correctly in this repo's own `_shared/paged_fetch_test.ts` (`makeFake()`, line ~45):
every intermediate method returns the builder itself; only the terminal method resolves
to `{ data: [], error: null }`. Strengthened the test's assertions to check each
section's actual rendered "none" line and to assert `"unreadable"` never appears in the
output — directly falsifying the class of bug this fix addresses.

## Verification

- Targeted test (telegram-admin-bot): 30 tests pass.
- Full Deno suite (`deno test supabase/functions/`, all 37 function test files): 422
  tests pass.
- Type-check (six Edge Function files touched by this plan's Tasks 4/5/7/8/12): clean.
- Mutation check: reverting `makeEmptyDigestFake()`'s chainable methods back to bare
  Promises reddens the new "unreadable" absence assertion and the per-section "none"
  assertions — the prior form of the test (a single `assertStringIncludes(text, "none")`)
  would not have caught it; this form does.

## Related bugs

None — first occurrence of this specific fake-shape defect. Related in spirit (not
mechanism) to the recurring loose-substring-assertion class flagged in Tasks 9, 10, and
11 of this same batch (`.superpowers/sdd/2026-09-13-telegram-admin-bot/progress.md`) —
this is the 4th instance across the batch, though a different failure shape (a
structurally-broken fake vs. a merely-loose assertion).
