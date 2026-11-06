---
branch: discipline-tooling-hardening
date: 2026-08-05
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/discipline-tooling-hardening-bpass.md
---

# Plan review — discipline-tooling-hardening (Units 3a + 3c, diagnose c9f4e1)

## Scope

`scripts/_git_lock.sh` (a concurrency lock for the git wrappers) and
`scripts/safe_merge.sh` (a wrapper for the merge-into-main step), plus their
wiring into `safe_commit.sh` / `safe_push.sh`, the `blast_radius.yaml`
promotions, a CLAUDE.md §4.13 update, and three test files.

**Unit 3b is NOT here.** It was split out and shipped separately on
2026-08-05 as `unit3b-one-record-one-landing` (diagnose `a7f3c2`, merge
`1b60ca62`) under CLAUDE.md §4.12's "ship the smallest converged piece" rule.

Tier re-derived from the real staged diff via the `-` stdin form:
**`platform`**, driven by the scripts themselves.

## The review history is unusual and worth stating plainly

Rounds 1, 2 and 3 (2026-08-03, prior session) reviewed a design that **is not
what ships here**. Each found a defect of the same check-then-act shape in the
lock's automatic stale-reclaim, and each fix relocated it one step:

1. release deleted a lock it no longer owned
2. claim became visible before the holder file was written
3. reclaim decided-then-acted (blind `rm -rf`)

**Round 4 (2026-08-05) found a fourth, in the round-3 fix itself** — the restore
`mv -T` FAILS into a non-empty destination while the following `rm -rf` ran
unconditionally, so a third process claiming the momentarily-emptied path caused
a stolen **live** lock to be destroyed and two processes to hold the mutex.
Reproduced by execution. Round 3's own text had explicitly weighed and *accepted*
that residual on the grounds it "fails toward refuse-not-corrupt" — the round-4
reproduction disproved exactly that claim.

Per §4.12 that is the stop-and-reconsider signal, not a cue for a fifth patch.
Filed as **OI-92**; the founder ratified **removing the auto-reclaim outright**.

The two rounds counted in `review_rounds` above are the rounds run on the
**post-removal** code (R1, R2 below). Counting the earlier three would be
dishonest — they reviewed a different design, and their conclusion was rejected.

## What actually ships

- **The auto-reclaim is deleted** — `_RECLAIM_MIN_AGE_SECONDS`, the age gate,
  and the steal-verify-restore block. A dead-holder lock is REFUSED, printing the
  manual `rm -rf` the script already emitted.
- **The claim path is unchanged** — private candidate → single atomic `mv -T`
  publish. This was never the defective part; it is verified under 5-way
  contention and by two cascade repros, all retained.
- **A vanish-race retry** — if the lock is released between our failed publish
  and our read, retry rather than reporting a stale lock that no longer exists.
- **Signal handling fixed** (B-pass finding, see below).
- `safe_merge.sh` unchanged from round 3: refuses to merge onto a local `main`
  behind `origin/main`, and shares the lock.

## R1 — the new code paths

- **"The only looping path is the vanish race"** — asserted in a comment, so
  verified by tracing every branch after a failed publish: `mkdir` fail → return
  1; publish success → return 0; not-a-dir → `continue`; holder alive → return 1;
  otherwise → return 1. Exactly one loops. The comment is accurate, and the
  "after N attempts" message it justifies is still reachable and still means
  something.
- **Candidate leak per retry** — `rm -rf "$candidate"` runs at line 225, before
  the `continue` at 244. No leak; the next iteration also re-cleans.
- **`set -u` safety** — `holder_started` is assigned `""` at the top of every
  iteration's read block, so the pre-existing unguarded expansion cannot trip
  `set -u`. New code uses `${holder_started:-unknown}` regardless.

## R2 — the docs and the callers (where a removal usually leaves wreckage)

- **No present-tense reclaim claim survives** anywhere in the script; every
  remaining mention is an explicit historical/removal note.
- **No caller claims reclaim behaviour** (`safe_commit.sh`, `safe_push.sh`,
  `safe_merge.sh` all clean).
- **`blast_radius.yaml`'s justification still holds** — "_git_lock.sh provides
  the mutual-exclusion safe_commit.sh and safe_push.sh both depend on" is still
  true of the claim path.
- **CLAUDE.md §4.13's safe_merge claim verified against the code**, not assumed:
  the behind-`origin/main` refusal is at `safe_merge.sh:122`, the shared lock at
  `:98-99`. Its caveat that `git_safety_hook.dart` has no `git merge` clause is
  also true — confirmed by behaviour, since raw `git merge --no-ff` ran unblocked
  repeatedly during this session.
- **The diagnose-doc's own frontmatter was stale** and was corrected:
  `proposed_fix:` described the age gate and steal-verify-restore as shipping,
  and `regression_test_planned:` described two tests that no longer exist. A
  diagnose-doc whose `proposed_fix` describes deleted code is exactly the
  wrong-but-live class this batch series has been fixing elsewhere.

## Ground-truth verification

- **Every claim about `mv -T` re-proven by execution**, not inherited: the
  restore-into-occupied-path failure that defines the round-4 bug was reproduced
  directly on this toolchain before being written down.
- **`flock` absence checked**, not assumed — it is what makes removal (rather
  than a correct reclaim) the only option.
- **Tests negative-controlled twice, by execution:**
  - re-adding a naive auto-reclaim → **only** the inverted stale-lock test fails;
  - reverting the trap to its non-exiting form → **only** the new signal test
    fails.
  Both times the script was restored from a byte-copy and re-verified by md5.
- All 6 lock tests plus the `safe_merge` / `safe_push` suites pass (11 total).

## Convergence

Converged. The shipped change is a **net deletion** of the only component that
ever failed review, plus one genuinely new fix (signals) that is itself
negative-controlled. The surviving surface is the claim path, which three
independent rounds and two cascade repros already attacked without finding a
defect.

Stated rather than buried: the B-pass found a real defect *after* R1 and R2
(below). That is normally the §4.12 signal to split again. It does not apply
here — the finding is a different class (signal semantics, not check-then-act),
it was pre-existing rather than introduced by this change, its fix is one line
per signal, and it now has a dedicated regression test that fails without it.
A further round would be re-reviewing a verified deletion.
