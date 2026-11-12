// WIDGET TEST — OI-479 "Clear conversation" UI (diagnose 5970aa; plan
// docs/plans/2026-11-12-oi479-clear-conversation.md, test T8).
//
// * The menu item is disabled while a reply is in flight.
// * The item opens a dialog; CANCEL changes nothing; CLEAR stamps the marker,
//   pushes it and the thread re-renders hidden.
// * A send that starts while the dialog is open makes CLEAR a no-op (that
//   turn's row predates the marker; its reply would vanish).
// * A clear that throws is reported (coach_chat_clear_failed) and told.
// * Pending action cards are not touched by a clear (coordinator call C2).
@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/coach_chat_clear.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/screens/ai_coach/screen.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';

import '../helpers/hive_test_setup.dart';

class _FakeSend extends SendMessageNotifier {
  @override
  bool build() => false;
  void setSending(bool v) => state = v;
}

const _menuKey = ValueKey('coach-menu');

void main() {
  // Hive is opened LAZILY by the first test that needs it, inside
  // tester.runAsync: opening it in setUpAll mocks path_provider before the
  // font warm-up, and GoogleFonts then fails loudly (root CLAUDE.md 4.9).
  Directory? dir;
  final pushed = <String>[];

  Future<void> hiveReady(WidgetTester tester) async {
    dir ??= await tester.runAsync(setUpHiveForTests);
    // ignore: invalid_use_of_visible_for_testing_member
    HiveUserSession.debugCurrentUidResolverForTests = () => kTestUserId;
    CoachChatClear.debugPushOverride = (owner) async => pushed.add(owner);
    pushed.clear();
    await tester.runAsync(() async {
      await HiveService.instance.coachBox.clear();
      await HiveService.instance.userBox.delete(CoachChatClear.markerKey);
    });
  }

  tearDownAll(() async {
    CoachChatClear.debugPushOverride = null;
    // ignore: invalid_use_of_visible_for_testing_member
    HiveUserSession.debugCurrentUidResolverForTests = null;
    if (dir != null) await tearDownHiveForTests(dir!);
  });

  // Root CLAUDE.md 4.9: the first test renders every font family used later.
  testWidgets('typography warmup', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Text('a', style: AppTypography.body),
              Text('b', style: AppTypography.monoXs),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  Future<void> pumpMenu(WidgetTester tester, {required bool isSending}) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(0.6)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: PopupMenuButton<String>(
              key: _menuKey,
              itemBuilder: (context) =>
                  coachHeaderMenuItems(isPro: true, isSending: isSending),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(_menuKey));
    await tester.pumpAndSettle();
  }

  PopupMenuItem<String> clearItem(WidgetTester tester) => tester
      .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
      .singleWhere((w) => w.value == 'clear');

  testWidgets('the item is disabled while a reply is in flight', (
    tester,
  ) async {
    await pumpMenu(tester, isSending: true);
    expect(clearItem(tester).enabled, isFalse);
  });

  testWidgets('the item is enabled when nothing is sending', (tester) async {
    await pumpMenu(tester, isSending: false);
    expect(clearItem(tester).enabled, isTrue);
  });

  late BuildContext hostContext;
  late WidgetRef hostRef;

  Future<ProviderContainer> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserIdTokenProvider.overrideWithValue(kTestUserId),
          sendMessageProvider.overrideWith(_FakeSend.new),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                hostContext = context;
                hostRef = ref;
                final users = ref
                    .watch(chatHistoryProvider)
                    .where((m) => m.isUser)
                    .length;
                return Column(
                  children: [
                    Text('users=$users'),
                    TextButton(
                      onPressed: () =>
                          confirmClearCoachConversation(context, ref),
                      child: const Text('open'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    return ProviderScope.containerOf(tester.element(find.text('open')));
  }

  Future<void> seedChat(WidgetTester tester) async {
    await hiveReady(tester);
    await tester.runAsync(
      () => HiveService.instance.coachBox.put('coach_1', {
        'id': 'coach_1',
        'user_message': 'q',
        'ai_response': 'a',
        'mode': 'quick',
        'created_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
      }),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('CANCEL changes nothing', (tester) async {
    await seedChat(tester);
    await pumpHost(tester);
    expect(find.text('users=1'), findsOneWidget);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Clear this chat?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('coach_clear_cancel')));
    await settle(tester);
    expect(CoachChatClear.clearedAt(), isNull);
    expect(pushed, isEmpty);
    expect(find.text('users=1'), findsOneWidget);
  });

  testWidgets('CLEAR stamps the marker, pushes it, and the thread hides', (
    tester,
  ) async {
    await seedChat(tester);
    await pumpHost(tester);
    // The flow is STARTED inside runAsync, so the code after the dialog (a
    // real Hive write) runs in the real zone; a write started from a tap in
    // the fake-async zone never drains and hangs the next Hive call (the
    // pattern of coach_day_completion_behavioral_test.dart).
    late Future<void> flow;
    await tester.runAsync(() async {
      flow = confirmClearCoachConversation(hostContext, hostRef);
    });
    await tester.pumpAndSettle();
    expect(find.text('Clear this chat?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('coach_clear_confirm')));
    await tester.pump();
    await tester.runAsync(() => flow);
    await tester.pumpAndSettle();
    expect(CoachChatClear.clearedAt(), isNotNull);
    expect(pushed, [kTestUserId]);
    expect(find.text('users=0'), findsOneWidget);
  });

  testWidgets('a send that starts while the dialog is open cancels the clear', (
    tester,
  ) async {
    await seedChat(tester);
    final container = await pumpHost(tester);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    (container.read(sendMessageProvider.notifier) as _FakeSend).setSending(
      true,
    );
    await tester.tap(find.byKey(const ValueKey('coach_clear_confirm')));
    await settle(tester);
    expect(CoachChatClear.clearedAt(), isNull);
    expect(pushed, isEmpty);
    expect(find.text('users=1'), findsOneWidget);
  });

  testWidgets('a clear that throws is reported and told, never uncaught '
      '(B-pass F2)', (tester) async {
    await seedChat(tester);
    await pumpHost(tester);
    final reasons = <String>[];
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (e, st, {required reason, extra}) => reasons.add(reason);
    // A synchronous throw from the push call is a throw out of clear() itself
    // (the production push is async; this stands in for a closed user box).
    CoachChatClear.debugPushOverride = (_) => throw StateError('box closed');
    addTearDown(() {
      ErrorTelemetry.debugOnRecordNonFatalForTests = null;
      CoachChatClear.debugPushOverride = (owner) async => pushed.add(owner);
    });
    late Future<void> flow;
    await tester.runAsync(() async {
      flow = confirmClearCoachConversation(hostContext, hostRef);
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('coach_clear_confirm')));
    await tester.pump();
    // Without the catch, this await rethrows the StateError.
    await tester.runAsync(() => flow);
    await tester.pumpAndSettle();
    expect(reasons, ['coach_chat_clear_failed']);
    expect(find.text("Couldn't clear this chat. Try again."), findsOneWidget);
  });

  test('C2: the clear flow never touches the pending action cards', () {
    final src = File(
      'lib/features/ai_coach/screens/ai_coach/compact_header.dart',
    ).readAsStringSync();
    final start = src.indexOf('Future<void> confirmClearCoachConversation(');
    final end = src.indexOf('\n}\n', start);
    final body = src.substring(start, end);
    for (final p in const [
      'pendingLogActionsProvider',
      'pendingToolIntentsProvider',
      'workoutDraftProvider',
    ]) {
      expect(body.contains(p), isFalse, reason: '$p must survive a clear');
    }
  });
}
