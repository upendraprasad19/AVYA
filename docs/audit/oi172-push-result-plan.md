# OI-172 push-result file + the §4.9 verification-width row

**Branch** `oi172-push-result-file` · **v4, post-round-3** · tier **platform** (both halves, computed:
`blast_radius_from_diff.dart scripts/safe_push.sh test/scripts/safe_push_test.dart` → platform;
`CLAUDE.md` alone → platform)

Two owed items from the 2026-09-08/09 slice-3b session, batched because both are platform, both
are discipline infrastructure, and both trace to the same session.

---

## 0. ⚠ A CORRECTION TO THE JUSTIFICATION I GAVE THE FOUNDER

I said the result file *"would have turned a `ps` forensics pass into one `cat`."*
**Reading the actual control flow shows that is not true as stated, and the plan is weaker for it
than I claimed.**

Yesterday's incident had the push **still running** when I investigated. No terminal verdict
existed yet, so a terminal-verdict-only file would have been **absent**, and I would still have
needed the lock holder + `kill -0`. The claim described a benefit the design as pitched does not
deliver.

Two consequences, both folded into this plan rather than glossed:

1. **The design must include a pre-push `STARTED` record carrying the pid**, or it does not address
   the incident that motivated the OI at all. With it, yesterday becomes `cat` + one `kill -0`
   instead of reading the lock's `holder` file and then re-establishing liveness by hand.
   ⚠ **Bounded to what is actually recorded** (review round 1, F5): OI-172
   (`open_issues.md:3409-3423`) documents recovering pid 86281 from the holder file and nothing
   further, so the `ps` and `git ls-remote` steps I originally cited rest on unlogged memory and are
   NOT claimed here. A real improvement, and a smaller one than I sold.
2. **The genuinely unique value is the POST-HOC record**, and that is now verified rather than
   assumed: `git_lock_release` (`_git_lock.sh:174-189`) `rm -rf`s the lock dir and is wired to
   `trap … EXIT HUP INT TERM` (`:257-260`), so on any normal or signalled exit **the holder file is
   gone**. The lock answers *"is one in flight right now"* and can never
   answer *"what happened"*. Today nothing does. That is the gap worth closing.

## 1. Bug-history (§4.1.5) — three prior instances, and one of them nearly ate this fix

Grepped `docs/diagnoses/INDEX.md` + the retirement lib before designing anything.

| prior art | what it forces on this plan |
|---|---|
| **`INDEX.md:45`** — *"A tool that WRITES INTO the worktree made the worktree permanently unretirable, **for the third time**."* `safe_push.sh`'s LANDED path already arms `.claude/.ci_reconcile_pending.jsonl` into whichever worktree pushed, and `retire_worktree_lib.dart` treats any unlisted gitignored file as PRECIOUS. | A `.claude/.last_push_result` in the worktree would be **instance four**. This is the single most important finding of the planning pass, and it is why §3 moves the file out of the worktree entirely. |
| **`retire_worktree_lib.dart:291-297`** — `.ci_reconcile_pending.jsonl` is listed **with its `.tmp` mirror**, because `_writeState` writes `$path.tmp` then renames, so a process dying between leaves a file with the identical blocking property. *"Fixing only the file that was REPORTED would have left the same bug reachable by a narrower path."* | Any atomic tmp+rename write owes the list TWO entries, not one — if it lands in the worktree. |
| **`INDEX.md:189`** (`d4f9b2`, 2026-08-11) — `safe_push.sh` *"exits 0 having verified nothing whenever `git ls-remote` cannot"* reach the remote. | This is where exit code **2 / UNVERIFIED** came from. The record must carry that state distinctly; collapsing it into FAILED re-creates `d4f9b2`. |
| **`INDEX.md:122`** — the bad-news-vs-no-news class (a deploy smoke tolerating 401 printed "Smoke OK" over a dead function). | The reader contract below must never let *absent* read as *failed*. |

**Recurrence: YES**, and the class is `feedback_bad_news_vs_no_news` + the write-into-the-worktree
family (OI-128 → `b4d7e9` → `INDEX.md:45`). Cited in the diagnose-doc.

## 2. Writers and readers by file:line (§4.1)

**`scripts/safe_push.sh` (201 lines) — EIGHT exits, only FOUR are verdicts about an attempted push:**

| line | exit | meaning | write a record? |
|---|---|---|---|
| `:58` | 1 | not a git repo | **NO** — no push attempted |
| `:60` | 1 | `cd "$REPO_ROOT"` failed | **NO** — same |
| `:63` | 1 | **`git_lock_acquire "safe_push"` failed** — another op holds the lock, or a stale one does | **NO** — same, and it is the one most likely to be MISREAD as a push failure |
| `:78` | 1 | could not resolve local ref for branch | **NO** — same |
| `:167` | 0 | **LANDED** (remote ref observed at local tip; messages at `:152`/`:154`) | **YES** |
| `:176` | 1 | **FAILED** — `git push` returned non-zero | **YES** |
| `:189` | 2 | **UNVERIFIED** — push exit 0, remote unreachable on BOTH probes | **YES** |
| `:201` | 1 | **FAILED** — git exit 0 but the remote ref did not move | **YES** |

⚠ **Writing a FAILED record at `:58`/`:60`/`:63`/`:78` would be a lie** — it would tell a reader a
push failed when none was attempted. Those four are deliberately silent, which creates the staleness
hazard §4 closes. `:63` is the sharpest case: "another push is already running" and "this push
failed" are opposite facts, and the exit code is `1` for both.

**Readers.** ⚠ **This changed in v4, and it is the most substantive thing any review round found.**
The plan through v3 shipped the reader as **prose in §4** and a test that invented its own
stand-in — so `case 10` asserted that a reader authored inside the test file agreed with a contract
authored by the same person, and proved nothing about any real caller (round 3, F2). A prose-only
contract is also exactly the shape §4.13 point 6 names: *everything with a gate holds, everything on
intention decays.*
- **`scripts/push_result_lib.dart` (NEW)** — pure `parsePushResult(String) → PushResult` +
  `classify(record, wantRef, wantSha) → landed | failed | unverified`. No file I/O, so it is unit
  testable without a repo. **This is the one place the contract lives**, and every future reader calls
  it instead of re-deriving §4 from prose.
- a human after an interrupted push (yesterday's case) — `cat` the file, or run the lib
- `scripts/reconcile_ci.dart` (SessionStart) — a possible future consumer; not wired here, and the
  format deliberately does not foreclose it
- no gate reads it, by design (§8.5)

**Precedent, not invention:** `scripts/ci_reconcile_state_lib.dart` is this exact shape already — a
pure lib for the gitignored file `arm_ci_reconcile.sh` writes, with the I/O in `reconcile_ci.dart` and
a `test/scripts/ci_reconcile_state_lib_test.dart` beside it. Same author-shell / pure-reader / own-test
split, one directory over.

**`scripts/_git_lock.sh`** — provides `git_lock_acquire` / `git_lock_release`. Verified by reading it,
because the plan's design rests on it:
- The lock key is **`$(git rev-parse --git-dir)/.safe_git_op.lock`** (`:203`), and its header at
  `:19-31` states the choice deliberately. ⚠ **`--git-dir` is NOT `--git-common-dir`.** Measured in
  this worktree: `--git-dir` = `…/.git/worktrees/oi172-push-result-file`, `--git-common-dir` =
  `…/.git`. So **the lock is per-worktree when run from a linked worktree** and only collapses onto
  the shared dir when run from primary. Two linked worktrees can push CONCURRENTLY — the lock does
  not prevent it and is not meant to.
- `git_lock_release` (`:174-189`) **`rm -rf`s the lock directory**, and it is wired to
  `trap … EXIT HUP INT TERM` (`:257-260`). So on any normal or signalled exit the holder file is
  **gone**. It answers "is one in flight right now" and structurally cannot answer "what happened".
- **Not modified by this plan.** Four review rounds killed its auto-reclaim (`:78-117`); nothing here
  needs to touch it.

## 3. DESIGN DECISION — where the file lives

**Option A — `.claude/.last_push_result` in the worktree.** Matches the `arm_ci_reconcile.sh`
precedent. Costs: a `.gitignore` entry, **two** `regenerableIgnoredPaths` entries (file + `.tmp`),
and it joins the class that has now fired three times. It also inherits the exact defect the
ci_reconcile comment documents: the path is worktree-relative, so a reader in the primary worktree
cannot see a result written in a linked one — and the linked worktree is precisely the one nobody
opens again.

**Option B — `$(git rev-parse --git-dir)/.safe_push_result`. RECOMMENDED.**
Note the flag: **`--git-dir`, the same key the lock uses**, not `--git-common-dir`. I drafted this
row as `--git-common-dir` and it was wrong; see the correction below, which is the reason the
recommendation is what it is.
- It sits **beside `.safe_git_op.lock`** — literally the same directory, by the same
  `git rev-parse` call. Not a new location for coordination state; the existing one.
- It is **inside `.git`, not the working tree**, so `git status --ignored` never reports it and it
  **cannot** trip the retirement predicate. No `.gitignore` entry, no `regenerableIgnoredPaths`
  entries, no `.tmp` mirror entry. The write-into-the-worktree class is *dodged*, not managed.
  Proof this is not theory: `.safe_git_op.lock` has lived there since 2026-08-03 and has never
  blocked a retirement.
- **Writes to it are serialised by the lock that already exists**, because it shares the lock's
  exact scope. One writer at a time, for free, with no new concurrency reasoning.

**Why NOT `--git-common-dir`, the version I first wrote.** It looks better — one path, visible from
every worktree — and it is worse, for a reason only visible after reading `_git_lock.sh`: the lock
is per-`--git-dir`, so it does **not** serialise pushes from two different worktrees. A single
shared result file is therefore racy exactly when two sessions are active, which §4.13 treats as
the normal state. My draft justified the shared file with *"the lock serialises pushes repo-wide"* —
**that claim is false**, and it was the load-bearing half of the argument.

**Residual of B, stated:** a reader standing in the PRIMARY worktree cannot see a linked worktree's
result without enumerating `git worktree list`. Accepted, because the reader who needs it is the
session that pushed, standing in that worktree — and it is the same scope the lock has always had,
so nobody has to learn a second rule. `git worktree remove` deletes the record along with the
worktree, which is coherent: retirement requires nothing unpushed, so no open question survives it.

## 4. The record, and the reader contract

Plain `key=value` lines — shell-writable, greppable, no `jq` dependency, unlike the existing
`.jsonl` queue:

```
result=STARTED|LANDED|FAILED|UNVERIFIED
exit=<0|1|2|->            # '-' while STARTED
branch=main
ref=refs/heads/main
remote=origin
local_sha=<sha at push time>
remote_sha=<observed sha, empty for FAILED/UNVERIFIED>
pid=<pid of the safe_push process>
started=<ISO8601>
ended=<ISO8601, empty while STARTED>
worktree=<abs path the push ran from>
verified_ref=<the ref the probe ACTUALLY queried, e.g. refs/heads/main>
reason=<one line, only for UNVERIFIED/FAILED>
```

⚠ **`verified_ref` exists because of the tag bug in §8.4** (round 3, F4). `probe_remote_sha()`
hardcodes `refs/heads/$BRANCH`, so when `$BRANCH` is not a branch the probe looks in the wrong
namespace and the script reports FAILED for a push that landed. Recording the ref that was *actually
queried* makes that self-diagnosing — a reader sees `verified_ref=refs/heads/v1.2.3` and knows
immediately why the verdict is untrustworthy. This is contained entirely to the new writer: it changes
**no** verification semantics in `safe_push.sh`, and the record still reports the verdict the script
reached rather than silently substituting a nicer one, which would put the file and stdout in
disagreement.

**Write points:** `STARTED` immediately after the lock is acquired and the branch resolved (so it
overwrites any prior result at the moment a new attempt begins), then exactly one terminal record
at each of the four verdict exits.

**Reader contract — the safety property, and it must be stated in the file's own header and in
CLAIMS made about it:**

1. **Absent ⇒ UNVERIFIED, NEVER failed.** No file means no attempt was recorded *or the writer
   died before writing*. Reading absent as FAILED re-creates the inversion this fix exists to kill.
2. **`ref` AND `local_sha` must BOTH match what the reader cares about** — not the sha alone.
   If either differs, the record belongs to a different attempt ⇒ treat as UNVERIFIED.
   **This is what makes the four silent pre-push aborts harmless** — a stale record cannot be
   mistaken for a fresh verdict. Staleness is defused by the contract rather than by perfect write
   coverage.
   ⚠ **`local_sha` alone is NOT sufficient, and the sha-only version of this rule was a real hole**
   (review round 1, F2): two refs legitimately share a tip after a fast-forward merge, or on a
   freshly-cut branch with no new commits — an ordinary state, not an exotic one. In that window a
   `LANDED` record written for branch B passes a sha-only check by a reader asking about branch A,
   and B's verdict gets attributed to A. The fields were already in the record; the contract simply
   did not require reading them.
3. **`result=STARTED` is not a verdict.** Pair it with `kill -0 <pid>`: alive ⇒ a push is in flight,
   **do not start another**; dead ⇒ interrupted, landing unknown, probe the remote.
   ⚠ This inherits `_git_lock.sh`'s **PID-reuse** blind spot — a recycled pid belonging to an
   unrelated live process reads as "still running". Pre-existing and accepted in this repo (the lock's
   holder check has the same exposure, and `_git_lock.sh:104-109` names the PID-reuse case
   explicitly at `:108`); noted so nobody reads the
   pid as stronger evidence than the lock's own.

4. **`reason=` is SANITIZED before it is written** — newlines collapsed to spaces, `=` and control
   chars stripped, capped at ~200 chars. It carries raw `git push` / `ls-remote` stderr, and an
   embedded newline would inject a bogus `key=value` line and corrupt the record for every parser.
   A one-line spec, but the format is only as trustworthy as its least-controlled field.
5. **`LANDED` never means CI-green.** CI runs after; that is what the reconcile arm is for.

## 5. Changes

| # | File | Change |
|---|---|---|
| 1 | `scripts/safe_push.sh` | a `_write_push_result()` helper + one `STARTED` write + four terminal writes at the four terminal exits (`:167`/`:176`/`:189`/`:201` **in the pre-fix file**; the diff's own inserted comments move them to `:319`/`:329`/`:343`/`:356`, and re-deriving them was B-pass F1). Atomic: write `<path>.tmp`, then **`mv -T`** (NOT plain `mv`) so a reader never sees a torn record. ⚠ **The `-T` is mandatory, and not only for the test** — measured on this stack: with a pre-existing DIRECTORY at the destination, plain `mv` exits **0** and moves the file *inside* it, so the record lands where no reader looks and the push reports success; `mv -T` fails loudly (exit 1). That is a bad-news-vs-no-news instance. ⚠ **And the COMMON path was verified separately, because `-T` refusing to overwrite would break every push after the first:** `mv -T` onto an existing regular FILE **replaces it unconditionally**, exit 0, tmp consumed — confirmed over 4 consecutive writes. `_git_lock.sh:100-101` documents exactly this asymmetry — *"a directory destination makes `mv -T` fail-if-present (correct for claiming, useless for replacing), and a file destination makes it replace unconditionally (**exactly backwards**)"* — where "backwards" is that file's verdict for ITS problem. For this one the same asymmetry is exactly right in both directions: replace the record every push, and refuse a directory sitting where the record belongs. The primitive that defeated the lock's reclaim is the one that makes this publish correct. Every write is `|| true`-guarded — **a failure to record must never turn a landed push into a reported failure**, the same reasoning `arm_ci_reconcile.sh` already uses |
| 2 | `scripts/safe_push.sh` header | document the file, its four states and the reader contract where the three exit codes are already documented (`:12-21`) |
| 3 | `CLAUDE.md` §4.3 | the `safe_push.sh` bullet already explains what it "CANNOT tell you" — extend it with the result file + the absent⇒UNVERIFIED rule |
| 4 | `CLAUDE.md` §4.9 | **the verification-width row** (item 2 — text in §6) |
| 5 | **`scripts/push_result_lib.dart` (NEW)** | the contract as CODE — pure parse + classify, no I/O. Round 3's F2: without it the contract is prose and its test is circular |
| 6 | **`test/scripts/push_result_lib_test.dart` (NEW)** | unit tests for the lib, incl. case 10; no repo or temp dir needed, so it is fast and cannot flake on contention |
| 7 | `test/scripts/safe_push_test.dart` | the subprocess cases (§7) |
| 8 | `docs/audit/open_issues.md` | close OI-172 (`:3409`), citing which option shipped and why option 1 was folded in rather than dropped |
| 9 | diagnose-doc | `docs/diagnoses/2026-09-10-*-<id>.md`, `recurrence:` citing OI-128 / `b4d7e9` / `INDEX.md:45` |

**NOT changed, deliberately:** `_git_lock.sh` (three rounds of review scars; the trap and the
refuse-a-dead-holder behaviour are load-bearing), `arm_ci_reconcile.sh`, `reconcile_ci.dart`,
`retire_worktree_lib.dart` (option B needs no entry — and that is the point).

## 6. The §4.9 row (item 2), verbatim for review

> **A filter you add for readability narrows the verification's input set — and zero results look
> identical to proof.** Every `--include` / `-v` / `^\s+` / directory argument / `\| head` is a
> CLAIM that what you are looking for cannot appear where you just excluded. State the claim or drop
> the filter. **Four instances in ONE session** (2026-09-08/09, OI-162 slice 3b): (a) a
> `grep -rn <symbol> lib/ test/` written into a plan but *run* against `lib/` only returned "1 hit,
> its own definition", and the plan concluded a method was safely deletable — there were **2**, the
> second a contract-test map asserting that very file still read the old table; (b)
> `grep -cE "^\s+(warning\|error) -"` over `dart`/`flutter analyze` output returned **0 against a real
> warning**. The analyzer **right-aligns the severity column to a FIXED width of 7** (`len("warning")`),
> so `warning` gets **0** leading spaces, `error` (5) gets **2**, `info` (4) gets **3** — measured, and
> the width is fixed rather than the longest present, because info-only output still gets 3. So that
> anchor MATCHES `error` and `info` and is structurally blind to exactly ONE severity: **`warning`** —
> the only one that matters, since `--no-fatal-infos` suppresses infos and an `error` fails the build
> anyway. It would have failed the push with git's opaque `failed to push some refs`. Verbatim
> positive control on real output: warnings+info → `^\s+` **0** vs `^\s*` **2** with 2 warnings present;
> and — worse — on output that ALSO contains an `error`, `^\s+` returns a **NON-ZERO** count while
> still missing every warning, so the number reads like a successful find. **Two independent runs
> disagreed on the count (0 vs 1) purely because one sample had an error line, and both were right**;
> (c) a `grep -v "Running build hooks"` **deleted the answer**, because
> the banner prints on the SAME LINE as the result (`Running build hooks...Blast-radius: platform`)
> — stacked with omitting `blast_radius_from_diff.dart`'s `-` stdin flag, which silently classifies
> the EMPTY staged set instead; (d) a post-rename sweep scoped `--include=*.md --include=*.yaml`
> reported "none remaining" while the stale name sat in a **`.sql`**. **Prefer `git grep` for
> does-this-still-exist** — every tracked file, no extension list to get wrong. ⚠ **The tell: you
> wrote the filter and the expected answer in the same breath.** Class file:
> `feedback_green_check_input_set_width` (39 instances).

**Why CLAUDE.md and not memory alone:** §4.9 is auto-loaded every session; the memory class file is
*recalled*. That file stands at 39 instances, which is the evidence that memory-only has not held.

## 7. Tests + mutation plan (§4.4 rule 21)

`test/scripts/safe_push_test.dart` exists and drives real subprocesses, so it already carries
`@Timeout` — **verify that before adding, and grep for a per-test `timeout:` override**, which
takes precedence over the file annotation (§4.9's 5th recurrence).

New cases, each against a real temp repo + a real remote:
1. a successful push writes `result=LANDED` with `local_sha == remote_sha`
2. a rejected push (remote ahead) writes `result=FAILED` and a non-empty `reason`
3. an unreachable remote writes `result=UNVERIFIED` with `exit=2` and an EMPTY `remote_sha`
4. a `STARTED` record exists mid-push carrying a live pid — the case that motivated the OI.
   ⚠ **The slowdown must be explicit, not incidental**: push to a local bare repo whose
   `pre-receive` hook sleeps, so the mid-flight window is created deliberately rather than sampled
   by luck. An implicit race here is the 6th recurrence of the green-targeted/red-in-suite class
5. the record is **overwritten**, not appended, by a second push
6. an abort before the push (bad branch) leaves the PRIOR record untouched, and its `local_sha`
   therefore does not match the new HEAD — the §4-rule-2 property, asserted directly
7. the file lands in `--git-dir`, NOT the worktree — asserted by path, and by
   `git status --porcelain --ignored` reporting nothing new (the anti-regression for the
   retirement class; this is the assertion that would have caught instance four)
8. **a record write that FAILS does not fail the push** — pre-create `.safe_push_result` as a
   *directory*, then assert the push still exits **0** and still reports LANDED on stdout.
   ⚠ **This fixture only works because change 1 mandates `mv -T`** (round 2, F-R2-1): measured here,
   plain `mv` onto a directory exits **0** and moves the file inside it, so with plain `mv` this case
   would be a silent no-op and the `|| true` guard would ship untested — a zero-red mutation read as
   "covered elsewhere". **Run the fixture once and confirm it fails before trusting the test.**
9. **`reason=` cannot inject a line** — force a failure whose stderr contains a newline, then assert
   the parsed record has exactly the expected key set (no extra keys) and that `reason` is one line
10. **two refs at the SAME sha do not borrow each other's verdict** — feed `classify()` a `LANDED`
    record for ref A and ask it about ref **B** at the identical sha; it must answer UNVERIFIED.
    ⚠ **In v4 this exercises `push_result_lib.dart`, real shipped code.** Through v3 it exercised a
    reader the test invented, which made it circular (round 3, F2): the assertion could only prove a
    stand-in agreed with prose written by the same author. Being a pure function, it also needs no
    repo and cannot flake.
    ⚠ This is the test the F2 fix was missing (round 2, F-R2-2): case 6 exercises a *sha* mismatch,
    which is a different leg. Accepting a finding and not testing its own mirror is exactly
    `feedback_mistake_guard_without_its_mirror` — the fix landed in the contract prose and had no
    assertion behind it

**Mutations to run, each confirmed APPLIED before its run, none allowed to be a shell syntax error
(this language's equivalent of the compile-error trap — a script that no longer parses proves the
file is invalid, not that any assertion detects the defect):**

| mutation | test that MUST redden |
|---|---|
| collapse UNVERIFIED into FAILED | case 3 (guards `d4f9b2`) |
| write the record into the worktree instead of `--git-dir` | case 7 |
| remove the `STARTED` write | case 4 |
| drop the `\|\| true` guard on a write | **case 8** |
| drop the `reason` sanitizer | **case 9** |
| relax `classify()` to compare `local_sha` only, ignoring `ref` — **a real code mutation in `push_result_lib.dart`**, not an edit to a test-authored stand-in | **case 10** |
| use plain `mv` instead of `mv -T` for the publish | **case 8** |

⚠ **Every mutation is paired with a NAMED test, and that pairing is the finding from review round 1**
(F3). The draft listed a `|| true` mutation with nothing in the suite that could induce a write
failure, and a "torn-read assertion" that **did not exist anywhere in the plan** — so both would have
reddened ZERO and been read as "covered elsewhere". That is precisely the trap §4.4 rule 21's
third clause describes, committed inside the section that quotes it. Cases 8 and 9 exist to close it.

⚠ **Torn reads are deliberately NOT claimed as tested.** A concurrent reader landing mid-`rename()`
is not reliably reproducible in a Dart test on this stack, so atomicity is carried by the
tmp+`mv` construction and by review — stated as an untested property rather than listed as a
mutation with an imaginary assertion behind it.

⚠ **A zero-red mutation has two explanations** and they are indistinguishable from the run alone.
If one reddens nothing, find out which before believing the case is covered elsewhere.

⚠ **Round 3's F3 (the `mv -T` overwrite path undersupported in the doc) was already closed before that round reported** — the measurement was added to change 1 after the dispatch, so r3 reviewed the pre-edit text. Its independent run agreed: absent → creates, existing file → replaces (exit 0), existing directory → refuses (exit 1). Two independent confirmations of the full matrix.

**Precondition, verified rather than assumed:** `test/scripts/safe_push_test.dart:20` already carries
`@Timeout(Duration(minutes: 3))` and `grep -n timeout` finds **no per-test override** — the 5th
recurrence of that class was a per-test `timeout:` silently beating the file annotation, so it was
checked, not presumed. **6 tests today; this adds 12, for 18** — plus 21 in the new pure reader test and 12 in the new contract test, 51 in all. ⚠ The figure read "adds 9" until round 3 (F1) — stale the moment round 2 added case 10, in a plan whose own §6 row is about stale verification claims. Re-count from the list, never from this sentence.

## 8. Risks / what this does NOT fix

1. **`kill -9` still defeats it.** No shell can write a record after SIGKILL — the same limit
   `_git_lock.sh`'s trap has. The absent⇒UNVERIFIED rule is what keeps that honest rather than
   dangerous.
2. **It does not reduce the memory pressure** that caused yesterday's reaping. It stops the pressure
   from producing false beliefs. Two different problems; only this one is small.
3. **A reader that ignores `local_sha` can still be fooled** by a stale record. Mitigated by
   contract + test 6, not by mechanism — stated plainly rather than left implied.
4. **A TAG passed where a branch is expected gets a durably WRONG verdict** (round 2, F-R2-3).
   `probe_remote_sha()` (`safe_push.sh:113-118`) hardcodes `git ls-remote "$REMOTE" "refs/heads/$BRANCH"`.
   Give `$BRANCH` a tag name and the push lands, the probe matches nothing, `PROBE_EXIT` is 0, and the
   script falls through to `:201` — **FAILED for a push that succeeded**. Pre-existing, NOT introduced
   here, and today unreachable: `grep -rn "safe_push.sh.*--tags"` finds zero call sites and every
   caller passes a real branch. But this plan **persists that wrong verdict into a durable, greppable
   artifact**, which is a real change in kind from a stderr line a human scrolls past. Recorded as a
   bounded residual rather than fixed, because fixing it means changing `safe_push.sh`'s verification
   semantics — a different change with its own blast radius. The record's header comment must say
   plainly: **it verifies the primary branch ref only.** Companion refspecs pushed in the same
   invocation (tags, `-u` upstream wiring) are unverified by this mechanism (F-R2-5).
5. **No gate reads the file**, so nothing enforces that future callers honour the contract. That is
   deliberate (a gate on a diagnostic artifact would be a ship-stop for a hygiene feature, §4.13
   point 6's reasoning) and it is a real residue, not a solved problem.

## 9. Out of scope, explicitly

The **full-suite memory footprint** (~1.17 GB `dartvm.exe`; three processes reaped). ⚠ MEMORY.md
flags **CI sharding, `PRE_COMMIT_GATE_JOBS` and Defender exclusions** as *do-not-re-derive traps* —
all three being the obvious reflexes here. Anyone attacking this reads that trap list first; this
plan does not touch it. · `_git_lock.sh` · OI-153 · slice 4.

---

## 10. Review round 1 — disposition (v2)

7 findings, **0 P0**, 3 P1, 2 P2, 2 P3. Six accepted and fixed above; one REJECTED with evidence.

| # | sev | disposition |
|---|---|---|
| F1 | P1 | **REJECTED — the finding is wrong.** See below. |
| F2 | P1 | **ACCEPTED** — `ref` AND `local_sha` must both match; sha-only was a real hole (§4 rule 2). |
| F3 | P1 | **ACCEPTED** — two of five mutations had no test that could redden them; cases 8 + 9 added, every mutation now paired with a named test, torn-read explicitly declared untested (§7). |
| F4 | P2 | **ACCEPTED** — citation `290-296` → `291-297` (the `.tmp` entry is at 297; the old range stopped one line short of the thing it cited). |
| F5 | P2 | **ACCEPTED** — the `ps` + `ls-remote` steps are not in the OI record, so the claim is now bounded to what `open_issues.md:3409-3423` actually documents. |
| F6 | P3 | **ACCEPTED** — `reason=` sanitization is now a stated part of the format (§4 rule 4). |
| F7 | P3 | **ACCEPTED** — PID-reuse blind spot acknowledged inline (§4 rule 3). |

### F1 REJECTED — and it committed the very class the row documents

**The finding claimed** the row's *"`info` lines are indented and `warning` lines are not"* is false, on
the strength of `docs/reports/2026-04-20-wardroom-handoff-sweep.md:149-152`, where warning lines
carry two leading spaces.

**That file is not analyzer output.** Two tells, both in the quoted block itself: it uses `—`
(em-dash) as its field separator where the analyzer uses ` - `, and it prints `4 issues found.`
**above** the issues where the analyzer prints the count **last**. It is a hand-typed summary inside
a markdown report, uniformly indented for the code fence. Characterising analyzer stdout from a
prose report is **exactly the input-set-width error the row exists to document** — the finding
committed the class while arguing the class was misdescribed. Recorded because that is more
instructive than the correction.

**Measured instead, with a positive control** (`dart analyze` on a scratch file, `cat -A` for exact
bytes):

```
warning - probe.dart:3:7 - The value of the local variable ... - unused_local_variable
warning - probe.dart:6:7 - The operand must be 'null' ...     - unnecessary_null_comparison
   info - probe.dart:4:3 - Don't invoke 'print' ...           - avoid_print
  error - err.dart:3:11  - A value of type 'String' ...       - invalid_assignment
```

The severity column is **right-aligned to a FIXED width of 7** (`len("warning")`): `warning` → **0**
leading spaces, `error` → **2**, `info` → **3**. Fixed, not longest-present — info-only output still
gets 3. The published regex, run verbatim on the real mixed output: `^\s+(warning|error) -` → **0**
while 2 warnings were present; `^\s*` → **2**. Against error-only output the same anchor returns
**1**, i.e. it matches errors fine.

So the row is not merely right, it is sharper than drafted: the anchor is blind to **exactly one
severity, `warning`** — the only one that matters, because `--no-fatal-infos` suppresses infos and an
`error` fails the build regardless. §6 now states the mechanism and the measurement rather than the
informal "indented" phrasing that invited the objection.

---

## 11. Review round 2 — disposition (v3)

7 findings, **0 P0**, 3 P1, 3 P2, 1 P3. **All 7 accepted**, all fixed above. Round 2 also
**independently reproduced** the analyzer measurement and confirmed round 1's F1 rejection was sound.

| # | sev | disposition |
|---|---|---|
| F-R2-1 | P1 | **ACCEPTED** — case 8's fixture only fails under `mv -T`; plain `mv` exits 0 and swallows the file into the directory. Verified here. `mv -T` is now mandated in change 1 **for the production reason as well**, and case 8 states its dependency. |
| F-R2-2 | P1 | **ACCEPTED** — the F2 fix had no test of its own; case 6 is a *sha* mismatch. Added **case 10** (two refs at one sha) and repaired the mutation pairing. |
| F-R2-3 | P1 | **ACCEPTED** — a tag passed as `$BRANCH` yields a durably WRONG `FAILED`. Verified `safe_push.sh:113-118` hardcodes `refs/heads/$BRANCH`. Recorded as residual §8.4 with the reasoning for not fixing it here. |
| F-R2-4 | P2 | **ACCEPTED** — PID-reuse is at `:108`, not `:145-155` (which is `_pid_alive`). Citation corrected. |
| F-R2-5 | P2 | **ACCEPTED** — companion refspecs unverified; folded into §8.4. |
| F-R2-6 | P2 | **ACCEPTED** — case 4's mid-flight window is now created deliberately (bare remote + sleeping `pre-receive`), not sampled by luck. |
| F-R2-7 | P3 | **ACCEPTED** — header was still `v1`; now `v3`. |

### Two of the three P1s were defects in round 1's own corrections

F-R2-1 arose from F3's fix and F-R2-2 from F2's fix. That is exactly what §4.12.1 predicts and why
round 2 runs on the HARDENED plan rather than the original. F-R2-2 is the sharper of the two: I
accepted a contract fix and shipped it **with no assertion behind it** — `guard_without_its_mirror`
in its purest form, one round after being told the class by name.

### Convergence

Round 2's own verdict was *"not converged, narrowly"* — three bounded fixes, no redesign. The core
design has now survived **two independent re-derivations**: Option B / `--git-dir` immunity to the
retirement predicate was re-derived from `retire_worktree.dart` without reference to my reasoning, and
the analyzer measurement was reproduced from scratch. Nothing in either round touched the central
decision; all churn was in test and contract detail, which is convergence on detail rather than the
"5 P1s ⇒ split" shape.

**Item B (the §4.9 row) has ZERO open findings** after two rounds and is independently verified.
Item A carried all six code-side findings. That is a real seam, and it is the founder's call whether
to use it — recorded here rather than decided unilaterally.

---

## 12. Review round 3 — disposition (v4)

6 findings, **0 P0**, 1 P1, 3 P2, 2 P3. **All accepted.** Round 3 was scoped narrowly to the v2→v3
delta, on the stated grounds that two of round 2's three P1s had been defects in round 1's corrections.
It found more of the same, which is the argument for having run it.

| # | sev | disposition |
|---|---|---|
| F1 | P1 | **ACCEPTED** — "adds 9" against 10 enumerated cases, stale the moment round 2 added case 10. A stale verification count inside the plan whose own §6 row is about stale verification counts. ⚠ **It went stale AGAIN twice after this fix** — first to "adds 10, for 16", then to the real final figure of **12 new / 18 in file / 51 across three files**, as the writer→reader and kill-switch tests landed. Third time on one number in one batch. The lesson is not "re-count" but **stop writing derived counts into prose that the same batch keeps changing**; every figure here was finally re-derived from `grep -c` after the last edit. |
| F2 | P2 | **ACCEPTED and UPGRADED — the most substantive finding of all three rounds.** See below. |
| F3 | P2 | **ALREADY CLOSED before r3 reported** — the overwrite measurement was added to change 1 after dispatch, so r3 read pre-edit text. Its independent run agreed on the full matrix. |
| F4 | P2 | **ACCEPTED — FIXED, not accepted-as-residual.** Added `verified_ref=` so the tag case self-diagnoses. Contained to the new writer; changes no verification semantics. |
| F5 | P3 | **ACCEPTED — my framing was wrong.** See the corrected accounting below. |
| F6 | P3 | **ACCEPTED** — no `v2` state was ever stamped; §10 is the round-1 disposition and should have carried it. Noted rather than back-dated. |

### F2 — the reader contract was prose, and its test was circular

Through v3 the contract lived in §4 as prose, and case 10 asserted it against a reader **the test
invented**. So the assertion could only show that a stand-in agreed with prose written by the same
author — it said nothing about any real caller, and there were no real callers. §8.5 half-disclosed
this ("nothing enforces that future callers honour the contract") and I never connected it to case 10.
Worse, my F-R2-2 disposition claimed the case *closed* the `guard_without_its_mirror` gap; it closed it
for an entity that does not exist.

Fixed by shipping the contract as code: **`scripts/push_result_lib.dart`**, pure parse + classify, no
I/O. Three things follow that prose could not give:
1. **One place to be right.** Every future reader calls `classify()` instead of re-deriving §4.
2. **Case 10 tests real shipped code**, so the "relax to `local_sha`-only" mutation is a genuine code
   mutation rather than an edit to a fixture.
3. **The decay risk drops.** A prose contract is precisely what §4.13 point 6 describes — everything
   with a gate holds, everything on intention decays.

Not invented here: `scripts/ci_reconcile_state_lib.dart` is the same shape, one directory over, for the
gitignored file `arm_ci_reconcile.sh` writes.

⚠ **This is a scope change and it is flagged as one.** It adds two files that were not in the founder's
original ask. The case for it is that "a result file nobody can correctly read" does not close OI-172 —
but it is a judgement call, and vetoing the lib (keeping prose + an honest relabel of case 10 as a
specification test) is a legitimate alternative that costs two files and buys back the circularity.

### F5 — the corrected convergence accounting

I wrote that this was "not the 5-P1s-⇒-split shape". **It is exactly 5 accepted P1s**: F2 + F3
(round 1), F-R2-1 + F-R2-2 + F-R2-3 (round 2). Round 3 is right that saying otherwise understated it,
and right that two of those were about whether the verification methodology itself was sound — not
incidental detail.

What the three rounds actually show, stated without spin:
- **The core design has never moved.** Option B / `--git-dir` immunity was independently re-derived
  twice; the `mv -T` matrix, the tag trace, the analyzer regex and the sleeping-`pre-receive` technique
  were each reproduced from scratch by a reviewer who did not write them.
- **Every P1 was in the scaffolding around it** — the reader contract, the mutation pairings, the
  test count, one residual. That is convergence on detail.
- **The recurring fault is mine and it is one fault:** my corrections claimed more than they proved,
  three rounds running. F-R2-2 and F2 are the same error one level apart.

**Item B has ZERO findings across all three rounds** and was independently verified twice. Item A
carried all 11 findings. Per §4.12.1 that is a real seam, and it is the founder's call.

---

## 13. §5 close-out — the context-artifact budget row

The §5 row is the trigger and it fired: `check_context_artifact_budget.dart`
reported `WARN docs/audit/open_issues.md 235720 → 291597 B (+23.7%)`, past the
15% soft band. **Re-baselined with `--record`** (soft breach, so no
`--force-record`); the gate now reports `PASS: 3 within band`.
`backups/context_artifact_sizes.json` is part of this batch.

**What the measurement actually showed, because `--record` should never be a
reflex.** The soft band is documented in `context_budget_lib.dart:110` as
*"where a human should look"*, not as an instruction to re-baseline, so I
looked:

| | bytes | vs baseline | this batch's share |
|---|---|---|---|
| `CLAUDE.md` | 107,282 → 115,659 | +7.8% | +6,407 B (§4.3 bullet + the §4.9 row) |
| `docs/audit/OPEN_INDEX.md` | 16,337 → 17,975 | +10.0% | regenerated |
| `docs/audit/open_issues.md` | 235,720 → 291,597 | **+23.7%** | +3,504 B (OI-172's closure block) |

**This batch caused 3,504 B of a 55,877 B breach — 6%.** The other 94% is
inherited drift from batches that filed issues and never re-baselined.

**The remedy that looks obvious does not work, and this is the part worth
keeping.** The documented precedent is the 2026-08-30 pass that archived 27
CLOSED entries to `closed_issues.md` and reclaimed 46% of the board. Applying it
here: exactly **three** entries currently carry `Status: CLOSED` (OI-170, OI-171
from `regen-wave-alignment`, and OI-172 from this batch), totalling **14,972 B**.
Archiving all three leaves the board at **276,625 B, +17.4% — still past the
soft band.** So the growth is not a CLOSED-entry backlog waiting to be swept; it
is **92 live OPEN entries**. No archive pass can clear this WARN, and a session
that assumes one can will spend the effort and still see the warning.

⚠ **Not attempted here for a second reason, stated so nobody retries it
casually:** OI-172's closure must remain visible on the board for this batch's
own commit-msg gate — `check_closes_oi_cited.dart` fires on an OPEN→CLOSED
*transition*, and moving the entry out of the file in the same commit presents
as a deletion, not a transition.

**Surfaced rather than filed.** No OI exists for the board-growth class, and
filing "the board is large" with no decided remedy produces exactly the
`Verified: never` entry the board is already full of. The founder's call, with
the numbers above: the hard band (50%) sits at 353,580 B, so this is not urgent
— but it is now measured, and the next 15% is counted from 291,597.
