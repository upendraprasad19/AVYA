# Batch A — get `main` CI green + board hygiene (2026-09-26)

Branch / worktree: `ci-green-batch-a` · base `fafec56a` (= `origin/main`)
Execution mode (§4.12.7, decided at start): **inline** — one coordinator, no
subagent-built units. Four units, ≥4 ⇒ closure YAML
`docs/audit/ci-green-batch-a.closure.yaml` (§4.2).

Expected tier: **feature** for every file below (`test/**`, `.gitignore` →
`default_tier`, `docs/**`). To be RE-classified on the written diff with
`scripts/blast_radius_from_diff.dart` before any commit — if anything
classifies ≥ account, the batch takes a plan-review record + B-pass.
S/M/L (§4.12.6): **M** (not S-eligible — nothing under the four S dirs) ⇒
×2 plan review + compile gate. No `lib/` change is planned; if one becomes
necessary the batch re-plans.

---

## U1 — `main` is RED: a test fixture depends on an ambient global git identity

**Evidence (verified by the coordinator, not a subagent).** Last 4 CI runs on
`main` (`0c92c105`, `b4a42556`, `fc797551`, `fafec56a`) fail job "Unit Tests"
with exactly one test:
`test/scripts/discipline_hook_main_sync_e2e_test.dart: stays silent when there
is no origin/main to read (no remote at all) [E]` · `Expected: <0>` (job log,
run on `fafec56a`, 6429 passed / 1 failed).

**Writer / reader.**
- Writer: the `lone` fixture, `discipline_hook_main_sync_e2e_test.dart:172-176`
  — `git init` then `_commit(lone, …)` with NO `user.email` / `user.name`.
  (The `clone`/`other` fixtures in `setUp` DO set them, `:97-98`.)
- Reader: `_commit` (`:71-75`) → `expect(_git(['commit', …]).exitCode, 0)`.
- `_cleanEnv()` (`:25-29`) strips `GIT_*` but inherits `HOME`, so on any
  machine with a global identity (the founder laptop, this VPS) the commit
  succeeds; the CI runner has none ⇒ git exits 128 ("Author identity
  unknown"). Passing locally and failing in CI is the whole symptom.

**Fix.**
1. Set `user.email` / `user.name` on the `lone` repo exactly as `setUp` does.
2. Make the file HERMETIC so local runs reproduce CI: `_cleanEnv()` additionally
   sets `GIT_CONFIG_GLOBAL=<an empty temp file>` and `GIT_CONFIG_NOSYSTEM=1`
   (portable — an empty file rather than `/dev/null`, which differs on
   Windows). This applies to every fixture git call AND the hook subprocess
   (neither needs global config; the hook only fetches/compares). It also
   REMOVES `EMAIL` (R1 F8): git falls back to `$EMAIL` for the author, so on a
   machine that sets it the mutation below would stay green. And the empty
   global file is not empty: it holds `[user]\n\tuseConfigOnly = true` (R2 F7)
   — otherwise a host with a real FQDN auto-detects an identity and the
   mutation stays green; the `GIT_CONFIG_*` entries are set AFTER the `GIT_*`
   strip in `_cleanEnv()`, or the strip removes them.

**Regression proof (rule 21, mutate-and-run).** With (2) in place, delete (1)
→ the `lone` test must go RED locally with the same exit-128 shape CI shows
(this is the proof the hermetic env reproduces CI); restore → green. Whole file
(8 tests) green hermetically. Also confirm no sibling test in the file relied on
global config.

**Sweep.** 23 test files `git commit` in fixtures; all other 22 pass CI today,
so none currently commits without an identity. Not widened to them in this
batch (their CI-green is the evidence); the class goes into the diagnose-doc
and the debugging skill's bug-class table so the next fixture author sees it.

## U2 — OI-242 + OI-86: tests race an UNAWAITED `_downgradeLocally`

**Evidence.** OI-242 flake fired in CI 2026-09-15 and 2026-09-23 (subagent CI
scan of the last 100 runs; the coordinator re-verified the root cause in code).
`realtime_pro_gate_behavioral_test.dart:221-241` "THE SECOND BUG" fails with
`Expected: true Actual: false`, then `HiveError: Box not found` from
`resetToFreeCapOnLapse`.

**Writer / reader.**
- Writer: `SubscriptionService._enforceEntitlementInvariants`
  (`lib/core/services/subscription_service.dart:~480-483`) — on an expired row
  it `unawaited(MigratedKey.write(pro_lapsed_at …))` then calls
  `_downgradeLocally()` WITHOUT awaiting (isPro() is sync by design).
  `_downgradeLocally` (`:1175-1227`) awaits FIVE MigratedKey writes (`:1191-1195`),
  then fires `onStateChanged` (`:1199`), then `onDowngrade` (`:1213`), then
  `resetToFreeCapOnLapse()` synchronously.
- Readers (five test files wait on that chain with a PROXY, not the signal):
  | file | wait used | sites that downgrade |
  |---|---|---|
  | `realtime_pro_gate_behavioral_test.dart:237` | `pumpEventQueue()` (≈20 turns) | 1 |
  | `subscription_expiry_banner_behavioral_test.dart:44-58` | 3×10 ms quiescence sampler | 2 (`:105`, `:134`) |
  | `subscription_cqrs_behavioral_test.dart:105-140` | sampler + "restart once on hook" (a3e9b7) | ~7 of 12 |
  | `subscription_paused_for_simulation_guard_test.dart:102,146` | fixed 50 ms sleep | 2 (the 2 un-paused sites) |
  | `subscription_payment_grace_window_behavioral_test.dart:79-81` | tearDown 12×5 ms drain | the expired-row tests |
- MECHANISM (corrected by plan-review R1 F2, verified in hive 2.2.3 source):
  Hive inserts a `put` into the in-memory keystore SYNCHRONOUSLY
  (`box_impl.dart:85` `keystore.beginTransaction(frames)`) and only then awaits
  the disk write (`:88` `backend.writeFrames`), serialised per box
  (`storage_backend_vm.dart` `_sync.syncWrite`). So `isPro=false` and the
  lapsed marker are visible in memory before `isPro()` returns. What waits on
  real I/O is everything AFTER the first `await`: `_downgradeLocally` awaits its
  five writes ONE AT A TIME (`:1191-1195`), so writes 2-5 and BOTH hooks sit
  behind one real file write per key that is actually PRESENT, plus the lapsed stamp (a `delete` of an absent key produces zero frames — R2 F4; three real writes in the realtime fixture). A loaded runner can outlast any fixed
  count/sleep. Once the test gives up, `tearDown` closes Hive under the
  still-running chain ⇒ the trailing `Box not found`. So OI-242's "leaking
  earlier file / bisect" hypothesis is WRONG (the trace is a consequence, not
  the cause), and OI-86's stated cause ("process-shared Hive dir") is refuted —
  `setUpHiveForTests` uses a unique `createTemp('avya_test_')` per test
  (`test/helpers/hive_test_setup.dart:24`).

**Why a3e9b7's fix is not sufficient either (found this session).** Its loop
exits after 3 stable 10 ms rounds even if the hook has NOT fired; "restart once
on hook" only applies if the hook fires INSIDE the loop. If a later write takes
> ~30 ms under load, `_settle` returns after only the FIRST write's in-memory
effect — the same race, narrower window.

**Why waiting on the hook is sufficient FOR THESE FIVE FILES (precondition
stated, R1 F3).** `onDowngrade` fires only after all five awaited writes have
completed, and `Completer.complete()` resumes the waiter in a later microtask,
i.e. after `resetToFreeCapOnLapse()`'s synchronous body has run. That body can
START further async work without awaiting it: `UserRepository.updateProgress`
→ `saveProgress` (a real disk write) when `streak_freezes_available > 1`, and
`SyncService.syncFreezes()` (returns early only because
`SupabaseService.currentUser` is null in VM tests). None of the five files
seeds progress (grep `streak_freezes|'progress'|updateProgress` → 0 in all
five), so after `wait()` nothing is left in flight. The helper's docstring
states this precondition so a future caller who seeds freezes knows the
waiter does not cover that tail.

**Fix — one shared primitive, test-only (rewritten after R2 F1/F3/F8).**
New `test/helpers/pro_downgrade_waiter.dart`:
- `ProDowngradeWaiter.arm()` chains `SubscriptionService.onDowngrade` (never
  replaces — the realtime test's own `tornDown` handler still fires) and
  completes a Completer on the first fire. **Ordering rule (R1 F5a):** call
  `arm()` AFTER the test installs its own `onDowngrade`. Nested arms (a second
  `arm()` before the first is settled) are UNSUPPORTED and fail immediately
  with a named message (R2 F8) — no call site needs them.
- **Self-draining teardown (R2 F1 — replaces R1's `addTearDown(restore)` +
  `drainArmed()`, which was WRONG):** test_api runs teardowns LIFO
  (`invoker.dart:296` `removeLast()`), so a callback `arm()` registers with
  `addTearDown` runs BEFORE the file's group `tearDown` (which closes Hive /
  the session). That callback therefore: (1) if `wait()` was never awaited,
  awaits completion with a bounded timeout, NEVER throws, prints a named
  diagnostic on timeout (§4.9 "teardown must never throw"); (2) restores the
  previous hook only if the installed hook is still ours; (3) marks the waiter
  settled. This IS the drain the grace-window file needs — it runs before that
  file's `tearDown` — so `drainArmed()` is dropped.
- `await waiter.wait({timeout = 10 s})` — throws a `TestFailure` NAMING the
  wait ("onDowngrade never fired within …") well inside the 30 s default test
  budget; asserts the installed hook is still ours (else named failure: a later
  plain assignment dropped the chain); restores in `finally`.
- Restore is IDEMPOTENT (R2 F8): guarded by `onDowngrade == _myHook` plus a
  `_restored` flag, so `wait()`'s `finally` and the teardown cannot clobber a
  hook installed later.
- Signal choice: `onDowngrade`, not `onStateChanged` — it fires ONLY from
  `_downgradeLocally` (`:1213`), whereas `onStateChanged` also fires from
  other writers (`subscription_service.dart:70` user-swap, `:326`).
- Precondition in the docstring (R1 F3): after `onDowngrade`,
  `resetToFreeCapOnLapse()` may START an unawaited progress write when
  `streak_freezes_available > 1`; the waiter does not cover that tail, and no
  migrated file seeds it.
- `pausedForSimulation` makes `_downgradeLocally` return before its hooks ⇒
  paused sites do NOT arm; they assert an ABSENCE (`isPro` stays true), which a
  late write cannot falsify on that path, so they keep their existing sleep.
- **Tripwire in cqrs `_settle()` (R2 F3):** misclassification must be loud in
  BOTH directions. Arming a non-downgrade site already fails loudly (named
  timeout). The reverse — a downgrade site left on `_settle()` — would keep
  the flake silently, so `_settle()` installs an `onDowngrade` tripwire (same
  chaining + restore discipline) that fails with "this site downgrades — use
  ProDowngradeWaiter" if it fires.

Applied per site: realtime "SECOND BUG" → arm + wait (the mirror "still-valid
PRO does NOT fire" keeps `pumpEventQueue`: no downgrade happens). Banner
`:105`, `:134` → arm + wait (`:134` has no session, but `onDowngrade` still
fires there). cqrs → 7 downgrade sites arm + wait; 5 no-downgrade sites keep
`_settle()` (now carrying the tripwire). Paused guard `:102`, `:146` → arm +
wait. Grace window → arm in each of the 3 expired-row tests; the 60 ms
`tearDown` loop is removed (the self-draining teardown replaces it).

**Regression proof — two layers.** A loaded-runner flake cannot be reproduced
on demand (a3e9b7 recorded an 8-core busy-loop repro as uninformative in both
arms), so the proof makes the race DETERMINISTIC. New
`test/contracts/pro_downgrade_waiter_behavioral_test.dart`:
1. **Real-chain reproduction of OI-242 (R1 F4, calibrated by R2 F2).** Session
   open; expired PRO row with `plan` and `lastVerifiedAt` SEEDED (else their
   null checks are vacuous); queue an UNAWAITED `userBox.put('big',
   Uint8List(16 MiB))` immediately before `isPro()`. R2 measured the old
   `pumpEventQueue()` wait: 0/10 red at 0–1 MB, 9/10 at 4 MB, **10/10 at 16
   MB**; the new wait green in ~87 ms. (Hive serialises + CRCs the frame
   synchronously inside `syncWrite`, `storage_backend_vm.dart:124-132`; the red
   depends on the post-serialisation I/O outlasting ~20 zero-timer turns — the
   diagnose-doc says so.) Discriminators, labelled: PRIMARY `onDowngrade`
   fired; SECONDARY `expiresAt`/`plan`/`lastVerifiedAt` null. `isPro == false`
   and the lapsed marker are BEHAVIOUR-INVARIANTS (set in memory synchronously,
   `box_impl.dart:85`) — asserted, labelled as not-proof. The SAME fixture with
   the OLD wait must be RED 5/5 (recorded) — the fixture-vs-history check.
2. **Primitive contract (rule-21 mutation target).** hook fired by hand after
   a real 300 ms delay ⇒ `wait()` does not return early and the chained
   previous hook ran; never fired ⇒ named `TestFailure`; hook replaced after
   `arm()` ⇒ named failure; nested `arm()` ⇒ named failure; an
   armed-but-unawaited waiter drains in ITS OWN teardown, BEFORE the file's
   `tearDown` (ordering pinned explicitly), and never throws on timeout;
   restore idempotent and never clobbers a later hook; cqrs-style tripwire
   fires on a downgrade.
Mutation: replace `wait()`'s body with `await pumpEventQueue()` ⇒ expect ~5
reds (case 1, 300 ms, named-timeout, hook-replaced, restored-after-wait — R2
F9); measured and recorded, confirming the mutation applied and the reds are
assertion failures, not compile errors. Plus all five migrated files green,
run TOGETHER in one `flutter test` invocation, and the full suite once before
push. The realtime file's header mutation table (`:26-34`) is re-measured
(conversion-on-touch).

### U2 SPLIT after round 3 (§4.12.1 — successive rounds kept surfacing new material issues)

R1 → R2 found a P1 introduced by R1's own correction; R3 found three new P2s,
all in machinery R2 added (the cqrs tripwire, the grace-window drain). That is
the split signal, so U2 ships as its smallest converged piece:

**U2a (THIS batch):** `test/helpers/pro_downgrade_waiter.dart` (arm / wait /
self-draining teardown / idempotent restore / nested-arm refusal); the waiter's
hook calls `complete()` in a `finally` around `previous?.call()` (R3 F1 — a
throwing chained hook is swallowed by production's `try/catch` at
`subscription_service.dart:1212-1214` and would otherwise read as a misleading
"never fired"); on a `wait()` TIMEOUT the hook is LEFT installed so the
teardown can still drain and restore (R3 F6). Sites migrated: realtime
"SECOND BUG" (the OI-242 flake itself), banner `:105`/`:134` (banner `_settle`
deleted — it would have 0 callers ⇒ `unused_element` warning ⇒ CI analyze
fails, R3 F5), paused guard `:102`/`:146`. Every migrated site calls
`wait()` — none relies on the teardown drain to be loud. Stale citations in the
touched files repointed (`:461` → `:480-483`/`:1175`, R3 F7). Proof: a
real-chain reproduction + the primitive contract. ⚠ AS BUILT: the 16 MiB
fixture (R3 probe: old wait red 6/6) was NOT deterministic on the build
machine — the old wait passed with it — so the test queues a backlog of 2000
unawaited puts instead (old wait RED 5/5, waiter green 3/3; diagnose b3f8e5);
mutations (a)
`wait()` → `pumpEventQueue()` and (b) the self-draining teardown skips its
await (R3 F3a) — both run and recorded.

**U2b (NOT this batch — its own plan + ×2 review):** cqrs (12 `_settle` sites,
the tripwire redesign of R3 F1, the setUp-started downgrade of R3 F4 + a
per-test drain) and the grace-window file (R3 F2: every site must `wait()`).
Both files keep today's a3e9b7 / 60 ms-drain behaviour, unchanged. OI-86 stays
OPEN, narrowed to exactly these two files with R2/R3's findings on the entry;
OI-242 closes with U2a (its failing test is the realtime one). Scheduling U2b
is a founder call, surfaced at batch end — not decided here.

## U3 — live Supabase Management-API token at repo root is not gitignored

**Evidence (coordinator-verified).** `git check-ignore -v ".supabase/supabase
access token.txt"` exits 1 in the primary worktree; `.gitignore:71-73` covers
only `supabase/.supabase/`. The file is untracked, 44 B, mode `-rw-rw-r--` in a
`drwx---rwx` dir. Readers of the token (`.claude/deploy_via_api.js:254`,
`.claude/apply_migration_via_api.js:26`, `scripts/check_onconflict_live_arbiter.dart:132`)
all read `supabase/.supabase/…`. ⚠ **Corrected by R1 F1 (coordinator
re-verified):** that path is empty only in the LINKED worktree. In the primary,
`supabase/.supabase/supabase access token.txt` EXISTS (44 B, 2026-08-08) and is
a DIFFERENT token from the root copy (`cmp` exits 1; root copy 2026-09-23). So
there are two Management-API tokens on this machine, and `git add -A` in the
primary would stage one of them.

**Writer / reader.** Writer: `.gitignore:73` (the only token rule). Reader:
git's ignore matcher; guard test `test/scripts/gitignore_classification_test.dart`.

**Fix.** Add an anchored `/.supabase/` rule beside `:73` with a comment; add
`'.supabase/'` to `deliberatelyPreciousIgnoredPaths` (secrets group) — it must
NOT be classed regenerable, so `retire_worktree` keeps any worktree holding a
token. (The test strips a leading `/`, so the literal is `.supabase/`.)
Founder-side, NOT in the diff and NOT a blind move (moving would overwrite the
other token): determine which token is valid (a harmless read-only
Management-API GET with each — offered to the founder, not run unasked), keep
the valid one at `supabase/.supabase/`, revoke the other in the dashboard, then
delete its file. `chmod 600` is hygiene only (`/home/ubuntu` is `drwxr-x---`).

**Regression proof.** (a) Existing guard: drop the precious-list entry ⇒
"every literal .gitignore entry is deliberately classified" RED; drop the
`.gitignore` line but keep the entry ⇒ "precious list has no orphans" RED.
(b) R1 F6 — those two only prove the LISTS agree (delete both and everything
stays green while the token is unignored), so add a direct test assertion:
`git check-ignore -q ".supabase/supabase access token.txt"` exits 0 (and the
same for `supabase/.supabase/supabase access token.txt`). It spawns a
subprocess ⇒ file-level `@Timeout` + `library;` (§4.9 — the file has neither
today, R2 F6). Run it as `git check-ignore -v` with `GIT_*` stripped from the
env and assert the reported match SOURCE is `.gitignore:` (R2 F6) — a global
`core.excludesFile` or `.git/info/exclude` listing `.supabase` would otherwise
make it green for the wrong reason.
Mutation: delete the new `.gitignore` line AND the list entry together ⇒ (b)
RED.

## U4 — board hygiene (docs/audit/open_issues.md), evidence-backed only

Every closure below was re-verified by the coordinator this session; the
evidence goes on the entry. Commit cites `closes-oi:` for each OPEN→CLOSED
(`check_closes_oi_cited.dart`).

Close (verified fixed):
- OI-63 — live: 137 of 144 public policies mention `auth.uid()`, **0** unwrapped
  (case-insensitive strip of `( SELECT auth.uid() AS uid)`); migration 100.
- OI-66 — HEAD CI run: "Cache hit … Cache restored successfully", APK job
  02:59:14→03:02:39Z = 3m25s vs 7m41s uncached baseline.
- OI-206 — `'deno.lock'` at `scripts/retire_worktree_lib.dart:255` (`8bf79dde`).
- OI-168 — superseded by the OI-220 sweep arm (`contract_sweep.dart:99`,
  `git grep -l -F <basename> -- test/`), which runs at pre-push for every tier.
- OI-198 — 812 successes / 0 non-success pr-detection rows in retained
  `cron_call_log` (back to 2026-09-14; the failures were 09-13). Closed on the
  EVIDENCE; the cause (disk-IO starvation era / migration 141's cadence change)
  recorded as a HYPOTHESIS, not a finding (R1 F9). Note the 12-day retention
  itself is a symptom of new item 3 below (7-day prune not running).
- OI-235 — `cron.job_run_details` shows 0.1–1.3 s daily except the two
  2026-09-21 "job startup timeout" failures (1488 s / 1853 s). Misattributed;
  and that metric times the pg_net DISPATCH, not the Edge Function runtime, so
  it never measured a per-user loop either way (R1 F9).
- OI-242, OI-86 — closed by U2. Evidence cited on the entry is the
  DETERMINISTIC real-chain reproduction (U2 test case 1: red on the old
  `pumpEventQueue` wait, green on the waiter) plus the local full-suite run —
  not a statistical "no flake since" claim (R1 F10). Root cause corrected on
  both entries (F2 mechanism; OI-86's shared-dir cause refuted).
Close as duplicate (content read side by side before closing): OI-224 → OI-179,
OI-234 → OI-197 item 2, OI-209 → OI-180 (census moved onto the survivor).
Narrow / correct (stay OPEN): OI-60 (FOB-7 a/b closed in `d8b90e86`; add FOB-8
`train_provider.dart:958`), OI-61 (→ test7 subscription-row cleanup only),
OI-62 (FC6 shipped; Unit A has no content in the repo — founder question),
OI-97 (2 live labels, not 5), OI-87 (residual: record exists but not converged),
OI-135 (61 mismatches = 56 CRLF artifacts + 5 real: 057 069 070 108 123 —
coordinator recomputed), OI-140 (3 live `bug_id` collisions: d3f7b2, e8a3b1,
f7a2c9), OI-165 (new root-cause hypothesis: CWD-relative token path absent in
linked worktrees), OI-80 (root cause: reader regex rejects `/` in
`fn: _shared/notification_prefs`), OI-207 (real cause: `method: a / b / c`
fails `_bareSymbolRe` ⇒ prose-skipped).
File NEW (via `sh scripts/mint_oi.sh`, never hand-numbered):
1. restored PRO photo turns replay into Gemini history (`sync_coach.dart:261`
   hardcodes `mode: 'quick'`; filter `coach_interaction_repository.dart:362`
   keys on `mode == 'media'`; PRO rows are channel `app`) — coordinator-verified.
2. deleted exercise logs resurrect on restore (no cloud delete path:
   `workout_write_service.dart deleteLog` removes the Hive key + index only;
   restore re-puts absent keys `sync_workout.dart:916`) — coordinator-verified.
3. `db_maintenance_nightly` (jobid 41) failed every run 09-22→09-26 (5 runs): `VACUUM
   cannot run inside a transaction block` — coordinator-verified live; batch B.
4. offline telemetry-queue replay trips `client_errors_spike` (1 device, rows
   not distinct users) — batch B.
5. 45 s restore-op timeouts on tiny tables on +45–+47 (stall, not volume).
Each new entry records a severity and its scheduling status explicitly (R1
F10, so none reads as silently parked): items 3-4 → "scheduled: batch B
(founder choice 2026-09-26)"; items 1, 2 (P1 — user-visible data wrongness)
and 5 (P2) → "unscheduled — surfaced to the founder 2026-09-26 as candidate
batches D (1) and F (2); awaiting founder scope decision". `Blocked on:` says
exactly that.
Board re-indexed by the pre-commit hook (`build_oi_index.dart`).

## Commits, diagnose-docs, citations (R1 F7)
| # | subject | diagnose-doc (full template) | trailers |
|---|---|---|---|
| 1 | `fix(test): hermetic git env + lone fixture identity — main CI red (U1)` | new id, first instance (no recurrence) | `closes-diagnose:` |
| 2 | `fix(test): wait for the downgrade signal, not a proxy — 5 files (U2)` | new id, `recurrence:` of a3e9b7 + f3c7d2, `related_bugs:` both | `closes-diagnose:` |
| 3 | `fix(gitignore): ignore root .supabase/ token dir (U3)` | new id, first instance | `closes-diagnose:` |
| 4 | `docs(audit): board hygiene — 10 closed (OI-86 stays open for U2b), 10 corrected, 5 filed (U4)` + closure YAML | — (no fix) | 10 SEPARATE `closes-oi: OI-NN` lines (R2 F5 — `check_closes_oi_cited.dart:101` captures one OI per token): OI-63, 66, 168, 198, 206, 209, 224, 234, 235, 242 (10 — OI-86 narrowed, not closed) |
Every diagnose-doc passes `dart run scripts/validate_diagnose_doc.dart`, lists
what was mutated and how many tests reddened (rule 21), and is referenced in
the debugging skill's bug-class table where the class is new (U1). Every commit
goes through `sh scripts/safe_commit.sh "<msg>"` (one positional arg).

## Out of scope (tracked, not dropped)
Batch B (the user's chosen next batch): items 3 + 4 above, OI-178, OI-200.
Everything else in the triage stays on the board as filed/updated in U4.

## Order
U1 → U2 → U3 (code+tests, each its own commit) → U4 (board) → closure YAML →
full `flutter test` once → gate loop (commit) → push only on founder go.
