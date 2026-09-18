// B1 (ai-coach-ux-tool-integrity spec 2026-09-18) — structured capture for
// "Log my workout". Replaces the /LOG text-prefill that made the model
// interrogate the user for exercises/sets/reps.
//
// Reads today's scheduled exercises, prefills sets/reps/weight from the plan
// prescription (suggested_weight), and on confirm submits one `log_set`
// ToolIntent per exercise through PendingToolIntentsNotifier — the SAME
// confirm plumbing the model's tool calls use, so completion derivation
// (_maybeCompleteScheduledDay), provider invalidation and sync all run
// through ToolDispatcher.execute unchanged. Zero Gemini tokens:
// deterministic, works offline.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/hive_service.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/ist_date.dart';
import '../../../shared/widgets/wardroom/ward_button.dart';
import '../models/tool_intent.dart';
import '../providers/pending_tool_intents_provider.dart';

/// One capture row: a scheduled exercise plus the controllers for its sets.
class _ExerciseCapture {
  final String exerciseId;
  final String name;
  final TextEditingController sets;
  final TextEditingController reps;
  final TextEditingController weight;

  _ExerciseCapture({
    required this.exerciseId,
    required this.name,
    required String? planSets,
    required String? planReps,
    required String? planWeight,
  })  : sets = TextEditingController(text: planSets ?? ''),
        reps = TextEditingController(text: planReps ?? ''),
        weight = TextEditingController(text: planWeight ?? '');

  bool get isComplete =>
      sets.text.trim().isNotEmpty &&
      reps.text.trim().isNotEmpty &&
      weight.text.trim().isNotEmpty;

  void dispose() {
    sets.dispose();
    reps.dispose();
    weight.dispose();
  }
}

/// Shows the log-workout capture sheet. [ref] comes from the coach screen's
/// ConsumerState (the composer), so intents land in the SAME
/// PendingToolIntentsNotifier the chat thread renders.
Future<void> showLogWorkoutSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const LogWorkoutSheet(),
  );
}

class LogWorkoutSheet extends ConsumerStatefulWidget {
  const LogWorkoutSheet({super.key});

  @override
  ConsumerState<LogWorkoutSheet> createState() => _LogWorkoutSheetState();
}

class _LogWorkoutSheetState extends ConsumerState<LogWorkoutSheet> {
  List<_ExerciseCapture> _captures = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final todayKey = istDateStr(nowWall());
    final raw = HiveService.instance.workoutBox.get('schedule_$todayKey');
    if (raw is! Map) {
      setState(() => _loaded = true);
      return;
    }
    final row = Map<String, dynamic>.from(raw);
    final status = row['status']?.toString();
    // Terminal/completed rows are not loggable from here (a 'moved' row's
    // workout lives on another date; a completed day is already done).
    if (status != null && status != 'planned') {
      setState(() => _loaded = true);
      return;
    }
    final exercisesRaw = row['exercises'];
    final exercises = exercisesRaw is List ? exercisesRaw : const [];
    final captures = <_ExerciseCapture>[];
    for (final ex in exercises) {
      if (ex is! Map) continue;
      final m = Map<String, dynamic>.from(ex);
      final name = (m['exercise_name'] as String?) ?? '';
      if (name.isEmpty) continue;
      String? numStr(num? v) => v?.toString();
      captures.add(_ExerciseCapture(
        exerciseId: (m['exercise_id'] as String?) ?? name,
        name: name,
        planSets: numStr(m['sets'] as num?),
        planReps: numStr(m['reps'] as num?),
        planWeight: numStr(m['suggested_weight'] as num?),
      ));
    }
    setState(() {
      _captures = captures;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    for (final c in _captures) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _allComplete =>
      _captures.isNotEmpty && _captures.every((c) => c.isComplete);

  void _confirm() {
    if (!_allComplete) return;
    final dateKey = istDateStr(nowWall());
    final now = DateTime.now();
    final intents = <ToolIntent>[];
    for (var i = 0; i < _captures.length; i++) {
      final c = _captures[i];
      intents.add(ToolIntent(
        id: 'sheet_log_${now.millisecondsSinceEpoch}_$i',
        type: 'log_set',
        payload: {
          'exerciseId': c.exerciseId,
          'weightKg': double.tryParse(c.weight.text.trim()) ?? 0.0,
          'reps': int.tryParse(c.reps.text.trim()) ?? 0,
          'sets': int.tryParse(c.sets.text.trim()) ?? 1,
          'date': dateKey,
        },
        confirmationClass: ConfirmationClass.trivial,
        previewSummary:
            'Log ${c.name} — ${c.sets.text.trim()}×${c.reps.text.trim()} '
            '@ ${c.weight.text.trim()}kg',
        createdAt: now,
      ));
    }
    ref.read(pendingToolIntentsProvider.notifier).addIntents(intents);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          14,
          AppSpacing.gutter,
          18 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: !_loaded
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()))
            : _captures.isEmpty
                ? _buildEmpty()
                : _buildForm(context),
      ),
    );
  }

  Widget _buildEmpty() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text(
          'NO WORKOUT SCHEDULED TODAY',
          style: AppTypography.mono.copyWith(
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.w800,
            color: AppColors.accent,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Log anything you did from the Train screen — or ask the coach for '
          'a travel workout.',
          style: AppTypography.bodyS.copyWith(color: AppColors.textMute),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        WardButton(
          label: 'CLOSE',
          variant: WardButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        const SizedBox(height: 12),
        Text(
          'LOG TODAY\'S WORKOUT',
          style: AppTypography.mono.copyWith(
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.w800,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Prefilled from your plan. Confirm logs every exercise.',
          style: AppTypography.bodyS.copyWith(color: AppColors.textMute),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _captures.length,
            separatorBuilder: (ctx2, i2) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) => _buildRow(_captures[i]),
          ),
        ),
        const SizedBox(height: 14),
        WardButton(
          label: 'LOG WORKOUT',
          onPressed: _allComplete ? _confirm : null,
        ),
      ],
    );
  }

  Widget _buildRow(_ExerciseCapture c) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.name,
              style: AppTypography.body
                  .copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              _field(c, 'SETS', c.sets, 64),
              const SizedBox(width: 8),
              _field(c, 'REPS', c.reps, 64),
              const SizedBox(width: 8),
              Expanded(child: _field(c, 'KG', c.weight, null)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(
      _ExerciseCapture c, String label, TextEditingController ctrl,
      double? width) {
    final field = TextField(
      controller: ctrl,
      onChanged: (_) => setState(() {}),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: AppTypography.body.copyWith(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: AppTypography.bodyS
            .copyWith(fontSize: 10, color: AppColors.textMute),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.line2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
    );
    if (width == null) return field;
    return SizedBox(width: width, child: field);
  }
}
