---
reviewed_at: 2026-08-13T12:05:00+05:30
staged_against: origin/main...supabase-test-http
blast_radius: feature
reviewer: fresh-sonnet-subagent-context-blind
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 6
verdict: accepted
---

# Code Review (B-pass) — `supabase-test-http`

Self-triggered per §4.3 before the merge to `main`. The reviewer was told explicitly to assume
motivated reasoning, because the author of the diff is the person the diff unblocks.

**Outcome: 2 P1, 2 P2, 2 P3. All six actioned in-batch. One P1 proved a board entry I had marked
`Verified` was factually false.**

## Finding 1 — P1 — unverified_claim (OI-118 contradicted by its own cited source)

- **file:line:** `docs/audit/open_issues.md` (OI-118 as filed), contradicted by `scripts/safe_commit.sh:43`
- **claim:** OI-118 stated "`safe_commit.sh` logs to a fixed `/tmp` path". The actual line is
  `LOG="$(mktemp 2>/dev/null || echo "/tmp/safe_commit_$$.log")"` — unique per invocation, PID
  fallback — and `:50`/`:82` `cat` it to stdout then `rm -f` it. The string `safe_commit_run.log`
  appears **zero** times in that script in every version in its history.
- **verification:** `git log -p --all -- scripts/safe_commit.sh | grep -c "safe_commit_run.log"` → `0`;
  `grep -rn "safe_commit_run" scripts/` → no matches.
- **what I actually did wrong:** the OBSERVATION was real — I read `/tmp/safe_commit_run.log` and got
  another session's commit. I then named a mechanism without opening the script, and filed it under
  `Verified`. Nothing writes that path; agent sessions redirect stdout there ad hoc and several
  independently chose the same name. My proposed fix would have "fixed" a collision `mktemp` already
  prevents.
- **fix applied:** OI-118 rewritten with the correction kept in-place as a visible warning block,
  reframed as a practice hazard (don't redirect to a guessable shared `/tmp` name), downgraded P2→P3,
  and its blast radius corrected `platform`→`feature` since no script changes.
- **status:** fixed

## Finding 2 — P1 — signal_degradation (CI job headroom, missed entirely by the author)

- **file:line:** `test/contracts/git_safety_hook_integration_test.dart:115-237` vs `.github/workflows/test.yml:93,112`
- **claim:** tests within one file run sequentially, so that file's worst-case timeout exposure went
  from 8×30s + 1×60s = **5 min** to 9×120s = **18 min**, against a `unit-test` job capped at
  `timeout-minutes: 20` running the unfiltered full suite. ~2 minutes of margin.
- **verification:** `grep -n "timeout-minutes" .github/workflows/test.yml` → `:93` = 20; `:112` runs
  `flutter test test/ --exclude-tags golden`.
- **why it matters:** it does not invalidate the raise (every observed failure was a timeout, none an
  assertion; all 21 test bodies read, none has a path where waiting changes the RESULT). The exposure
  is forward-looking and is the *same conflation the fix exists to fight*: a future genuine hang
  degrades the signal from "9 named TimeoutExceptions in one file" to "the job timed out", which names
  nothing.
- **fix applied:** filed as **OI-120** (deliberately separate from OI-116, which is scoped to the local
  gate — different runner, different limit, different fix), and added to `c3f9a7`'s "What is NOT fixed
  here" section naming it as something I failed to check.
- **status:** fixed

## Finding 3 — P2 — guard_without_its_mirror (the timeout raise had no regression coverage)

- **file:line:** the three guarded files; `c3f9a7`'s `regression_test_planned: None added, deliberately`
- **claim:** nothing asserted these files declare a non-default timeout. A merge conflict or IDE tidy-up
  restoring 30s would reintroduce the bug disguised as flakiness — which the diagnose-doc itself names
  as the dangerous shape.
- **verification:** `grep -rln "c3f9a7|subprocess_test_timeout" test/ scripts/` → only the files' own headers.
- **fix applied:** added `test/contracts/subprocess_test_timeouts_declared_test.dart`. Asserts a ≥90s
  floor, parsed by **regex on the `Timeout(Duration(...))` argument shape** rather than literal source
  text (this repo has a guard on record defeated by one extra space), plus a mirror assertion that the
  guarded-file list is length 3 and every path exists, so a rename cannot silently shrink coverage.
  **MUTATION-PROVEN:** restoring one `Duration(seconds: 30)` in place reddens it with
  `Expected: empty / Actual: [30]`. Restored after; file confirmed byte-identical.
  Header states plainly what it proves (declarations survive) and what it does not (that the timeouts
  suffice).
- **status:** fixed

## Finding 4 — P2 — unbounded_local_walk (quantifies OI-116)

- **file:line:** `scripts/pre-commit.sh:341-347`, `scripts/check_regression_catalog.dart:56-64`
- **claim:** `pre-commit.sh` contains zero occurrences of "timeout" and the `Process.run` has no timeout
  parameter, so the merge walk is entirely unbounded at the shell level. This diff raises that file's
  worst-case contribution 5 min → 18 min: a 3.6× larger hang window with no external backstop.
- **verification:** `grep -n timeout scripts/pre-commit.sh` → 0 hits.
- **fix applied:** the multiplier added to OI-116's evidence. No separate action — OI-116 already owns
  the root cause and correctly states a measurement is needed before picking a bound.
- **status:** fixed

## Finding 5 — P3 — misattributed_mechanism (OI-119 conflated two different detectors)

- **file:line:** `scripts/git_safety_lib.dart:32-33` (unanchored) vs `:18-27` (anchored per statement)
- **claim:** OI-119 bullet 2 (`--no-verify` prose blocked) is confirmed and is the leaky one —
  `commandHasNoVerifyFlag` is a fully unanchored substring match, which the reviewer reproduced
  **involuntarily** when its own read-only `grep -n -- "--no-verify" docs/audit/open_issues.md` was
  blocked. Bullet 1 (a grep for `git`+`commit` text) does **not** reproduce:
  `commandInvokesGitSubcommand` anchors on `^git` per statement. I attributed my block to the wrong
  detector without checking.
- **verification:** read both functions; the anchoring difference is plain.
- **fix applied:** OI-119 corrected — bullet 1 marked as not reproducing with the likely real cause,
  and the fix shape now says **split it**: tighten the unanchored flag matcher, leave the anchored
  subcommand matcher alone since changing it risks reopening the raw-push hole.
- **status:** fixed

## Finding 6 — P3 — imprecise_citation (OI-117 line number)

- **file:line:** OI-117 cited `pre-commit.sh:318`; the invocation is `:315`, and `:318` is the closing `) &`.
- **fix applied:** corrected to `:315`, and the note now explains *why* the `Killed` message appears
  despite `>/dev/null 2>&1` — it comes from bash job control, not from the gate.
- **status:** fixed

## Lenses returning clean (with evidence, per the skill's anti-pattern rule)

- **writer_reader_drift** — `git diff --name-only | grep -E "^lib/|^supabase/functions/"` → 0 hits.
  Genuinely N/A: test infrastructure and docs only.
- **function_exception_swallow** — `grep -n "\.functions\.invoke("` across all changed files → 0 hits.
- **blast_radius_mismatch** — `test/**` and `docs/**` both → `feature` (`docs/blast_radius.yaml:255,257`);
  the `platform`-pinned gate SOURCES are untouched (`git diff --name-only | grep '\.dart$' | grep -v '^test/'`
  → 0 hits). Self-declared tier is mechanically correct. *Reviewer's soft observation, recorded not
  actioned:* the registry has no tier for "a test OF a platform-tier gate", so a future change that
  genuinely weakened an assertion in these files would also classify `feature`.
- **secrets_in_tree** — `QA_Test_2024!` / `qa@icanbefitter.com` are **pre-existing**: `git blame` puts
  both at commit `de94c9f38`, 2026-04-04, four months before this branch. Not introduced here. OI-115
  already records the account does not exist, so the credential is inert.
- **unawaited_no_error_sink** — 2 hits, both pre-existing context lines in `docs/diagnoses/INDEX.md`
  quoting an unrelated 2026-06-27 entry. No new call sites.

## Questions the reviewer answered by experiment rather than by reading

- **Is `debugRemoveHttpMock()` safe process-wide?** Directly tested with a purpose-built 2-file probe:
  file A held a marker `HttpOverrides.global` for 4s; file B checked at t≈1.6s and t≈3.6s — both inside
  A's window — and saw `null` both times. `flutter test` gives each test FILE its own isolate with
  independent `dart:io` static state, so nulling the mock cannot leak into a sibling file. This rules
  out the contamination risk I was most worried about. It is never restored, which is harmless for the
  same reason (the isolate exits). `grep -rn "HttpOverrides|MockHttpOverrides|createHttpClient" test/`
  → only the two files in this diff depend on it.
- **Can the new HTTP test pass vacuously?** Mutation-tested: removing the fix line yields
  `Expected: null / Actual: <Instance of '_MockHttpOverrides'>`. The precondition assertion throws on
  failure, so a future Flutter that stops installing the mock fails loudly rather than skipping to a
  false green.

## Founder triage notes

All six findings actioned in-batch per §4.2 — none deferred. The two P1s are the ones worth
remembering: one was a false `Verified` claim of mine (the most recurrent mistake class in this repo,
committed inside a batch whose own subject is signals that misreport), and the other was a real risk
I missed because I checked the local gate and stopped rather than following the same question into CI.
