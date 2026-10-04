---
bug_id: c2b8e5
date: 2026-08-24
batch: launch-blockers-1
status: fixed
blast_radius: account
symptom: >
  The paywall's hero letterhead reads "PRO is a PRO feature" — and, from the Profile upgrade chip,
  "PRO Upgrade is a PRO feature". It appears on the three highest-intent surfaces in the app: the
  Profile FREE PLAN upgrade chip, the subscription card, and the subscription-expiry renew banner
  shown to a lapsed subscriber. These are the screens a user reaches when they have already decided
  to pay.
concept: >
  A display template applied to inputs it was never meant to receive. PaywallSheet.feature is a
  DISPLAY STRING interpolated verbatim into "<feature> is a PRO feature". That sentence is correct
  when the sheet was opened BY a specific locked feature, and degenerate when it was opened by a
  general "go PRO" affordance, where there is no feature to name. Both kinds of caller went through
  one unconditional template, so the second kind produced a tautology.
sot_registry_entry: >
  None added. subscription_state already registers the isPro writer/reader set, and this fix
  touches neither — showPaywallSheet is display plus a paywall_shown telemetry value, and never
  reaches gate() or verifyFromServer(). Recording that explicitly because the OI-76 board entry
  once claimed the opposite (that coding rule 19's server verification keyed off this id), and the
  sibling test paywall_feature_label_test.dart already corrects it.
writers:
  - { file: lib/features/home/screens/home_screen.dart, method: "expiry renew banner onRenew — passed the bare label 'PRO'", line: 568 }
  - { file: lib/features/profile/screens/profile/subscription_section.dart, method: "FREE PLAN upgrade chip onTap — passed the bare label 'PRO'", line: 195 }
  - { file: lib/features/profile/screens/profile/profile_content.dart, method: "profile upgrade affordance — passed 'PRO Upgrade'", line: 221 }
readers:
  - { file: lib/shared/widgets/paywall_sheet.dart, method: "WardLetterhead title — interpolated the value verbatim into '<feature> is a PRO feature'", line: 367 }
  - { file: lib/shared/widgets/paywall_sheet.dart, method: "_featureSubtitle switch — a bare label also misses every case and falls to the generic default (pre-fix line; :134 post-fix)", line: 75 }
hive_key_prefix: not_applicable — no box, key or adapter is involved; this is a render-time string.
hive_key_formula: not_applicable — see hive_key_prefix.
sync_methods: not_applicable — nothing is synced; the label never leaves the device except as a paywall_shown telemetry string.
restore_methods: not_applicable — no restore leg reads a paywall label.
cloud_table: none — no table stores the paywall letterhead.
cloud_columns: none — see cloud_table.
contract_test_path: test/contracts/paywall_generic_upgrade_title_behavioral_test.dart
ist_handling: not_applicable — no date key, counter reset or cloud date column is touched.
provider_invalidations: none — the title is computed during build from a constructor argument.
telemetry_op_types: >
  None added, and one behaviour deliberately preserved: initState still logs paywall_shown with
  feature=<raw value>, so the conversion funnel keeps attributing each surface separately. The fix
  changes only what is RENDERED, not what is measured.

  ⚠ THE FIRST CUT BROKE THIS AND A HERMES L1 PASS CAUGHT IT. Routing all three sites through one
  `genericUpgrade = 'PRO'` sentinel collapsed the Profile chip's segment (previously 'PRO Upgrade')
  into the same bucket as the subscription card and the renew banner — silently ending a funnel
  series, which is exactly what this field promised would not happen. Fixed by giving the Profile
  chip its own sentinel, `genericUpgradeProfile = 'PRO Upgrade'`; `isGenericUpgradeLabel` matches
  BOTH (derived from the constants, not re-typed), so the letterhead is correct on every surface
  while telemetry stays distinguishable.
cross_account_guard: not_applicable — no user-scoped Hive access on this path.
forbidden_patterns_checked: >
  Checked and clean. No Container with color+decoration, no inline isPro added, no raw
  GoogleFonts (the title flows through WardLetterhead / AppTypography), no client-side key.
  PaywallSheet remains the ONLY paywall UI per coding rule 7 — no new modal was introduced.
proposed_fix: >
  Introduce PaywallSheet.genericUpgrade as a named sentinel, and a pure top-level
  paywallLetterheadTitle(feature) that returns "Unlock every PRO feature" for a generic upgrade
  prompt and the existing "<feature> is a PRO feature" for a real gate. The three call sites pass
  the sentinel instead of a bare string. The predicate matches trimmed and case-insensitively, and
  treats empty as generic, so a future call site passing 'pro' or '' cannot reintroduce the
  tautology. The function is top-level and pure specifically so it is testable without pumping the
  sheet, whose initState fires telemetry and whose tree needs Riverpod and Hive.
regression_test_planned: [test/contracts/paywall_generic_upgrade_title_behavioral_test.dart]
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze clean on paywall_sheet.dart and the three call sites. New behavioral test 6/6. The pre-existing paywall_feature_label_test.dart still passes, so the OI-76 contract is intact." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No box or key involved." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No rows read or written." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function involved." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron reads a paywall label." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket or object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: verified, evidence: "Razorpay is reached from this sheet's CTA and is untouched — only the letterhead string above it changed; the checkout path is byte-identical." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "No request shape changed. paywall_shown telemetry deliberately keeps its existing value." }
impact_analysis: >
  Severity: no data is at risk and nothing breaks — this is pure copy. It earns account-tier
  attention anyway because of WHERE it renders. The two surfaces a user reaches having already
  decided to pay, plus the renew prompt for someone whose subscription just lapsed, all opened with
  a sentence that reads like a placeholder someone forgot to fill in. On a screen asking for ₹349 a
  month, that is a trust cost, not a typo.

  Reach: every free user who taps the Profile upgrade chip or the subscription card, and every
  lapsed subscriber shown the renew banner. That is the entire top of the payment funnel.

  Why the board under-rated it: OI-97 is filed P3 on the reasoning that "no user sees a wrong
  claim, only a weak one". That is true of the other labels in the entry, and false for these
  three — "PRO is a PRO feature" is not weak copy, it is a rendering artefact. The rating was made
  without reading the rendered letterhead, which is the general hazard in judging a template bug
  from its call sites.

  Why the existing test did not catch it: paywall_feature_label_test.dart is a source-grep test and
  says so in its own header. Per coding rule 21 a source-grep proves PRESENCE only — it pins that
  no call site passes an AppConstants.feature* id, which is a different defect. It would still pass
  with the tautology fully live. The new test calls the production function with the exact inputs
  the real call sites pass, and its MUTATION GUARD group reddens if the unconditional template
  returns: restoring the old one-liner failed 4 of 6 tests, with 'PRO is a P...' and
  ' is a PRO feature' in the output.
---

# c2b8e5 — the paywall told users "PRO is a PRO feature"

## What the user sees

Three entry points open the paywall as a general upgrade prompt rather than a feature gate:

| Surface | Passed | Rendered |
|---|---|---|
| Profile FREE PLAN → UPGRADE chip | `'PRO'` | **PRO is a PRO feature** |
| Subscription card | `'PRO'` | **PRO is a PRO feature** |
| Profile upgrade affordance (`profile_content.dart:221`) | `'PRO Upgrade'` | **PRO Upgrade is a PRO feature** |

## Why it happened

`paywall_sheet.dart:367` rendered `'${widget.feature} is a PRO feature'` unconditionally. The
sentence is right when a specific locked feature opened the sheet — *"Progress Photos is a PRO
feature"* — and degenerate when the user simply tapped "upgrade", because there is no feature to
name. One template served both kinds of caller.

## The fix

A named sentinel plus a pure title function:

```dart
static const String genericUpgrade = 'PRO';

String paywallLetterheadTitle(String feature) => isGenericUpgradeLabel(feature)
    ? 'Unlock every PRO feature'
    : '$feature is a PRO feature';
```

`isGenericUpgradeLabel` matches trimmed and case-insensitively and treats empty as generic, so a
later call site passing `'pro'`, `'PRO Upgrade'` or `''` cannot bring the tautology back. It
matches by EQUALITY, not substring — `Progress Photos` and `Protein Alerts` both begin with "Pro"
and must keep naming themselves; that case is pinned by its own test.

## Verification

- `flutter test test/contracts/paywall_generic_upgrade_title_behavioral_test.dart` → 6/6.
- Mutation (restore the unconditional template) → 4 of 6 red, output showing the exact tautology.
- The pre-existing `paywall_feature_label_test.dart` still passes (OI-76 contract intact).
