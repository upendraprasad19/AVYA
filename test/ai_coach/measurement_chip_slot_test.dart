// HARNESS NOTE (GoogleFonts pitfall, root CLAUDE.md section 4.9): the FIRST test
// is a typography warmup that runs before any path_provider mock is installed.
// Real Hive writes happen inside tester.runAsync (a put started in the
// fake-async zone never completes).
@Timeout(Duration(minutes: 4))
library;

// L2b Landing C (E4): the AI Coach chat's measurements chip.
// Plan: docs/plans/coach-measurement-surfaces.md (C3, section 4).
//
// CLOCKS: pinned to 2031-06-15 20:00 UTC (2031-06-16 01:30 IST, the IST and UTC
// days differ). The real-graph rows plant a measurement dated 2031-05-01, which
// is 46 days old at that clock, so the prompt is `due`, and those rows ASSERT
// the prompt they are named after: against the device clock (before 2031) that
// entry is in the future, the reader drops it and the prompt would be
// `baseline`, which shows the same chip, so only the assertion tells them apart.
// After the real clock passes the pinned day a device-clock consumer simply
// stops being detectable; no row turns red on that day.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/widgets/measurement_chip_slot.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_flag_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_prompt_provider.dart';
import 'package:icanbefitter/features/profile/services/measurement_prompt_rules.dart';
import 'package:icanbefitter/features/profile/widgets/body_measurements_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_chip.dart';

import '../helpers/dart_source_slice.dart';
import '../helpers/flutter_error_capture.dart';
import '../helpers/hive_test_setup.dart';

class _FakePrompt extends MeasurementPromptNotifier {
  _FakePrompt(this.value, this.log);

  final MeasurementPrompt value;
  final List<String> log;

  @override
  MeasurementPrompt build() => value;

  @override
  Future<void> dismiss() async => log.add('dismiss');

  @override
  Future<void> skipBaseline() async => log.add('skipBaseline');
}

class _FakeHistory extends BodyMeasurementsNotifier {
  @override
  BodyMeasurementsState build() => const BodyMeasurementsState(loaded: true);
}

final class _Created extends ProviderObserver {
  final List<ProviderBase<Object?>> providers = [];

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    providers.add(context.provider);
  }

  bool saw(ProviderBase<Object?> p) => providers.contains(p);
}

/// The chip over a real [TextField] with the given focus node, the way the
/// chat screen has its composer: between the chat area and the input bar.
///
/// [composerFollowsSending] disables the field while `isSending`, as the real
/// input bar does (`enabled: !isLimitReached && !isSending`): a disabled field
/// cannot keep focus. [chat] puts a scrolling list above the chip, as the chat
/// area is, inside a fixed 600 dp column.
Widget screen({
  required FocusNode node,
  bool isSending = false,
  double width = 360,
  bool composerFollowsSending = false,
  ScrollController? chat,
  ValueChanged<double>? onShown,
}) {
  final slot = MeasurementChipSlot(
    inputFocusNode: node,
    isSending: isSending,
    onShown: onShown,
  );
  final field = TextField(
    focusNode: node,
    enabled: composerFollowsSending ? !isSending : true,
  );
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: width,
          height: chat == null ? null : 600,
          child: chat == null
              ? Column(mainAxisSize: MainAxisSize.min, children: [slot, field])
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: chat,
                        padding: const EdgeInsets.all(22),
                        itemCount: 30,
                        itemBuilder: (_, i) =>
                            SizedBox(height: 60, child: Text('message $i')),
                      ),
                    ),
                    slot,
                    field,
                  ],
                ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('typography warmup - GoogleFonts caches before any Hive mock', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Text('a', style: AppTypography.body),
              Text('b', style: AppTypography.bodyS),
              Text('c', style: AppTypography.titleS),
              Text('d', style: AppTypography.mono),
              Text('e', style: AppTypography.monoXs),
              Text('f', style: AppTypography.label),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  group('MeasurementChipSlot over fake notifiers', () {
    late Directory dir;
    late List<String> log;
    late FocusNode node;

    setUp(() async {
      dir = await setUpHiveForTests();
      setTestClockTo(DateTime.utc(2031, 6, 15, 20));
      log = [];
      node = FocusNode();
    });

    tearDown(() async {
      node.dispose();
      resetTestClock();
      await tearDownHiveForTests(dir);
    });

    Widget host(
      MeasurementPrompt prompt, {
      bool isSending = false,
      double width = 360,
      double textScale = 1.0,
      bool flag = true,
      bool composerFollowsSending = false,
      ScrollController? chat,
      ValueChanged<double>? onShown,
    }) {
      return ProviderScope(
        overrides: [
          authUserIdTokenProvider.overrideWithValue(kTestUserId),
          measurementsEnabledProvider.overrideWithValue(flag),
          measurementPromptProvider.overrideWith(
            () => _FakePrompt(prompt, log),
          ),
          bodyMeasurementsProvider.overrideWith(_FakeHistory.new),
        ],
        child: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: screen(
            node: node,
            isSending: isSending,
            width: width,
            composerFollowsSending: composerFollowsSending,
            chat: chat,
            onShown: onShown,
          ),
        ),
      );
    }

    final chip = find.byType(WardChip);

    // ── the truth table: 3 prompts x sending x focus ────────────────────
    for (final prompt in MeasurementPrompt.values) {
      for (final sending in [false, true]) {
        for (final focused in [false, true]) {
          final visible =
              prompt != MeasurementPrompt.none && !sending && !focused;
          testWidgets('prompt ${prompt.name}, sending $sending, composer '
              '${focused ? 'focused' : 'unfocused'}: chip '
              '${visible ? 'visible' : 'hidden'}', (tester) async {
            await tester.pumpWidget(host(prompt, isSending: sending));
            if (focused) {
              node.requestFocus();
              await tester.pump(); // applies the focus change
              expect(node.hasFocus, isTrue, reason: 'precondition');
            }
            await tester.pump(); // rebuilds the ListenableBuilder
            expect(chip, visible ? findsOneWidget : findsNothing);
            expect(
              find.byIcon(Icons.close),
              visible ? findsOneWidget : findsNothing,
            );
          });
        }
      }
    }

    testWidgets('OFF flag: nothing, whatever the prompt', (tester) async {
      await tester.pumpWidget(host(MeasurementPrompt.due, flag: false));
      await tester.pump();
      expect(chip, findsNothing);
    });

    testWidgets('focus set AFTER mount hides the chip and blur brings it '
        'back', (tester) async {
      await tester.pumpWidget(host(MeasurementPrompt.due));
      await tester.pump();
      expect(chip, findsOneWidget);
      node.requestFocus();
      await tester.pump(); // applies the focus change
      await tester.pump(); // rebuilds the ListenableBuilder
      expect(node.hasFocus, isTrue, reason: 'precondition');
      expect(chip, findsNothing);
      node.unfocus();
      await tester.pump();
      await tester.pump();
      expect(node.hasFocus, isFalse, reason: 'precondition');
      expect(chip, findsOneWidget);
    });

    testWidgets('after a send the chip is back under the reply (sending true '
        'then false, composer unfocused)', (tester) async {
      await tester.pumpWidget(host(MeasurementPrompt.due));
      await tester.pump();
      expect(chip, findsOneWidget);
      await tester.pumpWidget(host(MeasurementPrompt.due, isSending: true));
      await tester.pump();
      expect(chip, findsNothing);
      await tester.pumpWidget(host(MeasurementPrompt.due));
      await tester.pump();
      expect(chip, findsOneWidget);
    });

    // The row above never focuses the composer, so it cannot tell a chip that
    // returns because the send ended from one that returns because nothing was
    // ever focused. The real input bar disables the field while sending, and a
    // disabled field drops focus: that is why the chip is back under the reply.
    testWidgets('a focused composer that a send disables drops focus, and the '
        'chip is back under the reply', (tester) async {
      await tester.pumpWidget(
        host(MeasurementPrompt.due, composerFollowsSending: true),
      );
      await tester.pump();
      node.requestFocus();
      await tester.pump();
      await tester.pump();
      expect(node.hasFocus, isTrue, reason: 'precondition: focused');
      expect(chip, findsNothing);
      await tester.pumpWidget(
        host(
          MeasurementPrompt.due,
          isSending: true,
          composerFollowsSending: true,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(
        node.hasFocus,
        isFalse,
        reason: 'precondition: a disabled field cannot keep focus',
      );
      expect(chip, findsNothing);
      await tester.pumpWidget(
        host(MeasurementPrompt.due, composerFollowsSending: true),
      );
      await tester.pump();
      await tester.pump();
      expect(node.hasFocus, isFalse, reason: 'nothing gave it back');
      expect(chip, findsOneWidget);
    });

    testWidgets('the label is the one verb "Add"', (tester) async {
      await tester.pumpWidget(host(MeasurementPrompt.due));
      await tester.pump();
      expect(find.text('ADD BODY MEASUREMENTS'), findsOneWidget);
      expect(
        find.byIcon(Icons.straighten),
        findsOneWidget,
        reason: 'the tape-measure glyph leads the label',
      );
      expect(
        tester.widget<WardChip>(chip).tone,
        WardChipTone.gold,
        reason: 'a gold accent pill, never a status colour',
      );
    });

    testWidgets('the pill sits on the gutter and the X on the right edge, 4 dp '
        'in', (tester) async {
      await tester.pumpWidget(host(MeasurementPrompt.due));
      await tester.pump();
      final slot = tester.getRect(find.byType(MeasurementChipSlot));
      expect(tester.getRect(chip).left, slot.left + AppSpacing.gutter);
      final x = find.ancestor(
        of: find.byIcon(Icons.close),
        matching: find.byType(InkWell),
      );
      expect(tester.getRect(x).right, slot.right - 4);
    });

    // ── one tap target, one node ────────────────────────────────────────

    testWidgets('a tap at the pill centre opens exactly one sheet', (
      tester,
    ) async {
      await tester.pumpWidget(host(MeasurementPrompt.due));
      await tester.pump();
      await tester.tapAt(tester.getCenter(chip));
      await tester.pumpAndSettle();
      expect(find.byType(BodyMeasurementsSheet), findsOneWidget);
      expect(log, isEmpty, reason: 'the pill does not dismiss');
    });

    testWidgets('a tap in the padding around the pill (inside the 44 dp '
        'target) opens exactly one sheet', (tester) async {
      await tester.pumpWidget(host(MeasurementPrompt.due));
      await tester.pump();
      final pill = tester.getRect(chip);
      final target = tester.getRect(find.byType(InkWell).first);
      expect(pill.height, lessThan(44), reason: 'precondition: a small pill');
      expect(target.height, greaterThanOrEqualTo(44));
      // 2 dp inside the target's top edge: above the pill, in the padding.
      final point = Offset(pill.center.dx, target.top + 2);
      expect(
        pill.contains(point),
        isFalse,
        reason: 'precondition: off the pill',
      );
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(find.byType(BodyMeasurementsSheet), findsOneWidget);
    });

    testWidgets('semantics: ONE button node with the label, and the pill text '
        'is not announced again', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(MeasurementPrompt.due));
      await tester.pump();
      final node = find.bySemanticsLabel('Add body measurements');
      expect(node, findsOneWidget);
      expect(tester.getSemantics(node).flagsCollection.isButton, isTrue);
      expect(find.bySemanticsLabel(RegExp('ADD BODY')), findsNothing);
      // Each control excludes its descendants' semantics, so the node's own tap
      // action is the ONLY way a screen reader's double tap reaches it: a
      // control that declares a label and a role but no action is a button
      // that does nothing. This throws if the node has no tap action.
      tester.semantics.tap(find.semantics.byLabel('Add body measurements'));
      await tester.pumpAndSettle();
      expect(find.byType(BodyMeasurementsSheet), findsOneWidget);
      expect(log, isEmpty, reason: 'the pill does not dismiss');
      handle.dispose();
    });

    // ── the X ───────────────────────────────────────────────────────────

    testWidgets('the X is 44 x 44 with the dismiss label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(MeasurementPrompt.due));
      await tester.pump();
      final x = find.ancestor(
        of: find.byIcon(Icons.close),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(x), const Size(44, 44));
      final label = find.bySemanticsLabel('Dismiss measurements reminder');
      expect(label, findsOneWidget);
      expect(tester.getSemantics(label).flagsCollection.isButton, isTrue);
      tester.semantics.tap(
        find.semantics.byLabel('Dismiss measurements reminder'),
      );
      await tester.pumpAndSettle();
      expect(log, ['dismiss'], reason: 'the X has its own tap action');
      expect(find.byType(BodyMeasurementsSheet), findsNothing);
      handle.dispose();
    });

    testWidgets('a tap on the X dismisses and does NOT open the sheet', (
      tester,
    ) async {
      await tester.pumpWidget(host(MeasurementPrompt.due));
      await tester.pump();
      await tester.tapAt(tester.getCenter(find.byIcon(Icons.close)));
      await tester.pumpAndSettle();
      expect(find.byType(BodyMeasurementsSheet), findsNothing);
      expect(log, ['dismiss']);
    });

    testWidgets('the X on a baseline chip calls skipBaseline, not dismiss', (
      tester,
    ) async {
      await tester.pumpWidget(host(MeasurementPrompt.baseline));
      await tester.pump();
      await tester.tapAt(tester.getCenter(find.byIcon(Icons.close)));
      await tester.pumpAndSettle();
      expect(find.byType(BodyMeasurementsSheet), findsNothing);
      expect(log, ['skipBaseline']);
    });

    testWidgets('a failing dismiss is logged, not thrown', (tester) async {
      final events = <String>[];
      ErrorTelemetry.debugOnLogEventForTests = (op, {message}) =>
          events.add(op);
      addTearDown(() => ErrorTelemetry.debugOnLogEventForTests = null);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserIdTokenProvider.overrideWithValue(kTestUserId),
            measurementsEnabledProvider.overrideWithValue(true),
            measurementPromptProvider.overrideWith(_ThrowingPrompt.new),
            bodyMeasurementsProvider.overrideWith(_FakeHistory.new),
          ],
          child: screen(node: node),
        ),
      );
      await tester.pump();
      await tester.tapAt(tester.getCenter(find.byIcon(Icons.close)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(events, contains('measurement_chip_dismiss_failed'));
    });

    testWidgets('320 dp wide at 2x text: no overflow', (tester) async {
      final capture = FlutterErrorCapture()..start();
      addTearDown(capture.stop);
      await tester.pumpWidget(
        host(MeasurementPrompt.due, width: 320, textScale: 2.0),
      );
      await tester.pump();
      capture.stop();
      expect(chip, findsOneWidget);
      expect(capture.messages, isEmpty, reason: capture.messages.join('\n'));
    });

    // ── the chat above the chip ─────────────────────────────────────────
    //
    // The chip appears AFTER the reply landed and the chat scrolled to it (it
    // returns when isSending ends) and takes its height from the chat, so the
    // last message would sit under the chip until the next scroll. The host
    // passes keepBottomAfterChip as onShown; the screen itself cannot be
    // pumped, so these rows are a chat-like column of the same shape.

    Widget chatHost(
      ScrollController chat, {
      required bool sending,
      List<double>? shown,
      bool follow = true,
    }) => host(
      MeasurementPrompt.due,
      isSending: sending,
      chat: chat,
      onShown: (height) {
        shown?.add(height);
        if (follow) keepBottomAfterChip(chat, height);
      },
    );

    testWidgets('a chip appearing under a chat at its bottom keeps the last '
        'message in view', (tester) async {
      final chat = ScrollController();
      addTearDown(chat.dispose);
      final shown = <double>[];
      await tester.pumpWidget(chatHost(chat, sending: true, shown: shown));
      await tester.pump();
      chat.jumpTo(chat.position.maxScrollExtent);
      await tester.pump();
      expect(
        chat.position.extentAfter,
        0,
        reason: 'precondition: at the bottom',
      );
      expect(chip, findsNothing, reason: 'precondition: still sending');
      await tester.pumpWidget(chatHost(chat, sending: false, shown: shown));
      await tester.pumpAndSettle();
      expect(chip, findsOneWidget);
      expect(shown, hasLength(1));
      expect(shown.single, greaterThanOrEqualTo(44));
      expect(chat.position.extentAfter, closeTo(0, 0.5));
    });

    // The control that gives the row above its meaning: without the follow the
    // chat IS left short by the slot's height, so the row can see the difference.
    testWidgets('control: without the follow the chat is left short by the '
        'height the slot took', (tester) async {
      final chat = ScrollController();
      addTearDown(chat.dispose);
      final shown = <double>[];
      await tester.pumpWidget(
        chatHost(chat, sending: true, shown: shown, follow: false),
      );
      await tester.pump();
      chat.jumpTo(chat.position.maxScrollExtent);
      await tester.pump();
      await tester.pumpWidget(
        chatHost(chat, sending: false, shown: shown, follow: false),
      );
      await tester.pumpAndSettle();
      expect(chip, findsOneWidget);
      expect(chat.position.extentAfter, closeTo(shown.single, 0.5));
    });

    testWidgets('a chat scrolled up (reading older messages) is not moved', (
      tester,
    ) async {
      final chat = ScrollController();
      addTearDown(chat.dispose);
      await tester.pumpWidget(chatHost(chat, sending: true));
      await tester.pump();
      chat.jumpTo(400);
      await tester.pump();
      expect(
        chat.position.extentAfter,
        greaterThan(500),
        reason: 'precondition: well above the bottom',
      );
      await tester.pumpWidget(chatHost(chat, sending: false));
      await tester.pumpAndSettle();
      expect(chip, findsOneWidget);
      expect(chat.offset, 400);
    });

    testWidgets('onShown fires once per appearance, not per rebuild, and '
        'never while the chip is hidden', (tester) async {
      final chat = ScrollController();
      addTearDown(chat.dispose);
      final shown = <double>[];
      await tester.pumpWidget(chatHost(chat, sending: false, shown: shown));
      await tester.pumpAndSettle();
      expect(shown, hasLength(1), reason: 'first appearance');
      await tester.pumpWidget(chatHost(chat, sending: false, shown: shown));
      await tester.pumpAndSettle();
      expect(shown, hasLength(1), reason: 'a rebuild is not an appearance');
      await tester.pumpWidget(chatHost(chat, sending: true, shown: shown));
      await tester.pumpAndSettle();
      expect(shown, hasLength(1), reason: 'hidden: nothing to announce');
      await tester.pumpWidget(chatHost(chat, sending: false, shown: shown));
      await tester.pumpAndSettle();
      expect(shown, hasLength(2), reason: 'back under the reply');
      node.requestFocus();
      await tester.pump();
      await tester.pump();
      expect(shown, hasLength(2), reason: 'hidden by the composer focus');
      node.unfocus();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(shown, hasLength(3), reason: 'back after the composer blurs');
    });

    testWidgets('an OFF slot and a prompt of none never call onShown', (
      tester,
    ) async {
      final chat = ScrollController();
      addTearDown(chat.dispose);
      final shown = <double>[];
      await tester.pumpWidget(
        host(
          MeasurementPrompt.due,
          flag: false,
          chat: chat,
          onShown: shown.add,
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        host(MeasurementPrompt.none, chat: chat, onShown: shown.add),
      );
      await tester.pumpAndSettle();
      expect(chip, findsNothing);
      expect(shown, isEmpty);
    });

    testWidgets('keepBottomAfterChip with no list attached (the Telegram '
        'view) does nothing and does not throw', (tester) async {
      final chat = ScrollController();
      addTearDown(chat.dispose);
      keepBottomAfterChip(chat, 44);
      expect(chat.hasClients, isFalse);
    });

    test('presence only: the slot cannot send a message (its file has no '
        'send callback and no sendMessage)', () {
      // The slot is mounted alone in these tests (no send pipeline exists to
      // observe), so "a tap cannot send" is carried by the source: no send
      // call and no callback parameter that could carry one.
      final src = stripDartComments(
        File(
          'lib/features/ai_coach/widgets/measurement_chip_slot.dart',
        ).readAsStringSync(),
      );
      expect(src.contains('sendMessage'), isFalse);
      expect(src.contains('onSend'), isFalse);
      expect(src.contains('_sendMessage'), isFalse);
    });
  });

  // The slot over the REAL notifiers (nothing overridden but the token): the
  // fakes above return a constant, so they cannot tell a slot that WATCHES its
  // state from one that read it once.
  group('MeasurementChipSlot on the real graph', () {
    late Directory dir;
    late FocusNode node;

    setUp(() async {
      dir = await setUpHiveForTests();
      setTestClockTo(DateTime.utc(2031, 6, 15, 20));
      node = FocusNode();
      SyncService.pausedForSimulation = true;
    });

    tearDown(() async {
      SyncService.pausedForSimulation = false;
      node.dispose();
      resetTestClock();
      await tearDownHiveForTests(dir);
    });

    Future<void> plant(
      WidgetTester tester, {
      required bool flag,
      String? lastEntry,
      bool corrupt = false,
    }) async {
      await tester.runAsync(() async {
        await HiveService.instance.configBox.put(
          'enable_body_measurements',
          flag,
        );
        await HiveService.instance.userBox.put('profile', <String, dynamic>{
          'full_name': 'Test',
          'onboarding_completed_at': '2031-01-01T00:00:00Z',
        });
        if (lastEntry != null) {
          await HiveService.instance.healthBox.put('measurement_$lastEntry', {
            'id': 'meas_$lastEntry',
            'date': lastEntry,
            'waist': 80.0,
            'created_at': '${lastEntry}T01:00:00.000Z',
            'updated_at_ms': 1,
          });
        }
        if (corrupt) {
          await HiveService.instance.healthBox.put(
            'measurement_2031-04-01',
            'not a map',
          );
          await HiveService.instance.healthBox.put('measurement_garbage', {
            'date': 12345,
            'waist': 'x',
          });
        }
      });
    }

    Future<ProviderContainer> mount(
      WidgetTester tester, {
      ProviderObserver? observer,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          observers: [?observer],
          overrides: [authUserIdTokenProvider.overrideWithValue(kTestUserId)],
          child: screen(node: node),
        ),
      );
      await tester.pump();
      return ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
      );
    }

    /// Fires the X's callback in the REAL zone (the notifier writes Hive).
    Future<void> tapX(WidgetTester tester) async {
      final x = find.ancestor(
        of: find.byIcon(Icons.close),
        matching: find.byType(InkWell),
      );
      await tester.runAsync(() async {
        tester.widget<InkWell>(x.first).onTap!();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
    }

    final chip = find.byType(WardChip);

    testWidgets('due: the chip shows; the X hides it afterwards, no parent '
        'rebuild', (tester) async {
      await plant(tester, flag: true, lastEntry: '2031-05-01');
      final container = await mount(tester);
      expect(
        container.read(measurementPromptProvider),
        MeasurementPrompt.due,
        reason: 'precondition: the prompt this row is named after',
      );
      expect(chip, findsOneWidget);
      await tapX(tester);
      expect(chip, findsNothing);
    });

    testWidgets('baseline (never measured): the chip shows; the X hides it', (
      tester,
    ) async {
      await plant(tester, flag: true);
      final container = await mount(tester);
      expect(
        container.read(measurementPromptProvider),
        MeasurementPrompt.baseline,
        reason: 'precondition: the prompt this row is named after',
      );
      expect(chip, findsOneWidget);
      await tapX(tester);
      expect(chip, findsNothing);
    });

    testWidgets('a real save() clears the due prompt under a mounted slot', (
      tester,
    ) async {
      await plant(tester, flag: true, lastEntry: '2031-05-01');
      final container = await mount(tester);
      expect(
        container.read(measurementPromptProvider),
        MeasurementPrompt.due,
        reason: 'precondition: due before the save',
      );
      expect(chip, findsOneWidget);
      late WriteResult result;
      await tester.runAsync(() async {
        result = await container
            .read(measurementWriteProvider.notifier)
            .save(
              sites: {'waist': 79.5},
              source: WriteSource.manual,
              inchesUsed: false,
            );
      });
      await tester.pumpAndSettle();
      expect(result.success, isTrue, reason: 'precondition: the write landed');
      expect(chip, findsNothing);
    });

    testWidgets(
      'switching the flag off under a mounted slot removes the chip',
      (tester) async {
        await plant(tester, flag: true, lastEntry: '2031-05-01');
        final container = await mount(tester);
        expect(chip, findsOneWidget);
        await tester.runAsync(
          () => HiveService.instance.configBox.put(
            'enable_body_measurements',
            false,
          ),
        );
        container.invalidate(measurementsEnabledProvider);
        await tester.pumpAndSettle();
        expect(chip, findsNothing);
      },
    );

    // The mirror, which pins `watch` over `read`: an OFF slot returns before it
    // watches the prompt, so the flag watch is its only subscription.
    testWidgets('switching the flag ON under a mounted OFF slot shows the '
        'chip', (tester) async {
      await plant(tester, flag: false, lastEntry: '2031-05-01');
      final container = await mount(tester);
      expect(chip, findsNothing);
      await tester.runAsync(
        () => HiveService.instance.configBox.put(
          'enable_body_measurements',
          true,
        ),
      );
      container.invalidate(measurementsEnabledProvider);
      await tester.pumpAndSettle();
      expect(chip, findsOneWidget);
    });

    testWidgets('OFF creates neither the prompt nor the history provider, '
        'even over a planted corrupt record (ON is the positive control)', (
      tester,
    ) async {
      final off = _Created();
      await plant(tester, flag: false, lastEntry: '2031-05-01', corrupt: true);
      await mount(tester, observer: off);
      expect(chip, findsNothing);
      expect(off.saw(measurementPromptProvider), isFalse);
      expect(off.saw(bodyMeasurementsProvider), isFalse);

      await tester.pumpWidget(const SizedBox());
      final on = _Created();
      await plant(tester, flag: true, lastEntry: '2031-05-01', corrupt: true);
      await mount(tester, observer: on);
      expect(on.saw(measurementPromptProvider), isTrue);
      expect(chip, findsOneWidget);
    });
  });
}

class _ThrowingPrompt extends MeasurementPromptNotifier {
  @override
  MeasurementPrompt build() => MeasurementPrompt.due;

  @override
  Future<void> dismiss() async => throw StateError('write failed');

  // Both X paths fail: if the slot called the other method, the real write
  // would start inside the fake-async zone and never complete, which hangs the
  // test's teardown instead of failing it.
  @override
  Future<void> skipBaseline() async => throw StateError('write failed');
}
