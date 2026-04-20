import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/services/identity_signal_detector.dart';

void main() {
  late IdentitySignalDetector det;

  setUp(() => det = IdentitySignalDetector());

  group('Hinglish detection', () {
    test('pure English does NOT flip style', () {
      final s = det.detect('What should I eat for dinner today?');
      expect(s.communicationStyle, isNull);
    });

    test('single Hinglish message alone does not flip (sticky)', () {
      final s = det.detect('yaar today bench dabaya');
      expect(s.communicationStyle, isNull);
    });

    test('three consecutive Hinglish messages flip to hinglish', () {
      det.detect('yaar today bench dabaya');
      det.detect('bhai mera workout kaisa raha');
      final s = det.detect('aaj kya khaaun bata');
      expect(s.communicationStyle, equals('hinglish'));
    });

    test('Devanagari script triggers hinglish on first message', () {
      final s = det.detect('आज वर्कआउट कैसा रहा');
      expect(s.communicationStyle, equals('hinglish'));
    });

    test('one-word match (e.g. "yaar") in English sentence does NOT count as Hinglish', () {
      final s = det.detect('I want to bulk yaar');
      expect(s.communicationStyle, isNull);
    });
  });

  group('preferred name detection', () {
    test('"call me Upen" extracts preferred name', () {
      final s = det.detect('call me Upen');
      expect(s.preferredName, equals('Upen'));
    });

    test('"my name is Upendra" extracts preferred name', () {
      final s = det.detect('my name is Upendra');
      expect(s.preferredName, equals('Upendra'));
    });

    test('"I\'m Upen" extracts preferred name', () {
      final s = det.detect("I'm Upen");
      expect(s.preferredName, equals('Upen'));
    });

    test('no name pattern returns null', () {
      final s = det.detect('what is my macros today');
      expect(s.preferredName, isNull);
    });

    test('rejects names < 2 chars or > 20 chars', () {
      expect(det.detect('call me X').preferredName, isNull);
      expect(det.detect('call me ${"a" * 25}').preferredName, isNull);
    });
  });
}
