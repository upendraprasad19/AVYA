import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart'
    show PlanGenerator;
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/volume_filter.dart';

import 'cascade_tracer.dart';
import 'combos.dart';

class DiagnosticMarkdownWriter {
  static String renderCombo(
    DiagnosticCombo combo,
    List<Map<String, dynamic>> library,
  ) {
    final buf = StringBuffer();
    final effExp = PlanGenerator.effectiveLevel(combo.experience, combo.phase);

    buf.writeln('## Combo: ${combo.label}');
    buf.writeln();
    buf.writeln('**INPUT:**');
    buf.writeln('- goal=${combo.goal}');
    buf.writeln('- equipment=${combo.equipment}');
    buf.writeln('- daysPerWeek=${combo.daysPerWeek}');
    buf.writeln('- experience=${combo.experience}');
    buf.writeln('- phase=${combo.phase}');
    buf.writeln('- sessionDuration=${combo.sessionDuration}');
    buf.writeln('- injuries=${combo.injuries}');
    buf.writeln();
    buf.writeln('**EFFECTIVE:**');
    buf.writeln('- effectiveExp=$effExp');
    buf.writeln('- equipmentTier=${combo.equipment}');
    buf.writeln();

    // Run SplitResolver — pure Dart, no Hive
    final splitDays = SplitResolver.selectV4(
      combo.goal,
      combo.daysPerWeek,
      experienceLevel: effExp,
    );

    for (final weekChar in combo.weekCharacters) {
      buf.writeln('### Week $weekChar');
      buf.writeln();

      // Apply VolumeFilter
      final filteredDays = VolumeFilter.filterDays(
        splitDays,
        experience: effExp,
        weekCharacter: weekChar,
      );

      for (var dayIdx = 0; dayIdx < splitDays.length; dayIdx++) {
        final rawDay = splitDays[dayIdx];
        final filteredDay = filteredDays[dayIdx];
        _renderDay(
          buf,
          library,
          rawDay: rawDay,
          filteredDay: filteredDay,
          equipmentTier: combo.equipment,
          effectiveExp: effExp,
          phase: combo.phase,
          injuries: combo.injuries,
        );
      }
    }
    buf.writeln('---');
    buf.writeln();
    return buf.toString();
  }

  static void _renderDay(
    StringBuffer buf,
    List<Map<String, dynamic>> library, {
    required MuscleSlotDay rawDay,
    required MuscleSlotDay filteredDay,
    required String equipmentTier,
    required String effectiveExp,
    required int phase,
    required List<String> injuries,
  }) {
    buf.writeln('#### Day "${rawDay.name}" (${rawDay.dayType}, ${rawDay.intensity})');
    buf.writeln();
    for (final variant in ['A', 'B']) {
      final rawSlots = variant == 'A' ? rawDay.slotsA : (rawDay.slotsB ?? rawDay.slotsA);
      final fSlots = variant == 'A' ? filteredDay.slotsA : (filteredDay.slotsB ?? filteredDay.slotsA);

      buf.writeln('**Variant $variant**');
      buf.writeln();
      buf.writeln('- PRE-VolumeFilter: ${rawSlots.length} slots — '
          '${rawSlots.map((s) => _slotLabel(s)).join(", ")}');
      buf.writeln('- POST-VolumeFilter: ${fSlots.length} slots — '
          '${fSlots.map((s) => _slotLabel(s)).join(", ")}');
      final droppedLabels = rawSlots
          .where((s) => !fSlots.any((f) => _slotLabel(f) == _slotLabel(s)))
          .map((s) => _slotLabel(s))
          .toList();
      if (droppedLabels.isNotEmpty) {
        buf.writeln('  - ⚠️ Dropped by VolumeFilter: ${droppedLabels.join(", ")}');
      }
      buf.writeln();

      // Run cascade for each surviving slot
      final pickedNames = <String>{};
      for (final slot in fSlots) {
        buf.writeln('- **Slot:** ${_slotLabel(slot)}');
        buf.writeln('  - excludeNames-in (${pickedNames.length}): '
            '${pickedNames.isEmpty ? "{}" : pickedNames.join(", ")}');
        final trace = CascadeTracer.trace(
          library,
          slot: slot,
          equipmentTier: equipmentTier,
          effectiveExp: effectiveExp,
          phase: phase,
          injuries: injuries,
          pickedNames: pickedNames,
        );
        for (final a in trace.attempts) {
          final sample = a.sampleNames.isEmpty
              ? ''
              : ' → [${a.sampleNames.join(", ")}]';
          buf.writeln('  - A${a.number} (${a.signature}): ${a.resultCount}$sample');
        }
        if (trace.finalPick != null) {
          final flag = trace.finalPick!.source == CascadePickSource.universalPoolPlaceholder
              ? ' ⚠️ PLACEHOLDER (not in library)'
              : trace.finalPick!.source == CascadePickSource.universalPool
                  ? ' ⚠️ FROM UNIVERSAL POOL'
                  : '';
          buf.writeln('  - **PICK:** ${trace.finalPick!.name} '
              '(${trace.finalPick!.source.name})$flag');
          pickedNames.add(trace.finalPick!.name);
        } else {
          buf.writeln('  - **PICK:** (none — cascade exhausted) ⚠️');
        }
        buf.writeln();
      }
    }
  }

  static String _slotLabel(MuscleSlot s) {
    final sf = s.subFocus != null ? '/${s.subFocus}' : '';
    return '${s.targetMuscle}$sf/${s.movementPattern}/${s.exerciseType}/P${s.priority}';
  }
}
