# /diagnose-bug — Interactive bug diagnose walkthrough

Walks the user through the L3 12-question discipline checklist + 2 boolean
checks (defined in `docs/discipline.md`), then writes a YAML-frontmatter
diagnose-doc to `docs/diagnoses/YYYY-MM-DD-<slug>-<6-char-id>.md`.

After the doc is written, validates via
`dart run scripts/validate_diagnose_doc.dart <path>`. Refuses to commit the
doc if validation fails.

## When to invoke

Before proposing ANY code change to a bug fix. Per CLAUDE.md §6 rule 22, every
commit on `main` whose message subject matches `^(fix|bug|regression):`
MUST reference a valid diagnose-doc via `closes-diagnose: <bug-id>`.

If you have already proposed a fix without a diagnose-doc, INTERRUPT the
work, invoke this skill, then return to the fix once the doc validates.

## Walkthrough

1. **Generate bug_id** — 6 hex chars (e.g., first 6 chars of a random UUID).
   Re-roll if a file at `docs/diagnoses/*-<id>.md` already exists.

2. **Q1 — Symptom**: "What is the observable symptom? One sentence,
   what the user sees."
   - Reject prose explanations. Reject internal reasoning ("I think the
     bug is..."). Demand observable behavior.
   - Example pass: "Calendar strip shows S9 with no checkmark when today-
     card reads DONE."
   - Example fail: "There's a sync issue with Saturday's workout."
   - Re-ask if answer is vague or contains explanations.

3. **Q2 — Concept**: "Which concept in `docs/sot_registry.yaml` does
   this affect?"
   - Run Grep to list concept keys from the registry.
   - If user names a concept not in the registry, REFUSE: "That concept
     isn't registered. Either name an existing one, or add it to
     sot_registry.yaml first (separate task)."
   - Re-ask if user gives a made-up concept name.

4. **Q3 — Writers**: "Run grep for every writer of this concept. Paste
   actual file:line output."
   - INSIST on running the Grep tool live. Do NOT accept "all the usual
     places" or "I'll check later."
   - Grep the codebase for variable names / method names / keys related
     to the concept.
   - For each result, capture in format: `{ file: <path>, line: <num>, method: <name> }`.
   - Keep grepping until the user confirms "that's all the writers."
   - Re-ask if user provides vague or incomplete output.

5. **Q4 — Readers**: Same insistence. Run Grep, paste output, capture
   structured data.

6. **Q5 — Hive key prefix + formula**: "What's the exact Dart expression
   that produces the Hive key for this concept?"
   - If concept is cloud-only (no Hive), accept `null`.
   - Example: `'wlog_${istDateStr(date)}'`.
   - Copy the literal expression from the writer code.
   - Re-ask if answer is incomplete or vague (e.g., "some timestamp").

7. **Q6 — Sync methods**: "Which `_syncX()` methods in
   `lib/core/services/sync_service.dart` touch this concept?"
   - Run Grep `lib/core/services/sync_service.dart` for `Future<void> _sync`.
   - List by method name (e.g., `_syncWorkoutLogs`, `_syncExerciseLogs`).
   - Re-ask if user skips running grep.

8. **Q7 — Restore methods**: Same for `_restoreX` methods in
   `sync_service.dart`.

9. **Q8 — Cloud table + columns**: "If this concept is synced to Supabase,
   which table and columns?"
   - Example: `table: workout_logs, columns: [id, user_id, date, completed_at]`.
   - If cloud-only, list the table. If Hive-only, accept `null`.
   - Run Grep `supabase/migrations/` or `docs/reference/database-schema.md`
     if unsure.
   - Re-ask if vague.

10. **Q9 — Existing contract test**: "Path to the existing contract test
    that pins writer ↔ reader agreement."
    - If no test exists, prompt: "Path to the NEW contract test you'll add
      in this PR" (e.g., `test/contracts/my_concept_contract_test.dart`).
    - Re-ask if user skips this.

11. **Q10 — IST handling**: "Every site touching DateTime.now() / date-keys /
    time-of-day for this concept."
    - Run Grep for sites using `DateTime.now()`, `istDateStr()`, `istNow()`.
    - Paste all results in format: `{ file: <path>, line: <num>, source: <snippet> }`.
    - Per feedback_ist_sweep_gap.md, expect to find 2–3 unexpected sites in
      first pass.
    - Re-ask if user says "I'll grep later."

12. **Q11 — Provider invalidation set**: "Which Riverpod providers must
    be `ref.invalidate(...)`'d after a successful write?"
    - Example: `[currentPlanProvider, workoutStatsProvider, streakProvider]`.
    - Run Grep for `ref.invalidate` callsites that touch this concept's
      write paths.
    - Re-ask if empty or incomplete.

13. **Q12 — Telemetry op_types**: "Success + failure paths for telemetry."
    - Example: `op_type_success: workout_log_created, op_type_failure: workout_log_save_failed`.
    - Check `lib/core/services/telemetry_service.dart` for existing op_types.
    - Re-ask if incomplete.

14. **Boolean B1 — cross_account_guard**: "Does this concept use
    `MigratedKey.read/write`? (Required for user-scoped data per Test
    #11.1.)"
    - Answer: `true | false | n/a`.
    - Run Grep `lib/core/services/migrated_key.dart` if unsure.
    - Re-ask if blank.

15. **Boolean B2 — forbidden patterns absent**: "List every applicable
    `forbidden_legacy_patterns` from sot_registry.yaml concept entry.
    Confirm each absent."
    - Run Grep for each pattern (e.g., `.toString()`, `Hive.box('name')`).
    - Answer format: `pattern_1: absent, pattern_2: absent, ...`.
    - Re-ask if user says "I'll check later."

16. **Q13 — proposed_fix**: "Describe the fix in prose. NO CODE."
    - 2–4 sentences explaining what will change in writer(s) or reader(s).
    - Do NOT paste code. Do NOT say "I'll write it later."
    - Re-ask if vague or incomplete.

17. **Q14 — regression_test_planned**: "List paths of regression tests
    you'll add."
    - Example: `[test/contracts/my_concept_contract_test.dart]`.
    - If updating existing test, cite the path + what assertion changes.
    - Re-ask if empty.

18. **Generate slug + write the doc**:
    - Generate `<slug>` from symptom: kebab-case, ≤30 chars.
    - Example symptom: "Calendar strip shows S9 with no checkmark"
    - Example slug: "calendar-strip-mismatch"
    - Today's date: YYYY-MM-DD (current date from system).
    - Path: `docs/diagnoses/<date>-<slug>-<bug_id>.md`.
    - Write the file with YAML frontmatter below `---` + `# Body` heading + free-form notes.

## YAML frontmatter fields

```yaml
---
bug_id: <6-char hex>
date: <YYYY-MM-DD>
batch: <version code or test batch name, e.g. "APK Test #13">
status: open
symptom: |
  <Q1 answer>
concept: <Q2 answer>
sot_registry_entry: <concept name from sot_registry.yaml>
writers: |
  { file: <path>, line: <num>, method: <name> }
  { file: <path>, line: <num>, method: <name> }
readers: |
  { file: <path>, line: <num>, method: <name> }
  { file: <path>, line: <num>, method: <name> }
hive_key_prefix: <prefix string>
hive_key_formula: |
  <Q5 answer — literal Dart expression>
sync_methods: |
  - _syncX
  - _syncY
restore_methods: |
  - _restoreX
  - _restoreY
cloud_table: <table name or null>
cloud_columns: |
  - column_1
  - column_2
contract_test_path: <Q9 answer — path to test file>
ist_handling: |
  { file: <path>, line: <num>, source: <snippet> }
  { file: <path>, line: <num>, source: <snippet> }
provider_invalidations: |
  - provider1
  - provider2
telemetry_op_types:
  success: <op_type>
  failure: <op_type>
cross_account_guard: <true | false | n/a>
forbidden_patterns_checked: |
  pattern_1: absent
  pattern_2: absent
proposed_fix: |
  <Q13 answer — prose description>
regression_test_planned: |
  - <test path>
  - <test path>
---

# Body

<free-form notes, context, links, prior art>
```

19. **Validate**: Run `dart run scripts/validate_diagnose_doc.dart <path>`.
    - If exit 0: continue to step 20.
    - If exit non-zero: REPORT THE ERROR to user, DELETE the file, and
      re-ask the question that produced the failure.

20. **Output to user**:
    - The bug_id.
    - The diagnose-doc path.
    - The exact line to paste into the eventual fix commit's body:
      `closes-diagnose: <bug-id>`.

## Rules (MANDATORY)

- **NEVER** accept a placeholder answer (TBD, TODO, ?). Re-ask the question.
- **NEVER** accept "I'll grep later." Run Grep NOW (use the Grep tool).
- **NEVER** skip a question because "the bug is obvious" — the discipline
  fails when even one of the 12+2 is skipped (Tests 12.5 → 12.9 are proof).
- **ALWAYS** validate the doc post-write; delete + retry on validation failure.
- **ALWAYS** invoke this skill BEFORE proposing any code change to a fix.
- Per feedback_no_deferrals.md: every question must be answered in THIS
  session. Do NOT defer to a follow-up session.

## Example flow

```
User: `/diagnose-bug`

Claude:
> Generating bug_id: `a3f4c1`
> 
> **Q1 — Symptom?** (One sentence, observable behavior only.)

User: "Calendar strip shows S9 with no checkmark when today-card reads DONE."

Claude:
> Recorded: "Calendar strip shows S9 with no checkmark when today-card reads DONE."
> 
> **Q2 — Which concept in `docs/sot_registry.yaml`?**
> 
> (Running grep to list available concepts...)
> 
> Available concepts include:
> - workout_completion_status
> - workout_logs
> - exercise_logs
> - calendar_week_view
> - ...

User: "workout_completion_status"

Claude:
> Recorded.
> 
> **Q3 — Run grep for every writer.**
> 
> (Grepping codebase for writers of workout_completion_status...)

User: [pastes grep results showing 2 writers]

Claude:
> Recorded 2 writers: [structured list]
> 
> **Q4 — Run grep for every reader.**

[continues through Q14, enforcing live Grep on every question that requires it]

Claude (after Q14):
> Writing `docs/diagnoses/2026-05-12-calendar-strip-mismatch-a3f4c1.md`
> with YAML frontmatter...
> 
> Validating: `dart run scripts/validate_diagnose_doc.dart docs/diagnoses/2026-05-12-calendar-strip-mismatch-a3f4c1.md`
> 
> ✅ Validates.
> 
> **Diagnose complete.**
> - bug_id: `a3f4c1`
> - path: `docs/diagnoses/2026-05-12-calendar-strip-mismatch-a3f4c1.md`
> - Add to your fix commit body: `closes-diagnose: a3f4c1`
```

## Integration with fix commits

After the diagnose-doc validates, proceed with the fix. When you commit the
fix on the feature branch, the commit message MUST include:

```
closes-diagnose: <bug-id>
```

Example:

```
fix(workout-logs): calendar strip + today card IST mismatch

Calendar strip was keying by UTC date while today-card keyed by IST date,
causing S9 (a Saturday in IST) to show as hidden when logs existed.

closes-diagnose: a3f4c1
```

The pre-commit hook (`scripts/pre-commit.sh`) will verify that the bug_id
resolves to a valid diagnose-doc in `docs/diagnoses/` before allowing the
commit.

## References

- `docs/discipline.md` — L3 discipline full reference
- `docs/sot_registry.yaml` — machine-readable SoT concept index
- `scripts/validate_diagnose_doc.dart` — validation entry point
- `scripts/validate_diagnose_doc_lib.dart` — validation logic
- CLAUDE.md §6 rule 22 — non-negotiable rule for all commits
- `feedback_source_of_truth_audit.md` — why SoT discipline matters
