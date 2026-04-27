import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/features/ai_coach/services/induction_service.dart';
import 'package:icanbefitter/features/ai_coach/widgets/typing_indicator.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// 5-question muster — captures motivational anchor + definitions + injuries
/// + schedule + body-part priorities. Sequential reveal with typing pause.
///
/// Route: /coach/muster (entered from InductionScreen after I COMMIT)
///
/// After Q5 commits, fires [InductionService.completeMuster] and navigates
/// to /home. Each answer is persisted immediately via
/// [InductionService.recordMusterAnswer].
///
/// Sequence: typing indicator (1100ms) → reveal question → user answers →
/// CONTINUE → typing indicator → next question. Repeat × 5.
class MusterScreen extends ConsumerStatefulWidget {
  const MusterScreen({super.key});

  @override
  ConsumerState<MusterScreen> createState() => _MusterScreenState();
}

class _MusterScreenState extends ConsumerState<MusterScreen> {
  /// Current question index 0..4. After Q5 commits, [_completed] flips true.
  int _qIdx = 0;
  bool _typing = true;
  bool _completed = false;

  // Q1
  final _whyNowCtrl = TextEditingController();
  // Q2
  final _winningCtrl = TextEditingController();
  // Q3
  final _injuriesCtrl = TextEditingController();
  // Q4
  TimeOfDay? _wakeTime;
  TimeOfDay? _workoutTime;
  // Q5
  final Set<String> _bodyParts = {};

  static const _bodyPartOptions = [
    'Back',
    'Chest',
    'Shoulders',
    'Arms',
    'Legs',
    'Glutes',
    'Core',
    'None',
  ];

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
    _whyNowCtrl.dispose();
    _winningCtrl.dispose();
    _injuriesCtrl.dispose();
    super.dispose();
  }

  // ── Submit handlers ────────────────────────────────────────────────────────

  Future<void> _onSubmitQ1() async {
    final v = _whyNowCtrl.text.trim();
    if (v.length < 10) {
      _toast('At least a sentence, Recruit.');
      return;
    }
    await InductionService.instance.recordMusterAnswer('why_now', v);
    await _showTypingThen(1);
  }

  Future<void> _onSubmitQ2() async {
    final v = _winningCtrl.text.trim();
    if (v.length < 10) {
      _toast('At least a sentence, Recruit.');
      return;
    }
    await InductionService.instance.recordMusterAnswer('definition_of_winning', v);
    await _showTypingThen(2);
  }

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
    await _showTypingThen(3);
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
    await _showTypingThen(4);
  }

  Future<void> _onSubmitQ5() async {
    final list = _bodyParts.contains('None')
        ? <String>[]
        : _bodyParts.map((s) => s.toLowerCase()).toList();
    await InductionService.instance.recordMusterAnswer('body_part_priorities', list);
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
      children: List.generate(5, (i) {
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
        return _buildQ1();
      case 1:
        return _buildQ2();
      case 2:
        return _buildQ3();
      case 3:
        return _buildQ4();
      case 4:
        return _buildQ5();
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

  // ── Q1: Why now ────────────────────────────────────────────────────────────

  Widget _buildQ1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBubble(
            'Why now? What triggered this enlistment?'),
        TextField(
          controller: _whyNowCtrl,
          maxLines: 3,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: _inputDecoration(hint: 'October wedding, want to feel strong...'),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 16),
        WardButton(label: 'CONTINUE', onPressed: _onSubmitQ1),
      ],
    );
  }

  // ── Q2: Definition of winning ──────────────────────────────────────────────

  Widget _buildQ2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBubble(
            'What does winning look like to you? Describe it in your own words.'),
        TextField(
          controller: _winningCtrl,
          maxLines: 3,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration:
              _inputDecoration(hint: 'Strong. Energetic. Not tired all day...'),
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 16),
        WardButton(label: 'CONTINUE', onPressed: _onSubmitQ2),
      ],
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

  // ── Q5: Body part priorities ───────────────────────────────────────────────

  Widget _buildQ5() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBubble(
            'Beyond your goal, any body part you specifically want to bring up?'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _bodyPartOptions.map((opt) {
            final selected = _bodyParts.contains(opt);
            return GestureDetector(
              onTap: () => _toggleBodyPart(opt),
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
                  opt,
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
          onPressed: _bodyParts.isEmpty ? null : _onSubmitQ5,
        ),
      ],
    );
  }

  void _toggleBodyPart(String opt) {
    setState(() {
      if (opt == 'None') {
        _bodyParts
          ..clear()
          ..add('None');
      } else {
        _bodyParts.remove('None');
        if (_bodyParts.contains(opt)) {
          _bodyParts.remove(opt);
        } else {
          _bodyParts.add(opt);
        }
      }
    });
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
