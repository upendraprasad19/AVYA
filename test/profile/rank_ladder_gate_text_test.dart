// Test #10 obs 2 — pin the rank-criteria copy table so the rewrite of
// `_humanGateText` (rank_service.dart) doesn't drift later. Surfaces
// the previously-hidden gate halves on PO/CPO (deployments) and MCPO +
// every officer rank (completion rate).
//
// _humanGateText is private. We exercise it by reading
// LadderEntryView.gateText off RankService.getLadder() — the only
// public path that produces the rendered string. Each rank's expected
// text is asserted as `contains` snippets so future copy refinements
// (e.g., punctuation tweaks) don't blanket-fail.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/rank_ladder_data.dart';
import 'package:icanbefitter/core/services/rank_service.dart';

Future<void> _bootstrapHive() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => '.',
  );
  await Hive.initFlutter();
}

void main() {
  setUpAll(_bootstrapHive);

  test('SD2 — earned at induction', () {
    final views = RankService.instance.getLadder();
    final sd2 = views.firstWhere((v) => v.entry.code == 'SD2');
    // SD2 is the starting rank — it's always earned, gateText is null
    // (LadderEntryView.gateText is only populated for unearned ranks).
    // The displayable copy comes from `_humanGateText` which we test
    // indirectly by walking the unearned-rank gates below.
    expect(sd2.isEarned, isTrue);
  });

  group('_humanGateText output (via gateText) for unearned ranks', () {
    late List<LadderEntryView> views;

    setUp(() {
      views = RankService.instance.getLadder();
    });

    LadderEntryView byCode(String code) =>
        views.firstWhere((v) => v.entry.code == code);

    test('SD1 — streak + week of service', () {
      final t = byCode('SD1').gateText;
      if (t == null) return; // already earned in this snapshot
      expect(t, contains('7-workout streak'));
      expect(t, contains('1 week of service'));
    });

    test('LS — streak + 4 weeks of service', () {
      final t = byCode('LS').gateText;
      if (t == null) return;
      expect(t, contains('14-workout streak'));
      expect(t, contains('4 weeks of service'));
    });

    test('PO — streak + 12 weeks + 2 deployments (deployments NOW surfaced)', () {
      final t = byCode('PO').gateText;
      if (t == null) return;
      expect(t, contains('30-workout streak'));
      expect(t, contains('12 weeks of service'));
      expect(t, contains('2 deployments complete'));
    });

    test('CPO — streak + 26 weeks + 3 deployments (deployments NOW surfaced)', () {
      final t = byCode('CPO').gateText;
      if (t == null) return;
      expect(t, contains('50-workout streak'));
      expect(t, contains('26 weeks of service'));
      expect(t, contains('3 deployments complete'));
    });

    test('MCPO — completion rate AND max-gap (both NOW surfaced)', () {
      final t = byCode('MCPO').gateText;
      if (t == null) return;
      expect(t, contains('52 weeks of service'));
      expect(t, contains('80% completion'));
      expect(t, contains('no >14-day gap'));
    });

    test('SubLt — 2 years of service + completion rate (NEW)', () {
      final t = byCode('SubLt').gateText;
      if (t == null) return;
      expect(t, contains('2 years of service'));
      expect(t, contains('80% completion'));
      expect(t, contains('rolling 26 weeks'));
    });

    test('Lt — 2.5 years of service + completion rate', () {
      final t = byCode('Lt').gateText;
      if (t == null) return;
      expect(t, contains('2.5'));
      expect(t, contains('years of service'));
      expect(t, contains('80% completion'));
      expect(t, contains('rolling 26 weeks'));
    });

    test('LtCdr — 3 years of service + completion rate (52-week window)', () {
      final t = byCode('LtCdr').gateText;
      if (t == null) return;
      expect(t, contains('3 years of service'));
      expect(t, contains('80% completion'));
      expect(t, contains('rolling 52 weeks'));
    });

    test('Cdr — 4 years of service + completion rate', () {
      final t = byCode('Cdr').gateText;
      if (t == null) return;
      expect(t, contains('4 years of service'));
      expect(t, contains('80% completion'));
    });

    test('Capt — 5 years of service + 85% completion', () {
      final t = byCode('Capt').gateText;
      if (t == null) return;
      expect(t, contains('5 years of service'));
      expect(t, contains('85% completion'));
    });

    test('every unearned rank produces a non-empty gateText', () {
      for (final v in views) {
        if (v.isEarned) continue;
        expect(v.gateText, isNotNull,
            reason: '${v.entry.code} should have a gateText');
        expect(v.gateText, isNotEmpty,
            reason: '${v.entry.code} gateText must not be empty');
      }
    });
  });
}
