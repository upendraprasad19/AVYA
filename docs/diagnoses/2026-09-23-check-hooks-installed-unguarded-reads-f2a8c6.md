---
bug_id: f2a8c6
date: 2026-09-23
batch: discipline-v3-phase3
status: fixed
blast_radius: platform
symptom: |
  scripts/check_hooks_installed.dart (Gate 32) has always documented its own
  contract as "never hard-fail unexpectedly" -- a hygiene gate whose
  freshness/presence checks degrade to a WARN or an UNDETERMINED-passing
  message rather than crashing the commit over an environment quirk. Live
  code inspection during this batch (an independent, context-blind ×2 plan
  review per CLAUDE.md §4.12) found THREE separate file-read call sites in
  this same script with no surrounding try/catch, each capable of throwing
  UNCAUGHT and turning a documented "never hard-fail" gate into an
  accidental hard FAIL: (1)+(2) inside the per-hook freshness-comparison
  loop, reading the installed hook's content and the source script's
  content; (3) the installer script's own read at the top of main(). No
  founder report triggered this -- found by two independent review rounds
  re-reading the whole file rather than trusting a prior round's "fixed"
  claim: round 1 (earlier in this session) found and fixed (1)+(2); round 2,
  dispatched fresh with no memory of round 1's diff, re-grepped every
  readAsStringSync() call site in the file and found (3) sitting nine lines
  above the other two fixes.
concept: check_hooks_installed_unguarded_reads
sot_registry_entry: |
  Not a Hive/cloud writer-reader concept. This is a pre-commit gate script
  (grandfathered, docs/audit/gate_test_ledger.yaml) hardening its own
  fail-open contract. No SoT registry entry applicable.
writers:
  - { file: scripts/check_hooks_installed.dart, method_or_widget: "main() -- installer read", line: 122 }
  - { file: scripts/check_hooks_installed.dart, method_or_widget: "main() -- per-hook installed-content read", line: 187 }
  - { file: scripts/check_hooks_installed.dart, method_or_widget: "main() -- per-hook source-content read", line: 220 }
readers:
  - { file: test/scripts/check_hooks_installed_e2e_test.dart, method_or_widget: "process spawn of the real gate binary against fixture repos", line: 84 }
hive_key_prefix: "N/A -- infra/tooling fix, no Hive involvement"
hive_key_formula: "N/A"
sync_methods:
  - "N/A -- no cloud sync involved"
restore_methods:
  - "N/A"
cloud_table: "N/A -- no cloud table involved"
cloud_columns:
  - "N/A"
contract_test_path: test/scripts/check_hooks_installed_e2e_test.dart
ist_handling:
  - "Not applicable -- no date offsets within this fix."
provider_invalidations:
  - "N/A -- no Riverpod providers involved"
telemetry_op_types:
  success:
    - "N/A"
  failure:
    - "N/A"
cross_account_guard: "N/A -- this is a repo-local pre-commit gate with no per-user data access."
forbidden_patterns_checked:
  - { pattern: "readAsStringSync() with no surrounding try/catch inside a gate documented as never-hard-fail", absent: true }
proposed_fix: |
  All three reads wrapped in try/catch, each degrading to the SAME shape
  the file already established for its other fail-open branches:
  (1)+(2) (round 1, earlier this session) -- degrade to a WARN naming the
  hook and "checked for PRESENCE only, its contents were not verified
  against anything", then `continue` to the next hook.
  (3) (round 2, this session) -- degrade to the SAME "UNDETERMINED
  (passing)" message shape the missing-installer branch (existsSync()
  check) already used a few lines above it, then exit(0).
  No structural rewrite (e.g. wrapping the whole of main() in one blanket
  try/catch, as scripts/check_hive_first_pattern.dart does) was applied --
  considered and declined during the B-pass, since the three point patches
  each carry a message specific to what failed, which a single blanket
  catch would collapse into one generic message, losing diagnostic
  specificity the file's own comments treat as deliberate.
regression_test_planned:
  - "test/scripts/check_hooks_installed_e2e_test.dart: 'an unreadable (invalid-UTF-8) installed hook degrades to a WARN, never crashes' (round 1) and 'an unreadable (invalid-UTF-8) installer script degrades to UNDETERMINED, never crashes' (round 2) -- both write invalid UTF-8 bytes to the target file so existsSync() stays true while readAsStringSync() throws FormatException, then assert exit code 0 and the expected message substring."
  - "Mutation-proof (round 2, confirmed applied): reverting the installer try/catch to a bare readAsStringSync() reddens exactly the new installer test, with the process exiting 255 (an uncaught crash) instead of 0. Reverted back to the fix afterward; all 7 tests in the file confirmed green again."
impact_analysis: |
  Scoped entirely to scripts/check_hooks_installed.dart (Gate 32), a
  pre-commit hygiene gate. No product code, no Hive schema, no cloud table,
  no migration. Before this fix, any of three realistic conditions --
  a permission error, invalid file encoding, or a delete-between-
  existsSync()-and-read race on scripts/setup-hooks.sh or an installed
  git hook -- would have crashed this gate with a non-zero exit, blocking
  every commit in every worktree until the transient condition cleared,
  which is the exact ship-stop-over-a-hygiene-problem class CLAUDE.md
  §4.13 point 6 already names as unacceptable for a different gate in this
  same family. No other caller of these read sites exists (both are
  private to main() in this file).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "scripts/check_hooks_installed.dart:104-130 (installer read), :187-194 (installed-hook read), :220-227 (source read) -- all three now try/catch-guarded; verified via test/scripts/check_hooks_installed_e2e_test.dart (7 tests, all green) plus two independent mutation proofs (round 1: reverting the per-hook guards reddens the installed-hook-unreadable test; round 2: reverting the installer guard reddens the installer-unreadable test with exit 255)." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive access in this fix." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema access." }
---

## Summary

`scripts/check_hooks_installed.dart` (Gate 32) documents its own contract as
"never hard-fail unexpectedly" throughout its comments, but had three
unguarded `readAsStringSync()` calls that could throw uncaught and violate
that contract. Two were found and fixed in an earlier round this session;
the third survived that fix and was found only by a second, independent,
context-blind review round re-reading the whole file from scratch.

## Root Cause

The per-hook freshness-comparison loop (added the same session, for OI-104)
introduced two new file reads with no try/catch. Once those were found and
fixed, it was reasonable to believe the "unguarded read" class was closed --
but the installer's own read, a few lines above the loop and written before
this session even started, was never audited against the same standard. A
fix that closes N of N *known* instances of a class does not close the
class if N was undercounted; only re-grepping every call site (rather than
re-reading the fix's own diff) surfaces the miss.

## Fix

All three call sites now wrap their read in try/catch and degrade to the
message shape already established elsewhere in the same file (WARN for the
per-hook loop, UNDETERMINED-passing for the installer), then either
`continue` or `exit(0)` as appropriate -- never propagate the exception.

## Related

Same defect family as `docs/diagnoses/2026-09-23-discipline-hook-memory-path-worktree-bug-c8d5b2.md`
(a fix applied to one instance of a bug class, verified narrowly, missing a
sibling instance) though a different root cause. Both found by this same
session's discipline-v3-phase3 batch through independent review rather than
a live founder-reported symptom.
