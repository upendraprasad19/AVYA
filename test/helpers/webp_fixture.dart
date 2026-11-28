// Fixtures for the Batch M media tools (plan R12): shape-valid `RIFF....WEBP` byte strings
// of a chosen size and content, and a Wardroom-shaped tree (animation and thumbnail files
// plus a `generation-ledger.json` with the real field shapes of the founder's ledger).
//
// The media tools parse no WebP, so the bytes only need the RIFF header and a size. The
// ledger shape is the real one: `outputs.animation` / `outputs.thumbnail` carry their
// directory prefix (`webp-720/`, `thumbnails-192/`), `animationValidation.SHA256`,
// `thumbnailValidation.SHA256`, `duplicateOf` is null or a string, and the run-level
// `completedAt` sits at the top.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../scripts/migration_ledger_hash_lib.dart' show sha256Hex;

/// `RIFF<len>WEBP` followed by pseudo-random bytes derived from [seed]; exactly [size]
/// bytes long. Different seeds give different bytes (so different sha256).
Uint8List webpBytes(int size, int seed) {
  if (size < 12) throw ArgumentError.value(size, 'size', 'a RIFF/WEBP header needs 12 bytes');
  final b = Uint8List(size);
  b.setRange(0, 4, ascii.encode('RIFF'));
  final len = size - 8;
  b[4] = len & 0xff;
  b[5] = (len >> 8) & 0xff;
  b[6] = (len >> 16) & 0xff;
  b[7] = (len >> 24) & 0xff;
  b.setRange(8, 12, ascii.encode('WEBP'));
  var x = (seed * 2654435761 + 12345) & 0xffffffff;
  for (var i = 12; i < size; i++) {
    x = (x * 1664525 + 1013904223) & 0xffffffff;
    b[i] = (x >> 16) & 0xff;
  }
  return b;
}

/// One ledger entry to write. [number] null means a non-numeric id such as the real
/// `table-row-clean` sample (then [id] must be given).
class FixtureEntry {
  FixtureEntry({
    this.number,
    required this.name,
    this.id,
    this.animSize = 2000,
    this.thumbSize = 400,
    this.seed = 1,
    this.duplicateOf,
    this.sameBytesAs,
  });

  final String? number;
  final String name;
  final String? id;
  final int animSize;
  final int thumbSize;
  final int seed;

  /// The canonical entry id this one is an alias of (ledger `duplicateOf`).
  final String? duplicateOf;

  /// Reuse the animation and thumbnail BYTES of the entry with this id (aliases are
  /// byte-identical copies with their own output file).
  final String? sameBytesAs;

  String get entryId => id ?? '${number}_${name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}';
}

class FixtureWardroom {
  FixtureWardroom(this.dir, this.ledger);

  final Directory dir;

  /// The decoded ledger as written; edit it and call [saveLedger] to change what the tool reads.
  final Map<String, dynamic> ledger;

  List<Map<String, dynamic>> get entries => (ledger['entries'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> entry(String entryId) => entries.firstWhere((e) => e['id'] == entryId);
  File animFile(String entryId) => File('${dir.path}/${(entry(entryId)['outputs'] as Map)['animation']}');
  File thumbFile(String entryId) => File('${dir.path}/${(entry(entryId)['outputs'] as Map)['thumbnail']}');
  File get ledgerFile => File('${dir.path}/generation-ledger.json');

  void saveLedger() =>
      ledgerFile.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(ledger)}\n');
}

/// Writes `webp-720/`, `thumbnails-192/` and `generation-ledger.json` under [dir].
FixtureWardroom writeFixtureWardroom(
  Directory dir,
  List<FixtureEntry> entries, {
  String completedAt = '2026-10-08T13:11:00.000Z',
}) {
  Directory('${dir.path}/webp-720').createSync(recursive: true);
  Directory('${dir.path}/thumbnails-192').createSync(recursive: true);
  final anim = <String, Uint8List>{};
  final thumb = <String, Uint8List>{};
  final out = <Map<String, dynamic>>[];
  for (final e in entries) {
    final id = e.entryId;
    final a = e.sameBytesAs != null ? anim[e.sameBytesAs]! : webpBytes(e.animSize, e.seed);
    final t = e.sameBytesAs != null ? thumb[e.sameBytesAs]! : webpBytes(e.thumbSize, e.seed + 1000);
    anim[id] = a;
    thumb[id] = t;
    final animRel = 'webp-720/${id}_wardroom_720.webp';
    final thumbRel = 'thumbnails-192/${id}_wardroom_192.webp';
    File('${dir.path}/$animRel').writeAsBytesSync(a);
    File('${dir.path}/$thumbRel').writeAsBytesSync(t);
    out.add({
      'id': id,
      'name': e.name,
      'source': '$id.gif',
      'sourceSHA256': sha256Hex(utf8.encode('source:$id')),
      'sourceBytes': 100000,
      'canonicalId': e.duplicateOf ?? id,
      'duplicateOf': e.duplicateOf,
      'stage': 'ready',
      'outputs': {'animation': animRel, 'thumbnail': thumbRel},
      'animationValidation': {
        'bytes': a.length,
        'SHA256': sha256Hex(a),
        'frames': 12,
        'delay': 100,
        'fullyDecoded': true,
      },
      'thumbnailValidation': {
        'bytes': t.length,
        'SHA256': sha256Hex(t),
        'width': 192,
        'height': 192,
        'singleFrame': true,
      },
    });
  }
  final w = FixtureWardroom(dir, {
    'schemaVersion': 1,
    'entries': out,
    'completedAt': completedAt,
  });
  w.saveLedger();
  return w;
}
