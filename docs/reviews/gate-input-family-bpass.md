---
reviewed_at: 2026-07-27
branch: gate-input-family
staged_against: 88eeffa38f37
blast_radius: platform
reviewer: fresh context-blind sonnet subagent (/code-review B-pass)
lens_set: [fail_open_paths, blast_radius_mismatch, self_consistency, claim_accuracy, test_vacuity, gate_wiring]
findings_count: 4
verdict: accepted
---

# B-pass — gate-input-family (post-split)

**4 findings: 3 P2, 1 P3. All four fixed.** This pass mattered more than a formality:
the split happened *after* round 2, so no prior round had seen the code that actually
ships. It found one real fail-open the three earlier rounds missed, and caught me
reporting a fix as landed when it had not.

## P2 — two `_git` sites still failed open, including one I had claimed was fixed

`check_plan_review_record_exists.dart:365` (`rev-list --first-parent`) and `:380`
(`log -1 --format=%P`) both used `_git` (empty-string-on-failure) against this file's
own stated invariant, *"fail loud whenever git cannot answer"*.

The consequences differ in severity and the second is the worse one:

- an errored `rev-list` yielded an empty list and printed `PASS: nothing landed`
- an errored `log --format=%P` yielded no parents, so `parents.length >= 2` was false
  and a genuine **merge** was silently filed as a direct commit — which, after the
  OI-58a scope cut, means it is never checked for a record at all

**The part worth recording:** I had already reported the `rev-list` site as fixed in an
earlier turn. It was not — the edit silently failed to apply and I did not re-verify.
That is `feedback_mistake_unverified_done_claims`, the most recurrent class in this
repo, occurring inside the batch whose entire subject is gates that report the wrong
answer. Both sites now use `_gitOrNull` and fail loud.

Neither has a crafted trigger — both operate on revisions confirmed to exist moments
earlier — which is precisely why three rounds hunting *reachable* bypasses walked past
them. Worth remembering: "no attacker path" is not the same as "correct".

## P2 — `writers:` cited symbols this batch deleted, at lines that cannot exist

Diagnose `a7f3d1`'s `writers:` field pointed at `versionBumpAllowedPaths:231`,
`isMechanicalVersionBump:241` and `requiresFreshRecord:265` in a **237-line** file where
all three had been removed by the split. `:265` is past EOF; `:231` is now
`allCommitsAuthoredByDependabot`. The doc's own body said correctly that they "were
built here and removed again" — the frontmatter contradicted it. §4.5 treats `writers:`
as the SoT pointer, so this would have sent the next reader chasing ghosts. Fixed.

## P2 — the control count doubled the real number

`regression_test_planned:` claimed "16 controls … fourteen are revert-controls, two are
DESIGN-LOCK". Actual: **8** tests, **7** revert-controls, **1** DESIGN-LOCK. The field
still counted the OI-58 tests removed by the split, and contradicted the same document's
body two sections later. Fixed to 8/7/1 plus the 3 OI-72 controls in their own file.

## P3 — `stagedPaths()` fail-open (pre-existing, fixed anyway)

`check_code_review_pass_exists.dart:95-103` returned `[]` when
`git diff --cached --name-only` failed, which the caller read as "no staged changes" and
exited 0 — waving a catastrophic-tier commit through. The reviewer correctly identified
this as **pre-existing and outside the diff**. Fixed regardless: it is the same class
OI-72 fixes twice further down the same file, it sits a few lines from its own cure, and
leaving a known fail-open in a file I am already editing would be a deferral by another
name (§4.2).

## Lenses that returned clean, with evidence

- **Standard 5 (Hive / `functions.invoke` / `unawaited` / secrets):** grep over the
  staged diff returns only the two `{ tier: 2_hive, status: not_applicable }` checklist
  lines in the diagnose-docs. No Hive box, no `functions.invoke`, no `unawaited`, no
  credential-shaped literal. This diff is CI/gate tooling only.
- **blast_radius_mismatch:** all four touched scripts plus `.github/workflows/test.yml`
  are registered `platform`; the record exists with `review_rounds: 3`,
  `ground_truth_verified: true`, `verdict: converged`. Gate 40 PASS, 12/12 terminal.
- **self_consistency:** every surviving mention of `isMechanicalVersionBump`,
  `requiresFreshRecord`, `versionBumpAllowedPaths`, `_branchLandedBefore`,
  `landedInRange`, `rangePaths`, "one-record-one-landing" and "version-bump exemption"
  is either the removal NOTE, forward-looking `reopen_when:` prose, or the OI-58 entry
  in `open_issues.md`. Nothing live still assumes they ship.
- **claim_accuracy:** all 13 ship-dark `build_commit`/`build_date` entries re-derived
  byte-for-byte; both flip-order quotes confirmed in source; every OI-48 and OI-73 line
  citation resolves; `a3ff9571` re-confirmed not a commit; the 5-of-60 and 182-merge
  measurements reproduced exactly.
- **test_vacuity:** 8 controls traced against pre-fix behaviour — 7 discriminate, the
  1 self-labelled DESIGN-LOCK correctly does not. The OI-72 "rejected verdict" control
  asserts the message text, not just the exit code, because the pre-fix gate also exits
  1 there for a different reason.
- **gate_wiring:** `check_gate_scripts_wired.dart` PASS (90 scripts covered); the gate
  is on both skip-lists and invoked for real only in the `fetch-depth: 0` job; full
  suite green (101 after these fixes).
