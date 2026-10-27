// test/contracts/subscription_columns_dropped_test.dart
//
// OI-202 — `users.subscription_status` and `users.subscription_expires_at` are
// DROPPED (migration 152). Entitlement is derived from `public.subscriptions`
// only (`status='active' AND end_date > now()`, supabase/functions/_shared/
// subscription.ts). Nothing that ships may still read or write either column:
// once they are gone, a stale reference does not fail quietly — a PostgREST
// `select` naming a missing column 400s the whole request, and an `update`
// naming one makes the webhook return 500 (Razorpay then retries forever).
//
// WHY A SOURCE SCAN AND NOT ONLY A BEHAVIOURAL TEST: the behavioural proofs are
// elsewhere — `supabase/functions/_shared/subscription_test.ts` (the derived
// read, against a filter-evaluating fake), the digest / bot / admin Deno suites
// and `test/sql/onconflict_live_arbiter.sql` case 28 (the live schema). What no
// runtime test can do is prove that NO OTHER file quietly still names the
// column, which is exactly how the `private.founder_metrics()` reader was
// missed by a schema-scoped dependency query (plan-review R1). This scan is that
// presence guard, and it is presence-only by construction.
//
// SCOPE: shipped source only — Edge Functions (`*.ts`, tests excluded because
// they legitimately hold fixtures), the Flutter client, the Telegram bot and
// the QA seed. Comments are stripped first (feedback_source_grep_strip_comments
// _first) so prose explaining the drop cannot satisfy or trip the scan.
//
// ALLOWLIST: exact snippets, not file-level skips, and each must actually
// appear — so the allowance cannot silently widen or go stale. Both are the
// name of a RESPONSE key (admin-dashboard-data's `subscriptions_expiring`
// rows and the Flutter model that parses them), which is not the dropped DB
// column and is deliberately kept so no client release is needed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _dropped = RegExp(r'subscription_status|subscription_expires_at');

/// file -> exact snippets whose `subscription_expires_at` is the response key.
const _allowed = <String, List<String>>{
  'supabase/functions/admin-dashboard-data/index.ts': [
    '  subscription_expires_at: string;',
    'row.subscription_expires_at',
    'subscription_expires_at: endIso,',
  ],
  'lib/features/admin/models/admin_dashboard_data.dart': [
    "json['subscription_expires_at']",
  ],
};

String _stripComments(String src, String path) {
  var s = src;
  if (path.endsWith('.py')) {
    s = s.replaceAll(RegExp(r'"""[\s\S]*?"""'), '');
    return s.split('\n').where((l) => !l.trimLeft().startsWith('#')).join('\n');
  }
  if (path.endsWith('.sql')) {
    return s.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');
  }
  s = s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return s.replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
}

Iterable<File> _shippedSources() sync* {
  bool ext(File f, List<String> exts) => exts.any(f.path.endsWith);
  for (final root in ['supabase/functions', 'lib', 'telegram-bot']) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      final p = f.path.replaceAll('\\', '/');
      if (p.contains('/node_modules/')) continue;
      if (p.endsWith('_test.ts')) continue;
      if (ext(f, ['.ts', '.dart', '.py'])) yield f;
    }
  }
  final seed = File('supabase/seed_qa.sql');
  if (seed.existsSync()) yield seed;
}

/// Returns the file's remaining references to the dropped columns after the
/// reviewed exact-snippet allowances are removed.
List<String> _violations(String path, String rawSrc) {
  var src = _stripComments(rawSrc, path);
  for (final snippet in _allowed[path] ?? const <String>[]) {
    expect(src.contains(snippet), isTrue,
        reason: 'allowance `$snippet` no longer appears in $path — it was '
            'moved/removed; update or delete it (do not let this go stale).');
    src = src.replaceAll(snippet, '');
  }
  return [
    for (final m in _dropped.allMatches(src))
      '$path: `${src.substring(m.start, (m.end + 20).clamp(0, src.length)).split('\n').first}`',
  ];
}

void main() {
  group('OI-202 — the users.subscription_* mirror columns are gone from shipped source', () {
    test('no shipped file references either dropped column (comments stripped)', () {
      final all = <String>[];
      var scanned = 0;
      for (final f in _shippedSources()) {
        scanned++;
        final p = f.path.replaceAll('\\', '/');
        all.addAll(_violations(p, f.readAsStringSync()));
      }
      expect(scanned, greaterThan(50),
          reason: 'the scan walked only $scanned files — the roots moved and '
              'this guard is passing vacuously');
      expect(all, isEmpty,
          reason: 'users.subscription_status / subscription_expires_at were '
              'dropped by migration 152. Derive entitlement from `subscriptions` '
              '(_shared/subscription.ts) instead.\n  ${all.join("\n  ")}');
    });

    test('POSITIVE CONTROL: the detector flags every shape a stray reference takes', () {
      const shapes = [
        '.select("id, subscription_expires_at")',
        '.eq("subscription_status", "pro")',
        '.update({ subscription_status: "pro" })',
        '.update({ subscription_expires_at: end })',
        '.gte("subscription_expires_at", now)',
        'user.get("subscription_status", "free")',
        'const isPro = user.subscription_status === "pro";',
      ];
      for (final line in shapes) {
        expect(_violations('supabase/functions/x/index.ts', line), isNotEmpty,
            reason: 'the scan failed to flag `$line`');
      }
      // and prose in a comment does NOT trip it
      expect(
          _violations('supabase/functions/x/index.ts',
              '// users.subscription_status was dropped\n/* subscription_expires_at */'),
          isEmpty);
    });

    test('POSITIVE CONTROL: an allowance applies only to its own exact snippet', () {
      // The response-key allowance must not excuse a DB access in the same file.
      final v = _violations(
        'supabase/functions/admin-dashboard-data/index.ts',
        '  subscription_expires_at: string;\n'
            'row.subscription_expires_at\n'
            'subscription_expires_at: endIso,\n'
            '.select("id, subscription_expires_at")',
      );
      expect(v, hasLength(1),
          reason: 'only the `.select(...)` DB access should survive the allowance');
    });
  });
}
