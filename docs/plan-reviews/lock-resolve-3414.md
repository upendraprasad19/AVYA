---
branch: lock-resolve-3414
date: 2026-11-21
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/lock-resolve-3414-bpass.md
---

# Plan-review record: lock-resolve-3414 (platform; one dependency file, tier M)

Plan: `docs/plans/2026-11-21-lock-resolve-3414.md` (v4). The change is one tracked dependency file, `pubspec.lock`, replaced by the file `flutter pub get` writes under Flutter 3.41.4 (the version CI, Vercel and `.fvmrc` pin), plus the process documents and two board entries (OI-520, OI-521). `pubspec.yaml`, `lib/` and CI are untouched.
`bpass: accepted` since the `/code-review` B-pass ran on the committed three-dot diff `origin/main...510a641c` (two fresh read-only seats, 15 findings: 3 P2, 12 P3, no P0 or P1; every one accepted and folded, none rejected; `docs/reviews/lock-resolve-3414-bpass.md`). The verdict in that file is the coordinator's triage, self-attested. This record lands in the same commit as the review and the fixes it names; no hash names the review (the staged-hash gate `check_code_review_pass_exists.dart` is catastrophic-only), so there is no fixed point to break. The tier is stated from `docs/blast_radius.yaml`: `pubspec.lock` is `platform` (`:678`), every other path of the branch is `docs/**`, `feature` (`:579`).

## Round 1 (context-blind Sonnet, read-only, on plan v1)

7 findings: 1 P1, 5 P2, 1 P3. Verdict: NOT executable as written. Every finding was checked against the code by the coordinator before it was folded (table in the plan). Material fixes: claim C2 was false as worded because `meta`, `test` and `flutter_riverpod` are imported directly (F11), so it was re-derived with an import count over all 31 names; `test` was found to be a hidden transitive dependency (F12), now OI-521; the recurrence risk was understated, now OI-520; a verification that could not tell the two locks apart was replaced by two scratch-folder acceptance checks; the writer list and the gate demands (C4) were corrected against `scripts/plan_review_record_lib.dart` and `scripts/check_plan_review_record_exists.dart`.

## Round 2 (a fresh context-blind Sonnet, read-only, on the HARDENED plan v2)

8 findings: 3 P2, 5 P3. Reviewer verdict: NOT CONVERGED until folded; no P0 or P1 was open. Every finding was re-measured by the coordinator. Material fixes: the board entries conflicted with `main` (OI-519 appended at the same place), so the branch was synced through `scripts/sync_with_main.sh --commit` first and the entries appended after the merge; the cause was MEASURED instead of called unknown (`--enforce-lockfile` exits 0 at `2c2b3496` and 65 at `a6c1825d`; the committed lock asks for `riverpod` 3.4.3, which declares `sdk: ^3.12.0`, against Dart 3.11.1); the commit order and the review-file naming were written down.

Why `converged` is recorded after a "NOT CONVERGED" reviewer verdict: the round 2 findings were mechanical or evidence that was then measured and written down, no P0 or P1 was open, the change itself (one lock file with a reproducible hash) was confirmed by both reviewers and by the coordinator, and every finding has a disposition. A third round was NOT run. This follows the precedent of `docs/plan-reviews/play-billing-fallback.md`. It is the coordinator's judgement, self-attested, and the B-pass is where it was tested again: the B-pass found no merge-blocking issue and its 15 findings changed wording, citations and process documents, not the change.

## Ground-truth verification

Both plan reviewers and both B-pass seats verified claims against the live worktree at file:line, and every number the plan states was re-derived by the coordinator. The lock itself was verified by running, in scratch folders: `flutter pub get --enforce-lockfile` exits 0 on the new pair and 65 on `main`'s, with the lock hash `B990F94F1EB4B65BDB392AA659CF6180BC44F1930D4345F8D2669767986AD7C2` unchanged; a plain `pub get` leaves the tracked files unchanged; the lock's 230 hosted entries all match the pub cache's integrity digests. NOT verified by anyone offline: the pub.dev facts (`sdk: ^3.12.0` of `riverpod` 3.4.3; its dependency on `test_api`), which the plan labels as network facts; and whether Dependabot applies an `ignore` rule to a transitive entry.
