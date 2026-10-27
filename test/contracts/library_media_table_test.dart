// Batch M1 (plan R10, R1): CI-run links between the committed media provenance table
// (`scripts/data/library_media_v16.json`), the committed media map
// (`scripts/data/library_batch_c_media_map.json`) and the committed library
// (`assets/data/exercise_library.json`).
//
// CI has no Wardroom ledger and no animation files, so `webp_sha256`, `webp_bytes` and `frames`
// are SHAPE-checked here and verified against the real files only by the builder
// (`scripts/build_library_media_v16.js`) and by the live verify of the upload tool. What this file
// proves is that the table, the map and the library cannot drift apart unnoticed: a row mapped to
// the wrong animation, two files claiming one gif number, a released held row that would ship
// without media, a taken-down file that is still mapped.
//
// Every leg is also run against a deliberately broken copy of the real data: a leg that passes when
// its input is absent would guard nothing.
//
// The library-side legs of R10 (c) (every mapped row carries the table's slug, `media_version` and
// `media_source`) live in `exercise_library_media_fields_test.dart`, added with the importer stage.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

typedef Json = Map<String, dynamic>;

final RegExp _slugRe = RegExp(r'^\d{4}-[a-z0-9]+(-[a-z0-9]+)*$');
final RegExp _sha256Re = RegExp(r'^[0-9a-f]{64}$');

Json _readObject(String path) => jsonDecode(File(path).readAsStringSync()) as Json;

/// kebab(s): lower-case, each run outside [a-z0-9] becomes one '-', trim '-'. Permanent: object
/// names are immutable, so this never changes (the same function is in the builder).
String kebab(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

T _copy<T>(T v) => jsonDecode(jsonEncode(v)) as T;

String _gifOfMap(Json map, String id) {
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
    final want = isOld ? '${(files[e.value] as Json?)?['gif']}' : _gifOfMap(map, e.key);
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
    if (!RegExp(r'^E\d+$').hasMatch(id) && _gifOfMap(map, id).isEmpty) {
      out.add('(c) $id has no gif in the media map but has a rows entry');
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
          _gifOfMap(map, r['id'] as String).isNotEmpty &&
          !takenDownGifs.contains(_gifOfMap(map, r['id'] as String)))
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

void main() {
  final table0 = _readObject('scripts/data/library_media_v16.json');
  final map0 = _readObject('scripts/data/library_batch_c_media_map.json');
  final lib0 = jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List<dynamic>;

  late Json table;
  late Json map;
  late List<dynamic> lib;
  setUp(() {
    table = _copy(table0);
    map = _copy(map0);
    lib = _copy(lib0);
  });

  Json files() => table['files'] as Json;
  Json rows() => table['rows'] as Json;
  Json meta() => table['_meta'] as Json;
  String slugOf(String id) => rows()[id] as String;

  void expectLeg(String leg) {
    final v = tableViolations(table, map, lib);
    expect(v.where((s) => s.startsWith('($leg)')), isNotEmpty, reason: 'leg ($leg) stayed green on a broken copy; all: $v');
  }

  group('the committed table against the committed map and library', () {
    test('every leg of R10 (a)-(h) and R1 holds on the real data', () {
      expect(tableViolations(table0, map0, lib0), isEmpty);
    });

    test('the table has the shape M1 shipped: 617 rows, 616 files, all active, nothing held back', () {
      expect(rows().length, 617);
      expect(files().length, 616);
      expect(files().values.every((f) => (f as Json)['status'] == 'active'), isTrue);
      expect(meta()['old_rows'], isNull);
      expect(meta()['taken_down'], isEmpty);
      expect(meta()['bucket'], 'exercise-media');
      expect(meta()['webp_bytes_max'], 1500000);
    });

    test('N06 and G3643 share one slug and one files entry (one gif number, one file)', () {
      expect(slugOf('N06'), slugOf('G3643'));
      expect(slugOf('N06'), startsWith('3643-'));
    });

    test('the 12 shipped rows without an animation are absent from rows', () {
      final noGif = [
        for (final r in lib)
          if ((r as Json)['source'] == 'exercise-gif-set' && _gifOfMap(map, r['id'] as String).isEmpty) r['id'] as String,
      ];
      expect(noGif, isNotEmpty);
      for (final id in noGif) {
        expect(rows().containsKey(id), isFalse, reason: '$id has no animation yet rows maps it');
      }
    });
  });

  group('each leg turns red on a broken copy of the real data (a leg green on absent input guards nothing)', () {
    test('(b) two slugs with one gif number', () {
      final slug = slugOf('G0103');
      final copy = _copy(files()[slug]);
      files()['${slug.substring(0, 4)}-another-name'] = copy;
      expectLeg('b');
    });

    test('(a) a rows slug whose prefix is another number', () {
      rows()['G0103'] = (rows()['G0103'] as String).replaceFirst(RegExp(r'^\d{4}'), '9999');
      expectLeg('a');
    });

    test('(g) a slug name part edited (key renamed in files and rows)', () {
      final slug = slugOf('G0103');
      final renamed = '$slug-x';
      files()[renamed] = files().remove(slug);
      for (final k in rows().keys.toList()) {
        if (rows()[k] == slug) rows()[k] = renamed;
      }
      expectLeg('g');
    });

    test('(d) webp_bytes over the cap', () {
      (files()[slugOf('G0103')] as Json)['webp_bytes'] = 1500001;
      expectLeg('d');
    });

    test('(e) an N01 row added (its map entry has no gif)', () {
      rows()['N01'] = slugOf('G0103');
      expectLeg('e');
      expectLeg('c');
    });

    test('(e) one rows entry deleted', () {
      rows().remove('G0103');
      expectLeg('e');
    });

    test('(e) a library row added with a map gif and no table row', () {
      lib.add({'id': 'G9999', 'source': 'exercise-gif-set'});
      map['G9999'] = {'_gif': '0001'};
      expectLeg('e');
    });

    test('(c) a rows id that is not a row of the library (a held row)', () {
      rows()['G9998'] = slugOf('G0103');
      map['G9998'] = {'_gif': slugOf('G0103').substring(0, 4)};
      expectLeg('c');
    });

    test('(R1) a files entry dropped while a row still maps to it', () {
      files().remove(slugOf('G0103'));
      expectLeg('R1');
    });

    test('(R1) a slug that breaks the regex', () {
      final slug = slugOf('G0103');
      files()['${slug.substring(0, 4)}-Bad_Slug'] = files().remove(slug);
      rows()['G0103'] = '${slug.substring(0, 4)}-Bad_Slug';
      expectLeg('R1');
    });

    test('(h) a taken_down slug listed in _meta without its status', () {
      meta()['taken_down'] = [slugOf('G0103')];
      expectLeg('h');
    });

    test('(h) a taken_down status that _meta does not list', () {
      (files()[slugOf('G0103')] as Json)['status'] = 'taken_down';
      expectLeg('h');
    });

    test('(h) taken down properly: listed, status set, rows removed, the gif subtracted by (e) - green', () {
      final slug = slugOf('G0103');
      meta()['taken_down'] = [slug];
      (files()[slug] as Json)['status'] = 'taken_down';
      for (final k in rows().keys.toList()) {
        if (rows()[k] == slug) rows().remove(k);
      }
      expect(tableViolations(table, map, lib), isEmpty);
    });

    test('(f) an E id in rows while _meta.old_rows is null', () {
      rows()['E050'] = slugOf('G0103');
      expectLeg('f');
    });

    test('(f) _meta.old_rows.entries off by one', () {
      rows()['E050'] = slugOf('G0103');
      meta()['old_rows'] = {'entries': 2, 'omitted': 0, 'sha256': 'a' * 64};
      expectLeg('f');
    });

    test('(f) the E row, its count and its hash all agree - green', () {
      rows()['E050'] = slugOf('G0103');
      meta()['old_rows'] = {'entries': 1, 'omitted': 0, 'sha256': 'a' * 64};
      expect(tableViolations(table, map, lib), isEmpty);
    });

    test('(h) versions[0].file outside webp-720/', () {
      final f = files()[slugOf('G0103')] as Json;
      ((f['versions'] as List).first as Json)['file'] = '../outside/${slugOf('G0103')}.webp';
      expectLeg('h');
    });

    test('(h) an active file nothing maps to', () {
      rows().remove('G0103');
      expectLeg('h');
    });

    test('(h) media_version other than 1', () {
      final f = files()[slugOf('G0103')] as Json;
      ((f['versions'] as List).first as Json)['media_version'] = 2;
      expectLeg('h');
    });

    test('(h) a malformed sha256', () {
      (files()[slugOf('G0103')] as Json)['thumb_sha256'] = 'xyz';
      expectLeg('h');
    });
  });
}
