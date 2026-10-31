// test/contracts/exercise_media_webp_test.dart
//
// Batch M2a (plan Task 5, mutation [ac]): `isWellFormedWebp` is the ONE predicate the store's `read` and the client share. Each
// term is pinned by a mirror: a good file passes; each SINGLE defect fails alone and none may throw. The defect bodies are
// `webpBytes(...)` with exactly ONE thing changed (or raw bytes for the three short ones), so a zero-filled body cannot satisfy a
// mutant by failing a different term.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media_webp.dart';

import '../helpers/webp_fixture.dart';

void main() {
  test('a well-formed file passes (the mirror of every defect below)', () {
    expect(isWellFormedWebp(webpBytes(40, 1)), isTrue);
    expect(isWellFormedWebp(webpBytes(12, 1)), isTrue, reason: 'the smallest body webpBytes builds');
    expect(isWellFormedWebp(webpBytes(1500000, 1)), isTrue, reason: 'exactly at the bucket limit');
  });

  test('an empty body, 1 byte, the 8-byte JSON error body and 11 bytes fail and never throw [ac: >= 12]', () {
    expect(isWellFormedWebp(Uint8List(0)), isFalse);
    expect(isWellFormedWebp(Uint8List.fromList([0x52])), isFalse);
    expect(isWellFormedWebp(Uint8List.fromList(ascii.encode('{"error"'))), isFalse);
    expect(isWellFormedWebp(Uint8List.fromList(webpBytes(40, 1).sublist(0, 11))), isFalse);
  });

  test('1,500,001 bytes fails alone [ac: cap]', () {
    expect(isWellFormedWebp(webpBytes(1500001, 1)), isFalse);
  });

  test('RIFX magic with a consistent size field fails alone [ac: RIFF]', () {
    final b = webpBytes(40, 1)..[3] = 0x58;
    expect(isWellFormedWebp(b), isFalse);
  });

  test('WEBX magic with a consistent size field fails alone [ac: WEBP]', () {
    final b = webpBytes(40, 1)..[11] = 0x58;
    expect(isWellFormedWebp(b), isFalse);
  });

  test('a wrong RIFF size field fails alone, in either direction [ac: size]', () {
    final small = webpBytes(40, 1)..[4] = 31; // says 39 bytes, is 40
    final big = webpBytes(40, 1)..[4] = 33; // says 41 bytes, is 40
    expect(isWellFormedWebp(small), isFalse);
    expect(isWellFormedWebp(big), isFalse);
  });
}
