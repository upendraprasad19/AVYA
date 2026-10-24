// Pins the client-side capability handshake const (spec §5.8, Task 9/U3's
// day_swap_routing.ts + Task 27/U6's swapWorkoutDaysTool.requiresCapability
// both use the literal "swap_workout_days" — this list is what the CLIENT
// declares it can honour).

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/services/coach_client_capabilities.dart';

void main() {
  test('declares swap_workout_days', () {
    expect(kCoachClientCapabilities, contains('swap_workout_days'));
  });

  test('every entry matches the server-side validation regex ^[a-z_]{1,48}\$', () {
    final pattern = RegExp(r'^[a-z_]{1,48}$');
    for (final cap in kCoachClientCapabilities) {
      expect(pattern.hasMatch(cap), isTrue,
          reason: '"$cap" must match the server\'s parseClientCapabilities '
              'entry pattern (client_capabilities.ts) or the server silently '
              'drops it and the tool never unlocks.');
    }
  });

  test('at most 32 entries (server caps client_capabilities at 32)', () {
    expect(kCoachClientCapabilities.length, lessThanOrEqualTo(32));
  });

  test('no duplicates', () {
    expect(kCoachClientCapabilities.toSet().length, kCoachClientCapabilities.length);
  });
}
