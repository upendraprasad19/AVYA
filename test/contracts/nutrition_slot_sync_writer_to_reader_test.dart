// OI-348 Landing 1a-ii — SoT concept `nutrition_slot_sync`. Pins the contract
// between the client (nutrition_slot_engine.dart / nutrition_slot_remote.dart)
// and migration 181 by TEXT (presence), and the payload → server → read-back
// round trip by BEHAVIOUR through the fake server. The live behaviour is
// supabase/tests/nutrition_slot_rpc_live_verify.sql (run once after apply).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_engine.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_merge.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_remote.dart';

import '../sync/nutrition_slot_fake_server.dart';

const _migration = 'supabase/migrations/181_nutrition_slot_sync.sql';

String _sql() {
  final raw = File(_migration).readAsStringSync();
  // Strip `--` comments so a comment can never satisfy a pin.
  return raw.split('\n').map((l) {
    final i = l.indexOf('--');
    return i < 0 ? l : l.substring(0, i);
  }).join('\n');
}

String _src(String p) => File(p).readAsStringSync();

void main() {
  test('the bounds const equals the SQL bounds (§4.2)', () {
    final sql = _sql();
    expect(sql, contains('jsonb_array_length(p_entries) > $kNslotMaxEntriesPerSlot'));
    expect(sql, contains('jsonb_array_length(p_items) > $kNslotMaxItemsPerSlot'));
    expect(sql, contains("> $kNslotMaxStringLength THEN\n        RAISE EXCEPTION 'nutrition_slot_put: entry field"));
    expect(sql, contains("length(v_i->>'food_name') > $kNslotMaxStringLength"));
    expect(sql, contains('v_n > $kNslotMaxItemsPerSlot'));
    // FC6 ceilings, per entry and per item, never the slot sum.
    expect(sql, contains("(v_field = 'calories' AND v_num > 15000)"));
    expect(sql, contains("(v_field = 'calories' AND v_num > 10000)"));
    expect(RegExp(r"IN \('protein', 'carbs', 'fat'\) AND v_num > 2000")
        .allMatches(sql), hasLength(2));
    expect(RegExp(r"\(v_field = 'fiber' AND v_num > 500\)").allMatches(sql),
        hasLength(2));
    // The 3-decimal p_totals comparison (R16 P2-1).
    expect(RegExp(r'round\(coalesce\(\(p_totals->>.total_[a-z]+.\)::numeric, -1\), 3\) <> round\(v_sum')
        .allMatches(sql), hasLength(5));
  });

  test('the payload keys the client sends are the keys the RPC reads', () {
    final sql = _sql();
    for (final k in ['id', 'k', 's', 'la', 'ca', 'src']) {
      expect(sql, contains("'$k'"), reason: 'entry field $k');
    }
    expect(sql, contains("v_e->'t'"));
    expect(sql, contains("v_e->>'n'"));
    for (final k in [
      'entry_key',
      'food_name',
      'quantity_g',
      'calories',
      'protein',
      'carbs',
      'fat',
      'fiber',
    ]) {
      expect(sql, contains("'$k'"), reason: 'item field $k');
    }
    final engine = _src('lib/core/services/sync/nutrition_slot_engine.dart');
    for (final k in ["'entry_key'", "'food_name'", "'quantity_g'", "'k':",
        "'s':", "'la':", "'ca':", "'src':", "'t':", "'n':"]) {
      expect(engine, contains(k), reason: 'client sends $k');
    }
  });

  test('the columns the client reads are the columns the migration adds', () {
    final sql = _sql();
    for (final c in [
      'rev bigint NOT NULL DEFAULT 1',
      'updated_at timestamptz NOT NULL DEFAULT now()',
      'entries jsonb',
      'legacy_rev bigint NOT NULL DEFAULT 0',
      'entry_key text',
    ]) {
      expect(sql, contains(c));
    }
    final remote = _src('lib/core/services/sync/nutrition_slot_remote.dart');
    for (final c in ["m['rev']", "m['legacy_rev']", "m['updated_at']",
        "m['entries']", "m['nutrition_log_items']", "i['entry_key']",
        "m['deleted_at']", "'nutrition_slot_tombstones'"]) {
      expect(remote, contains(c));
    }
  });

  test('the migration never reaches the catastrophic tier (blast_radius.yaml)',
      () {
    final raw = File(_migration).readAsStringSync();
    expect(raw.toUpperCase().contains('SECURITY ' 'DEFINER'), isFalse);
    final name = _migration.split('/').last;
    for (final g in ['pseudonymize', 'rls', 'security_definer']) {
      expect(name.contains(g), isFalse, reason: g);
    }
    expect(RegExp(r'SECURITY INVOKER').allMatches(_sql()).length, 7);
  });

  test('the delete trigger keeps both guards; the triggers sort after the '
      'redundant-update suppression', () {
    final sql = _sql();
    expect(sql, contains('IF pg_trigger_depth() > 1 THEN\n    RETURN NULL;'));
    expect(sql,
        contains('IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = OLD.user_id) THEN'));
    for (final t in [
      'trg_zz_nutrition_rev',
      'trg_zz_nutrition_items_rev',
      'trg_zz_nutrition_tombstone',
    ]) {
      expect(t.compareTo('trg_suppress_redundant_updates') > 0, isTrue);
      expect(sql, contains('CREATE TRIGGER $t'));
    }
    // Non-RPC writes null the per-meal split; the items trigger bumps rev
    // explicitly (suppression would swallow a no-op `entries = NULL`).
    expect(sql, contains('NEW.entries := NULL;'));
    expect(sql, contains('SET rev = rev + 1, entries = NULL WHERE id = NEW.log_id'));
  });

  // B-pass seat A findings 1 and 9 (2026-11-23): the security and marker
  // lines a reviewer found unpinned. Comments are stripped, so a comment can
  // never satisfy a pin. The live check is the verify SQL (cases C, K, N).
  // The first fix was a function-level `SET app.nutrition_rpc = 'on'`; the
  // live apply REFUSED it (42501: a non-superuser may not attach a custom
  // placeholder to a function), so the body sets the marker and puts the
  // previous value back before every return (an error rolls it back itself).
  test('the RPC marker is set once in the body and put back before EVERY '
      'return; no function-level SET of a custom setting', () {
    final sql = _sql();
    const setOn = "PERFORM set_config('app.nutrition_rpc', 'on', true);";
    const save = "v_prev := current_setting('app.nutrition_rpc', true);";
    const restore =
        "PERFORM set_config('app.nutrition_rpc', coalesce(v_prev, ''), true);";
    String body(String fn) {
      final start = sql.indexOf('CREATE OR REPLACE FUNCTION public.$fn(');
      expect(start, greaterThanOrEqualTo(0), reason: fn);
      final open = sql.indexOf(r'AS $$', start);
      expect(sql.substring(start, open), contains('SET search_path = public'),
          reason: fn);
      return sql.substring(open, sql.indexOf('\n\$\$;', open));
    }

    for (final fn in ['nutrition_slot_put', 'nutrition_slot_delete']) {
      final b = body(fn);
      expect(setOn.allMatches(b), hasLength(1), reason: '$fn sets once');
      final setAt = b.indexOf(setOn);
      expect(b.indexOf(save), allOf(greaterThanOrEqualTo(0), lessThan(setAt)),
          reason: '$fn saves the previous value first');
      final lines = b.split('\n').map((l) => l.trim()).toList();
      var returns = 0;
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].startsWith('RETURN ')) continue;
        returns++;
        var j = i - 1;
        while (j >= 0 && lines[j].isEmpty) {
          j--;
        }
        expect(lines[j], restore, reason: '$fn: line before "${lines[i]}"');
      }
      expect(returns, 3, reason: '$fn return paths');
      // Every RETURN anywhere in the body (an inline `THEN RETURN ...` or a
      // bare `RETURN;` too) must be one the line scan above saw (delta seat
      // finding 1, 2026-11-23): `\bRETURN\b` does not match RETURNS.
      expect(RegExp(r'\bRETURN\b').allMatches(b), hasLength(returns),
          reason: '$fn: a RETURN that does not start its own line');
      expect(restore.allMatches(b), hasLength(returns), reason: fn);
    }
    // Live Postgres refuses this form for the migration role (2026-11-23).
    expect(RegExp(r'^\s*SET app\.', multiLine: true).hasMatch(sql), isFalse);
    // Only the two writers set the marker; the triggers only read it.
    expect("set_config('app.nutrition_rpc'".allMatches(sql), hasLength(8));
    expect(
        RegExp(r"coalesce\(current_setting\('app\.nutrition_rpc', true\), ''\) = 'on'")
            .allMatches(sql),
        hasLength(3));
    expect(RegExp(r'SET search_path = public').allMatches(sql), hasLength(7));
  });

  test('grants: the four RPCs only to authenticated; the trigger functions '
      'to nobody; the tombstone table owner-only under RLS', () {
    final sql = _sql();
    for (final sig in [
      'nutrition_slot_put(date, text, bigint, jsonb, jsonb, jsonb)',
      'nutrition_slot_delete(date, text, bigint)',
      'nutrition_slot_state(date, text)',
      'nutrition_server_now()',
    ]) {
      expect(sql, contains('REVOKE ALL ON FUNCTION public.$sig FROM PUBLIC, anon;'),
          reason: sig);
      expect(sql, contains('GRANT EXECUTE ON FUNCTION public.$sig TO authenticated;'),
          reason: sig);
    }
    for (final fn in [
      'nutrition_logs_rev_trg()',
      'nutrition_log_items_rev_trg()',
      'nutrition_logs_tombstone_trg()',
    ]) {
      expect(sql,
          contains('REVOKE ALL ON FUNCTION public.$fn FROM PUBLIC, anon, authenticated;'),
          reason: fn);
    }
    expect(RegExp(r'GRANT EXECUTE').allMatches(sql), hasLength(4));
    expect(sql, contains('REVOKE ALL ON TABLE public.nutrition_slot_tombstones FROM anon;'));
    expect(
        RegExp(r'ALTER TABLE public\.nutrition_slot_tombstones ENABLE ROW LEVEL SECURITY')
            .hasMatch(sql),
        isTrue);
    expect(RegExp(r'CREATE POLICY \S+ ON public\.nutrition_slot_tombstones')
        .allMatches(sql), hasLength(4));
  });

  test('both writers serialise one slot: advisory lock, then FOR UPDATE', () {
    final sql = _sql();
    expect(
        RegExp(r"PERFORM pg_advisory_xact_lock\(\s*hashtext\(v_uid::text \|\| '\|' \|\| p_date::text \|\| '\|' \|\| p_meal_type\)\);")
            .allMatches(sql),
        hasLength(2));
    expect(RegExp(r'FOR UPDATE;').allMatches(sql).length, greaterThanOrEqualTo(4));
  });

  test('both RPC calls sit inside the skip-index closure (§4.8)', () {
    final engine = _src('lib/core/services/sync/nutrition_slot_engine.dart');
    expect(RegExp(r'remote\s*\.put\(').allMatches(engine), hasLength(1));
    expect(RegExp(r'remote\s*\.delete\(').allMatches(engine), hasLength(1));
    // `_pushSlot` holds both calls and has exactly one caller: the closure.
    expect(RegExp(r'_pushSlot\(date, meal, out\)').allMatches(engine),
        hasLength(1));
    final call = engine.indexOf('await index.pushIfChanged(');
    final inner = engine.indexOf('_pushSlot(date, meal, out)');
    expect(call, greaterThan(0));
    expect(inner, greaterThan(call));
    expect(inner - call, lessThan(400));
  });

  // B-pass delta seat P3: `since` is inclusive by INSTANT (timestamptz >=),
  // whatever the text shape of either side.
  test('the fake keeps a row whose updated_at equals since, across text shapes',
      () async {
    final server = FakeNslotServer();
    for (final meal in ['breakfast', 'lunch', 'dinner', 'snacks']) {
      final rows = [
        NslotLocalRow('nlog_2026-11-23_${meal}_aaaaaaaa', {
          'date': '2026-11-23',
          'meal_type': meal,
          'entry_id': 'e-$meal',
          'total_calories': 100,
          'items': [
            {'name': 'Dal', 'quantity_g': 100, 'calories': 100},
          ],
          'logged_at': '2026-11-23T04:00:00.000Z',
          'created_at': '2026-11-23T04:00:00.000Z',
        }),
      ];
      final p = NslotEngine.buildPayload(rows)!;
      final r = await server.put(
          date: '2026-11-23',
          mealType: meal,
          baseRev: 0,
          totals: p.totals,
          entries: p.entries,
          items: p.items);
      expect(r.ok, isTrue);
      final ts = server.rowJson('2026-11-23', meal)!['updated_at'] as String;
      // The client's text for the same instant (`…Z`, fixed fraction).
      final since = DateTime.parse(ts).toUtc().toIso8601String();
      expect(since, isNot(ts), reason: 'the two texts differ in shape');
      final page = await server.rowsPage(since: since);
      expect(page.map((x) => x['meal_type']), contains(meal),
          reason: 'updated_at == since must be included ($ts vs $since)');
    }
  });

  test('payload → server → read back: same entry ids and signatures',
      () async {
    final server = FakeNslotServer();
    final rows = [
      NslotLocalRow('nlog_2026-11-23_lunch_aaaaaaaa', {
        'date': '2026-11-23',
        'meal_type': 'lunch',
        'entry_id': 'e1',
        'total_calories': 300,
        'total_protein': 0.1 + 0.2,
        'total_carbs': 30,
        'total_fat': 10,
        'total_fiber': 5,
        'items': [
          {'name': ' Dal ', 'quantity_g': 150, 'calories': 300, 'protein': 0.3,
            'carbs': 30, 'fat': 10, 'fiber': 5},
        ],
        'logged_at': '2026-11-23T04:00:00.123456Z',
        'created_at': '2026-11-23T04:00:00.123456Z',
        'source': 'manualSearch',
      }),
    ];
    final p = NslotEngine.buildPayload(rows)!;
    final r = await server.put(
        date: '2026-11-23',
        mealType: 'lunch',
        baseRev: 0,
        totals: p.totals,
        entries: p.entries,
        items: p.items);
    expect(r.ok, isTrue);
    final back = NslotCloudRow.fromJson((await server.rowsPage()).single)!;
    final local = back.toLocalEntries().single;
    expect(local['entry_id'], 'e1');
    expect(local['_k'], 'nlog_2026-11-23_lunch_aaaaaaaa');
    expect(nslotSignature(local), rows.single.signature);
    expect(((local['items'] as List).single as Map)['name'], 'Dal');
  });
}
