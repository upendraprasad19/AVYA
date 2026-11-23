// OI-348 B5 (diagnose 6d9f3b): the real `disable_speech_segment_accumulate`
// read. The controller tests inject the switch; this pins the getter itself:
// absent → on, `true` → off, no opened box → on (the plate_flags guard).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/speech_input_service.dart';

import '../helpers/fake_speech_engine.dart';

void main() {
  SpeechInputService service() =>
      SpeechInputService(engine: FakeSpeechEngine(), isWeb: false);

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
