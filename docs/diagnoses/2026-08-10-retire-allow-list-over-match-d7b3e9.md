---
bug_id: d7b3e9
date: 2026-08-10
batch: worktree-config-integrity
status: fixed
blast_radius: platform
symptom: |
  `scripts/retire_worktree.dart` — the worktree-retirement command — would
  DELETE gitignored files that no process can recreate, while reporting the
  worktree as "merged + clean + pushed".

  Three successive P0-class variants, EACH INTRODUCED BY THE FIX FOR THE
  PREVIOUS ONE:

    v1  no ignored check at all. `git status --porcelain` EXCLUDES ignored files
        and `git worktree remove` does NOT refuse on them (verified: exit 0,
        file gone), so an ignored `secrets/.env` was destroyed silently.
    v2  PREFIX matching on the regenerable allow-list. `.env` also matched
        `.envrc` (direnv secrets) and the ignored directory `.envs/`. Because
        `--ignored=matching` collapses an ignored directory to ONE entry, a
        single false positive authorises deleting an unbounded subtree.
    v3  BASENAME-at-any-depth matching. `.env` matched `supabase/.env` — a REAL
        518-byte credentials file in this repo, separately ignored at
        `.gitignore:69` and therefore emitted by git as its own `!!` entry.
        `p.contains('/build/')` likewise made
        `android/keystore/build/upload.jks` destroyable.

  A FOURTH defect in the same file shipped INERT: the `locked`-worktree check.
  Verified against git 2.53, `git worktree list --porcelain` emits `locked`
  AFTER `branch`; the parser flushed the record on the `branch` line, so
  `locked` was ALWAYS false. A routine sweep still hit `fatal: cannot remove a
  locked working tree` and exited 1 — verbatim the outcome the code comment
  claimed the check prevented.

  Every variant was caught in review BEFORE reaching main. No user data and no
  production system was ever affected; the destroyed files in the reproductions
  were scratch-repo fixtures. The one live file at risk, `supabase/.env`, still
  exists (verified).
concept: worktree_retirement_allow_list
sot_registry_entry: >
  Not a Hive/cloud writer-reader storage concept — dev-workflow tooling, same
  class as f0c2d5 and a4f7c2. The contract: an ignored path may be destroyed
  ONLY if it appears verbatim in `regenerableIgnoredPaths`. No prefix, no
  basename, no substring. Deliberately NOT added to docs/sot_registry.yaml,
  which tracks Hive/Postgres writer-reader contracts.
writers:
  - { file: scripts/retire_worktree.dart, method_or_widget: "leg-3 gathering — parses `git status --porcelain --ignored=matching` and counts only NON-regenerable `!!` entries", line: 196 }
  - { file: scripts/new-worktree.sh, method_or_widget: "cp .env into each new worktree — the ONLY reason `.env` is on the allow-list, and only the ROOT one", line: 53 }
readers:
  - { file: scripts/retire_worktree_lib.dart, method_or_widget: "isRegenerableIgnored — exact-path match; anything absent is precious", line: 156 }
  - { file: scripts/retire_worktree_lib.dart, method_or_widget: "parseWorktreePorcelain — flushes on the RECORD boundary so `locked` (emitted after `branch`) is seen", line: 66 }
  - { file: scripts/retire_worktree_lib.dart, method_or_widget: "classifyWorktree leg 3 — ignoredFiles > 0 keeps the worktree", line: 213 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: null
contract_test_path: test/scripts/retire_worktree_lib_test.dart
ist_handling:
  - "Not applicable — git working-tree state. No date key, counter reset, or IST-scoped column."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: |
  Not applicable in the user-account sense — local developer tooling with no
  user data path.
forbidden_patterns_checked:
  - { pattern: "prefix/substring/basename matching in the regenerable allow-list (startsWith, contains, split('/').last)", absent: true }
  - { pattern: "record emitted before the porcelain record boundary (flush on `branch`)", absent: true }
proposed_fix: |
  (1) EXACT-PATH allow-list. `isRegenerableIgnored` compares the normalised path
  against `regenerableIgnoredPaths` with `==` only. A live worktree's entire
  ignored set is SIX entries, so exactness costs nothing in retirability while
  removing the whole false-positive class. The standing rule recorded in the
  file: if this list ever appears to need a pattern, that is the signal to KEEP
  the worktree instead — inertness is recoverable, a deleted credentials file is
  not.

  (2) Porcelain parsing moved into the pure lib as `parseWorktreePorcelain`,
  flushing on the RECORD boundary rather than on `branch`, so `locked` is seen.

  Both were previously unreachable from tests: the allow-list was private to the
  IO script, and nothing referenced `locked` at all.
regression_test_planned:
  - test/scripts/retire_worktree_lib_test.dart
  - test/scripts/retire_worktree_e2e_test.dart
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "41 tests (32 unit + 9 e2e); `dart analyze` clean. MUTATION-PROVEN on every protective leg: dirty 7 red, ignored 4, exact-path 4, record-boundary flush 3. Coverage is explicitly NOT the claim — v3 shipped with a green suite that ASSERTED the bug was correct (`isRegenerableIgnored('supabase/.env')` must be true)." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive box, adapter or key touched." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema change." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "No data path." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "No cron involvement." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "No table involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "No storage involvement." }
  - { tier: 10, name: "Secrets / API keys", status: verified, evidence: "The at-risk artefact WAS a secret: `supabase/.env`, 518 bytes, ignored at .gitignore:69. Confirmed still present on disk after all reproductions; every destructive repro ran in a scratch temp repo, never the real one." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "Contract is tooling-internal. Live dry-run against the real repo keeps every remaining worktree with correct per-leg reasons and reports all orphans without touching them; measured ignored set across all live worktrees is exactly the six allow-listed entries, so the tool is neither destructive nor inert." }
impact_analysis: |
  POTENTIAL: silent, unrecoverable loss of any gitignored file in a worktree
  that was otherwise merged+clean+pushed — credentials (`supabase/.env`,
  `.envrc`), signing material (`android/keystore/.../upload.jks`), local notes.
  Unrecoverable by definition: gitignored means git holds no copy.

  ACTUAL: none. All three variants were caught by review before merge. The
  founder-run sweep that DID execute (46 -> 10 worktrees) ran the v1 code, which
  destroyed only regenerable `.env` copies that `new-worktree.sh` recreates.
  `supabase/.env` verified intact.

  WHY THE TESTS DID NOT CATCH IT: they were written by the same author as the
  fix, in the same pass, encoding the same wrong mental model. v3's suite
  actively asserted the defect was correct behaviour. Coverage measures whether
  a line ran, not whether the assertion was right. The discriminator was
  independent adversarial review plus mutation testing — deliberately breaking
  each leg to confirm the suite notices.
recurrence: |
  First instance in `retire_worktree`, but the THIRD instance of the broader
  "green check narrower than the thing it certifies" class in this batch alone:
  a4f7c2's gate initially had a per-worktree-scope false negative; Gate 44's own
  test never invoked `main()`; and here a test asserted the bug was correct.

  The specific sub-pattern worth naming — **a fix that introduces the next
  instance of the same class** — recurred three times consecutively in ONE
  function. Each fix narrowed the match (none -> prefix -> basename -> exact)
  without asking "what else does this match?". The generalisable rule: when a
  predicate authorises destruction, enumerate what it ALLOWS, never what it
  blocks; and prefer an exact set that must be extended over a pattern that must
  be constrained.
related_bugs:
  - a4f7c2
  - f0c2d5
---

# Retirement allow-list matched too broadly — three times

## The one-line rule that came out of it

> A predicate that authorises deletion takes an EXACT set, never a pattern.
> Inertness is recoverable; a deleted credentials file is not.

## How to check the current behaviour

```
dart run scripts/retire_worktree.dart          # dry-run, safe
```

Anything reported `KEEP … non-regenerable ignored file(s)` is the leg working.
If a worktree becomes permanently unretirable because it acquired a new
generated file, add that file's EXACT path to `regenerableIgnoredPaths` — do
not reach for a pattern.

## Why the suite did not save us

`retire_worktree_lib_test.dart` asserted `isRegenerableIgnored('supabase/.env')`
must be **true**. The test was written from the same wrong model as the code, so
it certified the defect. Every protective leg is now mutation-proven: the fix is
reverted in place and the suite must go red. A test that has never failed is an
untested assumption.
