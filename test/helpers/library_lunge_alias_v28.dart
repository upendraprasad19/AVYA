// test/helpers/library_lunge_alias_v28.dart
//
// OI-523 (library seed v28): G3470 Forward Lunge lost its name_aliases entry "Reverse Lunge". The older upgrade tests
// (v23-v27) rebuild the bundle an older install held and pin a sha256 of it; the helper puts the alias back so those
// digests stay what they were at the branch base. Key order is part of jsonEncode: the alias sits at index 41, after
// variant_family and before the media keys.
library;

/// The id of the one row whose alias seed v28 removed.
const String lungeAliasRowIdV28 = 'G3470';

/// The alias seed v28 removed from [lungeAliasRowIdV28].
const String lungeAliasV28 = 'Reverse Lunge';

/// [row] as the v27 bundle held it: unchanged unless it is G3470, which gets `name_aliases: ["Reverse Lunge"]` back at its
/// original key position (before `media_slug`, `media_version` and `media_source`, which are always last).
Map<String, dynamic> withLungeAliasV27(Map<String, dynamic> row) {
  if (row['id'] != lungeAliasRowIdV28) return row;
  if (row.containsKey('name_aliases')) return row;
  const mediaKeys = {'media_slug', 'media_version', 'media_source'};
  final out = <String, dynamic>{};
  var placed = false;
  for (final e in row.entries) {
    if (!placed && mediaKeys.contains(e.key)) {
      out['name_aliases'] = <String>[lungeAliasV28];
      placed = true;
    }
    out[e.key] = e.value;
  }
  if (!placed) out['name_aliases'] = <String>[lungeAliasV28];
  return out;
}
