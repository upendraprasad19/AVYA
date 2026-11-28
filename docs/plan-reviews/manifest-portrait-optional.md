---
branch: manifest-portrait-optional
date: 2026-11-22
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
---

# Plan-review record: manifest-portrait-optional (account; `android/**`)

Plan: `docs/plans/2026-11-22-manifest-portrait-optional.md`. One unit: a `<uses-feature android:name="android.hardware.screen.portrait" android:required="false"/>` in `android/app/src/main/AndroidManifest.xml` plus a presence-only contract test.

## How this record came to be late

The change was built and pushed (PR #318) before its tier was known: `blast_radius_from_diff.dart --staged` fails open on a flag it does not take and printed `feature`; measured by path, `android/**` is `account` (`docs/blast_radius.yaml:674`), and the merge gate (`land_pr.sh`, `record-failed`) caught it. The plan and both rounds therefore ran against the BUILT diff, not before it. No B-pass was run as a separate `/code-review` invocation (`bpass:` is required only from platform up); round 2 read the built diff and the test line by line, which is the substance of lenses 1, 3, 6 and 7, and that is the only review of the built code.

## Round 1 (context-blind Sonnet, read-only)

Verdict NOT CONVERGED. Material finding (P1/P2): the plan, the manifest comment and the test text said `MainActivity` is portrait-locked; the only `screenOrientation` is on `com.yalantis.ucrop.UCropActivity` and `MainActivity` rotates (coordinator re-read the manifest: confirmed; the error was the coordinator's grep of the string and an unchecked assumption, repeated to the founder in chat). The edit stays right because aapt derives the implied feature from any activity. Also: C2 unverified for transitive Maven libraries (empty Gradle cache on the VPS; 23 pub plugins checked, none declares `screen.portrait`; `mobile_scanner` declares camera optional); the merger can let a library's `required="true"` win; test case 3 matched the crop lock and mis-described it. Folded: comment, test header and case 3 rewritten around `UCropActivity` (mutant dropping the lock reddens it), plan C1/C2/C3/C5 corrected.

## Round 2 (a fresh context-blind Sonnet, read-only, on the revised plan and the built diff)

Verdict NOT CONVERGED on three mechanical points, all folded and re-checked by the coordinator: (1) the plan claimed `/build-apk` prints the merged manifest; `grep` of `.claude/commands/build-apk.md` finds no such step (confirmed), so the check is now `docs/operations/GO_LIVE_CHECKLIST.md` row 5.9 with the `bundletool dump manifest` command; (2) the failure action lacked `xmlns:tools` on the manifest root (it has only `xmlns:android`), now stated; (3) the HEAD commit message still says MainActivity: not amended (the branch is pushed; no force-push), superseded by a follow-up commit and stated in the PR body. Confirmed clean by the reviewer: one orientation lock in the whole manifest; XML well-formed and the element is a direct child of `<manifest>`; the two other manifest-reading tests are unaffected; no doc or nested CLAUDE.md mentions the lock; rollback is a revert.

`mechanical_only: true` for round 2 (every finding was a wording or step fix, none changed the unit).

## Ground-truth verification

Both reviewers and the coordinator read the live worktree (file:line): manifest activities and `uses-feature` count, the 23 plugin manifests, the readers of the manifest in `test/` and `scripts/`, `blast_radius.yaml:674`, and the `build-apk.md` grep. Four mutants on the original test (`required="true"`, element deleted, element moved into `<application>`, lock dropped) each reddened one test; the rewritten case 3 was mutated again (UCropActivity lock to `unspecified`: red).

## Open until the next AAB

Whether a library forces the feature back to required is not provable on this VPS. It is owned by GO_LIVE_CHECKLIST row 5.9 and the plan's failure action; the Play Console warning on the first build carrying this change is the proof.
