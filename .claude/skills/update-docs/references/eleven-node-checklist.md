# 11-Node Knowledge Graph Checklist

> The canonical 11 nodes that may need updating after any batch.

1. **Diagnose-docs** — every bug fix has one in `docs/diagnoses/`. Validator: `scripts/validate_diagnose_doc.dart`.
2. **Contract tests** — every fix lands one in `test/contracts/` (or equivalent).
3. **SoT registry** — `docs/sot_registry.yaml`. Update when writer/reader file:line moves.
4. **Applied migrations record** — `backups/applied_migrations.json`. Pair with every `apply_migration` MCP call.
5. **Root CLAUDE.md** — only when a NEW non-negotiable invariant emerges.
6. **Nested CLAUDE.md** — when a feature's writer/reader contract changes.
7. **Architecture docs** — `docs/architecture/<topic>.md`. When cross-cutting topic changes.
8. **Memory feedback_*.md** — when user corrects a claim OR same correction recurs 3×.
9. **Memory project_*.md** — every shipped batch.
10. **MEMORY.md index** — every memory file add.
11. **Skills** — `.claude/skills/<topic>/SKILL.md`. When new bug class extends skill scope.

For each node: status is one of `updated`, `not_applicable`, `deferred` (with reason).
