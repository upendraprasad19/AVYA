# Plan: integration tests on pull requests (OI-527) and a rebuild for a fixture hit by a lost status (OI-528)

Branch `ci-integration-on-pr`. Founder go 2026-11-25 ("let's do 2 and 3"). Tier: M, blast radius platform
(workflow + merge wrapper + test helpers). Execution mode: inline, one writer. No product code changes.
Revision 2 (after review round 1; its findings are in section 6).

## 1. Measured facts (2026-11-25)

1. `.github/workflows/test.yml:637`, job `supabase-tests` (name `Supabase Integration Tests`):
   `if: github.event_name == 'push' && github.ref == 'refs/heads/main'`. It never runs on a pull request.
2. The last 25 `main` runs: 6 red, consecutive, `70add5cf` (merge of PR #328, 2026-11-23 14:31 UTC) to `7e8bb3d2`
   (2026-11-24 04:23 UTC). All six job logs (jobs 137763492119, 137876262796, 138174340447, 138194224984,
   138202681077, 138215878402) show the same single failure: `test/supabase/sync_service_test.dart` T4,
   `Bad state: No element` at line 269. Fixed by PR #335 (`814c0cf5`, diagnose `c7f4e2`). 12 green runs before,
   7 green after. ONE real break that sat on `main` for 14 hours across six merges, not a flake.
3. The job takes 2.1 to 3.4 min (the seven runs read).
4. Both test steps sign in as ONE shared QA account and delete that account's rows in `setUp`
   (`--concurrency=1` comments, `test.yml:682-714`). Two jobs at the same time can wipe each other's rows. Two
   back-to-back `main` merges can already overlap today (the workflow-level group never cancels `main`).
5. `test/edge_functions/ai_proxy_test.dart` costs 3 of the QA account's 7 daily chat messages per run and accepts
   a well-formed 429 once the cap is reached (`chatBodyOrAssertCapped`), and a hard-failure reply
   (`ai_proxy_hard_failure_lib.dart`). Live model cost is bounded by the cap, whatever the number of runs.
6. Run volume since 2026-11-23: 37 pull-request runs, 13 pushes to `main`.
7. `scripts/safe_pr_merge_lib.dart`: the job is in `skippedOkJobs` (`:35-38`). For such a job `_judgeCheckRuns`
   accepts `success` and `skipped`, refuses failure / pending / other conclusions, and TOLERATES a missing
   check-run (`:244-245`) and a job whose only runs were cancelled (the only-cancelled pass skips these names,
   `:268`). Consumers: `safe_pr_merge.dart:135`, `land_pr.dart:472-491`.
8. GitHub concurrency (docs read 2026-11-25, not exercised): default `queue: single` keeps ONE pending job per
   group and a newer pending job CANCELS the older one; `queue: max` keeps up to 100 pending and may not be
   combined with `cancel-in-progress: true`; the group may use only the `github`, `inputs`, `vars` contexts.
   NOT established: whether a job held by a concurrency group already has a check-run.
9. OI-528: both sightings are inside `SyncCli.create` (`test/helpers/sync_cli_fixture.dart:55-69`):
   `git remote add origin` (PR #329) and `git checkout -q -b feature` (PR #338 run 45361275474). For the second
   the job log carries `[spawn-retry] lost-status retry 1 of 1 ... exit=-523296808`: the first attempt created
   the branch, its status was lost, the OI-468 retry ran the command again and the second attempt failed on its
   own earlier effect. The first sighting's log was not re-read for that line: it is ASSUMED to be the same
   mechanism. Why the status is lost is NOT established (OI-468).
10. Two retry loops exist in `test/helpers/spawn.dart`: `retryingSpawn` (`:256`, used by `runSpawn`) and
    `retryingSpawnAsync` (`:311`, used by `runSpawnAsync` and `runSpawnWithInput`). `SyncCli.create` is fully
    synchronous (every command through `runSpawn`).
11. `LandFixture.create` (`test/helpers/land_pr_fixture.dart:82`) starts with `SyncCli.create`.
12. `ScopeRepo.commitAll` uses `commit --allow-empty` (`merge_scope_repo.dart:119`): a commit retried after a
    lost status would not fail, it would add a second commit silently.

## 2. OI-527: run the integration job on pull requests, one at a time

Writer: `.github/workflows/test.yml` job `supabase-tests`. Readers: `scripts/safe_pr_merge_lib.dart`
(`_judgeCheckRuns`, behind `evaluateCheckRuns` / `classifyCheckRuns`, used by `safe_pr_merge` and `land_pr`).

1. **`if:`** becomes
   `(github.event_name == 'push' && github.ref == 'refs/heads/main') || (github.event_name == 'pull_request' &&
   github.actor != 'dependabot[bot]' && github.event.pull_request.head.repo.full_name == github.repository)`.
   Cases: push to `main` runs; a same-repository pull request (into `main` or `develop`) runs with secrets; a
   Dependabot run is `skipped` (it gets no Actions secrets); a human commit on a `dependabot/*` branch has the
   human as `github.actor`, so it runs, with secrets; a fork is `skipped`. `github.actor`, not
   `pull_request.user.login`: the latter stays `dependabot[bot]` after a human commit and would skip a run that
   has secrets.
2. **Job-level `concurrency`:** one literal group name shared by every pull request and by `main`,
   `cancel-in-progress: false`, `queue: max`. This also closes today's overlap of two `main` runs (fact 4).
   Consequences, accepted: a `main` job waits its turn behind queued pull-request jobs (about 3 min each); a job
   that hangs holds the group for up to its 15-minute timeout; a job cancelled mid-run (its pull request got a
   newer push) leaves QA rows behind, which the next job's `setUp` cleanup removes, as it does today.
   **If GitHub rejects `queue: max`** the whole workflow fails to parse on this pull request's own run (every
   job red, nothing merged): then the key is dropped, the default single-pending queue stays, and rule 3 below
   turns a queue-cancelled job into a refusal that a re-run cures.
3. **Merge wrapper: a new class, because a missing run can no longer be read as fine.** The job leaves
   `skippedOkJobs` (which keeps `Plan-review record`, a true push-only job) and goes into a new list
   `prTimeSkippableJobs`: `success` or `skipped` pass; failure, any other conclusion, pending, a MISSING
   check-run and a job with ONLY cancelled runs all refuse (missing and only-cancelled as "not finished", so
   `land_pr` keeps waiting instead of calling it red). This holds whatever GitHub does with a queued job's
   check-run (fact 8), and it means a normal pull request cannot merge unless the job produced a result on the
   head SHA. `skipped` stays accepted because a Dependabot pull request's skip is legitimate; a same-repository
   pull request can be skipped only by editing the workflow, which already needs `--allow-workflow-change`.
4. **Missing secrets on a pull request fail the job.** The `if:` already removes the two legitimate no-secret
   cases, so on a `pull_request` event the announce step exits 1 when a secret is missing (on a push to `main`
   it stays today's warning). Otherwise a green job could have verified nothing.
5. **What the job proves, and what it cannot.** It runs this pull request's CLIENT and TEST code against the
   LIVE backend: deployed Edge Functions and applied migrations, not the pull request's. So:
   - a pull request that changes an Edge Function is tested against the old deployed version (a false green
     for the server half; the Deno job and the deploy protocol cover that half);
   - a pull request whose client code or tests need a migration that is not applied yet goes red until the
     migration is live. Order rule, stated in `docs/architecture/hooks.md` and `supabase/migrations/CLAUDE.md`:
     an ADDITIVE migration is applied (with its own founder go, §4.3) before the pull request that needs it is
     landed. That is the order that keeps `main` green today; the gate now shows it one step earlier;
   - an outage of Supabase or of the model provider blocks landing while it lasts (the AI tests already accept
     a capped or hard-failure reply). There is NO override flag, the same as for every other required job.
   - pull-request test code now runs against the live project with the QA account before review. Not new
     privilege (same-repository authors only), and `SupabaseTestHelper.assertDisposableTarget`
     (`test/supabase/cleanup_target_guard_test.dart`) refuses a non-QA target.
6. Both test steps run on pull requests. Known cost, accepted: the daily chat cap is reached earlier, so the
   reply-content assertions of `ai_proxy_test` run on fewer runs (today every `main` run after the second of
   the day is already capped).
7. Wall time: the job runs beside the test machines (slowest about 10 min) and takes about 3, so a pull
   request's wall time changes only when three or more integration jobs are queued ahead of it.
8. **NEW protections (each mutation-tested, rule 21):**
   - `test/contracts/ci_integration_job_on_pr_test.dart`, pure `integrationJobProblems(String workflow,
     {required lists})`: the `if:` is exactly the expression of item 1 (whitespace-normalised); job-level
     concurrency exists; the group is a literal (no `${{`) and no other job uses it; `cancel-in-progress` is
     `false`; `queue` is `max`; the announce step fails on a pull request; the job's `name:` is in
     `prTimeSkippableJobs` and in neither other list.
   - `test/scripts/safe_pr_merge_lib_test.dart`: the new class's table (success, skipped, failure, running,
     neutral / timed_out, missing, only-cancelled, cancelled then success); the `push-only jobs` group and the
     `(push-only)` message are renamed to what they now are; the every-job-is-classified test includes the
     new list. `test/scripts/land_pr_lib_test.dart` fixtures gain the job as a run.
9. Docs: `docs/architecture/hooks.md` (CI section, and `safe_pr_merge`'s job classes), the job's own comment
   block, `supabase/migrations/CLAUDE.md` (the order rule), the OI-527 entry (what was decided).

## 3. OI-528: rebuild the fixture when a status was lost while it was being built

Writer of the hazard: the lost-status retry re-running a non-idempotent child. Reader: every `must(...)` in
`SyncCli.create`.

A general cure in the retry is not possible: the helper cannot know whether the first attempt ran. What IS
idempotent is the whole build of a fresh temporary repository.

1. `test/helpers/spawn.dart`: a top-level counter with a read-only getter `lostStatusRetriesSeen`, incremented
   in ONE private function that BOTH retry loops call on the lost-status branch (never on the native-assets
   branch: a retried `dart` start is idempotent).
2. Pure `rebuildOnLostStatus<T>(T Function() build, {required int Function() lostCount, void Function(String)?
   note})`: reads the counter at entry, runs `build` catching `Object` (a failed `expect` throws `TestFailure`);
   counter unchanged: returns the value or rethrows the error unchanged; counter moved: prints ONE
   `[fixture-rebuild]` line and runs `build` once more, whatever the first outcome (fact 12); the second
   build's outcome is final, and the line of a second lost status says so instead of retrying again.
   Synchronous `build` only: nothing can interleave inside it, which is what makes a process-wide counter
   sound here. An `unawaited` async spawn left running by an earlier test could move the counter during the
   build; the cost of that is one needless rebuild, never a wrong result.
3. `SyncCli.create` wraps its body in `rebuildOnLostStatus`. The abandoned repository's `dispose` is already
   registered by `ScopeRepo.create` and runs at teardown; it exists beside the rebuilt one until then.
   `LandFixture.create` is covered for its `SyncCli.create` part only, and its header says so.
4. NOT covered, stated in the header: a lost status after the fixture is built (mid-test commands), and
   fixtures other than `SyncCli`. No sighting of either.
5. Tests in `test/contracts/spawn_retry_test.dart`: the counter moves on the lost-status branch of the sync
   loop AND of the async loop, and not on the native-assets branch; `rebuildOnLostStatus` with a fake counter:
   no move + value, no move + throw (same error object), move + throw then value, move + value then value
   (rebuilt, second value returned), move on both builds (exactly two builds), the note line. Mutation-tested.
6. Slim diagnose doc for OI-528. OI-527 and OI-528 close with `closes-oi:` trailers.

## 4. Verification

- Local: `flutter analyze --no-fatal-infos`, the pre-commit gate loop, the touched tests.
- CI on the pull request, read from the check-runs of the head SHA (not from the checks page): the integration
  job's conclusion is `success` (not `skipped`) and its log shows both test steps ran. The pull request edits
  the workflow, so `land_pr` needs `--allow-workflow-change`.
- Fact 8's open point is MEASURED on this pull request: two runs are started close together (a second push
  while the first run's integration job is running) and the check-runs API is read for the waiting job. The
  result is recorded here; rule 2.3 is correct either way.
- The first `main` run after the merge: the job runs and is green.

## 5. Out of scope

Why the status is lost (OI-468); a second QA account; an override flag for a red integration job.

## 6. Review round 1 (context-blind Sonnet, 2026-11-25): 4 P1, 5 P2, 1 P3, all taken

1. P1: a red job a pull request cannot fix (unapplied migration, provider outage), and the false green for a
   changed Edge Function: section 2 item 5.
2. P1: a queued job may have no check-run and a missing run was tolerated: section 2 item 3 (new class) and the
   measurement in section 4.
3. P1: `queue: max` unverified, no fallback: section 2 item 2.
4. P1: only one of the two retry loops was counted: section 3 item 1 and fact 10.
5. P2: catch `Object`; first sighting not tied to a lost-status line; teardown: section 3 items 2-3, fact 9.
6. P2: the `if:` per case, `github.actor`, missing secrets green: section 2 items 1 and 4.
7. P2: stale "push-only" wording in the lib, its test and the OI: section 2 items 8-9.
8. P2: queue consequences: section 2 item 2.
9. P2: pull-request test code against the live project; the AI path's signal: section 2 items 5-6.
10. P3: contract test also pins the lists and `cancel-in-progress`: section 2 item 8.

## 7. Review round 2 (context-blind Sonnet, on revision 2): 2 P1, 5 P2, 6 P3; no design change, all taken

Both P1 are completeness, not mechanism; the plan is converged with these amendments.

1. P1: `test/helpers/land_pr_fixture.dart` `allGreen()` has no integration run, so every `land_pr` e2e test
   would wait as "not finished". It gains the job (`completed/success`); `land_pr_e2e_test.dart` gains the case
   "integration job missing: the wait goes on, it is not red". `test/scripts/fixtures/
   safe_pr_merge_pr96_check_runs.json` already carries the job as `skipped` and stays valid.
2. P1: the `queue: max` fallback of section 2 item 2 would let a newer pending pull-request job CANCEL a pending
   `main` job. Amended fallback, used only if GitHub rejects the key: drop `queue`, and give pushes to `main`
   their own literal group, so a `main` job can only be displaced by another `main` job (two pending `main`
   jobs at once needs three merges inside about 3 minutes). The pull request's first push is the measurement:
   a rejected key shows as a run with no jobs.
3. P2: a pull-request head that predates this merge has no integration run and is refused by a direct
   `safe_pr_merge` until its branch is synced (`land_pr` syncs first, so it is unaffected). The refusal reads
   `"<job>" has no check-run (it runs on every pull request: sync the branch or re-run the job)`.
4. P2: wording of section 2 item 3: a MISSING run stays pending for the whole CI wait; an ONLY-CANCELLED run is
   reported `ci-failed` by `CiWatch` after three consecutive polls (`land_pr_lib.dart`), and a re-run cures it.
5. P2: the bare version-bump landing (CLAUDE.md §4.3, OI-275 B2) and docs-only pull requests also wait for the
   integration job and can be refused by a live-backend red. Accepted: that path skips the plan-review record
   and the B-pass, never CI.
6. P2: the counter function sits ABOVE `retryingSpawn` (after `_defaultNote`): `spawn_retry_test.dart` and
   `spawn_helper_test.dart` slice `spawn.dart` between function signatures. Its call sits beside `lost++`.
7. P2: test list of section 3 item 5, sharpened: the throwing build throws an `Error` subtype; the unchanged
   rethrow is asserted with `identical`; the fake counter moves only DURING the first build (kills a snapshot
   taken after it); a move during the second build only gives exactly one build; `note` is called exactly once
   on a rebuild and never otherwise; the native-assets branch leaves the counter alone in BOTH loops. The
   `[fixture-rebuild]` line is plain `print`, so it survives a passing test.
8. P3 (holds, recorded): the `if:` is valid and false-safe on a push; the announce step can read
   `GITHUB_EVENT_NAME`; a push to `main` with missing secrets stays a warning (accepted, unchanged); no other
   script names the job; the order rule contradicts no migration rule (a DESTRUCTIVE migration still merges its
   code half first, `supabase/migrations/CLAUDE.md`); building `SyncCli` twice in one test is legal.
