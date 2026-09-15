import 'dart:async';

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:uuid/uuid.dart';

/// Bottom sheet for creating a custom exercise on the fly.
///
/// Writes the new exercise to `customBox` with `type: 'exercise'` and
/// `is_custom: true`, then invokes [onCreated] with the exercise map so
/// the caller can add it to the current workout or template immediately.
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

  bool get _showRepsField =>
      _loggingType == 'weight_reps' || _loggingType == 'bodyweight_reps';

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
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: AppColors.line2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'NEW EXERCISE',
            style: AppTypography.mono.copyWith(
              color: AppColors.accent,
              letterSpacing: 2.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Create custom',
            style: AppTypography.h2,
          ),
          const SizedBox(height: 14),

          // Name field
          _fieldLabel('Exercise Name'),
          const SizedBox(height: 6),
          _sharpTextField(
            controller: _nameCtrl,
            autofocus: true,
            hint: 'e.g. Band Pull-Apart',
          ),
          const SizedBox(height: 12),

          // Category + Logging Type row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fieldLabel('Category'),
                    const SizedBox(height: 6),
                    _sharpDropdown<String>(
                      value: _category,
                      items: _categories,
                      itemLabel: (c) => c,
                      onChanged: (v) =>
                          setState(() => _category = v ?? _category),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fieldLabel('Logging Type'),
                    const SizedBox(height: 6),
                    _sharpDropdown<String>(
                      value: _loggingType,
                      items: _loggingTypes.map((lt) => lt.$1).toList(),
                      itemLabel: (v) => _loggingTypes
                          .firstWhere((lt) => lt.$1 == v)
                          .$2,
                      onChanged: (v) =>
                          setState(() => _loggingType = v ?? _loggingType),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Sets + (Reps | Duration) row
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
                  style: AppTypography.bodySm.copyWith(
                    color: AppColors.textDim,
                  ),
                ),
              ),
              Switch(
                value: _shareWithCommunity,
                onChanged: (v) => setState(() => _shareWithCommunity = v),
                activeThumbColor: AppColors.accent,
                activeTrackColor:
                    AppColors.accent.withValues(alpha: 0.3),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Sharp 2-px SAVE slab
          WardButton(
            label: 'SAVE',
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: AppTypography.monoXs.copyWith(
        color: AppColors.textMute,
        letterSpacing: 1.8,
      ),
    );
  }

  Widget _sharpTextField({
    required TextEditingController controller,
    String? hint,
    bool autofocus = false,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgRaise,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppColors.line2, width: 2),
      ),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: keyboardType,
        style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
          hintText: hint,
          hintStyle: hint == null
              ? null
              : AppTypography.body.copyWith(color: AppColors.textMute),
        ),
      ),
    );
  }

  Widget _sharpDropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) itemLabel,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgRaise,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: AppColors.line2, width: 2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.card,
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
          items: items
              .map((c) => DropdownMenuItem<T>(
                    value: c,
                    child: Text(itemLabel(c)),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _numericField({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool numericOnly = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(label),
        const SizedBox(height: 6),
        _sharpTextField(
          controller: controller,
          hint: hint,
          keyboardType:
              numericOnly ? TextInputType.number : TextInputType.text,
        ),
      ],
    );
  }
}
