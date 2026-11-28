---
bug_id: d4f9b2
date: 2026-08-11
batch: safe-push-verifier
status: fixed
blast_radius: platform
symptom: >-
  scripts/safe_push.sh — the ONLY sanctioned push path and the file whose entire
  purpose is to be trusted about whether a push landed — exits 0 having verified
  nothing whenever `git ls-remote` cannot reach the remote, printing only a
  stderr WARNING that says "Trusting git's exit code". A caller checking `$?`
  cannot distinguish that from a verified landing. Separately, a duplicated
  success block at :110-115 is unreachable on every route while reading as a
  live success path ("confirmed on retry").
concept: landing_verification_probe_conflation
sot_registry_entry: not_applicable
writers:
  - "scripts/safe_push.sh:78 (pre-fix) — `REMOTE_SHA=\"$(git ls-remote ... | cut -f1)\"`,
     the sole writer of the value every downstream decision reads. Discards BOTH the
     probe's exit status and its stderr."
  - "scripts/safe_push.sh:91 (pre-fix) — the retry, same defect verbatim."
readers:
  - "scripts/safe_push.sh:80 (pre-fix) — first success test on REMOTE_SHA."
  - "scripts/safe_push.sh:98-105 (pre-fix) — `if [ -z \"$REMOTE_SHA2\" ]` → `exit 0`
     with 'Trusting git's exit code'. The reader that cannot tell 'ref absent' from
     'probe failed', because its writer destroyed the only signal separating them."
  - "scripts/safe_push.sh:110-115 (pre-fix) — unreachable-true duplicate success exit."
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/scripts/safe_push_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >-
  Grepped scripts/ for the same `$(cmd ... | cut ...)` shape where the pipeline's
  exit status is then relied upon. safe_merge.sh and safe_commit.sh were hand-checked:
  neither derives a pass/fail decision from a piped command substitution's `$?`.
  Known exposure is this one file. Stated as known-exposure, NOT a census.
proposed_fix: >-
  Capture the probe's exit status separately (`_probe_out="$(git ls-remote ...)"`
  then `PROBE_EXIT=$?`, splitting the field only afterwards), which restores the
  signal that separates "ref genuinely absent" (ls-remote exits 0 with empty
  output) from "could not reach the remote" (non-zero). That makes three honest
  outcomes available where the old code had to choose between two dishonest ones:
  0 LANDED / 1 FAILED / 2 UNVERIFIED. Retry only the ambiguous case — a failed
  probe — never a probe that already answered definitively. Delete the unreachable
  :110-115 block.
regression_test_planned: >-
  test/scripts/safe_push_test.dart, three new behavioral tests driven by real git,
  no stubs. (a) `--dry-run` makes git push exit 0 while provably not moving the ref
  → must exit 1. (b) split push-URL/fetch-URL so the push genuinely lands but
  ls-remote cannot resolve the remote → must exit 2. (c) happy path still exits 0
  and reports the OBSERVED sha. Plus a source assertion for the removed unreachable
  block (presence-only, and labelled as such — unreachable code cannot be exercised
  at runtime).
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "5/5 green in test/scripts/safe_push_test.dart; `flutter analyze` clean (grepped for ^\\s*(error|warning), not tail-piped)." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "Shell script; no Hive surface. Fixtures are scratch git repos in systemTemp." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "MUTATION-PROVEN: reverting scripts/safe_push.sh to HEAD (verified the file actually changed before running — a prior mutation silently no-opped and reported a false pass) reddens 3 tests. Actuals ARE the bug: absent ref gave `Expected: <1> Actual: <0>`; unreachable remote gave `Expected: <2> Actual: <0>`. Happy path and the pre-existing arg-splitting test stayed green, confirming the tests discriminate this fix rather than the file at large." }
impact_analysis: >-
  The wrapper exists because "it reported success" and "it actually landed" had
  silently diverged six documented times. This defect put that exact divergence
  INSIDE the verifier: on any push where the verification round-trip failed, the
  script reported exit 0 while having observed nothing. The stderr WARNING is not
  a mitigation — every automated consumer reads the exit code, and the whole point
  of the wrapper is that a human should not have to read the log to know whether
  the push landed. The second half (piping into `cut`, so `$?` is cut's status and
  always 0) is the same exit-code-masking class the file's own header names as its
  reason for existing, reproduced internally.
related_bugs:
  - "The `feedback_git_landing_verification.md` class this file was written to close
     — exit codes lying about whether work landed. This is that class recurring
     inside the remedy."
  - "f3c7a2 (2026-08-10) — same session-family lesson: a check whose input set is
     narrower than the thing it certifies."
recurrence: >-
  Yes — instance of `feedback_green_check_input_set_width`, the repo's most
  recurrent class. Here the certification is "the push landed" and the input set
  was "an empty string", which two mutually exclusive causes both produce. The
  generalisable rule: when a check collapses a rich result (exit status + stdout +
  stderr) into one impoverished value, verify that no two OPPOSITE conditions map
  onto the same value. `cmd | cut` is a reliable smell, because it discards the
  exit status of everything upstream of the last pipeline stage.
---

# safe_push's verifier could not tell "did not land" from "could not check"

## What happened

`scripts/safe_push.sh` verifies a push by re-reading the remote ref rather than
trusting `git push`'s exit code. The probe was written as:

```sh
REMOTE_SHA="$(git ls-remote "$REMOTE" "refs/heads/$BRANCH" 2>/dev/null | cut -f1)"
```

An empty `REMOTE_SHA` has two mutually exclusive causes:

- **the ref genuinely does not exist** — `ls-remote` exits **0** with empty output.
  The push did not land. A real failure.
- **the probe could not reach the remote** — `ls-remote` exits **non-zero**.
  We simply do not know.

The pipeline discards the exit status (`$?` becomes `cut`'s, which is always 0)
and `2>/dev/null` discards the stderr, so both causes arrive as the same empty
string. With the signal gone, the code had no honest answer available and picked
the worst one — `exit 0`, commented *"Trusting git's exit code"* — in the file
whose header says git's exit code must never be trusted.

## Why the obvious fix was wrong

Flipping that `exit 0` to non-zero re-creates the **F6 false positive** the retry
logic was added to prevent: crying "FAILED" at a push that genuinely landed, just
because the separate verification round-trip blipped. That was caught in review
before it was written — it is the "added a guard without its mirror" class.

The fix is one line **above** the symptom. Capture the probe's own exit status and
the ambiguity disappears, which makes a third outcome expressible:

| exit | meaning |
|---|---|
| 0 | LANDED — the remote ref was **observed** at the local tip |
| 1 | FAILED — git push failed, or the probe succeeded and the ref did not move |
| 2 | UNVERIFIED — push reported success, remote unreachable twice |

`2` is the outcome the old code had no way to say. It is deliberately not `0`
(never claim a landing you did not observe) and deliberately not `1` (never
report failure for a push that may well have landed).

## The dead code

`:110-115` was a second, identical success exit. Both routes to it guarantee
`REMOTE_SHA != LOCAL_SHA`: `:80` already exited on equality, `:92` already exited
on the retry's equality, and `:107` assigns a value `:92` had just proven unequal.
It could never be true — while reading as a live success path, complete with a
"confirmed on retry" message. Removed.

## The transferable part

**When a check collapses a rich result into one value, ask which opposite
conditions now collide.** `cmd | cut` discards the exit status of everything
before the final stage — so any decision made on the result of a piped command
substitution is, by construction, blind to whether the command worked.
