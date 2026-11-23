/// Keeps the words of a long native dictation across the recognizer's segment
/// ends (OI-348 B5, diagnose 6d9f3b, plan `docs/plans/oi348-walk-fixes-landing1b.md`).
///
/// The Android plugin reports a segment the recognizer has finished as an
/// `intermediate` result and adds no accumulation; the partials after it may
/// start again from the new words (a SEGMENTED recognizer) or carry the whole
/// utterance (a CUMULATIVE one). The controller used to replace its text with
/// every result, so a segmented recognizer left only the last fragment.
///
/// Pure (no plugin, no Hive): the controller feeds it every non-final result
/// and asks it for the final transcript. Rules, in order (plan B5):
/// - cumulative mode: every result replaces the segment (today's behaviour);
/// - the first non-empty result after a segment end: a repeat of the last
///   committed segment is ignored; else, while undecided and the committed text
///   has 3+ words, a result with STRICTLY more words whose words match the
///   committed ones position by position for at least 70% decides CUMULATIVE
///   (the committed text is dropped, the result carries it); else, with 3+
///   committed words, the mode is SEGMENTED;
/// - a segment end commits its words; any other result replaces the segment.
/// Without any segment end nothing is committed and [text] is exactly the
/// latest result, as before.
library;

enum SpeechSegmentMode { undecided, segmented, cumulative }

class SpeechSegmentAccumulator {
  String _committed = '';
  String _segment = '';
  String _lastCommitted = '';
  bool _afterEnd = false;
  SpeechSegmentMode _mode = SpeechSegmentMode.undecided;

  int partials = 0;
  int segmentEnds = 0;
  int finals = 0;
  int repeats = 0;
  int wholeFinals = 0;

  SpeechSegmentMode get mode => _mode;

  /// The words on screen.
  String get text => _mode == SpeechSegmentMode.cumulative
      ? _segment
      : _join(_committed, _segment);

  int get resultCount => partials + segmentEnds + finals;

  void reset() {
    _committed = '';
    _segment = '';
    _lastCommitted = '';
    _afterEnd = false;
    _mode = SpeechSegmentMode.undecided;
    partials = 0;
    segmentEnds = 0;
    finals = 0;
    repeats = 0;
    wholeFinals = 0;
  }

  /// A non-final result. An empty or whitespace result is ignored (it would
  /// otherwise blank the committed words).
  void onResult(String words, {required bool segmentEnd}) {
    if (segmentEnd) {
      segmentEnds++;
    } else {
      partials++;
    }
    if (words.trim().isEmpty) return;
    if (_mode == SpeechSegmentMode.cumulative) {
      _segment = words;
      return;
    }
    if (_afterEnd) {
      final r = normalizedWords(words);
      if (_listEquals(r, normalizedWords(_lastCommitted))) {
        repeats++;
        return; // no new word yet; _afterEnd stays true
      }
      final c = normalizedWords(_committed);
      if (_mode == SpeechSegmentMode.undecided && c.length >= 3) {
        if (r.length > c.length && prefixMatch(c, r) >= 0.7) {
          _mode = SpeechSegmentMode.cumulative;
          _committed = '';
          _lastCommitted = '';
          _segment = words;
          _afterEnd = false;
          return;
        }
        _mode = SpeechSegmentMode.segmented;
      }
    }
    if (segmentEnd) {
      _committed = _join(_committed, words);
      _lastCommitted = words;
      _segment = '';
      _afterEnd = true;
      return;
    }
    _segment = words;
    _afterEnd = false;
  }

  /// The transcript a non-empty final ends the session with.
  String onFinal(String words) {
    finals++;
    if (_mode == SpeechSegmentMode.cumulative || _committed.trim().isEmpty) {
      return words;
    }
    final c = normalizedWords(_committed);
    final r = normalizedWords(words);
    if (c.length >= 2 && r.length >= c.length && prefixMatch(c, r) >= 0.7) {
      wholeFinals++;
      return words; // the recognizer re-sent (and maybe rescored) everything
    }
    if (_segment.trim().isEmpty &&
        _listEquals(r, normalizedWords(_lastCommitted))) {
      repeats++;
      return _committed; // e.g. the plugin's timeout final of the last segment
    }
    return _join(_committed, words);
  }

  /// Counts and the mode only, never words (plan G18).
  String telemetryMessage() =>
      'partials=$partials segment_ends=$segmentEnds finals=$finals '
      'mode=${_mode.name} repeats=$repeats whole_finals=$wholeFinals';

  static final RegExp _strip = RegExp(r"[^\p{L}\p{M}\p{N}\s']", unicode: true);
  static final RegExp _space = RegExp(r'\s+');

  /// Lowercase, a curly apostrophe made straight, punctuation removed (letters,
  /// combining marks such as Devanagari vowel signs, digits and `'` kept).
  static List<String> normalizedWords(String s) => s
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(_strip, ' ')
      .split(_space)
      .where((w) => w.isNotEmpty)
      .toList();

  /// Share of [committed]'s words equal to the word at the same position in
  /// [result]; 0 for an empty [committed].
  static double prefixMatch(List<String> committed, List<String> result) {
    if (committed.isEmpty) return 0;
    var same = 0;
    for (var i = 0; i < committed.length && i < result.length; i++) {
      if (committed[i] == result[i]) same++;
    }
    return same / committed.length;
  }

  static String _join(String a, String b) =>
      [a.trim(), b.trim()].where((s) => s.isNotEmpty).join(' ');

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
