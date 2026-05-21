part of 'screen.dart';

extension _FlushCard on _ProfileScreenState {

  // ── Theme C · Test #8 — Flush card stack ─────────────────────────────
  //
  // Five Profile cards (Daily Goals → SlimAchievements → Journey →
  // Body Stats → My Targets) render as a single visual block: outer
  // 6-dp corners, square inner corners, no inter-card gaps, shared
  // 1-px border rail. Each card builder below was unwrapped from its
  // WardCard so `_buildFlushCard` can supply the conditional border.
  //
  // ProfileCompletenessCard (rendered above the stack) is OUTSIDE this
  // group — it keeps its own WardCard styling and the 8-px gap that
  // follows it.
  Widget _buildFlushCard(
    Widget child, {
    required _FlushPos pos,
    EdgeInsets padding = const EdgeInsets.all(14),
    VoidCallback? onTap,
  }) {
    final isFirst = pos == _FlushPos.first || pos == _FlushPos.only;
    final isLast = pos == _FlushPos.last || pos == _FlushPos.only;
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isFirst ? AppRadius.card : 0),
          topRight: Radius.circular(isFirst ? AppRadius.card : 0),
          bottomLeft: Radius.circular(isLast ? AppRadius.card : 0),
          bottomRight: Radius.circular(isLast ? AppRadius.card : 0),
        ),
        // Top border drops on every card except the first so adjacent
        // cards share a single 1-px rail (no double-line seam).
        border: Border(
          top: BorderSide(
            color: AppColors.line2,
            width: isFirst ? 1 : 0,
          ),
          left: const BorderSide(color: AppColors.line2),
          right: const BorderSide(color: AppColors.line2),
          bottom: const BorderSide(color: AppColors.line2),
        ),
      ),
      child: child,
    );

    final wrapped = onTap == null
        ? body
        : Material(
            color: Colors.transparent,
            child: InkWell(onTap: onTap, child: body),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: wrapped,
    );
  }
}
