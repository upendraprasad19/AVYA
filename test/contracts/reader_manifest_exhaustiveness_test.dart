// test/contracts/reader_manifest_exhaustiveness_test.dart
//
// Contract (OI-01 — 2026-05-17):
// `scripts/check_reader_manifest_complete.dart` enforces TWO phases:
//   1. Forbidden-patterns are absent from production source.
//   2. Every concept with `reader_manifest_complete: true` AND a
//      `hive.key_prefix` set in the SoT registry has an EXHAUSTIVE
//      `readers:` list — every source file in `lib/` + `supabase/functions/`
//      that touches the prefix via a Hive-read context (`.get(...)`,
//      `.startsWith(...)`, `.put(...)`, `.containsKey(...)`, `.delete(...)`)
//      must appear in `readers:`, `writers:`, or `reader_allow_files:`
//      of the concept.
//
// This test runs the gate as a subprocess and asserts exit 0. If a new
// reader is introduced without manifest registration, this test FAILS
// and the gate stderr explains exactly which file/concept/prefix.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'check_reader_manifest_complete passes (forbidden-patterns + exhaustive readers)',
    () async {
      final result = await Process.run(
        'dart',
        ['run', 'scripts/check_reader_manifest_complete.dart'],
        workingDirectory: Directory.current.path,
        runInShell: true,
      );
      // Combine stdout + stderr so the failure reason is visible in the
      // test log without re-running the gate manually.
      final output = [
        if ((result.stdout as String).trim().isNotEmpty) result.stdout,
        if ((result.stderr as String).trim().isNotEmpty) result.stderr,
      ].join('\n');
      expect(
        result.exitCode,
        0,
        reason:
            'scripts/check_reader_manifest_complete.dart exited with code '
            '${result.exitCode}.\n$output',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
