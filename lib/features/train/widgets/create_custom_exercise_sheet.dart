import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:uuid/uuid.dart';

/// Bottom sheet for creating a custom exercise on the fly.
///
/// Writes the new exercise to `customBox` with `type: 'exercise'` and
/// `is_custom: true`, then invokes [onCreated] with the exercise map so
/// the caller can add it to the current workout or template immediately.
///
/// Extracted from `active_workout_screen.dart` so the template builder
/// can reuse the same UI — keeps a single source of truth for the
/// custom-exercise creation flow.
class CreateCustomExerciseSheet extends StatefulWidget {
  final void Function(Map<String, dynamic> exercise) onCreated;

  const CreateCustomExerciseSheet({super.key, required this.onCreated});

  @override
  State<CreateCustomExerciseSheet> createState() =>
      _CreateCustomExerciseSheetState();
}

class _CreateCustomExerciseSheetState extends State<CreateCustomExerciseSheet> {
  final _nameCtrl = TextEditingController();
  final _setsCtrl = TextEditingController(text: '3');
  final _repsCtrl = TextEditingController(text: '10');
  final _durationCtrl = TextEditingController(text: '30');

  String _loggingType = 'weight_reps';
  String _category = 'Push';
  bool _shareWithCommunity = false;

  static const _loggingTypes = [
    ('weight_reps', 'Weight + Reps'),
    ('bodyweight_reps', 'Bodyweight Reps'),
    ('timed', 'Timed'),
    ('cardio', 'Cardio'),
  ];

  /// Whether to show the "Default Reps" field. Reps is meaningful for
  /// weight_reps and bodyweight_reps. For timed/cardio it's nonsensical
  /// (observed 2026-04-18 — user picked "Timed" for L Sit but the form
  /// still showed Default Reps).
  bool get _showRepsField =>
      _loggingType == 'weight_reps' || _loggingType == 'bodyweight_reps';

  /// Whether to show the "Default Duration (sec)" field. Only for
  /// timed — the active-workout UI then prompts the user for a stopwatch
  /// duration per set.
  bool get _showDurationField => _loggingType == 'timed';

  static const _categories = [
    'Push', 'Pull', 'Legs', 'Core', 'Cardio', 'Flexibility',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _setsCtrl.dispose();
    _repsCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    // Stable id (F8): deterministic v5 from (user_id, 'exercise', lower(name)).
    // Makes cloud upserts idempotent — same exercise from multiple devices
    // collapses to one row instead of creating duplicates on every sync.
    const customNs = '5a1f0b0c-9dad-11d1-80b4-00c04fd430c8';
    final userId = SupabaseService.instance.currentUser?.id ?? 'anon';
    final id = const Uuid().v5(customNs, '$userId|exercise|${name.toLowerCase()}');

    final key = 'custom_exercise_${DateTime.now().millisecondsSinceEpoch}';
    final exercise = <String, dynamic>{
      'id': id,
      'name': name,
      'category': _category,
      'logging_type': _loggingType,
      'default_sets': int.tryParse(_setsCtrl.text) ?? 3,
      // Only store default_reps when the logging type uses reps.
      // For timed / cardio the field is hidden in the UI and the active
      // workout screen uses different inputs (duration / distance).
      if (_showRepsField)
        'default_reps':
            _repsCtrl.text.trim().isEmpty ? '10' : _repsCtrl.text.trim(),
      if (_showDurationField)
        'default_duration_seconds':
            int.tryParse(_durationCtrl.text.trim()) ?? 30,
      'primary_muscles': <String>[],
      'equipment_needed': <String>[],
      'is_custom': true,
      'type': 'exercise',
      'submitted_to_library': _shareWithCommunity,
      'approved_for_library': false,
    };

    HiveService.instance.customBox.put(key, exercise);
    // Push custom exercise to Supabase immediately.
    //
    // Previously only pushSnapshot() fired here, which refreshes AI coach
    // context but does NOT touch the `user_custom_exercises` table. Combined
    // with a bug in _syncCustomItems that looked for a list key, custom
    // exercises never reached cloud at all (observed 2026-04-18 — "L Sit"
    // created, user_custom_exercises stayed at 0 rows). syncCustomItemsNow
    // now iterates per-key entries and writes this exercise's row.
    unawaited(SyncService.instance.syncCustomItemsNow());
    unawaited(SyncService.instance.pushSnapshot());
    Navigator.of(context).pop();
    widget.onCreated(exercise);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'CREATE CUSTOM EXERCISE',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),

          // Name field
          Text(
            'Exercise Name',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.25)),
            ),
            child: TextField(
              controller: _nameCtrl,
              autofocus: true,
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
                hintText: 'e.g. Band Pull-Apart',
                hintStyle:
                    TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Category + Logging Type row
          Row(
            children: [
              // Category dropdown
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Category',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.input,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _category,
                          isExpanded: true,
                          dropdownColor: AppColors.card,
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          items: _categories
                              .map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _category = v ?? _category),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Logging type dropdown
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Logging Type',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.input,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _loggingType,
                          isExpanded: true,
                          dropdownColor: AppColors.card,
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          items: _loggingTypes
                              .map((lt) => DropdownMenuItem(
                                    value: lt.$1,
                                    child: Text(lt.$2),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _loggingType = v ?? _loggingType),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Sets + (Reps | Duration) row — second field swaps based on
          // logging_type. Sets stays visible for every type; Reps shows
          // for weight_reps / bodyweight_reps; Duration (sec) shows for
          // timed; cardio shows Sets only (distance input lives in the
          // active workout UI for now).
          Row(
            children: [
              Expanded(
                child: _numericField(
                  label: 'Default Sets',
                  controller: _setsCtrl,
                ),
              ),
              if (_showRepsField) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _numericField(
                    label: 'Default Reps',
                    controller: _repsCtrl,
                    hint: '10 or 8-12',
                    numericOnly: false,
                  ),
                ),
              ],
              if (_showDurationField) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: _numericField(
                    label: 'Default Duration (sec)',
                    controller: _durationCtrl,
                    hint: '30',
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Share with community toggle
          Row(
            children: [
              Expanded(
                child: Text(
                  'Share with AVYA community',
                  style: GoogleFonts.getFont('DM Sans', fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
              Switch(
                value: _shareWithCommunity,
                onChanged: (v) => setState(() => _shareWithCommunity = v),
                activeThumbColor: AppColors.accent,
                activeTrackColor: AppColors.accent.withValues(alpha: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Save button
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: _save,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(100),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Add to Workout',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Small reusable numeric / text field used for Default Sets / Reps /
  /// Duration. Extracted so the Sets+Reps+Duration row stays readable.
  Widget _numericField({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool numericOnly = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: TextField(
            controller: controller,
            keyboardType:
                numericOnly ? TextInputType.number : TextInputType.text,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
              hintText: hint,
              hintStyle: hint == null
                  ? null
                  : TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}
