---
bug_id: 0a1e17
date: 2026-05-17
batch: audit-2026-05-17 / OI-01 reader-manifest exhaustiveness gate
status: fixed
oi_closed: OI-01
symptom: |
  The build-apk Gate 18 script `scripts/check_reader_manifest_complete.dart`
  only enforced the "forbidden-patterns absent" half of the reader-side
  manifest contract. It did NOT enforce "every source file in `lib/` +
  `supabase/functions/` that reads a concept's Hive `key_prefix` must
  appear in that concept's `readers:` list" — a new reader could grep
  `workoutBox.keys` for `exlog_*` rows tomorrow and bypass the registry
  silently. The manifest was therefore a passive document, not an
  enforceable contract.
concept: reader_manifest_exhaustive_completeness
sot_registry_entry: workout_receipt_rendering
writers:
  - { file: scripts/check_reader_manifest_complete.dart, method: main, line: 28 }
  - { file: docs/sot_registry.yaml, method: concept manifests, line: 47 }
readers:
  - { file: test/contracts/reader_manifest_exhaustiveness_test.dart, method: subprocess gate runner, line: 25 }
  - { file: scripts/check_reader_manifest_complete.dart, method: _extractConcepts, line: 270 }
hive_key_prefix: "exlog_"
hive_key_formula: "'exlog_${istDateStr(date)}_${uuidV5(lowercase+trim(name))}' (representative — same gate runs for every concept's prefix)"
sync_methods: [none]
restore_methods: [none]
cloud_table: none
cloud_columns: [none]
contract_test_path: test/contracts/reader_manifest_exhaustiveness_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a — gate is a static build-time check; no runtime auth surface"
forbidden_patterns_checked:
  - { pattern: "reader_manifest gate scans only forbidden_legacy_patterns", absent: true }
proposed_fix: |
  Two-phase rewrite of `scripts/check_reader_manifest_complete.dart`:

  Phase 1 (unchanged): forbidden_legacy_patterns enforcement.

  Phase 2 (new): walks docs/sot_registry.yaml extracting every concept
  whose `reader_manifest_complete: true` AND `hive.key_prefix` is a
  non-placeholder non-empty value. For each, source-greps `lib/` +
  `supabase/functions/` for any line matching one of three strict
  Hive-read context detectors anchored on the prefix literal:
    1. `.get|containsKey|delete|put('<prefix>...')`
    2. `.startsWith('<prefix>')`
    3. (intentionally NOT matched: bare subscript `['<prefix>...']`
       and equality `== '<prefix>'`, both noise-prone — first
       false-positives on row field reads like `row['weight_kg']`,
       second on logging-type enum comparisons like
       `loggingType == 'weight_reps'`)

  Each matched file must appear in EITHER the concept's `readers:`,
  `writers:`, or new `reader_allow_files:` list. The allow-files list
  accepts both inline-map (`- { file: ..., reason: ... }`) and bare-path
  (`- lib/path/to/file.dart  # reason: ...`) forms.

  Registry side: populated `reader_allow_files:` whitelists across 15
  concepts (67 file entries total) and added 14 new genuine reader
  entries across 8 concepts. Every new entry was verified by reading
  the cited file line-range with the Read tool — per
  `feedback_audit_findings_require_live_verification.md`.

  Bug-id intentionally named `oi-01-exhaustive-reader-gate` so future
  searchers find it from the OI number alone.
regression_test_planned:
  - test/contracts/reader_manifest_exhaustiveness_test.dart
---
# Body

## Symptom

OI-01 in `docs/audit/open_issues.md` documented the gap: the reader
manifest in `sot_registry.yaml` was passive, not an enforceable
contract. A new widget added tomorrow that scans `workoutBox.values`
for `exlog_*` rows would never be caught by the gate even though it
silently introduces another writer/reader drift surface — the bug class
that has dominated every APK test cycle since Test #6.

## Root cause

`scripts/check_reader_manifest_complete.dart` had one job: enforce
`forbidden_legacy_patterns`. The script never inspected concept-level
`readers:` arrays or attempted to verify exhaustiveness. The manifest
was thus a documentation artefact, not a gate input.

## Fix

Three changes, shipped together:

1. **Gate script extended** (`scripts/check_reader_manifest_complete.dart`):
   added a new Phase 2 that enumerates concepts with
   `reader_manifest_complete: true` AND `hive.key_prefix`, then
   source-greps every `.dart` / `.ts` file under `lib/` +
   `supabase/functions/` for strict Hive-read contexts on the prefix.
   Each match must be declared (readers / writers / allow-files).

2. **Registry populated** (`docs/sot_registry.yaml`): 25
   manifest-complete concepts audited. Initial gate run surfaced 87
   undeclared readers across 16 concepts. After verifying each by
   reading the cited code, the registry now declares:
   - 14 new `readers:` entries (genuine readers that were missing —
     `progression_resolver`, `badge_service`, `profile_screen` weight
     trajectory, `day_detail_sheet._hasExerciseLogsForDate`, etc.).
   - 67 entries in new `reader_allow_files:` blocks across 15
     concepts (migrators, sync helpers, the canonical writer's own
     scans, and cross-concept readers that touch the same prefix for
     unrelated purposes — e.g. `userBox.get('profile')` reads for
     subscription state vs. the narrowly-defined `user_full_name`
     concept).

3. **Contract test added**
   (`test/contracts/reader_manifest_exhaustiveness_test.dart`): spawns
   the gate as a subprocess and asserts exit 0. Will fail (loudly,
   with file:line + concept + prefix in stderr) the moment a new
   undeclared reader lands on `main`.

## Verification

```
$ dart run scripts/check_reader_manifest_complete.dart
check_reader_manifest_complete: phase-1 scanned 437 files against 30
forbidden patterns; phase-2 enforced 25 manifest-complete concepts.
OK: reader manifest check passed.

$ flutter test test/contracts/reader_manifest_exhaustiveness_test.dart
00:07 +1: All tests passed!

$ dart run scripts/validate_diagnose_doc.dart \
    docs/diagnoses/2026-05-17-oi-01-exhaustive-reader-gate-0a1e17.md
OK: ... passes diagnose-doc validation
```

## Open follow-ups

- OI-04 (agent reader-enumeration may have missed readers) is now
  partially closed — every missing reader the gate surfaced has been
  added or whitelisted. Any further misses surface as new gate
  failures on future commits.
- OI-03 (server-side reader drift) and OI-07 (AI snapshot contract)
  remain open — they need their own `docs/snapshot_contract.yaml`
  manifest before this gate's pattern can extend to Edge Function
  reads of AI snapshot keys.
