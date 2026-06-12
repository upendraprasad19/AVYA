// f4d1b7 — the catastrophic review gate (check_code_review_pass_exists.dart)
// must hash the staged diff as RAW BYTES so its hash equals
// `git diff --cached | git hash-object --stdin`. Pre-fix it decoded stdout to a
// String (SystemEncoding — cp1252 on Windows) then hashed `.codeUnits`
// (UTF-16); both steps corrupt non-ASCII bytes, so for any diff containing a
// non-ASCII char (e.g. the ⚠️ emoji in migration 090 that broke this during the
// 2026-06-11 security commit) the gate's hash diverged from git's and the
// catastrophic review file could never be matched.
//
// This test proves raw-UTF-8-bytes-via-stdin == git hash-object of the file for
// non-ASCII content, and that the old .codeUnits path diverges.
//
// closes-diagnose: f4d1b7
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

Future<String> _hashObjectStdin(List<int> bytes) async {
  final p = await Process.start('git', ['hash-object', '--stdin']);
  p.stdin.add(bytes);
  await p.stdin.close();
  final out = await p.stdout.transform(const SystemEncoding().decoder).join();
  await p.exitCode;
  return out.trim();
}

void main() {
  test(
      'review-gate hash: raw UTF-8 bytes match git hash-object; codeUnits diverge (f4d1b7)',
      () async {
    // Non-ASCII content — same class as the ⚠️ that broke the gate.
    const content = 'diff line with an emoji ⚠️ and accent é\n';
    final tmp = await Directory.systemTemp.createTemp('hashtest_f4d1b7');
    final f = File('${tmp.path}/d.txt');
    await f.writeAsBytes(utf8.encode(content));

    final fileHash = (await Process.run('git', ['hash-object', f.path]))
        .stdout
        .toString()
        .trim();
    expect(fileHash, isNotEmpty, reason: 'git hash-object must succeed');

    // FIXED gate path: raw UTF-8 bytes via --stdin.
    final rawHash = await _hashObjectStdin(utf8.encode(content));
    expect(rawHash, fileHash,
        reason: 'raw UTF-8 bytes via --stdin must equal git hash-object of the '
            'file — this is what the gate now does.');

    // BROKEN path: UTF-16 code units of the decoded string.
    final codeUnitsHash = await _hashObjectStdin(content.codeUnits);
    expect(codeUnitsHash, isNot(fileHash),
        reason: 'the pre-fix .codeUnits (UTF-16) path diverges for non-ASCII — '
            'the bug this fix prevents.');

    await tmp.delete(recursive: true);
  });
}
