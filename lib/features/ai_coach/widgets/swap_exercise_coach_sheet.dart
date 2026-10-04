// B2 (ai-coach-ux-tool-integrity spec 2026-09-18) — structured capture for
// "Swap exercise". Replaces the /SWAP text-prefill ("Swap [exercise] for ")
// that sent placeholder text to the model and got back "I need the specific
// exercise IDs".
//
// Picker 1: today's scheduled exercises. Picker 2: library + custom
// substitutes filtered by the SAME equipment-capability predicate the swap
// service enforces (EquipmentCapability.canOfferInPicker) — so every option
// offered here is one swapExerciseInDay will accept. Confirm submits ONE
// `swap_exercise` ToolIntent with confirmationClass reviewable — the
// existing reviewable preview card renders the diff and runs the canonical
// dispatcher path. Zero Gemini tokens.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/hive_service.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/theme/typography.dart';
import '../../../core/utils/ist_date.dart';
import '../../../shared/repositories/plan_engine/equipment_capability.dart';
import '../../../shared/repositories/plan_engine/training_history_analyzer.dart';
import '../../../shared/repositories/exercise_repository.dart';
import '../../../shared/widgets/wardroom/ward_button.dart';
import '../models/tool_intent.dart';
import '../providers/pending_tool_intents_provider.dart';

/// A flat exercise option for the substitute picker.
class _SwapOption {
  final String id;
  final String name;
  final bool isCustom;
  const _SwapOption({required this.id, required this.name, required this.isCustom});
}

Future<void> showCoachSwapSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const CoachSwapSheet(),
  );
}

class CoachSwapSheet extends ConsumerStatefulWidget {
  const CoachSwapSheet({super.key});

  @override
  ConsumerState<CoachSwapSheet> createState() => _CoachSwapSheetState();
}

class _CoachSwapSheetState extends ConsumerState<CoachSwapSheet> {
  List<({String id, String name})> _today = const [];
  bool _loaded = false;
  /// Review round 1 (e8f4a3) finding 5 — honest empty-state message when a
  /// schedule row exists but is not swappable (completed / terminal).
  String? _unavailableMessage;
  String? _selectedFrom;
  _SwapOption? _selectedTo;
  // e8f4a3 B-pass P3c — double-tap latch (see log_workout_sheet.dart): the
  // SWAP button stays live until the route pops and intent ids embed
  // millisecondsSinceEpoch, so a fast second tap submits a duplicate
  // swap_exercise intent that dedup cannot catch (and double-dispatch fails
  // noisily via ConcurrentEditException). First confirm wins.
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _loadToday();
  }

  void _loadToday() {
    final todayKey = istDateStr(nowWall());
    final raw = HiveService.instance.workoutBox.get('schedule_$todayKey');
    final items = <({String id, String name})>[];
    String? unswappable;
    if (raw is Map) {
      final row = Map<String, dynamic>.from(raw);
      final status = row['status']?.toString();
      // Review round 1 (e8f4a3) finding 5 — SAME raw+guard pattern as
      // log_workout_sheet.dart: a row whose status is terminal or completed
      // is not swappable from here. A 'moved' row's exercises live on another
      // date (picking one submits a swap against a day that no longer
      // holds them); a completed day is done. Give an HONEST message
      // instead of a dead-end picker.
      // Review round 2 (e8f4a3 B2): `paused` PASSES — the dispatcher
      // explicitly keeps paused days swappable (paused = pending, not
      // terminal; tool_dispatcher.dart _executeSwapExercise guards
      // TERMINAL rows + completed only, and paused days execute fine).
      if (status != null && status != 'planned' && status != 'paused') {
        unswappable = status == 'completed'
            ? 'Today\'s workout is already done — edit it from the '
                'Train screen.'
            : 'No swappable workout scheduled today.';
      }
    }
    if (unswappable == null && raw is Map) {
      final exercisesRaw = raw['exercises'];
      final exercises = exercisesRaw is List ? exercisesRaw : const [];
      for (final ex in exercises) {
        if (ex is! Map) continue;
        final m = Map<String, dynamic>.from(ex);
        final name = (m['exercise_name'] as String?) ?? '';
        if (name.isEmpty) continue;
        items.add((
          id: (m['exercise_id'] as String?) ?? name,
          name: name,
        ));
      }
    }
    setState(() {
      _today = items;
      _unavailableMessage = unswappable;
      _loaded = true;
    });
  }

  /// Library + custom exercises the swap service would ACCEPT for this user
  /// (same predicate swap_service.dart enforces on execute).
  List<_SwapOption> _substitutesFor(String fromId) {
    final capability = TrainingHistoryAnalyzer.resolveCapabilityFromProfile();
    final options = <_SwapOption>[];
    void addRow(Map<String, dynamic> m, bool isCustom, String fallbackId) {
      final name = (m['name'] as String?) ?? '';
      if (name.isEmpty) return;
      final id = (m['id'] as String?) ?? fallbackId;
      if (id == fromId || name == fromId) return;
      final equipment = m['equipment_needed']?.toString();
      if (capability != null &&
          equipment != null &&
          !EquipmentCapability.canOfferInPicker(equipment, capability,
              isCustom: isCustom)) {
        return;
      }
      options.add(_SwapOption(id: id, name: name, isCustom: isCustom));
    }

    for (final row in ExerciseRepository.instance.getAll()) {
      addRow(Map<String, dynamic>.from(row), false,
          (row['id'] as String?) ?? (row['exercise_id'] as String?) ?? '');
    }
    for (final row in ExerciseRepository.instance.getCustomExercises()) {
      addRow(Map<String, dynamic>.from(row), true,
          (row['id'] as String?) ?? '');
    }
    return options;
  }

  void _confirm() {
    if (_submitted) return; // e8f4a3 B-pass P3c double-tap latch
    final from = _selectedFrom;
    final to = _selectedTo;
    if (from == null || to == null) return;
    _submitted = true;
    final fromName = _today.firstWhere((t) => t.id == from,
        orElse: () => (id: from, name: from)).name;
    ref.read(pendingToolIntentsProvider.notifier).addIntents([
      ToolIntent(
        id: 'sheet_swap_${DateTime.now().millisecondsSinceEpoch}',
        type: 'swap_exercise',
        payload: {
          'exerciseId': from,
          'newExerciseId': to.id,
          'reason': 'Chosen from the Compass swap tool',
        },
        confirmationClass: ConfirmationClass.reviewable,
        previewSummary: 'Swap $fromName for ${to.name}',
        createdAt: DateTime.now(),
      ),
    ]);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpacing.gutter, 14, AppSpacing.gutter,
            18 + MediaQuery.of(context).viewInsets.bottom),
        child: !_loaded
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()))
            : _today.isEmpty
                ? _buildEmpty()                : _buildBody(),
      ),
    );
  }

  Widget _header(String title, String? subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
        Text(title,
            style: AppTypography.mono.copyWith(
              fontSize: 11,
              letterSpacing: 2,
              fontWeight: FontWeight.w800,
              color: AppColors.accent,
            )),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle,
              style: AppTypography.bodyS.copyWith(color: AppColors.textMute)),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildEmpty() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header('SWAP EXERCISE', null),
        const SizedBox(height: 12),
        Text(
          // Review round 1 (e8f4a3) finding 5 — honest per-state message
          // (completed day → Train-screen pointer; terminal → plain
          // no-swap). Default (no row / empty plan) keeps the original copy.
          _unavailableMessage ??
              'No workout scheduled today — there is nothing to swap. Ask '
                  'the coach to plan a session first.',
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

  Widget _buildBody() {
    final pickingFrom = _selectedFrom == null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pickingFrom
            ? _header('SWAP WHICH EXERCISE?', 'Tap the one to replace.')
            : _header('REPLACE WITH…',
                'Only exercises your equipment allows are listed.'),
        Flexible(
          child: pickingFrom
              ? ListView.separated(
                  shrinkWrap: true,
                  itemCount: _today.length,
                  separatorBuilder: (ctx2, i2) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) => _tile(
                    label: _today[i].name,
                    selected: false,
                    onTap: () => setState(() => _selectedFrom = _today[i].id),
                  ),
                )
              : Builder(builder: (ctx) {
                  final options = _substitutesFor(_selectedFrom!);
                  if (options.isEmpty) {
                    return Text(
                      'No substitutes available with your current equipment. '
                      'Add equipment under Profile, or ask the coach instead.',
                      style: AppTypography.bodyS
                          .copyWith(color: AppColors.textMute),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (ctx2, i2) => const SizedBox(height: 6),
                    itemBuilder: (ctx, i) => _tile(
                      label: options[i].name +
                          (options[i].isCustom ? '  ·CUSTOM' : ''),
                      selected: _selectedTo?.id == options[i].id,
                      onTap: () =>
                          setState(() => _selectedTo = options[i]),
                    ),
                  );
                }),
        ),
        const SizedBox(height: 14),
        if (!pickingFrom) ...[
          WardButton(
            label: 'SWAP',
            onPressed: _selectedTo == null ? null : _confirm,
          ),
          const SizedBox(height: 8),
        ],
        WardButton(
          label: pickingFrom ? 'CLOSE' : 'BACK',
          variant: WardButtonVariant.outline,
          onPressed: () {
            if (pickingFrom) {
              Navigator.of(context).pop();
            } else {
              setState(() {
                _selectedFrom = null;
                _selectedTo = null;
              });
            }
          },
        ),
      ],
    );
  }

  Widget _tile({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.input : AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.line2,
          ),
        ),
        child: Text(
          selected ? '✓  $label' : label,
          style: AppTypography.body.copyWith(
            fontSize: 13,
            color: selected ? AppColors.accent : AppColors.textDim,
          ),
        ),
      ),
    );
  }
}
