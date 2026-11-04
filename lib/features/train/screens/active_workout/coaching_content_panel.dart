part of 'screen.dart';

// ══════════════════════════════════════════════════════════════════
// Per-exercise coaching content (form cues) — collapsible, collapsed
// by default. W3.6: surfaces the curated library fields that were
// seeded but never shown — coaching_cues, common_mistakes,
// breathing_cue, warmup_protocol. FREE (basic form education).
// ══════════════════════════════════════════════════════════════════

class CoachingContentPanel extends StatefulWidget {
  final String exerciseName;

  const CoachingContentPanel({super.key, required this.exerciseName});

  @override
  State<CoachingContentPanel> createState() => _CoachingContentPanelState();
}

class _CoachingContentPanelState extends State<CoachingContentPanel> {
  // Collapsed by default so the info-dense logging screen stays clean.
  bool _expanded = false;

  // Resolved ONCE in initState (re-resolved in didUpdateWidget only when the
  // exercise name changes) — the active-workout card list rebuilds ~1×/sec
  // from the workout timer, so a build()-time library scan is out.
  ExerciseCues _cues = const ExerciseCues();

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant CoachingContentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Belt-and-suspenders: the card is keyed by exercise name (a swap mints a
    // fresh State so initState already re-runs), but re-resolve here too so the
    // panel is correct even if a future refactor reuses the State across names.
    if (oldWidget.exerciseName != widget.exerciseName) _resolve();
  }

  void _resolve() {
    // Exact-name lookup (NOT substring search — "Push Up" must not resolve to
    // "Pike Push Up"). Null for swapped/custom exercises → panel renders nothing.
    //
    // ONE parser for this panel, the plate sheet and the logging viewer
    // (`exerciseCuesOf`): the numeric-breathing guard, the never-hard-cast
    // rule and the array handling live there, not here.
    _cues = exerciseCuesOf(
        ExerciseRepository.instance.getByExactName(widget.exerciseName));
  }

  @override
  Widget build(BuildContext context) {
    // No library match / all sections empty → render nothing (never a bare
    // heading).
    if (_cues.isEmpty) return const SizedBox.shrink();

    const accent = AppColors.accent;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
      child: Container(
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: accent.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header (tap to expand/collapse)
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.tips_and_updates_outlined,
                        size: 15, color: accent),
                    const SizedBox(width: 8),
                    Text(
                      'FORM & CUES',
                      style: AppTypography.mono.copyWith(
                        color: accent,
                        letterSpacing: 2.5,
                      ),
                    ),
                    const Spacer(),
                    // The SECOND door. The thumb answers "what is this
                    // movement?" while scanning; this answers "am I doing it
                    // right?" at the rep. Placed before the Spacer's chevron so
                    // it reads as part of the label group, and with its own
                    // detector so the panel's expand/collapse tap is untouched.
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          ExercisePlateSheet.show(context, widget.exerciseName),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          'VIEW PLATE',
                          style: AppTypography.monoXs.copyWith(
                            color: accent,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: accent.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ),

            // Body (collapsible)
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_cues.cues.isNotEmpty)
                      _bulletSection('COACHING CUES', _cues.cues),
                    if (_cues.mistakes.isNotEmpty)
                      _bulletSection('COMMON MISTAKES', _cues.mistakes),
                    if (_cues.breathing != null)
                      _lineSection('BREATHING', _cues.breathing!),
                    if (_cues.warmup != null)
                      _lineSection('WARM-UP', _cues.warmup!),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(
          label,
          style: AppTypography.monoXs.copyWith(
            color: AppColors.textDim,
            letterSpacing: 1.8,
          ),
        ),
      );

  Widget _bulletSection(String label, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(label),
        ...items.map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ',
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.accent)),
                Expanded(
                  child: Text(
                    t,
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.textSecondary, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _lineSection(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(label),
        Text(
          value,
          style: AppTypography.bodySm
              .copyWith(color: AppColors.textSecondary, height: 1.35),
        ),
      ],
    );
  }
}
