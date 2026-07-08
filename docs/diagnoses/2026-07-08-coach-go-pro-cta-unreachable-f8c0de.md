---
bug_id: f8c0de
date: 2026-07-08
batch: coach-memory-snapshot (FC8)
status: fixed
blast_radius: feature
symptom: >
  Founder-reported live (test7, 2026-07-04): tapping the AI-coach "Go PRO" at the
  10/10 free daily limit did nothing. Root cause read from source: at the limit
  the composer shows a gold "Daily limit reached — Go PRO" string that is the
  HINT of an `enabled:false` TextField (a dead placeholder with no gesture), and
  the ONLY working paywall affordance — the inline "GO PRO" link under the message
  counter — was gated `if (isWarning && !isLimitReached)`, which HID it at exactly
  the limit-reached state. Since `isLimitReached ⟹ isWarning`, the guard removed
  the CTA at the precise moment of upgrade intent, so from 10/10 there was NO
  reachable paywall CTA in the coach — a silent conversion-blocker.
concept: n/a — UI reachability fix (no SoT concept; no writer/reader contract change)
sot_registry_entry: >
  n/a — no SoT registry concept. FC8 is a pure UI-reachability fix in the coach
  input bar; it changes NO data writer/reader, gate logic, or subscription state.
  The paywall itself (showPaywallSheet / PaywallSheet) and the free-limit gate
  (AppConstants.freeAiMessagesPerDay) are unchanged.
writers: >
  n/a — no data write. The only change is which UI affordances are RENDERED +
  tappable in
  { file: lib/features/ai_coach/screens/ai_coach/input_bar.dart, method: _buildInputBar, line: 182 } (counter-row GO PRO link predicate isWarning) and
  { file: lib/features/ai_coach/screens/ai_coach/input_bar.dart, method: _buildInputBar, line: 76 } (limit-state composer wrapped in a GestureDetector → showPaywallSheet).
readers: >
  n/a — no data read. Downstream the user reaches the existing
  { file: lib/core/services/subscription_service.dart, method: showPaywallSheet, line: 414 } → PaywallSheet (unchanged) — Razorpay checkout as for every other paywall entry point.
hive_key_prefix: "n/a — no Hive key touched"
hive_key_formula: "n/a — UI-only change"
sync_methods: []
restore_methods: ["n/a — no persisted state changed"]
cloud_table: "n/a — no cloud contract touched"
cloud_columns: ["n/a"]
contract_test_path: test/contracts/coach_go_pro_cta_reachable_test.dart
ist_handling: >
  n/a — no date/time handling. FC8 touches only widget predicates + a gesture
  wrapper in the coach input bar.
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - "The paywall CTA gated `isWarning && !isLimitReached` so it HID at the limit. FIXED: the counter-row predicate is now `if (isWarning)` (isLimitReached ⟹ isWarning ⇒ the tappable GO PRO link persists through the limit). Pinned by coach_go_pro_cta_reachable_test.dart — asserts the fixed predicate is present AND the old `isWarning && !isLimitReached` is absent."
  - "The limit-reached composer being a dead disabled TextField with no tap target. FIXED: at the limit the composer is wrapped in a GestureDetector(behavior:opaque) → showPaywallSheet, so the gold hint the user actually taps opens the paywall. Pinned by the same test (isLimitReached ? GestureDetector + HitTestBehavior.opaque + ≥2 showPaywallSheet call sites)."
proposed_fix: >
  Client-only, lib/features/ai_coach/screens/ai_coach/input_bar.dart: (a) change
  the counter-row predicate `if (isWarning && !isLimitReached)` → `if (isWarning)`
  so the tappable "GO PRO" link stays visible AT the limit; (b) hoist the composer
  TextField into a local and, when isLimitReached (the field is disabled), wrap it
  in a GestureDetector(behavior:HitTestBehavior.opaque, onTap: showPaywallSheet)
  so the disabled composer becomes a paywall tap target. Below the limit the plain
  field renders (typing/focus unchanged). No gate-logic, subscription, or copy
  change (the existing "Go PRO" / "Unlimited AI Coach" strings are already
  Wardroom-conformant).
regression_test_planned: >
  test/contracts/coach_go_pro_cta_reachable_test.dart (source-anchored, comment-
  stripped): (1) the counter-row predicate is `if (isWarning)` and the old
  `isWarning && !isLimitReached` is ABSENT; (2) the limit-state composer is
  wrapped `isLimitReached ? GestureDetector` with HitTestBehavior.opaque and
  showPaywallSheet appears in ≥2 call sites (counter link + composer wrap). Fails
  against the pre-fix tree (narrowed predicate; single showPaywallSheet call site;
  no composer tap target). input_bar.dart is a `part of screen.dart` private
  extension that cannot be pumped in isolation, so the behavioral confirmation is
  the on-device tap at end-of-batch APK verify (isPro=false + messageCount=10 →
  tapping the composer / GO PRO opens the paywall).
touched_layers_checked:
  - "client_code — status: fixed_in_this_batch — input_bar.dart: counter-row predicate `isWarning`; limit-state composer wrapped in a GestureDetector(opaque) → showPaywallSheet; composer TextField hoisted (no duplication). flutter analyze clean on lib/features/ai_coach/screens/ai_coach/ (only 3 pre-existing SpeechListenOptions deprecation infos, unrelated). Regression coach_go_pro_cta_reachable_test.dart green."
  - "hive_local — status: not_applicable — no Hive read/write; UI reachability only."
  - "client_to_server_contract — status: not_applicable — no request/body/gate change; the reached paywall is the existing showPaywallSheet → Razorpay path (unchanged)."
  - "postgres_schema — status: not_applicable — no schema change."
  - "postgres_data — status: not_applicable — no data change."
  - "migrations_applied — status: not_applicable — client-only."
  - "edge_function_code_vs_deploy — status: not_applicable — no EF change (FC8 is client UI only)."
  - "rls_policies — status: not_applicable — no RLS-touching change."
impact_analysis: >
  Feature blast radius (coach UI; no gate-logic change). Every FREE coach user who
  hit the 10/10 daily limit had NO reachable paywall CTA at the exact upgrade
  moment — a silent conversion-blocker. Post-fix the tappable GO PRO link persists
  through the limit AND the limit-state composer itself opens the paywall, so the
  gold "Go PRO" hint the user actually taps works. No gate, subscription, copy, or
  cloud contract changed; the free-limit enforcement (10/day, server-side) and the
  paywall sheet are untouched. Rides the same /build-apk as Units 2+3.
---

# f8c0de — AI-coach "Go PRO" CTA unreachable at the 10/10 daily limit

See YAML frontmatter for the full diagnosis. Founder-reported live (test7,
2026-07-04): tapping "Go PRO" at the daily limit did nothing.

## Root cause (one line)
At 10/10 the only tappable paywall affordance (the counter-row "GO PRO" link) was
gated `isWarning && !isLimitReached` — which HID it at exactly the limit — and the
gold "Daily limit reached — Go PRO" composer hint is a disabled `TextField`
placeholder with no gesture. Net: no reachable paywall CTA at the upgrade moment.

## Fix (client-only, input_bar.dart)
(a) counter-row predicate `isWarning && !isLimitReached` → `isWarning`
(`isLimitReached ⟹ isWarning`, so the link persists through the limit); (b) at the
limit, the composer TextField (disabled) is wrapped in a
`GestureDetector(behavior: HitTestBehavior.opaque, onTap: showPaywallSheet)` so the
placeholder becomes a paywall tap target. Below the limit the plain field renders —
typing/focus behave exactly as before. No gate/subscription/copy change.

## Test
`test/contracts/coach_go_pro_cta_reachable_test.dart` — source-anchored (comment-
stripped): pins the fixed predicate (and the ABSENCE of the old one) + the
limit-state GestureDetector→showPaywallSheet tap target. `input_bar.dart` is a
`part of screen.dart` private extension (not pumpable in isolation), so the
behavioral confirmation is the on-device tap at end-of-batch APK verify.
