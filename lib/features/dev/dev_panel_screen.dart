import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/services/day_rollover_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/features/dev/simulation_service.dart';
import 'package:icanbefitter/features/dev/plan_xls.dart';

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
  SimReport? _lastReportObj;

  @override
  void initState() {
    super.initState();
    // Debug-only deterministic autorun: open `/dev?autorun=lt` (full URL
    // http://host/?autorun=lt#/dev) to drive amar reset → PRO → 910-day sim
    // → Lieutenant → Excel export with ZERO in-app clicking. Added because
    // CanvasKit scroll/drag is unreliable for reaching the below-the-fold
    // sim buttons during automated browser driving. No-op in release and
    // when the flag is absent.
    final auto = Uri.base.queryParameters['autorun'];
    if (kDebugMode && (auto == 'lt' || auto == 'diag')) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autorunToLt());
    }
  }

  /// Full deterministic journey to Lieutenant + plan export, logged to the
  /// console (debugPrint) so the run is observable without the UI.
  Future<void> _autorunToLt() async {
    if (!kDebugMode) return;
    if (SimulationService.instance.isBusy) {
      debugPrint('[autorun] aborted — a sim is already in flight');
      return;
    }
    debugPrint('[autorun] === Lieutenant journey START ===');
    // The deep-link to /dev can mount this screen before Supabase finishes
    // init (the normal session bootstrap runs in the restore flow we skip).
    // Wait for the auth session + open the user-scoped Hive boxes so
    // resetJourney's box access succeeds (otherwise it throws on userBox).
    debugPrint('[autorun] waiting for Supabase session…');
    for (var i = 0; i < 120; i++) {
      if (SupabaseService.instance.currentUser != null) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    await HiveUserSession.ensureOpenedForCurrentSession();
    if (SupabaseService.instance.currentUser == null) {
      debugPrint('[autorun] ABORT — no Supabase session after 60s wait');
      return;
    }
    debugPrint('[autorun] session ready (${HiveUserSession.currentOwnerFullId})');
    // Pause subscription server-refresh NOW (before grant): the sim user has no
    // real subscriptions row, so an un-paused refresh would downgrade the
    // dev-granted PRO before the sim loop even starts. Cleared by
    // SimulationService.run's finally. (Debug-only.)
    SubscriptionService.pausedForSimulation = true;
    debugPrint('[autorun] reset journey (day-0)…');
    await SimulationService.instance.resetJourney(ref);
    debugPrint('[autorun] grant PRO (10-yr sim window)…');
    await _grantPro();
    // diag mode = short 49-day run (covers the Phase 1→2 transition at ~day 28)
    // for fast root-causing; lt mode = full 910-day journey to Lieutenant.
    final isDiag = Uri.base.queryParameters['autorun'] == 'diag';
    final days = isDiag ? 49 : 910;
    debugPrint('[autorun] sim $days days (adherence 0.99)…');
    if (!mounted) return;
    setState(() => _simStatus = 'autorun: simulating $days days…');
    var lastLogged = 0;
    final report = await SimulationService.instance.run(
      ref: ref,
      days: days,
      adherence: 0.99,
      onProgress: (line) {
        // Throttle: log roughly every 28 simulated days.
        final m = RegExp(r'Day (\d+)/').firstMatch(line);
        final d = m == null ? 0 : int.tryParse(m.group(1) ?? '0') ?? 0;
        if (d - lastLogged >= 28 || d == days) {
          lastLogged = d;
          debugPrint('[autorun] $line');
        }
      },
    );
    if (!mounted) return;
    _lastReportObj = report;
    setState(() {
      _simStatus = 'autorun done — ${istTodayStr()}';
      _lastReport = report.summarize();
    });
    debugPrint('[autorun] === sim done ===');
    debugPrint('[autorun] ${report.summarize().replaceAll("\n", " | ")}');
    debugPrint('[autorun] captured ${report.capturedPhases.length} phase plans');
    if (report.capturedPhases.isEmpty) {
      debugPrint('[autorun] WARNING: no captured phases — export skipped');
      return;
    }
    final fname = 'amar_plans_to_lt_${istTodayStr()}.xls';
    downloadPlansXls(fname, report.capturedPhases);
    debugPrint('[autorun] export triggered → $fname (browser download)');
    debugPrint('[autorun] === Lieutenant journey COMPLETE ===');
  }

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
      _lastReportObj = report;
    });
    _toast('Simulated $days days');
  }

  void _exportPlans() {
    final r = _lastReportObj;
    if (r == null || r.capturedPhases.isEmpty) {
      _toast('No captured plans — run a sim first');
      return;
    }
    downloadPlansXls('amar_plans_to_lt_${istTodayStr()}.xls', r.capturedPhases);
    _toast('Exported ${r.capturedPhases.length} phase plans (.xls)');
  }

  // ── Account / PRO ───────────────────────────────────────────────

  Future<void> _grantPro() async {
    // 10-year window (was 1 yr): the year-sim fast-forwards the clock up to
    // 2.5 simulated years (910-day → Lieutenant run). A 1-yr expiry would
    // lapse against the simulated clock partway through, silently halting
    // PRO-gated phase generation. 10 yr keeps PRO valid for the whole span so
    // a SINGLE run() captures every generated phase in one SimReport.
    final expires = nowWall().add(const Duration(days: 3650)).toIso8601String();
    await SubscriptionService.instance.writeSubscriptionState(
      isPro: true,
      expiresAt: expires,
      plan: 'yearly',
    );
    if (!mounted) return;
    setState(() {});
    _toast('PRO granted (10 yr — sim window)');
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

  // ── Ship-dark flags ─────────────────────────────────────────────

  /// Re-reads every daily-scoped provider so a clock jump or a flag flip is
  /// actually REFLECTED on screen.
  ///
  /// Why this exists: Riverpod caches `currentPlanProvider`, and nothing else in
  /// this panel invalidates anything — so time-travelling and walking to Train
  /// can render month-old data, and a flag flip can appear to do nothing. The
  /// obvious workaround is a trap: reloading the page DOES rebuild providers but
  /// also wipes `_clockOverride`, which is an in-memory static (`ist_date.dart`),
  /// silently returning you to real time.
  ///
  /// Delegates to the canonical invalidation entry point rather than hand-rolling
  /// a second provider list that could drift from it.
  Future<void> _refreshProviders() async {
    await DayRolloverObserver.instance.runRolloverNow(ref);
    if (!mounted) return;
    setState(() {});
    _toast('Providers refreshed');
  }

  Future<void> _toggleHoldWeeks() async {
    final next = !PlanEngineFlags.holdWeeksEnabled;
    // configBox is the SHARED, UNSYNCED Hive box — this never reaches the cloud
    // and never leaves this browser profile / device.
    await HiveService.instance.configBox.put('enable_hold_weeks', next);
    await DayRolloverObserver.instance.runRolloverNow(ref);
    if (!mounted) return;
    setState(() {});
    _toast('enable_hold_weeks = ${next ? 'ON' : 'OFF'}');
  }

  /// The equipment-exclusions KILL-SWITCH (diagnose e2d6b8, flipped ON
  /// 2026-08-05). Unlike `enable_hold_weeks` this flag is DEFAULT ON, so the
  /// switch writes `disable_equipment_exclusions = true` to turn the feature
  /// OFF and DELETES the key to return to the default.
  ///
  /// Added because round-1 review found the kill-switch had NO writer anywhere
  /// in the app: §4.6 requires the old path stay "reachable when the gate is
  /// closed", and a gate nothing can close is not reachable — reverting a
  /// platform-tier plan change for every gym-tier user would have needed a code
  /// change plus an APK respin.
  ///
  /// Turning it OFF reverts BOTH behaviours this one flag gates: the exclusion
  /// filter AND ⑥ C2's WU-2 gym-cardio pools.
  Future<void> _toggleEquipmentExclusions() async {
    final nextEnabled = !PlanEngineFlags.equipmentExclusionsEnabled;
    final cfg = HiveService.instance.configBox;
    if (nextEnabled) {
      await cfg.delete('disable_equipment_exclusions');
    } else {
      await cfg.put('disable_equipment_exclusions', true);
    }
    await DayRolloverObserver.instance.runRolloverNow(ref);
    if (!mounted) return;
    setState(() {});
    _toast('equipment exclusions = ${nextEnabled ? 'ON' : 'OFF (killed)'} '
        '— regenerate a plan to see the effect');
  }

  /// Readiness kill-switch. Deleting the key returns to the default (ON).
  ///
  /// Added because a gate nothing can close is not reachable (CLAUDE.md 4.6) --
  /// the equipment-exclusions flip hit this identical gap and its fix records
  /// why at the sibling method below.
  Future<void> _toggleReadiness() async {
    final nextEnabled = !PlanEngineFlags.readinessEnabled;
    final cfg = HiveService.instance.configBox;
    if (nextEnabled) {
      await cfg.delete('disable_readiness');
    } else {
      await cfg.put('disable_readiness', true);
    }
    await DayRolloverObserver.instance.runRolloverNow(ref);
    if (!mounted) return;
    setState(() {});
    _toast('readiness = ${nextEnabled ? 'ON' : 'OFF (killed)'} '
        '-- applies on your next Start Workout');
  }

  /// Phase-arc kill-switch. Deleting the key returns to the default (ON).
  ///
  /// Added with the 2026-09-05 flip, for the same reason as the sibling above:
  /// a gate nothing can close is not reachable (CLAUDE.md §4.6). ⚠ This is
  /// DEBUG-ONLY and is NOT a production rollback — `/dev` is registered behind
  /// `kDebugMode` (`app_router.dart:337`), so it is compiled out of
  /// `--flavor prod --release` and there is no RemoteConfig. Reverting the flip
  /// for real users means a code revert plus a store round-trip (OI-95).
  Future<void> _togglePhaseArc() async {
    final nextEnabled = !PlanEngineFlags.phaseArcEnabled;
    final cfg = HiveService.instance.configBox;
    if (nextEnabled) {
      await cfg.delete('disable_phase_arc');
    } else {
      await cfg.put('disable_phase_arc', true);
    }
    // Load-bearing, and the reason the sibling toggles all call
    // runRolloverNow: `setState` rebuilds THIS screen, not the Train tab.
    // phaseArcProvider reads the flag non-reactively and watches
    // currentPlanProvider, so invalidating that is what actually re-runs the
    // gate. Without it the switch appears inert until something else forces a
    // Train rebuild -- a kill-switch you cannot observe working is the same
    // problem as one you cannot reach.
    ref.invalidate(currentPlanProvider);
    if (!mounted) return;
    setState(() {});
    _toast('phase arc = ${nextEnabled ? 'ON' : 'OFF (killed)'} '
        '-- applies on your next Train tab rebuild');
  }

  /// Deload-reason-line kill-switch (OI-53 flag 4, live 2026-09-06).
  ///
  /// Same shape as [_togglePhaseArc]. The invalidate is load-bearing, but name
  /// the chain precisely: the FLAG is read in `PhaseArcStrip.build`, NOT in
  /// deloadReasonProvider, and non-reactively — so nothing about
  /// deloadReasonProvider's VALUE changes when the flag toggles. What rebuilds
  /// the widget is `phaseArcProvider` re-emitting a new `PhaseArcData`, which
  /// works only because that class has no `==` override. Adding value equality
  /// to it would make this toggle silently inert.
  Future<void> _toggleDeloadReasonLine() async {
    final nextEnabled = !PlanEngineFlags.deloadReasonLineEnabled;
    final cfg = HiveService.instance.configBox;
    if (nextEnabled) {
      await cfg.delete('disable_deload_reason_line');
    } else {
      await cfg.put('disable_deload_reason_line', true);
    }
    ref.invalidate(currentPlanProvider);
    if (!mounted) return;
    setState(() {});
    _toast('deload reason line = ${nextEnabled ? 'ON' : 'OFF (killed)'} '
        '-- applies on your next Train tab rebuild');
  }

  /// Triggered-deload kill-switch.
  ///
  /// WARNING: turning this OFF also stops NEW plans stashing their working
  /// base, so a plan generated while it is off can never be lifted later.
  /// runRolloverNow is load-bearing here: it is what invokes
  /// DeloadEvaluator.maybeEvaluate(), so without it the toggle has no
  /// observable effect until the next real rollover.
  Future<void> _toggleTriggeredDeload() async {
    final nextEnabled = !PlanEngineFlags.triggeredDeloadEnabled;
    final cfg = HiveService.instance.configBox;
    if (nextEnabled) {
      await cfg.delete('disable_triggered_deload');
    } else {
      await cfg.put('disable_triggered_deload', true);
    }
    await DayRolloverObserver.instance.runRolloverNow(ref);
    if (!mounted) return;
    setState(() {});
    _toast('triggered deload = ${nextEnabled ? 'ON' : 'OFF (killed)'} '
        '-- generate a new plan for the stash to apply');
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
      isPro = SubscriptionService.instance.proStateSnapshot(); // OI-44 U6: build
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
            title: 'Ship-dark flags',
            children: [
              _kv('enable_hold_weeks',
                  PlanEngineFlags.holdWeeksEnabled ? 'ON' : 'off'),
              // DEFAULT ON since 2026-08-05 (e2d6b8) — the kill-switch key is
              // `disable_equipment_exclusions`, so "off" here means killed.
              _kv('equipment exclusions (+ WU-2 gym cardio)',
                  PlanEngineFlags.equipmentExclusionsEnabled ? 'ON' : 'KILLED'),
              _kv('readiness',
                  PlanEngineFlags.readinessEnabled ? 'ON' : 'KILLED'),
              _kv('triggered deload',
                  PlanEngineFlags.triggeredDeloadEnabled ? 'ON' : 'KILLED'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _btn(
                    PlanEngineFlags.holdWeeksEnabled
                        ? 'Turn hold weeks OFF'
                        : 'Turn hold weeks ON',
                    () => _toggleHoldWeeks(),
                  ),
                  _btn(
                    PlanEngineFlags.equipmentExclusionsEnabled
                        ? 'KILL equipment exclusions'
                        : 'Restore equipment exclusions',
                    () => _toggleEquipmentExclusions(),
                  ),
                  _btn(
                    PlanEngineFlags.readinessEnabled
                        ? 'KILL readiness'
                        : 'Restore readiness',
                    () => _toggleReadiness(),
                  ),
                  _btn(
                    PlanEngineFlags.triggeredDeloadEnabled
                        ? 'KILL triggered deload'
                        : 'Restore triggered deload',
                    () => _toggleTriggeredDeload(),
                  ),
                  _btn(
                    PlanEngineFlags.phaseArcEnabled
                        ? 'KILL phase arc'
                        : 'Restore phase arc',
                    () => _togglePhaseArc(),
                  ),
                  _btn(
                    PlanEngineFlags.deloadReasonLineEnabled
                        ? 'KILL deload reason line'
                        : 'Restore deload reason line',
                    () => _toggleDeloadReasonLine(),
                  ),
                  // Use after every time-travel jump — the clock buttons above
                  // do NOT invalidate providers on their own.
                  _btn('Refresh providers', () => _refreshProviders(),
                      outlined: true),
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
                  _btn('Sim → Lieutenant (130wk)', () => _runSim(910)),
                  _btn('Export plans (.xls)', _exportPlans, outlined: true),
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
