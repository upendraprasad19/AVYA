// test/contracts/cron_auth_no_reserved_prefix_env_test.dart
//
// Regression guard for diagnose c3f8a1 (2026-07-26) — ~8 weeks of total cron
// silence caused by an Edge Function depending on an environment variable that
// Supabase makes it IMPOSSIBLE to provide.
//
// WHAT HAPPENED
// -------------
// `_shared/cron_auth.ts` verified the cron bearer token against
// `Deno.env.get("SUPABASE_JWT_SECRET")` and returned false when it was unset.
// That variable is:
//   (a) NOT among the secrets Supabase injects automatically, and
//   (b) impossible to add by hand — the platform reserves the `SUPABASE_`
//       prefix for secret names ("Names must NOT start with the prefix
//       `SUPABASE_`", Edge Functions platform limits).
// So the gate could never return true. Every cron-dispatched function 401'd
// from the day it deployed, and three separate safeguards failed to surface it.
//
// THE GENERALISABLE RULE
// ----------------------
// Any `SUPABASE_`-prefixed env var an Edge Function reads MUST be one the
// platform actually injects. Reading any other is unsatisfiable by
// construction — it will always be undefined, in every environment, forever.
// That is a whole class of silent-failure bug, not just this one instance.
//
// This test FAILS on the pre-fix source (which read SUPABASE_JWT_SECRET) and
// PASSES after it, satisfying CLAUDE.md rule 21.

import 'dart:io';
import 'package:test/test.dart';

const _functionsDir = 'supabase/functions';

/// Secrets Supabase injects into every Edge Function automatically.
///
/// Captured from the live dashboard (Project Settings -> Edge Functions ->
/// Secrets -> "Default secrets — Reserved secrets available in every project")
/// on 2026-07-26. Anything `SUPABASE_`-prefixed and NOT in this set cannot be
/// created, because the platform rejects the prefix for custom secrets.
///
/// If Supabase adds a new default, add it here — do NOT relax the check.
const _platformProvidedSupabaseEnv = <String>{
  'SUPABASE_URL',
  'SUPABASE_DB_URL',
  'SUPABASE_PUBLISHABLE_KEYS',
  'SUPABASE_SECRET_KEYS',
  'SUPABASE_ANON_KEY', // deprecated by Supabase, still injected
  'SUPABASE_SERVICE_ROLE_KEY', // deprecated by Supabase, still injected
  'SUPABASE_JWKS',
};

final _envReadRegex = RegExp(r'''Deno\.env\.get\(\s*['"](SUPABASE_[A-Z0-9_]+)['"]''');

Iterable<File> _tsFilesUnder(Directory dir) => dir
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.ts'));

void main() {
  group('cron auth must not depend on an uncreatable SUPABASE_ env var', () {
    test('no Edge Function reads a SUPABASE_ var the platform does not inject',
        () {
      final dir = Directory(_functionsDir);
      expect(dir.existsSync(), isTrue,
          reason: '$_functionsDir must exist — run from the repo root.');

      final violations = <String>[];
      for (final file in _tsFilesUnder(dir)) {
        final src = file.readAsStringSync();
        for (final m in _envReadRegex.allMatches(src)) {
          final name = m.group(1)!;
          if (!_platformProvidedSupabaseEnv.contains(name)) {
            violations.add('${file.path} reads $name');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'These reads can NEVER resolve. Supabase reserves the '
            '`SUPABASE_` prefix, so a custom secret with this name cannot be '
            'created, and the platform does not inject it. The function will '
            'silently take its failure path in every environment.\n'
            'Violations:\n  ${violations.join("\n  ")}\n'
            'Fix: use a non-reserved name (e.g. CRON_SECRET). See diagnose '
            'c3f8a1.',
      );
    });

    test('cron_auth.ts authenticates via CRON_SECRET', () {
      final gate = File('$_functionsDir/_shared/cron_auth.ts');
      expect(gate.existsSync(), isTrue);
      final src = gate.readAsStringSync();

      expect(
        src.contains('Deno.env.get("CRON_SECRET")'),
        isTrue,
        reason: 'The cron auth gate must read CRON_SECRET — a name without the '
            'reserved prefix, so it can actually be set.',
      );
    });

    // POSITIVE CONTROL — added after Hermes L24-F3.
    //
    // Every other test in this file asserts an ABSENCE (`isEmpty`). That means
    // a regex that matches nothing at all — a typo, a Dart raw-string change,
    // an accidental deletion — would make all of them pass vacuously, and the
    // guard would be silently dead exactly when it mattered. This test fails if
    // the detector stops detecting.
    test('POSITIVE CONTROL: the detector actually detects', () {
      const knownBad = '''
        const jwtSecret = Deno.env.get("SUPABASE_JWT_SECRET");
      ''';
      final hits = _envReadRegex.allMatches(knownBad).map((m) => m.group(1)!);
      expect(
        hits,
        contains('SUPABASE_JWT_SECRET'),
        reason: 'The regex failed to flag the exact pre-fix line that caused '
            'the c3f8a1 outage. If this fails, every other test in this file '
            'is passing vacuously and the guard is dead.',
      );
      expect(
        _platformProvidedSupabaseEnv.contains('SUPABASE_JWT_SECRET'),
        isFalse,
        reason: 'SUPABASE_JWT_SECRET must never be allowlisted — the platform '
            'reserves the SUPABASE_ prefix, so it can never be created.',
      );

      // And it must find real reads in the actual tree, not just a literal.
      final real = _tsFilesUnder(Directory(_functionsDir))
          .expand((f) => _envReadRegex.allMatches(f.readAsStringSync()))
          .length;
      expect(
        real,
        greaterThan(10),
        reason: 'Expected many SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY reads '
            'across the Edge Functions. Near-zero means the regex or the file '
            'walk has broken, not that the tree is clean.',
      );
    });

    test('cron_auth.ts depends on NO SUPABASE_ env var at all', () {
      final src =
          File('$_functionsDir/_shared/cron_auth.ts').readAsStringSync();
      final found =
          _envReadRegex.allMatches(src).map((m) => m.group(1)!).toList();

      expect(
        found,
        isEmpty,
        reason: 'The cron auth gate must not couple itself to Supabase '
            'platform key management. Both previous designs did — one via '
            'SUPABASE_SERVICE_ROLE_KEY (broke on key drift, diagnose 5a65bd), '
            'one via SUPABASE_JWT_SECRET (uncreatable, diagnose c3f8a1). '
            'Found: $found',
      );
    });
  });
}
