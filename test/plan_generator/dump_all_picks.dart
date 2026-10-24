// ignore_for_file: avoid_print
//
// Batch A (library data repair, docs/plans/2026-10-22-library-data-repair.md) —
// dump EVERY persona's picks so a library data change can be diffed pick by pick.
//
// generate_baseline.dart writes aggregates plus a curated subset of plans; a data
// change needs the full set. Run it on the tree BEFORE the change and AFTER it,
// writing to two files, then diff them:
//
//   dart run test/plan_generator/dump_all_picks.dart <out.json>
//
// Deterministic (stable persona order, no timestamps), so an unchanged library
// produces byte-identical output. Covers the harness mirror only: generateAll()
// passes no previous-phase names, so cross-phase novelty (`_preferNovel`) is not
// exercised here.

import 'dart:convert';
import 'dart:io';
import 'generator_matrix.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: dart run test/plan_generator/dump_all_picks.dart <out.json>');
    exit(2);
  }
  final out = <String, List<Map<String, Object>>>{};
  for (final plan in generateAll()) {
    out[plan.persona.id] = [
      for (final day in plan.days)
        {
          'day': day.name,
          'picks': [
            for (final ex in day.exercises)
              '${ex.slot.targetMuscle}/${ex.slot.movementPattern}/'
                  '${ex.slot.exerciseType} => ${ex.name} [${ex.source}]',
          ],
        },
    ];
  }
  File(args.single)
      .writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
  print('Wrote ${out.length} personas to ${args.single}');
}
