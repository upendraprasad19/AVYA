# Progress-write durability + restore authority (OI-150)

**Date:** 2026-08-30 · **Branch:** `oi150-phase-merge` · **Supersedes** the merge-only approach in
`docs/plans/oi150-phase-delta.md` (revisions 1–3, all `not_converged` — see §8).

---

## 1. Problem

Two defects with one cause, found while investigating OI-150.

### 1.1 A progress write can vanish with nothing recording the debt

`commitPhaseAdvance` writes four fields to Hive, then pushes fire-and-forget:

```dart
unawaited(SyncService.instance.syncProgressNow());   // user_repository.dart:448
```

The upload exists only as an in-flight HTTP request in RAM. Process death — task-swipe, an Android
low-memory kill, a network drop — destroys it, and **nothing anywhere records that a write was
owed.** No retry, because nothing knows.

### 1.2 The restore path contradicts the push path about who owns the data

`_syncUserProgress` (`sync/sync_profile.dart:345`) pushes through an optimistic-locked RPC and, on
version conflict, re-fetches the version and **re-asserts the same local values**. Its comment
states the model:

> *"these fields are client-authoritative … cloud is a passive mirror for cron/report consumption …
> re-asserting local values against the fresh version is the correct reconciliation, not a 3-way
> merge."*

`mergeCloudProgress` (`user_repository.dart:315`) does the opposite: **cloud-non-null-wins for every
key except three.** So the passive mirror overwrites the authority.

`commitPhaseAdvance` writes `current_phase` / `current_week` / `phase_started_at` /
`plan_generated_at` as one atomic sentence. OI-83 guarded the first. The other three still take
cloud, so a stale cloud row splits the sentence — phase advances, its dates revert — and the merged
result is written back to Hive (`sync_profile.dart:783`), so both sides then agree on a state
neither ever wrote.

**Damage:** on the next login `auth_session_bootstrapper.dart:597` anchors a plan regeneration on
that reverted date, producing a Phase-2 plan starting a month in the past — the `c9e4b7` / `b7f1c8`
"expired / wrong week / missing Phase I" family.

### 1.3 Live impact

Zero real users. All 17 `user_progress` rows are ours; the only two at `current_phase >= 2` are QA
accounts (`amar@gmail.com` — 0 workout_logs at phase 2, unreachable through the product — and the
founder's own, with 84 scheduled rows across three overlapping generations). **No heal** (founder,
2026-08-30): `scheduled_workouts.week_number` only holds 1..4, so no phase discriminator exists and
any heal value would be invented. Terminal state `verified_clean`.

---

## 2. Field enumeration — the criterion, derived from code

All 23 `user_progress` columns, grouped by who may write them.

### Group A — the phase delta. Written atomically by ONE client writer; **zero server writers**

| Field | Merge today |
|---|---|
| `current_phase` | monotonic (local max wins) — OI-83 |
| `current_week` | **cloud wins** ← defect |
| `phase_started_at` | **cloud wins** ← defect |
| `plan_generated_at` | **cloud wins** ← defect |

Verified: `phase_started_at` and `plan_generated_at` have **0** Edge Function references;
`current_phase` / `current_week` EF references are all READS (`weekly-report:148`,
`weekly-recap-ready:226`, `beat-my-coach:144`, `getPromotionStatus:149`).

### Group B — the server writes these. Local cannot be authoritative

| Field | Server writer |
|---|---|
| `detected_experience_level` | `weekly-recalc/index.ts:365` |
| `experience_last_calculated` | `weekly-recalc/index.ts:366` — **no client file touches it** |
| `total_workouts_done` | `weekly-recalc/index.ts:367` (`Math.max`, monotonic server-side too) |
| `streak_progress_version` | the RPC (`115_…:207`) — an optimistic-lock counter the client only adopts |
| `longest_gap_days` | server `GREATEST`s it; **no client writer exists** |

### Group C — cloud must be able to LOWER these

`current_streak_days`, `current_streak_weeks` — a streak legitimately resets to 0. Local-wins would
make a genuinely broken streak unfixable from the server.

### Group D — already has its own merge

`streak_freezes_available` / `_used_dates` / `_last_refill` / `_first_pro_grant_done` —
`StreakProgressService.mergeFreezeProgress`. Two merge rules over one field is how drift starts.

### Group E — not user data, or not this device's

`id`, `user_id` (stripped pre-merge), `created_at`, `updated_at`, `plan_json` (its own snapshot-blob
concept, §2.30), and `onesignal_player_id` — **device-specific**, so the cloud value belongs to a
different phone.

### The criterion

> Local-authoritative applies to fields written **atomically by a single client writer** with **no
> server writer at all.**

Exactly Group A satisfies it. This is mechanically checkable, not a judgement call.

**"Whole map with exceptions" was considered and REJECTED** — it needs ~11 exceptions across 19 real
fields, which is the same per-field list that has now been wrong three times, wearing a rule's
clothing.

---

## 3. Design

### Unit 2a — profile carries the SAME defect, and must be fixed with it

Established 2026-08-30 by enumerating all 12 `patchProfile` / `updateProfile` call sites.
`_restoreUserProfile` (`sync/sync_profile.dart:642-649`) merges cloud over local wholesale —
`{...existing, for (e in cloud.entries) if (e.value != null) e.key: e.value, …}` — with **no guard
of any kind**, not even the monotonic one progress received from OI-83.

Two client writers put semantically-coupled fields in one map:

- `profile_provider.dart:103` — `{...targets.toMap(), 'activity_level': resolvedActivity}`. Its own
  comment: *"Persist computed targets AND the resolved activity level so downstream code that reads
  'activity_level' directly stays consistent."* Splitting it yields macros inconsistent with the
  activity level they were computed from.
- `tool_dispatcher.dart:997` — `primary_goal` + `goal_changed_at` + `goal_changed_via` +
  `previous_goal`, written by the AI coach on a goal change. Splitting it yields an audit trail
  that contradicts the goal.

**Profile does NOT get Unit 2's coupling rule — it gets something smaller and better.**

**Why the coupling rule cannot transfer.** Progress has a natural version stamp: `current_phase`.
Profile has none. `updated_at` is a cloud column that the client never pushes (**absent from the
34-field payload — verified**), so the server sets it on receipt: it records when the cloud last
*heard from* the device, not when the device last *changed* something. The device clock is not a
substitute — this app ships a time-travel simulator that moves it deliberately. So "newer wins" has
no honest discriminator here, and inventing one means a new column plus a migration plus a backfill.

**The better answer: the derived fields do not need merging — they need recomputing.**

The profile splits cleanly into INPUTS (weight, height, DOB, gender, activity, days/week, goal) and
values DERIVED from them (`bmr`, `tdee`, `daily_calories`, `protein_grams`, `carbs_grams`,
`fat_grams`, `activity_level`). Merge the inputs — they are independent scalars with no coupling —
then **recompute the derived set from whatever inputs won.** Nothing is left to keep consistent,
because consistency is regenerated rather than preserved.

**This is cheap, and three crosschecks confirm it:**

1. `BmrCalculator.calculateTargets(...)` and `BmrCalculator.resolveActivityLevel(...)` are already
   **static and pure** (`profile_provider.dart:81,87`). Only the read-state/write-state wrapper is
   provider-bound, so **the recompute runs INSIDE `_restoreUserProfile`'s merge, before the
   `put()`** — no provider call from a service, no layering violation, no extra cloud push, no
   `skipSync` juggling.
2. **No manual macro override exists** — zero UI writes to `daily_calories` / `protein_grams` across
   `lib/features/profile/` and `lib/features/nutrition/`. Recompute cannot destroy user input,
   because there is none to destroy.
3. It matches the app's own canonical pattern: `edit_profile_screen.dart:1806-1807` is literally
   *update inputs, then recompute targets*. Restore is currently the only mutation path that skips
   step two.

⚠ **The `c3f2d8` trap the recompute must not reopen.** `body_fat_percent` once carried a fabricated
`?? 18.0` default that fed Katch-McArdle for every skip-user. The recompute path must preserve NULL
rather than defaulting, and route through `BmrCalculator.bodyFatForCalc` — the shared selector built
for exactly this. Pin it with a test: a restored profile with null body fat must not acquire a value.

**Residual, named rather than hidden: `primary_goal` can still revert.** It is an INPUT, so
recompute does not fix it. Its three companions (`goal_changed_at`, `goal_changed_via`,
`previous_goal`) are **Hive-only — not cloud columns**, so a restore cannot touch them; the split is
therefore the reverse of what an earlier draft of this section claimed. The goal reverts while the
local audit trail keeps describing the change that just got undone. One cloud field plus three local
companions; it needs its own small answer in the plan, not the group rule.

**Correction recorded** (r-profile, 2026-08-30): an earlier draft said the AI-coach goal write was a
four-field cloud split producing "an audit trail that contradicts the goal." Three of those four are
Hive-only. The defect is real and the direction is inverted.

### Unit 1 — route progress AND profile writes through the existing outbox

`SyncQueue` (`lib/core/services/sync_queue.dart`) is already a real outbox: Hive-persisted,
exponential backoff, dead-letter + telemetry, `SyncBanner` UI, drains on launch / connectivity /
5-min timer / manual retry. Built for `docs/superpowers/specs/2026-04-17-sync-reliability.md`
Pillar B.

Its state today: gated on `sync_reliability_v1` (**default false**), with **one** registered
executor — `upsert_user_profile`. `user_progress` never touches it, and would not even if the flag
were flipped.

**Change:** register a `sync_user_progress` executor and enqueue on failure.

⚠ **The queue entry must be a MARKER, not a payload.** The RPC takes `p_expected_version`; a payload
replayed ten minutes later carries a stale version and is rejected. Because Group A is
client-authoritative, the executor should re-read **current Hive state** at drain time and push
that — the latest truth, not a fossil. The existing
`_retrySyncUserProgressOnceAfterConflict` already does the version re-fetch this needs.

### Unit 2 — the phase delta moves as one unit

The three review rounds produced an increasingly elaborate per-field predicate over
`mergeCloudProgress`'s seven branches. §2's criterion makes that unnecessary. The four Group-A
fields are one versioned record, and **`current_phase` is its version stamp**:

> Whichever side has the higher `current_phase` owns **all four** fields.

| state | outcome |
|---|---|
| local phase absent (reinstall) | cloud higher ⇒ all four from cloud — byte-identical to today |
| local advanced, cloud stale | local higher ⇒ all four stay local ← **the fix** |
| cloud advanced (second device) | cloud higher ⇒ all four from cloud ← correct, and pure local-wins would break this |
| equal | cloud (unchanged from today) |
| either side absent / non-numeric | fall back to today's behaviour exactly |

**Why this is materially better than revisions 1–3.** It leaves `current_phase` in the loop
untouched — so its `declinedFields` / `malformedFields` telemetry keeps working (r3/B1), and the
seven-branch cascade is not duplicated for the other two monotonic fields (r3/B2). It is one
comparison with three guard cases, not seven branches times per-field rules. The whole
provenance-resolver design is withdrawn.

### Unit 3 — put the flag on the board

`sync_reliability_v1` appears in **neither** `docs/ship_dark_pending_review.yaml` **nor**
`docs/audit/open_issues.md`. It was dark-launched in April and forgotten — exactly the failure that
ledger exists to catch. The April spec's own checklist (§6) shows items 1–9 shipped (all artifacts
verified present, banner mounted in `home_screen.dart` + `profile_content.dart`) and items 10–13
never done: no `sync_reliability_flow_test.dart`, flag never flipped, checklist never updated.

Register it, and correct the stale checklist in the April spec.

### Kill-switches (§4.6)

- Unit 1 rides the existing `sync_reliability_v1`.
- Unit 2 gets its own `disable_progress_phase_delta_coupling`, independent of
  `disable_progress_restore_monotonic_merge` so rolling back this coupling cannot also disable the
  shipped OI-83 guard.

---

## 4. Testing

**Unit 2 (behavioral, `progress_restore_monotonic_behavioral_test.dart`):** the five §3 rows, plus —
a companion absent from local while phase is present (the r2/B1 shape: `updateProgress`'s seed at
`user_repository.dart:452-457` writes `current_phase` but **no dates**, and
`PhaseProgressReconciler:138` then advances the phase alone); `current_phase`'s existing
`declinedFields`/`malformedFields` emissions unchanged; unrelated non-monotonic keys still cloud-win.

⚠ **One EXISTING test must be rewritten, not merely extended:**
`progress_restore_monotonic_behavioral_test.dart:316-341` asserts `expect(readBack['current_week'],
1)` under the comment *"the merge is scoped, not a blanket local-wins"* — a deliberate OI-83
contract this change reverses. Its **rationale comment and the file header (`:20-47`)** must be
updated too, or a false rationale is left in the tree. Two independent review rounds confirmed this
is the only existing test affected.

**Unit 1:** the April spec's item 10 (`sync_reliability_flow_test.dart`) — enqueue on failure, drain
on reconnect, and specifically that a drained progress op pushes **current** Hive state rather than
the enqueued snapshot.

**Mutation proofs** (rule 24 / §2.39, and **run the neutered arm**, §2.54): drop the group rule →
the local-advanced case reddens; invert the comparison → the cloud-advanced case reddens; make the
queue executor replay a stored payload → the current-state test reddens. Run in a dedicated
worktree (OI-134).

---

## 5. Risk

Unit 1 is platform-tier and changes sync behaviour for all users — and flipping `sync_reliability_v1`
also changes `user_profile` behaviour, its one existing op. **Doing this now is the low-risk
option:** 17 accounts, all ours, zero real users. Every day after launch this gets more expensive,
so deferring it is the riskier choice, not the safer one.

Unit 2 alone is `account`. ⚠ Touching any file under `lib/core/services/sync/` lifts the batch to
`platform` (`docs/blast_radius.yaml:63`), which makes `bpass: accepted` mandatory — Unit 1 does
touch it, so this batch is **platform**.

---

## 6. Sequencing

Unit 2 → Unit 1 → Unit 3. Unit 2 is self-contained and closes the user-visible defect; Unit 1 is the
larger infrastructure change and benefits from landing on a restore path that is already correct.
Per §4.11 the flag ledger entry (Unit 3) lands with Unit 1, not after it.

---

## 7. Decisions (both former open questions — RESOLVED 2026-08-30)

### 7.1 Flip `sync_reliability_v1` in THIS batch — founder, 2026-08-30

The flag flips with the fix rather than shipping dark.

**What the flip actually changes — measured, because an earlier draft overstated it.**
`_syncReliabilityEnabled` has exactly **one** gate in the whole codebase (`sync_profile.dart:247`;
the getter is `sync_service.dart:626`). Flipping it changes profile-sync behaviour on the
**failure path only** — enqueue-and-retry instead of bubble-up-and-`debugPrint`. The success path
is byte-identical. So the blast is far smaller than "it changes `user_profile` behaviour" implied.

**It still does not qualify for §4.12.4's lighter ship-dark tier** — but for the correct reason:
§4.12.4 requires the full ×2 review *on the commit that flips a flag's default*, no exceptions,
because that is the moment real user risk starts. Full ×2 plus `bpass: accepted` apply.

### 7.2 The outbox covers `progress` and `profile` ONLY — not the other ~28 sites

Enumerated and measured 2026-08-30 rather than assumed.

**The decisive finding: a lost write already self-heals within a day.** `weeklyFullSync` is
misnamed — `_fullSyncInterval = Duration(days: 1)` (`sync_service.dart:532`) — so it is a DAILY
full re-push on app launch across **20** surfaces, `_syncUserProgress` among them.

So the outbox is **not** about permanent data loss. Its value is closing the window in which a
stale cloud row is **merged back into Hive**, because there the staleness does not sit harmlessly
in the backup — it corrupts the phone, and the next daily sync faithfully pushes the corruption up.

Only two surfaces merge cloud back that way:

| surface | merge-back path | status |
|---|---|---|
| `syncProgressNow` | `mergeCloudProgress` | proven defect (OI-150) |
| `syncProfileNow` | `_restoreUserProfile:642-649` | **same class, NO guard at all** (§2.1a) |

The other ~28 sites carry data that is additive-by-id on restore (`custom items`, `saved meals`,
`diet plan`, `notification inbox`), completion-preserving (`syncWorkoutData`), or derived and
recomputed daily (`pushSnapshot`, ~10 sites). Queueing `pushSnapshot` would persist a large derived
blob for no gain.

**Live evidence the lost write is real, not theoretical:** `sync_user_progress_retry_dropped` —
**8 events across 3 users** in `client_errors` (30-day window). The progress push hits a version
conflict, retries once, and drops.

**Filed rather than bundled, with terminal board records (§4.2 — not deferrals):**
- **OI-151** — telemetry outweighs user data 1.7:1; `restore_op_done` is 64% of it and scales to
  ~240k rows/day at 10k DAU. Bounded today (~1.2% of the 2000/user/day cap). A pre-launch tuning
  decision, not a defect.
- **OI-152** — 8 call sites fire `syncX()` + `pushSnapshot()` back to back, doubling round-trips
  per user action. An efficiency win, not a correctness one.

### 7.3 Volume is NOT a reason to act

Measured live: ~5–10 user-generated writes per user per active day. All real user data across all
17 accounts and ~4 months is ~1,147 rows. Nowhere near any Supabase limit. **This batch is
justified by correctness alone; do not optimise for cost.**

---

## 8. Why the earlier approach was withdrawn

`docs/plans/oi150-phase-delta.md` went through three context-blind review rounds, all
`not_converged` — r1: 6 blocking; r2: 5 (three introduced by r1's own hardening); r3: 5 (again
mostly from r2's). Each round narrowed the same per-field predicate over seven merge branches.

The plan was compensating for a lost write rather than preventing one, and re-deriving a
who-owns-this-field rule that the push path had already answered in a comment. Stepping back to the
root cause dissolved the hard part: keying the group on `current_phase` replaces the seven-branch
provenance resolver with one comparison.

Findings that survive the withdrawal and are carried into §4: r1/F1 + r3 (the existing test that
must be rewritten), r2/B1 (the absent-companion case), r3/B1 (don't break `current_phase`'s
telemetry), r3/B2 (don't duplicate the cascade), r3/B3 (Part A needs a pure resolver and a
kill-switch — folded into Unit 2).
