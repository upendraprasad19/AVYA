import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/features/ai_coach/services/induction_service.dart';
import 'package:icanbefitter/features/ai_coach/widgets/typing_indicator.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// One-question muster — captures physique focus.
///
/// Route: /coach/muster (entered from Plan screen's "REPORT FOR DUTY",
/// BEFORE InductionScreen's narrative + I COMMIT — diagnose e2b8a4,
/// 2026-09-19). Runs first so nothing is asked AFTER the user commits;
/// I COMMIT is the true final action of the sequence.
///
/// Answer is persisted immediately via
/// [InductionService.recordMusterAnswer], then navigates straight to
/// /coach/induction. [InductionService.completeInduction] (the terminal
/// `induction_completed_at` stamp) is fired from InductionScreen's I COMMIT
/// handler, not here — this screen no longer marks the sequence complete.
///
/// Sequence: typing indicator (1100ms) → reveal question → user answers →
/// CONTINUE → /coach/induction.
///
/// History (diagnose e2b8a4, 2026-09-19): this screen used to ask 3
/// questions (injuries, wake/workout time, physique focus — renumbered from
/// the original 5-question muster after Q1/Q2 were dropped per APK Test
/// #15.4/B2a). Injuries and wake/workout-time were removed as LIVE writer/reader
/// drift, not just redundant UX:
///  - Injuries duplicated Details screen's own onboarding collection
///    (`profile['injuries']`), and muster's `_bridgeToProfile` had no
///    "don't clobber" guard — muster's answer silently overwrote whatever
///    the user told Details, since muster always runs after onboarding.
///  - Wake/workout-time had no onboarding collection point at all, but
///    Edit Profile already has full UI for both (`profile['wake_up_time']`
///    / `profile['preferred_workout_time']`) — asking again in muster was
///    pure duplication. `morning-alert` already degrades gracefully for a
///    null `wake_up_time` (a 07:00 IST fallback quarter, not silence).
/// Their coachBox keys (`known_injuries`, `typical_wake_time`,
/// `preferred_workout_time`) are retained as READ-ONLY in
/// [InductionService] solely so pre-existing users' old answers still
/// migrate onto their profile via the one-shot backfill.
class MusterScreen extends ConsumerStatefulWidget {
  const MusterScreen({super.key});

  @override
  ConsumerState<MusterScreen> createState() => _MusterScreenState();
}

class _MusterScreenState extends ConsumerState<MusterScreen> {
  bool _typing = true;
  bool _submitting = false;

  // Single-select matching profile.physique_focus enum
  // (see edit_profile_screen.dart _buildPhysiqueFocusSelector line ~980).
  static const _physiqueFocusOptions = <(String, String)>[
    ('balanced', 'Balanced — all-round'),
    ('glutes_legs', 'Glutes & Legs'),
    ('chest_shoulders_arms', 'Chest, Shoulders & Arms'),
    ('strength', 'Strength — heavy compounds'),
  ];
  String? _physiqueFocus;

  @override
  void initState() {
    super.initState();
    _showTyping();
  }

  Future<void> _showTyping() async {
    await Future.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;
    setState(() => _typing = false);
  }

  // ── Submit ───────────────────────────────────────────────────────────────

  Future<void> _onSubmit() async {
    if (_physiqueFocus == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      // Wrap single value in 1-element List so the existing coachBox key
      // shape (List<String>) is preserved. ai_snapshot_builder reads the
      // PROFILE field this bridges to (profile['physique_focus']), not this
      // coachBox key directly — see diagnose e2b8a4.
      await InductionService.instance.recordMusterAnswer(
        'body_part_priorities',
        [_physiqueFocus!],
      );
      if (!mounted) return;
      context.go('/coach/induction');
    } catch (e) {
      // B-pass finding (e2b8a4 round 2): recordMusterAnswer can throw
      // (GuardedBox.put's StateError during the documented auth/Hive
      // owner-disagreement race window — auth_hive_owner_agreement SoT).
      // Without this catch, _submitting stayed true forever on a throw,
      // permanently latching CONTINUE unresponsive with no visible error —
      // reset on failure only; success navigates away so the flag is moot.
      if (!mounted) return;
      setState(() => _submitting = false);
      unawaited(ErrorTelemetry.logEvent(
        'muster_submit_failed',
        message: e.toString(),
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save — try again, Recruit.')),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_typing)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: TypingIndicator(),
                ),
              if (!_typing) _buildQuestion(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(String prompt) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        prompt,
        style: const TextStyle(
          fontSize: 15,
          height: 1.6,
          color: AppColors.coachBubbleText,
        ),
      ),
    );
  }

  Widget _buildQuestion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBubble(
            'One quick thing before we deploy — where do you want extra '
            'emphasis? Pick one, your plan will weight that area.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _physiqueFocusOptions.map((opt) {
            final selected = _physiqueFocus == opt.$1;
            return GestureDetector(
              onTap: () => setState(() => _physiqueFocus = opt.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? AppColors.accent : AppColors.card,
                  border: Border.all(
                    color: selected ? AppColors.accent : AppColors.border,
                  ),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  opt.$2,
                  style: TextStyle(
                    color: selected ? AppColors.bgDeep : Colors.white,
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        WardButton(
          label: 'CONTINUE',
          onPressed: _physiqueFocus == null ? null : _onSubmit,
        ),
      ],
    );
  }
}
