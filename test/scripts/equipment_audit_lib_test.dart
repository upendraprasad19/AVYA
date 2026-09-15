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

  group('the accept-list is a hole in the gate, so it is pinned', () {
    AuditFinding f(String id, String token) => AuditFinding(
          id: id,
          name: 'X',
          impliedToken: token,
          evidenceField: 'name',
          evidenceSnippet: 's',
        );

    test('an accepted (id, token) pair is held back', () {
      final p = partitionAccepted([f('E238', 'bench')]);
      expect(p.unaccepted, isEmpty);
      expect(p.accepted.single, contains('E238'));
      expect(p.accepted.single, contains('elevated surface'),
          reason: 'the reason travels with the entry, so the next audit does '
              'not have to re-derive the judgement');
    });

    test('a DIFFERENT token on an accepted row still FAILS', () {
      // The whole point of keying on the pair. If E238 later grew a pro_tip
      // naming a barbell, a bare-id exemption would swallow it in silence.
      final p = partitionAccepted([f('E238', 'barbell')]);
      expect(p.unaccepted, hasLength(1));
      expect(p.accepted, isEmpty);
    });

    test('the same token on an unaccepted row still FAILS', () {
      final p = partitionAccepted([f('E999', 'bench')]);
      expect(p.unaccepted, hasLength(1));
    });

    test('every accepted key is a well-formed id|token pair', () {
      for (final k in acceptedMentions.keys) {
        final parts = k.split('|');
        expect(parts, hasLength(2), reason: '"$k" is not id|token');
        expect(parts[0], matches(RegExp(r'^E\d{3}$')), reason: 'bad id in "$k"');
        expect(equipmentNouns.values, contains(parts[1]),
            reason: '"${parts[1]}" is not a token the scan can ever emit, so '
                'this entry exempts nothing and is dead weight');
      }
    });

    test('every accepted entry carries a non-trivial reason', () {
      // An accept-list whose entries say nothing is an allowlist, and an
      // allowlist is how a gate goes quietly inert.
      for (final e in acceptedMentions.entries) {
        expect(e.value.length, greaterThan(25),
            reason: '${e.key} has no real reason recorded');
      }
    });
  });
}
