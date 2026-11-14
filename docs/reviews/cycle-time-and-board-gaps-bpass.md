---
reviewed_at: 2026-08-17T18:40:00+05:30
staged_against: 3c7cb9d2a93f7af4969cec20a5d400e672164507
branch: cycle-time-and-board-gaps
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 5
verdict: accepted
---

# Code Review (B-pass) — `cycle-time-and-board-gaps` @ `3c7cb9d2`

Fresh context-blind Sonnet subagent, 6 lenses, dispatched per
`.claude/skills/code-review/SKILL.md`. Ran AFTER two independent context-blind
plan-review rounds (8 and 10 findings). **Every finding below was independently
re-verified by the author before being acted on** — per CLAUDE.md, subagent
claims are unverified until confirmed against the file.

4 of 5 findings are `guard_without_its_mirror`. That lens has now earned its
place three passes running on this one branch.

## Finding 1 — P0 — guard_without_its_mirror

- **file:line:** `scripts/git_safety_hook.dart:120-139`; root cause at the call
  site, not in `scripts/git_safety_lib.dart`.
- **claim:** The inline escape hatch was bound correctly to a statement and then
  the CALLER collapsed it into one command-wide boolean applied to every deny.
  A harmless hatched statement therefore exempted a DIFFERENT, dangerous one.
  No shell behaves this way — an inline `NAME=1 cmd` assignment prefixes exactly
  one command and is never carried to the next statement, so this was not even
  shell-accurate.
- **verification:** Driven through the hook's real stdin contract with controls
  in both directions (plain raw commit/push → exit 2 throughout):
  | command | before | after |
  |---|---|---|
  | `ALLOW_RAW_GIT=1 git status; git push origin main --force` | **0** | 2 |
  | `ALLOW_RAW_GIT=1 git status && git commit -m sneaky` | **0** | 2 |
  | `FOUNDER_APPROVED_NO_VERIFY=1 git status; git commit --no-verify -m x` | **0** | 2 |
  | `ALLOW_RAW_GIT=1 git log -1 \| git push origin main` | **0** | 2 |
  The third is the worst: it exits the hook at the top, before the commit and
  push checks run at all.
- **suggested-fix:** Pair the hatch with the danger per statement.
- **fix applied:** New `unhatchedGitStatements` / `unhatchedNoVerifyStatements`
  in `git_safety_lib.dart` return the offending STATEMENTS (not a bool —
  returning a bool is what let this happen), each judged against its own leading
  prefix. Exported env vars stay command-wide, which is correct: a real exported
  variable does apply to every statement. 37/37 across three case matrices;
  8 new library tests.
- **status:** fixed

## Finding 2 — P1 — guard_without_its_mirror

- **file:line:** `scripts/check_oi_numbering_unique.dart` — both merge arms.
- **claim:** Blind to octopus merges by two independent mechanisms: the
  post-merge arm compares `parents[1]` vs `parents[2]` only, and the mid-merge
  arm reads `MERGE_HEAD` via `git rev-parse --verify`, which silently resolves a
  multi-line `MERGE_HEAD` to its FIRST line with exit 0.
- **verification:** Three branches, two minting `OI-31` with different titles in
  non-conflicting regions; `git merge --no-ff A B` completes cleanly and the
  gate printed PASS — while its own diagnostic line reported 32 raw headings vs
  31 distinct.
- **fix applied:** Detects both shapes (`parents.length > 3`, or a `MERGE_HEAD`
  with >1 non-blank line) and reports **UNDETERMINED**, skipping the comparison
  rather than answering about two of three-plus sides. Deliberately not a
  looping N-way predicate: that is a different predicate needing its own e2e
  coverage, and nothing in this repo produces octopus merges — `safe_merge.sh`
  takes a single branch. Refusing to answer matches this file's convention
  everywhere else.
- **status:** fixed

## Finding 3 — P1 — blast_radius_mismatch

- **file:line:** `docs/blast_radius.yaml` — no entries; fell through `scripts/**`.
- **claim:** The new hook was pinned `platform`; the gate scripts it invokes and
  the resolver all five hooks source were not. Fourth instance of this exact
  miss — the file's own comments record two prior rounds of it.
- **verification:** `printf '<path>\n' | dart run scripts/blast_radius_from_diff.dart -`
  → `feature` for `check_oi_numbering_unique.dart`, `oi_numbering_lib.dart`,
  `check_hooks_installed.dart`, `_dart_bin.sh`; control `pre-merge-commit.sh`
  → `platform`, isolating the gap to the dependencies.
- **fix applied:** All four pinned `platform` with the reasoning recorded inline.
  `_dart_bin.sh` in particular is a more central single point of failure than
  `_git_lock.sh`, which was itself promoted for having two dependents.
- **status:** fixed

## Finding 4 — P1 — guard_without_its_mirror

- **file:line:** `scripts/check_hooks_installed.dart` — the `invocationCount`
  cross-check added in round 2.
- **claim:** It catches UNDER-parsing only. A DUPLICATE `install_hook` line
  keeps both counts equal while a different hook goes missing entirely — the
  same "PASS while the flagship hook is not installed" failure the gate was
  rewritten to stop, reached through a different corruption (a merge-conflict
  resolution keeping both sides).
- **verification:** Installer text with `pre-commit` duplicated and
  `pre-merge-commit` absent → 5 parsed, 5 counted, cross-check satisfied,
  `pre-merge-commit` never checked.
- **fix applied:** Duplicate destinations now report UNDETERMINED.
- **status:** fixed

## Finding 5 — P2 — guard_without_its_mirror

- **file:line:** `scripts/pre-merge-commit.sh` — `_restore_index`.
- **claim:** Round 2 hardened the copy INTO the backup and left the copy back
  OUT unchecked. Asymmetric hardening of two halves of one operation.
- **verification:** Reviewer forced the restore-direction `cp` to fail and
  confirmed it aborts under `set -e` — fail-CLOSED, not a bypass. Residual: a
  bare `cp` error instead of this file's usual actionable message, and the
  backup temp file left uncleaned with no pointer to it.
- **fix applied:** Checked, with a message naming the retained backup path and
  an explicit note that the backup is deliberately NOT deleted on that path.
- **status:** fixed

## Lens coverage

| lens | result | evidence |
|---|---|---|
| writer_reader_drift | N/A | `grep -niE "\.put\(\|\.get\(\|Box<\|hive_flutter"` over the diff → one hit, prose naming an unrelated gate. No Hive/Postgres access in any changed file. |
| function_exception_swallow | clean | `grep -n "functions.invoke("` over the diff → 0 matches. |
| blast_radius_mismatch | **1 finding** | Real classifier run per path + full read of the registry and its wiring test. |
| secrets_in_tree | clean | `grep -nE "sk-[A-Za-z0-9]\|rzp_live_\|AKIA[0-9A-Z]{16}\|-----BEGIN"` → one hit, prose describing the `rzp_live_*` PATTERN used by a pre-existing gate. No literal credentials. |
| unawaited_no_error_sink | clean | `grep -n "unawaited("` over the diff → 0 matches. |
| guard_without_its_mirror | **4 findings** | Method: files copied verbatim into scratch dirs or run unmodified against synthetic repo state, then EXECUTED against adversarial inputs. Also checked and found clean: CRLF heredoc delimiters, backslash-in-single-quotes (POSIX-correct), no-`origin/main` and detached-HEAD paths. |

## Founder triage notes

All five accepted and fixed in-batch per §4.2; none disputed. Verdict `accepted`.

**What this pass says about the batch, beyond the five findings.** This is the
third consecutive independent pass to find a defect in the previous pass's fix,
in one function:

| pass | found | introduced by |
|---|---|---|
| round 1 | hatch matched anywhere in a statement | the original hardening |
| round 2 | "statement" could be non-executable text | round 1's fix |
| B-pass | statement binding discarded at the call site | round 2's fix |

Every one was found by EXECUTION with a control, never by reading the diff, and
every gate was green throughout — because the artifact under change *was* the
gate. That is the batch's own lesson, and it is why `guard_without_its_mirror`
now carries a method note demanding mutation over reading.

**Known-open, deliberately out of scope, founder-scoped 2026-08-17:** OI-119 —
the DENY path misses 13+ executable spellings (`(git commit)`, `/usr/bin/git`,
`sudo git`, `xargs git`, single-`&` separator) and `commandUsesWrapper` matches
a path suffix command-wide. Pre-existing; this batch is a net improvement in
that exact direction. Closing it means widening the deny path, whose one
intolerable failure mode is a false BLOCK — the analysis OI-119 is already
blocked on. Both directions are now measured and recorded there with the
reproduction harness.
