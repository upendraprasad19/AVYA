// ignore_for_file: avoid_print
import 'dart:io';
import 'v4_diagnostic/library_loader.dart';
import 'v4_diagnostic/cascade_tracer.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/split_resolver.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/volume_filter.dart';

void main() {
  final library = LibraryLoader.loadFromAssets();
  final buf = StringBuffer();

  buf.writeln('# Sample Workout Plans — All Experience × Day Splits');
  buf.writeln('Generated: ${DateTime.now().toIso8601String().split("T").first}');
  buf.writeln();

  const experiences = ['beginner', 'intermediate', 'advanced'];
  const daySplits = [3, 4, 5, 6];
  const goal = 'build_muscle';
  const equipment = 'full_gym';
  const phase = 1;

  for (final exp in experiences) {
    for (final days in daySplits) {
      buf.writeln('---');
      buf.writeln('## ${exp.toUpperCase()} / $days days / $goal / $equipment');
      buf.writeln();

      // Get split
      final splitDays = SplitResolver.selectV4(
        goal, days,
        experienceLevel: exp,
      );

      // Volume filter
      final filteredDays = VolumeFilter.filterDays(
        splitDays,
        experience: exp,
        weekCharacter: 'baseline',
      );

      final pickedNames = <String>{};

      for (int d = 0; d < filteredDays.length; d++) {
        final day = filteredDays[d];
        buf.writeln('### Day ${d + 1}: ${day.name} (${day.focus})');
        buf.writeln('| # | Slot | Exercise Picked | Source |');
        buf.writeln('|---|------|----------------|--------|');

        final slotsA = day.slotsA;
        for (int s = 0; s < slotsA.length; s++) {
          final slot = slotsA[s];
          final trace = CascadeTracer.trace(
            library,
            slot: slot,
            equipmentTier: equipment,
            effectiveExp: exp,
            phase: phase,
            injuries: const [],
            pickedNames: pickedNames,
          );

          final pick = trace.finalPick;
          final exerciseName = pick?.name ?? '(none)';
          final source = pick?.source.name ?? 'none';

          if (pick != null) pickedNames.add(pick.name);

          buf.writeln('| ${s + 1} | ${slot.targetMuscle}/${slot.movementPattern}/${slot.exerciseType}/P${slot.priority} | **$exerciseName** | $source |');
        }
        buf.writeln();
      }

      // Summary
      buf.writeln('**Total exercises: ${pickedNames.length}** across $days days');
      buf.writeln();
    }
  }

  final outFile = File('test/plan_generator/sample_plans_output.md');
  outFile.writeAsStringSync(buf.toString());
  print('Written to ${outFile.path}');
  print('Total length: ${buf.length} chars');
}
