// test/contracts/restore_user_snapshot_paged_reads_wiring_test.dart
//
// WIRING contract for `restore-user-snapshot` (diagnose: restore-user-snapshot returns every row).
//
// The behaviour — every row comes back exactly once, in order, scoped to the caller, with a
// throw on a failed page / an unknown name / an unvalidated user id — is proven by the Deno tests
// `supabase/functions/restore-user-snapshot/paged_reads_test.ts` (a fake database that clamps to
// PostgREST's 1000-row cap and reshuffles ties) and `restore_reads_test.ts` (the assembly against
// a golden recorded from the serial code). THIS file proves only what Deno cannot see from inside
// those modules: that `restore_reads.ts` READS (OI-348 B10, a0d5f7: the reads moved out of
// `index.ts`) actually ROUTES each bundle key through the paged readers, that every read is
// scoped to the caller, that `index.ts` hands them one per-request budget, and that the Dart
// client's bundle contract (`SyncService.singleCallBundleKeys`) and the Edge Function still name
// the same keys. Source-grep tests prove PRESENCE only (feedback_source_grep_false_confidence).
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

/// One `READS` tuple of restore_reads.ts: its name, kind and BODY (from after its `=>` to the next
/// tuple head or the close of `READS`; the parameter list is excluded, since every head names vUid).
class _Tuple {
  _Tuple(this.name, this.kind, this.body);
  final String name;
  final String kind;
  final String body;
}

List<_Tuple> _tuples(String reads) {
  final start = reads.indexOf('export const READS');
  expect(start, greaterThan(0), reason: 'READS not found in restore_reads.ts');
  final close = reads.indexOf('\n];', start);
  expect(close, greaterThan(start), reason: 'the close of READS was not found');
  final block = reads.substring(start, close);
  final heads = RegExp(r'\[\s*"([a-z_]+)",\s*"([a-z]+)",\s*\([^)]*\)\s*=>')
      .allMatches(block)
      .toList();
  return [
    for (var i = 0; i < heads.length; i++)
      _Tuple(
        heads[i].group(1)!,
        heads[i].group(2)!,
        block
            .substring(heads[i].end, i + 1 < heads.length ? heads[i + 1].start : block.length)
            .trim()
            .replaceFirst(RegExp(r'\],?$'), '')
            .trim(),
      ),
  ];
}

/// The body with all whitespace removed (a chain may be split over lines).
String _flat(String s) => s.replaceAll(RegExp(r'\s+'), '');

void main() {
  late String index;
  late String paged;
  late String reads;
  late List<_Tuple> tuples;

  setUpAll(() {
    index = _read('index.ts');
    paged = _read('paged_reads.ts');
    reads = _read('restore_reads.ts');
    tuples = _tuples(reads);
  });

  // OI-348 B10 (a0d5f7): the reads moved from index.ts into restore_reads.ts READS tuples. Every
  // assertion below is the old one, repointed; none is loosened.

  test('every paged tuple reads through readPaged with the SAME name, vUid and the request budget', () {
    final calls = RegExp(r'readPaged\(').allMatches(reads).length;
    final pagedTuples =
        tuples.where((t) => t.kind == 'paged' && t.name != 'ai_coach_interactions').toList();
    expect(pagedTuples, isNotEmpty);
    expect(pagedTuples.length, calls,
        reason: 'every readPaged( call must be the whole body of a paged tuple');
    for (final t in pagedTuples) {
      expect(_flat(t.body), 'readPaged(db,vUid,"${t.name}",budget)',
          reason: 'tuple "${t.name}" must be exactly readPaged(db, vUid, "${t.name}", budget)');
    }
    expect(RegExp(r'readPaged\(').hasMatch(index), isFalse,
        reason: 'index.ts must not read on its own: the bundle is READS');
  });

  test('the set of tuples read through readPaged equals the manifest in paged_reads.ts', () {
    final wired = tuples
        .where((t) => t.kind == 'paged' && t.name != 'ai_coach_interactions')
        .map((t) => t.name)
        .toSet();
    expect(wired, _manifestNames(paged));
    expect(wired.length, 13);
  });

  test('ai_coach_interactions is read exactly once, through readCoachNewest(db, vUid)', () {
    expect(RegExp(r'readCoachNewest\(').allMatches(reads).length, 1);
    expect(RegExp(r'readCoachNewest\(').hasMatch(index), isFalse);
    final coach = tuples.singleWhere((t) => t.name == 'ai_coach_interactions');
    expect(coach.kind, 'paged');
    expect(_flat(coach.body), 'readCoachNewest(db,vUid)');
  });

  test('index.ts and restore_reads.ts carry no hand-written row cap', () {
    for (final (label, src) in [('index.ts', index), ('restore_reads.ts', reads)]) {
      expect(src.contains('.range('), isFalse,
          reason: '$label: a bare .range(0, N>=1000) is silently clamped to 1000 rows by PostgREST');
      expect(src.contains('PAGINATED_CEILING'), isFalse, reason: label);
      expect(RegExp(r'\bSINCE(_DATE)?\b').hasMatch(src), isFalse,
          reason: '$label: the restore window has ONE owner: paged_reads.ts');
    }
  });

  test('ONE page budget is created per request, inside the handler, and handed to assembleTables', () {
    final created = RegExp(r'const budget = createPageBudget\(\);').allMatches(index).toList();
    expect(created.length, 1, reason: 'exactly one per-request budget, shared by every paged read');
    // INSIDE the request handler: hoisted above serve(...) it would be ONE budget for the whole
    // isolate, spent after a handful of restores and never refilled (every later restore would 500).
    final handler = index.indexOf('serve(async');
    expect(handler, greaterThan(0), reason: 'the serve(async ...) handler was not found');
    expect(created.single.start, greaterThan(handler),
        reason: 'createPageBudget() must be called per request, inside the handler');
    expect(RegExp(r'createPageBudget\(').allMatches(index).length, 1,
        reason: 'a second createPageBudget() would hand a read a fresh budget and defeat the bound');
    expect(RegExp(r'createPageBudget\(').hasMatch(reads), isFalse,
        reason: 'restore_reads.ts must use the budget it is given, never make one');
    // The mirror of the old "before the first paged read": the budget exists before the ONE call
    // that runs every read, and that call is handed THIS budget.
    final assemble =
        RegExp(r'assembleTables\(\s*db\s*,\s*vUid\s*,\s*budget\s*,').allMatches(index).toList();
    expect(assemble.length, 1, reason: 'index.ts must call assembleTables(db, vUid, budget, ...) once');
    expect(created.single.start, lessThan(assemble.single.start));
  });

  test('index.ts uses the ONE UUID_RE from paged_reads.ts and declares no copy', () {
    expect(RegExp(r'\bconst\s+UUID_RE\b').hasMatch(index), isFalse,
        reason: 'a second regexp can drift from the one the readers re-validate with');
    expect(RegExp(r'UUID_RE\.test\(vUid\)').hasMatch(index), isTrue);
    expect(
        RegExp(r'^import\s[^;]*\bUUID_RE\b[^;]*from\s+"\./paged_reads\.ts"', multiLine: true)
            .hasMatch(index),
        isTrue);
    expect(RegExp(r'export const UUID_RE\b').hasMatch(paged), isTrue);
    // The validation precedes the only call that reads anything.
    expect(index.indexOf('UUID_RE.test(vUid)'), lessThan(index.indexOf('assembleTables(db')));
  });

  test('EVERY tuple is scoped by the caller (vUid in a call position of its body)', () {
    // PRESENCE only (the Deno fake proves the behaviour): service_role bypasses RLS, so a read with
    // no vUid at all would return the whole table.
    expect(tuples.length, SyncService.singleCallBundleKeys.length);
    final scoped = [
      RegExp(r'\.eq\("[a-z_]+",vUid\)'),
      RegExp(r'\.or\(`[^`]*\$\{vUid\}[^`]*`\)'),
      RegExp(r'^readPaged\(db,vUid,'),
      RegExp(r'^readCoachNewest\(db,vUid\)$'),
    ];
    for (final t in tuples) {
      final body = _flat(t.body);
      expect(scoped.any((r) => r.hasMatch(body)), isTrue,
          reason: 'tuple "${t.name}" is read without the caller scope');
      final isReader = body.startsWith('readPaged(') || body.startsWith('readCoachNewest(');
      expect(isReader, t.kind == 'paged',
          reason: 'tuple "${t.name}": kind "${t.kind}" does not match its body '
              '(a "query" body is a builder wrapped by q(); a "paged" body is a reader call)');
    }
  });

  test('the READS names and SyncService._kSingleCallBundleKeys are the same set', () {
    final names = tuples.map((t) => t.name).toList();
    expect(names.length, 29);
    expect(names.toSet().length, names.length, reason: 'a bundle key is read twice');
    expect(names.toSet(), SyncService.singleCallBundleKeys.toSet());
  });

  test('the user scope lives in paged_reads.ts itself; the modules import only what they need', () {
    // PRESENCE only — the behavioural proof is the Deno test's second-user / foreign-template fakes.
    expect(RegExp(r'\.eq\("user_id",\s*vUid\)').allMatches(paged).length, greaterThanOrEqualTo(2),
        reason: 'readPaged and readCoachNewest must each apply .eq("user_id", vUid) themselves');
    List<String> importsOf(String src) =>
        RegExp(r'^import\s[^;]*?from\s+"([^"]+)"', multiLine: true)
            .allMatches(src)
            .map((m) => m.group(1)!)
            .toList();
    expect(importsOf(paged), ['../_shared/paged_fetch.ts'],
        reason: 'the deploy payload ships no import map: no bare specifier, never index.ts');
    expect(importsOf(reads), ['./paged_reads.ts'],
        reason: 'restore_reads.ts imports its readers from ./paged_reads.ts only');
    final readsImport =
        RegExp(r'^import\s*\{([^}]*)\}\s*from\s+"\./paged_reads\.ts"', multiLine: true)
            .firstMatch(reads);
    expect(readsImport, isNotNull);
    expect(readsImport!.group(1)!, allOf(contains('readPaged'), contains('readCoachNewest')),
        reason: 'restore_reads.ts must import readPaged and readCoachNewest from ./paged_reads.ts');
    expect(RegExp(r'^import\s[^;]*?from\s+"\./paged_reads\.ts"', multiLine: true).hasMatch(index),
        isTrue,
        reason: 'index.ts must import its budget and UUID_RE from ./paged_reads.ts');
    expect(
        RegExp(r'^import\s[^;]*?\bassembleTables\b[^;]*?from\s+"\./restore_reads\.ts"', multiLine: true)
            .hasMatch(index),
        isTrue);
  });
}
