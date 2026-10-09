import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/local_onboarding_evidence.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/injury_vocab.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/features/profile/services/profile_write_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import '../constants/equipment_defaults.dart';

/// Sealed-class-ish destination resolution for the post-sign-in router.
///
/// `RestoringScreen` and any silent re-auth path call
/// [AuthSessionBootstrapper.resolveDestination] to learn where to send
/// the user next — `goHome`, `resumeOnboarding('<step>')`, or
/// `startMissionBrief`.
sealed class PostSignInDestination {
  const PostSignInDestination();
}

/// Fully onboarded — sync restore can run; final stop is `/home`.
class GoHome extends PostSignInDestination {
  const GoHome();
}

/// Returning user with a `user_profile` row whose
/// `onboarding_completed_at` is still NULL. The bootstrapper inspects
/// the row's column nullness to pick the earliest missing step, and
/// the caller routes to `/onboarding/<step>`.
class ResumeOnboarding extends PostSignInDestination {
  final String firstMissingStep;
  const ResumeOnboarding(this.firstMissingStep);
}

/// Brand-new user — no `user_profile` row exists yet. Caller routes
/// to `/onboarding/mission-brief`.
class StartMissionBrief extends PostSignInDestination {
  const StartMissionBrief();
}

/// **The cloud read did not answer.** Distinct from [StartMissionBrief],
/// which asserts a positive fact ("this user has no profile row").
///
/// closes-diagnose: c2e9f4 — third instance of the restore→onboarding
/// misroute class (1bfeed 2026-05-16, a3f6d9 2026-08-03).
///
/// Before this existed, [AuthSessionBootstrapper.resolveDestination]
/// collapsed THREE outcomes into two: row-present, row-absent, and
/// *could-not-determine* — with the third folded into [StartMissionBrief]
/// under a comment calling it "the conservative fallback". It is
/// conservative for a brand-new user and the single most destructive
/// answer available for an existing one, because it routes a fully
/// onboarded account into onboarding, where completing the flow
/// overwrites a real profile.
///
/// The ambiguity is not hypothetical, and it has two separate entrances
/// that look identical at the call site:
///   1. the SELECT throws (expired JWT → 401, transport error), or
///   2. the SELECT returns HTTP 200 with ZERO ROWS because RLS
///      (`user_profile_select_own`, own-row-only) filtered a request whose
///      token was stale or not yet attached — `.maybeSingle()` yields
///      `null`, byte-identical to "no such user".
///
/// Callers MUST NOT treat this as "new user". `RestoringScreen` consults
/// local Hive evidence instead and, failing that, keeps the user on the
/// restoring screen rather than sending them into onboarding.
class DestinationUnknown extends PostSignInDestination {
  /// Why the read could not be resolved — telemetry/debug only, never
  /// shown to the user.
  final String reason;
  const DestinationUnknown(this.reason);
}

/// Single-owner post-sign-in hydration funnel.
///
/// Tech-debt audit 2026-05-20 finding A1 (god-provider extract) +
/// A9 (widget-layer direct Supabase): `auth_provider.dart` previously
/// did Postgres CRUD on three tables (`users`, `user_profile`,
/// `user_progress`) inline in `_ensureLocalUser`, AND
/// `restoring_screen.dart` ran its own `.from('user_profile').select()`
/// calls inside a Flutter widget. Both violations consolidated here.
///
/// Shape mirrors [WorkoutWriteService] / [HealthWriteService]:
///   - private constructor + static `instance` singleton.
///   - per-user mutex so concurrent `hydrateFromCloud(userId)` /
///     `resolveDestination(userId)` calls serialise rather than
///     racing on the read-modify-write of the local Hive profile map.
///   - all Supabase access goes through
///     [SupabaseService.instance.client] — never `Supabase.instance`
///     directly (matches §4.4 rule #4: no direct Supabase from non-
///     repository / non-service code).
///   - error reporting routed through
///     [ErrorTelemetry.recordNonFatal] (audit A11 pattern).
///
/// Public API:
///   - [resolveDestination] — pure read; the routing decision tree
///     (was `restoring_screen.dart` lines 50/59/228).
///   - [hydrateFromCloud] — writes (merge cloud → Hive, ToS sync,
///     plan regeneration). Was `_ensureLocalUser` lines 477-770.
///   - [pushOneSignalPlayerId] — extracted from `_syncOneSignalPlayerId`.
class AuthSessionBootstrapper {
  AuthSessionBootstrapper._();
  static final AuthSessionBootstrapper instance = AuthSessionBootstrapper._();

  /// §4.6 kill-switch for the OI-150 plan-regeneration anchor. Set `true` in
  /// `configBox` to restore the verbatim pre-fix read of the raw cloud row.
  @visibleForTesting
  static const String kDisableGuardedPlanRegenAnchorKey =
      'disable_guarded_plan_regen_anchor';

  /// Resolves the plan-regeneration anchor for the login restore (OI-150).
  ///
  /// Takes the GUARDED post-merge Hive value, never the raw cloud row. Pure so
  /// the decision has a behavioural test that fails when the runtime path is
  /// mis-wired even if the source text still looks right (rule 21) — the same
  /// reason `WorkoutScheduleReadService.currentWeekColumnProjection` exists.
  ///
  /// An absent or unparseable value falls back to [now], matching what the
  /// pre-fix code did for a null cloud value.
  @visibleForTesting
  static DateTime resolvePlanRegenStart({
    required String? hiveIso,
    required DateTime now,
  }) {
    if (hiveIso == null) return now;
    return DateTime.tryParse(hiveIso) ?? now;
  }

  /// Hard ceiling on how long the post-auth routing read may hold the splash.
  ///
  /// closes-diagnose e5b2a9 — during the 2026-10-01 Supabase API outage the auth
  /// endpoint and the REST endpoints answered 504/521 for ~25 minutes and each
  /// hung request held a connection 10-36 s (same shape as d7b1f8).
  /// [resolveDestination] (token refresh + SELECT + hard-refresh retry +
  /// SELECT) had NO ceiling, so `RestoringScreen._kickoffRestore`'s
  /// `await destinationFuture` never reached its local-evidence branch and the
  /// user sat on "Getting you ready…" until they found the 30 s CONTINUE button.
  static const Duration kDestinationReadLimit = Duration(seconds: 8);

  /// `DestinationUnknown.reason` stamped by the ceiling. Distinct from every
  /// reason [resolveDestination] itself produces, so [resolveBounded] can tell
  /// "the ceiling fired" from "the read answered unknown".
  static const String kDestinationTimeoutReason = 'read_ceiling';

  /// §4.6 kill-switch: `configBox[...] == true` restores the unbounded await.
  static const String kDisableDestinationTimeoutKey =
      'disable_resolve_destination_timeout';

  /// Defensive read — a missing/unopened configBox means the fix stays ACTIVE.
  static bool get destinationTimeoutDisabled {
    try {
      return HiveService.instance.configBox
              .get(kDisableDestinationTimeoutKey) ==
          true;
    } catch (_) {
      return false;
    }
  }

  /// §4.6 kill-switch: `configBox[...] == true` restores the await-the-read path
  /// verbatim (evidence is consulted only AFTER the ceiling fires).
  static const String kDisableEvidenceFirstKey =
      'disable_evidence_first_routing';

  /// Defensive read — a missing/unopened configBox means the change stays ACTIVE.
  static bool get evidenceFirstDisabled {
    try {
      return HiveService.instance.configBox.get(kDisableEvidenceFirstKey) ==
          true;
    } catch (_) {
      return false;
    }
  }

  /// Bounds [read] so an unanswered routing read becomes
  /// [DestinationUnknown]([kDestinationTimeoutReason]) — NEVER
  /// [StartMissionBrief]. "The read did not answer" is its own state (c2e9f4).
  ///
  /// The abandoned read keeps running inside [resolveDestination]'s per-user
  /// lock. A second [resolveDestination] call therefore queues behind it, which
  /// is why the CONTINUE retry is bounded (and guarded) too.
  static Future<PostSignInDestination> boundDestination(
    Future<PostSignInDestination> read, {
    Duration limit = kDestinationReadLimit,
    bool disabled = false,
  }) {
    if (disabled) return read;
    return read.timeout(
      limit,
      onTimeout: () => const DestinationUnknown(kDestinationTimeoutReason),
    );
  }

  /// The routing policy `RestoringScreen._kickoffRestore` runs.
  ///
  ///  * [evidenceFirst] AND the device already holds local evidence of
  ///    onboarding → [GoHome] immediately, without waiting for the cloud. With
  ///    evidence EVERY branch of the screen ends in `_goHome`
  ///    (StartMissionBrief is overridden by the evidence, Unknown goes home on
  ///    it, ResumeOnboarding self-heals and goes home), so the read cannot
  ///    change where the user lands; [onEvidenceFirst] receives the ORIGINAL
  ///    [read] so the one side effect worth keeping (the self-heal stamp, the
  ///    c2e9f4 override signal) still happens when it answers;
  ///  * answered within [limit] → that answer, untouched;
  ///  * ceiling fired AND the device holds local evidence of onboarding → the
  ///    ceiling's [DestinationUnknown] (the screen's existing unknown branch
  ///    then goes home on that evidence);
  ///  * ceiling fired and there is NO local evidence (fresh device / reinstall —
  ///    nothing to fall back to) → keep awaiting the ORIGINAL [read], so a late
  ///    answer still routes instead of being thrown away.
  ///
  /// No evidence ⇒ the evidence-first leg falls straight through to the
  /// pre-existing policy: "the read did not answer" is never [StartMissionBrief]
  /// (c2e9f4) and a fresh device keeps awaiting the original read.
  /// [disabled] (the `disable_resolve_destination_timeout` kill-switch) also
  /// turns [evidenceFirst] off, so that switch still restores the old path whole.
  static Future<PostSignInDestination> resolveBounded(
    Future<PostSignInDestination> read, {
    required Future<bool> Function() hasLocalEvidence,
    Duration limit = kDestinationReadLimit,
    bool disabled = false,
    bool evidenceFirst = false,
    void Function(Future<PostSignInDestination> read)? onEvidenceFirst,
  }) async {
    if (evidenceFirst && !disabled) {
      // Observe `read`'s outcome NOW: nothing listens to it until the evidence
      // check below returns (and, on the evidence path, until the background
      // settle attaches), so an error completing in that gap would otherwise be
      // reported as an uncaught zone error. A later `await read` still sees it.
      read.ignore();
      var evidenceNow = false;
      try {
        evidenceNow = await hasLocalEvidence();
      } catch (_) {
        evidenceNow = false;
      }
      if (evidenceNow) {
        try {
          onEvidenceFirst?.call(read);
        } catch (_) {}
        return const GoHome();
      }
    }
    final bounded =
        await boundDestination(read, limit: limit, disabled: disabled);
    final ceilingFired = bounded is DestinationUnknown &&
        bounded.reason == kDestinationTimeoutReason;
    if (!ceilingFired) return bounded;
    var evidence = false;
    try {
      evidence = await hasLocalEvidence();
    } catch (_) {
      evidence = false;
    }
    if (evidence) return bounded;
    return read;
  }

  /// [resolveDestination] + [resolveBounded] + the kill-switches, for the screen.
  ///
  /// [hasLocalEvidence] MUST open the user-scoped Hive session before it reads
  /// (the screen's `_hasLocalOnboardedEvidence` does). Until the session is open
  /// the raw user-scoped box is unreadable (an owner-null or owner-mismatch
  /// session serves the guarded empty stub and the raw getter throws), which the
  /// screen's callback turns into "no evidence" — evidence-first would then
  /// silently never fire. The callback also honours
  /// `disable_local_onboarded_evidence`, so that switch turns the evidence-first
  /// leg inert too.
  Future<PostSignInDestination> resolveDestinationBounded(
    String userId,
    Future<bool> Function() hasLocalEvidence,
  ) =>
      resolveBounded(
        resolveDestination(userId),
        hasLocalEvidence: hasLocalEvidence,
        disabled: destinationTimeoutDisabled,
        evidenceFirst: !evidenceFirstDisabled,
        onEvidenceFirst: (read) => _settleLateAnswer(userId, read),
      );

  /// The user is already home; the read is still running inside
  /// [resolveDestination]'s per-user lock. Apply its answer when it lands
  /// ([settleLateAnswer] owns the error sink: nothing here may become an
  /// unhandled async error).
  void _settleLateAnswer(String userId, Future<PostSignInDestination> read) {
    unawaited(settleLateAnswer(
      read,
      sessionStillMine: () => _sessionStillMine(userId),
      shouldStamp: () =>
          hasAllRequiredProfileFields(_hive.userBox.get('profile')),
      stamp: () => stampOnboardingCompletedAt(userId),
      logOverride: () => unawaited(ErrorTelemetry.logEvent(
          'restoring_missionbrief_overridden_by_local_evidence',
          message: 'userId=${_shortId(userId)} (evidence-first)')),
      onError: (e, st) => unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'evidence_first_late_answer_failed',
          extra: {'user_id': userId})),
    ));
  }

  /// Waits for the original routing read — NO ceiling: it may take minutes in an
  /// outage and the user is already home — then applies it. Never throws: a
  /// rejecting read, a throwing stamp or a throwing guard all end in [onError].
  @visibleForTesting
  static Future<void> settleLateAnswer(
    Future<PostSignInDestination> read, {
    required bool Function() sessionStillMine,
    required bool Function() shouldStamp,
    required Future<void> Function() stamp,
    required void Function() logOverride,
    required void Function(Object error, StackTrace st) onError,
  }) async {
    try {
      final answer = await read;
      await applyLateAnswer(
        answer,
        sessionStillMine: sessionStillMine,
        shouldStamp: shouldStamp,
        stamp: stamp,
        logOverride: logOverride,
      );
    } catch (e, st) {
      try {
        onError(e, st);
      } catch (_) {}
    }
  }

  /// The late answer may land after a sign-out or an account switch (an
  /// outage-slow read can take 30 s+). It may only touch Hive while BOTH the
  /// Supabase session and the open user-scoped boxes still belong to [userId] —
  /// otherwise the stamp would write into the next user's profile.
  ///
  /// During the TAIL of a sign-out teardown both readers can still name the user
  /// (`clearAllData` and the box deletion run before Supabase `signOut`, and the
  /// Hive owner is nulled only after the boxes close). That window is covered by
  /// the second line: `shouldStamp`'s all-9-fields gate reads the cleared
  /// profile, and a closed guarded box throws into the settle's error sink — at
  /// worst one `evidence_first_late_answer_failed` event, never a cross-account
  /// write.
  bool _sessionStillMine(String userId) => liveSessionOwnedBy(userId);

  /// [sessionOwnedBy] fed by the LIVE Supabase uid and the LIVE Hive owner. The
  /// two readers are injectable so the feed itself (not only the truth table) is
  /// behaviourally testable.
  @visibleForTesting
  static bool liveSessionOwnedBy(
    String userId, {
    String? Function()? supabaseUid,
    String? Function()? hiveOwner,
  }) =>
      sessionOwnedBy(
        userId,
        supabaseUid: (supabaseUid ?? _liveSupabaseUid)(),
        hiveOwner: (hiveOwner ?? _liveHiveOwner)(),
      );

  static String? _liveSupabaseUid() => SupabaseService.instance.currentUser?.id;

  static String? _liveHiveOwner() => HiveUserSession.currentOwnerFullId;

  /// Pure so the cross-account rule is testable: BOTH must name [userId].
  @visibleForTesting
  static bool sessionOwnedBy(
    String userId, {
    required String? supabaseUid,
    required String? hiveOwner,
  }) =>
      supabaseUid == userId && hiveOwner == userId;

  /// What `RestoringScreen._kickoffRestore`'s per-branch work did with the
  /// answer before evidence-first routing — now run AFTER the user is home.
  /// Pure (every effect is injected) so each branch is behaviourally testable.
  ///
  ///  * [StartMissionBrief] with local evidence → only the c2e9f4 override
  ///    signal (cloud says "no row", Hive says onboarded — a stale-token RLS
  ///    filter looks exactly like this); nothing is routed or written;
  ///  * [ResumeOnboarding] → the Plan A self-heal stamp, only when the profile
  ///    carries all 9 migration-112 fields ([shouldStamp]; OI-46 — a
  ///    flag-only legacy user must not retry a write the server rejects);
  ///  * [GoHome] / [DestinationUnknown] → nothing.
  @visibleForTesting
  static Future<void> applyLateAnswer(
    PostSignInDestination answer, {
    required bool Function() sessionStillMine,
    required bool Function() shouldStamp,
    required Future<void> Function() stamp,
    required void Function() logOverride,
  }) async {
    if (!sessionStillMine()) return;
    switch (answer) {
      case StartMissionBrief():
        logOverride();
      case ResumeOnboarding():
        if (shouldStamp()) await stamp();
      case GoHome() || DestinationUnknown():
        break;
    }
  }

  /// Plan A self-heal — stamps `onboarding_completed_at` on both Hive and
  /// Supabase so the populated-but-NULL state can't recur. The ONE writer:
  /// `RestoringScreen._stampOnboardingCompletedAt` delegates here (it used to
  /// hold this body; two copies would drift). Ref-free on purpose — the screen
  /// is disposed by the time a late answer lands.
  ///
  /// Self-protecting for every caller: nothing is written, and nothing is pushed,
  /// unless the session still belongs to [userId] ([sessionStillMine] defaults to
  /// the LIVE check) — checked at entry AND again after the Hive write, because
  /// `syncProfileNow` pushes the WHOLE current profile under [userId]. An
  /// existing real stamp is KEPT (a device that finished onboarding but never
  /// got the push must send the true time, not "now") and is simply pushed.
  /// [push] is injectable for tests.
  ///
  /// Deliberately not routed through `ProfileWriteService.patchProfile`: its
  /// mutex adds an `await` between the ownership check and the write, whereas
  /// this read-modify-write is atomic with the check. A stamp lost to a rare
  /// concurrent full-replace writer is self-healing — the cloud stays NULL, so
  /// the next cold start re-stamps.
  static Future<void> stampOnboardingCompletedAt(
    String userId, {
    bool Function()? sessionStillMine,
    Future<void> Function(String userId)? push,
  }) async {
    final mine = sessionStillMine ?? () => liveSessionOwnedBy(userId);
    if (!mine()) return;
    final profileBox = HiveService.instance.userBox;
    final existing = (profileBox.get('profile') as Map?) ?? <dynamic, dynamic>{};
    final merged = Map<String, dynamic>.from(existing.cast<String, dynamic>());
    final prior = merged['onboarding_completed_at'];
    final hasRealStamp = prior is String && prior.trim().isNotEmpty;
    if (!hasRealStamp) {
      merged['onboarding_completed_at'] = DateTime.now().toUtc().toIso8601String();
      await profileBox.put('profile', merged);
    }
    if (!mine()) return;
    unawaited((push ?? SyncService.instance.syncProfileNow)(userId));
  }

  /// The CONTINUE button's retry: bounded, and a second tap while one is in
  /// flight gets an "unknown" (the screen's existing "tap again" branch) instead
  /// of queueing another abandoned read behind the per-user lock.
  final ExclusiveRun _continueRetry = ExclusiveRun();

  Future<PostSignInDestination> resolveDestinationBoundedOnce(String userId) =>
      _continueRetry.run<PostSignInDestination>(
        () => boundDestination(
          resolveDestination(userId),
          disabled: destinationTimeoutDisabled,
        ),
        whenBusy: const DestinationUnknown('retry_in_flight'),
      );


  /// Per-user mutex. Concurrent calls for the same user (RestoringScreen
  /// + token-refresh listener + manual retry) queue rather than racing.
  /// Map key is the Supabase user id.
  final Map<String, Completer<void>> _locks = {};

  SupabaseService get _supabase => SupabaseService.instance;
  HiveService get _hive => HiveService.instance;

  // ─────────────────────────────────────────────────────────────
  //  Public API
  // ─────────────────────────────────────────────────────────────

  /// Decision tree for "where do we send the user after sign-in?"
  ///
  /// Single live SELECT on `user_profile` for the current user:
  ///   - no row             → [StartMissionBrief]
  ///   - row + completed_at IS NOT NULL → [GoHome]
  ///   - row + completed_at IS NULL     → [ResumeOnboarding(firstMissingStep)]
  ///
  /// `firstMissingStep` is computed by scanning the row's columns in
  /// onboarding order — `identity` < `goal` < `stats` < `details` <
  /// `plan` (same order the screens are wired into the router).
  ///
  /// On a read that FAILS: returns [DestinationUnknown], **not**
  /// [StartMissionBrief] (closes-diagnose c2e9f4). See that class for why
  /// "couldn't read" must never collapse into "brand-new user".
  ///
  /// Before the SELECT, the access token is refreshed via
  /// [SupabaseService.ensureFreshToken] — the same precaution
  /// `SupabaseService.callFunction` has always taken, and for the same
  /// reason (CLAUDE.md §4.4 rule 9: a stale JWT 401s). This read had no such
  /// step, despite being the single decision that routes every returning
  /// user. On a throw it retries ONCE behind a hard `refreshSession()`.
  ///
  /// Kill-switch `configBox['disable_resolve_destination_unknown']` restores
  /// the verbatim pre-fix behaviour (no refresh, no retry, catch →
  /// StartMissionBrief) per §4.6.
  Future<PostSignInDestination> resolveDestination(String userId) async {
    return _withLock(userId, () async {
      final legacyMode = _legacyResolveFallbackEnabled;

      if (!legacyMode) {
        // Proactive refresh — a token that expires mid-flight comes back as
        // either a 401 (throw) or an RLS-filtered empty result (no throw at
        // all), and the second shape is indistinguishable from "no row".
        try {
          await _supabase.ensureFreshToken();
        } catch (e, st) {
          // Non-fatal: the SELECT below may still succeed on the existing
          // token. Recorded so a refresh that fails EVERY boot is visible.
          debugPrint(
              '[AuthSessionBootstrapper.resolveDestination] token refresh: $e');
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'resolve_destination_token_refresh_failed',
              extra: {'user_id': userId}));
        }
      }

      try {
        return classifyDestination(await _selectProfileRow(userId));
      } catch (e, st) {
        debugPrint('[AuthSessionBootstrapper.resolveDestination] $e');
        unawaited(ErrorTelemetry.recordNonFatal(
          e,
          st,
          reason: 'auth_session_bootstrapper_resolve_destination',
          extra: {'user_id': userId},
        ));

        if (legacyMode) {
          // Verbatim pre-fix behaviour behind the kill-switch.
          return const StartMissionBrief();
        }

        // One retry behind a HARD refresh. `ensureFreshToken` above only
        // refreshes inside its expiry buffer; a token rejected for any other
        // reason (rotated, revoked, clock skew) needs the forced path.
        try {
          await _supabase.client.auth.refreshSession();
          final retried = classifyDestination(await _selectProfileRow(userId));
          unawaited(ErrorTelemetry.logEvent(
              'resolve_destination_retry_succeeded',
              message: 'userId=${_shortId(userId)}'));
          return retried;
        } catch (e2, st2) {
          debugPrint(
              '[AuthSessionBootstrapper.resolveDestination] retry failed: $e2');
          unawaited(ErrorTelemetry.recordNonFatal(e2, st2,
              reason: 'resolve_destination_unknown',
              extra: {'user_id': userId}));
          // The whole point of c2e9f4: an unanswered read is its OWN state.
          return DestinationUnknown('read_failed: $e2');
        }
      }
    });
  }

  /// The single `user_profile` SELECT, shared by the first attempt and the
  /// post-refresh retry so the two can never drift in their column list.
  ///
  /// NOTE: identity-step completion is detected via `date_of_birth` (a real
  /// `user_profile` column written by the onboarding identity screen →
  /// sync_profile.dart). Do NOT select `full_name` here — that column lives
  /// on the `users` table, NOT `user_profile`; selecting it raises PostgREST
  /// 42703 and degrades EVERY user. See diagnose
  /// 2026-05-30-resolve-destination-full-name-drift.
  Future<Map<String, dynamic>?> _selectProfileRow(String userId) {
    return _supabase.client
        .from('user_profile')
        .select('user_id, onboarding_completed_at, date_of_birth, '
            'primary_goal, current_weight_kg, fitness_experience')
        .eq('user_id', userId)
        .maybeSingle();
  }

  static String _shortId(String userId) =>
      userId.length >= 8 ? userId.substring(0, 8) : userId;

  /// §4.6 kill-switch. Defaults to the FIX being on (returns false) whenever
  /// Hive is unavailable: without it a failed read mis-routes an onboarded
  /// user into onboarding, so "fix on" is the safe direction.
  bool get _legacyResolveFallbackEnabled {
    try {
      return _hive.configBox.get('disable_resolve_destination_unknown') == true;
    } catch (_) {
      return false;
    }
  }

  /// Pure decision function. Visible-for-testing — given a
  /// `user_profile` row payload (or null for "no row"), returns the
  /// canonical destination. Has no side effects and no Supabase
  /// dependency, so unit tests can pin every branch without spinning
  /// up the SDK.
  ///
  /// Field-order is `identity → goal → stats → details → plan`,
  /// matching the order the onboarding screens are wired into the
  /// router.
  @visibleForTesting
  static PostSignInDestination classifyDestination(
      Map<String, dynamic>? row) {
    if (row == null) return const StartMissionBrief();
    if (row['onboarding_completed_at'] != null) return const GoHome();

    // Row exists but onboarding_completed_at IS NULL → resume.
    // `date_of_birth` is the identity-step sentinel (full_name is on the
    // `users` table, not user_profile — see diagnose 2026-05-30-resolve-
    // destination-full-name-drift).
    if (row['date_of_birth'] == null) {
      return const ResumeOnboarding('identity');
    }
    if (row['primary_goal'] == null) {
      return const ResumeOnboarding('goal');
    }
    if (row['current_weight_kg'] == null) {
      return const ResumeOnboarding('stats');
    }
    if (row['fitness_experience'] == null) {
      return const ResumeOnboarding('details');
    }
    return const ResumeOnboarding('plan');
  }

  /// Pure decision function for the Google OAuth / phone-OTP consent
  /// fallback (closes-diagnose b3f9e7).
  /// Extracted from [hydrateFromCloud] for testability — the same pattern
  /// as [classifyDestination] — since the surrounding method makes live
  /// Supabase network calls a unit test can't exercise.
  ///
  /// Returns true only when the cloud row has no consent value yet, so a
  /// returning user's real historical timestamp is never clobbered on a
  /// later login. (The caller only reaches this helper at all when Hive
  /// also has no value — see the `if (termsAcceptedAt is String...)` guard
  /// immediately above the call site.)
  @visibleForTesting
  static bool shouldStampFallbackTermsConsent({
    required String? cloudTermsAcceptedAt,
  }) {
    return cloudTermsAcceptedAt == null || cloudTermsAcceptedAt.isEmpty;
  }

  /// Google OAuth / phone-OTP consent-fallback stamp (closes-diagnose
  /// b3f9e7). Extracted to its own public method (plan-review round 1,
  /// 2026-08-02) — `hydrateFromCloud` is NOT actually reachable for a real
  /// Google OAuth sign-in: `signInWithGoogle()` never calls
  /// `_ensureLocalUser` (it only starts the OAuth redirect and returns), and
  /// the post-redirect re-entry path (`RestoringScreen._kickoffRestore` →
  /// `resolveDestination` + `SyncService.restoreFromCloudForUser`) never
  /// calls `hydrateFromCloud` either — confirmed by `grep -rn
  /// "hydrateFromCloud(" lib` returning exactly one real call site
  /// (`auth_provider.dart`'s `_ensureLocalUser`, reachable only from
  /// email/OTP). The original design's "hydrateFromCloud is the single
  /// place every post-auth path converges on" premise was wrong for OAuth.
  /// This method is now called from TWO places: `hydrateFromCloud`'s own
  /// else-branch (still correct for phone OTP, which DOES reach
  /// `_ensureLocalUser`) and `RestoringScreen`'s returning-user path (the
  /// actual OAuth convergence point) — see `restoring_screen.dart`.
  ///
  /// PRECONDITION: caller must have already confirmed a Hive session is
  /// open for [userId] (this reads/writes `_hive.userBox`, which throws
  /// `StateError` if `HiveUserSession.openForUser` hasn't run yet — the
  /// exact bug class this diagnose-doc is about). Safe to call more than
  /// once per session — a no-op once Hive already has a value.
  Future<void> ensureTermsConsentFallback(String userId) async {
    try {
      // Plan-review round 2 (2026-08-02): the userBox access used to sit
      // OUTSIDE this try block. A caller violating this method's own
      // documented precondition (Hive session open) would throw an
      // unhandled async StateError from an unawaited() call site instead
      // of routing through ErrorTelemetry.recordNonFatal like every
      // sibling method in this file — inconsistent, and an easy trap for
      // a future call site given this file's whole subject is exactly
      // "precondition not met at the call site." Not currently reachable
      // (both existing call sites are verified safe by construction), but
      // hardened defensively.
      final userBox = _hive.userBox;
      final localTermsAcceptedAt = userBox.get('terms_accepted_at');
      if (localTermsAcceptedAt is String && localTermsAcceptedAt.isNotEmpty) {
        // Primary path (email/OTP Hive write, or a prior run of this same
        // fallback) already has a value — nothing to do.
        return;
      }
      // e5b2a9 (evidence-first routing): `_goHome` now calls this at t~0, no
      // longer AFTER `resolveDestination` has refreshed the token. A stale token
      // can come back as HTTP 200 with ZERO rows (RLS-filtered, c2e9f4) — which
      // would read as "no consent in cloud" and stamp `now()` instead of
      // `created_at`. Refresh first, the same precaution `resolveDestination`
      // takes (§4.4 rule 9). Only legacy users with no local stamp reach here.
      try {
        await _supabase.ensureFreshToken();
      } catch (e, st) {
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'terms_fallback_token_refresh_failed',
            extra: {'user_id': userId}));
      }
      final row = await _supabase.client
          .from('users')
          .select('terms_accepted_at, created_at')
          .eq('id', userId)
          .maybeSingle();
      if (shouldStampFallbackTermsConsent(
          cloudTermsAcceptedAt: row?['terms_accepted_at'] as String?)) {
        // Stamp `created_at`, not `now()` — converges with migration 118's
        // backfill value for the 19 pre-fix legacy rows regardless of which
        // one runs first (B-pass review finding 2, 2026-08-02).
        final stamp = (row?['created_at'] as String?) ??
            DateTime.now().toUtc().toIso8601String();
        await _supabase.client.from('users').update({
          'terms_accepted_at': stamp,
          'terms_version': AppConstants.termsVersion,
        }).eq('id', userId);
        await userBox.put('terms_accepted_at', stamp);
        await userBox.put('terms_version', AppConstants.termsVersion);
      }
    } catch (e, st) {
      debugPrint('[AuthSessionBootstrapper.ensureTermsConsentFallback] '
          'failed: $e');
      unawaited(ErrorTelemetry.recordNonFatal(
        e,
        st,
        reason: 'terms_fallback_stamp_failed',
        extra: {'user_id': userId},
      ));
    }
  }

  /// Long-running post-sign-in cloud hydration.
  ///
  /// Extracted verbatim from the inline block at
  /// `auth_provider.dart._ensureLocalUser` lines 477-770. Owns:
  ///
  ///   - public.users upsert (id, email, full_name, created_at) with
  ///     `ignoreDuplicates: true` so the email-prefix seed is set only
  ///     on first signup.
  ///   - `last_active_at` update.
  ///   - H-3 (audit 2026-05-11) full_name self-heal: if local Hive
  ///     profile carries a real name, push it up — overwrites the
  ///     email-prefix seed.
  ///   - ToS/Privacy acceptance sync (Hive → cloud).
  ///   - F2/F3 user_profile cloud → Hive merge (always pulls, even
  ///     for same-user re-login — fixes stale avatar/banner).
  ///   - user_progress restore.
  ///   - ai_chat_started_at + terms_accepted_at hydration.
  ///   - Local workout schedule regeneration if missing.
  ///   - Last-ditch gap-closer: pushes Hive profile if cloud row
  ///     missing.
  ///   - Early-stage SubscriptionService.refreshFromSupabase fast path.
  ///
  /// All exceptions are caught + routed to ErrorTelemetry. Callers
  /// (the `_ensureLocalUser` orchestrator in auth_provider) wrap this
  /// in their own outer catch so the cross-account guard + verify-
  /// after-clear semantics are preserved at the orchestration layer.
  Future<void> hydrateFromCloud(User user) async {
    final userId = user.id;
    await _withLock(userId, () async {
      final userBox = _hive.userBox;
      final existing = userBox.get('profile');

      // ─── public.users upsert + last_active + ToS sync ──────────
      try {
        await _supabase.client.from('users').upsert({
          'id': user.id,
          'email': user.email ?? '',
          'full_name': user.userMetadata?['full_name'] ??
              ((user.email?.isNotEmpty == true)
                  ? user.email!.split('@').first
                  : 'User'),
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'id', ignoreDuplicates: true);

        // Always update last_active_at (safe — doesn't touch full_name).
        await _supabase.client.from('users').update({
          'last_active_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', user.id);

        // H-3 (audit-2026-05-11) full_name self-heal.
        final localProfile = userBox.get('profile');
        if (localProfile is Map) {
          final localName = (localProfile['full_name'] as String?)?.trim();
          final emailPrefix = (user.email?.contains('@') == true)
              ? user.email!.split('@').first
              : null;
          final looksReal = localName != null &&
              localName.isNotEmpty &&
              RegExp(r'[A-Za-z]').hasMatch(localName) &&
              localName != emailPrefix;
          if (looksReal) {
            await _supabase.client
                .from('users')
                .update({'full_name': localName}).eq('id', user.id);
          }
        }

        // Sync ToS/Privacy acceptance from Hive (stamped by the email
        // sign-up flow — see sign_in_screen.dart / auth_provider.dart).
        final termsAcceptedAt = userBox.get('terms_accepted_at');
        final termsVersion = userBox.get('terms_version');
        if (termsAcceptedAt is String && termsAcceptedAt.isNotEmpty) {
          await _supabase.client.from('users').update({
            'terms_accepted_at': termsAcceptedAt,
            if (termsVersion is String && termsVersion.isNotEmpty)
              'terms_version': termsVersion,
          }).eq('id', user.id);
        } else {
          // closes-diagnose: b3f9e7
          // Phone-OTP fallback (verifyOtp DOES reach _ensureLocalUser →
          // hydrateFromCloud, unlike Google OAuth — see
          // ensureTermsConsentFallback's doc comment for why OAuth needs a
          // SEPARATE call site, wired in RestoringScreen instead).
          await ensureTermsConsentFallback(user.id);
        }
      } catch (e, st) {
        // Bug A defense (2026-04-26): silent-swallow let an orphan
        // public.users row block sync for 48h. Route through canonical
        // ErrorTelemetry so 23505/23503 violations surface (audit A11).
        String errorType = 'users_upsert_failed';
        final eStr = e.toString();
        if (eStr.contains('23505')) {
          errorType = 'users_unique_violation_23505';
        }
        if (eStr.contains('23503')) {
          errorType = 'users_fk_violation_23503';
        }
        debugPrint('[AuthSessionBootstrapper.hydrateFromCloud] '
            'users upsert failed: $e');
        unawaited(ErrorTelemetry.recordNonFatal(
          e,
          st,
          reason: errorType,
          extra: {
            'user_id': user.id,
            'platform': 'android',
            'error_message_preview':
                eStr.length > 1000 ? eStr.substring(0, 1000) : eStr,
          },
        ));
      }

      // ─── user_profile cloud → Hive merge (F2/F3) ───────────────
      try {
        final supabase = _supabase.client;
        final profileRows = await supabase
            .from('user_profile')
            .select()
            .eq('user_id', user.id)
            .limit(1);

        final cloudHasRealData = profileRows.isNotEmpty &&
            (profileRows.first['primary_goal'] != null ||
                profileRows.first['height_cm'] != null);

        final existingMap =
            existing is Map ? Map<String, dynamic>.from(existing) : null;
        final hiveHasRealData = existingMap != null &&
            (existingMap['primary_goal'] != null ||
                existingMap['height_cm'] != null);

        if (cloudHasRealData) {
          // Merge cloud → Hive. Cloud wins for non-null fields; Hive
          // values survive for fields the cloud left null (F2).
          final cloud = Map<String, dynamic>.from(profileRows.first);
          final merged = <String, dynamic>{
            ...?existingMap,
            for (final e in cloud.entries)
              if (e.value != null) e.key: e.value,
          };
          merged['id'] = user.id;
          merged['email'] = user.email;
          // Restore-class hydration → skipSync (audit A4).
          await ProfileWriteService.instance
              .updateProfile(merged, skipSync: true);
          await MigratedKey.write('onboarding_completed', true);

          // Also pull progress (rare to have local progress before login).
          try {
            final progressRows = await supabase
                .from('user_progress')
                .select()
                .eq('user_id', user.id)
                .limit(1);
            if (progressRows.isNotEmpty) {
              final existingProgress = userBox.get('progress');
              final existingProgressMap = existingProgress is Map
                  ? Map<String, dynamic>.from(existingProgress)
                  : <String, dynamic>{};
              final cloudProgress =
                  Map<String, dynamic>.from(progressRows.first);
              // OI-83: the 4 monotonic fields are local-max-wins. This merge
              // used to be cloud-non-null-wins for EVERY key, which silently
              // demoted current_phase / the lifetime counters on a device that
              // had advanced locally and not yet pushed. Shared with
              // sync_profile.dart's _restoreUserProgress so the two restore
              // writers cannot drift — they had already drifted from each
              // other's telemetry (neither had any).
              final progressMerge = UserRepository.mergeCloudProgress(
                local: existingProgressMap,
                cloud: cloudProgress,
                istToday: istDateStr(nowWall()),
              );
              await userBox.put('progress', progressMerge.merged);
              reportProgressDemotionsDeclined(progressMerge,
                  source: 'auth_session_bootstrapper');
              // c9d2f6: the freeze merge kept local ahead of the cloud row.
              if (progressMerge.scheduleFreezeSyncUp) {
                unawaited(SyncService.instance.syncFreezes());
              }
            }

            // Hydrate terms acceptance.
            final userRows = await supabase
                .from('users')
                .select('terms_accepted_at, terms_version')
                .eq('id', user.id)
                .limit(1);
            if (userRows.isNotEmpty) {
              final serverTermsAt =
                  userRows.first['terms_accepted_at'] as String?;
              final serverTermsVersion =
                  userRows.first['terms_version'] as String?;
              if (serverTermsAt != null && serverTermsAt.isNotEmpty) {
                final localTermsAt = userBox.get('terms_accepted_at');
                if (localTermsAt == null) {
                  await userBox.put('terms_accepted_at', serverTermsAt);
                  if (serverTermsVersion != null) {
                    await userBox.put('terms_version', serverTermsVersion);
                  }
                }
              }
            }

            // Regenerate workout schedule locally if plan is missing.
            if (!WorkoutScheduleService.instance.hasPlan() &&
                MigratedKey.read<bool>('onboarding_completed') == true) {
              final goal =
                  merged['primary_goal'] as String? ?? 'general_fitness';
              final equipment =equipmentAccessOf(merged);
              final daysPerWeek =
                  (merged['days_per_week'] as num?)?.toInt() ?? 4;
              final experience =
                  merged['fitness_experience'] as String? ?? 'beginner';
              // OI-83 / d1f6b3 (B-pass finding 1): read the phase from HIVE —
              // the post-merge, monotonically-guarded value — not from the raw
              // cloud row. `progressRows.first['current_phase']` is the
              // PRE-merge cloud value, so on a restore that just refused a
              // demotion (local ahead of cloud, not yet pushed) this block
              // would generate a plan for the LOWER phase while
              // `userBox['progress']` correctly holds the higher one: the
              // counter and the plan content would disagree, which is the
              // same failure shape OI-85 tracks, reached by a third path.
              // Falling back to the local value when the cloud row is absent
              // is also strictly better than the previous hardcoded 1.
              final phase =
                  (UserRepository.instance.getProgress()?['current_phase']
                          as int?) ??
                      1;
              // U4: thread injuries so the login-restore plan regen excludes
              // contraindicated exercises (vocab canonicalized in generateV4).
              final injuries = InjuryVocab.fromProfile(merged['injuries']);

              // OI-150: anchor on the GUARDED post-merge Hive value — the same
              // source `phase` above already uses, for the same reason the
              // :576-586 comment gives. The pre-fix code read
              // `progressRows.first['phase_started_at']`, the RAW PRE-MERGE
              // cloud row, eight lines below a comment explaining why the raw
              // row must not be trusted here. So a restore that had just
              // refused a stale phase regenerated the ADVANCED phase's plan
              // anchored at the STALE phase's start date.
              //
              // The cloud row is deliberately NOT a fallback on the guarded
              // path: it fires exactly when the merge has just declined that
              // value, i.e. only in the state where it is known wrong.
              final DateTime startDate;
              if (HiveService.instance.configBox
                      .get(kDisableGuardedPlanRegenAnchorKey) ==
                  true) {
                // §4.6 kill-switch — verbatim pre-fix behaviour.
                if (progressRows.isNotEmpty) {
                  final genStr =
                      progressRows.first['phase_started_at'] as String?;
                  startDate = genStr != null
                      ? DateTime.tryParse(genStr) ?? DateTime.now()
                      : DateTime.now();
                } else {
                  startDate = DateTime.now();
                }
              } else {
                startDate = resolvePlanRegenStart(
                  hiveIso: UserRepository.instance.getPhaseStartedAtIso(),
                  now: DateTime.now(),
                );
              }

              try {
                await WorkoutScheduleService.instance.generateAndSchedule(
                  goal: goal,
                  equipment: equipment,
                  daysPerWeek: daysPerWeek,
                  startDate: startDate,
                  experienceLevel: experience,
                  phase: phase,
                  injuries: injuries, // U4
                );
              } catch (genErr, genSt) {
                debugPrint(
                    'Plan generation failed on login restore: $genErr');
                unawaited(ErrorTelemetry.recordNonFatal(
                  genErr,
                  genSt,
                  reason: 'auth_session_bootstrapper_login_plan_gen_failed',
                ));
              }
            }
          } catch (e, st) {
            debugPrint(
                '[AuthSessionBootstrapper] Progress/trial restore failed: $e');
            unawaited(ErrorTelemetry.recordNonFatal(
              e,
              st,
              reason: 'auth_session_bootstrapper_progress_trial_restore',
            ));
          }
        } else if (hiveHasRealData) {
          // F3 · Hive is the source of truth; cloud is stale/empty.
          // Push Hive → cloud to repair instead of routing to onboarding.
          await MigratedKey.write('onboarding_completed', true);
          unawaited(SyncService.instance.syncProfileNow(user.id));
        } else {
          // Neither has real data → genuine new user.
          if (profileRows.isNotEmpty) {
            // Delete empty cloud row so onboarding's upsert creates fresh.
            try {
              await supabase
                  .from('user_profile')
                  .delete()
                  .eq('user_id', user.id);
            } catch (_) {}
          }
          // Edge case: users.onboarding_completed=true but user_profile wiped.
          final userRows = await supabase
              .from('users')
              .select('onboarding_completed')
              .eq('id', user.id)
              .limit(1);
          if (userRows.isNotEmpty &&
              (userRows.first['onboarding_completed'] as bool?) == true) {
            await MigratedKey.write('onboarding_completed', true);
          }
        }
      } catch (e, st) {
        debugPrint(
            '[AuthSessionBootstrapper.hydrateFromCloud] restore query failed: $e');
        unawaited(ErrorTelemetry.recordNonFatal(
          e,
          st,
          reason: 'auth_session_bootstrapper_restore_query_failed',
          extra: {'user_id': user.id},
        ));
      }

      // ─── Minimal local profile stub for brand-new users ────────
      // Audit 2026-05-20 A4 — routed through canonical write service.
      // skipSync: true because the user_profile cloud row is created
      // by the onboarding sync path; the minimal stub here doesn't yet
      // have the foreign-key fields the upsert would need.
      if (userBox.get('profile') == null) {
        await ProfileWriteService.instance.updateProfile(
          {
            'id': user.id,
            'email': user.email,
            'created_at': DateTime.now().toIso8601String(),
          },
          skipSync: true,
        );
      }

      // Last-ditch gap closer: if cloud still has no user_profile row,
      // push Hive now. Rare — F3 branch above already handled the main case.
      _pushProfileToSupabaseIfMissing(user.id);

      // F1 · Early-stage subscription refresh.
      unawaited(SubscriptionService.instance.refreshFromSupabase());

      // a4c7d1: One-time heal for mismatched logged exercise sets.
      // After cross-account guard passes, normalize any persisted exlog rows
      // with logging_type mismatches (e.g., from a mid-workout swap).
      unawaited(_healMismatchedExerciseLogs());
    });
  }

  /// Reads OneSignal's current push subscription id and upserts it onto
  /// `user_progress.onesignal_player_id`. Fire-and-forget — failure
  /// must never block auth. Idempotent: same id → upsert is a no-op.
  ///
  /// Extracted from `auth_provider._syncOneSignalPlayerId` (Test #11.1
  /// requirement: persist player_id so delete-account Edge Function
  /// can unsubscribe pushes when the user erases their account).
  Future<void> pushOneSignalPlayerId(String userId, String playerId) async {
    if (playerId.isEmpty) return;
    try {
      await _supabase.client.from('user_progress').upsert({
        'user_id': userId,
        'onesignal_player_id': playerId,
      }, onConflict: 'user_id');
    } catch (e, st) {
      debugPrint('[AuthSessionBootstrapper.pushOneSignalPlayerId] $e');
      unawaited(ErrorTelemetry.recordNonFatal(
        e,
        st,
        reason: 'auth_session_bootstrapper_push_onesignal_player_id',
        extra: {'user_id': userId},
      ));
    }
  }

  /// Convenience wrapper: read OneSignal's push subscription id at the
  /// call site (only available on non-web) and forward to
  /// [pushOneSignalPlayerId]. Used by `auth_provider._ensureLocalUser`.
  Future<void> syncCurrentOneSignalPlayerId(String userId) async {
    if (kIsWeb) return;
    try {
      final playerId = OneSignal.User.pushSubscription.id;
      if (playerId == null || playerId.isEmpty) return;
      await pushOneSignalPlayerId(userId, playerId);
    } catch (e, st) {
      debugPrint('[AuthSessionBootstrapper.syncCurrentOneSignalPlayerId] $e');
      unawaited(ErrorTelemetry.recordNonFatal(
        e,
        st,
        reason: 'auth_session_bootstrapper_sync_current_player_id',
      ));
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  Internals
  // ─────────────────────────────────────────────────────────────

  /// Checks if `user_profile` row is missing in Supabase and pushes
  /// local Hive profile if so. Fire-and-forget — never blocks sign-in.
  void _pushProfileToSupabaseIfMissing(String userId) async {
    try {
      final rows = await _supabase.client
          .from('user_profile')
          .select('user_id')
          .eq('user_id', userId)
          .limit(1);
      if (rows.isEmpty) {
        await SyncService.instance.syncProfileNow(userId);
        debugPrint(
            '[AuthSessionBootstrapper] Gap detected — pushed missing user_profile.');
      }
    } catch (_) {
      // Offline — SyncService.checkAndSync() will handle on next launch.
    }
  }

  /// a4c7d1: One-time boot heal for mismatched logged exercise sets.
  ///
  /// When an exercise is swapped mid-workout, in-flight logged sets may carry
  /// the OLD logging type's format. This method normalizes any persisted
  /// exlog rows with a type mismatch against the exercise's library definition.
  /// Runs post-login, after cross-account guard passes.
  ///
  /// Non-fatal on error — boot continues even if heal fails.
  Future<void> _healMismatchedExerciseLogs() async {
    try {
      final workoutBox = _hive.workoutBox;
      final exerciseBox = _hive.exerciseBox;

      for (final key in workoutBox.keys) {
        if (key is! String || !key.startsWith('exlog_')) continue;

        final log = workoutBox.get(key);
        if (log is! Map) continue;

        final loggedType = log['logging_type'] as String?;
        final exerciseName = log['exercise_name'] as String?;
        if (loggedType == null || exerciseName == null) continue;

        // Resolve the exercise's CURRENT library definition
        final libraryExercise = exerciseBox.values.firstWhere(
          (e) => e is Map && (e['name'] as String?) == exerciseName,
          orElse: () => null,
        ) as Map?;
        final correctType = libraryExercise?['logging_type'] as String? ?? loggedType;

        // If mismatch, normalize the sets
        if (loggedType != correctType) {
          final sets = (log['sets'] as List? ?? []).cast<Map<String, dynamic>>();
          final normalized = sets.map((s) {
            if (correctType == 'timed') {
              s['weight_kg'] = 0;
              s['reps'] = 0;
            } else {
              s['duration_sec'] = 0;
            }
            return s;
          }).toList();

          log['sets'] = normalized;
          log['logging_type'] = correctType;
          await workoutBox.put(key, log);

          unawaited(ErrorTelemetry.recordNonFatal(
            Exception('exlog_format_normalization_healed'),
            null,
            reason: 'exlog_format_normalization_healed',
            extra: {
              'exercise_name': exerciseName,
              'old_type': loggedType,
              'new_type': correctType,
            },
          ));
        }
      }
    } catch (e, st) {
      unawaited(ErrorTelemetry.recordNonFatal(
        e,
        st,
        reason: 'exlog_format_normalization_heal_failed',
      ));
      // Non-fatal; boot continues
    }
  }

  /// Per-user mutex helper. Concurrent calls for the same userId queue;
  /// calls for different users run independently.
  Future<T> _withLock<T>(String userId, Future<T> Function() op) async {
    while (_locks[userId] != null) {
      try {
        await _locks[userId]!.future;
      } catch (_) {/* swallowed; holder will release */}
    }
    final c = Completer<void>();
    _locks[userId] = c;
    try {
      return await op();
    } finally {
      _locks.remove(userId);
      if (!c.isCompleted) c.complete();
    }
  }
}

/// Runs one async job at a time: a call made while another is in flight returns
/// [whenBusy] without starting, and the slot is released even if the job throws.
class ExclusiveRun {
  bool _busy = false;

  Future<T> run<T>(Future<T> Function() start, {required T whenBusy}) async {
    if (_busy) return whenBusy;
    _busy = true;
    try {
      return await start();
    } finally {
      _busy = false;
    }
  }
}
