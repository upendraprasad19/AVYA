import 'dart:async';

import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:uuid/uuid.dart';

/// Bottom sheet for creating OR editing a custom exercise.
///
/// CREATE mode (default, `existing == null`): writes a new exercise to
/// `customBox` with `type: 'exercise'` and `is_custom: true`, then invokes
/// [onCreated] with the exercise map so the caller can add it to the current
/// workout or template immediately.
///
/// EDIT mode (`existing != null`, entry: tapping a chip in YOUR EXERCISES):
/// prefills every field from the existing row, LOCKS the name (renaming
/// would change the deterministic v5 UUID — id is derived from
/// `<user_id>|exercise|<lower(name)>` — and orphan the name-keyed log
/// history), and saves to the SAME Hive key through the canonical SoT
/// writer `WorkoutWriteService.upsertCustomExercise` (source
/// `editSheet`). `onCreated` is NOT invoked in edit mode.
///
/// `equipment_needed` and `approved_for_library` are NEVER re-stamped on
/// edit: the sheet has no equipment field (customs store `[]` by design),
/// and re-stamping `approved_for_library: false` would demote an approved
/// community submission and wipe an AI-authored row's real equipment
/// (custom-picker-fix round-2 P1-1).
class CreateCustomExerciseSheet extends StatefulWidget {
  final void Function(Map<String, dynamic> exercise)? onCreated;

  /// Edit mode: the existing custom-exercise map, including the `_key`
  /// field injected by `your_exercises_section._collectCustomExercises`.
  final Map<String, dynamic>? existing;

  const CreateCustomExerciseSheet({super.key, this.onCreated, this.existing});

  /// Muscle chips the UI can render (token → display label). Every token
  /// MUST be a key of `_muscleToGroup` in plan_engine/muscle_groups.dart —
  /// pinned by test/contracts/custom_muscle_vocabulary_test.dart. Tokens
  /// outside this list cannot be edited here, but edit mode PRESERVES any
  /// existing unmapped tokens on the row through save (never silently
  /// drops data the UI can't render).
  static const muscleOptions = <(String, String)>[
    ('chest', 'Chest'),
    ('upper chest', 'Upper Chest'),
    ('lats', 'Lats'),
    ('upper back', 'Upper Back'),
    ('lower back', 'Lower Back'),
    ('traps', 'Traps'),
    ('shoulders', 'Shoulders'),
    ('biceps', 'Biceps'),
    ('triceps', 'Triceps'),
    ('forearms', 'Forearms'),
    ('quads', 'Quads'),
    ('hamstrings', 'Hamstrings'),
    ('glutes', 'Glutes'),
    ('calves', 'Calves'),
    ('abs', 'Abs'),
    ('obliques', 'Obliques'),
  ];

  /// PURE — the union rule behind the edit/create muscle list, public so
  /// the edit-mode contract is behaviorally testable without widget pumps.
  static List<String> resolveMuscles(
    Iterable<String> selected,
    Iterable<String> unmapped,
  ) =>
      <String>{...unmapped, ...selected}.toList();

  /// PURE — the edit-mode payload handed to
  /// `WorkoutWriteService.upsertCustomExercise`, extracted so the
  /// write→read-same-key contract is behaviorally testable.
  ///
  /// Identity + cloud-state fields are PRESERVED from [existing], never
  /// re-stamped: `id` (deterministic v5), `name` (locked), `created_at`
  /// (the service back-fills only when absent — dropping it would reset a
  /// years-old row's creation date), `equipment_needed` (the sheet has no
  /// equipment field; re-stamping `[]` would wipe an AI-authored row's
  /// real requirement and re-open the L2-append capability hole), and
  /// `approved_for_library` (re-stamping `false` would demote an approved
  /// community submission and stop fresh installs from pulling it).
  /// `source`/`updated_at`/`_key` are dropped so the service re-stamps.
  static Map<String, dynamic> buildEditPayload(
    Map<String, dynamic> existing, {
    required String category,
    required String loggingType,
    required int defaultSets,
    String? defaultReps,
    int? defaultDurationSeconds,
    required List<String> primaryMuscles,
    required bool submittedToLibrary,
  }) {
    final updated = Map<String, dynamic>.from(existing)
      ..remove('_key')
      ..remove('source')
      ..remove('updated_at')
      // B-pass F2: drop the cloud-named twin. Restored rows carry
      // `default_duration_secs`; Hive-canonical writers use
      // `default_duration_seconds`. Preserving BOTH would fork the row —
      // train_provider's parser and exercise_selector's L2 read different
      // keys and would disagree after an edit. The edit CONVERGES the row
      // onto the canonical key.
      ..remove('default_duration_secs')
      ..['category'] = category
      ..['logging_type'] = loggingType
      ..['default_sets'] = defaultSets
      // Match the create shape: only store reps when rep-based, duration
      // when timed — a stale key from the old logging type must not linger.
      ..remove('default_reps')
      ..remove('default_duration_seconds')
      ..['primary_muscles'] = primaryMuscles
      ..['submitted_to_library'] = submittedToLibrary;
    if (defaultReps != null) updated['default_reps'] = defaultReps;
    if (defaultDurationSeconds != null) {
      updated['default_duration_seconds'] = defaultDurationSeconds;
    }
    return updated;
  }

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
  final Set<String> _selectedMuscles = <String>{};
  /// Edit mode only: existing `primary_muscles` tokens outside the UI
  /// vocabulary. They are unioned back into every save so editing can never
  /// silently drop them (round-2 P1-2).
  final List<String> _unmappedMuscleTokens = <String>[];

  bool get _isEdit => widget.existing != null;

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
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      // Null-safe prefill: `default_reps` is stored as a String (sheet +
      // AI writer both toString()), `default_sets` as int — never cast.
      _nameCtrl.text = (ex['name'] as String?) ?? '';
      _setsCtrl.text = (ex['default_sets'] ?? 3).toString();
      _repsCtrl.text = ex['default_reps']?.toString() ?? '10';
      // Restored rows carry the CLOUD column name (`default_duration_secs`);
      // UI/AI writers use the Hive-canonical `default_duration_seconds`.
      // Read both (B-pass F2), never cast.
      _durationCtrl.text = (ex['default_duration_secs'] ??
              ex['default_duration_seconds'])
          ?.toString() ??
          '30';
      _loggingType = (ex['logging_type'] as String?) ?? _loggingType;
      _category = (ex['category'] as String?) ?? _category;
      _shareWithCommunity = ex['submitted_to_library'] == true;
      final raw = ex['primary_muscles'];
      if (raw is List) {
        final vocabTokens = CreateCustomExerciseSheet.muscleOptions
            .map((o) => o.$1)
            .toSet();
        for (final m in raw) {
          final token = m.toString().toLowerCase().trim();
          if (token.isEmpty) continue;
          if (vocabTokens.contains(token)) {
            _selectedMuscles.add(token);
          } else {
            _unmappedMuscleTokens.add(token);
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _setsCtrl.dispose();
    _repsCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  /// Every muscle token the row will carry after this save: the selected
  /// chips UNION any pre-existing tokens the UI cannot render. Deselecting
  /// a chip drops it (user intent); unmapped tokens always ride along.
  List<String> get _resolvedMuscles => CreateCustomExerciseSheet.resolveMuscles(
      _selectedMuscles, _unmappedMuscleTokens);

  Future<void> _save() async {
    final isEdit = _isEdit;
    final name = isEdit
        ? (widget.existing!['name'] as String? ?? '')
        : _nameCtrl.text.trim();
    if (name.isEmpty) return;

    if (isEdit) {
      final key = widget.existing!['_key'] as String?;
      if (key == null || key.isEmpty) {
        // B-pass F5: a malformed entry point must not produce a dead SAVE
        // button. Unreachable via the sole current entry
        // (your_exercises_section injects _key), guarded with feedback.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update exercise. Try again.',
                style: AppTypography.bodyS),
            backgroundColor: AppColors.card,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final updated = CreateCustomExerciseSheet.buildEditPayload(
        widget.existing!,
        category: _category,
        loggingType: _loggingType,
        defaultSets: int.tryParse(_setsCtrl.text) ?? 3,
        defaultReps: _showRepsField
            ? (_repsCtrl.text.trim().isEmpty ? '10' : _repsCtrl.text.trim())
            : null,
        defaultDurationSeconds: _showDurationField
            ? (int.tryParse(_durationCtrl.text.trim()) ?? 30)
            : null,
        primaryMuscles: _resolvedMuscles,
        submittedToLibrary: _shareWithCommunity,
      );
      final res = await WorkoutWriteService.instance.upsertCustomExercise(
        key: key,
        exercise: updated,
        source: WriteSource.editSheet,
      );
      if (!mounted) return;
      if (res.success) {
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not update exercise. Try again.',
                style: AppTypography.bodySm),
            backgroundColor: AppColors.card,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

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
      'primary_muscles': _resolvedMuscles,
      'equipment_needed': <String>[],
      'is_custom': true,
      'type': 'exercise',
      'submitted_to_library': _shareWithCommunity,
      'approved_for_library': false,
    };

    unawaited(HiveService.instance.customBox.put(key, exercise));
    unawaited(SyncService.instance.syncCustomItemsNow());
    unawaited(SyncService.instance.pushSnapshot());
    Navigator.of(context).pop();
    widget.onCreated?.call(exercise);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = _isEdit;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
      child: SingleChildScrollView(
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
              isEdit ? 'EDIT EXERCISE' : 'NEW EXERCISE',
              style: AppTypography.mono.copyWith(
                color: AppColors.accent,
                letterSpacing: 2.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              isEdit ? 'Edit custom' : 'Create custom',
              style: AppTypography.h2,
            ),
            const SizedBox(height: 14),

            // Name field
            _fieldLabel('Exercise Name'),
            const SizedBox(height: 6),
            _sharpTextField(
              controller: _nameCtrl,
              autofocus: !isEdit,
              hint: 'e.g. Band Pull-Apart',
              // Name locked in edit mode: the deterministic v5 UUID is
              // derived from the lowercased name, so a rename would mint a
              // NEW id and orphan the name-keyed log history.
              readOnly: isEdit,
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

            // Target muscles (optional) — multi-select chips. Tokens are
            // library-canonical lowercase tokens; they re-arm the
            // plan-generator's custom-supplement path
            // (exercise_selector._eligibleCustomExercises), which skips
            // customs with empty `primary_muscles`.
            _fieldLabel('Target Muscles (optional)'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: CreateCustomExerciseSheet.muscleOptions
                  .map(_muscleChip)
                  .toList(),
            ),
            if (_unmappedMuscleTokens.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Keeping: ${_unmappedMuscleTokens.join(', ')}',
                style: AppTypography.bodyS.copyWith(
                  color: AppColors.textMute,
                ),
              ),
            ],
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
      ),
    );
  }

  Widget _muscleChip((String, String) option) {
    final selected = _selectedMuscles.contains(option.$1);
    return GestureDetector(
      onTap: () => setState(() {
        if (selected) {
          _selectedMuscles.remove(option.$1);
        } else {
          _selectedMuscles.add(option.$1);
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent.withValues(alpha: 0.12) : AppColors.bgRaise,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.line2,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          option.$2,
          style: AppTypography.bodyS.copyWith(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            color: selected ? AppColors.accent : AppColors.textPrimary,
          ),
        ),
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
    bool readOnly = false,
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
        readOnly: readOnly,
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
