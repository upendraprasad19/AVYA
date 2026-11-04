

## OI-459 — safe_commit.sh and land_pr.sh do not pin TZ=Asia/Kolkata, so a merge commit on the UTC VPS fails the pre-commit regression catalog

- **Status**: CLOSED · 2026-11-04 · branch `tz-pin-catalog` · diagnose `c44dfc` · the commit carrying `closes-oi: OI-459`
- **Blocked on**: — (resolved)
- **Verified**: 2026-11-03 - observed while landing PR #204 (OI-450): `land_pr.sh` stopped at the pre-commit regression catalog on a merge commit (6 tests); the same files passed with `TZ=Asia/Kolkata` and failed without it. `grep -n 'TZ\|Kolkata' scripts/safe_commit.sh scripts/land_pr.sh` finds nothing on 2026-11-04.
- **Identified**: 2026-11-04 · filed via mint_oi.sh from branch `tz-pin-safe-commit-oi`

**What.** The VPS runs UTC and CI pins IST (CLAUDE.md section 0). The pre-commit regression catalog runs date-sensitive tests on a merge commit, so `sh scripts/safe_commit.sh ...` or `sh scripts/land_pr.sh <pr>` run without `TZ=Asia/Kolkata` fails there, and the failure looks like a flaky test. During OI-450 it cost one failed landing and a wrong "load flake" guess; the workaround was `TZ=Asia/Kolkata sh scripts/safe_commit.sh ...`, with the hook left on. A rerun of `land_pr.sh` while MERGE_HEAD existed was also refused, so the staged merge had to be concluded through `safe_commit.sh` first.

**Done when.** The scripts that run the catalog (`scripts/safe_commit.sh`, `scripts/land_pr.sh`, or the shared pre-commit entry they call) export `TZ=Asia/Kolkata` for the catalog run, with a test that fails without it (mutate and run it), and a merge commit on the UTC VPS passes the catalog with no manual `TZ`.

**Residual moved.** The test (f) tap-guard residual that was recorded here is now OI-463 (OPEN, parked until a `lib/` seam for the card is wanted).

**CLOSED 2026-11-04.** Fixed at the spawn site, not in the two wrappers: `catalogChildEnvironment` in `scripts/regression_catalog_lib.dart` applies the canonical scrub and pins `TZ=Asia/Kolkata`, and `scripts/check_regression_catalog.dart` passes it to `flutter test`. The pre-commit hook runs the walk for every way of making a merge commit (`safe_commit.sh`, `land_pr.sh`, `safe_merge.sh`, a plain `git merge`), so a wrapper-level export would have covered only two of them. The failure is time-of-day dependent: UTC and IST name different dates from 18:30 to 24:00 UTC, so the walk passes in the VPS morning (reproduced green at 06:35 UTC with `TZ` unset) and fails in the evening. Reproduced deterministically with `TZ=Etc/GMT+12` (exit 1 before the fix, exit 0 after, 59 tests green). Four mutants all reddened the new tests (3, 1, 1, 3 red). Regression tests: `test/scripts/regression_catalog_lib_test.dart`. Diagnose `docs/diagnoses/2026-11-04-catalog-child-tz-unpinned-c44dfc.md`.

