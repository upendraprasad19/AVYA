// OI-517 (docs/plans/diet-grams-toggle.md sections 3, 6, 13): the switch at the
// right end of the BMR / TDEE / TARGET card. Widget tests run on the Ahem
// fallback font (the repo ships no font files), so they assert only what holds
// under ANY font: no overflow error from the card or the toggle, the card at
// most kDietPlanCompactCardMaxHeight, the switch inside the card, one tap
// target of the full inner height, one flip per tap, one Semantics value.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/nutrition/providers/diet_serving_view_provider.dart';
import 'package:icanbefitter/features/nutrition/services/diet_serving_label.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/nutrition/widgets/diet_plan_macro_cards.dart';
import 'package:icanbefitter/features/nutrition/widgets/diet_serving_view_toggle.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

import '../helpers/hive_test_setup.dart';

/// A view holder and a profile notifier that records the write instead of
/// doing Hive I/O: the write-to-read round trip is pinned by
/// test/contracts/diet_serving_view_writer_to_reader_test.dart; this file pins
/// the widget (one tap, one flip, one Semantics value).
class _View extends Notifier<DietServingView> {
  _View(this._initial);
  final DietServingView _initial;
  @override
  DietServingView build() => _initial;
  void set(DietServingView v) => state = v;
}

final _fakeView = NotifierProvider<_View, DietServingView>(
  () => _View(DietServingView.portions),
);
final _writes = <String>[];
bool _throwOnWrite = false;

class _FakeProfile extends UserProfileNotifier {
  @override
  Map<String, dynamic> build() => <String, dynamic>{};
  @override
  Future<void> updateProfile(Map<String, dynamic> fields) async {
    if (_throwOnWrite) throw StateError('hive write failed');
    final next = fields['diet_serving_view'] as String;
    _writes.add(next);
    ref.read(_fakeView.notifier).set(DietServingView.fromStorage(next));
  }
}

/// No figure of the calorie card is ellipsised: a FittedBox lays its child out
/// unconstrained, so the paragraph never exceeds its one line (findsNWidgets(3)
/// of 'kcal' alone passes on an ellipsised string).
void _expectNoEllipsis(WidgetTester tester) {
  final els = find.textContaining('kcal', findRichText: true).evaluate();
  expect(els, hasLength(3));
  for (final e in els) {
    final ro = e.renderObject;
    expect(ro, isA<RenderParagraph>());
    expect((ro! as RenderParagraph).didExceedMaxLines, isFalse);
  }
  // The three captions shrink too (B-pass B6): none is truncated.
  for (final cap in ['BMR', 'TDEE', 'TARGET']) {
    final ro = find.text(cap).evaluate().single.renderObject;
    expect(ro, isA<RenderParagraph>());
    expect((ro! as RenderParagraph).didExceedMaxLines, isFalse, reason: cap);
  }
}

void main() {
  // The font warm-up MUST stay first: the Hive group mocks path_provider, and
  // GoogleFonts then fails loudly instead of degrading (CLAUDE.md pitfalls).
  testWidgets('typography warmup: GoogleFonts caches before any Hive mock', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Text('a', style: AppTypography.body),
              Text(
                'b',
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                'c',
                style: AppTypography.body.copyWith(fontWeight: FontWeight.w900),
              ),
              Text('d', style: AppTypography.monoXs),
              Text(
                'e',
                style: AppTypography.monoXs.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'f',
                style: AppTypography.monoXs.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'g',
                style: AppTypography.monoXs.copyWith(
                  fontWeight: FontWeight.w400,
                ),
              ),
              Text(
                'h',
                style: AppTypography.monoXs.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('a'), findsOneWidget);
  });

  group('with Hive', () {
    late Directory tempDir;
    setUp(() async {
      tempDir = await setUpHiveForTests();
      await UserRepository.instance.saveProfile(<String, dynamic>{
        'full_name': 'T',
      });
    });
    tearDown(() async => tearDownHiveForTests(tempDir));

    Future<List<FlutterErrorDetails>> pump(
      WidgetTester tester, {
      double width = 360,
      double textScale = 1.0,
      Map<String, double>? targets,
    }) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final errors = <FlutterErrorDetails>[];
      final prev = FlutterError.onError;
      FlutterError.onError = errors.add;
      try {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(textScale)),
                child: child!,
              ),
              home: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(22),
                  child: DietPlanTdeeCard(
                    targets:
                        targets ??
                        const {'bmr': 1665, 'tdee': 2481, 'calories': 2687},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      } finally {
        FlutterError.onError = prev;
      }
      return errors;
    }

    testWidgets(
      '360 dp, a 4-digit TARGET: no overflow, height <= cap, switch inside',
      (tester) async {
        final errors = await pump(tester);
        expect(
          errors.where((e) => e.toString().contains('overflowed')),
          isEmpty,
        );
        final card = find.byKey(const ValueKey('diet_plan_tdee_card'));
        final toggle = find.byKey(const ValueKey('diet_serving_view_toggle'));
        expect(toggle, findsOneWidget);
        expect(
          tester.getSize(card).height,
          lessThanOrEqualTo(kDietPlanCompactCardMaxHeight),
        );
        final c = tester.getRect(card);
        final t = tester.getRect(toggle);
        expect(c.contains(t.topLeft) && c.contains(t.bottomRight), isTrue);
        // The whole switch is one target as tall as the card's inner height.
        expect(t.height, greaterThanOrEqualTo(40));
        // Every figure keeps its unit (the existing pin counts three).
        expect(
          find.textContaining('kcal', findRichText: true),
          findsNWidgets(3),
        );
      },
    );

    testWidgets('text scale 2.0 at 360 dp: no overflow, no figure ellipsised '
        '(the captions shrink too)', (tester) async {
      final errors = await pump(tester, textScale: 2.0);
      expect(errors.where((e) => e.toString().contains('overflowed')), isEmpty);
      _expectNoEllipsis(tester);
    });

    testWidgets('a worst-case 4-digit set at 320 dp still has no overflow', (
      tester,
    ) async {
      final errors = await pump(
        tester,
        width: 320,
        targets: const {'bmr': 2999, 'tdee': 4999, 'calories': 4999},
      );
      expect(errors.where((e) => e.toString().contains('overflowed')), isEmpty);
      _expectNoEllipsis(tester);
    });

    testWidgets('one tap flips the view once; the Semantics value follows', (
      tester,
    ) async {
      _writes.clear();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith(_FakeProfile.new),
            dietServingViewProvider.overrideWith((ref) => ref.watch(_fakeView)),
          ],
          child: const MaterialApp(
            home: Scaffold(body: Center(child: DietServingViewToggle())),
          ),
        ),
      );
      await tester.pump();
      final toggle = find.byKey(const ValueKey('diet_serving_view_toggle'));
      expect(_semValue(tester), 'Portions');

      await tester.tap(toggle);
      await tester.pump();
      expect(_writes, ['grams']);
      expect(_semValue(tester), 'Grams');

      await tester.tap(toggle);
      await tester.pump();
      expect(_writes, ['grams', 'portions']);
      expect(_semValue(tester), 'Portions');
    });

    testWidgets('a failed profile write is swallowed at the tap (B-pass A4): '
        'no uncaught error, the switch does not move', (tester) async {
      _writes.clear();
      _throwOnWrite = true;
      addTearDown(() => _throwOnWrite = false);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith(_FakeProfile.new),
            dietServingViewProvider.overrideWith((ref) => ref.watch(_fakeView)),
          ],
          child: const MaterialApp(
            home: Scaffold(body: Center(child: DietServingViewToggle())),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('diet_serving_view_toggle')));
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_semValue(tester), 'Portions');
    });

    testWidgets('a Grams view shows Grams at once', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            userProfileProvider.overrideWith(_FakeProfile.new),
            dietServingViewProvider.overrideWith(
              (ref) => DietServingView.grams,
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: Center(child: DietServingViewToggle())),
          ),
        ),
      );
      await tester.pump();
      expect(_semValue(tester), 'Grams');
    });
  });
}

/// The value of the toggle's one Semantics node, read from the widget (the
/// semantics tree itself needs a flush the test does not otherwise run).
String? _semValue(WidgetTester tester) => tester
    .widget<Semantics>(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Serving view',
      ),
    )
    .properties
    .value;
