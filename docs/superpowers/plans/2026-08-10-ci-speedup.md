# Unit 4 — CI cycle-time reduction

**Branch:** `ci-speedup` · **Date:** 2026-08-10 · **Tier:** platform
(`docs/blast_radius.yaml:183` → `.github/workflows/test.yml`; `:101` → `scripts/pre-commit.sh`) ·
**Status:** CONVERGED after ×2 context-blind review

> **Round 2** (on this rewritten text) returned **1 P0 + 3 P1 + 5 P2**, and the P0 was a defect
> **introduced by round 1's own correction**: switching to the native `--total-shards` flags was
> right, but the plan inherited v1's file-level mental model of what sharding does. Verified at
> source by the main thread — `test_core/lib/src/runner.dart:496-502` shards WITHIN each suite — so
> §4's headline numbers were unsupportable. Resolved by predicting **no** number and fixing a
> falsifiable decision rule in advance instead. Round 2 also corrected 16/70 → **15/71** on the skip
> counts (a name in a comment is not a skip arm), showed §3.5's remedy was not implementable as
> written (`jobs.<id>.if` cannot read `secrets`), and found a **second** live line-citation
> (`open_issues.md:603` → `test.yml:171`) that v2 missed. All closed above before any execution.

Founder's ask: *"how to reduce GitHub Actions CI time — it is taking a lot of time."*

> **v1 of this plan was designed on ASSUMPTION and was largely wrong.** It never measured a single
> CI job. Two context-blind reviewers independently pulled real timings and returned the same two
> P0s. Every number below is now measured from run `31350916315` on `main` (all six jobs green) and
> re-verified by the main thread directly, not taken from reviewer prose.

> **Framing (unchanged, still correct).** `main`'s branch protection has
> `required_status_checks.contexts: []` — CI is **advisory-only at the merge gate, deliberately**.
> Required checks block a *direct push* (the workflow is triggered BY the push, so the new SHA has
> zero check-runs at ref-update validation); that caused a total ship-stop on 2026-07-25/26 and
> emptying `contexts` was the correct narrow repair. **Do NOT "fix" this.** Consequence: this batch
> buys **cycle time**, not safety.

---

## 1. MEASURED BASELINE — the thing v1 skipped

Run `31350916315`, workflow wall clock **7m49s**. No job has a `needs:`, so all six start at t=0.

| Job | Duration | Critical path? |
|---|---|---|
| **Analyze & Unit Tests** | **7m49s** | **YES — it IS the wall clock** |
| Build Check (APK) | 3m22s | no — but it is the FLOOR (see §5) |
| Audit Gates | 1m06s | no — **6m43s of slack** |
| Plan-review record | 35s | no |
| Supabase Integration Tests | 28s | no — and runs **zero tests** (§4) |
| Deno Edge-Function tests | 16s | no |

Step level inside the two jobs v1 targeted:

| Step | Measured |
|---|---|
| `Analyze & Unit Tests` fixed overhead (setup+checkout+flutter-action+pub get) | **21s** |
| `flutter analyze` | **47s** — runs SERIALLY before the tests, same job |
| `flutter test` | **6m38s** |
| `Audit Gates` — `Run all check_*.dart gates` | **32s** |

## 2. WHAT v1 GOT WRONG (all confirmed by direct measurement)

1. **DROP the `audit-gates` parallelisation entirely.** The gate loop is **32 seconds** on a job
   with **6m43s of slack**. Bounded-parallel at 4 saves ≤24s of wall clock: **exactly zero**, since
   the job ends 6m43s before the workflow does. v1 spent its whole risk budget — the Gate 33
   textual-marker fragility, the subprocess-isolation rationale — on the 6th-longest of six jobs.
   The repo is PUBLIC, so runner minutes are free too; there is not even a cost argument.
   **Dropping a change with a MEASURED benefit of zero is not a deferral (§4.2)** — no defect is
   being carried forward. The measurement is recorded here so it is not re-proposed.
2. **`flutter test` has NATIVE sharding — verified `flutter test --help`:** `--total-shards` /
   `--shard-index`. v1's hand-rolled `find | sort | awk 'NR % N'` partition, the explicit file-list
   argv, the golden-inclusion subtlety it spent a paragraph on, **and the entire
   `check_test_shard_completeness.dart` gate** (plus its rule-24 ledger entry, its bare-invocation
   hazard in both gate loops, and its locale-dependent `sort`) all evaporate.
3. **The "86" correction was itself wrong.** `pre-commit.sh:52` ("38") and `:188` ("~28") describe
   what each loop EXECUTES, not how many files exist. Measured: **86 files**, CI case-block skips
   **13** → executes **73**; pre-commit case-block skips **16** → executes **70**. Writing "86"
   would replace one wrong number with another.
4. **The Gate 33 mechanism claim was wrong.** v1 said `extractCaseSkips` subtracts from the wired
   set, making a malformed case block a silent false PASS. The subtraction exists
   (`check_gate_scripts_wired.dart:172-173`) but is **inert**: every name in `workflowCaseSkips` is
   extracted from `workflowContent` itself, so `contains(script)` is unconditionally true for
   exactly those scripts and the second disjunct can never flip a verdict. v1's *conclusion* ("a
   green Gate 33 does not prove skip semantics survived") was right; its mechanism was not — and
   its mitigation ("diff Gate 33's computed sets") names an operation the script does not support:
   it prints only `PASS: all N gate/validator scripts covered`. Moot now that §2.1 drops the
   rewrite.
5. **The per-leg cost model was ~5× wrong, in the plan's own disfavour.** v1: "~1.5–2 min" per
   matrix leg. Measured: flutter-action 16s + pub get 2s + checkout 2s + setup 1s = **21s**.

## 3. WHAT ACTUALLY LANDS

### 3.1 Shard `analyze-and-unit-test` with the NATIVE flags

```yaml
strategy:
  fail-fast: false
  matrix:
    shard: [0, 1, 2]
steps:
  - run: flutter test test/ --exclude-tags golden
         --total-shards 3 --shard-index ${{ matrix.shard }} --reporter expanded
```

`--exclude-tags golden` keeps working exactly as at `test.yml:61` — goldens stay declared by
`@Tags(['golden'])` inside 5 files, never by path, so nothing about golden handling changes.
`fail-fast: false` so one red shard does not mask the others.

**Shard isolation verified, not assumed:** no `flutter_test_config.dart` anywhere under `test/`;
every Hive init takes a per-test temp path; no socket binding. `flutter test` already runs suites
concurrently in-process, so any ordering hazard would already be firing today.

### 3.2 Hoist `flutter analyze` into its own job

47 seconds currently runs **serially before** the 6m38s test step in the same job. Its own job runs
in parallel with everything else and takes it off the critical path for free — no risk, no new
tooling. v1 said analyze "stays its own un-sharded step" without noticing it was serial.

### 3.3 The three A0 corrections (unchanged in substance, one renumbered)

1. **`check_apk_release_signed.dart` → CI's case-block.** Present in pre-commit's list AND Gate 33's
   `_allowList` ("Needs an APK + apksigner + JDK; runs from /build-apk Gate 48"), absent from CI's,
   so CI bare-runs it every push. Harmless today (dry-run-skips to exit 0) but its own header says
   it should not run from CI. Verified: it is already in `_allowList`, so this changes no Gate 33
   verdict — it only removes a misleading log line.
2. **Remove `--warn-only` from `check_skipped_discipline_budget.dart`** (`pre-commit.sh:174`). Both
   waivers are `**resolved** 2026-06-19` (`docs/skipped-discipline.md:5-6`) and the gate exits **0**
   without the flag — ran it live. v1's original remedy here was BACKWARDS: it proposed adding the
   gate to CI's skip-list, which would have deleted the only hard-failing surface. Also wrap it with
   a `[pre-commit] FAIL:` message like its neighbours — bare `set -e` gives no diagnostic.
3. **Fix the stale counts.** Counted from source, arm lines only (a name appearing in a *comment*
   inside the case block is not a skip — that error gave 16/70 on the first pass):
   `pre-commit.sh`'s case block has **15** arms → the loop executes **71** of 86.
   CI's has **13** → **73**, becoming **72** once item 1 lands.
   Phrase both comments as "86 gate files, 71 run in this loop" so the pair cannot drift again, and
   add: **2 of the 15 skipped (`check_no_deferral_euphemism`, `check_skipped_discipline_budget`) are
   invoked explicitly at `:174` and `:182`**, so real pre-commit coverage is 73 of 86, not 71 —
   without that sentence the new number understates coverage the same way the old one overstated it.

### 3.4 `scripts/new-worktree.sh` bases new worktrees off a STALE main

`:42-46` comments *"Base off the freshest main"* and unconditionally prefers `origin/main` whenever
`git fetch` succeeds. But `origin/main` is only freshest when nothing is merged-but-unpushed — and
§4.13's workflow is *merge locally in the primary, then push*, so the stale window is **structural**.

**Measured, not theoretical — it bit this batch.** `new-worktree.sh ci-speedup` ran after
`gate-registry` merged to local `main` (`f909cf35`) while the push was still in flight, so the
worktree was created at `be74bf63`, WITHOUT the gate registry. Since this unit also edits
`pre-commit.sh`, a conflict was guaranteed. Recovered by `git reset --hard f909cf35` (0 unique
commits).

**Fix — four branches** (v1's prose said both "otherwise use local main" AND "fail loud on
divergence", which are mutually exclusive). Order matters, because `git merge-base --is-ancestor A B`
returns 0 when **A == B**, so identical refs satisfy BOTH ancestor tests:
1. `origin/main` missing / no remote → local `main`. Guard FIRST: `--is-ancestor` errors under
   `set -e` when a ref does not exist.
2. **refs identical** → either; take local `main` explicitly. v1 resolved this correctly only by
   accident of branch ordering — state it so the next editor cannot reorder the branches and
   silently change behaviour.
3. local `main` is an ancestor of `origin/main` (local behind) → `origin/main`.
4. `origin/main` is an ancestor of local `main` (**merged-but-unpushed** — the case that bit this
   batch) → local `main`.
5. neither is an ancestor of the other (genuinely diverged) → **loud warning + local `main`**.

**Not a hard exit.** v1 said "fail loud, do not guess" — but `new-worktree.sh` is the entry point for
ALL new work under §4.13 point 1, so hard-exiting on a diverged main is a ship-stop for a hygiene
problem: the same error class §4.13 point 6 explicitly names, and the same class as the 2026-07-25/26
required-status-checks incident. Warn loudly, pick local `main`, let the operator decide.

**Test:** `test/scripts/new_worktree_base_test.dart` — a scratch repo per case (behind / ahead /
identical / diverged / no-remote). **`environment: _cleanEnv()` scrubbing `GIT_*`, `GITHUB_*` and
`PUSH_BEFORE`, copied verbatim from `test/scripts/retire_worktree_e2e_test.dart`** — this test shells
out to `git fetch` / `git worktree add`, and under `pre-commit` the inherited `GIT_DIR`/`GIT_WORK_TREE`
override even `-C` (`feedback_mistake_git_hook_env_leak`; documented at `pre-commit.sh:25-42`). Then
register it in `test/contracts/gate_e2e_env_hermetic_test.dart`'s hand-enumerated `_helpers`.
Mutation: revert to the unconditional `origin/main` preference → red.

### 3.5 `supabase-tests` runs ZERO tests and reports green

`test.yml:263-301`. Both test steps are gated `if: env.SUPABASE_URL != ''`, but `SUPABASE_URL` is
defined **only inside each step's own `env:` block** — there is no job-level or workflow-level
`env:` for it. GitHub evaluates `if:` before the step's own `env:` applies, so the condition is
always false.

**Confirmed against the live run**, not inferred: both steps report `skipped` while the job reports
`success`, and `gh secret list` returns **empty**. The job pays 28s of checkout + flutter-action +
`pub get` to run nothing, and its green tick feeds the claim in CLAUDE.md §0 that "CI is the
full-suite source-of-truth".

**The one-line root-cause fix, which v2 diagnosed but never stated:** hoist
`SUPABASE_URL: ${{ secrets.SUPABASE_URL }}` (and the anon key) from the two step-level `env:` blocks
to a **job-level `env:`**. `secrets` IS available in a job-level `env:`, and `if: env.SUPABASE_URL != ''`
then evaluates correctly — the steps run when the secret exists and skip when it does not, which is
what the condition was always meant to express.

**The visibility half, and its real constraint.** Round 2 is right that "loud but not red" has no
trivial spelling: a job-level `if:` cannot read `secrets` at all (`jobs.<id>.if` sees only `github`,
`needs`, `vars`, `inputs`), so `if: secrets.X != ''` silently does nothing. With no secrets
configured today the honest options are exactly two, and this plan picks the first:
- **Chosen — green with a `::warning::`.** Add a first step that always runs and, when
  `env.SUPABASE_URL` is empty, emits `::warning::Supabase integration tests did not run — no
  SUPABASE_URL secret configured. This job verifies NOTHING.` The annotation surfaces on the run
  page and in the PR UI. Green-but-annotated, not silently green.
- Rejected — a probe job exposing an output plus `needs:` + `if:` on the real job, so it renders as
  *skipped*. Structurally correct but adds a job and a dependency edge to make a cosmetic
  distinction, and `needs:` would put the first `needs:` in this workflow, changing its start-time
  topology.

Do NOT make it red (a false alarm on every push) and do NOT delete the job — it becomes correct the
moment the founder adds the secrets. **Adding those secrets is a founder-only action and is called
out in the batch summary, not silently assumed.**

## 4. EXPECTED RESULT — and the number this plan deliberately does NOT predict

**`--total-shards` shards WITHIN each suite, not across files. Verified at source**, not inferred:
`test_core/lib/src/runner.dart:496-502` — `_shardSuite` computes
`shardSize = suite.group.testCount / totalShards` and filters inside **one** `RunnerSuite`; its call
site at `:297` applies it per-suite. So **every shard still discovers, compiles and loads all 693
test files** and runs every `setUpAll`; only the individual test bodies are divided.

Consequence: **wall clock does NOT divide by N.** The per-file fixed cost is paid in full by every
shard, so the speedup is Amdahl-bounded by whatever fraction of the 6m38s is compile/load rather
than test execution. Round 1 was right to switch to the native flags and round 2 was right that the
*arithmetic* inherited a file-level mental model that the source does not support — **a defect
introduced by round 1's own correction**, which is exactly why §4.12 runs review #2 on the hardened
plan.

**This plan therefore predicts no specific post-change number.** A reviewer's 19-file Windows
subdirectory measured 1.78× at N=3, but that subtree is `test/scripts/` — dominated by spawned
subprocesses, not compile — so it does not generalise to a 693-file Linux run. Substituting it would
be trading one unmeasured number for another.

**Instead, the first CI run IS the measurement**, with the decision rule fixed in advance:
- shard wall clock **≤ 3m22s** → `Build Check (APK)` is the floor; N=3 is done, N>3 buys nothing.
- shard wall clock **> 3m22s** → the shards are the critical path and N>3 still pays. Raise N and
  re-measure until either the APK floor or the fixed-cost floor binds.
- **no meaningful improvement (< 25%)** → the suite is compile-dominated, sharding is the wrong
  lever, and the correct next move is the path-filter option in §8, not more shards.

Writing the rule down before the run is the point: it makes the result falsifiable instead of
retrofitting a story onto whatever number appears.

**Why sharding rather than just `--concurrency`:** in-process concurrency is capped by the single
runner's 4 cores; three shards give 3 machines × 4 cores. But note this cuts BOTH ways — because
each shard re-pays the full compile cost, sharding buys parallelism at the price of duplicated fixed
work, which is precisely why the speedup is sub-linear.

## 5. VERIFICATION

- Workflow wall clock across 3 real runs before vs after. Target ~3m25s; anything above ~4m means a
  premise here is wrong and gets investigated, not rationalised.
- **Total tests executed across all shards == today's single-job total, exactly.** With native
  sharding this is `flutter test`'s own accounting, not a hand-rolled union — sum the per-shard
  "All tests passed" counts and compare against a baseline run.
- The `[gate] <name>` / `[skip allow-list] <name>` **SET** (sorted), before vs after, for the A0-1
  skip-list change — a COUNT survives swapping one gate for another (v1's §5 said "count"; that is
  the very `feedback_green_check_input_set_width` error this repo keeps hitting).
- `supabase-tests` no longer reports a bare green while executing zero tests.
- Blast radius measured via **stdin with the `-` flag** (`… | dart run scripts/blast_radius_from_diff.dart -`)
  — positional args are read as PATHS (`feedback_mistake_blast_radius_positional_mode`), and the
  bare-stdin form without `-` silently prints nothing.

## 6. REQUIRED ARTIFACTS (platform tier)

- `docs/plan-reviews/ci-speedup.md` — `review_rounds: >= 2`, `ground_truth_verified: true`,
  `verdict: converged`, `bpass: accepted`, `---` frontmatter, line-anchored keys.
- Self-initiated `/code-review` B-pass BEFORE the `--no-ff` merge (§4.3).
- `docs/audit/ci-speedup.closure.yaml` — per-entry `terminal_state:`, no `deferred:` key.
- **No rule-24 ledger entry needed** — §2.2 deletes the only new gate v1 proposed. The grandfather
  list stays closed and untouched.
- **TWO live line-number citations into `test.yml`, both of which this batch moves, and nothing
  catches either** (`check_claude_md_citations.dart` covers CLAUDE.md `§N` citations only):
  - `docs/blast_radius.yaml:117` → `test.yml:61` (golden-exclusion rationale) — moved by §3.1.
  - **`docs/audit/open_issues.md:603` → `test.yml:171`** — an OPEN board entry, and line 171 today is
    exactly `check_snapshot_contract.dart|\`. Moved by §3.3 item 1 (which inserts a skip arm) AND by
    §3.2. v2 missed this one; it is the more damaging of the two because the OI board is live
    working state, not a rationale comment.
  Both fixed in the same commit that moves the lines. Historical copies in `docs/reviews/` and
  `docs/superpowers/plans/` are records and stay untouched.
- `test.yml:253` claims the APK job is the critical path (v2 cited `:255`; the sentence spans
  `:253-255`). Measured: it is not — 3m22s vs 7m49s. Correct it while in the file.
- **Derive the shard count once.** `matrix: shard: [0,1,2]` plus `--total-shards 3` is the same
  number written twice and hand-synced; use `${{ strategy.job-total }}` for `--total-shards`.
- **Rename the job.** Stripping analyze (§3.2) leaves `name: Analyze & Unit Tests`, which the matrix
  renders as `Analyze & Unit Tests (0..2)`. Verified NOT load-bearing — `/build-apk --from-green`
  keys on run-level `.conclusion` (`.claude/commands/build-apk.md:357-359`), not job names, and
  required contexts are empty — so this is cosmetic, but rename anyway.
- Commit subjects must NOT begin `fix(` — no diagnose-doc is owed (tooling/CI, not a shipped bug).
  Unit 3 hit this gate once already. Use `perf(ci):` / `chore(ci):` / `fix` only with a real doc.

## 7. SEQUENCING — separate commits, one batch, one push

Not slices of one feature, so §4.3's consolidate rule does not apply; §4.12.1 says split. All land on
this branch and merge together — sequencing, not scope reduction.

- **C1** — A0 corrections (§3.3): trivial, independently verifiable.
- **C2** — `new-worktree.sh` + its test (§3.4): unrelated risk surface, own commit.
- **C3** — the CI change (§3.1 + §3.2 + §3.5): the actual win.

## 8. EXPLICITLY EVALUATED AND NOT DONE

- **Path filters** (skip `analyze-and-unit-test` + `build-check` on docs-only pushes). Plausibly a
  better *average* cycle-time win than sharding, and safe here because required contexts are empty.
  But many gates validate docs (closure YAML, OI index, diagnose-docs, CLAUDE.md citations), so a
  correct filter must keep `audit-gates` running and skip only the two heavy jobs — that needs its
  own analysis of which gates must still run. **Not deferred-as-euphemism: it is a DIFFERENT
  change with a different risk surface, and this batch does not need it to deliver the measured
  4m24s.** Recorded here with its reasoning so the option is not lost.
- **`dart-lang/setup-dart` instead of full Flutter** for `plan-review-record` (35s) and
  `supabase-tests`. Off the critical path — runner minutes only, and the repo is PUBLIC so those
  are free.
