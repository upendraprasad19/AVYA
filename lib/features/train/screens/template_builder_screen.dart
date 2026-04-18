import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import '../../home/providers/home_provider.dart';
import '../providers/train_provider.dart';
import '../widgets/create_custom_exercise_sheet.dart';
import '../widgets/exercise_card.dart';

class TemplateBuilderScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? editData;

  const TemplateBuilderScreen({super.key, this.editData});

  @override
  ConsumerState<TemplateBuilderScreen> createState() =>
      _TemplateBuilderScreenState();
}

class _TemplateBuilderScreenState
    extends ConsumerState<TemplateBuilderScreen> {
  final _nameController = TextEditingController();
  final _exercises = <Map<String, dynamic>>[];
  final _selectedDays = <int>{}; // 1=Mon, 2=Tue, ..., 7=Sun
  bool _isSaving = false;
  String? _editingTemplateId;

  @override
  void initState() {
    super.initState();
    final data = widget.editData;
    if (data != null) {
      _editingTemplateId = data['templateId'] as String?;
      final tmpl = data['templateData'] as Map?;
      if (tmpl != null) {
        _nameController.text = (tmpl['name'] as String?) ?? '';
        final exercises = tmpl['exercises'] as List?;
        if (exercises != null) {
          for (final e in exercises) {
            if (e is Map) _exercises.add(Map<String, dynamic>.from(e));
          }
        }
        final days = tmpl['assigned_days'] as List?;
        if (days != null) {
          for (final d in days) {
            if (d is int) _selectedDays.add(d);
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.header,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.go('/train'),
        ),
        title: Text(
          'Template Builder',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _exercises.isNotEmpty && !_isSaving ? _saveTemplate : null,
            child: Text(
              'Save',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: _exercises.isNotEmpty
                    ? AppColors.accent
                    : AppColors.textDisabled,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          children: [
            // Template name
            TextField(
              controller: _nameController,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Template Name',
                hintStyle: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDisabled,
                ),
                filled: true,
                fillColor: AppColors.input,
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.cardS),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.cardS),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.cardS),
                  borderSide: BorderSide(color: AppColors.accent, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sectionGap),

            // Day selector chips (W7) — assign template to specific weekdays
            Text(
              _editingTemplateId != null ? 'EDIT SCHEDULE' : 'ASSIGN TO DAYS',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap days to toggle. Selected days sync to your home calendar.',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: List.generate(7, (i) {
                final dayNum = i + 1; // 1=Mon ... 7=Sun
                const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                final isSelected = _selectedDays.contains(dayNum);
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i < 6 ? 6 : 0),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedDays.remove(dayNum);
                          } else {
                            _selectedDays.add(dayNum);
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.accent.withValues(alpha: 0.1)
                              : AppColors.input,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.accent.withValues(alpha: 0.4)
                                : AppColors.border,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            dayLabels[i],
                            style: GoogleFonts.getFont(
                              'DM Sans',
                              fontSize: 10,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            if (_selectedDays.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${_selectedDays.length} day${_selectedDays.length == 1 ? '' : 's'} selected',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: AppColors.accent,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.sectionGap),

            // Exercises header
            Row(
              children: [
                Text('Exercises', style: AppTypography.titleS),
                const Spacer(),
                Text(
                  '${_exercises.length} added',
                  style: AppTypography.bodyS
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.gridGap),

            // Exercise list
            if (_exercises.isEmpty)
              GestureDetector(
                onTap: () => _showExerciseSearch(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  decoration: BoxDecoration(
                    color: AppColors.input,
                    borderRadius: BorderRadius.circular(AppRadius.cardS),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.25),
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.add_circle_outline,
                          color: AppColors.accent, size: 40),
                      const SizedBox(height: 8),
                      Text(
                        'Tap to add exercises',
                        style: AppTypography.bodyM
                            .copyWith(color: AppColors.accent, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Build your workout by adding exercises',
                        style: AppTypography.bodyS
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              )
            else
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final item = _exercises.removeAt(oldIndex);
                    _exercises.insert(newIndex, item);
                  });
                },
                children: _exercises.asMap().entries.map((entry) {
                  final index = entry.key;
                  final exercise = entry.value;
                  return Padding(
                    key: ValueKey(
                        '${exercise['id'] ?? exercise['name']}_$index'),
                    padding:
                        const EdgeInsets.only(bottom: AppSpacing.gridGap),
                    child: ExerciseCard(
                      name: exercise['name'] as String? ?? 'Unknown',
                      category: exercise['category'] as String?,
                      loggingType: (exercise['logging_type'] as String?) ??
                          'weight_reps',
                      sets: (exercise['prescribed_sets'] as int?) ??
                          (exercise['default_sets'] as int?) ??
                          3,
                      reps: (exercise['prescribed_reps'] as String?) ??
                          (exercise['default_reps'] as String?) ??
                          '10',
                      restSeconds: (exercise['rest_seconds'] as int?) ??
                          (exercise['default_rest_secs'] as int?) ??
                          90,
                      onRemove: () {
                        setState(() => _exercises.removeAt(index));
                      },
                    ),
                  );
                }).toList(),
              ),

            const SizedBox(height: AppSpacing.gridGap),

            // Add exercise button
            OutlinedButton.icon(
              onPressed: () => _showExerciseSearch(context),
              icon: const Icon(Icons.add, color: AppColors.accent),
              label: Text(
                'Add Exercise',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accent,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                side: BorderSide(
                  color: AppColors.accent.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  void _showExerciseSearch(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExerciseSearchSheet(
        onSelect: (exercise) {
          setState(() => _exercises.add(exercise));
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Future<void> _saveTemplate() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enter a template name',
            style: GoogleFonts.getFont('DM Sans'),
          ),
          backgroundColor: AppColors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final templateData = {
        'name': name,
        'exercises': _exercises,
        'exercise_count': _exercises.length,
        'workout_type': 'custom',
        if (_selectedDays.isNotEmpty)
          'assigned_days': _selectedDays.toList()..sort(),
      };

      String templateId;
      if (_editingTemplateId != null) {
        await ref.read(templatesProvider.notifier).updateTemplate(
            _editingTemplateId!, templateData);
        templateId = _editingTemplateId!;
      } else {
        templateId = 'tmpl_${DateTime.now().millisecondsSinceEpoch}';
        templateData['id'] = templateId;
        await ref.read(templatesProvider.notifier).saveTemplate(templateData);
      }

      // Sync assigned_days to calendar schedule entries.
      //
      // Flow:
      //   1. Clean-sync: wipe this template's future non-completed
      //      entries and restore their displaced originals.
      //   2. Clamp writes to the real plan_end_date from configBox.
      //   3. If zero writable days, show the "Phase ends soon"
      //      snackbar and stop (template is still saved).
      //   4. On success, invalidate all consumers + fire-and-forget
      //      pushSnapshot so the AI coach catches up immediately.
      final scheduleService = WorkoutScheduleService.instance;
      await scheduleService.cleanSyncTemplateSchedule(templateId);

      int writtenCount = 0;
      if (_selectedDays.isNotEmpty) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        const maxWeeks = 4;

        // Clamp against the real plan end. For any user past the halfway
        // point of Phase 1 (or any future phase), some or all target
        // dates will fall beyond plan_end_date and must be skipped.
        final planEnd = scheduleService.getPlanEndDate() ??
            weekStart.add(const Duration(days: maxWeeks * 7 - 1));

        for (int weekOffset = 0; weekOffset < maxWeeks; weekOffset++) {
          for (final dayNum in _selectedDays) {
            // dayNum: 1=Mon, 7=Sun
            final targetDate = weekStart
                .add(Duration(days: weekOffset * 7 + dayNum - 1));
            if (targetDate.isBefore(today)) continue;
            if (targetDate.isAfter(planEnd)) continue;
            await scheduleService.assignTemplateToDate(templateId, targetDate);
            writtenCount++;
          }
        }
      }

      // Zero-writable-days guard: if the user picked days but none could
      // land inside the current Phase, tell them so they know why their
      // template didn't appear on the calendar.
      if (_selectedDays.isNotEmpty && writtenCount == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Template saved. No days could be scheduled — your current Phase ends soon. Schedule it manually after your next Phase commences.',
                style: GoogleFonts.getFont('DM Sans'),
              ),
              backgroundColor: AppColors.card,
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }

      // Invalidate every consumer of scheduled-workout state so the
      // Train tab, Home weekly calendar, stats, and streak all refresh
      // without the user having to restart. This is the Bug 1b fix.
      ref.invalidate(currentPlanProvider);
      ref.invalidate(calendarWeekProvider);
      ref.invalidate(todayWorkoutProvider);
      ref.invalidate(workoutStatsProvider);
      ref.invalidate(streakProvider);

      // Fire-and-forget snapshot push so the AI coach sees the new
      // schedule on the very next message (Bug 1g / Bug #6 fix).
      // Intentionally unawaited — do not block the UI on network.
      unawaited(SyncService.instance.pushSnapshot());

      // Push the template itself (and its exercises + assigned-day
      // schedule entries) to Supabase immediately.
      //
      // Added 2026-04-18: pushSnapshot only refreshes AI context; it does
      // NOT touch `workout_templates`, `template_exercises`, or
      // `scheduled_workouts`. Before this change, those tables only
      // filled on the weekly full-sync path — meaning a custom template
      // created today wouldn't appear in cloud (or "My Submissions") for
      // up to 7 days. Observed on icanbefitter@gmail.com — custom
      // template saved, workout_templates stayed at 0 rows.
      unawaited(SyncService.instance.syncWorkoutData());

      if (mounted) {
        context.go('/train');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to save template: $e',
              style: GoogleFonts.getFont('DM Sans'),
            ),
            backgroundColor: AppColors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

// ── Exercise Search Bottom Sheet ─────────────────────────────────

class _ExerciseSearchSheet extends StatefulWidget {
  final void Function(Map<String, dynamic> exercise) onSelect;

  const _ExerciseSearchSheet({required this.onSelect});

  @override
  State<_ExerciseSearchSheet> createState() => _ExerciseSearchSheetState();
}

class _ExerciseSearchSheetState extends State<_ExerciseSearchSheet> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _results = [];

  @override
  void initState() {
    super.initState();
    _refresh('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Merges bundled library with user-created custom exercises.
  ///
  /// Custom exercises are shown first so users can find their own
  /// additions quickly. When no query, caps at 30 bundled + all custom.
  void _refresh(String query) {
    final repo = ExerciseRepository.instance;
    final custom = repo.getCustomExercises();

    List<Map<String, dynamic>> bundled;
    List<Map<String, dynamic>> matchedCustom;

    if (query.isEmpty) {
      bundled = repo.getAll().take(30).toList();
      matchedCustom = custom;
    } else {
      final q = query.toLowerCase();
      bundled = repo.search(query).take(30).toList();
      matchedCustom = custom.where((e) {
        final name = (e['name'] as String?)?.toLowerCase() ?? '';
        return name.contains(q);
      }).toList();
    }

    setState(() {
      _results = [...matchedCustom, ...bundled];
    });
  }

  void _search(String query) => _refresh(query);

  Future<void> _openCreateCustom() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: CreateCustomExerciseSheet(
          onCreated: (ex) {
            // Immediately add the newly-created exercise to the template.
            widget.onSelect(ex);
          },
        ),
      ),
    );
    // Refresh so the new custom exercise is visible in the list even if
    // the user dismisses without the create sheet's auto-add firing.
    if (mounted) _refresh(_searchController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.cardL),
        ),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.textDisabled,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title + Create Custom button
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding, 0, AppSpacing.screenPadding, 10),
            child: Row(
              children: [
                Text(
                  'ADD EXERCISE',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _openCreateCustom,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add,
                            size: 12, color: AppColors.accent),
                        const SizedBox(width: 4),
                        Text(
                          'Create Custom',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _search,
              autofocus: true,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search exercises...',
                hintStyle: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 15,
                  color: AppColors.textSecondary,
                ),
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textSecondary, size: 20),
                filled: true,
                fillColor: AppColors.input,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.row),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.row),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.row),
                  borderSide: BorderSide(color: AppColors.accent),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Results
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      'No exercises found',
                      style: AppTypography.bodyM
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenPadding,
                    ),
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final ex = _results[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          ex['name'] as String? ?? 'Unknown',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          '${ex['category'] ?? ''} | ${_formatType(ex['logging_type'] as String? ?? '')}',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        trailing: const Icon(Icons.add_circle_outline,
                            color: AppColors.accent, size: 20),
                        onTap: () => widget.onSelect(ex),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatType(String type) =>
      type.replaceAll('_', ' ').toUpperCase();
}
