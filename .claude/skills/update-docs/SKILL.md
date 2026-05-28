---
name: update-docs
description: Walk the 11-node knowledge-graph maintenance protocol at
  end of a bug-fix or feature batch. Reads git diff main, populates the
  checklist with file-path → destination mappings, prompts per-node,
  writes the project_*.md retrospective. Use when user says "update
  docs", "wrap up docs", "finalize this batch's docs", or at any batch
  endpoint.
---

# Update Docs — Per-Batch Knowledge Maintenance

## When to invoke

End of any batch that lands a commit on a feature branch. User explicitly says "update docs" or any synonym.

## Steps

1. **Capture batch scope.**
   - Run `git log main..HEAD --name-only` to list every file touched since branching.
   - Run `git diff main --stat` for line-change summary.
   - Note any new diagnose-docs added this batch via `ls docs/diagnoses/<today>-*.md`.

2. **Extract diagnose-doc metadata.**
   - For each new diagnose-doc, parse its YAML frontmatter.
   - Capture: `writers:` paths, `readers:` paths, `concept:`, `recurrence:` if present.

3. **Map file paths to destination CLAUDE.md or architecture doc.**
   - Use `references/path-mappings.md` for the canonical table.
   - For cross-cutting changes (2+ feature areas), suggest `docs/architecture/<topic>.md`.

4. **Render the 11-node checklist.**
   - Use `references/eleven-node-checklist.md` as the template.
   - Pre-populate each node based on detected changes.
   - Mark nodes that need updates with concrete suggestions.

5. **Prompt per-node.**
   - For each node with a pre-populated suggestion, ask user: "Update [node] with [suggested content]? (y/n/edit)"
   - Apply updates or skip per response.

6. **Regenerate bug-history index.**
   - Run `dart run scripts/build_bug_index.dart` to refresh `docs/diagnoses/INDEX.md`.

7. **Write project_*.md retrospective.**
   - Use `references/retrospective-template.md`.
   - Pre-populate the "Knowledge nodes updated this batch" table.
   - Save to `~/.claude/projects/<project>/memory/project_<batch_name>.md`.

8. **Update MEMORY.md index.**
   - Append a one-line entry under "Recent batches" (newest first).
   - Cite the project_*.md file.

9. **Print summary.**
   - List touched files + skipped nodes.
   - Note any nodes flagged as "should be done in a follow-up" — those go into the retrospective's "Follow-ups deferred" section.

## Extended checklist nodes (added by Tech-debt audit 2026-05-20 / B1)

Beyond the 11-node knowledge-graph protocol above, every batch must also walk these tech-debt-prevention nodes:

10. **Is `docs/diagnoses/INDEX.md` regenerated?** Run `dart run scripts/check_diagnose_index_fresh.dart`. If FAIL, run `dart run scripts/build_bug_index.dart` + verify any new diagnose-doc has parseable YAML frontmatter (closing `---`) + filename ending `-<6char-id>.md`.

11. **Are CLAUDE.md `§N` citations live?** Run `dart run scripts/check_claude_md_citations.dart`. If FAIL, replace broken cites with `docs/diagnoses/INDEX.md` or `docs/playbook/common-pitfalls.md` per convention.

12. **Is `backups/applied_migrations.json` in structured ledger form?** Each row must be `{migration, applied_at, hash, applier}`, not a bare string. Gate: `scripts/check_applied_migrations_ledger.dart` (lands in B3).

13. **Is `docs/operations/SECRET_INVENTORY.md` current?** If this batch added a new local-only secret file (env var, key file, PAT), append a row.

14. **Are new cron jobs registered in `CRON_REGISTRY.md`?** Gate: `scripts/check_cron_registry.dart`. Every `cron.schedule('NAME', ...)` in a new migration MUST be added to the registry in the same commit.

15. **Are new gate scripts wired into pre-commit + CI?** Gate: `scripts/check_gate_scripts_wired.dart`. If you added a `scripts/check_*.dart`, the dynamic loop in `scripts/pre-commit.sh` + `.github/workflows/test.yml` picks it up automatically — but verify by running the gate.

16. **Are SoT registry entries tagged with `behavioral_test_path:` (not just source-grep)?** Source-grep tests count for "presence" only; semantic drift slips through. Every new SoT entry needs a behavioral contract test too (lands in B2 sweep; this checklist node lights up after B2).

17. **Were new singletons added without Riverpod scoping?** If yes, audit cross-account leak risk — `feedback_singleton_cross_account_leak.md` codifies. Gate `scripts/check_singleton_provider_migration.dart` (Gate 46) enforces the 7 named services are accessed via Provider not `.instance` (lands B5 D9-D10).

18. **Did every closed audit finding get `terminal_state:` (not a stale comment)?** Per `feedback_closure_yaml_per_finding_discipline.md`. Gate 40 (`scripts/validate_audit_closure.dart`) warns on entries with only a stale-pattern comment + no terminal_state. Pre-merge: `dart run scripts/validate_audit_closure.dart --strict` to fail loudly.

19. **Does every nested `lib/.../CLAUDE.md` carry real content (not a Milestone-2 scaffold)?** Gate 44 (`scripts/check_nested_claude_md_content.dart`) flags files under 40 lines or containing literal "Milestone-2 scaffold" string. Lands B5 D2.

20. **Was a `behavioral_test_path:` recorded alongside any new `source_grep_test_path:`?** Reinforces node 16. SoT registry entries without behavioral test get `behavioral_test_required: true` + a Gate 42 WARN (lands B5 D2).

21. **Are new screens under 800 lines / using sibling-folder pattern for widgets?** Gate 43 (`scripts/check_god_screen_max_lines.dart`) flags any `lib/**/screens/*_screen.dart` over 800 lines. Sibling folder pattern: `train/screens/active_workout/{screen.dart, set_card.dart, ...}` per locked C3/C4 decision.

22. **Was a feedback memory added when this batch surfaced a NEW recurrence class?** (Not for one-off fixes — but if the bug class would appear in `debugging/SKILL.md` §6 / `writer-reader-drift-detector/SKILL.md` §2 as a future entry, codify the memory.)

23. **Was a new project-local skill warranted by this batch?** Per §5.1 — 3+ batches share a pattern → new skill. Current count: 6 (debugging, update-docs, tech-debt-audit, dep-bump-sweep, edge-function-deploy-rollback, writer-reader-drift-detector). Next candidates if pattern recurs: secret-rotation, cron-registry-check.

24. **Did this batch make an architectural decision worth an ADR?** Per `docs/adr/README.md` (added in 2026-05-28 six-industry-gap closure batch). If yes → invoke `/adr` to scaffold the next-numbered ADR with MADR-lite frontmatter. Test: "if someone proposed reverting this decision 6 months from now, would I have to re-do the analysis?" — yes → ADR.

25. **Did any new durable rule emerge this batch?** Per `docs/handbook/README.md` (added in 2026-05-28 six-industry-gap closure batch). If yes, promote from memory `feedback_*.md` to `docs/handbook/<category>/<topic>.md`. Memory dir's role going forward is scratch + retros only.

26. **Is the batch's max blast-radius ≥ `account`?** Per `docs/blast_radius.yaml` (added in 2026-05-28 batch). If yes, **propose invoking `/hermes-pass`** before commit. The Hermes deep-pass dispatches parallel Opus subagents per `LENS_REGISTRY.md` lens and consolidates findings into `docs/audit/<date>-hermes-<batch>.md`. Skip the prompt for `feature`-tier batches; mandatory for any `catastrophic`-tier commit.

## Self-evolution changelog

- **2026-05-21 (Tech-debt audit 2026-05-20 / B1)** — Added extended-checklist nodes 10-17.
- **2026-05-21 (Tech-debt audit 2026-05-20 / B5 D1)** — Added nodes 18-23. Updated node 17 to point at landed `feedback_singleton_cross_account_leak.md` + Gate 46.
- **2026-05-28 (six-industry-gap closure batch)** — Added nodes 24 (ADR), 25 (handbook port), 26 (Hermes-pass auto-suggest). Wires this skill to `/adr` and `/hermes-pass` skills and `docs/blast_radius.yaml`.

## Output

- N nodes updated.
- 1 retrospective written.
- 1 INDEX.md regenerated.
- MEMORY.md index appended.

## Anti-patterns

- Skipping a node "because it seems unchanged" without checking — if your batch touched any file in the node's domain, AT LEAST consider the update.
- Writing the retrospective without filling the 11-node table — the table IS the retrospective discipline.
