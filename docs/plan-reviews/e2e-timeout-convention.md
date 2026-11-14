---
branch: e2e-timeout-convention
date: 2026-08-25
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/e2e-timeout-convention-bpass.md
---

# Plan-review record — e2e-timeout-convention (platform)

Keystone record for the §4.12 merge gate. Platform tier because the change touches root
`CLAUDE.md`, which is path-pinned platform in `docs/blast_radius.yaml`.

## What the branch is

**One line.** `git diff --stat cb778dbd^1 cb778dbd` → `CLAUDE.md | 1 +`. It adds a row to the §4.9
"Common process pitfalls" table: give a test file that spawns subprocesses a file-level
`@Timeout(Duration(minutes: N))` + `library;` annotation, because such a file can pass targeted and
time out in the full suite.

## Review type — and why this is not an adversarial bug-hunt

Per §4.3: *"Docs/process-only ≥account changes — e.g. CLAUDE.md edits — take a self-consistency
review of the wording instead of an adversarial bug-hunt."* This is docs-only, so the review is a
self-consistency check of the wording plus a ground-truth audit of every factual claim it makes.

⚠ **Written after the merge, not before it.** `cb778dbd` landed on local `main` without this record,
which is what the keystone gate caught. The review below was performed in full at that point — two
rounds, both against the actual repo — and is recorded honestly as retrospective rather than
back-dated. It is a real review, not a rubber stamp: it found and fixed three defects.

## Round 1 — ground-truth audit

Every factual claim in the new row was checked against the repo.

**FINDING (P2), fixed — the row's central claim was FALSE.** It asserted *"EVERY e2e under
`test/scripts/` already has one."* Enumerating all 11 `*e2e*_test.dart` files showed
`pre_merge_commit_e2e_test.dart` had **no annotation**. Worse, that file is the archetype of the
hazard the row describes: its own header says it *"Executes the REAL scripts/pre-merge-commit.sh as
a REAL git hook, in a real throwaway repo."* So the one exception was a live instance of the bug.

Fixed by adding `@Timeout(Duration(minutes: 5))` + `library;` — closing the gap AND making the
row's claim true. `minutes: 5` matches its closest analog, `plan_review_record_gate_e2e_test.dart`
(same one-hook-invocation-per-test shape). The file still passes (3/3).

**Verified accurate:** `gate_index_e2e` = 3 ✓, `retire_worktree_e2e` = 4 ✓, "the two 2026-08-25
hook/gate files" = `batch_close_hook_e2e` + `skill_tuning_history_e2e`, both 6 ✓. The §0 quote
"3.4–10.5 s for a no-op" is word-for-word ✓. The 30 s default is real (`package:test_api`
`timeout.dart`: *"By default, a test will time out after 30 seconds"*) ✓. The "4897/-2 across 9
unpushed commits" figure is corroborated verbatim in the messages of `0a99a0b7` and `0a7335e1` —
self-reported-but-consistent; no CI log or diagnose-doc independently confirms it, and this record
says so rather than implying external corroboration.

## Round 2 — independent, context-blind

A fresh reviewer with no knowledge of round 1. Five findings; three fixed, two recorded.

**FINDING (P2), fixed — the row named the wrong class.** Titled *"A new **e2e** test file…"*, but
the bug class is "spawns a subprocess", not "is named `*_e2e_*`". Verified: **9 files under
`test/scripts/` with no `e2e` in the name call `Process.run`/`Process.start`, and all 9 already
carry `@Timeout`** — so the repo was already applying the wider convention while the documentation
described a narrower one. A future author of `foo_lib_test.dart` could reasonably have concluded
the row did not apply. Retitled and the scope corrected, including the indirect-spawn case
(`pre_merge_commit_e2e` spawns none itself; its `git merge` invokes a hook that resolves dart via
`_dart_bin.sh`).

**FINDING (P3), fixed — the Source column broke the table's convention.** All five sibling rows
cite a document; this one carried a bare date plus inline narrative, and
`docs/playbook/common-pitfalls.md` — the file the table's siblings point to — had **zero** mentions
of the convention. Fixed by writing the actual entry there and citing it. (Citing a doc that does
not cover the topic would have been a phantom citation, which this repo already calls *worse than
citing none, because it reads as coverage*.)

**FINDING (P2), RECORDED NOT FIXED — a per-file convention is the weaker fix, and the class has
recurred 4×.** `aac52fb6` records three consecutive merge attempts failing on this same defect
(9 → 3 → 1 failures); it then recurred on 2026-08-25. Nothing gates it. `dart_test.yaml` exists and
configures only the `golden` tag, so a repo-wide `timeout:` there — or `--timeout` on the two
`flutter test` invocations — would close the class in one place; a `check_*.dart` gate asserting
"spawns a subprocess ⇒ has `@Timeout`" is the other option.

**Deliberately not done here, with the reason.** Changing the global test timeout alters the
behaviour of every test in the repo and both CI jobs; adding a gate is new `check_*.dart`
engineering that rule 24 requires to ship mutation-proven with a ledger entry. Neither belongs
inside a record written to unblock a push on someone else's one-line doc commit. Both are named in
the row's own Source cell and in the new `common-pitfalls.md` entry, in the text a future author
reads at the moment they would need it — not silently dropped.

**FINDING (P3), noted — no diagnose-doc for the red main.** The prior instance of this identical
class (`aac52fb6`) cited `closes-diagnose: 4f2a9e`. This one shipped under `test(` and `docs(`
prefixes, which rule 22's `^(fix|bug|regression)` regex does not match, so the requirement was
sidestepped by prefix choice rather than by judgement. Recorded as an observation about the rule's
reach, not as a demand on this branch.

## Ground truth verified

- All 11 `*e2e*_test.dart` under `test/scripts/` now annotated — enumerated individually, not sampled.
- All 9 non-`e2e` subprocess-spawning files under `test/scripts/` already annotated.
- `dart_test.yaml` read in full: `golden` tag only, no timeout key.
- `package:test_api` `timeout.dart` read for the 30 s default.
- CLAUDE.md §0 quoted directly for the 3.4–10.5 s figure.
- Gate 26 (`check_claude_md_citations.dart`) PASS after the edits — all §N citations resolve across
  16 CLAUDE.md/AGENTS.md files and 1685 source files.
- `flutter test test/scripts/pre_merge_commit_e2e_test.dart` → 3/3 with the new annotation.

## Verdict

`converged`. The row's advice is correct and worth having; three defects in how it was stated are
fixed, and the two structural improvements it does not make are named where they will be read.
