@Timeout(Duration(minutes: 3))
library;

// L2b Landing B (B7, section 4.6) - the live chat path
// (ConversationalLogHandler._logMeasurement). With the flag OFF the handler
// reads NO provider (a measurement written from chat is byte-identical to
// before); with the flag ON a successful write refreshes the measurements
// history through the notifier's own Ref; and neither the notifier lookup nor
// the refresh may turn a successful write into the catch-all's `false`.
//
// The handler needs a WidgetRef, which is sealed: a real one is captured from a
// Consumer, and Hive I/O runs under tester.runAsync.
//
// Plan: docs/plans/coach-measurement-sheet-ui.md (B7, section 4)

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/services/conversational_log_handler.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_flag_provider.dart';

import '../helpers/hive_test_setup.dart';

final class _Created extends ProviderObserver {
  final List<ProviderBase<Object?>> providers = [];

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    providers.add(context.provider);
  }

  bool saw(ProviderBase<Object?> p) => providers.contains(p);
}

class _Counting extends MeasurementWriteNotifier {
  int noted = 0;
  @override
  void noteWritten() {
    noted++;
    super.noteWritten();
  }
}

class _ThrowingNote extends MeasurementWriteNotifier {
  int attempts = 0;
  @override
  void noteWritten() {
    attempts++;
    throw StateError('noteWritten blew up');
  }
}

class _ThrowingBuild extends MeasurementWriteNotifier {
  @override
  void build() => throw StateError('build blew up');
}

typedef _Captured = ({WidgetRef ref, ProviderContainer container});

class _Capture extends ConsumerStatefulWidget {
  const _Capture({required this.onCapture});
  final void Function(_Captured) onCapture;

  @override
  ConsumerState<_Capture> createState() => _CaptureState();
}

class _CaptureState extends ConsumerState<_Capture> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onCapture(
          (ref: ref, container: ProviderScope.containerOf(context)));
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

PendingLogAction _action(String site, num cm) => PendingLogAction(
      id: 'a1',
      type: LogActionType.measurement,
      data: {'type': site, 'value_cm': cm},
      displayText: '$site: $cm',
    );

void main() {
  late Directory dir;
  late _Created obs;
  late List<({String op, String? message})> events;

  // The handler dates the record with the REAL clock (`DateTime.now()`, the
  // handler's own line), so nothing here pins the clock to a calendar day or
  // reads a fixed `measurement_<day>` key: a fixture frozen on the authoring day
  // goes red the next day with no code change (B-pass reviewer B, finding 1).
  // The seam clock stays unpinned, so the writer, the history reader's
  // future-date filter and the handler agree on one day.
  setUp(() async {
    dir = await setUpHiveForTests();
    SyncService.pausedForSimulation = true;
    resetTestClock();
    obs = _Created();
    events = [];
    ErrorTelemetry.debugOnLogEventForTests =
        (op, {message}) => events.add((op: op, message: message));
  });

  tearDown(() async {
    ErrorTelemetry.debugOnLogEventForTests = null;
    SyncService.pausedForSimulation = false;
    resetTestClock();
    await tearDownHiveForTests(dir);
  });

  /// The one `measurement_<day>` record the chat write produced, whatever day
  /// the clock says it is.
  Future<Map> theRecord(WidgetTester tester) async {
    final recs = await tester.runAsync(() async {
      final box = HiveService.instance.healthBox;
      return [
        for (final k in box.keys)
          if (k.toString().startsWith('measurement_')) box.get(k),
      ];
    });
    expect(recs, hasLength(1), reason: 'exactly one day record');
    return recs!.single as Map;
  }

  Future<_Captured> mount(
    WidgetTester tester, {
    required bool flag,
    List<dynamic> extra = const [],
  }) async {
    await tester.runAsync(() => HiveService.instance.configBox
        .put('enable_body_measurements', flag));
    final completer = Completer<_Captured>();
    await tester.pumpWidget(ProviderScope(
      observers: [obs],
      overrides: [
        authUserIdTokenProvider.overrideWithValue(kTestUserId),
        ...extra.cast(),
      ],
      child: _Capture(onCapture: completer.complete),
    ));
    await tester.pump();
    return (await tester.runAsync(() => completer.future))!;
  }

  Future<bool?> run(WidgetTester tester, _Captured c, PendingLogAction a) =>
      tester.runAsync(() => ConversationalLogHandler(c.ref).executeAction(a));

  testWidgets('flag OFF: a chat measurement is written, returns true and no '
      'measurements provider is created', (tester) async {
    final c = await mount(tester, flag: false);
    expect(await run(tester, c, _action('waist', 80)), isTrue);
    expect((await theRecord(tester))['waist'], 80.0);
    // Control: the observer does see a provider the container creates.
    c.container.read(pendingLogActionsProvider);
    expect(obs.saw(pendingLogActionsProvider), isTrue);
    expect(obs.saw(measurementWriteProvider), isFalse);
    expect(obs.saw(bodyMeasurementsProvider), isFalse);
    // "No provider read at all": the flag is read through the static getter,
    // never through the flag provider (which would create it).
    expect(obs.saw(measurementsEnabledProvider), isFalse);
    expect(events, isEmpty, reason: 'the OFF path reports nothing');
  });

  testWidgets('flag ON: the successful write refreshes a live history '
      'provider (a new state object that holds the site)', (tester) async {
    final c = await mount(tester, flag: true);
    final sub = c.container.listen(bodyMeasurementsProvider, (_, _) {});
    addTearDown(sub.close);
    final before = c.container.read(bodyMeasurementsProvider);
    expect(before.latest, isEmpty);

    expect(await run(tester, c, _action('waist', 80)), isTrue);

    final after = c.container.read(bodyMeasurementsProvider);
    expect(identical(before, after), isFalse, reason: 'it was refreshed');
    expect(after.latest['waist']?.cm, 80.0);
    expect(obs.saw(measurementWriteProvider), isTrue);
  });

  testWidgets('flag ON: noteWritten is called once after a success and never '
      'after a refused write', (tester) async {
    final counting = _Counting();
    final c = await mount(tester,
        flag: true,
        extra: [measurementWriteProvider.overrideWith(() => counting)]);
    expect(await run(tester, c, _action('waist', 80)), isTrue);
    expect(counting.noted, 1);
    // 3000 cm passes the handler's own guard (> 0) and is refused by the writer.
    expect(await run(tester, c, _action('waist', 3000)), isFalse);
    expect(counting.noted, 1, reason: 'a failed write refreshes nothing');
  });

  testWidgets('flag ON: a noteWritten that throws still returns true',
      (tester) async {
    final throwing = _ThrowingNote();
    final c = await mount(tester,
        flag: true,
        extra: [measurementWriteProvider.overrideWith(() => throwing)]);
    expect(await run(tester, c, _action('waist', 80)), isTrue);
    expect(throwing.attempts, 1);
    final failed =
        events.where((e) => e.op == 'measurement_chat_refresh_failed');
    expect(failed, hasLength(1));
    expect(failed.single.message, 'stage=note');
  });

  testWidgets('flag ON: a clean write and a clean refresh report nothing',
      (tester) async {
    final c = await mount(tester, flag: true);
    expect(await run(tester, c, _action('waist', 80)), isTrue);
    expect(events, isEmpty);
  });

  testWidgets('flag ON: a notifier that cannot be built still returns true',
      (tester) async {
    final c = await mount(tester,
        flag: true,
        extra: [measurementWriteProvider.overrideWith(_ThrowingBuild.new)]);
    expect(await run(tester, c, _action('waist', 80)), isTrue);
    expect((await theRecord(tester))['waist'], 80.0);
    // Riverpod hands back the notifier object of a void notifier whose build
    // threw without rethrowing at the lookup, and its `noteWritten` then
    // invalidates a provider that was never built: nothing fails, so nothing is
    // reported. (The two rows below are the ones that DO reach the catches.)
    expect(events, isEmpty);
  });

  testWidgets('flag ON: a provider whose creation throws still returns true '
      '(the notifier lookup is guarded)', (tester) async {
    final c = await mount(tester, flag: true, extra: [
      measurementWriteProvider.overrideWith(
          () => throw StateError('creation blew up')),
    ]);
    expect(await run(tester, c, _action('waist', 80)), isTrue);
    expect((await theRecord(tester))['waist'], 80.0);
    final failed =
        events.where((e) => e.op == 'measurement_chat_refresh_failed');
    expect(failed, hasLength(1));
    expect(failed.single.message, 'stage=lookup');
  });

  testWidgets('flag ON: the handler\'s own guards are unchanged (unknown site, '
      'zero)', (tester) async {
    final c = await mount(tester, flag: true);
    expect(await run(tester, c, _action('thighs', 50)), isFalse);
    expect(await run(tester, c, _action('waist', 0)), isFalse);
  });
}
