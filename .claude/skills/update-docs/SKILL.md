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

## Output

- N nodes updated.
- 1 retrospective written.
- 1 INDEX.md regenerated.
- MEMORY.md index appended.

## Anti-patterns

- Skipping a node "because it seems unchanged" without checking — if your batch touched any file in the node's domain, AT LEAST consider the update.
- Writing the retrospective without filling the 11-node table — the table IS the retrospective discipline.
