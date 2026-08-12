---
branch: ci-reconciler
date: 2026-08-12
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/ci-reconciler-bpass.md
---

# Plan review — ci-reconciler (post-push CI reconciler)

## What this batch does

`safe_push.sh` proves a push LANDED; it cannot know what CI concludes, because CI runs
asynchronously after it returns. Nothing in the repo closed that gap — a red run on a pushed branch
was noticed only if someone remembered to look. This adds arm-on-landing plus a warn-only
SessionStart reconciler.

## The spec problem, stated up front

Task #7 ("Build the post-push CI reconciler (arm + warn, never block)") predated the session and an
exhaustive search of the repo and harness memory found **no spec** — no OI, no ADR, no memory file.
The title was the only artifact. The plan therefore declared itself an **inference** rather than a
rediscovered design, grounded in three verified facts (`test.yml` triggers only on `main`/`develop`
pushes + PRs, so ~20 of ~29 branches get no CI until merged — ADR-0018; `safe_push.sh` has no CI
awareness and nothing consumes its exit code; the only `gh run list` logic in the repo is
duplicated inline twice in `build-apk.md`). Founder approved the inference before implementation.

This mattered: the repo's own cautionary tale is `check_open_issues_reconciled.dart` — a script
cited across CLAUDE.md and the OI board as shipped, that was never written, and whose absence read
as coverage for 70 days. A similarly-named tool was the last place to repeat that.

## Review rounds

**Round 1** (context-blind, Sonnet) — 4 findings, verdict *needs-revision*. Headline: the arm step
was caller-invoked "to avoid touching freshly-hardened `safe_push.sh`", which conflates *don't touch
the verification internals* (correct) with *don't add any line at all* (not the same risk). An arm
that depends on remembering to run it decays — §4.13 point 6's "everything with a gate holds,
everything on intention decays". Moved into `safe_push.sh`'s LANDED path, `|| true`-wrapped. Also:
reuse `_git_lock.sh`; `(branch, sha)` dedup key; drop a fabricated CLAUDE.md quote.

**Round 2** (on the hardened plan) — **2 BLOCKING defects inside round 1's own corrections**, which
is precisely why §4.12 mandates a second pass:
1. `_git_lock.sh` is **unusable from Dart** — no CLI entry point, releases via the *sourcing
   shell's* EXIT trap, so a `sh -c` acquire would release before any Dart I/O ran. Round 1
   recommended it; I confirmed the lock *existed* and never confirmed it was *usable* — verified
   input, unverified conclusion. Worse, it is the git lock: a pre-push suite holds it for minutes,
   so blocking session start behind it would violate this hook's one contract.
2. The stale-warning discriminator said "main/develop **or a branch with an open PR**" — prose with
   **no mechanism**; neither library could determine PR state.
Both resolved by *removing* a mechanism rather than adding one, so the design got smaller after
round 2 than before it.

**Round 3** (scoped to the two rewrites) — confirmed both were genuinely resolved rather than
relocated; found 3 spec gaps in the replacements: no test for the merge-resurrection case, "closes
the lost-update window" overclaimed (it narrows one), and the temp file's location unspecified
(a `Directory.systemTemp` file can cross volumes and silently degrade `renameSync` to non-atomic
copy+delete). All three folded in.

**Not a split signal (§4.12.1).** Findings fell 4 → 2 blocking → 3 spec-only while the design
shrank. Rounds 2 and 3 independently reached the same conclusion: one hook, two pure libs, one
shell appender; no piece has standalone value.

## Ground truth verified

- `docs/blast_radius.yaml:185` `.claude/settings.json` = platform; `:256` `scripts/**` = feature
  catch-all. Confirmed by reading, and by running the classifier on the staged diff → `platform`.
- `.claude/settings.json` SessionStart held exactly two entries before this change.
- `check_gate_test_ledger.dart` filters `startsWith('check_') && endsWith('.dart')`, so the new
  non-`check_`-prefixed files are genuinely outside rule 24. No ledger entry required.
- `check_bugfix_commits_have_diagnose.dart` keys on `^(fix|bug|regression)`; this commit is `feat:`,
  so rule 22's diagnose-doc requirement does not apply. (New capability, not a bug fix.)
- Dart's `renameSync` doc-comment (read in this machine's own SDK) confirms it removes an existing
  target but cannot cross filesystems — the reason the temp file is co-located.
- OI-107 confirmed the next free number against `open_issues.md`, `OPEN_INDEX.md` and
  `closed_issues.md`.

## Mutation proofs (rule 21 — tests that FAIL without the code)

Each mutation was the shape a real regression takes, and each lib was verified byte-identical to its
pre-mutation backup afterwards:

| Mutation | Result |
|---|---|
| Drop the `initialRead` guard in `mergeConcurrentArrivals` | 2 red — `Expected ['ccc333']`, `Actual ['aaa111','ccc333']`; a resolved entry resurrected |
| Remove the `createdAt` sort in `queryLatestRunForSha` | 2 red — picks run `10` (older **failure**) over `11` (newer **success**): a re-run that fixed a red build would still report red |
| Drop `develop` from `ciTriggeringBranches` | 2 red — a stale `develop` push silently reclassifies to "expected", losing the warning |
| Remove the arm call from `safe_push.sh` | 2 red — including the behavioral one: `Expected: true, Actual: false`, no state file after a genuinely landed push (this is the one that matters, because the call is `\|\| true`-wrapped and would otherwise fail silently) |

## B-pass

`docs/reviews/ci-reconciler-bpass.md` — 4 findings, 1 P1 + 2 P2 fixed, 1 P2 rejected with reasoning.

The P1 is worth restating here: `reconcile_ci.dart` conflated "gh is broken" with "CI never ran",
emitting a confident *"check whether Actions is enabled"* when the real fault was a local expired
token. That is the **same conflation class** as the `safe_push.sh` bug fixed one day earlier
(diagnose `d4f9b2`: empty `ls-remote` meaning both "ref absent" and "probe unreachable") —
re-committed inside the tool built to complement that very fix. Knowing the pattern by name did not
prevent it; the reviewer caught it by *running the script with `gh` stripped from `PATH`* and
getting byte-identical output. Fixed with an explicit `lookupFailed` state and a null-vs-empty
lister contract.

The B-pass also correctly flagged that platform tier `requires: feature_flag` and this batch had
none — closed with a kill switch (`.claude/.reconcile_ci.disabled`, checked before any I/O),
so the registry requirement is met rather than deviated from.

## Verification

- 49 tests across 4 files, all green; `flutter analyze` clean for every new/touched file.
- End-to-end against real infrastructure: a genuinely green SHA resolved and dropped silently; a
  genuinely red SHA (`1e981c82`) produced a warning naming the actual failing job
  ("Plan-review record (>=account merge-to-main)") and its run URL.
- Kill switch verified to suppress all work and leave state untouched.
- `git check-ignore -v` confirms all three machine-local paths are ignored.

## Deliberately out of scope

Migrating `build-apk.md`'s two inline `gh run list` copies onto the new helper — **OI-107**. Gate
3.5 gates every APK release; rewriting the highest-stakes `gh` call site in service of a
session-start warn-only tool is the wrong order. The helper should earn trust where a mistake costs
a spurious warning before it is put where a mistake costs a bad release.
