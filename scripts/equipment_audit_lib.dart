// scripts/equipment_audit_lib.dart
//
// ⑦ OI-89 Gate B — does a row's prose contradict its `equipment_needed`?
//
// WHY THIS EXISTS. The capability predicate reads `equipment_needed`. So does
// every oracle that checks it. An oracle sharing a field with its predicate can
// prove the check is THREADED; it can never prove the field is TRUE. That is how
// four rows survived every previous guard:
//
//   Negative Pull Up  ['bodyweight']  — needs a pull-up bar
//   Bench Dips        ['bodyweight']  — needs a bench or chair
//   Doorframe Curl    ['bodyweight']  — needs a doorway
//   Towel Row         ['bodyweight']  — needs a towel and an anchor
//
// Each is the SOLE core-satisfying row for its movement pattern, so the floor
// invariant would have gone green on false data. Note these were already wrong
// BEFORE `scripts/normalize_equipment_library.dart` ran, so recovering the
// pre-normalization values from git cannot reach them either — git answers
// "what did the tool change", not "what is wrong".
//
// This gate takes its evidence from OUTSIDE the field: the exercise name and the
// free-text coaching prose. False positives are expected and real (a `pro_tip`
// may mention a barbell only to contrast with it), so this is TRIAGE INPUT, not
// a verdict — it ships `--warn-only` first per §4.11.
//
// Pure (no dart:io) so the gate's own test can drive it with synthetic rows.

/// Prose nouns → the canonical token they imply.
///
/// Deliberately narrow: every entry is equipment that decides whether a
/// BODYWEIGHT user can perform the row. Adding a noun that is merely mentionable
/// (e.g. "muscle") would drown the signal.
const equipmentNouns = <String, String>{
  'pull-up bar': 'pull-up bar',
  'pull up bar': 'pull-up bar',
  'pullup bar': 'pull-up bar',
  'chin-up bar': 'pull-up bar',
  'overhead bar': 'pull-up bar',
  'ab wheel': 'ab wheel',
  'ab roller': 'ab wheel',
  'jump rope': 'jump rope',
  'skipping rope': 'jump rope',
  'medicine ball': 'medicine ball',
  'med ball': 'medicine ball',
  'parallel bars': 'parallel bars',
  'parallettes': 'parallel bars',
  'dip station': 'parallel bars',
  'dip bars': 'parallel bars',
  'suspension trainer': 'suspension trainer',
  'trx': 'suspension trainer',
  'plyo box': 'plyo box',
  'plyometric box': 'plyo box',
  'battle rope': 'battle ropes',
  'resistance band': 'resistance band',
  // Bare 'pull up' / 'bench' are deliberate: they catch Negative Pull Up and
  // Bench Dips, two of the four rows that were already wrong BEFORE the
  // normalizer ran and that each carry their pattern's only core-satisfying
  // entry. They cost some false positives on prose that merely mentions a
  // bench; that is the right trade for a triage gate.
  'pull up': 'pull-up bar',
  'pull-up': 'pull-up bar',
  'pullup': 'pull-up bar',
  'bench': 'bench',
  'doorway': 'doorway',
  'door frame': 'doorway',
  'doorframe': 'doorway',
  'towel': 'towel',
  'barbell': 'barbell',
  'dumbbell': 'dumbbells',
  'kettlebell': 'kettlebell',
  'cable': 'cables',
  'smith machine': 'smith machine',
};

/// A finding: a row whose prose implies equipment its `equipment_needed` omits.
class AuditFinding {
  final String id;
  final String name;
  final String impliedToken;
  final String evidenceField;
  final String evidenceSnippet;
  const AuditFinding({
    required this.id,
    required this.name,
    required this.impliedToken,
    required this.evidenceField,
    required this.evidenceSnippet,
  });

  @override
  String toString() =>
      '$id $name: prose implies "$impliedToken" but equipment_needed omits it '
      '($evidenceField: "...$evidenceSnippet...")';
}

/// Fields scanned for equipment nouns. There is no `description` field on this
/// library; these five are the free-text carriers.
const auditedFields = <String>[
  'name',
  'coaching_cues',
  'common_mistakes',
  'pro_tip',
  'warmup_protocol',
];

String _flatten(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is List) return v.map(_flatten).join(' ');
  if (v is Map) return v.values.map(_flatten).join(' ');
  return v.toString();
}

/// Rows whose prose names equipment their `equipment_needed` does not declare.
///
/// [normalizeNeeded] injects `EquipmentVocab.fromProfile` so this stays pure and
/// the test can drive it without the Flutter package.
List<AuditFinding> auditFindings({
  required List<Map<String, dynamic>> rows,
  required List<String> Function(Object?) normalizeNeeded,
  bool bodyweightTierOnly = true,
}) {
  final findings = <AuditFinding>[];
  for (final r in rows) {
    if (bodyweightTierOnly) {
      final tiers = (r['equipment_tier'] as List?)
              ?.map((e) => e.toString().toLowerCase())
              .toSet() ??
          const <String>{};
      if (!tiers.contains('bodyweight')) continue;
    }
    final declared = normalizeNeeded(r['equipment_needed']).toSet();
    for (final field in auditedFields) {
      final text = _flatten(r[field]).toLowerCase();
      if (text.isEmpty) continue;
      for (final entry in equipmentNouns.entries) {
        if (!text.contains(entry.key)) continue;
        if (declared.contains(entry.value)) continue;
        final at = text.indexOf(entry.key);
        final from = (at - 18) < 0 ? 0 : at - 18;
        final to = (at + entry.key.length + 18) > text.length
            ? text.length
            : at + entry.key.length + 18;
        findings.add(AuditFinding(
          id: (r['id'] ?? '?').toString(),
          name: (r['name'] ?? '?').toString(),
          impliedToken: entry.value,
          evidenceField: field,
          evidenceSnippet: text.substring(from, to).trim(),
        ));
        break; // one finding per field per row keeps the report readable
      }
    }
  }
  return findings;
}

/// (row id, implied token) pairs judged NOT to be defects, with the reason.
/// A pair, never a bare id: a new finding on an accepted row must still fail.
const acceptedMentions = <String, String>{
  'E042|dumbbells': 'pro_tip: "add dumbbells once 3x20 feels easy" - a progression',
  'E073|suspension trainer': 'pro_tip: "assisted pistol with trx or band FIRST" - a regression aid',
  'E210|pull-up bar': 'pro_tip names OTHER exercises ("before deadlifts, pull-ups")',
  'E220|bench': 'pro_tip: "rounded posture from bench press and desk work" - a contrast',
  'E222|bench': 'pro_tip: "rest upper back on a bench AND add a barbell" - the loaded progression; cues are floor-based',
  'E227|barbell': 'pro_tip: "without needing a barbell" - an explicit contrast',
  'E233|parallel bars': 'cues offer "handles, BOOKS, or parallettes" - books are household, so the row needs only an elevated surface',
  'E257|resistance band': 'pro_tip: "add ankle weight or resistance band to increase difficulty"',
  'E259|bench': 'pro_tip: "elevate rear foot on a bench" describes a DIFFERENT exercise (Bulgarian split squat)',
  'E261|bench': 'cues: "lie face-down on the floor OR a bench" - the floor is offered',
  'E074|bench': 'pro_tip/common_mistakes reference a flat-bench regression; the row itself needs only an elevated surface',
  'E134|bench': 'common_mistakes describes the setup generically; a chair or sofa serves',
  // -- gym-tier mentions, judged during the OI-89 B-pass `--all-tiers` sweep.
  // Comparison prose ("superior to dumbbell", "without a barbell", "kettlebell
  // swing first") is the dominant shape at these tiers and the scan cannot tell
  // a comparison from a requirement. E260 Incline Dumbbell Press was the ONE
  // real defect among the 18 -- its first cue says "Set bench to 30-45 degree
  // incline" unconditionally while the row claimed only dumbbells, so it was
  // fixed in the DATA and is deliberately not listed here.
  'E002|barbell': 'pro_tip: "% more range than barbell" - a comparison',
  'E035|barbell': 'pro_tip: "constant tension barbell cannot" - a comparison',
  'E097|dumbbells': 'pro_tip: "constant tension that dumbbells cannot" - a comparison',
  'E098|bench': 'cues offer "hinged at hip OR on incline bench" - the hinge needs nothing',
  'E125|bench': 'the row already declares `elevated surface`; the prose word is "elevated bench", and it is barbell-gated regardless',
  'E182|barbell': 'pro_tip: "barbell carry experience" - a reference to a different lift',
  'E184|kettlebell': 'pro_tip: "kettlebell swing first" - a progression reference',
  'E185|dumbbells': 'pro_tip: "practice movement with dumbbell first" - a regression aid',
  'E187|dumbbells': 'prose compares to the dumbbell row twice; this row IS the kettlebell version',
  'E223|barbell': 'pro_tip: "stimulus without a barbell" - an explicit contrast',
  'E224|kettlebell': 'cues: "think kettlebell swing, not squat" - a CUE METAPHOR, not kit',
  'E234|bench': 'cues say "lie on the FLOOR", pro_tip says "with no bench" - the contrast is the point',
  'E235|dumbbells': 'pro_tip: "superior to dumbbell for lateral delt" - a comparison',
  'E236|dumbbells': 'pro_tip: "dumbbell version does not" - a comparison',
  'E237|dumbbells': 'pro_tip: "more hypertrophic than dumbbell laterals" - a comparison',
  'E238|bench': 'the row is NAMED "Bench Dips" and its cues say "bench edge" -- but a chair, '
      'sofa or step serves, which is exactly why the requirement is `elevated surface` and not '
      '`bench`. Renaming it would break standard_swap references and every logged set keyed '
      'on the name, so the name stays and the mention is accepted here.',
};

/// The result of splitting findings against [acceptedMentions].
class AuditPartition {
  final List<AuditFinding> unaccepted;
  final List<String> accepted;
  const AuditPartition(this.unaccepted, this.accepted);
}

/// Split [findings] into those that must fail the gate and those a human has
/// judged benign.
///
/// The key is `id|impliedToken`, NOT a bare id. A bare id would exempt the whole
/// ROW, so a genuinely new finding on an already-accepted row would pass in
/// silence -- which is the failure mode an accept-list is most likely to have.
AuditPartition partitionAccepted(List<AuditFinding> findings) {
  final unaccepted = <AuditFinding>[];
  final accepted = <String>[];
  for (final f in findings) {
    final reason = acceptedMentions['${f.id}|${f.impliedToken}'];
    if (reason == null) {
      unaccepted.add(f);
    } else {
      accepted.add('${f.id} ${f.name} / ${f.impliedToken}: $reason');
    }
  }
  return AuditPartition(unaccepted, accepted);
}
