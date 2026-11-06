// Shared checks for the cumulative input of `build_library_media_v16.js --old-rows` (OI-443 data step, plan
// docs/plans/2026-11-01-library-old-rows-media.md, Task 1): used by test/contracts/library_media_table_test.dart.
//
// The 137 pairs are a RULE over the founder's picks, not a hand-typed list. The committed picks record
// (`docs/audit/library-old-rows-picks-2026-10-17.json`) holds every pick of the 2026-10-17 export; the committed input
// (`docs/audit/library-old-rows-media-input.json`) splits every pick whose row is in the library into exactly one bucket:
//   entries         applied (the builder reads only these)
//   held            the equipment check found a different kit or exercise; the founder decides
//   removal_slated  the row has the shape C2 is planned to delete (no core level, no variant family)
//   left_out        not a Wardroom file (the founder's own)
//   retag_waits     the founder decided a retag that needs a cloud seed migration first
// A parked bucket is tied to committed data, so a pick cannot be moved into one without a record that says so, and every
// pair is compared as id:gif, so a changed gif reddens. Parked is a SUBSET of the record, never equality: releasing a held
// pair into `entries` stays legal, but only with a recorded decision (P7): an entry whose id the equipment check held, or
// the founder decided to retag, carries `released_by`, a non-empty string naming the decision and its date. The builder
// ignores that key (it reads `id`, `gif` and `equipment_checked`).
library;

import 'library_media_table_checks.dart' show Json;

final RegExp _oldId = RegExp(r'^E\d+$');
const List<String> _parkedBuckets = ['held', 'removal_slated', 'left_out', 'retag_waits'];

/// The shape of a row C2 is planned to delete: an old row with no core level and no variant family.
bool isRemovalSlatedShape(Json row) => ((row['core_levels'] as List?) ?? const []).isEmpty && row['variant_family'] == null;

/// Every violation, each prefixed with its rule: (P1) every in-library pick is in exactly one bucket, (P2) every bucket pair is
/// a pick with the same gif, (P3) a parked bucket is a subset of its committed record, (P4) the removal-slated shape, (P5) the
/// entries are checked old rows of the library, (P6) the table's E rows are exactly the entries, (P7) an entry the equipment
/// check held or the founder decided to retag carries a `released_by` decision, and the record that names those ids is not empty.
List<String> oldRowsInputViolations({
  required Json input,
  required Json picks,
  required Json check,
  required List<dynamic> library,
  required Json table,
}) {
  final out = <String>[];
  final libById = <String, Json>{for (final r in library) (r as Json)['id'] as String: r};
  final pickGif = <String, String>{
    for (final p in (picks['picks'] as List)) (p as Json)['exercise_id'] as String: '${p['gif_id']}',
  };
  final entries = ((input['entries'] as List?) ?? const []).cast<Json>();
  List<Json> bucket(String name) => ((input[name] as List?) ?? const []).cast<Json>();

  final where = <String, List<String>>{};
  void place(String id, String name) => where.putIfAbsent(id, () => <String>[]).add(name);
  for (final e in entries) {
    place(e['id'] as String, 'entries');
  }
  for (final b in _parkedBuckets) {
    for (final e in bucket(b)) {
      place(e['id'] as String, b);
    }
  }

  // (P1) every pick on a row of the library is in exactly one bucket.
  for (final id in pickGif.keys) {
    if (!libById.containsKey(id)) continue; // a row Batch A retired
    final at = where[id] ?? const <String>[];
    if (at.isEmpty) out.add('(P1) pick $id is in no bucket');
    if (at.length > 1) out.add('(P1) pick $id is in ${at.join(' and ')}');
  }

  // (P2) every bucket pair is a pick with the same gif.
  void gifs(String name, List<Json> list) {
    for (final e in list) {
      final id = e['id'] as String;
      final want = pickGif[id];
      if (want == null) {
        out.add('(P2) $name $id has no pick in the picks record');
      } else if ('${e['gif']}' != want) {
        out.add('(P2) $name $id has gif ${e['gif']}, the pick says $want');
      }
    }
  }

  gifs('entries', entries);
  for (final b in _parkedBuckets) {
    gifs(b, bucket(b));
  }

  // (P3) a parked bucket is a subset of its committed record.
  final heldRecord = ((((check['held'] as Json?)?['rows']) as List?) ?? const []).cast<String>().toSet();
  final leftOutRecord = (((check['left_out'] as Json?) ?? const <String, dynamic>{}).keys).toSet();
  final retagRecord = (((picks['equipment_retag_decided'] as Json?) ?? const <String, dynamic>{}).keys).toSet();
  for (final e in bucket('held')) {
    if (!heldRecord.contains(e['id'])) out.add('(P3) held ${e['id']} is not in the equipment-check record held.rows');
  }
  for (final e in bucket('left_out')) {
    if (!leftOutRecord.contains(e['id'])) out.add('(P3) left_out ${e['id']} is not in the equipment-check record left_out');
  }
  for (final e in bucket('retag_waits')) {
    if (!retagRecord.contains(e['id'])) out.add('(P3) retag_waits ${e['id']} is not in the export equipment_retag_decided');
  }

  // (P4) removal_slated rows that are still in the library keep the shape (a row C2 keeps stops having it and forces a
  // decision); no entry has it.
  for (final e in bucket('removal_slated')) {
    final row = libById[e['id']];
    if (row != null && !isRemovalSlatedShape(row)) {
      out.add('(P4) removal_slated ${e['id']} no longer has the removal-slated shape: decide the pair');
    }
  }
  for (final e in entries) {
    final row = libById[e['id']];
    if (row != null && isRemovalSlatedShape(row)) out.add('(P4) entry ${e['id']} has the removal-slated shape');
  }

  // (P5) the entries are checked old rows of the library.
  for (final e in entries) {
    final id = e['id'] as String;
    if (!_oldId.hasMatch(id)) out.add('(P5) entry $id is not an E id');
    if (!libById.containsKey(id)) out.add('(P5) entry $id is not a row of the library');
    if (e['equipment_checked'] != true) out.add('(P5) entry $id has no equipment_checked: true');
  }

  // (P6) the table's E rows are exactly the entries, each slug starting with its gif.
  final rows = ((table['rows'] as Json?) ?? <String, dynamic>{}).cast<String, String>();
  final tableE = rows.keys.where(_oldId.hasMatch).toSet();
  final entryIds = {for (final e in entries) e['id'] as String};
  for (final id in entryIds.difference(tableE)) {
    out.add('(P6) entry $id has no E row in the table');
  }
  for (final id in tableE.difference(entryIds)) {
    out.add('(P6) the table maps $id but the input has no entry for it');
  }
  for (final e in entries) {
    final slug = rows[e['id']];
    if (slug != null && !slug.startsWith('${e['gif']}-')) {
      out.add('(P6) entry ${e['id']} gif ${e['gif']} but the table slug is $slug');
    }
  }

  // (P7) a pair the equipment check held (a different kit or a different exercise in the picture) or the founder decided to
  // retag enters `entries` only with a recorded decision. An empty record fails closed: the ids it names are the only thing
  // that makes this rule bite.
  Set<String> recordIds(String key) =>
      ((((check[key] as Json?)?['rows']) as Json?) ?? const <String, dynamic>{}).keys.toSet();
  final heldIds = {...recordIds('equipment_mismatch'), ...recordIds('movement_mismatch')};
  if (heldIds.isEmpty) {
    out.add('(P7) the equipment-check record lists no equipment_mismatch or movement_mismatch rows');
  }
  heldIds.addAll(retagRecord);
  for (final e in entries) {
    final id = e['id'] as String;
    final by = e['released_by'];
    if (heldIds.contains(id) && (by is! String || by.trim().isEmpty)) {
      out.add('(P7) entry $id was held or retag-decided and has no released_by');
    }
  }
  return out;
}
