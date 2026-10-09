# ⚠️ NOT the live memory index — read this before trusting anything in this directory

This file used to be a **mirror** of the agent memory index. Its old header instructed *"Keep both
files in sync when adding new memory entries."* That sync stopped on **2026-04-20** (`0a81f6cb`)
and the copy then sat unchanged for ~3 months while the real index moved on.

Worse than merely stale: most of its links pointed at files that live **only** in the harness
memory directory and were never committed here — so following them from the repo led nowhere. A
**cloud session**, which can see the repo and nothing else, would have found a confident-looking
index, trusted it, and been wrong about the project's state on every line.

Kept as a pointer rather than deleted. A grep for `memory/MEMORY.md` returns 7 hits, but be precise
about them — an earlier draft of this stub was not: **5 cite the harness path**
(`~/.claude/projects/…/memory/MEMORY.md`), including `scripts/discipline_hook.dart`'s own constructed
path. **Only 2 are repo-relative**, both inside already-executed 2026-05-10 plan documents. So the
filename is worth preserving, but the "7 citations" figure overstated the case.

## Where things actually live

| You want | Read | Visible from a cloud session? |
|---|---|---|
| **What is still owed / pending** | **`docs/audit/open_issues.md`** | **Yes — repo-tracked.** The cross-session source of truth. Surfaced automatically at every session start by `scripts/discipline_hook.dart`, and gated at merge-to-main by `scripts/check_open_issues_reconciled.dart`. |
| Why a decision was made; past scars | `~/.claude/projects/<mangled-project-path>/memory/` | **No.** Harness-local, outside git, untracked. Rich and current, but it does not exist on another machine. |
| Bug forensics | `docs/diagnoses/INDEX.md` | Yes |
| Architectural decisions | `docs/adr/` | Yes |

## The sibling files in this directory

`memory/feedback_worktree_per_session.md` is genuinely live — 5 inbound citations including
CLAUDE.md §7, which points at it directly. Do not treat it as stale.

The others are weaker, and saying so is the point of this stub: `project_pr_ah_part_b.md` and
`project_pr_ai_onboarding_fields.md` have **zero inbound citations**, and overwriting the old index
removed their only entry point. They are shipped-PR retrospectives from April, kept for history
rather than reference. If you need them, they are right here in this directory — that is now their
only discovery path, and this sentence is it.

Only **the index** rotted, because only the index was a duplicate of something that kept changing.
A mirror of a moving target is a liability; a file that is the only copy of itself is not.

## Why no attempt to re-sync

Restarting the mirror would recreate exactly the failure it just demonstrated: two copies, one
authoritative, no mechanism holding them equal, and silent divergence the moment attention moves
elsewhere. The durable-visibility problem is solved instead by putting *pending work* in a
repo-tracked file with a gate and a session-start injection behind it. See the
**Reconciliation 2026-07-26** section at the end of `docs/audit/open_issues.md` for the full
reasoning and the audit of what was still open after the backlog's 70 dormant days.
