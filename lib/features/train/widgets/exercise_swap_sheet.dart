import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import '../providers/train_provider.dart';

/// Bottom sheet for swapping an exercise.
/// Reads from Hive exerciseBox, filtered by same category + equipment.
class ExerciseSwapSheet extends StatefulWidget {
  final String currentExerciseName;
  final String? category;
  final List<String>? equipment;
  final ValueChanged<SwapExerciseData> onSelect;

  const ExerciseSwapSheet({
    super.key,
    required this.currentExerciseName,
    required this.onSelect,
    this.category,
    this.equipment,
  });

  @override
  State<ExerciseSwapSheet> createState() => _ExerciseSwapSheetState();
}

class _ExerciseSwapSheetState extends State<ExerciseSwapSheet> {
  String _searchQuery = '';
  late List<Map<String, dynamic>> _libraryExercises;
  late List<Map<String, dynamic>> _customExercises;

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  void _loadExercises() {
    final repo = ExerciseRepository.instance;

    // Filter by category if available
    if (widget.category != null && widget.category!.isNotEmpty) {
      _libraryExercises = repo.query(
        category: widget.category,
        equipment: widget.equipment,
        limit: 20,
      );
    } else {
      _libraryExercises = repo.getAll();
      if (_libraryExercises.length > 20) {
        _libraryExercises = _libraryExercises.sublist(0, 20);
      }
    }

    // Remove the current exercise from the list
    _libraryExercises.removeWhere((e) =>
        (e['name'] as String?)?.toLowerCase() ==
        widget.currentExerciseName.toLowerCase());

    // Load custom exercises via repository
    _customExercises = ExerciseRepository.instance.getCustomExercises();
  }

  List<Map<String, dynamic>> get _filteredLibrary {
    if (_searchQuery.isEmpty) return _libraryExercises;
    final q = _searchQuery.toLowerCase();
    return _libraryExercises.where((e) {
      final name = (e['name'] as String?)?.toLowerCase() ?? '';
      return name.contains(q);
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

          // Header
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
                    widget.category != null
                        ? 'LIBRARY \u00b7 ${widget.category!.toUpperCase()}'
                        : 'LIBRARY \u00b7 ALL EXERCISES',
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
