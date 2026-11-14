// Generator Unit 1B-F2 (seed v27, OI-495, docs/plans/2026-11-12-generator-1bf2-overlay-copy.md) copied the core-list
// overlays into the rows' own fields (slot_pattern -> movement_pattern, slot_focus -> target_focus; 27 rows) and removed
// both overlay keys. The seed tests that rebuild an OLDER bundle from the current asset (v23 to v26, each pinning the
// sha256 of its rebuilt bundle) restore the v26 form of those rows with [withOverlaysV26].
//
// The v26 form: movement_pattern and target_focus take the record's `before` values in place, and the overlay keys come
// back at their measured positions, directly after `variant_family`, `slot_focus` before `slot_pattern` (all 27 rows on
// main 67b536e4). A wrong position changes the rebuilt bundle's digest, so the older tests' sha pins prove the helper.

import 'dart:convert';
import 'dart:io';

/// The 26 kept rows (the importer's overlay-copy record) plus N20, a source row whose overlay moved in
/// scripts/data/library_batch_c_source.json.
Map<String, Map<String, dynamic>> _beforeById() {
  final rec = jsonDecode(File('scripts/data/library_overlay_copy_v27.json').readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in (rec['rows'] as List).cast<Map<String, dynamic>>())
      e['id'] as String: Map<String, dynamic>.from(e['before'] as Map),
    'N20': {
      'movement_pattern': ['knee_dominant'],
      'slot_pattern': ['hip_dominant'],
    },
  };
}

final Map<String, Map<String, dynamic>> _before = _beforeById();

/// The ids whose row Unit 1B-F2 changed (27).
Set<String> get overlayRowIdsV27 => _before.keys.toSet();

/// [row] as the v26 bundle held it: unchanged unless it is one of the 27 rows.
Map<String, dynamic> withOverlaysV26(Map<String, dynamic> row) {
  final b = _before[row['id']];
  if (b == null) return row;
  final out = <String, dynamic>{};
  for (final e in row.entries) {
    if (e.key == 'movement_pattern' && b.containsKey('movement_pattern')) {
      out[e.key] = b['movement_pattern'];
    } else if (e.key == 'target_focus' && b.containsKey('target_focus')) {
      out[e.key] = b['target_focus'];
    } else {
      out[e.key] = e.value;
    }
    if (e.key == 'variant_family') {
      if (b.containsKey('slot_focus')) out['slot_focus'] = b['slot_focus'];
      if (b.containsKey('slot_pattern')) out['slot_pattern'] = b['slot_pattern'];
    }
  }
  if (!out.containsKey('slot_focus') && b.containsKey('slot_focus') ||
      !out.containsKey('slot_pattern') && b.containsKey('slot_pattern')) {
    throw StateError('${row['id']}: no variant_family key to place the overlay after');
  }
  return out;
}
