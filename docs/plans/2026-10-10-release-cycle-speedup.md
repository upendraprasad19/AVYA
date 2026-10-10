# Release-cycle speedup — master plan v3 (OI-275 + more), FOUR batches

Status: v3 = v2 + plan-review round 2 applied. Round 1 (11 P1) forced the split into four batches; round 2 (0 P0, 8 P1, all localized spec fixes,
verdict "no third full round unless an edit changes a design") is applied below; the post-round-2 edits are re-checked mechanically by the
B-pass of each batch. Each batch's `docs/plan-reviews/<branch>.md` cites rounds 1+2 of this plan.
Base `fdf06564` (origin/main 2026-10-10). Every batch gets its OWN worktree/branch off the then-current `origin/main` (§4.13).
Founder directive 2026-10-09: "push and merge and CI is taking a lot of time everyday; plan and implement all of these." Max-autonomy: all gates in §6.

## 0. Baseline (measured; source in the right column)

| Fact | Value | Source |
|---|---|---|
| CI `Unit Tests` job | 13.0–13.5 min = the critical path (test step 12.9 min, ~0.5 min fixed setup) | `gh run view 37971525387` (main) / `37958167385` (PR); others <= 4 min: Analyze 1.1, Deno 0.85, Build Check 4.0, Supabase 3.75, Audit Gates 1.4, plan-review 0.8 |
| CI runs per change | 2 (PR + main push), 10.6–16.5 min over the last 30 runs (one 25 min failure) | `gh run list --workflow "Test & Analyze" --limit 30` |
| PR run job set | `Plan-review record (>=account merge-to-main)` and `Supabase Integration Tests` are `skipped` on PR runs (`if: push && main`, test.yml:319,393) | run 37958167385 |
| Exact CI job names | `Analyze`, `Unit Tests`, `Deno Edge-Function tests`, `Audit Gates`, `Plan-review record (>=account merge-to-main)`, `Supabase Integration Tests`, `Build Check (APK)` | test.yml:45,88,121,189,318,390,490 |
| Local pre-push suite (>= account) | ~39 min on the founder PC — ONE measurement (OI-275, 2026-10-01); VPS not measured | OI-275 text |
| Local pre-push analyze | 212 s | `scripts/pre-push.sh` comment at the analyze call |
| Version bump | `pubspec.yaml` is `platform` (`docs/blast_radius.yaml:493`), `lib/core/constants/app_constants.dart` is `account` (`lib/core/**`, :486); ~92 min suite time on the +48 bump | OI-275 |
| Main protection | `required_status_checks: strict:true, contexts:[]` (NO required checks), `enforce_admins:true`, `required_conversation_resolution:true`, no required PR reviews | `gh api repos/upendraprasad19/AVYA/branches/main/protection` |
| Repo | PUBLIC (standard-runner minutes free); merge commits only | `gh repo view`, `gh api` |
| Within-suite sharding | tried + reverted 2026-08-10 (18% < 25% floor; broke an order-dependent test) | comment above the `unit-test` job |
| Tests | 1050 files (contracts 678, scripts 90, sync 50) | `find test -name '*_test.dart'` |
| Goldens | 5 files `test/goldens/wardroom/*`, tag `golden`, **run NOWHERE automatically**: CI AND the pre-push full suite both pass `--exclude-tags golden` (`pre-push.sh:151`, pinned by `pre_push_matches_ci_invocation_test.dart`); only `PRE_COMMIT_FULL=1` or by hand. The comments claiming the pre-push suite runs them (`dart_test.yaml:7`, `docs/blast_radius.yaml:159`) are stale and get corrected in B1 | round-2 review, re-verified |

## 1. Batch order

1. **B1 — pre-push branch-push skip + `safe_pr_merge.sh` (U5, U4)** FIRST: after it lands and the hook is reinstalled, every later batch's push costs analyze only. Its own first push runs the old hook once.
2. **B2 — merge-commit version-bump exemption (U1b, U2, U3)** and **B3 — parallel test matrix (U7)** in parallel worktrees. They are mostly, NOT fully, disjoint: both touch `docs/blast_radius.yaml`; B2 and B4 both touch `.claude/commands/build-apk.md`; generated indexes overlap. Each rebases on the then-current `origin/main` before its push.
3. **B4 — skip the duplicate main-push run (U6)** LAST: edits the `test.yml` jobs B3 reshapes and needs B3's `Unit Tests` aggregator.
Each batch: own branch, own plan-review record, own B-pass, own closure ledger (`docs/audit/<batch>.closure.yaml`), one push, PR flow via `safe_pr_merge.sh` once B1 exists, CI-green merge. INLINE execution (§4.12.7). Commits use `perf(...)`/`feat(...)`; OI-275 stays OPEN until D is closed (no `closes-oi:` for it). OI-275's "diagnose-doc + bare-repo e2e" constraint is met by ONE slim diagnose-doc written in B1 (`docs/diagnoses/2026-10-10-release-cycle-wallclock-<id>.md`, `tier: s_fix`-style fields) and by the temp-git-repo e2e harnesses the batches' tests use.
Every new file/symbol is registered: new names (`tested-tree`, `dup-check`, `CI_SKIP_DUP_MAIN`, `safe_pr_merge.sh`, `ci_test_partition.dart`, the artifact-name writer/reader contract) go in `docs/naming_conventions.md` and, for the artifact contract, `docs/sot_registry.yaml` (with `behavioral_test_path:` per Gate 42).

## 2. B1 — U5 + U4

**`scripts/pre-push.sh`** (verified: today it DRAINS stdin with `cat > /dev/null`, :95-96).
- Replace the drain with `PUSH_REFS=$(cat)`, still ABOVE the analyze call (placement pinned by `test/contracts/hook_gate_placement_test.dart`). Parse WITHOUT a `while read` after a pipe (a pipe subshell loses the variable): feed the loop from a here-doc/`printf` redirect, or use `case`/`awk` over the whole string.
- Classes (4-field lines `<local ref> <local sha> <remote ref> <remote sha>`):
  `BRANCH_ONLY=1` iff >= 1 line AND every line has remote ref `refs/heads/<x>` with `<x>` not `main`/`develop` AND a non-zero local sha;
  `DELETE_ONLY=1` iff >= 1 line AND every line has an all-zero local sha AND a non-main/develop `refs/heads/*` remote ref (nothing lands, e.g. `mint_oi --prune`);
  empty/garbled input => both 0.
- After the tier computation: tier `feature` => skip (as today). `account|platform|catastrophic` AND (`BRANCH_ONLY` or `DELETE_ONLY`) => skip `run_full_suite` and print "CI on the open PR is the full-suite gate — open the PR now". **No goldens step** (round 2: they run nowhere today; adding them would be a NEW gate that false-reds on the Linux VPS). Everything else is the fail-safe and runs the full suite as today: push to `main`/`develop`, tag, mixed refs, empty/garbled stdin, unknown tier, `PRE_PUSH_FULL=1`.
- Analyze (212 s) and the warn-only contract sweep stay unconditional. Any new text must not put a literal `flutter test` line BEFORE `run_full_suite()` (`pre_push_matches_ci_invocation_test.dart` takes the FIRST match).

**New `scripts/safe_pr_merge.sh <pr>`** = thin shell around a pure Dart evaluator `scripts/safe_pr_merge_lib.dart` (injected lister, the `gh_run_lib.dart` pattern, so the filtering is unit-tested with real fixtures rather than a stubbed `gh` that ignores `--jq`):
- Lists check-runs for the PR head SHA (`gh api repos/{repo}/commits/{sha}/check-runs --paginate`), keeps only `app.slug == github-actions` (a real run also carries a third-party `Vercel Preview Comments` check), takes the LATEST non-cancelled run per name.
- Requires `success` for EXACTLY: `Analyze`, `Unit Tests`, `Deno Edge-Function tests`, `Audit Gates`, `Build Check (APK)`; `skipped` is accepted only for `Plan-review record (>=account merge-to-main)` and `Supabase Integration Tests`; ANY other non-success/non-skipped github-actions check-run refuses. Names matched EXACTLY (no prefixes). `gh`/network/JSON failure or zero check-runs FAIL CLOSED. The name list is data in the lib, checked by a test against the `name:` fields parsed out of test.yml (so a renamed job reddens the wrapper's test, not a merge).
- **B-pass hardening (applied in the B1 batch, review `docs/reviews/*-review.md`):** also refuses a PR whose base is not `main`/`develop` (CI does not run for it); a PR that edits `.github/` unless the caller passes the deliberate `--allow-workflow-change` (a pull_request run executes the PR's OWN workflow, so its green checks may prove nothing — B3/B4 will be merged with that flag after their `.github/` diff is read); a `total_count` that disagrees with the parsed check-runs; an unlisted job whose only runs were cancelled (a timed-out job is reported as cancelled). After `gh pr merge` it reads the PR state back and exits 2 UNVERIFIED unless it is `MERGED`. `sh scripts/safe_pr_merge.sh` forwards only the PR number and that one literal flag.
- Merges with `gh pr merge <n> --merge --match-head-commit <sha>`. If main has commits the PR lacks it WARNS (does not refuse — today's behaviour; main CI runs in full on a non-identical tree). If the merge is refused for `required_conversation_resolution` it prints that reason.
- Pinned `platform` in `docs/blast_radius.yaml` (like `safe_commit/safe_push/safe_merge`), and so is `safe_pr_merge_lib.dart`.

**U4 (founder-owned):** allow-rule text for the handoff: `Bash(sh scripts/safe_pr_merge.sh:*)` — names the wrapper ONLY, never raw `gh pr merge`. The harness classifier already blocks a raw `gh pr merge` from a session ("Merge Without Review"); that stays. Alternative NOT proposed: required status checks on main — on 2026-07-25 they blocked every direct push and `/build-apk` (`feedback_mistake_branch_protection_semantics.md`). Terminal state `blocked_on_user`.

**Tests (mutation-proven, §4.4 r21):**
- `test/scripts/pre_push_branch_push_skip_e2e_test.dart`: the REAL `pre-push.sh` with stubbed `flutter`/`dart` and a stdin fixture (the existing e2e always passes `< /dev/null`): branch-only >= account (skip), delete-only (skip), main, develop, tag, mixed refs, empty stdin, garbage lines, unknown tier, `PRE_PUSH_FULL=1`, feature tier. Mutations: treat `main` as a branch; drop the zero-sha check; make garbled input skip => the matching cases redden.
- `test/contracts/pre_push_blast_radius_failsafe_test.dart`: "skips the local full suite ONLY on feature tier" is reworded (a second skip path exists now) and the MIRROR added (still runs for main/develop/tag/mixed/unknown/empty).
- `test/scripts/safe_pr_merge_lib_test.dart` from a REAL fixture (PR #96 head `691d826b` check-runs, third-party check included): all-green; each required job failed/pending/missing; unknown extra failing check; stale head; skipped push-only OK; empty list; lister throws => refuse.
- Re-grep `test/` for every literal in `pre-push.sh` before editing (§4.9): `pre_push_matches_ci_invocation_test.dart`, `pre_push_analyze_always_e2e_test.dart`, `hook_gate_placement_test.dart`.

**Doc ripple:** CLAUDE.md §0 pre-push bullet, §4.3, §4.4 r20 (long text to `docs/architecture/process-invariants-detail.md` if the context-artifact budget demands — run `check_context_artifact_budget.dart`); `scripts/setup-hooks.sh:14,:79`; `scripts/batch_close_lib.dart:249`; `scripts/pre-commit.sh:116`; `docs/architecture/hooks.md`; `docs/architecture/process-invariants-detail.md:89,:116`; `docs/handbook/process/tiered-gating-by-blast-radius.md`; `.claude/commands/build-apk.md --from-green` premise; and CORRECT the stale golden claims (`dart_test.yaml:7`, `docs/blast_radius.yaml:159`).
**Hook reinstall:** `scripts/check_hooks_installed.dart` only WARNS on drift, so each clone keeps the OLD pre-push until `sh scripts/setup-hooks.sh`. After the merge I run it here (Bash has `sh`); the handoff states it for the VPS clone.
**Savings:** ~35 min per >= account branch push (39 min suite -> analyze; the PR CI was needed anyway). **Residual risk, stated:** a red branch can now leave the machine; it is caught by PR CI, by `safe_pr_merge.sh` (when used), and by main CI. The GitHub-UI merge remains an uncontrolled path (founder-only).

## 3. B2 — U1b, U2, U3 (merge-commit version-bump exemption + docs)

**U1(a) (a classifier flag/env that makes `blast_radius_from_diff.dart` content-aware for pre-push) is DROPPED** (round 2 P2-2/P1-6): after B1 a bump PR's branch push is analyze-only and the merge happens on GitHub, so (a) only helps a direct push to `main` (rare: the primary folder is integration-only and the sandbox blocks the local-merge flow); it adds an env var that needs a `spawn_env_manifest_test` classification and a leak-scoping fix, and a second classifier code path next to a gate with four prior failed attempts. OI-275 acceptance A is closed `verified_clean` with that evidence ("a bump's branch push no longer runs the suite — B1 — and a direct push of a bump to main keeps the fail-safe full suite by design"), not silently dropped.

**U1(b) keystone merge exemption.** In `check_plan_review_record_exists.dart`: a MERGE commit whose `sha^1..sha` net diff satisfies `isVersionBumpCommit` (`plan_review_record_lib.dart:316`: EVERY changed path in `versionBumpPaths` — exactly `pubspec.yaml` + `lib/core/constants/app_constants.dart` (:222) — and the single version token normalised, blobs byte-equal) needs no record / B-pass. All-or-nothing: a bump plus any other file (including a docs record) is NOT a bump. Content-keyed; the merge SUBJECT is not consulted (OI-58b untouched); a registry change adds `docs/blast_radius.yaml` to the path list so the exemption fails (OI-70 safe — reviewer-verified).
- **Placement:** after the `tier < account` skip (:617-620) and BEFORE `switch (ms.kind)` (:622), so an unrecognised/foreign subject does not fail first.
- **Code home:** `plan_review_record_lib.dart` has "No imports on purpose" (:14): the Process-using blob/mode readers (`_gitBlob`, `_gitMode`, today private in the gate script) move to a NEW lib `scripts/version_bump_git_lib.dart` exposing `rangeIsVersionBump(baseRev, headRev)`; the direct-commit loop (OI-58a) and the merge loop both call it. The new lib is pinned `platform` in `docs/blast_radius.yaml`.
- **`scripts/safe_merge.sh` advisory** (:251-254, "no plan-review record") currently does NOT mirror the exemption (OI-222); it uses `rangeIsVersionBump` through a tiny CLI so it stops warning on bump branches.
- **Tests:** EXTEND the existing `test/scripts/version_bump_exemption_test.dart` (do not overwrite) and `test/scripts/gate_input_family_e2e_test.dart` (direct-commit bump e2e ~L164-246): bump-only merge exempt; bump + docs file NOT; merge whose net diff includes `docs/blast_radius.yaml` NOT (OI-70); symlink mode; duplicate token; zero token; one-file-only (`pubspec.yaml` alone) behaviour PINNED to what `isVersionBumpCommit` does today (accepts) with a note that Gate 51 `check_app_version_matches_pubspec.dart` forces both files at commit time; foreign-subject merge of a bump is exempt BY CONTENT. Mutations: relax `paths.every`, drop the mode check, diff the wrong rev, move the exemption after `switch` => reddens.
- `docs/audit/gate_test_ledger.yaml:584`: `check_plan_review_record_exists.dart` moves off `grandfathered: 2026-08-10` to `mutation_proven: true` with `test_path:` + `evidence:` (precedent `ai_tool_dispatcher_coverage`), since the batch changes its protection surface.
- **U2/U3 — `.claude/commands/build-apk.md` Gate 2:** the one-commit sequence (worktree -> edit BOTH files -> ONE commit -> ONE push -> `gh pr create` -> CI -> `sh scripts/safe_pr_merge.sh` -> `--from-green`) and the up-front list of steps a classifier can block. Pinned by a source-grep (presence) AND a check that every script/flag the doc names exists.
- **Doc ripple (round 2 P2-3):** CLAUDE.md §4.3 and `.claude/skills/code-review/SKILL.md` ("B-pass for every >= account change") state the version-bump exception; `safe_merge_test.dart` advisory tests (:485-532); budget check for the tracked CLAUDE.md / `open_issues.md`.
**Savings (net of B1, no double count):** no plan-review record + B-pass to author for a bump, and no second PR CI round for the record commit (~13 min); a bump PR is analyze (3.5) + PR CI + main CI. (v1's "~78 min" was B1's saving, now claimed only in B1.)

## 4. B3 — U7 (parallel whole-file test matrix)

Why not path filters (measured): 7 of the last 40 merges touch no code path (recomputed by the round-2 reviewer), but the docs dirs they touch are read by tests (`docs/reviews` ~81 string literals in `test/`, `docs/audit` 72, `docs/architecture` 57, `docs/diagnoses` 46), so a docs-only skip is unsafe without per-file mapping. Closure: `verified_clean`.
Why this is not the reverted sharding: that sliced test BODIES within every suite, so each shard still compiled all ~693 files; U7 hands each job a disjoint set of WHOLE FILES.
- `scripts/ci_test_partition.dart <shard> <total>`: **sorted-path round-robin** (file i of the sorted `test/**/*_test.dart` list goes to shard `i % total`). Round 2 measured that declared `@Timeout`s do not predict wall-clock (per-file spans <= ~23 s; a 14-min declared file is invisible in the log), and a simulated LPT gave 262/263/262/263 files anyway — so no weights parser. The first matrix run logs per-shard durations; a skew > 1.5x between slowest and fastest shard re-balances with a committed measured-duration table in the same batch. Run with plain `dart scripts/ci_test_partition.dart` (NOT `dart run`: its "Running build hooks..." preamble pollutes stdout, `pre-push.sh:172-175`).
- The step: `FILES="$(dart scripts/ci_test_partition.dart $SHARD 4)"; test -n "$FILES" || exit 1; flutter test $FILES --exclude-tags golden --reporter expanded` (an empty list would otherwise run the ENTIRE `test/`; a failing `$(...)` does not trip `-e` inside an assignment used in `test -n` unless checked — hence the explicit `test -n`).
- `unit-test` becomes a matrix `shard: [1,2,3,4]` named `Unit Tests shard n/4`, `fail-fast: false`, same `TZ`.
- **Aggregator job named exactly `Unit Tests`** (`needs: [unit-test]` in B3; B4 adds `dup-check`), `if: ${{ !cancelled() }}`: passes when every shard is `success`; **B4 extends it** to also pass when the shards are `skipped` AND `dup-check` reported `skip=true` (round 2 P1-4). It keeps the check name stable for `/build-apk` Gate 3.5, `scripts/reconcile_ci.dart` (run-level conclusion only; no programmatic job-name consumer exists — prose only, e.g. `test/edge_functions/redeem_referral_test.dart:164,170`) and `safe_pr_merge.sh`.
- Mirror tests: shards pairwise disjoint; union == `find test -name '*_test.dart'` (completeness); none empty; deterministic; a file added/removed moves only `i % total` neighbours (not asserted stable). Mutations: off-by-one in the modulo, skip the last file, reorder the sort => the matching test reddens.
- Re-point: `pre_push_matches_ci_invocation_test.dart` (compares the FIRST CI `flutter test` line with pre-push's — keep `TZ` + `--exclude-tags golden` recognisable, update the comparison to the shard form), `ci_workflow_concurrency_test.dart`, `scripts/check_ci_flutter_version.dart` (every Flutter-setup job keeps the pin), plus the new `ci_test_partition.dart` pinned `platform` in `docs/blast_radius.yaml`.
- **Pre-committed abort conditions (written before the first run):** (1) the matrix's end-to-end workflow wall-clock (first job start -> last job end; the aggregator is on the critical path and is included) on a throwaway PR is not >= 25% faster than the MEDIAN of >= 10 baseline PR runs; (2) any test red that is green in the single job on the same SHA; (3) two simultaneous runs (a PR run and a main run, 7 jobs -> 10 jobs each) show queue time that makes the pair slower than today (measured from `started_at - created_at` of the jobs). Any => revert B3.
**Savings:** target 13 -> 6–8 min per PR run and per main run (ideal 4 shards ~3.7 min + setup; estimate until measured).

## 5. B4 — U6 (skip the duplicate main-push heavy jobs when the SAME TREE already passed on a PR)

Proof by TREE HASH, not timestamps:
- PR-only job `tested-tree` (`needs` Analyze, Unit Tests, Deno, Audit Gates, Build Check; `if: github.event_name == 'pull_request' && !cancelled()` and all five `success`; **its own `actions/checkout`**): `git rev-parse HEAD^{tree}` of the merge ref; uploads a ONE-LINE MARKER FILE (an empty upload creates no artifact) as `tested-tree-<tree>` with `overwrite: true` (a re-run otherwise 409s and reddens a green PR run).
- Main-push job `dup-check` (explicit `permissions: actions: read, contents: read, pull-requests: read`): computes `git rev-parse HEAD^{tree}`; `GET /repos/{repo}/actions/artifacts?name=tested-tree-<tree>`; for each unexpired hit takes `workflow_run.{id, head_branch, head_repository_id}` from the artifact and makes a SECOND call to `/actions/runs/{id}` for `event` and `conclusion` (the artifact object has neither). Skip iff: same-repo head repository, `head_branch != main`, `event == pull_request`, `conclusion == success`, same workflow path. Decision logic = pure Dart `scripts/ci_dup_main_decision.dart` (JSON in -> decision + reason out); the YAML only fetches and passes data. **`dup-check` never fails the run:** any API/parse/Dart error resolves to `skip=false` and everything runs (fail-safe). The Dart toolchain setup uses the same cached setup as the other jobs (cost measured, below).
- Skipped on a match: the `Unit Tests` shards and `Build Check` (~17 min of runner work). Always run: analyze, deno, audit-gates, `plan-review-record` (the keystone), `supabase-tests`, the aggregator.
- `needs`/`if`: `unit-test` and `build-check` gain `needs: dup-check` with `if: ${{ !cancelled() && needs.dup-check.outputs.skip != 'true' }}` — `!cancelled()`, NOT `always()` (keeps cancel-in-progress) and NOT bare `needs` (every PR run skips `dup-check`, which would silently skip the PR gate). `ci_workflow_concurrency_test.dart:73` ("build-check declares no needs") is updated with the new rationale AND gains a mirror asserting the exact `if:` expression and the PR-run case. `dup-check` cost is MEASURED, not assumed (round 2: Dart setup may add 0.5–1 min to every main run even in `dry`); if it exceeds 30 s it moves to a plain `gh api` + `jq` step with the decision re-implemented and tested in shell.
- **Ship-dark switch (round 2 P1-5):** `env.CI_SKIP_DUP_MAIN: ${{ vars.CI_SKIP_DUP_MAIN == 'off' && 'off' || 'dry' }}` — the repo variable can only DOWNGRADE (kill switch to `off`), never reach `on`. `on` exists only as the committed literal. `dry` (initial) computes and logs `WOULD_SKIP=<bool> reason=<...>` and skips NOTHING (outcomes identical to today; timing/YAML differ by the extra cheap jobs — stated). The FLIP is a commit changing `'dry'` -> `'on'`, on its own branch with its own record citing these x2 rounds + `bpass: accepted` (B4 is built at the normal x2 tier, not `ship_dark_build`, so it needs no `ship_dark_pending_review.yaml` row; the ledger is for 1-round builds — stated explicitly). Flip only after >= 3 real main pushes whose `dry` decision matched ground truth (at least one match and one non-match observed).
- `.claude/commands/build-apk.md --from-green` premise rewritten: the SHA is covered by "tree-identical to a CI-green PR run" (the artifact), not by a local suite.
- **Threat model, stated:** protects against mistakes, not malice. A same-repo PR that edits `test.yml` could upload any tree name; the control is that `test.yml` is `platform`-pinned and needs a reviewed record. Forks are excluded by the `head_repository` check.
- Tests: `scripts/ci_dup_main_decision.dart` fixtures (match; no artifact; expired; from main; from a fork; failed run; tree differs; several artifacts; malformed JSON => no skip), each with a mutation; source tests on test.yml (`if:` expressions, `permissions`, default `'dry'`, vars-only-downgrade, marker upload with `overwrite: true`); the new script pinned `platform`.
**Savings:** ~13–17 min of runner work per merge once `on`; main run wall-clock 13 -> ~4 min (supabase-tests becomes the critical path).

## 6. Gates and approvals owed (listed up front)

1. This plan: round 1 and round 2 done and applied (Sonnet, context-blind); each batch's record cites them; mechanical re-check of the post-round-2 edits happens in each batch's B-pass.
2. Per batch: full local gate loop before its B-pass dispatch (§4.12.8): `flutter analyze lib/`, `TZ=Asia/Kolkata flutter test`, the pre-commit loop — not a subset; `/code-review` B-pass self-triggered before the merge; record + bpass review file per branch.
3. Commit/push ONLY on the founder's word via `safe_commit.sh` / `safe_push.sh`; one push per batch; B1's first push runs the OLD hook (39 min) once.
4. Founder-only: (a) the U4 allow rule `Bash(sh scripts/safe_pr_merge.sh:*)`; (b) approving the B4 flip commit after the `dry` evidence; (c) `sh scripts/setup-hooks.sh` on the VPS clone (I do it here).
5. After each merge retire its worktree (§4.13.8). Then AAB 1.0.0+49 via `/build-apk` on a separate explicit go (+48 is recorded built 2026-10-01).

## 7. Savings summary (estimates; each cites its input; first runs re-measure)

| Batch / unit | Saves | Per what |
|---|---|---|
| B1 U5 | ~35 min | per >= account branch push (39 min suite -> analyze; the contract-sweep cost unchanged and not measured here) |
| B1 U4 | minutes–hours of waiting for a merge yes (unmeasured) | per merge |
| B2 U1b–U3 | no record/B-pass authoring + ~13 min (no second PR CI round) | per version bump |
| B3 U7 | ~5–7 min x2 | per PR run and per main run |
| B4 U6 | ~13–17 min runner work; main wall 13 -> ~4 | per merge, once `on` |
Typical >= account change: ~65 min + approval waits (39 local + 13 PR CI + 13 main CI) -> ~16 min (3.5 analyze + ~7 PR CI + ~4 main CI + merge). Version bump: ~105 min -> ~16 min (mostly B1+B3+B4; B2 removes the record and its extra CI round).

## 8. Rejected / not re-proposed
- Within-suite sharding (`--total-shards`): reverted 2026-08-10. Path filters / docs-only skip: tests read the docs dirs (§4).
- Required status checks on main: blocked every direct push and `/build-apk` on 2026-07-25.
- Dropping the 212 s pre-push analyze: the only compile check for PR-less branches.
- Timestamp-based duplicate-run proof: replaced by tree hash (§5). Goldens-only local step: dropped (they run nowhere today).
- Content-aware classifier flag/env for pre-push (v1 U1a): dropped (§3).
- `@Timeout`-weighted LPT partition: dropped, round-robin by sorted path (§4).
