---
reviewed_at: 2026-08-11T09:10:00+05:30
staged_against: 21774a99e7c2
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 2
verdict: accepted
---

# Code Review — safe-push-verifier (B-pass)

Fresh context-blind Sonnet subagent over the staged diff. Both findings came from
**lens 6 (`guard_without_its_mirror`)** — the lens added on 2026-08-10 after that
class produced four consecutive P0s in one session. It earned its place again
here: lenses 1–5 returned clean, and lens 6 found the only two real issues.

Both findings were **fixed in-batch** (§4.2 — no deferrals), and both fixes were
re-verified by the main thread against the code rather than accepted on reviewer
prose.

## Finding 1 — P2 — guard_without_its_mirror — FIXED

- **file:line:** `scripts/safe_push.sh` retry gate (post-fix :125)
- **claim:** The retry condition was narrowed from `[ "$GIT_EXIT" -eq 0 ] && [ -z "$REMOTE_SHA" ]`
  to `[ "$PROBE_EXIT" -ne 0 ]`, silently dropping the `GIT_EXIT` guard. A push that
  git reports as FAILED now gets a second probe, which the old code never
  attempted — and if that probe observes the ref at our tip, the script exits 0.
  Undocumented, and **zero of the tests exercised `GIT_EXIT != 0` at all**.
- **verification:** `git show HEAD:scripts/safe_push.sh | sed -n '90p'` → old gate
  is `if [ "$GIT_EXIT" -eq 0 ] && [ -z "$REMOTE_SHA" ]; then`. Independently
  re-confirmed by the main thread.
- **resolution:** The widening is **correct and kept** — but it is now documented
  and tested rather than implicit. The old code ALREADY let an observed remote
  override `GIT_EXIT` on the first probe (its `$REMOTE_SHA = $LOCAL_SHA` test ran
  before any `GIT_EXIT` check); it merely refused to retry a flaky probe in that
  case. Applying the rule to both probes is the *consistent* behaviour, and it is
  exactly this wrapper's founding scenario: a push whose data landed and then died
  on an idle SSH channel (SIGPIPE, exit 141) reports failure while the remote ref
  is correct. Added a 16-line comment naming that reasoning, plus a test — "a push
  that git reports as FAILED still exits 0 when the remote ref is OBSERVED at our
  tip" — which drives a genuinely failing `git push` (unknown flag, asserted
  non-zero as ground truth) against an already-landed ref.
  **Honest scope limit:** that test does NOT redden against the pre-fix script
  (old code reached the same exit 0 via its first-probe check), so it is a
  **contract pin, not a mutation proof**. It reddens against the plausible future
  mutation — re-adding a `GIT_EXIT -eq 0` conjunct to the success test.
- **status:** accepted

## Finding 2 — P3 — guard_without_its_mirror — FIXED

- **file:line:** `scripts/safe_push.sh` success message (post-fix :132-137)
- **claim:** Collapsing two success blocks into one lost the distinction between
  "matched on the first probe" and "matched only after a retry" — discarding the
  only signal that the verification round-trip is flaky, which is precisely the
  condition the retry exists to absorb.
- **verification:** `grep -n "confirmed on retry" scripts/safe_push.sh` returned 0
  after the initial fix; the live success path had no retry branch.
- **resolution:** Added a `RETRIED` flag; the success message now reads
  `(matches local; first probe was unreachable, confirmed on retry)` when the
  first probe failed. Observability only, no control-flow change.
  Knock-on: the source assertion that pinned the dead-code removal was keyed on
  the string `confirmed on retry`, which is now legitimately present on a
  REACHABLE path — so it was re-keyed to the **structural** fact instead (exactly
  one `[ "$REMOTE_SHA" = "$LOCAL_SHA" ]` test; pre-fix there were two). Verified
  directly: old = 2, new = 1.
- **status:** accepted

## Lenses that returned clean

- **writer_reader_drift** — sole writer of `REMOTE_SHA`/`PROBE_EXIT`/`_probe_out`
  is `probe_remote_sha()`, called unconditionally once then conditionally on
  retry; every reader runs after at least one call, and the function overwrites
  all three on each invocation (no partial-state carryover). `PROBE_EXIT=$?`
  confirmed POSIX-correct: for a simple assignment whose value is a command
  substitution, `$?` is the substitution's exit status. No `local` bug — the
  script uses none anywhere and the caller deliberately reads the globals the
  function leaves behind. `set -u` cannot fire: every read is preceded by a call.
- **function_exception_swallow** — N/A. POSIX shell + synchronous Dart
  (`Process.runSync`); `grep -n "async\|await\|Future" test/scripts/safe_push_test.dart`
  → no matches. No exception-typed control flow exists.
- **blast_radius_mismatch** — `docs/blast_radius.yaml:158` registers
  `scripts/safe_push.sh` as `platform`; the diff carries a validated diagnose-doc
  declaring `blast_radius: platform`. Rollback is a plain `git revert` (one file,
  no migration, no deployed state). §4.6's feature-flag protocol targets runtime
  payment/sync/auth/AI paths, not build tooling.
- **secrets_in_tree** — credential-shaped-literal grep over the diff returned only
  the English word "token" in a comment about argv word-splitting. Clean.
- **unawaited_no_error_sink** — N/A, same basis as lens 2.

## Caller-impact check (asked explicitly)

`grep -rn "safe_push"` across `scripts/`, `.github/`, `.claude/` finds **nothing
that branches on safe_push.sh's exit status**. `git_safety_hook.dart` /
`git_safety_lib.dart` only string-match the *command text* to decide whether a
shell command routes through the sanctioned wrapper; they never invoke it.
Independently re-verified by the main thread. **Exit code 2 therefore breaks no
caller** — the only consumer is a human or agent reading `$?`, for whom the new
three-outcome contract is strictly more informative than the old two.

## Founder triage notes

Both findings accepted and fixed in the same batch. Final state: 6/6 tests green;
mutation proof (revert `scripts/safe_push.sh` to HEAD, having first asserted the
file actually changed) reddens **3** — `Expected: <1> Actual: <0>` on an absent
ref, `Expected: <2> Actual: <0>` on an unreachable remote, and `Expected: <1>
Actual: <2>` on the structural duplicate-block assertion. `flutter analyze` clean.
