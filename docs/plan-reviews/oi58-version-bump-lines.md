---
branch: oi58-version-bump-lines
date: 2026-07-28
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi58-version-bump-lines-bpass.md
---

# Plan review — OI-58a (version-bump exemption by blob comparison)

**This batch edits the gate that grades it**, same as the batch it descends from, so the
record is authored before the review rounds and the tier was verified against `HEAD^1`.

## Scope

One issue: OI-58a. Direct-to-main commits skipped the keystone gate entirely
(`rev-parse HEAD^2` exit before reading any diff), demonstrated twice on account-tier
auth code — `be3b4baf` and `8c38c855`.

OI-58b (merge-subject identity) is explicitly **not** in scope and stays OPEN.

## Why a third attempt, and what changed

Attempts 1 and 2 shipped inside `gate-input-family` and were rejected by independent
review; the batch was split per §4.12.1 rather than reviewed a fourth time.

| Attempt | Rule | How it failed |
|---|---|---|
| 1 | per-PUSH union of direct commits | one `feature` docs commit beside the bump killed the exemption — the standard release flow (`2c4cbddd` + `6a364656`) |
| 2 | per-commit, `paths.every(allowList.contains)` | all-of over an **allow-list** accepts every subset: a commit rewriting `monthlyPriceInr`/`freeAiMessagesPerDay` in `app_constants.dart`, version line untouched, passed at `account` under a "version-bump exemption" banner |
| 3 | per-commit, **every changed LINE** must be a version line | **REJECTED by round 1** — three bypasses in one pass: a content line beginning `++ ` parsed as a header and skipped (and able to reassign which file's regex applied); a file rendered with no `+`/`-` lines never inspected while a global flag was satisfied elsewhere; an unanchored constants regex used with `hasMatch`, so `appVersion = '…'; static const bool kBypassProGate = true;` counted as a version line |
| 4 | per-commit, **every touched FILE byte-identical** to its parent modulo the version token | **two more at B-pass**, both in the normalisation not the idea: a SECOND version token mutating freely (`hasMatch` + `replaceAll`), and a symlink mode-swap `git show` renders as content. Fixed within this attempt. |

The logical trap in attempt 2 is worth naming: *all-of over an allow-list* and *all-of
over a requirement* read identically in English and are opposites. The docstring
asserted the protective reading while the code had the permissive one.

Attempt 3 repeated the shape one level down, and round 1 named it better than I had:
*attempt 2 was an all-of over an allow-list; attempt 3 was an all-of over the lines the
parser chose to look at — and the attacker controls which lines the parser looks at.*

**Attempt 4 therefore stops parsing.** It compares the touched files' BLOBS before and
after, with the version token normalised to a placeholder, and requires byte equality.
There is no attacker-shaped text in the decision path at all.

## Ground truth

- Version-bump diff shape confirmed against the real `2c4cbddd`: exactly four changed
  lines, `-/+ version: 1.0.0+3x` and `-/+ static const String appVersion = '1.0.0+3x';`.
- The regexes now identify the version TOKEN to normalise, not to validate a line.
  Round 1 showed that borrowing `check_app_version_matches_pubspec.dart:29,37` wholesale
  was the error: that gate uses them with `firstMatch` over a whole file to EXTRACT a
  version, where indifference to surrounding text is the point. `versionLinePubspec` is
  additionally anchored at **column 0** here, so a nested `version:` under a `hosted:`
  block cannot pose as the app version (round-1 P2-6).
- **17** historical commits touched `pubspec.yaml` alone — re-derived by me, not taken
  from a report: `git log --no-merges --format=%H -- pubspec.yaml`, keeping those whose
  changed-file set is exactly `{pubspec.yaml}`. Round 1 said 19 and I carried it; the
  B-pass measured 17 and I confirmed it. Requiring both files would still redden the
  release flow, so that design choice is unchanged — only the number was wrong.
- Baseline for hard-fail: 5 of the last 60 first-parent commits are single-parent,
  3 of those ≥account. Measured **per-commit**, matching how the code now evaluates —
  attempt 1 shipped hard-fail justified on a per-commit baseline while running
  per-push, and that mismatch is what broke the release flow.

## Discrimination — measured, and then found insufficient

The point of this batch is that attempt 2 passed all of its own tests. So the controls
were checked against the thing they must catch:

| Baseline | Result |
|---|---|
| main's pre-fix gate (direct commits unjudged) | **4 of 5 fail** — the release-push test passes, and is labelled DESIGN-LOCK in place |
| reconstructed **attempt 2** (path-level exemption) | **exactly 1 fails — the bypass control** |

Both rows reproduced exactly when round 1 re-ran them independently.

**And that reassurance was the trap.** Every one of those controls is shaped like a
PREVIOUS attempt's failure, so a green suite told me nothing about the attempt in front
of me — six live bypasses coexisted with it. The e2e scenarios are kept, and
`test/scripts/version_bump_exemption_test.dart` now carries **16** controls organised by
attack instead — one per round-1 bypass, and one for each B-pass P0.

## Rounds

| Round | Outcome |
|---|---|
| 1 — exemption logic (independent, context-blind) | **REJECT.** 2 P0, 2 P1, 2 P2, 4 P3. Verdict accepted in full; every headline bypass re-executed by me against the real helper before acting. Drove the redesign from line-parsing to blob comparison. |
| 2 — on the hardened branch (independent, context-blind) | **REJECT, 3 P1.** But the redesign HELD: every attack on `isVersionBumpCommit` failed. All three breaks were in the input PLUMBING the direct-commit loop newly exercises. All fixed, each with an e2e control. |

### Round 2 — the design survived; the plumbing did not

Round 2 attacked the blob comparison directly and reported that normalisation
collisions, placeholder injection, submodules, symlinks, case-only renames, duplicate
version tokens and lossy decoding all failed to break it.

> **That report was wrong on two counts, and I repeated it here without checking.**
> The B-pass then broke the exemption using *exactly* two of the attacks round 2 listed
> as defeated — duplicate version tokens and the symlink mode-swap — and both reproduced
> for me on the first try. Writing an unverified subagent claim into a durable record is
> the `feedback_audit_verifier_cannot_trust_own_subagent` failure, committed in the
> record whose entire purpose is to be the trustworthy account. Corrected in place rather
> than quietly edited, because the correction IS the lesson.

Submodules, case-only renames, `.gitattributes` filters, placeholder-text collisions and
lossy-decode collisions were independently re-confirmed as genuinely closed by the
B-pass. The two that were not are below.

What it broke instead was how the commit reaches that logic, all three verified by me
before acting:

- **P1-1 `--name-only` collapses renames to the DESTINATION.** Deleting a governed file
  by renaming it into `docs/` made the governed path invisible: a commit deleting a
  `platform` file graded `feature` and was skipped. Confirmed against real git —
  `--name-only` prints 1 path, `--no-renames --name-only` prints 2. Fixed with
  `--no-renames`.
- **P1-2 git C-quotes non-ASCII paths** (`"lib/…/rÃ©sumÃ©.dart"`), and the
  glob matcher anchors `^…$`, so the quoted form matched no rule and fell to
  `default_tier: feature`. Fixed with `-c core.quotePath=false`.
- **P1-3 would have CRASHED CI.** `Process.runSync`'s default `stdoutEncoding` is a
  strict `Utf8Decoder` on Linux — it throws on the first invalid byte — and the new loop
  reads blobs for changed paths. This repo tracks **83** binary files, so the next push
  touching a PNG would have died with an uncaught `FormatException`, exit 255. Windows
  hid it entirely: its ACP decoder is total, so every local run was green.

  The obvious fix is a trap, and round 2 flagged it: `allowMalformed: true` maps both
  `0x80` and `0x81` to U+FFFD — verified — which would convert a loud crash into a silent
  byte-equality COLLISION. Blobs are now read as raw bytes and decoded strictly; a
  non-UTF-8 blob returns null and every caller treats null as "cannot judge", not
  "nothing to see". The escalation site also checks `isMigrationSqlPath` first, so blobs
  that could never matter are no longer read at all.

Also fixed from round 2: `_gitOrNull`'s `.trim()` silently broke the byte-identity
contract the exemption documents (P2-2); comments still described the abandoned
line-parsing design and called this "the third attempt" (P2-1); and a pre-existing stale
count, "49 of the 174 merges on main", is now 62 of 187.

### What round 1 cost, and what it bought

I verified all three headline bypasses myself rather than taking them on trust, and all
three reproduced on the first try. Also corrected: I had written "79 green" when
`flutter test test/scripts/` was **76** — the 79 included a second file I did not name.

The finding that mattered most was not a bypass but a comment about the suite: the e2e
tests had a control for each *previous* attempt's failure and none for the current one's.
That is why a green suite coexisted with six live bypasses. `version_bump_exemption_test.dart`
is now organised by ATTACK rather than by attempt — 14 controls, each naming the payload
it would have caught, each executed against the real helper before being written.

Round 1 also correctly noted that the two regexes were justified as "copied from
`check_app_version_matches_pubspec.dart`" while being used with an inverted contract:
that gate uses them with `firstMatch` over a whole file to EXTRACT a version, where
indifference to surrounding text is the point.

### B-pass — it broke what two rounds had passed

**2 P0, 1 P1, 4 P3, all fixed.** Detail in `docs/reviews/oi58-version-bump-lines-bpass.md`.

The two P0s are the ones named above: a second version token mutating freely
(`hasMatch` + `replaceAll`), and a symlink mode-swap that `git show` renders as ordinary
content. Both are now closed — exactly-one-match, and a tree-mode check requiring
`100644`/`100755` on both sides — and both fixes are verified end-to-end against the real
gate, not only in the pure function.

It also mutation-tested the binary-file control added after round 2 and found it
**vacuous**: the payload sat at a path `_gitBlob` is never called for, so the test passed
with the guard deleted. Moved to `pubspec.yaml`, where removing the guard does crash it.

## Convergence

**Converged.** Four designs, three independent review events, and the through-line is one
sentence: every failed attempt was *"accept anything containing X"* wearing the costume
of *"require everything to be X"* — over an allow-list (attempt 2), over the lines a
parser chose to look at (attempt 3), over a token that appeared more than once
(attempt 4). The shipped rule has no such shape: two blobs are equal, or they are not.

What makes this converged rather than merely green is that the suite finally contains
controls for the CURRENT design's failure modes and not only for its predecessors' —
16 attack-shaped controls plus 8 e2e scenarios, 95 tests, each written after executing
the payload against the real helper.

OI-58b (merge-subject identity) remains OPEN and is not claimed here.
