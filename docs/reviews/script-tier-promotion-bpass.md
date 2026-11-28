---
reviewed_at: 2026-07-27
branch: script-tier-promotion
blast_radius: platform
reviewer: two independent context-blind agents (adversarial bypass lens; completeness/judgement lens)
lens_set: [bypass_surface, registry_ordering, test_vacuity, set_completeness, second_order_cost, doc_factual_accuracy]
findings_count: 14
verdict: accepted
---

# B-pass — script-tier-promotion

Two reviewers ran in parallel on the diff as first staged (five promotions). Between
them they found a **sixth omission**, a **numeric error I had already quoted to the
founder**, and a design flaw in the promotion itself. All material findings are fixed
in this same commit.

## The finding that changed the batch

**The set was incomplete for the third consecutive time, by the same mechanism.**

`scripts/setup-hooks.sh:38-41` installs four hook sources in four consecutive lines.
I promoted two and left `commit-msg.sh` at feature — a hard-fail hook, **zero tests**,
2 lifetime commits, the same profile as `pre-push.sh` and `safe_commit.sh` which I
*did* promote. Verified independently: `commit-msg.sh` → `Blast-radius: feature`,
`grep -rln 'commit-msg' test/` → 0.

Worse in principle: I promoted the §4.2 no-deferrals chain **in full** while leaving
the parallel **rule-22 chain** (`validate_diagnose_doc.dart` + `_lib` +
`check_bugfix_commits_have_diagnose.dart`) entirely at feature. Two invariants of
identical standing, opposite treatment, no stated reason.

**Fixed:** set expanded 5 → 10 (founder-ratified), and — the part that matters — the
git-hook half is now **derived from `setup-hooks.sh`** rather than hand-typed. Add a
fifth hook and the test fails until its tier is decided. Verified by negative control:
removing `commit-msg.sh`'s rule trips **both** its own assertion and the derived one,
independently.

## The number I had given the founder

**P2-2 — the cost basis was understated ~2× and the numerator double-counted.**
I reported "12 of 1366 commits, ~3 review events per quarter". The per-file counts are
right, but two commits touch more than one file, so the real figure is **10 distinct
commits across 6 distinct days in a 4.1-month repo ≈ 4–5 review events per quarter**.

Recomputed myself before accepting. The conclusion survives (well under 1%), but the
figure was the basis for a founder decision and is corrected in the diagnose-doc and
the registry comment.

## The design flaw the second reviewer surfaced

Promoting `check_no_deferral_euphemism.dart` means adding one banned phrase to its list
would cost two review rounds plus a B-pass. That does not make the gate safer — it makes
it **ossify** while §4.2 violations invent the next phrasing. The reviewer cited live
evidence of that decay in this very repo: a sibling gate has sat `--warn-only` for weeks
against a documented 24-hour window.

**Fixed (founder chose this option):** the phrase list moved to
`docs/deferral_euphemisms.yaml` at **feature** tier. Logic stays platform; data stays
cheap. The loader **fails closed** — missing file → exit 1, empty list → exit 1 — so a
feature-tier data file cannot quietly disable a hard-fail gate. Exit codes read directly,
not through a pipe.

## Every other finding, and what happened to it

| # | Finding | Action |
|---|---|---|
| P2-1 | Diagnose-doc cited `line: 101` (a pre-existing rule); the correction to `124` was **unstaged** and would not have committed | Staged; verified |
| P2-3 | The test re-implements the glob engine — faithful today (0 diffs over 83 globs × 2754 paths) but not drift-proof | Added a **real-classifier parity** test that shells out to the actual binary |
| P2-4 | Tier engines read the registry from the **merged tree**, so a commit deleting its own protecting rule is classified by the post-change registry | **Not fixed** — needs its own review. Recorded as **OI-70** and named in the diagnose-doc's residual section rather than left implicit |
| P3-1 | "local-only with no CI backstop" is literally wrong — it runs in CI, vacuously | Wording corrected |
| P3-2 | "zero behavioural coverage" overstated for the `safe_*` wrappers — their *filenames* are asserted, their logic is not | Qualified in both registry comment and doc |
| P3-3 | Sweep attribution wrong — `pre-commit.sh` was promoted by `d947743d` (2026-07-26), not the 2026-07-19 sweep | Verified via `git log -S`; corrected |
| P3-4 | `sot_registry_entry: blast_radius_registry_coverage` cited by two docs, **0 hits** in the registry | Entry written, with writer/readers and the residual documented |
| P3-5 | `review-gate-tier-gap-bpass.md` still said these files "remain feature tier" | Marked CLOSED by `a3d7b1` |
| P3-6 | Branch behind main | Rebased onto `origin/main` before continuing |
| — | Declined candidates (`prepare-commit-msg.sh`, `setup-hooks.sh`, three non-enforcement scripts) | Recorded **in the registry** with reasons, so the next sweep need not re-derive them |

## Clean on independent verification

- Registry rules sit above both the `scripts/**` and `docs/**` catch-alls; no earlier rule wins first.
- No collateral breakage: nothing asserts these paths are `feature`; `check_blast_radius_coverage.dart` passes; nothing auto-writes the promoted files.
- No circularity in `pre-push.sh` — it classifies via a subprocess; `run_full_suite` never re-enters the hook.
- The `--warn-only` claim in the CI-excludes-golden-tests argument holds (`test.yml:61`).

## Residual, stated plainly

**OI-70 is open and this batch does not close it.** The registry still grades its own
homework at merge time. Everything else here is closed in-commit.
