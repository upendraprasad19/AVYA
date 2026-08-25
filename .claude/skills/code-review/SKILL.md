---
name: code-review
description: Adversarial review pass over the staged diff. Run when blast-radius is ≥ account, or invoke manually. Dispatches a FRESH Sonnet subagent (no conversation context) prompted to find bugs not validate. Writes structured findings to docs/reviews/.
type: process
priority: high
self-evolving: true
---

# Code Review (B-pass) — Fresh-agent Adversarial Pass

> Track 1 of the 2026-05-28 six-industry-gap closure batch. **Per-commit lightweight reviewer.** Different from `/hermes-pass` (per-batch deep cross-lens pass).

## 0. When to invoke

- **Reminder-triggered** by `scripts/pre-commit.sh` — it PRINTS a `NOTE: blast-radius=<tier> (>=account) — run /code-review (B-pass)` nudge when the staged blast-radius is ≥ `account` (per `docs/blast_radius.yaml`). Git hooks **cannot invoke Claude skills**, so this is a printed reminder; run `/code-review` **manually** when you see it. (Corrected lean-workflow batch 2026-06-01 — the prior "auto-triggered" wording described behaviour the hook never had.)
- **Required** for commits with blast-radius `catastrophic` (gate `check_code_review_pass_exists.dart` blocks without an `accepted` verdict)
- **Manual**: `/review` any time, including pre-push and pre-batch-finalization
- **Skip**: commits with blast-radius `feature` (cost > value)

## 1. The contract

This skill produces a structured findings file at `docs/reviews/<staging-hash-or-sha>-review.md`.

### Output format

```markdown
---
reviewed_at: 2026-05-28T14:32:00+05:30
staged_against: <git-sha-or-stage-hash>
blast_radius: <feature|account|platform|catastrophic>
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 3
verdict: pending  # → accepted | rejected (after founder triage)
---

# Code Review — <staging-hash>

## Finding 1 — P0 — writer_reader_drift
- **file:line:** lib/features/auth/foo.dart:142
- **claim:** `getUserProfile()` reads `profile['email']` but `ProfileWriteService.update` writes `profile['user_email']` per writer/reader drift pattern.
- **verification:** `grep -n "profile\\['email'\\]" lib/` to confirm read sites
- **suggested-fix:** rename read to `profile['user_email']` OR migrate writer
- **status:** pending

## Finding 2 — P2 — secrets_in_tree
- **file:line:** lib/foo.dart:23
- **claim:** Hardcoded API key suffix visible
- **verification:** `git check-ignore -v lib/foo.dart`
- **status:** pending

[…]

## Founder triage notes
<filled in by founder during triage>
```

## 2. Lens set (6 lenses, fast)

Each lens has a focused prompt the dispatched agent runs against the staged diff:

1. **writer_reader_drift** — for every Hive write in the diff, find every cloud reader; for every cloud write, find every Hive reader. Look for field-name or semantic drift. Source: `feedback_writer_reader_field_drift_recurring.md`.
2. **function_exception_swallow** — for every `.functions.invoke(` in the diff, confirm catch + `e.status` + `e.details` is used. Source: `feedback_function_exception_class.md`.
3. **blast_radius_mismatch** — `docs/blast_radius.yaml` says path `X` is tier `T`. Does the diff treat it that way? E.g. catastrophic-tier changes must have rollback documented.
4. **secrets_in_tree** — credential-shaped literals (`sk-`, `rzp_live_`, `AKIA`, `-----BEGIN`) anywhere in the staged diff. Source: `feedback_secrets_pattern_audit_before_first_push.md`.
5. **unawaited_no_error_sink** — every `unawaited(` in the diff has either an inner `.catchError` or sits inside a function with declared error sink. Source: `feedback_observability_silent_drop.md`.
6. **guard_without_its_mirror** — for every guard, existence check, early return, or narrowed match ADDED in the diff, name its **mirror case** and check whether that is guarded too: local vs remote, present vs absent, too-narrow vs too-wide, first-of-N vs the rest. Then ask the sharper question: **is the new code WORSE than what it replaced for the mirror case?** A guard written for the failure the author just hit routinely breaks the symmetric case that the previous code handled fine. Source: `feedback_mistake_guard_without_its_mirror.md`.
   **Do NOT accept the diff's own tests as evidence for this lens** — they are written from the same mental model as the code and will cover the same side. Ask instead: what does *every* test in this file silently assume?
   **Method (added 2026-08-11 after this lens found its third consecutive escape in ONE guard):** do not read the guard — *mutate it and run it*. Two rules that came out of that:
   - **Mutate the way a real regression re-enters**, not the way that is convenient to write. The escapes that mattered were "someone restores the old line in place" and "someone types it slightly differently" — not "delete it" or "move it somewhere absurd", which is what the author had tested.
   - **FOLLOW THE RETURN VALUE TO ITS CALL SITE.** A guard can be perfectly correct and still be defeated by the code that consumes it. Added 2026-08-17 after two independent review rounds each fixed this file's escape-hatch predicate — correctly — and both stopped at the predicate; the B-pass then found that the CALLER reduced the per-statement result to one command-wide boolean, re-opening the exact hole both rounds had just closed. **A predicate that returns `bool` cannot carry a binding it just established** — that shape is the tell, and it is visible without running anything. Ask: what does the caller do with this, and does the answer still mean what the function meant?
   - **If the guard is a SOURCE GREP, assume it is defeatable and try indirection** — a helper function, a variable-built argument, an alias, `eval`. A grep is bounded by what its author could imagine writing, so tightening the pattern never converges. The finding is not "the regex is wrong", it is "this needs a runtime test that observes the behaviour". Check whether one is feasible before accepting a grep: hooks and scripts can usually be run with the expensive dependency stubbed on `PATH`, and an early-abort stub keeps it fast.

## 3. Dispatch protocol

When invoked, this skill should:

1. Run `git diff --cached --name-only` and `git diff --cached` to assemble the diff.
2. Compute blast-radius via `dart run scripts/blast_radius_from_diff.dart`.
3. Generate the staging hash **exactly the way the gate does**, or the file you write
   will not be the one it looks for:
   ```bash
   git diff --cached -- ':(top)' ':(top,exclude)docs/reviews' | git hash-object --stdin
   ```
   then truncate to 12 chars. Two details are load-bearing and this step documented
   neither:
   - It is git's **sha1 `hash-object`**, not `sha256`.
     `scripts/check_code_review_pass_exists.dart` has always used `git hash-object`, so
     a review named by following the old text could never match. (Found by round-1B
     review of the gate-input-family batch, 2026-07-27.)
   - `docs/reviews/` is **excluded** from the hash (OI-72, same batch). The gate now
     reads the review from the STAGED blob, so the file must be `git add`ed — and
     without the exclusion, staging it would move the hash and rename the very file it
     is meant to satisfy.
4. **Dispatch a FRESH Sonnet subagent** via `Agent({subagent_type: 'general-purpose', model: 'sonnet', ...})` with:
   - The diff inline (or list of changed files to Read)
   - The 6 lens prompts
   - Explicit instruction: "find bugs, do not validate; if you find nothing, list what you specifically checked and why each lens returned clean"
   - Output schema (the markdown above)
5. Subagent returns findings — write to `docs/reviews/<staging-hash>-review.md`, then
   **`git add` it**. An unstaged review no longer satisfies the catastrophic gate: it
   never enters history, so nothing in the commit records that a review happened.
6. Surface the file path in the main conversation; instruct founder to triage.

## 4. Triage workflow

For each finding:
- **accepted** — fix in same batch per `feedback_no_deferrals.md`. Update `status:` field.
- **false_alarm** — annotate `status: false_alarm` with reason. Helps tune the skill via self-evolution.
- **spawn_followup_task** — emit a new task via `TaskCreate`; status becomes `spawned`.

When ALL findings have non-`pending` status, founder sets `verdict: accepted` and the commit can proceed (for catastrophic; for account/platform the verdict is advisory).

## 5. False-positive tracking (self-evolution)

After each invocation, count `false_alarm` findings as a percentage of total. If > 30% on a single pass, that lens is too noisy. Update the lens prompt OR remove the lens entirely. Document the tuning in this SKILL.md under `## Tuning history`.

## 6. Anti-patterns (DO NOT)

- Pass conversation context to the subagent. It must be FRESH — context-blind reviewers catch what the writer missed.
- Default to "no findings found" when uncertain — force structure ("I checked X with grep Y, returned 0 hits").
- Skip the `verification:` field. Every finding must have a one-line verification command.
- Bundle this with `/hermes-pass`. That's a different skill (per-batch, all 53 lenses, Opus, slower).

## 7. Tuning history

> Append after each invocation: invocation date, blast-radius, findings count, false-alarm count, tuning made.

- **2026-08-25** — blast-radius **platform** — branch `discipline-enforcement` @ `fbbea768`.
  **4 findings (2 P0, 2 P1); 0 false_alarm.** All fixed in-batch.
  Review: `docs/reviews/discipline-enforcement-bpass.md`.
  **This pass reviewed the batch that BUILT this gate, and found the gate would have
  silently passed its own first real use.** `hasTuningEntryFor` matched any bullet carrying
  the review's date — and `SKILL.md` already held a 2026-08-25 entry for an unrelated batch,
  so THIS review would have been reported satisfied by somebody else's entry. Date is not
  identity, and two reviews on one calendar date is ordinary here, not exotic. Fixed with a
  block scan that requires the dated entry to NAME the review.
  **The second P0 is the same shape one layer out:** the Stop hook measured its batch with
  `origin/main..HEAD` while local `main` sat 7 commits ahead of origin — so three derived
  rows reported green on three unrelated batches' evidence (another batch's review file
  satisfied the skill-tuning row; another batch's `fix(...)` subjects set the feedback row;
  the retrospective check anchored to an unrelated commit's date). `new-worktree.sh:65-91`
  had solved that exact range-selection problem already and the fix was not carried across.
  **Generalisable, and it is why this pass earned its keep after TWO ×2 rounds found nothing
  of the kind:** when a batch builds a checker, point the checker at ITSELF and at the
  repo's real state, not at a fixture. Both P0s were invisible to 52 passing tests and to
  two context-blind rounds, and both fell out immediately from running the thing against the
  live tree. A fixture encodes the author's model of the world; the working tree does not.
  ⚠ Process: the reviewer's own failed `cd` left it in the target worktree and an
  `ALLOW_RAW_GIT=1 git commit` landed a stray commit there. Self-caught and fully reverted
  (author verified independently). Two lessons recorded in the review: chain `cd <dir> && …`,
  and a review subagent should not hold a raw-git escape hatch at all.
  False-alarm rate 0/4 → no tuning to lenses 1-6.

- **2026-08-25** — blast-radius **account** (self-declared platform) — branch `oi60-client-blockers` @ `2e9503eb` (OI-60 FOB-7a/7b). **4 findings (0 P0, 1 P1, 3 P2); 0 false_alarm.** All fixed in-batch. Review: `docs/reviews/2e9503eb-review.md`.
  **NEW OBSERVATION, and it is the reason this entry matters: all four findings were defects in the EVIDENCE, none in the CODE.** Every prior entry in this history records the pass catching a code or guard defect. Here the ×2 plan review had already caught the design defects — including a P0 it prevented — and the code shipped correct. What the B-pass found was that the ARTIFACTS DESCRIBING the code were false:
  (1) **P1 — a past-tense claim for work never done.** The plan-review record AND the closure YAML both stated the three wrong OI-127 board citations had been "corrected on the board in this batch". They were corrected in the plan document only; `git log <base>..HEAD -- docs/audit/open_issues.md` returned ZERO commits and the board still showed all three verbatim. The batch existing partly to stop the board misdirecting the next session was about to merge leaving it misdirecting, while asserting the opposite.
  (2) **P2 — `docs/sot_registry.yaml` described superseded behaviour** in two entries, one of which (`still clamped`) the same commit's own new code comment directly contradicted.
  (3) **P2 — the diagnose `bug_id` COLLIDED** with an unrelated doc, making `closes-diagnose:` ambiguous forever (git history cannot be rewritten to repair it). No detector exists: `validate_diagnose_doc.dart` takes ONE path and never scans the corpus, though the OI-number version of this identical bug shipped six times and earned its own gate. Filed OI-140.
  (4) **P2 — a stale mutation count** (claimed 4-of-7 red, actual 5-of-7). Measured when the file had SIX tests, never re-measured after a seventh was added, then copied into two documents.
  **Generalisable, and worth adding to how this skill is USED rather than to a lens:** the ×2 plan review reads the DESIGN; the B-pass reads the ARTIFACTS. Neither pass would have found the other's findings, and a batch can be entirely correct while shipping documents that lie about it. When the code is clean, do not conclude the pass found nothing — turn the lenses on the commit's own claims: does every past-tense assertion have a diff behind it, does every cited count come from a run against the file as it now stands, and is every id unique in its space.
  **Second, mechanical lesson (feeds the new Gate `check_skill_tuning_history.dart` added the same day):** this very entry was NOT written until founder asked whether discipline had been followed. §5.1 mandates it and nothing enforced it, so the skill's own self-evolution loop was the thing decaying. It is now gated: a commit adding `docs/reviews/<sha>-review.md` must also add a same-dated entry here.
  False-alarm rate 0/4 → no tuning to lenses 1-6.

- **2026-08-25** — blast-radius **platform** — branch `e2e-timeout-convention` (a ONE-LINE root-CLAUDE.md pitfalls row). **5 findings (0 P0, 3 P2, 2 P3); 0 false_alarm.** 3 fixed, 2 recorded with reasons. Review: `docs/reviews/e2e-timeout-convention-bpass.md`.
  **First recorded use of the §4.3 docs/process-only review MODE**, and it is worth distinguishing from the other entries here: §4.3 says a docs-only ≥account change *"takes a self-consistency review of the wording instead of an adversarial bug-hunt."* The pass was therefore a wording review plus a ground-truth audit of every factual claim — and the audit is what found everything. Lenses 1-6 as written barely apply to a one-line table row; do not force them, and do not let "the lens set returned clean" read as "the change is fine" on a docs change.
  **The finding that justifies running it at all: the row's CENTRAL CLAIM was false.** It asserted *"EVERY e2e under `test/scripts/` already has one"*; `pre_merge_commit_e2e_test.dart` had none — and that file executes the REAL pre-merge-commit hook in a real throwaway repo, i.e. it was the archetype of the hazard the row documents. A reviewer who read the row for plausibility rather than enumerating all 11 files would have passed it.
  **Generalisable rule this adds: on a docs change, every UNIVERSAL claim ("every", "all", "none", "always") is a finding until enumerated.** Two of the five findings were exactly that shape — the "EVERY e2e" claim, and a Source column citing `common-pitfalls.md` when that file had ZERO coverage of the topic (a phantom citation, which this repo already calls *worse than citing none, because it reads as coverage*).
  **Also generalisable: check whether the documented fix is the WEAKEST available one.** The row prescribes a per-file annotation held only by memory; the class has recurred 4× (`aac52fb6` alone records three consecutive failed merge attempts), and `dart_test.yaml` — which exists, configuring only the `golden` tag — would close it repo-wide in one line. Recorded rather than done, because changing the global test timeout touches every test and both CI jobs.
  False-alarm rate 0/5 → no tuning to lenses 1-6.

- **2026-08-20** — blast-radius **account** — branch `claude/oi-pending-hold-weeks-1od97o` (FOB-1 week identity, OI-60). **2 findings (0 P0, 1 P1, 1 P2); 0 false_alarm.** Both fixed in-batch. Review: `docs/reviews/fob1-week-identity-bpass.md`.
  **Lens 6 found the P1 by asking its question one level OUT — not "is this guard correct?" but "is the value it produces REACTIVE where it is consumed?"** The seam, the provider and four of six surfaces were all correct. The defect: `UserStatsNotifier.build()` read the identity through a plain singleton call, so `userStatsProvider` had NO dependency-graph edge to the hold write. The five tabs sit under `StatefulShellRoute.indexedStack`, so an already-mounted Profile tab never rebuilds on tab-switch — Profile would have kept printing `WEEK 4 OF 4` while Home and Train said `HOLDING · H1`, **reintroducing the exact cross-tab contradiction the batch existed to close, on two of its own six surfaces.** This is the 2026-08-17 "follow the return value to its CALL SITE" note generalising once more: the tell was again structural — a `build()` that watches nothing it derives from.
  **The P2 is the second consecutive batch where `test_can_actually_fail` beat a mutation-proven change, and the sharper lesson is new.** The batch shipped TWO mutation proofs on the service seam and cited both in its commit message — while the LABEL layer, which is what a user actually reads, had zero behavioral coverage: the only assertion was `body.contains('stats.isHolding')` against raw source. The reviewer inverted that ternary (a real defect printing "Holding · Hnull" to every non-holding user) and **all 16 tests still passed**. Fixed by extracting the five label ternaries to pure functions with a table-driven test; the same inversion now reddens 4. **Generalisable: mutation-proving a SEAM does not mutation-prove the SURFACES that consume it.** A source-grep over a widget is presence, not behaviour — when the logic is a ternary in a `build()`, extract it to a pure function so it can be asserted at all.
  False-alarm rate 0/2 → no tuning to lenses 1-5.

- **2026-08-17** — blast-radius **platform** — branch `cycle-time-and-board-gaps` @ `3c7cb9d2`. **5 findings (1 P0, 3 P1, 1 P2); 0 false_alarm.** All fixed in-batch. Review: `docs/reviews/cycle-time-and-board-gaps-bpass.md`.
  **The P0 is the clearest case yet for running the B-pass even after a ×2 plan review passed, and lens 6 found it.** The batch had already had TWO independent context-blind rounds (8 and 10 findings). Round 1 fixed an escape hatch that a mere MENTION could grant; round 2 fixed it again for mentions inside heredocs and multi-line commit messages. Both fixes were correct. The B-pass found generation THREE: the hatch was bound correctly to a statement, and then the **caller** collapsed that binding into one command-wide boolean, so `ALLOW_RAW_GIT=1 git status; git push --force` exempted the push. Reproduced against the real hook with controls in both directions.
  **The generalisable lesson, and it is a new one for this lens:** rounds 1 and 2 both reviewed the PREDICATE and neither reviewed the CALL SITE. A guard can be perfectly correct and still be defeated by the code that consumes it — so lens 6 must follow the guard's return value to where it is USED, not stop at where it is computed. The tell was structural and visible without any cleverness: the predicate returned a `bool`, which is exactly the shape that cannot carry the binding it just established. The fix returns the offending STATEMENTS.
  **Second observation, worth keeping:** 4 of 5 findings were lens 6, and the other (`blast_radius_mismatch`) was the FOURTH recurrence of "the hook got pinned, its dependencies did not". Both are the same failure family — the fix covers the thing you were looking at and not the thing one step away. No new lens; lens 3 and lens 6 already cover it, and adding a seventh would split attention rather than add reach.
  False-alarm rate 0/5 → no tuning to lenses 1-5.

- **2026-08-13** — blast-radius **platform** — branch `post38-auth-fixes` @ `04e29b25` (PR #22 merge resolution: OI-id renumber + a new duplicate-id detector). **5 findings (0 P0, 0 P1, 5 P2); 0 false_alarm.** All fixed in `79a313d6`. Review: `docs/reviews/04e29b25-review.md`.
  **The finding that justifies the pass: a test that could not fail for the property it asserted.** The new "reports every duplicated id, in numeric order" test used a fixture of `OI-100..105` — six ids of **identical digit width**, where lexical and numeric sort produce the same output. Its `reason:` string claimed *"lexical would put OI-100 last"*, false for its own data. The reviewer substituted a lexical `.sort()` and **all 25 tests still passed**. Fixed with `[9, 10, 100, 105]` (lexical differs at BOTH ends), re-proven by execution: clean 26/26, lexical mutation 25/1.
  **Why this is worth recording rather than filing as routine:** the commit under review shipped TWO deliberate mutation proofs and cited both in its message — and still contained a third assertion that could not discriminate. Mutation-proving the code does not mutation-prove the *fixtures*. This is the `test_can_actually_fail` lens finding a gap that rule 24's ledger cannot see, because the ledger checks that a red-path assertion EXISTS, not that its data makes the wrong implementation visible.
  **NO new lens.** This is `test_can_actually_fail` (already in the brief) working as intended, not a blind spot. The other four were documentation-integrity: two bare-number citations a `sed 's/OI-<n>\b/…/'` structurally could not see, a board-vs-diagnose-doc ordinal contradiction, an unexplained empty `related_bugs:`, and a plan-review record whose narrative was frozen at an earlier slice. False-alarm rate 0/5 → no tuning to lenses 1-6.

- **2026-08-11** — blast-radius **platform** — batch `commit-merge-push-process` (ADR-0018, the pre-commit cost split). **2 findings (0 P0, 1 P1, 1 P2); 0 false_alarm.** Both fixed in-batch. Review: `docs/reviews/commit-merge-push-process-bpass.md`.
  **Lens 6 earned its place again, and taught the sharper version of its own rule.** The P1: the batch's pre-commit guard was a SOURCE GREP, and the B-pass defeated it with an indirect invocation — `_sub="ana""lyze"; flutter "$_sub"` — which runs `flutter analyze` on every commit with the suite fully GREEN. That was the **third** escape found in that one guard across three passes: the ×2 plan review's round 1 restored the calls into the `else` body (the first version's asserted range *contained* the else branch), round 2 beat the fix with `flutter  analyze` (one extra space), and the B-pass beat *that* with indirection. Each fix was defeated by the next reviewer.
  **The generalisable lesson, now added to lens 6's method note:** tightening a matcher is a losing game — a source-grep guard is bounded by what its author can imagine writing. The fix was a RUNTIME test (`test/scripts/pre_commit_lean_path_e2e_test.dart`) that executes the hook with a stub `flutter` on PATH and observes actual invocation, so it holds against any spelling. It had been skipped on a cost assumption (~22s to run the whole hook) that collapsed once the abort trick was found: stub `dart` to exit 1 and the script dies at its first gate, which sits *below* the code under test — 2s per scenario. **Reach for the behavioural test FIRST; fall back to a grep only when execution genuinely cannot be observed, and say so in the test header.**
  The P2 (`blast_radius_mismatch`): platform tier's `requires:` lists `feature_flag`, which nothing in the diff addressed and which **no gate enforces** — `check_plan_review_record_exists.dart` never reads it, so it can pass CI while unmet. Resolved as a written, founder-ratified deviation in ADR-0018 rather than a compliance claim. Worth noting the lens caught a requirement that is registry-level-only; that is exactly the gap a human-run lens exists for.
  False-alarm rate 0/2 → no tuning to lenses 1-5.

- **2026-08-10** — blast-radius **platform** ×2 — batches `gate-registry` (merge `f909cf35`) and `ci-speedup` (merge `9a5ecd82`). **3 findings (0 P0, 0 P1, 3 P2); 0 false_alarm.** gate-registry: a generator emitting a bare "." as the purpose for 2 of 87 index rows, and a comment citing a gate number the same batch's own rule forbids. ci-speedup: an asymmetric existence guard in `new-worktree.sh` that made the script CRASH under `set -e` in a case the pre-fix code handled fine. All fixed in-batch with regression tests; two carry mutation proofs.
  **NEW LENS — `guard_without_its_mirror` (lens 6).** The ci-speedup finding was the **fourth** instance in one session of one shape: `isRegenerableIgnored` went none→prefix→basename→exact across three consecutive P0s; the gate-registry hard-fail went vacuous→over-firing→correct; the worktree guard covered `origin/main` but not local `main`; and a `_settle()` fix took a per-call-site predicate derived from only the FIRST of three following assertions, turning a flaky test into a deterministically failing one. **Each fix created the next round's finding.**
  Why a LENS and not just a memory file: the ×2 plan review caught **none** of the four, and the B-pass caught only the last. A plan review reads prose; this class only shows against code. The memory file naming the pattern already existed when the fourth instance was committed — writing the rule down did not prevent applying it wrong, so it needed a checkpoint that runs over the diff.
  False-alarm rate 0/3 → no tuning to lenses 1-5. Reviews: `docs/reviews/gate-registry-bpass.md`, `docs/reviews/ci-speedup-bpass.md`.

- **2026-06-08** — blast-radius **platform** — commit `b7c8040` (ai-proxy recompose server-enum). **3 findings (1 P1, 2 P2); 1 false_alarm.** 1 P1 (diagnose `blast_radius` account→platform) + 1 P2 (`_executeRegeneratePlanBlock` missing `FitnessGoals.isKnown` guard, asymmetric with `_executeSwitchGoal`) fixed in-batch; Finding 3 (`_humanGoal` default-case for recompose) = intentional/SoT-covered → false_alarm. False-alarm rate 1/3 ≈ 33% nominally > the 30% threshold, but **n=3 is too small to act on** and the false_alarm was lens 1's (writer_reader_drift) soft defense-in-depth sub-note, not a distinct noisy lens → **NO lens tuning**. The pass also independently re-verified the gate regex + token-parse + `describe()` text (zero false-greens) and caught a real P1 + a real P2 the 0 prior reviews missed → net valuable on a prod-bound platform change. Review: `docs/reviews/b7c8040-review.md`.
