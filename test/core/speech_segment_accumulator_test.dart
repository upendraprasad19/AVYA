// BEHAVIORAL TEST — dictation segment accumulation (OI-348 B5, diagnose 6d9f3b)
//
// Concept:  speech_segment_accumulation
// Writer:   the plugin's results (Android `intermediate` = a finished segment)
// Reader:   SpeechSegmentAccumulator.text / onFinal → SpeechInputController
//           liveText and the session transcript.
//
// The founder's walk (A19): one long sentence left only "or the coming week".

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/speech_segment_accumulator.dart';

void main() {
  late SpeechSegmentAccumulator acc;
  setUp(() => acc = SpeechSegmentAccumulator());

  void p(String w) => acc.onResult(w, segmentEnd: false);
  void end(String w) => acc.onResult(w, segmentEnd: true);

  test('S1 segmented: the walk sentence keeps every word', () {
    p('I want a plan');
    p('I want a plan for next week');
    end('I want a plan for next week');
    p('or the coming');
    expect(acc.text, 'I want a plan for next week or the coming');
    p('or the coming week');
    expect(acc.mode, SpeechSegmentMode.segmented);
    expect(acc.onFinal('or the coming week'),
        'I want a plan for next week or the coming week');
  });

  test('S1b longer first post-end partial with different words: segmented', () {
    end('I want a plan');
    p('and then maybe something else later');
    expect(acc.mode, SpeechSegmentMode.segmented);
    expect(acc.text, 'I want a plan and then maybe something else later');
  });

  test('S1b same-words residue: taken as cumulative (stated in the plan)', () {
    end('I want a plan for next week');
    p('I want a plan for the weekend and more');
    expect(acc.mode, SpeechSegmentMode.cumulative);
    expect(acc.text, 'I want a plan for the weekend and more');
  });

  test('S1c a SHORTER first post-end partial never decides cumulative', () {
    // A cumulative recognizer's first partial after a segment end carries at
    // least the committed words; a shorter one is a new segment, even when its
    // words happen to match (the "strictly more" rule).
    end('I want a plan');
    p('I want a');
    expect(acc.mode, SpeechSegmentMode.segmented);
    expect(acc.text, 'I want a plan I want a');
  });

  test('S2 cumulative: the whole utterance once', () {
    end('I want a plan');
    p('I want a plan for');
    expect(acc.mode, SpeechSegmentMode.cumulative);
    p('I want a plan for next week');
    expect(acc.text, 'I want a plan for next week');
    expect(acc.onFinal('I want a plan for next week'),
        'I want a plan for next week');
  });

  test('S3 no segment end: exactly the latest result, as before', () {
    p('hello');
    p('hello there');
    expect(acc.text, 'hello there');
    expect(acc.onFinal('hello there coach'), 'hello there coach');
    expect(acc.mode, SpeechSegmentMode.undecided);
  });

  test('S4 a rescored whole-utterance final replaces everything', () {
    end('I want a plant for');
    p('next week');
    expect(acc.onFinal('I want a plan for next week'),
        'I want a plan for next week');
    expect(acc.wholeFinals, 1);
  });

  test('S5 repeats', () {
    end('A B C');
    expect(acc.onFinal('A B C'), 'A B C');

    acc.reset();
    end('A B C');
    p('A B C');
    expect(acc.repeats, 1);
    p('D');
    expect(acc.mode, SpeechSegmentMode.segmented);
    expect(acc.text, 'A B C D');

    acc.reset();
    end('A B C');
    p('A B C');
    p('A B C D');
    expect(acc.mode, SpeechSegmentMode.cumulative);
    expect(acc.text, 'A B C D');
  });

  test('S5b the timeout final of the last segment adds nothing', () {
    end('book a session for monday');
    expect(acc.onFinal('book a session for monday'),
        'book a session for monday');
  });

  test('S5c a one-word segment repeated by the final is kept once', () {
    end('yes');
    expect(acc.onFinal('Yes.'), 'yes');
    expect(acc.repeats, 1);
  });

  test('S6 a short committed segment never decides the mode', () {
    end('yes');
    p('yes');
    p('yes I will');
    expect(acc.mode, SpeechSegmentMode.undecided);
    expect(acc.text, 'yes yes I will');

    acc.reset();
    end('next week please do it');
    p('next');
    p('next week');
    expect(acc.mode, SpeechSegmentMode.segmented);
    expect(acc.text, 'next week please do it next week');
  });

  test('S11 Hindi: vowel signs are kept by the normaliser', () {
    end('मुझे एक प्लान चाहिए');
    p('अगले हफ्ते के लिए');
    expect(acc.text, 'मुझे एक प्लान चाहिए अगले हफ्ते के लिए');
    expect(SpeechSegmentAccumulator.normalizedWords('किताब'),
        isNot(SpeechSegmentAccumulator.normalizedWords('कताब')));
    expect(SpeechSegmentAccumulator.normalizedWords('किताब').single, 'किताब');
  });

  test('S13 an empty or whitespace partial keeps the words', () {
    end('I want a plan');
    p('   ');
    p('');
    expect(acc.text, 'I want a plan');
  });

  test('S13b an empty partial after a segment end does not decide the mode',
      () {
    // Without the guard the empty result decides SEGMENTED, and the cumulative
    // partial that follows is appended to the words it already carries.
    end('I want a plan');
    p('');
    expect(acc.mode, SpeechSegmentMode.undecided);
    p('I want a plan for next week');
    expect(acc.mode, SpeechSegmentMode.cumulative);
    expect(acc.text, 'I want a plan for next week');
  });

  test('S13c an empty partial in cumulative mode keeps the words', () {
    end('I want a plan');
    p('I want a plan for');
    expect(acc.mode, SpeechSegmentMode.cumulative);
    p(' ');
    expect(acc.text, 'I want a plan for');
  });

  test('normaliser: case, punctuation, curly apostrophe', () {
    expect(SpeechSegmentAccumulator.normalizedWords("Don’t, STOP!"),
        ["don't", 'stop']);
    expect(SpeechSegmentAccumulator.prefixMatch([], ['a']), 0);
  });

  test('telemetry message has counts and the mode only', () {
    end('my secret plan words');
    p('more secret words');
    final m = acc.telemetryMessage();
    expect(m, contains('segment_ends=1'));
    expect(m, contains('mode=segmented'));
    for (final w in ['secret', 'plan', 'words']) {
      expect(m.contains(w), isFalse);
    }
  });
}
