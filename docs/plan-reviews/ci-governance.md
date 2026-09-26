---
branch: ci-governance
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/ci-governance-bpass.md
---

# Plan review — ci-governance (keystone-gate hardening + platform tiering + CI de-duplication)

## What shipped

The §4.12 keystone gate (`scripts/check_plan_review_record_exists.dart`) is the repo's single
structural enforcement point for plan quality, and it had three branch-recovery defects and **zero
test coverage**. This batch fixes the defects, gives it its first tests, and closes the
self-referential hole where changing the review gate cleared no review gate.

- **Merge-subject recovery** now handles all three real shapes: `Merge branch 'X'` (any trailing
  description), `Merge pull request #N from owner/X` (owner-guarded — the repo is public), and
  `Merge branch 'X' of <url>` as a remote sync that passes **only** when X is `main`.
- **Slug** strips a leading `origin/` then maps `/`→`-`, replacing `.split('/').last`, which
  truncated every slashed branch and collided `feat/foo` with `fix/foo`.
- **`branch:` cross-check** — the record must name the branch being merged, scoped to frontmatter.
- **Dependabot exemption**, content-verified: `^dependabot/` waives the record only when every commit
  on the merged side is authored by Dependabot AND the diff touches only `pubspec.yaml`/`pubspec.lock`.
  `.github/workflows/**` is deliberately excluded.
- **Platform-tier promotion** of the gate, the new lib, and the tier-*deciding* machinery.
- **`contract-tests` job deleted** — a strict subset of the unit job.

Repo merge settings changed out-of-band (before-state recorded): `allow_squash_merge` and
`allow_rebase_merge` **true → false**, `allow_merge_commit` unchanged.

## Review rounds

**Round 1 — NOT CONVERGED, four P0s.** It refuted two planned units outright, both verified rather
than argued: a `check_repo_merge_settings.dart` gate could not work (this repo's
`default_workflow_permissions` is `read`, and merge settings need write — confirmed by an anonymous
API probe showing the field absent without push access), and 4-way sharding would *cost* ~2.1×
compute (`test_core`'s `_shardSuite` slices within each suite after load, so every shard compiles
every file). It also caught that my wiring plan omitted `pre-commit.sh`'s own case-block, which would
have run a network call on every local commit and blocked offline work. Per §4.12.1 the unit was
split; only the converged piece proceeded.

**Round 2 — NOT CONVERGED, one P0 that was mine.** Fixing the PR-merge shape, I end-anchored the
branch regex, which rejects `Merge branch 'X' — <description>` — **49 of the 174 merges on `main`**,
including `904e6961`, the merge immediately before this batch. It would have reddened `main` on the
very next merge, including this one. **All 25 pure-helper tests passed against it**, because they only
exercised ` into Y`. That is precisely the defect class §4.12.1 says round 2 exists to catch: the
corrections themselves introducing new defects. Round 2 also found that my new remote-sync PASS exited
0 *before* blast-radius was computed, making any subject ending `' of x'` a craftable bypass.

## Ground-truth verification

Every load-bearing claim was verified by the author against source or live state, not taken from
reviewer prose — and two reviewer claims were checked and corrected in opposite directions:

- The anchor regression was reproduced directly against this repo's own merge subjects before accepting it.
- `test_core`'s `_shardSuite` was read at source; confirmed byte-identical across the 0.6.15 and
  0.6.16 cache copies, so the conclusion is not version-specific.
- `default_workflow_permissions: "read"` confirmed live; field-absence confirmed by anonymous probe.
- **Round 2 was wrong about the record corpus** (it said 68 of 69) — but on re-check **the B-pass was
  right and I was wrong**: I had counted `ls docs/plan-reviews/*.md` in the shared main folder, which
  includes an untracked leftover. The tracked corpus is **69 records, 68 carrying `branch:`**. Every
  citation was corrected to the tracked basis.

## B-pass

`docs/reviews/ci-governance-bpass.md`, verdict **accepted** (line-anchored, single occurrence).

First pass returned **rejected** with a P0 in two halves. The *accidental* half was real and is fixed:
git permits a single quote **inside** a branch name (`git check-ref-format --branch "short-name'z-x"`
succeeds), so an ordinary merge yields `Merge branch 'short-name'z-x'` and the capture truncated onto a
different branch's record. A `(?=\s|$)` lookahead now makes that unrepresentable — ambiguous subjects
fail loud.

The *deliberate* half — `git merge --no-ff -m "Merge branch 'other-branch'"` — is **not fixed and not
claimed fixed**. Branch identity comes from author-asserted free text; no parsing repairs that. The
reviewer's sharpest point was not the exploit but that my closure ledger marked G3/G4
`closed_in_commit` while it remained open. That overclaim is corrected: it is now documented as face
(b) of the same architectural property as the single-parent bypass, with the same fix.

The B-pass also caught that four files had unstaged edits sitting on top of the index (`AM`) — my
later fixes would have silently not shipped.

## Known-open, explicitly not closed here

Branch identity derives from the merge subject and `HEAD^2`. Both the single-parent bypass and
deliberate subject-spoofing follow from that, and both need the same fix: evaluate the pushed range via
`github.event.before..after` rather than the subject. That is a materially different design and gets
its own reviewed unit. **This batch does not make the gate hold against a determined author** — it
makes the gate stop mis-firing and stop mis-resolving by accident.
