import 'package:flutter/material.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/exercise_name_identity.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/repositories/picker_rows.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import '../providers/train_provider.dart';

/// Bottom sheet for swapping an exercise or adding a new one.
/// Reads from Hive exerciseBox, with category chips and search.
class ExerciseSwapSheet extends StatefulWidget {
  final String currentExerciseName;
  final String? category;

  /// The OUTGOING exercise's requirement — NOT the user's capability.
  /// ⑦ OI-89: this field was declared, accepted, and read NOWHERE. Using it
  /// for the user would invert the check: swapping away from Chin Up would put
  /// pull-up-bar exercises first. [capability] is the user's; this stays for
  /// the caller's context.
  final List<String>? equipment;

  /// What the user's equipment covers, or null for "everything". It ORDERS
  /// the rows and never hides one: a swap picked by hand can be any exercise
  /// (founder 2026-11-28, [PickerRows]).
  final Set<String>? capability;

  /// `exerciseNameKey`s already in the session (OI-358): those rows stay
  /// findable by search and cannot be picked. Every session name, so a custom
  /// outgoing exercise (left in the custom list) is covered too.
  final Set<String> takenNames;
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
    this.capability,
    this.takenNames = const {},
    this.onDelete,
    this.onAdd,
  });

  @override
  State<ExerciseSwapSheet> createState() => _ExerciseSwapSheetState();
}

class _ExerciseSwapSheetState extends State<ExerciseSwapSheet> {
  String _searchQuery = '';
  String _selectedCategory = '';
  late List<Map<String, dynamic>> _matchingLibrary;
  late List<Map<String, dynamic>> _otherLibrary;
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
    // The whole list is arranged first, so a row that stands for another keeps
    // that row's names, the outgoing exercise's included.
    final rows = PickerRows.arrange(
      library: repo.getAll(),
      custom: repo.getCustomExercises(),
      capability: widget.capability,
    );
    final current = exerciseDuplicateKey(widget.currentExerciseName);
    bool notCurrent(Map<String, dynamic> e) =>
        exerciseDuplicateKey(e['name'] as String? ?? '') != current;
    _matchingLibrary = rows.matchingLibrary.where(notCurrent).toList();
    _otherLibrary = rows.otherLibrary.where(notCurrent).toList();
    _customExercises = rows.custom;
  }

  bool _isTaken(Map<String, dynamic> ex) =>
      PickerRows.isTaken(ex['name'] as String? ?? '', widget.takenNames);

  /// A search reads every category. With no search the chip narrows the
  /// library rows.
  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> rows) {
    if (_searchQuery.isNotEmpty) return _searched(rows);
    if (_selectedCategory == 'All') return rows;
    return rows
        .where((e) => PickerRows.inCategory(e, _selectedCategory))
        .toList();
  }

  /// The user's own exercises ignore the chip: many are filed under another
  /// category, or under one that has no chip.
  List<Map<String, dynamic>> get _filteredCustom => _searchQuery.isEmpty
      ? _customExercises
      : _searched(_customExercises);

  List<Map<String, dynamic>> _searched(List<Map<String, dynamic>> rows) {
    final q = exerciseDuplicateKey(_searchQuery);
    bool hit(Object? name) =>
        exerciseDuplicateKey(name?.toString() ?? '').contains(q);
    return rows.where((e) {
      final aliases = e['name_aliases'];
      return hit(e['name']) || (aliases is List && aliases.any(hit));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final matching = _filtered(_matchingLibrary);
    final other = _filtered(_otherLibrary);
    final filtered = [...matching, ...other];
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
                ...matching.map(_libraryItem),

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
                        taken: _isTaken(ex),
                        onSelect: () => widget.onSelect(SwapExerciseData(
                          name: ex['name'] as String? ?? 'Custom Exercise',
                          detail: 'Custom',
                          id: ex['id'] as String?, // W3.3: carry the custom id
                          // Obs 6: the swapped-IN exercise's own logging type.
                          loggingType: ex['logging_type'] as String?,
                        )),
                      )),
                ],

                // Rows outside the user's equipment: listed last, still
                // theirs to pick.
                if (other.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 6),
                    child: Text(
                      'MORE FROM THE LIBRARY',
                      style: AppTypography.mono.copyWith(
                        color: AppColors.textMute,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  ...other.map(_libraryItem),
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

  Widget _libraryItem(Map<String, dynamic> ex) => _SwapItem(
        name: ex['name'] as String? ?? 'Unknown',
        detail: _buildDetail(ex),
        taken: _isTaken(ex),
        onSelect: () => widget.onSelect(SwapExerciseData(
          name: ex['name'] as String? ?? 'Unknown',
          detail: _buildDetail(ex),
          id: ex['id'] as String?, // W3.3: carry the library id
          // Obs 6: the swapped-IN exercise's own logging type.
          loggingType: ex['logging_type'] as String?,
        )),
      );

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

  /// OI-358: already in the session. The row and its button both go dead.
  final bool taken;

  const _SwapItem({
    required this.name,
    required this.detail,
    required this.onSelect,
    this.isCustom = false,
    this.taken = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: taken ? null : onSelect,
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
                            color: taken ? AppColors.textGhost : null,
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
                    taken ? WardroomCopy.activeAlreadyInWorkoutTag : detail,
                    style: (taken ? AppTypography.monoXs : AppTypography.bodySm)
                        .copyWith(
                      color: taken ? AppColors.textMute : AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            if (!taken)
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
