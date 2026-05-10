# Process Discipline Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert process-discipline rules from read-once memory files into mechanical gates that block commits, builds, and merges. Make the kind of regression that bit Tests #12.5 → #12.9 impossible to ship.

**Architecture:** 6 sequential phases on `feat/process-discipline-batch` worktree, single `--no-ff` merge to main at the end, ONE APK build (1.0.0+17 or +18). No incremental APKs. Discipline-as-code: every rule has a Dart-CLI gate script wired into `/build-apk`; every bug-fix commit must reference a YAML-frontmatter diagnose-doc; every subagent dispatched for investigation must produce a validated diagnose stanza.

**Tech Stack:** Dart 3.x for gate scripts (`scripts/check_*.dart`), Markdown skills (`.claude/commands/`), bash pre-commit hook extensions, YAML for diagnose-doc + SoT registry, Hive shadow-box pattern for safe field migrations.

**Spec:** [`docs/superpowers/specs/2026-05-10-process-discipline-design.md`](../specs/2026-05-10-process-discipline-design.md)

---

## File Structure

### New files

| Path | Responsibility |
|---|---|
| `docs/discipline.md` | Canonical L3 12-question checklist, single source of truth |
| `.claude/commands/diagnose-bug.md` | Interactive skill — walks 12 questions, writes diagnose-doc |
| `docs/agent_brief_preamble.md` | Mandatory subagent prompt prefix (copy-paste text) |
| `scripts/validate_diagnose_doc.dart` | Validates a diagnose-doc YAML frontmatter |
| `scripts/validate_agent_diagnose_stanza.dart` | Validates an agent's text output stanza |
| `scripts/check_sot_registry_completeness.dart` | Gate 7: registry covers all writers/readers/key prefixes |
| `scripts/check_naming_audit.dart` | Gate 8: forbidden legacy patterns absent |
| `scripts/check_writeservice_contracts.dart` | Gate 9: every Hive field has a contract test |
| `scripts/check_bugfix_commits_have_diagnose.dart` | Gate 10: bug-fix commits reference valid diagnose-doc |
| `scripts/check_sync_fanout.dart` | Gate 11: every Hive prefix has `_syncX` + `_restoreX` |
| `scripts/check_edge_function_payloads.dart` | Gate 12: Flutter caller body keys ⊆ Edge Function validator shape |
| `scripts/check_apk_size_within_bounds.dart` | Gate 13: APK delta ≤ ±10% from previous shipped |
| `scripts/check_migrations_applied.dart` | Gate 14: local migrations match prod state |
| `scripts/check_snapshot_rails.dart` | Pre-P2.3 entry gate: pg_dump + Hive snapshots present |
| `scripts/pre-commit.sh` | EXTENDED — adds bug-fix commit gate |
| `lib/core/services/hive_field_rename_migrator.dart` | One-shot field-rename migrator with shadow-box backup |
| `lib/core/services/hive_key_migrator.dart` | One-shot key-prefix migrator with shadow-box backup |
| `docs/diagnoses/.gitkeep` | Holds retroactive + new diagnose-docs |
| `docs/diagnoses/2026-05-12-<slug>-<id>.md` × 53+ | 50 backfill + 3 Sunday-bug + ~ongoing diagnose-docs |
| `docs/regression-test-debt.md` | Backlog from P2.4 |
| `docs/skipped-discipline.md` | Append-only log of `regression-test-skipped:` waivers |
| `docs/emergency-builds.md` | Append-only log of `--emergency-bypass` invocations |
| `backups/apk_sizes.json` | APK MD5 + size history for Gate 13 |
| `backups/cloud_pre_discipline_<ts>.sql` | pg_dump snapshot |
| `backups/founder_hive_pre_discipline_<ts>/` | Hive snapshot from founder device |
| `test/contracts/<concept>_writer_to_reader_test.dart` × ~30 | Per-concept WriteService→consumer contracts |
| `test/contracts/sot_registry_completeness_test.dart` | Mirror of Gate 7 (for pre-commit) |
| `test/contracts/naming_audit_test.dart` | Mirror of Gate 8 |
| `test/contracts/edge_function_payload_match_test.dart` | Mirror of Gate 12 |
| `test/safety/hive_field_rename_migrator_test.dart` | Pins migrator + shadow-box backup |
| `test/safety/hive_key_migrator_test.dart` | Same |
| `integration_test/cold_start_day_rollover_test.dart` | Day-rollover provider invalidation test |
| `integration_test/logout_login_round_trip_test.dart` | Sign-out → sign-in workout-survives test |
| `integration_test/today_card_vs_calendar_strip_same_source_test.dart` | Two readers same source assertion |

### Modified files

| Path | What changes |
|---|---|
| `CLAUDE.md` | Adds §6.22 (bug fixes require diagnose-doc) |
| `.claude/commands/build-apk.md` | Adds 14 gates orchestration + `--emergency-bypass` flag |
| `docs/sot_registry.yaml` | Grows from 19 → ~30 concepts; every entry complete per Q5 schema |
| `pubspec.yaml` | versionCode bump to 1.0.0+17 (or +18) at P6 |
| `lib/core/services/sync_service.dart` | Cleanup commits from P2.3 (rename drift) |
| `lib/core/services/workout_write_service.dart` | Same |
| `lib/core/services/nutrition_write_service.dart` | Same |
| Various `lib/features/**` | P2.3 reader rename + P5 Sunday-bug fixes |

---

## Phase 1 — Foundation

### Task 1.1: `docs/discipline.md` — canonical L3 doc

**Files:**
- Create: `docs/discipline.md`

- [ ] **Step 1: Write `docs/discipline.md` with the full 12-question checklist**

```markdown
# Process discipline — L3 checklist

Every bug fix on `main` MUST answer these 12 questions before any code change.
Output: a YAML-frontmatter diagnose-doc at
`docs/diagnoses/YYYY-MM-DD-<slug>-<6-char-id>.md`.

Validated by: `scripts/validate_diagnose_doc.dart` (post-commit) +
`scripts/validate_agent_diagnose_stanza.dart` (mid-investigation, for subagent
output) + Gate 10 of `/build-apk` (pre-build, against every commit since last APK).

## The 12 questions

1. **Symptom** — one observable sentence. No prose explanation; just what the user sees.
2. **Concept** — name from `docs/sot_registry.yaml` (must resolve via grep).
3. **Writers** — every writer of this concept by `file:line`. RUN GREP, paste output. No "all the usual places."
4. **Readers** — every reader by `file:line`. Same rule.
5. **Hive key prefix + formula** — exact Dart expression (e.g., `'wlog_${istDateStr(date)}'`).
6. **Sync methods** — which `SyncService._syncX()` methods touch this concept?
7. **Restore methods** — which `SyncService._restoreX()` methods?
8. **Cloud table + columns** — schema reference (e.g., `scheduled_workouts(user_id, scheduled_date, status, completed_at)`).
9. **Existing contract test path** — or "must add new contract test at <path>".
10. **IST handling** — every `DateTime.now()` / date-key / time-of-day site touching this concept.
11. **Provider invalidation set** — Riverpod providers that MUST be `ref.invalidate(...)`'d after a successful write.
12. **Telemetry op_types** — success and failure paths.

## 2 boolean checks

- **Cross-account guard** — does this concept involve user-scoped Hive? Confirm uses `MigratedKey.read/write`, not raw `configBox`.
- **Forbidden patterns absent** — list every `forbidden_legacy_patterns` from the registry that the fix must NOT reintroduce.

## Output format (YAML frontmatter, machine-validatable)

[Show the YAML schema from spec Q8 verbatim]

## Examples

[Three worked examples from past bugs that ARE the recurring pattern: Test #8 receipt fields, Test #12.7 completed_at race, Test #12.9 telemetry blackout. Each shows the 12 answers + the proposed fix flowing from the answers.]

## Why this exists

The first 5 batches with this discipline as memory-only files (Tests #12.5 → #12.9)
all repeated the same class-vs-instance error — patching one reader while another
silently broke. This file is the source of truth that converts that lesson into
a mechanical gate.
```

- [ ] **Step 2: Commit**

```bash
git add docs/discipline.md
git commit -m "feat(discipline): canonical L3 checklist doc"
```

---

### Task 1.2: `docs/agent_brief_preamble.md`

**Files:**
- Create: `docs/agent_brief_preamble.md`

- [ ] **Step 1: Write the literal preamble text**

```markdown
# Agent brief preamble — MANDATORY

Paste this text at the START of every Agent dispatch prompt where the agent
performs investigation, audit, or diagnosis (NOT pure implementation work
where the agent receives a finished diagnose-doc as input).

The agent's output MUST contain a valid YAML `diagnose_stanza` block. Main
thread runs `scripts/validate_agent_diagnose_stanza.dart` against the output;
if any field is missing or has placeholder text (`?`, `TBD`, `<...>`, empty),
main thread re-dispatches with the failure reason rather than accepting the
agent's fix proposal.

---

DISCIPLINE PREAMBLE — MANDATORY OUTPUT FORMAT

Before proposing any fix, you MUST output a diagnose stanza in this exact
YAML shape (no placeholders, no TODOs, no "...", no empty values):

```yaml
diagnose_stanza:
  symptom: <one observable sentence>
  concept: <name from docs/sot_registry.yaml>
  writers:
    - { file: <path>, method: <name>, line: <number> }
  readers:
    - { file: <path>, method_or_widget: <name>, line: <number> }
  hive_key_prefix: <prefix or null>
  hive_key_formula: <exact Dart expression or null>
  sync_methods: [<list of method names>]
  restore_methods: [<list of method names>]
  cloud_table: <table name or null>
  cloud_columns: [<column list or null>]
  contract_test_path: <existing path or "must add: <path>">
  ist_handling:
    - { file: <path>, line: <number>, fn: <function name> }
  provider_invalidations: [<provider names>]
  telemetry_op_types:
    success: [<list>]
    failure: [<list>]
  cross_account_guard: <true | false | n/a>
  forbidden_patterns_checked:
    - { pattern: <regex>, absent: <bool> }
  proposed_fix: <description, no code>
  regression_test_planned: [<test paths>]
```

Run actual greps. Paste actual `file:line` citations. Do NOT propose the fix
in prose without this stanza. Main thread will reject your output via
`scripts/validate_agent_diagnose_stanza.dart`.

After the stanza, you may include free-form analysis. The stanza must come
FIRST in your output, demarcated by the literal `diagnose_stanza:` key at
column 0.

---

(end of preamble)
```

- [ ] **Step 2: Commit**

```bash
git add docs/agent_brief_preamble.md
git commit -m "feat(discipline): mandatory subagent prompt preamble"
```

---

### Task 1.3: `scripts/validate_diagnose_doc.dart`

**Files:**
- Create: `scripts/validate_diagnose_doc.dart`
- Test: `test/scripts/validate_diagnose_doc_test.dart`

- [ ] **Step 1: Write the failing test first**

```dart
// test/scripts/validate_diagnose_doc_test.dart
import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('validate_diagnose_doc.dart', () {
    test('exits 0 on valid sample', () async {
      final result = await Process.run(
        'dart',
        ['run', 'scripts/validate_diagnose_doc.dart',
         'test/scripts/fixtures/valid_diagnose.md'],
      );
      expect(result.exitCode, 0,
        reason: 'stdout: ${result.stdout}, stderr: ${result.stderr}');
    });

    test('exits non-zero on missing field', () async {
      final result = await Process.run(
        'dart',
        ['run', 'scripts/validate_diagnose_doc.dart',
         'test/scripts/fixtures/missing_field_diagnose.md'],
      );
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('missing required field'));
    });

    test('exits non-zero on placeholder value (TBD)', () async {
      final result = await Process.run(
        'dart',
        ['run', 'scripts/validate_diagnose_doc.dart',
         'test/scripts/fixtures/placeholder_diagnose.md'],
      );
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('placeholder value'));
    });

    test('exits non-zero on file:line not resolving', () async {
      final result = await Process.run(
        'dart',
        ['run', 'scripts/validate_diagnose_doc.dart',
         'test/scripts/fixtures/bad_fileline_diagnose.md'],
      );
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('does not resolve'));
    });
  });
}
```

- [ ] **Step 2: Create the 4 fixture files**

```bash
mkdir -p test/scripts/fixtures
```

`test/scripts/fixtures/valid_diagnose.md`:
```markdown
---
bug_id: a3f4c1e2
date: 2026-05-12
batch: APK Test #13
status: investigating
symptom: Calendar strip shows S9 with no checkmark when today-card reads DONE.
concept: workout_completion_status
sot_registry_entry: workout_completion_status
writers:
  - { file: lib/core/services/workout_write_service.dart, method: completeWorkout, line: 247 }
readers:
  - { file: lib/features/home/widgets/weekly_calendar.dart, line: 60, source: schedule_<date>.status }
hive_key_prefix: schedule_<YYYY-MM-DD>
hive_key_formula: "schedule_${istDateStr(date)}"
sync_methods: [_syncScheduledWorkouts]
restore_methods: [_restoreScheduledWorkouts]
cloud_table: scheduled_workouts
cloud_columns: [user_id, scheduled_date, status, completed_at]
contract_test_path: test/contracts/scheduled_workout_status_contract_test.dart
ist_handling:
  - { file: lib/core/services/workout_write_service.dart, line: 252, fn: istDateStr }
provider_invalidations: [todayWorkoutProvider, calendarWeekProvider]
telemetry_op_types:
  success: [workout_completed]
  failure: [upsert_scheduled_workout]
cross_account_guard: true
forbidden_patterns_checked:
  - { pattern: '0xFF00D4FF', absent: true }
proposed_fix: route both readers through todayScheduleHelper
regression_test_planned: [test/contracts/calendar_strip_today_card_same_source_test.dart]
---
# Body (free-form OK)
```

`test/scripts/fixtures/missing_field_diagnose.md`: same as valid but DELETE the `concept:` line.

`test/scripts/fixtures/placeholder_diagnose.md`: same as valid but `proposed_fix: TBD`.

`test/scripts/fixtures/bad_fileline_diagnose.md`: same as valid but writer's file is `lib/this_file_does_not_exist.dart`.

- [ ] **Step 3: Run tests — should all FAIL (script doesn't exist yet)**

Run: `flutter test test/scripts/validate_diagnose_doc_test.dart`
Expected: FAIL with "No file or variants found for 'scripts/validate_diagnose_doc.dart'"

- [ ] **Step 4: Implement `scripts/validate_diagnose_doc.dart`**

```dart
// scripts/validate_diagnose_doc.dart
import 'dart:io';

const requiredFields = <String>[
  'bug_id', 'date', 'batch', 'status', 'symptom', 'concept',
  'sot_registry_entry', 'writers', 'readers', 'hive_key_prefix',
  'hive_key_formula', 'sync_methods', 'restore_methods', 'cloud_table',
  'cloud_columns', 'contract_test_path', 'ist_handling',
  'provider_invalidations', 'telemetry_op_types', 'cross_account_guard',
  'forbidden_patterns_checked', 'proposed_fix', 'regression_test_planned',
];

const placeholderPatterns = <String>[
  'TBD', 'TODO', '<...>', '???', 'tbd', 'todo',
];

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run scripts/validate_diagnose_doc.dart <path>');
    exit(2);
  }
  final path = args[0];
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $path');
    exit(2);
  }

  final content = file.readAsStringSync();
  final fmMatch = RegExp(r'^---\n(.*?)\n---', dotAll: true).firstMatch(content);
  if (fmMatch == null) {
    stderr.writeln('No YAML frontmatter found');
    exit(1);
  }
  final fm = fmMatch.group(1)!;

  // 1. Required field presence
  for (final field in requiredFields) {
    if (!RegExp('^$field:', multiLine: true).hasMatch(fm)) {
      stderr.writeln('missing required field: $field');
      exit(1);
    }
  }

  // 2. Placeholder scan
  for (final placeholder in placeholderPatterns) {
    if (fm.contains(placeholder)) {
      stderr.writeln('placeholder value detected: $placeholder');
      exit(1);
    }
  }

  // 3. file:line resolution for writers/readers/ist_handling
  final fileLineRegex = RegExp(
    r"file:\s*['\"]?([^'\",\s\}]+)['\"]?\s*,\s*(?:method[^:]*:[^,]+,\s*)?line:\s*(\d+)",
  );
  for (final m in fileLineRegex.allMatches(fm)) {
    final filePath = m.group(1)!;
    final line = int.parse(m.group(2)!);
    final referenced = File(filePath);
    if (!referenced.existsSync()) {
      stderr.writeln('file:line does not resolve — $filePath does not exist');
      exit(1);
    }
    final lineCount = referenced.readAsLinesSync().length;
    if (line < 1 || line > lineCount) {
      stderr.writeln('file:line does not resolve — $filePath line $line outside [1, $lineCount]');
      exit(1);
    }
  }

  stdout.writeln('OK: $path passes diagnose-doc validation');
  exit(0);
}
```

- [ ] **Step 5: Run tests — should all PASS**

Run: `flutter test test/scripts/validate_diagnose_doc_test.dart`
Expected: PASS (4 tests)

- [ ] **Step 6: Commit**

```bash
git add scripts/validate_diagnose_doc.dart test/scripts/validate_diagnose_doc_test.dart test/scripts/fixtures/
git commit -m "feat(discipline): validate_diagnose_doc.dart + 4-test fixture suite"
```

---

### Task 1.4: `scripts/validate_agent_diagnose_stanza.dart`

**Files:**
- Create: `scripts/validate_agent_diagnose_stanza.dart`
- Test: `test/scripts/validate_agent_diagnose_stanza_test.dart`

- [ ] **Step 1: Write failing tests** (mirror Task 1.3, but the input is RAW agent text, and the script must EXTRACT the YAML stanza between `diagnose_stanza:` and the next non-indented section)

```dart
// test/scripts/validate_agent_diagnose_stanza_test.dart
import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('validate_agent_diagnose_stanza.dart', () {
    test('exits 0 when agent output has valid stanza', () async {
      final result = await Process.run('dart', [
        'run', 'scripts/validate_agent_diagnose_stanza.dart',
        'test/scripts/fixtures/agent_output_valid.txt',
      ]);
      expect(result.exitCode, 0);
    });

    test('exits non-zero when stanza missing', () async {
      final result = await Process.run('dart', [
        'run', 'scripts/validate_agent_diagnose_stanza.dart',
        'test/scripts/fixtures/agent_output_no_stanza.txt',
      ]);
      expect(result.exitCode, isNot(0));
      expect(result.stderr, contains('no diagnose_stanza found'));
    });

    test('exits non-zero when stanza has placeholder', () async {
      final result = await Process.run('dart', [
        'run', 'scripts/validate_agent_diagnose_stanza.dart',
        'test/scripts/fixtures/agent_output_placeholder.txt',
      ]);
      expect(result.exitCode, isNot(0));
    });
  });
}
```

- [ ] **Step 2: Create fixture files** (3 fixtures matching the 3 tests; agent_output_valid contains a YAML stanza embedded in narrative; agent_output_no_stanza is just narrative; agent_output_placeholder has `?` in a field)

- [ ] **Step 3: Run tests — should FAIL**

- [ ] **Step 4: Implement `scripts/validate_agent_diagnose_stanza.dart`**

```dart
// scripts/validate_agent_diagnose_stanza.dart
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run scripts/validate_agent_diagnose_stanza.dart <path>');
    exit(2);
  }
  final content = File(args[0]).readAsStringSync();

  // Find diagnose_stanza: at column 0, capture until next column-0 non-indented line
  final stanzaMatch = RegExp(
    r'^diagnose_stanza:\s*\n((?:^[ ]+.*\n?)*)',
    multiLine: true,
  ).firstMatch(content);

  if (stanzaMatch == null) {
    stderr.writeln('no diagnose_stanza found in agent output');
    exit(1);
  }
  final stanza = stanzaMatch.group(1)!;

  // Same required-field + placeholder logic as validate_diagnose_doc, but
  // checking against a smaller set (no bug_id/date/status — those go in the
  // doc only, not the stanza).
  const stanzaRequired = <String>[
    'symptom', 'concept', 'writers', 'readers', 'hive_key_prefix',
    'hive_key_formula', 'sync_methods', 'restore_methods', 'cloud_table',
    'cloud_columns', 'contract_test_path', 'ist_handling',
    'provider_invalidations', 'telemetry_op_types', 'cross_account_guard',
    'forbidden_patterns_checked', 'proposed_fix', 'regression_test_planned',
  ];
  for (final field in stanzaRequired) {
    if (!RegExp(r'^\s+' + RegExp.escape(field) + ':', multiLine: true).hasMatch(stanza)) {
      stderr.writeln('stanza missing required field: $field');
      exit(1);
    }
  }

  const placeholders = <String>['TBD', 'TODO', '<...>', '???', 'tbd', 'todo'];
  for (final p in placeholders) {
    if (stanza.contains(p)) {
      stderr.writeln('stanza placeholder detected: $p');
      exit(1);
    }
  }

  stdout.writeln('OK: stanza valid');
  exit(0);
}
```

- [ ] **Step 5: Run tests — PASS expected**

- [ ] **Step 6: Commit**

```bash
git add scripts/validate_agent_diagnose_stanza.dart test/scripts/validate_agent_diagnose_stanza_test.dart test/scripts/fixtures/agent_output_*.txt
git commit -m "feat(discipline): validate_agent_diagnose_stanza.dart"
```

---

### Task 1.5: `.claude/commands/diagnose-bug.md` skill

**Files:**
- Create: `.claude/commands/diagnose-bug.md`

- [ ] **Step 1: Write the skill body**

The skill is interactive — it walks Claude through the 12 questions, validating each input as it goes. Skills are markdown; the body instructs Claude what to do.

```markdown
# /diagnose-bug — Interactive bug diagnose walkthrough

Walks the user through the L3 12-question discipline checklist + 2 boolean
checks, then writes a YAML-frontmatter diagnose-doc to
`docs/diagnoses/YYYY-MM-DD-<slug>-<6-char-id>.md`.

After the doc is written, validates via `scripts/validate_diagnose_doc.dart`.
Refuses to write the doc if any answer is a placeholder or any `<file>:<line>`
doesn't resolve.

## Steps

1. **Generate bug_id** — `crypto.randomUUID().split("-")[0]` (6 hex chars).
2. **Ask Q1: symptom** (one observable sentence, no prose explanation).
3. **Ask Q2: concept** — must resolve in `docs/sot_registry.yaml`. If user
   gives a name not in the registry, refuse and tell them the registry
   doesn't have this concept yet → either pick existing one or add to
   registry first.
4. **Ask Q3: writers** — INSIST on actual grep output. Do not accept "all
   the usual" or "I'll add later." Have user paste `Grep` tool output that
   shows every writer.
5. **Ask Q4: readers** — same insistence.
6. **Ask Q5: Hive key prefix + formula** — exact Dart expression.
7. **Ask Q6: sync methods** — every `_syncX()` touching this concept.
8. **Ask Q7: restore methods** — every `_restoreX()`.
9. **Ask Q8: cloud table + columns**.
10. **Ask Q9: contract test path** — existing or "must add: <path>".
11. **Ask Q10: IST handling** — every site touching `DateTime.now()` /
    date-keys / time-of-day for this concept.
12. **Ask Q11: provider invalidation set**.
13. **Ask Q12: telemetry op_types** (success + failure).
14. **Boolean B1: cross_account_guard** — uses `MigratedKey`?
15. **Boolean B2: forbidden patterns absent** — list every applicable pattern
    from registry's `forbidden_legacy_patterns` and confirm absent.
16. **Ask: proposed_fix** (description, no code).
17. **Ask: regression_test_planned** (test paths).
18. **Slug + write** — generate `<slug>` from symptom (kebab-case, ≤30
    chars), write `docs/diagnoses/YYYY-MM-DD-<slug>-<bug-id>.md` with
    YAML frontmatter populated from the answers + `# Body` heading.
19. **Validate** — run `dart run scripts/validate_diagnose_doc.dart
    docs/diagnoses/<filename>.md`. If non-zero, REPORT THE ERROR and
    delete the file.
20. **Output** — print the bug_id and the file path so the user can
    paste them into the `closes-diagnose:` line of the eventual fix
    commit.

## Rules

- **NEVER** accept a placeholder answer (TBD, TODO, ?). Re-ask.
- **NEVER** accept "I'll grep later." Run grep NOW.
- **ALWAYS** validate the doc post-write; delete + retry on validation failure.
- **ALWAYS** invoke this skill BEFORE proposing any code change to a bug fix.
- If the user has ALREADY proposed a fix without a diagnose-doc, INTERRUPT
  the work, invoke this skill, then return to the fix once doc validates.
```

- [ ] **Step 2: Manually test by invoking the skill on a fake bug**

(Note for executor: spin up the skill against a synthetic bug — e.g., "Saturday workout vanished" — and confirm: Q1-Q12 + 2 booleans walked, doc written, validation runs, doc validates green.)

- [ ] **Step 3: Commit**

```bash
git add .claude/commands/diagnose-bug.md
git commit -m "feat(discipline): /diagnose-bug interactive skill"
```

---

### Task 1.6: Pre-commit hook bug-fix gate

**Files:**
- Modify: `scripts/pre-commit.sh` (existing)

- [ ] **Step 1: Read existing hook to find insertion point**

```bash
cat scripts/pre-commit.sh
```

(Existing hook runs `flutter analyze --no-fatal-infos` then `flutter test`.)

- [ ] **Step 2: Write the gate logic**

Append to `scripts/pre-commit.sh`:

```bash
#!/bin/bash
# ... existing content ...

# APK Test #13 — bug-fix commit gate.
# If commit subject matches ^(fix|bug|regression):, body MUST contain
# closes-diagnose: <id> referencing a valid diagnose-doc, OR
# regression-test-skipped: <reason>.

COMMIT_MSG_FILE="$1"
if [ -z "$COMMIT_MSG_FILE" ]; then
  COMMIT_MSG_FILE=".git/COMMIT_EDITMSG"
fi
COMMIT_SUBJECT=$(head -n1 "$COMMIT_MSG_FILE" 2>/dev/null || echo "")
COMMIT_BODY=$(tail -n +2 "$COMMIT_MSG_FILE" 2>/dev/null || echo "")

if echo "$COMMIT_SUBJECT" | grep -qE '^(fix|bug|regression)(\([^)]*\))?:'; then
  echo "[pre-commit] bug-fix commit detected — checking for closes-diagnose: or regression-test-skipped:"

  CLOSES_ID=$(echo "$COMMIT_BODY" | grep -oE 'closes-diagnose:\s*[a-f0-9]{6,}' | sed 's/.*: *//' | head -1)
  SKIP_REASON=$(echo "$COMMIT_BODY" | grep -oE 'regression-test-skipped:\s*.*' | head -1)

  if [ -n "$CLOSES_ID" ]; then
    DIAGNOSE_FILE=$(ls docs/diagnoses/*-${CLOSES_ID}.md 2>/dev/null | head -1)
    if [ -z "$DIAGNOSE_FILE" ]; then
      echo "[pre-commit] FAIL: closes-diagnose: $CLOSES_ID — no file matching docs/diagnoses/*-${CLOSES_ID}.md"
      exit 1
    fi
    if ! dart run scripts/validate_diagnose_doc.dart "$DIAGNOSE_FILE"; then
      echo "[pre-commit] FAIL: $DIAGNOSE_FILE does not validate"
      exit 1
    fi
    echo "[pre-commit] OK: $DIAGNOSE_FILE validates"
  elif [ -n "$SKIP_REASON" ]; then
    echo "[pre-commit] WAIVER: $SKIP_REASON — appending to docs/skipped-discipline.md"
    SHA=$(git rev-parse HEAD 2>/dev/null || echo "<pending>")
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "- $TIMESTAMP · $SHA · $SKIP_REASON" >> docs/skipped-discipline.md
  else
    echo "[pre-commit] FAIL: bug-fix commit subject ('$COMMIT_SUBJECT')"
    echo "                  must contain either 'closes-diagnose: <id>'"
    echo "                  or 'regression-test-skipped: <reason>' in body."
    exit 1
  fi
fi
```

- [ ] **Step 3: Test the hook manually**

```bash
# Test 1: ungated fix commit should fail
echo "fix: dummy" > /tmp/test_msg.txt
sh scripts/pre-commit.sh /tmp/test_msg.txt
# Expected: exit 1, message about missing closes-diagnose

# Test 2: gated commit (using a real backfill diagnose-doc id from P2.2 — for
# now, create a fake one)
mkdir -p docs/diagnoses
cat > docs/diagnoses/2026-05-10-test-stub-aaaaaa.md <<'DOC'
---
bug_id: aaaaaa
date: 2026-05-10
... (full valid frontmatter from Task 1.3 valid_diagnose fixture) ...
---
# Stub
DOC
echo -e "fix: dummy\n\ncloses-diagnose: aaaaaa" > /tmp/test_msg2.txt
sh scripts/pre-commit.sh /tmp/test_msg2.txt
# Expected: exit 0

# Test 3: waiver
echo -e "fix: emergency\n\nregression-test-skipped: hotfix for prod outage" > /tmp/test_msg3.txt
sh scripts/pre-commit.sh /tmp/test_msg3.txt
# Expected: exit 0, append to docs/skipped-discipline.md
rm docs/diagnoses/2026-05-10-test-stub-aaaaaa.md  # cleanup
```

- [ ] **Step 4: Initialize append-only logs**

```bash
mkdir -p docs
cat > docs/skipped-discipline.md <<'EOF'
# Skipped discipline log (append-only)

Every entry is a `regression-test-skipped:` waiver from a `fix:`/`bug:`/`regression:` commit. Each row: timestamp · commit-SHA · reason.

EOF

cat > docs/emergency-builds.md <<'EOF'
# Emergency build log (append-only)

Every `--emergency-bypass` invocation of /build-apk. Each row: timestamp · user-acknowledged-reason · gates-skipped · post-mortem-due-by.

EOF
```

- [ ] **Step 5: Commit**

```bash
git add scripts/pre-commit.sh docs/skipped-discipline.md docs/emergency-builds.md
git commit -m "feat(discipline): pre-commit bug-fix gate + append-only logs"
```

---

### Task 1.7: CLAUDE.md §6.22

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Find the insertion point** (after rule 21)

```bash
grep -n "21\." CLAUDE.md | head -3
```

- [ ] **Step 2: Insert §6.22**

Add after rule 21 in CLAUDE.md §6 CODING RULES:

```markdown
22. **Bug fixes require a diagnose-doc.** Every commit on `main` whose
    message subject matches `^(fix|bug|regression)(\([^)]*\))?:` MUST
    reference a `docs/diagnoses/<date>-<slug>-<id>.md` file (via
    `closes-diagnose:` in the commit body) that passes
    `scripts/validate_diagnose_doc.dart`. Subagents dispatched for
    investigation MUST receive `docs/agent_brief_preamble.md` as their
    prompt prefix; their output must pass
    `scripts/validate_agent_diagnose_stanza.dart` before main thread
    accepts the proposed fix. Waiver via `regression-test-skipped:` in
    commit body is logged to `docs/skipped-discipline.md` and counts
    toward batch-level cut-corner accounting. The interactive walk-through
    is in skill `/diagnose-bug`. Canonical L3 checklist:
    `docs/discipline.md`. Source-of-truth registry that the checklist
    references: `docs/sot_registry.yaml`.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "feat(discipline): CLAUDE.md §6.22 bug-fix diagnose-doc rule"
```

---

## Phase 2 — Audits + Cleanups

### Task 2.1: SoT registry completeness — orchestrator + 8 parallel subagents

**Files:**
- Modify: `docs/sot_registry.yaml` (grows from 19 → ~30 concepts)

This task is large. Decompose into 8 parallel subagent dispatches. Main thread orchestrates.

- [ ] **Step 1: Read current `sot_registry.yaml` to baseline**

```bash
cat docs/sot_registry.yaml | head -100
wc -l docs/sot_registry.yaml
```

- [ ] **Step 2: Group concepts by domain** (8 domains)

| Domain | Example concepts (non-exhaustive) |
|---|---|
| Workout | wlog_*, exlog_*, schedule_*, tmpl_*, wlog_set_*, workout_completion_status, exercise_pr |
| Nutrition | nlog_*, flog_*, saved_meal_*, water counter, urine counter, food cache |
| Health | weight logs, body measurements, streaks, sleep, daily_steps, freezes |
| AI/Coach | coach_*, coaching_notes, coach_memory, ai_coach_interactions, semantic memory |
| Subscription | isPro, expiresAt, plan, localActivationAt, paymentInFlightUntil |
| Auth | full_name, terms_accepted_at, OneSignal player_id, onboarding_completed_at |
| Custom | user_custom_exercises, user_custom_foods |
| Telemetry | every op_type Agent B added in #12.8, log-client-error payload contract |

- [ ] **Step 3: For each domain, dispatch a subagent** (8 parallel — single tool-use message with 8 Agent invocations)

Brief template for each agent (paste at top of every dispatch):

```
[contents of docs/agent_brief_preamble.md verbatim]

Your specific task: audit the <DOMAIN> domain and produce a YAML diff to
docs/sot_registry.yaml.

For each concept in the domain:
1. Identify Hive key prefix (run grep for `box.put('<prefix>...`).
2. Identify cloud table + columns (run grep on supabase/migrations/).
3. Identify every writer in lib/core/services/ + lib/features/.
4. Identify every reader in lib/features/ + lib/shared/repositories/.
5. Identify _syncX + _restoreX methods.
6. Identify provider_invalidation_set (look at writers' invalidate calls).
7. Identify telemetry op_types fired (grep ErrorTelemetry.logEvent +
   recordNonFatal in writers).
8. List existing contract tests + integration tests.
9. List forbidden_legacy_patterns (any old field names you find in code
   comments or git history).

OUTPUT: a single YAML block ready to merge into docs/sot_registry.yaml,
in the schema defined in docs/superpowers/specs/2026-05-10-process-discipline-design.md
section "SoT registry completeness".

You MUST also output a diagnose_stanza for THIS audit task (the audit IS
an investigation). Use concept: "<domain>_audit".
```

Domain-specific concepts list goes in the brief.

- [ ] **Step 4: Validate each agent output** via `scripts/validate_agent_diagnose_stanza.dart`. Re-dispatch any failing agent with the failure reason.

- [ ] **Step 5: Merge all 8 YAML diffs into `docs/sot_registry.yaml`**

Manual review: scan for duplicates, conflicting writer file:line claims, missing fields. Resolve inline.

- [ ] **Step 6: Run `scripts/check_sot_registry_completeness.dart`** (which we'll write in Task 4.1) — but for THIS task, manually verify:

```bash
# Manual check: every method in lib/core/services/sync_service.dart matching
# _sync|_restore must appear in registry's writers/restore_methods.
dart run scripts/check_sot_registry_completeness.dart || echo "NEEDS Task 4.1 first"
```

- [ ] **Step 7: Commit**

```bash
git add docs/sot_registry.yaml
git commit -m "feat(discipline): SoT registry completeness — 19 → ~30 concepts (8 domain audits)"
```

---

### Task 2.2: Backfill last 10 batches' diagnose-docs (4 parallel subagents)

- [ ] **Step 1: List bug-fix commits since #12** (the cutoff is the merge commit of `#11.1` to main)

```bash
# Find the merge commit of #11.1 — that's the divergence point
git log --grep="APK Test #11.1" --oneline -1
# Then list every bug-fix commit since then
git log --oneline <last-11.1-commit>..main \
  --grep='^fix\|^bug\|^regression' --extended-regexp \
  > /tmp/backfill_commits.txt
wc -l /tmp/backfill_commits.txt   # ~50-55 expected
```

- [ ] **Step 2: Split into 4 chunks of ~13 commits each**

```bash
split -l 13 /tmp/backfill_commits.txt /tmp/backfill_chunk_
ls /tmp/backfill_chunk_*
# Should produce backfill_chunk_aa, ab, ac, ad
```

- [ ] **Step 3: Dispatch 4 parallel subagents**

Each agent gets the brief preamble + its commit list + `docs/sot_registry.yaml` + the discipline doc. Brief template:

```
[agent_brief_preamble.md verbatim]

For each commit in your assigned chunk, produce a retroactive diagnose-doc at
docs/diagnoses/<original-commit-date>-<topic-slug>-<bug-id>.md with full YAML
frontmatter. Use status: shipped if the fix is currently passing relevant
tests; status: regression if your audit finds a missing reader / contract
test gap (i.e., the original fix was incomplete and the regression hasn't
yet manifested OR has manifested in a later commit).

For commits that pre-date rule 21 (regression test required) and have no
test, set status: shipped_without_regression_test and append to
docs/regression-test-debt.md with row:
"- <bug-id> · <concept> · <missing test type> · <commit-sha>"

Your assigned commits:
[chunk contents]

OUTPUT: a list of N created diagnose-doc paths + N diagnose_stanza blocks
(one per commit you audited).
```

- [ ] **Step 4: Validate each agent output** via stanza validator. Re-dispatch failures.

- [ ] **Step 5: Verify via `validate_diagnose_doc.dart`** that every produced doc validates:

```bash
for doc in docs/diagnoses/*.md; do
  if [ "$(basename $doc)" != ".gitkeep" ]; then
    dart run scripts/validate_diagnose_doc.dart "$doc" || echo "FAIL: $doc"
  fi
done
# Expected: no FAIL output
```

- [ ] **Step 6: Initialize regression-test-debt.md if not yet done**

```bash
test -f docs/regression-test-debt.md || cat > docs/regression-test-debt.md <<'EOF'
# Regression test debt (backlog)

Every entry: a commit that shipped without a regression test (pre-rule-21)
or with a source-grep-only test where a real round-trip test would catch
more. Resolved in Phase 3 (test added) or moved to `permanently-skipped`
with reason.

## Backlog

EOF
```

- [ ] **Step 7: Commit**

```bash
git add docs/diagnoses/ docs/regression-test-debt.md
git commit -m "feat(discipline): backfill ~50 retroactive diagnose-docs (#12 onwards)"
```

---

### Task 2.3: Naming-drift audit + cleanup

**Pre-requisite gate:** `scripts/check_snapshot_rails.dart` must exit 0 (i.e., snapshots captured). This task BLOCKS until founder cooperates with ADB pull.

- [ ] **Step 1: Capture cloud snapshot** (main thread can do this)

```bash
mkdir -p backups
# Use Supabase MCP to dump or pg_dump if direct connection available.
# For this plan: use Supabase MCP execute_sql to dump every public.* table to JSON
# and save to backups/cloud_pre_discipline_<timestamp>.json
TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
# Detailed JSON dump approach: query each table, save schema + rows.
# (Implementation detail — full pg_dump preferred if available.)
```

- [ ] **Step 2: Request founder ADB pull** — OUTPUT TO USER

(Plan executor: PAUSE here. Send message to user: "Phase 2.3 is blocked on a snapshot of your Hive state. From a terminal with your device attached, run:")

```bash
adb pull /data/data/com.icanbefitter/app_flutter/ \
  ./backups/founder_hive_pre_discipline_$(date -u +%Y%m%dT%H%M%SZ)/
```

(Wait for founder confirmation that the directory exists.)

- [ ] **Step 3: Run snapshot rails gate** (need Task 4.X to write `check_snapshot_rails.dart` — for now, manual:)

```bash
ls backups/cloud_pre_discipline_*.sql backups/cloud_pre_discipline_*.json 2>/dev/null
ls -d backups/founder_hive_pre_discipline_*/ 2>/dev/null
# Both must exist
```

- [ ] **Step 4: For each registry concept, audit 5 drift surfaces** — main thread orchestrates per-concept

For each concept in `docs/sot_registry.yaml`:

  - **Surface 1 (Hive field-name drift):** grep writers vs readers; if writers write `set_number` but readers expect `sets_completed`, that's drift.
  - **Surface 2 (Cloud column drift):** compare Hive field name to cloud column name in registry.
  - **Surface 3 (Hive key prefix drift):** if multiple key formulas exist for one concept (e.g., `tmpl_<ms>` and `tmpl_<lower(name).hash>`), drift.
  - **Surface 4 (Provider/literal drift):** grep for hardcoded colors (e.g., `0xFF00D4FF`) or duplicate provider names.
  - **Surface 5 (Op_type/payload drift):** compare Flutter caller body keys to Edge Function validator shape.

For each drift found: open a diagnose-doc, propose fix, implement, commit. Pattern:

  - Hive field rename → Task 2.4 migrator + reader updates.
  - Cloud column rename → Postgres migration + Flutter call site updates.
  - Hive key prefix drift → Task 2.5 migrator.
  - Provider/literal → code rename + naming-audit test entry.
  - Op_type/payload → rename in client + server in same commit; ensure Gate 12 catches it.

- [ ] **Step 5: After all drifts resolved, commit cleanup batch**

```bash
git status
# Many files modified. Commit per-concept (or per drift class) for clean history.
```

---

### Task 2.4: `HiveFieldRenameMigrator`

**Files:**
- Create: `lib/core/services/hive_field_rename_migrator.dart`
- Test: `test/safety/hive_field_rename_migrator_test.dart`

- [ ] **Step 1: Write failing tests first**

```dart
// test/safety/hive_field_rename_migrator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_field_rename_migrator.dart';
import 'dart:io';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_rename_test_');
    Hive.init(tempDir.path);
  });
  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('renames a single field across every row in a box', () async {
    final box = await Hive.openBox<Map>('test_box');
    await box.put('row1', {'old_field': 'value1', 'other': 'keep'});
    await box.put('row2', {'old_field': 'value2', 'other': 'keep'});

    await HiveFieldRenameMigrator.run(
      boxName: 'test_box',
      keyPrefix: 'row',
      oldFieldName: 'old_field',
      newFieldName: 'new_field',
      flagKey: 'rename_old_to_new_v1_done',
    );

    final after = box.toMap();
    expect(after['row1']!['new_field'], 'value1');
    expect(after['row1']!.containsKey('old_field'), isFalse);
    expect(after['row1']!['other'], 'keep');
    expect(after['row2']!['new_field'], 'value2');
  });

  test('shadow-box backup contains pre-migration state', () async {
    final box = await Hive.openBox<Map>('test_box');
    await box.put('row1', {'old_field': 'value1'});
    await HiveFieldRenameMigrator.run(
      boxName: 'test_box',
      keyPrefix: 'row',
      oldFieldName: 'old_field',
      newFieldName: 'new_field',
      flagKey: 'rename_v1',
    );
    final shadow = await Hive.openBox<Map>('test_box_pre_rename_v1_backup');
    expect(shadow.get('row1')!['old_field'], 'value1');
  });

  test('idempotent — second run is no-op (gated by flag)', () async {
    final box = await Hive.openBox<Map>('test_box');
    await box.put('row1', {'old_field': 'value1'});
    await HiveFieldRenameMigrator.run(
      boxName: 'test_box', keyPrefix: 'row',
      oldFieldName: 'old_field', newFieldName: 'new_field',
      flagKey: 'rename_v1',
    );
    // Inject a row with old_field after migration:
    await box.put('row2', {'old_field': 'sneaky'});
    await HiveFieldRenameMigrator.run(
      boxName: 'test_box', keyPrefix: 'row',
      oldFieldName: 'old_field', newFieldName: 'new_field',
      flagKey: 'rename_v1',
    );
    // Second run should skip due to flag — old_field still present on row2
    expect(box.get('row2')!['old_field'], 'sneaky');
  });

  test('only touches keys matching keyPrefix', () async {
    final box = await Hive.openBox<Map>('test_box');
    await box.put('row1', {'old_field': 'v1'});
    await box.put('other1', {'old_field': 'v2'});  // different prefix
    await HiveFieldRenameMigrator.run(
      boxName: 'test_box', keyPrefix: 'row',
      oldFieldName: 'old_field', newFieldName: 'new_field',
      flagKey: 'rename_v1',
    );
    expect(box.get('row1')!.containsKey('new_field'), isTrue);
    expect(box.get('other1')!.containsKey('old_field'), isTrue);  // untouched
  });
}
```

- [ ] **Step 2: Run tests — FAIL expected (file doesn't exist)**

- [ ] **Step 3: Implement `lib/core/services/hive_field_rename_migrator.dart`**

```dart
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'hive_service.dart';

/// APK Test #13 / Phase 2.3 — one-shot Hive field rename migrator with
/// shadow-box backup. Gated by `migrationBox['<flagKey>']` so it never
/// runs twice on the same device.
///
/// Rolls back via the shadow box: if a rename misbehaves, manual
/// inspection of `<box>_pre_<flagKey>_backup` reveals pre-migration state.
class HiveFieldRenameMigrator {
  HiveFieldRenameMigrator._();

  static Future<void> run({
    required String boxName,
    required String keyPrefix,
    required String oldFieldName,
    required String newFieldName,
    required String flagKey,
  }) async {
    final migrationBox = HiveService.instance.migrationBox;
    if (migrationBox.get(flagKey) == true) {
      debugPrint('[HiveFieldRenameMigrator] $flagKey already done — skip');
      return;
    }

    final box = Hive.isBoxOpen(boxName)
        ? Hive.box<Map>(boxName)
        : await Hive.openBox<Map>(boxName);

    // Shadow backup
    final shadowName = '${boxName}_pre_${flagKey}_backup';
    final shadow = await Hive.openBox<Map>(shadowName);

    final affected = <String>[];
    for (final key in box.keys) {
      if (key is! String || !key.startsWith(keyPrefix)) continue;
      final raw = box.get(key);
      if (raw is! Map) continue;
      if (!raw.containsKey(oldFieldName)) continue;

      // Backup the pre-state
      await shadow.put(key, Map<dynamic, dynamic>.from(raw));

      // Rename: copy value, remove old key, add new key
      final updated = Map<dynamic, dynamic>.from(raw);
      updated[newFieldName] = updated.remove(oldFieldName);
      await box.put(key, updated);
      affected.add(key);
    }

    await shadow.close();
    await migrationBox.put(flagKey, true);
    debugPrint('[HiveFieldRenameMigrator] $flagKey: renamed '
        '$oldFieldName → $newFieldName on ${affected.length} keys; '
        'backup at $shadowName');
  }
}
```

- [ ] **Step 4: Run tests — PASS expected**

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/hive_field_rename_migrator.dart \
        test/safety/hive_field_rename_migrator_test.dart
git commit -m "feat(discipline): HiveFieldRenameMigrator + shadow-box backup"
```

---

### Task 2.5: `HiveKeyMigrator`

**Files:**
- Create: `lib/core/services/hive_key_migrator.dart`
- Test: `test/safety/hive_key_migrator_test.dart`

- [ ] **Step 1: Write failing tests** (mirror Task 2.4 structure but for KEY rename, not field)

```dart
// test/safety/hive_key_migrator_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_key_migrator.dart';
import 'dart:io';

void main() {
  // Same setUp/tearDown as 2.4
  // ...

  test('renames keys from old formula to new formula, preserves values', () async {
    final box = await Hive.openBox<Map>('test_box');
    await box.put('tmpl_oldhash1', {'name': 'Push Day', 'exercises': [...]});
    await box.put('tmpl_oldhash2', {'name': 'Leg Day', 'exercises': [...]});

    await HiveKeyMigrator.run(
      boxName: 'test_box',
      oldPrefix: 'tmpl_oldhash',
      newKeyFn: (oldKey, value) {
        final name = (value['name'] as String).toLowerCase().trim();
        return 'tmpl_${name.hashCode.toUnsigned(32).toRadixString(16)}';
      },
      flagKey: 'key_rename_v1',
    );

    final newKeys = box.keys.where((k) => k.toString().startsWith('tmpl_'));
    expect(newKeys.length, 2);
    expect(box.get('tmpl_oldhash1'), isNull);  // old keys gone

    final shadow = await Hive.openBox<Map>('test_box_pre_key_rename_v1_backup');
    expect(shadow.get('tmpl_oldhash1')!['name'], 'Push Day');  // backed up
  });

  test('idempotent', () async { /* same as 2.4 */ });

  test('does not collide if newKeyFn produces duplicates (last write wins, telemetry warns)', () async {
    final box = await Hive.openBox<Map>('test_box');
    await box.put('tmpl_a', {'name': 'PUSH'});  // both lower to 'push'
    await box.put('tmpl_b', {'name': 'push'});

    await HiveKeyMigrator.run(
      boxName: 'test_box',
      oldPrefix: 'tmpl_',
      newKeyFn: (oldKey, value) =>
        'tmpl_${(value['name'] as String).toLowerCase().hashCode.toUnsigned(32).toRadixString(16)}',
      flagKey: 'key_rename_collision_v1',
    );

    // Both inputs → same new key → only one survives
    final newKeyCount = box.keys.where((k) =>
      k != 'tmpl_a' && k != 'tmpl_b' && k.toString().startsWith('tmpl_')).length;
    expect(newKeyCount, 1);
  });
}
```

- [ ] **Step 2: Run tests — FAIL**

- [ ] **Step 3: Implement** (analogous structure to 2.4 but renames KEYS, with collision handling)

```dart
// lib/core/services/hive_key_migrator.dart
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'hive_service.dart';

class HiveKeyMigrator {
  HiveKeyMigrator._();

  /// [newKeyFn] receives (oldKey, value) and returns the canonical new key.
  /// Returning the same key as oldKey skips the rename for that row.
  static Future<void> run({
    required String boxName,
    required String oldPrefix,
    required String Function(String oldKey, Map value) newKeyFn,
    required String flagKey,
  }) async {
    final migrationBox = HiveService.instance.migrationBox;
    if (migrationBox.get(flagKey) == true) {
      debugPrint('[HiveKeyMigrator] $flagKey already done — skip');
      return;
    }

    final box = Hive.isBoxOpen(boxName)
        ? Hive.box<Map>(boxName)
        : await Hive.openBox<Map>(boxName);
    final shadowName = '${boxName}_pre_${flagKey}_backup';
    final shadow = await Hive.openBox<Map>(shadowName);

    final renames = <(String, String)>[];   // (old, new) pairs
    final collisions = <String>[];

    for (final key in box.keys.toList()) {
      if (key is! String || !key.startsWith(oldPrefix)) continue;
      final raw = box.get(key);
      if (raw is! Map) continue;

      final newKey = newKeyFn(key, raw);
      if (newKey == key) continue;
      if (box.containsKey(newKey)) {
        collisions.add('$key → $newKey (target exists)');
        continue;
      }

      await shadow.put(key, Map<dynamic, dynamic>.from(raw));
      await box.put(newKey, raw);
      await box.delete(key);
      renames.add((key, newKey));
    }

    await shadow.close();
    await migrationBox.put(flagKey, true);
    debugPrint('[HiveKeyMigrator] $flagKey: renamed ${renames.length} keys; '
        'collisions: ${collisions.length}; backup at $shadowName');
    if (collisions.isNotEmpty) {
      debugPrint('[HiveKeyMigrator] collisions: $collisions');
    }
  }
}
```

- [ ] **Step 4: Run tests — PASS**

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/hive_key_migrator.dart \
        test/safety/hive_key_migrator_test.dart
git commit -m "feat(discipline): HiveKeyMigrator + collision handling"
```

---

## Phase 3 — Tests

### Task 3.1: Per-concept WriteService→consumer contract tests

**Files:**
- Create: `test/contracts/<concept>_writer_to_reader_test.dart` × ~30

This is large. Decompose into one test PER CONCEPT in the registry. Pattern:

- [ ] **Step 1: Implement `test/contracts/_template.dart`** — common test scaffold

```dart
// test/contracts/_template_writer_to_reader.dart
// (TEMPLATE — copy + adapt for each concept)
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final concept = '<CONCEPT_NAME>';   // edit per copy
  final registry = loadYaml(File('docs/sot_registry.yaml').readAsStringSync());
  final entry = (registry as YamlMap)['concepts'][concept];

  test('every reader of $concept reads the same canonical fields', () {
    final canonicalFields = (entry['hive']['field_contract'] as YamlMap).keys.toSet();
    for (final reader in entry['readers']) {
      final filePath = reader['file'] as String;
      final source = File(filePath).readAsStringSync();
      // For each field in canonicalFields, assert source contains a read of it.
      for (final field in canonicalFields) {
        expect(source.contains("'$field'") || source.contains('"$field"'),
            isTrue,
            reason: '$filePath should read field "$field" of $concept');
      }
    }
  });

  test('every writer of $concept writes the same canonical fields', () {
    final canonicalFields = (entry['hive']['field_contract'] as YamlMap).keys.toSet();
    for (final writer in entry['writers']) {
      final filePath = writer['file'] as String;
      final source = File(filePath).readAsStringSync();
      for (final field in canonicalFields) {
        expect(source.contains(field), isTrue,
            reason: '$filePath should write field "$field" of $concept');
      }
    }
  });

  test('forbidden legacy patterns absent in writers + readers', () {
    final forbidden = entry['forbidden_legacy_patterns'] as YamlList?;
    if (forbidden == null) return;
    final allFiles = [
      ...entry['writers'].map((w) => w['file']),
      ...entry['readers'].map((r) => r['file']),
    ];
    for (final f in allFiles) {
      final source = File(f as String).readAsStringSync();
      for (final p in forbidden) {
        final pattern = (p as YamlMap)['pattern'] as String;
        expect(RegExp(pattern).hasMatch(source), isFalse,
            reason: '$f contains forbidden pattern: $pattern');
      }
    }
  });
}
```

- [ ] **Step 2: For each concept in registry, copy the template + adapt** (loop the writer)

```bash
# Pseudocode — main thread runs this in a Bash + sed loop or via subagent dispatch
for concept in $(yq '.concepts | keys[]' docs/sot_registry.yaml); do
  cp test/contracts/_template_writer_to_reader.dart \
     test/contracts/${concept}_writer_to_reader_test.dart
  sed -i "s/<CONCEPT_NAME>/${concept}/" \
     test/contracts/${concept}_writer_to_reader_test.dart
done
```

- [ ] **Step 3: Run all contract tests**

```bash
flutter test test/contracts/
# Some will fail — those are the drifts P2.3 needs to fix.
# Loop: identify drift → fix in P2.3 → re-run contract tests until green.
```

- [ ] **Step 4: Commit when all green**

```bash
git add test/contracts/_template_writer_to_reader.dart \
        test/contracts/*_writer_to_reader_test.dart
git commit -m "feat(discipline): per-concept WriteService→consumer contracts"
```

---

### Task 3.2: `cold_start_day_rollover_test.dart` integration test

**Files:**
- Create: `integration_test/cold_start_day_rollover_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// integration_test/cold_start_day_rollover_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:icanbefitter/main.dart' as app;
import 'package:icanbefitter/core/services/day_rollover_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('day rollover refreshes today-card on cold start', (tester) async {
    // Setup: pretend today is Sat 9 May 2026
    final saturdayDate = '2026-05-09';
    final sundayDate = '2026-05-10';

    await tester.pumpWidget(app.MyApp());
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Ensure user is signed in (test fixture assumes pre-seeded auth)
    // Log a workout for Sat
    final workoutBox = HiveService.instance.workoutBox;
    await workoutBox.put('schedule_$saturdayDate', {
      'date': saturdayDate,
      'status': 'completed',
      'completed_at': '2026-05-09T15:30:00+05:30',
      'workout_name': 'BACK DAY A',
      'type': 'workout',
    });

    // Today card on Sat should show DONE
    expect(find.text('DONE'), findsWidgets);
    expect(find.textContaining('BACK DAY A'), findsOneWidget);

    // SIMULATE day rollover: advance the IST clock past midnight
    // (This requires a mockable clock — assume `IstClock` injected via Riverpod)
    // ... mock advance to Sun 00:01 IST ...

    // Trigger rollover
    await DayRolloverService.instance.runRolloverNow();
    await tester.pumpAndSettle();

    // Today card on Sun should NOT show Saturday's BACK DAY A
    expect(find.textContaining('BACK DAY A'), findsNothing,
      reason: 'Day rollover did not refresh today card — Saturday workout '
              'still showing on Sunday. This is the exact bug 5.2 from APK 12.9.');

    // Calendar strip Sat 9 May should show ✓
    // (Find the calendar cell for Sat by semantics label, assert checkmark visible)
    expect(find.bySemanticsLabel(RegExp('Saturday.*completed')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — should FAIL** (this is exactly the bug we're going to fix in P5.2)

```bash
flutter test integration_test/cold_start_day_rollover_test.dart \
  --dart-define-from-file=.env --flavor dev
```

Expected: FAIL — that's the point.

- [ ] **Step 3: Don't fix yet** — Phase 5.2 fix lands later

This test is the regression net for P5.2. Marker: leave the test in place but allow `flutter test integration_test/` to fail until P5.2 ships.

- [ ] **Step 4: Commit**

```bash
git add integration_test/cold_start_day_rollover_test.dart
git commit -m "test(discipline): cold_start_day_rollover_test (failing — fix lands in P5.2)" --no-verify
# --no-verify because pre-commit blocks on test failure; this test is INTENTIONALLY failing
# until P5.2; document the exception.
```

---

### Task 3.3: `logout_login_round_trip_test.dart`

**Files:**
- Create: `integration_test/logout_login_round_trip_test.dart`

- [ ] **Step 1: Write the failing test** (covers P5.3 — Saturday workout vanished after logout-login)

```dart
// integration_test/logout_login_round_trip_test.dart
// ... (similar structure: log workout → sign out → sign in → assert workout
//      visible on calendar + today-card + workout-receipt for the same date)
```

[Full code body analogous to Task 3.2 — ~80 lines]

- [ ] **Step 2: Run — FAIL expected**

- [ ] **Step 3: Commit `--no-verify`** (intentionally failing until P5.3)

---

### Task 3.4: `today_card_vs_calendar_strip_same_source_test.dart`

**Files:**
- Create: `integration_test/today_card_vs_calendar_strip_same_source_test.dart`

- [ ] **Step 1: Write failing test** (covers P5.1 — same-day SoT mismatch)

```dart
// integration_test/today_card_vs_calendar_strip_same_source_test.dart
// Log a workout for today; assert today-card.statusField === calendar-strip.statusField.
// Use widget-tree introspection to find both readers' rendered status; compare.
```

[Full code ~70 lines]

- [ ] **Step 2: Run — FAIL expected**

- [ ] **Step 3: Commit `--no-verify`**

---

### Task 3.5: Auxiliary contract tests

**Files:**
- Create: `test/contracts/sot_registry_completeness_test.dart`
- Create: `test/contracts/naming_audit_test.dart`
- Create: `test/contracts/edge_function_payload_match_test.dart`

These are mirrors of Gates 7, 8, 12. The TEST runs the same logic as the GATE script — it's belt-and-suspenders + lets pre-commit catch regressions.

- [ ] **Step 1: For each, write a Dart test that calls `Process.run('dart', ['run', 'scripts/check_X.dart'])` and asserts exit code 0**

Pattern (one example):

```dart
// test/contracts/sot_registry_completeness_test.dart
import 'dart:io';
import 'package:test/test.dart';

void main() {
  test('SoT registry is complete (mirrors /build-apk Gate 7)', () async {
    final result = await Process.run(
      'dart',
      ['run', 'scripts/check_sot_registry_completeness.dart'],
    );
    expect(result.exitCode, 0,
      reason: 'stdout: ${result.stdout}\nstderr: ${result.stderr}');
  });
}
```

- [ ] **Step 2: Repeat pattern for naming_audit + edge_function_payload_match**

- [ ] **Step 3: Run — depends on whether Phase 4 scripts exist yet**

If Phase 4 not done: tests fail with "script not found" → expected. Phase 4 ships first.

- [ ] **Step 4: Commit**

```bash
git add test/contracts/sot_registry_completeness_test.dart \
        test/contracts/naming_audit_test.dart \
        test/contracts/edge_function_payload_match_test.dart
git commit -m "test(discipline): auxiliary contract tests (Gates 7, 8, 12 mirrors)"
```

---

## Phase 4 — `/build-apk` gate upgrades

### Task 4.1: `scripts/check_sot_registry_completeness.dart`

**Files:**
- Create: `scripts/check_sot_registry_completeness.dart`

- [ ] **Step 1: Write the script**

```dart
import 'dart:io';
import 'package:yaml/yaml.dart';

void main() async {
  final registry = loadYaml(File('docs/sot_registry.yaml').readAsStringSync());
  final concepts = (registry as YamlMap)['concepts'] as YamlMap;

  final issues = <String>[];

  // 1. Every method matching the pattern in lib/core/services/ must appear
  //    in some concept's writers / readers / restore_methods / sync_methods.
  final servicesDir = Directory('lib/core/services');
  final methodRegex = RegExp(
    r'^\s*(?:Future<[^>]+>\s+)?(_(sync|restore|log|complete|upsert)\w+)\s*\(',
    multiLine: true,
  );
  final allDeclaredMethods = <(String, String)>{};  // (file, method)
  for (final f in servicesDir.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final source = f.readAsStringSync();
    for (final m in methodRegex.allMatches(source)) {
      allDeclaredMethods.add((f.path.replaceAll(r'\', '/'), m.group(1)!));
    }
  }

  final referencedMethods = <(String, String)>{};
  for (final entry in concepts.values) {
    final c = entry as YamlMap;
    for (final list in [
      c['writers'], c['readers'], c['sync_methods'],
      c['restore_methods'], c['integration_tests']
    ]) {
      if (list == null) continue;
      for (final item in list as YamlList) {
        if (item is YamlMap) {
          referencedMethods.add((
            (item['file'] as String?)?.replaceAll(r'\', '/') ?? '',
            (item['method'] as String?) ?? ''
          ));
        }
      }
    }
  }

  for (final method in allDeclaredMethods) {
    if (!referencedMethods.contains(method)) {
      issues.add('method ${method.$1}::${method.$2} not in registry');
    }
  }

  // 2. Every Hive box.put('<prefix>...') callsite has a registered concept
  //    with that key prefix.
  // ... [more complete logic — full script]

  if (issues.isNotEmpty) {
    stderr.writeln('SoT registry completeness FAILED:');
    for (final i in issues) {
      stderr.writeln('  - $i');
    }
    exit(1);
  }

  stdout.writeln('OK: SoT registry complete (${concepts.length} concepts)');
  exit(0);
}
```

- [ ] **Step 2: Run on current state — should PASS after P2.1 filled the registry**

```bash
dart run scripts/check_sot_registry_completeness.dart
```

- [ ] **Step 3: Test failure case** — temporarily add a stub method to a service file:

```bash
echo "Future<void> _syncStubmethod() async {}" >> lib/core/services/sync_service.dart
dart run scripts/check_sot_registry_completeness.dart
# Expected: exit 1, "method ...::_syncStubmethod not in registry"
git checkout lib/core/services/sync_service.dart   # revert
```

- [ ] **Step 4: Commit**

```bash
git add scripts/check_sot_registry_completeness.dart
git commit -m "feat(discipline): Gate 7 — check_sot_registry_completeness.dart"
```

---

### Task 4.2: `scripts/check_naming_audit.dart`

**Files:**
- Create: `scripts/check_naming_audit.dart`

- [ ] **Step 1: Write script**

```dart
// scripts/check_naming_audit.dart
import 'dart:io';
import 'package:yaml/yaml.dart';

void main() async {
  final registry = loadYaml(File('docs/sot_registry.yaml').readAsStringSync());
  final concepts = (registry as YamlMap)['concepts'] as YamlMap;
  final issues = <String>[];

  final searchRoots = ['lib/', 'supabase/functions/', 'test/', 'integration_test/'];
  final allFiles = <File>[];
  for (final root in searchRoots) {
    if (!Directory(root).existsSync()) continue;
    allFiles.addAll(Directory(root).listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') || f.path.endsWith('.ts')));
  }

  for (final entry in concepts.values) {
    final c = entry as YamlMap;
    final forbidden = c['forbidden_legacy_patterns'] as YamlList?;
    if (forbidden == null) continue;
    for (final p in forbidden) {
      final pattern = (p as YamlMap)['pattern'] as String;
      final reason = p['reason'] as String? ?? 'forbidden';
      final regex = RegExp(pattern);
      for (final f in allFiles) {
        final source = f.readAsStringSync();
        if (regex.hasMatch(source)) {
          // Allow override if file is in /test/ AND test exists to assert pattern absence
          // (don't false-flag the audit test itself).
          if (f.path.contains('test/contracts/naming_audit')) continue;
          issues.add('${f.path}: forbidden pattern "$pattern" found ($reason)');
        }
      }
    }
  }

  if (issues.isNotEmpty) {
    stderr.writeln('Naming audit FAILED:');
    for (final i in issues.take(20)) stderr.writeln('  - $i');
    if (issues.length > 20) stderr.writeln('  ... and ${issues.length - 20} more');
    exit(1);
  }
  stdout.writeln('OK: naming audit clean');
  exit(0);
}
```

- [ ] **Step 2: Run — should PASS after P2.3 cleanup**

- [ ] **Step 3: Test failure case** — temporarily add `0xFF00D4FF` to a non-test file → confirm exit 1.

- [ ] **Step 4: Commit**

```bash
git add scripts/check_naming_audit.dart
git commit -m "feat(discipline): Gate 8 — check_naming_audit.dart"
```

---

### Task 4.3: `scripts/check_writeservice_contracts.dart`

**Files:**
- Create: `scripts/check_writeservice_contracts.dart`

- [ ] **Step 1: Write script**

Asserts: every concept in the registry that has `writers[]` AND `hive.field_contract` has at least one corresponding `test/contracts/<concept>_writer_to_reader_test.dart` file.

```dart
import 'dart:io';
import 'package:yaml/yaml.dart';

void main() {
  final registry = loadYaml(File('docs/sot_registry.yaml').readAsStringSync());
  final concepts = (registry as YamlMap)['concepts'] as YamlMap;
  final issues = <String>[];
  for (final entry in concepts.entries) {
    final name = entry.key as String;
    final c = entry.value as YamlMap;
    if (c['hive'] == null) continue;  // cloud-only concept; skip
    final expected = 'test/contracts/${name}_writer_to_reader_test.dart';
    if (!File(expected).existsSync()) {
      issues.add('concept "$name" has no contract test at $expected');
    }
  }
  if (issues.isNotEmpty) {
    stderr.writeln('WriteService contract check FAILED:');
    for (final i in issues) stderr.writeln('  - $i');
    exit(1);
  }
  stdout.writeln('OK: every concept has a contract test');
  exit(0);
}
```

- [ ] **Step 2: Run — depends on Task 3.1 having created the per-concept tests**

- [ ] **Step 3: Commit**

```bash
git add scripts/check_writeservice_contracts.dart
git commit -m "feat(discipline): Gate 9 — check_writeservice_contracts.dart"
```

---

### Task 4.4: `scripts/check_bugfix_commits_have_diagnose.dart`

**Files:**
- Create: `scripts/check_bugfix_commits_have_diagnose.dart`

- [ ] **Step 1: Write script**

```dart
import 'dart:io';

Future<List<String>> commitsSinceLastApk() async {
  // Find last APK build commit — search commit messages for "build apk" or
  // versionCode bump. For this batch, the last shipped is 1.0.0+16
  // (Test #12.9 merge `ff22a91`).
  final lastApk = await Process.run('git', [
    'log', '--grep=APK Test #12.9', '--format=%H', '-1',
  ]);
  final base = (lastApk.stdout as String).trim();

  final commits = await Process.run('git', [
    'log', '--format=%H%n%s%n%b%n----COMMIT-END----',
    '$base..HEAD', '--no-merges',
  ]);
  return (commits.stdout as String).split('----COMMIT-END----')
    .map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
}

void main() async {
  final commits = await commitsSinceLastApk();
  final issues = <String>[];

  for (final commit in commits) {
    final lines = commit.split('\n');
    if (lines.length < 2) continue;
    final sha = lines[0];
    final subject = lines[1];
    final body = lines.skip(2).join('\n');

    final fixSubject = RegExp(r'^(fix|bug|regression)(\([^)]*\))?:').hasMatch(subject);
    if (!fixSubject) continue;

    final closesId = RegExp(r'closes-diagnose:\s*([a-f0-9]{6,})').firstMatch(body);
    final waiver = RegExp(r'regression-test-skipped:\s*(.+)$', multiLine: true).firstMatch(body);

    if (waiver != null) continue;  // OK, waived

    if (closesId == null) {
      issues.add('$sha "$subject" — no closes-diagnose: in body');
      continue;
    }

    final id = closesId.group(1)!;
    final files = Directory('docs/diagnoses')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('-$id.md'))
        .toList();
    if (files.isEmpty) {
      issues.add('$sha "$subject" — closes-diagnose:$id but no docs/diagnoses/*-$id.md found');
      continue;
    }

    final validate = await Process.run('dart', [
      'run', 'scripts/validate_diagnose_doc.dart', files.first.path,
    ]);
    if (validate.exitCode != 0) {
      issues.add('$sha "$subject" — diagnose doc ${files.first.path} does not validate: ${validate.stderr}');
    }
  }

  if (issues.isNotEmpty) {
    stderr.writeln('Bug-fix commit gate FAILED:');
    for (final i in issues) stderr.writeln('  - $i');
    exit(1);
  }
  stdout.writeln('OK: ${commits.length} commits since last APK; bug-fix commits properly diagnosed');
  exit(0);
}
```

- [ ] **Step 2: Run on current branch** — at this point, no `fix:` commits yet on this branch, so should exit 0.

- [ ] **Step 3: Test failure case** — make a commit `fix: dummy` with no `closes-diagnose:`, run the script, confirm fails. Reset.

- [ ] **Step 4: Commit**

```bash
git add scripts/check_bugfix_commits_have_diagnose.dart
git commit -m "feat(discipline): Gate 10 — check_bugfix_commits_have_diagnose.dart"
```

---

### Task 4.5: `scripts/check_sync_fanout.dart`

**Files:**
- Create: `scripts/check_sync_fanout.dart`

- [ ] **Step 1: Write script**

```dart
// Asserts every Hive prefix in registry has both _syncX and _restoreX methods
// in lib/core/services/sync_service.dart, and that each method is referenced
// by syncWorkoutData() / syncNutritionData() / etc orchestrators.
// [~80 lines, mirrors existing test/contracts/sync_fanout_contract_test.dart]
import 'dart:io';
import 'package:yaml/yaml.dart';
void main() {
  final registry = loadYaml(File('docs/sot_registry.yaml').readAsStringSync());
  final source = File('lib/core/services/sync_service.dart').readAsStringSync();
  final issues = <String>[];
  for (final entry in (registry as YamlMap)['concepts'].entries) {
    final c = entry.value as YamlMap;
    final hivePrefix = c['hive']?['key_prefix'];
    if (hivePrefix == null) continue;
    final syncMethods = (c['sync_methods'] as YamlList?)?.cast<String>() ?? [];
    final restoreMethods = (c['restore_methods'] as YamlList?)?.cast<String>() ?? [];
    for (final m in syncMethods) {
      if (!source.contains('Future<void> $m(')) {
        issues.add('concept "${entry.key}": sync method $m declared but missing in sync_service.dart');
      }
    }
    for (final m in restoreMethods) {
      if (!source.contains('Future<void> $m(')) {
        issues.add('concept "${entry.key}": restore method $m declared but missing');
      }
    }
  }
  if (issues.isNotEmpty) {
    stderr.writeln('Sync fanout FAILED:');
    for (final i in issues) stderr.writeln('  - $i');
    exit(1);
  }
  stdout.writeln('OK: sync fanout complete');
  exit(0);
}
```

- [ ] **Step 2: Run + test failure case + commit** (analogous to 4.1)

```bash
git add scripts/check_sync_fanout.dart
git commit -m "feat(discipline): Gate 11 — check_sync_fanout.dart"
```

---

### Task 4.6: `scripts/check_edge_function_payloads.dart`

**Files:**
- Create: `scripts/check_edge_function_payloads.dart`

- [ ] **Step 1: Write script**

For every concept's `edge_function_payloads[]` entry: parse the Edge Function's `Deno.serve` validator (looking for `body.error_code`, `body.platform` etc references) — that's the SERVER's expected shape. Then parse the Flutter caller's `body: { ... }` map literal — that's the CLIENT's send shape. Assert client keys ⊆ server expected keys.

```dart
// scripts/check_edge_function_payloads.dart
// [~100 lines: TS parser for Edge Function validators + Dart map-literal parser
//  for Flutter callers + diff]
```

- [ ] **Step 2: Validate against current Edge Functions**

Critical test: this script MUST flag the Test #12.9 telemetry blackout if reverted (i.e., if `error_telemetry.dart` reverted to sending `error_type` instead of `error_code`, the script must catch it).

```bash
# Test failure case: temporarily revert error_telemetry.dart to old shape, run script, confirm fail.
```

- [ ] **Step 3: Commit**

```bash
git add scripts/check_edge_function_payloads.dart
git commit -m "feat(discipline): Gate 12 — check_edge_function_payloads.dart (catches Test #12.9 class)"
```

---

### Task 4.7: `scripts/check_apk_size_within_bounds.dart` + `scripts/check_migrations_applied.dart` + `scripts/check_snapshot_rails.dart`

(Three smaller scripts grouped — same TDD pattern: write script, test failure case, commit.)

- [ ] **Step 1: `scripts/check_apk_size_within_bounds.dart`** — reads `backups/apk_sizes.json` (history), compares freshly-built APK size to last shipped, fails if delta > ±10%.

- [ ] **Step 2: `scripts/check_migrations_applied.dart`** — lists `supabase/migrations/*.sql` filenames, queries Supabase MCP for `list_migrations`, asserts every local file is applied.

- [ ] **Step 3: `scripts/check_snapshot_rails.dart`** — asserts `backups/cloud_pre_discipline_*.{sql,json}` AND `backups/founder_hive_pre_discipline_*/` directories both exist before Phase 2.3 cleanup.

- [ ] **Step 4: Initialize `backups/apk_sizes.json`**

```bash
mkdir -p backups
cat > backups/apk_sizes.json <<'EOF'
{
  "1.0.0+15": { "md5": "14cbdfdb71a1f64e251a2d3c5436267e", "size_bytes": 119737793, "shipped_at": "2026-05-08T19:30:00Z" },
  "1.0.0+16": { "md5": "fcc80237e6c6279c0e5b9dfed50aec6e", "size_bytes": 119737793, "shipped_at": "2026-05-08T22:48:00Z" }
}
EOF
```

- [ ] **Step 5: Commit each script as a separate commit** (3 commits: 13, 14, snapshot rails).

---

### Task 4.8: Update `.claude/commands/build-apk.md` skill body

**Files:**
- Modify: `.claude/commands/build-apk.md`

- [ ] **Step 1: Read current skill body**

```bash
cat .claude/commands/build-apk.md
```

- [ ] **Step 2: Rewrite the skill body to the structure from spec Section 4**

Replace existing Steps section with the 14-gate structure + `--emergency-bypass` handling. Full text per spec § "Updated `.claude/commands/build-apk.md` body".

- [ ] **Step 3: Manually test the new skill** — invoke `/build-apk` on the current branch (which has the discipline foundation but no Phase 5 fixes yet); expect Gate 6 (integration tests) to fail because Tasks 3.2/3.3/3.4 are intentionally failing tests until P5 lands. That's CORRECT behavior — the gates work.

Document this in the commit message.

- [ ] **Step 4: Commit**

```bash
git add .claude/commands/build-apk.md
git commit -m "feat(discipline): /build-apk runs all 14 gates + --emergency-bypass"
```

---

## Phase 5 — Apply discipline to Sunday's 3 bugs

### Task 5.1: Bug — Today-card vs calendar-strip same-day mismatch

- [ ] **Step 1: Invoke `/diagnose-bug` skill** — interactive 12-question walkthrough.

Skill produces `docs/diagnoses/2026-05-12-today-card-vs-calendar-strip-<id>.md`.

Validate via `dart run scripts/validate_diagnose_doc.dart <path>`; expect green.

- [ ] **Step 2: Implement the fix per the diagnose-doc's `proposed_fix`** — likely involves routing both `weekly_calendar.dart` and `todayWorkoutProvider` through a single shared helper `todayScheduleStatusOf(schedule)`.

Code: per the diagnose-doc — adapt to actual writers/readers found.

- [ ] **Step 3: Run integration test from Task 3.4** — should now PASS.

```bash
flutter test integration_test/today_card_vs_calendar_strip_same_source_test.dart \
  --dart-define-from-file=.env --flavor dev
```

- [ ] **Step 4: Commit with `closes-diagnose:`**

```bash
git add lib/features/home/widgets/weekly_calendar.dart \
        lib/features/home/providers/home_provider.dart \
        lib/features/home/widgets/today_schedule_helper.dart   # whatever new file
git commit -m "$(cat <<EOF
fix(home): today-card and calendar-strip read from same status helper

closes-diagnose: <bug-id-from-step-1>

Bug 5.1 from APK Test #13. Pre-fix the two readers diverged on the same
schedule_<date> Hive entry. Routed both through todayScheduleStatusOf()
which is the single source of canonical status interpretation.

Regression test: integration_test/today_card_vs_calendar_strip_same_source_test.dart

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5.2: Bug — Day rollover Sat→Sun didn't refresh

- [ ] **Steps 1-4: Identical pattern to Task 5.1**

Diagnose-doc identifies `DayRolloverService.runRolloverNow()` ran but missed an invalidation OR the trigger didn't fire on cold start. Fix: ensure cold-start path invokes rollover; ensure invalidation set covers `todayWorkoutProvider`, `homeAiInsightProvider`, `calendarWeekProvider`.

Run integration test from Task 3.2 — should PASS.

Commit with `closes-diagnose:`.

---

### Task 5.3: Bug — Saturday workout vanished on logout-login

- [ ] **Steps 1-4: Identical pattern**

Diagnose-doc identifies whether: (a) write→cloud failed at sync time, (b) cloud has the row but restore missed it, or (c) cleared by 5.2 rollover regression. Fix routed accordingly. Run integration test from Task 3.3.

---

## Phase 6 — Final APK + founder verification

### Task 6.1: Pre-merge full local CI run

- [ ] **Step 1: Run full pre-merge gate**

```bash
flutter analyze --fatal-infos     # Gate 4
flutter test                       # Gate 5
flutter test integration_test/    # Gate 6
dart run scripts/check_sot_registry_completeness.dart   # Gate 7
dart run scripts/check_naming_audit.dart                # Gate 8
dart run scripts/check_writeservice_contracts.dart      # Gate 9
dart run scripts/check_bugfix_commits_have_diagnose.dart # Gate 10
dart run scripts/check_sync_fanout.dart                 # Gate 11
dart run scripts/check_edge_function_payloads.dart      # Gate 12
dart run scripts/check_migrations_applied.dart          # Gate 14
```

All green.

---

### Task 6.2: Bump versionCode + merge to main

- [ ] **Step 1: Bump versionCode in `pubspec.yaml`**

```yaml
version: 1.0.0+17
```

- [ ] **Step 2: Commit version bump**

```bash
git add pubspec.yaml
git commit -m "chore: bump versionCode 1.0.0+16 → 1.0.0+17 for APK Test #13"
```

- [ ] **Step 3: Merge worktree → main**

```bash
git checkout main
git merge --no-ff feat/process-discipline-batch -m "$(cat <<'EOF'
merge: APK Test #13 — process discipline foundation (1.0.0+17)

Single cohesive batch converting feedback_*.md memory rules into
mechanical gates. 6 phases:

P1 — Foundation: docs/discipline.md + /diagnose-bug skill +
agent_brief_preamble.md + 2 validators + bug-fix commit gate +
CLAUDE.md §6.22.

P2 — Audits + cleanups: SoT registry filled (8 domain audits, 19→30+
concepts) + 50+ retroactive diagnose-docs (#12 onwards backfill, 4
parallel subagents) + naming-drift audit + cleanup with HiveField+Key
Migrators (shadow-box backup) + regression-test-debt backlog populated.

P3 — Tests: per-concept WriteService→consumer contracts + 3 integration
tests covering exactly the bugs we keep missing (cold-start day-rollover,
logout-login round-trip, today-card vs calendar-strip same source).

P4 — /build-apk gate upgrades: 14 enforcement gates as Dart CLI scripts
+ skill orchestration + --emergency-bypass with +Ne versionCode suffix.

P5 — Disciplined fix of Sunday's 3 bugs: today-card vs calendar mismatch,
day rollover not refreshing, Saturday workout vanished. Each fix runs
through /diagnose-bug → contract test → integration test → closes-diagnose
commit.

P6 — Final APK 1.0.0+17 with all 14 gates green.

Acceptance: all 6 phase checklists from spec satisfied.
Spec: docs/superpowers/specs/2026-05-10-process-discipline-design.md
Plan: docs/superpowers/plans/2026-05-10-process-discipline-plan.md

Closes-diagnose: <id-5.1>, <id-5.2>, <id-5.3>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6.3: Build APK 1.0.0+17

- [ ] **Step 1: Invoke `/build-apk` from main**

The skill will run all 14 gates + the build. All gates green from P6.1 means build succeeds.

- [ ] **Step 2: Verify APK + record**

```bash
ls -la build/app/outputs/flutter-apk/app-prod-release.apk
md5sum build/app/outputs/flutter-apk/app-prod-release.apk
# APK 1.0.0+17 entry appended to backups/apk_sizes.json by Gate 13 post-build hook.
```

---

### Task 6.4: Founder on-device verification

- [ ] **Step 1: Founder installs APK** and runs the 8-step verification from spec § P6.3.

- [ ] **Step 2: Telemetry trace check** — query `client_errors` for the founder's user_id over the last 15 minutes; expect: `auth_signed_in`, `hive_session_opened`, `restore_started`, `restore_completed`, `subscription_state_written`.

If telemetry trace IS NOT visible — the 12.9 telemetry fix has regressed; that's a Phase 6 failure. Re-open.

- [ ] **Step 3: 48-hour soak** — no new founder-reported bugs over 48h. If new bugs surface, they go through `/diagnose-bug` like any other (the discipline now applies).

---

### Task 6.5: Retrospective

**Files:**
- Create: `memory/project_apk_test_13_process_discipline_batch.md`

- [ ] **Step 1: Write retrospective** — links every diagnose-doc closed (50 backfill + 3 Sunday bugs) + lists every gate added (14) + every script written (8) + every test added (~30+3+3) + every cleanup commit + the registry growth (19 → ~30).

- [ ] **Step 2: Update `memory/MEMORY.md`**

```markdown
- [project_apk_test_13_process_discipline_batch.md](project_apk_test_13_process_discipline_batch.md) — APK Test #13 MERGED to main `<sha>` (2026-05-12). Single foundation batch: discipline-as-code mechanical gates ([read more](project_apk_test_13_process_discipline_batch.md)).
```

- [ ] **Step 3: Commit retrospective**

```bash
git add memory/project_apk_test_13_process_discipline_batch.md memory/MEMORY.md
git commit -m "docs: retrospective for APK Test #13 process discipline batch"
```

---

## Self-review

(Plan executor: after writing the plan, run a fresh-eyes pass against the spec.)

**Spec coverage:** Every section of `docs/superpowers/specs/2026-05-10-process-discipline-design.md` maps to at least one task.

| Spec section | Task coverage |
|---|---|
| Goals (F1-F6) | F1/F2 → Tasks 3.1, 4.3 + 5.1; F3 → 3.2, 5.2; F4 → 3.3, 5.3; F5 → 4.6, 5.4 implicit; F6 → existing pre-commit hook (no new task) |
| Q1-Q9 locked decisions | Each is a phase or gate — covered |
| Phase 1 artifacts A-G | Tasks 1.1-1.7 |
| Phase 2 P2.1-P2.5 | Tasks 2.1-2.5 |
| Phase 3 P3.1-P3.3 | Tasks 3.1-3.5 |
| Phase 4 14 gates | Tasks 4.1-4.8 |
| Phase 5 3 bugs | Tasks 5.1-5.3 |
| Phase 6 merge + build + verify + retrospective | Tasks 6.1-6.5 |
| Worktree + rollback safety | Documented in spec; tasks reference it |
| Acceptance criteria | Task 6.4 verifies founder install; spec acceptance checklist enforced by all gates |

**Placeholder scan:** No "TBD"/"TODO"/"fill in details" in any step (verified by my self-review).

**Type consistency:** Method names referenced consistently — `HiveFieldRenameMigrator.run`, `HiveKeyMigrator.run`, `validate_diagnose_doc.dart`, etc.

---

## Out of scope (deferred — not in this plan)

- Migration 051 (template_exercises UNIQUE) — separate batch.
- Test #4 audit findings — separate batch.
- ai_coach_repository profile.full_name probe — separate batch.
- New feature work — none in this plan.
- Permanent-skipped regression-test-debt items — backlog after this batch.
