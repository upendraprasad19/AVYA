# Progress + Profile Write Durability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop a not-yet-pushed progress or profile write from being silently lost, and stop a stale cloud row from splitting a coupled set when it is merged back into Hive.

**Architecture:** Three changes to the sync/restore seam. (1) The four fields `commitPhaseAdvance` writes atomically move as one group, keyed on which side the merge took `current_phase` from. (2) Profile's derived nutrition targets are *recomputed* after a restore instead of being merged field-by-field, which dissolves their coupling entirely. (3) Progress and profile writes route through the existing `SyncQueue` outbox so app death cannot lose them, and `sync_reliability_v1` flips on.

**Tech Stack:** Flutter/Dart, Hive (primary store), Supabase Postgres via PostgREST + an optimistic-locked RPC, Riverpod.

**Spec:** `docs/superpowers/specs/2026-08-30-progress-write-durability-design.md`

## Global Constraints

- **Hive-first (coding rule 1).** Never block UI on Supabase. Cloud writes stay background/async.
- **Repository pattern (rule 4).** No Supabase or Hive access from widgets.
- **No new `?? <literal>` default on `body_fat_percent`** — diagnose `c3f2d8`. Preserve NULL.
- **Every fix ships a diagnose-doc** (rule 22) + a behavioral regression test (rule 21) that fails without the fix.
- **Kill-switch required** (§4.6) for each behaviour change; old path reachable when the gate is closed.
- **Blast radius is `platform`** — touching `lib/core/services/sync/**` (`docs/blast_radius.yaml:63`). Requires ×2 plan review + `bpass: accepted` before the `--no-ff` merge.
- **Commit via `sh scripts/safe_commit.sh "<message>"`** — one positional arg, never a flag. Never raw `git commit`. Never `--no-verify`.
- **Work in the worktree** `.claude/worktrees/oi150-phase-merge`, never the shared main folder (§4.13).
- **Do not run `flutter test` while another suite is running** — the Dart wrapper serializes on the SDK lock (§2.55).
- **MUTATE IT AND RUN IT (rule 21, added 2026-08-30).** Any fix whose only NEW protection is a test written or extended by this batch must be mutated once before that test is believed — **behavioral and e2e tests included, not just source-greps** — and **the diagnose-doc must state what was mutated and how many tests reddened.** ⚠ Confirm the mutation actually APPLIED (`grep -c` the removed token) — a regex that silently matched nothing makes a green run read as proof of nothing. ⚠ Confirm the FIXTURE reproduces a state the real workflow produces; check it against HISTORY, not against the code under test. Self-attested — no gate enforces it.
- **Run the local gate loop BEFORE dispatching any review round that has a draft diff (2026-08-30).** `sh scripts/pre-commit.sh` — the whole loop, never a hand-picked subset. Reviewer attention is for mechanism; roughly half of one recent batch's 17 findings were mechanical things the gates catch for free.
- **Before landing any extraction/move/rename, grep the test tree for what is moving (2026-08-30).** Source-grep contracts pin code by LOCATION, so relocating it breaks assertions in files the diff never opens, invisible until the pre-push full suite. **Fix by REPOINTING, never by deleting or loosening.** Already applied to this plan — see the Rule-C notes in Tasks 3, 4 and 5.
- **`safe_merge.sh` now runs a pre-merge `bpass_review` verdict precheck (advisory).** A plan-review record claiming `bpass: accepted` must be matched by a `bpass_review:` file containing a line-anchored `verdict: accepted`, committed **on the feature branch** (the script reads `git show "$BRANCH:<path>"`, not the working tree). Task 9 produces both.

---

### Task 1: Pure phase-provenance resolver

**Files:**
- Modify: `lib/shared/repositories/user_repository.dart` (add above `mergeCloudProgress`, currently at `:315`)
- Test: `test/contracts/progress_restore_monotonic_behavioral_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `enum PhaseProvenance { keptLocal, tookCloud, noWrite }` and `static PhaseProvenance UserRepository.resolvePhaseProvenance({required Map<String, dynamic> local, required Map<String, dynamic> cloud, required bool guardOff})`. Task 2 consumes both.

**Why a separate task:** this is the piece three review rounds got wrong. It is pure, so it can be exhaustively tested against all seven merge branches without Hive or a network.

- [ ] **Step 1: Write the failing tests**

Add to `test/contracts/progress_restore_monotonic_behavioral_test.dart`, inside the existing `group('mergeCloudProgress (pure)', ...)`:

```dart
group('resolvePhaseProvenance — all 7 merge branches', () {
  test('branch 1: cloud current_phase null → noWrite', () {
    expect(
      UserRepository.resolvePhaseProvenance(
          local: {'current_phase': 3}, cloud: {'current_phase': null}, guardOff: false),
      PhaseProvenance.noWrite,
    );
  });

  test('branch 1b: cloud key absent → noWrite', () {
    expect(
      UserRepository.resolvePhaseProvenance(
          local: {'current_phase': 3}, cloud: {}, guardOff: false),
      PhaseProvenance.noWrite,
    );
  });

  test('branch 2: guardOff → tookCloud even when cloud is lower', () {
    expect(
      UserRepository.resolvePhaseProvenance(
          local: {'current_phase': 5}, cloud: {'current_phase': 2}, guardOff: true),
      PhaseProvenance.tookCloud,
    );
  });

  test('branch 3: cloud non-numeric with local present → keptLocal', () {
    expect(
      UserRepository.resolvePhaseProvenance(
          local: {'current_phase': 4}, cloud: {'current_phase': 'x'}, guardOff: false),
      PhaseProvenance.keptLocal,
    );
  });

  test('branch 3b: cloud non-numeric with local ABSENT → noWrite, not keptLocal', () {
    // Round-2 finding B4: "kept local" must require local to actually hold a
    // value, or a reinstalling user is refused into having no phase at all.
    expect(
      UserRepository.resolvePhaseProvenance(
          local: {}, cloud: {'current_phase': 'x'}, guardOff: false),
      PhaseProvenance.noWrite,
    );
  });

  test('branch 4: local absent (reinstall) → tookCloud', () {
    expect(
      UserRepository.resolvePhaseProvenance(
          local: {}, cloud: {'current_phase': 2}, guardOff: false),
      PhaseProvenance.tookCloud,
    );
  });

  test('branch 5: local non-numeric, cloud numeric → tookCloud', () {
    expect(
      UserRepository.resolvePhaseProvenance(
          local: {'current_phase': 'junk'}, cloud: {'current_phase': 2}, guardOff: false),
      PhaseProvenance.tookCloud,
    );
  });

  test('branch 6: cloud lower than local → keptLocal', () {
    expect(
      UserRepository.resolvePhaseProvenance(
          local: {'current_phase': 5}, cloud: {'current_phase': 2}, guardOff: false),
      PhaseProvenance.keptLocal,
    );
  });

  test('branch 7: cloud equal or higher → tookCloud', () {
    expect(
      UserRepository.resolvePhaseProvenance(
          local: {'current_phase': 2}, cloud: {'current_phase': 2}, guardOff: false),
      PhaseProvenance.tookCloud,
    );
    expect(
      UserRepository.resolvePhaseProvenance(
          local: {'current_phase': 2}, cloud: {'current_phase': 6}, guardOff: false),
      PhaseProvenance.tookCloud,
    );
  });

  test('a JSON double from PostgREST compares numerically', () {
    expect(
      UserRepository.resolvePhaseProvenance(
          local: {'current_phase': 5}, cloud: {'current_phase': 2.0}, guardOff: false),
      PhaseProvenance.keptLocal,
    );
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/contracts/progress_restore_monotonic_behavioral_test.dart --plain-name "resolvePhaseProvenance"`
Expected: FAIL — `Undefined name 'PhaseProvenance'` / `The method 'resolvePhaseProvenance' isn't defined`.

- [ ] **Step 3: Write the implementation**

In `lib/shared/repositories/user_repository.dart`, add at top level (outside the class, near `ProgressDemotion`):

```dart
/// Which side the merge took `current_phase` from. The three companion fields
/// `commitPhaseAdvance` writes atomically with it (pro_phase_advance.dart:343-348)
/// are keyed on this, so the four move as one group.
///
/// `keptLocal` REQUIRES local to hold a non-null value. A branch that keeps
/// "whatever local had" when local had nothing is `noWrite`, not `keptLocal` —
/// conflating them refuses a reinstalling user into having no phase at all.
enum PhaseProvenance { keptLocal, tookCloud, noWrite }
```

And inside `class UserRepository`, immediately above `mergeCloudProgress`:

```dart
  /// Resolves which side wins `current_phase`, WITHOUT mutating anything.
  ///
  /// Mirrors the seven exits of [mergeCloudProgress]'s loop for that one key.
  /// Kept pure and separate so every branch is testable without Hive, and so
  /// the companion-coupling rule keys on the decision the merge actually takes
  /// rather than re-deriving a comparison that can drift from it.
  @visibleForTesting
  static PhaseProvenance resolvePhaseProvenance({
    required Map<String, dynamic> local,
    required Map<String, dynamic> cloud,
    required bool guardOff,
  }) {
    const key = 'current_phase';
    final cloudRaw = cloud[key];
    // Branch 1 — cloud null / key absent: the loop `continue`s, nothing written.
    if (cloudRaw == null) return PhaseProvenance.noWrite;
    // Branch 2 — kill-switch: cloud-non-null-wins verbatim, pre-OI-83 behaviour.
    if (guardOff) return PhaseProvenance.tookCloud;

    final localRaw = local[key];
    // Branch 3 — cloud non-numeric: the loop keeps whatever local had.
    if (cloudRaw is! num) {
      return localRaw == null
          ? PhaseProvenance.noWrite
          : PhaseProvenance.keptLocal;
    }
    // Branch 4 — absent local is the reinstall case, not corruption.
    if (localRaw == null) return PhaseProvenance.tookCloud;
    // Branch 5 — local corrupt, cloud good: cloud repairs it.
    if (localRaw is! num) return PhaseProvenance.tookCloud;
    // Branches 6 / 7 — the monotonic comparison.
    return cloudRaw.toInt() < localRaw.toInt()
        ? PhaseProvenance.keptLocal
        : PhaseProvenance.tookCloud;
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/contracts/progress_restore_monotonic_behavioral_test.dart --plain-name "resolvePhaseProvenance"`
Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
sh scripts/safe_commit.sh "feat(sync): pure phase-provenance resolver over all 7 merge branches

Keys the coming companion coupling on the decision mergeCloudProgress
actually takes, rather than a re-derived comparison that can drift.
keptLocal requires a non-null local value so a reinstall cannot be
refused into having no phase.

Test: test/contracts/progress_restore_monotonic_behavioral_test.dart"
```

---

### Task 2: Couple the three companion fields to that decision

**Files:**
- Modify: `lib/shared/repositories/user_repository.dart` — `mergeCloudProgress` (`:315-395`), `ProgressMergeResult` (`:52-68`)
- Modify: `test/contracts/progress_restore_monotonic_behavioral_test.dart` — **rewrite** the existing test at `:316-341` and its file header at `:20-47`

**Interfaces:**
- Consumes: `PhaseProvenance`, `UserRepository.resolvePhaseProvenance` (Task 1).
- Produces: `UserRepository.phaseDeltaCompanionFields` (`List<String>`), `ProgressMergeResult.refusedPhaseDeltaFields` (`List<String>`, defaulted). Task 6 reads neither; Task 9 documents both.

⚠ **This task rewrites an existing passing test.** `:316-341` asserts `expect(readBack['current_week'], 1)` under the comment *"the merge is scoped, not a blanket local-wins"* — a deliberate OI-83 contract this change reverses. Two independent review rounds confirmed it is the **only** existing test affected.

- [ ] **Step 1: Write the failing tests**

Add inside `group('mergeCloudProgress (pure)', ...)`:

```dart
group('phase-delta companion coupling', () {
  Map<String, dynamic> localAdvanced() => {
        'current_phase': 2,
        'current_week': 1,
        'phase_started_at': '2026-05-25T00:00:00.000Z',
        'plan_generated_at': '2026-05-25T00:00:00.000Z',
      };
  Map<String, dynamic> cloudStale() => {
        'current_phase': 1,
        'current_week': 4,
        'phase_started_at': '2026-04-27T00:00:00.000Z',
        'plan_generated_at': '2026-04-27T00:00:00.000Z',
      };

  test('local advanced: all FOUR local values survive a stale cloud', () {
    final r = UserRepository.mergeCloudProgress(
        local: localAdvanced(), cloud: cloudStale());
    expect(r.merged['current_phase'], 2);
    expect(r.merged['current_week'], 1);
    expect(r.merged['phase_started_at'], '2026-05-25T00:00:00.000Z');
    expect(r.merged['plan_generated_at'], '2026-05-25T00:00:00.000Z');
    expect(r.refusedPhaseDeltaFields,
        containsAll(['current_week', 'phase_started_at', 'plan_generated_at']));
  });

  test('reinstall: empty local adopts all four from cloud, byte-identical', () {
    final r = UserRepository.mergeCloudProgress(
        local: <String, dynamic>{}, cloud: cloudStale());
    expect(r.merged['current_phase'], 1);
    expect(r.merged['current_week'], 4);
    expect(r.merged['phase_started_at'], '2026-04-27T00:00:00.000Z');
    expect(r.merged['plan_generated_at'], '2026-04-27T00:00:00.000Z');
    expect(r.refusedPhaseDeltaFields, isEmpty);
  });

  test('cloud ahead (second device): all four come from cloud', () {
    final r = UserRepository.mergeCloudProgress(
      local: {'current_phase': 1, 'current_week': 2, 'phase_started_at': 'LOCAL'},
      cloud: {'current_phase': 3, 'current_week': 9, 'phase_started_at': 'CLOUD'},
    );
    expect(r.merged['current_phase'], 3);
    expect(r.merged['current_week'], 9);
    expect(r.merged['phase_started_at'], 'CLOUD');
    expect(r.refusedPhaseDeltaFields, isEmpty);
  });

  test('r2/B1 carve-out: a companion ABSENT from local still takes cloud', () {
    // Reachable: updateProgress' seed (user_repository.dart:452-457) writes
    // current_phase but no dates, and PhaseProgressReconciler:138 then advances
    // the phase alone. Refusing an absent key would leave phase_started_at out
    // of the map entirely and anchor the next plan regen at today.
    final r = UserRepository.mergeCloudProgress(
      local: {'current_phase': 2, 'current_week': 1}, // no dates
      cloud: cloudStale(),
    );
    expect(r.merged['current_phase'], 2);
    expect(r.merged['current_week'], 1);
    expect(r.merged['phase_started_at'], '2026-04-27T00:00:00.000Z');
    expect(r.merged['plan_generated_at'], '2026-04-27T00:00:00.000Z');
  });

  test('identical values are not reported as a refusal', () {
    final r = UserRepository.mergeCloudProgress(
      local: {'current_phase': 2, 'phase_started_at': 'SAME'},
      cloud: {'current_phase': 1, 'phase_started_at': 'SAME'},
    );
    expect(r.merged['phase_started_at'], 'SAME');
    expect(r.refusedPhaseDeltaFields, isEmpty);
  });

  test('OI-83 kill-switch ON: phase AND companions all take cloud, no split', () async {
    await HiveService.instance.configBox
        .put('disable_progress_restore_monotonic_merge', true);
    addTearDown(() => HiveService.instance.configBox
        .delete('disable_progress_restore_monotonic_merge'));
    final r = UserRepository.mergeCloudProgress(
        local: localAdvanced(), cloud: cloudStale());
    expect(r.merged['current_phase'], 1);
    expect(r.merged['current_week'], 4);
    expect(r.merged['phase_started_at'], '2026-04-27T00:00:00.000Z');
  });

  test('new coupling kill-switch ON: companions take cloud, phase still guarded',
      () async {
    await HiveService.instance.configBox
        .put('disable_progress_phase_delta_coupling', true);
    addTearDown(() => HiveService.instance.configBox
        .delete('disable_progress_phase_delta_coupling'));
    final r = UserRepository.mergeCloudProgress(
        local: localAdvanced(), cloud: cloudStale());
    expect(r.merged['current_phase'], 2); // OI-83 guard intact
    expect(r.merged['current_week'], 4); // pre-fix behaviour
  });

  test('unrelated non-monotonic keys still take cloud while coupled', () {
    final r = UserRepository.mergeCloudProgress(
      local: {'current_phase': 5, 'current_streak_days': 9},
      cloud: {'current_phase': 2, 'current_streak_days': 0},
    );
    expect(r.merged['current_streak_days'], 0);
  });

  test('cloud map with current_phase LAST is still coupled', () {
    // Pins single-resolution: a mutant that decides in-loop from running state
    // sees the companions before the phase and behaves differently.
    final cloud = <String, dynamic>{
      'phase_started_at': '2026-04-27T00:00:00.000Z',
      'current_week': 4,
      'plan_generated_at': '2026-04-27T00:00:00.000Z',
      'current_phase': 1,
    };
    final r =
        UserRepository.mergeCloudProgress(local: localAdvanced(), cloud: cloud);
    expect(r.merged['phase_started_at'], '2026-05-25T00:00:00.000Z');
  });

  test('current_phase telemetry is unchanged by the coupling', () {
    final r = UserRepository.mergeCloudProgress(
        local: localAdvanced(), cloud: cloudStale());
    expect(r.declinedFields.map((d) => d.field), contains('current_phase'));
    expect(r.declinedFields.single.localValue, 2);
    expect(r.declinedFields.single.cloudValue, 1);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/contracts/progress_restore_monotonic_behavioral_test.dart --plain-name "phase-delta companion coupling"`
Expected: FAIL — `refusedPhaseDeltaFields` undefined, and the companion assertions return cloud values.

- [ ] **Step 3: Write the implementation**

**3a.** In `user_repository.dart`, immediately after the `monotonicProgressFields` literal (`:251-255`), add:

```dart
  /// The three fields `commitPhaseAdvance` writes ATOMICALLY alongside
  /// `current_phase` (pro_phase_advance.dart:343-348, fields at :344-347).
  ///
  /// They are NOT monotonic and must never be added to
  /// [monotonicProgressFields]: two are ISO dates and one is a reset-to-1
  /// counter, so max-wins on any of them is a guard pointed the wrong way —
  /// the `longest_gap_days` mistake documented at :238-249.
  ///
  /// They are refused PER KEY (not as an unconditional group), keyed on the
  /// phase decision: a companion is kept only when the merge kept local's
  /// `current_phase` AND local actually holds a non-null value for that key.
  /// Without the second condition a locally-advanced map that never held a
  /// date would have the key refused out of the merged map entirely.
  ///
  /// NOT carried by phase_progress_reconciler.dart:138, which advances the
  /// counter alone by design (:20-22 — "WITHOUT touching the in-progress
  /// plan"). Keeping local's companions after a counter-only advance is
  /// correct BY THAT WRITER'S OWN CONTRACT — not because the values happen to
  /// match cloud's. They need not: cloud's companions are last-writer-wins
  /// from any device (sync_profile.dart:315-316), and sync_service.dart:1185-1188
  /// can push a `?? DateTime.now()` this device never held.
  @visibleForTesting
  static const List<String> phaseDeltaCompanionFields = <String>[
    'current_week',
    'phase_started_at',
    'plan_generated_at',
  ];

  /// §4.6 kill-switch for the companion coupling, deliberately INDEPENDENT of
  /// `disable_progress_restore_monotonic_merge`: rolling this back must not
  /// also disable the shipped OI-83 monotonic guard.
  static bool get _phaseDeltaCouplingDisabled {
    try {
      return _hive.configBox
              .get('disable_progress_phase_delta_coupling', defaultValue: false)
          as bool;
    } catch (_) {
      return false;
    }
  }
```

**3b.** In `ProgressMergeResult` (`:52-68`), add the field, the constructor parameter and keep the existing ones untouched:

```dart
  /// Phase-delta companions kept from local because the merge kept local's
  /// `current_phase` and the two sides' values DIFFERED. A value-identical
  /// refusal is not recorded — it changes nothing and would fire on every
  /// counter-only reconciler advance.
  final List<String> refusedPhaseDeltaFields;
```

with `this.refusedPhaseDeltaFields = const <String>[],` added to the const constructor.

**3c.** In `mergeCloudProgress`, after `final guardOff = _monotonicMergeDisabled;` (`:324`), add the pre-pass:

```dart
    // Resolve the phase decision ONCE, before the loop, and reuse it. Map
    // iteration order is insertion order in Dart, but the cloud map's key
    // order comes from PostgREST's JSON and is not ours to control.
    final phaseProvenance = resolvePhaseProvenance(
      local: local,
      cloud: cloud,
      guardOff: guardOff,
    );
    final coupleDelta = !_phaseDeltaCouplingDisabled &&
        phaseProvenance == PhaseProvenance.keptLocal;
    final refusedPhaseDelta = <String>[];
```

**3d.** Inside the `for (final entry in cloud.entries)` loop, immediately after the existing `if (entry.value == null) continue;` (`:327`), add:

```dart
      if (coupleDelta && phaseDeltaCompanionFields.contains(entry.key)) {
        final localValue = local[entry.key];
        // r2/B1 carve-out: only refuse a companion local actually HAS.
        // Mirrors the monotonic path's own `localRaw == null` rule at :361-364.
        if (localValue != null) {
          merged[entry.key] = localValue;
          if (localValue != entry.value) refusedPhaseDelta.add(entry.key);
          continue;
        }
        // Local holds nothing — fall through and take cloud.
      }
```

**3e.** Update the `return` at `:394-395`:

```dart
    return ProgressMergeResult(
      merged: merged,
      declinedFields: declined,
      malformedFields: malformed,
      refusedPhaseDeltaFields: refusedPhaseDelta,
    );
```

- [ ] **Step 4: Rewrite the existing contradicting test and the file header**

In `test/contracts/progress_restore_monotonic_behavioral_test.dart`, replace the assertion and comment at `:337-339`:

```dart
      // Phase-delta companion: current_week now moves WITH current_phase.
      // Superseded the OI-83-era assertion `expect(readBack['current_week'], 1)`
      // and its "the merge is scoped, not a blanket local-wins" rationale —
      // that contract was correct for the three monotonic fields and wrong for
      // the phase delta, which commitPhaseAdvance writes atomically.
      expect(readBack['current_week'], 2);
```

And in the file header (`:20-47`), change the line asserting the guarded set is exactly three to:

```dart
/// The monotonic set is THREE (current_phase, deployments_complete,
/// total_workouts_done). Separately, the THREE phase-delta companions
/// (current_week, phase_started_at, plan_generated_at) are refused per key
/// when the merge kept local's current_phase — see phaseDeltaCompanionFields.
```

- [ ] **Step 5: Run the whole file**

Run: `flutter test test/contracts/progress_restore_monotonic_behavioral_test.dart`
Expected: PASS, all tests (23 existing + 10 from Task 1 + 10 new).

- [ ] **Step 6: Commit**

```bash
sh scripts/safe_commit.sh "fix(sync): couple the phase delta to the phase decision on restore

commitPhaseAdvance writes current_phase + current_week + phase_started_at
+ plan_generated_at atomically; mergeCloudProgress guarded only the first,
so a stale cloud row split the group and the merged result was written
back to Hive, cementing a state neither side wrote.

Companions are refused PER KEY and only when local holds a value, so a
reinstall and a seeded-but-dateless map both keep today's behaviour.
Kill-switch disable_progress_phase_delta_coupling, independent of the
OI-83 switch.

closes-diagnose: <ALLOCATE IN TASK 9>
closes-oi: OI-150
Test: test/contracts/progress_restore_monotonic_behavioral_test.dart"
```

---

### Task 3: Anchor the login plan regen on the guarded value

**Files:**
- Modify: `lib/core/services/auth_session_bootstrapper.dart:594-604`
- Test: `test/contracts/restore_progress_uses_shared_merge_test.dart`

**Interfaces:**
- Consumes: nothing from Tasks 1–2 at runtime; depends on Task 2 having made the Hive value trustworthy.
- Produces: `static DateTime AuthSessionBootstrapper.resolvePlanRegenStart({String? hiveIso, required DateTime now})`.

⚠ **RULE-C check, already run — this extraction is safe.** `grep -rn "phase_started_at" test/` returns four pins outside this batch's own files: `pro_phase_advance_behavioral_test.dart:164,165,174,185` (the WRITER side — `commitPhaseAdvance`'s atomic delta, untouched here), `past_phase_display_recovery_behavioral_test.dart:293` (a `reason:` string), `test/sql/cross_device_progress_optimistic_lock_verify.sql` (the RPC fixture), and `test/supabase/auth_restore_test.dart:80` (live-Supabase, skips without credentials). **None pins the bootstrapper's inline `startDate` block**, so extracting it breaks nothing. Re-run the grep before landing in case the tree has moved.

**The defect:** `:535` runs the guarded merge and `:539` writes it to Hive. `:587-590` reads `phase` from that guarded Hive value — with an 11-line comment at `:576-586` explaining why. `:597-598` then reads `startDate` from `progressRows.first['phase_started_at']`, the **raw pre-merge cloud row**, eight lines below. Both feed the same `generateAndSchedule(phase:, startDate:)`.

- [ ] **Step 1: Write the failing tests**

Add to `test/contracts/restore_progress_uses_shared_merge_test.dart`:

```dart
group('plan regen anchors on the guarded value (OI-150 Part A)', () {
  test('a present Hive ISO is used verbatim', () {
    final now = DateTime.utc(2026, 8, 30);
    expect(
      AuthSessionBootstrapper.resolvePlanRegenStart(
          hiveIso: '2026-05-25T00:00:00.000Z', now: now),
      DateTime.parse('2026-05-25T00:00:00.000Z'),
    );
  });

  test('a null Hive ISO falls back to now — never to the cloud row', () {
    final now = DateTime.utc(2026, 8, 30);
    expect(AuthSessionBootstrapper.resolvePlanRegenStart(hiveIso: null, now: now),
        now);
  });

  test('an unparseable Hive ISO falls back to now', () {
    final now = DateTime.utc(2026, 8, 30);
    expect(
        AuthSessionBootstrapper.resolvePlanRegenStart(hiveIso: 'junk', now: now),
        now);
  });

  test('the bootstrapper reads the accessor, not the raw cloud row', () {
    final src = _stripComments(
        File('lib/core/services/auth_session_bootstrapper.dart')
            .readAsStringSync());
    // Positive half: the guarded accessor is used.
    expect(src, contains('getPhaseStartedAtIso()'));
    expect(src, contains('resolvePlanRegenStart('));
    // Negative half: the raw pre-merge cloud read is gone.
    expect(src, isNot(contains("progressRows.first['phase_started_at']")));
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/contracts/restore_progress_uses_shared_merge_test.dart --plain-name "plan regen anchors"`
Expected: FAIL — `resolvePlanRegenStart` undefined; the source-grep negative half fails because the literal is still present.

- [ ] **Step 3: Write the implementation**

Add to `class AuthSessionBootstrapper`:

```dart
  /// Resolves the plan-regeneration anchor for the login restore.
  ///
  /// Reads the GUARDED post-merge Hive value, never the raw cloud row. The
  /// cloud row is deliberately NOT a fallback: it fires precisely when the
  /// merge has just declined that value as stale, so falling back to it would
  /// reintroduce the bug in the one state where it is known wrong.
  @visibleForTesting
  static DateTime resolvePlanRegenStart({
    required String? hiveIso,
    required DateTime now,
  }) {
    if (hiveIso == null) return now;
    return DateTime.tryParse(hiveIso) ?? now;
  }
```

Replace `:596-604` (the `if (progressRows.isNotEmpty) { final genStr = ... }` block) with:

```dart
              // OI-150: anchor on the GUARDED Hive value, the same source the
              // `phase` above already uses. The pre-fix code read
              // `progressRows.first['phase_started_at']` — the raw pre-merge
              // cloud row — so a restore that had just refused a stale phase
              // regenerated the advanced phase's plan anchored at the stale
              // phase's start date.
              final startDate = resolvePlanRegenStart(
                hiveIso: UserRepository.instance.getPhaseStartedAtIso(),
                now: DateTime.now(),
              );
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/contracts/restore_progress_uses_shared_merge_test.dart`
Expected: PASS.

- [ ] **Step 5: Run `flutter analyze` on the two files touched so far**

Run: `flutter analyze lib/shared/repositories/user_repository.dart lib/core/services/auth_session_bootstrapper.dart`
Expected: no `warning -` lines. ⚠ `--no-fatal-infos` at pre-push suppresses infos but NOT warnings.

- [ ] **Step 6: Commit**

```bash
sh scripts/safe_commit.sh "fix(auth): anchor login plan regen on the guarded phase_started_at

d1f6b3's B-pass finding F1 pointed the phase argument at the post-merge
Hive value and left the startDate argument on the raw pre-merge cloud
row, eight lines below, in the same generateAndSchedule call. The plan
regenerated for the advanced phase anchored at the stale phase's date.

closes-diagnose: <ALLOCATE IN TASK 9>
Test: test/contracts/restore_progress_uses_shared_merge_test.dart"
```

---

### Task 4: Pure recompute of profile's derived targets

**Files:**
- Create: `lib/features/profile/services/profile_target_recompute.dart`
- Test: Create `test/contracts/profile_target_recompute_test.dart`

**Interfaces:**
- Consumes: `BmrCalculator.calculateTargets`, `BmrCalculator.resolveActivityLevel` (both already `static`).
- Produces: `Map<String, dynamic>? recomputeDerivedTargets(Map<String, dynamic> profile, {required DateTime now})` — returns the derived overlay, or `null` when inputs are incomplete. Task 5 consumes it.

⚠ **RULE-C FINDING — this is an EXTRACTION, not a new parallel function. `ProfileProvider.recalculateTargets` MUST be rewritten to call it (Step 6 below).**

`grep -rn "recalculateTargets" test/` surfaced `test/contracts/profile_edit_recompute_consistency_test.dart:37`, whose own comment reads *"Mirror recalculateTargets' write-back into the profile map (profile_provider.dart:102-105)"*. It reimplements the derivation to check it.

So the logic already exists **twice** — in the provider and in that test's mirror. Adding a third copy in `sync_profile`'s path is the §2.53 mirror-drift class (*"a MIRROR harness stops modelling production, so it is green in every world"*) and the same duplication round 3 rejected for the merge (r3/B2). Extract once; have the provider delegate; the mirror test then validates the shared implementation rather than a copy of it.

**Why this replaces coupling for profile:** profile has no version stamp (`updated_at` is server-set and absent from the 34-field client payload), so "newer wins" has no honest discriminator. But `bmr`/`tdee`/`daily_calories`/`protein_grams`/`carbs_grams`/`fat_grams`/`activity_level` are *derived* from the inputs — so recompute them after the merge and there is nothing left to keep consistent.

- [ ] **Step 1: Write the failing tests**

Create `test/contracts/profile_target_recompute_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/profile/services/profile_target_recompute.dart';

void main() {
  final now = DateTime.utc(2026, 8, 30);

  Map<String, dynamic> completeProfile() => {
        'current_weight_kg': 80.0,
        'height_cm': 175.0,
        'date_of_birth': '1995-01-01',
        'gender': 'male',
        'primary_goal': 'muscle_gain',
        'lifestyle_activity': 'desk_job',
        'days_per_week': 4,
        'pace_preference': 'balanced',
      };

  test('returns a derived overlay for a complete profile', () {
    final out = recomputeDerivedTargets(completeProfile(), now: now);
    expect(out, isNotNull);
    expect(out!.keys, containsAll(<String>[
      'bmr', 'tdee', 'daily_calories', 'protein_grams', 'carbs_grams',
      'fat_grams', 'activity_level',
    ]));
    expect(out['daily_calories'], isA<int>());
  });

  test('returns null when a required input is missing', () {
    for (final missing in ['current_weight_kg', 'height_cm', 'date_of_birth',
        'gender', 'primary_goal']) {
      final p = completeProfile()..remove(missing);
      expect(recomputeDerivedTargets(p, now: now), isNull,
          reason: 'missing $missing must abort the recompute');
    }
  });

  test('returns null on an unparseable date_of_birth', () {
    final p = completeProfile()..['date_of_birth'] = 'not-a-date';
    expect(recomputeDerivedTargets(p, now: now), isNull);
  });

  test('c3f2d8: a null body_fat_percent is NOT defaulted', () {
    final withNull = completeProfile()..['body_fat_percent'] = null;
    final withValue = completeProfile()..['body_fat_percent'] = 18.0;
    final a = recomputeDerivedTargets(withNull, now: now)!;
    final b = recomputeDerivedTargets(withValue, now: now)!;
    // If null were being defaulted to 18.0 these would be identical.
    expect(a['daily_calories'], isNot(equals(b['daily_calories'])));
  });

  test('activity_level is resolved from lifestyle + days, not copied', () {
    final p = completeProfile()
      ..['lifestyle_activity'] = 'desk_job'
      ..['days_per_week'] = 2
      ..['activity_level'] = 'very_active'; // stale stored value
    final out = recomputeDerivedTargets(p, now: now)!;
    expect(out['activity_level'], 'light'); // desk_job + <=3 days
  });

  test('falls back to the stored activity_level when lifestyle is absent', () {
    final p = completeProfile()
      ..remove('lifestyle_activity')
      ..['activity_level'] = 'active';
    expect(recomputeDerivedTargets(p, now: now)!['activity_level'], 'active');
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/contracts/profile_target_recompute_test.dart`
Expected: FAIL — the target file does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/features/profile/services/profile_target_recompute.dart`:

```dart
import 'package:icanbefitter/core/utils/bmr_calculator.dart';

/// Recomputes the DERIVED half of the profile map from its INPUT half.
///
/// OI-150 / Unit 2a. The profile splits into inputs the user supplies
/// (weight, height, DOB, gender, goal, lifestyle, days) and values computed
/// from them (bmr, tdee, daily_calories, protein/carbs/fat, activity_level).
/// A field-by-field cloud restore can take cloud's weight while keeping the
/// phone's calorie target, leaving a target computed from a weight that is no
/// longer there.
///
/// Rather than version the profile — it has no client-written version stamp,
/// and `updated_at` is server-set — merge the inputs and RECOMPUTE the
/// outputs. Nothing is left to keep consistent.
///
/// Mirrors `ProfileProvider.recalculateTargets` (profile_provider.dart:54)
/// exactly, minus the state read/write, so the two cannot disagree about how
/// a target is derived.
///
/// Returns `null` when the inputs are incomplete — the caller must then leave
/// the merged map untouched rather than writing partial or invented values.
///
/// ⚠ `bodyFatPercent` is passed through NULLABLE and is never defaulted.
/// Diagnose `c3f2d8`: a `?? 18.0` here fed a fabricated body-fat into every
/// skip-user's Katch-McArdle calculation.
Map<String, dynamic>? recomputeDerivedTargets(
  Map<String, dynamic> profile, {
  required DateTime now,
}) {
  final weight = (profile['current_weight_kg'] as num?)?.toDouble();
  final height = (profile['height_cm'] as num?)?.toDouble();
  final dob = profile['date_of_birth'] as String?;
  final gender = profile['gender'] as String?;
  final goal = profile['primary_goal'] as String?;

  if (weight == null ||
      height == null ||
      dob == null ||
      gender == null ||
      goal == null) {
    return null;
  }

  final birthDate = DateTime.tryParse(dob);
  if (birthDate == null) return null;

  final age = now.difference(birthDate).inDays ~/ 365;
  if (age <= 0) return null;

  final lifestyle = profile['lifestyle_activity'] as String?;
  final days = (profile['days_per_week'] as num?)?.toInt() ?? 4;
  final resolvedActivity = lifestyle != null
      ? BmrCalculator.resolveActivityLevel(lifestyle, days)
      : (profile['activity_level'] as String? ?? 'moderate');

  final targetWeight = (profile['target_weight_kg'] as num?)?.toDouble();
  final bodyFat = (profile['body_fat_percent'] as num?)?.toDouble();

  final targets = BmrCalculator.calculateTargets(
    weightKg: weight,
    heightCm: height,
    age: age,
    gender: gender,
    activityLevel: resolvedActivity,
    goal: goal,
    pacePreference: (profile['pace_preference'] as String?) ?? 'balanced',
    targetWeightKg:
        targetWeight != null && targetWeight > 0 ? targetWeight : null,
    bodyFatPercent: bodyFat,
  );

  return <String, dynamic>{
    ...targets.toMap(),
    'activity_level': resolvedActivity,
  };
}
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/contracts/profile_target_recompute_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 5: Make the provider DELEGATE, so there is one implementation**

Replace the body of `ProfileProvider.recalculateTargets` (`profile_provider.dart:54-105`) — everything from `final weight = ...` down to the `await updateProfile({...})` — with:

```dart
  Future<void> recalculateTargets() async {
    // OI-150 Unit 2a: the derivation lives in `recomputeDerivedTargets` so the
    // restore path and this edit path cannot drift. Returns null when the
    // inputs are incomplete, which is the same early-return this method used
    // to spell out inline five times.
    final overlay = recomputeDerivedTargets(state, now: DateTime.now());
    if (overlay == null) return;
    await updateProfile(overlay);
  }
```

Add the import. **Do not change what is written** — `overlay` is `{...targets.toMap(), 'activity_level': resolvedActivity}`, byte-identical to the previous inline map.

- [ ] **Step 6: Verify the mirror test still passes against the shared implementation**

Run: `flutter test test/contracts/profile_edit_recompute_consistency_test.dart test/contracts/body_fat_default_heal_test.dart test/contracts/nutrition_target_carb_dualname_test.dart`
Expected: PASS. These three pin the derivation, the `c3f2d8` null-body-fat behaviour, and the `carb_grams`/`carbs_grams` dual-name that `toMap()` emits. All three were found by the Rule-C grep and none is touched by this diff — which is exactly why they must be run.

- [ ] **Step 7: Commit**

```bash
sh scripts/safe_commit.sh "feat(profile): extract the derived-target recompute; provider delegates to it

Extracted from ProfileProvider.recalculateTargets minus the state
read/write, so the restore path can regenerate the derived half of the
profile map instead of merging it field-by-field. body_fat_percent stays
nullable and is never defaulted (c3f2d8).

Test: test/contracts/profile_target_recompute_test.dart"
```

---

### Task 5: Recompute after the profile restore merge

**Files:**
- Modify: `lib/core/services/sync/sync_profile.dart:642-659`
- Test: `test/contracts/profile_target_recompute_test.dart` (add a round-trip group)

**Interfaces:**
- Consumes: `recomputeDerivedTargets` (Task 4).
- Produces: nothing new.

⚠ **RULE-C check, already run — one constraint on how this insertion is made.** `test/contracts/restore_users_row_retry_test.dart:63-71` source-greps `_restoreUserProfile` by scanning from `Future<void> _restoreUserProfile(` **up to the next signature, `Future<Map<String, dynamic>?> _fetchUsersRowForRestore(`**, and asserts the body still calls `_fetchUsersRowForRestore(userId)`. The window is method-bounded rather than fixed-length, so **inserting the recompute inside `_restoreUserProfile` is safe** — but do NOT move `_fetchUsersRowForRestore`, reorder it above `_restoreUserProfile`, or rename either, or that window collapses and the assertion breaks in a file this diff never opens. `test/contracts/nutrition_target_carb_dualname_test.dart` also pins the `carb_grams`/`carbs_grams` dual-name through this same restore path; `toMap()` emits both (`bmr_calculator.dart:317-318`), so the overlay satisfies it — run it (Task 4 Step 6) rather than assuming.

- [ ] **Step 1: Write the failing test**

Append to `test/contracts/profile_target_recompute_test.dart`:

```dart
  group('restore merge recomputes rather than splitting', () {
    test('cloud weight + local targets → targets recomputed from cloud weight',
        () {
      final now = DateTime.utc(2026, 8, 30);
      // Simulates _restoreUserProfile's merge: cloud wins per key.
      final local = <String, dynamic>{
        'current_weight_kg': 80.0,
        'height_cm': 175.0,
        'date_of_birth': '1995-01-01',
        'gender': 'male',
        'primary_goal': 'muscle_gain',
        'lifestyle_activity': 'desk_job',
        'days_per_week': 4,
        'pace_preference': 'balanced',
        'daily_calories': 3000,
      };
      final cloud = <String, dynamic>{'current_weight_kg': 60.0};
      final merged = <String, dynamic>{
        ...local,
        for (final e in cloud.entries)
          if (e.value != null) e.key: e.value,
      };

      final overlay = recomputeDerivedTargets(merged, now: now)!;
      merged.addAll(overlay);

      // The stale 3000 must not survive alongside cloud's 60 kg.
      expect(merged['daily_calories'], isNot(3000));
      final fresh = recomputeDerivedTargets({...local, 'current_weight_kg': 60.0},
          now: now)!;
      expect(merged['daily_calories'], fresh['daily_calories']);
    });

    test('incomplete inputs leave the merged map untouched', () {
      final now = DateTime.utc(2026, 8, 30);
      final merged = <String, dynamic>{'daily_calories': 2500};
      final overlay = recomputeDerivedTargets(merged, now: now);
      expect(overlay, isNull);
      expect(merged['daily_calories'], 2500);
    });

    test('sync_profile calls the recompute after building merged', () {
      final src = File('lib/core/services/sync/sync_profile.dart')
          .readAsStringSync();
      expect(src, contains('recomputeDerivedTargets('));
    });
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/contracts/profile_target_recompute_test.dart --plain-name "restore merge recomputes"`
Expected: FAIL on the source-grep case (`recomputeDerivedTargets` absent from `sync_profile.dart`).

- [ ] **Step 3: Write the implementation**

Add the import to `lib/core/services/sync/sync_profile.dart`:

```dart
import 'package:icanbefitter/features/profile/services/profile_target_recompute.dart';
```

Immediately after the `final merged = <String, dynamic>{ ... };` block ending at `:649`, insert:

```dart
      // OI-150 Unit 2a — the merge above is cloud-non-null-wins per key, so it
      // can take cloud's weight while keeping local's calorie target, leaving a
      // target computed from a weight that is no longer in the map. The derived
      // half is regenerated from whichever inputs won, so there is nothing left
      // to keep consistent. Null overlay = incomplete inputs; leave merged as-is
      // rather than writing partial values.
      if (_hive.configBox
              .get('disable_profile_target_recompute', defaultValue: false) !=
          true) {
        final overlay = recomputeDerivedTargets(merged, now: DateTime.now());
        if (overlay != null) merged.addAll(overlay);
      }
```

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/contracts/profile_target_recompute_test.dart`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
sh scripts/safe_commit.sh "fix(sync): recompute profile targets after the restore merge

_restoreUserProfile merges cloud over local per key with no guard, so it
could take cloud's weight and keep local's calorie target. The derived
half is now regenerated from whichever inputs won. Kill-switch
disable_profile_target_recompute.

closes-diagnose: <ALLOCATE IN TASK 9>
Test: test/contracts/profile_target_recompute_test.dart"
```

---

### Task 6: Queue progress writes as a marker

**Files:**
- Modify: `lib/core/services/sync_service.dart` — `initQueue()` (`:630-643`), add an executor beside `_executeUserProfileUpsert` (`:648`)
- Modify: `lib/core/services/sync/sync_profile.dart` — `_syncUserProgress` (`:345`)
- Test: Create `test/contracts/sync_queue_progress_marker_test.dart`

**Interfaces:**
- Consumes: `SyncQueue.instance.enqueue`, `SyncOpExecutor = Future<Result<void, SyncError>> Function(Map<String, dynamic>)`.
- Produces: op type `'sync_user_progress'` registered on `SyncQueue`.

⚠ **The queue entry is a MARKER, not a payload.** `_syncUserProgress` sends `p_expected_version`; a payload replayed later carries a stale version and the RPC rejects it. These fields are client-authoritative, so the executor re-reads **current Hive state** at drain time — the latest truth, not a fossil.

- [ ] **Step 1: Write the failing test**

Create `test/contracts/sync_queue_progress_marker_test.dart`:

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) => l.replaceAll(RegExp(r'(?<!:)//.*$'), ''))
    .join('\n');

void main() {
  test('sync_user_progress is registered as a queue executor', () {
    final src = _strip(
        File('lib/core/services/sync_service.dart').readAsStringSync());
    expect(src, contains("'sync_user_progress'"));
    expect(src, contains('registerExecutor'));
  });

  test('the progress executor re-reads Hive rather than replaying a payload',
      () {
    final src = _strip(
        File('lib/core/services/sync_service.dart').readAsStringSync());
    final i = src.indexOf('_executeUserProgressSync');
    expect(i, greaterThan(-1));
    final body = src.substring(i, i + 900);
    // Re-reads current state; must NOT take field values from the marker.
    expect(body, contains('_syncUserProgress'));
    expect(body, isNot(contains("payload['current_phase']")));
  });

  test('_syncUserProgress enqueues on failure when the flag is on', () {
    final src = _strip(File('lib/core/services/sync/sync_profile.dart')
        .readAsStringSync());
    final i = src.indexOf('Future<void> _syncUserProgress');
    final body = src.substring(i, i + 2600);
    expect(body, contains('_syncReliabilityEnabled'));
    expect(body, contains('SyncQueue.instance.enqueue'));
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/contracts/sync_queue_progress_marker_test.dart`
Expected: FAIL — `'sync_user_progress'` and `_executeUserProgressSync` absent.

- [ ] **Step 3: Write the implementation**

**3a.** In `sync_service.dart`, inside `initQueue()` after the existing `registerExecutor` block:

```dart
    SyncQueue.instance.registerExecutor(
      'sync_user_progress',
      _executeUserProgressSync,
    );
```

**3b.** Add beside `_executeUserProfileUpsert`:

```dart
  /// Drain-time executor for a queued progress push.
  ///
  /// The queued entry is a MARKER carrying only `user_id`, never a field
  /// payload. `_syncUserProgress` sends `p_expected_version` to an
  /// optimistic-locked RPC, so a stored payload replayed minutes later would
  /// carry a stale version and be rejected. These fields are
  /// client-authoritative (sync_profile.dart:345 documents the model), so
  /// re-reading current Hive state sends the latest truth rather than a fossil.
  Future<Result<void, SyncError>> _executeUserProgressSync(
    Map<String, dynamic> payload,
  ) async {
    final userId = payload['user_id'] as String?;
    if (userId == null) {
      return Err(SyncError(
        code: 'missing_user_id',
        message: 'queued sync_user_progress marker had no user_id',
      ));
    }
    try {
      await _syncUserProgress(userId);
      return const Ok(null);
    } catch (e) {
      return Err(SyncError(code: 'sync_user_progress_failed', message: '$e'));
    }
  }
```

⚠ Confirm `Ok` / `Err` / `SyncError` constructor shapes against `lib/core/services/result.dart` and `sync_error.dart` before writing — copy the exact form `_executeUserProfileUpsert` uses.

**3c.** In `sync_profile.dart`'s `_syncUserProgress`, replace the bare `catch` tail so a failure enqueues when the flag is on:

```dart
    } catch (e, st) {
      debugPrint('[SyncService._syncUserProgress] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_sync_user_progress'));
      if (_syncReliabilityEnabled) {
        // OI-150: persist the debt. A fire-and-forget push held only in RAM is
        // destroyed by process death with nothing recording that it was owed.
        await SyncQueue.instance.enqueue(
          opType: 'sync_user_progress',
          payload: <String, dynamic>{'user_id': userId},
          initialError: SyncError(
              code: 'sync_user_progress_failed', message: '$e'),
        );
      }
      try {
        await _reportSyncFailure(opType: 'sync_user_progress', error: e);
      } catch (_) {}
    }
```

Also enqueue on the version-conflict drop path — `_retrySyncUserProgressOnceAfterConflict` currently logs `sync_user_progress_retry_dropped` and gives up. That is the path live telemetry shows firing 8 times across 3 users; enqueue there too rather than dropping.

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/contracts/sync_queue_progress_marker_test.dart`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
sh scripts/safe_commit.sh "feat(sync): queue progress writes as a marker so app death cannot lose them

syncProgressNow was fire-and-forget: the push lived only in RAM, so
process death destroyed it with nothing recording the debt. It now
enqueues on failure AND on the version-conflict drop path that live
telemetry shows firing 8 times across 3 users.

The entry is a marker, not a payload -- the RPC is optimistic-locked, so
a replayed payload would carry a stale version. The executor re-reads
current Hive state.

Test: test/contracts/sync_queue_progress_marker_test.dart"
```

---

### Task 7: Queue profile writes the same way

**Files:**
- Modify: `lib/core/services/sync_service.dart` — `initQueue()`
- Modify: `lib/core/services/sync/sync_profile.dart:247-262`
- Test: `test/contracts/sync_queue_progress_marker_test.dart` (add a profile group)

**Interfaces:**
- Consumes: the Task 6 pattern.
- Produces: op type `'sync_user_profile_marker'`.

**Why a second op rather than reusing `upsert_user_profile`:** the existing op stores the full 34-field payload and replays it verbatim. That is correct for its current caller, and changing it would alter behaviour for the flag's one existing consumer in the same batch that flips the flag. Add a marker op alongside it.

- [ ] **Step 1: Write the failing test**

```dart
  test('sync_user_profile_marker is registered and re-reads Hive', () {
    final src = _strip(
        File('lib/core/services/sync_service.dart').readAsStringSync());
    expect(src, contains("'sync_user_profile_marker'"));
    final i = src.indexOf('_executeUserProfileMarker');
    expect(i, greaterThan(-1));
    final body = src.substring(i, i + 900);
    expect(body, contains('_syncUserProfile'));
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/contracts/sync_queue_progress_marker_test.dart --plain-name "sync_user_profile_marker"`
Expected: FAIL.

- [ ] **Step 3: Write the implementation**

Register in `initQueue()`:

```dart
    SyncQueue.instance.registerExecutor(
      'sync_user_profile_marker',
      _executeUserProfileMarker,
    );
```

And the executor, mirroring Task 6:

```dart
  /// Drain-time executor for a queued profile push. Marker-only, for the same
  /// reason as [_executeUserProgressSync]: re-read current state rather than
  /// replaying a 34-field snapshot captured minutes earlier.
  Future<Result<void, SyncError>> _executeUserProfileMarker(
    Map<String, dynamic> payload,
  ) async {
    final userId = payload['user_id'] as String?;
    if (userId == null) {
      return Err(SyncError(
        code: 'missing_user_id',
        message: 'queued sync_user_profile_marker had no user_id',
      ));
    }
    try {
      await _syncUserProfile(userId);
      return const Ok(null);
    } catch (e) {
      return Err(SyncError(code: 'sync_user_profile_failed', message: '$e'));
    }
  }
```

In `sync_profile.dart:247-262`, keep the existing `upsert_user_profile` enqueue and add the marker enqueue for the non-flagged legacy path's failures, so both paths persist the debt.

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/contracts/sync_queue_progress_marker_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
sh scripts/safe_commit.sh "feat(sync): queue profile writes as a marker

Mirrors the progress executor. A separate marker op rather than changing
upsert_user_profile, so the flag's one existing consumer keeps its
current replay semantics in the batch that flips the flag.

Test: test/contracts/sync_queue_progress_marker_test.dart"
```

---

### Task 8: Flip `sync_reliability_v1` and record it

**Files:**
- Modify: `lib/core/services/sync_service.dart:626` (the getter's default)
- Modify: `docs/ship_dark_pending_review.yaml`
- Modify: `docs/superpowers/specs/2026-04-17-sync-reliability.md` (§6 checklist items 10–13)
- Test: Create `test/contracts/sync_reliability_flag_default_test.dart`

**Interfaces:** none.

⚠ This is the commit that flips a flag's default, so §4.12.4 requires the **full ×2 review** regardless of how the build steps were reviewed. It does **not** qualify for the ship-dark tier.

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sync_reliability_v1 defaults to true', () {
    final src =
        File('lib/core/services/sync_service.dart').readAsStringSync();
    expect(src, contains("get('sync_reliability_v1', defaultValue: true)"));
  });

  test('the flag is recorded in the ship-dark ledger', () {
    final y = File('docs/ship_dark_pending_review.yaml').readAsStringSync();
    expect(y, contains('sync_reliability_v1'));
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/contracts/sync_reliability_flag_default_test.dart`
Expected: FAIL on both.

- [ ] **Step 3: Flip the default and record it**

`sync_service.dart:626`:

```dart
  bool get _syncReliabilityEnabled =>
      _hive.configBox.get('sync_reliability_v1', defaultValue: true) as bool;
```

Append to `docs/ship_dark_pending_review.yaml` under `pending:` — with `flip_reviewed` set once Task 9's plan-review record shows `review_rounds: >= 2` + `bpass: accepted`:

```yaml
  - flag: sync_reliability_v1
    branch: oi150-phase-merge
    build_commit: <fill from `git rev-parse --short HEAD` after Task 7>
    build_date: 2026-08-30
    flip_reviewed: false
    flip_commit: null
    note: >
      Shipped dark 2026-04-17 (sync-reliability Pillar B) and never flipped —
      it appeared in neither this ledger nor the OI board for four months.
      Flipped ON here with OI-150. Scope of the flip is narrow and was
      measured: ONE gate (sync_profile.dart:247), failure path only; the
      success path is byte-identical. Two new marker ops ride it
      (sync_user_progress, sync_user_profile_marker).
```

Update the April spec's §6 checklist: tick items 1–9 (verified shipped — `sync_queue.dart`, `sync_error.dart`, `result.dart`, `sync_state_provider.dart`, `sync_banner.dart` all exist; banner mounted in `home_screen.dart` and `profile_content.dart`), and mark 11–12 done here.

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/contracts/sync_reliability_flag_default_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
sh scripts/safe_commit.sh "feat(sync): flip sync_reliability_v1 on; record it in the ship-dark ledger

Dark-launched 2026-04-17 and never flipped -- it was in neither
ship_dark_pending_review.yaml nor the OI board for four months, which is
the exact failure that ledger exists to catch.

The flip is narrow and measured: one gate (sync_profile.dart:247),
failure path only; success is byte-identical.

Test: test/contracts/sync_reliability_flag_default_test.dart"
```

---

### Task 9: Diagnose-doc, SoT registry, closure YAML, plan-review record

**Files:**
- Create: `docs/diagnoses/2026-08-30-progress-profile-write-durability-<6hex>.md`
- Modify: `docs/sot_registry.yaml` — `phase_progress_current_phase`
- Create: `docs/audit/oi150-write-durability.closure.yaml`
- Create: `docs/plan-reviews/oi150-phase-merge.md`

- [ ] **Step 1: Read the validator before drafting**

Run: `sed -n '1,40p' scripts/validate_diagnose_doc_lib.dart`
The 25 required fields are listed at `:8-17`, `blast_radius` at `:23-25`, and banned placeholder values (`TBD`, `TODO`, `<...>`, `???`) at `:31-33`.

- [ ] **Step 2: Allocate the bug id**

Run: `openssl rand -hex 3`
Use the result for the filename suffix and the `bug_id:` field, and substitute it into the `closes-diagnose:` placeholders in the Task 2 / 3 / 5 commit messages — amend those commits if they have already landed, or set the id before starting Task 2.

- [ ] **Step 3: Write the diagnose-doc — including the mutation record**

Fill all 25 fields. `touched_layers_checked` must include tier 1 (client code), tier 2 (Hive), tier 3 (postgres schema — `verified`, no change), tier 12 (client→server contract). Cite `related_bugs: [d1f6b3, c8f3d1, c9e4b7, b7f1c8, c9f4a2, c3f2d8]` and `recurrence:` naming `d1f6b3` as the direct predecessor whose guard this extends.

⚠ **Rule 21's mutate-it-and-run-it clause (2026-08-30) applies to EVERY test this batch writes or extends — behavioral ones included.** The doc must state, per mutation, **what was neutered and how many tests reddened**, in the form:

```yaml
mutation_evidence: |
  - emptied phaseDeltaCompanionFields → 4 red (coupling group)
  - removed the `localValue != null` carve-out → 1 red (r2/B1 case)
  - keyed coupling on raw `cloud < local` → 2 red (kill-switch, non-numeric)
  - dropped the differ-check in reporting → 1 red (identical-values case)
  - resolved the phase in-loop from running state → 1 red (current_phase-last)
  - defaulted bodyFatPercent to 18.0 → 1 red (c3f2d8 case)
  - reverted the regen anchor to progressRows.first → 2 red (both halves)
  Each mutation was CONFIRMED APPLIED via `grep -c` on the removed token
  before the run; each arm was executed, not reasoned about.
```

⚠ Every count above is a **placeholder to be replaced with what the runs actually produce** — do not copy these numbers forward. A mutation that reddens 0 means the test does not test the fix (§2.41: something absorbed the damage), not that the mutation was wrong.

- [ ] **Step 4: Update the SoT registry**

`phase_progress_current_phase` gains the companion-field contract. ⚠ It **already has** `behavioral_test_path: test/contracts/pro_phase_advance_behavioral_test.dart` at `docs/sot_registry.yaml:6823` — do not add a second.

- [ ] **Step 5: Write the closure YAML**

`docs/audit/oi150-write-durability.closure.yaml`, one entry per unit, each with a `terminal_state:` from {`closed_in_commit`, `upstream_blocked`, `blocked_on_user`, `verified_clean`}. The no-heal decision is `verified_clean` with the SQL evidence. No `deferred:` key exists in the schema.

Run: `dart run scripts/validate_audit_closure.dart`

- [ ] **Step 6: Write the plan-review record AND the bpass_review file it points at**

`docs/plan-reviews/oi150-phase-merge.md` with `---` frontmatter (the keystone gate parses `^key:` line-anchored; a bullet header yields null fields and a CI hard-fail): `review_rounds: >= 2`, `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted`, and a `bpass_review:` key naming the B-pass output file.

⚠ **`safe_merge.sh`'s pre-merge precheck (2026-08-30) reads that named file and warns unless it contains a line-anchored `verdict: accepted`.** Two things about it, both learned the hard way in the batch that shipped it:
- It reads **`git show "$BRANCH:<path>"`**, not the working tree — so the `bpass_review` file must be **committed on this feature branch**, not merely present on disk or on `main`.
- The filename comes from `plan_review_record_lib.dart`'s `recordSlug()` (strip `origin/`, map `/`→`-`), not the raw branch name.

A `verdict: pending` here is unfixable after the merge, because CI reads the file at the merge commit — the repair is a full `git reset --hard` unwind. Confirm before merging:

```bash
git cat-file -e "oi150-phase-merge:docs/reviews/<bpass-file>.md" && echo "present on branch"
```

- [ ] **Step 7: Regenerate the indexes and run the gates**

```bash
dart run scripts/build_bug_index.dart
dart run scripts/build_oi_index.dart
dart run scripts/validate_diagnose_doc.dart docs/diagnoses/2026-08-30-progress-profile-write-durability-<id>.md
```

- [ ] **Step 8: Commit**

```bash
sh scripts/safe_commit.sh "docs(oi150): diagnose-doc, SoT contract, closure YAML, plan-review record

closes-diagnose: <id>
closes-oi: OI-150"
```

---

## Before the merge

1. **Run the FULL suite once**, not just the touched files — new test files that spawn subprocesses pass targeted and fail under suite contention (§4.9). `flutter test`.
2. **Mutation-prove, in a dedicated worktree** (`sh scripts/new-worktree.sh mutate-oi150`, per OI-134 — mutating in this tree shows reviewers a state matching no commit):
   - empty `phaseDeltaCompanionFields` → Task 2's coupling tests redden
   - remove the `localValue != null` carve-out → the r2/B1 test reddens
   - key the coupling on raw `cloud < local` instead of provenance → the kill-switch and non-numeric tests redden
   - drop the `localValue != entry.value` differ-check → the identical-values test reddens
   - resolve the phase in-loop from running merge state → the `current_phase`-last test reddens
   - make `recomputeDerivedTargets` default `bodyFatPercent` to `18.0` → the c3f2d8 test reddens
   - revert Task 3's call site to `progressRows.first['phase_started_at']` → both halves redden

   **Run the neutered arm every time** (§2.54). A mutation you reasoned about rather than executed cannot tell you it was absorbed.
3. **Self-trigger `/code-review` (B-pass)** before the `--no-ff` merge — `platform` tier, so `bpass: accepted` is mandatory (§4.3, §4.12.3).
4. **Merge with `sh scripts/safe_merge.sh oi150-phase-merge`** from the primary worktree, then push once.
5. **Walk the §5 checklist**, including retiring this worktree once merged and clean.

## Self-review of this plan

- **Spec coverage:** Unit 2 → Tasks 1–3. Unit 2a → Tasks 4–5. Unit 1 → Tasks 6–7. Unit 3 → Task 8. §4 testing → every task plus the mutation list. §1.5 no-heal → Task 9 closure YAML. §7.1 flip → Task 8. §7.2 scope → Tasks 6–7 cover progress and profile only, as decided.
- **Placeholders:** two deliberate `<ALLOCATE IN TASK 9>` markers for the diagnose id in Task 2/3/5 commit messages, and `<fill from git rev-parse>` in Task 8's ledger entry. Task 9 Step 2 resolves all three; these are ordering dependencies, not unspecified work.
- **Type consistency:** `PhaseProvenance` / `resolvePhaseProvenance` (Task 1) are used identically in Task 2. `recomputeDerivedTargets(Map, {required DateTime now})` (Task 4) matches its Task 5 call. `SyncOpExecutor`'s `Future<Result<void, SyncError>> Function(Map<String, dynamic>)` matches both executors.
- **Known residual, stated not hidden:** `primary_goal` can still revert on a stale restore — it is an input, so the recompute does not fix it. Its three companions are Hive-only and cannot be touched by a restore. Unit 1 closes the cause (the lost write) rather than the symptom; no separate merge rule is added for it. If review disagrees, that is a Task 2-shaped addition, not a redesign.
