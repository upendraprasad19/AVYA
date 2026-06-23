---
bug_id: e5c1a2
date: 2026-06-23
batch: fix-e2e-cosmetics-copy
status: fixed
blast_radius: feature
symptom: >
  Full-charter web E2E (2026-06-21) cosmetic + copy observations (Unit C of the
  fix arc). OBS-1: Home Today-card macro row RenderFlex right-overflow (~2.5-15px)
  at ~390px. OBS-5: subscription card shows "RENEWS <date>" on a referral_trial
  (a trial EXPIRES, doesn't renew). OBS-10: recurring "A borderRadius can only be
  given on borders with uniform colors" exception (caught) from the Profile
  flush-card stack. OBS-12: Profile goal card reads "Goal: Lose 70kg" (mis-reads
  as "lose 70 kilograms" vs the intended "reach 70 kg"). OBS-13: full_name saved
  lowercase ("test three") → greeting "Recruit test".
concept: e2e_cosmetic_copy_sweep
sot_registry_entry: not_applicable
contract_test_path: test/contracts/title_case_name_test.dart
writers: >
  OBS-1 today_workout_card.dart macro row; OBS-5 subscription_section.dart:109
  RENEWS line (gated on subInfo.plan); OBS-10 flush_card.dart BoxDecoration;
  OBS-12 journey_timeline.dart goal insight; OBS-13 onboarding_provider.dart
  completeOnboarding full_name writer.
readers: >
  Home Today card (OBS-1); Profile subscription section (OBS-5); Profile flush
  stack (OBS-10); Profile journey card (OBS-12); every greeting/profile-header
  that reads full_name (OBS-13).
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: "not_applicable"
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - "OBS-1: greedy Spacer() in the macro Row replaced with SizedBox(width:8) so label+number share the remaining width (no 3-way flex contention)."
  - "OBS-10: flush_card non-uniform Border + non-null borderRadius (Flutter assert) — rounded (first/last) cards now use a uniform Border.all; square middle cards use a null radius so the top-drop rail stays legal."
  - "OBS-5: 'RENEWS' shown only when plan is NOT a trial; trials show 'EXPIRES'."
proposed_fix: >
  5 cosmetic/copy fixes (all flutter-analyze clean): OBS-1 Spacer→SizedBox in the
  macro row; OBS-5 RENEWS→EXPIRES when (subInfo.plan ?? '').contains('trial');
  OBS-10 uniform-border-when-rounded in flush_card; OBS-12 "Goal: Reach 70kg";
  OBS-13 title-case full_name at the onboarding writer (textCapitalization.words
  is only a mobile keyboard hint, no effect on web).
regression_test_planned: >
  Cosmetic copy/layout fixes are flutter-analyze-verified + confirmed visually on
  the dev server (Flutter-web CanvasKit can't be screenshotted by the preview
  tools; founder visual re-check is the visual-verification channel — same as the
  FIX-1 blank-Home confirmation). OBS-1 overflow + OBS-10 render asserted live.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "5 files edited; flutter analyze (5 files) No issues found" }
impact_analysis: >
  Feature-tier, all-cosmetic/copy. No data, sync, or isolation impact. OBS-10 was
  a CAUGHT exception (no crash). OBS-13 (lowercase name) is the only one with a
  small data effect (the stored name) — fixed at the writer for new accounts; a
  one-off title-case heal for existing lowercase names was NOT added (low value,
  founder can edit via Profile). OBS-9 (empty Home card) + OBS-14 (DOB picker
  cramp) are deferred to a founder device-visual repro pass — they need a real
  CanvasKit render to pin the exact widget / measure the cramp (the plan flagged
  OBS-14 as measurement-gated). Tracked, not silently dropped.
---

# E2E cosmetics + copy sweep (e5c1a2) — Unit C

5 fixes (OBS-1/5/10/12/13). OBS-9 (empty Home card) + OBS-14 (DOB picker cramp)
are founder-device-visual-repro-gated (CanvasKit can't be screenshotted by the
preview tools; the exact widget / cramp needs a real render) — tracked here +
in the plan, to finish on the founder's next dev-server visual pass.

## Fixes
- **OBS-1** today_workout_card.dart — `Spacer()` → `SizedBox(width: 8)` (macro row overflow).
- **OBS-5** subscription_section.dart — `RENEWS` → `EXPIRES` when the plan is a trial.
- **OBS-10** flush_card.dart — uniform `Border.all` on rounded (first/last) cards, null radius on square middle cards (kills the borderRadius-uniform assert).
- **OBS-12** journey_timeline.dart — "Goal: Reach 70kg" (was "Lose 70kg").
- **OBS-13** onboarding_provider.dart — title-case `full_name` at the writer.

## See also
- docs/reviews/e2e-fullcharter-2026-06-21-evidence.md (OBS source)
- the 5 edited files above
