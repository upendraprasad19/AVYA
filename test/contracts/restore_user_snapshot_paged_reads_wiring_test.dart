// test/contracts/restore_user_snapshot_paged_reads_wiring_test.dart
//
// WIRING contract for `restore-user-snapshot` (diagnose: restore-user-snapshot returns every row).
//
// The behaviour — every row comes back exactly once, in order, scoped to the caller, with a
// throw on a failed page / an unknown name / an unvalidated user id — is proven by the Deno test
// `supabase/functions/restore-user-snapshot/paged_reads_test.ts` (a fake database that clamps to
// PostgREST's 1000-row cap and reshuffles ties). THIS file proves only what Deno cannot see from
// inside `paged_reads.ts`: that `index.ts` actually ROUTES each bundle key through it, and that the
// Dart client's bundle contract (`SyncService.singleCallBundleKeys`) and the Edge Function still
// name the same keys. Source-grep tests prove PRESENCE only (feedback_source_grep_false_confidence).
//
// Comments are stripped before every match: the EF header documents the old `.range(0, 49999)` read,
// and a comment must never satisfy (or fail) a wiring assertion.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

const _efDir = 'supabase/functions/restore-user-snapshot';

/// TypeScript comment stripper: block comments, then `//` to end of line when the `//` is not the
/// tail of a URL scheme (`https://`) and not inside a quoted string on that line's left side.
String _stripTs(String s) {
  final noBlock = s.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlock
      .split('\n')
      .map((line) {
        final m = RegExp(r'(^|[^:"\w])//').firstMatch(line);
        if (m == null) return line;
        // keep any code before the `//`
        return line.substring(0, m.start + m.group(1)!.length);
      })
      .join('\n');
}

String _read(String name) {
  final f = File('$_efDir/$name');
  expect(f.existsSync(), isTrue, reason: '$_efDir/$name must exist');
  return _stripTs(f.readAsStringSync());
}

/// The top-level keys of `export const PAGED_READS = { ... }` in paged_reads.ts.
Set<String> _manifestNames(String paged) {
  final start = paged.indexOf('export const PAGED_READS');
  expect(start, greaterThan(0), reason: 'PAGED_READS manifest not found');
  final end = paged.indexOf('export const PAGED_READ_NAMES', start);
  expect(end, greaterThan(start), reason: 'PAGED_READ_NAMES not found after the manifest');
  return RegExp(r'^  ([a-z_]+): \{', multiLine: true)
      .allMatches(paged.substring(start, end))
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  late String index;
  late String paged;

  setUpAll(() {
    index = _read('index.ts');
    paged = _read('paged_reads.ts');
  });

  test('every paged bundle key is assigned from readPaged with the SAME name, vUid and the request budget', () {
    final calls = RegExp(r'readPaged\(').allMatches(index).length;
    final good = RegExp(
      r'tables\["([a-z_]+)"\]\s*=\s*await readPaged\(\s*db\s*,\s*vUid\s*,\s*"([a-z_]+)"\s*,\s*budget\s*,?\s*\)',
    ).allMatches(index).toList();
    expect(good, isNotEmpty);
    expect(good.length, calls,
        reason: 'every readPaged( call must be the whole right-hand side of a '
            'tables["X"] = await readPaged(db, vUid, "X", budget) assignment');
    for (final m in good) {
      expect(m.group(2), m.group(1), reason: 'tables["${m.group(1)}"] reads the wrong table');
    }
    expect(good.map((m) => m.group(1)).toSet().length, good.length,
        reason: 'a bundle key is assigned from readPaged twice');
  });

  test('the set of keys read through readPaged equals the manifest in paged_reads.ts', () {
    final wired = RegExp(r'tables\["([a-z_]+)"\]\s*=\s*await readPaged\(')
        .allMatches(index)
        .map((m) => m.group(1)!)
        .toSet();
    expect(wired, _manifestNames(paged));
    expect(wired.length, 13);
  });

  test('ai_coach_interactions is read exactly once, through readCoachNewest(db, vUid)', () {
    expect(RegExp(r'readCoachNewest\(').allMatches(index).length, 1);
    expect(
      RegExp(r'tables\["ai_coach_interactions"\]\s*=\s*await readCoachNewest\(\s*db\s*,\s*vUid\s*\)')
          .hasMatch(index),
      isTrue,
    );
  });

  test('index.ts no longer carries a hand-written row cap', () {
    expect(index.contains('.range('), isFalse,
        reason: 'a bare .range(0, N>=1000) is silently clamped to 1000 rows by PostgREST');
    expect(index.contains('PAGINATED_CEILING'), isFalse);
    expect(RegExp(r'\bSINCE(_DATE)?\b').hasMatch(index), isFalse,
        reason: 'the restore window has ONE owner: paged_reads.ts');
  });

  test('ONE page budget is created per request, before the first paged read', () {
    final created = RegExp(r'const budget = createPageBudget\(\);').allMatches(index).toList();
    expect(created.length, 1, reason: 'exactly one per-request budget, shared by every paged read');
    expect(created.single.start, lessThan(index.indexOf('readPaged(db')),
        reason: 'the budget must exist before the first paged read');
    // INSIDE the request handler: hoisted above serve(...) it would be ONE budget for the whole
    // isolate, spent after a handful of restores and never refilled (every later restore would 500).
    final handler = index.indexOf('serve(async');
    expect(handler, greaterThan(0), reason: 'the serve(async ...) handler was not found');
    expect(created.single.start, greaterThan(handler),
        reason: 'createPageBudget() must be called per request, inside the handler');
    expect(RegExp(r'createPageBudget\(').allMatches(index).length, 1,
        reason: 'a second createPageBudget() would hand a read a fresh budget and defeat the bound');
  });

  test('index.ts uses the ONE UUID_RE from paged_reads.ts and declares no copy', () {
    expect(RegExp(r'\bconst\s+UUID_RE\b').hasMatch(index), isFalse,
        reason: 'a second regexp can drift from the one the readers re-validate with');
    expect(RegExp(r'UUID_RE\.test\(vUid\)').hasMatch(index), isTrue);
    expect(RegExp(r'^import\s[^;]*\bUUID_RE\b[^;]*from\s+"\./paged_reads\.ts"', multiLine: true).hasMatch(index),
        isTrue);
    expect(RegExp(r'export const UUID_RE\b').hasMatch(paged), isTrue);
  });

  test('EVERY table read in index.ts is scoped by the caller (vUid appears in each assignment)', () {
    // PRESENCE only (the Deno fake proves the behaviour of the paged reads): service_role bypasses
    // RLS, so a read with no vUid at all would return the whole table.
    final starts = RegExp(r'tables\["([a-z_]+)"\]\s*=').allMatches(index).toList();
    expect(starts.length, SyncService.singleCallBundleKeys.length);
    final end = index.indexOf('console.log(rowCountLogLine');
    expect(end, greaterThan(0));
    for (var i = 0; i < starts.length; i++) {
      final stop = i + 1 < starts.length ? starts[i + 1].start : end;
      final rhs = index.substring(starts[i].end, stop);
      expect(rhs.contains('vUid'), isTrue,
          reason: 'tables["${starts[i].group(1)}"] is read without the caller scope');
    }
  });

  test('the bundle keys of index.ts and SyncService._kSingleCallBundleKeys are the same set', () {
    final assigned = RegExp(r'tables\["([a-z_]+)"\]\s*=')
        .allMatches(index)
        .map((m) => m.group(1)!)
        .toList();
    expect(assigned.toSet().length, assigned.length, reason: 'a bundle key is assigned twice');
    expect(assigned.toSet(), SyncService.singleCallBundleKeys.toSet());
  });

  test('the user scope lives in paged_reads.ts itself, and the module imports only paged_fetch', () {
    // PRESENCE only — the behavioural proof is the Deno test's second-user / foreign-template fakes.
    expect(RegExp(r'\.eq\("user_id",\s*vUid\)').allMatches(paged).length, greaterThanOrEqualTo(2),
        reason: 'readPaged and readCoachNewest must each apply .eq("user_id", vUid) themselves');
    final imports = RegExp(r'^import\s[^;]*?from\s+"([^"]+)"', multiLine: true)
        .allMatches(paged)
        .map((m) => m.group(1)!)
        .toList();
    expect(imports, ['../_shared/paged_fetch.ts'],
        reason: 'the deploy payload ships no import map: no bare specifier, never index.ts');
    expect(RegExp(r'^import\s[^;]*?from\s+"\./paged_reads\.ts"', multiLine: true).hasMatch(index),
        isTrue,
        reason: 'index.ts must import its paged reads from ./paged_reads.ts');
  });
}
