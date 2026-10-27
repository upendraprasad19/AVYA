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
// R10 (c) is checked on both sides here: every `rows` id's library row carries the table's slug, `media_version`
// and `media_source`, and a library row with any media key is a `rows` id with all three.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/library_media_table_checks.dart';

Json _readObject(String path) => jsonDecode(File(path).readAsStringSync()) as Json;

T _copy<T>(T v) => jsonDecode(jsonEncode(v)) as T;

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

  /// Makes the library agree with the table's mapping (keys on every rows id, none elsewhere), the state the importer produces.
  void syncLibraryToTable() {
    final r = rows().cast<String, String>();
    for (final row in lib.cast<Json>()) {
      for (final k in ['media_slug', 'media_version', 'media_source']) {
        row.remove(k);
      }
      final slug = r[row['id']];
      if (slug != null) {
        row['media_slug'] = slug;
        row['media_version'] = 1;
        row['media_source'] = 'wardroom';
      }
    }
  }

  Json libRow(String id) => lib.cast<Json>().firstWhere((r) => r['id'] == id);

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
          if ((r as Json)['source'] == 'exercise-gif-set' && gifOfMap(map, r['id'] as String).isEmpty) r['id'] as String,
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

    test('(c) a triple stripped from a mapped library row', () {
      for (final k in ['media_slug', 'media_version', 'media_source']) {
        libRow('G0103').remove(k);
      }
      expectLeg('c');
    });

    test('(c) a media_version changed on a library row', () {
      libRow('G0103')['media_version'] = 2;
      expectLeg('c');
    });

    test('(c) a triple on a library row the table does not map', () {
      final unmapped = lib.cast<Json>().firstWhere((r) => !rows().containsKey(r['id']));
      unmapped['media_slug'] = slugOf('G0103');
      unmapped['media_version'] = 1;
      unmapped['media_source'] = 'wardroom';
      expectLeg('c');
    });

    test('(c) a partial triple on a mapped library row', () {
      libRow('G0103').remove('media_source');
      expectLeg('c');
    });

    test('(c) a media_source other than wardroom on a library row', () {
      libRow('G0103')['media_source'] = 'elsewhere';
      expectLeg('c');
    });

    test('(c) a partial triple on an unmapped library row', () {
      final unmapped = lib.cast<Json>().firstWhere((r) => !rows().containsKey(r['id']));
      unmapped['media_slug'] = slugOf('G0103');
      expectLeg('c');
    });

    test('(c) a wrong slug on a library row', () {
      libRow('G0103')['media_slug'] = slugOf('G0104');
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
      syncLibraryToTable();
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
      syncLibraryToTable();
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
