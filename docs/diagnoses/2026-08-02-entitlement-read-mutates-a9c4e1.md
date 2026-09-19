---
bug_id: a9c4e1
date: 2026-08-02
batch: Unit 6 (OI-25/44/45/46/48/50 batch) — closes OI-44
status: fixed
blast_radius: account
symptom: |
  A Riverpod provider's build method invalidates itself. `SubscriptionInfoNotifier.build()` —
  the data source behind the PRO pill — calls `isPro()`, which on an expired or cross-account
  row calls `_downgradeLocally()`, which fires `onStateChanged`, which `app.dart` wires to
  `ref.invalidate(subscriptionInfoProvider)`. The provider therefore schedules its own rebuild
  from inside its own build.

  It is NOT crashing today and was not user-visible: the second pass reads `isPro=false` and
  returns before mutating, so it terminates, and `_downgradeLocally()` is async and called
  un-awaited, so the invalidation lands a microtask AFTER build() returns rather than
  synchronously inside it. The cost today is one wasted rebuild. The reason to fix it is that
  a build method must not mutate — the loop is one `await` away from being synchronous and
  therefore throwing, and nothing in the codebase prevented that edit.
concept: subscription_state (isPro/gate CQRS split)
sot_registry_entry: subscription_state
writers:
  - { file: lib/core/services/subscription_service.dart, line: 414, method: _enforceEntitlementInvariants (the extracted mutating half) }
  - { file: lib/core/services/subscription_service.dart, line: 481, method: evaluateEntitlement (explicit public entry point) }
  - { file: lib/core/services/subscription_service.dart, line: 1048, method: _downgradeLocally (unchanged sink) }
  - { file: lib/core/services/subscription_service.dart, line: 1072, method: _downgradeLocally fires onStateChanged }
  - { file: lib/app.dart, line: 47, method: onStateChanged -> ref.invalidate(subscriptionInfoProvider) }
readers:
  - { file: lib/core/services/subscription_service.dart, line: 338, method: isPro (DECISION entry point — enforce then pure read) }
  - { file: lib/core/services/subscription_service.dart, line: 367, method: proStateSnapshot (new PURE read) }
  - { file: lib/core/services/subscription_service.dart, line: 392, method: _crossAccountMismatch (pure predicate shared by both halves) }
  - { file: lib/features/profile/providers/profile_provider.dart, line: 380, method: SubscriptionInfoNotifier.build — now the pure read }
  - { file: lib/core/services/subscription_service.dart, line: 878, method: verifyFromServer — 8 re-entrant reads now pure }
  - { file: lib/features/auth/screens/splash_screen.dart, line: 220, method: boot enforcement call }
  - { file: lib/core/services/subscription_service.dart, line: 56, method: _onUserChanged — account-swap enforcement call }
hive_key_prefix: n/a (fixed user-scoped keys, not a prefixed row family)
hive_key_formula: "MigratedKey user-scoped keys: isPro | expiresAt | plan | pro_lapsed_at | lastVerifiedAt"
sync_methods: none — entitlement state is written by refreshFromSupabase/verifyFromServer, not by a sync fan-out
restore_methods: none — PRO state is re-derived from the server on boot, never restored from a cloud snapshot
cloud_table: subscriptions
cloud_columns: status, end_date, plan
contract_test_path: test/contracts/subscription_cqrs_behavioral_test.dart
ist_handling: not_applicable — entitlement expiry is an absolute UTC instant compared against DateTime.now(); no IST date-key is involved
provider_invalidations: subscriptionInfoProvider, messageLimitProvider (via SubscriptionService.onStateChanged, app.dart:45-52 — unchanged)
telemetry_op_types: pro_state_force_downgrade_cross_account, subscription_gate_routed, paywall_hit_when_pro
cross_account_guard: |
  PRESERVED and strengthened. The Hive-profile.id vs session.id check is the defense-in-depth
  layer that catches Auto-Backup entitlement leaks the startup guard
  (hive_user_session.dart:208) misses. It still runs on EVERY entitlement decision via isPro().
  What changed is that it no longer runs incidentally on every render; it is invoked explicitly
  at the two moments state can BECOME cross-account — boot (splash_screen.dart:220) and account
  swap (_onUserChanged, subscription_service.dart:56).
forbidden_patterns_checked: |
  - no raw Hive.box( — all entitlement reads go through MigratedKey
  - no inline configBox.get('isPro') introduced (§4.4 rule 5)
  - no secrets in diff
  - no new .functions.invoke( — verifyFromServer's existing call is untouched
  - unawaited_futures / discarded_futures: flutter analyze reports 0 warnings, 0 errors on lib/
proposed_fix: |
  Split the mutating half out of isPro() WITHOUT narrowing the decision path.
    1. _enforceEntitlementInvariants() holds the cross-account and expiry branches. Round 1
       (P3-10) showed "verbatim" is imprecise: legacy kept logEvent + _downgradeLocally() inside
       one try, the new code wraps only the telemetry, so a throwing profile re-read now still
       downgrades where legacy fell through to the expiry check. The RETURN VALUE is identical
       in all six input classes; the difference is strictly fail-safe and is kept deliberately.
    2. proStateSnapshot() is a genuinely pure read (MigratedKey + expiry compare, zero writes,
       zero telemetry).
    3. isPro() keeps its name and its exact behaviour: enforce, then report. All 30+ decision
       callsites are byte-identical.
    4. Build methods and the re-entrant reads inside verifyFromServer() switch to the pure read.
       Round 1 found this claim understated: SEVEN build-path sites needed it, not one
       (profile_provider; home_provider SubscriptionExpiryBannerNotifier; ai_coach_provider
       PredictionData build; three nutrition Provider<int> bodies; rank_service_record_sheet's
       build helper; dev_panel_screen build). Three non-build sites also moved for correctness:
       writeSubscriptionState's oldIsPro (a comparison, not a decision), isExpiringSoon and
       isLapsed (both reachable from provider builds).
    5. evaluateEntitlement() is called explicitly at boot and on account swap, because
       refreshFromSupabase() does NOT cover the cross-account case (it decides from the SERVER
       response and never compares profile.id) — verified, not assumed.
    6. §4.6 kill-switch disable_cqrs_pure_pro_read restores the pre-split behaviour OF isPro()
       (via _legacyIsProWithInlineEnforcement) for the 30+ decision callsites. Round 1 (P1-4)
       caught that scoping it wider was actively unsafe: the first version also made
       evaluateEntitlement() inert when the switch was closed, but the pure-read callsites are
       NOT behind the flag — so closing it produced a state WEAKER THAN BOTH (build methods pure,
       AND no explicit enforcement). evaluateEntitlement() now enforces in both positions.
  Also: gate() -> gateAndVerify() returning Future<void>, and calculateCurrentStreak() deleted.
regression_test_planned: |
  test/contracts/subscription_cqrs_behavioral_test.dart (14 tests, all green).
  Groups A and B are a CONTROLLED PAIR and are the negative control: identical seeded state and
  an identical onStateChanged counter, differing only in which read is called. The pure read
  fires 0 invalidations and leaves every Hive key byte-identical; the decision read fires >=1 and
  wipes them. That pairing is permanent and runs on every commit, which is stronger evidence than
  a one-off revert-and-rerun — and it avoids editing a real lib/ file to prove a point, which is
  how Unit 7's round-2 reviewer destroyed that batch's work.
  Also extended: test/contracts/streaks_writer_to_reader_test.dart now pins the split PAIR
  instead of demanding the deleted merged name.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze (whole project) -> 0 warnings, 0 errors; 229 remaining issues are pre-existing infos. 49 tests green across the 9 affected suites after the round-1 fixes." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "subscription_cqrs_behavioral_test group A asserts isPro/expiresAt/pro_lapsed_at are untouched by the pure read; group B asserts the decision path still wipes them." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "no migration; no schema change." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "client-only refactor; no rows written." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration in this unit." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function touched. verify-subscription is called but unmodified." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron function touched." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no policy change; subscriptions RLS untouched." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no Storage access in this diff." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret read or write; grep for credential-shaped literals in the diff returned 0." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "Razorpay integration untouched — razorpay_service.dart is not in the diff." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "verifyFromServer's request/response handling is unchanged; only its 8 internal isPro() reads became pure. The gate's 4 exit paths (:453/:475/:481/:491 pre-edit) still fire the same subscription_gate_routed reasons." }
impact_analysis: |
  Blast radius MEASURED `account`, not assumed. The plan predicted `platform` on the reasoning
  that subscription_service.dart is payment-adjacent; the classifier says otherwise, and
  docs/blast_radius.yaml:183 carries an EXPLICIT `{ glob: lib/core/services/
  subscription_service.dart, tier: account }` entry — a deliberate classification, not a
  catch-all fallthrough. Recorded because the prediction was wrong: the true payment-critical
  tier in that registry is reserved for razorpay-webhook / verify-payment / subscriptions-RLS
  (all `catastrophic`, :41-49), and the client entitlement cache is correctly one rung below.
  Command: `git status --porcelain | sed 's/^...//' | dart run
  scripts/blast_radius_from_diff.dart -` (the trailing `-` is load-bearing).

  Surface, COUNTED not estimated — `.isPro()` CALL EXPRESSIONS with comment lines and trailing
  line-comments stripped: **27 across 22 files on `main`, 18 across 17 files after the split.**
  Three wrong numbers were published before this one and each was caught by a reviewer:
  the plan said 32 (counted grep LINES, comments included); a first correction said 28 (a
  `grep -vE` filter that let one indented comment through); round 2 measured 27 and was right.
  The lesson is the recurring one — a count is a claim, and `wc -l` on a grep is not a count of
  call expressions. gateAndVerify: 10 real callsites (an 11th grep hit at
  profile_content.dart:486 is a comment).

  RISK ACCEPTED AND MITIGATED. The one real behaviour change is WHEN the cross-account guard
  fires. Pre-split it ran on every read; now it runs on every entitlement DECISION plus two
  explicit transition points. The scenarios it exists for — Android Auto Backup restoring
  another account's Hive, a dev-build Hive copy, an in-session account switch — are all
  transitions, so they are covered. What is no longer covered is a mismatch appearing with no
  boot, no account swap, and no gated-feature tap in between, which requires the Hive file to be
  swapped underneath a running process.

  NOT changed: the decision semantics of isPro() (byte-identical), the pro_lapsed_at stamp that
  drives the Home expiry banner, the payment grace window, the 5-minute verify cache, and the
  free->PRO freeze grant.

  §4.6 kill-switch disable_cqrs_pure_pro_read reverts to the pre-split path verbatim. It is
  default ON (new path live), NOT ship-dark default-OFF, so §4.12.4's lighter 1-round tiering
  does NOT apply and no docs/ship_dark_pending_review.yaml entry is owed — this unit takes the
  full x2 review + B-pass.
---

# Entitlement read mutates: a provider build that invalidates itself

**Closes OI-44.** Unit 6 — the last unit of the OI-25/44/45/46/48/50 batch.

## What OI-44 said, and what is actually there

The board framed this as a naming problem: "10 query-named methods with side effects". A rename
across 32 payment-adjacent callsites buys nothing on its own. The finding worth acting on is the
concrete loop above. Three of the board's claims did not survive verification:

| OI-44 says | Verified |
|---|---|
| `gate()` — "15+ callsites" | **10** (`grep -rn "\.gate(" lib/`) |
| `calculateCurrentStreak()` — "zero live callers" | True for `lib/`. **False overall**: `test/train/streak_anchor_test.dart:42,73` call it, and `test/contracts/streaks_writer_to_reader_test.dart:59` *source-greps that the symbol exists*. Deleting it changed 3 files. |
| `isPro()` — "28+ callsites" | **27** call expressions on `main` — the board's "28+" was essentially right. The plan restated it as "32", which was wrong. |

A fourth correction, found while building the gate: `lib/CLAUDE.md` cited
`scripts/check_writer_reader_drift.dart` and `scripts/check_subscription_gate.dart` as live
pre-commit gates. **Neither has ever existed.** Same class as the OI board's own "fixed by
`check_open_issues_reconciled.dart`" note (root CLAUDE.md §7). Citing a gate that does not exist
is worse than citing none, because it reads as coverage.

## The gate, and why it is not the board's proposed test (§4.11)

`scripts/check_cqrs_query_naming.dart` + `scripts/cqrs_query_naming_lib.dart` ship in a commit
BEFORE the refactor. Three things the naive version got wrong:

1. **OI-44 proposed grepping bodies for `recordNonFatal`.** That is a false-positive generator —
   it is exactly why the 2026-07-29 board correction had to REMOVE `RankService.getCurrentRank()`
   from the finding list (its telemetry fires only in the catch block; zero writes in any
   branch). The gate strips `catch (...) { ... }` before scanning.
2. **Low-level patterns alone are blind here.** Rule 4 routes writes through repositories, so
   `box.put(` is the rare shape; the write behind this gate's own worked example is
   `StreakProgressService.instance.commitConsume(...)`. A writer-verb layer was needed — it
   contributed one true positive and zero noise across 466 files.
3. **Delegation had to be resolved TRANSITIVELY.** `calculateCurrentStreak() =>
   consumeMissedDayIfFreezeAvailable() => _calculateStreak(consume: true)` puts the write two
   hops from the query, so a single-hop resolver missed the very case the gate exists for.

Result on `lib/`: 135 query-named members scanned, 2 mutate, both exempted with reasons, 0
unexempted. Negative-controlled against a committed fixture
(`test/fixtures/cqrs_gate/violations.dart`) that plants one violation per detection shape plus
four clean controls — including catch-block telemetry and write syntax appearing only inside a
string, which a naive grep would flag.

The exemption ledger is load-bearing: `calculateCurrentStreak`'s entry was TEMPORARY and the
commit that deleted the method deleted the entry. The stale-exemption check fails if such a
deletion is forgotten, which is what makes §4.11's rolling window safe rather than a promise.

## Refuted while investigating — recorded, not dropped

**"`refreshFromSupabase()` at boot already covers the cross-account case."** False.
`splash_screen.dart` fires it, but it decides purely from the `subscriptions` response and never
compares the Hive `profile.id` against the session id — that comparison existed nowhere but
inside `isPro()`. The startup guard it claims to back up is `hive_user_session.dart:208` plus
`restoring_screen.dart:272-280`, and `isPro()`'s doc comment says explicitly that it is the layer
for what those miss. Had this not been checked, routing build methods to the pure read would have
silently narrowed an entitlement-leak guard on a payment path.

## Recurrence

Same class as the C-14 (audit-2026-05-11) streak split, whose leftover shim this unit finally
deleted: a query-named method that mutates, called from display surfaces. The difference is that
C-14 fixed one method and left the pattern unpoliced for three months; this unit ships the gate
that makes the shape unconstructible.

Related: `feedback_source_grep_false_confidence.md` (the streaks contract test demanded the
presence of the defective symbol), `feedback_source_grep_strip_comments_first.md` (the gate
scrubs comments and string literals before scanning).
