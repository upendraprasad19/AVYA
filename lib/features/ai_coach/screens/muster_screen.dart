import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/features/ai_coach/services/induction_service.dart';
import 'package:icanbefitter/features/ai_coach/widgets/typing_indicator.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// 3-question muster — captures injuries + schedule + body-part focus.
/// Sequential reveal with typing pause.
///
/// Route: /coach/muster (entered from InductionScreen after I COMMIT)
///
/// After Q5 commits, fires [InductionService.completeMuster] and navigates
/// to /home. Each answer is persisted immediately via
/// [InductionService.recordMusterAnswer].
///
/// Sequence: typing indicator (1100ms) → reveal question → user answers →
/// CONTINUE → typing indicator → next question. Repeat × 3.
///
/// Note: question identifiers in coachBox keep the original Q3/Q4/Q5
/// naming (`known_injuries`, `typical_wake_time`, `preferred_workout_time`,
/// `body_part_priorities`). Q1 (`why_now`) and Q2 (`definition_of_winning`)
/// were dropped per founder direction (APK Test #15.4 / B2a) — they were
/// high-friction essay prompts with low AI-context value. Their keys are
/// retained in `InductionService._allowedMusterKeys` so legacy data still
/// round-trips on read.
class MusterScreen extends ConsumerStatefulWidget {
  const MusterScreen({super.key});

  @override
  ConsumerState<MusterScreen> createState() => _MusterScreenState();
}

class _MusterScreenState extends ConsumerState<MusterScreen> {
  /// Current question index 0..2. After Q5 commits, [_completed] flips true.
  ///
  /// Indices map to the original Q3 → Q5 sequence (Q1/Q2 were dropped):
  ///   0 → injuries (was Q3)
  ///   1 → wake time + workout time (was Q4)
  ///   2 → body-part focus (was Q5, now single-select)
  int _qIdx = 0;
  bool _typing = true;
  bool _completed = false;

  // Q3 — injuries
  final _injuriesCtrl = TextEditingController();
  // Q4 — wake/workout time
  TimeOfDay? _wakeTime;
  TimeOfDay? _workoutTime;
  // Q5 — single-select matching profile.physique_focus enum
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
    _showTypingThen(0);
  }

  Future<void> _showTypingThen(int qIdx) async {
    if (!mounted) return;
    setState(() {
      _typing = true;
      _qIdx = qIdx;
    });
    await Future.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;
    setState(() => _typing = false);
  }

  @override
  void dispose() {
    _injuriesCtrl.dispose();
    super.dispose();
  }

  // ── Submit handlers ────────────────────────────────────────────────────────

  Future<void> _onSubmitQ3({bool skipped = false}) async {
    final List<String> injuries;
    if (skipped) {
      injuries = ['none'];
    } else {
      final raw = _injuriesCtrl.text.trim();
      if (raw.isEmpty) {
        injuries = ['none'];
      } else {
        injuries = raw
            .split(',')
            .map((s) => s.trim().toLowerCase())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    }
    await InductionService.instance.recordMusterAnswer('known_injuries', injuries);
    await _showTypingThen(1); // was 3 — renumbered after dropping Q1/Q2.
  }

  Future<void> _onSubmitQ4() async {
    if (_wakeTime == null || _workoutTime == null) {
      _toast('Both times required, Recruit.');
      return;
    }
    await InductionService.instance
        .recordMusterAnswer('typical_wake_time', _formatTime(_wakeTime!));
    await InductionService.instance
        .recordMusterAnswer('preferred_workout_time', _formatTime(_workoutTime!));
    await _showTypingThen(2); // was 4 — renumbered after dropping Q1/Q2.
  }

  Future<void> _onSubmitQ5() async {
    if (_physiqueFocus == null) {
      _toast('Pick one focus, Recruit.');
      return;
    }
    // Wrap single value in 1-element List so the existing coachBox key
    // shape (List<String>) is preserved. ai_coach_repository reads this as
    // `(coach.get('body_part_priorities') as List?) ?? const <String>[]`
    // — no consumer change needed. (APK Test #15.4 / B2d.)
    await InductionService.instance.recordMusterAnswer(
      'body_part_priorities',
      [_physiqueFocus!],
    );
    await _completeMuster();
  }

  Future<void> _completeMuster() async {
    setState(() => _completed = true);
    await InductionService.instance.completeMuster();
    // Final message lingers briefly before navigating
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    context.go('/home');
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _pickTime(bool isWake) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isWake
          ? const TimeOfDay(hour: 6, minute: 30)
          : const TimeOfDay(hour: 7, minute: 0),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isWake) {
        _wakeTime = picked;
      } else {
        _workoutTime = picked;
      }
    });
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
              if (!_completed) _buildProgress(),
              const SizedBox(height: 16),
              if (_typing && !_completed)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: TypingIndicator(),
                ),
              if (!_typing && !_completed) _buildCurrentQ(),
              if (_completed) _buildFinalMessage(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return Row(
      children: List.generate(3, (i) {
        final filled = i <= _qIdx;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            height: 3,
            decoration: BoxDecoration(
              color: filled ? AppColors.accent : AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCurrentQ() {
    switch (_qIdx) {
      case 0:
        return _buildQ3(); // injuries (now first)
      case 1:
        return _buildQ4(); // wake/workout time
      case 2:
        return _buildQ5(); // body part focus (single-select, physique_focus)
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Captain bubble (matches InductionScreen pattern) ───────────────────────

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
          color: Color(0xFFD8D8D8),
        ),
      ),
    );
  }

  // ── Q3: Injuries ───────────────────────────────────────────────────────────

  Widget _buildQ3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBubble(
            'Any old injuries or niggles I should plan around? Be specific — knee, '
            'lower back, shoulder, anything that flares. Comma-separate.'),
        TextField(
          controller: _injuriesCtrl,
          maxLines: 2,
          autofocus: true,
          decoration: _inputDecoration(hint: 'lower back, right knee'),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => _onSubmitQ3(skipped: true),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textDim,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text(
                  'NONE / SKIP',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: WardButton(
                label: 'CONTINUE',
                onPressed: () => _onSubmitQ3(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Q4: Wake time + workout time ───────────────────────────────────────────

  Widget _buildQ4() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBubble(
            'What time do you usually wake up, and when can you train?'),
        Row(
          children: [
            Expanded(
              child: _buildTimeTile(
                label: 'WAKE TIME',
                value: _wakeTime,
                onTap: () => _pickTime(true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTimeTile(
                label: 'WORKOUT TIME',
                value: _workoutTime,
                onTap: () => _pickTime(false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        WardButton(label: 'CONTINUE', onPressed: _onSubmitQ4),
      ],
    );
  }

  Widget _buildTimeTile({
    required String label,
    required TimeOfDay? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(
            color: value != null ? AppColors.accent : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.accent,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value != null ? _formatTime(value) : '—',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: value != null ? Colors.white : AppColors.textMute,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Q5: Physique focus (single-select, mirrors profile.physique_focus) ────

  Widget _buildQ5() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBubble(
            'Where do you want to put extra emphasis? Pick one — your plan '
            'will weight that area.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _physiqueFocusOptions.map((opt) {
            final selected = _physiqueFocus == opt.$1;
            return GestureDetector(
              onTap: () => _setPhysiqueFocus(opt.$1),
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
          label: 'COMPLETE MUSTER',
          onPressed: _physiqueFocus == null ? null : _onSubmitQ5,
        ),
      ],
    );
  }

  void _setPhysiqueFocus(String key) {
    setState(() => _physiqueFocus = key);
  }

  // ── Final message ──────────────────────────────────────────────────────────

  Widget _buildFinalMessage() {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.4),
          ),
        ),
        child: const Text(
          'Muster complete, Recruit. File updated. Tomorrow at 06:30 IST you '
          'receive your first daily brief. Carry on.',
          style: TextStyle(
            fontSize: 16,
            height: 1.6,
            color: Color(0xFFE8E8E8),
          ),
        ),
      ),
    );
  }

  // ── Input decoration ───────────────────────────────────────────────────────

  InputDecoration _inputDecoration({required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textMute),
      filled: true,
      fillColor: AppColors.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.accent, width: 1.5),
      ),
    );
  }
}
