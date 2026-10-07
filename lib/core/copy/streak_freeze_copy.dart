/// Streak Freeze copy: the notice shown when a freeze is spent on a missed
/// day, and the explainer rules that describe how freezes work.
///
/// Pure functions and constants only (no Flutter, no Hive), so every row is
/// testable. Kept apart from `WardroomCopy`, whose header promises a
/// const-only mirror of the design handoff; this copy takes live numbers.
///
/// The rule behind the words (founder decision 2026-10-06, ledger F8): a freeze
/// is a KEPT stock (+1 each Monday, at most 1 free / 3 PRO), spent
/// automatically on a missed scheduled day, and still spent when the streak
/// breaks anyway. So the notice says what was spent, never that the streak was
/// saved, and never calls the stock "this week's".
///
/// No em dashes (the app uses a middle dot where it needs a separator).
library;

/// Snackbar text for [used] freezes spent just now, with [remaining] left in
/// reserve.
///
/// [used] below 1 reads as 1 (a flag with no count is one freeze, the only
/// value a pre-count build could have written). A null [remaining] means the
/// caller does not know the live count, so the text makes no claim about it.
String streakFreezeUsedNotice({required int used, required int? remaining}) {
  final spent = used < 1 ? 1 : used;
  final head = spent == 1
      ? 'Streak Freeze used on a missed day.'
      : '$spent Streak Freezes used on missed days.';
  if (remaining == null) return head;
  if (remaining >= 1) return '$head $remaining left.';
  return '$head None left. A new one arrives next Monday.';
}

/// The notice for the progress map `UserRepository.getProgress()` returns, or
/// null when no freeze was just spent.
///
/// `remaining` is the LIVE `streak_freezes_available`, read at show time. The
/// `streak_freeze_remaining_after_use` snapshot, written when the freeze was
/// spent, goes stale (a Monday refill, or a restore, can land between the
/// debit and the moment Home shows the notice), so it is used only when the
/// live key is absent. With neither, the count is unknown and the text claims
/// nothing about it.
String? streakFreezeNoticeFromProgress(Map<String, dynamic>? progress) {
  if (progress == null) return null;
  if (progress['streak_freeze_just_used'] != true) return null;
  final used = _wholeNumber(progress['streak_freeze_just_used_count']) ?? 1;
  final remaining = _wholeNumber(progress['streak_freezes_available']) ??
      _wholeNumber(progress['streak_freeze_remaining_after_use']);
  return streakFreezeUsedNotice(used: used, remaining: remaining);
}

/// Explainer rule: what a missed scheduled workout does.
const String kStreakFreezeRuleMissed =
    'Miss a scheduled workout and a Streak Freeze is used for that day '
    'automatically.';

/// Explainer rule: how freezes are earned and how many can be kept.
String streakFreezeRuleRefill(int maxFreezes) =>
    'You earn one new Streak Freeze every Monday and can keep up to '
    '$maxFreezes in reserve.';

/// Explainer note shown to free users about the PRO reserve. The caps are
/// arguments (the caller's own free and PRO caps), never copies kept here, so
/// the words follow the numbers the same screen uses for rule 4.
String streakFreezeProNote({required int freeMax, required int proMax}) =>
    'PRO users can keep up to $proMax freezes in reserve instead of $freeMax.';

/// A stored count as a whole number, or null for anything else. NaN and
/// infinity are `num` but have no integer, and `toInt()` throws on them, so a
/// bad stored value reads as "unknown" instead of throwing.
int? _wholeNumber(Object? raw) =>
    raw is num && raw.isFinite ? raw.toInt() : null;
