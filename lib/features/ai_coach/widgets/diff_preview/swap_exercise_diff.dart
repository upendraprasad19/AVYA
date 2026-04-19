import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/services/hive_service.dart';
import '../../../../core/theme/colors.dart';
import '../../models/tool_intent.dart';

/// Minimal diff renderer for a `swap_exercise` tool intent.
///
/// Shows From / To rows (red / green outlined) plus an optional reason note.
/// Designed to slot into [ToolConfirmSheet]'s `diffPreview` parameter.
///
/// `swap_exercise` is currently `reviewable` (not destructive), so this is
/// primarily used by tests and as a pattern reference for Phase B's
/// `modifyWorkoutForInjury` and other destructive intents.
class SwapExerciseDiff extends StatelessWidget {
  final ToolIntent intent;

  const SwapExerciseDiff({super.key, required this.intent});

  @override
  Widget build(BuildContext context) {
    final fromId = intent.payload['exerciseId']?.toString() ?? '';
    final toId = intent.payload['newExerciseId']?.toString() ?? '';
    final fromName = _resolveExerciseName(fromId) ?? fromId;
    final toName = _resolveExerciseName(toId) ?? toId;
    final reason = intent.payload['reason']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row('From', fromName, isOld: true),
        const SizedBox(height: 8),
        _row('To', toName, isOld: false),
        if (reason != null && reason.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    reason,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _row(String label, String value, {required bool isOld}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isOld
            ? AppColors.red.withValues(alpha: 0.08)
            : AppColors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isOld
              ? AppColors.red.withValues(alpha: 0.3)
              : AppColors.green.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.getFont(
              'DM Sans',
              color: isOld ? AppColors.red : AppColors.green,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.getFont(
                'DM Sans',
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _resolveExerciseName(String id) {
    if (id.isEmpty) return null;
    final ex = HiveService.instance.exerciseBox.get(id);
    if (ex is Map && ex['name'] is String) return ex['name'] as String;
    final cust = HiveService.instance.customBox.get(id);
    if (cust is Map && cust['name'] is String) return cust['name'] as String;
    for (final k in HiveService.instance.customBox.keys) {
      final v = HiveService.instance.customBox.get(k);
      if (v is Map && v['id'] == id && v['name'] is String) {
        return v['name'] as String;
      }
    }
    return null;
  }
}
