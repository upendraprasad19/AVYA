// Regression test for OI-252 (workout templates: one stable identity).
// Pins `lib/core/services/template_identity.dart` — the pure key<->uuid
// conversion every template sync/restore/delete path now shares.
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/template_identity.dart';

void main() {
  group('templateKeyFor', () {
    test('prefixes the uuid with tmpl_', () {
      const uuid = 'a1b2c3d4-e5f6-4789-90ab-cdef01234567';
      expect(templateKeyFor(uuid), 'tmpl_$uuid');
    });
  });

  group('cloudIdFromKey', () {
    test('extracts the uuid from a stable-identity key', () {
      const uuid = 'a1b2c3d4-e5f6-4789-90ab-cdef01234567';
      expect(cloudIdFromKey('tmpl_$uuid'), uuid);
    });

    test('round-trips through templateKeyFor', () {
      const uuid = '11111111-2222-3333-4444-555555555555';
      expect(cloudIdFromKey(templateKeyFor(uuid)), uuid);
    });

    test('is case-insensitive on the uuid', () {
      const uuid = 'A1B2C3D4-E5F6-4789-90AB-CDEF01234567';
      expect(cloudIdFromKey('tmpl_$uuid'), uuid);
    });

    // Legacy pre-migration keys — the shapes real devices hold today.
    test('returns null for a legacy ms-timestamp key (create path)', () {
      expect(cloudIdFromKey('tmpl_1758901234567'), isNull);
    });

    test('returns null for a legacy namehash key (restore path)', () {
      expect(cloudIdFromKey('tmpl_a3f9'), isNull);
    });

    test('returns null for a key missing the tmpl_ prefix', () {
      expect(cloudIdFromKey('a1b2c3d4-e5f6-4789-90ab-cdef01234567'), isNull);
    });

    test('returns null for a non-template key entirely', () {
      expect(cloudIdFromKey('schedule_2026-09-26'), isNull);
    });

    test('returns null for a uuid-shaped string missing one segment', () {
      // Guards against a loosened regex accepting a truncated/malformed id.
      expect(cloudIdFromKey('tmpl_a1b2c3d4-e5f6-4789-90ab'), isNull);
    });

    test('returns null for the bare tmpl_ prefix with nothing after it', () {
      expect(cloudIdFromKey('tmpl_'), isNull);
    });
  });
}
