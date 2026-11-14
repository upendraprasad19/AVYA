---
bug_id: 4e9515
date: 2026-05-15
batch: APK Test #15 parallel-agent batch (Agent A7)
status: shipped
symptom: Founder asked for a "debugging" skill earlier in the session; both `superpowers:debugging` and `debugging` returned `Unknown skill`. The project's `.claude/skills/` directory did not exist. Debugging methodology was tribal knowledge spread across CLAUDE.md §19, MEMORY.md feedback_* files, and project_apk_test_*.md retrospectives — not invocable as a single skill. Result: every batch since Test #6 has re-discovered the same writer/reader drift class because the methodology to catch it was undocumented as a skill.
concept: debugging_methodology
sot_registry_entry: n/a — process discipline, not data
writers:
  - { file: .claude/skills/debugging/SKILL.md, method_or_widget: skill_definition, line: 1 }
readers:
  - { file: .claude/skills/debugging/SKILL.md, method_or_widget: main_thread_or_subagent_via_Skill_tool, line: 1 }
hive_key_prefix: null
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: "n/a — process discipline addition; the SKILL.md file itself is the contract, and § 5 self-evolution rule is enforced by the next debugging session's output contract (§ 4)"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: []
proposed_fix: Create `.claude/skills/debugging/SKILL.md` codifying the 6-step methodology (wait → writer/reader map → recall prior fixes → live verification → propose-then-approve → fix-with-doc/test/memory). Seed bug class catalog with 10 recurring classes from Tests #6 through #15.4 + audit 2026-05-12. Include self-evolution rule that mandates appending NEW classes / refinements / red flags to the skill before session completion.
regression_test_planned: []
---
# Body

Process-discipline addition, not a bug fix per se. This diagnose-doc justifies why it counts under CLAUDE.md §22:

**Why it qualifies as a fix:** The recurring class codified in `feedback_writer_reader_field_drift_recurring.md` notes "every batch since Test #6 has surfaced one" — i.e. the methodology gap is itself a bug in the development process. Each recurrence costs 30+ minutes of re-discovering "Step 2: writer/reader map" + "Step 3: grep MEMORY.md for prior fixes." Codifying the methodology as an invocable skill eliminates that re-discovery cost.

**What was created:**
- `.claude/skills/debugging/SKILL.md` — 6 sections, ~280 lines (within 500-line constraint).
  - § 0 When to invoke
  - § 1 Methodology — 6-step checklist with citations to MEMORY.md feedback_* files
  - § 2 Bug class catalog — 10 seeded classes (writer/reader drift, IST drift, cross-account Riverpod race, partial-unique-index ON CONFLICT trap, Edge cold-start retry, Vault service-role-key, Android Auto-Backup leak, migration-record pair gap, subagent numeric hallucination, provider-invalidation gaps)
  - § 3 Red flags — 10 "if you're thinking X, STOP" entries (mix of `superpowers:using-superpowers` patterns + project-specific from `feedback_no_stop_until_done.md`, `feedback_no_deferrals.md`, `feedback_apk_build_explicit_approval.md`, etc.)
  - § 4 Output contract — 11-field summary every session produces
  - § 5 Self-evolution rule — MANDATORY append on new class / refinement / red flag
  - § 6 Cross-references
  - Changelog

**Invocation:** The project-local skill at `.claude/skills/debugging/SKILL.md` mirrors the directory shape of `.claude/agents/` and `.claude/commands/` which already exist and are invoked by name. The harness's plugin-namespaced skills (`superpowers:systematic-debugging` etc.) remain available; this skill is the project-specific extension that knows about ICANBEFITTER's WriteServices, IST helpers, sync fan-out contract, and historical batches.

**Deviation from request:** None.

**Files changed:** `.claude/skills/debugging/SKILL.md` (new), `docs/diagnoses/2026-05-15-debugging-skill-creation-4e9515.md` (this file).

**No commit per A7 lane discipline.** Files staged for founder review; main thread / founder decides commit timing.
