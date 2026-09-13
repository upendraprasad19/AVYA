// founder_digest_caps_mirror_test.dart — OI-153 T7.
//
// `founder-digest/index.ts` renders one section per `DIGEST_KEYS` entry. That
// list is a hand-typed MIRROR of every quota_key the ledger can carry, and a
// mirror with no test is membership without completeness: a key that is
// misspelt, or a NEW consume_quota caller nobody added, returns 0 rows and
// renders "none" — indistinguishable from a quiet day, which the digest's
// three-state rendering (data · none · unreadable) cannot see.
//
// So this file derives the key set from the SOURCES and pins set equality in
// BOTH directions, plus the two associations a set check is blind to:
//
//   * the CAP next to each key equals the source's ceiling (or is absent when
//     the source has no single ceiling — food_text is tier-dependent, and the
//     sub-day rate-limit buckets are not a daily "at cap" signal);
//   * the KIND (daily / lifetime / subday) matches the window the source
//     passes — a lifetime key filed as daily would be filtered by
//     `window_start` in the handler and read "none" forever.
//
// Sources:
//   * every Edge Function `index.ts` — each `p_quota_key: <ident>` resolved
//     through its `const` to a string literal, with ONE level of ternary
//     (`isVideo ? A : B`) allowed because ai-media-proxy selects the PRO key
//     that way. Anything else is a FAIL, not a skip: an unresolvable site is
//     a caller this mirror cannot see.
//   * the three cap triggers in their LIVE definition (`latestMigrationDefining`,
//     so a future redefinition — migration 132 redefines the vision trigger —
//     is read from the winning file, not the first one).
//
// Positive control: ai-media-proxy must contribute exactly
// {pro_image_daily, pro_video_daily, free_image_analysis}. If the extractor
// silently matched nothing, the union would still fail set equality — but the
// control makes the failure name the extractor rather than the digest.

import 'dart:io';

import 'package:test/test.dart';

import '../helpers/migration_cap_reader.dart';

const _digestPath = 'supabase/functions/founder-digest/index.ts';
const _functionsDir = 'supabase/functions';

/// Comment-stripped TS source. `//` is a comment only when not preceded by
/// `:` — otherwise every `https://` import line is cut mid-string.
String _stripTs(String s) {
  final lf = s.replaceAll('\r\n', '\n');
  final noBlock = lf.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return noBlock
      .split('\n')
      .map((l) {
        final m = RegExp(r'(?<!:)//').firstMatch(l);
        return m == null ? l : l.substring(0, m.start);
      })
      .join('\n');
}

/// Resolves `ident` to its string-literal values through ONE level of
/// `const ident = "lit"` or `const ident = cond ? A : B` (A, B being
/// `const`-bound literals). Returns the branch-ordered list — position matters
/// for pairing a key ternary with its cap ternary. Null when unresolvable.
List<String>? _resolveStrings(String src, String ident) {
  final direct = RegExp('(?:const|let)\\s+$ident\\s*=\\s*"([^"]*)"\\s*;')
      .firstMatch(src);
  if (direct != null) return [direct.group(1)!];
  final tern = RegExp(
    '(?:const|let)\\s+$ident\\s*=\\s*\\w+\\s*\\?\\s*(\\w+)\\s*:\\s*(\\w+)\\s*;',
  ).firstMatch(src);
  if (tern == null) return null;
  final a = _resolveStrings(src, tern.group(1)!);
  final b = _resolveStrings(src, tern.group(2)!);
  if (a == null || b == null || a.length != 1 || b.length != 1) return null;
  return [a.single, b.single];
}

/// Same shape for integer constants (`p_limit`).
List<int>? _resolveInts(String src, String ident) {
  final direct = RegExp('(?:const|let)\\s+$ident\\s*=\\s*(\\d+)\\s*;')
      .firstMatch(src);
  if (direct != null) return [int.parse(direct.group(1)!)];
  final tern = RegExp(
    '(?:const|let)\\s+$ident\\s*=\\s*\\w+\\s*\\?\\s*(\\w+)\\s*:\\s*(\\w+)\\s*;',
  ).firstMatch(src);
  if (tern == null) return null;
  final a = _resolveInts(src, tern.group(1)!);
  final b = _resolveInts(src, tern.group(2)!);
  if (a == null || b == null || a.length != 1 || b.length != 1) return null;
  return [a.single, b.single];
}

/// The window KIND a `p_window_start: <ident>` implies, resolved one level.
String? _resolveKind(String src, String ident) {
  if (RegExp('const\\s+$ident\\s*=\\s*"1970-01-01T00:00:00\\+00:00"\\s*;')
      .hasMatch(src)) {
    return 'lifetime';
  }
  final init = RegExp('(?:const|let)\\s+$ident\\s*=\\s*([^;]+);').firstMatch(src);
  if (init == null) return null;
  final expr = init.group(1)!;
  if (expr.contains('istDayStartIso(')) return 'daily';
  if (expr.contains('bucketStartMs')) return 'subday';
  return null;
}

class _Site {
  _Site(this.file, this.key, this.cap, this.kind);
  final String file;
  final String key;
  final int? cap;
  final String kind;
  @override
  String toString() => '$file → $key (cap=$cap, $kind)';
}

/// Every `consume_quota` call site in every Edge Function, resolved.
/// Throws (fails the test) on any site it cannot resolve.
List<_Site> _efSites() {
  final sites = <_Site>[];
  final dirs = Directory(_functionsDir).listSync().whereType<Directory>();
  for (final d in dirs) {
    final f = File('${d.path}/index.ts');
    if (!f.existsSync()) continue;
    final rel = f.path.replaceAll('\\', '/');
    final src = _stripTs(f.readAsStringSync());
    // Each `.rpc("consume_quota", {...})` argument object — anchor on the
    // key line, then read its sibling fields from the same object.
    for (final m in RegExp(
      r'p_quota_key:\s*(\w+)\s*,\s*p_window_start:\s*(\w+)\s*,\s*p_limit:\s*(\w+)\s*,?',
    ).allMatches(src)) {
      final keys = _resolveStrings(src, m.group(1)!);
      final kind = _resolveKind(src, m.group(2)!);
      final caps = _resolveInts(src, m.group(3)!);
      if (keys == null || kind == null || caps == null) {
        fail('$rel: unresolvable consume_quota site '
            '(key=${m.group(1)} window=${m.group(2)} limit=${m.group(3)}) — '
            'this mirror only resolves `const X = "lit"` / `const X = <n>` and '
            'a one-level `c ? A : B` ternary. Add the shape here rather than '
            'letting a caller go unmirrored.');
      }
      if (keys.length != caps.length) {
        fail('$rel: key and cap ternaries have different arity — the '
            'branch-pairing below would mis-associate a cap with a key.');
      }
      for (var i = 0; i < keys.length; i++) {
        sites.add(_Site(rel, keys[i], caps[i], kind));
      }
    }
    // Any `p_quota_key:` the full-object regex did NOT consume is a shape
    // this file cannot read — e.g. a different field order. Fail loudly.
    final loose = RegExp(r'p_quota_key:\s*(\w+)').allMatches(src).length;
    final strict = RegExp(
      r'p_quota_key:\s*(\w+)\s*,\s*p_window_start:\s*(\w+)\s*,\s*p_limit:\s*(\w+)',
    ).allMatches(src).length;
    if (loose != strict) {
      fail('$rel: $loose p_quota_key site(s) but only $strict in the '
          'key/window/limit order this mirror reads.');
    }
  }
  return sites;
}

/// The three trigger-side callers, from their LIVE definitions.
List<_Site> _triggerSites() {
  const triggers = [
    'enforce_chat_app_daily_limit',
    'enforce_vision_analysis_daily_limit',
    'enforce_food_text_daily_limit',
  ];
  final sites = <_Site>[];
  for (final fn in triggers) {
    final file = latestMigrationDefining(fn);
    expect(file, isNotNull, reason: 'no migration defines $fn');
    final block = functionBlock(file!.readAsStringSync(), fn);
    expect(block, isNotNull, reason: '$fn block unreadable in ${file.path}');
    final key = RegExp(r"consume_quota\s*\(\s*NEW\.user_id\s*,\s*'(\w+)'")
        .firstMatch(block!);
    expect(key, isNotNull,
        reason: '$fn: no consume_quota(NEW.user_id, \'<key>\' …) call');
    final window = RegExp(
      r"consume_quota\s*\([^;]*?'Asia/Kolkata'[^;]*?\)",
    ).hasMatch(block);
    expect(window, isTrue,
        reason: '$fn: expected an IST-day window inside the consume_quota call');
    final rel = file.path.replaceAll('\\', '/');
    sites.add(_Site(rel, key!.group(1)!, readSingleCeiling(file, fn), 'daily'));
  }
  return sites;
}

class _DigestKey {
  _DigestKey(this.key, this.kind, this.cap);
  final String key;
  final String kind;
  final int? cap;
}

List<_DigestKey> _digestKeys() {
  final src = _stripTs(File(_digestPath).readAsStringSync());
  final start = src.indexOf('DIGEST_KEYS');
  expect(start, greaterThan(-1), reason: 'DIGEST_KEYS missing');
  final open = src.indexOf('[', start);
  final close = src.indexOf('];', open);
  final block = src.substring(open, close);
  final entries = RegExp(
    r'\{\s*key:\s*"(\w+)"\s*,\s*label:\s*"[^"]*"\s*,\s*kind:\s*"(\w+)"\s*(?:,\s*cap:\s*(\d+)\s*)?\}',
  ).allMatches(block).toList();
  // Every `{` in the block must be one entry — an entry in a shape the regex
  // does not read would otherwise vanish from the mirror silently.
  expect(entries.length, '{'.allMatches(block).length,
      reason: 'a DIGEST_KEYS entry is in a shape this test cannot read');
  return [
    for (final e in entries)
      _DigestKey(e.group(1)!, e.group(2)!,
          e.group(3) == null ? null : int.parse(e.group(3)!)),
  ];
}

void main() {
  late List<_Site> ef;
  late List<_Site> triggers;
  late List<_DigestKey> digest;

  setUpAll(() {
    ef = _efSites();
    triggers = _triggerSites();
    digest = _digestKeys();
  });

  group('founder-digest DIGEST_KEYS mirrors every consume_quota key', () {
    test('positive control — ai-media-proxy contributes exactly its three keys',
        () {
      final mine = ef
          .where((s) => s.file.endsWith('ai-media-proxy/index.ts'))
          .map((s) => s.key)
          .toSet();
      expect(mine, {'pro_image_daily', 'pro_video_daily', 'free_image_analysis'},
          reason: 'the extractor must see both PRO ternary branches AND the '
              'free lifetime site; anything else means the resolver is blind');
    });

    test('positive control — every trigger resolves to a key and 129+ file', () {
      expect(triggers.map((s) => s.key).toSet(),
          {'chat_app', 'vision_analysis', 'food_text'});
      for (final t in triggers) {
        final n = migrationNumber(t.file.split('/').last);
        expect(n, greaterThanOrEqualTo(129),
            reason: '${t.key} resolved to a pre-ledger migration (${t.file})');
      }
    });

    test('set equality — sources ⊆ digest AND digest ⊆ sources', () {
      final sources = {...ef.map((s) => s.key), ...triggers.map((s) => s.key)};
      final mirrored = digest.map((d) => d.key).toSet();
      expect(sources.difference(mirrored), isEmpty,
          reason: 'consume_quota key(s) with NO digest section — the digest '
              'would render "none" for them forever');
      expect(mirrored.difference(sources), isEmpty,
          reason: 'digest key(s) that NO caller writes — a misspelling or a '
              'removed caller, renders "none" forever');
    });

    test('caps — every digest cap equals its source ceiling', () {
      final sourceCap = <String, int?>{};
      for (final s in [...ef, ...triggers]) {
        if (sourceCap.containsKey(s.key) && sourceCap[s.key] != s.cap) {
          fail('${s.key}: two callers disagree on the cap '
              '(${sourceCap[s.key]} vs ${s.cap} in ${s.file})');
        }
        sourceCap[s.key] = s.cap;
      }
      for (final d in digest) {
        if (d.kind == 'subday') {
          expect(d.cap, isNull,
              reason: '${d.key}: a sub-day rate-limit bucket is a totals-only '
                  'line; a cap here would count "at cap" per bucket and read '
                  'as a daily ceiling');
          continue;
        }
        expect(d.cap, sourceCap[d.key],
            reason: '${d.key}: digest cap ${d.cap} vs source ${sourceCap[d.key]}'
                ' (null = no single ceiling, e.g. tier-dependent food_text)');
      }
    });

    test('kinds — each digest kind matches the window its source passes', () {
      final sourceKind = <String, String>{};
      for (final s in [...ef, ...triggers]) {
        sourceKind[s.key] = s.kind;
      }
      for (final d in digest) {
        expect(d.kind, sourceKind[d.key],
            reason: '${d.key}: digest kind "${d.kind}" vs source window '
                '"${sourceKind[d.key]}" — a lifetime key filed as daily is '
                'filtered by window_start and reads "none" forever');
      }
    });

    test('pinned literals — the caps the founder decided', () {
      final byKey = {for (final d in digest) d.key: d};
      expect(byKey['pro_image_daily']!.cap, 50);
      expect(byKey['pro_video_daily']!.cap, 10);
      expect(byKey['free_image_analysis']!.cap, 5);
      expect(byKey['weekly_report_free']!.cap, 1);
      expect(byKey['chat_app']!.cap, 10);
      expect(byKey['vision_analysis']!.cap, 20);
      expect(byKey['food_text']!.cap, isNull);
      expect(byKey['delete_account']!.cap, isNull);
      expect(byKey['verify_payment']!.cap, isNull);
    });
  });
}
