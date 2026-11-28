import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source_scan.dart';

/// OI-348 Landing 3a (P1, founder decision 2026-11-22): phases keep coming
/// after XII and the copy says "all phases". This bans the old "2-12" /
/// "II–XII" / "48-week" wording from every Dart string under lib/ and from the
/// coach's manual.
///
/// Limits (round 2, R2-8): comments are stripped by the string-aware
/// `stripDartComments`, so text in a comment is allowed; a "2-12" split
/// across concatenated literals, or spelled with a `–` escape, is not
/// seen. The Deno twin is `captain_manual_limits_test.ts`.
final _banned = <RegExp>[
  RegExp(r'\b2\s*[-–]\s*12\b'),
  RegExp(r'\bII\s*[-–]\s*XII\b'),
  RegExp(r'48[- ]week', caseSensitive: false),
];

void main() {
  test('no "phases end at 12" wording in lib/ Dart code', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines =
          stripDartComments(f.readAsStringSync()).split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final re in _banned) {
          if (re.hasMatch(lines[i])) {
            hits.add('${f.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(hits, isEmpty);
  });

  test('the coach manual says "no end point", not II–XII', () {
    final s = File('supabase/functions/_shared/captain_manual.ts')
        .readAsStringSync();
    for (final re in _banned) {
      expect(re.hasMatch(s), isFalse, reason: re.pattern);
    }
    expect(s, contains('All phases after Phase I auto-generated, with no end point'));
  });

  test('the five paywall doors use the one constant', () {
    const files = [
      'lib/features/train/screens/graduation_screen.dart',
      'lib/features/train/screens/train/phase_unlock_card.dart',
      'lib/features/train/widgets/plan_expired_card.dart',
      'lib/shared/widgets/paywall_sheet_phase_variant.dart',
    ];
    var count = 0;
    for (final p in files) {
      final s = stripDartComments(File(p).readAsStringSync());
      count += 'PaywallSheet.phaseProgressionFeature'.allMatches(s).length;
    }
    expect(count, 5);
    expect(
        stripDartComments(
            File('lib/shared/widgets/paywall_sheet.dart').readAsStringSync()),
        contains('case PaywallSheet.phaseProgressionFeature:'));
  });
}
