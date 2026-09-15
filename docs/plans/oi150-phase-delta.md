# OI-150 — couple the phase delta in the restore merge

**Branch:** `oi150-phase-merge` (base `a7a254b8`) · **Blast radius:** `account`
(`scripts/blast_radius_from_diff.dart -`, stdin mode) · **Diagnose id:** to allocate

**Revision 3** — hardened after TWO context-blind review rounds, both `not_converged` (r1: 6
blocking; r2: 5 blocking, **3 of them defects introduced by r1's own hardening** — the class
§4.12.1 says round 2 exists to catch). Every finding was verified against source before acceptance.
§6 and §7 record each and what changed.

The design converged across the rounds rather than churning: r1/F3+N8b replaced a raw `cloud <
local` comparison with a decision-keyed rule; r2/B1+B4+B5 replaced the resulting *boolean* with a
**single pure resolver returning provenance**, plus a per-key carve-out. Each round narrowed the
same predicate; none reopened the direction. ⚠ r2/B1 is the headline: without its one-clause
carve-out this fix would have **created** the symptom it exists to prevent.

⚠ **Tier is fragile, and holding it is a design constraint** (r2/N7): the planned file set measures
`account`, but adding any file under `lib/core/services/sync/` flips it to `platform`
(`docs/blast_radius.yaml:63`), which makes §4.12.4's `bpass: accepted` mandatory.
`reportProgressDemotionsDeclined` takes the whole `ProgressMergeResult`
(`user_repository.dart:79-96`), so **the callers need not change** — keep it that way.

---

## 1. What is actually wrong

### 1.1 `commitPhaseAdvance` emits ONE atomic 4-field delta

`pro_phase_advance.dart:343-348` (fields at `:344-347`, `return true;` at `:349`):

```dart
await UserRepository.instance.updateProgress({
  'current_phase': target,      // advancing        ← guarded
  'current_week': 1,            // reset-per-phase  ← unguarded
  'plan_generated_at': stamp,   // timestamp        ← unguarded
  'phase_started_at': stamp,    // timestamp        ← unguarded
});
```

Its doc comment (`:295-298`) states the atomicity requirement:

> *"A skip skips the WHOLE delta, not just `current_phase`: `current_week: 1` and
> `phase_started_at` written against somebody else's advance would reset the week and the
> phase-start date under them, which is the same class of damage as the demotion."*

The **advance** side honours that. The **restore** side does not.

### 1.1a ⚠ There is a SECOND `current_phase` writer, and it deliberately does NOT carry the delta

`phase_progress_reconciler.dart:138` writes the counter **alone**:

```dart
await UserRepository.instance.updateProgress({'current_phase': target});
```

Its header (`:17-22`) is explicit: *"advance the counter to match the number of phases the user has
moved past, **WITHOUT touching the in-progress plan** (streak + weeks-done preserved) and WITHOUT
deleting or rewriting any schedule row."*

**So "the writer has an atomic delta" is NOT a general truth about `current_phase`** — r1/F4
refuted that, correctly. The coupling below is keyed on **`commitPhaseAdvance`'s** semantic.

**Why the reconciler is nonetheless safe under it.** Keeping local's companions after a
counter-only advance is correct **by that writer's own contract** — `:20-22` says the advance
happens *"WITHOUT touching the in-progress plan"*, so the in-progress plan's dates are exactly what
should survive.

⚠ An earlier revision justified this differently and **wrongly**, claiming the refusal is a
"value-identical no-op because the stale cloud row carries the same companions". r2/B2 refuted it:
cloud's companions are last-writer-wins from **any** device (`sync_profile.dart:315-316`), and
`sync_service.dart:1185-1188` can push a `?? DateTime.now()` this device never held. They may
differ, and a refusal will then be recorded — correctly. Recorded ≠ defective; see §2 Reporting.

### 1.2 The merge dissolves the delta into per-field rules

`user_repository.dart:315` `mergeCloudProgress` — `{...local}`, then cloud-non-null-wins for every
key except the three in `monotonicProgressFields` (`:251-255`, verified literal):
`current_phase`, `deployments_complete`, `total_workouts_done`.

Both callers (`sync_profile.dart:779`, `auth_session_bootstrapper.dart:535`) pass a bare
`.select()` row, so all 23 `user_progress` columns flow through — `phase_started_at`,
`plan_generated_at` and `current_week` included (confirmed in `backups/live_schema_columns.json`).

The merged map is written straight back to Hive (`sync_profile.dart:783`,
`auth_session_bootstrapper.dart:539`), so local and cloud end up agreeing on a shape neither wrote.

### 1.3 Where the damage lands

**Primary path (every returning user):** `restoreLightweightAlways` → `_restoreUserProgress`
(`sync_service.dart:1222-1243`) — the non-empty-Hive branch. Part B covers it.

**Login path:** `auth_session_bootstrapper.dart`, inside one function — guard without its mirror:

| line | what |
|---|---|
| `:535` | guarded `mergeCloudProgress` → `:539` `put('progress', …)` |
| `:576-586` | an 11-line comment from **d1f6b3's B-pass finding F1** explaining why the raw cloud row must not be read here |
| `:587-590` | `phase` read from the **guarded** Hive value ✅ |
| `:597-598` | `startDate` read from **`progressRows.first['phase_started_at']`** — the **raw pre-merge cloud row** ❌ |

Both are arguments to the same `generateAndSchedule(phase:, startDate:)`. F1 wrote the rationale,
applied it to one argument, left the sibling. The plan is regenerated for the **advanced** phase
anchored at the **stale** phase's start date — the `c9e4b7` / `b7f1c8` family. Instance #16 of
`feedback_mistake_guard_without_its_mirror`, whose own #15 lesson is *"FOLLOW THE RETURN VALUE TO
ITS CALL SITE"*.

### 1.4 Three corrections to OI-150's board text

1. **The delta is 4 fields, not 3** — OI-150 omits `plan_generated_at` (`:346`).
2. **`current_week` is not "bumped by the advance"** — `:345` writes the literal `1`, and its Hive
   value is inert in production (`train_provider.dart:703`/`:1027` read it only when
   `calendarWeek <= 0`; `currentWeekColumnProjection` ignores `frozenWeek` unless
   `disable_program_week_projection` is ON). **The user-visible harm is `phase_started_at`.**
3. **OI-150's own evidence refutes its `current_week` claim** — `current_phase=2, current_week=8`
   is the *correct* projection for phase 2 (`getProgramWeek(2) = 4 + week_in_phase`).

⚠ OI-150's file:line citations are ~16 lines stale against this tree. Use the numbers here.

### 1.5 Live state — no production impact, no heal

17 `user_progress` rows on `dedsavbjuwgarrhphgnl` (2026-08-30). Only two at `current_phase >= 2`,
both QA accounts: `amar@gmail.com` (**0 workout_logs, 0 completed** at phase 2 — unreachable
through the product) and the founder's own row (`phase_started_at` = 2026-04-27 = the original plan
start; 84 scheduled rows across three overlapping generations). **No phase discriminator exists in
`scheduled_workouts`** — `week_number` only holds 1..4; `week_numbers = '1,2,3,4'` for both.

**Founder decision 2026-08-30: NO heal** — any value would be invented, not derived. Terminal
state `verified_clean`.

---

## 2. The fix

### Part A — `auth_session_bootstrapper.dart:597-598`

Read `phase_started_at` from the **guarded post-merge Hive map**, the same source `phase` uses,
**via the existing typed accessor `UserRepository.getPhaseStartedAtIso()`** (`:218-219`) — not a
hand-rolled `getProgress()?['phase_started_at']`. r2/B3: that accessor exists precisely so callers
do not hand-read the literal (`:205-217`), and coding rule 4 points at it. A2's positive half
asserts this spelling.

**The cloud-row fallback is DROPPED entirely** (r1/F2 + r1/F6). r1 showed the fallback fires
precisely when the merge refused the cloud value — i.e. only when cloud is known-wrong — and that
keeping the literal in source makes A2's negative half unsatisfiable. Absent/unparseable Hive
value → `DateTime.now()`.

**Extract the decision as a pure resolver** (r2/N4) — `resolvePlanRegenStart({String? hiveIso,
required DateTime now})` → `DateTime`. The regen block sits inside a private, network-bound method
(`auth_session_bootstrapper.dart:566-625`), which is exactly why
`restore_progress_uses_shared_merge_test.dart:42-47` calls its own coverage "presence-only".
Without the extraction A1 collapses into A2's grep and **rule 21 is unmet for Part A**. Precedent:
`currentWeekColumnProjection` (`workout_schedule_read_service.dart:1266-1279`), extracted for this
same reason. The resolver also pins the unparseable-string case (today `DateTime.tryParse(genStr)
?? DateTime.now()`, `:600`).

⚠ **Part A is NOT byte-identical on one path, and that is deliberate** (r2/N3). Today when the
cloud **row** is absent (`progressRows.isEmpty`, `:602-603`) the code returns `DateTime.now()`
unconditionally; reading Hive instead uses a local `phase_started_at` when one exists. This is a
behaviour change in the same "strictly better" direction this file's own `:585-586` comment claims
for `phase`. Stated here rather than left latent, and pinned by A3.

### Part B — `mergeCloudProgress`: couple the delta to the PHASE DECISION

```dart
/// Fields `commitPhaseAdvance` writes ATOMICALLY with `current_phase`
/// (pro_phase_advance.dart:343-348). NOT monotonic — never add them to
/// [monotonicProgressFields]: two are ISO dates and one is a reset-to-1
/// counter, so max-wins on any of them is a guard pointed the wrong way (the
/// `longest_gap_days` mistake, :238-249). Refused as a GROUP, keyed on the
/// phase decision the merge actually took.
///
/// NOT carried by phase_progress_reconciler.dart:138, which advances the
/// counter alone by design (:20-22 — "WITHOUT touching the in-progress
/// plan"). Keeping local's companions after a counter-only advance is
/// therefore CORRECT BY THAT WRITER'S OWN CONTRACT — not, as an earlier
/// draft of this comment claimed, because the values happen to match the
/// cloud row. They need not: cloud's companions are last-writer-wins from
/// any device (sync_profile.dart:315-316), and sync_service.dart:1185-1188
/// can push a `?? DateTime.now()` this device never held.
static const List<String> phaseDeltaCompanionFields = <String>[
  'current_week',
  'phase_started_at',
  'plan_generated_at',
];
```

**Resolve `current_phase` ONCE, return its PROVENANCE, and make the companion rule a function of
that provenance AND per-key local presence.** Round 1 keyed on a re-derived `cloud < local`, which
r1/F3+N8b showed is incoherent under the kill-switch and the malformed branch. Round 2 (B1/B4/B5)
showed a *boolean* pre-pass is still wrong: it has no per-key carve-out, it is undefined at 3 of
the merge's 7 outcomes, and a stored-boolean-plus-loop is two implementations of one rule.

A single pure resolver removes all three at once:

```dart
enum _PhaseProvenance { keptLocal, tookCloud, noWrite }
```

`current_phase` is resolved once by that resolver; the loop **skips the key entirely** (it is
already written), so there is exactly ONE implementation and nothing to drift. All **seven**
outcomes of `mergeCloudProgress` (`user_repository.dart:326-395`) map onto it:

| # | merge branch | line | provenance | companions |
|---|---|---|---|---|
| 1 | cloud value null / key absent | `:327` | `noWrite` | **cloud** |
| 2 | `guardOff` (OI-83 switch rolled) | `:328` | `tookCloud` | **cloud** |
| 3 | cloud non-numeric, local present | `:355` | `keptLocal` | **local** |
| 4 | local absent — reinstall | `:365` | `tookCloud` | **cloud** |
| 5 | local non-numeric, cloud numeric | `:370` | `tookCloud` | **cloud** |
| 6 | demotion refused (`cloud < local`) | `:385` | `keptLocal` | **local** |
| 7 | cloud ≥ local | `:392` | `tookCloud` | **cloud** |

⚠ **Branch 1 + branch 3 together are the r2/B4 trap.** `local absent × cloud non-numeric` takes
branch 3, which `continue`s and writes *nothing* — provenance is `keptLocal` only in the sense that
nothing overwrote an absent value. Resolver contract: `keptLocal` requires local to hold a
**non-null** value. Absent-local at branch 3 therefore yields `noWrite`, not `keptLocal`, so a
reinstalling user can never be refused into having no phase AND no companions — the `:365` P0
shape r2 flagged.

### ⚠ Per-key carve-out — the r2/B1 defect, and the one that would have shipped the symptom

Refuse a companion **only when local actually holds a non-null value for that key.** Otherwise take
cloud, mirroring the monotonic path's own `localRaw == null` rule at `:361-373`.

Without this clause the fix **creates** the bug it prevents. Verified reachable:
`updateProgress`'s seed (`user_repository.dart:452-457`) writes `current_phase`, `current_week`,
`total_workouts_done`, `current_streak_weeks` — **no dates**. `PhaseProgressReconciler` returns
early only on `progress == null` (`:128`), so once seeded it advances `current_phase` **alone**
(`:138`). That yields local = phase-ahead + `phase_started_at` **absent**. A group refusal keyed
only on provenance would refuse the absent companion, leaving the key out of `merged`; Part A then
falls to `DateTime.now()` and the plan regenerates **anchored at today** — the `c9e4b7`/`b7f1c8`
symptom, newly created by the fix. It does not self-heal: `sync_profile.dart:315` pushes the null
and the RPC COALESCEs it, so cloud keeps its good value and every later restore refuses again.

**Fail-safe direction.** The coupling fires only on positive evidence — provenance `keptLocal` AND
local holds the key. Absence of evidence keeps today's behaviour.

### Kill-switch (§4.6)

New **independent** flag `disable_progress_phase_delta_coupling`, default OFF (coupling ON).
Deliberately not folded into `disable_progress_restore_monotonic_merge` — reusing it would make a
rollback of this coupling also disable the shipped OI-83 guard.

### Reporting

`ProgressMergeResult` gains `refusedPhaseDeltaFields: List<String>` (defaulted, mirroring
`malformedFields`). `ProgressDemotion` is not reused — it requires `int` values and two companions
are ISO strings. **Recorded only when local and cloud values actually differ** (r1/N5) — a refusal
that changes nothing is not worth an event. ⚠ r2/B2: this does **not** mean the reconciler case is
silent. Cloud's companions are last-writer-wins from any device, so after a counter-only advance
they may well differ and a refusal WILL be recorded. That is correct — the refusal is real and
correct-by-contract there; it is simply not a *defect* signal, so the event name and its consumers
must not imply one. Both callers already invoke
`reportProgressDemotionsDeclined`; it gains the new list — this is the silent half of the bug, since
nothing emits today when a companion is overwritten.

---

## 3. Tests

### 3.1 ⚠ One EXISTING test asserts the opposite and must be rewritten (r1/F1)

`progress_restore_monotonic_behavioral_test.dart:316-341` — *"a locally-advanced phase survives a
stale cloud restore"* — uses `local {phase 5, current_week 2}` / `cloud {phase 2, current_week 1}`
and asserts:

```dart
// Non-monotonic field still took the cloud value — the merge is scoped,
// not a blanket local-wins.
expect(readBack['current_week'], 1);   // ← becomes 2 under Part B
```

That is `phaseDeltaStale` with a companion key. It must be rewritten to assert the coupled
semantic **and its rationale comment updated** — the comment records a deliberate OI-83 contract
this change reverses, so leaving it would be a false rationale in the tree.

**The file HEADER (`:20-47`) must be updated too** (r2/N5). It states the merge's whole contract
("the set is THREE", "HOW EACH TEST DISCRIMINATES", "COVERAGE HONESTY") and is materially
incomplete after Part B. §3.1's own argument — a false rationale must not be left in the tree —
applies to it verbatim.

**Two independent enumerations agree this is the ONLY existing test affected.** r1 read all 23;
r2 re-enumerated independently and confirmed, adding that `:251` *survives only by luck* (cloud's
`plan_generated_at` is also null there, so both readings converge — worth a deliberate second
assertion rather than leaving it coincidental). r2 also ran
`grep -rn "mergeCloudProgress\|phase_started_at\|plan_generated_at" test/` unpiped: **47 hits
across 7 files**, and the two outside the three known files (`phase_unlock_end_to_end_test.dart`,
`test/supabase/auth_restore_test.dart:80-81`) never reach the merge.

### 3.2 New cases

| # | case | assertion |
|---|---|---|
| B1 | local advanced (phase + 3 companions), cloud stale | all **four** local values survive |
| B2 | reinstall — local `{}`, stale cloud | all four take cloud (byte-identical) |
| B3 | cloud phase ahead | all four take cloud |
| B4 | new coupling flag ON | companions take cloud (verbatim pre-fix) |
| B5 | **OI-83 flag ON** (r1/F3) | phase AND companions all take cloud — no split |
| B6 | cloud `current_phase` non-numeric (r1/N8b) | local phase kept ⇒ companions kept too |
| B7 | unrelated non-monotonic key (`current_streak_days`) while stale | still cloud-wins — no leak |
| B8 | cloud `current_phase` absent | companions take cloud (fail-safe pinned) |
| B9 | companion values IDENTICAL on both sides (r1/N5) | refusal list is **empty** — no false telemetry |
| B10 | **cloud map built with `current_phase` LAST** (r1/F5) | still refused — pins single-resolution |
| **B11** | **`keptLocal` × local MISSING `phase_started_at`** (r2/B1) | companion takes **cloud** — the carve-out |
| **B12** | local `current_phase` non-numeric, cloud numeric (r2/B4 branch 5) | cloud taken ⇒ companions take cloud |
| **B13** | **`merged['current_phase']` byte-identical to today** across all 7 branches (r2/B5) | incl. branch 1: cloud-null ⇒ key **not inserted** |
| A1 | pure `resolvePlanRegenStart` (r2/N4) | stale-refused Hive date → resolves to the **local** date |
| A2 | `restore_progress_uses_shared_merge_test.dart` (r1/F2) | positive: bootstrapper calls `getPhaseStartedAtIso()`; negative (comments stripped, §2.37): no `progressRows.first['phase_started_at']` |
| **A3** | cloud row ABSENT but Hive holds a date (r2/N3) | resolves to the Hive date, not `now()` — pins the intended behaviour change |

### 3.3 Mutation proofs

Rule 24 / §2.39 (delete · reorder · respell) and §2.54 (**run the neutered arm**):

1. empty `phaseDeltaCompanionFields` → B1, B9 redden
2. **resolve `current_phase` inside the loop instead of once up front, consulting running merge
   state → B10 reddens.** ⚠ The mutation's SPELLING decides whether this is a real proof (r2/N1):
   it must consult *running state*, because a mutant that re-derives the rule from `local`/`cloud`
   on demand is order-independent and B10 stays green — reinstating r1/F5 exactly. ⚠ And B10 is a
   **synthetic pin, not a live-bug pin** (r2/N2): `live_schema_columns.json` orders `current_phase`
   *before* all three companions, and both callers preserve that order via `Map.from`. It hardens
   against a future reorder and against PostgREST key order, which is not ours to control.
3. revert Part A's call site to the raw cloud row → A1, A2 redden
4. key on raw `cloud < local` instead of provenance → B5, B6 redden
5. drop the differ-check in reporting → B9 reddens
6. **drop the per-key local-present carve-out → B11 reddens** (r2/B1 — the defect that would have
   shipped the symptom)
7. **map branch 3 with absent local to `keptLocal` instead of `noWrite` → B13 reddens** (r2/B4)

Mutations run in a **dedicated worktree** (OI-134 / §2.40).

---

## 4. Discipline

- ×2 context-blind review (§4.12.1); this is r2 input → `docs/plan-reviews/oi150-phase-merge.md`
  with `---` frontmatter, `review_rounds: >= 2`, `ground_truth_verified: true`, `verdict: converged`.
- Diagnose-doc (rule 22), 25 required fields + `blast_radius`, no `TBD`/`TODO` placeholders
  (`validate_diagnose_doc_lib.dart:8-32`); `closes-oi: OI-150` at commit-msg.
- `/code-review` B-pass self-triggered before the `--no-ff` merge (§4.3).
- SoT `phase_progress_current_phase` gains the **companion-field contract**. ⚠ It already HAS
  `behavioral_test_path` (`docs/sot_registry.yaml:6823`) — r1/N7 corrected r1 of this plan, which
  wrongly said it would gain one.

---

## 5. Named and deliberately NOT in scope

- **Same-phase companion stomp** (r1/N8a): cloud phase *equal* to local ⇒ companions take cloud, so
  a cross-device same-phase date overwrite is untouched. Not the OI-150 mechanism (which requires a
  refused demotion) and coupling on equality would refuse ordinary cloud updates. Named, not fixed.
- **`phase_started_at` has two homes** — `profile['phase_started_at']`
  (`workout_schedule_read_service.dart:396`; read by `rank_service.dart:424`,
  `rank_ladder_screen.dart:360` for rank tenure) vs `progress['phase_started_at']`. A §2.30
  two-representation split. Gets its own OI.
- **Stale citations elsewhere in the repo** found by r1: OI-150's own body (~16 lines off),
  `d1f6b3:35` (cites `auth_session_bootstrapper:373`, now `:587`), `pro_phase_advance.dart:322`
  (cites `sync_restore_completeness.dart:242,411`, actual `254,430`). Corrected where this batch
  touches them; the rest go on the board rather than silently rotting.

---

## 6. Round-1 findings → disposition

| # | finding | verified | disposition |
|---|---|---|---|
| F1 | existing test `:316-341` asserts the opposite | ✅ read verbatim | §3.1 — rewrite it + its rationale comment |
| F2 | A2 unsatisfiable while the fallback exists | ✅ logic | fallback DROPPED; A2 moved + given a positive half |
| F3 | predicate ignores `guardOff` ⇒ incoherent split | ✅ `:324` | predicate re-keyed on the decision; B5 |
| F4 | 2nd writer omits the delta by design | ✅ read `:138`, `:17-22` | §1.1a rewritten; justification corrected |
| F5 | mutation 2 reddens nothing | ✅ Dart LinkedHashMap | B10 added; rationale corrected |
| F6 | fallback fires only when cloud is known-wrong | ✅ logic | dissolved by dropping the fallback |
| N1/N2 | line numbers `344-349`→`343-348`, `294`→`295`, 10→11 lines | ✅ read | corrected (N1 was headed into a permanent source comment) |
| N3 | missed reader `getPhaseStartedAtIso()` | ✅ | named in §1.4 / enumeration |
| N4 | `current_week` push risk under the projection flag | ✅ `:298-303` | stated in §1.4 |
| N5 | refusal telemetry false positives | ✅ | differ-check + B9 |
| N6 | primary path is the restore, not login | ✅ `:1222-1243` | §1.3 restructured |
| N7 | SoT already has `behavioral_test_path` | ✅ `:6823` | §4 corrected |
| N8 | equal-phase and non-numeric cases | ✅ | N8b → B6; N8a → §5 |

---

## 7. Round-2 findings → disposition

All verified against source before acceptance.

| # | finding | verified | disposition |
|---|---|---|---|
| **B1** | group refusal has no absent-local carve-out ⇒ **the fix creates the symptom** | ✅ seed `user_repository.dart:452-457` has NO dates; reconciler `:128` early-returns only on null | §2 per-key carve-out + **B11** + mutation 6. The headline fix of this revision. |
| **B2** | "value-identical no-op" reconciler rationale is false, and was headed into a permanent source comment | ✅ `sync_profile.dart:315-316`, `sync_service.dart:1185-1188` push values this device never held | doc comment rewritten to rest on the reconciler's **contract** (`:20-22`), not on value equality; Reporting corrected |
| **B3** | r1/N3's disposition was FALSE — `getPhaseStartedAtIso()` never entered the body | ✅ appeared only in the §6 row | Part A now names the accessor; A2's positive half asserts that spelling |
| **B4** | predicate undefined at 3 of the merge's **7** outcomes; one dangerous | ✅ branches at `:327,328,355,365,370,385,392` | full 7-row provenance table; `keptLocal` requires non-null local; **B12**, **B13**, mutation 7 |
| **B5** | "reuse the stored outcome" is still two implementations; `merged['current_phase']` byte-identity unpinned | ✅ branch 1 writes no key today | resolver runs once, loop **skips** the key; **B13** pins byte-identity incl. non-insertion |
| N1 | mutation 2's spelling decides whether B10 reddens | ✅ | spelling specified in mutation 2 |
| N2 | B10's premise overstates the live hazard | ✅ `live_schema_columns.json` orders phase first | labelled a synthetic pin |
| N3 | Part A not byte-identical on `progressRows.isEmpty` | ✅ `:602-603` | stated as an intended change + **A3** |
| N4 | A1 not behaviourally drivable; rule 21 unmet for Part A | ✅ `:566-625` is private/network-bound | pure `resolvePlanRegenStart` extracted |
| N5 | §3.1 updates the inline comment but not the file HEADER | ✅ `:20-47` | header added to §3.1 |
| N6 | `pro_phase_advance.dart:320-322` cites 3 stale sites, plan named 1 | ✅ | all three recorded in §5 |
| N7 | tier flips to `platform` if any `lib/core/services/sync/` file is touched | ✅ re-ran the classifier | stated as a design constraint in the header |
| N8-10 | citation nits (`:31-33`, `:20-22`, `:601`) | ✅ | corrected inline |

### Why this was hardened rather than SPLIT (§4.12.1)

§4.12.1 says successive reviews surfacing new material issues means the unit is too large — split
and ship the smallest converged piece. That trigger was weighed and **does not apply here**:

- **Part A is a no-op without Part B.** Without the coupling, the post-merge Hive value equals the
  cloud value, so reading Hive instead of the raw row changes nothing. There is no smaller
  shippable piece; "split" would mean shipping nothing.
- **The complexity is not size, it is branch-completeness.** Both rounds converged on the same
  ~15-line predicate in one function. Narrowing the coupled field set (e.g. `phase_started_at`
  alone) would not reduce the 7-branch enumeration by one row — the hard part is invariant to it.
- **Each round narrowed the same rule; none reopened the direction.** That is convergence, not
  churn.

The genuine stopping rule for this batch: **if round 3 surfaces a new material defect in the
resolver's branch mapping, the predicate is beyond what review can settle** — at that point the
merge function gets a property-based test over all 7 branches instead of another prose round.
