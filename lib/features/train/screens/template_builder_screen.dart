import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
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
    final canSave = _exercises.isNotEmpty && !_isSaving;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bgDeep,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.go('/train'),
        ),
        title: Text(
          'TEMPLATE BUILDER',
          style: AppTypography.mono.copyWith(
            fontSize: 11,
            color: AppColors.textPrimary,
            letterSpacing: 2.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: canSave ? _saveTemplate : null,
            child: Text(
              'SAVE',
              style: AppTypography.mono.copyWith(
                fontSize: 11,
                color: canSave ? AppColors.accent : AppColors.textGhost,
                letterSpacing: 2.5,
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
              style: AppTypography.h2.copyWith(fontSize: 18),
              decoration: InputDecoration(
                hintText: 'Template Name',
                hintStyle: AppTypography.h2.copyWith(
                  fontSize: 18,
                  color: AppColors.textGhost,
                ),
                filled: true,
                fillColor: AppColors.bgRaise,
                contentPadding: const EdgeInsets.all(16),
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
                  borderSide:
                      const BorderSide(color: AppColors.accent, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sectionGap),

            // Day selector chips (W7) — assign template to specific weekdays
            Text(
              _editingTemplateId != null ? 'EDIT SCHEDULE' : 'ASSIGN TO DAYS',
              style: AppTypography.mono.copyWith(
                color: AppColors.textMute,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap days to toggle. Selected days sync to your home calendar.',
              style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
            ),
            const SizedBox(height: 8),
            Row(
              children: List.generate(7, (i) {
                final dayNum = i + 1; // 1=Mon ... 7=Sun
                const dayLabels = [
                  'MON',
                  'TUE',
                  'WED',
                  'THU',
                  'FRI',
                  'SAT',
                  'SUN'
                ];
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
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.accentSoft
                              : AppColors.bgRaise,
                          borderRadius:
                              BorderRadius.circular(AppRadius.sharp),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.accent.withValues(alpha: 0.4)
                                : AppColors.line2,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            dayLabels[i],
                            style: AppTypography.monoXs.copyWith(
                              color: isSelected
                                  ? AppColors.accent
                                  : AppColors.textDim,
                              letterSpacing: 1.5,
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
                  '${_selectedDays.length} DAY${_selectedDays.length == 1 ? '' : 'S'} SELECTED',
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.accent,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.sectionGap),

            // Exercises header
            Row(
              children: [
                Text('Exercises', style: AppTypography.h3),
                const Spacer(),
                Text(
                  '${_exercises.length} ADDED',
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.textDim,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.gridGap),

            // Exercise list
            if (_exercises.isEmpty)
              WardCard(
                variant: WardCardVariant.inset,
                padding: const EdgeInsets.symmetric(vertical: 30),
                onTap: () => _showExerciseSearch(context),
                child: Column(
                  children: [
                    const Icon(Icons.add_circle_outline,
                        color: AppColors.accent, size: 40),
                    const SizedBox(height: 8),
                    Text(
                      'TAP TO ADD EXERCISES',
                      style: AppTypography.mono.copyWith(
                        color: AppColors.accent,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Build your workout by adding exercises',
                      style: AppTypography.bodySm
                          .copyWith(color: AppColors.textDim),
                    ),
                  ],
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
            WardButton(
              label: '+ ADD EXERCISE',
              onPressed: () => _showExerciseSearch(context),
              variant: WardButtonVariant.outline,
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
            style: AppTypography.bodySm,
          ),
          backgroundColor: AppColors.bad,
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
        await ref
            .read(templatesProvider.notifier)
            .updateTemplate(_editingTemplateId!, templateData);
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
            // APK Test #15.3 / Bug 4b (closes-diagnose: 8f3d22):
            // only count the date as written when the service confirms
            // success — completed days return AssignTemplateRejected.
            final result = await scheduleService.assignTemplateToDate(
                templateId, targetDate);
            if (result is AssignTemplateOk) writtenCount++;
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
                style: AppTypography.bodySm,
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
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent('train_template_save_failed',
          message: clipped));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to save template: $e',
              style: AppTypography.bodySm,
            ),
            backgroundColor: AppColors.bad,
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
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
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
              color: AppColors.line2,
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
                  style: AppTypography.mono.copyWith(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    letterSpacing: 2.5,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _openCreateCustom,
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
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _search,
              autofocus: true,
              style: AppTypography.body,
              decoration: InputDecoration(
                hintText: 'Search exercises...',
                hintStyle:
                    AppTypography.body.copyWith(color: AppColors.textDim),
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textDim, size: 20),
                filled: true,
                fillColor: AppColors.bgRaise,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
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
                  borderSide: const BorderSide(color: AppColors.accent),
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
                      style: AppTypography.body
                          .copyWith(color: AppColors.textDim),
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
                          style: AppTypography.h3.copyWith(fontSize: 14),
                        ),
                        subtitle: Text(
                          '${ex['category'] ?? ''} · ${_formatType(ex['logging_type'] as String? ?? '')}',
                          style: AppTypography.monoXs.copyWith(
                            color: AppColors.textDim,
                            letterSpacing: 1.2,
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
