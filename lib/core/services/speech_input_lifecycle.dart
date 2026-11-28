/// Ends a dictation session when its host goes out of sight (plan D3, G17).
///
/// A hidden tab (the app shell keeps its tabs in an `IndexedStack`, which turns
/// `TickerMode` off for the hidden ones) or a closed sheet must not leave the
/// microphone running, and the app going to the background must not either.
/// Both hosts wrap their mic area in this widget.
///
/// This file also holds the dictation field's shared line geometry (OI-348
/// Landing 3e): both hosts let their field grow to [kDictationFieldMaxLines]
/// lines, and the coach's live words are capped at the same height.
library;

import 'package:flutter/widgets.dart';
import 'package:icanbefitter/core/services/speech_input_controller.dart';

/// The most lines a dictation field (coach composer, nutrition Log Food) shows
/// before it scrolls (OI-348 Landing 3e, plan `docs/plans/oi348-landing3e.md`).
const int kDictationFieldMaxLines = 6;

/// The line height, as a multiple of the 14 dp font size, of every dictation
/// line. Forced through [kDictationStrut], so a line is exactly
/// `scale(14) * kDictationLineHeight` whatever the font's own metrics.
const double kDictationLineHeight = 1.4;

/// The forced strut both hosts' fields and the coach's live words use, so the
/// live box's cap and the fields' own six-line height are the same number.
const StrutStyle kDictationStrut = StrutStyle(
  fontSize: 14,
  height: kDictationLineHeight,
  forceStrutHeight: true,
);

/// The height of [kDictationFieldMaxLines] dictation lines under [context]'s
/// text scaler: the SAME number a text field with `maxLines:
/// kDictationFieldMaxLines` and [kDictationStrut] takes (`RenderEditable` is
/// `preferredLineHeight * maxLines`). Measured, not `scale(14) * 1.4 * 6`: the
/// engine rounds a line's height (19.6 lays out as 20), so the formula was
/// 2.4dp short of the field (build finding, OI-348 Landing 3e T3c). The strut
/// is forced, so the font (loaded late by google_fonts) does not change it.
double dictationMaxHeight(BuildContext context) {
  final painter = TextPainter(
    text: const TextSpan(text: ' ', style: TextStyle(fontSize: 14)),
    strutStyle: kDictationStrut,
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  );
  final line = painter.preferredLineHeight;
  painter.dispose();
  return line * kDictationFieldMaxLines;
}

class SpeechInputLifecycle extends StatefulWidget {
  const SpeechInputLifecycle({
    super.key,
    required this.controller,
    required this.child,
  });

  final SpeechInputController controller;
  final Widget child;

  @override
  State<SpeechInputLifecycle> createState() => _SpeechInputLifecycleState();
}

class _SpeechInputLifecycleState extends State<SpeechInputLifecycle>
    with WidgetsBindingObserver {
  bool _tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    final wasEnabled = _tickerEnabled;
    _tickerEnabled = enabled;
    if (wasEnabled && !enabled) _endWhenSettled();
  }

  /// `endForHidden` runs `notifyListeners()` and the host's `onEnd` (which may
  /// `setState` a screen), which Flutter forbids while the tree is building, and
  /// `didChangeDependencies` runs inside the build phase. So it is deferred to
  /// after the frame, and re-checks that nothing changed in between.
  void _endWhenSettled() {
    final controller = widget.controller;
    if (!controller.isBusy) return;
    final epoch = controller.sessionEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_tickerEnabled) return; // the tab came back
      if (controller.sessionEpoch != epoch) return; // a different session now
      controller.endForHidden();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `hidden` and `paused` only. `inactive` is NOT a reason: the Android
    // permission dialog causes it, and ending the session there would kill the
    // very first tap. Flutter web emits `hidden`, never `paused` (plan G4).
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      widget.controller.endForHidden();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
