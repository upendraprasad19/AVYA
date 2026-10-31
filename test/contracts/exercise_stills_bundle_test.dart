// test/contracts/exercise_stills_bundle_test.dart
//
// Batch M2a (plan Task 2). The app bundles one still (192 x 192 WebP) per animation so a tile can show something at once and
// offline; the animation itself is fetched on demand. These are pure file checks of `assets/exercise_stills/` against the media
// table (`scripts/data/library_media_v16.json`): every slug has its still, the bytes are the ones the table hashed, and nothing
// else sits in the folder. No count is hard-coded (OI-443 adds about 160 stills); today the table holds 616 slugs and
// 3,102,690 bytes.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/migration_ledger_hash_lib.dart' show sha256Hex;

const _dir = 'assets/exercise_stills';

void main() {
  final table = jsonDecode(File('scripts/data/library_media_v16.json').readAsStringSync()) as Map<String, dynamic>;
  final files = (table['files'] as Map<String, dynamic>).cast<String, Map<String, dynamic>>();

  test('every slug of the media table has its still, with the size the table recorded', () {
    final problems = <String>[];
    for (final e in files.entries) {
      final f = File('$_dir/${e.key}.webp');
      if (!f.existsSync()) {
        problems.add('${e.key}: missing');
      } else if (f.lengthSync() != e.value['thumb_bytes']) {
        problems.add('${e.key}: ${f.lengthSync()} bytes, table says ${e.value['thumb_bytes']}');
      }
    }
    expect(problems, isEmpty, reason: problems.take(5).join('\n'));
  });

  test('every still is byte-for-byte the file the table hashed', () {
    final bad = <String>[];
    for (final e in files.entries) {
      final f = File('$_dir/${e.key}.webp');
      if (!f.existsSync()) continue; // the presence test names it
      if (sha256Hex(f.readAsBytesSync()) != e.value['thumb_sha256']) bad.add(e.key);
    }
    expect(bad, isEmpty, reason: 'sha256 differs from thumb_sha256 for: ${bad.take(5).join(', ')}');
  });

  test('the folder holds exactly the stills the table names and their total is the table total', () {
    final onDisk = Directory(_dir).listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toList()..sort();
    final expected = files.keys.map((s) => '$s.webp').toList()..sort();
    expect(onDisk, expected, reason: 'a stray file would ship in the app bundle');
    final total = onDisk.fold<int>(0, (n, name) => n + File('$_dir/$name').lengthSync());
    final tableTotal = files.values.fold<int>(0, (n, v) => n + (v['thumb_bytes'] as int));
    expect(total, tableTotal);
  });

  test('mirror: every library row with a media_slug has a still', () {
    final lib = (jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    final rowsWithMedia = lib.where((r) => (r['media_slug'] as String?)?.isNotEmpty ?? false).toList();
    expect(rowsWithMedia, isNotEmpty, reason: 'the library carries media slugs; an empty set would make this test vacuous');
    final missing = [
      for (final r in rowsWithMedia)
        if (!File('$_dir/${r['media_slug']}.webp').existsSync()) '${r['id']} -> ${r['media_slug']}',
    ];
    expect(missing, isEmpty);
  });

  test('pubspec.yaml bundles the stills folder', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(RegExp(r'^\s+- assets/exercise_stills/\s*$', multiLine: true).hasMatch(pubspec), isTrue);
  });
}
