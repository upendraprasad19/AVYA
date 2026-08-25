---
reviewed_at: 2026-08-25T12:40:00+05:30
staged_against: e2e-timeout-convention @ 0a7335e1 (+ the working-tree fix reviewed alongside it)
blast_radius: platform
reviewer: claude-sonnet-via-agent (context-blind, no conversation context)
review_type: self-consistency + ground-truth audit (§4.3 — docs/process-only change)
findings_count: 5
verdict: accepted
---

# Review — e2e-timeout-convention (platform, docs/process-only)

## What was reviewed and how

The branch is **one line** in root `CLAUDE.md` (`git diff --stat cb778dbd^1 cb778dbd` →
`CLAUDE.md | 1 +`): a §4.9 pitfalls row saying a test file that spawns subprocesses needs a
file-level `@Timeout(Duration(minutes: N))` + `library;` annotation.

Per §4.3, a docs/process-only ≥account change *"takes a self-consistency review of the wording
instead of an adversarial bug-hunt."* So this pass is a wording review plus a ground-truth audit of
every factual claim the row makes — not a code bug-hunt, and it is labelled as such rather than
dressed up as one.

The reviewer was a fresh agent with no conversation context, given the diff, told to find errors
rather than approve, and required to report the actual measured value for each claim rather than
confirm it.

## Findings

### Finding 1 — P2 — the row's central claim was FALSE — **fixed**
*"EVERY e2e under `test/scripts/` already has one."* Enumerating all 11 `*e2e*_test.dart` files
found `pre_merge_commit_e2e_test.dart` had **no annotation**. That file is the archetype of the
hazard — its own header: *"Executes the REAL scripts/pre-merge-commit.sh as a REAL git hook, in a
real throwaway repo."*
**Fix:** added `@Timeout(Duration(minutes: 5))` + `library;`, matching its closest analog
`plan_review_record_gate_e2e_test.dart` (same one-hook-per-test shape). Closes the gap AND makes
the row's claim true. File passes 3/3.

### Finding 2 — P2 — the row named the wrong class — **fixed**
Titled *"A new **e2e** test file…"*, but the class is "spawns a subprocess". **Nine files under
`test/scripts/` with no `e2e` in the name call `Process.run`/`Process.start`, and all nine already
carry `@Timeout`** — the repo was already applying the wider convention while the documentation
described a narrower one, so a future author of `foo_lib_test.dart` could reasonably have concluded
it did not apply.
**Fix:** retitled; scope corrected to name the real class, including the indirect-spawn case
(`pre_merge_commit_e2e` spawns none itself; its `git merge` invokes a hook that resolves dart via
`_dart_bin.sh`).

### Finding 3 — P3 — Source column broke the table's convention — **fixed**
All five sibling rows cite a document; this one carried a bare date plus inline narrative. Worse,
`docs/playbook/common-pitfalls.md` — the file the siblings point to — had **zero** mentions of the
convention.
**Fix:** wrote the actual entry in `common-pitfalls.md` and cited it. (Citing a doc that does not
cover the topic would have been a phantom citation — *worse than citing none, because it reads as
coverage*.) Gate 26 PASS afterward.

### Finding 4 — P2 — a per-file convention is the weaker fix — **recorded, not fixed**
Nothing gates this, and the class has recurred **4×**: `aac52fb6` records three consecutive merge
attempts failing on it (9 → 3 → 1 failures), then it recurred on 2026-08-25. `dart_test.yaml`
exists and configures only the `golden` tag, so a repo-wide `timeout:` there — or `--timeout` on
the `flutter test` invocations in `scripts/pre-push.sh` and `.github/workflows/test.yml` — would
close the class in one place. A `check_*.dart` gate asserting "spawns a subprocess ⇒ has
`@Timeout`" is the other option.
**Not fixed here, with the reason:** changing the global test timeout alters every test and both CI
jobs, and a new gate must ship mutation-proven with a rule-24 ledger entry. Neither belongs inside
a record written to unblock a push on a one-line doc commit. Both are named in the row's own Source
cell and in the new `common-pitfalls.md` entry — in the text the next author reads at the moment
they would need it.

### Finding 5 — P3 — no diagnose-doc for the red main — **noted**
The prior instance of this identical class (`aac52fb6`) cited `closes-diagnose: 4f2a9e`. This one
shipped under `test(` and `docs(` prefixes, which rule 22's `^(fix|bug|regression)` regex does not
match — so the requirement was sidestepped by prefix choice rather than by judgement. Recorded as
an observation about the rule's reach, not a demand on this branch.

## Claims verified accurate

- `gate_index_e2e` = 3 ✓ · `retire_worktree_e2e` = 4 ✓ · the two 2026-08-25 hook/gate files
  (`batch_close_hook_e2e`, `skill_tuning_history_e2e`) = 6 ✓ — each read directly.
- CLAUDE.md §0's *"3.4–10.5 s"* wrapper figure — quoted word-for-word ✓.
- The 30 s default — confirmed in `package:test_api` `timeout.dart`: *"By default, a test will time
  out after 30 seconds"* ✓.
- *"4897/-2 across 9 unpushed commits"* — corroborated verbatim in the commit messages of
  `0a99a0b7` and `0a7335e1`. **Self-reported-but-consistent; no CI log or diagnose-doc
  independently confirms it**, and this is stated rather than implied.
- `dart_test.yaml` read in full: `golden` tag only, no timeout key — so Finding 4's proposal is
  available and unused, not already present.
- No internal contradiction with §0 or with CI's job-level `timeout-minutes:` (a different
  mechanism — wall-clock job caps, not per-test timeouts).

## Verdict

**accepted.** The row's advice is correct and worth keeping. Three defects in how it was stated are
fixed; the two structural improvements it does not make are named where they will be read rather
than silently dropped.
