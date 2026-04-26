import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import 'rank_ladder_data.dart';

/// View model emitted from `RankService.getCurrentRank()` /
/// `getNextRank()`. UI-only — never round-trips to Supabase.
class RankInfo {
  final RankLadderEntry entry;
  final DateTime? achievedAt; // null for the not-yet-earned next rank
  final int? daysUntilEligible; // null if eligible now or terminal
  final int? workoutsRemaining; // for total-workout gated ranks

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
  final String? gateText; // e.g. "100 workouts to unlock Sub Lieutenant"

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

  /// Idempotent — evaluates the user's current state, computes the
  /// highest rank they qualify for, and writes a `rank_promotions`
  /// row + denorm `user_profile.current_rank_code` for any rank they
  /// newly qualify for. Fire-and-forget. Catches all errors.
  Future<void> evaluateAndPromote() async {
    // Implemented in Task 2.
    throw UnimplementedError();
  }

  /// Reads from `user_profile.current_rank_code` (denormalized for
  /// fast UI paint). Falls back to `'SD2'` on any read error so UI
  /// never shows blank.
  RankInfo getCurrentRank() {
    // Implemented in Task 2.
    throw UnimplementedError();
  }

  /// Returns the next rank above `getCurrentRank()`, with progress
  /// metrics (days remaining, workouts remaining). Returns null when
  /// user is at `Capt` (terminal).
  RankInfo? getNextRank() {
    // Implemented in Task 2.
    throw UnimplementedError();
  }

  /// Returns the full 10-rung ladder with earned/locked status for
  /// Profile Service Record rendering.
  List<LadderEntryView> getLadder() {
    // Implemented in Task 2.
    throw UnimplementedError();
  }
}
