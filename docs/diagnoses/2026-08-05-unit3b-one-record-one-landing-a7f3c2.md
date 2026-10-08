---
bug_id: a7f3c2
date: 2026-08-05
batch: unit3b-one-record-one-landing (Unit 3b, split out of the 3-part
  discipline-tooling-hardening unit c9f4e1 per CLAUDE.md §4.12 — three
  consecutive review rounds each surfaced new material issues, which is the
  stated signal to ship the smallest converged piece)
status: fixed
blast_radius: platform
symptom: >
  scripts/check_plan_review_record_exists.dart — the keystone merge-to-main
  gate — carried a numbered, self-documented hole in its own source. OI-58b's
  "one-record-one-landing" rule (a branch that lands at >=account a SECOND
  time must show its plan-review record was actually re-touched, not reused
  verbatim from the first landing) was independently reviewed and
  bpass-accepted in docs/plan-reviews/gate-input-family.md, then split into
  its own unit alongside OI-58a and never implemented. The gate's own code
  said so out loud: "One-record-one-landing (OI-58b) is NOT enforced here —
  it ships with OI-58a in the split unit. A branch re-landing at >=account
  can still satisfy the gate with the record from its first landing."
  Concretely: land branch X at account tier with a converged record, then
  later re-land the SAME branch name with an entirely different (possibly
  unreviewed) diff, and the gate re-reads the SAME unchanged record and
  passes. The record is keyed on branch NAME, so nothing tied it to the diff
  it was supposed to have reviewed.
concept: plan_review_record_gate
sot_registry_entry: not_applicable — this is CI/pre-commit gate tooling, not
  a writer/reader data contract. It reads git history and record files; it
  writes nothing to Hive or Postgres.
writers: not_applicable — the gate is read-only. It performs no writes to any
  store. Its only output is stdout/stderr plus an exit code.
readers: >
  scripts/check_plan_review_record_exists.dart:main (the loop over landings)
  reads docs/plan-reviews/<branch>.md via `git show <rev>:<path>` — the record
  must be in the merge commit's OWN tree, so a later commit cannot retroactively
  satisfy an earlier merge. Consumed by .github/workflows/test.yml's dedicated
  job (checkout fetch-depth: 0) and by scripts/safe_push.sh's local pre-push
  re-run.
hive_key_prefix: not_applicable — no Hive access anywhere in this gate.
hive_key_formula: not_applicable — no Hive keys are read or written.
sync_methods: not_applicable — no sync path is touched; this never runs on device.
restore_methods: not_applicable — no restore path is touched.
cloud_table: not_applicable — no Postgres access.
cloud_columns: not_applicable — no Postgres access.
contract_test_path: test/scripts/plan_review_record_gate_e2e_test.dart
ist_handling: not_applicable — the check is a byte-comparison of two git blobs
  and a first-parent history walk. No dates, no timestamps, no date-keys are
  computed or compared, so there is no timezone surface at all.
provider_invalidations: not_applicable — no Riverpod providers; this is a
  standalone Dart script run by CI and git hooks, never inside the app.
telemetry_op_types: not_applicable — gate scripts report via stdout/exit code,
  not ErrorTelemetry. The advisory NOTE is deliberately stdout so that real
  occurrences can be observed in CI logs before anything here can block a merge.
cross_account_guard: not_applicable — no user scope, no auth, no per-user state.
forbidden_patterns_checked: >
  No Container(color:+decoration:), no raw Supabase/Hive access from widgets, no
  client-side API keys, no inline isPro checks — none apply to a standalone gate
  script. Checked the two that DO apply: (a) the new code adds no `fail()` call,
  so it cannot block a merge while the baseline is being observed (§4.11 gates-
  before-refactor: observe first, promote to hard-fail after); (b) it introduces
  no new git-history assumption beyond the first-parent walk the gate already
  performed.
proposed_fix: >
  Add _checkOneRecordOneLanding to scripts/check_plan_review_record_exists.dart.
  It walks first-parent history strictly BEFORE the landing under inspection,
  finds the most recent earlier landing of the SAME raw branch name, and
  byte-compares that landing's record blob against the current one. Identical
  bytes => the record cannot be showing that THIS diff was reviewed, so it emits
  an advisory NOTE on stdout. Deliberately NOT routed through fail(): this is new
  history-walking logic in a file with a documented habit of subtle bugs (four
  attempts at the neighbouring version-bump exemption, each caught by independent
  review before landing). Ships informational-only so real NOTEs can be observed
  before it can block anything.
regression_test_planned: >
  test/scripts/plan_review_record_gate_e2e_test.dart — three tests driving the
  REAL script as a subprocess against purpose-built git repos with real merge
  commits, not mocked history: (1) a re-landing whose record is UNCHANGED prints
  the NOTE and still exits 0; (2) a re-landing whose record WAS updated prints no
  NOTE; (3) a FIRST landing of a brand-new branch name prints no NOTE. Positive,
  negative and boundary — so a mutation that makes the check fire always, or
  never, fails at least one.
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "No lib/ file touched — scripts/ + test/ only, so the change cannot reach the Flutter app at runtime. `dart analyze scripts/check_plan_review_record_exists.dart` — 0 issues." }
  - { tier: 2_hive, status: not_applicable, evidence: "The gate performs no Hive access." }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "No schema surface; no migration in this unit." }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "No Postgres access." }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "No migration authored or applied." }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "No supabase/functions/ file touched." }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "No cron dispatch involved." }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "No table, so no policy." }
  - { tier: 9_storage, status: not_applicable, evidence: "No storage access." }
  - { tier: 10_secrets, status: not_applicable, evidence: "Reads no secret — local git plumbing only, no network call, no token." }
  - { tier: 11_external_services, status: not_applicable, evidence: "No external service contacted." }
  - { tier: 12_client_server_contract, status: fixed_in_this_batch, evidence: "The repaired contract is process-side: between a merge commit and the plan-review record claiming to have reviewed it. Verified by EXECUTION, not inspection — the 3 e2e tests build real git repos with real merge commits and drive the real script as a subprocess, and the gate was separately run against the live repo with GITHUB_REF=refs/heads/main so the branch short-circuit could not yield a vacuous PASS." }
impact_analysis: >
  Advisory-only by construction, so the blast radius of a BUG in this code is
  bounded to a spurious or missing stdout line — it cannot block a correct merge
  and cannot pass a merge the pre-existing checks would have failed. That is
  deliberate: the value shipped today is the observation baseline, not
  enforcement. Two known divergences from the vetted gate-input-family.md
  predicate are stated in the function's own doc comment rather than silently
  carried: (a) it does not check the PRIOR landing's tier, so a leftover record
  from an unrelated situation could in principle be compared against (no known
  live instance); (b) it is a point-in-time blob comparison, not a range walk, so
  it cannot distinguish "genuinely re-reviewed" from "byte-identical after two
  edits that cancel out". Round-1 review finding #9 additionally notes the
  branchMerge/pullRequestMerge restriction is bypassable by an author who phrases
  a landing's subject in the remoteSyncMerge shape — harmless while advisory,
  and it must close before any promotion to fail(). Promotion to fail() is the
  moment real risk starts and takes a full CLAUDE.md §4.12 review then, not now.
---

# Unit 3b — the keystone gate could not tell a re-landing from a first landing

## Why this is Unit 3b and not Unit 3

`discipline-tooling-hardening` (diagnose `c9f4e1`) bundled three independent
pieces: **3a** a git lock (`_git_lock.sh`), **3b** this gate check, **3c** a
`safe_merge.sh` wrapper. Rounds 1, 2 and 3 each surfaced NEW material issues —
round 2 rewrote 3a's claim mechanism after reproducing a live race between
claiming the lock and writing its holder metadata; round 3 then found the
*reclaim* branch had the same check-then-act shape one step over, which neither
earlier round had caught.

CLAUDE.md §4.12 names that pattern explicitly: when successive reviews keep
surfacing new material issues, the unit is too large — split it and ship the
smallest converged piece. This is that split.

3b is the piece that converged. It was verified independent by grep, not by
assertion: its diff contains zero references to `_git_lock`, `git_lock_acquire`,
`git_lock_release` or `safe_merge`. 3a and 3c cannot split further from each
other — `safe_merge.sh` sources `_git_lock.sh` as a hard runtime dependency —
and they ship separately once one narrowly-scoped round on the round-3 reclaim
fix clears.

This doc is deliberately NOT a copy of `c9f4e1`. That doc's frontmatter and
narrative describe the combined unit, including the lock's three-round history,
and reusing it would have made this landing look reviewed for work it does not
contain.

## The hole

The gate's own source documented it, in the code, unresolved:

```
// One-record-one-landing (OI-58b) is NOT enforced here — it ships with
// OI-58a in the split unit. A branch re-landing at >=account can still
// satisfy the gate with the record from its first landing.
```

The record is keyed on **branch name** — necessarily so, because the file is
authored during development and its name has to be stable at both author-time
and merge-time (a staged-diff hash is empty at a merge commit). The consequence:
land branch `X` at account tier with a converged record; later re-land the same
branch name carrying an entirely different, possibly unreviewed diff; the gate
re-reads the same unchanged record and passes. Nothing tied the record to the
diff it claimed to have reviewed.

`docs/plan-reviews/gate-input-family.md` (lines 156-160) had already reviewed
and bpass-accepted a *more precise* predicate for this gap — "if the branch has
already landed at ≥account, the record must have been modified in this range" —
then split it out and never implemented it.

## What ships, and how it differs from the vetted design

`_checkOneRecordOneLanding` walks first-parent history strictly before the
landing under inspection, finds the most recent earlier landing of the same raw
branch name, and byte-compares that landing's record blob against the current
one. Identical bytes ⇒ the record cannot be evidence that *this* diff was
reviewed ⇒ advisory NOTE on stdout.

An earlier draft of the function's doc comment claimed it implemented the
gate-input-family predicate. Round-1 review of this function established that it
does not. Rather than quietly leave the claim standing, the comment now states
the two divergences outright:

- it does not check the **prior landing's own tier**, so a leftover record from
  an unrelated situation could in principle be compared against (no known live
  instance);
- it is a **point-in-time blob comparison, not a range walk**, so it cannot
  distinguish "genuinely re-reviewed" from "byte-identical after two edits that
  cancel out".

## Why advisory, not `fail()`

Deliberate, per §4.11 (gate before refactor: observe, then enforce). This is new
history-walking logic in a file with a documented habit of subtle bugs — the
neighbouring version-bump exemption took four attempts, each caught by
independent review before landing. Shipping it as a stdout NOTE means real
occurrences can be observed in CI before anything here can block a merge.

Round-1 finding #9 is recorded at the code: the `branchMerge`/`pullRequestMerge`
restriction is bypassable by an author who phrases a landing's subject in the
`remoteSyncMerge` shape (`Merge branch 'X' of <url>`). Harmless while advisory —
the cost is a missed NOTE — but it must close before any promotion to `fail()`.
That promotion is when real risk starts, and it takes a full §4.12 review then.

## Verification — by execution, not inspection

- **`dart analyze`** on the gate: 0 issues.
- **All 8 tests green** in the e2e file (5 pre-existing + 3 new).
- **Negative-controlled in both directions**, which is what distinguishes a test
  that discriminates from one that merely passes:
  - *never fires* (function returns null immediately) → **only** the positive
    test fails; the two absence-asserting tests still pass.
  - *always fires* (returns a message unconditionally) → **all three** fail.
    Test 1 fails here too, because it pins the message CONTENT — it asserts the
    fixture branch name `reuse-stale` appears, not merely that the
    `NOTE (possible stale reuse)` marker did. A test that checked only the
    marker would have passed under this mutation.
  - The script was restored from a byte-copy after each mutation and re-verified
    by md5 (`a9667c19…`), with a grep confirming no `MUTATION` residue.
- **The gate was run against the live repo** with `GITHUB_REF=refs/heads/main`
  and `PUSH_BEFORE` set to the real range base, so the branch short-circuit
  could not manufacture a vacuous PASS. (An earlier run in this session PASSED
  only because the branch was not `main` — that PASS proved nothing.)

## Related

- `c9f4e1` — the combined unit this was split out of; 3a + 3c still there.
- `docs/plan-reviews/gate-input-family.md` — the vetted predicate this
  approximates, and the OI-58a/58b split that stranded it.
- OI-58b — remains OPEN. This ships its realistic half as an advisory; the
  residual first-time spoof needs PR-enforced merge subjects, a
  repository-settings decision, not a code change.
