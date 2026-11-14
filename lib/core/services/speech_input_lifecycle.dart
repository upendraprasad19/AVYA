/// Ends a dictation session when its host goes out of sight (plan D3, G17).
///
/// A hidden tab (the app shell keeps its tabs in an `IndexedStack`, which turns
/// `TickerMode` off for the hidden ones) or a closed sheet must not leave the
/// microphone running, and the app going to the background must not either.
/// Both hosts wrap their mic area in this widget.
library;

import 'package:flutter/widgets.dart';
import 'package:icanbefitter/core/services/speech_input_controller.dart';

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
