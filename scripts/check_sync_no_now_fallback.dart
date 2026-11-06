// scripts/check_sync_no_now_fallback.dart
//
// Gate G2 (day-swapper + sync-load batch, spec §5.12 / §7): a sync payload
// never sends "now" as the fallback for a past timestamp. Logic and rationale:
// scripts/sync_no_now_fallback_lib.dart.
//
// HARD-FAIL by default since Task 32 of the day-swapper + sync-load plan,
// after a 24 h warn-only baseline (CLAUDE.md §4.11). `--hard` is still
// accepted and changes nothing.
//
// Usage: dart run scripts/check_sync_no_now_fallback.dart [--hard]
import 'dart:io';

import 'sync_no_now_fallback_lib.dart';

const bool _hardFailByDefault = true;

void main(List<String> args) {
  final hard = _hardFailByDefault || args.contains('--hard');
  final findings = <NowFallbackFinding>[];
  for (final path in _syncLayerFiles()) {
    findings.addAll(findNowFallbacks(path, File(path).readAsStringSync()));
  }
  if (findings.isEmpty) {
    stdout.writeln('check_sync_no_now_fallback: OK (0 now-fallbacks in the sync layer)');
    return;
  }
  stderr.writeln('check_sync_no_now_fallback: ${hard ? 'FAIL' : 'WARN'} — '
      '${findings.length} past-timestamp field(s) fall back to "now":');
  for (final f in findings) {
    stderr.writeln('  $f');
  }
  stderr.writeln('  Fix: recorded value -> derive from a *_ms sibling or the '
      'Hive key -> otherwise OMIT the field (spec §5.12).');
  if (hard) exit(1);
}

List<String> _syncLayerFiles() {
  final out = <String>[];
  final dir = Directory('lib/core/services/sync');
  if (dir.existsSync()) {
    for (final e in dir.listSync(recursive: true)) {
      if (e is! File) continue;
      final rel = e.path.replaceAll(r'\', '/');
      if (isSyncLayerPath(rel)) out.add(rel);
    }
  }
  if (File('lib/core/services/sync_service.dart').existsSync()) {  // file-only: fixed .dart filename, never a directory
    out.add('lib/core/services/sync_service.dart');
  }
  out.sort();
  return out;
}
