import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/services/rank_service.dart';

/// Debug-only developer panel — fast-forward the IST calendar and inspect
/// rank state without building an APK or waiting real time.
///
/// Reached at `/dev` (the route is registered ONLY when [kDebugMode]). The
/// screen itself ALSO guards against release builds defensively, and the
/// clock override it drives is a no-op in release (see [setTestClock]).
///
/// Audit 2026-05-29 Phase B3. Pairs with the injectable clock seam
/// (`ist_date.dart`) and the headless rank year-sim
/// (`test/contracts/rank_year_simulation_test.dart`).
class DevPanelScreen extends StatefulWidget {
  const DevPanelScreen({super.key});

  @override
  State<DevPanelScreen> createState() => _DevPanelScreenState();
}

class _DevPanelScreenState extends State<DevPanelScreen> {
  Duration _offset = Duration.zero;

  void _applyOffset() {
    if (_offset == Duration.zero) {
      resetTestClock();
    } else {
      // Moving clock: real time keeps ticking from the shifted point, so
      // timers/animations still behave naturally while "today" is shifted.
      setTestClock(() => DateTime.now().add(_offset));
    }
    setState(() {});
  }

  void _addDays(int days) {
    _offset += Duration(days: days);
    _applyOffset();
  }

  void _resetClock() {
    _offset = Duration.zero;
    _applyOffset();
  }

  Future<void> _reevaluateRank() async {
    await RankService.instance.evaluateAndPromote();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rank re-evaluated')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kReleaseMode) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Text('Dev panel is disabled in release builds.',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    // Guard the rank reads: pre-auth (no signed-in user) the user-scoped
    // Hive boxes aren't open, so getNextRank() can throw HiveUserSession.
    // The panel must still render so time-travel works before sign-in.
    RankInfo? current;
    RankInfo? next;
    try {
      current = RankService.instance.getCurrentRank();
      next = RankService.instance.getNextRank();
    } catch (_) {
      current = null;
      next = null;
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.header,
        title: const Text('Dev Panel — debug only',
            style: TextStyle(color: AppColors.accent)),
        iconTheme: const IconThemeData(color: AppColors.accent),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            title: 'Clock',
            children: [
              _kv('Today (IST)', istTodayStr()),
              _kv('Override active', isTestClockActive ? 'YES' : 'no'),
              _kv('Offset', '${_offset.inDays} days'),
            ],
          ),
          const SizedBox(height: 12),
          _card(
            title: 'Time travel',
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _btn('+1 day', () => _addDays(1)),
                  _btn('+1 week', () => _addDays(7)),
                  _btn('+4 weeks', () => _addDays(28)),
                  _btn('+12 weeks', () => _addDays(84)),
                  _btn('+1 year', () => _addDays(365)),
                  _btn('Reset', _resetClock, outlined: true),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _card(
            title: 'Rank',
            children: [
              _kv('Current', current == null
                  ? 'n/a (sign in)'
                  : '${current.entry.displayName} (${current.entry.code})'),
              _kv('Next', next == null
                  ? 'n/a'
                  : '${next.entry.displayName} (${next.entry.code})'),
              _kv('Days to next', '${next?.daysUntilEligible ?? 0}'),
              const SizedBox(height: 8),
              _btn('Re-evaluate rank now', _reevaluateRank),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Time travel drives the global IST test clock (ist_date.dart). '
            'It is a no-op in release builds. After jumping the clock, use '
            '"Re-evaluate rank now" to recompute promotions, then open Home / '
            'Profile to see the promotion + new-phase screens.',
            style: TextStyle(color: AppColors.textMute, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _card({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: AppColors.textMute)),
            Flexible(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: AppColors.textPrimary)),
            ),
          ],
        ),
      );

  Widget _btn(String label, VoidCallback onTap, {bool outlined = false}) {
    if (outlined) {
      return OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          side: const BorderSide(color: AppColors.line),
        ),
        child: Text(label),
      );
    }
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accentBg,
        foregroundColor: AppColors.accent,
        elevation: 0,
      ),
      child: Text(label),
    );
  }
}
