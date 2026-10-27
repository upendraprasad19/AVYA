---
bug_id: 7b3eaf
date: 2026-05-22
batch: APK Test #16.2 +30 obs 5-12 batch (commit 2 / Theme F2)
status: shipped
symptom: |
  Founder tapped GENERATE NEXT PHASE on graduation screen 2026-05-21
  evening — nothing happened. No navigation. No error toast. No
  paywall. No telemetry in `train_graduation_generate_phase_2_failed`.
  Cloud `user_profile.current_phase=1`, `phase_started_at=2026-04-27`
  (20+ days old, never advanced). Founder IS PRO cloud-side
  (`subscriptions.status=active`, plan=monthly).

  Root cause: `SubscriptionService.gate` at
  subscription_service.dart:342-351 had no `.catchError` and no
  `.timeout` on the `verifyFromServer().then(...)` async chain. When
  verify threw (network blip, JWT expired mid-call, Edge function
  hung), the `.then` callback never executed — neither onPro nor
  onFree fired. Button taps vanished silently.
concept: subscription_gate
sot_registry_entry: subscription
writers:
  - { file: lib/core/services/subscription_service.dart, method_or_widget: SubscriptionService.gate now has .timeout(10s) + .catchError fallback + per-exit telemetry, line: 342 }
readers:
  - { file: lib/features/train/screens/graduation_screen.dart, method_or_widget: GENERATE NEXT PHASE tap, line: 414 }
  - { file: lib/features/train/screens/train/phase_unlock_card.dart, method_or_widget: UNLOCK PHASE 2 card tap (post-B5 split), line: 61 }
  - { file: lib/features/profile/screens/profile/profile_content.dart, method_or_widget: Progress Photos PRO gate (post-B5 split), line: 295 }
hive_key_prefix: "n/a — pure callback wiring; no Hive contract change"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: subscriptions
cloud_columns: [is_pro, plan, status, expires_at]
contract_test_path: test/contracts/subscription_gate_catcherror_test.dart
ist_handling:
  - { file: lib/core/services/subscription_service.dart, line: 342, source: "no date-key math in this fix — gate just calls verifyFromServer + dispatches callbacks" }
provider_invalidations: []
telemetry_op_types:
  success: [subscription_gate_routed]
  failure: [subscription_gate_verify_failed]
cross_account_guard: gate reads isPro() which routes through SubscriptionService's authUserIdTokenProvider-watched state.
forbidden_patterns_checked:
  - "Future.then without .catchError on user-tap paths — silently drops both branches on throw."
  - "verifyFromServer() without a timeout — a hung Edge Function blocks the tap indefinitely."
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "subscription_service.dart:342-389 — .catchError + .timeout + 5 telemetry callsites" }
  - { tier: 5, name: cloud_sync_outbound, status: verified, evidence: "verifyFromServer logic unchanged; only the caller hardened" }
  - { tier: 12, name: end_to_end_contract, status: fixed_in_this_batch, evidence: "test/contracts/subscription_gate_catcherror_test.dart pins .timeout(10s), .catchError, fallback-to-onPro, and >=4 subscription_gate_routed callsites" }
impact_analysis:
  callers_audited:
    - lib/features/train/screens/graduation_screen.dart (GENERATE NEXT PHASE)
    - lib/features/train/screens/train/phase_unlock_card.dart (UNLOCK PHASE 2, post-B5 split)
    - lib/features/profile/screens/profile/profile_content.dart (Progress Photos, post-B5 split)
    - lib/features/profile/screens/reports_screen.dart + edit_profile_screen.dart
    - lib/features/nutrition/widgets/* (scan_meal, food_logger, cart_auditor)
    - lib/features/ai_coach/screens/ai_coach/media_picker.dart (photo analysis)
  callers_updated_in_this_batch:
    - lib/core/services/subscription_service.dart (gate() body)
  callers_unchanged:
    - All call sites — gate's signature `void gate(String feature, {required VoidCallback onPro, required VoidCallback onFree})` is byte-identical
proposed_fix: |
  Three changes inside SubscriptionService.gate at lines 342-389:

  1. Wrap `verifyFromServer()` with `.timeout(Duration(seconds: 10),
     onTimeout: () { telemetry; return true; })`. On verify hang
     beyond 10s, fall back to onPro (we already passed the cheap
     isPro() check above — local says PRO, server is slow; better
     UX is to trust local than block the user).

  2. Add `.catchError((e, st) { telemetry; recordNonFatal; onPro(); })`
     to the chain. On any throw from verifyFromServer, emit
     `subscription_gate_verify_failed` telemetry + fall back to
     onPro (same justification — local already said PRO).

  3. Add `subscription_gate_routed` telemetry at every gate exit:
     - not_pro_local (the !isPro() early return → onFree)
     - verify_timeout (timeout fallback → onPro)
     - verify_pro / verify_failed (normal .then → onPro/onFree)
     - verify_threw (catchError fallback → onPro)
     - local_pro (non-high-value features → onPro)
     One query against client_errors tells the next debugger which
     branch fired for any tap.

  No call-site changes — gate's signature is byte-identical. Every
  existing onPro/onFree pair keeps working.
regression_test_planned:
  - test/contracts/subscription_gate_catcherror_test.dart — pins (a) .timeout(Duration(seconds: 10)) on verifyFromServer, (b) .catchError on the chain, (c) catchError falls back to onPro, (d) >=4 subscription_gate_routed callsites.
---
# Body

## Why "fall back to onPro" on server fail

Server-side verifyFromServer is the high-value-feature server check —
protects against rooted-device Hive spoofing of PRO state. But the
cheap `isPro()` check at gate's top (line 347) ALREADY ran and
returned true; we're only here because the user passed local PRO
state. The choice is:

- **Server says no**: existing onFree fires (rooted-device protection).
- **Server says yes**: existing onPro fires.
- **Server throws / times out**: PRE-FIX nothing fires; POST-FIX onPro
  fires.

The trade-off in the throw/timeout case: a rooted-device attacker
could in principle DoS the verify server to bypass the protection.
That's not a real threat model — Supabase Edge Functions are
hardened against the attacker's narrow scope, and the user has
already tampered with Hive to set `is_pro=true` locally — they don't
need to DoS our verify to use the feature, they'd just bypass the
client gate entirely. The "trust local on server fail" choice
prefers legitimate-user UX over a defence that's irrelevant against
the actual threat.

## Why timeout=10s specifically

verifyFromServer's normal latency budget is ~2-5s. Cold-start spikes
to 7-10s observed (per skill §2.5 retry-budget data). 10s catches the
hang without prematurely failing a slow-but-working call. If a real
P0 happens (regional outage), users see the tap respond within 10s
instead of staring at a dead button.

## Telemetry payoff

Pre-fix: zero events on a silent tap. Post-fix: every gate exit
emits `subscription_gate_routed` with `feature=<name>
exit=<branch> reason=<why>`. The next time a tap "does nothing",
one Supabase MCP query against `client_errors` answers exactly
which branch fired and why.

## Combined effect with Theme F (provider invalidations)

Theme F (commit 6 of this batch) wires post-unlock provider
invalidations. Together, this Theme F2 + Theme F means: button tap
ALWAYS lands on a branch, success path ALWAYS invalidates the
right providers, and the founder cannot land in the
"button-vanished-cloud-state-stale" trap again.
