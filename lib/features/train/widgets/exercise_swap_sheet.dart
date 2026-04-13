import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import '../providers/train_provider.dart';

/// Bottom sheet for swapping an exercise or adding a new one.
/// Reads from Hive exerciseBox, with category filter chips and search.
class ExerciseSwapSheet extends StatefulWidget {
  final String currentExerciseName;
  final String? category;
  final List<String>? equipment;
  final ValueChanged<SwapExerciseData> onSelect;
  final VoidCallback? onDelete;

  /// Called when the user taps "+ Add Exercise" to append (not replace).
  /// Receives the same [SwapExerciseData] as [onSelect].
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
    // Pre-select the current day's category if it matches a chip, otherwise "All"
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
    // Load ALL library exercises (no category filter — chips handle that)
    _allLibraryExercises = repo.getAll();

    // Remove the current exercise from the list
    _allLibraryExercises.removeWhere((e) =>
        (e['name'] as String?)?.toLowerCase() ==
        widget.currentExerciseName.toLowerCase());

    // Load custom exercises via repository
    _customExercises = ExerciseRepository.instance.getCustomExercises();
  }

  List<Map<String, dynamic>> get _filteredLibrary {
    if (_searchQuery.isNotEmpty) {
      // When searching, ignore the chip filter and search across ALL exercises
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
    // No search — apply category chip filter
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
        color: Color(0xFF0e1219),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF1c2535),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header row with title + optional Add Exercise button
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Swap: ${widget.currentExerciseName}',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (widget.onAdd != null) ...[
                  GestureDetector(
                    onTap: () {
                      // Use same sheet but in "add" mode —
                      // show picker, and when user selects, call onAdd
                      setState(() {
                        // Switch to "add" mode visually (handled via _isAddMode)
                      });
                    },
                    child: const SizedBox.shrink(),
                  ),
                ],
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF161d28),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '\u2715',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // "+ Add Exercise" button (when onAdd callback is provided)
          if (widget.onAdd != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: GestureDetector(
                onTap: () {
                  // Pop this sheet, then the parent will show the same picker
                  // in "add" mode. We use a special sentinel to signal this.
                  Navigator.of(context).pop();
                  widget.onAdd!(const SwapExerciseData(
                    name: '__ADD_MODE__',
                    detail: '',
                  ));
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.08),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.25),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '\uff0b Add Exercise',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Delete button
          if (widget.onDelete != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onDelete!();
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFef4444).withValues(alpha: 0.08),
                    border: Border.all(
                      color: const Color(0xFFef4444).withValues(alpha: 0.25),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '\u2212 Remove Exercise',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFef4444),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          const Divider(height: 1, color: Color(0xFF1c2535)),

          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF161d28),
                border: Border.all(color: const Color(0xFF1c2535)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 12,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Search exercises...',
                  hintStyle: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  isDense: true,
                ),
              ),
            ),
          ),

          // Category filter chips
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              itemCount: _categoryChips.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final chip = _categoryChips[i];
                final isActive = chip == _selectedCategory;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = chip),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color:
                          isActive ? AppColors.accent : const Color(0xFF161d28),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      chip,
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? Colors.black
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // Scrollable list
          Flexible(
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                // Section label
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                  child: Text(
                    _searchQuery.isNotEmpty
                        ? 'RESULTS \u00b7 ALL CATEGORIES'
                        : _selectedCategory == 'All'
                            ? 'LIBRARY \u00b7 ALL EXERCISES'
                            : 'LIBRARY \u00b7 ${_selectedCategory.toUpperCase()}',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      letterSpacing: 1,
                    ),
                  ),
                ),

                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      'No matching exercises found',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ...filtered.map((ex) => _SwapItem(
                        name: ex['name'] as String? ?? 'Unknown',
                        detail: _buildDetail(ex),
                        onSelect: () => widget.onSelect(SwapExerciseData(
                          name: ex['name'] as String? ?? 'Unknown',
                          detail: _buildDetail(ex),
                        )),
                      )),

                // Custom exercises section
                if (filteredCustom.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                    child: Text(
                      'YOUR CUSTOM EXERCISES',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  ...filteredCustom.map((ex) => _SwapItem(
                        name: ex['name'] as String? ?? 'Custom Exercise',
                        detail:
                            'Custom \u00b7 ${ex['category'] ?? ''} \u00b7 ${ex['logging_type'] ?? 'weight_reps'}',
                        onSelect: () => widget.onSelect(SwapExerciseData(
                          name: ex['name'] as String? ?? 'Custom Exercise',
                          detail: 'Custom',
                        )),
                      )),
                ],

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
    return parts.join(' \u00b7 ');
  }
}

class _SwapItem extends StatelessWidget {
  final String name;
  final String detail;
  final VoidCallback onSelect;

  const _SwapItem({
    required this.name,
    required this.detail,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFF1c2535)),
          ),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF161d28),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Center(
                child: Icon(
                  Icons.fitness_center,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Select button
            GestureDetector(
              onTap: onSelect,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Select',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
