// test/contracts/clean_orphan_media_pro_recheck_test.dart
//
// OI-321 / diagnose clean-orphan-media-unreadable-pro-check. SoT concept:
// clean_orphan_media_pro_recheck. Bug class 2.49 (an error fallback picks the
// DESTRUCTIVE default); direct recurrence of f2b9d4 (ai-proxy checkPro).
//
// WHAT HAPPENED. `clean-orphan-media` rechecked "is this user PRO?" with a
// `.maybeSingle()` that kept only `data`. `.maybeSingle()` over two unexpired
// active rows answers PGRST116 with a null `data`, and ANY read failure also
// leaves `data` null; both read as "free", and the next line deleted the file.
//
// THE FIX is behavioural and is proven by the Deno tests, NOT here:
//   supabase/functions/_shared/subscription_test.ts          readProState
//   supabase/functions/clean-orphan-media/logic_test.ts      sweepOrphans / runSweep
// (the registry's behavioral_test_path is logic_test.ts).
//
// THIS FILE IS SOURCE-GREP: PRESENCE ONLY. It pins that the wiring cannot
// quietly go back, that the bucket and the RPC are the right ones (the c1ea30
// pin that was promised and never written), that the third copy of the PRO
// predicate cannot blind the older pins, and -- derived, not hand-listed --
// that no user-keyed `subscriptions` read ending in `.maybeSingle()` or
// `.single()` lacks `.limit(1)` (the f2b9d4 / OI-321 shape).

import 'dart:io';

import 'package:test/test.dart';

const _functionsDir = 'supabase/functions';
const _cleanDir = '$_functionsDir/clean-orphan-media';
const _subscriptionTs = '$_functionsDir/_shared/subscription.ts';

/// Comment stripper for TS. `(?<!:)//` keeps `https://` URLs intact (the form
/// weekly_recap_pro_filter_test.dart uses).
String _strip(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'(?<!:)//.*$', multiLine: true), '');

String _squash(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

String _read(String path) => _strip(File(path).readAsStringSync());

/// Non-test .ts files directly in the function folder.
List<File> _cleanSources() => Directory(_cleanDir)
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.ts') && !f.path.endsWith('_test.ts'))
    .toList()
  ..sort((a, b) => a.path.compareTo(b.path));

int _count(String haystack, String needle) => needle.allMatches(haystack).length;

// ── derived chain extractor ────────────────────────────────────────────────

bool _isWs(String c) => c.trim().isEmpty;
final _idChar = RegExp(r'[A-Za-z0-9_$]');

/// Offset of the `)` that closes the `(` at [p]; skips string literals.
int _closeParen(String s, int p) {
  var depth = 0;
  String? quote;
  for (var q = p; q < s.length; q++) {
    final c = s[q];
    if (quote != null) {
      if (c == r'\') {
        q++;
        continue;
      }
      if (c == quote) quote = null;
      continue;
    }
    if (c == "'" || c == '"' || c == '`') {
      quote = c;
      continue;
    }
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return q;
    }
  }
  return s.length - 1;
}

/// The method chain that continues after offset [i] (`.a(...).b(...)`), with
/// balanced parentheses, so a neighbouring chain in a `Promise.all([...])` is
/// never swallowed (a `;`-bounded scan would).
String _chainAfter(String s, int i) {
  var j = i;
  while (true) {
    var k = j;
    while (k < s.length && _isWs(s[k])) {
      k++;
    }
    if (k >= s.length || s[k] != '.') break;
    var n = k + 1;
    while (n < s.length && _idChar.hasMatch(s[n])) {
      n++;
    }
    if (n == k + 1) break;
    // `.maybeSingle<Row>()`: a balanced type argument before the `(` belongs to the call.
    if (n < s.length && s[n] == '<') {
      var angle = 0;
      var q = n;
      for (; q < s.length; q++) {
        if (s[q] == '<') angle++;
        if (s[q] == '>') {
          angle--;
          if (angle == 0) break;
        }
      }
      n = q + 1;
    }
    var p = n;
    while (p < s.length && _isWs(s[p])) {
      p++;
    }
    if (p >= s.length || s[p] != '(') {
      j = n;
      continue;
    }
    j = _closeParen(s, p) + 1;
  }
  return s.substring(i, j);
}

final _fromSubscriptions = RegExp(r'''\.from\(\s*['"]subscriptions['"]\s*\)''');

class _Chain {
  _Chain(this.where, this.text);
  final String where;
  final String text;

  List<String> get calls =>
      RegExp(r'\.([A-Za-z0-9_$]+)\s*(?:<[^()]*>)?\s*\(').allMatches(text).map((m) => m.group(1)!).toList();
  bool get keyedByUser => RegExp(r'''\.eq\(\s*['"]user_id['"]''').hasMatch(text);
  bool get endsInSingle => calls.isNotEmpty && (calls.last == 'maybeSingle' || calls.last == 'single');
  bool get hasLimit1 => RegExp(r'\.limit\(\s*1\s*\)').hasMatch(text);
  // razorpay_payment_id is UNIQUE (migration 010): a payment-id LOOKUP is not a PRO read. Only an
  // `.eq("razorpay_payment_id", …)` filter exempts a chain; merely selecting the column does not.
  bool get exempt => RegExp(r'''\.eq\(\s*['"]razorpay_payment_id['"]''').hasMatch(text);
  bool get subject => keyedByUser && endsInSingle && !exempt;
}

List<_Chain> _chainsIn(String path, String stripped) => [
      for (final m in _fromSubscriptions.allMatches(stripped))
        _Chain('$path:~${stripped.substring(0, m.start).split('\n').length}', _chainAfter(stripped, m.end)),
    ];

Iterable<File> _edgeFunctionSources() => Directory(_functionsDir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.ts') && !f.path.endsWith('_test.ts') && !f.path.endsWith('.test.ts'));

void main() {
  group('clean-orphan-media wiring (presence only)', () {
    test('index.ts delegates to runSweep: no local recheck, no .maybeSingle(), no .remove(', () {
      final src = _read('$_cleanDir/index.ts');
      expect(src, contains('runSweep(supabaseClient'), reason: 'the sweep must go through logic.ts');
      expect(src, isNot(contains('rechecksIsPro')), reason: 'the pre-fix recheck must not come back');
      expect(src, isNot(contains('.maybeSingle(')), reason: 'a .maybeSingle() recheck errors on two rows (PGRST116)');
      expect(src, isNot(contains('.remove(')), reason: 'the only removal lives in logic.ts removeFromBucket');
      expect(src, isNot(contains('coach-media')), reason: 'coach-media is long-term consented retention (c1ea30)');
    });

    test('index.ts still reads candidates from the chat-media RPC and still ends a thrown run as failed', () {
      final src = _read('$_cleanDir/index.ts');
      expect(src, contains("rpc('find_orphan_chat_media'"),
          reason: 'the candidate RPC (migration 071) is the chat-media one; the coach-media one was dropped');
      expect(src, contains("logCronEnd(logId, 'failed'"),
          reason: 'cron_telemetry_adoption_test requires the failed leg');
      // Two legs end a run as failed: the candidate-RPC error and the outer catch. A bare `contains` is
      // satisfied by either, so flipping the other one went unseen (mutant M34). Pin BOTH, by position.
      expect(_count(src, "logCronEnd(logId, 'failed'"), 2, reason: 'the candidate-RPC leg AND the outer catch leg');
      final catchAt = src.lastIndexOf('} catch (err) {');
      expect(catchAt, greaterThan(-1), reason: 'the outer catch is missing');
      expect(src.indexOf("logCronEnd(logId, 'failed'", catchAt), greaterThan(catchAt),
          reason: 'the outer catch must end the run as failed');
      // The sweep's own outcome: a systemic failure ends the run `failed`/500, anything milder `success`/200.
      final sq = _squash(src);
      expect(sq, contains("const status = isSystematicFailure(result) ? 'failed' : 'success';"));
      expect(sq, contains("const httpStatus = status === 'failed' ? 500 : 200;"));
      expect(sq, contains('await logCronEnd(logId, status, {'));
      expect(sq, contains("{ status: httpStatus, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }"),
          reason: 'the HTTP response must follow the run status, not a hard-coded 200');
      final rpcAt = src.indexOf("rpc('find_orphan_chat_media'");
      final firstFailed = src.indexOf("logCronEnd(logId, 'failed'");
      expect(firstFailed, greaterThan(rpcAt), reason: 'the candidate-RPC error leg must end the run as failed');
      expect(firstFailed, lessThan(catchAt));
      expect(src, contains('errorSummary: runErrorSummary(result)'),
          reason: 'an unreadable subscription must be recorded on the cron_call_log row');
    });

    test('exactly ONE .remove( across the function folder, and it is in logic.ts', () {
      final hits = <String>[
        for (final f in _cleanSources())
          if (_read(f.path).contains('.remove(')) '${f.path.replaceAll(r'\', '/')} x${_count(_read(f.path), '.remove(')}',
      ];
      expect(hits, ['$_cleanDir/logic.ts x1'], reason: 'a second door would bypass the PRO decision');
    });

    test('the bucket is chat-media only and is the constant passed to removeFromBucket', () {
      final src = _squash(_read('$_cleanDir/logic.ts'));
      expect(src, contains("const CHAT_MEDIA_BUCKET = 'chat-media';"));
      expect(src, contains('removeFromBucket(client.storage, CHAT_MEDIA_BUCKET, path)'));
      expect(src, isNot(contains('coach-media')));
      expect(_count(src, 'CHAT_MEDIA_BUCKET'), 2, reason: 'declared once, used once: a second use is a second target');
    });

    test('an object is removed ONLY on exactly "free": the guard precedes the one removeObject call', () {
      final src = _read('$_cleanDir/logic.ts');
      final guard = src.indexOf("state !== 'free'");
      final remove = src.indexOf('deps.removeObject(');
      expect(guard, greaterThan(-1), reason: 'the exact-equality guard is missing');
      expect(remove, greaterThan(guard), reason: 'removeObject must come AFTER the free-only guard');
      expect(_count(src, 'deps.removeObject('), 1);
    });

    test('no .maybeSingle() anywhere in the function folder', () {
      for (final f in _cleanSources()) {
        expect(_read(f.path), isNot(contains('.maybeSingle(')), reason: f.path);
      }
    });
  });

  group('readProState shape (presence only; behaviour is in subscription_test.ts)', () {
    late String tail;
    setUpAll(() {
      final src = _read(_subscriptionTs);
      final i = src.indexOf('export async function readProState');
      expect(i, greaterThan(-1), reason: 'readProState is missing');
      tail = src.substring(i);
    });

    test('it is an ARRAY read with .limit(1), never .maybeSingle()', () {
      expect(tail, contains('.limit(1)'));
      expect(tail, isNot(contains('.maybeSingle(')));
      expect(tail, contains('Array.isArray(data)'), reason: 'a non-array result must be unknown, not free');
    });

    test('it applies the PRO predicate with its own nowIso binding', () {
      final s = _squash(tail);
      expect(s, contains('const nowIso = now.toISOString();'));
      expect(s, contains('.eq("status", "active") .gt("end_date", nowIso)'));
    });
  });

  group('the three copies of the PRO predicate stay individually pinned', () {
    // progress_photos_pro_insert_rule_test.dart pins isProUser and fetchProUserIds with
    // whitespace-collapsed `contains`. A repeat of one copy's exact token elsewhere in the
    // file would let a mutation of the original pass, so each form must occur exactly once.
    test('each .gt("end_date", …) form occurs exactly once in comment-stripped subscription.ts', () {
      final s = _squash(_read(_subscriptionTs));
      expect(_count(s, '.gt("end_date", new Date().toISOString())'), 1, reason: 'isProUser');
      expect(_count(s, '.gt("end_date", cutoffIso)'), 1, reason: 'fetchProUserIds');
      expect(_count(s, '.gt("end_date", nowIso)'), 1, reason: 'readProState');
      expect(_count(s, 'const nowIso = now.toISOString();'), 1);
    });
  });

  group('derived sweep: a user-keyed subscriptions read ending in .maybeSingle()/.single() carries .limit(1)', () {
    test('every such chain in supabase/functions has .limit(1) (f2b9d4 / OI-321 shape)', () {
      final subjects = <_Chain>[];
      for (final f in _edgeFunctionSources()) {
        subjects.addAll(_chainsIn(f.path, _strip(f.readAsStringSync())).where((c) => c.subject));
      }
      // Measured on the real tree 2026-10-11: weekly-report, ai-media-proxy, ai-proxy,
      // assess-body-composition, create-razorpay-order, future-prediction,
      // verify-subscription = 7. The floor is BELOW that on purpose: it only guards against a broken
      // extractor passing vacuously, and moving a gate read to the array form (`.limit(1)` with no
      // `.maybeSingle()`) legitimately lowers the count.
      expect(subjects.length, greaterThanOrEqualTo(5), reason: 'the extractor found only: ${subjects.map((c) => c.where).toList()}');
      final bad = subjects.where((c) => !c.hasLimit1).map((c) => c.where).toList();
      expect(bad, isEmpty,
          reason: 'a user can hold several unexpired active rows (a renewal); .maybeSingle()/.single() over them '
              'answers PGRST116 with a null data, read as "no row". Add .order("end_date",{ascending:false}).limit(1). '
              'Offenders: $bad');
    });

    test('payment-id lookups (UNIQUE razorpay_payment_id) are exempt, not flagged', () {
      final all = <_Chain>[];
      for (final f in _edgeFunctionSources()) {
        all.addAll(_chainsIn(f.path, _strip(f.readAsStringSync())));
      }
      final paymentIdKeyed = all.where((c) => c.keyedByUser && c.endsInSingle && c.exempt).toList();
      expect(paymentIdKeyed, isNotEmpty, reason: 'verify-payment has three user_id + razorpay_payment_id chains');
      expect(paymentIdKeyed.every((c) => !c.subject), isTrue);
    });

    test('POSITIVE CONTROL: the verbatim pre-fix clean-orphan-media chain is flagged', () {
      const preFix = '''
async function rechecksIsPro(client: SupabaseClient, userId: string): Promise<boolean> {
  const { data } = await client
    .from('subscriptions')
    .select('end_date')
    .eq('user_id', userId)
    .eq('status', 'active')
    .gt('end_date', new Date().toISOString())
    .maybeSingle();
  return !!data;
}
''';
      final chains = _chainsIn('control', _strip(preFix));
      expect(chains, hasLength(1));
      expect(chains.single.subject, isTrue, reason: 'single-quote form, keyed by user_id, ends in maybeSingle');
      expect(chains.single.hasLimit1, isFalse, reason: 'this is the defect the sweep exists to catch');
    });

    test('NEGATIVE CONTROLS: a compliant chain, a lone .single() without limit, a payment-id chain, two chains in one array', () {
      const compliant = '''
const { data } = await supabase.from("subscriptions").select("status").eq("user_id", id)
  .eq("status", "active").order("end_date", { ascending: false }).limit(1).maybeSingle();
''';
      final ok = _chainsIn('c', _strip(compliant)).single;
      expect(ok.subject && !ok.hasLimit1, isFalse);

      const loneSingle = '''
const r = await supabase.from("subscriptions").select("x").eq("user_id", id).single();
''';
      final single = _chainsIn('s', _strip(loneSingle)).single;
      expect(single.subject, isTrue);
      expect(single.hasLimit1, isFalse, reason: '.single() without .limit(1) has the same PGRST116 failure');

      const payment = '''
const r = await supabase.from("subscriptions").select("id").eq("user_id", u).eq("razorpay_payment_id", p).maybeSingle();
''';
      expect(_chainsIn('p', _strip(payment)).single.subject, isFalse);

      // Two chains in one Promise.all: the second must not be judged by the first one's limit.
      const pair = '''
const [a, b] = await Promise.all([
  supabase.from("subscriptions").select("x").eq("user_id", u).limit(1).maybeSingle(),
  supabase.from("subscriptions").select("x").eq("user_id", u).maybeSingle(),
]);
''';
      final chains = _chainsIn('pair', _strip(pair));
      expect(chains.map((c) => c.hasLimit1).toList(), [true, false]);
    });

    test('CONTROLS for the two blind spots the B-pass found: a generic type argument, and a chain that only SELECTS razorpay_payment_id', () {
      // `.maybeSingle<Row>()` used to end the chain before the generic, so `calls.last` was the
      // previous method and the chain was not treated as ending in maybeSingle.
      const generic = '''
const r = await supabase.from("subscriptions").select("x").eq("user_id", id).maybeSingle<Row>();
''';
      final g = _chainsIn('g', _strip(generic)).single;
      expect(g.calls.last, 'maybeSingle');
      expect(g.subject, isTrue, reason: 'a generic maybeSingle<Row>() over a user-keyed read is still a subject');
      expect(g.hasLimit1, isFalse);

      // Selecting the payment-id column is not a payment-id LOOKUP and must not exempt the chain.
      const selectOnly = '''
const r = await supabase.from("subscriptions").select("razorpay_payment_id, end_date").eq("user_id", id).maybeSingle();
''';
      final so = _chainsIn('so', _strip(selectOnly)).single;
      expect(so.exempt, isFalse, reason: 'only .eq("razorpay_payment_id", …) is a UNIQUE-keyed lookup');
      expect(so.subject, isTrue);

      // The real lookup still exempts.
      const lookup = '''
const r = await supabase.from("subscriptions").select("id").eq("user_id", u).eq("razorpay_payment_id", p).maybeSingle();
''';
      expect(_chainsIn('l', _strip(lookup)).single.exempt, isTrue);
    });
  });
}
