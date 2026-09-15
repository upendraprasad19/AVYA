---
branch: gate-input-family
date: 2026-07-27
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/gate-input-family-bpass.md
---

# Plan review — the gate-input family (OI-70 / OI-71 / OI-72)

> **SCOPE WAS CUT MID-BATCH.** This started as a quartet including OI-58a/OI-58b.
> After three independent review rounds each found a NEW material defect in that
> half — the last a version-bump exemption that accepted any subset of its path
> allow-list — the batch was split per CLAUDE.md §4.12.1 and the founder approved
> shipping the converged three. OI-58a/OI-58b remain OPEN and get their own unit.
> The "Decisions" section below still records the reasoning for the removed half,
> deliberately: the next unit starts from it rather than from scratch.

**Authored BEFORE the first line of gate code, deliberately.** This batch edits the
gate that grades it, and OI-70 is a demonstrated self-exemption route: the tier engines
read `docs/blast_radius.yaml` from the *merged* tree, so a commit that relaxes its own
rules is judged by the relaxed rules. Writing the record first means the batch cannot
quietly grade itself down partway through.

Every tier figure below was computed against `HEAD^1`, never the merged tree.

## Scope

One thesis: **the gate must not derive its inputs from author-controllable or
post-merge state.** Four open issues are four instances of it, all in the same two
files.

| OI | Input | Where it comes from today |
|---|---|---|
| OI-70 | the tier registry | the merged working tree (`File(_registryPath)`) |
| OI-71 | the changed-file set | `HEAD^1...HEAD^2`, a three-dot diff |
| ~~OI-58a~~ | whether the gate runs at all | `rev-parse HEAD^2` — **SPLIT OUT, still open** |
| ~~OI-58b~~ | which branch is being landed | the merge subject — **SPLIT OUT, still open** |
| OI-72 | the review artifact | `existsSync()` on the working tree, while the hash comes from the index |

OI-58's own entry asked for its own unit. It was folded in anyway (founder-approved
2026-07-27) because its fix replaces the very line OI-71 patches, and splitting would
have meant writing the range derivation twice. **Three review rounds later, OI-58's
original instinct turned out to be right** and it was split back out — but the range
derivation still only got written once, which was the point. The shared work ships here;
the judgement built on top of it does not.

## Ground truth

Measured, not assumed. Commands and outputs are reproducible from `main` at `1b02d00e`.

### OI-58a has already fired twice, on auth code

Of the last 60 first-parent commits on `main`, 55 are merges and **5 are
single-parent**. Three of those five are ≥account:

| Commit | Tier | What it is |
|---|---|---|
| `be3b4baf` | account | `feat(auth): complete in-app password reset flow` — 11 files, incl. `app_router.dart`, `reset_password_screen.dart` |
| `8c38c855` | account | `fix(auth): password-recovery URL fragment consumed by GoRouter` — 8 files, incl. `main.dart` |
| `2c4cbddd` | platform | versionCode bump — **only** `pubspec.yaml` + `lib/core/constants/app_constants.dart` |

The first two are exactly what §4.12 exists to catch: account-tier auth work landing on
`main` with no branch, no merge commit, and no plan-review record. The gate exited at
`check_plan_review_record_exists.dart:142` before looking at anything. This is not a
theoretical bypass — it is the observed default when someone commits straight to main.

The third is mechanical and is the one case that must stay passing (see Decisions).

### OI-70's stated fix is half a fix

`904e6961` (`ci-speed`, merged 2026-07-26) landed `.github/workflows/test.yml`. Judged
against **today's** registry that merge is `platform`; judged against the registry **as
of that merge** it is `feature` — `git show 904e6961:docs/blast_radius.yaml` grades it
by a BROADER rule, `.github/** -> feature` (line 111). The narrower
`.github/workflows/test.yml -> platform` promotion arrived one batch later, in
`ci-governance` (`9e3ce5d8`, line 96).

(An earlier draft of this paragraph said "no rule covered that path, so it fell through
to `default_tier`". Round-1B review showed that is false — I had grepped the historical
registry for `workflows` and `scripts/` and never for `.github/**`. The tier outcome,
and therefore the max() decision below, is unchanged; the mechanism was misstated.)

So the gate passed a merge that today's rules call platform, and it was *right to*, by
the rules it had. But it shows the hole runs both ways:

- read only the **merged** tree → a commit that deletes its own rule self-exempts (OI-70)
- read only **`HEAD^1`** → a commit landing content no rule covers yet is judged lax, and
  the branch that adds the rule is itself exempt from it

Neither single source is safe. Decision below.

### OI-71: three-dot vs two-dot, and what it does not explain

`HEAD^1...HEAD^2` is `merge-base..branch-tip` — the branch's own changes, excluding
whatever the merge commit itself wrote during conflict resolution. Checked `904e6961`
specifically to see whether this explained its `feature` verdict: it does not
(`comm -13` of the two file lists is empty there). The registry-version effect above is
the real explanation, and conflating the two would have been the easy wrong answer.

The three-dot hole is still real; it just has not been the cause of a specific past
miss that I could find. Recorded that way rather than overstated.

### The record-freshness rule is safe on real history

For the last 25 first-parent merges, `docs/plan-reviews/<slug>.md` appears in the
merge's own range for **every ≥account merge except `904e6961`**, which is the
`feature`-at-the-time case above.

Round-1B review widened the window, and the conclusion got *stronger*: across all **182**
first-parent merges on `main` exactly two branches landed more than once —
`hold-display` (×3, whose 2nd and 3rd landings are `feature` tier so the record
requirement never fires) and `deno-type-debt-cleanup` (×2, both **catastrophic**, and
both carried their record in range). So the freshness rule has zero false positives over
the whole history, not just the sampled 25.

## Decisions, and why

1. **Registry: take `max(tier under HEAD^1, tier under the merged tree)`** rather than
   OI-70's `HEAD^1`-only. Strictly stronger than either source alone and closes both
   directions at once. The one behavioural cost is that a legitimate *demotion* commit
   is still judged at the old, higher tier — which is correct: demoting a tier is
   precisely the change that should carry a review.

2. **Range: two-dot `base..head` over the pushed range**, replacing the three-dot
   branch diff. Can only ever add files to the inspected set, so it can raise a tier
   and never lower one. In CI the base is `github.event.before`; locally it falls back
   to `HEAD^1`, and the gate stays a no-op outside CI as it does today.

3. **Single-parent ≥account landings hard-fail, with one narrow exemption.**
   **NOT SHIPPED — this is the decision that failed review and was split out.** It is
   kept here verbatim so the next unit inherits the reasoning *and* the trap: the
   exemption described below is PATH-verified, and a path allow-list tested with
   `every(...)` accepts every subset, so it exempted far more than a version bump. The
   next unit must verify the changed LINES. Shipping
   this `--warn-only` per §4.11 was considered and rejected: OI-68 already records that
   `check_skipped_discipline_budget.dart` has sat `--warn-only` for 38 days against a
   documented "24h smoke window", and a warn-only gate with no flip mechanism is the
   documented decay pattern. The baseline here is measured and tiny (3 of 60), so it
   ships hard.

   The exemption is content-verified, mirroring the Dependabot precedent already in
   this file: a version bump touching **only** `pubspec.yaml` and
   `lib/core/constants/app_constants.dart`. Those two are already pinned to each other
   by `check_app_version_matches_pubspec.dart`, so the exemption adds no new trust.
   `be3b4baf` and `8c38c855` do **not** qualify and would now fail, which is the point.

4. **OI-58b (subject spoof): closed to the extent a script can, and no further.**
   A merge subject is free text written by whoever has push access. Nothing in-repo can
   distinguish `git merge --no-ff other-work -m "Merge branch 'hold-mechanic'"` from the
   real thing, because every input the script can read is under that author's control.

   What ships is **one-record-one-landing**: if the branch named in the subject has
   already landed on `main` at ≥account, the record must have been *modified in this
   range* — a second landing needs a second review round, not a re-run of the first.
   That defeats re-pointing an old approved record at new content, which is the
   realistic form of this bug.

   The residual — a first-time spoof naming a branch that has never landed — is a trust
   boundary, not a script defect. The control for it is requiring PRs so GitHub, not the
   author, writes the subject from the real head ref. That is a repository-settings
   decision and is recorded as `blocked_on_user` in the closure ledger rather than
   claimed as closed here. Deliberately NOT touching branch protection in this batch:
   `feedback_mistake_branch_protection_semantics` records three separate occasions of
   getting those semantics wrong.

5. **OI-72: read the review artifact from the staged blob**, using
   `_stagedFileExists` / `_stagedFileContent` — helpers that already exist in that same
   file, with a comment explaining this exact class, applied to `contentForcesCatastrophic`
   but not to the review file. Staging the review file would move the staged-diff hash it
   is named after, so the hash is computed over the staged diff **excluding**
   `docs/reviews/**`.

## Rounds

| Round | Outcome |
|---|---|
| 1A — gate correctness (independent, context-blind) | **3 P1, 3 P2, 3 P3.** All nine fixed in-branch. Detail below. |
| 1B — tests and factual claims (independent, context-blind) | **1 P1, 6 P2, 4 P3.** All fixed. Three were false claims in my own docs. Detail below. |
| B-pass — final staged diff, post-split (fresh context-blind) | **3 P2, 1 P3, all fixed.** Found a fail-open three rounds missed, and caught me reporting a fix as landed when it had not been. `docs/reviews/gate-input-family-bpass.md`. |
| 2 — on the hardened branch | **NOT CONVERGED: 1 new P1 bypass (introduced by round 1's own fix), 1 P1 test gap, 5 P2, 9 P3.** Triggered the split. Every finding in the shipped scope is fixed. |

### Round 1B, and the claims it broke

1B ran on a separate surface — the tests and every factual assertion — and its most
useful output was not a code defect but **three statements of mine that were simply not
true**. Each was re-verified by me before acting.

**The registry claim was wrong, and it was the second incomplete grep in one batch.** I
wrote that `904e6961`'s registry had "no `.github/workflows/**` rule at all, so the path
fell through to `default_tier`". It has `.github/** → feature` at line 111 — a broader
rule, not a fall-through. I had grepped that historical registry for `workflows` and
`scripts/` and never for `.github/**`. The tier outcome is unchanged, so the max()
decision survives, but the mechanism I documented in four places was false.

**"Five untracked `docs/reviews/*-review.md` files" — there are three.** Five files are
untracked in that directory; only three match the pattern the gate looks for. The other
two are `-bpass.md` and invisible to it. Corrected in five places.

**One of my eight controls was vacuous.** The OI-70 *"a rule that arrives WITH the
change also binds it"* test passes against the pre-fix gate too — the old gate read the
merged tree, which already contains the new rule, so it failed there as well. It is a
**design-lock** on the rejected base-only alternative, not a revert-control. Worth
keeping; the file header claiming *every* test was a revert-control was not. Both the
header and the closure ledger's "both directions carry an e2e control" now say which
kind each test is.

Also fixed: the closure ledger failed its own Gate 40 validator (no `commit:` fields);
the ship-dark ledger this batch set out to make true still carried an unresolved
`"(uncommitted — fill sha at commit)"` placeholder for `hold-display-fixes`
(`ff13623e`, merged `342820b3` — a merge that touched the ledger and left it); the
`/code-review` skill still documented the staging hash as `sha256(git diff --cached)`
when the gate has always used git's sha1 `hash-object` **and** now excludes
`docs/reviews/`, so a review named by following that text could never match (§5.1 skill
self-evolution); four `file:line` citations had drifted; the freshness-rule safety
window was 25 merges when 182 were available; and one control asserted only an exit code
where the pre-fix gate exited 1 for a *different* reason.

1B independently re-derived all 13 ship-dark entries, both flip-order quotes, every
OI-48 line number, the 5-of-60 single-parent measurement, and the four-commit replay —
all confirmed exact.

### Round 1A, and what it cost me to be wrong

Every finding below was re-verified by me against the code or by execution before
being acted on — subagent claims do not enter the work unchecked
(`feedback_audit_verifier_cannot_trust_own_subagent`; five refuted on 2026-07-25).

**P1-1 — the version-bump exemption was per-PUSH, not per-COMMIT.** The first draft
unioned every direct commit's paths before testing the exemption, so one
`feature`-tier commit alongside the bump killed it. That is not a corner case, it is
the standard release flow — verified by running the gate over `3bca83a8..HEAD`, which
contains `2c4cbddd` (the versionCode bump, 05:24) and `6a364656`
(`docs(audit): close OI-52`, 06:42), the two halves of shipping APK +37. It FAILED on
the bump the exemption exists for.

The compounding error is mine and worth naming: **§ "Decisions" 3 above justifies
shipping hard-fail on a baseline of "3 of 60, of which 1 is exempted" — and that
baseline was measured per-COMMIT while the code I then wrote was per-PUSH**, where 0
would have been exempted. The justification did not describe the implemented
behaviour. My own tier-12 evidence could not have caught it either: I replayed the
four commits *individually*, a method structurally blind to a union defect. Fixed to
per-commit, which is provably never more permissive (the exemption is an all-of test,
so a passing union implies every subset passes).

**P1-2 — I deleted a loud-fail guard and put nothing back.** The old gate had
`if (diff.isEmpty) exit(die('empty merge diff …'))`. The rewrite dropped it, and
`_git()` returned `''` on any git failure, so an errored diff became an empty path
list, resolved to `feature`, and waved a merge through with a reassuring NOTE.
Confirmed by grep against `HEAD`. `_git` now has a nullable form and three sites fail
loud.

**P1-3 — the batch over-claimed its own thesis. Recorded, not fixed.** See below.

**P2-1** a supplied-but-unresolvable `PUSH_BEFORE` silently narrowed to `HEAD^1` and
printed a clean PASS (force-push shape); now fails loud. My doc comment also claimed
an all-zero base returned null — it returned `'HEAD^1'`. Both corrected, and all-zeros
is now handled explicitly as git's new-branch sentinel.
**P2-2** content escalation read the working tree, so a `SECURITY DEFINER` migration
added by one merge and removed later in the same push escaped `hermes: accepted`; now
read via `git show <sha>:<path>`.
**P2-3** one-record-one-landing walked history only at the range base, so two landings
of one branch inside a single push both looked like firsts.
**P3-1** every record field except `branch:` was matched against the whole file rather
than the frontmatter (pre-existing, closed here since the function was rewritten).
**P3-2** the OI-72 pathspec was CWD-relative; now `:(top)`.
**P3-3** the CI comment still described the deleted `HEAD^1..HEAD^2` diff.

Seven new regression tests, one per finding, all failing without their fix.

## What this batch does NOT close

**P1-3 — the gate is still read from the tree it is judging.** `.github/workflows/test.yml`
runs `dart run scripts/check_plan_review_record_exists.dart` from the merged checkout,
and on a `push` event GitHub evaluates the workflow file at the pushed SHA — so both
the gate and its invocation are supplied by the commit under test. Both files are
`platform` in the registry, so the registry says they need a record while the check
enforcing that is performed by the artifact being changed.

This is the same class OI-70 closes for `docs/blast_radius.yaml`, and my diagnose-doc's
original "What is NOT closed" named only the merge-subject spoof. That was an
over-claim against the batch's own stated thesis, and it is corrected rather than
quietly widened.

It is not fixable in-repo: pinning the script to a base revision still leaves the
workflow step itself author-supplied, and would also mean a genuine improvement to the
gate never governs its own merge. It shares the single real control with
`OI-58b-residual` — requiring PRs so main cannot be pushed directly — and is recorded
as `blocked_on_user` in the closure ledger under that same control.

### Round 2, and the decision it forced

Round 2 returned **NOT converged**, and its headline finding was a bypass that round 1's
own fix had introduced. `isMechanicalVersionBump` tested
`paths.every(versionBumpAllowedPaths.contains)` — an all-of test over an *allow-list*,
which accepts every proper subset. Confirmed by execution: a direct-to-main commit
rewriting `monthlyPriceInr` and `freeAiMessagesPerDay` in `app_constants.dart`, touching
no version line at all, passed at `account` tier with a reassuring
`NOTE (version-bump exemption)`. My own docstring claimed the opposite protection, and
the justification ("already pinned to each other by
`check_app_version_matches_pubspec.dart`") only ever held for the pair — that gate
compares the `version:` string alone.

The shape mattered more than the bug. Every material defect after the initial build was
in the *same sub-area*, and each round's fix seeded the next round's finding:

| Round | New material code defect | Where |
|---|---|---|
| 1 | per-PUSH union; deleted loud-fail guard | direct-commit / exemption |
| 1B | none (three false claims in my docs) | docs |
| 2 | subset-accepting exemption — from round 1's fix | direct-commit / exemption |

Meanwhile OI-70, OI-71 and OI-72 were stable: round 2 found no defect in the two-dot
diff or the dual-registry logic and replayed 11 real pushed ranges, all passing. That is
precisely §4.12.1's split signal, so the batch was split rather than reviewed a fourth
time.

Round 2's findings **inside the shipped scope** are all fixed: three more `_git`
sites that failed open (`rev-parse --abbrev-ref`, `rev-list`, and one inside the removed
helper), a `readFile` callback that threw into
`blast_radius_content_rules_lib.dart`'s `catch (_) { return false; }` and so failed OPEN
while reading as a defence, a record validated against the working tree instead of the
merge's own tree, a 40-zero sentinel regex that would hard-fail a SHA-256 repo, an
uncaught `FileSystemException` on the event payload, and a test that reimplemented the
hash oracle with the *old* pathspec so it passed by coincidence.

It also corrected round 1 on its own terms: **P3-2 was fixing a non-bug.** The original
code passed no pathspec at all and `git diff --cached` is not CWD-limited, so there was
nothing to fix; adding the exclusion is what introduced a pathspec in the first place.
`:(top)` is kept because it is correct, and the comment now says so honestly.

## Convergence

**Converged for the shipped scope.** The three shipped issues have had no new material
finding since round 1B, and every round-2 finding touching them is closed with a test.
The unconverged half is not hidden — it is split out with terminal states in
`docs/audit/gate-input-family.closure.yaml` and carried OPEN in
`docs/audit/open_issues.md`, with the design its next unit should start from.

### The B-pass earned its keep

It ran on the final staged diff — which no earlier round had seen, because the split
happened after round 2 — and returned three P2s and a P3, all fixed.

The one worth carrying forward: **I had reported the `rev-list` fail-open fix as landed
in an earlier turn, and it had not applied.** The B-pass caught it. That is
`feedback_mistake_unverified_done_claims` — the most recurrent class in this repo —
occurring inside the batch whose entire subject is gates that confidently return the
wrong answer. It is also the second incomplete-verification of mine this batch, after
the `.github/**` grep. Both were caught by review rather than by me.

Neither of the two fail-open sites had a crafted trigger; both operate on revisions
confirmed to exist moments earlier. That is exactly why three rounds hunting *reachable*
bypasses walked past them, and it is the standing lesson: "no attacker path" is not the
same as "correct".
