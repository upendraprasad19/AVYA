---
reviewed_at: 2026-11-04T13:10:00+05:30
branch: ci-shard-time-fix
staged_against: 1681e0ca
blast_radius: platform
reviewer: context-blind adversarial B-pass (fresh Sonnet, self-initiated, section 4.3)
lens_set: [blast_radius_mismatch, guard_without_its_mirror, writer_reader_drift]
findings_count: 2
verdict: accepted
verdict_note: 2 P2 findings, both fixed in this batch and re-verified; no P0 or P1
---

# Code Review (B-pass) - ci-shard-time-fix (OI-461)

Change: `timeout-minutes` of the unit-test shards 20 -> 30 in `.github/workflows/test.yml`, the pin in
`test/contracts/ci_unit_test_matrix_shape_test.dart`, and the OI-461 entry moved to `closed_issues.md`.

## Finding 1 - P2 - guard_without_its_mirror
- **file:line:** test/contracts/ci_unit_test_matrix_shape_test.dart:203
- **claim:** the pin `timeout-minutes:\s*30` has no end anchor, so it also matches 300 or 301.
- **verification:** reviewer read the regex; I mutated the workflow to 300 with the old pin in mind and added the anchor.
- **status:** fixed. The pin is now `timeout-minutes:\s*30\b`. Mutated to 20: 1 test red. Mutated to 300: 1 test red. Both mutations confirmed applied by a `grep -c` before the run; the restore was confirmed after.

## Finding 2 - P2 - writer_reader_drift (prose)
- **file:line:** docs/audit/closed_issues.md (OI-461 "Done when" line)
- **claim:** it still cites `test.yml` lines 80 to 113 and line 121, which no longer match the file.
- **status:** fixed. A note records that those numbers are as of filing and the limit is now at line 128.

## Checks that came back clean
YAML validity and indentation of the edited block, only the matrix job changed, no other job timeout touched,
no other test greps the replaced comment text, exactly one `## OI-461` header across the board files, the
commit body carries `closes-oi: OI-461` once as a trailer and no other phrase that could trip the citation gate,
and no other mirror of the 20-minute shard budget in scripts/, .claude/ or docs/architecture.

## Founder triage notes
none (self-initiated, no code under lib/).

## Tuning entry
- **2026-11-04** - blast-radius platform - 2 findings; 0 false_alarm; tuning: none (a pin regex should be end-anchored, already covered by the compound-boolean/pin mutation memories).
