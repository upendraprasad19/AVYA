import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/features/ai_coach/services/induction_service.dart';
import 'package:icanbefitter/features/ai_coach/widgets/typing_indicator.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';

/// Captain's induction sequence: 3 paced messages + I COMMIT contract.
///
/// Routed from REPORT FOR DUTY on Plan screen (router task B6) when the user
/// has not yet committed ([InductionService.hasCommitted] == false).
///
/// Reveal sequence:
///   t=0       → typing indicator
///   t+1400ms  → Msg 1 (intro) revealed; pause 2400ms
///   t+3800ms  → typing indicator
///   t+5200ms  → Msg 2 (Lt Cdr promise, gold emphasis) revealed; pause 3000ms
///   t+8200ms  → typing indicator
///   t+9600ms  → Msg 3 (muster bridge) + I COMMIT button revealed
///
/// Tap I COMMIT:
///   → [InductionService.recordCommitment()] (Hive + fire-and-forget sync)
///   → "Contract sealed." shown for 700ms
///   → context.go('/coach/muster')
class InductionScreen extends ConsumerStatefulWidget {
  const InductionScreen({super.key});

  @override
  ConsumerState<InductionScreen> createState() => _InductionScreenState();
}

class _InductionScreenState extends ConsumerState<InductionScreen> {
  /// Stage encoding:
  ///   0  = initial (blank)
  ///   1  = typing before msg1
  ///   2  = msg1 visible
  ///   3  = typing before msg2
  ///   4  = msg2 visible
  ///   5  = typing before msg3
  ///   6  = msg3 + button visible
  ///   7  = committed ("Contract sealed.")
  int _stage = 0;

  static const _typingDuration = Duration(milliseconds: 1400);
  static const _readPause1 = Duration(milliseconds: 2400);
  static const _readPause2 = Duration(milliseconds: 3000);
  static const _commitBeat = Duration(milliseconds: 700);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showMsg1());
  }

  Future<void> _showMsg1() async {
    if (!mounted) return;
    setState(() => _stage = 1); // typing
    await Future.delayed(_typingDuration);
    if (!mounted) return;
    setState(() => _stage = 2); // msg1
    await Future.delayed(_readPause1);
    if (!mounted) return;
    unawaited(_showMsg2());
  }

  Future<void> _showMsg2() async {
    if (!mounted) return;
    setState(() => _stage = 3); // typing
    await Future.delayed(_typingDuration);
    if (!mounted) return;
    setState(() => _stage = 4); // msg2
    await Future.delayed(_readPause2);
    if (!mounted) return;
    unawaited(_showMsg3());
  }

  Future<void> _showMsg3() async {
    if (!mounted) return;
    setState(() => _stage = 5); // typing
    await Future.delayed(_typingDuration);
    if (!mounted) return;
    setState(() => _stage = 6); // msg3 + button
  }

  Future<void> _onCommit() async {
    if (_stage == 7) return; // guard double-tap
    setState(() => _stage = 7);
    await InductionService.instance.recordCommitment();
    if (!mounted) return;
    await Future.delayed(_commitBeat);
    if (!mounted) return;
    context.go('/coach/muster');
  }

  String get _firstName {
    final profile = HiveService.instance.userBox.get('profile') as Map?;
    final name = (profile?['full_name'] as String?)?.trim();
    if (name == null || name.isEmpty) return 'Recruit';
    return name.split(' ').first;
  }

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
              const SizedBox(height: 24),

              // ── Message 1: intro ──────────────────────────────────────
              if (_stage == 1 || _stage == 3 || _stage == 5)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: TypingIndicator(),
                ),

              if (_stage >= 2) _buildMsg1(),

              // ── Typing before msg2 ────────────────────────────────────
              if (_stage == 3)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: TypingIndicator(),
                ),

              // ── Message 2: Lt Cdr promise ─────────────────────────────
              if (_stage >= 4) _buildMsg2(),

              // ── Typing before msg3 ────────────────────────────────────
              if (_stage == 5)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: TypingIndicator(),
                ),

              // ── Message 3: muster bridge ──────────────────────────────
              if (_stage >= 6) _buildMsg3(),

              // ── I COMMIT button ───────────────────────────────────────
              if (_stage == 6)
                Padding(
                  padding: const EdgeInsets.only(top: 28),
                  child: WardButton(
                    label: 'I COMMIT.',
                    onPressed: _onCommit,
                  ),
                ),

              // ── Contract sealed confirmation ──────────────────────────
              if (_stage == 7)
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: Center(
                    child: Text(
                      'Contract sealed.',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Message builders ────────────────────────────────────────────────────

  Widget _buildMsg1() {
    return _CoachBubble(
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            fontSize: 15,
            height: 1.6,
            color: Color(0xFFD8D8D8),
          ),
          children: [
            TextSpan(
              text: 'Recruit $_firstName — welcome aboard.\n\n',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const TextSpan(
              text:
                  "I'm your AI Coach. I've trained sailors at sea and recruits in the "
                  'gym for longer than I care to count. I\'ll be working you through this '
                  'deployment — your first 12 weeks and beyond. You\'ll know me by my voice. '
                  "I'll know you by your data.\n\n",
            ),
            const TextSpan(
              text: "Here's the deal, plain.\n\n",
              style: TextStyle(color: AppColors.textPrimary),
            ),
            const TextSpan(
              text:
                  "Show up. Log honestly. Don't lie to me about reps or meals — I see the "
                  'numbers, I just want them straight. Follow the plan I write for you. '
                  "Tell me when something hurts. Tell me when life happens.",
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMsg2() {
    return _CoachBubble(
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            fontSize: 15,
            height: 1.6,
            color: Color(0xFFD8D8D8),
          ),
          children: [
            const TextSpan(
              text: "In return, here's what I commit:\n\n",
              style: TextStyle(color: AppColors.textPrimary),
            ),
            TextSpan(
              text:
                  'Make Sub Lieutenant rank — 104 workouts on this app — and your life '
                  "will change. Physically, and in every possible way I can measure. "
                  "That's not a slogan. That's a guarantee.\n\n",
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
                fontSize: 16,
                height: 1.5,
              ),
            ),
            const TextSpan(
              text:
                  '104 workouts is roughly six months of disciplined training. Most don\'t '
                  'make it past month two. The ones who do — they don\'t recognize themselves '
                  'in the mirror, in their work, in their relationships. Compounding return. '
                  "I've seen it happen. I'll show you the way.\n\n",
            ),
            const TextSpan(
              text: 'Tap below to seal it.',
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMsg3() {
    return const _CoachBubble(
      child: Text(
        "Before we deploy, your file is missing a few entries. "
        "Quick muster — five questions, three minutes. Then we're operational.",
        style: TextStyle(
          fontSize: 15,
          height: 1.6,
          color: Color(0xFFD8D8D8),
        ),
      ),
    );
  }
}

// ── Private sub-widgets ────────────────────────────────────────────────────

/// Standard chat bubble surface matching the coach's voice channel.
class _CoachBubble extends StatelessWidget {
  const _CoachBubble({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}
