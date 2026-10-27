---
bug_id: d5f1b8
date: 2026-09-28
batch: gate14-migration-collision (standalone, feature-tier — prevention half of OI-255)
status: fixed
blast_radius: feature
symptom: |
  OI-255 (filed 2026-09-27 from `template-stable-identity`) documented that
  `template-stable-identity` and `ops-alerting` independently minted BOTH
  migration 145 and migration 146 before either branch saw the other's draft
  file — four distinct `.sql` files across two colliding number prefixes, all
  four applied live before the collision was noticed during a `git pull`
  before a merge. Gate 14 (`scripts/check_migrations_applied.dart`) never
  caught it at commit or push time on either branch: its "unapplied" check
  matches by bare numeric prefix via `appliedMigrations.any((a) =>
  a.startsWith(prefix) || ...)` (line 124), so BOTH colliding files under a
  shared number independently satisfy the SAME ledger entry and the gate
  reports PASS for all four. OI-255 named this as the root cause and proposed
  two fix shapes, "(a) and/or (b)": (a) a migration-number allocator mirroring
  `mint_oi.sh`'s ref-reservation compare-and-swap, or (b) widen Gate 14 to
  hard-fail on two `.sql` files sharing an exact bare numeric prefix. This
  fix implements (b) — the founder authorized it explicitly in chat after I
  explained what it does, in preference to (a) for now, on the reasoning that
  (b) alone already closes the practical risk (a collision is caught before
  it can land) at a fraction of the engineering cost of a full allocator.
concept: migration-number-collision-detection
sot_registry_entry: not_applicable — gate-script fix, not a Hive/cloud writer/reader contract
writers:
  - { file: scripts/check_migrations_applied.dart, method_or_widget: "the pre-existing 'unapplied' check's ambiguous match — `appliedMigrations.any((a) => a.startsWith(prefix) || ...)`", line: 124 }
readers:
  - { file: scripts/check_migrations_applied.dart, method_or_widget: "new collision check calling findMigrationPrefixCollisions() before the snapshot comparison runs", line: 67 }
  - { file: scripts/migration_collision_lib.dart, method_or_widget: "findMigrationPrefixCollisions() — groups local migration filenames by bare prefix, excluding the two permanently grandfathered prefixes", line: 33 }
hive_key_prefix: not_applicable — no Hive involvement
hive_key_formula: not_applicable — no Hive involvement
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: "test/scripts/migration_collision_lib_test.dart (7 pure unit tests) + test/scripts/check_migrations_applied_collision_e2e_test.dart (3 e2e tests spawning the real gate binary)"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: not_applicable — no per-user data path touched; this is a repo-tooling gate
forbidden_patterns_checked:
  - "widening the existing 'unapplied' check's own `startsWith` match instead of adding a separate check — rejected: that check's job is 'is this file recorded as applied', and conflating it with 'is this number ambiguous' would make one red exit code mean two different things, harder to message correctly to the reader (the two failure modes need different fix instructions)."
  - "hard-failing on ANY prefix collision including the two already-applied, immutable 145/146 pairs — rejected: this would make the fix retroactively unshippable, since those four files exist in this repo permanently. A grandfather list (scripts/migration_collision_lib.dart:26, referencing OI-255 by name) is the same pattern rule 24 already uses for check_gate_test_ledger.dart's `grandfathered:` gates."
proposed_fix: |
  Added scripts/migration_collision_lib.dart with a pure function
  findMigrationPrefixCollisions(filenames, {grandfathered}) that groups
  supabase/migrations/*.sql basenames by the token before their first `_`
  and returns any group with >1 file that is NOT in the grandfathered set.
  scripts/check_migrations_applied.dart now calls this immediately after
  listing local migrations (before loading the applied-snapshot at all) and
  exits 1 naming every colliding filename if any NEW (non-grandfathered)
  collision is found. The two prefixes already known to collide -- "145" and
  "146" (OI-255) -- are permanently grandfathered by name in
  grandfatheredMigrationCollisionPrefixes, with a comment explicitly
  forbidding adding further entries to that set: a future collision must be
  avoided by re-deriving the next free number fresh at draft time, not
  grandfathered in after the fact.
regression_test_planned: |
  test/scripts/migration_collision_lib_test.dart: 7 pure tests covering no-
  collision, single-file, a genuine new collision (2 files sharing "148",
  naming both), the real 145/146 quadruple correctly NOT flagged, an explicit
  empty-override grandfather set still catching 145/146 (proves the override
  parameter genuinely narrows rather than silently falling back to the
  default), 3-way collisions naming all three files, and a letter-suffixed
  prefix ("145a") correctly NOT colliding with the bare "145".
  test/scripts/check_migrations_applied_collision_e2e_test.dart: 3 e2e tests
  spawning the real dart run scripts/check_migrations_applied.dart against a
  throwaway repo -- (1) two files sharing prefix "148", each independently
  present in the applied-migrations snapshot (reproducing the EXACT shape
  that let the real 145/146 collision through Gate 14 twice) -> asserts
  non-zero exit + stderr names both files; (2) the real 145/146 quadruple ->
  asserts exit 0 (must not start failing every future commit); (3) the
  existing single-migration happy path -> asserts exit 0 + "PASS" in stdout
  (no regression on Gate 14's pre-existing behavior).
  MUTATED AND RUN (rule 21): Mutation 1 -- neutered
  findMigrationPrefixCollisions to always `return <String, List<String>>{}`
  (mutation confirmed applied via diff before running) -- reddened 4/10
  tests: the pure "THE OI-255 SCENARIO" test, the pure "three files sharing
  one prefix" test (crashed on a null-check operator indexing the
  now-missing key -- a genuine assertion-path failure, not a compile error,
  confirmed by reading the failure output), and both relevant e2e tests
  ("THE OI-255 SCENARIO" e2e). Mutation 2 -- removed the
  `!grandfathered.contains(entry.key)` clause so ANY length>1 group is
  flagged (mutation confirmed applied via diff) -- reddened exactly 2/10
  tests: the pure "known 145/146 grandfathered pairs are NOT re-flagged"
  test and its e2e twin. Both mutations left the file compiling and
  semantically wrong (not a compile-error false-red); both reddened tests
  for the correct reason (an `expect()` assertion failure naming the actual
  vs expected collision set, not a swallowed exception). File restored to
  the pre-mutation version after each experiment; final `flutter test` run
  post-restore: 10/10 green.
impact_analysis: |
  Gate 14 now fails any commit that introduces a NEW migration-number
  collision (two `.sql` files sharing a bare numeric prefix outside the
  145/146 grandfather set), at commit time locally and in CI -- closing the
  exact blind spot that let the real 145/146 collision land twice
  undetected. Does not touch or attempt to resolve the two already-applied,
  immutable collisions themselves (impossible per
  supabase/migrations/CLAUDE.md's immutability rule) -- OI-255's underlying
  historical fact remains permanently true and undone; this fix only
  prevents a THIRD recurrence. OI-255's fix-shape option (a), a
  mint_oi.sh-style number-reservation allocator, remains unimplemented and is
  a legitimate future enhancement (would catch a collision even earlier, at
  draft time on a still-diverged branch, rather than at first commit) --
  intentionally not bundled into this fix per the founder's explicit choice
  to do (b) alone for now. No production runtime code touched; this is
  entirely local to the pre-commit/pre-push/CI gate tooling.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "scripts/check_migrations_applied.dart:67 wired to the new scripts/migration_collision_lib.dart. flutter analyze lib/ unaffected (scripts/ is not under lib/); dart analyze on both changed files reported no issues." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive read/write; this is a repo-tooling gate script." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema touched." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No new migration file added by this fix; it changes only how EXISTING and FUTURE migration files are gated." }
---

## Summary

OI-255 documented that Gate 14's own "unapplied" check cannot distinguish
"this migration is genuinely unapplied" from "two different migrations share
this number" — a shared bare numeric prefix satisfies its `startsWith` match
for either colliding file, so the real 145/146 collision (two branches,
independently minted, both applied live before anyone noticed) passed Gate 14
cleanly on both sides. Added a separate, stricter check
(`scripts/migration_collision_lib.dart`'s `findMigrationPrefixCollisions`)
that Gate 14 now runs before its existing snapshot comparison: any two
`supabase/migrations/*.sql` files sharing a bare numeric prefix fail the
commit, naming both files, UNLESS that prefix is in a small permanent
grandfather list (currently just "145" and "146", the two already-applied,
immutable collisions from OI-255 — never add to this list; a future
collision must be avoided at draft time instead). Both new tests were
mutation-proven: neutering the detection reddened 4 tests, neutering the
grandfather exclusion reddened 2, confirming the new protection is real and
narrowly targeted. Does not implement OI-255's other proposed fix shape (a
`mint_oi.sh`-style migration-number allocator) — founder chose option (b)
alone for now.
