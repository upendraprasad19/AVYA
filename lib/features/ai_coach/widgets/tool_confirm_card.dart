import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/hive_service.dart';
import '../../../core/theme/colors.dart';
import '../models/tool_intent.dart';
import '../providers/pending_tool_intents_provider.dart';

/// Inline confirmation card for an AI coach tool intent.
///
/// Handles BOTH `trivial` (5s countdown auto-confirm) and `reviewable`
/// (explicit confirm only) confirmation classes via the intent's
/// [ConfirmationClass]. Destructive intents use [ToolConfirmSheet] instead.
///
/// Borrows visual style from [LogConfirmCard] but operates on
/// [pendingToolIntentsProvider] + [ToolDispatcher] rather than the legacy
/// `<ICBF_LOG>` action pipeline.
class ToolConfirmCard extends ConsumerStatefulWidget {
  final ToolIntent intent;

  const ToolConfirmCard({super.key, required this.intent});

  @override
  ConsumerState<ToolConfirmCard> createState() => _ToolConfirmCardState();
}

class _ToolConfirmCardState extends ConsumerState<ToolConfirmCard> {
  Timer? _autoConfirmTimer;
  int _secondsRemaining = 5;
  bool _executing = false;

  @override
  void initState() {
    super.initState();
    if (widget.intent.confirmationClass == ConfirmationClass.trivial &&
        widget.intent.status == ToolIntentStatus.pending) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    _autoConfirmTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsRemaining--);
      if (_secondsRemaining <= 0) {
        t.cancel();
        _confirm();
      }
    });
  }

  Future<void> _confirm() async {
    _autoConfirmTimer?.cancel();
    if (!mounted || _executing) return;
    setState(() => _executing = true);
    final result = await ref
        .read(pendingToolIntentsProvider.notifier)
        .confirm(widget.intent.id);
    if (!mounted) return;
    setState(() => _executing = false);
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? 'Failed')),
      );
    }
  }

  void _skip() {
    _autoConfirmTimer?.cancel();
    ref.read(pendingToolIntentsProvider.notifier).reject(widget.intent.id);
  }

  Future<void> _retry() async {
    if (_executing) return;
    setState(() => _executing = true);
    final result = await ref
        .read(pendingToolIntentsProvider.notifier)
        .retry(widget.intent.id);
    if (!mounted) return;
    setState(() => _executing = false);
    if (!result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.errorMessage ?? 'Failed')),
      );
    }
  }

  @override
  void dispose() {
    _autoConfirmTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final intent = widget.intent;

    if (intent.status == ToolIntentStatus.executed) {
      return _buildExecutedState();
    }
    if (intent.status == ToolIntentStatus.rejected) {
      return _buildRejectedState();
    }
    if (intent.status == ToolIntentStatus.expired) {
      return _buildRejectedState(label: 'Expired');
    }
    if (intent.status == ToolIntentStatus.failed) {
      return _buildFailedState();
    }

    // pending | confirming | executing
    final isCountdown = intent.confirmationClass == ConfirmationClass.trivial;
    final summary = _buildSummary(intent);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.accent.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconForType(intent.type), color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                _titleForType(intent.type),
                style: GoogleFonts.getFont(
                  'DM Sans',
                  color: AppColors.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (isCountdown && !_executing)
                Text(
                  '${_secondsRemaining}s',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            summary,
            style: GoogleFonts.getFont(
              'DM Sans',
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _executing ? null : _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: _executing
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(
                          'Confirm',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _executing ? null : _skip,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    'Skip',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExecutedState() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.green, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _executedMessage(widget.intent),
              style: GoogleFonts.getFont(
                'DM Sans',
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRejectedState({String label = 'Skipped'}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: ${_titleForType(widget.intent.type)}',
        style: GoogleFonts.getFont(
          'DM Sans',
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildFailedState() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.red.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, color: AppColors.red, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.intent.errorMessage ?? 'Failed',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _executing ? null : _retry,
              child: _executing
                  ? const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accent,
                      ),
                    )
                  : Text(
                      'Retry',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String _buildSummary(ToolIntent intent) {
    if (intent.type == 'swap_exercise') {
      final fromId = intent.payload['exerciseId']?.toString() ?? '';
      final toId = intent.payload['newExerciseId']?.toString() ?? '';
      final fromName = _resolveExerciseName(fromId) ?? fromId;
      final toName = _resolveExerciseName(toId) ?? toId;
      final reason = intent.payload['reason']?.toString();
      final base = '$fromName \u2192 $toName';
      return reason != null && reason.isNotEmpty ? '$base\n$reason' : base;
    }
    if (intent.type == 'log_set') {
      final exerciseId = intent.payload['exerciseId']?.toString() ?? '';
      final name = _resolveExerciseName(exerciseId) ?? exerciseId;
      final w = intent.payload['weightKg'];
      final reps = intent.payload['reps'];
      final sets = intent.payload['sets'];
      return '$name \u2014 ${w}kg \u00d7 $reps \u00d7 $sets sets';
    }
    if (intent.type == 'mark_workout_complete') {
      final date = intent.payload['date'] as String?;
      return date != null
          ? 'Mark $date workout complete'
          : "Mark today's workout complete";
    }
    if (intent.type == 'shorten_workout') {
      final minutes = intent.payload['minutes'];
      final date = intent.payload['date'] as String?;
      return date != null
          ? 'Shorten $date workout to $minutes min'
          : "Shorten today's workout to $minutes min";
    }
    if (intent.type == 'create_custom_exercise') {
      final name = intent.payload['name']?.toString() ?? '';
      final category = intent.payload['category']?.toString() ?? '';
      final equipment = intent.payload['equipment']?.toString() ?? '';
      return '$name\n$category \u00b7 $equipment';
    }
    return intent.previewSummary;
  }

  String? _resolveExerciseName(String id) {
    if (id.isEmpty) return null;
    final ex = HiveService.instance.exerciseBox.get(id);
    if (ex is Map && ex['name'] is String) return ex['name'] as String;
    final cust = HiveService.instance.customBox.get(id);
    if (cust is Map && cust['name'] is String) return cust['name'] as String;
    // Custom items may be keyed differently (e.g. custom_exercise_<ts>) with
    // an inner 'id' field — scan for a match.
    for (final k in HiveService.instance.customBox.keys) {
      final v = HiveService.instance.customBox.get(k);
      if (v is Map && v['id'] == id && v['name'] is String) {
        return v['name'] as String;
      }
    }
    return null;
  }

  String _titleForType(String type) {
    switch (type) {
      case 'swap_exercise':
        return 'SWAP EXERCISE';
      case 'log_set':
        return 'LOG SET';
      case 'mark_workout_complete':
        return 'MARK COMPLETE';
      case 'shorten_workout':
        return 'SHORTEN WORKOUT';
      case 'create_custom_exercise':
        return 'NEW EXERCISE';
      default:
        return type.toUpperCase().replaceAll('_', ' ');
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'swap_exercise':
        return Icons.swap_horiz;
      case 'log_set':
        return Icons.fitness_center;
      case 'mark_workout_complete':
        return Icons.check_circle_outline;
      case 'shorten_workout':
        return Icons.timer;
      case 'create_custom_exercise':
        return Icons.add_circle_outline;
      default:
        return Icons.bolt;
    }
  }

  String _executedMessage(ToolIntent intent) {
    switch (intent.type) {
      case 'swap_exercise':
        return 'Swapped';
      case 'log_set':
        return 'Logged';
      case 'mark_workout_complete':
        return 'Marked complete';
      case 'shorten_workout':
        return 'Workout shortened';
      case 'create_custom_exercise':
        return 'Created';
      default:
        return 'Done';
    }
  }
}
