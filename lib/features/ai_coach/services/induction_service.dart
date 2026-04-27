import 'dart:async';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

/// Single source for induction state. Idempotency lives here — [hasCommitted]
/// and [inductionCompleted] are the canonical guards.
///
/// Hive keys (in coachBox):
///   committed_at              ISO datetime when user tapped I COMMIT
///   committed_to_lt_cdr       bool, set true on commitment
///   induction_completed_at    ISO datetime when 5-question muster finished
///   why_now / definition_of_winning / known_injuries / typical_wake_time /
///   preferred_workout_time / body_part_priorities  → muster answers
class InductionService {
  static final InductionService instance = InductionService._();
  InductionService._();

  bool get hasCommitted =>
      HiveService.instance.coachBox.get('committed_to_lt_cdr') == true;

  bool get inductionCompleted =>
      HiveService.instance.coachBox.get('induction_completed_at') != null;

  /// Records the I COMMIT tap. Writes Hive immediately, fires sync to Supabase
  /// fire-and-forget per CLAUDE.md §15.
  Future<void> recordCommitment() async {
    final now = DateTime.now().toIso8601String();
    await HiveService.instance.coachBox.put('committed_at', now);
    await HiveService.instance.coachBox.put('committed_to_lt_cdr', true);
    final userId =
        (HiveService.instance.userBox.get('profile') as Map?)?['id'] as String?;
    if (userId != null) {
      unawaited(SyncService.instance.syncCoachMemoryNow(userId));
    }
  }

  static const _allowedMusterKeys = {
    'why_now',
    'definition_of_winning',
    'known_injuries',
    'typical_wake_time',
    'preferred_workout_time',
    'body_part_priorities',
  };

  /// Records a single muster answer. Throws [ArgumentError] on unknown key.
  Future<void> recordMusterAnswer(String key, dynamic value) async {
    if (!_allowedMusterKeys.contains(key)) {
      throw ArgumentError('Unknown muster key: $key');
    }
    await HiveService.instance.coachBox.put(key, value);
  }

  /// Marks the muster complete. Writes Hive + fires sync + pushSnapshot
  /// fire-and-forget per CLAUDE.md §15.
  Future<void> completeMuster() async {
    final now = DateTime.now().toIso8601String();
    await HiveService.instance.coachBox.put('induction_completed_at', now);
    final userId =
        (HiveService.instance.userBox.get('profile') as Map?)?['id'] as String?;
    if (userId != null) {
      unawaited(SyncService.instance.syncCoachMemoryNow(userId));
      unawaited(SyncService.instance.pushSnapshot());
    }
  }
}
