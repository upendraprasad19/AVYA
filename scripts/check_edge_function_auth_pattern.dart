// scripts/check_edge_function_auth_pattern.dart
//
// Gate — Edge Function auth-pattern validation (e8a1c3 class, 2026-06-12).
//
// THE CLASS WE'RE CATCHING
// ------------------------
// An authed Edge Function builds its auth client with the USER JWT in the
// supabaseKey (apikey) slot:
//
//   const c = createClient(SUPABASE_URL, authHeader.replace("Bearer ", ""));
//   const { data } = await c.auth.getUser();   // bare, no token
//
// GoTrue rejects a USER JWT used as an apikey, so EVERY valid user token 401s.
// delete-account shipped exactly this (v1..v4): the DPDP §17 erasure was
// unreachable for ALL users, and the anon-Bearer boot-verify could NOT catch it
// (the module's own 401 is the CORRECT anon response AND masks the broken auth —
// see edge-function-deploy-rollback §6.7). Diagnose e8a1c3 (live web E2E, Obs#10).
//
// THE CORRECT PATTERNS (NOT flagged):
//   createClient(URL, SERVICE_ROLE).auth.getUser(token)        // service key + explicit token
//   createClient(URL, ANON_KEY).auth.getUser(token)            // anon key + explicit token
//   createClient(URL, KEY, {global:{headers:{Authorization}}}) // header in options; getUser() may be bare
//
// A bare `getUser()` is NOT flagged on its own — it is VALID when the client was
// built with `{ global: { headers: { Authorization } } }` (e.g. redeem-referral,
// promote-community-item). The unambiguous bug signature is the JWT in the KEY
// slot, which this gate targets precisely (low false-positive).
//
// WHAT THIS GATE DOES (regex)
// ---------------------------
// For every `createClient(<url>, <keyArg> ...)` in supabase/functions/**/*.ts,
// flag when <keyArg> (the 2nd positional arg = the supabaseKey) is a USER-JWT
// expression rather than a service/anon key:
//   - contains  authHeader  /  .replace("Bearer  /  headers.get("Authorization"
//   - OR is a bare token-ish identifier: token|jwt|userJwt|accessToken|bearer|authToken
// Allowed key args: anything containing SERVICE_ROLE / ANON / SERVICE_KEY, or
// matching /_?key$/i (SUPABASE_SERVICE_ROLE_KEY, serviceRoleKey, SUPABASE_ANON_KEY).
//
// BASELINE
// --------
// backups/edge_function_auth_pattern_baseline.txt grandfathers any file present
// on landing-day (EMPTY on landing — delete-account is already fixed). NEW
// violations (file not in baseline) hard-fail. Refresh with --update-baseline
// after closing a true violation in a separate commit.
//
// Usage: dart run scripts/check_edge_function_auth_pattern.dart [--update-baseline]

import 'dart:io';

const _baselinePath = 'backups/edge_function_auth_pattern_baseline.txt';
const _functionsDir = 'supabase/functions';

// 2nd positional arg to createClient(url, KEY ...). `url` is always a simple
// identifier (SUPABASE_URL / supabaseUrl); the capture grabs the key expression
// up to the next top-level comma / ) / {. \s matches newlines, so multi-line
// createClient(...) calls are handled.
final _createClient =
    RegExp(r'createClient\(\s*[A-Za-z_][\w.]*\s*,\s*([^,){]+)');

// Newline-preserving comment strip (line numbers stay accurate). Removes // line
// comments (not inside https://) + single-line /* */; per feedback_source_grep_
// strip_comments_first — the bug-describing comments quote the OLD broken pattern.
String _stripComments(String src) {
  return src.split('\n').map((line) {
    var l = line.replaceAll(RegExp(r'/\*.*?\*/'), '');
    final m = RegExp(r'(?<!:)//').firstMatch(l);
    return m == null ? l : l.substring(0, m.start);
  }).join('\n');
}

bool _isJwtInKeySlot(String keyArg) {
  final k = keyArg.trim();
  // Service / anon key → always OK (the legitimate supabaseKey).
  final allowed = k.contains('SERVICE_ROLE') ||
      k.contains('ANON') ||
      k.contains('SERVICE_KEY') ||
      RegExp(r'_?[Kk]ey$').hasMatch(k); // serviceRoleKey, supabaseAnonKey, *_KEY
  if (allowed) return false;
  // USER-JWT-shaped key → the e8a1c3 bug.
  if (k.contains('authHeader') ||
      k.contains('.replace("Bearer') ||
      k.contains(".replace('Bearer") ||
      k.contains('headers.get("Authorization') ||
      k.contains("headers.get('Authorization")) {
    return true;
  }
  return RegExp(r'^(token|jwt|userJwt|userJWT|accessToken|bearer|authToken)$')
      .hasMatch(k);
}

void main(List<String> args) {
  final updateBaseline = args.contains('--update-baseline');

  final dir = Directory(_functionsDir);
  if (!dir.existsSync()) {
    stdout.writeln('[EF-auth-pattern] SKIP: $_functionsDir not found.');
    exit(0);
  }

  final violations = <String>[]; // "relative/path.ts:line  <keyArg>"
  final violatingFiles = <String>{};

  for (final f in dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.ts'))) {
    final content = _stripComments(f.readAsStringSync());
    for (final m in _createClient.allMatches(content)) {
      final keyArg = m.group(1)!;
      if (!_isJwtInKeySlot(keyArg)) continue;
      final line = '\n'.allMatches(content.substring(0, m.start)).length + 1;
      final rel = f.path.replaceAll('\\', '/');
      violations.add('$rel:$line  ${keyArg.trim()}');
      violatingFiles.add(rel);
    }
  }

  if (updateBaseline) {
    File(_baselinePath).writeAsStringSync(
        '${(violatingFiles.toList()..sort()).join('\n')}\n');
    stdout.writeln(
        '[EF-auth-pattern] baseline updated: ${violatingFiles.length} file(s).');
    exit(0);
  }

  final baseline = File(_baselinePath).existsSync()
      ? File(_baselinePath)
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#'))
          .toSet()
      : <String>{};

  final fresh = violations
      .where((v) => !baseline.contains(v.split(':').first))
      .toList();

  if (fresh.isEmpty) {
    stdout.writeln(
        '[EF-auth-pattern] PASS: no user-JWT-as-apikey createClient (${baseline.length} baselined).');
    exit(0);
  }
  stderr.writeln(
      '[EF-auth-pattern] FAIL: ${fresh.length} Edge Function(s) pass the USER JWT as the supabaseKey (e8a1c3 class):');
  for (final v in fresh) {
    stderr.writeln('  - $v');
  }
  stderr.writeln('');
  stderr.writeln('  The supabaseKey (2nd arg of createClient) must be SERVICE_ROLE or ANON,');
  stderr.writeln('  NOT the user JWT. Validate the caller with createClient(url, SERVICE_ROLE)');
  stderr.writeln('  + getUser(token). A user JWT used as apikey 401s every valid token.');
  exit(1);
}
