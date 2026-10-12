import 'package:flutter/foundation.dart';

/// Records the FlutterErrors a test reports instead of letting the first one
/// fail it. Used where a widget under test has a PRE-EXISTING render overflow
/// under the test font: GoogleFonts families do not load in `flutter test`, the
/// fallback font is much wider, and the Weight sheet's fixed 160 dp weight row
/// overflows by a few pixels even with the measurements flag OFF. A test that
/// concerns what a change ADDS compares against that baseline.
class FlutterErrorCapture {
  final List<String> messages = [];

  /// The full report of each entry in [messages] (same index): it carries the
  /// creation location of the widget that failed, which the one-line message
  /// does not.
  final List<String> _full = [];
  FlutterExceptionHandler? _previous;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _previous = FlutterError.onError;
    FlutterError.onError = (details) {
      messages.add(details.exceptionAsString());
      _full.add(details.toString());
    };
  }

  void stop() {
    if (!_started) return;
    _started = false;
    FlutterError.onError = _previous;
  }

  void clear() {
    messages.clear();
    _full.clear();
  }

  /// Render-overflow reports ("A RenderFlex overflowed by 44 pixels ...").
  List<String> get overflows =>
      messages.where((m) => m.contains('overflowed')).toList();

  /// Render-overflow reports whose message names [fragment] (a source file
  /// name: the report ends with the creation location of the widget that
  /// overflowed, `...weight_log_sheet.dart:123:45`). Lets a test say "the PRE-
  /// EXISTING overflow of the Weight sheet is tolerated, but the sheet this
  /// change adds must report none", which the plain [overflows] list cannot.
  List<String> overflowsIn(String fragment) => [
    for (var i = 0; i < messages.length; i++)
      if (messages[i].contains('overflowed') && _full[i].contains(fragment))
        messages[i],
  ];

  /// Everything that is not an overflow report. A test that installs a capture
  /// must assert on THIS list: `tester.takeException()` cannot see an error the
  /// capture has taken over.
  List<String> get others =>
      messages.where((m) => !m.contains('overflowed')).toList();
}
