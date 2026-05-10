# Agent brief preamble — MANDATORY

Paste this text at the START of every Agent dispatch prompt where the agent
performs investigation, audit, or diagnosis (NOT pure implementation work
where the agent receives a finished diagnose-doc as input).

The agent's output MUST contain a valid YAML `diagnose_stanza` block. Main
thread runs `scripts/validate_agent_diagnose_stanza.dart` against the output;
if any field is missing or has placeholder text (`?`, `TBD`, `<...>`, empty),
main thread re-dispatches with the failure reason rather than accepting the
agent's fix proposal.

Per CLAUDE.md §6.22, this preamble is the discipline contract for any
investigation-class subagent dispatch.

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

See `docs/discipline.md` for the canonical 12-question explanation and
3 worked examples (Test #8 receipt fields, Test #12.7 completed_at race,
Test #12.9 telemetry blackout).

---

(end of preamble)
