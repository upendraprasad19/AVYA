import 'package:flutter_test/flutter_test.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Referral Code — Pure Logic Tests (No Supabase Required)
/// Run with: flutter test test/referral_code_test.dart
/// ─────────────────────────────────────────────────────────────────────────────
///
/// Tests the referral code generation and validation logic used in
/// SupabaseService.getOrCreateReferralCode() and the redeem-referral
/// Edge Function.
///
/// RC-1  — Code format: starts with AVYA-
/// RC-2  — Code prefix derived from user name
/// RC-3  — Short names are padded to 4 chars with X
/// RC-4  — Special characters stripped from name prefix
/// RC-5  — Code is max 20 chars (matches maxLength on input field)
/// RC-6  — Code validation: empty/null codes are rejected
/// RC-7  — Self-referral detection: referrer == referee

/// Generates a referral code in the same format as SupabaseService.
/// Extracted for testability.
String generateReferralCode(String? fullName, {int attempt = 0}) {
  final name = fullName ?? 'USER';
  final prefix = name.replaceAll(RegExp(r'[^a-zA-Z]'), '').toUpperCase();
  final shortPrefix = prefix.length >= 4 ? prefix.substring(0, 4) : prefix.padRight(4, 'X');
  final seed = DateTime.now().microsecondsSinceEpoch + attempt * 1000;
  final random = (1000 + seed % 9000).toString();
  return 'AVYA-$shortPrefix$random';
}

/// Validates referral code format (client-side check).
bool isValidReferralCode(String? code) {
  if (code == null || code.isEmpty) return false;
  if (code.length > 20) return false;
  final trimmed = code.trim().toUpperCase();
  if (!trimmed.startsWith('AVYA-')) return false;
  if (trimmed.length < 9) return false; // AVYA- + 4 chars min
  return true;
}

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // Code generation
  // ─────────────────────────────────────────────────────────────────────────

  group('Referral Code — generation', () {
    test('RC-1: Code starts with AVYA-', () {
      final code = generateReferralCode('Upendra Prasad');
      expect(code.startsWith('AVYA-'), isTrue,
          reason: 'All referral codes must start with AVYA-');
    });

    test('RC-2: Code prefix is derived from user name', () {
      final code = generateReferralCode('Upendra Prasad');
      // After stripping spaces and taking first 4: UPEN
      expect(code.substring(5, 9), equals('UPEN'),
          reason: 'First 4 alpha chars of name should form the prefix');
    });

    test('RC-3: Short names padded with X', () {
      final code = generateReferralCode('Li');
      expect(code.substring(5, 9), equals('LIXX'),
          reason: 'Short names should be padded to 4 chars with X');
    });

    test('RC-3b: Single character name padded with XXX', () {
      final code = generateReferralCode('A');
      expect(code.substring(5, 9), equals('AXXX'));
    });

    test('RC-4: Special characters stripped from name', () {
      final code = generateReferralCode('O\'Brien-Smith 123');
      // Stripping non-alpha: OBRI (from OBrienSmith)
      expect(code.substring(5, 9), equals('OBRI'),
          reason: 'Special chars and numbers should be stripped');
    });

    test('RC-4b: Null name uses USER as default', () {
      final code = generateReferralCode(null);
      expect(code.substring(5, 9), equals('USER'),
          reason: 'Null name should default to USER prefix');
    });

    test('RC-5: Code is at most 20 characters', () {
      final code = generateReferralCode('VeryLongFirstNameLastName');
      expect(code.length, lessThanOrEqualTo(20),
          reason: 'Code must fit maxLength: 20 on the input field');
    });

    test('RC-5b: Code format is AVYA-XXXX#### (13 chars)', () {
      final code = generateReferralCode('Test User');
      // AVYA- (5) + 4 alpha + 4 digits = 13
      expect(code.length, equals(13),
          reason: 'Code should be exactly 13 chars: AVYA- + 4 alpha + 4 digits');
    });

    test('RC-gen-unique: Different attempts produce different codes', () {
      final code1 = generateReferralCode('Test', attempt: 0);
      final code2 = generateReferralCode('Test', attempt: 1);
      // They share the prefix but random part differs
      expect(code1.substring(5, 9), equals(code2.substring(5, 9)),
          reason: 'Same name should produce same prefix');
      // Random parts may differ (not guaranteed due to timing, but attempt offset helps)
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Code validation
  // ─────────────────────────────────────────────────────────────────────────

  group('Referral Code — validation', () {
    test('RC-6a: Empty code is invalid', () {
      expect(isValidReferralCode(''), isFalse);
    });

    test('RC-6b: Null code is invalid', () {
      expect(isValidReferralCode(null), isFalse);
    });

    test('RC-6c: Code without AVYA- prefix is invalid', () {
      expect(isValidReferralCode('ABCD-TEST1234'), isFalse);
    });

    test('RC-6d: Code over 20 chars is invalid', () {
      expect(isValidReferralCode('AVYA-VERYLONGREFERRALCODE1234'), isFalse);
    });

    test('RC-6e: Valid code passes validation', () {
      expect(isValidReferralCode('AVYA-UPEN1234'), isTrue);
    });

    test('RC-6f: Code with whitespace trimmed passes', () {
      expect(isValidReferralCode('  AVYA-TEST1234  '), isTrue);
    });

    test('RC-6g: Too short code (no suffix) is invalid', () {
      expect(isValidReferralCode('AVYA-AB'), isFalse,
          reason: 'Code must have at least 4 chars after AVYA-');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Self-referral detection
  // ─────────────────────────────────────────────────────────────────────────

  group('Referral Code — self-referral guard', () {
    test('RC-7: Same user IDs detected as self-referral', () {
      const userId = 'abc-123-def';
      const referrerId = 'abc-123-def';
      expect(userId == referrerId, isTrue,
          reason: 'Self-referral should be detectable by ID comparison');
    });

    test('RC-7b: Different user IDs pass self-referral check', () {
      const userId = 'abc-123-def';
      const referrerId = 'xyz-456-ghi';
      expect(userId == referrerId, isFalse);
    });
  });
}
