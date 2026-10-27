// scripts/check_authed_invoke_fresh_token.dart
//
// Gate — every authed Edge Function call from the client sends a FRESH token
// (§2.31 token-freshness class; mechanical backstop for diagnose d3a1c7).
//
// THE CLASS WE'RE CATCHING
// ------------------------
// A client calls an authed Edge Function with a RAW `client.functions.invoke(...)`
// that does NOT refresh the JWT first. supabase_flutter attaches the current
// session's access token as the Bearer automatically; on a backgrounded / aged
// web session that token is STALE → the EF 401s ("Invalid or expired token").
//
// §2.31 was codified in PROSE + one source-grep test (d3a1c7, 2026-06-09) whose
// rule literally said "grep ALL functions.invoke callsites" — yet the sweep
// STILL missed delete_account_screen (the DPDP delete button "did nothing" on an
// aged web token, Obs#9), assess-body-composition, the video endpoints, and
// redeem-referral. Prose did not prevent recurrence; this gate does.
//
// THE RULE
// --------
// Every `.functions.invoke(` in lib/ must be preceded (within 15 lines, same
// file) by `ensureFreshToken`. The canonical wrapper `SupabaseService.callFunction`
// already refreshes internally, so routing a call through callFunction (no raw
// `.functions.invoke`) is the preferred fix and is invisible to this gate.
//
// EXEMPT
// ------
// lib/core/services/supabase_service.dart — the callFunction wrapper DEFINITION;
// its raw invoke is wrapped by callFunction, which calls ensureFreshToken first.
//
// BASELINE
// --------
// backups/authed_invoke_fresh_token_baseline.txt grandfathers files present on
// landing-day (per-file). NEW violations hard-fail. The Obs#9 sweep removes the
// grandfathered files as it routes each through callFunction / adds the refresh.
// Refresh with --update-baseline.
//
// Usage: dart run scripts/check_authed_invoke_fresh_token.dart [--update-baseline]

import 'dart:io';

const _baselinePath = 'backups/authed_invoke_fresh_token_baseline.txt';
const _libDir = 'lib';
const _lookback = 15;

// The callFunction wrapper itself — its raw invoke is the refresh-wrapped impl.
const _exempt = <String>{'lib/core/services/supabase_service.dart'};

// `\s*` matches newlines, so a MULTI-LINE split call is caught:
//   `...client.functions⏎              .invoke('redeem-referral', ...)`
// The prior `\.functions\.invoke\(` matched line-by-line and MISSED exactly that
// shape at onboarding_provider.dart:537-538 — which is why the §2.31 Obs#9 sweep's
// gate stayed green while that raw-invoke callsite leaked (Unit 1, 2026-06-13).
final _invoke = RegExp(r'\.functions\s*\.invoke\(');

// Newline-preserving comment strip (line numbers stay accurate). Without it the
// gate flags `.functions.invoke(` inside a // comment (e.g. razorpay_service.dart
// documents the FunctionException behavior). Per feedback_source_grep_strip_comments_first.
String _stripComments(String src) {
  return src.split('\n').map((line) {
    var l = line.replaceAll(RegExp(r'/\*.*?\*/'), '');
    final m = RegExp(r'(?<!:)//').firstMatch(l);
    return m == null ? l : l.substring(0, m.start);
  }).join('\n');
}

void main(List<String> args) {
  final updateBaseline = args.contains('--update-baseline');

  final dir = Directory(_libDir);
  if (!dir.existsSync()) {
    stdout.writeln('[authed-invoke-fresh-token] SKIP: $_libDir not found.');
    exit(0);
  }

  final violations = <String>[]; // "rel/path.dart:line"
  final violatingFiles = <String>{};

  for (final f in dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))) {
    final rel = f.path.replaceAll('\\', '/');
    if (_exempt.contains(rel)) continue;
    // Content-level scan (not line-by-line) so a multi-line `.functions\n.invoke(`
    // is matched; derive the 1-based line from the match offset.
    final content = _stripComments(f.readAsStringSync());
    final lines = content.split('\n');
    for (final m in _invoke.allMatches(content)) {
      final i = '\n'.allMatches(content.substring(0, m.start)).length; // 0-based line
      final from = (i - _lookback) < 0 ? 0 : i - _lookback;
      final window = lines.sublist(from, i + 1).join('\n');
      if (window.contains('ensureFreshToken')) continue;
      violations.add('$rel:${i + 1}');
      violatingFiles.add(rel);
    }
  }

  if (updateBaseline) {
    File(_baselinePath).writeAsStringSync(
        '${(violatingFiles.toList()..sort()).join('\n')}\n');
    stdout.writeln(
        '[authed-invoke-fresh-token] baseline updated: ${violatingFiles.length} file(s).');
    exit(0);
  }

  final baseline = File(_baselinePath).existsSync()
      ? File(_baselinePath)
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toSet()
      : <String>{};

  final fresh =
      violations.where((v) => !baseline.contains(v.split(':').first)).toList();

  if (fresh.isEmpty) {
    stdout.writeln(
        '[authed-invoke-fresh-token] PASS: every raw functions.invoke refreshes first (${baseline.length} baselined).');
    exit(0);
  }
  stderr.writeln(
      '[authed-invoke-fresh-token] FAIL: ${fresh.length} raw functions.invoke without a preceding ensureFreshToken (§2.31):');
  for (final v in fresh) {
    stderr.writeln('  - $v');
  }
  stderr.writeln('');
  stderr.writeln('  Route the call through SupabaseService.callFunction (refreshes +');
  stderr.writeln('  retries), OR `await ensureFreshToken()` immediately before the invoke.');
  exit(1);
}
