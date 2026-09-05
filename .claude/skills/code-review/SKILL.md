---
name: code-review
description: Adversarial review pass over the staged diff. Run when blast-radius is ≥ account, or invoke manually. Dispatches a FRESH Sonnet subagent (no conversation context) prompted to find bugs not validate. Writes structured findings to docs/reviews/.
type: process
priority: high
self-evolving: true
---

# Code Review (B-pass) — Fresh-agent Adversarial Pass

> Track 1 of the 2026-05-28 six-industry-gap closure batch. **Per-commit lightweight reviewer.** Different from `/hermes-pass` (per-batch deep cross-lens pass).

## 0. When to invoke

- **Reminder-triggered** by `scripts/pre-commit.sh` — it PRINTS a `NOTE: blast-radius=<tier> (>=account) — run /code-review (B-pass)` nudge when the staged blast-radius is ≥ `account` (per `docs/blast_radius.yaml`). Git hooks **cannot invoke Claude skills**, so this is a printed reminder; run `/code-review` **manually** when you see it. (Corrected lean-workflow batch 2026-06-01 — the prior "auto-triggered" wording described behaviour the hook never had.)
- **Required** for commits with blast-radius `catastrophic` (gate `check_code_review_pass_exists.dart` blocks without an `accepted` verdict)
- **Manual**: `/review` any time, including pre-push and pre-batch-finalization
- **Skip**: commits with blast-radius `feature` (cost > value)

## 1. The contract

This skill produces a structured findings file at `docs/reviews/<staging-hash-or-sha>-review.md`.

### Output format

```markdown
---
reviewed_at: 2026-05-28T14:32:00+05:30
staged_against: <git-sha-or-stage-hash>
blast_radius: <feature|account|platform|catastrophic>
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 3
verdict: pending  # → accepted | rejected (after founder triage)
---

# Code Review — <staging-hash>

## Finding 1 — P0 — writer_reader_drift
- **file:line:** lib/features/auth/foo.dart:142
- **claim:** `getUserProfile()` reads `profile['email']` but `ProfileWriteService.update` writes `profile['user_email']` per writer/reader drift pattern.
- **verification:** `grep -n "profile\\['email'\\]" lib/` to confirm read sites
- **suggested-fix:** rename read to `profile['user_email']` OR migrate writer
- **status:** pending

## Finding 2 — P2 — secrets_in_tree
- **file:line:** lib/foo.dart:23
- **claim:** Hardcoded API key suffix visible
- **verification:** `git check-ignore -v lib/foo.dart`
- **status:** pending

[…]

## Founder triage notes
<filled in by founder during triage>
```

## 2. Lens set (8 lenses, fast)

Each lens has a focused prompt the dispatched agent runs against the staged diff:

1. **writer_reader_drift** — for every Hive write in the diff, find every cloud reader; for every cloud write, find every Hive reader. Look for field-name or semantic drift. Source: `feedback_writer_reader_field_drift_recurring.md`.
2. **function_exception_swallow** — for every `.functions.invoke(` in the diff, confirm catch + `e.status` + `e.details` is used. Source: `feedback_function_exception_class.md`.
3. **blast_radius_mismatch** — `docs/blast_radius.yaml` says path `X` is tier `T`. Does the diff treat it that way? E.g. catastrophic-tier changes must have rollback documented.
4. **secrets_in_tree** — credential-shaped literals (`sk-`, `rzp_live_`, `AKIA`, `-----BEGIN`) anywhere in the staged diff. Source: `feedback_secrets_pattern_audit_before_first_push.md`.
5. **unawaited_no_error_sink** — every `unawaited(` in the diff has either an inner `.catchError` or sits inside a function with declared error sink. Source: `feedback_observability_silent_drop.md`.
6. **guard_without_its_mirror** — for every guard, existence check, early return, or narrowed match ADDED in the diff, name its **mirror case** and check whether that is guarded too: local vs remote, present vs absent, too-narrow vs too-wide, first-of-N vs the rest. Then ask the sharper question: **is the new code WORSE than what it replaced for the mirror case?** A guard written for the failure the author just hit routinely breaks the symmetric case that the previous code handled fine. Source: `feedback_mistake_guard_without_its_mirror.md`.
   **Do NOT accept the diff's own tests as evidence for this lens** — they are written from the same mental model as the code and will cover the same side. Ask instead: what does *every* test in this file silently assume?
   **Method (added 2026-08-11 after this lens found its third consecutive escape in ONE guard):** do not read the guard — *mutate it and run it*. Two rules that came out of that:
   - **Mutate the way a real regression re-enters**, not the way that is convenient to write. The escapes that mattered were "someone restores the old line in place" and "someone types it slightly differently" — not "delete it" or "move it somewhere absurd", which is what the author had tested.
   - **FOLLOW THE RETURN VALUE TO ITS CALL SITE.** A guard can be perfectly correct and still be defeated by the code that consumes it. Added 2026-08-17 after two independent review rounds each fixed this file's escape-hatch predicate — correctly — and both stopped at the predicate; the B-pass then found that the CALLER reduced the per-statement result to one command-wide boolean, re-opening the exact hole both rounds had just closed. **A predicate that returns `bool` cannot carry a binding it just established** — that shape is the tell, and it is visible without running anything. Ask: what does the caller do with this, and does the answer still mean what the function meant?
   - **If the guard is a SOURCE GREP, assume it is defeatable and try indirection** — a helper function, a variable-built argument, an alias, `eval`. A grep is bounded by what its author could imagine writing, so tightening the pattern never converges. The finding is not "the regex is wrong", it is "this needs a runtime test that observes the behaviour". Check whether one is feasible before accepting a grep: hooks and scripts can usually be run with the expensive dependency stubbed on `PATH`, and an early-abort stub keeps it fast.

7. **missing_input** — for every path, package, or asset the work reads that **no step in this
   same change creates** — a vendored directory, a package's internals, a generated tree, a
   downloaded catalogue, *or a repo file the diff simply assumes is already there* — prove **two
   separate things**: that it EXISTS where the code looks, and that it has the SHAPE the code
   assumes. They fail independently, and the second is the one that survives
   review, because a plausible path reads as a checked one.
   **Method:** `find` / `ls` the literal path, then read one real file out of it and confirm the
   field, extension, or key the code indexes on is actually there. Never reason from the name.
   ⚠ **"Shape" includes the DISTRIBUTION of values, not just the schema.** A guard that hard-fails
   on an input class the author believes is rare is only correct if someone COUNTED. Instance
   2026-08-29, same batch: an asset pipeline raised on SVG path commands `A`/`S`/`T` on the theory
   they were exotic. Against the real catalogue **every one of the 292 files uses them** — `s`
   alone appears 20,917 times — so the tool would have processed zero files and the guard read as
   a safety feature right up until it refused everything. **One command settles it:** extract the
   class from the real corpus and count, before deciding whether to handle it or refuse it. The
   same measurement then tells you whether handling it is cheap; here `S`/`T` turned out to be
   exact arithmetic and only arcs needed real geometry.
   **Source (2026-08-29, plate pipeline, caught in self-review before dispatch):** a build script
   read `<src>/<slug>/frame-N.png` to measure an image's bounds. The vendored catalogue was in the
   repo **nowhere** — a session-temp directory held 94 samples, not the 906-frame source — and
   upstream ships **SVG only**: all 906 frames in its own manifest are `"format": "svg"`, so the
   PNG could not have existed even had the tree been present. Two independent fatal assumptions in
   one line, both invisible to any amount of re-reading, both answered by one `find`.
   ⚠ **Widened 2026-08-29, same batch, third instance:** the lens was written as
   *out_of_repo_dependency* and would have missed the worst case of the three — a plan instructing
   `git add docs/plans/<x>.json` for a file that existed in **no branch, tracked or untracked**,
   and on which six of its ten tasks depended. In-repo is not a proof of existence. The question is
   not *where does this live* but **does anything in this change create it, and if not, did anyone
   look?**

   **The tell:** a path assembled from a variable and a literal (`os.path.join(SRC, slug, "frame-%s.png")`)
   where nothing upstream of it ever listed the directory; or a `git add` of a path the diff never
   writes. Ask what would happen on the *first*
   iteration, and whether anything in the diff would say so out loud.
   **Also check the fallback:** a default like `SRC = sys.argv[1] if len(sys.argv) > 1 else "<some/path>"`
   encodes a guess as a default. If the guess is wrong the tool runs against nothing, and a
   zero-file result must be a hard stop rather than a quiet success — otherwise this lens's failure
   mode is a green run that produced no output.

8. **asserted_fixture_value** — for every test whose expected value is a LITERAL about real data —
   a name, a count, a derived string, a field's contents — compute it from the data and compare.
   Do not read the implementation and reason forward to what it "should" return; that reproduces
   the author's assumption instead of testing it.
   **Method:** run the function over the real input, or query the data file, and diff against the
   literal in the test. One command per assertion.
   **Two instances, 2026-08-29, one batch:**
   `expect(monogramFor("Captain's Chair Leg Raise"), 'CCL')` actually returned `CSC` — stripping
   the apostrophe leaves a bare `s` token that the author never pictured. And a test asserting a
   *numeric* `breathing_cue` was suppressed named an exercise whose cue reads "Inhale down, exhale
   on press" — a real cue, so the assertion was about the wrong row entirely and would have failed.
   **Distinct from lens 6:** that one asks whether the tests share the code's blind spot about
   BEHAVIOUR. This asks whether a specific asserted VALUE is simply factually wrong. A test can be
   perfectly designed and still assert `CCL` about a function that returns `CSC`.
   **The sharper question:** for a suppression or absence test — *would this pass if the feature
   did nothing at all?* Pair it with a positive case, or it asserts nothing.
   **Second sharper question, added 2026-09-05 (OI-162 slice 2):** *does this assertion depend on
   state the test does not CONTROL?* A status code, a count, or a "success" against a SHARED,
   rate-limited, or quota-bearing resource is not a fixture value — it is a reading of live
   mutable state. Three `ai_proxy_test.dart` tests asserted a bare `200` from a live chat as one
   shared QA account; they were green for months because the daily cap was broken, and went red
   the moment a migration repaired it. **The tell is an assertion about an outcome that another
   test, another CI run, or a real user could have changed.** The fix is not to loosen it: accept
   both outcomes and pin the CONTRACT of each, which usually adds an assertion (the refusal path
   here had none). ⚠ Paired lens for the diff side: when a change repairs an enforcement, grep the
   test tree for anything exercising the now-enforced path and asserting success — those tests are
   untouched by the diff and invisible to a targeted run.
   **Sibling shape — the check that matches ITSELF.** A test or gate that NAMES the thing it
   forbids, then scans a tree containing its own source, always finds itself and can never pass.
   Found 2026-08-29 in a plan whose dead-field scan was widened from `lib/` to `lib/`+`test/` — a
   correct widening that made the file scan its own `const _dead = [...]`. **This repo already has
   an answer, so use it rather than inventing one:** `check_no_deferral_euphemism.dart:105-109`
   exempts a line carrying a `deu-quote` marker, chosen so every exemption stays auditable by
   `grep -rn deu-quote` (three live in CLAUDE.md). Prefer a visible marker to a silent path-skip;
   a skip is invisible the day someone adds a second file that should have been covered.

## 3. Dispatch protocol

When invoked, this skill should:

1. Run `git diff --cached --name-only` and `git diff --cached` to assemble the diff.
2. Compute blast-radius via `dart run scripts/blast_radius_from_diff.dart`.
3. Generate the staging hash **exactly the way the gate does**, or the file you write
   will not be the one it looks for:
   ```bash
   git diff --cached -- ':(top)' ':(top,exclude)docs/reviews' | git hash-object --stdin
   ```
   then truncate to 12 chars. Two details are load-bearing and this step documented
   neither:
   - It is git's **sha1 `hash-object`**, not `sha256`.
     `scripts/check_code_review_pass_exists.dart` has always used `git hash-object`, so
     a review named by following the old text could never match. (Found by round-1B
     review of the gate-input-family batch, 2026-07-27.)
   - `docs/reviews/` is **excluded** from the hash (OI-72, same batch). The gate now
     reads the review from the STAGED blob, so the file must be `git add`ed — and
     without the exclusion, staging it would move the hash and rename the very file it
     is meant to satisfy.
4. **Dispatch a FRESH Sonnet subagent** via `Agent({subagent_type: 'general-purpose', model: 'sonnet', ...})` with:
   - The diff inline (or list of changed files to Read)
   - The 6 lens prompts
   - Explicit instruction: "find bugs, do not validate; if you find nothing, list what you specifically checked and why each lens returned clean"
   - Output schema (the markdown above)
5. Subagent returns findings — write to `docs/reviews/<staging-hash>-review.md`, then
   **`git add` it**. An unstaged review no longer satisfies the catastrophic gate: it
   never enters history, so nothing in the commit records that a review happened.
6. Surface the file path in the main conversation; instruct founder to triage.

## 4. Triage workflow

For each finding:
- **accepted** — fix in same batch per `feedback_no_deferrals.md`. Update `status:` field.
- **false_alarm** — annotate `status: false_alarm` with reason. Helps tune the skill via self-evolution.
- **spawn_followup_task** — emit a new task via `TaskCreate`; status becomes `spawned`.

When ALL findings have non-`pending` status, founder sets `verdict: accepted` and the commit can proceed (for catastrophic; for account/platform the verdict is advisory).

## 5. False-positive tracking (self-evolution)

After each invocation, count `false_alarm` findings as a percentage of total. If > 30% on a single pass, that lens is too noisy. Update the lens prompt OR remove the lens entirely. Document the tuning in this SKILL.md under `## Tuning history`.

## 6. Anti-patterns (DO NOT)

- Pass conversation context to the subagent. It must be FRESH — context-blind reviewers catch what the writer missed.
- Default to "no findings found" when uncertain — force structure ("I checked X with grep Y, returned 0 hits").
- Skip the `verification:` field. Every finding must have a one-line verification command.
- Bundle this with `/hermes-pass`. That's a different skill (per-batch, all 53 lenses, Opus, slower).

## 7. Tuning history

> Append after each invocation: invocation date, blast-radius, findings count, false-alarm count, tuning made.

- **2026-09-05** — blast-radius **platform** — branch `oi162-slice2-triggers`, OI-162 slice 2
  (diagnose `e7c4b2`). **8 findings (0 P0, 2 P1, 4 P2, 2 P3); 0 false_alarm.** All 8 fixed
  in-batch. Review: `docs/reviews/004af467034f-review.md`.
  **Tuning — lens 6 (`guard_without_its_mirror`) gains INDIRECTION AS A FIRST-CLASS CASE, not a
  footnote.** The lens already says "if the guard is a SOURCE GREP, assume it is defeatable and
  try indirection". Two findings this pass were exactly that, and both were in guards written
  BY THIS BATCH to be careful:
  (a) a landmine guard matching `channel: '<literal>'` was blind to
  `'channel': _channel` — a `static const` 35 lines up — **live, today, in one of the guard's own
  two positive-control files**. Fixed by resolving same-file consts and, crucially, FAILING
  CLOSED on any channel value it cannot statically resolve. A guard that cannot read a value must
  refuse to pass it, not skip it.
  (b) a per-STATEMENT SQL exemption was defeated three ways in one sitting (data-modifying CTE,
  unstripped `/* */` comment, and a false POSITIVE on legitimate CTE-first ordering).
  **Add to lens 6: when the fix for a defeated grep is "tighten the pattern", that is the signal
  the pattern is the wrong mechanism.** Prefer an enumerated, grep-auditable allowlist (the repo's
  `deu-quote` / `grandfathered:` precedent) or a runtime test. Tightening never converges; a named
  list converges by construction, because a new entry forces a human to look exactly once.
  **Second tuning — a NEW question for lens 7 (`inert check`): "would this assertion pass against
  the code it replaces?"** Not "would it pass if the feature did nothing" (already covered) — the
  sharper, cheaper form for a MIGRATION: restore the old implementation inside a rolled-back
  transaction and re-run. Done here after the first B-pass attempt died mid-run having proposed
  exactly that: **5 of 7 new behavioural assertions passed against the pre-migration triggers.**
  Two were vacuous (NULL compared to NULL) and were fixed; three were legitimate
  behaviour-invariants and are now LABELLED as such in the harness header, so nobody cites a
  contract regression test as evidence that a migration landed.
  ⚠ Process note: both P1s were the author's own **false verification claims** — one asserting a
  four-tag migration header that has only two tags, the other claiming "zero stale citations
  remain" after running a NARROWER grep than the one the same document tells everyone to run.
  Neither is a code defect; both are the `feedback_mistake_unverified_done_claims` class, and a
  context-blind reviewer re-running the PUBLISHED command is what caught them.
  False-alarm rate 0/8 → no lens removed.

- **2026-09-05** — blast-radius **platform** — branch `oi162-delete-account-counter` @
  `303c57af` (OI-162 slice 1: migration 128, the usage_counters ledger, applied to prod).
  **7 findings (0 P0, 1 P1, 3 P2, 3 P3); 0 false_alarm.** 4 fixed, 3 recorded as named
  invariants. Review: `docs/reviews/303c57af-review.md`.
  **The P1 would have failed CI at the merge commit** — the keystone plan-review record for
  the branch simply did not exist yet. Worth noting because the batch had run three plan-review
  rounds and produced two review documents; neither is the artifact
  `check_plan_review_record_exists.dart` reads, which is branch-keyed with `---` frontmatter.
  **Producing review artifacts is not the same as producing THE artifact the gate reads.**
  **Tuning — a TENTH lens, `tool_action_side_effects`.** Finding 6 is the one no lens asked
  for and no amount of reading the diff would surface: `git checkout -- <file>` — the obvious
  way to undo a test mutation — silently converts an applied migration's CRLF to LF via
  `.gitattributes` `eol=lf`, **invalidating the ledger's recorded sha256 while `git status`
  and `git diff` both read CLEAN**, because git compares normalized content and the ledger
  hashes bytes. The reviewer hit it by doing the natural thing, then checked the hash anyway.
  Ask: **does the tool I am using to VERIFY or RESTORE have side effects on the artifact being
  measured?** Sibling of "a green check is only as wide as its input set", pointed at the
  instrument rather than the sample. Now recorded in `supabase/migrations/CLAUDE.md`.
  **Second tuning — lens 8 gains COMPLETENESS, not just correctness.** Finding 7's fix was
  itself defeated: an assertion `contains("RAISE EXCEPTION 'consume_quota:")` stayed GREEN
  when one of the TWO such guards was converted to `RETURN -1`, because the other still
  matched. A `contains` over a pattern that occurs N times cannot detect one of them
  disappearing. Ask of any absent/present assertion: **how many times does this pattern occur,
  and would the test notice if exactly one went away?** Same family as 2026-09-04's
  membership-is-not-association, one step further.
  ⚠ Also: two of the seven were defects in this batch's OWN corrections (line citations
  captured before a later edit to the same file; the test written to close a finding). That
  ratio keeps recurring and is the argument for the B-pass running AFTER remediation, not
  alongside it.
  False-alarm rate 0/7 → no change to lenses 1-9.

- **2026-09-04 (b)** — blast-radius **platform** — branch `oi162-delete-account-counter`,
  PLAN-STAGE (no code). Two context-blind rounds on a migration spec: round 1 **2 BLOCKING**,
  round 2 **0 blocking / 2 major / 2 minor**. **Tuning only — no review file produced**, logged
  here because §5.1 asks for a new bug-class in ANY skill, and both are reusable lenses.
  **Lens 3 (`blast_radius_mismatch`) gains an INPUT-EXISTS check.** The plan claimed
  `platform` and said "computed not estimated" — having run
  `blast_radius_from_diff.dart` against **a path that did not exist on disk**. The classifier
  has a CONTENT rule (`SECURITY DEFINER` in a migration ⇒ catastrophic) that can only fire on
  a file it can READ, so a missing file silently yields the path-glob tier. **A tier computed
  before the file exists is not a computed tier.** Ask of any blast-radius claim: did the
  classifier have CONTENT to read? The cost is not cosmetic — catastrophic requires
  `hermes: accepted`, so the wrong tier drops a mandatory review round.
  **Lens 7 (`missing_input`) gains: a test that needs credentials must LIVE where the
  credentialed job looks.** The plan specified a behavioural test "runs in CI against live
  prod" without naming a directory. CI's `supabase-tests` job — the only one with live
  secrets — runs exactly `test/supabase/` and `test/edge_functions/` (`test.yml:441,465`).
  Placed in `test/contracts/`, where its source-grep sibling correctly belongs, it would have
  landed in the credential-less unit job, hit the repo-standard `hasCredentials` guard, and
  **skipped forever while reading green** — the section's central claim false, with a passing
  suite. **For any test asserting live behaviour, verify the DIRECTORY is in the runner's
  path list before believing the claim.** Sibling of the "green check is only as wide as its
  input set" family, applied to CI job scoping rather than to a grep.
  **A negative result worth keeping:** round 2 was told the DEFINER→INVOKER correction might
  have swapped one false premise for another, and tested it rather than reasoning — reading
  every `createClient` call in the five EFs, and checking `prosecdef` on all three live cap
  triggers. It came back clean and said so. Asking a reviewer to attack the CORRECTION, by
  name, is what round 2 is for.

- **2026-09-04** — blast-radius **platform** — branch `food-text-limit-parity` @ `9b3e688d`
  (diagnose `b8f4c2`: the free food-text cap was 10 in the client and in
  business-rules, 50 in the Postgres trigger that enforces it). **8 findings
  (0 P0, 2 P1, 2 P2, 4 P3); 1 false_alarm (12.5%).** 7 fixed in-batch, 1
  informational. Review: `docs/reviews/9b3e688d-review.md`.
  **All four mutation claims and the live-prod state reproduced EXACTLY — and the
  pass still found eight things, every one the same shape.** The fix had been
  applied where the cap is ENFORCED and nowhere it is REPORTED. `ai-proxy`
  rendered its 429 body from an inline `isProUser ? 200 : 50`, so the one message
  a capped caller actually reads kept saying "50/day" — misinforming precisely
  the direct-API population the cap exists to constrain.
  **Tuning — lens 1 (`writer_reader_drift`) gains a DISPLAY-READER question, and it
  is not the same as the data-reader question the lens already asks.** When a diff
  changes a VALUE (a cap, a threshold, a price, a limit), enumerate everywhere that
  value is *reported* — error bodies, user-facing copy, log lines, docs — not only
  where it is *enforced*. A display reader has no functional coupling to the writer,
  so nothing breaks when it drifts; it just starts lying, silently, to the only
  audience that asked.
  **Second tuning, and it is new to this history: AUTO-LOADED CONTEXT FILES ARE A
  PROPAGATION TARGET.** Two nested `CLAUDE.md` files (`supabase/functions/`,
  `lib/features/nutrition/`) still documented 50/day. Those load automatically into
  every future session working in those subtrees, so a stale number there is fed
  back to the next agent as authoritative context and will be reasoned from. The
  reviewer noticed because they were injected into its OWN context mid-review. Add
  to lens 5: when a diff changes a documented constant, `grep` the nested
  `CLAUDE.md` set specifically — they are the highest-leverage stale docs in the
  repo and the easiest to forget, because nobody opens them deliberately.
  **Third — the author's grep was the bug, again.** The pre-commit check was
  `grep -rn "50/day" test/ scripts/` on a repo-wide constant: zero hits, read as
  proof of absence. Fourth instance in one session of
  `feedback_green_check_input_set_width`, and it happened *inside the fix for a bug
  whose cause was exactly that*. Worth stating in this history because it is the
  argument for the B-pass existing at all — the author cannot audit their own input
  set, since the too-narrow scope feels complete from inside it.
  ⚠ **Also, a NEGATIVE claim the reviewer was asked to check and did:** the commit
  asserted that removing comment-stripping from `latestMigrationDefining` reddens
  ZERO tests (recorded as defensive-only rather than claimed as proven). The
  reviewer reproduced the zero. **Asking a reviewer to verify a negative result is
  cheap and worth doing** — an unearned mutation-proof is invisible by construction,
  and "0 red" is the easiest number to omit rather than report.
  False-alarm rate 1/8 → no change to lenses 2-4, 6-9.
  **Addendum, same day, from the full-suite pre-push run:** lens 6 should ask, of any diff
  that adds a FILE-LEVEL annotation or default, whether a PER-ITEM override survives it. The
  push went red on `batch_close_hook_e2e_test.dart` — a file `0a99a0b7` had already fixed for
  full-suite contention by adding `@Timeout(Duration(minutes: 6))`. One test in it carried its
  own `timeout: const Timeout(Duration(seconds: 60))`, and **a per-test `timeout:` takes
  precedence over the file annotation**, so the fix never reached the one test that needed it.
  Green targeted (7/7) and green across all of `test/scripts/` (555/555); red only in the
  ~5300-test suite. Generalises past timeouts: a file-level default plus a surviving local
  override is a guard whose mirror is the override, and the override is invisible from the
  diff that adds the default.

- **2026-09-03** — blast-radius **platform** — branch `techdebt-audit-sep02`, Slice A of the
  2026-09-02 tech-debt audit (diagnoses `e4d1b7`, `f2b9d4`). **3 findings (0 P0, 1 P1, 1 P2,
  1 P3); 0 false_alarm.** 1 fixed in-batch, 1 answered in the plan-review record, 1 tracked as
  OI-161. Review: `docs/reviews/db5584050b6b-review.md`.
  **Tuning — lens 10 (`stale_or_wrong_citation`) gains a question about the GATE, not the
  citation.** The P1 was a `writers:` entry, in both a SoT registry concept and its diagnose-doc,
  naming `migrations/052:82-85` — a **comment block** in a file containing no `INSERT` at all. The
  real writers were two Edge Functions one grep away. What makes it worth recording is *why it
  survived*: `check_sot_registry_parity.dart` verifies a `method:` field ONLY when it parses as a
  bare identifier or dotted path. `"subscriptions table — payment path inserts rows"` is prose, so
  the gate **silently skipped the symbol check** and verified only file-exists + line-in-bounds —
  both trivially true of a comment. So the citation was "gated" in the sense that a gate ran over
  it and said PASS, and unchecked in every sense that matters.
  **Add to lens 10: when a citation lives in a field a gate reads, check whether the gate's parser
  could actually READ THIS VALUE — prose in a structured field converts a checked claim into an
  unchecked one, and the PASS is indistinguishable either way.** Generalises past this gate: any
  validator with a "skip what I cannot parse" branch has the same shape, and free-text is the
  easiest thing in the world to write into a field meant for a symbol. Sibling of OI-100
  (`prior_art_checked:` must reference a verified artifact, not free text) and of INFRA-11 in this
  same audit (Gate 33's allowlist reasons are unparsed prose).
  **Second, a NEGATIVE result worth keeping, per this history's own convention:** the reviewer
  mutated **to the real pre-fix `HEAD` content** of both files rather than to a convenient
  synthetic edit, and reported 7-of-9 assertions reddening with the 2 green ones correctly pinning
  invariants the diff never touched. That is the mutate-the-way-a-real-regression-re-enters rule
  applied without being asked, and it is the strongest form of the check — it also independently
  reproduced the author's own three isolated mutation runs.
  ⚠ Process note: the author's `blast_radius: account` claim in both diagnose-docs was wrong — the
  two EF files ALONE classify **platform**. Caught not by review but by the pre-commit loop's own
  printed tier line. **A tier you estimated and a tier the classifier computed are different
  claims**, and only the second one gates the review requirement.
  False-alarm rate 0/3 → no change to lenses 1-9.

- **2026-09-02 (b)** — blast-radius **platform** — branch `profile-stale-restore`
  (diagnose b3c9d4, Profile tab serving a pre-restore profile map). **8 findings
  (0 P0, 1 P1, 3 P2, 4 P3); 0 false_alarm — 7 fixed in-batch, 1 DECLINED with
  evidence.** Review: `docs/reviews/d8f51f77c896-review.md` (that file also
  carries the two context-blind plan-review rounds, 7 + 3 findings, same
  0 false alarms).
  **The result worth recording: the P1 was a regression the FIX ITSELF
  introduced, and it was invisible from reading the diff.** The batch moved a
  `restoreCompletedTick` listener into the shared tab mixin so all 4 tabs
  refresh after a background restore. Correct in isolation — but Nutrition's
  `invalidateOnRetry` includes `aiBreakdownProvider`, and
  `ai_mode_body.dart:41` reads that provider's non-null→null transition as
  "the user committed or cancelled" and pops the Log Food sheet. So a restore
  completing while someone reviewed an AI food analysis would have closed the
  sheet and discarded it, silently. The diff's own diagnose-doc asserted the
  opposite in writing ("no provider is being invalidated that was not already
  designed to be").
  **Tuning made — lens 6 gains a TRIGGER-PROVENANCE question.** Its existing
  method asks for the mirror case, the ordering, and the caller. Add: **when a
  change causes an existing call to fire from a NEW trigger, re-audit that
  call's whole target set against the new trigger's provenance.** "Safe when a
  user taps retry" and "safe when a background event fires" are different
  claims, and a set assembled under the first is not validated for the second.
  The tell is a diff that changes WHO calls something rather than WHAT it does
  — the call site looks untouched, so it reads as out of scope.
  **Second tuning — lens 3 (stale_or_wrong_citation) earns a mechanical note.**
  Two of the three P2s were citation errors, and one was inherited: the doc
  copied `sync_profile.dart:648` forward from the PRIOR diagnose-doc for the
  same concept without re-deriving it (the real line is 764). A citation
  copied from another document is not a verified citation. Cheap rule: any
  file:line lifted from an existing doc gets re-grepped, because the file it
  points into has moved since that doc was written — by definition, or the doc
  would not be old enough to copy from.
  ⚠ Process note worth keeping: the DECLINED finding (remove Home's now-
  "redundant" Train-provider invalidation) was refuted by checking
  `app_router.dart:359` — `StatefulShellRoute.indexedStack` with no `preload`,
  so an unvisited Train tab has no State and no listener, making those lines
  load-bearing. A reviewer's "this is now redundant" is a hypothesis about
  runtime lifetime, and lifetime is exactly what static reading cannot see.
  False-alarm rate 0/8 → no change to lenses 1-5, 7, 8.

- **2026-09-02** — blast-radius **platform** — branch `readiness-flip` @ `9e4c5681`
  (OI-53 flags 1+2: readiness + triggered deload flipped live, Health Connect
  sleep). **5 findings (0 P0, 1 P1, 2 P2, 2 P3); 0 false_alarm.** All fixed
  in-batch. Review: `docs/reviews/9e4c5681-review.md`.
  **Tuning — lens 6 gains a PERMISSION-SCOPE question, and lens 7 gains the
  layer BELOW the API.** Both come from the same batch getting Android wrong
  three times in three rounds, each time in a way NO `flutter test` could see.
  1. **Lens 7 (`missing_input`) must descend to the PLATFORM MANIFEST, not stop
     at the API.** Plan review round 1 caught that `SLEEP_ASLEEP` was the wrong
     data type (the plugin returns a whole session only for `SLEEP_SESSION`;
     every other sleep type matches individual STAGES, so a stageless or
     granular-tracker session yields zero points). Round 2 then found the layer
     underneath: `android.permission.health.READ_SLEEP` was declared in **no
     manifest**, so the permission could never be granted and the feature was a
     permanent no-op *regardless* of the data type. **A correct API call against
     an undeclared permission is indistinguishable from a correct feature until
     it runs on a device.** Ask: for every new platform capability, is it
     declared where the OS reads declarations — and did anyone check, or did the
     enum's existence stand in for it?
  2. **Lens 6 gains: when a user action requests permission X, does its code path
     also request Y?** The B-pass P1: the sheet's "sync your sleep" nudge called
     the shared `syncToHive()`, which falls through to the steps/weight
     permission request — so a user tapping about SLEEP would get a
     STEPS+WEIGHT consent dialog and unrequested step/weight writes. The file's
     own comment promised "sleep must fail soft, both ways" and only one
     direction was guarded. **A shared entry point inherits the union of every
     caller's side effects; a narrow user action must not reach a wide one.**
  3. **A NEGATIVE result worth recording, per this history's own convention:**
     the reviewer independently re-ran Mutation B (kill-switch polarity flip) and
     measured 22 failures, matching the commit's claim exactly — then reverted and
     verified the tree clean before reporting. Confirming a mutation count costs
     one run and is the only thing that makes the claim mean anything.
  ⚠ Also, third instance in this batch of the stale-self-citation class: a
  comment the batch ADDED cited `volume_titration.dart:56` while its own
  insertion had shifted the guard to `:60`. **Capture line citations LAST.**
  False-alarm rate 0/5 → no change to lenses 1-5, 8, 9.

- **2026-08-30 (c)** — blast-radius **platform** — branch `oi150-phase-merge`
  (OI-150 progress + profile write durability). **4 findings (0 P0, 2 P1, 1 P2,
  1 P3); 0 false_alarm — all four real, all fixed in-batch.** Review:
  `docs/reviews/375e3a351e7b-review.md`.
  **The result worth recording: BOTH P1s were defects the batch's own earlier
  remediation created**, in a batch that had already survived three review
  rounds on a withdrawn design, one on the plan, and two on the implementation.
  P1-1: a fix for a missed coupling path (the "key-absent seed") was inserted
  ABOVE the line that reads the older kill-switch, so rolling
  `disable_progress_restore_monotonic_merge` — documented as restoring
  "verbatim pre-OI-83" behaviour — left the new coupling still firing. P1-2: an
  N10-class fix ("a drain must not delete a marker for a push that never
  happened") was applied to two call frames and not to the third, where three
  early `return`s let a drain report `Result.ok` and delete the marker.
  **Tuning made — lens 6 gains an ORDERING question, which is new.** Its
  existing method says mutate-and-run and follow-the-return-value-to-its-caller.
  Add: **when a fix INSERTS a statement near an existing guard, check where it
  lands relative to that guard's own predicate.** P1-1 was not a wrong
  condition — the condition was right and simply ran three lines too early, and
  no amount of reading the guard reveals that. The reviewer found it by setting
  the older switch and running, which is the only thing that does. Sibling
  formulation: *a guard added ABOVE the switch that is supposed to disable it is
  not disabled by that switch.*
  **Second tuning — a NEGATIVE result on lens 8 worth keeping.** The reviewer
  re-derived this batch's "~2.1% of birthdays, 232 of 10,958" prose claim by
  brute-force sweeping every DOB 1980-2009 and got 232/10,958 = 2.117% — an
  exact match. Recording the confirmation matters as much as recording a
  refutation: the lens's value is that the number gets CHECKED, and a history
  that only logs catches would imply the checks are free.
  ⚠ Process note: the reviewer ran two probe tests and one mutation against the
  live tree, then reverted all three and verified clean against the staged index
  before reporting. That disclosure is the behaviour to keep.
  False-alarm rate 0/4 → no change to lenses 1-5, 7, 8.

- **2026-08-30 (b)** — blast-radius **platform** — branch `process-hardening` (the
  batch that closes defect classes found in `profile-phase-fixes`). **3 findings
  (1 P0, 1 P1, 1 P2); 0 false_alarm — all three real, all fixed in-batch.**
  Review: `docs/reviews/2ef6e60d897d-review.md`.
  **The result worth recording: two of the three findings were the batch
  committing the exact classes it was written to close.** A new `safe_merge.sh`
  precheck — built because a silent no-op had cost a merge unwind — read the
  WORKING TREE on `main` for a record that lives on the FEATURE BRANCH, so it
  matched nothing on every real invocation: a no-op guard against no-op guards.
  And a new `case "$0"` execution guard, built because `sh _dart_bin.sh` had
  silently done nothing, was forward-slash-only, so `sh 'scripts\_dart_bin.sh'`
  — the dominant path spelling in this Windows environment — sailed past it and
  did silently nothing. Neither was visible from reading; both needed the
  reviewer to RUN the thing against reality.
  **Tuning made — lens 8 (`asserted_fixture_value`) gains its sharpest form
  yet, and it is a level above "is this literal right".** The P0's three tests
  were green, and green *because* their fixture committed the record onto
  `main`, a shape the real workflow never produces. So the question to add is
  not only *would this pass if the feature did nothing* but **does the fixture
  reproduce a state the real workflow actually produces?** Check the fixture
  against real history (`git cat-file -e <merge>^1:<path>` settled it here in
  one command), not against the code under test. A mutation run on top of a
  fictional fixture proves nothing — which is precisely why the P0 survived a
  mutation-proof claim made in good faith hours earlier.
  ⚠ Also: the reviewer accidentally landed a real commit on the worktree
  mid-review (a silently-failed `cd`), caught and reset it, and **said so**.
  That disclosure is the behaviour to keep; the review was verified against
  HEAD + staged-hash afterward and was clean.
  **Round-2 addendum (same batch, verdict `converged`).** Two more lessons,
  both about the REVIEWER's own output rather than the code. First, the
  cheapest real findings round 2 produced were **stale numeric claims in prose
  written earlier in the same batch** — a §7 row said a test group had 4 tests
  when it had 5, and "reddens exactly one test" when it reddens two, because a
  test was added during remediation and the sentence was never re-derived. Add
  to lens 8's habit: **re-run any count a diff ASSERTS, including counts the
  same diff introduced hours earlier** — the batch's own prose is the highest-
  yield place to look, not the lowest. Second, three "declared defense, zero
  test" gaps were found only by reintroducing each bug and watching the suite
  stay green; reading the code would never have surfaced them, because the code
  was correct and the comment describing it was accurate. **A correct defense
  with no test is invisible to review-by-reading, and that is the shape to hunt
  once the obvious defects are gone.**

- **2026-08-30** — blast-radius **platform** — branch `profile-phase-fixes` (11 files, a
  full-name restore-race fix + a phase-2 tripwire + a DEPLOYMENT-label fix). **6 findings
  (0 P0, 2 P1, 1 P2, 3 P3 incl. 1 informational); 0 false_alarm — all 6 were real and all
  fixed/resolved in-batch.** Review: `docs/reviews/56e7d3cf49d0-review.md`. Dispatched as a
  fresh context-blind subagent with live Supabase MCP access; it ran the actual test suite,
  gates, and live SQL rather than reasoning from the diff alone.
  **No new lens — the existing 8 caught everything cleanly, including two genuine code gaps
  (guard_without_its_mirror ×2: a retry fix unreachable on the primary C3 restore path; a
  hard-refresh call with no catch of its own, unlike the precedent it claimed to mirror) and
  a factual error in the AUTHOR's own prior live-data investigation (asserted_fixture_value:
  a diagnose-doc misattributed a telemetry account to the wrong email — the reviewer's live
  Postgres re-query caught it, and it was independently re-verified before accepting the
  correction).**
  **One process lesson worth recording: a reviewing subagent can misdiagnose its OWN
  tooling.** Given a `git hash-object --stdin` value (correct — that call deliberately never
  writes the blob), the subagent ran `git cat-file -t <hash>`, saw it fail, concluded the
  hash was wrong, and silently substituted the HEAD commit sha into its own report instead of
  asking or flagging the discrepancy. The substitution was caught by recomputing the hash
  independently before trusting it — the same "verify a subagent's own claims, don't just
  verify the claims about the code" discipline this skill's dispatch protocol already assumes
  for the DIFF, extended here to the reviewer's incidental tooling claims too.
  **Tuning made:** none to the 8 lenses. Confirms the lens set generalizes past its two prior
  outings without needing a 9th.

- **2026-08-30** — blast-radius **platform** — branch `board-budget` @ `6ad3920e`
  (board token reclaim + a new context-artifact budget gate). **5 findings (1 P0, 2 P1,
  2 P2); 0 false_alarm.** All fixed in-batch. Review: `docs/reviews/board-budget-bpass.md`.
  **This pass ran THIRD, after two context-blind plan-review rounds, and its best finding is
  one both of them read past.** Rounds 1 and 2 each opened
  `check_context_artifact_budget.dart` and neither noticed `--record` executed BEFORE the
  report — so re-baselining blessed whatever was on disk with no comparison and no trace,
  and the FAIL path printed `--record` as its own escape hatch. The B-pass found it by
  opening the gate whose name the docstring invokes (`check_apk_size_within_bounds.dart`)
  and diffing the two: Gate 13's `exit(1)` sits ABOVE its record step, making that branch
  unreachable on a breach, and this gate had inverted exactly that ordering.
  **Tuning — a NINTH lens, `modelled_on_is_a_checkable_claim`:** when a diff says it
  mirrors, follows, or is modelled on an existing component, OPEN THAT COMPONENT AND DIFF
  THE TWO. "Same shape as X" is an assertion with a truth value; it is cheap to test and
  easy to skip, because the phrase reads as provenance and reviewers grant it. Here the
  docstring was sincere and the code contradicted it on the single ordering that mattered.
  Generalises past code — it applies to any claim of the form "this follows the existing
  pattern".
  **Second tuning, for lens 6 — ask for the mirror MESSAGE, not only the mirror CASE.**
  Round 1 made the bands two-sided; round 2 found the report still hardcoding the growth
  thresholds and the verb "grew", so the very fixture round 1 built printed *"grew past the
  50% hard band"* for a file that shrank 100%. A classifier fixed without its report is
  still wrong where the operator reads it. Lens 6 asks whether the mirror case is guarded;
  it should also ask whether everything that DESCRIBES the classification still describes
  it correctly.
  **Third — a number-hygiene rule the whole batch argues for.** 4 of the 10 findings across
  the three rounds were stale numeric or line claims that SURVIVED a deliberate correction:
  a citation fixed twice and still wrong (captured by grep, then invalidated by a later edit
  to the same file in the same commit), and a retracted figure still live in a second
  document nobody revisited. **After correcting any number, grep the repo for the OLD value;
  and capture line citations LAST, or re-derive them immediately before commit.**
  False-alarm rate 0/5.

- **2026-08-29** — blast-radius **platform** — branch `exercise-plates` (25 commits, the
  exercise plate feature). **3 findings (0 P0, 1 P1, 1 P2, 1 P3); 0 false_alarm, but ONE
  finding was half-wrong in a way that mattered.** All fixed in-batch. Review:
  `docs/reviews/exercise-plates-bpass.md`. Dispatched as a fresh context-blind subagent,
  unlike the 2026-08-28 inline pass.
  **The lesson is about a REJECTED causal claim, and it is new to this history.** Finding 1
  was right that platform tier's `requires: feature_flag` was unmet — and wrong about why
  the branch is platform, asserting it was *"solely because it edits `CLAUDE.md`"* and
  recommending the doc rows be split out to drop the tier. Classifying each path ALONE
  refuted it in one command: `pubspec.yaml` → platform (`blast_radius.yaml:324`) and
  `CLAUDE.md` → platform (`:68`) are independently sufficient, so the proposed split would
  have produced a second commit and the same unmet requirement. **Generalisable: when a
  finding explains WHY a classifier returned a value, re-run the classifier per-path
  rather than reading the registry — a tier is a max over globs, and "which edit caused
  it" is not a question the registry answers.** Had the recommendation been taken on
  trust, the batch would have shipped with the real gap intact and a spurious commit split
  on top.
  **What the pass was worth, and it is the arc math.** Lens 6 was pointed at the SVG crop
  with an explicit "is the bbox ever too SMALL?" — a defect no test in the batch could see,
  since they check counts, viewBox equality and tintability, never ink coverage. The
  reviewer re-implemented the arc geometry with an ANALYTIC extrema solver, ran it over all
  292 shipped assets, found 7 whose ink pokes outside the canvas, then re-ran the
  pipeline's own sampler at 24/240/2400/24000 samples and got byte-identical results —
  proving the difference was not sampling error but ink the source `viewBox` had already
  clipped. **Asking a lens for a specific falsifiable property ("too small", not "correct")
  is what made an independent re-derivation possible.**
  **Second, smaller: an evidence claim wider than the check behind it.** Finding 2 was not
  really "a generator still emits dead fields" — it was that the closure ledger claimed the
  fields were *"pinned absent across lib/ and test/"* when the pinning test scans `.dart`
  files only and structurally could not see the `.py` generator. The overstatement is the
  dangerous half; a claim wider than its check reads as coverage. Same family as this
  repo's phantom-citation rule.
  **Tuning made:** none to lenses 1-8. Add to lens 3's habit: a blast-radius finding must
  classify per-path before asserting which edit drives the tier.

- **2026-08-29 (d)** — branch `exercise-plates`, during round 3, from running the plan against
  real data for the first time. **Sharpened lens 7** rather than adding a ninth: a guard that
  hard-fails on an input class assumed rare is only correct if someone counted, and "shape" in
  that lens has to mean the value DISTRIBUTION as well as the schema. The pipeline refused SVG
  `A`/`S`/`T`; all 292 shipping files use them and `s` appears 20,917 times, so it would have
  produced nothing while looking like a careful tool. Neither of the two context-blind rounds
  could have caught it — the upstream catalogue had never been cloned, which is lens 7's own
  territory and the reason it now says to fetch the corpus and measure.

- **2026-08-29 (c)** — branch `exercise-plates`, after review round 2 (5 BLOCKER / 11 MAJOR /
  17 MINOR, verdict `not converged`; **four of five blockers sat inside round 1's own fixes**).
  **No new lens.** The one genuinely new shape — a check that names what it forbids and then scans
  itself — is a class this repo had ALREADY solved, with the `deu-quote` exemption marker
  (`check_no_deferral_euphemism.dart:105-109`, three live sites in CLAUDE.md). Recorded as a
  sibling note under lens 8 pointing at that convention instead of minting a parallel one. Logged
  here because "considered and declined, for this reason" is the answer §5.1 asks for, and a lens
  set that only ever grows stops being run.

- **2026-08-29 (b)** — branch `exercise-plates`, after review round 1 of the implementation plan
  (7 BLOCKER / 15 MAJOR / 16 MINOR; all 7 blockers verified real against the files).
  **Widened lens 7 `out_of_repo_dependency` -> `missing_input`** on its third instance in one
  batch — the worst case was an IN-repo path (`docs/plans/<x>.json`) that existed in no branch and
  that six of ten tasks consumed, which the out-of-repo framing would have missed entirely.
  **Added lens 8 `asserted_fixture_value`** after two test expectations in the same plan asserted
  literals that the real data contradicts (`CCL` where the function returns `CSC`; a numeric-cue
  suppression test naming a row whose cue is prose). Both were written by reasoning forward from
  the implementation rather than computing from the data.

- **2026-08-29 (a)** — blast-radius **platform** — branch `exercise-plates` (plan-stage, no code yet).
  **Tuning only; no invocation.** Added lens 7 `out_of_repo_dependency` after a plan self-review
  found a build script reading `frame-N.png` from a vendored catalogue that (a) was not in the repo
  at all and (b) ships SVG exclusively — 906 of 906 frames `"format": "svg"`. Neither failure is
  visible by reading the code; both fall out of one `find`. Logged here rather than waiting for the
  B-pass because the existing six lenses all look INSIDE the diff, and this class is the one that
  lives outside it — no lens would have asked the question.

- **2026-08-28** — blast-radius **platform** — branch `oi89-bodyweight-floor` @ `1f817e2f` (11 commits, OI-89 equipment capability floor). **3 findings (0 P0, 2 P1, 1 P2); 0 false_alarm.** 2 fixed in-batch, 1 recorded as residual. Review: `docs/reviews/oi89-bodyweight-floor-bpass.md`.
  ⚠ **Method deviation, and it must be read alongside the findings:** the pass was run
  INLINE BY THE AUTHOR, not by a fresh context-blind subagent, because this session
  carried a standing instruction not to call the Agent tool unasked. That is weaker
  by construction and the record says so — `verdict: accepted` feeds the merge gate,
  and the gate cannot tell the two apart.
  **Both P1s were lens-6-family and both were self-inflicted hours earlier**, which is
  the useful part: an author CAN catch their own guard-mirror defects if the lens is
  run as a checklist against the diff rather than as a memory of intent.
  **P1-1 is the sharpest instance of "the comment claims the opposite of the code" yet
  recorded.** The commit message asserted *"the strong entries stay FIRST … reordering
  would hand them a floor move over a real one"*, and the diff reordered two pools the
  other way — promoting `Dip (Parallel Bars)` to the head of `elbow_extension`. Because
  attempt-5 does not check `equipment_tier` and capability is null ABOVE bodyweight,
  position in that pool IS the prescription for gym-tier users, so a `home_dumbbells`
  user would have been handed a dip station where the old order gave a Diamond Push Up.
  **Generalisable: when a diff's own comment states an invariant, CHECK THE DIFF AGAINST
  IT rather than reading the comment as evidence.** A comment asserting "I did not
  reorder" is the cheapest possible place for a reorder to hide.
  **P1-2 extends the seventh lens (`same_class_in_the_fix`) with a scope question.** The
  batch's independent evidence that `equipment_needed` is trustworthy is a prose-scanning
  gate — which scanned BODYWEIGHT-TIER ROWS ONLY. That is exactly the wrong scope for the
  defect it must catch: a row over-tagged in `equipment_needed` rather than in
  `equipment_tier` is not bodyweight-tier to begin with, so the narrow scan could never
  reach one. Widening to all tiers surfaced 18 findings, 17 comparison prose and one real
  (E260 Incline Dumbbell Press: first cue *"Set bench to 30-45 degree incline"*, row
  claimed dumbbells only, tier `home_dumbbells` grants no bench). **Ask of any gate the
  batch relies on: is its INPUT SET the set where the defect can live?** The batch had
  already hit this hole once — two rows surfaced from a tier re-derive rather than from
  the gate — and treated it as two rows instead of as a scope bug.
  **Tuning made:** none to lenses 1-7. Add to lens 3's habit instead — when a batch adds
  or leans on a gate, verify the gate's scope covers the defect class, not just the
  instance that motivated it. False-alarm rate 0/3.

- **2026-08-26** — blast-radius **platform** — branch `oi98-notification-prefs` @ `885ebd47f4c0`.
  **6 findings (1 P0, 2 P1, 2 P2, 1 P3); 0 false_alarm.** All fixed in-batch.
  Review: `docs/reviews/885ebd47f4c0-review.md`.
  **The P0 was the batch's own bug class, surviving into its own fix.** OI-98 was
  "authoritative data living in a wholesale-replaced document". The fix moved it to a
  dedicated jsonb column — and a jsonb COLUMN is also replaced wholesale by an upsert, so
  a device holding a sparse map deleted every key it had not personally seen. Per-key merge
  had been written on the RESTORE side and wholesale replace left on the WRITE side.
  **Tuning made — a seventh lens, `same_class_in_the_fix`:** when the batch under review
  fixes a named bug CLASS, ask explicitly whether the replacement re-creates that class in
  its new shape, and check the mirror side of any per-key/merge/guard semantics the fix
  introduces. The existing `guard_without_its_mirror` lens found it, but only because the
  reviewer generalised on its own; the prompt did not ask. Note also that the same lens
  fired on the fix's OWN new guard (Finding 3 — the owner re-check protected the new call
  and not its sibling two lines above), which is evidence the lens is worth its cost on any
  batch that adds a guard.
  **Second tuning — assert the WRITE payload, not just the read path.** Finding 6 named why
  the P0 survived a suite that was already mutation-proven: every test exercised restore and
  emission, and none asserted the SHAPE of what the client sends. When a batch changes a
  cloud write, require a pure extracted payload builder and a test over it; a round-trip
  test that never inspects the outgoing payload is blind in exactly the direction that
  matters.

- **2026-08-25** — blast-radius **platform** — branch `discipline-enforcement` @ `fbbea768`.
  **4 findings (2 P0, 2 P1); 0 false_alarm.** All fixed in-batch.
  Review: `docs/reviews/discipline-enforcement-bpass.md`.
  **This pass reviewed the batch that BUILT this gate, and found the gate would have
  silently passed its own first real use.** `hasTuningEntryFor` matched any bullet carrying
  the review's date — and `SKILL.md` already held a 2026-08-25 entry for an unrelated batch,
  so THIS review would have been reported satisfied by somebody else's entry. Date is not
  identity, and two reviews on one calendar date is ordinary here, not exotic. Fixed with a
  block scan that requires the dated entry to NAME the review.
  **The second P0 is the same shape one layer out:** the Stop hook measured its batch with
  `origin/main..HEAD` while local `main` sat 7 commits ahead of origin — so three derived
  rows reported green on three unrelated batches' evidence (another batch's review file
  satisfied the skill-tuning row; another batch's `fix(...)` subjects set the feedback row;
  the retrospective check anchored to an unrelated commit's date). `new-worktree.sh:65-91`
  had solved that exact range-selection problem already and the fix was not carried across.
  **Generalisable, and it is why this pass earned its keep after TWO ×2 rounds found nothing
  of the kind:** when a batch builds a checker, point the checker at ITSELF and at the
  repo's real state, not at a fixture. Both P0s were invisible to 52 passing tests and to
  two context-blind rounds, and both fell out immediately from running the thing against the
  live tree. A fixture encodes the author's model of the world; the working tree does not.
  ⚠ Process: the reviewer's own failed `cd` left it in the target worktree and an
  `ALLOW_RAW_GIT=1 git commit` landed a stray commit there. Self-caught and fully reverted
  (author verified independently). Two lessons recorded in the review: chain `cd <dir> && …`,
  and a review subagent should not hold a raw-git escape hatch at all.
  False-alarm rate 0/4 → no tuning to lenses 1-6.

- **2026-08-25** — blast-radius **account** (self-declared platform) — branch `oi60-client-blockers` @ `2e9503eb` (OI-60 FOB-7a/7b). **4 findings (0 P0, 1 P1, 3 P2); 0 false_alarm.** All fixed in-batch. Review: `docs/reviews/2e9503eb-review.md`.
  **NEW OBSERVATION, and it is the reason this entry matters: all four findings were defects in the EVIDENCE, none in the CODE.** Every prior entry in this history records the pass catching a code or guard defect. Here the ×2 plan review had already caught the design defects — including a P0 it prevented — and the code shipped correct. What the B-pass found was that the ARTIFACTS DESCRIBING the code were false:
  (1) **P1 — a past-tense claim for work never done.** The plan-review record AND the closure YAML both stated the three wrong OI-127 board citations had been "corrected on the board in this batch". They were corrected in the plan document only; `git log <base>..HEAD -- docs/audit/open_issues.md` returned ZERO commits and the board still showed all three verbatim. The batch existing partly to stop the board misdirecting the next session was about to merge leaving it misdirecting, while asserting the opposite.
  (2) **P2 — `docs/sot_registry.yaml` described superseded behaviour** in two entries, one of which (`still clamped`) the same commit's own new code comment directly contradicted.
  (3) **P2 — the diagnose `bug_id` COLLIDED** with an unrelated doc, making `closes-diagnose:` ambiguous forever (git history cannot be rewritten to repair it). No detector exists: `validate_diagnose_doc.dart` takes ONE path and never scans the corpus, though the OI-number version of this identical bug shipped six times and earned its own gate. Filed OI-140.
  (4) **P2 — a stale mutation count** (claimed 4-of-7 red, actual 5-of-7). Measured when the file had SIX tests, never re-measured after a seventh was added, then copied into two documents.
  **Generalisable, and worth adding to how this skill is USED rather than to a lens:** the ×2 plan review reads the DESIGN; the B-pass reads the ARTIFACTS. Neither pass would have found the other's findings, and a batch can be entirely correct while shipping documents that lie about it. When the code is clean, do not conclude the pass found nothing — turn the lenses on the commit's own claims: does every past-tense assertion have a diff behind it, does every cited count come from a run against the file as it now stands, and is every id unique in its space.
  **Second, mechanical lesson (feeds the new Gate `check_skill_tuning_history.dart` added the same day):** this very entry was NOT written until founder asked whether discipline had been followed. §5.1 mandates it and nothing enforced it, so the skill's own self-evolution loop was the thing decaying. It is now gated: a commit adding `docs/reviews/<sha>-review.md` must also add a same-dated entry here.
  False-alarm rate 0/4 → no tuning to lenses 1-6.

- **2026-08-25** — blast-radius **catastrophic** ×2 — branch `launch-blockers-1` then its split `launch-blockers-1a`. **Pass 1: 3 findings (0 P0, 1 P1, 2 P2). Pass 2 (post-split): 6 findings (0 P0, 1 P1, 2 P3+). 0 false_alarm across both.** Reviews: `docs/reviews/eb37932a4218-review.md`, `docs/reviews/a51a2ba9de14-review.md`.
  **The headline is what happened BETWEEN the two passes, and it is an argument for Hermes rather than for this skill.** Pass 1 was clean and its findings were real — the sharpest being a restore leg wired into one of four entry points, certified by a test asserting a COUNT that two branches of one function satisfied. But a five-lens Hermes pass on the post-B-pass code then found **two P0s that broke BOTH of the batch's headline fixes**: a bodyweight guard keyed on `equipment_tier`, a field `docs/sot_registry.yaml` itself declares *"over-tags tolerated"* (so Chin Up — one of the three exercises the bug reported — still shipped); and a restore leg reading the newest snapshot row that the device's own `splash_screen:189` push overwrites first, confirmed against live prod (126 rows, 14 with prefs, all all-enabled). Per §4.12.1 the unit was SPLIT.
  **Lens-6 lesson, new sub-shape — THE ORACLE COPIED THE CODE'S BLIND SPOT.** The B-pass ran lens 6 on the bodyweight guard, mutated both sites, watched 3 and 2 tests redden, and passed it. That was all true and all beside the point: the test's oracle read the same `equipment_tier` field as the code, so the mutation proved the guard guards what the test measures, not what the user suffers. **Mutating a guard cannot detect an oracle derived from the same expression as the guard.** Lens 6 should now also ask: *what field does the ORACLE read, and is it the field the HARM lives in?* If the oracle cannot be stated without reusing the production predicate, it is a mirror, not a test.
  **Second sub-shape — a hard floor on a field documented as imprecise.** §4.1/§4.5 already say read the SoT entry for a field before keying on it. Neither the author nor the B-pass did; Hermes did, and it was decisive. Cheap to add to lens 1: for any NEW guard, open the SoT entry of the field it keys on and quote its invariant.
  **Also: 3 of the 6 pass-2 findings were false file:line citations in the batch's own diagnose-docs** — including one conflating `writeSubscriptionState` (an activation write) with `_downgradeLocally` (a downgrade wipe), inside the doc written to demonstrate file:line discipline. Worth keeping lens 1 pointed at the DOCS, not only the code.
  False-alarm rate 0/9 → no tuning to lenses 1-5. The seventh lens used in pass 2, `split_self_consistency` (grep the staged docs for references to work NOT in the diff), is worth reaching for on any split batch — it returned clean and independently re-verified the checklist's STILL-OPEN claim against live data.
- **2026-08-25** — blast-radius **platform** — branch `e2e-timeout-convention` (a ONE-LINE root-CLAUDE.md pitfalls row). **5 findings (0 P0, 3 P2, 2 P3); 0 false_alarm.** 3 fixed, 2 recorded with reasons. Review: `docs/reviews/e2e-timeout-convention-bpass.md`.
  **First recorded use of the §4.3 docs/process-only review MODE**, and it is worth distinguishing from the other entries here: §4.3 says a docs-only ≥account change *"takes a self-consistency review of the wording instead of an adversarial bug-hunt."* The pass was therefore a wording review plus a ground-truth audit of every factual claim — and the audit is what found everything. Lenses 1-6 as written barely apply to a one-line table row; do not force them, and do not let "the lens set returned clean" read as "the change is fine" on a docs change.
  **The finding that justifies running it at all: the row's CENTRAL CLAIM was false.** It asserted *"EVERY e2e under `test/scripts/` already has one"*; `pre_merge_commit_e2e_test.dart` had none — and that file executes the REAL pre-merge-commit hook in a real throwaway repo, i.e. it was the archetype of the hazard the row documents. A reviewer who read the row for plausibility rather than enumerating all 11 files would have passed it.
  **Generalisable rule this adds: on a docs change, every UNIVERSAL claim ("every", "all", "none", "always") is a finding until enumerated.** Two of the five findings were exactly that shape — the "EVERY e2e" claim, and a Source column citing `common-pitfalls.md` when that file had ZERO coverage of the topic (a phantom citation, which this repo already calls *worse than citing none, because it reads as coverage*).
  **Also generalisable: check whether the documented fix is the WEAKEST available one.** The row prescribes a per-file annotation held only by memory; the class has recurred 4× (`aac52fb6` alone records three consecutive failed merge attempts), and `dart_test.yaml` — which exists, configuring only the `golden` tag — would close it repo-wide in one line. Recorded rather than done, because changing the global test timeout touches every test and both CI jobs.
  False-alarm rate 0/5 → no tuning to lenses 1-6.

- **2026-08-28** — blast-radius **platform** — branch `apk39-claudemd-jdk` (one §4.9 pitfalls row: the APK build's undocumented JDK dependency). **3 findings (0 P0, 1 P1, 2 P3); 0 false_alarm.** Docs/process-only, so per §4.3 this was a self-consistency + ground-truth pass, labelled as such rather than dressed up as a bug-hunt. Review: `docs/reviews/apk39-claudemd-jdk-bpass.md`.
  **The finding worth keeping is about EVIDENCE WIDTH, not code.** The row claimed *"every APK +35→+38 used Android Studio's bundled JetBrains Runtime"*. I had read the `javaHome=` line from exactly ONE log and inferred the other three from **mtimes matching ship dates** — which establishes *when* a daemon ran, not *which JVM it used*. Two different claims, and the second does not follow from the first. Auditing properly meant enumerating all **111** logs; the claim held, and held wider than stated (every build 2026-03-30→2026-08-06, with today's the first non-JBR one ever recorded). **Generalisable: when a claim is "all N of X did Y", the audit is enumerating N, not checking one and finding a correlate that plausibly covers the rest.** Sibling of `feedback_green_check_input_set_width` — the input set here was one log wearing the costume of four.
  **Second, a process finding this pass exists because of:** the content first landed as `acd6c818`, a DIRECT commit to main at platform tier, on my assertion that the keystone gate keys on `HEAD^1..HEAD^2` and so cannot see single-parent commits. That was true before 2026-07-27 and is false now — the gate's own error text names `be3b4baf` and `8c38c855` as the account-tier auth commits that slipped through when it *"exited before looking"*. The preceding versionCode commit passed via the **version-bump exemption**, not because direct commits are exempt; I generalised from one passing case whose reason I never checked. Caught by `git-safety`'s advisory precheck seconds before the push. **A gate that passed for a neighbouring commit is not evidence it will pass for yours — read WHY it passed.**
  False-alarm rate 0/3 → no tuning to lenses 1-6.

- **2026-08-20** — blast-radius **account** — branch `claude/oi-pending-hold-weeks-1od97o` (FOB-1 week identity, OI-60). **2 findings (0 P0, 1 P1, 1 P2); 0 false_alarm.** Both fixed in-batch. Review: `docs/reviews/fob1-week-identity-bpass.md`.
  **Lens 6 found the P1 by asking its question one level OUT — not "is this guard correct?" but "is the value it produces REACTIVE where it is consumed?"** The seam, the provider and four of six surfaces were all correct. The defect: `UserStatsNotifier.build()` read the identity through a plain singleton call, so `userStatsProvider` had NO dependency-graph edge to the hold write. The five tabs sit under `StatefulShellRoute.indexedStack`, so an already-mounted Profile tab never rebuilds on tab-switch — Profile would have kept printing `WEEK 4 OF 4` while Home and Train said `HOLDING · H1`, **reintroducing the exact cross-tab contradiction the batch existed to close, on two of its own six surfaces.** This is the 2026-08-17 "follow the return value to its CALL SITE" note generalising once more: the tell was again structural — a `build()` that watches nothing it derives from.
  **The P2 is the second consecutive batch where `test_can_actually_fail` beat a mutation-proven change, and the sharper lesson is new.** The batch shipped TWO mutation proofs on the service seam and cited both in its commit message — while the LABEL layer, which is what a user actually reads, had zero behavioral coverage: the only assertion was `body.contains('stats.isHolding')` against raw source. The reviewer inverted that ternary (a real defect printing "Holding · Hnull" to every non-holding user) and **all 16 tests still passed**. Fixed by extracting the five label ternaries to pure functions with a table-driven test; the same inversion now reddens 4. **Generalisable: mutation-proving a SEAM does not mutation-prove the SURFACES that consume it.** A source-grep over a widget is presence, not behaviour — when the logic is a ternary in a `build()`, extract it to a pure function so it can be asserted at all.
  False-alarm rate 0/2 → no tuning to lenses 1-5.

- **2026-08-17** — blast-radius **platform** — branch `cycle-time-and-board-gaps` @ `3c7cb9d2`. **5 findings (1 P0, 3 P1, 1 P2); 0 false_alarm.** All fixed in-batch. Review: `docs/reviews/cycle-time-and-board-gaps-bpass.md`.
  **The P0 is the clearest case yet for running the B-pass even after a ×2 plan review passed, and lens 6 found it.** The batch had already had TWO independent context-blind rounds (8 and 10 findings). Round 1 fixed an escape hatch that a mere MENTION could grant; round 2 fixed it again for mentions inside heredocs and multi-line commit messages. Both fixes were correct. The B-pass found generation THREE: the hatch was bound correctly to a statement, and then the **caller** collapsed that binding into one command-wide boolean, so `ALLOW_RAW_GIT=1 git status; git push --force` exempted the push. Reproduced against the real hook with controls in both directions.
  **The generalisable lesson, and it is a new one for this lens:** rounds 1 and 2 both reviewed the PREDICATE and neither reviewed the CALL SITE. A guard can be perfectly correct and still be defeated by the code that consumes it — so lens 6 must follow the guard's return value to where it is USED, not stop at where it is computed. The tell was structural and visible without any cleverness: the predicate returned a `bool`, which is exactly the shape that cannot carry the binding it just established. The fix returns the offending STATEMENTS.
  **Second observation, worth keeping:** 4 of 5 findings were lens 6, and the other (`blast_radius_mismatch`) was the FOURTH recurrence of "the hook got pinned, its dependencies did not". Both are the same failure family — the fix covers the thing you were looking at and not the thing one step away. No new lens; lens 3 and lens 6 already cover it, and adding a seventh would split attention rather than add reach.
  False-alarm rate 0/5 → no tuning to lenses 1-5.

- **2026-08-13** — blast-radius **platform** — branch `post38-auth-fixes` @ `04e29b25` (PR #22 merge resolution: OI-id renumber + a new duplicate-id detector). **5 findings (0 P0, 0 P1, 5 P2); 0 false_alarm.** All fixed in `79a313d6`. Review: `docs/reviews/04e29b25-review.md`.
  **The finding that justifies the pass: a test that could not fail for the property it asserted.** The new "reports every duplicated id, in numeric order" test used a fixture of `OI-100..105` — six ids of **identical digit width**, where lexical and numeric sort produce the same output. Its `reason:` string claimed *"lexical would put OI-100 last"*, false for its own data. The reviewer substituted a lexical `.sort()` and **all 25 tests still passed**. Fixed with `[9, 10, 100, 105]` (lexical differs at BOTH ends), re-proven by execution: clean 26/26, lexical mutation 25/1.
  **Why this is worth recording rather than filing as routine:** the commit under review shipped TWO deliberate mutation proofs and cited both in its message — and still contained a third assertion that could not discriminate. Mutation-proving the code does not mutation-prove the *fixtures*. This is the `test_can_actually_fail` lens finding a gap that rule 24's ledger cannot see, because the ledger checks that a red-path assertion EXISTS, not that its data makes the wrong implementation visible.
  **NO new lens.** This is `test_can_actually_fail` (already in the brief) working as intended, not a blind spot. The other four were documentation-integrity: two bare-number citations a `sed 's/OI-<n>\b/…/'` structurally could not see, a board-vs-diagnose-doc ordinal contradiction, an unexplained empty `related_bugs:`, and a plan-review record whose narrative was frozen at an earlier slice. False-alarm rate 0/5 → no tuning to lenses 1-6.

- **2026-08-11** — blast-radius **platform** — batch `commit-merge-push-process` (ADR-0018, the pre-commit cost split). **2 findings (0 P0, 1 P1, 1 P2); 0 false_alarm.** Both fixed in-batch. Review: `docs/reviews/commit-merge-push-process-bpass.md`.
  **Lens 6 earned its place again, and taught the sharper version of its own rule.** The P1: the batch's pre-commit guard was a SOURCE GREP, and the B-pass defeated it with an indirect invocation — `_sub="ana""lyze"; flutter "$_sub"` — which runs `flutter analyze` on every commit with the suite fully GREEN. That was the **third** escape found in that one guard across three passes: the ×2 plan review's round 1 restored the calls into the `else` body (the first version's asserted range *contained* the else branch), round 2 beat the fix with `flutter  analyze` (one extra space), and the B-pass beat *that* with indirection. Each fix was defeated by the next reviewer.
  **The generalisable lesson, now added to lens 6's method note:** tightening a matcher is a losing game — a source-grep guard is bounded by what its author can imagine writing. The fix was a RUNTIME test (`test/scripts/pre_commit_lean_path_e2e_test.dart`) that executes the hook with a stub `flutter` on PATH and observes actual invocation, so it holds against any spelling. It had been skipped on a cost assumption (~22s to run the whole hook) that collapsed once the abort trick was found: stub `dart` to exit 1 and the script dies at its first gate, which sits *below* the code under test — 2s per scenario. **Reach for the behavioural test FIRST; fall back to a grep only when execution genuinely cannot be observed, and say so in the test header.**
  The P2 (`blast_radius_mismatch`): platform tier's `requires:` lists `feature_flag`, which nothing in the diff addressed and which **no gate enforces** — `check_plan_review_record_exists.dart` never reads it, so it can pass CI while unmet. Resolved as a written, founder-ratified deviation in ADR-0018 rather than a compliance claim. Worth noting the lens caught a requirement that is registry-level-only; that is exactly the gap a human-run lens exists for.
  False-alarm rate 0/2 → no tuning to lenses 1-5.

- **2026-08-10** — blast-radius **platform** ×2 — batches `gate-registry` (merge `f909cf35`) and `ci-speedup` (merge `9a5ecd82`). **3 findings (0 P0, 0 P1, 3 P2); 0 false_alarm.** gate-registry: a generator emitting a bare "." as the purpose for 2 of 87 index rows, and a comment citing a gate number the same batch's own rule forbids. ci-speedup: an asymmetric existence guard in `new-worktree.sh` that made the script CRASH under `set -e` in a case the pre-fix code handled fine. All fixed in-batch with regression tests; two carry mutation proofs.
  **NEW LENS — `guard_without_its_mirror` (lens 6).** The ci-speedup finding was the **fourth** instance in one session of one shape: `isRegenerableIgnored` went none→prefix→basename→exact across three consecutive P0s; the gate-registry hard-fail went vacuous→over-firing→correct; the worktree guard covered `origin/main` but not local `main`; and a `_settle()` fix took a per-call-site predicate derived from only the FIRST of three following assertions, turning a flaky test into a deterministically failing one. **Each fix created the next round's finding.**
  Why a LENS and not just a memory file: the ×2 plan review caught **none** of the four, and the B-pass caught only the last. A plan review reads prose; this class only shows against code. The memory file naming the pattern already existed when the fourth instance was committed — writing the rule down did not prevent applying it wrong, so it needed a checkpoint that runs over the diff.
  False-alarm rate 0/3 → no tuning to lenses 1-5. Reviews: `docs/reviews/gate-registry-bpass.md`, `docs/reviews/ci-speedup-bpass.md`.

- **2026-06-08** — blast-radius **platform** — commit `b7c8040` (ai-proxy recompose server-enum). **3 findings (1 P1, 2 P2); 1 false_alarm.** 1 P1 (diagnose `blast_radius` account→platform) + 1 P2 (`_executeRegeneratePlanBlock` missing `FitnessGoals.isKnown` guard, asymmetric with `_executeSwitchGoal`) fixed in-batch; Finding 3 (`_humanGoal` default-case for recompose) = intentional/SoT-covered → false_alarm. False-alarm rate 1/3 ≈ 33% nominally > the 30% threshold, but **n=3 is too small to act on** and the false_alarm was lens 1's (writer_reader_drift) soft defense-in-depth sub-note, not a distinct noisy lens → **NO lens tuning**. The pass also independently re-verified the gate regex + token-parse + `describe()` text (zero false-greens) and caught a real P1 + a real P2 the 0 prior reviews missed → net valuable on a prod-bound platform change. Review: `docs/reviews/b7c8040-review.md`.
