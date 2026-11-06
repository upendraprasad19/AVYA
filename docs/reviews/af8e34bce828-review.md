---
reviewed_at: 2026-11-04T22:30:00+05:30
staged_against: af8e34bce828
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 8
verdict: accepted
verdict_note: all 8 findings fixed or confirmed non-defect in this batch; reviewed staged hash 20d1c584b51e, fixes restaged as af8e34bce828
---

# Code Review — realtime-weight-off (af8e34bce828)

One context-blind Sonnet reviewer, read-only, on the staged diff (hash 20d1c584b51e). No P0/P1.

## Finding 1 — P2 — writer_reader_drift
- **file:line:** docs/sot_registry.yaml (_settleRestoreMarker line_range 2010-2027)
- **claim:** range not shifted; method now at sync_service.dart:1977.
- **verification:** grep -n "void _settleRestoreMarker" lib/core/services/sync_service.dart
- **status:** accepted — fixed (1977-1995)

## Finding 2 — P2 — writer_reader_drift
- **file:line:** docs/sot_registry.yaml (restoreFailureReason 2870-2872)
- **claim:** not shifted; method at 2823.
- **status:** accepted — fixed (2823-2825)

## Finding 3 — P3 — writer_reader_drift
- **file:line:** docs/sot_registry.yaml:1712 (runRolloverNow line: 133)
- **claim:** single-number citation not shifted; method at day_rollover_service.dart:120.
- **status:** accepted — fixed (120)

## Finding 4 — P2 — writer_reader_drift
- **file:line:** docs/sot_registry.yaml:4731 (weight_logs class_constraints)
- **claim:** prose still says a Realtime channel auto-updates Hive.
- **status:** accepted — fixed (states no channel, points to OI-279 item 8)

## Finding 5 — P3 — writer_reader_drift
- **file:line:** docs/reference/directory-structure.md:242
- **claim:** "7 part files" wrong; 9 part directives remain.
- **verification:** grep -c "^part 'sync/" lib/core/services/sync_service.dart  (9)
- **status:** accepted — fixed (9, and the two unlisted part files named)

## Finding 6 — P2 — guard_without_its_mirror
- **file:line:** test/contracts/no_client_realtime_subscription_test.dart (onDowngrade scan)
- **claim:** no positive control; regex missed ??= and named-argument wiring.
- **status:** accepted — fixed (extracted assignsOnDowngrade with fixtures, regex widened; a mutant that drops ??=/: reddens 1 test)

## Finding 7 — P3 — guard_without_its_mirror
- **file:line:** test/contracts/no_client_realtime_subscription_test.dart (stripCommentsAndStrings)
- **claim:** evaded by interpolation, raw string ending in backslash, triple quote with apostrophe, generic .stream<, RealtimeClient.
- **status:** accepted — fixed (stripper handles triple/raw/interpolation; patterns add RealtimeClient and .stream[<(]; mutants: interpolation off reddens 1, triple off reddens 2). Tear-off (f = client.channel; f('x')) is not detectable by a regex scan; the header says the guard is regex-grade.

## Finding 8 — P3 — process
- **claim:** no plan-review record yet; assetlinks.json is unstaged.
- **status:** accepted — not a code defect; the record lands as its own later commit (hash-cycle rule) and assetlinks ships as its own chore(web) commit.

## What I checked per lens
See the reviewer's report: all eight lenses ran; symbols grep clean outside historical docs; ranges for sync_service/day_rollover/subscription_service/completed_title_healer verified; fixture literals and four targeted test files green.

## Founder triage notes
Self-attested in this batch (platform tier, advisory).

## Tuning entry
- **2026-11-04** - blast-radius platform - 8 findings; 0 false_alarm; tuning: none (the registry line-range sub-check from 2026-11-01 caught 3 of the 8).
