import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../providers/train_provider.dart';

/// Bottom sheet for swapping an exercise or adding a new one.
/// Reads from Hive exerciseBox, with category chips and search.
class ExerciseSwapSheet extends StatefulWidget {
  final String currentExerciseName;
  final String? category;
  final List<String>? equipment;
  final ValueChanged<SwapExerciseData> onSelect;
  final VoidCallback? onDelete;

  /// Called when the user taps "+ Add Exercise" to append (not replace).
  final ValueChanged<SwapExerciseData>? onAdd;

  const ExerciseSwapSheet({
    super.key,
    required this.currentExerciseName,
    required this.onSelect,
    this.category,
    this.equipment,
    this.onDelete,
    this.onAdd,
  });

  @override
  State<ExerciseSwapSheet> createState() => _ExerciseSwapSheetState();
}

class _ExerciseSwapSheetState extends State<ExerciseSwapSheet> {
  String _searchQuery = '';
  String _selectedCategory = '';
  late List<Map<String, dynamic>> _allLibraryExercises;
  late List<Map<String, dynamic>> _customExercises;

  static const _categoryChips = [
    'All',
    'Push',
    'Pull',
    'Legs',
    'Core',
    'Cardio',
    'Flexibility',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.category != null &&
        _categoryChips
            .map((c) => c.toLowerCase())
            .contains(widget.category!.toLowerCase())) {
      _selectedCategory = _categoryChips.firstWhere(
        (c) => c.toLowerCase() == widget.category!.toLowerCase(),
        orElse: () => 'All',
      );
    } else {
      _selectedCategory = 'All';
    }
    _loadExercises();
  }

  void _loadExercises() {
    final repo = ExerciseRepository.instance;
    _allLibraryExercises = repo.getAll();
    _allLibraryExercises.removeWhere((e) =>
        (e['name'] as String?)?.toLowerCase() ==
        widget.currentExerciseName.toLowerCase());
    _customExercises = ExerciseRepository.instance.getCustomExercises();
  }

  List<Map<String, dynamic>> get _filteredLibrary {
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      return _allLibraryExercises.where((e) {
        final name = (e['name'] as String?)?.toLowerCase() ?? '';
        if (name.contains(q)) return true;
        final aliases = e['name_aliases'];
        if (aliases is List) {
          return aliases
              .any((a) => a.toString().toLowerCase().contains(q));
        }
        return false;
      }).toList();
    }
    if (_selectedCategory == 'All') return _allLibraryExercises;
    return _allLibraryExercises.where((e) {
      final cat = (e['category'] as String?)?.toLowerCase() ?? '';
      return cat == _selectedCategory.toLowerCase();
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredCustom {
    if (_searchQuery.isEmpty) return _customExercises;
    final q = _searchQuery.toLowerCase();
    return _customExercises.where((e) {
      final name = (e['name'] as String?)?.toLowerCase() ?? '';
      return name.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredLibrary;
    final filteredCustom = _filteredCustom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 10),
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: AppColors.line2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Eyebrow + title
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SWAP EXERCISE',
                        style: AppTypography.mono.copyWith(
                          color: AppColors.accent,
                          letterSpacing: 2.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.currentExerciseName,
                        style: AppTypography.h2,
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: AppColors.bgRaise,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: AppColors.line2),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: AppColors.textDim,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // "+ Add Exercise" slab (when onAdd available)
          if (widget.onAdd != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: WardButton(
                label: '+ ADD EXERCISE',
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onAdd!(const SwapExerciseData(
                    name: '__ADD_MODE__',
                    detail: '',
                  ));
                },
                variant: WardButtonVariant.outline,
                size: WardButtonSize.small,
              ),
            ),

          // Delete slab
          if (widget.onDelete != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: WardButton(
                label: '− REMOVE EXERCISE',
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onDelete!();
                },
                variant: WardButtonVariant.danger,
                size: WardButtonSize.small,
              ),
            ),

          const WardRule(margin: EdgeInsets.zero),

          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.bgRaise,
                border: Border.all(color: AppColors.line2, width: 2),
                borderRadius: BorderRadius.circular(2),
              ),
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                style: AppTypography.body,
                decoration: InputDecoration(
                  hintText: 'Search exercises...',
                  hintStyle: AppTypography.body.copyWith(
                    color: AppColors.textMute,
                  ),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  isDense: true,
                ),
              ),
            ),
          ),

          // Category chips
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              itemCount: _categoryChips.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final chip = _categoryChips[i];
                final isActive = chip == _selectedCategory;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = chip),
                  child: WardChip(
                    label: chip,
                    tone: isActive
                        ? WardChipTone.filled
                        : WardChipTone.neutral,
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          Flexible(
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
                  child: Text(
                    _searchQuery.isNotEmpty
                        ? 'RESULTS · ALL CATEGORIES'
                        : _selectedCategory == 'All'
                            ? 'LIBRARY · ALL EXERCISES'
                            : 'LIBRARY · ${_selectedCategory.toUpperCase()}',
                    style: AppTypography.mono.copyWith(
                      color: AppColors.textMute,
                      letterSpacing: 2,
                    ),
                  ),
                ),

                // APK Test #15.4 / A5 — render library results when non-empty.
                // Empty-state moved below to fire only when BOTH library AND
                // custom filtered lists are empty (pre-fix: a search that
                // matched a custom exercise but no library entry showed
                // misleading "No matching exercises found" above the custom
                // results below, confusing the founder into reporting
                // "Single Leg Front Lever" as missing).
                ...filtered.map((ex) => _SwapItem(
                      name: ex['name'] as String? ?? 'Unknown',
                      detail: _buildDetail(ex),
                      onSelect: () => widget.onSelect(SwapExerciseData(
                        name: ex['name'] as String? ?? 'Unknown',
                        detail: _buildDetail(ex),
                      )),
                    )),

                if (filteredCustom.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 6),
                    child: Text(
                      'YOUR CUSTOM EXERCISES',
                      style: AppTypography.mono.copyWith(
                        color: AppColors.textMute,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  ...filteredCustom.map((ex) => _SwapItem(
                        name: ex['name'] as String? ?? 'Custom Exercise',
                        detail:
                            'Custom · ${ex['category'] ?? ''} · ${ex['logging_type'] ?? 'weight_reps'}',
                        isCustom: true,
                        onSelect: () => widget.onSelect(SwapExerciseData(
                          name: ex['name'] as String? ?? 'Custom Exercise',
                          detail: 'Custom',
                        )),
                      )),
                ],

                if (filtered.isEmpty && filteredCustom.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Text(
                      'No matching exercises found',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textDim,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _buildDetail(Map<String, dynamic> ex) {
    final category = ex['category'] as String? ?? '';
    final loggingType = ex['logging_type'] as String? ?? 'weight_reps';
    final difficulty = ex['difficulty_level'] as String? ?? '';
    final parts = <String>[category, loggingType];
    if (difficulty.isNotEmpty) parts.add(difficulty);
    return parts.join(' · ');
  }
}

class _SwapItem extends StatelessWidget {
  final String name;
  final String detail;
  final VoidCallback onSelect;
  final bool isCustom;

  const _SwapItem({
    required this.name,
    required this.detail,
    required this.onSelect,
    this.isCustom = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.line2),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.bgRaise,
                borderRadius: BorderRadius.circular(2),
              ),
              child: const Center(
                child: Icon(
                  Icons.fitness_center,
                  size: 14,
                  color: AppColors.textDim,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // APK Test #15.4 / A5 — CUSTOM badge so users
                      // can visually distinguish their own exercises
                      // from the seeded library.
                      if (isCustom) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accentSoft,
                            borderRadius: BorderRadius.circular(2),
                            border:
                                Border.all(color: AppColors.accent, width: 1),
                          ),
                          child: Text(
                            'CUSTOM',
                            style: AppTypography.monoXs.copyWith(
                              color: AppColors.accent,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            WardButton(
              label: 'SELECT',
              onPressed: onSelect,
              variant: WardButtonVariant.outline,
              size: WardButtonSize.small,
              fullWidth: false,
            ),
          ],
        ),
      ),
    );
  }
}
