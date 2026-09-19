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

   **Third question, added 2026-09-06 (OI-162 slice 3a) — the one that catches a fix's own
   fallout: *does this change alter the SHAPE of a read or write, and if so, what are the NEW
   outcome states?*** A `count: "exact"` query has two (a number, an error). A value-select has
   THREE — row, error, and `data: null, error: null`, the successful read of an absent row. A
   rule written for two states silently assigns the third to whichever branch reads more
   naturally, and that is usually the strict one. Here a "fail CLOSED on an unreadable counter"
   rule — itself added to satisfy an earlier review round — would have swallowed the absent case
   and refused EVERY first-time free user permanently, because at cutover every user is in the
   empty state. ⚠ **Check the cold-start state first**: a bug that only affects users with no
   rows affects all of them on day one. ⚠ And note the shape of the miss — the mirror did not
   exist in the original design; **the remediation created it**, so "I already checked the
   mirror" was true of the old code and false of the new.
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

0. **Refuse to dispatch while the index and the working tree disagree.** Run
   `git status --porcelain | grep -E '^(MM|AM|MD|AD) '` — any hit means a file has edits on
   top of what is staged, and the reviewer reads the STAGED blob while every `Read` and
   `flutter test` the author ran saw the working tree. Stage or discard first, then dispatch.
   Added 2026-09-12 (author side of the 2026-09-11 `regen-wave-unit2` F1, a P0): the fix for
   a sub-defect and its widened test were verified working-tree-only and never `git add`-ed;
   the reviewer caught it by resetting to `git show :<path>` content. Lens 10 is the
   reviewer-side half; this is the check that makes the author's "done" mean the index.
1. Run `git diff --cached --name-only` and `git diff --cached` to assemble the diff.
2. Compute blast-radius via `dart run scripts/blast_radius_from_diff.dart`.
3. Generate the staging hash **exactly the way the gate does**, or the file you write
   will not be the one it looks for:
   ```bash
   git diff --cached -- ':(top)' ':(top,exclude)docs/reviews' ':(top,exclude).claude/skills/code-review/SKILL.md' | git hash-object --stdin
   ```
   then truncate to 12 chars. Three details are load-bearing and this step used to document
   only two — corrected 2026-09-14, telegram-admin-bot batch, after a session chased a
   FALSE hash-fixed-point across 3 renames believing SKILL.md's own content moved the
   hash (it does not — `check_code_review_pass_exists.dart`'s real exclusion set already
   dropped SKILL.md too, per the OI-162 slice 4 addendum this file's own history section
   documents at length below; this step's code block had simply never been updated to
   match):
   - It is git's **sha1 `hash-object`**, not `sha256`.
     `scripts/check_code_review_pass_exists.dart` has always used `git hash-object`, so
     a review named by following the old text could never match. (Found by round-1B
     review of the gate-input-family batch, 2026-07-27.)
   - `docs/reviews/` is **excluded** from the hash (OI-72, same batch). The gate now
     reads the review from the STAGED blob, so the file must be `git add`ed — and
     without the exclusion, staging it would move the hash and rename the very file it
     is meant to satisfy.
   - `.claude/skills/code-review/SKILL.md` is **also excluded** (OI-162 slice 4
     addendum, 2026-09-11) — its own §5.1-required tuning-history entry must land in
     the SAME commit as any new review file, so without this exclusion staging THAT
     would move the hash exactly the way staging the review itself would have, with no
     clean iterative fix. Use the three-pathspec command above, not the two-pathspec
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

- **2026-09-19 (c)** — blast-radius **platform** — branch `oi204-delta-sync`
  (OI-204: extends the proven `_syncScheduledWorkouts` fingerprint-skip
  pattern to `_syncExerciseLogs`/`_syncNutritionLogs`, plus the
  gate-before-refactor atomicity checker CLAUDE.md §4.11 required before the
  first refactor commit). **4 findings (1 P1, 1 P2, 2 P3); 0 false_alarm —
  all 4 accepted and closed in-batch** (3 fixed in code/docs, 1 verified
  already correctly — if under-emphasized — disclosed, wording strengthened).
  Review: `docs/reviews/oi204-delta-sync-bpass.md`. Two fresh reviewers,
  lenses 1-5 / 6-8, against the three-dot `main...HEAD` diff (23 files; the
  naive two-dot form is a live trap on any branch whose base independently
  gained commits after the fork — confirmed here, since `main` picked up 8
  unrelated gates from a sibling branch mid-session).
  **Tuning — lens 6 (`guard_without_its_mirror`) gains a specific sub-shape
  for gates that scan SOURCE TEXT in two passes at different granularities:
  a whole-text existence check and a per-line follow-up scan can silently
  disagree, and the disagreement IS the defeat.** Finding 1 (P1): the
  atomicity gate's `hasStore` matched a store statement against the WHOLE
  file (tolerating `\s*` spanning a newline, which Dart's `\s` always does),
  then separately re-ran the SAME regex per INDIVIDUAL LINE to locate which
  line(s) to guard-scan from. A store wrapped across two lines — a plausible
  `dart format` output past 80 columns, not a contrived shape — matched the
  first pass and matched NEITHER half of the second, so the guard-scan list
  came back empty and an unguarded multi-line store silently passed. Reviewer
  B reproduced this live against the real gate with a positive control
  (single-line form correctly failed) before reporting it. **Add to lens 6's
  method: when a gate computes the same property twice at different
  granularities (whole-file vs per-line, whole-statement vs per-token), ask
  whether both passes are guaranteed to agree — a regex whose match spans
  newlines but whose re-application is scoped per-line is exactly this
  shape, and it generalizes past this one gate.**
  **Second — a lens-6 finding whose correct triage was "verify the existing
  disclosure, then strengthen wording" rather than "write new code."**
  Finding 2 (P2) reproduced a second, DIFFERENT blind spot in the same gate
  (a new swallowing catch that forgets to flip its flag false leaves an
  aggregate COUNT check unchanged) — and this one was ALREADY disclosed
  accurately in `docs/architecture/sync.md`, confirmed by reading the cited
  section directly rather than trusting the citation. The finding's real
  value was that the disclosure's WORDING undersold the severity ("the gate
  can't distinguish X from Y" reads as benign ambiguity; the actual
  consequence is a false-skip, the dangerous direction the whole mechanism
  exists to prevent). **Not every accepted finding needs a code fix — some
  need the existing accurate-but-underselling prose corrected to name the
  real consequence, and that's a legitimate, cheaper terminal state than the
  heavier structural fix the finding's own author correctly declined to
  demand.**
  False-alarm rate 0/4 → no lens removed; lens 6 extended per above.

- **2026-09-19 (b)** — blast-radius **platform** — branch `gate-integrity`
  (OI-220 pre-push contract sweep · OI-155 Gate 33 typed allowlist · OI-195
  Gate 42 path resolution · OI-181 safe_merge absent-record precheck; four
  forks in isolated worktrees, coordinator-integrated). **2 findings (0 P0,
  0 P1, 1 P2, 1 P3); 0 false_alarm — both fixed in-batch** (`e993a345`).
  Review: `docs/reviews/gate-integrity-bpass.md`. The reviewer ran in its OWN
  worktree (`isolation: worktree` + `git reset --hard <sha>`) so its mutation
  probes could not collide with the coordinator's concurrent
  `flutter test test/scripts/` run — do this whenever a review and a test run
  overlap in time; it is the same lesson as "serialise review rounds" without
  paying the serialisation.
  **Tuning 1 — lens 6 gains a sub-shape: "the hardening one function ABOVE
  did not travel."** `extractCaseSkips` had been hardened against
  comment-restated names; `invokesGate`, directly below it in the same file
  and backing every `file()` runner, shipped as a bare `contains()` and read
  heredoc bodies and invoker-less prose as invocations. When a file contains
  a documented past hardening, ask which SIBLING predicates in that file make
  the same class of decision and whether the hardening reached them.
  **Tuning 2 — lens 7 (missing_input) for CHECK SCRIPTS: a non-`check_*`
  runner is invisible to every gate that enumerates `check_*`.** The sweep is
  deliberately `contract_sweep.dart` (both loops enumerate `check_*`; the
  rule-24 ledger rejects non-`check_*` keys), so its wiring needs its OWN pin
  (`test/contracts/contract_sweep_wired_test.dart` + a behavioural assertion
  that the real hook reaches the line). Reviewer question: "what enumerates
  this, and if nothing does, what pins it?"
  **Tuning 3 — lens 8 (asserted_fixture_value) for REGEXES written into a
  plan: `grep -c` the regex against the REAL file before believing any
  selection it drives.** The v1 registry arm matched `^\s+file:` — zero hits
  against 896 `- file:` items and 176 `{ file: }` maps — and would have
  shipped inert; caught by plan-review round 1, not by reading.
  **Tuning 4 — Windows-specific red flag for anything that spawns `flutter`
  from Dart under a test that stubs `flutter` on PATH:** `Process.runSync(
  'flutter', …, runInShell: true)` goes through cmd.exe, which cannot execute
  an extensionless POSIX stub and finds the REAL flutter — a recursion the
  file-level `@Timeout` cannot interrupt (`runSync` blocks the isolate).
  Guard with an env sentinel set on the spawn (`CONTRACT_SWEEP_NESTED=1`) and
  a kill switch the e2e sets; probe `flutter --version` from Dart to see which
  binary answers.
  **Tuning 5 — L25 adjacency greps miss LINE-WRAPPED citations.** Finding 2's
  three wrong dates were found with a `0768a0ce.{0,3}2026-09-18` adjacency
  grep, which missed the closure YAML's instance because YAML `>` folding put
  the date on the next line; `git grep <sha> | grep <date>` (two passes, no
  adjacency) is the widest form. Same family as the analyzer `^\s+` trap.
- **2026-09-19** — blast-radius **feature** (record commit; the underlying
  bump commit `a4eb42ab` self-declared **platform**) — branch
  `plan-review-record-versionbump44`, filling in a plan-review record the
  `aab-versioncode-bump-44` merge (`0768a0ce`) needed but never got: the
  version-bump exemption in `check_plan_review_record_exists.dart` only
  covers single-parent direct-to-main commits, never a `--no-ff` merge, so
  the standard §4.13 worktree+`safe_merge.sh` flow (unlike every prior
  versionCode bump) failed CI's plan-review-record gate. **0 findings; 0
  false_alarm.** Review: `docs/reviews/aab-versioncode-bump-44-bpass.md`
  (two independent zero-finding passes — self + a fresh context-blind
  subagent — both confirmed the diff touches only the two version literals).
  **Tuning — none.** Nothing new surfaced; recorded here only because §5.1's
  gate requires an entry for any `docs/reviews/**.md` addition, and this one
  genuinely has no lesson beyond the process gap already named in the plan-
  review record itself (`mechanical_only: true` per CLAUDE.md §4.12.6 has no
  effect in the gate script — confirmed by grep, zero hits).
- **2026-09-19 (c)** — blast-radius **feature** — branch
  `discipline-gates-tier12` (8 new mechanically-gateable `check_*.dart`
  gates derived from the repo's 2 highest-recurrence `feedback_*.md` files —
  `feedback_green_check_input_set_width.md` and
  `feedback_mistake_guard_without_its_mirror.md`). **4 findings (0 P0, 0 P1,
  0 P2, 4 P3 — all low); 0 false_alarm — all 4 fixed in-batch.** Review:
  `docs/reviews/ab9c36f14353-review.md`. All 4 were documentation-only: 2
  arithmetic errors in `docs/audit/gate_test_ledger.yaml`'s own
  `evidence:` prose (test totals that didn't sum after the coordinating
  session's own manual mutation re-runs — the reviewer independently re-ran
  all 8 gates' mutations rather than trusting the ledger text, and found the
  2 gates nobody had personally re-verified were exactly the 2 with wrong
  arithmetic), and 2 wording-precision issues in
  `gate_existssync_file_vs_dir_lib.dart`'s header comment (a stale,
  self-referential calibration count; and a past-tense framing of a
  caught-in-review spec defect that could misread as a confirmed live
  incident against the cited OI's actual "0 missing, not a live breach"
  status). No functional defect in any of the 8 gates' detection logic.
  **Tuning — a new sub-instance of the ledger's own trust model, not a new
  lesson:** rule 21/24's `mutation_proven:` and `evidence:` fields are
  self-attested by design (CLAUDE.md §4.4 rule 21 says so explicitly), and
  this review is a concrete case of that self-attestation drifting on
  exactly the arithmetic a human proofreader tends to skim past — the
  fresh-agent B-pass is doing real work here, not rubber-stamping. No skill
  change warranted; the existing "mutate it and run it, personally" discipline
  is what caught this, both in the coordinating session (6 of 8 gates,
  independently) and in this B-pass (the remaining 2).
- **2026-09-18 (b)** — blast-radius **platform** — branch `discipline-v2`
  (S/M/L fix tiering + batch telemetry + hook wiring). **6 findings (0 P0, 0 P1,
  6 P2); 0 false_alarm — all 6 fixed in-batch** (`7de94167`). Review:
  `docs/reviews/discipline-v2-bpass.md`. ⚠ **Process lesson (the 5th instance of
  `feedback_gates_unsatisfiable_at_merge`): the B-pass REPORT must be written to
  `docs/reviews/<x>.md` with a line-anchored `verdict: accepted` BEFORE the merge,
  and the plan-review record's `bpass_review:` field must point at it — `bpass:
  accepted` alone hard-fails the CI record gate at the merge commit, unfixable
  after.** The controller folded the B-pass findings into the record's prose and
  skipped the pointer file; CI caught it post-push.
  **Tuning 1 — the "hook pinned, dependencies not" class has a THIRD member: the
  hook's output CONTRACT.** The telemetry CLI's stdout is embedded into the Stop
  hook's harness-visible `reason` payload, yet both telemetry scripts fell through
  the `scripts/**` feature catch-all — a telemetry-only commit would have cleared
  no review gate while changing what the harness parses at batch close. When a
  helper's OUTPUT is consumed by a pinned gate/hook, pin the helper too.
  **Tuning 2 — null-valued enum fields need a no-news state, not a default.**
  `top_gate` rendered `none` (a clean answer) beside `gate_failures_7d=unknown`
  (no answer) — the pair contradicted itself. When one field signals "unknown",
  every sibling field on the same line must say `unknown` too.
- **2026-09-18 (a)** — blast-radius **account** — branch `sync-banner-force-retry`
  (sync queue: force-retry on manual Retry, SyncBanner display grace, enqueueFresh
  count heal). **6 findings (0 P0, 0 P1, 1 P2, 5 P3); 0 false_alarm — all 6
  accepted and fixed in the same session.** Review:
  `docs/reviews/efcfe7745ebe-review.md`. Run as one agent (8 files; the reviewer
  re-derived interleavings, window arithmetic, and mutation outcomes by trace
  rather than trusting the tests' own comments).
  **Tuning 1 — lens 6: a per-CALL flag can still be AMBIENT WITHIN one
  coalesced invocation.** The force flag was correctly per-call at the trigger
  sites, but `passForce` is declared OUTSIDE the do-while and only ever raised —
  so a PLAIN caller coalesced into an in-flight forced pass rides that pass and
  is served forced. Three docs asserted "force is per-call, never ambient" and
  all three were true only at the call-site level. **When a new per-call flag
  interacts with an existing coalescing/in-flight mechanism, trace
  cross-caller contamination INSIDE one invocation, not just across calls —
  and make the doc say which level the guarantee holds at.**
  **Tuning 2 — a gate-parked behavioral test must GUARANTEE the parked pass
  drains on premise failure.** The sticky-rerun scenario parked the queue's
  executor on a Completer; if the premise assertion failed first, the gate was
  never completed, `_draining` stayed true for the rest of the FILE, and
  subsequent tests failed with confusing no-op symptoms (setUp cleared Hive but
  not the singleton's in-flight flag). Fixed with a try/finally that always
  completes the gate and swallows the secondary await. **Any test that parks a
  singleton's in-flight state on a future owes its own finally an unconditional
  release — the same hygiene rule as teardown-never-throws, one level earlier.**
  **Tuning 3 — lens 10 generalized: when a doc carries the SAME fact in TWO
  places (frontmatter evidence field + prose narration), diff them against
  each other.** The diagnose doc's frontmatter correctly recorded m2's real
  discriminator (mixed-ages test; the "just under" test self-adjusts with the
  constant) while its prose paragraph still claimed the parameterized test
  reddened — a future mutation runner could not tell which record was true
  without re-running. The same pass found the prose test-count split (9+34)
  contradicted the file reality (6+37) while the total (43) was right.
  **Count claims that appear twice in one document get checked twice, once
  against each other.**
  **Tuning 4 (remediation-side, author lesson) — a SYNCHRONOUSLY-throwing
  executor cannot be interleaved against: it unwinds on MICROTASKS, so the
  test's next statement runs AFTER the pass has fully unwound (finally
  included) and a mid-pass force request never hits the in-flight guard. The
  gate-park pattern (executor returns a pending Completer future; test
  completes it with the throw) is the only reliable way to position a request
  mid-pass.** Costs one silent test rewrite during F5 remediation; caught by
  reading the failure trace, not by the diff.
  False-alarm rate 0/6 → no lens removed; lens 6 and the general method extended
  per above.

- **2026-09-17 (c)** — blast-radius **platform** — branch `diet-plan-quality`
  (diet plan generator meal-quality constraints + tagged food DB v3).
  **6 findings (1 blocker, 2 majors, 3 minors); 0 false_alarm — all
  remediated in-batch.** Review: `docs/reviews/diet-plan-quality-bpass.md`.
  **Tuning — DATA-append commits need the SAME duplicate/name/source
  contract checks the code gets: the B-pass caught 4 appended food-DB rows
  duplicating existing NAMES (append script checked ids only), plus a
  `source` tag that inflated a pinned count 93->103 — 2 RED assertions that
  would have shipped on main. When a batch appends rows to a curated data
  asset, run the asset's own contract tests (required-fields, duplicate
  names, pinned counts) BEFORE the append is believed, and give appended
  rows a DISTINCT source tag. Second lesson: the fixture suite and the
  real-data suite disagree in BOTH directions — a fixture-only green hid 4
  real-data defects (vegan name-blocklist leak, thin anchor pool), and the
  B-pass's veg-preference finding showed the same class on a second
  preference. Any filter built against a curated fixture must be re-proven
  against the full production dataset in the same batch.**
- **2026-09-18** — blast-radius **platform** — branch `ai-coach-ux-tool-integrity`
  (paused/moved/dropped schedule-status semantics: streak/rank invisibility,
  terminal rows replacing reschedule raw-deletes, exlog re-key + index
  maintenance, restore-merge terminal arm, Compass capture sheets, Captain
  chat suffix). **9 findings (0 P0, 1 P1, 2 P2, 4 P3, 2 P4); 0 false_alarm —
  all fixed or documented as accepted deviations in the same session.**
  Review: `docs/reviews/2026-09-18-ai-coach-ux-tool-integrity-bpass.md`.
  **Tuning 1 — when a batch redefines the semantics of a stored VALUE
  (a status/enum/kind), the server mirror is a separate reader: the client
  fixed its rate math (rank/streak) but `rank_engine.ts` (the
  evaluate-rank-promotions cron's own aggregation) still counted the new
  terminal rows — permanent server-side gate deflation that BOTH plan
  reviews missed and only the B-pass cross-seam lens caught. Add to the
  general method: a value-semantics change requires grepping the SERVER
  tree (supabase/functions/) for the same value, not just lib/.**
  **Tuning 2 — a new persisted state must teach every READER class, not
  just its writer: terminal rows needed (a) an index-maintenance arm in
  `moveExerciseLogs` (the exlog index is a second writer-side structure the
  re-key must carry along), (b) a restore-merge arm (cloud planned vs local
  terminal), (c) overwrite guards in EVERY writer that skips only
  `completed` today (pauseRange was the one the batch missed). Checklist
  for any new row-status: writer, index/derived structures, restore merge,
  all `completed`-skipping guards, server mirrors, then tests that seed the
  state the REAL writer produces (the round-1 fixture seeded no index entry
  and was blind to the exact bug it existed to catch).**
- **2026-09-17 (b)** — blast-radius **account** — branch `web-razorpay-checkout`
  (web Razorpay checkout: checkout.js bridge via dart:js_interop, shared
  handlePaymentConfirmed extraction, kill-switch). **8 findings (0 P0, 0 P1,
  4 P2, 4 P3); 0 false_alarm — all 8 accepted and fixed in the same session.**
  Review: `docs/reviews/7446a3c8a418-review.md`. Run as one agent (15 files).
  **Tuning 1 — a fix can be silently UNDONE by the author's own later
  `git checkout -- <file>` during mutation-proofing: the file carried
  UNCOMMITTED lint fixes when the restore ran, and the reviewer's fresh
  analyze caught the reverted lint (Finding 8) that the author believed was
  already shipped. Add to the general fix-application method: after ANY
  mutation-restore cycle, re-verify that every earlier uncommitted edit in
  the same file still exists — mutation restores and pending fixes share one
  working tree, and "I fixed that" is only true if the fix is still there
  (or committed). Commit lint fixes BEFORE starting mutation cycles.**
  **Tuning 2 — a mid-batch SoT `line_range:` update rotted within the SAME
  batch: correct at its own commit, stale 3 commits later (Finding 4),
  invisible to the parity gate (gate keys on the class name). This is
  2026-09-16(d) Tuning 4's "re-derive citations LAST" applied to the batch
  scale rather than the finding scale: not just later FIXES shift lines —
  the batch's own ordinary follow-on commits do too, so the registry
  re-derivation must be scheduled as the FINAL code touch of the batch, not
  bundled into the commit that renames the method.**
  **Tuning 3 — a comment's negative capability claim ("checkout.js has NO
  failure callback") was false per the vendor's own docs and was doing
  load-bearing work: it justified an unwired error path. Lens 6 found it by
  checking the claim against the SDK's documented API instead of the diff's
  internal consistency. Add to lens 6's method: a comment that explains why
  something is NOT wired is a checkable claim — verify against the
  dependency's actual API surface, because "impossible" claims create blind
  spots that survive every other lens.**
  False-alarm rate 0/8 → no lens removed; lenses 6 and 8 extended per above.

- **2026-09-17** — blast-radius **platform** — branch `custom-picker-fix`
  (custom exercises invisible in all 3 pickers: OI-89 fail-closed
  capability filter vs the creation sheet's hardcoded empty
  `equipment_needed`; diagnose `e7b2d4`. Reader-side picker exemption +
  muscle capture + edit mode; Option B filed as OI-211). **6 findings (1
  P1, 3 P2, 2 P3); 1 false_alarm — 5 accepted and fixed in-batch, 1
  resolved by writing this artifact.** Review:
  `docs/reviews/5e1a43da8881-review.md`. Run as one agent over the staged
  diff; the reviewer independently re-derived all 5 mutation-proof claims
  (all reproduced exactly).
  **Tuning 1 — lens 6 (`guard_without_its_mirror`), sibling-seam sweep:
  when a batch narrows a guard for one POPULATION, grep for every OTHER
  call site applying the un-narrowed guard to that same population — not
  just within the touched files.** `git grep -n "canPerform(" lib/` after
  the picker exemption found `swap_service.dart:256` (OI-89 seam 9, the
  AI-driven swap executor) still refusing the exact population the UI
  swap sheet had just started offering — an asymmetry the batch CREATED
  (the picker previously refused it too), so the diff hunk itself could
  never show it. The fix site's own seam inventory (`exercise_seam_lib`)
  knew about seam 9 but nothing tied its capability policy to the new
  predicate. **Generalized: a guard-narrowing batch owes a full grep of
  the narrowed predicate's call sites, not a review of the diff's own
  sites.**
  **Tuning 2 — writer_reader_drift extended to TWIN-NAME fields: a batch
  that adds an EDIT path to a row family must sweep the field set for
  cloud-vs-Hive name twins, because the EDIT (not the restore) is what
  forks a row carrying both.** `default_duration_secs` (cloud column,
  kept verbatim by restore) vs `default_duration_seconds` (Hive-canonical,
  written by both UI and AI writers) coexisted harmlessly while rows were
  write-once; the first edit that preserved unknowns while adding the
  canonical key forked them, and the two readers (`train_provider.dart`'s
  parser read only the cloud name; `exercise_selector.dart`'s L2 read
  only the Hive name) then disagreed per reader. The reviewer's suggested
  fix (drop the twin on edit) plus the main-thread extension (the parser
  must read BOTH keys — a pre-existing drift the fork fix alone would
  have left) together closed it; pinned behaviorally by
  `custom_duration_key_convergence_test.dart`.
  **Tuning 3 — the anti-fabrication check for `bpass: accepted` is now
  experienced as the EXPECTED first finding, not a process failure: a
  plan-review record authored before the B-pass runs will always
  initially lack `bpass_review:`.** Writing the record with
  `bpass: accepted` before the pass runs is the failure; the flow that
  worked here is record → B-pass → fix findings → write review artifact
  with the FINAL staging hash → add `bpass_review:` → stage (the review
  file is hash-excluded, so staging it does not move its own name).
  False-alarm rate 1/6 (16%) → no lens removed; lens 6's sibling-seam
  sweep and writer_reader_drift's twin-name sweep added per above.

- **2026-09-16 (a)** — blast-radius **platform** — worktree `apk43-obs-fixes`
  (not yet a merged branch), APK 1.0.0+43 observation batch, Obs 1 (nutrition
  save-meal silent-catch telemetry, diagnose `d8e2f4`) + Obs 2 (AI coach
  history-poisoning `hadHardFailure` flag, diagnose `a1c6b9`). **3 findings
  (1 P1, 0 P2, 2 P3); 0 false_alarm — all 3 accepted and fixed in the same
  session.** Review: `docs/reviews/6f1e4db85459-review.md`. Run as one agent.
  **Tuning 1 — lens 6 (`guard_without_its_mirror`) found the batch's own
  fix incomplete by grepping the file for a SECOND instance of the exact
  string shape the fix was written around, not by re-reading the diff.**
  `tool-loop.ts` has TWO hardcoded, non-model apology texts (a documented,
  pre-existing pair — one for "the Gemini call itself threw", one for "the
  loop exhausted without ever producing text or a queued intent"). The
  diff added a `hadHardFailure` flag and wired it through the ENTIRE
  history-replay + memory-embed pipeline correctly for the FIRST apology,
  and simply never checked whether the second one needed the same
  treatment — its own diagnose-doc's root-cause section only named the one
  code path it was written against. `grep -n "I had trouble"
  supabase/functions/_shared/tool-loop.ts` — one command — surfaces the
  second site immediately; the diff's own author had run that exact
  investigation for the FIRST site (a live Supabase log query) and had no
  reason to suspect a sibling existed elsewhere in the same file. **Add to
  lens 6's method: when a fix's mechanism is "mark case X so it can't
  reach sink Y", grep the whole touched file (not just the diff hunk) for
  every OTHER value that also reaches sink Y unconditionally — a new flag
  is a new mirror-case surface, and the diff hunk itself will never show
  you a sibling it didn't touch.**
  **Tuning 2 — the fastest way to find an untested vacuous negative
  control is still lens 8's own "would this pass if the feature did
  nothing at all?" question, but it has to be asked about the SPECIFIC
  code path claimed, not the test's name.** Finding 3's test was literally
  titled "negative control" and its docstring said "no exception is
  thrown" — both true, both describing a path (the `state == null` early
  return) that sits BEFORE the code under test. A reader trusting the
  title would credit it with proving something it structurally cannot.
  The check that catches this is mechanical and cheap: read the function
  body, find every `return` that precedes the code the fix touches, and
  ask which of them the "negative control" actually exercises.
  **Tuning 3 — a diagnose-doc's own `cloud_columns:` frontmatter claim is
  exactly as citable-and-wrong as a line-number citation (2026-09-14
  Tuning 2's class), just for a schema shape instead of a file position.**
  `failed` was invented as a plausible-sounding cloud column because the
  SAME name is real on the Hive side one paragraph earlier in the same
  doc — the author's own correct Hive fact bled into an adjacent,
  unverified cloud claim. `backups/live_schema_columns.json` settles it in
  one read; the SoT registry entry itself (unlike the diagnose-doc) never
  made the same mistake, which is worth noting as a MODEL for how the
  doc's own frontmatter should have been written.

- **2026-09-16 (b)** — blast-radius **platform** — branch `oi53-batch1-flip` (OI-53 batch 1: flip
  `exerciseIdHistoryEnabled` + `injurySubstitutePreferenceEnabled` + `crossPhaseVarietyEnabled`
  from ship-dark default-OFF to default-ON-with-kill-switch — the full ×2-review flip-on tier per
  §4.12.4, not the lighter ship-dark build tier). **3 findings (0 P0, 0 P1, 1 P2, 2 P3); 0
  false_alarm — all 3 accepted, 2 fixed in-batch, 1 accepted with no code fix (substance already
  tracked by an existing, wider OI).** Review: `docs/reviews/1cadbcd1d01f-review.md`. Run as one
  agent (10 files: 1 flag-definitions file, 4 behavioral test files, 1 nested CLAUDE.md, 1
  SoT-registry, 2 OI-board files, 1 plan-review record).
  **Tuning — `modelled_on_is_a_checkable_claim` gains: verify a claimed "established convention"
  against the CONTENT of the cited commits, not just their existence in `git log`.** The diff's own
  plan-review record justified leaving `docs/ship_dark_pending_review.yaml` untouched (these 3
  flags stay under `pending:` pending a follow-up records commit) by calling that a "established
  split-commit convention" for this file, citing two real prior commit pairs. Reading the actual
  diffs of the other 3 prior OI-53-family flips (not just checking they existed) found 2 of them
  had written a literal placeholder string `flip_commit: pending` into the WRONG list
  (`pending:`, not `resolved:`) and the 3rd hadn't touched the ledger at all — all 3 sat wrong for
  27/5/1 days until a dedicated cleanup commit (whose own message calls it a bug fix, not a
  workflow) corrected them. The convention was real for the 2 MOST RECENT flips only; citing "5
  prior commits" without opening what each one actually wrote let a 2-real/3-broken precedent read
  as an established pattern. **The general form: when a citation claims a REPEATED pattern across
  N prior instances, open all N, not just enough to find one clean example** — sibling of this same
  file's existing "verify the precedent's CURRENT form" rule (2026-09-14), one level earlier: here
  the precedent's frequency was the unchecked claim, not its content.
  **A negative result worth keeping.** Every other lens returned clean, and each "verified clean"
  claim in the reviewer's own report (mutation-test results, the OI-53 board arithmetic, the
  dev-panel absence grep, the blast-radius `requires:` list) was independently re-run by the
  orchestrating session before being trusted, rather than accepted on the subagent's prose — the
  OI-53 "6 remain" figure in particular was re-confirmed a THIRD independent time this way (having
  already been corrected once from a subagent's stale arithmetic earlier in the same session,
  per this record's own plan-review "Remediation" section) and held exactly.
  False-alarm rate 0/3 → no lens removed; `modelled_on_is_a_checkable_claim` extended per above.

- **2026-09-16 (email-confirm-ux OI-51 follow-up)** — blast-radius **account**
  — branch `email-confirm-ux`, a second, later B-pass on the SAME branch: the
  OI-51 device-identity-release fix on `confirm_email_screen.dart` (diagnose
  `d4a8f6`) discovered and fixed while pushing the branch — distinct from the
  earlier same-day `email-confirm-ux` entry below, which reviewed the whole
  feature batch before this fix existed. **5 findings (0 P0, 0 P1, 2 P2,
  3 P3); 0 false_alarm — all 5 accepted**, 4 fixed via doc corrections, 1
  filed as OI-208 rather than fixed inline. Review:
  `docs/reviews/a558ff1b978b-review.md` (renamed from the dispatch-time
  hash `22569be9cd62` after the doc corrections below moved the staging
  hash — see that file's own header note). Run as one agent (3 files, one a
  12-line code diff).
  **Tuning 1 — a diagnose-doc's claimed FAILURE MECHANISM is a checkable
  claim, the same way lens 3 already re-derives a claimed blast-radius tier
  and lens 9 re-derives a claimed "modelled on X".** The doc's `symptom:`
  field said the bug was reachable via "any step in `_teardown()` throwing" —
  plausible-reading prose, and false: every step in `_teardown()` already
  swallows its own throw in its own try/catch, and the caller's try/catch
  around the whole call also does not rethrow, so an internal step throwing
  structurally cannot escape `signOut()`. The fix itself was still correct
  (it matches an already-shipped precedent for the identical call shape) —
  only the AUTHOR's own explanation of why was wrong, caught by reading the
  actual code path rather than accepting the doc's narrative. Add to the
  lens set's general method: when a diagnose-doc states WHY a bug is
  reachable, trace the claimed code path yourself before accepting it,
  exactly as already done for WHERE a claim points (asserted_fixture_value)
  and WHAT a claim's value is (blast_radius_mismatch).
  **Tuning 2 — mutating the same code path a step further, past what the fix
  addresses, found a real but correctly out-of-scope gap — and the right
  move was filing an OI, not fixing it and not dropping it.** The same
  swallow-without-rethrow shape that made Finding 1's claimed mechanism
  impossible ALSO means a genuine `_teardown()` TIMEOUT (not a throw) leaves
  `signOut()` returning normally to every caller — so none of the three
  call sites' try/catch guards (this fix and its two precedents) can ever
  fire for that case, because nothing throws. Real, pre-existing, identical
  across all three sites, not introduced by any of their guards. Filed as
  OI-208 rather than redesigning `_teardown()`'s signal contract inline —
  the established "distinguish 'the doc is wrong, fix now' from 'the system
  has a gap, file it'" split (see the 2026-09-14 (c) entry below) applied a
  further time, here between two findings from the SAME trace rather than
  two findings from different files.
  **Tuning 3 — two of the five findings were confirmable by pure arithmetic,
  with no test execution needed, and are worth a specific callout as the
  cheapest possible form of asserted_fixture_value.** A mutation-proof
  citing "line 211" for a REVERTED state that removes exactly one line above
  it is checkable by counting, not running: removing one line shifts
  everything below it up by exactly one, so the reverted state's line is
  necessarily 210. Likewise a claimed "8 of 10 pass when 1 fails" is
  arithmetically wrong on its own terms (10 − 1 = 9) without needing to know
  anything about the test file at all — confirmed by `grep -c` against the
  real file only as a second check, not the first. **Before re-running
  anything to verify a numeric mutation claim, check whether the claim is
  already self-contradictory or off by a checkable arithmetic step.**
  False-alarm rate 0/5 → no lens removed; general method note added per
  Tuning 1.

- **2026-09-16 (c)** — blast-radius **platform** — branch `oi53-batch2-flip` (OI-53 batch 2: flip
  `gradedProgressionEnabled` + `sessionDetrainingCutEnabled` + `physiqueFocusBringupEnabled` +
  `adherenceGateEnabled` from ship-dark default-OFF to default-ON-with-kill-switch, same pattern
  as batch 1 above). **2 findings (0 P0, 0 P1, 1 P2, 1 P3); 0 false_alarm — both pending
  founder triage at write time.** Review: `docs/reviews/c22fa39a1cbf-review.md`. Run as one
  agent (22 files: 1 flag-definitions file, 4 call-site comment updates, 7 behavioral test
  files, 2 nested CLAUDE.md, 1 SoT registry, 2 OI-board files).
  **Tuning — lens 6 (`guard_without_its_mirror`) found the batch's own "redundant defense-in-depth"
  claim was TRUE for only one of the two call sites it was written to describe, and the batch's
  own more-precise sibling docs already knew the narrower truth.** `adherenceGateEnabled` gates
  a repeat-pin decision computed at two call sites — `pro_phase_advance.dart`'s automatic
  low-adherence repeat (3-a2) and `graduation_screen.dart`'s explicit choice sheet (3-b). The
  flags file's doc comment, a new `docs/audit/open_issues.md` bullet, and a nested CLAUDE.md all
  described the flag as re-checked a second, redundant, mutation-confirmed time "immediately
  before `_buildRepeatPins`" for the mechanism as a whole. Tracing the actual call graph found
  that re-check exists ONLY on the 3-a2 path (`workout_schedule_read_service.dart:659`,
  reachable with zero `await`s from the first read — genuinely un-raceable); the 3-b
  (graduation) path calls `buildRepeatPinsForAdvance` → `_buildRepeatPins` directly, which
  contains no flag reference at all, and its ONE flag read sits before a real human-time
  `await showAdvanceChoiceSheet(context)` with nothing re-verifying it after. Two files already
  had the narrower, correct phrasing — `docs/sot_registry.yaml`'s own concept entry ("checked
  TWICE on the 3-a2 path") and the new test's own comment ("checked TWICE on this path") — which
  is what made the broader claim in the other three files checkable as wrong rather than merely
  ambiguous. **Add to lens 6's method: when a diff describes a guard as covering "N call sites"
  collectively, find the one sibling doc (if any) that scopes the claim to a SINGLE site, and
  treat any wider phrasing elsewhere as the thing to verify, not confirm.** Coverage gap
  confirmed structurally: `grep -rln "runGraduationPhaseAdvance" test/` found no test that
  touches `PlanEngineFlags.adherenceGateEnabled` while driving that function, so nothing catches
  a future regression on the unprotected path. Rated P2, not higher, because none of the OI-53
  flags has a release-build toggle (dev-panel only, no RemoteConfig, per OI-95) — the race
  window is real but reachable only in a debug/QA session today.
  **Tuning 2 — lens 8 extended to a PROSE count, not just a test literal, and caught a
  same-diff self-inconsistency.** A freshly-filed OI's own "how found" bullet said "4 more
  stale citations" and then named five; cross-checked against the `sot_registry.yaml` diff,
  which does show exactly five method-level `line_range:` corrections for the named methods.
  All five corrected ranges, and separately the new OI's own cited line numbers for the
  DIFFERENT (deliberately out-of-scope, pre-existing) stale citations it was filed to track,
  were independently re-read against the live file and are byte-exact — the miscount is
  isolated to the one summary number, not to any of the corrections themselves. **Lens 8's
  "compute it, don't read it" method applies equally to a hand-counted list inside a doc as to
  a test's expected literal — count the enumeration, don't trust the numeral next to it.**
  False-alarm rate 0/2 → no lens removed; lens 6 and lens 8 extended per above.

- **2026-09-16 (d)** — blast-radius **platform** — branch `obs-batch-2026-09-16` (a 5-fix
  founder-observation batch: quote-picker category collision, sync-queue auto-drain never
  wired, Train phase-lock empty state, signup-confirm toast color, and the `/confirm` web
  redirect — none individually account/platform-worthy, but `pubspec.yaml`/`pubspec.lock`
  adding `connectivity_plus` for the sync fix classified the WHOLE batch platform-tier).
  **7 findings (0 P1, 2 P2, 5 P3); 0 false_alarm — all 7 accepted and fixed in the same
  session.** Review: `docs/reviews/08821dc5a27b-review.md`. Run as one agent (26 files, but
  ~1,050 of the 1,699 inserted lines were diagnose-doc/test prose — modest real code diff for
  5 independent, small, well-scoped fixes).
  **Tuning 1 — lens 3 (`blast_radius_mismatch`) caught a diagnose-doc under-declaring its OWN
  fix's tier, not just the batch's.** Finding 2: `lib/core/utils/hold_week_labels.dart` falls
  under the `lib/core/** -> account` catch-all in `docs/blast_radius.yaml`, which the author
  missed because the OTHER two files touched by that same fix (`screen.dart`,
  `empty_states.dart`) are feature-tier — a diagnose-doc's self-declared tier needs the
  classifier run on ALL of ITS OWN touched files, not just the ones that feel representative.
  Cross-checking all 5 of this batch's diagnose-docs the same way found the other 4 exactly
  matched the classifier; only the one spanning `lib/core/` under-declared.
  **Tuning 2 — lens 6 (`guard_without_its_mirror`) applied to §4.6 itself, not just to a guard
  in the diff: a fix that establishes a NEW dependency triggering a stricter blast-radius tier
  inherits that tier's `requires:` obligations, and nobody re-checked them.** Finding 3: adding
  `connectivity_plus` pushed the whole batch to `platform`, which `docs/blast_radius.yaml`
  gates on `feature_flag`, and CLAUDE.md §4.6 independently mandates a kill-switch for any
  sync-touching change — the new always-on connectivity listener + periodic timer shipped with
  zero `configBox`/`kDebugMode` gating. **Add to lens 3/6's shared method: when a batch's
  overall tier is driven by ONE file (here, a pubspec dependency bump for an unrelated-looking
  fix), check that tier's `requires:` list against the WHOLE batch, not just the file that
  triggered it** — the obligation attaches to the tier, not to the triggering file.
  **Tuning 3 — lens 6, a second instance in the same pass: a doc comment's safety claim
  attributed protection to the WRONG mechanism, and two new auto-drain triggers turned a
  previously-rare race into a routine one.** Finding 4: a comment claimed `drain()`'s
  `_isDue` backoff check made overlapping calls "a cheap no-op" — `_isDue` is purely
  time-based and has zero concurrency semantics; the actual (pre-existing) safety is that both
  registered executors are independently idempotent. Harmless today, but the batch that just
  added a SECOND auto-drain trigger (making overlap routine instead of requiring a user
  double-tap) is exactly the batch that should have re-examined this claim instead of
  copy-pasting it forward. **Add to lens 6: when a diff adds a NEW trigger for an existing
  code path, re-verify any comment near that path asserting concurrency safety — a claim
  written when the path had one caller does not automatically hold with two.**
  **Tuning 4 — self_attesting_artifact (lens 10) found citation drift that then had to be
  re-derived a SECOND time, because fixing Findings 3+4 shifted the very lines Finding 6 named.**
  The reviewer's suggested corrected line numbers for Finding 6 were accurate when written and
  stale by the time they were applied, since Findings 3/4's own remediation (a new getter + two
  guard clauses) landed ABOVE the connectivity listener in the same file. **Add to the general
  fix-application method: when triage fixes findings in a batch where an EARLIER finding's fix
  could shift an EARLIER-computed line citation, re-derive citations LAST, after all other
  fixes in the pass have landed — not from the review's suggested numbers.**
  **A negative result worth keeping.** Two mutation-proof claims in the diagnose-docs
  (quote-picker's 1-of-9, train-phase-lock's 2-of-39) were independently reproduced exactly by
  the reviewer, and the sync-queue mutation the reviewer ran as a bonus check (to investigate
  Finding 7) was independently re-run a SECOND time by the author post-remediation, against the
  grown 18-test file (up from 11), reddening the same 3 assertions — confirming the fix's
  protection survived the batch's own additional changes rather than assuming it did.
  False-alarm rate 0/7 → no lens removed; lenses 3, 6, 10 extended per above.

- **2026-09-14 (e)** — blast-radius **platform** — branch `telegram-admin-bot`, Task 13 Step 8
  push-gate fix (migration 137: re-asserts the anon/authenticated revoke on
  `founder_metrics_ops()` that migrations 135/136 each omitted — caught by the FIRST full
  `flutter test` run on this branch, at pre-push, since neither review round nor the Hermes
  pass ran it locally). **3 findings (0 P0, 0 P1, 2 Medium, 1 Low); 0 false_alarm — all 3
  accepted and fixed in-batch.** Review: `docs/reviews/9765a1fbaf00-review.md`. Run as one agent
  (4 small files: a migration, a test-file diff, a diagnose-doc, a JSON ledger entry).
  **Tuning 1 — a diagnose-doc's SELF-DECLARED `blast_radius:` frontmatter field is not read by
  any gate and can silently drift from the classifier's actual computed tier — check it
  explicitly, every time, the same way lens 3 already checks a diff's OWN blast-radius
  claim.** The doc claimed `catastrophic`; `blast_radius_from_diff.dart` computed `platform`
  (migration 137 is a bare `revoke`, carrying none of the `SECURITY DEFINER` text its siblings
  135/136 do). Overstated rather than understated — no review round was skipped as a result —
  but it directly contradicted the SAME doc's own `impact_analysis` section ("no live exposure
  at any point"). **Add to lens 3's method: a diagnose-doc's `blast_radius:` field is a claim
  like any other citation — recompute it, don't read it.**
  **Tuning 2 — a line-number citation copied from a SIBLING file (not from thin air) is the
  quietest version of the stale-citation class, because the two files are similar enough that
  the copy usually happens to be right.** Migration 136's correct `CREATE OR REPLACE
  FUNCTION` line (27) was reused for migration 135's identical-shaped citation — wrong only
  because 135's header comment is 3 lines shorter (line 24 is the real one). A citation that
  is "close enough to plausible" between near-duplicate files is exactly the shape a reader
  skims past; `grep -n` on each file independently is the only check that catches it.
  **Tuning 3 — lens 6 (`guard_without_its_mirror`) found a real gap in a guard the SAME BATCH
  had just written to satisfy lens 6's own prior instance:** the new test exemption (for two
  already-applied, immutable migrations) skipped at the FILE level, before the scanner
  extracted which function(s) the file touches — so a future (improper, immutability-violating)
  edit adding a SECOND function-touch to either exempted file would have silently inherited the
  exemption too. Fixed by re-scoping the exemption to `(file, function)` pairs, checked only
  after the function set is computed. **When a fix adds an exemption/allowlist keyed on one
  dimension (here: filename) while the underlying scan operates on a FINER dimension (here:
  per-function within a file), the exemption inherits everything the finer dimension could ever
  match — check whether the exemption's own key matches the scan's actual unit of work.**
  **A negative result worth keeping, per this file's own convention:** the reviewer independently
  re-ran both of the author's mutation-proof claims (mutating migration 137's revoke line; the
  exemption's skip line) rather than trusting the diagnose-doc's assertion, and both reproduced
  exactly as claimed. It also attempted a live `has_function_privilege` re-check via Supabase MCP,
  hit a transient connection timeout on both tries, and correctly flagged the claim as
  UNVERIFIED-BY-IT rather than either asserting a defect or silently passing it — closed during
  triage by a third, successful live re-check (unchanged: anon=false, authenticated=false,
  service_role=true).
  False-alarm rate 0/3 → no lens removed; lens 3 and lens 6 extended per above.

- **2026-09-14 (d)** — blast-radius **catastrophic** — branch `telegram-admin-bot`, Task 6
  third follow-up (migration 136: `founder_metrics_ops()` extends the (c) entry's fix — adds
  `error_code is distinct from 'info'` to the `client_errors_7d` subquery, the sibling
  migration 135 already applied to `client_errors_today`; already applied live with explicit
  founder authorization). **0 findings across all 8 lenses.** Review:
  `docs/reviews/57b11b5c90cb-review.md`. Run as one agent (3 small files: a migration, a JSON
  metadata record, a manual SQL verify script).
  **Every lens's "clean" was backed by a live check or a real cross-reference, not a read of
  the migration's own prose** — `pg_get_functiondef` pulled live and diffed against the staged
  body (byte-identical modulo Postgres's canonical type spelling); `has_function_privilege`
  re-queried for all three roles rather than trusted from the header; `list_migrations`
  cross-checked against `applied_migrations.json`'s `cloud_version`; and the migration's two
  citations (086/087's exclusion pattern, 135 as the verbatim base) were each opened and
  confirmed to say what the header claims, not accepted as scene-setting.
  **Lens 6 (`guard_without_its_mirror`) — this migration is itself a mirror-fix, so the
  question was whether a THIRD site shares the same `error_code='info'` inflation bug that
  neither 135 nor 136 catches.** Found one genuinely separate counting site —
  `telegram-admin-bot/index.ts:481`'s `cmdErrors` (`/errors` command), a direct
  `.from("client_errors")` query independent of `founder_metrics_ops()` — and, per the
  in-file `R2-02` comment, it was ALREADY fixed in an earlier round of this same branch's
  review, and more completely than the migration under review (it excludes both `'info'` and
  non-failure-shaped `'event'`, where `founder_metrics_ops()` still only excludes `'info'`).
  That asymmetry is not new: it's the SAME gap the (c) entry below already recorded as
  pre-existing/P2 for 135, now equally true of 136 by inheritance — not a fresh regression,
  and correctly left unfixed by this migration's narrower, deliberately-scoped intent.
  `admin_metrics_daily`'s snapshot columns and `compute-admin-metrics-daily`'s persistence
  were confirmed to read `founder_metrics_ops()`'s own return values rather than
  re-implementing the count, so they inherit the fix rather than constituting a second miss.
  **Lens 8 (`asserted_fixture_value`) on the new SQL verify file** — the INSERT column list
  was checked against `backups/live_schema_columns.json`'s real `client_errors` columns
  (avoiding the exact 073/078 fabricated-column trap CLAUDE.md §4.9 documents), and the
  `user_id`-omission was checked against the CURRENT schema (nullable since migration 119),
  not the table's original NOT NULL definition — reading only `018_client_errors.sql` would
  have wrongly flagged this as a constraint violation. One informational discrepancy noted but
  NOT filed as a finding: 135's live-verify file recorded `baseline_7d=143` about an hour
  before 136's recorded `baseline_7d=140` on the same rolling 7-day window — a plausible
  natural consequence of rows aging out of the window (`client_errors` has no ad hoc deletes,
  only a 30-day retention cron far outside this window), not falsifiable after the fact, and
  not something either migration's correctness depends on. Recorded so the reasoning is
  visible rather than left as an unexamined number mismatch.
  False-alarm rate: 0/0 (no findings raised) → no lens removed; no lens changed. Third
  consecutive zero/near-zero-finding pass on this branch's tail of small, well-scoped,
  already-Hermes-corroborated follow-up migrations (this entry, plus (b) and (c) below) —
  consistent with, not contradicting, §4.12's "successive reviews keep surfacing new material
  issues ⇒ split" signal: these are genuinely small, independently-converged units, not a
  large unit being re-reviewed past diminishing returns.

- **2026-09-14 (c)** — blast-radius **catastrophic** — branch `telegram-admin-bot`, Task 6
  second follow-up (migration 135: `founder_metrics_ops()` excludes `error_code='info'` from
  `client_errors_today`, fixing round-2 finding R2-10 of the branch's whole-branch review;
  already applied live with explicit founder authorization). **2 findings (0 P0, 0 P1, 1 P2,
  1 P3); 0 false_alarm — both accepted, neither fixed in-batch** (the P2 is cosmetic/informational
  on a founder-only ops metric and pre-existing, not a regression; the P3 is a duplicate-sentence
  nit in a manual, non-gated verification script). Review: `docs/reviews/c0ea56c3d0e5-review.md`.
  **Tuning 2 — §3 step 3's hash-generation code block was stale for 3 years
  worth of gate history and cost this exact batch 3 needless renames.** It
  showed only the `docs/reviews` exclusion; the real gate
  (`check_code_review_pass_exists.dart`, per its own OI-162 slice 4 comment)
  has excluded `.claude/skills/code-review/SKILL.md` from the hash since
  2026-09-11. A session correcting a P2 finding kept "fixing" SKILL.md's own
  citation of the review filename to match a hash it believed SKILL.md's
  edits moved — chasing a fixed point that does not exist in the real gate.
  §3's code block now includes the third pathspec exclusion so this cannot
  recur; see this review file's own preamble for the full chronology.
  Run as one agent (3 small files: a migration, a JSON metadata record, a manual SQL verify
  script).
  **Tuning — lens 3's "verify the precedent citation, not just its existence" extension
  (established 2026-09-14 for a repo-precedent-by-name citation) generalizes to a
  precedent-by-NUMBER-RANGE citation too, and caught a real gap the diff's own author had not
  noticed.** The migration's header claims it "mirrors the exclusion pattern migrations
  086/087 already established" — true only for HALF of that pattern. 086/087 exclude both
  `error_code='event'` AND `'info'` (087 additionally re-includes failure-shaped `'event'` rows
  via an `op_type` regex, because `ErrorTelemetry.logEvent` hardcodes `error_code='event'` for a
  huge mix of benign breadcrumbs and real failures alike). This migration excludes only `'info'`.
  Reading the citation as a checkable claim rather than scene-setting prose, and then measuring
  it against LIVE data rather than reasoning from the SQL alone, is what surfaced it: `select
  error_code, count(*) from client_errors where <today> group by error_code` returned
  `{event: 4, info: 2}` at review time — `client_errors_today` reads **4** right now, on a day
  with **zero real errors**, because the `'event'` breadcrumbs are still counted. Not a
  regression (the diff doesn't add this problem, it just doesn't finish removing it), so P2 not
  P1 — but a citation that names a fix as "mirroring" a broader precedent while shipping a
  narrower one is exactly the shape lens 3's method exists to catch, and it would have read as
  clean from the SQL text alone; only running the live count against `error_telemetry.dart`'s
  hardcoded `'event'` code made it visible.
  **A second, smaller confirmation — the byte-identical-deploy claim was independently
  re-derived rather than trusted from the migration's own header/applied_migrations.json note,
  per the 2026-09-14(b) entry's standing method.** `pg_get_functiondef('public.
  founder_metrics_ops()'::regprocedure)` was pulled live and diffed against the staged file
  (identical apart from formatting); `has_function_privilege` was re-queried for all three roles
  (anon/authenticated/service_role) rather than accepting the note's stated values; and
  `list_migrations` was cross-checked against the `applied_migrations.json` entry's
  `cloud_version` field. All three held.
  False-alarm rate 0/2 → no lens removed; lens 3's citation-verification method now explicitly
  covers precedent-by-number-range, not just precedent-by-name.

- **2026-09-14 (b)** — blast-radius **catastrophic** — branch `telegram-admin-bot`, Task 6
  follow-up (migration 134: `client_errors` telemetry + a `COMMENT ON TRIGGER`, fixing 2 of the
  prior same-day review's 5 findings). **2 findings (0 P0, 0 P1, 0 P2, 2 P3); 0 false_alarm — both
  accepted and parked** (a `||`-NULL-propagation diagnostic-quality gap on a doubly-unlikely path,
  and a migration-header enum mismatch the repo's own convention already documents as unenforced).
  Review: `docs/reviews/297bae7db41c-review.md`. Run as one agent (3 small files, one a two-line
  comment fix).
  **Tuning — the reviewer independently RE-DERIVED the prior review's central safety claim against
  LIVE state rather than trusting the migration's own header prose, and that is what makes this
  entry worth recording despite finding nothing above P3.** The header claims the failure-path
  telemetry insert is "nested... so a telemetry-insert failure can never itself abort the parent
  alerts INSERT" — exactly the property 078 exists to guarantee for this trigger family. Rather
  than accept the claim from the comment, the reviewer traced PL/pgSQL exception SCOPING precisely
  for all three `client_errors` INSERT call sites, THEN cross-checked the traced structure against
  the LIVE deployed function body (`pg_get_functiondef` via MCP, confirmed byte-identical to the
  staged file) — closing the exact gap the 2026-09-04(b) entry's "a tier computed before the file
  exists is not a computed tier" lesson describes for blast-radius, applied here to a STRUCTURAL
  safety claim instead of a tier number: a claim about live behaviour is only checked once it is
  checked against what is actually LIVE, not against the file that describes it.
  **Second, smaller — a genuine confirmation that a prior review's ACCEPTED rationale, reused
  verbatim in a follow-up migration's header, does not need re-litigating from scratch, but DOES
  need checking that it was not silently weakened.** Lens 3 (`blast_radius_mismatch`) explicitly
  cross-referenced the PRIOR review's Finding 2 (the `feature_flag` rationale) rather than raising
  it fresh, verified 134 reuses it in substance without contradiction, and correctly left the
  PRIOR review's still-open Finding 1 (the whole-branch plan-review record) alone as genuinely out
  of scope for this diff. Add to lens 3's method: when a diff's header cites a PRIOR finding by
  number, verify the citation is accurate and that the rationale it points to still holds for the
  NEW diff — don't treat "already discussed" as a reason to skip the check entirely.
  False-alarm rate 0/2 → no lens removed; lens 3 extended per above.

- **2026-09-14** — blast-radius **catastrophic** — branch `telegram-admin-bot`, Task 6 (migration
  133: a SECURITY DEFINER trigger dispatching an immediate Telegram push on a critical alert).
  **5 findings (0 P0, 2 P1, 1 P2, 2 P3); 0 false_alarm — all 5 accepted, 4 fixed in-batch (in a
  follow-up migration + a direct EF comment fix, both separate commits to preserve the
  hash-pinned review identity), 1 correctly deferred to the branch's still-pending final
  whole-branch review.** Review: `docs/reviews/28213f7956e2-review.md`. Run as one agent (3
  small files).
  **Tuning — the reviewer's OWN suggested-fix for the P2 finding cited the wrong
  `client_errors` columns, and they were not an arbitrary wrong guess: they were the EXACT
  columns that caused a real prod P0 in `073_proactive_coach_promotion_trigger.sql`, later fixed
  by `078_fix_dispatch_proactive_coach_promotion_columns.sql`.** The reviewer correctly cited 073
  as the precedent this migration's header claims to follow, but wrote its suggested-fix as
  `client_errors(user_id, op_type, message, severity)` — columns that table has never had (real:
  `error_code`, `error_message`, `client_version` NOT NULL, `platform` NOT NULL). Had that
  suggested-fix been applied verbatim, it would have reintroduced 078's exact bug: because a
  `plpgsql` trigger body is never validated against real schema until it actually RUNS, the
  broken INSERT would ship silently and only fail live — and because 073's original `WHEN OTHERS`
  handler used the SAME bad columns for its own telemetry insert, the re-raised exception would
  have escaped the trigger and aborted the parent `alerts` INSERT, the identical failure mode
  078's diagnose-doc (`f4b2c9`) documents for `rank_promotions`. Caught only because the fix was
  independently re-verified against LIVE `information_schema.columns` before being applied, rather
  than trusted from the review's prose. **Add to lens 3/7's method: when a review's suggested-fix
  cites a REPO PRECEDENT BY NAME (here, "mirroring 073"), verify the precedent's CURRENT, possibly
  since-corrected form — not its original commit — before using the suggested-fix verbatim. A
  precedent that itself needed a follow-up fix (078) is evidence the ORIGINAL version is exactly
  the wrong thing to copy, and a reviewer citing it by its introducing commit rather than its
  latest form inherits the bug the follow-up exists to have fixed.** Sibling of this file's own
  2026-09-04 `latestMigrationDefining` lesson (CLAUDE.md §4.9's "last `CREATE OR REPLACE` wins")
  applied to a REVIEWER's citation rather than an author's.
  **Second, smaller — a genuine instance of the hash-fixed-point class this file's 2026-09-11
  entries already document, worth one more data point because the mitigation held cleanly this
  time.** Triaging 4 of 5 findings required staging NEW content (a follow-up migration, an EF
  comment fix) — doing so in the SAME commit as the reviewed diff would have moved the
  `git hash-object` value the gate keys on, invalidating `28213f7956e2-review.md`'s own filename.
  Resolved by committing the EXACTLY-as-reviewed diff first (re-verifying the hash matched before
  committing), then landing the fixes as a separate follow-up commit/review. `docs/reviews/` stays
  excluded from the hash by design, so the review file's OWN triage edits (marking findings
  accepted/fixed, setting `verdict: accepted`) could be made freely without this problem — only
  the code side of the fix needed the split.
  False-alarm rate 0/5 → no lens removed; lenses 3, 7 extended per above.

- **2026-09-13** — blast-radius **platform** — branch `oi153-pro-media-caps` (OI-153: the
  ai-media-proxy PRO caps moved onto the ledger + the new `founder-digest` cron EF; diagnose
  `a9d4e7`). **6 findings (0 P0, 2 P1, 2 P2, 2 P3); 0 false_alarm — all accepted, 5 fixed
  in-batch, 1 resolved by an existing pin with the refactor declined and the reason recorded.**
  Review: `docs/reviews/88cfc8594fcc-review.md`. Run as TWO context-blind agents (1-5+9/10 and
  6-8) per the 2026-09-08 split rule — 28 files.
  **Tuning 1 — lens 6's method gains a REACHABILITY question, and it produced the pass's only
  mechanism finding.** Mutation (n) — the founder-digest lifetime read filtered by
  `window_start` instead of `updated_at`, a filter that can never match, so a section renders
  "none" forever with no error — reddened **0 of 19** tests. Not because the assertion was
  wrong: because the reads sat inside the handler behind `createClient(...)` and NO test could
  reach them at all. Before mutating a guard, ask *what test can even see this line?* — if the
  answer is "none", the mutation result is known in advance and the finding is structural: pull
  the code out to where a fake can drive it. The fix here (an exported `readDigestSections`
  driven by a recording fake client) then exposed a SECOND gap in its own first version: the
  alerts read's error path was swallowed (`if (error) return []`) and only usage_counters had ever
  been failed in the test — the mirror of the fixture, not of the code. ⚠ Corollary for the
  extraction: keep every `.from("<table>")` chain literal and inline. `check_schema_column_refs`
  validates columns only inside a `.from(...)` statement window, so extracting the FILTERS into
  table-less helpers would have moved them out of that gate's input set while looking like a
  pure improvement (`feedback_green_check_input_set_width`, yet again).
  **Tuning 2 — lens 10 (`self_attesting_artifact`): the deploy-state claim in a diagnose-doc's
  `touched_layers_checked` is the highest-yield line to check live, and it should be checked
  with the Management API, not the file.** Both P1s were this shape: tier 6 said ai-media-proxy
  was "deployed, byte-identity verified" while live was v23, the PRE-fix bundle (verified by
  `list_edge_functions` + a source grep of `get_edge_function`); and three files cited a
  `test/sql/…live_verify.sql` that existed nowhere. Neither was a lie about code — both were
  template prose written before the event. **Add to lens 10's method:** for every
  `touched_layers_checked` row with `status: fixed_in_this_batch` on tiers 5/6/7 (migrations,
  EF deploy, cron), pull the live version/migration list and compare; for every path a
  `presence_only:` comment or a test header cites, `test -f` it. Gate 42 checks that
  `behavioral_test_path:` is non-empty text and never that the file exists — filed as its own
  OI in this batch's close-out (134 of 134 cited paths exist today, so it is a gap, not a live
  violation).
  **Tuning 3 — lens 6 (mutation a) — an "anchor not found" red is not a guard assertion.** The
  pre-fix shape `if (isPro && !isVideo)` reddened the T1 file only because a `_span` anchor
  vanished. The repair reads the condition of the nearest `if (` above the RPC and pins it —
  and its second mutation (a nested `if (isVideo)` inside the block, which leaves every anchor
  intact) is the one to keep running: it reddens ONLY the new assertion.
  **A negative result worth keeping.** Every literal in the new Deno test file and the mirror
  test was recomputed by hand (the author's own first draft had asserted 2026-09-11 was a
  Thursday — it is a Friday — and had already corrected it before dispatch); the Telegram
  send's error containment was traced to the outer `catch` and confirmed unreachable by a
  URL-bearing error; live ACL on `consume_quota` re-queried. 0/6 false alarms → no lens removed.

- **2026-09-13 (second entry today)** — blast-radius **catastrophic** — branch
  `oi153-pro-media-caps`, the SAME apply commit as the entry above, one deploy cycle later (v25 →
  v26/v3). **5 findings (0 P0, 2 P1, 2 P2, 1 P3); 0 false_alarm — 4 fixed in-batch, 1
  verified_clean.** Review: `docs/reviews/1214f9bbb700-review.md`. Run as two agents on the
  same 1-5+10 / 6-8 split.
  **Tuning 1 — lens 6 (`guard_without_its_mirror`) on a fix landed EARLIER THE SAME DAY, by
  THIS SAME batch, still found a real asymmetry.** Finding 1 (P1): the served-MIME
  reconciliation the entry above had JUST added closed one direction of a mislabel (video served
  as image); the pre-fetch video paywall, unchanged by that fix, still ran on the raw claim and
  paywalled a free user whose real VIDEO was mislabelled "image" — denying a legitimate free
  analysis, and making the naive fix (delete that paywall) a WORSE bug (a free-cap bypass via
  mislabel, since the sibling free-image-cap check shares the same claim gate). **The lesson: a
  same-day fix for one direction of an asymmetry is not evidence the mirror was checked — it is
  often evidence it was NOT, because the fix's own diff draws attention away from the branch it
  didn't touch.** Ask "what did NOT change in this diff that the thing which DID change assumes
  is still true?"
  **Tuning 2 — lens 2 (`function_exception_swallow`'s sibling, staged-vs-working drift) belongs
  in the standard set, not just as an ad hoc catch.** Finding 2 (P1): an on-disk gate-literal fix
  (`.limit(MAX_ALERT_LINES)` → `.limit(10)`, required because `check_unbounded_cron_reads.dart`
  reads only literals) was made and never re-staged — the INDEX still carried the defect the gate
  exists to catch. `git diff --cached <file>` catches this in one command; add it to lens 6's
  checklist as a zero-cost first step on any file the diff claims to have "already fixed".
  **Tuning 3 — a review dispatched on a batch that JUST passed its own prior B-pass still found
  2 P1s, both real.** Neither Hermes (19 findings, same day) nor the first B-pass (6 findings,
  same day, same branch) had surfaced either — both fixes they DID land (F2's reconciliation, the
  digest's own literal fix) were the exact site each new finding sits beside. **Corroborates
  §4.12's "successive reviews keep surfacing NEW material issues" signal, but for one commit
  across two consecutive B-passes rather than across plan-review rounds** — worth watching for a
  third recurrence before concluding the unit needs splitting; one instance is not yet the
  pattern.
  Finding 5 (P3, `unlistedTotals`'s sibling call sites, verified_clean): independently re-traced
  all 6 other call sites of the same count-fallback pattern and confirmed each is windowed, not
  lifetime — not a recurrence of Finding 3's bug. 0/5 false alarms → no lens removed.
  **Self-reference note, worth recording once rather than re-discovering it:** `docs/reviews/
  bc593ef17136-review.md` is a byte-identical copy of the file above, named after the STAGED
  hash as it stood after the plan-review record's own citation of this review was added — citing
  a review's filename inside the plan-review record changes the very diff the hash is computed
  over, so the name that satisfies `check_code_review_pass_exists.dart`'s exact-match rule at
  commit time cannot, in general, be the same name `bpass_review:` settled on earlier without
  solving a hash fixed-point. `bpass_review:` (checked only for EXISTENCE + `verdict: accepted`
  by `check_plan_review_record_exists.dart`) points at `1214f9bbb700-review.md`; the duplicate
  exists solely to satisfy the exact-hash gate. Two files, one review.

- **2026-09-13** — blast-radius **platform** — branch `oi-allocator` (the OI-number
  allocator: `scripts/mint_oi.sh` reserving `refs/heads/oi/N` as a remote CAS, Check
  B′/C in `check_oi_numbering_unique.dart`, the SessionStart next-free line; diagnose
  `f3a9c1`, closes OI-176). **4 findings (0 P0, 0 P1, 2 P2, 2 P3); 0 false_alarm — all
  four accepted and fixed in-batch, each with a regression test and a mutation.**
  Review: `docs/reviews/oi-allocator-bpass.md` (branch-named — the plan-review record
  is the one pointer, per the 2026-09-11 (second) entry's fixed-point lesson).
  **Tuning 1 — lens 8 gains a CARDINALITY question, and it is this batch's headline
  even though the B-pass did not find it: a per-element subprocess loop measured
  against a FIXTURE is not measured at all.** The sibling-branch exclusion ran one
  `git show` per local branch per board. Every e2e fixture has 1–2 branches; 17/17
  green, four mutations reddening exactly the named tests, two context-blind
  plan-review rounds read the loop and passed it. The real repo has **205** local
  branches: **15.7 s** per SessionStart, **24.6 s** per `--next`, against the spec's own
  2 s rule. Found by the author running the shipped hook in the primary worktree BEFORE
  dispatch (§4.12.5's "run the cheap checks first"), rewritten as one `git grep` per
  150-ref chunk (1.3 s / 4.1 s), `050e70ab`. **Add to lens 8: for any loop over a
  repo-derived set (refs, files, rows), ask `| wc -l` on the REAL repo and multiply by
  the per-iteration spawn cost; a fixture's n is never the repo's n.** Sibling of the
  input-set-width family (`feedback_green_check_input_set_width` #45).
  **Tuning 2 — lens 6 gains: "the file exists" and "the ref resolves" are DIFFERENT
  predicates, and a dispatch keyed on the second silently falls through on the first.**
  F3: `MERGE_HEAD` present but unparseable ⇒ `rev-parse --verify` null ⇒ the mid-merge
  arm never fired ⇒ the NEW working-tree arm pronounced on a tree holding both sides.
  Fixing it exposed a pre-existing blind spot on the same line: the octopus count read
  the literal `.git/MERGE_HEAD`, which does not exist in a LINKED WORKTREE (`.git` is a
  one-line file there) — so it had read 0 in every §4.13 session since 2026-08-17.
  `git rev-parse --git-path` is the answer, and the mutation that restores the literal
  path reddens exactly the worktree test. **Any gate that opens a path under `.git/`
  by name is wrong in a worktree; grep the repo's scripts for `'.git/` before trusting
  one.**
  **Tuning 3 — lens 6e: a "taken" classifier over `git push` stderr must be confirmed
  by the ref's EXISTENCE, not widened.** F4: `*"rejected"*` also matches a pre-receive
  hook or branch-protection refusal, which would have been retried as N+1 ten times
  and reported as "gave up after 10 lost races" with the real reason never shown. The
  fix is not a narrower substring — it is `git ls-remote --exit-code` on the ref, which
  IS the definition of a lost race; pinned by a fixture whose bare remote carries a
  refusing `pre-receive` hook and asserts the hook's line appears exactly ONCE. Same
  lesson as the 2026-08-11 entry (tightening a matcher never converges).
  **A NEGATIVE result worth keeping:** the reviewer verified the Vercel `ignoreCommand`
  exit-code contract against Vercel's live documentation rather than the diff's comment,
  confirmed `ls-remote` exits 0 on an empty-but-reachable namespace against a real bare
  remote, and captured REAL DNS-failure stderr for both HTTPS and SSH to prove the
  offline path does not collide with the "taken" shapes — three claims the author had
  reasoned about and not measured. It also attributed one verified claim to the wrong
  document (a spec sentence credited to CLAUDE.md) and cited a symbol name the author
  first took for an invention until `grep` found it at `oi_numbering_lib.dart:85` —
  **verify a reviewer's ATTRIBUTIONS as well as its numerics, in both directions.**
  ⚠ Process: a first dispatch of the identical brief was killed by a Sonnet
  session-limit (HTTP 429) mid-run — worktree verified clean, re-dispatched after the
  reset. The second run disclosed a stray `git push -u origin main` from a scratch
  script's variable-persistence bug, killed during the pre-push analyze; the author
  verified local `main` = `origin/main` = remote (`39111d1e`, nothing to push) and zero
  `oi/*` refs on origin. Third recorded instance of a reviewer's own shell slip
  (2026-08-25, 2026-08-30); the disclosure is the behaviour to keep, and a review
  subagent should hold no push-capable escape hatch at all.
  False-alarm rate 0/4 → no lens removed; lenses 6 and 8 extended per above.

- **2026-09-11** — blast-radius **catastrophic** — branch
  `oi162-slice4-windowed-counters`, OI-162 slice 4 (diagnose `f2c8d5`).
  **4 findings (0 P0, 1 P1, 1 P2, 2 P3); 0 false_alarm — all 4 triaged
  accepted and fixed.** Review, as of THIS episode:
  `docs/reviews/1486254681fb-review.md` (renamed from `12408db06b47-review.md`
  — the batch grew after dispatch; see that file's own "Post-dispatch
  remediation" section). ⚠ Renamed twice more after the second entry below —
  its FINAL location is `docs/reviews/3cd1891ee7eb-review.md`; this bullet is
  left naming the intermediate hash deliberately, as an accurate record of
  what THIS episode produced, not a live pointer.
  **The P1 is the SAME shape this file already recorded for slice 1 of this
  exact series six days earlier, and it recurred anyway.** The 2026-09-05
  `oi162-delete-account-counter` entry below says outright: "the keystone
  plan-review record for the branch simply did not exist yet." Slice 4 hit
  the identical gap — no `docs/plan-reviews/oi162-slice4-windowed-counters.md`
  exists, staged or committed, despite two real review rounds having run
  (`docs/audit/oi162-slice4-plan.md`, `oi162-slice4-review-continuity.md`,
  neither of which opens with the `---` frontmatter the gate parses) — and,
  being catastrophic this time (slice 1 was platform), it is missing not
  just `bpass: accepted` but `hermes: accepted` too, with zero evidence a
  Hermes pass was ever run against this branch. **Recording a lesson in this
  file does not, by itself, stop the SAME multi-slice project from repeating
  it a few slices later** — the fix that would is structural (a check keyed
  on branch name, run the moment a diagnose-doc citing that branch is
  staged), not another sentence here.
  **Second — a new nuance for the self-attesting-artifact family: a batch
  can file SOME of its own tangential discoveries as OIs and not others, and
  the asymmetry itself is the tell.** This batch's review round 2 surfaced
  two out-of-scope defects — a payment-grace-window mismatch and a dormant
  NULL-channel guard gap in an untouched trigger (`enforce_vision_analysis_
  daily_limit`'s `NOT IN` is not NULL-safe, unlike its two siblings' `IS
  DISTINCT FROM`). The first got a full `OI-182` entry with every required
  field; the second lives only in prose inside
  `docs/audit/oi162-slice4-channel-enumeration.md` with no board entry at
  all, despite the same document explicitly labelling it a
  `guard_without_its_mirror`-class defect. Nothing about the second was less
  real or less findable — it was simply the SECOND finding of the same kind
  in the same round, and the batch's own filing discipline visibly ran out
  between the two. Ask, of any batch that files ONE out-of-scope discovery
  as an OI: did it find others, and did they all get the same treatment?
  **A negative result worth keeping.** The two new contract tests were run
  live (13/13 green), and the diagnose-doc's own 6-mutation proof table was
  spot-checked byte-for-byte against the real files (4 line citations, all
  exact) rather than trusted, then independently extended with a 5th
  mutation not in their table (`RATE_LIMIT_MAX` 5→6), which reddened exactly
  the one expected assertion. The fail-open-vs-fail-closed asymmetry the
  dispatch prompt asked to confirm was traced in both files' actual control
  flow and matches the claim exactly.
  False-alarm rate 0/4 → no change to lenses 1-8.

- **2026-09-11 (second entry today)** — blast-radius **catastrophic** — same
  branch `oi162-slice4-windowed-counters`, OI-162 slice 4, second remediation
  round. Review file renamed a SECOND time (`1486254681fb-review.md` →
  `016af81ca391-review.md`), a THIRD (→ `42ed72d24303`), and a FOURTH (→
  final `docs/reviews/3cd1891ee7eb-review.md`) — not a new dispatch, but the
  `/hermes-pass` remediation this same review's own Finding 1 demanded moved
  the staged-diff hash again, and `check_code_review_pass_exists.dart`
  correctly re-blocked the commit on the STALE filename until the rename
  landed. **Tuning — the self-attesting-artifact family (this file's own
  `2026-09-08`/`2026-09-05` entries) has a THIRD member: a review file's
  identity is pinned to a MOVING TARGET (the staged-diff hash), and any
  substantive work landing after `verdict: accepted` — even work the review
  itself explicitly called for — re-opens that pin.** This is not a defect
  in the gate; re-blocking on a stale hash is exactly what stops an accepted
  review from silently certifying content it never saw.
  **The sharper half, learned by hitting it: a PROSE CITATION of the
  review's hash-named path, in any file the hash covers, can never be made
  correct — fixing the citation moves the hash the citation names.** Three
  such citations (the OI-183 board entry, the diagnose-doc, the migrations
  CLAUDE.md pitfall row) each cost one rename cycle before this was seen
  for what it is: a fixed-point problem on a cryptographic hash, with no
  solution. The fix is structural, and it is what every catastrophic
  batch since OI-72 has done, checked against `git log` on
  `docs/plan-reviews/*.md` (six of the last seven landed the record in a
  SEPARATE docs-tier commit): prose cites the plan-review record — keyed
  on the BRANCH NAME, stable — whose `bpass_review:` field is the one
  authoritative, gate-validated pointer; and that record lands in its own
  follow-on commit, where the blast radius is `feature` and the hash gate
  does not fire. **And the FOURTH rename had a different cause worth its
  own sentence: a direct `dart run check_code_review_pass_exists.dart`
  reports the hash of the index AS IT IS, but `pre-commit.sh` first
  REGENERATES and re-stages `OPEN_INDEX.md` / `INDEX.md` / `GATE_INDEX.md`
  from the board and diagnose-docs — so an `open_issues.md` edit moves the
  hash a SECOND time, only when the hook runs.** Read the expected hash
  from the hook's own failure output (or run the hook once, THEN the
  direct gate), never from a direct run on a stale index.
  `check_skill_tuning_history.dart` also fired on the
  renamed file as if newly added (it is, from git's perspective, unless the
  rename is staged as a pure rename with zero content change — this one
  carried a substantive addendum, so it is not) — a second same-day bullet
  was required here for exactly that reason; a bullet is owed per LANDED
  review file, not per calendar day or per distinct review episode.
  16 further findings from the Hermes pass (3 P1, 4 P2, 5 P3, 4
  verified_clean/false_alarm) — full detail in
  `docs/audit/2026-09-11-hermes-oi162-slice4-windowed-counters.md`, not
  duplicated here. All 16 reached a terminal state in this same batch.

- **2026-09-10 (second entry today)** — blast-radius **platform** — branch
  `realtime-pro-gate` (the e4a7c9 realtime PRO gate, cherry-picked onto a main 25
  days newer). **6 findings (0 P0, 2 P1, 3 P2, 1 P3); 0 false_alarm.** Review:
  `docs/reviews/4f6eb6532418-review.md`. **No functional defect in the code** — the
  agent ran the suite and its own mutation and confirmed the logic survived intact.
  Every finding was documentation, and one was hard-blocking.
  **Tuning 1 — NEW LENS: `rebase_semantic_drift`, for any diff whose code is old
  and whose BASE is new.** A cherry-pick or long-lived branch carries a review that
  is a statement about a DIFFERENT tree. Git auto-merging every file means
  textually compatible, not semantically correct. Brief the agent with the exact
  list of commits that touched the same files since the merge-base and make it
  answer, per commit: does this invalidate an assumption the original design made?
  Here that framing produced both P1s. **Its highest-value output was not a code
  bug at all** — it was that a pre-commit gate now FAILS on two citations the diff
  never touches, because the diff's own insertions shifted the methods below them.
  **Tuning 2 — a count-based source-grep assertion is absorbed by the file's own
  COMMENTS about the thing it counts.** From the sibling batch the same day:
  `expect('SECURITY DEFINER'.allMatches(flat).length, greaterThanOrEqualTo(2))`
  passed after a real function was demoted to INVOKER, because the file says the
  phrase FOUR times — twice in declarations, twice in prose about a past incident.
  **Zero of nine tests reddened.** This repo writes deliberately comment-heavy
  migrations, so any `allMatches(...).length` assertion over a documented file has
  the same hole. Add to lens 8: **assert the declaration, never the census.**
  **Tuning 3 — a `false_alarm` verdict records a MEASUREMENT, not a permanent
  truth.** The 2026-08-16 Hermes pass listed "migration-number collision" among 11
  false alarms on the then-correct evidence that "main added zero migrations since
  merge-base; highest is 119". Main now has 120-129, and that dismissed collision
  is exactly what this batch hit. **Re-verify a false alarm before relying on it to
  skip a check** — and prefer recording the EVIDENCE with it, which that pass did,
  and which is the only reason the staleness was detectable.
  **A NEGATIVE result worth keeping.** The agent's stated CAUSE for its blocking P1
  was wrong — it blamed four commits on main; clean main passes. The finding was
  real and the mechanism was not. It also got every line number right, which is the
  reverse of this history's usual warning. **Verify a subagent's MECHANISM as
  carefully as its numerics**; a correct finding with a wrong cause teaches the
  wrong lesson to whoever reads the review next.
  False-alarm rate 0/6 -> no change to lenses 1-7.

- **2026-09-10** — blast-radius **platform** — branch `oi172-push-result-file`
  (OI-172: a terminal push-result record for `safe_push.sh`, plus the §4.9
  verification-width row). **7 findings (0 P0, 1 P1, 4 P2, 2 P3); 0 false_alarm.**
  All accepted, all fixed in-batch. Review: `docs/reviews/08e601e60f35-review.md`.
  **NO functional defect was found in the shipped logic** — and that is the entry's
  point, because the pass still earned its keep four times over.
  **Tuning 1 — lens 10 (`self_attesting_artifact`) should run against the OI BOARD
  and any closure prose, not only ledgers and diagnose-docs.** The P1 was a
  citation in `docs/audit/open_issues.md` to
  `docs/plan-reviews/<branch>.md` — the keystone record — written *before* the file
  existed. It would have failed `check_plan_review_record_exists.dart` at the merge
  commit in CI, where the repair is a `git reset --hard` unwind. The author knew the
  record was still owed and cited it anyway while closing the board entry, which is
  the shape to hunt: **a resolution block is written at the moment of maximum
  optimism about what else got done.** Sibling of the 2026-09-05 entry, one
  document over.
  **Tuning 2 — lens 8 gains: a mutation count measured against a NARROWER run than
  the suite can only UNDERCOUNT, and therefore never looks alarming.** The reviewer
  re-ran 6 of 13 claimed legs against the full three-file suite and found 3
  undercounted by exactly one, because the author had measured each leg against the
  single file it obviously touched. **The error direction is what makes it
  survivable:** an undercount reads as a slightly weaker proof, not as a red flag,
  so nobody re-checks it — whereas an overcount would be caught immediately. Ask of
  any per-leg mutation count: *against which files was this measured, and is that
  the same set the claim is about?* Fourth instance of the input-set-width class in
  two sessions, and this one shipped **inside the batch adding the CLAUDE.md row
  about it**.
  **Tuning 3 — when a lens says "follow the precedent", check whether the precedent
  carries a defect you would be importing.** F4 (platform tier's unenforced
  `requires: feature_flag`) was fixed with a kill switch modelled on
  `.claude/.reconcile_ci.disabled`. Copying its LOCATION would have been wrong:
  **neither existing `.claude/` kill switch is listed in `retire_worktree_lib.dart`'s
  `regenerableIgnoredPaths`**, so a worktree where someone flipped one is
  unretirable until they remember to delete it. The switch shipped beside the record
  inside `.git` instead. Extends lens 9
  (`modelled_on_is_a_checkable_claim`): the claim "modelled on X" is checkable in two
  directions — does it match X, and *should* it, given what X gets wrong.
  **A NEGATIVE result worth keeping, per this history's convention.** The reviewer
  was asked to re-verify both PREDICTED-GREEN mutation legs, and both reproduced at
  exactly 0 red with the stated explanations holding. It also flagged that
  `git cat-file -t <staging-hash>` fails — correctly noting the discrepancy rather
  than silently substituting a commit sha, which is what the 2026-08-30 entry
  records a previous reviewer doing. The hash is unresolvable **by design**
  (`git hash-object --stdin` without `-w` writes no object, and the gate never
  resolves it either). **Worth adding to the dispatch protocol's step 3: say so in
  the brief, so each reviewer does not have to rediscover it.**
  False-alarm rate 0/7 → no change to lenses 1-7.

- **2026-09-09** — blast-radius **platform** — branch `oi162-slice3b-media-meter`, OI-162 slice 3b
  (diagnose `c4f9e2`). **3 findings (0 P0, 0 P1, 1 P2, 2 P3); 0 false_alarm.** All fixed in-batch.
  Review: `docs/reviews/4b31af31a792-review.md`.
  **Tuning — lens 10 (`stale_or_wrong_citation`) gains the VERIFICATION-WIDTH question, and it is
  the highest-value thing this pass produced.** Two of the three findings were stale citations, and
  the P3 is the instructive one: the author HAD run a post-rename sweep and it reported "none". The
  sweep was `grep -rn --include=*.md --include=*.yaml`, and the surviving stale reference was in a
  `.sql` file. **A verification narrower than the thing being verified returns zero and is
  indistinguishable from a clean result.** Add to lens 10: *when a finding is "I already checked
  that", ask what the CHECK's input set was, in its widest form, and re-run it without the filter.*
  In this one session that shape fired **four** times — a `lib/`-scoped grep presented as
  repo-wide; a `^\s+`-anchored warning count that missed a real warning because the line had no
  leading space; a blast-radius run whose answer was deleted by a `grep -v` filter (the build-hooks
  banner shares the result's line); and this one. Sibling of `feedback_green_check_input_set_width`.
  **Second tuning — lens 10 should also flag a citation the SAME COMMIT invalidates.** The P2 cited
  a line that was correct when written and wrong when shipped, because the diff inserted ~83 lines
  above it. That is OI-167's class, recurring here. Cheap rule, now applied: **in prose that ships
  alongside the code it cites, name the SYMBOL, not the line** — the repo's own CLAUDE.md §0 already
  warns that no gate validates numeric-line prose.
  **A NEGATIVE result worth keeping, per this history's convention:** the reviewer EXECUTED the
  test suite (16/16) and re-queried every live-data claim in the diagnose-doc rather than trusting
  it — including independently confirming `ai-media-proxy` is live at v21 and that
  `'epoch'::timestamptz` really equals the TS literal. It also traced all four requested mirror
  cases in source and reported them clean rather than manufacturing a finding. 0/3 false alarms →
  no change to lenses 1-9.

- **2026-09-11 (third entry today)** — blast-radius **account** — branch `regen-wave-unit2` (OI-166
  Unit 2: the AI-coach regen path never wrote `current_plan`, so the phase-arc
  strip rendered stale content past week 4). **6 findings (1 P0, 2 P1, 1 P2,
  2 P3); 0 false_alarm.** All fixed/disclosed in-batch. Review:
  `docs/reviews/9c7cbabe4d3d-review.md`. Run as ONE fresh agent (12 files, the
  batch's own guideline threshold for the two-agent split).
  **Tuning 1 — a NEW question for lens 10 (`self_attesting_artifact`), and this
  pass's headline finding: a claim that code was FIXED must be checked against
  the STAGED BLOB, never the working tree, even when the working tree is what
  every other tool in the session (`Read`, `flutter test`) was reading all
  along.** The author had genuinely fixed a real bug, mutation-proven it, and
  written a diagnose-doc describing the fix in detail — and never `git add`ed
  either the fix or its test. Every `Read` call, every `flutter test` run, and
  every plain-English description of "the staged diff" in the same session
  reflected the working tree, which happened to agree with the working tree's
  own edits and therefore never surfaced the gap. The reviewer caught it only
  by explicitly resetting to `git show :<path>` content before testing — the
  session's own default read path (`Read`, disk-backed test runs) cannot see
  this class at all, because both sides of the comparison it needs to make
  collapse to the same value from inside that path. **Add to lens 10's method:**
  for any diagnose-doc / commit-message / review-response CLAIM that a specific
  bug was fixed in a specific file, diff `git show :<path>` against the
  described fix — not the file on disk. Sibling of the existing "does the
  referenced artifact exist" check, one level deeper: does the referenced FIX
  match what would actually be committed.
  **Tuning 2 — lens 6 (`guard_without_its_mirror`) gains a SAME-DIFF sibling-writer
  form, distinct from its usual old-code-vs-new-code framing.** Finding 3: two
  writers performing the SAME kind of `current_plan` write, BOTH introduced or
  touched in this one diff, and only one of them inherited the zero-rows guard
  the other one exists specifically to demonstrate is necessary (the diff's own
  diagnose-doc names the guarded writer's omission as a closed P0). When a diff
  adds two writers of the same shape, diff them against EACH OTHER, not just
  each against history — a guard present in one and absent in its twin is
  invisible to a review that reads forward through the diff file-by-file rather
  than comparing siblings directly.
  **Tuning 3 — small, folded into lens 7's existing habit rather than a new
  lens: a file's OWN established defensive posture is evidence a sibling
  write-path should share it.** Finding 4: three new write-side casts threw on
  malformed input while the SAME file's pre-existing read-side reader for the
  SAME blob was explicitly documented as crash-safe. Not a new check — the
  existing "does this diff match an established pattern" instinct just needs to
  include READER-SIDE precedent as a source of the pattern, not only prior
  writer-side code.
  **A NEGATIVE result worth keeping, per this history's convention:** the
  reviewer explicitly declined to extend its own P0 finding into a claim that
  the diagnose-doc's OTHER mutation-proof claims (against a file it had not
  touched) were also false — it flagged them as merely UNVERIFIED-BY-IT rather
  than asserting a defect, and named the exact budget reason it stopped there.
  That distinction was preserved rather than collapsed: the two flagged
  mutations were independently re-run post-fix (by the author, per Finding 1's
  updated status) and reproduced cleanly — the reviewer's restraint was
  correct, not merely cautious.
  False-alarm rate 0/6 → no lens removed; lenses 6, 7, 10 extended per above.

- **2026-09-08** — blast-radius **platform** — branch `regen-wave-alignment`
  (OI-166 Unit 1: the schedule-row gate + `rawWeekNumber` extraction + the hotel
  planner's stamps, plus OI-170/171 folded in). **5 findings (2 P0, 1 P1, 2 P2);
  0 false_alarm.** Review: `docs/reviews/df96a61cf598-bpass.md`. Run as TWO
  context-blind agents with the lens set split 1-5 / 6-8.
  **Tuning 1 — SPLIT THE LENS SET ACROSS TWO AGENTS ON A LARGE DIFF, and give
  the deep lenses their own agent.** 23 files / ~2,590 insertions went to two
  agents rather than one. The 6-8 agent spent its whole budget on mutation work
  and produced both P2s by RUNNING things — it defeated the new gate on its
  first attempt with a four-line fixture, and it deleted the OI-171 line and
  watched 60 tests stay green. The 1-5 agent, freed of that, found the P0 board
  collision and the tier mismatch. Neither would plausibly have done the other's
  work inside one budget: lens 6 alone consumed 55 tool calls. The split is
  cheap and the skill should default to it above roughly 15 files.
  **Tuning 2 — lens 3 (`blast_radius_mismatch`) must READ THE `requires:` LIST,
  not just compare the tier.** The finding here was not "the tier is wrong" but
  "the tier is right and its `requires:` list was never satisfied":
  `docs/blast_radius.yaml:25` demands `feature_flag` at `platform`, and
  **nothing enforces it** — `check_blast_radius_coverage.dart` does not read the
  list (grep: 0 hits). So a platform-tier change to the sync restore path passed
  the entire gate loop green with no kill-switch. Lens 3's prompt should now
  say: resolve the tier, open `blast_radius.yaml`, and check each entry of that
  tier's `requires:` against the diff INDIVIDUALLY. A declarative requirement
  with no gate is exactly what a reviewer is for, and it is invisible to every
  other check.
  **Tuning 3 — a stale plan document is a finding, and the tell is a
  self-refuting justification.** The plan header claimed `account` and defended
  it with *"positive control `sync_workout.dart` → `platform`, so the classifier
  discriminates"* — a control valid only while that file is OUT of the diff.
  The batch later folded it IN, so the sentence proving the tier became the
  sentence refuting it, and nobody re-derived the number. Generalised: when a
  document justifies a value by naming what is excluded, check whether that
  thing is still excluded. Same family as the `part`-file analyze row in §4.9 —
  the measurement was right when taken and its input set moved underneath it.

- **2026-09-06** — blast-radius **platform** — branch `unitb-deload-reason`
  (Unit B: fix the stale deload reason, then flip `enable_deload_reason_line`).
  **10 B-pass findings (1 P0, 1 P1, 3 P2, 5 P3); 0 false_alarm.** Review:
  `docs/reviews/06d7bc7f5e28-bpass.md`. Two independent plan-review rounds ran
  alongside; between them the batch took **22 findings**, of which the author
  accepted 21.
  **Tuning 1 — lens 6 gains a MUTATION-RESULT reading rule, and it is the
  inverse of the one rule 21 already has.** CLAUDE.md warns that a mutation
  reddening for a COMPILE error proves nothing. This batch found the mirror: a
  mutation reddening **NOTHING** also proves nothing. Deleting three separate
  guards each reddened ZERO of twelve assertions, because the guards sat inside
  a method whose `catch (_) { return null; }` turned the resulting RangeError /
  NoSuchMethodError into the SAME null the tests asserted. Four assertions were
  testing the exception handler. **When a mutation reddens 0, do not record
  "already covered" — ask what absorbed it.** The structural fix is to extract
  the guarded logic into a pure function with no `catch` above it, so every
  returned value has one source; that turned 0 red into 1 red with no test
  changed. Added to rule 21 in CLAUDE.md as the third named mutation trap.
  **Tuning 2 — a new lens, `decision_boolean_as_explanation`, for any diff that
  renders COPY derived from control flow.** Round 2's only P1 was not in the
  batch's code at all: the flip made five pre-existing copy branches
  user-visible, and one of them read a decision flag (`notBackstop`) whose false
  case covers BOTH "a deload is overdue" and "none has ever been recorded". The
  wording was written for the first, so a user in block ONE was told they were
  "two blocks in". **For every user-facing string chosen by a boolean, enumerate
  what ELSE makes that boolean take that value.** A flag computed to make a safe
  DECISION is routinely false for several unrelated reasons; the decision is
  identical for all of them and the sentence is not.
  **Tuning 3 — a flip commit must review the copy it makes reachable, and the
  diagnose-doc sentence that prevented it is worth naming.** The doc asserted
  "no new copy reaches a user" one line after "the line becomes visible for the
  first time". True of the guard, false of the flip — and it exempted all five
  copy branches from a B-pass and a full round-1 review. **On any ship-dark
  flip, treat every string the flag makes reachable as new code, because for
  every user it is.**
  ⚠ **Process note for whoever dispatches these: do NOT run two reviewers
  against one worktree concurrently.** Both were told they may mutate to verify;
  they did, saw each other's edits mid-run, and each had to discount results and
  re-derive. Serialise them, or give each its own worktree.

- **2026-09-05** — blast-radius **platform** — branch `phase-arc-flip`
  (flip `enable_phase_arc` live; new ship-dark `enable_deload_reason_line`).
  **5 findings (1 P0, 2 P2, 2 P3); 0 false_alarm.** Review:
  `docs/reviews/phase-arc-flip-bpass.md`.
  **The P0 is a lens this skill did not have: TRACKING DOCS THAT ATTEST TO
  THEMSELVES.** The batch's closure ledger listed `plan_review_record:` and
  `bpass_review:` as existing artifacts, and one entry asserted in the PAST
  TENSE that a tuning entry "was appended … in this commit". None of the three
  existed or were staged. Every code lens passed; the batch would still have
  failed `check_plan_review_record_exists.dart` in CI **at the merge commit**,
  where the repair is a `git reset --hard` unwind.
  **Tuning made — a new lens, `self_attesting_artifact`:** for every path a
  staged doc CLAIMS exists — `plan_review_record:`, `bpass_review:`,
  `hermes_report:`, `behavioral_test_path:`, `flip_review_record:`,
  `contract_test_path:`, any `docs/…` pointer in a ledger — run
  `git cat-file -e :<path>` (the STAGED blob, not the working tree) and report
  every one that resolves to nothing. Also flag past-tense claims about the
  commit's own contents ("was added in this commit") whose subject is absent
  from `git diff --cached --name-only`. This is cheap, fully mechanical, and
  catches the class the code lenses structurally cannot: a diff can be perfect
  and still be un-mergeable because a doc lied about a sibling file.
  **Second, smaller tuning — lens 6 gains a UI-reachability question.** F4:
  a new debug kill-switch called `setState` in the dev panel, which rebuilds the
  DEV screen and not the screen under test, while the provider read the flag
  non-reactively. The guard was correct and unobservable. Every sibling toggle
  in that file forces invalidation via `runRolloverNow(ref)`; this one forced
  nothing. Ask of any added toggle: **what re-runs the thing it toggles?**
  A false-alarm note worth keeping: the reviewer's own P3 correctly identified
  this as a PRE-EXISTING pattern (`phaseArcProvider` has always read its flag
  non-reactively) and still flagged it, because the new toggle is what makes it
  reachable. Distinguishing "pre-existing" from "newly reachable" is the right
  call and the review made it explicitly.
  False-alarm rate 0/5 → no change to lenses 1-5, 7, 8.

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

- **2026-09-07 (b)** — blast-radius **platform** — branch `live-test-budget-docs`, a
  DOCS-ONLY diff (CLAUDE.md 4.9 row, debugging SKILL.md, OI-167). **6 findings (0 P0, 2 P1,
  3 P2, 1 P3); 0 false_alarm**, all fixed in-batch. Review:
  `docs/reviews/0acbed4f3155-review.md`.
  **Tuning — lens 8 gains the counting rule, because both P1s were miscounts inside a
  `Verified:` field: A FILTER NARROWER THAN THE THING BEING COUNTED RETURNS ZERO AND LOOKS
  LIKE PROOF.** The author's census for "which bug-class numbers are cited elsewhere"
  filtered to lines also containing `bug.?class|debugging skill`. Real citations mostly do
  not say that — one reads `2.36 (FunctionException not unpacked → masked errors)` and
  matches no keyword — so the census returned zero for five numbers and the entry declared
  them "mechanically safe to renumber". Unfiltered, **all nine were cited**. The zero was
  produced by the filter, not by the world. ⚠ **Ask what the filter EXCLUDES before citing
  its output**, and sanity-check any zero against one case you have read with your own eyes.
  Sibling of the empty-input-set rule: a command that returns nothing has two explanations.
  **Second, and this one no gate can catch — A CITATION DERIVED AGAINST THE PRE-EDIT FILE IS
  INVALIDATED BY THE EDIT THAT SHIPS IT.** The diff cited exact line numbers in the same file
  it was modifying; its own inserted block pushed every one of them down 17 lines, so they
  were correct when derived and wrong the moment the commit existed. **When a diff cites line
  numbers in a file the diff also changes, re-derive them AFTER staging — or cite the section,
  not the line.** Fixed here by dropping the line numbers entirely.
  Third, smaller: a `114-115` citation was copied forward from CLAUDE.md 7 rather than
  re-derived (real line: 110) — the 2026-09-02 entry's "a citation copied from another
  document is not a verified citation" rule, recurring, and the CLAUDE.md occurrence is still
  stale.
  False-alarm rate 0/6 -> no change to lenses 1-7, 9-10.

- **2026-09-07** — blast-radius **platform** — branch `oi162-slice3-lifetime-meters`, OI-162
  slice 3a (diagnose `f4a2d8`). **6 findings (0 P0, 3 P1, 2 P2, 1 P3); 0 false_alarm**, all fixed
  in-batch. Review: `docs/reviews/4d7054d4aa51-review.md`.
  **Tuning — lens 6 gains a rule about the REMEDIATION, not the finding: when a finding arrives
  carrying a mutation that defeated the old code, RE-RUN THAT MUTATION against the fix before
  calling it fixed.** A finding of the form *"this assertion is inert, proven by mutation M"*
  hands the author a free acceptance test, and the author's natural instinct is to reason about
  whether the new assertion is stronger rather than to execute M. Measured here: of two inert-test
  findings, the first fix reddened on re-run and **the second did not**. F2's remediation replaced
  "the guard appears somewhere above the call" with "the guard is within 200 chars of the call" —
  which reads as a real tightening and is worthless against this specific mutation, because a
  decoy guard is planted *adjacent* to the real call by construction. Proximity is not
  containment. The working form asserts that no other `if (` sits between the guard and the call.
  ⚠ **The general shape: a remediation written from the finding's PROSE inherits the finding's
  blind spot the same way a test written by the fix's author inherits the code's.** The mutation
  is the only part of a review finding that cannot be reasoned around, and it is already written
  down. Cost of ignoring it here would have been shipping a "fixed" inert test with a review
  citation attesting that it was checked — strictly worse than the original, which at least did
  not claim to have been verified.
  **Second, for lens 7 (`missing_input`), a documentation instance worth naming:** F3 was a test
  file's own SCOPE header citing a companion live-verification artifact (`slice3a_*` labels in a
  named `.sql` file) that contained **zero** occurrences of the string. One `grep -c` settles it.
  The lens is written for paths the CODE reads; a header that tells a future reader "the
  behavioural half lives over there" is the same failure with a longer fuse, because nothing
  executes it and the reader who trusts it never runs the check. **Resolved by making the claim
  true, not by deleting it** — and the new header states explicitly what those assertions do NOT
  cover, since they verify the ledger and would pass unchanged against the pre-fix Edge Function.
  False-alarm rate 0/6 → no change to lenses 1-5, 8-10.

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

- **2026-08-15** — blast-radius **platform** — branch
  `claude/debugging-stuck-issue-89b2e9` (e4a7c9, the realtime PRO gate).
  **1 finding (1 P0, 0 P1, 0 P2); 0 false_alarm.** Fixed in-batch. Review:
  `docs/reviews/realtime-pro-gate-bpass.md`.
  ⚠ **BACKFILLED 2026-09-10.** This entry was owed on 2026-08-15 and never
  written; the review file sat on an unmerged branch for 25 days, so
  `check_skill_tuning_history.dart` — which fires on a review file being ADDED —
  had nothing to fire on until the cherry-pick. That is the gate working exactly
  as designed and also the proof of its one blind spot: **a review that never
  merges is a review whose lesson never enters the skill.** The entry is dated to
  the review, not to the backfill, because the gate matches on `reviewed_at`.
  **The tuning — lens 6 (`guard_without_its_mirror`) gains its sharpest instance
  yet: the ANTI-FLOOD MECHANISM RE-CREATED THE FLOOD.** The fix added a latch so
  a free user logs `realtime_subscribe_skipped_free_tier` once per transition
  rather than once per resume. The latch was reset inside `unsubscribeRealtime()`
  — and `day_rollover_service` calls that on EVERY `AppLifecycleState.paused`. So
  the latch re-armed on every background/foreground cycle and the event re-fired
  on every resume: an Edge Function invocation plus a `client_errors` row, across
  essentially the whole free population. **Bug-class 2.13 reintroduced by the
  very mechanism written to prevent it, inside the fix whose own diagnose-doc
  names 2.13 as the thing to avoid.**
  **Why the shipped test could not see it, which is the transferable part:** the
  case named "the skip is logged ONCE" called `subscribeToRealtimeSync()` three
  times **with no pause between them**. That is not the production call pattern.
  The test was written from the same mental model as the code and exercised the
  same half — precisely what lens 6 says never to accept as evidence. The
  reviewer reproduced the defect with a throwaway probe first
  (`Expected: <1> Actual: <5>`), then re-measured it as a mutation.
  **Rule to carry forward: when a fix adds a latch, a cache, a debounce or a
  once-flag, find every RESET of it and name the lifecycle event that triggers
  that reset.** A latch is only as correct as its clear condition, and the clear
  condition is usually written somewhere the diff does not touch. The repair here
  moved the reset out of `unsubscribeRealtime()` into `_onUserChanged` alone: the
  latch means "I have already reported that THIS user is unentitled", so the only
  thing that may clear it is the user changing.
  False-alarm rate 0/1 → no change to the lens set.

- **2026-09-13** — blast-radius **platform** — branch `oi189-plan-end-bound` (OI-189: every
  phase-layout writer stops at `plan_end`, every regen sweeps rows already past it, every window
  move pushes `plan_json` immediately; diagnose `b9e4d1`). **11 findings (1 P1, 6 P2, 4 P3); 1
  false_alarm (9%).** 7 fixed in-batch (3 mutation-proven: M20/M21/M22), 2 correctly scoped OUT as
  already-tracked residuals (OI-190, a new OI-174 bullet), 1 escalated to the founder (unresolved
  as of this entry), 1 false_alarm (informational, no defect). Review:
  `docs/reviews/oi189-plan-end-bound-bpass.md`. Run as TWO agents — reviewer A the 8 read-only
  lenses, reviewer B the 2 mutation lenses (6, 8) dispatched only AFTER A returned, so no mutating
  tree was ever shared between them (this skill's own dispatch-protocol step 0 concern, applied to
  the REVIEWERS this time rather than to author/reviewer handoff).
  **Tuning 1 — lens 8 (`asserted_fixture_value`) gains: a census that "gets a smaller number" on
  independent reproduction is not automatically the ORIGINAL claim being wrong.** Reviewer B
  reproduced the diagnose-doc's "92 files, 849 tests" census with its OWN best-effort basename
  guess (the 8 touched `lib/` files + the test file = 9 terms) and got 87/784 — smaller, still
  green, and reported as a discrepancy. The original 92 was in fact CORRECT; the missing tenth
  basename was `workout_schedule_service.dart`, the FACADE the batch deliberately does NOT edit
  **A "smaller but still
  green" reproduction of a census claim is not proof the claim was inflated — it can just as
  easily mean the reproducer's input set was narrower than the original's.** Same family as this
  history's repeated input-set-width lessons, one direction further: here it was not the ORIGINAL
  claim that undercounted, it was the VERIFICATION attempting to check it. Fix: name every
  basename a census claim used, in the claim itself, not just the resulting numbers.
  **Tuning 2 — lens 6 (`guard_without_its_mirror`) gains: a guard's own justifying COMMENT is a
  checkable claim, and "the mirror is out of scope" is not the same as "the mirror doesn't
  exist."** Two separate P2 findings in this pass (B-1, B-2) were guards whose own doc-comment
  asserted safety for a case the guard's author had not actually traced: `pausedForSimulation`'s
  comment claimed "cloud catches up at the next weeklyFullSync, as before" for a code path
  (`simulation_service.dart`'s year-sim) that NEVER calls `weeklyFullSync` at all — the comment
  was true for the app's real users and silently false for the one caller class this unit's own
  guard was written to protect. **When a guard's comment names WHY the mirror case is safe, verify
  that reasoning against the mirror caller specifically — a comment can be accurate for the common
  case and false for an edge case the guard itself newly created.**
  **Tuning 3 — a NEW instance for the "extract to a pure function" pattern this history has used
  before (2026-08-20's label-ternary entry): TWO widgets carrying a BYTE-IDENTICAL private method
  is itself the tell that neither was ever testable, and it is cheap to check BEFORE trusting
  "the diff duplicates X, but both copies are correct" as a clean lens-9 result.** Reviewer A's
  lens 9 check (`diff <(...) <(...)` on both widgets' `_phaseNote`/`_dayLabel`) correctly found
  them identical and reported it as CLEAN — technically accurate, but it stopped one question
  short: identical AND untestable is worse than either alone, since a future edit to one copy and
  not the other would drift silently with nothing to catch it. Lens 9's method note now adds: when
  a "modelled on X" check finds true byte-identity between two PRIVATE, per-class copies, that is
  itself a finding (extract + test), not merely a clean result.
  **A NEGATIVE result worth keeping, per this history's convention:** reviewer A independently
  re-derived the plan's "review_rounds: 5" claim by counting the dated round headers in the Review
  log itself, rather than trusting the plan-review record's frontmatter number — and it matched.
  Both prod censuses were also re-run live, read-only, and matched exactly. Recording a confirmed
  claim is as much the lens's job as catching a wrong one.
  False-alarm rate 1/11 ≈ 9% → well under the 30% threshold; no lens removed. Lenses 6, 8, 9
  extended per above.

- **2026-09-14 (c)** — blast-radius **catastrophic** — branch `telegram-admin-bot`, the F2-F13
  fix-response commit for a separate whole-branch review's findings (touches
  `_shared/cron_auth.ts`, catastrophic by path in `docs/blast_radius.yaml`, even though the
  change to it — exporting a previously-private `timingSafeEqual` — is behavior-preserving for
  its existing callers). **1 P2, 1 P3; 0 false_alarm; both accepted and fixed in the same
  commit.** Review: `docs/reviews/014866ecac87-review.md`.
  **Tuning — lens 8 (`asserted_fixture_value`) caught a review-writer's OWN comment repeating an
  unverified claim, not just a test's asserted value.** The fix-diff's code comment justifying
  the `/cron` 7-day-window fix claimed a cleanup function "ALWAYS SPARES each function's most
  recent row" — plausible-sounding, written by the same author who wrote the fix, and false: the
  live function body spares exactly ONE row globally, not one per function. This is the same
  class this history has flagged before (a review's own suggested-fix repeating a stale claim,
  2026-09-14 (b)'s entry) but one level earlier — here it was the FIX's own justification, not a
  reviewer's suggestion, and it survived because nobody had re-read the cited function's live
  body since writing the sentence. **Any comment citing a named function/migration's behavior as
  the reason a fix is safe is itself a claim in asserted_fixture_value's scope — verify it
  against the live body, not just the test's literal values.** The deeper defect (the cleanup
  function itself only sparing one row, not per-function) was correctly NOT fixed in the same
  diff — filed as OI-199, since it is separate pre-existing infrastructure (migration 109
  predates the branch) with its own blast radius and testing needs. Distinguishing "the comment
  is wrong" (fix now) from "the underlying system has a gap" (file it) kept the diff from scope-
  creeping into an unrelated migration under review-response pressure.

- **2026-09-16** — blast-radius **account** — branch `email-confirm-ux`, the B-pass on the
  signup-confirmation-link feature (new `/confirm` screen + Android App Links). **7 findings (2
  P1, 2 P2, 3 P3); 0 false_alarm — all 7 accepted** (5 fixed in code, 1 resolved via
  documentation + a filed OI rather than an unscoped UX redesign, 1 recorded as pre-existing
  architecture needing no action). Review: `docs/reviews/email-confirm-ux-bpass.md`.
  **Tuning — verifying a framework-internals claim means reading the installed PACKAGE'S OWN
  SOURCE, not reasoning from how the library is generally believed to behave.** Finding 1's whole
  severity rested on whether go_router's `pageKey` includes the query string — the reviewer read
  `go_router-17.2.3/lib/src/match.dart:227-292` directly and confirmed
  `pageKey: ValueKey<String>(newMatchedPath)` never touches `uri.query`, and independently
  confirmed `AndroidManifest.xml`'s pre-existing `launchMode="singleTop"` rather than assuming it.
  Lens 6 (`guard_without_its_mirror`) already asks to "verify every claim against code + live
  state", but this pass is worth citing because the claim being verified was about a THIRD-PARTY
  DEPENDENCY's internals, not this repo's own code — the temptation to reason from memory of "how
  go_router generally works" is exactly the shape a subagent hallucinates most fluently
  (debugging skill bug-class 2.9). The author independently re-verified the same two claims
  post-review (both confirmed) before trusting the fix's design on them.
  **A second pattern worth keeping, not tuning:** the review ran the mutation test ITSELF
  end-to-end (baseline green → neuter the guard → confirm exactly the two expected tests redden
  for a genuine assertion failure, not a compile error → revert → confirm byte-identical) rather
  than trusting the dispatch brief's characterization of what the test would show. No lens
  changed; a 0% false-alarm rate here is a data point, not evidence a lens is under-firing.

- **2026-09-16 (b)** — blast-radius **platform** — branch `cron-ai-removal`, the B-pass on the
  Gemini-removal batch (9 cron/prediction Edge Functions converted from AI calls to deterministic
  templates / real trend math, after this batch's own 4-round plan-review chain caught 3 unrelated
  defects earlier). **6 findings (2 P1, 1 P2, 3 P3); 0 false_alarm — all 6 accepted**, but only 4
  fixed in-batch: Finding 2 (unbounded regression forecast, reproduced exactly via `deno run`
  against the two cited fixtures) and Findings 3/5/6 (stale comments/prose) fixed directly;
  Findings 1 and 4 resolved via a founder decision + 2 filed OIs (OI-210, OI-209) rather than
  in-batch code changes. Review: `docs/reviews/247d945d1ba0-review.md`.
  **Tuning — `blast_radius_mismatch` (lens 3) caught something wider than a tier-classifier
  disagreement: it questioned whether the touched code has ANY live caller at all.** Finding 1
  found that `future-prediction` — roughly a quarter of this batch's commits — has zero confirmed
  callers anywhere in the shipped app (no client call site, no cron schedule, not in
  `CRON_REGISTRY.md`), while the actual live prediction surface calls a completely different,
  untouched, still-Gemini-calling function. That's a reachability question, not a tier
  question — the lens's own name and worked examples so far have been about a diff's blast-radius
  TIER disagreeing with the classifier, not about whether a function is reachable at all. Worth
  keeping the lens's scope explicitly this wide: a batch can be internally correct and still not
  achieve its stated goal if the code it hardens is never invoked.
  **Second pattern, a recurrence of the email-confirm-ux entry's lesson above, not a new one:**
  Finding 4's suggested fix (widen a parser regex) was drafted, then found to surface 14
  pre-existing violations in subsystems this batch never touched, against a gate
  (`check_sot_registry_parity.dart`) that runs unconditionally on every commit repo-wide. Landing
  it half-done would have failed pre-commit for every future commit until all 14 were cleared — a
  worse outcome than the finding itself. Reverted; filed as OI-209 instead. **A review's suggested
  fix is a starting hypothesis, not an instruction — verify its OWN blast radius (run the widened
  check, count what turns red) before applying it, the same discipline this skill asks of the
  findings themselves.**
