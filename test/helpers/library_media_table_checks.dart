// Shared checks for the Batch M1 media table (plan R10, R1): used by the CI test
// test/contracts/library_media_table_test.dart and by the importer chain tests in
// test/scripts/library_media_importer_test.dart, so one function decides what a consistent
// table / map / library triple is.
library;

typedef Json = Map<String, dynamic>;

final RegExp _slugRe = RegExp(r'^\d{4}-[a-z0-9]+(-[a-z0-9]+)*$');
final RegExp _sha256Re = RegExp(r'^[0-9a-f]{64}$');

/// kebab(s): lower-case, each run outside [a-z0-9] becomes one '-', trim '-'. Permanent: object
/// names are immutable, so this never changes (the same function is in the builder).
String kebab(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

/// The map entry's `_gif` as text, empty when the entry has none.
String gifOfMap(Json map, String id) {
  final v = map[id];
  if (v is! Map) return '';
  final g = v['_gif'];
  return g == null ? '' : '$g';
}

/// Every violation of R10 (a)-(h) and R1 in the given data, each prefixed with its leg.
List<String> tableViolations(Json table, Json map, List<dynamic> library) {
  final out = <String>[];
  final meta = (table['_meta'] as Json?) ?? <String, dynamic>{};
  final files = (table['files'] as Json?) ?? <String, dynamic>{};
  final rows = ((table['rows'] as Json?) ?? <String, dynamic>{}).cast<String, String>();
  final libById = <String, Json>{for (final r in library) (r as Json)['id'] as String: r};
  final takenDown = ((meta['taken_down'] as List?) ?? const []).cast<String>();
  final bytesMax = meta['webp_bytes_max'];

  // R1: slug shape, and every rows slug has a files entry.
  for (final e in rows.entries) {
    if (!_slugRe.hasMatch(e.value)) out.add('(R1) ${e.key}: slug "${e.value}" does not match the slug regex');
    if (!files.containsKey(e.value)) out.add('(R1) ${e.key}: slug "${e.value}" has no files entry');
  }
  for (final slug in files.keys) {
    if (!_slugRe.hasMatch(slug)) out.add('(R1) files key "$slug" does not match the slug regex');
  }

  // (a) the 4-digit prefix of a rows slug is the row's gif number.
  for (final e in rows.entries) {
    final isOld = RegExp(r'^E\d+$').hasMatch(e.key);
    final want = isOld ? '${(files[e.value] as Json?)?['gif']}' : gifOfMap(map, e.key);
    final got = e.value.length >= 4 ? e.value.substring(0, 4) : e.value;
    if (want != got) out.add('(a) ${e.key}: slug ${e.value} starts $got, expected gif $want');
  }

  // (b) gif numbers across files are distinct.
  final seenGif = <String, String>{};
  for (final e in files.entries) {
    final g = '${(e.value as Json)['gif']}';
    final prior = seenGif[g];
    if (prior != null) out.add('(b) gif $g is claimed by both $prior and ${e.key}');
    seenGif[g] = e.key;
    if (!e.key.startsWith('$g-')) out.add('(b) files key ${e.key} does not start with its gif $g');
  }

  // (c) second half: every rows id is a (non-held) row of the committed library. A held row is not in it.
  for (final id in rows.keys) {
    if (!libById.containsKey(id)) out.add('(c) rows id $id is not a row of the committed library');
  }
  // A row whose map entry has no gif never gets a rows entry (the 12 shipped rows without an animation).
  for (final id in rows.keys) {
    if (!RegExp(r'^E\d+$').hasMatch(id) && gifOfMap(map, id).isEmpty) {
      out.add('(c) $id has no gif in the media map but has a rows entry');
    }
  }

  // (c) first half, library side: every rows id's library row carries exactly the table's slug, the file's last
  // media_version and media_source wardroom; every library row that carries any media key is a rows id and carries
  // all three.
  const mediaKeys = ['media_slug', 'media_version', 'media_source'];
  for (final e in rows.entries) {
    final row = libById[e.key];
    if (row == null) continue; // reported above
    final versions = (files[e.value] as Json?)?['versions'];
    final lastVersion = (versions is List && versions.isNotEmpty) ? (versions.last as Json)['media_version'] : null;
    if (row['media_slug'] != e.value) out.add('(c) ${e.key}: library media_slug ${row['media_slug']} != table slug ${e.value}');
    if (row['media_version'] != lastVersion) {
      out.add('(c) ${e.key}: library media_version ${row['media_version']} != table version $lastVersion');
    }
    if (row['media_source'] != 'wardroom') out.add('(c) ${e.key}: library media_source ${row['media_source']} is not wardroom');
  }
  for (final r in library) {
    final row = r as Json;
    // A partial triple on a mapped row fails the per-key checks above; on an unmapped row it fails here.
    if (mediaKeys.any(row.containsKey) && !rows.containsKey(row['id'])) {
      out.add('(c) library row ${row['id']} carries media keys but the table does not map it');
    }
  }

  // (d) first half: every file is within the size cap the bucket will enforce.
  if (bytesMax is! int || bytesMax <= 0) out.add('(d) _meta.webp_bytes_max is not a positive integer');
  for (final e in files.entries) {
    final b = (e.value as Json)['webp_bytes'];
    if (b is! int || b <= 0) {
      out.add('(d) ${e.key}: webp_bytes is not a positive integer');
    } else if (bytesMax is int && b > bytesMax) {
      out.add('(d) ${e.key}: webp_bytes $b is over webp_bytes_max $bytesMax');
    }
  }

  // (e) completeness: every gif-set library row with a map gif (minus taken-down gifs) has a rows entry.
  final takenDownGifs = {for (final s in takenDown) if (s.length >= 4) s.substring(0, 4)};
  final expected = <String>{
    for (final r in library)
      if ((r as Json)['source'] == 'exercise-gif-set' &&
          gifOfMap(map, r['id'] as String).isNotEmpty &&
          !takenDownGifs.contains(gifOfMap(map, r['id'] as String)))
        r['id'] as String,
  };
  final have = {for (final id in rows.keys) if (!RegExp(r'^E\d+$').hasMatch(id)) id};
  for (final id in expected.difference(have)) {
    out.add('(e) library row $id has a map gif but no rows entry (it would ship without media)');
  }
  for (final id in have.difference(expected)) {
    out.add('(e) rows id $id is not a gif-set library row with a map gif');
  }

  // (f) E ids exist in rows exactly when _meta.old_rows is not null, and old_rows.entries counts them.
  final eIds = rows.keys.where((k) => RegExp(r'^E\d+$').hasMatch(k)).toList();
  final oldRows = meta['old_rows'];
  if (oldRows == null) {
    if (eIds.isNotEmpty) out.add('(f) E rows ${eIds.join(',')} exist but _meta.old_rows is null');
  } else {
    final o = oldRows as Json;
    if (eIds.isEmpty) out.add('(f) _meta.old_rows is set but no E row exists');
    if (o['entries'] != eIds.length) out.add('(f) _meta.old_rows.entries ${o['entries']} != ${eIds.length} E rows');
    if (o['sha256'] is! String || !_sha256Re.hasMatch(o['sha256'] as String)) {
      out.add('(f) _meta.old_rows.sha256 is not a sha256');
    }
    if (o['omitted'] is! int) out.add('(f) _meta.old_rows.omitted is not an integer');
  }

  // (g) the name part of a slug is kebab(ledger_id after its first five characters).
  for (final e in files.entries) {
    final f = e.value as Json;
    final lid = f['ledger_id'];
    if (lid is! String || lid.length < 6) {
      out.add('(g) ${e.key}: ledger_id is missing');
      continue;
    }
    final want = '${f['gif']}-${kebab(lid.substring(5))}';
    if (e.key != want) out.add('(g) ${e.key}: slug differs from the ledger id (expected $want)');
  }

  // (h) statuses, taken_down, versions.
  final used = rows.values.toSet();
  for (final e in files.entries) {
    final f = e.value as Json;
    final st = f['status'];
    if (st == 'active' && !used.contains(e.key)) out.add('(h) ${e.key} is active but no row maps to it');
    if (st == 'unmapped' && used.contains(e.key)) out.add('(h) ${e.key} is unmapped but a row maps to it');
    if (st == 'taken_down' && used.contains(e.key)) out.add('(h) ${e.key} is taken_down but a row maps to it');
    if (st != 'active' && st != 'unmapped' && st != 'taken_down') out.add('(h) ${e.key}: unknown status "$st"');
    final vs = f['versions'];
    if (vs is! List || vs.length != 1) {
      out.add('(h) ${e.key}: versions must hold exactly one entry in M1');
      continue;
    }
    final v = vs.first as Json;
    if (v['media_version'] != 1) out.add('(h) ${e.key}: media_version is ${v['media_version']}, expected 1');
    if (v['webp_sha256'] != f['webp_sha256'] || v['webp_bytes'] != f['webp_bytes']) {
      out.add('(h) ${e.key}: versions[0] sha or bytes differ from the top-level webp_*');
    }
    final file = v['file'];
    if (file is! String || !file.startsWith('webp-720/') || !file.endsWith('.webp') || file.contains('..')) {
      out.add('(h) ${e.key}: versions[0].file "$file" must start webp-720/, end .webp and hold no ..');
    }
    // Shape only: the real files are checked by the builder and the live verify.
    for (final k in ['webp_sha256', 'thumb_sha256', 'source_gif_sha256']) {
      if (f[k] is! String || !_sha256Re.hasMatch(f[k] as String)) out.add('(h) ${e.key}: $k is not a sha256');
    }
    if (f['frames'] is! int || (f['frames'] as int) < 1) out.add('(h) ${e.key}: frames is not a positive integer');
    if (f['thumb_bytes'] is! int || (f['thumb_bytes'] as int) < 1) out.add('(h) ${e.key}: thumb_bytes is not a positive integer');
  }
  final tdStatus = {
    for (final e in files.entries)
      if ((e.value as Json)['status'] == 'taken_down') e.key,
  };
  if (!(tdStatus.length == takenDown.toSet().length && tdStatus.containsAll(takenDown))) {
    out.add('(h) the files with status taken_down (${tdStatus.join(',')}) differ from _meta.taken_down (${takenDown.join(',')})');
  }
  return out;
}

