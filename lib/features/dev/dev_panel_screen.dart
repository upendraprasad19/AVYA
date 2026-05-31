import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/features/dev/simulation_service.dart';

/// Debug-only developer panel — fast-forward the IST calendar, run the
/// year-simulation harness, toggle PRO, and inspect rank state without
/// building an APK or waiting real time.
///
/// Reached at `/dev` (the route is registered ONLY when [kDebugMode]). The
/// screen itself ALSO guards against release builds defensively, and the
/// clock override it drives is a no-op in release (see [setTestClock]).
///
/// Audit 2026-05-29 Phase B3 (time travel + rank). Extended 2026-05-31 with
/// the [SimulationService] driver (Simulation + Account cards). Pairs with
/// the injectable clock seam (`ist_date.dart`).
class DevPanelScreen extends ConsumerStatefulWidget {
  const DevPanelScreen({super.key});

  @override
  ConsumerState<DevPanelScreen> createState() => _DevPanelScreenState();
}

class _DevPanelScreenState extends ConsumerState<DevPanelScreen> {
  Duration _offset = Duration.zero;
  String _simStatus = 'idle';
  String? _lastReport;

  void _applyOffset() {
    if (_offset == Duration.zero) {
      resetTestClock();
    } else {
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
    _toast('Rank re-evaluated');
  }

  // ── Simulation ──────────────────────────────────────────────────

  void _resetSim() {
    SimulationService.instance.resetCursor(ref);
    setState(() {
      _simStatus = 'cursor reset to day 0';
      _lastReport = null;
    });
  }

  Future<void> _resetJourney() async {
    setState(() => _simStatus = 'resetting journey…');
    await SimulationService.instance.resetJourney(ref);
    if (!mounted) return;
    setState(() {
      _simStatus = 'journey reset — SD2 / free / Phase 1 wk1';
      _lastReport = null;
    });
    _toast('Journey reset to day-0 baseline');
  }

  Future<void> _runSim(int days) async {
    if (SimulationService.instance.isBusy) return;
    setState(() => _simStatus = 'running $days days…');
    final report = await SimulationService.instance.run(ref: ref, days: days);
    if (!mounted) return;
    setState(() {
      _simStatus = 'done — clock now at ${istTodayStr()}';
      _lastReport = report.summarize();
    });
    _toast('Simulated $days days');
  }

  // ── Account / PRO ───────────────────────────────────────────────

  Future<void> _grantPro() async {
    final expires = nowWall().add(const Duration(days: 365)).toIso8601String();
    await SubscriptionService.instance.writeSubscriptionState(
      isPro: true,
      expiresAt: expires,
      plan: 'yearly',
    );
    if (!mounted) return;
    setState(() {});
    _toast('PRO granted (1 yr)');
  }

  Future<void> _revokePro() async {
    await SubscriptionService.instance.writeSubscriptionState(
      isPro: false,
      expiresAt: '',
      plan: 'free',
    );
    if (!mounted) return;
    setState(() {});
    _toast('PRO revoked');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
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

    RankInfo? current;
    RankInfo? next;
    try {
      current = RankService.instance.getCurrentRank();
      next = RankService.instance.getNextRank();
    } catch (_) {
      current = null;
      next = null;
    }

    bool isPro = false;
    try {
      isPro = SubscriptionService.instance.isPro();
    } catch (_) {}

    final simCursor = SimulationService.instance.cursor;

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
            title: 'Simulation (year-sim harness)',
            children: [
              _kv('Cursor',
                  simCursor == null ? 'not set' : istDateStr(simCursor)),
              _kv('Status', _simStatus),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _btn('Reset journey (day-0)', _resetJourney, outlined: true),
                  _btn('Reset cursor', _resetSim, outlined: true),
                  _btn('Sim +1 week', () => _runSim(7)),
                  _btn('Sim +4 weeks', () => _runSim(28)),
                  _btn('Sim +12 weeks', () => _runSim(84)),
                  _btn('Sim +1 year', () => _runSim(365)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _card(
            title: 'Account',
            children: [
              _kv('PRO', isPro ? 'YES' : 'no'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _btn('Grant PRO (1 yr)', _grantPro),
                  _btn('Revoke PRO', _revokePro, outlined: true),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _card(
            title: 'Rank',
            children: [
              _kv(
                  'Current',
                  current == null
                      ? 'n/a (sign in)'
                      : '${current.entry.displayName} (${current.entry.code})'),
              _kv(
                  'Next',
                  next == null
                      ? 'n/a'
                      : '${next.entry.displayName} (${next.entry.code})'),
              _kv('Days to next', '${next?.daysUntilEligible ?? 0}'),
              const SizedBox(height: 8),
              _btn('Re-evaluate rank now', _reevaluateRank),
            ],
          ),
          if (_lastReport != null) ...[
            const SizedBox(height: 12),
            _card(
              title: 'Last sim report',
              children: [
                SelectableText(
                  _lastReport!,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Simulation drives the REAL write path dated to each simulated '
            'day via the clock seam. Run free weeks 1-4 first, then Grant PRO '
            'and continue — phases auto-generate at each 4-week boundary. The '
            'clock is left at the final simulated day so the live screens show '
            'the end-state; tap Reset (Time travel) to return to real now.',
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
