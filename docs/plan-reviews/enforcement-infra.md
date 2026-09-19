---
branch: enforcement-infra
date: 2026-07-29
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/enforcement-infra-bpass.md
---

# Plan review — enforcement-infra

CI dependency resilience, a `closes-oi` commit-msg gate, and the open-issues
board's economics. Tier is `platform`: the batch touches
`.github/workflows/test.yml` and `scripts/check_no_deferral_euphemism.dart`,
both platform-tier.

## Scope, and what left it

Shipped: **Unit 0** (unblock `main`), **Unit 1** (CI deps), **Unit 3**
(`closes-oi` gate), **Unit 4a** (bug-index symptoms), **Unit 4b** (board split +
`OPEN_INDEX.md`).

**Unit 2 (OI-58b) was withdrawn** — see below. It is not deferred prose: the
OI-58 entry already prescribes "own reviewed unit", and `gate-input-family.md`
Decision 4 already chose the mechanism.

## Rounds

| Round | Outcome |
|---|---|
| 1 — independent, context-blind (haiku), on the plan | **REJECT.** 1 P1, 2 P2, 2 P3. The P1 demanded evidence for Unit 2's CI-ref premise; checking it *removed* the risk (the real CI log shows `+refs/heads/*:refs/remotes/origin/*`). One P2 was refuted, one adopted (the `MERGE_HEAD` skip). |
| 2 — independent, context-blind (sonnet), on the hardened plan | **REJECT, P0.** Unit 2 contradicted an already-converged decision AND closed nothing. Withdrawn. |
| B-pass — fresh context-blind (sonnet), on the branch diff | **REJECT → accepted after fixes.** 3 P1, 3 P2, 2 P3. Detail in `docs/reviews/enforcement-infra-bpass.md`. |

## Why this is converged rather than merely green

Three review events, and the through-line of every serious defect is one
sentence: **I cited a source without reading it.**

- `.gitignore:129` cited as evidence for changing that exact line, while the
  four-line comment directly above it recorded a deliberate decision from the
  day before not to make that change.
- OI-58's `Fix shape:` never read, in a file I read the same day for a different
  entry — and the mechanism I designed instead didn't work, because branch
  protection covers only `main`.
- **OI-68's "SCARS — read before re-attempting"** never read, in the file I was
  actively splitting, so I rebuilt its third-generation vocabulary bug verbatim.

Round 1 and round 2 each found material the other missed, which is §4.12.1's
split signal — hence Unit 2 leaving. The B-pass then broke three things two
rounds had passed, which is why `bpass:` is not a formality here.

What makes it converged is that each fix is now **fail-closed and controlled**:
unknown status vocabulary errors instead of vanishing an issue; an unreadable
status line errors instead of silently exempting one; a generated mirror can't
fail a commit for prose it didn't author. 58 tests across three contract files,
each written after executing the payload against the real code.

## Ground truth

Everything load-bearing was re-derived, and four of my own numbers were wrong
(`345`→346 entries; `10`→3 commits citing the malformed ids; `3`→1; the
`Verified: 2026-07-26` count `8`→6). None changed a decision, but all four were
stated as measured when they were not — recorded in the B-pass rather than
quietly corrected.

Verified directly: the split is exhaustive (73 → 26 + 47, 46/47 closed sections
byte-identical against `e4bc9040^`); both generators are idempotent; the CI
retry loop's `set -e` semantics are safe; `setup-deno`'s `cache-hash` input is
real, checked against the action's own `action.yml`.

## Residuals, stated

- **OI-58b stays OPEN** with its recorded fix shape (`github.event.before..after`
  / one-record-one-landing) and the first-time spoof `blocked_on_user`.
- **`clean-orphan-media` git ≠ deployed** by one import line. The live function
  works; a redeploy is optional and needs its own explicit go per §4.3.
- **`closes-oi` laundering** by delete-and-renumber in one commit — deliberate
  only, conspicuous in a diff, out of scope for this gate.
- **71 Edge Function files still import via `https://` URLs** vs 24 on
  `npm:`/`jsr:`. This batch buys resilience (cache + retry), not conversion; a
  71-file specifier sweep is a different change with a different risk profile.
