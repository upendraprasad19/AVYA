import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/services/error_telemetry.dart';
import '../../../../core/theme/colors.dart';
import '../../models/tool_intent.dart';
import '../../services/injury_swap_planner.dart';
import 'package:icanbefitter/core/theme/typography.dart';

/// Diff preview for a `modify_workout_for_injury` intent.
///
/// Computes the swap plan in [initState] (Hive read + library scan) and
/// caches it on [InjurySwapPlanner.instance] keyed by `intent.id` so the
/// dispatcher can pick it up on confirm without recomputing.
class InjuryModifyDiff extends StatefulWidget {
  final ToolIntent intent;
  const InjuryModifyDiff({super.key, required this.intent});

  @override
  State<InjuryModifyDiff> createState() => _InjuryModifyDiffState();
}

class _InjuryModifyDiffState extends State<InjuryModifyDiff> {
  List<InjurySwap>? _swaps;
  String? _error;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  Future<void> _compute() async {
    try {
      final swaps = await InjurySwapPlanner.instance.plan(
        bodyPart: widget.intent.payload['bodyPart'] as String,
        severity: widget.intent.payload['severity'] as String,
        daysAhead: (widget.intent.payload['daysAhead'] as num?)?.toInt() ?? 7,
      );
      InjurySwapPlanner.instance.cacheSwaps(widget.intent.id, swaps);
      if (mounted) setState(() => _swaps = swaps);
    } catch (e) {
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent(
          'diff_preview_injury_modify_load_failed',
          message: clipped));
      if (mounted) setState(() => _error = errStr);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Could not compute changes: $_error',
          style: AppTypography.bodyM.copyWith(color: AppColors.red),
        ),
      );
    }
    if (_swaps == null) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final daysAhead =
        (widget.intent.payload['daysAhead'] as num?)?.toInt() ?? 7;
    if (_swaps!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No exercises in the next $daysAhead days hit this body part — no changes needed. Confirm to record the injury anyway.',
          style: AppTypography.bodyM.copyWith(color: AppColors.textSecondary),
        ),
      );
    }

    // Group by date for readable display.
    final byDate = <String, List<InjurySwap>>{};
    for (final s in _swaps!) {
      byDate.putIfAbsent(s.date, () => []).add(s);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${_swaps!.length} change${_swaps!.length == 1 ? '' : 's'} across ${byDate.length} day${byDate.length == 1 ? '' : 's'}',
            style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
        ),
        ...byDate.entries.map((entry) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key,
                  style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w800, color: AppColors.accent),
                ),
                const SizedBox(height: 8),
                ...entry.value.map(
                  (s) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.swap_horiz,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${s.fromName}  \u2192  ${s.toName}',
                            style: AppTypography.bodyM.copyWith(color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
