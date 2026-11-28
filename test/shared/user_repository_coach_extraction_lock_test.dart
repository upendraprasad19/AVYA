import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

// a2b-2 (single-owner batch, 2026-09-27): pins UserRepository.
// shouldLockOnboardingInjuries — the pure decision extracted from
// syncOnboardingToSupabase's injuries-lock trigger, so the value-equality
// requirement (not a bare `!=` on lists, which is always true in Dart) is
// genuinely behaviorally tested rather than only source-grep pinned.
void main() {
  group('UserRepository.shouldLockOnboardingInjuries', () {
    test('the ["none"] default is NOT locked', () {
      expect(UserRepository.shouldLockOnboardingInjuries(['none']), isFalse);
    });

    test('a genuine single injury IS locked', () {
      expect(UserRepository.shouldLockOnboardingInjuries(['knee']), isTrue);
    });

    test('a genuine multi-injury selection IS locked', () {
      expect(
        UserRepository.shouldLockOnboardingInjuries(['knee', 'shoulder']),
        isTrue,
      );
    });

    test('a DIFFERENT list instance with the SAME single "none" content is NOT locked (value equality, not reference equality)', () {
      // Two separate list literals — if the implementation used a bare `!=`
      // this would incorrectly read as "changed" (reference inequality is
      // always true between two distinct List instances in Dart).
      final a = List<String>.from(['none']);
      expect(UserRepository.shouldLockOnboardingInjuries(a), isFalse);
    });

    test('an empty list IS locked (only the exact ["none"] sentinel is exempt)', () {
      expect(UserRepository.shouldLockOnboardingInjuries([]), isTrue);
    });
  });
}
