part of 'screen.dart';

extension _YourExercisesSection on _TrainScreenState {
  // ── Your Exercises Section (D4 / D6) ─────────────────────────────
  //
  // Replaces the pre-2026-04-24 full-width "Create Custom Exercise"
  // WardCard with a header-plus-chips layout that mirrors MY TEMPLATES.
  // Users can see every exercise they've created, with a visible
  // approval state (DRAFT / PENDING / APPROVED) so the path from
  // create -> community -> approved is legible without opening Profile.

  Widget _buildYourExercisesSection(BuildContext context) {
    final customBox = HiveService.instance.customBox;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'YOUR EXERCISES',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _openCreateCustomExerciseSheet(context),
                child: const WardChip(
                  label: '+ CREATE',
                  tone: WardChipTone.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ValueListenableBuilder rebuilds the chip row whenever the
          // Hive customBox mutates — so new exercises appear as soon as
          // CreateCustomExerciseSheet._save writes them.
          ValueListenableBuilder<Box<dynamic>>(
            valueListenable: customBox.listenable(),
            builder: (context, box, _) {
              final exercises = _collectCustomExercises(box);
              if (exercises.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Row(
                    children: [
                      Text(
                        'No custom exercises yet — tap ',
                        style: AppTypography.bodyS
                            .copyWith(color: AppColors.textDim),
                      ),
                      GestureDetector(
                        onTap: () => _openCreateCustomExerciseSheet(context),
                        child: Text(
                          '+ CREATE',
                          style: AppTypography.bodyS.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        ' to add one.',
                        style: AppTypography.bodyS
                            .copyWith(color: AppColors.textDim),
                      ),
                    ],
                  ),
                );
              }
              return SizedBox(
                height: 68,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: exercises.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) =>
                      _CustomExerciseChip(exercise: exercises[i]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Reads every `custom_exercise_*` entry from the Hive customBox and
  /// returns them newest-first. Filters out malformed entries.
  List<Map<String, dynamic>> _collectCustomExercises(Box<dynamic> box) {
    final out = <Map<String, dynamic>>[];
    for (final key in box.keys) {
      if (key is! String || !key.startsWith('custom_exercise_')) continue;
      final raw = box.get(key);
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      map['_key'] = key;
      out.add(map);
    }
    // Newest first. Hive keys are `custom_exercise_<ms>` so string
    // descending sort == recency order.
    out.sort((a, b) => (b['_key'] as String).compareTo(a['_key'] as String));
    return out;
  }

  void _openCreateCustomExerciseSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => CreateCustomExerciseSheet(
        onCreated: (exercise) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Exercise saved. Showing in YOUR EXERCISES.',
                style: AppTypography.bodySm,
              ),
              backgroundColor: AppColors.card,
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
      ),
    );
  }
}
