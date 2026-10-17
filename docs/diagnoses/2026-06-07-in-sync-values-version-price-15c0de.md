---
bug_id: 15c0de
date: 2026-06-07
batch: psych-skill-and-audit-2026-06-07 (audit remediation — Batch 4, in-sync values)
status: fixed
blast_radius: account
symptom: >
  Hardcoded values/figures had drifted from their single source of truth.
  F13: AppConstants.appVersion lagged at '1.0.0+28' while pubspec was '1.0.0+33',
  so client_errors / telemetry rows from builds +29..+33 were mis-labelled +28 —
  exactly the regression the constant's own comment was added to prevent — and
  the parity gate only ran at build time. F35: the paywall computed the discounted
  price rounded in whole rupees while the server charges a paise-rounded amount,
  so a promo's displayed price differed from the actual charge by up to ₹0.50.
  F11: the phase-variant paywall baked '₹349 / ₹2,999' as a literal, so a price
  change in AppConstants would silently miss that one screen. Plus 31 raw-hex
  Color(0x..) literals across 9 feature files bypassed the Wardroom palette.
concept: hardcoded_value_centralization
sot_registry_entry: "prices → AppConstants; appVersion → pubspec (gate check_app_version_matches_pubspec, now pre-commit); colors → AppColors (gate check_raw_hex_in_features, hard-fail)"
writers:
  - "{ file: pubspec.yaml, line: 19 } — version SoT (F13)"
  - "{ file: lib/core/constants/app_constants.dart, method: monthlyPriceInr/yearlyPriceInr, line: 38 } — price SoT (F11)"
readers:
  - "{ file: lib/core/constants/app_constants.dart, method: appVersion, line: 112 } — telemetry build label (was stale +28)"
  - "{ file: lib/shared/widgets/paywall_sheet.dart, method: _discountedPrice, line: 181 } — displayed discounted price (was rupee-rounded vs server paise)"
hive_key_prefix: n/a
hive_key_formula: n/a
sync_methods: n/a
restore_methods: n/a
cloud_table: client_errors
cloud_columns: "client_version (telemetry build label — F13)"
contract_test_path: scripts/check_app_version_matches_pubspec.dart
ist_handling: n/a
provider_invalidations: n/a
telemetry_op_types: "n/a — F13 fixes the build LABEL on all telemetry, not an op_type"
cross_account_guard: n/a (app-wide constants)
forbidden_patterns_checked: >
  raw Color(0x..) in lib/features (check_raw_hex_in_features, hard-fail, allowlist
  empty); hardcoded ₹349/₹2,999/15-per-day (check_hardcoded_pricing_and_limits,
  hard-fail, allowlist empty); appVersion != pubspec (check_app_version_matches_pubspec,
  now wired into pre-commit + CI).
proposed_fix: >
  appVersion '1.0.0+28' → '1.0.0+33' to match pubspec + wire
  check_app_version_matches_pubspec.dart into pre-commit/CI (was build-time only).
  paywall _discountedPrice now rounds in paise (byte-identical to
  create-razorpay-order). phase-variant price interpolates AppConstants. 31 raw-hex
  literals → 20 new grouped AppColors tokens (visuals preserved). steps goal 10000 →
  AppConstants.defaultDailyStepGoal. sign-in version literal → AppConstants.appVersion.
  scan/cart doc comments corrected. The raw-hex + pricing gates flipped to hard-fail.
regression_test_planned: check_raw_hex_in_features + check_hardcoded_pricing_and_limits (hard-fail) + check_app_version_matches_pubspec (pre-commit) + check_gate_scripts_wired — all GREEN
touched_layers_checked:
  - "{ layer: client_code, status: fixed_in_this_batch, evidence: 31 hex→AppColors (20 tokens); price/version/steps→SoT; F35 paise-round; analyze clean; 4 gates PASS at hard-fail }"
  - "{ layer: postgres_data, status: fixed_in_this_batch, evidence: client_version telemetry label now '1.0.0+33' — rows from new builds correlate to the actual APK }"
  - "{ layer: external_services, status: verified, evidence: F35 — paywall display now matches create-razorpay-order's paise rounding; the client never sends a self-computed amount, only discountPct, so no charge-path change }"
impact_analysis: >
  F13: production errors from builds +29..+33 were silently mislabelled +28 —
  correlation to a specific APK was broken (the documented F10.1 regression class);
  fixed + the gate now runs every commit. F35: free/promo users saw a price up to
  ₹0.50 off the real charge (a small but real trust leak for an integrity-led brand).
  F11: latent price-drift on one paywall. Plus the raw-hex + pricing gates are now
  hard-fail with empty allowlists, so the centralization can't regress.
closes-diagnose: 15c0de
---

# In-sync values: version / price / colour centralization (F11 / F13 / F35 + raw-hex sweep)

## Fixes
- **F13 (appVersion):** `'1.0.0+28' → '1.0.0+33'` (matches pubspec). Wired
  `check_app_version_matches_pubspec.dart` into pre-commit + CI (removed from the
  three build-time-only skip-lists) so the constant can never lag pubspec again.
- **F35 (paywall rounding):** `_discountedPrice` now rounds in **paise**
  (`_discountedPaise`, byte-identical to `create-razorpay-order`) and the labels
  render the exact charge; the client only ever sends `discountPct`, so this is a
  display-alignment fix with no charge-path change.
- **F11 (phase-variant price):** interpolates `AppConstants.monthlyPriceInr` /
  `yearlyPriceInr`.
- **Raw-hex sweep:** 31 `Color(0x..)` literals across 9 feature files → 20 new,
  grouped `AppColors` tokens (chart hues / hydration ladder / gradient stops /
  slate / coach-bubble greys) — exact hex preserved, no visual change.
- **F15 / F22 / F30:** steps goal `10000` → `AppConstants.defaultDailyStepGoal`;
  sign-in footer version literal → `AppConstants.appVersion`; scan/cart doc comments
  corrected to match the real day-caps.

## Gates (now hard-fail)
`check_raw_hex_in_features` + `check_hardcoded_pricing_and_limits` flipped to
hard-fail with empty allowlists; `check_app_version_matches_pubspec` moved to
every-commit. All green; `check_gate_scripts_wired` confirms 71 gates wired.
