// HARNESS NOTE (GoogleFonts pitfall, root CLAUDE.md section 4.9): the first test
// of the widget group is a typography warmup that runs before any path_provider
// mock is installed. Reference: test/widgets/day_swap_allowance_line_test.dart.
@Timeout(Duration(minutes: 4))
library;

// L2b Landing B (section 4.6) - FLAG-OFF IDENTITY. With
// configBox['enable_body_measurements'] absent or false, no measurements
// provider is created on any installation path: the Home slot, the Weight sheet
// and the prompt provider read the flag first and stop there. Observer-based:
// a ProviderObserver records every provider the container creates, so "nothing
// was created" is a statement about the container and not about a widget tree.
//
// Every "not created" assertion sits next to a POSITIVE CONTROL on the same
// installation path (the flag ON creates the provider): an observer that saw
// nothing at all would otherwise pass every row.
//
// Plan: docs/plans/coach-measurement-sheet-ui.md (section 4.6, section 4)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/measurement_flags.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/home/widgets/measurement_due_banner.dart';
import 'package:icanbefitter/features/home/widgets/measurement_due_slot.dart';
import 'package:icanbefitter/features/home/widgets/weight_log_sheet.dart';
import 'package:icanbefitter/features/profile/providers/body_measurements_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_flag_provider.dart';
import 'package:icanbefitter/features/profile/providers/measurement_prompt_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/profile/services/measurement_prompt_rules.dart';

import '../helpers/dart_source_slice.dart';
import '../helpers/flutter_error_capture.dart';
import '../helpers/hive_test_setup.dart';

final class _Created extends ProviderObserver {
  final List<ProviderBase<Object?>> providers = [];

  @override
  void didAddProvider(ProviderObserverContext context, Object? value) {
    providers.add(context.provider);
  }

  bool saw(ProviderBase<Object?> p) => providers.contains(p);
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
              Text('f', style: AppTypography.display),
              Text('g', style: AppTypography.label),
              Text('h', style: AppTypography.numeric),
              Text('i', style: AppTypography.buttonLabel),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  // ── (e) the flag getter ────────────────────────────────────────────────────

  group('MeasurementFlags.bodyMeasurementsEnabled', () {
    test(
      'an unopened box is OFF (a pure unit test that never opened Hive)',
      () {
        expect(MeasurementFlags.bodyMeasurementsEnabled, isFalse);
      },
    );

    group('with Hive', () {
      late Directory dir;
      setUp(() async => dir = await setUpHiveForTests());
      tearDown(() async => tearDownHiveForTests(dir));

      test('absent is OFF', () {
        expect(MeasurementFlags.bodyMeasurementsEnabled, isFalse);
      });

      test('true is ON', () async {
        await HiveService.instance.configBox.put(
          'enable_body_measurements',
          true,
        );
        expect(MeasurementFlags.bodyMeasurementsEnabled, isTrue);
      });

      test('false, the string "true", 1 and null are OFF (the getter is '
          '== true, not truthy)', () async {
        for (final v in <Object?>[false, 'true', 1, 'on']) {
          await HiveService.instance.configBox.put(
            'enable_body_measurements',
            v,
          );
          expect(
            MeasurementFlags.bodyMeasurementsEnabled,
            isFalse,
            reason: '$v',
          );
        }
        await HiveService.instance.configBox.delete('enable_body_measurements');
        expect(MeasurementFlags.bodyMeasurementsEnabled, isFalse);
      });
    });
  });

  // ── (a) the prompt provider, read directly ────────────────────────────────

  group('measurementPromptProvider', () {
    late Directory dir;
    late _Created obs;

    setUp(() async {
      dir = await setUpHiveForTests();
      obs = _Created();
    });
    tearDown(() async => tearDownHiveForTests(dir));

    ProviderContainer container() {
      final c = ProviderContainer(
        observers: [obs],
        overrides: [authUserIdTokenProvider.overrideWithValue(kTestUserId)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('flag OFF: none, and neither the history nor the profile provider is '
        'ever created', () {
      final c = container();
      final sub = c.listen(measurementPromptProvider, (_, _) {});
      addTearDown(sub.close);
      expect(c.read(measurementPromptProvider), MeasurementPrompt.none);
      expect(
        obs.saw(measurementsEnabledProvider),
        isTrue,
        reason: 'control: the flag provider itself IS created',
      );
      expect(obs.saw(bodyMeasurementsProvider), isFalse);
      expect(
        obs.saw(userProfileProvider),
        isFalse,
        reason: 'the profile (the onboarding stamp) is read only past the flag',
      );
    });

    test(
      'control, flag ON: the same read DOES create the history provider',
      () async {
        await HiveService.instance.configBox.put(
          'enable_body_measurements',
          true,
        );
        final c = container();
        final sub = c.listen(measurementPromptProvider, (_, _) {});
        addTearDown(sub.close);
        c.read(measurementPromptProvider);
        expect(obs.saw(bodyMeasurementsProvider), isTrue);
        expect(
          obs.saw(userProfileProvider),
          isTrue,
          reason: 'control for the profile assertion above',
        );
      },
    );
  });

  // ── (b), (c) the widget paths ──────────────────────────────────────────────

  group('widget paths', () {
    late Directory dir;
    late _Created obs;
    late FlutterErrorCapture errors;

    setUp(() async {
      dir = await setUpHiveForTests();
      obs = _Created();
      // The Weight sheet overflows by a few pixels under the test font (see
      // FlutterErrorCapture); nothing ELSE may be reported.
      errors = FlutterErrorCapture();
    });
    tearDown(() async {
      errors.stop();
      expect(errors.others, isEmpty);
      await tearDownHiveForTests(dir);
    });

    Widget scope(Widget child) => ProviderScope(
      observers: [obs],
      overrides: [authUserIdTokenProvider.overrideWithValue(kTestUserId)],
      child: MaterialApp(home: Scaffold(body: child)),
    );

    /// The capture must be installed INSIDE the test body: the test binding
    /// replaces FlutterError.onError when the body starts, after setUp.
    void wtest(String description, Future<void> Function(WidgetTester) body) {
      testWidgets(description, (tester) async {
        errors.start();
        try {
          await body(tester);
        } finally {
          errors.stop();
        }
      });
    }

    Future<void> setFlag(WidgetTester tester, bool on) async {
      await tester.runAsync(
        () =>
            HiveService.instance.configBox.put('enable_body_measurements', on),
      );
    }

    /// A corrupt `measurement_*` record: the history provider is the only
    /// reader of the box, so an OFF build must not even look at it.
    Future<void> plantCorrupt(WidgetTester tester) async {
      await tester.runAsync(() async {
        await HiveService.instance.healthBox.put(
          'measurement_2026-13-45',
          <dynamic, dynamic>{'date': 'garbage', 'waist': 'not a number'},
        );
        await HiveService.instance.healthBox.put('measurement_broken', 7);
      });
    }

    wtest('the Home slot, flag OFF: renders nothing and creates neither '
        'the prompt nor the history provider', (tester) async {
      await setFlag(tester, false);
      await plantCorrupt(tester);
      await tester.pumpWidget(scope(const MeasurementDueSlot()));
      expect(find.byType(MeasurementDueBanner), findsNothing);
      expect(obs.saw(measurementsEnabledProvider), isTrue, reason: 'control');
      expect(obs.saw(measurementPromptProvider), isFalse);
      expect(obs.saw(bodyMeasurementsProvider), isFalse);
    });

    wtest('control, the Home slot with the flag ON creates the prompt '
        'provider', (tester) async {
      await setFlag(tester, true);
      await tester.pumpWidget(scope(const MeasurementDueSlot()));
      expect(obs.saw(measurementPromptProvider), isTrue);
      expect(obs.saw(bodyMeasurementsProvider), isTrue);
    });

    wtest('the Weight sheet, flag OFF: no prompt and no history provider', (
      tester,
    ) async {
      await setFlag(tester, false);
      await plantCorrupt(tester);
      await tester.pumpWidget(scope(const WeightLogSheet()));
      await tester.pump();
      expect(obs.saw(measurementPromptProvider), isFalse);
      expect(obs.saw(bodyMeasurementsProvider), isFalse);
      expect(find.text('Add body measurements'), findsNothing);
    });

    wtest('control, the Weight sheet with the flag ON creates the prompt '
        'provider', (tester) async {
      await setFlag(tester, true);
      await tester.pumpWidget(scope(const WeightLogSheet()));
      await tester.pump();
      expect(obs.saw(measurementPromptProvider), isTrue);
    });
  });

  // ── pins on the OFF paths' source (presence only) ─────────────────────────

  group('source pins (presence only; the behaviour is above)', () {
    String strip(String path) =>
        stripDartComments(File(path).readAsStringSync());

    test('Home invalidateOnRetry invalidates the history provider exactly once '
        'and never reads or refreshes a measurements provider', () {
      final body = functionBody(
        strip('lib/features/home/screens/home_screen.dart'),
        'void invalidateOnRetry(WidgetRef ref)',
      );
      expect(countOf(body, 'ref.invalidate(bodyMeasurementsProvider);'), 1);
      // A top-level statement of the function: not wrapped in an `if` (which
      // would still contain the substring), a loop or a closure.
      final at = body.indexOf('ref.invalidate(bodyMeasurementsProvider);');
      var depth = 0;
      for (var i = 0; i < at; i++) {
        if (body[i] == '{') depth++;
        if (body[i] == '}') depth--;
      }
      expect(depth, 1, reason: 'not inside any nested block');
      final before = body.substring(0, at).trimRight();
      expect(
        before.endsWith(';') || before.endsWith('{'),
        isTrue,
        reason: 'no condition or `else` in front of it',
      );
      for (final banned in [
        'ref.read(bodyMeasurementsProvider',
        'ref.refresh(bodyMeasurementsProvider',
        'ref.watch(bodyMeasurementsProvider',
        'measurementPromptProvider',
        'measurementsEnabledProvider',
      ]) {
        expect(body.contains(banned), isFalse, reason: banned);
      }
    });

    test('the dev toggle writes the key, invalidates the flag provider, then '
        'runs the rollover - in that order', () {
      final src = strip('lib/features/dev/dev_panel_screen.dart');
      final body = functionBody(src, 'Future<void> _toggleBodyMeasurements()');
      final put = body.indexOf(
        "configBox.put('enable_body_measurements', next)",
      );
      final inval = body.indexOf('ref.invalidate(measurementsEnabledProvider)');
      final roll = body.indexOf('runRolloverNow(ref)');
      expect(put, greaterThanOrEqualTo(0));
      expect(inval, greaterThan(put));
      expect(roll, greaterThan(inval));
      expect(src.contains("'Open measurements sheet'"), isTrue);
      expect(src.contains('BodyMeasurementsSheet.show(context)'), isTrue);
      // The polarity: the toggle writes the OPPOSITE of what is shown.
      expect(
        body.contains(
          'final next = !MeasurementFlags.bodyMeasurementsEnabled;',
        ),
        isTrue,
      );
      // The status row and the button label read the same getter, ON / off.
      final squashed = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        squashed.contains(
          "_kv('enable_body_measurements', "
          "MeasurementFlags.bodyMeasurementsEnabled ? 'ON' : 'off')",
        ),
        isTrue,
      );
      expect(
        squashed.contains(
          'MeasurementFlags.bodyMeasurementsEnabled ? '
          "'Turn body measurements OFF' : 'Turn body measurements ON'",
        ),
        isTrue,
      );
    });

    test('Home mounts the slot once, in the card stack, after the repeat '
        'nudge and before the PWA banner', () {
      final body = functionBody(
        strip('lib/features/home/screens/home_screen.dart'),
        'Widget _buildContent()',
      );
      expect(countOf(body, 'const MeasurementDueSlot(),'), 1);
      final nudge = body.indexOf('_buildRepeatNudge(ref),');
      final slot = body.indexOf('const MeasurementDueSlot(),');
      final pwa = body.indexOf('const PwaInstallBanner(),');
      expect(nudge, greaterThanOrEqualTo(0));
      expect(slot, greaterThan(nudge));
      expect(pwa, greaterThan(slot));
    });

    test('WeightLogSheet: the decision is made in initState (flag first), and '
        'build makes no provider call', () {
      final cls = blockBody(
        strip('lib/features/home/widgets/weight_log_sheet.dart'),
        'class _WeightLogSheetState extends ConsumerState<WeightLogSheet>',
      );
      final init = functionBody(cls, 'void initState()');
      final flag = init.indexOf('ref.read(measurementsEnabledProvider)');
      final prompt = init.indexOf('ref.read(measurementPromptProvider)');
      expect(flag, greaterThanOrEqualTo(0));
      expect(prompt, greaterThan(flag), reason: 'the flag is read first');
      expect(init.contains('&&'), isTrue);
      final build = functionBody(cls, 'Widget build(BuildContext context)');
      expect(build.contains('ref.watch('), isFalse);
      expect(build.contains('ref.read('), isFalse);
    });

    test(
      'the measurements sheet and its callers are not named by any PRO gate',
      () {
        for (final path in [
          'lib/features/profile/widgets/body_measurements_sheet.dart',
          'lib/features/home/widgets/measurement_due_slot.dart',
          'lib/features/home/widgets/measurement_due_banner.dart',
          'lib/features/profile/providers/measurement_prompt_provider.dart',
          'lib/features/profile/providers/body_measurements_provider.dart',
        ]) {
          final src = strip(path);
          for (final banned in [
            'isPro',
            'gateAndVerify',
            'PaywallSheet',
            'showPaywallSheet',
            'subscriptionInfoProvider',
          ]) {
            expect(
              src.contains(banned),
              isFalse,
              reason: '$path names $banned',
            );
          }
        }
      },
    );
  });
}
