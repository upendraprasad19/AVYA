part of 'screen.dart';

// ══════════════════════════════════════════════════════════════════
// Warm-up / Cool-down collapsible checklist
// ══════════════════════════════════════════════════════════════════

class _WarmupCooldownSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<ExerciseData> exercises;
  final bool initiallyExpanded;

  const _WarmupCooldownSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.exercises,
    this.initiallyExpanded = true,
  });

  @override
  State<_WarmupCooldownSection> createState() => _WarmupCooldownSectionState();
}

class _WarmupCooldownSectionState extends State<_WarmupCooldownSection> {
  late bool _expanded;
  late List<bool> _checked;

  /// Hive key used to persist the check list across widget rebuilds (scroll,
  /// keyboard, parent rebuild). F10 · without this, scrolling the workout
  /// screen clears every warmup check.
  String get _hiveKey {
    // APK Test #12.6 IST sweep — see feedback_use_ist_throughout.md
    final today = istDateStr(DateTime.now());
    final slug = widget.title.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    return 'warmup_checks_${today}_$slug';
  }

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _checked = _loadChecks();
  }

  List<bool> _loadChecks() {
    try {
      final raw = HiveService.instance.workoutBox.get(_hiveKey);
      if (raw is List) {
        final restored = raw
            .map((v) => v == true)
            .toList();
        // Adjust length if exercise count changed since last session.
        if (restored.length == widget.exercises.length) return restored;
      }
    } catch (_) {/* hive corrupt — fall through */}
    return List.filled(widget.exercises.length, false);
  }

  Future<void> _persistChecks() async {
    try {
      await HiveService.instance.workoutBox.put(_hiveKey, _checked);
    } catch (_) {/* non-fatal — UI still shows the tick */}
  }

  @override
  void didUpdateWidget(covariant _WarmupCooldownSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.exercises.length != _checked.length) {
      // Exercise count changed — reload from Hive (may still match),
      // else reset.
      _checked = _loadChecks();
    }
  }

  int get _checkedCount => _checked.where((c) => c).length;
  bool get _allDone => _checkedCount == widget.exercises.length;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: widget.color.withValues(alpha: _allDone ? 0.3 : 0.12),
          ),
        ),
        child: Column(
          children: [
            // Header row (tappable to expand/collapse)
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(widget.icon, size: 16, color: widget.color),
                    const SizedBox(width: 8),
                    Text(
                      widget.title,
                      style: AppTypography.mono.copyWith(
                        color: widget.color,
                        letterSpacing: 2.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_checkedCount > 0)
                      Text(
                        '$_checkedCount/${widget.exercises.length}',
                        style: AppTypography.monoXs.copyWith(
                          color: widget.color.withValues(alpha: 0.6),
                          letterSpacing: 1.2,
                        ),
                      ),
                    const Spacer(),
                    if (_allDone)
                      Icon(Icons.check_circle, size: 16, color: widget.color)
                    else
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 18,
                        color: widget.color.withValues(alpha: 0.5),
                      ),
                  ],
                ),
              ),
            ),

            // Exercise rows (collapsible)
            if (_expanded)
              ...widget.exercises.asMap().entries.map((entry) {
                final idx = entry.key;
                final ex = entry.value;
                final done = _checked[idx];

                // Format duration/reps. ExerciseData.reps is now a clean
                // numeric string for timed exercises (Bug #16 fix). Defensive
                // fallback to 30s if parsing somehow fails.
                String detail;
                if (ex.loggingType == 'timed') {
                  final raw = ex.reps.replaceAll(RegExp(r'[^0-9]'), '');
                  final parsedSecs = int.tryParse(raw) ?? 0;
                  final secs = parsedSecs > 0 ? parsedSecs : 30;
                  if (secs >= 60) {
                    final mins = secs ~/ 60;
                    final remainder = secs % 60;
                    detail = remainder == 0 ? '${mins}m' : '${mins}m ${remainder}s';
                  } else {
                    detail = '${secs}s';
                  }
                } else {
                  detail = '${ex.sets} × ${ex.reps}';
                }

                return GestureDetector(
                  onTap: () {
                    setState(() => _checked[idx] = !_checked[idx]);
                    _persistChecks(); // F10 · survive scroll rebuild
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                    child: Row(
                      children: [
                        Icon(
                          done ? Icons.check_circle : Icons.circle_outlined,
                          size: 18,
                          color: done
                              ? widget.color
                              : widget.color.withValues(alpha: 0.3),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            ex.name,
                            style: AppTypography.bodySm.copyWith(
                              color: done
                                  ? AppColors.textDim
                                  : AppColors.textPrimary,
                              decoration: done
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        Text(
                          detail,
                          style: AppTypography.monoXs.copyWith(
                            color: AppColors.textDim,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            if (_expanded) const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }
}
