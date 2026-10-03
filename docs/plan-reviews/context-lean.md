---
branch: context-lean
date: 2026-09-29
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/54e7a99c801b-review.md
---

# Plan-review record — context-artifact lean-down (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`, COMPUTED** — `dart run scripts/blast_radius_from_diff.dart CLAUDE.md` -> `platform`,
and the whole staged diff (stdin mode fed the staged path list) also -> `platform`. Driven by the root
CLAUDE.md edit, the skill/gate scripts and `docs/blast_radius.yaml`. No `SECURITY DEFINER` migration,
so not catastrophic.

## What this branch is

A lean-down of the always-loaded and per-invocation context artifacts, measured 2026-09-29:

| Artifact | Before (B) | After (B) |
|---|---|---|
| root `CLAUDE.md` | 152,740 | ~40,800 |
| `code-review/SKILL.md` | 317,594 | ~22,200 |
| `debugging/SKILL.md` | 236,274 | ~48,400 |
| `supabase/functions/CLAUDE.md` | 45,519 | 24,073 |
| `lib/features/train/CLAUDE.md` | 33,639 | 18,036 |
| `lib/features/auth/CLAUDE.md` | 33,275 | 15,939 |
| `lib/core/services/CLAUDE.md` | 30,171 | 18,002 |
| `lib/features/ai_coach/CLAUDE.md` | 25,163 | 15,229 |
| `lib/shared/repositories/plan_engine/CLAUDE.md` | 40,328 | 16,986 |
| `docs/audit/open_issues.md` | 574,521 | 479,979 |

Nothing is deleted: the removed text MOVED (content-identical; three OI bodies and three bug-class
blocks differ only by a trailing blank line or `---` separator) to `docs/architecture/{hooks,
process-invariants-detail,functions-detail,train-detail,auth-detail,services-detail,ai-coach-detail,
plan-engine-detail}.md`, the appended "Full incident detail for CLAUDE.md §4.9 rows" section of
`docs/playbook/common-pitfalls.md`, `.claude/skills/code-review/tuning-history.md`,
`.claude/skills/debugging/bug-classes.md` and `docs/audit/closed_issues.md` (22 closed OI entries).
The rule text of root §4.3/§4.4/§4.12/§4.13 was CONDENSED (full text in
`process-invariants-detail.md`); that condensing is the highest-risk part and was reviewed line by line.
Enforcement that read the moved text was repointed: the tuning-history gate, the review-hash pathspec,
the deferral-euphemism full sweep (16 -> 21 documents), the context-budget gate (3 -> 13 tracked files,
plus a tracked-list test), `docs/blast_radius.yaml` (6 new globs so binding prose keeps its tier).

**Execution mode (decided at batch start, §4.12.7):** subagent-driven — one isolated worktree per unit
(U1 root, U2 five nested files, U3 skills + gate repoint, U4 OI board, U6 plan_engine added at the
founder's request), the coordinator integrating by file copy and being the single writer of shared files
(budget baseline, blast_radius.yaml, this record). Harness memory cleanup (U5) is outside the repo.

## Rounds

| Round | Reviewers (context-blind, read-only) | Findings |
|---|---|---|
| 1 | A: rule fidelity + pointer integrity. B: readers of moved text (writer/reader drift) | A: 0 P0/P1, 8 P2 (dropped qualifiers in §4.12.4/.6 and rule 21, stale self-references, an over-promising §4.9 intro, an un-announced §5 row). B: 0 P0, 2 P1 (the code-review skill's staging-hash recipe listed three pathspecs where the gate uses four; `tech-debt-audit` told writers to append bug-class bodies to the now index-only SKILL.md) + P2s. All fixed. |
| 2 | C: fix verification + agent-usability simulation (8 questions answered from root alone). D: gate loop, CI parity and mutation proof of the changed gates | C: 0 P0, 1 latent P1 (the full text of the binding rules moved to a `feature`-tier doc; fixed by blast_radius globs), 4 P2. D: 0 P0, 1 P1 (removing a tracked path from the budget gate reddened zero tests; fixed with `context_artifact_tracked_list_test.dart`, mutation-proven 2 of 3 red) + 2 P2. All fixed. |
| B-pass | Fresh Sonnet via the code-review skill, 8 lenses (`docs/reviews/54e7a99c801b-review.md`) | 4 findings (0 P0/P1), 0 false alarms, all fixed; it ran on the tree before its own fixes and the review file says so. |

**Converged at round 2 + B-pass.** Round 1 found only stale-text and dropped-qualifier issues; round 2
found no defect in the round-1 fixes, one latent tiering gap and one unproven protection, both fixed and
mutation-proven; the B-pass then found four smaller items and no P0/P1. No round surfaced a lost binding
rule. Per §4.12.1 the split-and-re-review signal is successive rounds surfacing NEW material issues;
that did not occur.

## Ground truth (verified against files, not against reviewer or agent prose)

- Sizes re-measured with `wc -c` after each integration; the budget baseline matches actual bytes for all
  13 tracked files.
- Losslessness re-derived by the coordinator: OI ids across both boards equal HEAD's multiset (265 = 265,
  22 moved, none duplicated or lost); 87 debugging `### 2.N` headings equal the 87 index rows; plan_engine
  310 original lines, 1 not verbatim (the intentionally bumped `updated:` date); the moved-verbatim claim
  for root text was independently checked by two reviewers (824 long HEAD lines found in destination docs).
- Gates and suite on the FINAL staged tree: `sh scripts/pre-commit.sh` exit 0; `flutter analyze lib/`
  60 infos, 0 warnings, 0 errors (this batch changes no `lib/` code); `TZ=Asia/Kolkata flutter test test/
  --exclude-tags golden` 7064 passed, 9 skipped, 0 failed.
- Mutation proofs (§4.4 rule 21), each confirmed applied, red on assertion text and restored: tuning-history
  path revert (6 red), `:(top,exclude)` pathspec removal (1 red), budget tracked-path removal (2 of 3 red),
  deferral sweep moved-docs loop disabled (3 red) and skill-file filter narrowed (2 red), `deu-quote` marker
  deletion (gate exit 1), a broken `§` cite (Gate 26 red), a duplicate OI heading (numbering gate exit 1).
- A full-loop run also caught a real defect the reviews had not: `check_gate_existssync_file_vs_dir.dart`
  flagged the batch's own new `File().existsSync()`; fixed with the gate's `// file-only:` justification
  and the whole loop re-run.

## Deliberate residues (stated, not hidden)

- The new §5 checklist row "open_issues.md has 0 CLOSED entries" is an ADDITION, self-attested, with no
  gate behind it.
- The nested CLAUDE.md files landed at 15–24 KB rather than the ~12 KB first aimed at; what remains is live
  contract (writer/reader rows, kill-switch and gate names, do-not rules). plan_engine ended at ~17 KB.
- `docs/architecture/hooks.md` is `platform` after two reviewers recommended it; the coordinator's earlier
  default had been `feature`.
- The primary checkout holds an uncommitted, staged row in `lib/core/services/CLAUDE.md` (diagnose f7b2c9)
  that is not on `main`; it will conflict with the trimmed file when it lands and belongs to whoever owns it.
- Pre-existing rot observed and NOT introduced here: a stale `open_issues.md:481` self-cite and several old
  diagnose-doc line anchors.
