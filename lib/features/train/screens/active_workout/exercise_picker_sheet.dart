part of 'screen.dart';

// ── Exercise Picker Bottom Sheet ─────────────────────────────────

class _ExercisePickerSheet extends StatefulWidget {
  final void Function(Map<String, dynamic> exerciseData) onSelect;

  /// `exerciseNameKey`s already in the session (OI-358): those rows stay
  /// findable by search and cannot be tapped.
  final Set<String> takenNames;

  const _ExercisePickerSheet({required this.onSelect, required this.takenNames});

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All';
  List<Map<String, dynamic>> _allExercises = [];
  List<Map<String, dynamic>> _filtered = [];

  static const _categoryFilters = [
    'All', 'Push', 'Pull', 'Legs', 'Core', 'Cardio', 'Flexibility',
  ];

  @override
  void initState() {
    super.initState();
    _loadAllExercises();
    _searchController.addListener(_applyFilter);
  }

  void _loadAllExercises() {
    // Every exercise is listed (founder 2026-11-28): the ones the user's
    // equipment covers come first, and a name is listed once.
    _allExercises = PickerRows.arrange(
      library: ExerciseRepository.instance.getAll(),
      custom: ExerciseRepository.instance.getCustomExercises(),
      capability: TrainingHistoryAnalyzer.resolveCapabilityFromProfile(),
    ).merged;
    _filtered = _allExercises;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final typed = _searchController.text;
    final query = typed.isEmpty ? '' : exerciseDuplicateKey(typed);
    setState(() {
      _filtered = _allExercises.where((e) {
        // Category filter
        if (_selectedCategory != 'All' &&
            !PickerRows.inCategory(e, _selectedCategory)) {
          return false;
        }
        // Search filter
        if (query.isNotEmpty) {
          final name = exerciseDuplicateKey(e['name'] as String? ?? '');
          if (!name.contains(query)) {
            final aliases = e['name_aliases'];
            if (aliases is List) {
              final aliasMatch = aliases.any((a) =>
                  exerciseDuplicateKey(a.toString()).contains(query));
              if (!aliasMatch) return false;
            } else {
              return false;
            }
          }
        }
        return true;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
        border: const Border(
          top: BorderSide(color: AppColors.line2),
          left: BorderSide(color: AppColors.line2),
          right: BorderSide(color: AppColors.line2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 6),
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.line2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title + Create Custom button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Text(
                  'ADD EXERCISE',
                  style: AppTypography.mono.copyWith(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    letterSpacing: 2.5,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () async {
                    await showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      builder: (_) => Padding(
                        padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).viewInsets.bottom),
                        child: CreateCustomExerciseSheet(
                          onCreated: (ex) {
                            widget.onSelect(ex);
                          },
                        ),
                      ),
                    );
                    // Refresh list in case user created and then dismissed
                    if (mounted) {
                      setState(() => _loadAllExercises());
                      _applyFilter();
                    }
                  },
                  child: const WardChip(
                    label: '+ CREATE CUSTOM',
                    tone: WardChipTone.gold,
                  ),
                ),
              ],
            ),
          ),

          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _searchController,
              style: AppTypography.bodySm,
              decoration: InputDecoration(
                hintText: 'Search exercises...',
                hintStyle:
                    AppTypography.bodySm.copyWith(color: AppColors.textDim),
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textDim, size: 18),
                filled: true,
                fillColor: AppColors.bgRaise,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: const BorderSide(color: AppColors.line2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: const BorderSide(color: AppColors.line2),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  borderSide: BorderSide(
                      color: AppColors.accent.withValues(alpha: 0.5)),
                ),
              ),
            ),
          ),

          // Category filter chips
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: _categoryFilters.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final cat = _categoryFilters[i];
                final isSelected = cat == _selectedCategory;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedCategory = cat);
                    _applyFilter();
                  },
                  child: WardChip(
                    label: cat,
                    tone: isSelected
                        ? WardChipTone.gold
                        : WardChipTone.neutral,
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 4),

          // Exercise list
          Flexible(
            child: _filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No exercises found',
                        style: AppTypography.bodySm
                            .copyWith(color: AppColors.textDim),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final ex = _filtered[i];
                      final name = ex['name'] as String? ?? 'Unknown';
                      final category = ex['category'] as String? ?? '';
                      final muscles =
                          (ex['primary_muscles'] as List?)?.join(', ') ?? '';
                      final loggingType =
                          ex['logging_type'] as String? ?? 'weight_reps';
                      final taken =
                          PickerRows.isTaken(name, widget.takenNames);

                      return InkWell(
                        onTap: taken ? null : () => widget.onSelect(ex),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                  color: AppColors.line2, width: 0.5),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: AppTypography.h3.copyWith(
                                          fontSize: 13,
                                          color:
                                              taken ? AppColors.textGhost : null),
                                    ),
                                    if (taken)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 2),
                                        child: Text(
                                          WardroomCopy.activeAlreadyInWorkoutTag,
                                          style: AppTypography.monoXs.copyWith(
                                            color: AppColors.textMute,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      ),
                                    if (muscles.isNotEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 2),
                                        child: Text(
                                          muscles,
                                          style: AppTypography.bodySm
                                              .copyWith(
                                                  color: AppColors.textDim),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Category badge
                              WardChip(
                                label: category,
                                tone: WardChipTone.gold,
                              ),
                              const SizedBox(width: 6),
                              // Logging type icon
                              Icon(
                                loggingType == 'timed'
                                    ? Icons.timer_outlined
                                    : loggingType == 'cardio'
                                        ? Icons.directions_run
                                        : Icons.fitness_center,
                                size: 14,
                                color: AppColors.textGhost,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
