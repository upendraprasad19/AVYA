import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/plan_integrity_reconciler.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/utils/injury_vocab.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

/// Shared PRO next-phase advance — REG-1 fix (a4e2d9).
///
/// A single code path used by BOTH:
///   - the splash silent auto-path (`_autoGenerateNextPhaseForPro`, fired
///     unawaited on app launch), and
///   - the Home/Train `PhaseGeneratingCard` retry CTA — the PRO user's recourse
///     when that silent pass failed or raced (it is fire-and-forget, so a slow
///     or errored generation used to strand a paying user on the FREE
///     `PlanExpiredCard` "go PRO" upsell).
///
/// Reads goal / equipment / days / experience / injuries from the Hive profile
/// (the same inputs onboarding used for Phase 1), generates the next phase IFF
/// the PRO user's current phase has expired, then bumps `user_progress`. Returns
/// `true` iff a new phase was generated (the caller refreshes its providers on
/// `true`).
///
/// This function NEVER swallows errors — it lets them propagate so each caller
/// applies its own handling (splash → `ErrorTelemetry.recordNonFatal`; the card
/// → a retry snackbar + telemetry). The `isPro` / `isPhaseExpired` guards below
/// make it safe to call redundantly: once a phase has been generated,
/// `isPhaseExpired()` is false, so a second call returns `false` without
/// generating again. And the [withPhaseAdvanceLock] mutex closes the narrow
/// concurrency window where the splash's unawaited pass and a card tap could
/// BOTH pass the expiry gate before either writes → a double-generate.
bool _advanceInFlight = false;

/// Single-isolate advance **TRY-lock**, SHARED across every surface that
/// generates or heals a phase — the splash's unawaited pass, the Home/Train
/// `PhaseGeneratingCard` retry CTA, (Unit 3c) `graduation_screen`'s explicit
/// unlock, and `PhaseProgressReconciler.reconcile`. The check+set is atomic (no
/// `await` between them), so two of those can never both proceed to generation.
///
/// **Try-lock, not a queueing mutex** — round-2 review flagged that calling it a
/// "mutex" misleads, because a busy caller is turned away rather than made to
/// wait. That is the right semantic for the three advance surfaces ("somebody is
/// already advancing you — stop"), and the WRONG one for the reconciler, which
/// needs to run eventually; the reconciler therefore supplies its own bounded
/// retry rather than this primitive growing a queue. The required [ifBusy]
/// argument is the signature-level reminder: every caller must decide what
/// "busy" means for it.
///
/// It was module-private and covered only the first two until Unit 3c: the
/// graduation screen ran its own `generateAndSchedule` outside this guard
/// entirely, so a splash pass and a graduation unlock could each generate the
/// SAME phase, the second overwriting the first's `schedule_*` rows and
/// `plan_start` under a user already looking at the plan.
///
/// [ifBusy] is what the caller gets when someone else holds the lock — a value,
/// not an exception, because "somebody is already advancing you" is a normal
/// outcome for every one of these surfaces, not an error.
/// Kill-switch (`configBox`). Set `true` to make [withPhaseAdvanceLock] a
/// pass-through — every caller runs its body, nobody is turned away.
///
/// §4.6 / the platform-tier `feature_flag` requirement in `docs/blast_radius.yaml`.
/// It gates the LOCK ONLY, deliberately, and it is default-OFF-meaning-active —
/// the same `disable_*` shape as `disable_phase_reconciler`,
/// `disable_plan_integrity_reconciler` and `disable_bg_restore`. Two halves,
/// two answers:
///   - The **lock** is the genuinely risky new primitive: round-2 review already
///     found one starvation bug in it (the reconciler's bare try-lock), so a
///     runtime escape hatch for "the lock is wedging a surface in the field" is
///     real value, not ceremony.
///   - The **monotonic guard** ([phaseAdvanceTarget] / [commitPhaseAdvance]) has
///     NO switch. It is pure, cannot deadlock, starve or wedge anything, and the
///     only thing disabling it could achieve is re-enabling the demotion bug
///     this batch exists to fix. A kill-switch whose only effect is to restore a
///     defect is not a safety valve.
const String kDisablePhaseAdvanceLockKey = 'disable_phase_advance_lock';

bool get _lockDisabled {
  try {
    return HiveService.instance.configBox.get(kDisablePhaseAdvanceLockKey) ==
        true;
  } catch (_) {
    // Box not open (pre-boot / test) — the lock stays ACTIVE. Failing closed
    // here is right: an unopened box must not silently disable a guard.
    return false;
  }
}

Future<T> withPhaseAdvanceLock<T>(
  Future<T> Function() body, {
  required T ifBusy,
}) async {
  if (_lockDisabled) return await body();
  if (_advanceInFlight) return ifBusy;
  _advanceInFlight = true;
  try {
    return await body();
  } finally {
    _advanceInFlight = false;
  }
}

Future<bool> advanceProPhaseIfExpired(WidgetRef ref) async =>
    withPhaseAdvanceLock<bool>(
      () async {
        // C-7 (audit-2026-05-11) — defensive HiveUserSession bootstrap. The
        // splash fires this before `_ensureLocalUser` has opened the per-user
        // namespaced boxes; without this the profile/progress reads below throw
        // `HiveUserSession not opened`.
        //
        // Unit 3c: hoisted OUT of the body and into this wrapper (order is
        // unchanged — still after the in-flight check, still before any read)
        // so [runProPhaseAdvance] is drivable from a test. It reads
        // `SupabaseService.instance.currentUser`, which is null whenever
        // Supabase was never initialised, so a unit test calling the public
        // entry point returned `false` here and never reached the write this
        // function exists to perform — the reason task #41's behavioral
        // coverage did not exist.
        final uid = await HiveUserSession.ensureOpenedForCurrentSession();
        if (uid == null) return false;
        return runProPhaseAdvance(ref);
      },
      ifBusy: false,
    );

/// The advance itself, minus the session bootstrap. Public + `@visibleForTesting`
/// ONLY so the behavioral test can drive the real read → slow-generate → write
/// path (task #41 / OI-45). Production code calls [advanceProPhaseIfExpired].
@visibleForTesting
Future<bool> runProPhaseAdvance(WidgetRef ref) async {
  // A7 / B5 D9-D10 — canonical provider path (imperative isPro() gate is a
  // point-in-time check inside an action; the UI RENDER guard uses the reactive
  // subscriptionInfoProvider instead — H-1).
  if (!ref.read(subscriptionServiceProvider).isPro()) return false;
  if (!ref.read(workoutScheduleServiceProvider).isPhaseExpired()) return false;

  final profile = UserRepository.instance.getProfile() ?? {};
  final progress = UserRepository.instance.getProgress() ?? {};

  final goal = (profile['primary_goal'] as String?) ?? 'general_fitness';
  final equipment = (profile['equipment_access'] as String?) ?? 'bodyweight';
  final daysPerWeek = (profile['days_per_week'] as num?)?.toInt() ?? 4;
  final experience =
      (profile['fitness_experience'] as String?) ?? 'intermediate';
  final currentPhase = (progress['current_phase'] as int?) ?? 1;
  final rawInjuries = profile['injuries'];
  final injuries = rawInjuries is List
      ? rawInjuries.map((e) => e.toString()).toList()
      : const <String>[];
  final sessionDuration =
      (profile['session_duration_minutes'] as num?)?.toInt();

  // ⑧ 3-a2 (W2.5, ship-dark): when the adherence gate is ON AND the just-
  // finished phase's completion rate is low, REPEAT its content into the next
  // phase (at detrained loads) instead of a fresh pick. The `&&` short-circuits
  // so the ≤12× getWeek loop inside currentPhaseCompletionRate never runs when
  // the flag is OFF — then `repeatContent` stays false and this is
  // byte-identical to the fresh-generation path.
  final repeatContent = PlanEngineFlags.adherenceGateEnabled &&
      ref.read(workoutScheduleServiceProvider).currentPhaseCompletionRate() <
          AppConstants.phaseUnlockCompletionRate;

  final result = await ref
      .read(workoutScheduleServiceProvider)
      .autoGenerateNextPhaseIfNeeded(
        goal: goal,
        equipment: equipment,
        daysPerWeek: daysPerWeek,
        experienceLevel: experience,
        currentPhase: currentPhase,
        injuries: injuries,
        sessionDuration: sessionDuration,
        repeatContent: repeatContent,
      );

  if (result.generated) {
    // Bump user_progress.current_phase + plan_generated_at (monotonic advance).
    //
    // Unit 3a (OI-45 finding 2): was saveProgress(wholeMapReadAtLine65) — a
    // STALE snapshot carried across the autoGenerateNextPhaseIfNeeded await
    // above (real plan-gen work, tens-hundreds of ms). Any OTHER progress
    // writer landing during that window would have been silently clobbered
    // by this whole-map overwrite. updateProgress(delta) calls getProgress()
    // fresh at write time instead — same safe idiom
    // graduation_screen.dart / phase_progress_reconciler.dart already use.
    // Side effect (also a real fix): saveProgress does NOT sync cloud
    // internally, so this path left user_progress stale in the cloud after
    // every PRO phase advance until some unrelated updateProgress call
    // happened to sync it. updateProgress fires syncProgressNow() itself.
    //
    // Unit 3c (OI-45 finding 5): that fix closed the whole-map clobber of OTHER
    // fields but left `current_phase`'s own VALUE pre-await — `currentPhase` is
    // still read at the top of this function, before the generate. Routed
    // through [commitPhaseAdvance], which re-reads the live phase at write time
    // and refuses to write a lower one.
    // OI-83: this return used to be DISCARDED. A decline here means the
    // generation above wrote schedule_* rows + a plan window for a phase the
    // user is no longer advancing to — see [reconcileAfterDeclinedAdvance].
    final committed = await commitPhaseAdvance(
      intendedPhase: currentPhase + 1,
      source: 'pro_phase_advance',
    );
    if (!committed) {
      await reportDeclinedAdvanceLeftStaleRows(
        source: 'pro_phase_advance',
        intendedPhase: currentPhase + 1,
        livePhase:
            (UserRepository.instance.getProgress()?['current_phase'] as int?) ??
                1,
      );
    }
    // Fire-and-forget snapshot push so the AI coach sees the new Phase.
    unawaited(ref.read(syncServiceProvider).pushSnapshot());

    // ⑧ 3-a2/3-b: on an ACTUAL repeat (G5 gate passed → pins applied), flag the
    // low-adherence "you repeated — step it up?" Home nudge via the SHARED
    // writer (the cross-account belt lives in markPhaseRepeatNudgePending, so
    // the graduation choice sheet's repeat branch inherits it too).
    if (result.repeated) {
      await markPhaseRepeatNudgePending();
    }
  }
  return result.generated;
}

/// ⑧ 3-a2/3-b: set the local-only low-adherence "you repeated — step it up?"
/// Home nudge flag (`phase_repeat_nudge_pending`). SHARED writer used by BOTH
/// [advanceProPhaseIfExpired] (splash/card auto-repeat, on `result.repeated`)
/// AND the graduation choice sheet's repeat branch (on `pins != null` — the
/// same predicate: see `autoGenerateNextPhaseIfNeeded`'s `repeated: pins != null`).
///
/// CROSS-ACCOUNT belt (the codified expiry-banner P0 guard,
/// `subscription_service.dart`): only write when the Hive session OWNER is known
/// — a non-null uid from `ensureOpenedForCurrentSession` does NOT imply the owner
/// opened, and a null owner makes `MigratedKey.write` fall back to the
/// DEVICE-shared configBox, leaking the nudge to the next account on this device.
Future<void> markPhaseRepeatNudgePending() async {
  if (HiveUserSession.currentOwnerFullId != null) {
    await MigratedKey.write('phase_repeat_nudge_pending', true);
  }
}

/// PURE decision behind [commitPhaseAdvance] (visible for testing — no Hive, no
/// clock). Returns the phase to write, or `null` when the write must be SKIPPED
/// because another advancer already moved the counter to [intendedPhase] or past
/// it.
///
/// **Why this exists (Unit 3c / OI-45 finding 5).** `current_phase` is the one
/// progress field with NO monotonic guard anywhere: `UserRepository.saveProgress`
/// guards `deployments_complete` (`max(prior, phase-1)`) and writes
/// `current_phase` straight through. Every advance path computes its target
/// BEFORE a real, slow plan-generation `await` and writes it after, so a
/// concurrent advancer landing inside that window gets overwritten by a stale,
/// LOWER number. Concurrent higher-phase writers that reach it:
/// [advanceProPhaseIfExpired] (reached from `splash_screen.dart:225`'s
/// `unawaited(_autoGenerateNextPhaseForPro())`, and on tap from
/// `phase_generating_card.dart`), `PhaseProgressReconciler.reconcile` (called
/// from `restoring_screen.dart`, can jump more than +1),
/// `runGraduationPhaseAdvance` (this file), and the dev sim. That is the
/// `feedback_monotonic_field_recompute_demotion` class — same shape as diagnose
/// `3a7b9f`'s rank demotion.
///
/// Deliberately mirrors `PhaseProgressReconciler.reconciledPhase`: monotonic,
/// `null` for a no-op, pure so it can be tested without a widget tree.
///
/// The guard does NOT belong in `saveProgress`, which looks like the right choke
/// point because that is where `deployments_complete` is stamped: a blanket
/// monotonic `current_phase` there would break the two legitimate resets to
/// phase 1 (`onboarding_provider.dart`'s first write, the dev `resetJourney`),
/// both of which call `saveProgress` directly. The guard belongs to the ADVANCE
/// operation, not to the storage primitive.
@visibleForTesting
int? phaseAdvanceTarget({required int livePhase, required int intendedPhase}) {
  if (livePhase >= intendedPhase) return null; // already advanced — never demote
  return intendedPhase;
}

/// The SINGLE writer for a phase advance's progress delta. Used by all three
/// advance paths: [advanceProPhaseIfExpired] (splash + card),
/// `runGraduationPhaseAdvance` (below, Unit B), and `simulation_service._maybeAdvancePhase`.
///
/// Re-reads `current_phase` from Hive HERE, at write time, so the decision is
/// made against live state rather than against the snapshot the caller took
/// before its plan-generation await. Returns `true` iff the delta was written.
///
/// A skip skips the WHOLE delta, not just `current_phase`: `current_week: 1` and
/// `phase_started_at` written against somebody else's advance would reset the
/// week and the phase-start date under them, which is the same class of damage
/// as the demotion.
///
/// [now] is threaded so the dev sim can pass its time-travel seam (`nowWall()`);
/// production callers omit it. Both timestamps come from ONE instant — the
/// previous code called `DateTime.now()` twice, microseconds apart, for two
/// fields that describe the same event.
Future<bool> commitPhaseAdvance({
  required int intendedPhase,
  required String source,
  DateTime? now,
}) async {
  // `as int?`, matching the other two advance-path readers of this field
  // (runGraduationPhaseAdvance below, phase_progress_reconciler `_reconcileLocked`).
  // A `num?)?.toInt()` hardening was written here and REMOVED after the
  // hypothesis behind it was tested rather than assumed: the guarantee is the
  // SCHEMA — `user_progress.current_phase` is `integer`/`int4`, verified by live
  // `information_schema` query 2026-08-01 — so PostgREST cannot deliver a
  // double for it and no writer can land one.
  //
  // Round-2 review corrected the FIRST rationale written here, which said
  // `saveProgress` (user_repository.dart:129) would throw on a double before
  // this read ran. That is true only for writers that go through
  // `saveProgress`, and four do not: sync_profile.dart:613-622,
  // auth_session_bootstrapper.dart:323-328 and
  // sync_restore_completeness.dart:242,411 all `put('progress', …)` directly
  // (see OI-83). The column type is what holds, not the repository.
  //
  // Note `sync_profile.dart:100,289,301` DO use `as num?)?.toInt()` for this
  // field — on the cloud-payload side, where the value has been through JSON.
  final livePhase =
      (UserRepository.instance.getProgress()?['current_phase'] as int?) ?? 1;
  final target =
      phaseAdvanceTarget(livePhase: livePhase, intendedPhase: intendedPhase);

  if (target == null) {
    // Not silent: a skip means two advancers raced, which is exactly the
    // condition nobody could see before this fix existed.
    unawaited(ErrorTelemetry.logEvent(
      'phase_advance_conflict_skipped',
      message: 'source=$source live=$livePhase intended=$intendedPhase',
    ));
    return false;
  }

  final stamp = (now ?? DateTime.now()).toIso8601String();
  await UserRepository.instance.updateProgress({
    'current_phase': target,
    'current_week': 1,
    'plan_generated_at': stamp,
    'phase_started_at': stamp,
  });
  return true;
}

/// SHARED reporter for the one outcome [commitPhaseAdvance] cannot fix by
/// itself: it DECLINED, but the caller had already run a full
/// `generateAndSchedule` before asking (OI-83's second-order effect).
///
/// The counter is correct — the decline is what keeps it correct. What is left
/// wrong is the `schedule_*` rows and the plan window that generation already
/// wrote for the phase we did NOT advance to. Nothing rolls them back.
///
/// **This function REPORTS that condition. It does not repair it, deliberately.**
/// Three repair mechanisms were designed and each was refuted, the last two by
/// context-blind review, and the refutations are recorded here so the fourth
/// attempt does not repeat them:
///
///  1. *Make the restore writers take [withPhaseAdvanceLock].* Refuted: it is a
///     TRY-lock (returns `ifBusy` immediately, no queue), so a restore arriving
///     mid-generation would be turned away entirely and the user's cloud
///     progress would never land — a dropped restore is worse than stale rows.
///  2. *Force [PlanIntegrityReconciler.reconcile] past its `needsHeal` gate.*
///     Refuted as INERT: `mergeScheduleEntry` then applies the same
///     "local already has exercises → keep local" predicate per row, and these
///     rows have their exercises. Only rest days would have healed.
///  3. *Add a `preferSnapshot` override plus deletion of rows past the
///     re-anchored `plan_end`.* Refuted as DATA-LOSS: cloud `plan_json` is
///     pushed only by the DAILY full sync (`sync_service.dart` `_fullSyncInterval`
///     = 1 day), so the snapshot can be 24h stale and describe the PREVIOUS
///     phase window — the sweep would then delete the winner's freshly-generated
///     rows. And `_syncWorkoutPlan` snapshots every `schedule_*` key box-wide,
///     so `preferSnapshot` would also revert an un-synced local exercise swap on
///     any planned day.
///
/// What a correct repair needs is the set of keys the LOSING generation wrote —
/// which only the caller knows, and which nothing currently records. That is
/// real, separate engineering, tracked as its own board item rather than
/// guessed at a fourth time (CLAUDE.md §4.12.1: when successive reviews keep
/// surfacing new material issues, ship the smallest converged piece).
///
/// Reporting alone is a real improvement on `main`: today this condition is
/// completely invisible, so nobody can tell how often it happens or whether it
/// is worth the repair. Never throws — the advance itself already succeeded or
/// was correctly declined, and a telemetry call must not turn that into an
/// error the user sees.
Future<void> reportDeclinedAdvanceLeftStaleRows({
  required String source,
  required int intendedPhase,
  required int livePhase,
}) async {
  try {
    // AWAITED inside the try, deliberately. `unawaited(...)` would put the
    // failure OUTSIDE this catch — the future rejects after the synchronous
    // body has already returned, so the "never throws" guarantee would have
    // been false. This unit's own test caught exactly that. The path is rare
    // (a declined advance) and the caller is already async, so awaiting costs
    // nothing worth optimising.
    await ErrorTelemetry.logEvent(
      'phase_advance_declined_rows_stale',
      message: 'source=$source intended=$intendedPhase live=$livePhase',
    );
  } catch (e, st) {
    unawaited(ErrorTelemetry.recordNonFatal(e, st,
        reason: 'phase_advance_declined_report_failed'));
  }
}

/// What [runGraduationPhaseAdvance] actually did.
///
/// Unit B / OI-84 replaced a `bool?` return whose three states the graduation
/// screen had to decode positionally (`null` busy / `false` two different
/// things / `true` committed). `false` genuinely covered TWO outcomes that
/// already had distinct telemetry events, so the type was lossier than the
/// instrumentation.
enum GraduationAdvanceOutcome {
  /// Another advance surface holds [withPhaseAdvanceLock]. Nothing was read,
  /// generated or written here. Was `null`.
  busy,

  /// The lock was held, but the live phase had ALREADY reached the intended
  /// phase, so no generation ran. Fires `phase_unlock_preempted_before_generate`.
  preemptedBeforeGenerate,

  /// Plan rows WERE generated, but [commitPhaseAdvance] refused the counter
  /// write because a concurrent advancer got there first. The stale-rows
  /// condition is reported via [reportDeclinedAdvanceLeftStaleRows] (OI-85).
  generatedButDeclined,

  /// Generated and the counter advanced. The only success.
  committed,
}

/// Result of [runGraduationPhaseAdvance].
///
/// [repeatNudgeFlagged] exists for a LAYERING reason, not a stylistic one.
/// The old in-screen closure called `ref.invalidate(phaseRepeatNudgeProvider)`
/// itself, but that provider lives in `lib/features/home/providers/
/// home_provider.dart:957` — a FEATURE file, and this is `lib/shared/**`.
///
/// **Precise about the strength of that constraint** (round-1 review corrected
/// an overstatement here). `lib/shared → lib/features` is a layering
/// CONVENTION, not a hard rule: it is not gated by any `check_*.dart`, and
/// FOUR imports already breach it —
/// `lib/shared/mixins/hive_tab_scaffold.dart:75`,
/// `lib/shared/repositories/user_repository.dart:10`,
/// `lib/shared/widgets/video_share_button.dart:5`, and
/// `lib/shared/widgets/wardroom/ward_status_strip.dart:3`. The first draft
/// said THREE: its grep matched only `package:icanbefitter/features/`, and the
/// fourth uses the RELATIVE form `../../../features/...`. Grep both spellings. The first draft of this
/// comment cited `lib/CLAUDE.md` rule 7 as the authority; rule 7 is about
/// import STYLE (relative within a feature, `package:` for shared/core), not
/// direction, so that citation was wrong. Claiming a rule that does not say
/// what you need it to say is the same defect as citing a gate that does not
/// exist.
///
/// The design still stands on its own merits, which is why it was kept: the
/// nudge's Hive WRITE is shared-layer work and belongs here beside the
/// cross-account belt in [markPhaseRepeatNudgePending]; a provider INVALIDATION
/// is widget-layer work and belongs in the widget. Returning the flag keeps
/// each on the side that owns it and adds one more shared→feature edge to a
/// list that should be shrinking, not growing.
class GraduationAdvanceResult {
  final GraduationAdvanceOutcome outcome;

  /// `true` iff repeat pins were actually built AND `phase_repeat_nudge_pending`
  /// was written. NOT the same as the `repeat` argument: `buildRepeatPinsForAdvance`
  /// returns null when its G5 frame-shape gate rejects the pins, and the old code
  /// keyed the nudge on `pins != null`, not on the user's choice.
  final bool repeatNudgeFlagged;

  const GraduationAdvanceResult(
    this.outcome, {
    this.repeatNudgeFlagged = false,
  });
}

/// The graduation screen's phase advance — generation + the progress write,
/// under the SHARED [withPhaseAdvanceLock].
///
/// **Unit B / OI-84.** Hoisted verbatim out of `graduation_screen._onPro`, where
/// it was a ~120-line closure inside a 909-line file that survived Gate 43 only
/// on an allow-list entry. It now sits beside [commitPhaseAdvance] with the
/// other three advance paths ([advanceProPhaseIfExpired],
/// `PhaseProgressReconciler`, the dev sim), completing the "one place owns the
/// phase advance" thesis `c8f3d1` started. The screen keeps UI only.
///
/// Behaviour is unchanged by the move. Two argument choices are forced by the
/// new home rather than chosen:
///  - **[repeat] is a `bool`, not the `AdvanceChoice` enum.** That enum lives in
///    `lib/features/train/widgets/advance_choice_sheet.dart:14`; importing it
///    here would be the same `shared/ → features/` inversion described on
///    [GraduationAdvanceResult]. The closure only ever asked
///    `choice == AdvanceChoice.repeat`, so the boolean loses nothing.
///  - **[profile] is passed in, not re-read.** The caller reads it before the
///    choice sheet opens; re-reading it here would introduce a fresh Hive read
///    across that human-time await and silently change which profile the pins
///    and the generate agree on. They MUST agree — see the G5 note below.
///
/// [stopwatch] is the caller's, so `phase_unlock_plan_generated` keeps measuring
/// from the tap rather than from lock acquisition.
Future<GraduationAdvanceResult> runGraduationPhaseAdvance({
  required WidgetRef ref,
  required Map<dynamic, dynamic> profile,
  required int nextPhase,
  required bool repeat,
  required Stopwatch stopwatch,
}) async {
  final scheduleSvc = ref.read(workoutScheduleReadServiceProvider);

  // Unit 3c (OI-45 finding 5): generation + the progress write run under the
  // SHARED phase-advance mutex, the same one advanceProPhaseIfExpired uses.
  // Before this, graduation generated entirely outside that guard, so the
  // splash's unawaited pass (or the Home/Train card CTA) could be generating
  // this very phase concurrently — two generateAndSchedule runs writing
  // overlapping schedule_* rows and each moving plan_start, the second
  // silently overwriting the first under a user already looking at the plan.
  //
  // The lock is taken AFTER the choice sheet closes, never across it: a modal
  // waiting on human input must not block the splash's advance. That ordering
  // is the CALLER's to keep — this function is already past the sheet.
  return withPhaseAdvanceLock<GraduationAdvanceResult>(
    () async {
      // B-pass F1: re-check the live phase ONCE MORE, now that the lock is
      // actually held. The caller's check ran before acquisition, and the
      // restore-path writers tracked as OI-83 do not take this lock at all
      // — so a bump could have landed in between. Catching it HERE avoids
      // running a full plan generation whose schedule_* rows would then be
      // written for a phase the user is already past, with commitPhaseAdvance
      // correctly declining the counter write afterwards and nothing
      // reconciling the rows. Cheap (one Hive read) versus a generate.
      final liveInLock =
          (UserRepository.instance.getProgress()?['current_phase'] as int?) ?? 1;
      if (liveInLock >= nextPhase) {
        // Distinct from the post-generate decline below: nothing was
        // generated here, so the two must not share one event name.
        unawaited(ErrorTelemetry.logEvent(
            'phase_unlock_preempted_before_generate',
            message: 'live=$liveInLock intended=$nextPhase'));
        return const GraduationAdvanceResult(
            GraduationAdvanceOutcome.preemptedBeforeGenerate);
      }

      // graduation's OWN profile defaults — the SAME values MUST feed both the
      // pin-build and the generate, or repeatPinsFrom's G5 gate validates a
      // different frame-shape than the one generated (writer/reader value drift).
      final goal = profile['primary_goal'] as String? ?? 'general_fitness';
      final equipment = profile['equipment_access'] as String? ?? 'basic_gym';
      final daysPerWeek = (profile['days_per_week'] as num?)?.toInt() ?? 4;
      final experienceLevel =
          profile['fitness_experience'] as String? ?? 'beginner';

      final savedDays = MigratedKey.read<List>('preferred_training_days');
      final preferredDays = savedDays is List ? savedDays.cast<int>() : null;

      // Theme H fix — nextPhaseStartDate computes max(today, currentPhaseEnd + 1)
      // Monday-normalized (was DateTime.now() → overwrote the current W4 rows).
      final startDate = scheduleSvc.nextPhaseStartDate();

      // Build repeat pins BEFORE generateAndSchedule overwrites plan_start
      // (getWeek reads the just-finished window). Only on an explicit "repeat".
      final pins = repeat
          ? scheduleSvc.buildRepeatPinsForAdvance(
              goal: goal,
              equipment: equipment,
              daysPerWeek: daysPerWeek,
              experienceLevel: experienceLevel,
              newPhase: nextPhase,
            )
          : null;

      // W3.4 (Batch 11-B): variety avoid-names on a fresh advance (reader self-gates on the flag; read before plan_start moves, like pins).
      final previousPhaseByDay =
          pins == null ? scheduleSvc.previousPhaseNamesByDay() : null;

      await scheduleSvc.generateAndSchedule(
        goal: goal,
        equipment: equipment,
        daysPerWeek: daysPerWeek,
        startDate: startDate,
        phase: nextPhase,
        // U4: thread injuries so the graduated next-phase plan excludes
        // contraindicated exercises (vocab canonicalized in generateV4).
        injuries: InjuryVocab.fromProfile(profile['injuries']),
        experienceLevel: experienceLevel,
        preferredDays: preferredDays,
        pinnedExercisesByDay: pins,
        // W2.7 (Batch 9): titrate ONLY a FRESH advance (pins == null) — a
        // low-adherence "repeat" (pins != null) must not gain volume.
        applyVolumeTitration: pins == null,
        previousPhaseByDay: previousPhaseByDay,
        applyPlateauEscalation: pins == null, // W3.5 12-A: fresh-advance-only
      );
      unawaited(ErrorTelemetry.logEvent('phase_unlock_plan_generated',
          message: 'phase=$nextPhase ms=${stopwatch.elapsedMilliseconds}'));

      // Theme F — stamp plan_generated_at; UserRepository.updateProgress
      // fires syncProgressNow so this push lands on cloud.
      //
      // Unit 3c (OI-45 finding 5): `nextPhase` was computed at the TOP of the
      // caller, before the tens-to-hundreds-of-ms generateAndSchedule above.
      // commitPhaseAdvance re-reads the live phase HERE and refuses to write a
      // lower one — `current_phase` has no monotonic guard in saveProgress, so
      // a concurrent advancer landing in that window used to be silently
      // demoted.
      final committed = await commitPhaseAdvance(
        intendedPhase: nextPhase,
        source: 'graduation_screen',
      );

      // ⑧ 3-b: a chosen "repeat" (pins applied) flags the Home "step it up
      // next time" nudge (cross-account gated in the shared writer). The
      // provider invalidation that surfaces it THIS session is the caller's —
      // see [GraduationAdvanceResult.repeatNudgeFlagged].
      final repeatNudgeFlagged = pins != null;
      if (repeatNudgeFlagged) {
        await markPhaseRepeatNudgePending();
      }

      // OI-83: `committed == false` means the rows above were generated
      // for a phase the counter did not move to — a concurrent advancer or
      // a cloud restore (which does NOT take this lock, deliberately) got
      // there first. REPORT it; the repair itself is not attempted here —
      // see reportDeclinedAdvanceLeftStaleRows for the three mechanisms
      // that were designed and refuted, and why a correct one needs the
      // losing generation's own key set.
      if (!committed) {
        await reportDeclinedAdvanceLeftStaleRows(
          source: 'graduation_screen',
          intendedPhase: nextPhase,
          livePhase:
              (UserRepository.instance.getProgress()?['current_phase'] as int?) ??
                  1,
        );
      }
      return GraduationAdvanceResult(
        committed
            ? GraduationAdvanceOutcome.committed
            : GraduationAdvanceOutcome.generatedButDeclined,
        repeatNudgeFlagged: repeatNudgeFlagged,
      );
    },
    ifBusy: const GraduationAdvanceResult(GraduationAdvanceOutcome.busy),
  );
}
