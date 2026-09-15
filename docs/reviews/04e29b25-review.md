---
reviewed_at: 2026-08-13T07:40:00+05:30
staged_against: 04e29b25
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh, context-blind)
lens_set: [renumber_correctness, duplicate_detector_correctness, test_can_actually_fail, union_completeness, gate_record_validity, honesty_of_partial_close]
findings_count: 5
verdict: accepted
---

# Code Review — 04e29b25 (PR #22 merge resolution: OI renumber + duplicate detector)

## Scope

`git diff origin/main...HEAD` at `origin/main` = `4894539f`. Three commits:
`babea1a4` (renumber + detector + diagnose-doc), `35a5e094` and `04e29b25` (two
catch-up merges of `origin/main`, which moved twice mid-flight).

The reviewer was context-blind and given the change's four claims as *hypotheses*, not
as facts. Every finding below was reproduced first-hand by me before acceptance.

## Finding 1 — P2 — dangling bare-number citations that now resolve to main's issues

- **file:line:** `docs/audit/post38-auth-fixes.closure.yaml:289`, `docs/reviews/d4a8de00-review.md:65`
- **claim:** The renumber rewrote only tokens prefixed `OI-`. Both files contain a clause
  mixing a renumbered id with bare numbers from the same set — `"Renumbered to
  OI-111/100/101"` and `"OI-99 → OI-111 (100/101 verified free)"`. Post-merge, `OI-100`
  and `OI-101` are **main's own** issues (`prior_art_checked:`, Gate 41). A reader tracing
  those numbers lands on unrelated work.
- **verification:** `grep -n "100/101" docs/audit/post38-auth-fixes.closure.yaml docs/reviews/d4a8de00-review.md`
  → the two lines above. Root cause is mine: the renumber used `sed 's/OI-<n>\b/OI-<m>/g'`,
  which by construction cannot see a bare number after a slash.
- **resolution:** FIXED — both now read `109/110`. This sat in the exact domain the change
  exists to protect (citation integrity), which is why it is worth fixing despite no gate
  reading it.
- **status:** fixed

## Finding 2 — P2 — board and diagnose-doc disagreed on the ordinal for the SAME event

- **file:line:** `docs/audit/open_issues.md:2420` ("a THIRD and largest") vs
  `docs/diagnoses/…-b7e3d1.md:110,119` ("FOURTH recorded instance", "this instance is the fourth")
- **claim:** Self-contradiction between two documents describing one event. Cause: while
  verifying the merge I found a third instance that hit a *different session in parallel*
  and updated the diagnose-doc's `recurrence:`, but not the board entry.
- **verification:** `grep -n "a THIRD and largest" docs/audit/open_issues.md` and
  `grep -n "FOURTH recorded" docs/diagnoses/…-b7e3d1.md` — both present simultaneously.
- **resolution:** FIXED — board now says FOURTH and cites
  `docs/plan-reviews/claude-commit-merge-push-process-aae061.md:56-58` for the parallel
  instance, while noting its own "Measured" bullet covers only the two on this branch.
- **status:** fixed

## Finding 3 — P2 — `related_bugs: []` empty despite a densely-populated `recurrence:`

- **file:line:** `docs/diagnoses/…-b7e3d1.md:108`
- **claim:** §4.1.5 asks for prior instances in BOTH fields on a recurrence. `recurrence:`
  names three; `related_bugs:` was `[]`.
- **verification:** read both fields.
- **resolution:** FIXED — not by inventing ids (none exist: the three prior collisions were
  renumber-and-move-on with no diagnose-doc), but by saying so explicitly. An empty list
  reads as "no prior art was looked for", which is the opposite of what happened.
- **status:** fixed

## Finding 4 — P2 (I treat it as the most important) — a test that could not fail for the property it named

- **file:line:** `test/contracts/oi_index_test.dart`, "reports every duplicated id, in numeric order"
- **claim:** The fixture used `OI-100..105` — six ids of **identical digit width**, where
  lexical and numeric order coincide. Its own `reason:` string said *"lexical would put
  OI-100 last"*, which is false for that data. The reviewer substituted a lexical
  `.sort()` and **all 25 tests still passed**.
- **verification:** I reproduced it by inspection (the fixture is literally
  `[100,101,102,103,104,105]`), then fixed and re-proved by execution:
  clean → `+26 All tests passed`; lexical-sort mutation → `+25 -1`, failing exactly on
  `numeric order — a lexical sort puts OI-10 first`. Restored, md5 byte-identical.
- **resolution:** FIXED — fixture now spans digit widths (`[9, 10, 100, 105]`), where
  lexical order differs at BOTH ends, so `first` and `last` each discriminate. The
  six-id real-world shape is preserved as its own separate test so nothing is lost.
- **note:** The reviewer rated this P2 because detection correctness is unaffected — the
  `.where(value > 1)` filter runs before the sort, so every real duplicate is still caught
  and the gate still exits 1; only stderr ordering would change. That is a fair call. I
  am recording it as the batch's most important finding anyway, because a test asserting a
  property it cannot detect is precisely the Gate-44 class this repo's rule 24 exists to
  make impossible — and it appeared in the very commit whose selling point is
  mutation-proof discipline.
- **status:** fixed

## Finding 5 — P2 — plan-review record's narrative frozen at slice 0

- **file:line:** `docs/plan-reviews/post38-auth-fixes.md`
- **claim:** `reviewed_at: 2026-08-09` and the prose scope to "slice 0 only" (`d4a8de00`),
  while `5fd5b337` and `babea1a4`+merges landed afterwards on the same branch with no
  mention. The gate passes regardless — it validates frontmatter fields, never narrative
  completeness — so "converged" would have implied coverage the file does not describe.
- **verification:** `git log --format='%ad %s' --date=iso` on each commit vs the record's
  section headers.
- **resolution:** FIXED — `bpass_review:` re-pointed at THIS file, `reviewed_at` bumped,
  and a scope section added naming the later commits and the ×2 rounds they received.
- **status:** fixed

## Lenses that came back clean, with evidence

- **renumber_correctness (header level):** the synthetic sort fixture `OI-9/OI-10/OI-100`
  in the pre-existing `parseOpenIssues` group is INTACT — `git show babea1a4 --
  test/contracts/oi_index_test.dart` shows that block was purely additive. Main's own
  OI-100..108 are untouched at both revisions, verified by grepping headers on
  `origin/main` and `HEAD` and comparing titles.
- **duplicate_detector_correctness:** no false negative found. CLOSED-vs-OPEN handled by
  construction (scans headers, not `parseOpenIssues`). CRLF normalised before the split.
  `### OI-x` sub-headers would not match `_sectionRe`, but zero live instances exist
  (`git grep -n "^### .*OI-"` → empty) and that behaviour is inherited from the
  pre-existing regex, not introduced here. No false positive: no `## OI-` sits inside a
  fenced code block (awk fence-tracking scan, and a sanity count confirmed the scan was
  actually tracking fences rather than vacuously finding nothing).
- **test_can_actually_fail:** both mutation claims in `babea1a4`'s message reproduce
  exactly — `return const []` → 21/4; rebuilt over `parseOpenIssues` → 24/1 with the ONE
  failure being the OPEN-vs-CLOSED case. Finding 4 is the gap this lens found.
- **union_completeness:** proven mechanically for BOTH merges, not argued. Merge 1
  (`35a5e094`): parent union 60 ids, result 60, zero dropped, zero invented. Merge 2
  (`04e29b25`): union 62, result 62, same. `closed_issues.md` byte-identical across all
  five relevant revisions. The reviewer additionally replayed both merges with
  `git merge-tree --write-tree` and confirmed the conflict sets independently: 2 conflicts
  in merge 1, 1 in merge 2, all in GENERATED files, with `open_issues.md` auto-merging
  cleanly both times despite 60-90 files differing between parents.
- **gate_record_validity:** tier independently recomputed as `platform`
  (`blast_radius_from_diff.dart` on the branch diff). Every `_validateRecord` requirement
  enumerated and satisfied: branch match, `review_rounds: 2` ≥ 2, `ground_truth_verified`,
  `verdict: converged`, `bpass: accepted` (required at ≥platform), hermes not required
  (tier ≠ catastrophic), and the referenced review file exists and contains
  `verdict: accepted`.
- **secrets_in_tree:** no credential-shaped literals in the diff.

## On the honesty question — is the partial close of OI-112 honest?

The reviewer judged the LANDING-vs-MINT-TIME split **honest, not overclaiming**, and went
further than asked to test it: worried that §4.12.3 says "a `--no-ff` merge skips the local
pre-commit hook entirely" — which would undercut "cannot LAND" — it built a throwaway repo
and ran a clean `--no-ff` merge. The hook **did** fire (git 2.53.0), and `safe_merge.sh`
passes no `--no-verify`. So the caveat does not apply to this gate.

It also flagged, correctly, that there is **no CI-side backstop**: `build_oi_index.dart` is
not a `check_*.dart`, so it sits outside CI's `audit-gates` loop, and CI's `flutter test`
exercises only the synthetic fixtures, never the real board. Detection therefore depends on
the local hook being installed. That is the same trust model as every other pre-commit gate
here, not a special weakness of this fix — but it is a real limit on the word "cannot", and
it is recorded rather than glossed.

## Triage

Five findings, all P2, all fixed. Nothing found breaks detection correctness, causes a
false negative on the real board, or lets a gate wrongly pass corrupt state.

**verdict: accepted**
