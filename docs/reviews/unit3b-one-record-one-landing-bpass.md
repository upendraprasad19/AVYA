---
branch: unit3b-one-record-one-landing
diagnose: a7f3c2
date: 2026-08-05
blast_radius: platform
pass: B
verdict: accepted
---

# B-pass — unit3b-one-record-one-landing (diagnose a7f3c2)

Self-initiated per §4.3 (≥account) and required independently at `platform` per
§4.12.3 — the ship-dark tiering relaxes the *round count*, never `bpass`.

Run because the ×2 rounds inherited from `c9f4e1` do **not** carry a B-pass that
covered 3b. Writing `bpass: accepted` on the strength of those rounds alone would
have been an unearned field in a gate-parsed record, which is precisely the
failure this gate exists to prevent.

**Verdict: accepted.** No P0/P1. Two P2-class observations, both already stated
at the code rather than discovered here.

## Attacked by execution, not inspection

**The tests discriminate in both directions.** A test suite that passes tells you
nothing until you know it can fail:

| mutation | expected | observed |
|---|---|---|
| `return null` first (never fires) | positive test fails; absence tests pass | **only** test 1 failed |
| `return '<msg>'` first (always fires) | absence tests fail | **all 3** failed |

The always-fires case failing test 1 as well is the stronger result: test 1
asserts the fixture branch name `reuse-stale` appears in the output, not merely
that the `NOTE (possible stale reuse)` marker did. A test pinning only the marker
would have passed under that mutation. This is the assertion-strength lesson from
Unit 1 (`GuardedBox.empty`) applied correctly here already.

Hygiene: the script was restored from a byte-copy after each mutation and
re-verified by md5 (`a9667c1992d6ef08907b6f9283ba51c9`), with a grep confirming
no `MUTATION` residue survived into the staged diff.

**The live run was made non-vacuous.** The gate short-circuits when the branch is
not `main`. An earlier run in this session returned PASS purely on that
short-circuit — proving nothing. Re-run with `GITHUB_REF=refs/heads/main` and a
real `PUSH_BEFORE`, it evaluates for real.

**The caller contract was read, not assumed.** `branch = recordSlug(rawBranch)`
at `:641`, and the call passes the slugged path (`$_recordsDir/$branch.md`) while
matching on `rawBranch`. Same raw branch ⇒ same slug ⇒ both landings resolve to
the same record path, so the comparison is apples-to-apples. A many-to-one slug
cannot yield a false positive: `priorMs.branch != rawBranch` rejects a different
raw branch before any blob is read. Ordering is also right — it runs *before*
`_validateRecord`, so a missing record produces no NOTE (both `_gitBlob` calls
return null) and then fails properly in the validator rather than being masked.

**History-walk edges checked.** `git log --first-parent $sha^1` walks strictly
before the landing, so a landing cannot match itself. A root commit with no
parent makes `_gitOrNull` return null ⇒ null ⇒ no NOTE, which is the correct
conservative outcome for an advisory. `git log` is reverse-chronological, so the
first match is genuinely the most recent earlier landing.

## P2s — pre-stated at the code, confirmed accurate

- **P2-A** — the check does not verify the PRIOR landing's own tier, so a
  leftover record from an unrelated situation could in principle be compared
  against. No known live instance. Stated in the function's doc comment.
- **P2-B** — point-in-time blob comparison, not the range walk
  `gate-input-family.md` vetted, so "byte-identical after two edits that cancel
  out" is indistinguishable from "genuinely re-reviewed". Narrow, and stated.

Both are acceptable *because the check is advisory*. Neither would be acceptable
at `fail()`.

## Bounded blast radius is the reason this is accepted, not the absence of flaws

A bug anywhere in this function costs at most a spurious or missing stdout line.
It cannot block a correct merge, and it cannot pass a merge the pre-existing
checks would have failed — the `_validateRecord` path is untouched, which the
still-green pre-existing test "a platform change with NO record still FAILS
(gate not defanged)" confirms directly.

Round-1 finding #9 (the `remoteSyncMerge`-shaped subject bypasses detection) is
recorded at the code as a must-close-before-`fail()`. Flagging here that the
promotion commit is where the full §4.12 ×2 applies again — the lighter path was
never taken for this landing, but the promotion must not inherit *this* record.
