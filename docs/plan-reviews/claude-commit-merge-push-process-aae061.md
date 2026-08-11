---
branch: claude/commit-merge-push-process-aae061
date: 2026-08-11
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/commit-merge-push-process-bpass.md
---

# Plan-review record — commit-time gate cost split (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

`bpass: accepted` — the B-pass ran after round 2 (this field was held at `pending` until it
actually existed). It returned **2 findings, both fixed in-batch, 0 false alarms**:

- **P1 / guard_without_its_mirror** — the pre-commit half was pinned only by a source grep, and
  an indirect invocation (`_sub="ana""lyze"; flutter "$_sub"`) ran analyze on every commit with
  the suite fully green. Closed by a new RUNTIME test,
  `test/scripts/pre_commit_lean_path_e2e_test.dart`, which observes actual invocation and so
  holds against any spelling. Mutation-proven both ways: the indirect call reddens the runtime
  test while the grep stays green.
- **P2 / blast_radius_mismatch** — platform tier's `requires:` includes `feature_flag`, which
  this batch does not satisfy. Resolved as a documented, founder-ratified deviation (ADR-0018
  gained a section stating it plainly), NOT as a compliance claim.

## Scope

Move `flutter analyze` + `flutter test test/contracts/` off `scripts/pre-commit.sh`; add an
unconditional `flutter analyze` to `scripts/pre-push.sh` above every early exit. The
blast-radius-tiered full-suite rule at pre-push is unchanged. Old behaviour reachable via
`PRE_COMMIT_LEGACY=1`; `PRE_COMMIT_FULL=1` keeps its meaning. Decision + alternatives: ADR-0018.

Platform tier: `scripts/pre-commit.sh`, `scripts/pre-push.sh` and `CLAUDE.md` are each pinned
platform in `docs/blast_radius.yaml`.

## Round 1 — NOT CONVERGED (4 substantive findings, all upheld)

1. **BLOCKING — the pre-commit pin did not work.** The first
   `hook_gate_placement_test.dart` asserted only that every flutter call fell between the hatch
   `if` and its `fi` — a range that *contains* the `else` body. The reviewer restored both calls
   into the else branch (the most natural way the regression returns) and the suite stayed green.
   Fixed: the else body is now asserted flutter-free directly, with a mirror assertion for the
   rest of the file.
2. **BLOCKING — contested numbers written into CLAUDE.md as settled.** An in-session run measured
   analyze 212s / contracts 521s / total 845s. The reviewer measured a warm analyze at ~18s, and
   **OI-102 — which this session never opened** — carries a board-`Verified` JSON-reporter figure
   of 1114.6s for the contracts subset, same day, 2.1× the 521s. OI-102 is itself open *because*
   in-session timings are contamination-prone. Fixed: every quotation now states the conflict and
   defers to OI-102; 845s is described as a floor. The decision is robust to either figure.
3. **MAJOR — OI-102 left asserting a false "What's wrong".** Fixed: OI-102 → CLOSED (its trigger
   is gone), with its unanswered measurement question carried forward as a well-formed **OI-105**
   rather than dying with it. `OPEN_INDEX.md` regenerated.
4. **MAJOR — "42 branches pushed to origin, none run CI" was wrong on both halves.** 42 is
   `git branch -r` (remote-*tracking* refs, incl. `origin/main` and refs deleted upstream); the
   real count is 29 refs / 28 non-main. And `test.yml` has a `pull_request` trigger, so the 8
   branches with open PRs *do* get CI. Fixed in all five places. The conclusion survives — the
   ~20 PR-less branches genuinely have no remote backstop — which is exactly why analyze is
   unconditional.

Also fixed from round 1: three more live files still asserting pre-commit runs tests
(`test.yml` comment, `analysis_options.yaml`, `integration_test/README.md`); Gate 32's anchor;
an inverted §4.6 compliance claim; hatch precedence (FULL now wins over LEGACY).

## Round 2 — run on the HARDENED state, NOT CONVERGED (3 MAJOR), then fixed

Round 2 confirmed all six round-1 fixes as correct on their own terms, and then found that
**two of the corrections had left the corrected-away version alive elsewhere** — the same class
round 1 existed to fix:

1. **MAJOR — `pre-push.sh` echoed "a branch push runs NO CI"** at the feature-skip, while the
   header three screens up carried the corrected version. The echo is what the operator actually
   reads. Fixed.
2. **MAJOR — ADR-0013 still stated "CI runs the full suite on every push regardless"** as one of
   the two justifications for the whole tiering decision, with no forward pointer. It is the
   document the three corrected passages were quoting. Fixed with an in-place Correction note,
   a Consequences correction, and a See-also entry.
3. **MAJOR — ADR-0018 failed `validate_adr.dart`** (missing `## Status`). Fixed; both ADRs now
   validate.
4. **MINOR, and the sharpest one — the round-1 test hardening was one whitespace character from
   being defeated.** `flutter  analyze` (two spaces) passed green. Fixed: matching is now a
   regex, narrow on the subcommand so an `echo` mentioning "analyze" cannot false-red it.

Also fixed: `check_hooks_installed.dart`'s stale comment + an OI-104 cross-reference; the
477/478/479/480 file-count drift reconciled explicitly; "`scripts/` is feature-tier" corrected
(the hook scripts are platform); ADR-0018's "caught at push" overstatement corrected to say
plainly that at feature tier a failing **test** is not caught until the merge-to-main push;
`unset _v _hatch`.

## Ground truth verified

Every claim below was checked against the repo or live state, not asserted:

- Hook install mechanism: `diff -q` proves `.git/hooks/pre-commit` is byte-identical to the
  script (a `cp`, not a shim), installed into the worktree-**shared** `git-common-dir/hooks`.
- CI triggers: `test.yml` is the only workflow; `push: [main, develop]` + `pull_request`.
  `git ls-remote --heads origin` = 29; `gh pr list --state open` = 8.
- Gate 32's anchor was **already** 0-occurrence at `HEAD` (`git show HEAD:scripts/pre-commit.sh
  | grep -c`), so this batch repairs a pre-existing latent breakage rather than causing one.
- Gate 33's two textual markers intact; `check_gate_scripts_wired` PASS (96 scripts covered).
- Both YAML files still parse identically to HEAD (comment-only edits).
- `build_oi_index.dart` re-run → byte-identical, 38 open.

## Mutation proof

| Mutation | Result |
|---|---|
| Restore both flutter calls into the pre-commit `else` body | **1 test red** (defeated the first version — green) |
| Unguarded `flutter analyze` above the hatch chain | **1 test red** (mirror assertion) |
| Same, double-spaced `flutter  analyze` | **1 test red** (defeated the round-1 fix — green) |
| Move pre-push analyze below the `feature`-tier skip | **3 tests red**; the feature-tier e2e reports `Got: []` |

The feature-tier e2e builds a scratch git repo with a stubbed `dart` to force the tier, because
the first version inherited whatever tier the real branch happened to be — on this `platform`
branch it passed *with* the mutation applied, and in CI the empty-range fail-safe means the
feature path is never exercised at all.

## Convergence

Converged after round 2's corrective pass: the remaining items were ten small, mechanical,
non-interacting fixes with no design change, which is §4.12.1's stated signal that the unit is
**not** too large and does not need splitting. Both rounds agreed the design itself is sound —
neither disputed moving the steps or making analyze unconditional; every finding was about
evidence quality, stale duplicate claims, or a test that did not bite.

## Owed before merge

1. ~~`/code-review` B-pass~~ — **done**, see `bpass_review:` above. 2 findings, both fixed
   in-batch.
2. Commit message must carry `closes-oi: OI-102` (`check_closes_oi_cited.dart` enforces it at
   commit-msg; verified EXIT=1 without it, EXIT=0 with it).
3. ADR must be in the same `git add` set so pre-commit regenerates and stages `docs/adr/INDEX.md`.
4. **After** the merge to `main`: `sh scripts/setup-hooks.sh` from the primary worktree. Until
   then the change is inert — and per OI-104 every gate reports green while the installed hook is
   the old one. Never run it from this branch: the hooks dir is shared by every worktree.
