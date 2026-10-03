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
      // OBS-10 — Flutter throws "A borderRadius can only be given on borders
      // with uniform colors" whenever a NON-uniform Border (the top-drop rail
      // trick) is combined with a non-null borderRadius. Only the first/last
      // cards round corners, so give THEM a uniform Border.all (+ the rounded
      // radius); the square middle cards get a NULL radius so their non-uniform
      // top-drop border (1-px shared rail, no double seam) stays legal.
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: (isFirst || isLast)
            ? BorderRadius.only(
                topLeft: Radius.circular(isFirst ? AppRadius.card : 0),
                topRight: Radius.circular(isFirst ? AppRadius.card : 0),
                bottomLeft: Radius.circular(isLast ? AppRadius.card : 0),
                bottomRight: Radius.circular(isLast ? AppRadius.card : 0),
              )
            : null,
        border: (isFirst || isLast)
            ? Border.all(color: AppColors.line2)
            : const Border(
                top: BorderSide(color: AppColors.line2, width: 0),
                left: BorderSide(color: AppColors.line2),
                right: BorderSide(color: AppColors.line2),
                bottom: BorderSide(color: AppColors.line2),
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
