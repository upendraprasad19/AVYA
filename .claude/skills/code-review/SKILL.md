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
   - **Moved-prose sub-check (2026-09-29, context-lean).** When the diff MOVES text between files, ask of the OLD location: *what enforcement swept it?* A full-sweep gate keyed on file names (e.g. `check_no_deferral_euphemism.dart`'s `_governingDocs()`) goes blind to text relocated to a file it does not list, while its diff-scoped half still looks healthy. Also check the tier (`docs/blast_radius.yaml`) of the NEW location — binding prose that was `platform` inline can land in a `feature` doc.
2. **function_exception_swallow** — for every `.functions.invoke(` in the diff, confirm catch + `e.status` + `e.details` is used. Source: `feedback_function_exception_class.md`.
3. **blast_radius_mismatch** — `docs/blast_radius.yaml` says path `X` is tier `T`. Does the diff treat it that way? E.g. catastrophic-tier changes must have rollback documented.
4. **secrets_in_tree** — credential-shaped literals (`sk-`, `rzp_live_`, `AKIA`, `-----BEGIN`) anywhere in the staged diff. Source: `feedback_secrets_pattern_audit_before_first_push.md`.
5. **unawaited_no_error_sink** — every `unawaited(` in the diff has either an inner `.catchError` or sits inside a function with declared error sink. Source: `feedback_observability_silent_drop.md`.
   - **Refactor-onto-a-shared-helper sub-check (2026-09-27, 3 instances in one batch).** When a diff moves N per-domain call sites onto one shared helper (e.g. `SyncSkipIndex.pushIfChanged`), the helper's OWN handling is not a substitute for what each site did on top of it. Take the pre-change file (`git show <base>:<path>`) and diff the SET of per-site extras before vs after: every `_reportSyncFailure(<opType>)` / `recordNonFatal(<reason>)` op-type string, and every inline guard (e.g. the literal `ownerChangedSince(` sink guard a contract test pins adjacent to each write). Any member missing afterwards is a finding, even if the helper "already does something similar". Instances: day-swapper Task 13 (exlog/nlog failure reports dropped), Task 16 (`upsert_template_exercise` report dropped), Task 17 (inline sink guard dropped, caught only by the full `test/contracts/` run), Task 17 again (per-table opTypes `upsert_custom_exercise`/`upsert_custom_food` collapsed into one generic `sync_custom_items` string — the 4th instance in the same batch; fixed in the Task 17 fix round, `b503bcd6`/`745fdb98`, with a coordinator-found MIRROR gap: the fix's own `if (failed == 1)` reported only the first failure per pass, so two different tables failing in one pass under a shared index would report only one — closed with a distinct-opType-once report, diagnose `docs/diagnoses/2026-09-26-sync-write-amplification-a9d3f6.md`).
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
   git diff --cached -- ':(top)' ':(top,exclude)docs/reviews' ':(top,exclude).claude/skills/code-review/SKILL.md' ':(top,exclude).claude/skills/code-review/tuning-history.md' | git hash-object --stdin
   ```
   then truncate to 12 chars. Three details are load-bearing and this step used to document
   only two — corrected 2026-09-14, telegram-admin-bot batch, after a session chased a
   FALSE hash-fixed-point across 3 renames believing SKILL.md's own content moved the
   hash (it does not — `check_code_review_pass_exists.dart`'s real exclusion set already
   dropped SKILL.md too, per the OI-162 slice 4 addendum that `tuning-history.md` documents at length; this step's code block had simply never been updated to
   match):
   - It is git's **sha1 `hash-object`**, not `sha256`.
     `scripts/check_code_review_pass_exists.dart` has always used `git hash-object`, so
     a review named by following the old text could never match. (Found by round-1B
     review of the gate-input-family batch, 2026-07-27.)
   - `docs/reviews/` is **excluded** from the hash (OI-72, same batch). The gate now
     reads the review from the STAGED blob, so the file must be `git add`ed — and
     without the exclusion, staging it would move the hash and rename the very file it
     is meant to satisfy.
   - `.claude/skills/code-review/tuning-history.md` is **excluded too** (2026-09-29,
     context-lean batch): the Tuning history moved there out of SKILL.md, so the
     required same-commit entry is now staged in THAT file. Same reasoning as the next
     bullet; the command above has FOUR pathspecs and the gate uses the same four.
   - `.claude/skills/code-review/SKILL.md` is **also excluded** (OI-162 slice 4
     addendum, 2026-09-11) — its own §5.1-required tuning-history entry must land in
     the SAME commit as any new review file, so without this exclusion staging THAT
     would move the hash exactly the way staging the review itself would have, with no
     clean iterative fix. Use the four-pathspec command above, not the two-pathspec
     is meant to satisfy.
   - **`docs/plan-reviews/` is NOT excluded, and citing this review's filename from
     there is a fourth hash-fixed-point source** (found 2026-09-21,
     `observation-batch-and-digest-redesign` batch, Round 2): the plan-review
     record's `bpass_review:` field must name this file, but staging that
     citation moves the hash the citation names, exactly like staging
     `docs/reviews/` itself would if it weren't excluded. Unlike the review file
     and this SKILL.md, the plan-review record is NOT hash-excluded by design —
     excluding it would let the record's OWN content (branch, verdict,
     review_rounds) go unreviewed as part of "the diff". **Break the cycle by
     landing the plan-review record in its own separate, later commit** (this
     file's own 2026-09-11 "second entry today" precedent, generalized): the
     catastrophic-tier code commit's review file settles to a stable name with
     `docs/plan-reviews/` left OUT of that commit entirely, then the
     plan-review record — citing that now-stable name — lands as its own
     small, typically feature-tier follow-on commit. `check_plan_review_record_exists.dart`
     only requires the record to exist on the branch BY THE MERGE COMMIT
     (keyed on branch name, not staged-diff hash), so this split is always safe.
4. **Dispatch a FRESH Sonnet subagent** via `Agent({subagent_type: 'general-purpose', model: 'sonnet', ...})` with:
   - The diff inline (or list of changed files to Read)
   - The 6 lens prompts
   - Explicit instruction: "find bugs, do not validate; if you find nothing, list what you specifically checked and why each lens returned clean"
   - Output schema (the markdown above)
   - An EXHAUSTIVE list of the commands the reviewer may run (read-only `git`, file reads, the named `flutter test` file(s), `flutter analyze lib/`), stated as exhaustive, plus an explicit ban on `dart run scripts/*`, `scripts/*.sh` and every network tool and database statement (§6: a class such as "gates that only read" is not enforceable by its reader). A lens-6 reviewer that must mutate files also gets the exact files it may touch and the backup / restore / sha256 protocol; run it AFTER the fixes from any earlier reviewer, on the post-fix tree.
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

After each invocation, count `false_alarm` findings as a percentage of total. If > 30% on a single pass, that lens is too noisy. Update the lens prompt OR remove the lens entirely. Document the tuning by appending an entry to `tuning-history.md` (same directory) under its `## 7. Tuning history` heading.

## 6. Anti-patterns (DO NOT)

- Pass conversation context to the subagent. It must be FRESH — context-blind reviewers catch what the writer missed.
- Default to "no findings found" when uncertain — force structure ("I checked X with grep Y, returned 0 hits").
- Skip the `verification:` field. Every finding must have a one-line verification command.
- Bundle this with `/hermes-pass`. That's a different skill (per-batch, all 53 lenses, Opus, slower).
- Tell a reviewer it may "run the gates that only read". `scripts/check_*.dart` includes gates that POST SQL to the LIVE project (`check_onconflict_live_arbiter.dart`). Name the exact commands a reviewer may run, and say "no writing statement, even inside BEGIN…ROLLBACK". 2026-10-03: a reviewer swept the glob and the live arbiter ran (rolled back, 0 residue rows).

## 7. Tuning history

The full history lives in [`tuning-history.md`](tuning-history.md) (moved out of this file
2026-09-29 to keep the skill's per-invocation load small). **Append new dated entries there**, as
`- **YYYY-MM-DD** - blast-radius ...` bullets under its `## 7. Tuning history` heading, naming the
review file's basename in the entry. Read it on demand (grep the branch or lens name); do not load
it whole. Gate: `scripts/check_skill_tuning_history.dart`.
