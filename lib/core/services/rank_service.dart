import 'dart:async';

import 'package:flutter/foundation.dart';
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
    } catch (e) {
      // Fire-and-forget contract — errors must never propagate to UI.
      debugPrint('[RankService.evaluateAndPromote] $e');
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
    } catch (e) {
      debugPrint('[RankService.getCurrentRank] $e');
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

  String _humanGateText(RankLadderEntry entry) {
    final gate = kRankGates[entry.code]!;
    if (gate.totalWorkoutsAtLeast != null) {
      return '${gate.totalWorkoutsAtLeast} workouts to unlock '
          '${entry.displayName}';
    }
    if (gate.streakAtLeast != null) {
      return '${gate.streakAtLeast}-workout streak + ${entry.minWeeks} '
          'weeks to unlock ${entry.displayName}';
    }
    if (gate.maxGapDays != null) {
      return '${entry.minWeeks}-week active streak (no >${gate.maxGapDays}-day '
          'gap) to unlock ${entry.displayName}';
    }
    return '${entry.minWeeks} weeks to unlock ${entry.displayName}';
  }

  _EvalState _readEvaluationState({DateTime? signupAt}) {
    final repo = WorkoutRepository.instance;
    final progress = UserRepository.instance.getProgress() ?? {};
    final streakDays = repo.calculateCurrentStreak();
    final totalWorkouts =
        (progress['total_workouts_done'] as int?) ?? 0;

    DateTime? signup = signupAt;
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
    return true;
  }
}

class _EvalState {
  final int streakDays;
  final int totalWorkouts;
  final int weeksSinceSignup;
  final int deploymentsComplete;
  final int longestGapDays;

  const _EvalState({
    required this.streakDays,
    required this.totalWorkouts,
    required this.weeksSinceSignup,
    required this.deploymentsComplete,
    required this.longestGapDays,
  });
}
