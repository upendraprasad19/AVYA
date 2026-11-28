// Seed v30 (docs/plans/2026-11-28-media-two-new-two-retag.md): two rows were added (G0592, G0979), and E027 / E120 were
// retagged and gained their media keys; G0574 joined the core list and links to E027. A test that rebuilds a bundle shipped BEFORE v30 from the current asset applies
// this in its DIGEST expression only; its Hive box is still seeded from the unstripped rebuild, so "every other row is
// unchanged" stays true across the upgrade. The old values are typed here on purpose (not read from the retag records):
// the pinned digests of the older tests are what prove them.
const newRowIdsV30 = {'G0592', 'G0979'};
const _mediaKeys = {'media_slug', 'media_version', 'media_source'};
const retaggedBeforeV30 = <String, Map<String, Object>>{
  'E027': <String, Object>{
    'equipment_needed': ['barbell'],
    'equipment_tier': ['basic_gym', 'full_gym'],
    'coaching_cues': ['Wide stance', 'hip hinge', 'chest on pad', 'pull to lower chest'],
  },
  'E120': <String, Object>{
    'equipment_needed': ['barbell'],
    'equipment_tier': ['basic_gym', 'full_gym'],
    'gym_availability': 'standard_gym',
  },
};

/// [rows] as they shipped before v30: the two new rows are gone, E027 / E120 carry their old values (key order kept) and
/// no media keys, G0574 is off the core list and unlinked (it kept its media); every other row is the object given.
List<Map<String, dynamic>> beforeV30(Iterable<Map<String, dynamic>> rows) => [
      for (final r in rows)
        if (!newRowIdsV30.contains(r['id'])) _restore(r),
    ];

Map<String, dynamic> _restore(Map<String, dynamic> row) {
  if (row['id'] == 'G0574') {
    return {
      for (final e in row.entries)
        if (e.key != 'same_movement_as') e.key: e.key == 'core_levels' ? <String>[] : e.value,
    };
  }
  final old = retaggedBeforeV30[row['id']];
  if (old == null) return row;
  return {
    for (final e in row.entries)
      if (!_mediaKeys.contains(e.key)) e.key: old[e.key] ?? e.value,
  };
}
