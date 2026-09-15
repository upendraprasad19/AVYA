part of 'screen.dart';

/// Horizontal chip for a custom exercise on the Train screen, showing
/// name + approval status. Status rules:
///   * `approved_for_library=true`          -> APPROVED (ok)
///   * `submitted_to_library=true` only     -> PENDING  (warn)
///   * neither                               -> DRAFT    (textMute)
class _CustomExerciseChip extends StatelessWidget {
  const _CustomExerciseChip({required this.exercise});

  final Map<String, dynamic> exercise;

  @override
  Widget build(BuildContext context) {
    final name = exercise['name'] as String? ?? 'Unnamed';
    final submitted = exercise['submitted_to_library'] == true;
    final approved = exercise['approved_for_library'] == true;

    final (String statusLabel, Color statusColor) = approved
        ? ('APPROVED', AppColors.ok)
        : submitted
            ? ('PENDING', AppColors.warn)
            : ('DRAFT', AppColors.textMute);

    return Container(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line2),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.h3.copyWith(
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (approved) ...[
                Icon(Icons.check_circle_outline, size: 11, color: statusColor),
                const SizedBox(width: 4),
              ],
              Text(
                statusLabel,
                style: AppTypography.monoXs.copyWith(
                  color: statusColor,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _RowStatus { done, today, planned, missed, rest }

/// Bug #15a: Collapsible WARM-UP / COOL-DOWN section in the train preview.
/// Default state is collapsed — header (label + chevron) is tappable to toggle.
/// Body uses [AnimatedSize] for a smooth reveal.
class _CollapsibleExerciseSection extends StatefulWidget {
  const _CollapsibleExerciseSection({
    required this.label,
    required this.color,
    required this.exercises,
    required this.buildRow,
  });

  final String label;
  final Color color;
  final List<ExerciseData> exercises;
  final Widget Function(ExerciseData) buildRow;

  @override
  State<_CollapsibleExerciseSection> createState() =>
      _CollapsibleExerciseSectionState();
}

class _CollapsibleExerciseSectionState
    extends State<_CollapsibleExerciseSection> {
  // Default to collapsed — that's the entire point of Bug #15a.
  bool _expanded = false;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header — label + count + chevron, tappable
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Text(
                  widget.label,
                  style: AppTypography.mono.copyWith(
                    color: widget.color.withValues(alpha: 0.7),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${widget.exercises.length}',
                  style: AppTypography.monoXs.copyWith(
                    color: widget.color.withValues(alpha: 0.4),
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 200),
                  turns: _expanded ? 0.5 : 0.0,
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: widget.color.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Body — animated reveal
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.exercises.map(widget.buildRow).toList(),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
