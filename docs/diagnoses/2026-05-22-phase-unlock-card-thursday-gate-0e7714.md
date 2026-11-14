---
bug_id: 0e7714
date: 2026-05-22
batch: APK Test #16.2 +30 obs 5-12 batch (commit 9 / Theme E)
status: shipped
symptom: |
  Founder mid-Phase-1-Week-4 (Wed 2026-05-21) saw the UNLOCK PHASE 2
  card and asked "since when does the user start seeing unlock phase
  2? or subsequent phases? it should open up on thursday of the last
  week."

  Root cause: phase_unlock_card.dart:9 gated on
  `if (plan.currentWeek < 4) return const SizedBox.shrink()` — the
  card surfaces for ANY day of Week 4, including Monday. The 80%-
  completion check (secondary at line 14) controlled COPY (locked
  "PHASE 2 AVAILABLE" vs unlocked "PHASE 1 COMPLETE!") but did not
  delay surface. So a user with a single Monday workout in Week 4 saw
  the card 4 days into the week with most of the week still ahead.
concept: phase_unlock_card_surface_gate
sot_registry_entry: workout_logs
writers:
  - { file: lib/features/train/screens/train/phase_unlock_card.dart, method_or_widget: _buildPhaseUnlockCard — gate is `plan.currentWeek != 4 || DateTime.now().weekday < DateTime.thursday`, line: 6 }
readers:
  - { file: lib/features/train/screens/train/screen.dart, method_or_widget: train screen renders phase_unlock_card when applicable, line: 1 }
hive_key_prefix: "n/a — UI gate change only"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: n/a
cloud_columns: []
contract_test_path: test/contracts/phase_unlock_card_thursday_gate_test.dart
ist_handling:
  - { file: lib/features/train/screens/train/phase_unlock_card.dart, line: 18, source: "Uses LOCAL DateTime.now().weekday — UI presence is perceptual (Thursday begins at local midnight). istNow() would surface at 05:30 local for Indian users which the founder explicitly does NOT want. Per CLAUDE.md §4.5, IST helpers are for date-key math (Hive keys + cloud date columns + counter resets), not UI presence gates." }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: pure UI render gate; reads plan.currentWeek which is already user-scoped via currentPlanProvider.
forbidden_patterns_checked:
  - "Bare `plan.currentWeek < 4` predicate (pre-fix shape) — surfaces card every day of Week 4."
  - "istNow().weekday for UI presence — would shift surface time to 05:30 local for Indian users."
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "phase_unlock_card.dart:9 gate rewritten" }
  - { tier: 12, name: end_to_end_contract, status: fixed_in_this_batch, evidence: "test/contracts/phase_unlock_card_thursday_gate_test.dart — 4 assertions covering Thursday gate, pre-fix predicate gone, week==4 scope, no IST shift" }
impact_analysis:
  callers_audited:
    - lib/features/train/screens/train/phase_unlock_card.dart (only file with this gate)
  callers_updated_in_this_batch:
    - lib/features/train/screens/train/phase_unlock_card.dart
    - lib/features/train/CLAUDE.md (new pitfall row)
  callers_unchanged:
    - lib/features/train/screens/graduation_screen.dart (graduation flow downstream — unchanged; only the entry-point card is gated)
proposed_fix: |
  Replace the bare `plan.currentWeek < 4` predicate with a combined
  Week-4-AND-weekday-Thursday gate:

  ```dart
  if (plan.currentWeek != 4 ||
      DateTime.now().weekday < DateTime.thursday) {
    return const SizedBox.shrink();
  }
  ```

  Notes:
  - `DateTime.thursday == 4` in Dart's DateTime constants. The named
    constant is preferred for readability.
  - `!= 4` (vs `< 4`) ensures the card also hides on weeks 5+ —
    post-unlock the user shouldn't see the entry-point card.
  - LOCAL weekday on purpose. UI presence is perceptual ("Thursday
    begins at local midnight"). istNow().weekday would surface the
    card at 05:30 local for Indian users which contradicts the
    founder's "should open up on thursday" intent.
  - The COPY gate (locked "PHASE 2 AVAILABLE" vs unlocked "PHASE 1
    COMPLETE!") at line 14 stays unchanged — completion rate still
    governs which message renders inside the (now Thursday-gated)
    card.

  4-day runway (Thursday → Sunday) gives users a reasonable window to
  finish Week 4 workouts and tap unlock. Less than a week feels
  ceremonial; more would be premature.
regression_test_planned:
  - test/contracts/phase_unlock_card_thursday_gate_test.dart — 4 assertions: gate uses DateTime.thursday (or literal 4); bare pre-fix predicate gone; week == 4 scope (not >= 4); LOCAL weekday (no istNow shift).
related_bugs:
  - b0baa5  # Theme H — phase unlock startDate fix (same flow downstream)
  - ec4d27  # Theme F — phase unlock end-to-end UX (same flow downstream)
---
# Body

## Why LOCAL weekday, NOT IST

CLAUDE.md §4.5 says all date-key math uses IST. That rule is about
when a "day" begins for storage purposes — Hive keys, cloud `date`
columns, counter resets — so a workout logged at 23:00 IST is "today"
not "yesterday's UTC".

UI presence gates are different. The user perceives "Thursday begins"
at their local midnight, not at IST's 05:30 local equivalent (for
users outside IST). The card surface time is a perceptual concern;
applying IST shift would mean:
- Indian user: card appears Wed 18:30 → mostly correct, but feels
  ~6 hours early.
- US user: card appears Wed 18:30 their local Tuesday → 1.5 days
  early.

LOCAL keeps the surface time aligned with each user's perceived day
boundary. The trade-off (a user crossing time zones during Week 4
would see the surface shift) is acceptable because (a) crossing time
zones is rare during a 4-week phase, (b) the surface still happens
on a Thursday in their current timezone, which matches the founder's
stated semantic.

## Why 4-day runway (Thu-Sun), not 3 (Fri-Sun) or 5 (Wed-Sun)

3 days feels rushed — the user has one weekday (Fri) and a weekend
to act.
5 days starts blurring into "anytime Wed onwards" which is back
toward the pre-fix monday-surface complaint.
4 days = Thursday + Friday + Sat + Sun = the natural "end of week"
window with a weekday for those who train Mon-Fri and a weekend for
those who train Sat-Sun. The founder's "thursday of the last week"
formulation fits cleanly.

## Test coverage gap (documented for future work)

This test is source-grep only — pins the gate expression. A behavioral
test would need a fake clock so we could assert "on Wednesday: card
hidden; on Thursday: card visible". Without `clock` package wiring,
flutter widget tests can't easily fake DateTime.now(). For now the
source-grep coverage + manual smoke during APK +31 install is
sufficient. If we later add a clock-injection layer (e.g. for the
hourly-quote provider testing), the behavioral test ports cleanly.
