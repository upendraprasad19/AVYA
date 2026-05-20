// scripts/check_secrets_gitignored.dart
//
// Gate 23 (Tech-debt audit 2026-05-20, finding I1): assert that Android
// signing artifacts and other sensitive secret patterns are never tracked
// by git AND are matched by an active .gitignore rule.
//
// The audit subagent originally flagged this as P0 thinking `key.properties`
// + `release.jks` were unprotected. They were actually covered by the nested
// `android/.gitignore` (lines 12-14). The misdiagnosis came from reading
// only root `.gitignore`. This gate prevents the same ambiguity by using
// `git check-ignore -v` (authoritative) AND `git ls-files` (definitive).
//
// Exit 0 = pass: no tracked secret files + every sensitive pattern is
//                gitignored at SOME level.
// Exit 1 = fail: any tracked secret file OR any sensitive pattern reachable
//                by `git add` without ignore protection.
//
// Usage: dart run scripts/check_secrets_gitignored.dart
//        dart run scripts/check_secrets_gitignored.dart --warn-only

import 'dart:io';

// Files whose presence in the working tree should trigger this gate to
// verify they're properly ignored. Even if not present, the patterns must
// exist somewhere in .gitignore so a future `touch` doesn't slip in.
const _sensitiveFiles = <String>[
  'android/key.properties',
  'android/app/release.jks',
  'android/app/upload-keystore.jks',
  'android/app/debug.keystore',
];

// Pattern globs that must be matched by some .gitignore. Used when the
// concrete file doesn't exist yet but we want a guarantee for the future.
const _sensitivePatterns = <String>[
  'android/app/release.jks',
  'android/app/foo.keystore',
  '*.aab',
  '*.apk',
];

// Regex for plaintext credential literals in tracked source.
// Restricted to credential-shaped field names so we don't false-positive on
// map literals like `key: 'gender'`. Catches Avya[0-9]+ specifically (the
// audit precedent) plus generic password/api_key field shapes.
final _credentialFieldRegex = RegExp(
  r'\b(?:password|storePassword|keyPassword|apiKey|api[_-]?key|client[_-]?secret|access[_-]?token|service[_-]?role[_-]?key)\s*[:=]\s*["' "'" r'][^"' "'" r']{6,}["' "'" r']',
  caseSensitive: false,
);
final _avyaLiteralRegex = RegExp(r'\bAvya\d{4}\b');

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final violations = <String>[];

  // (1) Tracked-file check — if any of these are in `git ls-files`, immediate fail.
  final lsFiles = await _git(['ls-files', ..._sensitiveFiles]);
  if (lsFiles.trim().isNotEmpty) {
    violations.add('TRACKED SECRET FILES IN GIT:\n  ${lsFiles.trim().split('\n').join('\n  ')}');
  }

  // (2) git check-ignore on every sensitive pattern — must be matched by some .gitignore.
  for (final pattern in _sensitivePatterns) {
    final result = await Process.run('git', ['check-ignore', '-v', pattern], runInShell: true);
    if (result.exitCode != 0) {
      violations.add('NOT GITIGNORED: $pattern (no .gitignore rule matches)');
    }
  }

  // (3) Plaintext password literal scan across tracked source files.
  // Skip test files (they may have fake creds for fixtures).
  final allTracked = await _git(['ls-files', 'lib/', 'android/', 'supabase/functions/']);
  for (final path in allTracked.split('\n')) {
    if (path.isEmpty) continue;
    if (path.startsWith('test/') || path.contains('/test/') || path.contains('_test.')) continue;
    if (!_isTextFile(path)) continue;
    final file = File(path);
    if (!file.existsSync()) continue;
    try {
      final content = file.readAsStringSync();
      final lines = content.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // Skip comments.
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('#') || trimmed.startsWith('*')) continue;

        // Avya[N] literal — specific credential pattern from this project.
        final avya = _avyaLiteralRegex.firstMatch(line);
        if (avya != null) {
          violations.add('AVYA-LITERAL in $path:${i + 1} → ${avya.group(0)}');
          continue;
        }

        // Generic credential-field literal.
        final m = _credentialFieldRegex.firstMatch(line);
        if (m == null) continue;
        final hit = m.group(0)!;
        // Skip placeholders / examples / env-var indirection.
        if (hit.contains('XXXX') ||
            hit.contains('your_') ||
            hit.contains('example') ||
            hit.toLowerCase().contains('placeholder') ||
            hit.contains(r'$') || // ${ENV_VAR} or $env interpolation
            hit.contains('process.env') ||
            hit.contains('Deno.env') ||
            hit.contains('dotenv') ||
            hit.contains('<') || // <PLACEHOLDER> shapes
            hit.contains('TEST_')) continue;
        violations.add('PLAINTEXT CREDENTIAL in $path:${i + 1} → ${hit.trim()}');
      }
    } catch (_) {
      continue;
    }
  }

  final tag = warnOnly ? '[Gate 23 WARN]' : '[Gate 23]';

  if (violations.isEmpty) {
    stdout.writeln('$tag PASS: no tracked secrets, all sensitive patterns gitignored, no plaintext literals in tracked source.');
    exit(0);
  }

  stderr.writeln('$tag FAIL: ${violations.length} violation(s) found:');
  for (final v in violations) {
    stderr.writeln('  - $v');
  }
  stderr.writeln('');
  stderr.writeln('Fix: add the missing patterns to .gitignore (root or nested).');
  stderr.writeln('Rotate any plaintext literals exposed in tracked source.');
  exit(warnOnly ? 0 : 1);
}

Future<String> _git(List<String> args) async {
  final result = await Process.run('git', args, runInShell: true);
  return (result.stdout as String?) ?? '';
}

bool _isTextFile(String path) {
  const skipExts = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.pdf', '.zip', '.jks', '.keystore', '.p12', '.aab', '.apk', '.so', '.bin'};
  for (final ext in skipExts) {
    if (path.toLowerCase().endsWith(ext)) return false;
  }
  return true;
}
