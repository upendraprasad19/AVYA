---
branch: discipline-enforcement
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/discipline-enforcement-bpass.md
tier: platform
reviewed_at: 2026-08-25T12:40:00+05:30
---

# Plan review — automatic §5 enforcement (a gate + a Stop hook)

## Why this exists

Founder asked, after an audit found **four §5 rows unwalked** in one three-part
batch: *"how can we enforce this so that I don't have to remind you again and
again? I want this enforcement to be automatic."*

The answer the repo already contains, written about a different rule entirely
(§4.13 point 6): **everything with a gate holds, everything on intention decays.**
§5.1 had no gate. §5's end-of-batch rows had no trigger. So they decayed.

## What ships

1. **`check_skill_tuning_history.dart`** — a commit adding a review file under
   `docs/reviews/` must also append a same-dated entry to the code-review
   skill's Tuning history.
2. **`batch_close_hook.dart`** — a `Stop` hook, the first thing in this repo that
   fires at the **end** of a batch. The three previously-wired events
   (`SessionStart`, `UserPromptSubmit`, `PreToolUse`) all fire BEFORE work, which
   is precisely why the end-of-batch rows were the ones that rotted.

**What it enforces, stated plainly:** that the rows are **answered**, not that
they were done. Several are unknowable to any script and render `[?]` — *could
not determine*, deliberately not the same as fine. The content stays
self-attested; same trust model as rule 21's `presence_only:` and rule 24's
ledger. This is a forcing function, not a proof.

## Round 1 — NOT SAFE TO MERGE. 1 BLOCKING, 2 MAJOR, 2 MINOR. All accepted.

**BLOCKING — the Stop hook could hang, wedging every session.** It used the
synchronous `stdin.readLineSync`; a caller that never closes stdin blocks
forever, and a hang is not an exception so the surrounding `try/catch` could not
rescue it. Reproduced: still blocked past 8s, exit 124. Stop fires at the end of
**every turn**, so this was the worst possible location for it.

⚠ **The repo had already fixed this exact class, twice.** Both sibling hooks
carry `hasTerminal` + a 3s timeout, and `git_safety_hook.dart:86` records it as a
prior B-pass finding: *"an unresolved read … must never hang the whole session;
fail open instead."* A grep for `hasTerminal` would have found it. **Second
bug-history miss of this shape in two consecutive batches.**

**MAJOR — the gate was blind to the majority naming convention.** It matched only
`-review.md`. Measured: of **164** files in `docs/reviews/`, **81** end
`-bpass.md` and **79** end `-review.md`, and the skill's own history cites
`-bpass.md` for most recent entries. Enumerating both suffixes would fix today
and rot on the next spelling, so a review is now identified by **where it lives**.
Also fixed: one dateless stray `.md` used to make the whole evaluation
undetermined, masking a real miss beside it.

**MAJOR — the two bugs this batch was proudest of catching had NO regression
protection, and the commit message claimed they did.** Reverting
`--git-common-dir`, and reinstating the `-+` collapse, each reddened **zero**
tests. Both functions were inline in the hook and unreachable by any test — the
lesson `gatherHoldRows` taught one batch earlier. Extracted as
`primaryRootFrom()` / `mangleProjectPath()`; they now redden 4 and 2.

**That false claim was the THIRD past-tense assertion this session with nothing
behind it** — logged as its own class in the memory file.

**MINOR — three mutation counts were wrong**, and the mangling was untested for
exotic paths.

### And my fix for the BLOCKING finding was wrong before it was right

The no-hang test failed, and I nearly concluded the hook still hung.
Instrumenting showed it completing in **5s**: the **test** never drained the
child's stdout, the JSON block filled the pipe buffer, and the child blocked on
**write**. A test-harness deadlock wearing the costume of the defect under test.
Both pipes are drained now, and the mutation confirms it reddens on the real bug.

## Round 2 — NOT CONVERGED, 0 BLOCKING. All accepted and fixed.

Round 2 independently re-ran **all nine mutations** and every one matched the
claimed count. It also verified the stdin fix against a genuinely-open pipe
(exits in 5.3s, never hangs), confirmed `--git-common-dir` returns the identical
primary path from both the primary and a linked worktree, and confirmed the
`Stop` entry matches the existing hook schema.

What it found instead was **false coverage in `CLAUDE.md`** — round 1's exact
class recurring one level out, in prose rather than in tests:

| claimed | actual |
|---|---|
| `batch_close_lib_test.dart` 14 | **22** |
| `batch_close_hook_e2e_test.dart` 6 | **7** |
| skill-tuning pair 20 | **23** (13 + 10) |
| gate "mutation-proven on two legs" | **three** |
| 89 `check_*.dart` | **90** |

**How it slipped is the instructive part.** The commit's own aggregate — "52
tests across 4 files" — **is correct**. I verified the sum and never reconciled
the parts I had written into CLAUDE.md against it. A right total sat on top of
four wrong components. **Checking a derived figure is not checking its inputs.**

Round 2 also surfaced two things now recorded rather than left implicit: the
gate's "code-review only" scope is protected **by accident** (the one hermes
output in `docs/reviews/` happens to use `staged_against:` not `reviewed_at:`,
so it fails open), and `Stop` firing at turn-end means Dart-wrapper startup is
now paid **twice per turn**.

⚠ **I nearly shipped another wrong number while fixing the wrong numbers.** My
first count of the case-skip list returned 16, because the grep also matched gate
names inside comments in that block. Reading `pre-commit.sh:328-341` directly
shows exactly **14** real case labels. Verified by reading, not grepping.

## Evidence — nine mutation legs, all re-measured after the round-2 fixes

| unit | mutation | red |
|---|---|---|
| gate | matcher → `contains(isoDate)` | 4 |
| gate | fail-open → satisfied | 3 |
| gate | filter → `-review.md` only | 2 |
| hook | remove `stop_hook_active` guard | 2 |
| hook | UNVERIFIED → satisfied | 1 |
| hook | remove once-per-HEAD guard | 2 |
| hook | `primaryRootFrom` returns raw | 4 |
| hook | reinstate the `-+` collapse | 2 |
| hook | `readLineSync` back (the hang) | 1 |

52 tests across 4 files. `flutter analyze` clean on all 8 touched files.

## The honest limit

This makes the checklist **unskippable**, not **truthful**. A row can be answered
carelessly. What is closed is the silent-omission hole — the case where four rows
went unwalked and nobody, including me, noticed until founder asked.

## B-pass — 4 findings, **2 P0**, all fixed. And it caught what ×2 could not.

**P0 — the Stop hook measured its batch against a stale mainline.** `origin/main..HEAD` = 9
while `main..HEAD` = 2, because three earlier batches were merged-but-unpushed — which §4.13
point 1 calls **the common state** for this repo. Three DERIVED rows then reported green on
other batches' evidence: another batch's review file satisfied the skill-tuning row, another
batch's `fix(...)` subjects set the feedback row, and the retrospective check anchored to an
unrelated commit's date. `new-worktree.sh:65-91` had already solved this exact
range-selection problem; the fix was not carried across. **Third guard-without-its-mirror
instance in this batch.** Fixed via `chooseRange()`; mutation reddens 1.

**P0 — the gate would have silently passed its own first real use.** `hasTuningEntryFor`
matched ANY bullet carrying the date, and `SKILL.md` already held a 2026-08-25 entry for an
unrelated batch. This very B-pass's review file, written the same day, would have been
reported PASS with no entry of its own. Fixed with a block scan requiring the entry to NAME
the review; mutation reddens 2. **Demonstrated live afterwards:** staging the review file
blocked the commit *even though* a same-dated entry already existed, and passed only once an
entry naming this review was written.

**P1 — the four new scripts classified `feature` alone**, so a later commit fixing one of the
P0s above would have skipped both the pre-push full suite and the keystone plan-review gate.
Pinned `platform` at birth.

**P1 — the `_range()` comment contradicted its own code** on the unknown-range case. Resolved
as a doc fix, deliberately: with no mainline there is nothing to measure a batch against, and
a hook that blocked every turn in a fresh clone would be worse than silence. A test now pins
that silence as intentional.

### Why this pass earned its keep after two ×2 rounds

Both P0s were invisible to 52 passing tests and to two independent context-blind rounds, and
both fell out **immediately** on running the thing against the live tree. A fixture encodes
the author's model of the world; the working tree does not. **When a batch builds a checker,
point the checker at itself and at the real repo, not at a fixture.**

### Process incident, recorded rather than absorbed

The reviewer's own `cd` into a not-yet-created directory failed silently, leaving it in this
worktree, and an `ALLOW_RAW_GIT=1 git commit` landed a stray commit that deleted an untracked
file. Self-caught, reset, file recovered byte-for-byte; author independently verified HEAD,
ancestry and file length afterwards. Two lessons: chain `cd <dir> && …` so a failed `cd`
aborts, and **a review subagent should not hold a raw-git escape hatch at all.**

## Final evidence — eleven mutation legs

Nine from rounds 1-2, plus the two P0 fixes (`chooseRange` → always-origin: 1 red;
identity → date-only: 2 red). **61 tests** across 4 files. `flutter analyze` clean.
