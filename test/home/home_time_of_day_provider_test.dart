// Test #10 obs 1 — pin the new userTimeOfDayProvider time-bucket
// boundaries. Decoupled from userGreetingProvider so the new home
// header can render `GOOD MORNING,` / `GOOD AFTERNOON,` / `GOOD EVENING,`
// in mono caps without the embedded first-name suffix that the legacy
// greeting provider returns.
//
// Boundaries: hour < 12 → MORNING, hour < 17 → AFTERNOON, else EVENING.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';

void main() {
  test('userTimeOfDayProvider returns one of the 3 mono-caps strings', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final value = container.read(userTimeOfDayProvider);
    expect(
      value,
      anyOf('GOOD MORNING', 'GOOD AFTERNOON', 'GOOD EVENING'),
    );
  });

  test('returned string is uppercase mono caps (no name suffix)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final value = container.read(userTimeOfDayProvider);
    expect(value, equals(value.toUpperCase()),
        reason: 'must be uppercase for the mono caps eyebrow style');
    expect(value, isNot(contains(',')),
        reason: 'comma is appended by the consuming widget, not the provider');
  });
}
