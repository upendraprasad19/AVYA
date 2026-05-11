import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/stat_snapshot_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import 'rank_ladder_data.dart';

class RankInfo {
  final RankLadderEntry entry;
  final DateTime? achievedAt;
  final int? daysUntilEligible;
  final int? workoutsRemaining;

  const RankInfo({
    required this.entry,
    this.achievedAt,
    this.daysUntilEligible,
    this.workoutsRemaining,
  });
}

class LadderEntryView {
  final RankLadderEntry entry;
  final bool isEarned;
  final DateTime? earnedAt;
  final String? gateText;

  const LadderEntryView({
    required this.entry,
    required this.isEarned,
    this.earnedAt,
    this.gateText,
  });
}

class RankService {
  RankService._();
  static final RankService instance = RankService._();

  // ── Public API ─────────────────────────────────────────────────

  Future<void> evaluateAndPromote() async {
    try {
      final user = SupabaseService.instance.currentUser;
      if (user == null) return; // not signed in — nothing to write

      // C-7 (audit-2026-05-11) — defensive HiveUserSession bootstrap.
      // Splash fires this fire-and-forget before `_ensureLocalUser` has
      // necessarily opened the session. Without this, every
      // user-scoped box read inside `_readEvaluationState` would throw
      // `HiveUserSession not opened` and the surrounding catch would
      // silently swallow it → users miss rank promotions.
      await HiveUserSession.ensureOpenedForCurrentSession();

      final signupAt = DateTime.tryParse(user.createdAt);
      final state = _readEvaluationState(signupAt: signupAt);
      final qualifiedCode = _qualifiedRankCode(state);
      final qualified = rankByCode(qualifiedCode)!;

      // Read currently-recorded promotions to find which (if any)
      // ranks we still need to insert. `rank_promotions` has UNIQUE
      // (user_id, rank_code) so upsert is safe under retries.
      final supa = SupabaseService.instance.client;
      final existing = await supa
          .from('rank_promotions')
          .select('rank_code')
          .eq('user_id', user.id);
      final existingCodes = (existing as List)
          .map((e) => (e as Map)['rank_code'] as String)
          .toSet();

      // Promote every rank up to and including `qualified` that
      // hasn't been recorded yet. (User might leap multiple rungs in
      // one evaluation — e.g. server cron after long absence.)
      final toInsert = <Map<String, dynamic>>[];
      for (final r in kRankLadder) {
        if (r.ordinal > qualified.ordinal) break;
        if (existingCodes.contains(r.code)) continue;
        toInsert.add({
          'user_id': user.id,
          'rank_code': r.code,
          'trigger_type': _triggerTypeFor(r.code),
          'trigger_metadata': {
            'streak': state.streakDays,
            'total_workouts': state.totalWorkouts,
            'weeks': state.weeksSinceSignup,
            'source': 'client',
          },
        });
      }

      if (toInsert.isNotEmpty) {
        await supa.from('rank_promotions').upsert(
              toInsert,
              onConflict: 'user_id,rank_code',
            );

        // APK Test #6 / Plan F-10 — capture a promotion snapshot per
        // newly-inserted rank. Fire-and-forget; idempotent via
        // (user_id, source='promotion', rank_at_snapshot) check inside
        // snapshotOnPromotion. UNIQUE (user_id, rank_code) on
        // rank_promotions ensures we only get here once per rank, so
        // the snapshot also fires at most once per rank.
        for (final row in toInsert) {
          final code = row['rank_code'] as String;
          unawaited(StatSnapshotService.instance.snapshotOnPromotion(code));
        }
      }

      // Update denormalized current_rank_code only when it actually
      // changed — avoids a no-op write on every call.
      final currentDenorm = await supa
          .from('user_profile')
          .select('current_rank_code')
          .eq('user_id', user.id)
          .maybeSingle();
      final currentCode = currentDenorm == null
          ? null
          : (currentDenorm)['current_rank_code'] as String?;
      if (currentCode != qualified.code) {
        await supa.from('user_profile').update({
          'current_rank_code': qualified.code,
          'current_rank_achieved_at': DateTime.now().toIso8601String(),
        }).eq('user_id', user.id);
      }
    } catch (e, st) {
      // H-42 (audit-2026-05-11) — fire-and-forget contract; errors
      // must never propagate to UI but they MUST reach Crashlytics +
      // client_errors. Splash + post-workout hot path; pre-fix a
      // single debugPrint left us blind to silent failures.
      debugPrint('[RankService.evaluateAndPromote] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'rank_service_evaluate_and_promote'));
    }
  }

  RankInfo getCurrentRank() {
    try {
      final profile = UserRepository.instance.getProfile() ?? {};
      final code = (profile['current_rank_code'] as String?) ?? 'SD2';
      final entry = rankByCode(code) ?? rankByCode('SD2')!;
      final achievedAtRaw = profile['current_rank_achieved_at'];
      final achievedAt = achievedAtRaw is String
          ? DateTime.tryParse(achievedAtRaw)
          : null;
      return RankInfo(entry: entry, achievedAt: achievedAt);
    } catch (e, st) {
      // H-42 (audit-2026-05-11) — same pattern as above.
      debugPrint('[RankService.getCurrentRank] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'rank_service_get_current_rank'));
      return RankInfo(entry: rankByCode('SD2')!);
    }
  }

  RankInfo? getNextRank() {
    final current = getCurrentRank();
    if (current.entry.isTerminal) return null;
    final nextOrdinal = current.entry.ordinal + 1;
    if (nextOrdinal >= kRankLadder.length) return null;
    final nextEntry = kRankLadder[nextOrdinal];

    // Compute how many days / workouts away the user is.
    final state = _readEvaluationState();
    final gate = kRankGates[nextEntry.code]!;

    int? daysOut;
    if (gate.minWeeksSinceSignup != null) {
      final weeksOut = gate.minWeeksSinceSignup! - state.weeksSinceSignup;
      if (weeksOut > 0) daysOut = weeksOut * 7;
    }
    int? workoutsOut;
    if (gate.totalWorkoutsAtLeast != null) {
      workoutsOut = gate.totalWorkoutsAtLeast! - state.totalWorkouts;
      if (workoutsOut < 0) workoutsOut = 0;
    }
    if (gate.streakAtLeast != null) {
      final streakOut = gate.streakAtLeast! - state.streakDays;
      // Convert "10 streak workouts away" into a soft "days away"
      // estimate by assuming workout cadence ~ 4/week → 1.75d/workout.
      // Surfaces in chip copy as "NEXT IN 18 DAYS" — a hint, not a
      // promise.
      if (streakOut > 0) {
        final streakDays = (streakOut * 1.75).ceil();
        daysOut = (daysOut == null)
            ? streakDays
            : (streakDays > daysOut ? streakDays : daysOut);
      }
    }

    // B4: clamp both values to non-negative as a defense-in-depth measure.
    // Individual paths already guard with > 0, but this ensures callers
    // that skip the guard (e.g. chip headers) never render a negative number.
    return RankInfo(
      entry: nextEntry,
      daysUntilEligible: daysOut?.clamp(0, 365),
      workoutsRemaining: workoutsOut?.clamp(0, 10000),
    );
  }

  /// Days until the user reaches the next rank.
  ///
  /// Returns 0 if: at top rank, requirements already met, or no days gate.
  /// ALWAYS non-negative. Shared helper so both chip header and profile
  /// RANK card use the same value with the same sign.
  int daysUntilNextRank() {
    final next = getNextRank();
    return next?.daysUntilEligible?.clamp(0, 365) ?? 0;
  }

  List<LadderEntryView> getLadder() {
    final current = getCurrentRank();
    return kRankLadder.map((entry) {
      final isEarned = entry.ordinal <= current.entry.ordinal;
      final earnedAt =
          (entry.code == current.entry.code) ? current.achievedAt : null;
      return LadderEntryView(
        entry: entry,
        isEarned: isEarned,
        earnedAt: earnedAt,
        gateText: isEarned ? null : _humanGateText(entry),
      );
    }).toList();
  }

  // ── Internals ──────────────────────────────────────────────────

  String _triggerTypeFor(String code) {
    switch (code) {
      case 'SD2':
        return 'signup';
      case 'PO':
      case 'CPO':
        return 'deployment_complete';
      case 'SubLt':
      case 'LtCdr':
      case 'Cdr':
      case 'Capt':
        return 'workout_count';
      case 'MCPO':
        return 'calendar';
      default:
        return 'combined';
    }
  }

  /// Test #10 obs 2 — surfaces every active gate half (the previous
  /// implementation used early-return on a single branch and silently
  /// dropped `deploymentsCompleteAtLeast` for PO/CPO and the entire
  /// `completionRateMinimum` half for MCPO + every officer rank).
  ///
  /// Output is a compact single line, parts joined by ` · ` middot:
  ///   `30-workout streak · 12 weeks of service · 2 deployments complete`
  ///   `52 weeks active · 80% completion · no >14-day gap`
  ///   `2 years of service · 80% completion (rolling 26 weeks)`
  ///
  /// Officer-track calendar weeks (≥104) are rendered in years for
  /// readability — `104 → 2 years`, `130 → 2.5 years`, etc.
  String _humanGateText(RankLadderEntry entry) {
    if (entry.code == 'SD2') return 'Earned at induction';

    final gate = kRankGates[entry.code]!;
    final parts = <String>[];

    if (gate.streakAtLeast != null) {
      parts.add('${gate.streakAtLeast}-workout streak');
    }

    final weeks = entry.minWeeks;
    if (weeks > 0) {
      parts.add(_weeksLabel(weeks, entry));
    }

    if (gate.deploymentsCompleteAtLeast != null) {
      parts.add('${gate.deploymentsCompleteAtLeast} deployments complete');
    }

    if (gate.completionRateMinimum != null &&
        gate.completionRateWindowWeeks != null) {
      final pct = (gate.completionRateMinimum! * 100).round();
      final win = gate.completionRateWindowWeeks!;
      final winLabel = win >= 104
          ? '${(win / 52).toStringAsFixed(0)} years'
          : '$win weeks';
      // MCPO is the only rank that pairs completionRate with maxGapDays.
      // Render its completion compactly without "rolling" qualifier so
      // the third part (gap rule) reads as a peer.
      if (gate.maxGapDays != null) {
        parts.add('$pct% completion');
      } else {
        parts.add('$pct% completion (rolling $winLabel)');
      }
    }

    if (gate.maxGapDays != null) {
      parts.add('no >${gate.maxGapDays}-day gap');
    }

    if (parts.isEmpty) {
      // Fallback for any rank whose gates are entirely empty besides
      // minWeeksSinceSignup. Should not happen for any of the 11 ranks
      // today; defensive.
      return '${entry.minWeeks} weeks to unlock ${entry.displayName}';
    }

    return parts.join(' · ');
  }

  /// Returns the calendar-weeks half of the gate, rendered in years for
  /// officer ranks (≥104 weeks) and in weeks otherwise. Sailor ranks
  /// keep weeks because they're short enough to read directly
  /// (`1 week`, `4 weeks`, `12 weeks`, `26 weeks`).
  String _weeksLabel(int weeks, RankLadderEntry entry) {
    if (entry.category == 'officer' && weeks >= 104) {
      final years = weeks / 52;
      final whole = years == years.truncate();
      final yearText = whole
          ? '${years.toInt()} years'
          : years.toStringAsFixed(1);
      return whole ? '$yearText of service' : '$yearText years of service';
    }
    return weeks == 1 ? '1 week of service' : '$weeks weeks of service';
  }

  _EvalState _readEvaluationState({DateTime? signupAt}) {
    final repo = WorkoutRepository.instance;
    final progress = UserRepository.instance.getProgress() ?? {};
    // C-14 (audit-2026-05-11) — rank-gate evaluation is a READ.
    // Must not consume freezes as a side effect of cron / splash
    // / post-workout fire-and-forget evaluation.
    final streakDays = repo.currentStreak();
    final totalWorkouts =
        (progress['total_workouts_done'] as int?) ?? 0;

    // APK Test #6 obs #7 + spec §3.2 — prefer phase_started_at on
    // user_profile (set by generateAndScheduleFromDate to IST midnight
    // of onboarding day) over auth.users.created_at. Pre-fix, a user
    // who signed up on a Wed but onboarded the following Mon had
    // weeksSinceSignup=1 from auth-created-at the moment they finished
    // onboarding — the gate-relative clock should start when the plan
    // starts, not when the auth row was minted.
    DateTime? signup = signupAt;
    if (signup == null) {
      final profile = UserRepository.instance.getProfile();
      final phaseStartedAtIso = profile?['phase_started_at'] as String?;
      if (phaseStartedAtIso != null) {
        signup = DateTime.tryParse(phaseStartedAtIso);
      }
    }
    if (signup == null) {
      final raw = SupabaseService.instance.currentUser?.createdAt;
      if (raw != null) signup = DateTime.tryParse(raw);
    }
    final weeks = signup == null
        ? 0
        : DateTime.now().difference(signup).inDays ~/ 7;

    // Deployments complete = count of rank_promotions rows with
    // trigger_type='deployment_complete'. Reading that requires a
    // network call; for the *client-side* fast path used by getNextRank
    // we approximate via Hive `progress['deployments_complete']` which
    // is updated when Plan A's W12 path lands (defer until F18 ships;
    // for now this stays at 0 → PO/CPO gate doesn't flip prematurely).
    final deployments =
        (progress['deployments_complete'] as int?) ?? 0;
    final longestGap =
        (progress['longest_gap_days'] as int?) ?? 0;

    return _EvalState(
      streakDays: streakDays,
      totalWorkouts: totalWorkouts,
      weeksSinceSignup: weeks,
      deploymentsComplete: deployments,
      longestGapDays: longestGap,
      workoutRepo: repo,
    );
  }

  String _qualifiedRankCode(_EvalState s) {
    String winner = 'SD2';
    for (final r in kRankLadder) {
      if (_qualifies(r.code, s)) winner = r.code;
    }
    return winner;
  }

  bool _qualifies(String code, _EvalState s) {
    final entry = rankByCode(code);
    if (entry == null) return false;
    if (s.weeksSinceSignup < entry.minWeeks) return false;
    final gate = kRankGates[code]!;
    if (gate.streakAtLeast != null &&
        s.streakDays < gate.streakAtLeast!) {
      return false;
    }
    if (gate.totalWorkoutsAtLeast != null &&
        s.totalWorkouts < gate.totalWorkoutsAtLeast!) {
      return false;
    }
    if (gate.minWeeksSinceSignup != null &&
        s.weeksSinceSignup < gate.minWeeksSinceSignup!) {
      return false;
    }
    if (gate.deploymentsCompleteAtLeast != null &&
        s.deploymentsComplete < gate.deploymentsCompleteAtLeast!) {
      return false;
    }
    if (gate.maxGapDays != null &&
        s.longestGapDays > gate.maxGapDays!) {
      return false;
    }
    if (gate.completionRateMinimum != null) {
      final window = gate.completionRateWindowWeeks ?? 26;
      final rate = s.completionRate(window);
      if (rate < gate.completionRateMinimum!) return false;
    }
    return true;
  }

  /// Test-only entry point: builds an `_EvalState` from explicit inputs
  /// (no Hive / Supabase reads) and runs `_qualifies` against the gate
  /// for [code]. `completionRateOverride` short-circuits the
  /// `completionRateOverWindow` scan — pass it for officer-rank tests.
  ///
  /// Returns `true` iff the rank's gate passes.
  @visibleForTesting
  bool testQualify({
    required String code,
    int streak = 0,
    int totalWorkouts = 0,
    int weeksSinceSignup = 0,
    int deploymentsComplete = 0,
    int longestGapDays = 0,
    double? completionRateOverride,
  }) {
    final state = _EvalState(
      streakDays: streak,
      totalWorkouts: totalWorkouts,
      weeksSinceSignup: weeksSinceSignup,
      deploymentsComplete: deploymentsComplete,
      longestGapDays: longestGapDays,
      workoutRepo: WorkoutRepository.instance,
      completionRateOverride: completionRateOverride,
    );
    return _qualifies(code, state);
  }
}

class _EvalState {
  final int streakDays;
  final int totalWorkouts;
  final int weeksSinceSignup;
  final int deploymentsComplete;
  final int longestGapDays;
  final WorkoutRepository workoutRepo;
  final double? completionRateOverride;

  const _EvalState({
    required this.streakDays,
    required this.totalWorkouts,
    required this.weeksSinceSignup,
    required this.deploymentsComplete,
    required this.longestGapDays,
    required this.workoutRepo,
    this.completionRateOverride,
  });

  /// Lazy completion-rate accessor; only invoked when a gate sets
  /// `completionRateMinimum`. Test code can supply
  /// `completionRateOverride` to skip the Hive scan.
  double completionRate(int windowWeeks) {
    final override = completionRateOverride;
    if (override != null) return override;
    return workoutRepo.completionRateOverWindow(windowWeeks);
  }
}
