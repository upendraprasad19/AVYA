import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// Pins the weekly-report fixes (diagnose c7a1f5): the EF reads the canonical
/// stored macro target instead of recomputing, and the report refreshes on open.
void main() {
  final ef = _strip(
      File('supabase/functions/weekly-report/index.ts').readAsStringSync());
  final screen = _strip(
      File('lib/features/profile/screens/reports_screen.dart').readAsStringSync());

  group('weekly report canonical target + refresh-on-open', () {
    test('EF selects the canonical stored macro columns', () {
      expect(ef.contains('daily_calories'), isTrue);
      expect(ef.contains('protein_grams'), isTrue);
    });

    test('EF uses the stored target (not only a recomputed estimate)', () {
      expect(ef.contains('storedCalories'), isTrue);
      expect(ef.contains('storedProtein'), isTrue);
    });

    test('report refreshes on open via a silent regenerate', () {
      expect(screen.contains('_generateReport(silent: true)'), isTrue);
    });
  });
}
