// The toast after a LOG (batch 2, docs/plans/log-exercise-batch2.md §6 test 20):
// only UNDO takes touches; a tap on the rest of the toast reaches what is under
// it; a long exercise name does not overflow at phone width. And the host
// keeps the list's tree shape when the toast comes and goes (B-pass finding 1).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/train/widgets/log_undo_toast.dart';

import 'card_harness.dart';

Future<({List<String> undo, List<String> under})> pumpHosted(
    WidgetTester tester, String text) async {
  final undo = <String>[];
  final under = <String>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => under.add('tap'),
          ),
        ),
        Positioned(
          top: 8,
          left: 16,
          right: 16,
          child: LogUndoToast(text: text, onUndo: () => undo.add('undo')),
        ),
      ]),
    ),
  ));
  return (undo: undo, under: under);
}

class _Probe extends StatefulWidget {
  const _Probe({super.key});
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) => const SizedBox(height: 100);
}

/// A LogUndoToastHost over a 40-row list whose toast the test switches.
Future<({ScrollController scroll, void Function(bool) show})> pumpHost(
    WidgetTester tester, {required bool enabled}) async {
  final scroll = ScrollController();
  addTearDown(scroll.dispose);
  late StateSetter setShow;
  var show = false;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(builder: (context, setState) {
        setShow = setState;
        return Column(children: [
          Expanded(
            child: LogUndoToastHost(
              enabled: enabled,
              list: ListView(controller: scroll, children: [
                for (var i = 0; i < 40; i++) _Probe(key: ValueKey('row$i')),
              ]),
              toast: show
                  ? LogUndoToast(text: 'Squat logged', onUndo: () {})
                  : null,
            ),
          ),
        ]);
      }),
    ),
  ));
  return (
    scroll: scroll,
    show: (bool v) => setShow(() => show = v),
  );
}

void main() {
  testWidgets('fonts first (GoogleFonts + path_provider pitfall)',
      (tester) async {
    await renderFontsFirst(tester);
  });

  testWidgets('renders the text and UNDO; UNDO calls back once and does not '
      'reach the list; a tap on the body does', (tester) async {
    final h = await pumpHosted(tester, 'Bench Press logged · 3 sets · 1200 KG');
    expect(find.text('Bench Press logged · 3 sets · 1200 KG'), findsOneWidget);
    expect(find.text('UNDO'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await tester.pump();
    expect(h.undo, ['undo']);
    expect(h.under, isEmpty);

    // The body is under IgnorePointer, so the tap lands on the host's detector
    // (the "missed" hit IS the behaviour under test).
    await tester.tap(find.text('Bench Press logged · 3 sets · 1200 KG'),
        warnIfMissed: false);
    await tester.pump();
    expect(h.undo, ['undo'], reason: 'the body is not an UNDO target');
    expect(h.under, ['tap'], reason: 'the body lets the tap through');
  });

  testWidgets('a long name at phone width ellipsises, no overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpHosted(tester,
        'Barbell Bulgarian Split Squat With Pause logged · 4 sets · 1840 KG');
    expect(tester.takeException(), isNull);
    expect(find.text('UNDO'), findsOneWidget);
  });

  testWidgets('host: the toast coming and going never rebuilds the list '
      '(scroll offset and row State survive)', (tester) async {
    final h = await pumpHost(tester, enabled: true);
    h.scroll.jumpTo(1500);
    await tester.pump();
    final scrollable = tester.state(find.byType(Scrollable));
    final row = tester.state(find.byKey(const ValueKey('row16')));

    h.show(true);
    await tester.pump();
    expect(find.text('Squat logged'), findsOneWidget);
    expect(h.scroll.offset, 1500, reason: 'toast shown: no scroll reset');
    expect(tester.state(find.byType(Scrollable)), same(scrollable));
    expect(tester.state(find.byKey(const ValueKey('row16'))), same(row));

    h.show(false);
    await tester.pump();
    expect(find.text('Squat logged'), findsNothing);
    expect(h.scroll.offset, 1500, reason: 'toast cleared: no scroll reset');
    expect(tester.state(find.byType(Scrollable)), same(scrollable));
    expect(tester.state(find.byKey(const ValueKey('row16'))), same(row));
  });

  testWidgets('host disabled (flag OFF): the bare list, no Stack', (tester) async {
    await pumpHost(tester, enabled: false);
    expect(
        find.descendant(
            of: find.byType(LogUndoToastHost), matching: find.byType(Stack)),
        findsNothing);
    expect(find.byType(ListView), findsOneWidget);
  });
}
