// Gate G1 (day-swapper + sync-load batch, spec §7): every Supabase history
// write in the sync layer sits inside SyncSkipIndex.pushIfChanged or an
// allowlisted single-row method; a catch inside a push rethrows or returns
// false; index-key literals live only in sync_skip_index.dart. Logic and
// rationale: scripts/sync_hash_skip_atomicity_lib.dart.
//
// It replaced the OI-204 count-based exlog/nlog check (retired in Task 32,
// when both domains moved onto SyncSkipIndex and the flags it counted no
// longer existed). Hard-fail by default since Task 32, after a 24 h warn-only
// baseline (CLAUDE.md §4.11). `--hard` is still accepted and changes nothing.
import 'dart:io';

import 'sync_hash_skip_atomicity_lib.dart';
import 'sync_no_now_fallback_lib.dart' show isSyncLayerPath;

void main(List<String> args) {
  final structural = checkSyncStructure(_syncLayerSources());
  if (structural.isNotEmpty) {
    stderr.writeln('FAIL sync write structure (G1) — '
        '${structural.length} violation(s):');
    for (final v in structural) {
      stderr.writeln('  $v');
    }
    exit(1);
  }
  print('check_sync_hash_skip_atomicity: OK');
}

Map<String, String> _syncLayerSources() {
  final out = <String, String>{};
  final dir = Directory('lib/core/services/sync');
  if (dir.existsSync()) {
    for (final e in dir.listSync(recursive: true)) {
      if (e is! File) continue;
      final rel = e.path.replaceAll(r'\', '/');
      if (isSyncLayerPath(rel)) out[rel] = e.readAsStringSync();
    }
  }
  final svc = File('lib/core/services/sync_service.dart');
  if (svc.existsSync()) out[svc.path] = svc.readAsStringSync();
  return out;
}
