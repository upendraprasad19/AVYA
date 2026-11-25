---
reviewed_at: 2026-11-25T08:10:00+05:30
staged_against: 37adbd98
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [guard_without_its_mirror, writer_reader_drift, test_green_for_the_wrong_reason, blast_radius_mismatch, secrets_in_tree]
findings_count: 7
verdict: accepted
---

# Code Review: ci-integration-on-pr (PR #341) at 37adbd98

Scope: `git diff cf988f07..37adbd98` (15 files): the integration job on pull requests with its shared concurrency
group (`.github/workflows/test.yml`), the merge wrapper's new class `prTimeSkippableJobs`
(`scripts/safe_pr_merge_lib.dart`), the lost-status counter and `rebuildOnLostStatus` (`test/helpers/spawn.dart`,
`test/helpers/sync_cli_fixture.dart`), their tests and docs. CI's full suite was green on the reviewed SHA (run
45531579264; the integration job ran on the pull request and both of its test steps passed). One fresh Sonnet
reviewer, read-only, no conversation context. 0 P0, 0 P1, 2 P2, 5 P3.

## Finding 1 - P2 - guard_without_its_mirror
- **file:line:** test/contracts/ci_integration_job_on_pr_test.dart `integrationJobProblems`
- **claim:** the contract test pinned the job-level `if:`, name and concurrency and the announce step's shell, but nothing at step level. `continue-on-error: true` on a test step or on the job, `|| true` after `flutter test`, an `if: false` on the announce step, or an unmapped secret would leave a job that now gates merges green on any failure, with the test green.
- **verification:** read against the test; none of the four shapes was looked at.
- **fix:** the test refuses any `continue-on-error`, any `||` outside the job-level `if:`, any step-level `if:` other than the four-secret guard on exactly two steps, anything but exactly the two `flutter test` commands, and a secret not mapped from `secrets.<name>`. Seven in-test mutants, each red for its own token; one mutation of the REAL workflow (`continue-on-error: true` on the first test step): 3 red.
- **status:** fixed

## Finding 2 - P2 - test_green_for_the_wrong_reason
- **file:line:** test/contracts/ci_integration_job_on_pr_test.dart `_concurrency`, the group-reuse regex
- **claim:** the hand-written reader built a map, so `queue: single` followed by `queue: max` read as `max`; and a second job using the group in QUOTED form was not counted.
- **verification:** by reading; both shapes pass the old reader.
- **fix:** a repeated key is kept under `duplicate <key>` and refused as an unexpected key; the group is counted as plain text over the uncommented workflow. Mutants for both, red.
- **status:** fixed

## Finding 3 - P3 - test_green_for_the_wrong_reason
- **file:line:** the same file, the `[secrets]` regex
- **claim:** the lazy `(?:.*\n)*?` only required an `exit 1` just before the `elif`; an `exit 1` moved behind an unreachable branch passed.
- **fix:** the four lines are pinned consecutively (the branch, its one message, `exit 1`, the warning branch). Mutant red.
- **status:** fixed

## Finding 4 - P3 - note
- **claim:** whether GitHub HONOURS `queue: max` could not be verified by reading.
- **status:** accepted. GitHub accepted the key (run 45531579264 parsed and ran). Whether a second job waits rather than cancels needs two runs of the NEW workflow at once, which one pull request cannot produce before it is on `main`; if the key were ignored the outcome is a cancelled job, which the merge wrapper refuses and a re-run cures. Read on the first overlap after the merge (closure ledger, QUEUE-HONOURED).

## Finding 5 - P3 - note
- **claim:** about 12 queued jobs exhaust `land_pr`'s 60-minute wait; pull-request test code runs with the QA account before review.
- **status:** accepted, both stated in docs/architecture/hooks.md and diagnose b7e3c1.

## Finding 6 - P3 - note
- **claim:** `rebuildOnLostStatus` relies on `build` being synchronous; nothing enforces it.
- **status:** accepted; the doc comment states it and the one caller complies.

## Finding 7 - P3 - note
- **claim:** the bare version-bump landing now waits for the job too.
- **status:** accepted, stated in hooks.md.

## Attacks that found nothing
`_judgeCheckRuns` for duplicate names, re-runs in both orders, a queued run with a null conclusion, a cancelled run
with a higher id than a success, `skipped` before or after a real run; `CiWatch`, `_waitCi`, `safe_pr_merge` with the
new class; `late final T value` (read only when no error), a nullable `T`, the `finally`, reentrancy; the counter in
both loops; `SyncCli.create` with no lost status (one build, as before); the `if:` expression's precedence and quoting;
the announce step under `bash -e`; the docs against the code. No surviving mutant was found for the merge wrapper,
`rebuildOnLostStatus` or the counter.

## Founder triage notes
None needed: no finding changes behaviour the founder decided.

## Tuning entry
- **2026-11-25** - blast-radius platform - 7 findings in one round; 0 false_alarm; tuning: none to the lens set. Both P2 were in a hand-written reader of a YAML workflow (second time in two days, after the Dart-source reader of ci-sweep-split): a contract test over a CI job that GATES MERGES must also pin the ways the job can pass while failing (`continue-on-error`, `||`, a step `if:`), and a hand-written map reader must refuse a repeated key. Added to the brief template as an explicit question for the next workflow review.
