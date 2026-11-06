---
reviewed_at: 2026-08-10T02:40:00+05:30
staged_against: worktree-config-integrity (HEAD 05635e97) vs main
blast_radius: platform
reviewer: fresh-context-blind-agent (adversarial B-pass, two passes)
lens_set: [destructive_safety, ignored_file_blindspot, porcelain_parsing, allow_list_over_match, test_discrimination, doc_code_drift, merge_gate_satisfiability]
findings_count: 8
verdict: accepted
---

# Code Review (B-pass) — worktree config integrity + retirement (`worktree-config-integrity`)

Two adversarial passes by fresh context-blind agents against the staged change set
(`check_worktree_config_integrity.dart` + `retire_worktree.dart` + their pure libs + four test
files + root CLAUDE.md §4.13). Platform tier, so `bpass: accepted` is required by
`check_plan_review_record_exists.dart`.

**Pass 1 rejected on 1 P0 + 5 lesser. Pass 2 rejected on 2 P1. Both sets fixed and verified; this
record is the accepted state after those fixes.** The verdict field reflects the FINAL state, and
the findings below are recorded rather than summarised away — the whole value of this review was
in what it caught.

## Pass 1 — P0: a real credentials file was destroyable

`isRegenerableIgnored` matched allow-listed names by **basename at any depth**, so `.env` also
matched `supabase/.env` — a REAL 518-byte file in this repo, separately ignored at
`.gitignore:69`, which git therefore emits as its own `!!` entry. Reproduced end-to-end in a
scratch repo: `RETIRED deep` → `DESTROYED: supabase/.env is GONE`. `p.contains('/build/')`
likewise made `android/keystore/build/upload.jks` destroyable.

Only the ROOT `.env` is reconstructible (`new-worktree.sh:53` copies exactly that one).

**Worse: the test suite had locked the bug in.** `retire_worktree_lib_test.dart` asserted
`isRegenerableIgnored('supabase/.env')` **must be true**. A green suite proved nothing.

**Fix:** exact-path matching against `regenerableIgnoredPaths` — no prefix, no basename, no
`contains`. A live worktree's entire ignored set is six entries, so exactness costs nothing in
retirability while removing the whole class. The offending assertion is inverted, and three new
tests pin the nested cases.

### Pass-1 lesser findings (all fixed)
- **P1** — no e2e case exercised `!! <dir>/<file>`; the existing "ignored file survives" test used
  `secrets/creds.txt`, which git collapses to `!! secrets/` and which is kept by the trailing-slash
  rule, so it would have passed with the basename allow-list entirely broken.
- **P2** — leg-count drift: lib and script headers still said THREE legs after CLAUDE.md moved to
  four.
- **P2** — `locked` worktrees not honoured (see pass 2 — the first fix for this was inert).
- **P2** — mutation counts in CLAUDE.md mixed lib-only and combined bases.
- **P2** — naming the PRIMARY as a slug printed nothing and exited 0, indistinguishable from
  success.

## Pass 2 — the `locked` fix shipped INERT

Verified against git 2.53: `git worktree list --porcelain` emits `locked` **after** `branch`. The
parser flushed the record on the `branch` line, so `locked` was ALWAYS false. Scratch-repo proof on
a merged+clean+locked worktree:

```
DRY-RUN : RETIRE  lockedwt  [merged + clean …]
EXECUTE : FAILED  lockedwt  [fatal: cannot remove a locked working tree]  EXIT=1
```

— verbatim the outcome the code comment claimed the fix prevented. **Zero tests referenced
`locked`**, which is precisely why it shipped that way. No data loss (git refuses without `-f -f`),
hence P1.

**Fix:** the porcelain parser moved into the pure lib as `parseWorktreePorcelain`, flushing on the
RECORD boundary, with 7 unit tests over captured git output plus an e2e case using a real
`git worktree lock`. Mutation-proven: restoring flush-on-`branch` reddens 3 tests.

Pass 2 also caught **P1-2**: this record's own path was declared in the plan-review record's
`bpass_review:` field while the file did not exist — `check_plan_review_record_exists.dart:854-857`
fails the build on a dangling reference. Closed by this file existing and being committed.

## What this review says about the batch

Four successive P0/P1-class defects in ONE function, each introduced by the fix for the previous:
no ignored check → prefix matching → basename matching → exact matching. Plus a `locked` fix that
was inert and a test that asserted the bug was correct. Every intermediate state passed its tests
and looked finished.

That is the argument for the ×2 review and for mutation-proving each protective leg rather than
trusting coverage. Recorded in the plan-review record's convergence section, and it is the reason
the allow-list now refuses patterns of any kind: **inertness is recoverable, a deleted credentials
file is not.**

## Verified correct (pass 2)

- Exact-path allow-list is not inert: measured ignored set across all 8 live worktrees = exactly 6
  distinct entries, all allow-listed. Scratch `--execute` kept `supabase/.env`, `.envrc`,
  `.envs/prod.key`, `android/keystore/build/upload.jks` byte-intact.
- Test discrimination confirmed against the actual pre-fix implementation: the nested-`.env` and
  nested-directory tests fail there, so they are genuinely discriminating.
- Porcelain shapes: detached counted; prunable → unreadable → KEEP; bare dropped as documented.
- `_countEntries` fixes the empty-subdirectory miscount; `-1` (unreadable) → treated as non-empty.
- Status bucketing sound for renames, quoted/unicode paths, `MM`, `??`.
- Dry-run default; unmatched slug → exit 1; orphan sweep skipped when scoped; `GIT_*` scrubbed.
- 41 tests green; `dart analyze` clean.

## Residual (stated, not hidden)

- `android/.gradle/`, `lib/.dart_tool/`, `.claude/settings.local.json` are ignored in the primary
  but on no live worktree. A worktree that runs gradle would become unretirable until its exact
  path is added. Fail-safe direction (inert, never destructive), so no pattern was added to catch
  it — that is the concession that caused three P0s.
- `GIT_WORK_TREE` remains undetected by the integrity gate: git exports it into every hook, so
  flagging it would fail every pre-commit run. Transient vector; documented in diagnose `a4f7c2`.
