// Regression contract for bug e2b8a4 (2026-09-19): the Plan screen's
// "FOUNDATION" phase title wrapped onto two lines ("FOUNDATI"/"ON") inside
// WardPhaseBlock's title Row. Root cause: the title Text sat in an
// `Expanded` alongside a fixed-width sibling (the weeks label), with no
// `maxLines`/`overflow` set — so once the app's global textTheme moved
// display/title slots to Fraunces (wider glyphs than the old DM Sans
// assumption), "FOUNDATION" (10 chars, the longest of the three phase
// names) tipped over the available width and wrapped, while "CAPACITY"
// and "CONVERGE" (8 chars each) still just barely fit.
//
// Second finding, same day, on first actual execution of this file (it was
// written but never run): weeksLabel's Text had NO maxLines/overflow AND
// was a bare Row child (not Expanded/Flexible) — a Row gives non-flexible
// children their full intrinsic width before any flexible sibling sees
// remaining space, so at this exact width the Row overflowed regardless of
// what the title's own maxLines/overflow did. Fixed by wrapping weeksLabel
// in Flexible (so its width becomes genuinely bounded and ellipsis can
// activate) with maxLines:1/overflow:ellipsis of its own.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_phase_block.dart';

void main() {
  testWidgets(
      'e2b8a4 — a long phase title never exceeds one line, even '
      'when it would otherwise overflow its Row slot', (tester) async {
    // Narrow width forces the exact squeeze that originally wrapped
    // "FOUNDATION" — a fixed-width sibling (the weeks label) plus a long
    // title in a tight Row.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            child: WardPhaseBlock(
              roman: 'I',
              title: 'FOUNDATION',
              weeksLabel: 'WEEKS 1-4',
              description: 'Technique, baselines.',
              active: true,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull,
        reason: 'e2b8a4: no RenderFlex overflow at this width — the '
            'weeksLabel sibling must not overflow the Row regardless of '
            'what the title does (2nd finding, same bug_id, same day)');

    // B-pass round-2 finding (2026-09-19): the takeException() check above
    // only catches REMOVING weeksLabel's Flexible wrapper (which reproduces
    // the original literal RenderFlex-overflow crash) — it does NOT catch
    // removing JUST maxLines/overflow while Flexible stays in place. In
    // that shape, Flutter wraps "WEEKS 1-4" onto a 2nd line INSIDE the
    // Flexible's bounded width instead of throwing, so takeException()
    // stays null and this test previously stayed green with no truncation
    // enforced at all — mutation-confirmed: deleting maxLines/overflow from
    // weeksLabel's Text (keeping Flexible) left every prior assertion here
    // passing. This diagnose-doc's own claim that this file was "mutation-
    // proven against both [title and weeksLabel]" was FALSE for weeksLabel;
    // these two assertions close that gap directly, the same way the two
    // assertions above already do for the title.
    final weeksLabelText = tester.widget<Text>(find.text('WEEKS 1-4'));
    expect(weeksLabelText.maxLines, 1,
        reason: 'e2b8a4 round 2: weeksLabel must be capped to one line — '
            'without this, "WEEKS 1-4" can silently wrap onto a 2nd line '
            'inside its Flexible slot with no RenderFlex overflow to catch '
            'it, which is exactly what the pre-fix bug looked like');
    expect(weeksLabelText.overflow, TextOverflow.ellipsis,
        reason: 'e2b8a4 round 2: overflow must truncate weeksLabel '
            'gracefully rather than silently wrapping onto a second line');

    final titleText = tester.widget<Text>(find.text('FOUNDATION'));
    expect(titleText.maxLines, 1,
        reason: 'e2b8a4: the title must be capped to one line — this is '
            'the actual fix, not just a narrow-width coincidence');
    expect(titleText.overflow, TextOverflow.ellipsis,
        reason: 'e2b8a4: overflow must truncate gracefully rather than '
            'wrap onto a second line');

    // Confirm the fix is actually ENFORCED on the rendered tree, not just
    // declared. Two complementary checks:
    final renderParagraph = tester.renderObject<RenderParagraph>(
      find.text('FOUNDATION'),
    );
    // (1) didExceedMaxLines TRUE proves this width genuinely reproduces the
    // squeeze (the untruncated text WOULD need >1 line) and that ellipsis
    // truncation is actively engaged, not just inertly configured.
    // didExceedMaxLines is FALSE either when the text already fits on one
    // line (not a real test of the fix) OR when maxLines was never set at
    // all (a mutation removing the fix also reads as false, NOT true) — an
    // earlier version of this assertion asserted isFalse here, which had
    // the semantics backwards and could not actually distinguish the fixed
    // state from the no-maxLines-at-all mutated state.
    expect(renderParagraph.didExceedMaxLines, isTrue,
        reason: 'FOUNDATION at width 220 must genuinely be too long for one '
            'line — otherwise this test is not exercising the squeeze at '
            'all, and the height check below is unverified');

    // (2) The RENDERED height must still be exactly one line's worth, not
    // two — the actual "does not visually wrap" proof. Compared against a
    // reference render of a short string in the identical style, since
    // Fraunces' own line-height metric isn't a simple hardcoded constant
    // to assume, and it must be measured BEFORE replacing the widget tree
    // (a RenderObject from an unmounted tree is not safe to read from).
    final titleHeight = renderParagraph.size.height;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Text('F', key: const Key('ref'), style: titleText.style),
        ),
      ),
    );
    final oneLineHeight = tester.getSize(find.byKey(const Key('ref'))).height;

    expect(titleHeight, closeTo(oneLineHeight, 0.5),
        reason: 'e2b8a4: FOUNDATION must render at exactly one line\'s '
            'height, not two — a mutation removing maxLines/overflow would '
            'let it wrap onto a second line and roughly double this height');
  });
}
