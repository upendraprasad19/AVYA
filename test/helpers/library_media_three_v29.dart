// Seed v29 (docs/plans/2026-11-26-media-three-adds.md): E051, E109 and E264 gained their three media keys. A test that
// rebuilds a bundle shipped BEFORE v29 from the current asset removes them in its DIGEST expression only; its Hive box is
// still seeded from the unstripped rebuild, so "every other row is unchanged" stays true across the upgrade.
const mediaThreeRowIdsV29 = {'E051', 'E109', 'E264'};
const _mediaKeys = ['media_slug', 'media_version', 'media_source'];

/// [row] as it shipped before v29: a copy without the media keys for the three rows, every other row as given.
Map<String, dynamic> withoutMediaV29(Map<String, dynamic> row) => mediaThreeRowIdsV29.contains(row['id'])
    ? {
        for (final e in row.entries)
          if (!_mediaKeys.contains(e.key)) e.key: e.value
      }
    : row;
