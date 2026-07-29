---
bug_id: de29b8
date: 2026-05-16
batch: audit-2026-05-16-E13
status: shipped-framework-only
symptom: >-
  Not a bug — the audit-2026-05-16 framework deliverable: 6 new gate scripts
  plus 6 new contract tests codifying discipline rules that until then existed
  only as prose. Carries a symptom line so the bug index has no blank entry.
regression_test: test/contracts/applied_migrations_parity_test.dart, test/contracts/type_consistency_test.dart, test/contracts/high_priority_op_types_parity_test.dart, test/contracts/migrated_key_contracts_test.dart, test/contracts/custom_exercise_writer_to_reader_test.dart, test/contracts/undo_stash_lifetime_test.dart
---

# Phase E.13 — Framework deliverables

Not a bug fix. This is the audit-batch's framework deliverable: 6 new
gate scripts + 6 new contract tests that codify discipline rules from
CLAUDE.md §15 + the audit findings. Filed as a diagnose-doc so the
discipline-history audit (`scripts/audit_discipline_history.dart`) has
a doc to anchor against if the framework commits ever land under
`fix:` subjects.

## Deliverables shipped

### Gate scripts (`scripts/`)

| Script | Purpose | Exit-0 state today |
|---|---|---|
| `check_naming_conventions.dart` | Riverpod naming, Edge Function entry-point, contracts/ test naming | PASS |
| `check_sot_registry_parity.dart` | Registry file:line + method presence + orphan-class warning | PASS (1 stale line_range warned, 5 orphan repos warned) |
| `check_writeservice_only.dart` | All `<box>.put|delete` outside allowed-writers list | PASS (17 known-violations allowlisted; remediation in E.5/E.6/E.7) |
| `check_mutation_invalidation_set.dart` | Mutation files invalidate CLAUDE.md §15 canonical provider set | PASS |
| `check_ai_tool_dispatcher_coverage.dart` | Every WRITE-kind tool has dispatcher case | PASS (17/17) |
| `audit_discipline_history.dart` | Every `fix:` commit since 2026-05-10 has diagnose-doc or waiver | PASS (64/64) |

### Contract tests (`test/contracts/`)

| Test | Pins |
|---|---|
| `applied_migrations_parity_test.dart` | Every `*.sql` file recorded in `backups/applied_migrations.json` |
| `type_consistency_test.dart` | 8 high-traffic cloud column types pinned via DDL grep |
| `high_priority_op_types_parity_test.dart` | Client ↔ server `HIGH_PRIORITY_OP_TYPES` set equality |
| `migrated_key_contracts_test.dart` | Every `MigratedKey.*` key in `userScopedKeys` or `_intentionallyShared` |
| `custom_exercise_writer_to_reader_test.dart` | Writer/reader field-name parity for `custom_exercise_<ms>` Hive key |
| `undo_stash_lifetime_test.dart` | `undo_<logKey>` 1-hour TTL + stash field set on `WorkoutWriteService.deleteLog` |

## Discovered violations (out of scope — documented for follow-up)

See `docs/audit/2026-05-16/e13-discovered-violations.md` for the full
list of 17 `check_writeservice_only` violations and 5 orphan repository
classes. All are slated for remediation in E.5 / E.6 / E.7 of the same
audit batch. Tests + scripts pass against current `main` by
allowlist; remove the allowlist entry as each remediation lands so the
script catches regressions.

## Verification log

```
$ flutter test test/contracts/applied_migrations_parity_test.dart \
    test/contracts/type_consistency_test.dart \
    test/contracts/high_priority_op_types_parity_test.dart \
    test/contracts/migrated_key_contracts_test.dart \
    test/contracts/custom_exercise_writer_to_reader_test.dart \
    test/contracts/undo_stash_lifetime_test.dart
00:03 +24: All tests passed!

$ dart run scripts/check_naming_conventions.dart           # PASS
$ dart run scripts/check_sot_registry_parity.dart          # PASS (with warns)
$ dart run scripts/check_writeservice_only.dart            # PASS
$ dart run scripts/check_mutation_invalidation_set.dart    # PASS
$ dart run scripts/check_ai_tool_dispatcher_coverage.dart  # PASS (17/17)
$ dart run scripts/audit_discipline_history.dart           # PASS (64/64)
```

## Next steps

1. Wire each new script into `/build-apk` Gates 1-22 after the
   remediation tasks (E.5/E.6/E.7) land so the pipeline catches
   regressions from day 1 post-remediation.
2. Update `docs/sot_registry.yaml` line_ranges for sync_coach.dart
   (currently flagged as stale by `check_sot_registry_parity.dart`).
3. Add stub registry entries for the 5 read-only repository classes
   (`AiCoachRepository`, `ProgressPhotoRepository`,
   `ExerciseRepository`, `FoodRepository`, `SubmissionsRepository`)
   so the orphan-class warning goes quiet.
