// OI-348 B5 (diagnose 6d9f3b): the real `disable_speech_segment_accumulate`
// read. The controller tests inject the switch; this pins the getter itself:
// absent → on, `true` → off, no opened box → on (the plate_flags guard).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/speech_input_service.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

import '../helpers/fake_speech_engine.dart';

void main() {
  SpeechInputService service() =>
      SpeechInputService(engine: FakeSpeechEngine(), isWeb: false);

  group('engineResultFromPlugin (the one line B5 depends on; B-pass)', () {
    SpeechRecognitionResult r(String w, int type) => SpeechRecognitionResult(
        [SpeechRecognitionWords(w, null, 0.9)], type);

    test('intermediate → segment end, not final', () {
      final e = engineResultFromPlugin(
          r('I want a plan', ResultType.intermediate.value));
      expect(e.words, 'I want a plan');
      expect(e.isSegmentEnd, isTrue);
      expect(e.isFinal, isFalse);
    });
    test('partial → neither', () {
      final e = engineResultFromPlugin(r('I want', ResultType.partial.value));
      expect(e.isSegmentEnd, isFalse);
      expect(e.isFinal, isFalse);
    });
    test('finalResult → final, not a segment end', () {
      final e =
          engineResultFromPlugin(r('done', ResultType.finalResult.value));
      expect(e.isFinal, isTrue);
      expect(e.isSegmentEnd, isFalse);
    });
    test('an unknown type int is a plain partial and does not throw', () {
      final e = engineResultFromPlugin(r('hm', 7));
      expect(e.isSegmentEnd, isFalse);
      expect(e.isFinal, isFalse);
    });
  });

  test('no opened box reads as enabled', () {
    expect(service().segmentAccumulateEnabled, isTrue);
  });

  group('with the config box', () {
    late Directory tmp;
    setUpAll(() async {
      tmp = Directory.systemTemp.createTempSync('speech_switch_');
      Hive.init(tmp.path);
      await Hive.openBox(HiveService.configBoxName);
      HiveService.debugMarkInitializedForTests();
    });
    tearDownAll(() async {
      await Hive.close();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('absent → enabled; true → disabled; false → enabled', () async {
      final box = Hive.box(HiveService.configBoxName);
      await box.delete(SpeechInputService.kDisableSpeechSegmentAccumulateKey);
      expect(service().segmentAccumulateEnabled, isTrue);
      await box.put(SpeechInputService.kDisableSpeechSegmentAccumulateKey, true);
      expect(service().segmentAccumulateEnabled, isFalse);
      await box.put(SpeechInputService.kDisableSpeechSegmentAccumulateKey, false);
      expect(service().segmentAccumulateEnabled, isTrue);
    });

    test('an injected value wins over the box', () async {
      final box = Hive.box(HiveService.configBoxName);
      await box.put(SpeechInputService.kDisableSpeechSegmentAccumulateKey, true);
      final s = SpeechInputService(
        engine: FakeSpeechEngine(),
        isWeb: false,
        segmentAccumulateEnabled: () => true,
      );
      expect(s.segmentAccumulateEnabled, isTrue);
    });
  });
}
