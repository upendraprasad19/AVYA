---
bug_id: c3f9a1
date: 2026-06-06
batch: wls-reps-fix
status: fixed
blast_radius: account
symptom: >
  Two AI-coach interactions saved within the same millisecond both minted the Hive
  key coach_<ms>; the second coachBox.put overwrote the first (silent data loss).
  Surfaced as a non-deterministic CI failure in coach_writer_dedup_test ("different
  media_url -> not deduped" got the same key) and a real rapid-write loss path.
concept: coach_interactions
sot_registry_entry: coach_interactions
writers: >
  CoachInteractionRepository.saveUserMessagePending + saveInteraction minted
  'coach_${DateTime.now().millisecondsSinceEpoch}' (coach_interaction_repository.dart).
  Same-ms calls collided on the Hive key; the second put overwrote the first.
readers: >
  chat thread renderer in ai_coach_screen.dart iterates coach_* keys; a collided
  (overwritten) row means one user message vanishes from the rendered thread.
hive_key_prefix: coach_
hive_key_formula: coach_<monotonic ms> (mintCoachKey bumps to last+1 on collision)
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: ai_coach_interactions
cloud_columns: not_applicable (key minting; columns unchanged)
contract_test_path: test/ai_coach/coach_writer_dedup_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable (coachBox is user-scoped via wrapUserScopedBox)
forbidden_patterns_checked:
  - "minting coach keys directly from DateTime.now().millisecondsSinceEpoch (collides same-ms) — both sites now call mintCoachKey()."
proposed_fix: >
  A monotonic key minter (CoachInteractionRepository.mintCoachKey): if the current
  ms is <= the last minted ms, use last+1. Keeps the key numeric + ordered +
  collision-free with no format change. Both mint sites call it.
regression_test_planned: >
  test/ai_coach/coach_writer_dedup_test.dart — a tight loop minting many keys
  asserts all are unique (reliably reproduces the same-ms collision without the
  fix; passes deterministically with it).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "mintCoachKey monotonic minter; both mint sites call it; flutter analyze clean" }
  - { tier: 2, layer: hive_local_state, status: fixed_in_this_batch, evidence: "coach_writer_dedup_test mintCoachKey uniqueness loop passes; no same-ms collision" }
impact_analysis: >
  Account blast radius — rare in production (user taps are not sub-ms) but real
  under rapid / programmatic writes; two same-ms coach rows lost one. Also a CI
  flake source (coach_writer_dedup_test failed when two calls landed in the same
  ms). The monotonic minter is collision-free with no key-format change.
---

# AI-coach same-millisecond key collision (coach_<ms>)

## What happened
CoachInteractionRepository minted Hive keys as coach_<millisecondsSinceEpoch>.
Two interactions saved in the same ms got the same key; the second put overwrote
the first. Non-deterministic CI failure in coach_writer_dedup_test + a real
rapid-write data-loss path.

## Root cause
DateTime.now().millisecondsSinceEpoch is not unique under sub-ms successive
writes; a key derived purely from it collides.

## Fix
mintCoachKey() returns coach_<ms> but bumps ms to last+1 when the clock has not
advanced since the previous mint — monotonic, ordered, collision-free, same
numeric format. Both mint sites (saveUserMessagePending + saveInteraction) use it.

## Verification
coach_writer_dedup_test: a tight mint loop yields all-unique keys; the existing
"different media_url" case now passes deterministically. analyze clean.

## See also
- lib/features/ai_coach/repositories/coach_interaction_repository.dart (mintCoachKey)
- test/ai_coach/coach_writer_dedup_test.dart
