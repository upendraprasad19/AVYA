// test/contracts/telegram_surface_removed_test.dart
//
// OI-466 (closes the residue of OI-227): the app no longer shows, offers or
// links Telegram anywhere a user can see it. Telegram is dropped (founder,
// 2026-11-04). This file replaces telegram_connect_ui_removed_test.dart, which
// pinned the OPPOSITE of the end state (it required the channel switch and the
// "Coming Soon" view to stay).
//
// THREE groups, with their proof level stated plainly:
//
//   P  BEHAVIORAL  the real PaywallSheet is pumped, once for the generic upgrade
//                  and once for EVERY feature label its subtitle switch names
//                  (plus the default branch); no text widget, tooltip or
//                  semantics label on any of them names Telegram, and the weekly
//                  report perk is still there.
//   M  BEHAVIORAL  the AI Coach overflow menu entries are pumped from the same
//                  top-level function the real header calls
//                  (coachHeaderMenuItems): exactly Clear conversation, plus
//                  Upgrade to PRO on a free account, and nothing about
//                  Telegram or a channel switch.
//   S  STRUCTURAL  (PRESENCE only, not behavior) a comment-stripped scan of
//                  every lib/**/*.dart and the text files under assets/ and
//                  web/. This is the ONLY proof for the tester who had saved
//                  coach_channel == 'telegram': AiCoachScreen cannot be pumped
//                  in a test (test/features/ai_coach/
//                  coach_chat_restore_invalidation_test.dart:15-36,
//                  test/contracts/workout_surface_invalidation_test.dart:
//                  134-135), so the guarantee that such a tester now lands in
//                  chat rests on there being NO reader of that key, NO channel
//                  branch left in lib/, and the chat area being the
//                  UNCONDITIONAL body of the screen build (pinned below by its
//                  neighbours, so gating it behind any local fails).
//
// KNOWN RESIDUE of the substring scan (group S): adjacent string literals such
// as 'Tele' 'gram' and Unicode lookalikes slip through any substring scan, and a
// string built at run time is only seen where the paywall is pumped (group P).
// The realistic threat is an old branch merged back, which this catches.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/ai_coach/screens/ai_coach/screen.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_button.dart';

import '../helpers/dart_source_slice.dart';

class _Sub extends SubscriptionInfoNotifier {
  _Sub(this.data);
  final SubscriptionInfoData data;
  @override
  SubscriptionInfoData build() => data;
}

final _telegram = RegExp('telegram', caseSensitive: false);

/// Every string a user could read on the pumped tree: rich text (which every
/// `Text` builds), `Text` data, tooltips and semantics labels.
List<String> _visibleStrings(WidgetTester tester) {
  final out = <String>[];
  for (final w in tester.widgetList<RichText>(find.byType(RichText))) {
    out.add(w.text.toPlainText());
  }
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    out.add(w.data ?? w.textSpan?.toPlainText() ?? '');
  }
  for (final w in tester.widgetList<Tooltip>(find.byType(Tooltip))) {
    out.add(w.message ?? '');
  }
  for (final w in tester.widgetList<Semantics>(find.byType(Semantics))) {
    out.add(w.properties.label ?? '');
  }
  return out;
}

Future<void> _pumpPaywall(WidgetTester tester,
    {String feature = PaywallSheet.genericUpgrade}) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      subscriptionInfoProvider
          .overrideWith(() => _Sub(const SubscriptionInfoData())),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PaywallSheet(feature: feature),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 500));
}

const _menuKey = ValueKey('coach-menu');

Future<void> _pumpMenu(WidgetTester tester, {required bool isPro}) async {
  await tester.pumpWidget(MaterialApp(
    // The test font (Ahem, the fallback when GoogleFonts cannot download) is a
    // full em wide per glyph, so "Clear conversation" would overflow the 256 px
    // menu by 22 px here though it fits with the real DM Sans. At text scale
    // 0.6 Ahem's advance approximates the real font's, so the layout under
    // test is the real one and no overflow error needs swallowing.
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(0.6),
      ),
      child: child!,
    ),
    home: Scaffold(
      body: Center(
        child: PopupMenuButton<String>(
          key: _menuKey,
          itemBuilder: (context) => coachHeaderMenuItems(isPro: isPro),
        ),
      ),
    ),
  ));
  await tester.tap(find.byKey(_menuKey));
  await tester.pumpAndSettle();
}

String _read(String path) => File(path).readAsStringSync();

String _normalised(String path) =>
    stripDartComments(_read(path)).replaceAll(RegExp(r'\s+'), '');

void main() {
  // First test warms every GoogleFonts family the pumped widgets render
  // (root CLAUDE.md 4.9): a later render then degrades quietly.
  testWidgets('typography warmup — GoogleFonts caches every family first',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Text('a', style: AppTypography.h3),
          Text('b', style: AppTypography.bodySm),
          Text('c', style: AppTypography.monoXs),
          Text('d', style: AppTypography.body),
          Text('e', style: AppTypography.h1),
          Text('f', style: AppTypography.mono),
          const WardButton(label: 'x', onPressed: null),
        ]),
      ),
    ));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  group('P — the paywall promises no Telegram (behavioral)', () {
    setUp(() => ErrorTelemetry.debugOnLogEventForTests = (op, {message}) {});
    tearDown(() => ErrorTelemetry.debugOnLogEventForTests = null);

    testWidgets('no visible string names Telegram; the weekly report perk stays',
        (tester) async {
      await _pumpPaywall(tester);
      // Positive controls: the sheet really rendered, and the perk list too.
      expect(find.text('UPGRADE TO PRO'), findsOneWidget,
          reason: 'the sheet rendered');
      expect(find.text('Weekly AI nutrition report'), findsOneWidget,
          reason: 'the perk survives without the Telegram suffix');
      final hits = _visibleStrings(tester).where(_telegram.hasMatch).toList();
      expect(hits, isEmpty,
          reason: 'the paywall sells a PRO perk that cannot be delivered: '
              '$hits');
    });

    // The subtitle under the title is chosen by the feature label the caller
    // passes, so a promise built into ONE branch (or assembled at run time,
    // which no source scan can see) shows only when that label is pumped.
    // Every `case '<label>':` of the paywall source is pumped, plus a label
    // that falls to the default branch.
    testWidgets('no feature label, nor the default branch, names Telegram',
        (tester) async {
      final src = stripDartComments(_read('lib/shared/widgets/paywall_sheet.dart'));
      final labels = <String>{
        for (final m in RegExp(r"case\s+'([^']+)'\s*:").allMatches(src)) m.group(1)!,
        'zz-label-that-falls-to-the-default-branch',
      };
      // Positive control: the label list is the real switch, not an empty or
      // truncated match (it holds 15 labels today).
      expect(labels.length, greaterThan(12), reason: 'labels found: $labels');
      expect(labels, contains('Weekly AI Report'));
      final bad = <String>[];
      for (final label in labels) {
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpPaywall(tester, feature: label);
        if (find.text('Weekly AI nutrition report').evaluate().length != 1) {
          bad.add('$label: the sheet did not render its perk list');
        }
        for (final s in _visibleStrings(tester).where(_telegram.hasMatch)) {
          bad.add('$label: "$s"');
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });
  });

  group('M — the AI Coach overflow menu has no channel switch (behavioral)', () {
    testWidgets('a free account sees Clear conversation and Upgrade to PRO only',
        (tester) async {
      await _pumpMenu(tester, isPro: false);
      final values = tester
          .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
          .map((i) => i.value)
          .toList();
      expect(values, ['clear', 'upgrade']);
      expect(find.text('Clear conversation'), findsOneWidget);
      expect(find.text('Upgrade to PRO'), findsOneWidget);
      final hits = _visibleStrings(tester)
          .where((s) => _telegram.hasMatch(s) || s.contains('Switch'))
          .toList();
      expect(hits, isEmpty, reason: 'menu text: $hits');
    });

    testWidgets('a PRO account sees Clear conversation only', (tester) async {
      await _pumpMenu(tester, isPro: true);
      final values = tester
          .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
          .map((i) => i.value)
          .toList();
      expect(values, ['clear']);
      expect(find.text('Upgrade to PRO'), findsNothing);
      expect(
          _visibleStrings(tester)
              .where((s) => _telegram.hasMatch(s) || s.contains('Switch')),
          isEmpty);
    });
  });

  group('S — structural scan (PRESENCE only; see the header comment)', () {
    // Anything that names the dropped channel, case-insensitive. The old card
    // and deep link said "@AVYACOACHBOT" and "t.me/..." without the word
    // "telegram", so those are denied by name too. `t.me` is denied as a WORD
    // (a deep link can be built as host: 't.me', path: '/Bot'), and so are the
    // `tg://` scheme and the Devanagari spellings of the name, which are built
    // from code units so this file stays ASCII.
    final hindiTelegram =
        '${String.fromCharCodes([0x091F, 0x0947, 0x0932])}'
        '[${String.fromCharCodes([0x0940, 0x093F])}]'
        '${String.fromCharCodes([0x0917, 0x094D, 0x0930, 0x093E, 0x092E])}';
    final deny = RegExp(
      'telegram|\\bt\\.me\\b|tg://|AVYACoachBot|ICanbeFitterBot|$hindiTelegram',
      caseSensitive: false,
    );

    // The ONLY non-comment lines allowed to match in lib/, pinned by their
    // EXACT trimmed text (not a count, so swapping the string inside an
    // allow-listed line for user copy still fails):
    //   sync_service.dart         `'source': 'telegram'` (x2) and
    //                             `map['source'] ?? 'telegram'` — the
    //                             cross-channel pull, owned by OI-467
    //   user_config_migrator.dart the `telegram_connected` migrated-key name
    const allowedLines = <String, List<String>>{
      'lib/core/services/sync_service.dart': [
        "'source': 'telegram',",
        "'source': map['source'] ?? 'telegram',",
        "'source': 'telegram',",
      ],
      'lib/core/services/user_config_migrator.dart': [
        "'telegram_connected', 'coach_channel',",
      ],
    };

    List<File> libDart() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    String posix(File f) => f.path.replaceAll('\\', '/');

    test('no lib/ source names Telegram outside the exact-line allow-list', () {
      final files = libDart();
      // Positive control: the scan is not vacuous (wrong cwd or wrong path).
      expect(files.length, greaterThan(500),
          reason: 'expected the whole lib/ tree, found ${files.length}');
      final seen = <String>{};
      final bad = <String>[];
      for (final f in files) {
        final path = posix(f);
        final hits = stripDartComments(f.readAsStringSync())
            .split('\n')
            .map((l) => l.trim())
            .where(deny.hasMatch)
            .toList()
          ..sort();
        final want = [...?allowedLines[path]]..sort();
        if (allowedLines.containsKey(path)) seen.add(path);
        if (hits.join('\n') != want.join('\n')) {
          bad.add('$path: matching lines $hits, expected exactly $want');
        }
      }
      for (final p in allowedLines.keys) {
        expect(seen.contains(p), isTrue,
            reason: '$p was not scanned (path or cwd wrong)');
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });

    test('no text file under assets/ or web/ names Telegram', () {
      const textExt = {
        'json', 'txt', 'md', 'html', 'svg', 'xml', 'yaml', 'yml', 'js', 'css',
      };
      var scanned = 0;
      final bad = <String>[];
      for (final dir in ['assets', 'web']) {
        if (!Directory(dir).existsSync()) continue;
        for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
          final ext = f.path.split('.').last.toLowerCase();
          if (!textExt.contains(ext)) continue;
          scanned++;
          final text = utf8.decode(f.readAsBytesSync(), allowMalformed: true);
          if (deny.hasMatch(text)) bad.add(posix(f));
        }
      }
      expect(scanned, greaterThan(0), reason: 'positive control: files scanned');
      expect(bad, isEmpty, reason: bad.join('\n'));
    });

    test('the removed files and symbols are gone from lib/', () {
      expect(
          File('lib/features/ai_coach/screens/ai_coach/telegram_view.dart')
              .existsSync(),
          isFalse);
      expect(File('lib/features/ai_coach/widgets/telegram_card.dart').existsSync(),
          isFalse);
      const gone = [
        'switch_channel',
        'channelProvider',
        'ChannelNotifier',
        'telegramConnectionProvider',
        'TelegramConnectionNotifier',
        '_openTelegramBot',
        '_menuItemsForChannel',
      ];
      final bad = <String>[];
      for (final f in libDart()) {
        final src = stripDartComments(f.readAsStringSync());
        for (final t in gone) {
          // Whole words: a future `NotificationChannelNotifier` is not this.
          if (RegExp('\\b${RegExp.escape(t)}\\b').hasMatch(src)) {
            bad.add('${posix(f)} still has $t');
          }
        }
        // The stored channel key may only be NAMED by the migrator's key list,
        // exactly once (the file is not exempt from the count: a second use
        // there would be a new reader).
        final uses = 'coach_channel'.allMatches(src).length;
        final isMigrator = posix(f) == 'lib/core/services/user_config_migrator.dart';
        if (uses != (isMigrator ? 1 : 0)) {
          bad.add('${posix(f)} names coach_channel $uses time(s), '
              'expected ${isMigrator ? 1 : 0}');
        }
      }
      expect(bad, isEmpty, reason: bad.join('\n'));
    });

    test('the real header wires the pure menu function exactly once', () {
      final header = _normalised(
          'lib/features/ai_coach/screens/ai_coach/compact_header.dart');
      expect(
        countOf(header, 'itemBuilder:(context)=>coachHeaderMenuItems(isPro:isPro),'),
        1,
        reason: 'T2 proves the function; this ties it to the real button',
      );
    });

    // The menu is split across two places: the VALUES live in the pure
    // function (pumped above) and the DISPATCH lives in the header's
    // onSelected switch. Renaming only one side leaves an entry that does
    // nothing while every other test stays green, so each value pinned by
    // group M must have exactly one case label in the real header.
    test('every overflow menu value has its case in the real header handler', () {
      final header = _normalised(
          'lib/features/ai_coach/screens/ai_coach/compact_header.dart');
      for (final value in const ['clear', 'upgrade']) {
        expect(countOf(header, "case'$value':"), 1,
            reason: 'menu value "$value" needs one `case \'$value\':` in the '
                'header onSelected switch');
      }
    });

    // The "tester with a saved telegram channel lands in chat" guarantee has
    // two legs: no reader of the key (above) and the chat area being the
    // body of the screen build with no condition of its own. This is the
    // second leg, pinned by its neighbours: the header just before it and the
    // quick-prompts line just after it, so gating the chat area behind a
    // local, a ternary or an `if` breaks the adjacency.
    test('the chat area is the unconditional body of the real screen build', () {
      final screen = _normalised('lib/features/ai_coach/screens/ai_coach/screen.dart');
      expect(
        countOf(
            screen,
            '_buildCompactHeader(isPro),'
            'Expanded(child:_buildChatArea(messages,isSending),),'
            'if(!isSending&&messages.length<=1)_buildQuickPrompts(),'),
        1,
        reason: 'the chat area must sit between the header and the quick '
            'prompts with no condition of its own',
      );
      expect(countOf(screen, '_buildChatArea('), 1,
          reason: 'one call site: the unconditional one');
    });
  });
}
