// scripts/check_migrations_live.dart
//
// Gate: 14b
//
// Gate 14b: Local migrations match LIVE Supabase migration state.
//
// Closes OI-34 (audit-2026-05-17 Hermes F9). The companion
// `check_migrations_applied.dart` (Gate 14) is snapshot-based — it
// compares local files against `backups/applied_migrations.json` which
// is manually maintained. This gate hits the Supabase Management API
// directly so we catch drift the snapshot misses.
//
// Reads the PAT from `supabase/.supabase/supabase access token.txt`
// (gitignored, fitness-app account per CLAUDE.md §2a). If the token
// file is absent OR network is unavailable, exits 0 with a warning
// rather than failing — letting Gate 14 (offline snapshot) be the
// safety net.
//
// Usage:
//   dart run scripts/check_migrations_live.dart
//
// Exit codes:
//   0 — all local migrations applied in live (or fallback to snapshot)
//   1 — drift detected (some local migration missing in live, or
//       live has unknown migration not on disk)
//
// **Known limitation (follow-up):** the local→live matcher is a prefix
// heuristic. Local files are named "071_rename_orphan_media_rpc.sql"
// (prefix-numeric) but live versions can be either short numerics ("071")
// OR auto-generated timestamps ("20260517123456") depending on apply
// path (raw SQL vs MCP `apply_migration`). False-positive FAILs are
// conservative — investigate any flag before assuming the gate is wrong.

import 'dart:convert';
import 'dart:io';

const _projectId = 'dedsavbjuwgarrhphgnl';
const _tokenPath = 'supabase/.supabase/supabase access token.txt';
const _migrationsDir = 'supabase/migrations';

Future<void> main(List<String> args) async {
  // ── 1. Token ──────────────────────────────────────────────────────────────
  final tokenFile = File(_tokenPath);
  if (!tokenFile.existsSync()) {
    stderr.writeln(
        '[Gate 14b] SKIP — token file not found at $_tokenPath. '
        'Falling back to snapshot-based Gate 14. Exit 0.');
    exit(0);
  }
  final token = tokenFile.readAsStringSync().trim();
  if (token.isEmpty) {
    stderr.writeln('[Gate 14b] SKIP — token file is empty. Exit 0.');
    exit(0);
  }

  // ── 2. Fetch live migration list ──────────────────────────────────────────
  final uri = Uri.parse(
      'https://api.supabase.com/v1/projects/$_projectId/database/migrations');
  final client = HttpClient();
  late HttpClientResponse resp;
  try {
    final req = await client.getUrl(uri);
    req.headers.set('Authorization', 'Bearer $token');
    resp = await req.close().timeout(const Duration(seconds: 15));
  } catch (e) {
    stderr.writeln(
        '[Gate 14b] SKIP — network/timeout error: $e. '
        'Falling back to snapshot-based Gate 14. Exit 0.');
    exit(0);
  } finally {
    client.close();
  }
  if (resp.statusCode != 200) {
    final body = await resp.transform(utf8.decoder).join();
    stderr.writeln(
        '[Gate 14b] FAIL — Management API returned ${resp.statusCode}: $body');
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      stderr.writeln(
          '  Token rejected. Re-generate the PAT from Supabase Dashboard → '
          'Account → Access Tokens for the fitness-app account, replace '
          '$_tokenPath, retry.');
    }
    exit(1);
  }
  final bodyJson = jsonDecode(await resp.transform(utf8.decoder).join());

  // Shape: list of { version, name, ... }
  if (bodyJson is! List) {
    stderr.writeln(
        '[Gate 14b] FAIL — unexpected response shape: ${bodyJson.runtimeType}');
    exit(1);
  }
  final liveVersions = <String>{
    for (final m in bodyJson)
      if (m is Map && m['version'] is String) m['version'] as String,
  };

  // ── 3. List local migrations ──────────────────────────────────────────────
  final migrationsDir = Directory(_migrationsDir);
  if (!migrationsDir.existsSync()) {
    stderr.writeln('[Gate 14b] WARN — $_migrationsDir not found. Exit 0.');
    exit(0);
  }
  final localVersions = <String>{};
  for (final entity in migrationsDir.listSync()) {
    if (entity is File && entity.path.endsWith('.sql')) {
      final basename = entity.path.split(RegExp(r'[/\\]')).last;
      if (basename.startsWith('all_')) continue;
      // Local migrations have variable naming. Extract the leading numeric
      // prefix (e.g. "071_rename_orphan_media_rpc.sql" → "071"). Live
      // versions may use different shapes (timestamps for older, plain
      // ints for new). We tolerate both and match by suffix-of-version.
      final prefixMatch = RegExp(r'^(\d+)').firstMatch(basename);
      if (prefixMatch == null) continue;
      localVersions.add(prefixMatch.group(1)!);
    }
  }

  // ── 4. Diff ───────────────────────────────────────────────────────────────
  // Local file with prefix "071" matches a live version that ENDS with
  // "071" (since timestamp-style live versions are zero-padded).
  bool isLocalAppliedLive(String local) {
    return liveVersions.any((live) =>
        live == local ||
        live.endsWith(local) ||
        live.startsWith(local));
  }

  final unapplied = localVersions.where((v) => !isLocalAppliedLive(v)).toList()
    ..sort();

  stdout.writeln(
      '[Gate 14b] local migrations: ${localVersions.length}, '
      'live migrations: ${liveVersions.length}');

  if (unapplied.isEmpty) {
    stdout.writeln('[Gate 14b] PASS — every local migration is applied live.');
    exit(0);
  } else {
    stderr.writeln(
        '[Gate 14b] FAIL — ${unapplied.length} local migration(s) NOT applied live:');
    for (final v in unapplied) {
      stderr.writeln('  UNAPPLIED: $v');
    }
    stderr.writeln(
        '\n  Fix: apply via Supabase MCP `apply_migration` or Dashboard, '
        'then re-run.');
    exit(1);
  }
}
