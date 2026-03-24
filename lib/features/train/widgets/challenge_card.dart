import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/utils/card_share_service.dart';
import 'package:icanbefitter/shared/widgets/shareable_card.dart';

// ── Challenge Data ─────────────────────────────────────────────

enum ChallengeDifficulty { brutal, savage, insane }

class ChallengeData {
  final String name;
  final List<ChallengeExercise> exercises;
  final String coachTime; // e.g. "18:42"
  final ChallengeDifficulty difficulty;

  const ChallengeData({
    required this.name,
    required this.exercises,
    required this.coachTime,
    this.difficulty = ChallengeDifficulty.brutal,
  });
}

class ChallengeExercise {
  final String name;
  final int reps;

  const ChallengeExercise({required this.name, required this.reps});
}

class ChallengeResultData {
  final ChallengeData challenge;
  final String userTime; // e.g. "17:55"
  final bool didBeatCoach;

  const ChallengeResultData({
    required this.challenge,
    required this.userTime,
    required this.didBeatCoach,
  });
}

// ── Challenge Card (Pre-attempt) ───────────────────────────────

/// Beat My Coach Challenge card — shareable before and after attempt.
///
/// Tier: FREE for all users (1 per 2 weeks).
class ChallengeCard extends StatefulWidget {
  final ChallengeData challenge;
  final VoidCallback? onStartChallenge;

  const ChallengeCard({
    super.key,
    required this.challenge,
    this.onStartChallenge,
  });

  @override
  State<ChallengeCard> createState() => _ChallengeCardState();
}

class _ChallengeCardState extends State<ChallengeCard> {
  final _cardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The shareable card
        ShareableCard(
          repaintKey: _cardKey,
          child: _buildContent(),
        ),
        const SizedBox(height: 12),

        // Action buttons
        Row(
          children: [
            // Challenge a Friend
            Expanded(
              child: GestureDetector(
                onTap: () => CardShareService.captureAndShare(
                  _cardKey,
                  filename: 'icanbefitter_challenge.png',
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.accentTint,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'Challenge a Friend',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.onStartChallenge != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: widget.onStartChallenge,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Center(
                      child: Text(
                        'Accept Challenge',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildContent() {
    final diffLabel = _difficultyLabel(widget.challenge.difficulty);
    final diffColor = _difficultyColor(widget.challenge.difficulty);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Difficulty badge + header
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: diffColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: diffColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  diffLabel,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: diffColor,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.local_fire_department,
                  color: AppColors.orange, size: 16),
            ],
          ),
          const SizedBox(height: 12),

          // Challenge name
          Text(
            widget.challenge.name,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 14),

          // Exercise list
          ...widget.challenge.exercises.map((ex) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        ex.name,
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${ex.reps} reps',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 14),

          // Divider
          Container(height: 1, color: AppColors.border),
          const SizedBox(height: 14),

          // Coach's time
          Center(
            child: Column(
              children: [
                Text(
                  'COACH\'S TIME',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.challenge.coachTime,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'CAN YOU BEAT IT?',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _difficultyLabel(ChallengeDifficulty d) {
    switch (d) {
      case ChallengeDifficulty.brutal:
        return 'BRUTAL';
      case ChallengeDifficulty.savage:
        return 'SAVAGE';
      case ChallengeDifficulty.insane:
        return 'INSANE';
    }
  }

  Color _difficultyColor(ChallengeDifficulty d) {
    switch (d) {
      case ChallengeDifficulty.brutal:
        return AppColors.orange;
      case ChallengeDifficulty.savage:
        return AppColors.red;
      case ChallengeDifficulty.insane:
        return AppColors.purple;
    }
  }
}

// ── Challenge Result Card (Post-attempt) ────────────────────────

/// Shows the user's time vs. the coach's time after completing a challenge.
class ChallengeResultCard extends StatefulWidget {
  final ChallengeResultData result;

  const ChallengeResultCard({
    super.key,
    required this.result,
  });

  @override
  State<ChallengeResultCard> createState() => _ChallengeResultCardState();
}

class _ChallengeResultCardState extends State<ChallengeResultCard> {
  final _cardKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShareableCard(
          repaintKey: _cardKey,
          child: _buildResultContent(),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => CardShareService.captureAndShare(
            _cardKey,
            filename: 'icanbefitter_challenge_result.png',
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Center(
              child: Text(
                widget.result.didBeatCoach
                    ? 'Share Your Victory'
                    : 'Share Result',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultContent() {
    final r = widget.result;
    final resultColor = r.didBeatCoach ? AppColors.green : AppColors.red;
    final resultText = r.didBeatCoach ? 'COACH DEFEATED' : 'COACH WINS';
    final resultIcon =
        r.didBeatCoach ? Icons.emoji_events : Icons.sentiment_very_dissatisfied;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Result badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: resultColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: resultColor.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(resultIcon, color: resultColor, size: 16),
                const SizedBox(width: 6),
                Text(
                  resultText,
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: resultColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Challenge name
          Text(
            r.challenge.name,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),

          // Times comparison
          Row(
            children: [
              Expanded(
                child: _timeColumn('YOUR TIME', r.userTime,
                    r.didBeatCoach ? AppColors.green : AppColors.textPrimary),
              ),
              Text(
                'VS',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textSecondary,
                ),
              ),
              Expanded(
                child: _timeColumn(
                    'COACH\'S TIME',
                    r.challenge.coachTime,
                    r.didBeatCoach
                        ? AppColors.textSecondary
                        : AppColors.accent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timeColumn(String label, String time, Color timeColor) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          time,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: timeColor,
          ),
        ),
      ],
    );
  }
}
