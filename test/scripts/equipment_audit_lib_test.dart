// test/scripts/equipment_audit_lib_test.dart
//
// Unit test for the pure logic behind `check_equipment_audit.dart` (rule 24 —
// a gate ships with a test that can go RED).
//
// The gate exists because an oracle that reads the same field as its predicate
// proves THREADING, never TRUTH. `canPerform` reads `equipment_needed`; so did
// every previous check. This gate reads the exercise's NAME and coaching prose
// instead — evidence from outside the field — which is the only way to catch a
// row that simply lies.
import 'package:flutter_test/flutter_test.dart';

import '../../scripts/equipment_audit_lib.dart';

/// Stand-in for `EquipmentVocab.fromProfile`, kept trivial so these tests
/// exercise the AUDIT logic and not the vocabulary.
List<String> _norm(Object? raw) {
  if (raw is List) return raw.map((e) => e.toString().toLowerCase()).toList();
  if (raw is String) return [raw.toLowerCase()];
  return const [];
}

Map<String, dynamic> _row({
  String id = 'E001',
  String name = 'Push Up',
  Object? needed = const ['bodyweight'],
  List<String> tiers = const ['bodyweight'],
  Object? cues,
  Object? proTip,
}) =>
    <String, dynamic>{
      'id': id,
      'name': name,
      'equipment_needed': needed,
      'equipment_tier': tiers,
      'coaching_cues': ?cues,
      'pro_tip': ?proTip,
    };

void main() {
  group('auditFindings', () {
    test('a row whose prose matches its declaration is clean', () {
      final findings = auditFindings(
        rows: [_row(name: 'Push Up', needed: const ['bodyweight'])],
        normalizeNeeded: _norm,
      );
      expect(findings, isEmpty);
    });

    // ── red paths ────────────────────────────────────────────────────────
    test('a NAME that implies equipment the row does not declare is a finding', () {
      // The Bench Dips shape: name says bench, equipment_needed says bodyweight.
      final findings = auditFindings(
        rows: [_row(id: 'E238', name: 'Bench Dips', needed: const ['bodyweight'])],
        normalizeNeeded: _norm,
      );
      expect(findings, isNotEmpty);
      expect(findings.first.impliedToken, 'bench');
      expect(findings.first.evidenceField, 'name');
    });

    test('coaching prose is scanned, not just the name', () {
      // The Towel Row shape: the anchor only shows up in the cues.
      final findings = auditFindings(
        rows: [
          _row(
            id: 'E255',
            name: 'Row Variation',
            needed: const ['bodyweight'],
            cues: const ['loop towel around a sturdy door'],
          )
        ],
        normalizeNeeded: _norm,
      );
      expect(findings, isNotEmpty);
      expect(findings.first.impliedToken, 'towel');
      expect(findings.first.evidenceField, 'coaching_cues');
    });

    test('every finding carries an evidence snippet a human can judge', () {
      // False positives are expected, so a finding without evidence is useless.
      final findings = auditFindings(
        rows: [
          _row(
            name: 'Glute Kickback',
            needed: const ['bodyweight'],
            proTip: 'add an ankle weight or resistance band to increase difficulty',
          )
        ],
        normalizeNeeded: _norm,
      );
      expect(findings, isNotEmpty);
      expect(findings.first.evidenceSnippet, contains('resistance band'));
      expect(findings.first.toString(), contains('Glute Kickback'));
    });

    test('a declared token is NOT reported', () {
      final findings = auditFindings(
        rows: [
          _row(name: 'Barbell Row', needed: const ['barbell'],
              tiers: const ['bodyweight'])
        ],
        normalizeNeeded: _norm,
      );
      expect(findings, isEmpty);
    });

    test('non-bodyweight rows are skipped by default', () {
      final findings = auditFindings(
        rows: [
          _row(name: 'Bench Press', needed: const ['barbell'],
              tiers: const ['full_gym'])
        ],
        normalizeNeeded: _norm,
      );
      expect(findings, isEmpty);
    });

    test('--all-tiers scope reaches them', () {
      final findings = auditFindings(
        rows: [
          _row(name: 'Bench Press', needed: const ['barbell'],
              tiers: const ['full_gym'])
        ],
        normalizeNeeded: _norm,
        bodyweightTierOnly: false,
      );
      expect(findings, isNotEmpty);
      expect(findings.first.impliedToken, 'bench');
    });

    test('a row with no prose fields produces nothing', () {
      final findings = auditFindings(
        rows: [
          <String, dynamic>{
            'id': 'E999',
            'equipment_needed': const ['bodyweight'],
            'equipment_tier': const ['bodyweight'],
          }
        ],
        normalizeNeeded: _norm,
      );
      expect(findings, isEmpty);
    });
  });

  group('the noun map', () {
    test('every value is a plausible canonical token, not free text', () {
      for (final v in equipmentNouns.values) {
        expect(v, isNot(contains(RegExp(r'[A-Z]'))),
            reason: 'canonical tokens are lowercase');
        expect(v.trim(), v);
      }
    });

    test('the four rows that motivated check_equipment_audit are reachable', () {
      // Negative Pull Up, Bench Dips, Doorframe Curl, Towel Row — each was
      // already wrong BEFORE the normalizer ran, so git recovery cannot reach
      // them, and each is its pattern's sole core-satisfying entry.
      expect(equipmentNouns.keys, contains('pull up'));
      expect(equipmentNouns.keys, contains('bench'));
      expect(equipmentNouns.keys, contains('doorframe'));
      expect(equipmentNouns.keys, contains('towel'));
    });
  });
}
