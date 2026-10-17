---
bug_id: f4d1b7
date: 2026-06-12
batch: audit-2026-06-10
status: fixed
blast_radius: feature
symptom: >
  Two commit-gate tooling bugs surfaced during the f1c8e4 commit gauntlet, both
  in the "stable staged-diff hash" path the catastrophic review gate
  (check_code_review_pass_exists.dart) relies on:
  (#2) scripts/build_bug_index.dart embedded a wall-clock `Generated:
  ${DateTime.now()}` line in docs/diagnoses/INDEX.md, so the regenerated INDEX
  differed on EVERY run — shifting the staged-diff hash (and producing noisy
  no-op diffs). It also sorted entries by `date` only (Dart List.sort is not
  stable; dir.listSync() is filesystem-ordered), so two same-date diagnose-docs
  could swap on re-run.
  (#3) scripts/check_code_review_pass_exists.dart computed the staged-diff hash
  by decoding `git diff --cached` stdout to a String (SystemEncoding — cp1252 on
  Windows) and hashing `.codeUnits` (UTF-16). Both steps corrupt non-ASCII
  bytes, so for any diff containing a non-ASCII char (the ⚠️ emoji in migration
  090 during the 2026-06-11 security commit) the gate's hash diverged from
  `git diff --cached | git hash-object --stdin` and the catastrophic review file
  could never be matched — forcing a workaround (split the diagnose into a
  separate docs: commit) to land the security fix.
concept: commit_gate_hash_stability
sot_registry_entry: not_applicable
writers: >
  scripts/build_bug_index.dart (emits docs/diagnoses/INDEX.md) +
  scripts/check_code_review_pass_exists.dart (stagedDiffHash()).
readers: >
  The catastrophic review gate matches docs/reviews/<staged-diff-hash>-review.md;
  the diagnose-index-fresh gate diffs the regenerated INDEX.md.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable (build-tooling scripts; no Hive)
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/contracts/review_gate_hash_raw_bytes_test.dart
ist_handling: >
  not_applicable for #3. For #2 the FIX is removing a wall-clock timestamp
  entirely (it served no purpose — git history records change times); the INDEX
  content is now a pure function of the diagnose-doc inputs.
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - "build_bug_index emitting a DateTime.now() Generated: line — removed; INDEX is now deterministic (verified: two runs byte-identical)."
  - "stagedDiffHash decoding to String + hashing .codeUnits — replaced with raw-bytes (stdoutEncoding: null) so the hash matches git hash-object."
proposed_fix: >
  (#2) Drop the `Generated:` timestamp line from build_bug_index.dart; add a
  `_path` tiebreak to the entry sort for a stable total order. (#3) Capture
  `git diff --cached` with `stdoutEncoding: null` (raw List<int> bytes) and feed
  those verbatim to `git hash-object --stdin`, byte-identical to git's own hash.
regression_test_planned: >
  test/contracts/review_gate_hash_raw_bytes_test.dart — proves raw-UTF-8-bytes
  via --stdin == `git hash-object` of a file with non-ASCII (⚠️ + é), AND that
  the old `.codeUnits` (UTF-16) path diverges. #2 verified empirically: running
  build_bug_index twice now yields a byte-identical INDEX.md.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "build_bug_index.dart determinism (two-run diff byte-identical) + check_code_review_pass_exists.dart raw-bytes hash; review_gate_hash_raw_bytes_test 1/1 green" }
impact_analysis: >
  Feature blast radius (build tooling only; no app/data effect). Latent severity
  was moderate-for-process: both bugs jam the catastrophic-tier review gate (the
  hash can't match a real review file), which is exactly when the gate matters
  most — this session hit #3 live and had to work around it to ship a security
  fix. No user impact. Found during the f1c8e4 commit gauntlet (audit-2026-06-10);
  feeds the debugging skill's commit-gate bug-class.
---

# Commit-gate hash stability: INDEX non-determinism + review-gate UTF-16 hash (f4d1b7)

## What happened
Two tooling bugs in the staged-diff-hash path the catastrophic review gate keys on:
1. `build_bug_index.dart` embedded `Generated: ${DateTime.now()}` in INDEX.md →
   the regenerated INDEX differed every run → the staged-diff hash shifted.
2. `check_code_review_pass_exists.dart` hashed the diff as `String.codeUnits`
   (UTF-16) after a SystemEncoding decode → non-ASCII bytes (an emoji) made the
   gate's hash diverge from `git hash-object`, so the review file never matched.

## Root cause
(1) A wall-clock timestamp in deterministic-by-design output. (2) Decoding raw
git bytes to a String then re-deriving bytes via UTF-16 code units — never
byte-faithful for non-ASCII (and worse under Windows cp1252).

## Fix
(1) Remove the timestamp; add a `_path` tiebreak for a stable sort. (2) Capture
the diff as raw bytes (`stdoutEncoding: null`) and feed them verbatim.

## Verification
- `build_bug_index` run twice → byte-identical INDEX.md.
- `test/contracts/review_gate_hash_raw_bytes_test.dart` 1/1 (raw == git;
  codeUnits diverges).

## See also
- scripts/build_bug_index.dart
- scripts/check_code_review_pass_exists.dart (`stagedDiffHash`)
- .claude/skills/debugging/SKILL.md (commit-gate bug-class)
