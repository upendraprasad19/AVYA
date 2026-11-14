---
reviewed_at: 2026-07-26
staged_against: ci-governance (worktree, pre-commit staged diff — 10 files)
blast_radius: platform
reviewer: claude-sonnet-via-code-review-skill (fresh, context-blind; re-verification pass)
lens_set: [branch_identity_trust, regex_classification_boundaries, control_flow_null_safety, dependabot_exemption_scope, test_vacuousness, ci_yaml_structural_integrity, numeric_self_consistency, coverage_regression, staged_vs_working_tree_drift]
findings_count: 0 P0, 0 P1, 2 P2 open (record-count citation still wrong; 2 correct fixes not yet staged), 1 P0 downgraded to accepted-known-open (subject spoofing, honestly documented, architecturally scoped with the pre-existing single-parent bypass), 1 P0 confirmed fixed (quote-truncation), 3 P2 confirmed resolved
verdict: accepted
---

# Code Review (B-pass) — ci-governance — RE-VERIFICATION

This supersedes the original review below (kept at the bottom for the record).
Every claim in the coordinator's response was independently re-verified against
the actual repository state — code execution and `git show :path` /
`git ls-tree` reads, not the coordinator's prose. Where I disagreed I re-ran
the check a second way before writing it down.

**Methodology note, because it mattered this round:** several of the files
under review have *unstaged* changes sitting on top of what's in the index
(`git status` showed `AM`, not `M`, for three files). "The staged diff" and
"the current working tree" are not the same thing right now. I tested both,
explicitly, and say which is which below — this is exactly the kind of
drift a B-pass exists to catch.

## 1. Repro B (accidental quote-truncation) — CONFIRMED FIXED, and staged

Extracted the exact **index** (staged) copies of `plan_review_record_lib.dart`
and `check_plan_review_record_exists.dart` via `git show :path` into an
isolated temp repo (env scrubbed, `includeParentEnvironment: false`, same
pattern as `plan_review_record_gate_e2e_test.dart`) and re-ran my original
repro against the real, staged binary:

```
merge exit=0
git-generated subject: "Merge branch 'short-name'z-unreviewed-extra'"
[plan-review-record] FAIL: could not recover merged branch from subject:
'Merge branch 'short-name'z-unreviewed-extra'' (expected "Merge branch 'X'"
or "Merge pull request #N from owner/X").
REPRO B exit=1
```

Confirmed by hand-tracing the regex too:
`_branchRe = RegExp(r"^Merge branch '([^']+)'(?=\s|$)")` — for
`Merge branch 'short-name'z-x'`, `[^']+` can only anchor its trailing `'` at
the position right after `short-name` (the first literal quote in the
string); the char immediately after that position is `z`, so `(?=\s|$)`
fails there, and no shorter/longer backtrack of `[^']+` produces another
position where a literal `'` even exists. The whole regex fails to match →
`unrecognized` → `die()`. A sanity run (same repo, an honest merge of the
same approved branch, no trickery) still exits 0, so the fix isn't
over-tightened. `dart analyze` clean on the staged file. The new regression
test (`"REGRESSION: a quote inside a branch name cannot truncate to another
branch's record"`, staged, verified present via `git show :path`) plus a
companion `"the lookahead does not reject any legitimate shape"` guard test
(bare / em-dash / `into main` / remote-sync — all four still classify
correctly) are both real, non-vacuous checks, not just asserting the
implementation. **Agreed: fixed.**

## 2. Repro A (deliberate `-m` spoofing) — CONFIRMED still open, CONFIRMED honestly documented, judged acceptable as known-open

Re-ran the exact repro against the same staged snapshot:

```
subject: Merge branch 'legit-reviewed-branch'
[plan-review-record] PASS: branch `legit-reviewed-branch` (platform) has a
converged plan-review record (2 rounds, ground-truth-verified).
REPRO A exit=0
```

Still bypassed, exactly as stated — not fixed, not claimed to be fixed.

Checked the STAGED diagnose-doc's `impact_analysis` (`git show
:docs/diagnoses/2026-07-26-keystone-gate-branch-recovery-defects-d3f8a2.md`)
directly: it names the single-parent bypass and the subject-spoofing gap as
"TWO faces of one architectural property, both with the same fix," quotes my
exact repro command, states plainly "No amount of parsing fixes this — the
input itself is author-asserted," and "it is NOT closed here." Checked the
STAGED closure YAML: `G14` exists, `terminal_state: closed_in_commit`, and
its own `notes:` field says, verbatim, *"the ledger previously overclaimed:
this closes the ACCIDENTAL half only"* and cross-references the unfixed
deliberate half by name. Both are staged (`git show :path` matches the
working tree for both files at these locations — the diagnose-doc has zero
unstaged diff; the closure YAML's unstaged diff, shown below, doesn't touch
G14 or the impact_analysis wording). This is not spin — it correctly narrows
its own prior overclaim rather than quietly redefining "closed."

**Judgment call, since I was asked to make one rather than negotiate one:**
I weighed reachability against precedent and landed on *acceptable as
known-open*, not *blocking*.

- Both the single-parent bypass and Repro A require push access, which is
  the trust boundary this gate has *never* claimed to defend against (it
  defends the honest path against parsing accidents and honor-system drift,
  not against a privileged actor deliberately choosing not to comply — the
  diagnose-doc's own analogy to `--no-verify` is apt: nothing in this repo
  cryptographically stops that either).
- The two are now *architecturally unified* with a stated common fix
  (`github.event.before..after` instead of `HEAD^2`/subject-parsing) rather
  than Repro A being a fresh, unrelated hole bolted onto the side — that's a
  real technical claim I independently understand and agree with, not just
  asserted.
- The task brief that opened this review already established the governing
  precedent: "known-open, deliberately NOT fixed... explicitly a separate
  future unit" was pre-approved for the single-parent bypass. Holding Repro A
  to a stricter standard than its own sibling, now that it's honestly
  documented with the same rigor, would be inventing a new bar mid-review
  rather than applying the one already set.
- What tips this from "could argue either way" to "accept": the batch closed
  the part that *was* free (zero privilege required — any ordinary,
  undeviating `--no-ff` merge could hit it), with proof and tests, and did
  not round Repro A off as "basically the same thing, also fine" — G14 exists
  specifically to prevent that rounding-off.

I want to be explicit that this is not a "the docs are honest so anything
goes" free pass — if the diagnose-doc had said "fixed" or stayed silent on
Repro A, or if closing it required no real redesign (i.e. if this were a
cheap fix being deferred out of laziness), I would still be rejecting. It's
the combination of (a) genuinely requiring the different, larger design the
diagnose-doc describes, (b) honest, specific, cross-referenced documentation
of exactly what remains open and why, and (c) the pre-existing sibling
precedent, together, that makes this a legitimate known-open rather than a
deferral wearing a known-open costume.

## 3. G3/G4 overclaim check — you asked me to actually check this, not assume it

Re-read all three (G3, G4, G14) as staged, in ledger order, as a reader
would encounter them:

- **G3** ("Record-path collision: feat/foo and fix/foo both resolved to
  foo.md") is entirely about `.split('/').last` truncation. That's fully and
  correctly closed — unaffected by Repro A, no overclaim.
- **G4** ("record's own `branch:` field now cross-checked") is, read in
  total isolation, the one a skimmer could over-read as "branch identity is
  now trustworthy, full stop." Read as part of the same ledger, G14 sits a
  few entries below it and explicitly says G4's slug work does NOT close the
  deliberate-spoofing case. I judge this adequate — closure ledgers in this
  repo are meant to be read as a whole document (G9's "REFUTED" and G10's
  self-correcting note are the same pattern already in use), not as
  independently-scoped tweets — but if you want to remove even the
  skimming risk, a one-clause addition to G4's notes ("residual
  subject-spoofing exposure not closed by this — see G14") would make it
  unambiguous without changing anything structural. Not blocking either way.

## 4. P2 items — resolution status, independently verified

**P2-1 (431/626 vs 432/627 count drift) — FIXED, and staged.** Live count
reconfirmed unchanged: `find test -name "*_test.dart"` → 629 total in the
working tree; this batch's own 2 new files live under `test/scripts/`, not
`test/contracts/`, so pre-existing = 627; `find test/contracts -name
"*_test.dart"` → 432. Matches `test.yml`'s comment exactly.
`git ls-files -- 'test/*_test.dart'` / `'test/contracts/*_test.dart'`
(index, not filesystem) → 629 / 432, same numbers. The staged closure YAML
(`git show :docs/audit/ci-governance.closure.yaml`) now reads "432 of the
627" with an explanatory note ("An earlier draft of this entry said
431/626 — the pre-batch count, stale by the test file the ci-speed batch
added"). Agreed and confirmed correct.

**P2-2 (record corpus: 69/68 vs your 70/69) — you were wrong, and I found
why.** Re-ran your exact command, `ls docs/plan-reviews/*.md | wc -l`, from
inside the `ci-governance` worktree: **69**, not 70.
`grep -lE "^branch:" docs/plan-reviews/*.md | wc -l`: **68**. Cross-checked
a third way, bypassing the filesystem entirely: `git ls-tree HEAD --
docs/plan-reviews/` → 69 `.md` blobs. All three agree; this batch's diff
never touches `docs/plan-reviews/` at all (`git diff --cached --stat --
docs/plan-reviews/` is empty), and `main`/`origin/main`/this worktree's HEAD
are all the same commit (`904e6961`, no drift). So there's no environmental
reason for a 69-vs-70 split *within this worktree*.

I found where the extra one comes from: the **shared main integration
folder** (`C:/Upendra/Claude Code/Fitness App`, not this worktree) has an
**untracked** file, `docs/plan-reviews/opt-a-rls-initplan.md`, left over
from unrelated, unshipped work (`git status --short` there shows `??`). It
has `branch: opt-a-rls-initplan` in it. 69 tracked + that 1 untracked = 70;
68 tracked-with-branch + that 1 = 69 — exactly your numbers. If the count
was run from the shared folder (or a `main` checkout that isn't this
worktree), that explains it precisely; §4.13 exists for exactly this kind
of cross-worktree bleed. The diagnose-doc's `impact_analysis`
("70 existing records, 69 already carry one") and the closure YAML's G4
notes ("69 of 70 existing records") and
`plan_review_record_lib_test.dart:193`'s comment ("all 70 existing
records") are all still wrong as staged — none of the three were touched by
either round of edits. **Still open — please fix at these three exact
citations**, using 69/68:
- `docs/diagnoses/2026-07-26-keystone-gate-branch-recovery-defects-d3f8a2.md:79`
- `docs/audit/ci-governance.closure.yaml:51` (G4 notes)
- `test/scripts/plan_review_record_lib_test.dart:193` (comment only, no
  behavior change needed)

This is prose/citation accuracy, not gate logic — it does not block
`accepted` on its own, same tier as before.

**P2-3 (test_core version + "~2.1x") — content is correct, but only in the
working tree, not staged.** `git diff -- docs/audit/ci-governance.closure.yaml`
shows this fix is *unstaged*. I verified it anyway, against the actual pub
cache: `diff` between
`test_core-0.6.15/lib/src/runner.dart` and `test_core-0.6.16/lib/src/runner.dart`
is **byte-for-byte empty** (0 differing lines) — "verified identical in the
0.6.15 and 0.6.16 copies" is correct, not just asserted. On the arithmetic:
I agree these are two different, non-contradictory ratios. Mine (~1.98x)
was `(365/689) / (642/2404)` — per-test relative overhead, a measure of how
disproportionate shard 0's wall-clock share is versus its test share.
Yours (~2.1x) is `(4 × 365) / 689 = 1460/689 ≈ 2.12` — total compute
consumed running all 4 shards versus running the suite once unsharded. Both
are internally correct for what they measure; the now-explicit "4 × 365s =
1460s" spells out which one is meant, resolving the ambiguity I flagged.
Confirmed, agreed. **Not yet staged** (see §5).

**P2-4 (recordBranchFieldMatches frontmatter scoping) — implementation is
correct, but only in the working tree, not staged.** Tested directly rather
than trusting the diff: ran the identical "a `branch:` line embedded in
body prose, no `branch:` in frontmatter" input against both copies of
`recordBranchFieldMatches` as a standalone function call (not the full
gate) —

```
STAGED   recordBranchFieldMatches(body-only branch:, "some-other-branch-entirely") = true
WORKING-TREE  same input = false
```

The working-tree version (with the new `_frontmatter()` helper, scoping to
the text between the first two `---` lines and falling back to whole-file
scan only when no frontmatter fence exists) is correct and does fix the
latent fragility I flagged. The regression test
(`"REGRESSION: a branch: line in the BODY does not vouch"`) is real and
non-vacuous — it asserts both that the true frontmatter `branch:` still
matches AND that the body decoy does not. **Not yet staged** (see §5).

## 5. Staging gap — action item, not a logic defect

`git status` shows three files as `AM` (staged content exists, but further
unstaged edits sit on top): `docs/audit/ci-governance.closure.yaml`,
`scripts/plan_review_record_lib.dart`, `test/scripts/plan_review_record_lib_test.dart`.
Concretely, what's missing from the **staged** diff right now, versus what's
on disk:
- `recordBranchFieldMatches`'s frontmatter-scoping fix (P2-4) + its 2 new
  tests.
- The `test_core` version-agnostic rewrite + explicit 4×365s arithmetic
  (P2-3).

Both are verified correct (§4). Neither is a P0/P1. But as things stand,
committing right now would silently ship without them despite this review
describing them as done. `git add scripts/plan_review_record_lib.dart
test/scripts/plan_review_record_lib_test.dart
docs/audit/ci-governance.closure.yaml` before the commit that closes this
batch.

## 6. Test suite / gates — re-run against current state

`flutter test test/scripts/ --reporter compact` against the full current
working tree (all 5 files under `test/scripts/`, including the unstaged
additions): **63/63 pass, "All tests passed!"** — confirms the headline
number. (Against the staged-only snapshot the count would be 61 — 2 fewer,
since the 2 unstaged tests wouldn't exist to run yet — still fully green;
this is the same staging gap as §5, not a red test.)

Re-ran independently rather than trusting the prior run:
- `dart run scripts/validate_audit_closure.dart` → `[Gate 40] PASS: 11
  closure file(s) validated.`
- `dart run scripts/validate_diagnose_doc.dart docs/diagnoses/2026-07-26-...md`
  → `OK: ... passes diagnose-doc validation`.
- `dart analyze` on all 4 touched/added `.dart` files (current working
  tree) → `No issues found!`

All confirmed.

## 7. Operational note carried forward

The near-miss disclosed in the original review (a scratch script's failed
`cd` risking a `git commit` in the real worktree) remains fully resolved —
re-checked again this round: HEAD is still `904e6961`, `git status --short`
still shows exactly the same file set as at the start of this
re-verification pass. Every check in this re-review used either read-only
git plumbing (`git show :path`, `git ls-tree`, `git diff`, `git status`) or
isolated throwaway repos via `Process.runSync(workingDirectory: ...)` with
`GIT_*` scrubbed and `includeParentEnvironment: false` — never a shell `cd`
into a mutating git command this time.

## Verdict

**Accepted.** Repro B is genuinely fixed and staged. Repro A is genuinely
not fixed, and — after independently verifying the documentation is honest
rather than taking that on faith — I judge it an acceptable known-open item
under the same precedent already governing the single-parent bypass, not a
blocking gap. Nothing else rises above P2. Two concrete, non-blocking
action items remain before this is fully wrapped: (1) `git add` the three
files carrying the P2-3/P2-4 fixes so they actually ship, and (2) correct
"70 existing records / 69 with branch:" to "69 / 68" at the three cited
locations — that number was wrong before this round and is still wrong now,
including in your own re-check, which I traced to a stray untracked file in
the shared main folder rather than this worktree's tracked state.

---

# ORIGINAL REVIEW (superseded by the re-verification above; kept for the record)

Fresh, context-blind, adversarial review of the staged diff hardening
`scripts/check_plan_review_record_exists.dart` (the §4.12 keystone gate).
Read `docs/agent_brief_preamble.md` first. All claims below were verified
against the actual staged files (`git diff --cached`) and, where the hunt
brief asked for adversarial construction, against the **real gate binary**
run inside isolated throwaway git repos (never the real worktree — see the
env-scrubbing note under Finding 1). `dart analyze` was run on all 4
touched/added Dart files (clean), `flutter test test/scripts/` was run
directly (35/35 new tests + 18 pre-existing pass), and every `check_*.dart`
/ `validate_*.dart` gate cited as evidence in the closure YAML was re-run
independently rather than trusted from the diagnose-doc's prose.

The known-open single-parent bypass (HEAD^2 absent → exit 0) is explicitly
out of scope per the brief and is NOT reported below. Finding 1 is a
**different** defect: it requires a genuine 2-parent `--no-ff` merge
(HEAD^2 present, verified `2` parents in both repros).

## Finding 1 — P0 — branch identity is derived entirely from the free-text merge-commit subject; an unreviewed branch can ride an unrelated, already-approved record

**Where:** `scripts/plan_review_record_lib.dart:77` (`_branchRe`), `:90-115`
(`classifyMergeSubject`), `:147-152` (`recordBranchFieldMatches`);
`scripts/check_plan_review_record_exists.dart:161` (subject read verbatim
from `git log -1 --format=%s HEAD`), `:198-199` (`rawBranch`/`branch`
derived from it), `:297` (`recordBranchFieldMatches(content, rawBranch)`).

**The claim this batch makes:** the new `recordBranchFieldMatches` check
was built specifically so that "one branch's approved record" cannot
"satisfy an unrelated branch's gate" (doc comment,
`plan_review_record_lib.dart:137-142`; identical language in
`check_plan_review_record_exists.dart:290-296`; closure YAML G3/G4 both
marked `closed_in_commit`). This is true **only** against the narrow case
the batch tested (an honest, git-generated subject whose slug happens to
collide with another branch's slug, e.g. `hold/mechanic` → `hold-mechanic`).
It is **not** true against a subject that was never honestly generated in
the first place — and the entire identity chain (`classifyMergeSubject` →
`recordSlug` → `recordBranchFieldMatches`) has no source of truth other
than that subject string.

**Repro A — `-m` override (no branch-naming trick needed at all).**
Standard, undocumented-as-dangerous git usage:

```
git checkout -B sneaky-unreviewed-branch main
# ... make an unreviewed, platform-tier change (e.g. touch pubspec.yaml) ...
git commit -m "sneaky change"
git checkout main
git merge --no-ff -m "Merge branch 'legit-reviewed-branch'" sneaky-unreviewed-branch
```

where `legit-reviewed-branch` is a **real, separate, already-merged branch**
with a genuine `docs/plan-reviews/legit-reviewed-branch.md` carrying
`verdict: converged`, `bpass: accepted`, a real `bpass_review:` file, etc.
I built exactly this in an isolated temp repo (copies of the 3 real
`.dart` files + the real `docs/blast_radius.yaml`, `GIT_*` stripped from
the child environment, `includeParentEnvironment: false`, a runtime
toplevel-resolution self-check — the same isolation pattern
`plan_review_record_gate_e2e_test.dart` uses) and ran the **actual** gate
binary against it:

```
Actual merge commit subject: Merge branch 'legit-reviewed-branch'
Actual merge commit parents (2 = real merge): 2

ATTACK (unreviewed branch, spoofed subject) exit=0 (1 = safe/blocked, 0 = BYPASSED)
[plan-review-record] PASS: branch `legit-reviewed-branch` (platform) has a converged
plan-review record (2 rounds, ground-truth-verified).
```

The gate exits **0**. `sneaky-unreviewed-branch`'s actual content was never
reviewed and has no record of its own; it rode `legit-reviewed-branch`'s
review purely because the merge SUBJECT said so. The sanity control (same
repo, same branch, merging `legit-reviewed-branch` for real with git's own
auto-generated subject) also exits 0, confirming the isolation harness and
gate wiring are correct and the divergence is caused only by the crafted
`-m`.

**Repro B — no `-m` at all; an ordinary, default-message merge.** Git
permits a single quote inside a branch name (`git check-ref-format --branch
"short-name'z-unreviewed-extra"` → exit 0, confirmed live). `_branchRe =
^Merge branch '([^']+)'` stops at the *first* `'`, so:

```
git checkout -B "short-name'z-unreviewed-extra" main
# ... unreviewed change ...
git commit -m "unreviewed change"
git checkout main
git merge --no-ff "short-name'z-unreviewed-extra"     # NO -m — git's own subject
```

produced the auto-generated subject `Merge branch 'short-name'z-unreviewed-extra'`,
parsed by `_branchRe` as branch = `short-name` (truncated at the embedded
quote). Against a real `docs/plan-reviews/short-name.md` approved record:

```
git-generated subject: "Merge branch 'short-name'z-unreviewed-extra'"

ATTACK (quote-truncated branch name, default subject) exit=0 (1 = safe/blocked, 0 = BYPASSED)
[plan-review-record] PASS: branch `short-name` (platform) has a converged plan-review record
(2 rounds, ground-truth-verified).
```

This variant is arguably worse operationally: nothing about the merge
command looks unusual (no `-m` override to raise an eyebrow in review) —
the entire attack surface is the branch name chosen at creation time,
weeks before merge.

*(Superseded: Repro B is fixed as of the re-verification pass above — see §1.)*

**Why this is in scope and not the documented single-parent bypass:** both
repros are genuine `--no-ff` merges with 2 parents; `HEAD^2` is present and
inspected. Nothing in the diagnose-doc's `impact_analysis` mentions
subject-text trust as a known-open risk — only the single-parent case is
flagged there, which the author demonstrably knows how to do when aware of
a gap. None of the 35 new tests exercise this: the closest,
`"REGRESSION: a record naming a DIFFERENT branch is rejected"`
(`plan_review_record_gate_e2e_test.dart:186-191`), merges a branch with an
**honest** subject and checks the record *at that branch's own correct
slug path* for an internally-mismatched `branch:` field — a different bug
class (G3/G4) from a subject that lies about which branch was merged at
all.

*(Superseded: the diagnose-doc's impact_analysis now names this explicitly
as known-open — see §2 above.)*

**Suggested direction (not prescribing the fix):** stop trusting the
commit subject as the sole identity source. The cheapest structural
mitigation that fits this design: additionally require that
`docs/plan-reviews/$branch.md` itself appears in
`git diff --name-only HEAD^1...HEAD^2` (i.e., the merged branch brought its
own record) — under a spoofed subject, the attacker's branch never touched
the victim's record file, so this closes both repros above without needing
git-ref ground truth. A fuller fix would derive branch identity from
something the merge-committer cannot freely author (e.g. requiring
`bpass_review`'s own `staged_against:` to reference a commit reachable from
`HEAD^2`), but that's a larger redesign, consistent with how the
single-parent bypass was scoped out as its own unit.

This is a P0: it defeats the stated primary security property of this
batch's central deliverable, is reachable via completely ordinary git
usage (no exotic prerequisites beyond what push access already implies —
the same threat model the authors themselves use to accept the Dependabot
email-spoofing risk), and both variants are live-proven against the actual
shipped binary, not theoretical.

---

## Findings 2-5 — P2 (documentation/numeric accuracy + defense-in-depth; none block on their own)

**2. `docs/audit/ci-governance.closure.yaml` G10 and
`.github/workflows/test.yml`'s own new comment disagree on the same
measurement, and the closure YAML is the wrong one.** G10
(`ci-governance.closure.yaml:124`): *"the contract-tests job re-ran 431 of
the 626 files the unit job already runs."* `test.yml:191-193`: *"432 of the
627 `*_test.dart` files."* Live count in this worktree:
`find test -name "*_test.dart" | wc -l` = **629** total; this batch's own 2
new files (`test/scripts/plan_review_record_lib_test.dart`,
`plan_review_record_gate_e2e_test.dart`) live under `test/scripts/`, not
`test/contracts/`, so pre-existing total = 627. `find test/contracts -name
"*_test.dart" | wc -l` = **432**. This matches `test.yml`'s figure exactly
and contradicts G10's "431 of the 626" by one file. Unlike Finding 3 below,
there's no plausible "counts a not-yet-created file" explanation here —
both texts describe the identical pre-existing state. Fix the number in
the closure YAML for accuracy (does not affect `closed_count`/
`total_findings`, which I independently re-validated via
`dart run scripts/validate_audit_closure.dart` — PASS, 11 closure files
repo-wide, no `deferred:` keys, all terminal states present).

*(Superseded: fixed and staged — see §4/P2-1 above.)*

**3. "70 existing records" / "69 of 70 carry `branch:`"**
(diagnose-doc `impact_analysis`; `plan_review_record_lib_test.dart:157`)
vs. live count: `docs/plan-reviews/*.md` = **69** files right now, 68 with
a `^branch:` line (the one exception, `free-tier-hold-findings.md`,
matches the claimed exception exactly). `docs/plan-reviews/ci-governance.md`
itself does not exist yet on disk. Plausibly the "70th" is this very
batch's own not-yet-authored record (which, once written to satisfy this
same gate at merge time, will necessarily carry its own `branch:
ci-governance` field, making the count self-consistent post-hoc) — noting
this rather than flatly calling it wrong, but it's unverifiable as
currently staged and worth a founder eyeball once `ci-governance.md` is
authored.

*(Superseded: still wrong, root cause identified (stray untracked file in
the shared main folder, not this worktree) — see §4/P2-2 above. My
original "maybe it's forward-counting ci-governance.md" hypothesis turned
out to be incorrect; the real explanation is cross-worktree file bleed.)*

**4. Minor citation staleness in G10's supporting analysis.** Cites
`test_core-0.6.15/lib/src/runner.dart:492-502`; the resolved version in
`pubspec.lock` is `test_core 0.6.16` (verified: `grep -A8 '^  test_core:'
pubspec.lock` → `version: "0.6.16"`). Adjacent patch version, unlikely to
change `_shardSuite`'s slicing behavior materially, but the citation as
written doesn't match the lockfile. Same note's "~2.1x the compute" from
"53% of the wall-clock for 27% of the tests": precise arithmetic gives
365/689 ÷ 642/2404 ≈ **1.98x**, not 2.1x. The raw historical figures
(642 tests, 2404 tests, 365s, 689s, CI run 30188423209) could not be
independently re-verified in this review (no access to that historical CI
run's logs) — flagging the arithmetic-from-the-cited-figures mismatch
only.

*(Superseded: correct and version-agnostic in the working tree, not yet
staged — see §4/P2-3 above. Confirmed my ~1.98x and the corrected ~2.1x are
different, both-correct metrics, not a contradiction.)*

**5. `recordBranchFieldMatches` (and the pre-existing `field()` helper it
mirrors) scan the *entire* record file for the first column-0 `^branch:`
(resp. `^key:`) line, not scoped to YAML frontmatter.** Checked all 69 real
records: every file's first such match is inside its genuine declaration
(confirmed by locating each file's first `^branch:` line number and
diffing against frontmatter boundaries), so nothing currently exploits
this. But it's a latent fragility for a *future* record: one whose
frontmatter omits `branch:` while a later fenced YAML example or quoted
prose happens to contain a column-0 `branch: X` line would be silently
misread as that record's real identity, rather than correctly falling into
the "no branch: field, vouches for nothing" `false` case. Suggest scoping
the regex to the text between the first two `---` lines (falling back to
"before first blank line" for the 2 legacy non-fenced records, e.g.
`c1-drop-dup-water-index.md`, `fix-session-token-stale-authuid.md`, which
use a `#` heading + bare `key: value` instead of `---` frontmatter).

*(Superseded: implemented correctly, not yet staged — see §4/P2-4 above.)*

---

## Verified clean — no defect found (hunt items checked, nothing to report)

- **Remote-sync PASS restriction (`branch == 'main'`) is enforced in the
  gate itself**, not just the lib (`check_plan_review_record_exists.dart:178-183`):
  a non-main sync correctly `break`s out of the switch and falls through to
  the ordinary blast-radius + record-required path, using the *synced*
  branch name (not `'main'`) for slug/record lookup. Matches the e2e test
  `"a genuine \`git pull\` sync of main PASSES"` / the lib test
  `"REGRESSION: a non-main sync is distinguishable from a main sync"`.
- **`ms.branch!` (line 198) is never null when reached.** Every
  `MergeSubjectKind` that reaches that line (`branchMerge`,
  `pullRequestMerge`, and `remoteSyncMerge` with `branch != 'main'`) always
  sets `branch` in the lib; the two kinds that could carry a meaningfully
  "absent" identity (`foreignPullRequest`, `unrecognized`) both `exit()`
  inside the switch before line 198 is reached. `exit()` from `dart:io` is
  `Never`-typed, confirmed by `dart analyze` being clean on a switch whose
  non-terminal-looking cases end in `exit(die(...))` with no trailing
  `break`.
- **`paths` (the lazy `Iterable<String>` at line 215) is safe to reuse.**
  It wraps a concrete `List<String>` (from `diff.split('\n')`) via
  `.map().where()`; Dart iterables built this way re-evaluate from the
  underlying list on every fresh iteration, so the 4 separate consumptions
  (blast-radius loop, `dependabotDiffIsManifestOnly`, the `offending`
  computation, the final PASS message's `.join`) are all consistent and
  correct, not a single-pass-then-empty generator.
- **Dependabot exemption is correctly positioned** after the `< account`
  early-exit and before the record requirement, keyed on `rawBranch`
  (pre-slug, correct per the lib's own doc comment), and
  `.github/workflows/**` is correctly excluded from
  `dependabotAllowedPaths` (confirmed: `dependabotDiffIsManifestOnly(['.github/workflows/test.yml'])`
  → `false`, and the corresponding test exists and is non-vacuous). The
  author-email check's spoofability is explicitly and accurately
  self-documented by the authors as the weaker of the two conditions
  (`check_plan_review_record_exists.dart:244-249`) — not a fresh finding.
- **Coverage is not lost by deleting the `contract-tests` job.**
  `dart_test.yaml` defines only the `golden` tag; `grep -rl "@Tags"
  test/contracts` → 0 files; `grep -rl "@TestOn" test/contracts` → 0 files;
  no nested `dart_test.yaml` under `test/`; repo-wide grep for `needs:.*
  contract` → 0 hits; the one remaining textual reference to
  `contract-tests` in `test.yml:252` is a historical comment, not an active
  dependency. `analyze-and-unit-test`'s `flutter test test/ --exclude-tags
  golden` therefore genuinely runs every file that used to live under the
  deleted job. YAML re-parsed with `python -c "import yaml; ...")"` after
  the edit — valid, job list is exactly `[analyze-and-unit-test,
  deno-edge-functions, audit-gates, plan-review-record, supabase-tests,
  build-check]`, no orphaned structure.
- **Test quality — both new files pass as authored**
  (`flutter test test/scripts/` → 35/35 new + 18 pre-existing green).
  **Non-vacuousness independently proven**, not assumed: applied the
  actual pre-fix regexes/logic (single unanchored `Merge branch` regex
  missing the PR shape; `.split('/').last`; the round-2 end-anchored
  `^Merge branch '([^']+)'(?:\s+into\s+\S+)?\s*$`; the round-2 unconditional
  remote-sync pass) to the exact strings the new REGRESSION-labeled tests
  assert against, in a standalone script — every one fails/mismatches
  exactly as the tests assume, confirming they'd have caught the
  regression they're named for. The e2e harness's env-scrubbing
  (`includeParentEnvironment: false` + explicit `GIT_*` strip +
  a runtime `git rev-parse --show-toplevel` self-check that throws
  `StateError` if resolution doesn't land inside the temp dir) is sound in
  principle and was exercised successfully by my own two repro scripts,
  built the same way, from inside this same worktree.
- **Numeric claims independently verified correct:** "49 of the 174 merges
  on main" use the non-end-anchored convention (precise regex
  reconstruction against `git log main --merges`: 174 total merges, 80
  `Merge branch '...'` subjects, 31 match the old anchored form bare-or-
  `into`, 80−31=49 — exact match); "30 pure + 5 end-to-end" tests (manual
  enumeration of both files, including the 4-subject loop in
  `plan_review_record_lib_test.dart` = exactly 30, plus 5 in the e2e file);
  commit `7c973ee3`'s subject and its ancestor-of-`main` status (both
  confirmed live); live GitHub repo settings via `gh api
  repos/upendraprasad19/AVYA` — `allow_squash_merge: false,
  allow_rebase_merge: false, allow_merge_commit: true` — exact match to
  the diagnose-doc's `touched_layers_checked` tier-11 claim.
- `dart analyze` clean on all 4 touched/added `.dart` files (both scripts,
  both test files). Independently re-ran `validate_audit_closure.dart`
  (Gate 40), `check_blast_radius_coverage.dart`, `check_ci_flutter_version.dart`,
  `check_gate_scripts_wired.dart`, and `check_no_deferral_euphemism.dart` —
  all PASS against the staged state.

## Operational note (not a finding against this diff)

Mid-review, a scratch shell script of mine failed a `cd` (missing
`set -e`, wrong assumption about cwd persistence across tool calls) and
fell through to running `git add -A` / `git commit` **in this actual
worktree** before the repo's real `git_safety_hook.dart` blocked/aborted
it. Verified immediately after: `git log -1` still shows `904e6961` as
HEAD and `git diff --cached --stat` still shows the identical 9-file,
1142-insertion staged diff described at the top of this review — nothing
was committed or altered. Mentioned only for the record; it does not
implicate anything in the diff under review, and every finding above was
produced afterward using an isolated-subprocess pattern (mirroring
`plan_review_record_gate_e2e_test.dart`'s own approach) specifically to
avoid repeating it.

## Original verdict (superseded)

~~Rejected.~~ See the re-verification section at the top of this document
for the current verdict (`accepted`).
