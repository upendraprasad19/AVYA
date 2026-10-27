// scripts/gate_test_ledger_lib.dart
//
// Pure parsing + verdict logic for docs/audit/gate_test_ledger.yaml (rule 24).
// No filesystem, no process spawning. Named without the `check_` prefix so the
// gate loop treats only the gate itself as a gate, not this lib.
//
// Hand-parsed rather than via a YAML package: this repo has no `yaml`
// dependency and `validate_audit_closure.dart` (the closest precedent) also
// hand-parses. The accepted shape is deliberately narrow — two levels, one
// state key per entry — so a hand parser is adequate and a malformed file
// fails loudly rather than being silently half-read.
//
// WHAT THIS CAN AND CANNOT PROVE
//   A script cannot prove a mutation was actually RUN. What it CAN prove — and
//   what this checks — is that the named test exists, references the gate, and
//   asserts a FAILING path. That is precisely the class Gate 44 shipped: a test
//   that passed whether or not the gate worked. Making that class mechanically
//   impossible is the whole point; the residual "was the mutation real?" is
//   self-attested and read by the ×2 plan review, the same trust model as
//   Gate 42's `presence_only:` and the plan-review gate's `tier:` field.

enum LedgerState { mutationProven, grandfathered, testExempt }

class LedgerEntry {
  const LedgerEntry({
    required this.gate,
    required this.state,
    this.testPaths = const [],
    this.evidence,
    this.reason,
    this.grandfatheredDate,
  });

  final String gate;
  final LedgerState state;
  final List<String> testPaths;
  final String? evidence;
  final String? reason;
  final String? grandfatheredDate;
}

class LedgerViolation {
  const LedgerViolation(this.gate, this.message);
  final String gate;
  final String message;

  @override
  String toString() => '$gate: $message';
}

/// The ONE date the closed grandfather list carries. A date check alone does
/// NOT close a list — see [checkLedger], which requires membership by NAME.
const String grandfatherDate = '2026-08-10';

/// Accepted red-path assertion forms — a closed, literal set of two families.
///
/// The principle: the test must assert the gate DETECTING something. Either the
/// process exits non-zero, or the collection the gate produces when it finds a
/// problem is asserted non-empty. Both families are needed — a pure
/// `_lib_test.dart` never spawns a process, and an e2e never sees the
/// collection.
///
/// Left open-ended ("or an assertion on a violating verdict", as an earlier
/// draft had it) the implementer invents a form and the check becomes
/// unfalsifiable. Bare `isNotEmpty` is deliberately NOT accepted: it appears in
/// hundreds of unrelated assertions and would make this pass for almost any
/// file, which is the Gate-44 failure wearing a different hat.
final List<RegExp> redPathForms = <RegExp>[
  RegExp(r'exitCode,\s*(1|2|isNot\(0\)|isNonZero|greaterThan\(0\))'),
  RegExp(r'(violations|collisions|problems|findings|failures|conflicts|'
      r'disagreements|unregistered)\s*,\s*(isNotEmpty|hasLength)'),
  RegExp(r'(isViolation|hasViolation)\s*,\s*isTrue'),
];

bool containsRedPathAssertion(String testSource) =>
    redPathForms.any((r) => r.hasMatch(testSource));

/// Parses the ledger's narrow two-level shape. Returns entries keyed by gate.
/// Throws [FormatException] on a shape the schema does not allow.
Map<String, LedgerEntry> parseLedger(String yaml) {
  final out = <String, LedgerEntry>{};
  String? gate;
  LedgerState? state;
  var testPaths = <String>[];
  String? evidence;
  String? reason;
  String? date;
  var seenStateKeys = 0;

  void flush() {
    final g = gate;
    if (g == null) return;
    final st = state;
    if (st == null) {
      throw FormatException('$g: no state key '
          '(mutation_proven / grandfathered / test_exempt)');
    }
    if (seenStateKeys > 1) {
      throw FormatException('$g: $seenStateKeys state keys; exactly 1 allowed');
    }
    out[g] = LedgerEntry(
      gate: g,
      state: st,
      testPaths: List.unmodifiable(testPaths),
      evidence: evidence,
      reason: reason,
      grandfatheredDate: date,
    );
    state = null;
    testPaths = <String>[];
    evidence = null;
    reason = null;
    date = null;
    seenStateKeys = 0;
  }

  for (final raw in yaml.replaceAll('\r\n', '\n').split('\n')) {
    final line = raw.trimRight();
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;

    // Top-level key: `check_foo.dart:`
    if (!line.startsWith(' ') && line.endsWith(':')) {
      flush();
      gate = line.substring(0, line.length - 1).trim();
      continue;
    }
    if (gate == null) {
      throw FormatException('content before any gate key: $line');
    }

    final t = line.trim();
    if (t.startsWith('- ')) {
      testPaths.add(_unquote(t.substring(2).trim()));
      continue;
    }
    final idx = t.indexOf(':');
    if (idx < 0) continue;
    final key = t.substring(0, idx).trim();
    final value = _unquote(t.substring(idx + 1).trim());

    switch (key) {
      case 'mutation_proven':
        state = LedgerState.mutationProven;
        seenStateKeys++;
        break;
      case 'grandfathered':
        state = LedgerState.grandfathered;
        date = value;
        seenStateKeys++;
        break;
      case 'test_exempt':
        state = LedgerState.testExempt;
        reason = value;
        seenStateKeys++;
        break;
      case 'evidence':
        evidence = value;
        break;
      case 'test_path':
        if (value.isNotEmpty) testPaths.add(value);
        break;
    }
  }
  flush();
  return out;
}

String _unquote(String v) {
  if (v.length >= 2 &&
      ((v.startsWith('"') && v.endsWith('"')) ||
          (v.startsWith("'") && v.endsWith("'")))) {
    return v.substring(1, v.length - 1);
  }
  return v;
}

/// Full verdict.
///
/// [gatesOnDisk]      every `check_*.dart` basename present in scripts/.
/// [grandfathered]    the CLOSED list, BY NAME. Membership — not the date
///                    string — is what closes it: a date-equality check lets
///                    any future gate write `grandfathered: 2026-08-10` and
///                    pass, and both gates born in this batch carry that very
///                    date, so the boundary would be ambiguous on day one.
/// [testFileExists]   does this path exist?
/// [readTestFile]     source of a test file, or null if unreadable.
List<LedgerViolation> checkLedger({
  required Map<String, LedgerEntry> ledger,
  required Set<String> gatesOnDisk,
  required Set<String> grandfathered,
  required bool Function(String path) testFileExists,
  required String? Function(String path) readTestFile,
}) {
  final violations = <LedgerViolation>[];

  for (final gate in gatesOnDisk.toList()..sort()) {
    final entry = ledger[gate];
    if (entry == null) {
      violations.add(LedgerViolation(
          gate,
          'missing from docs/audit/gate_test_ledger.yaml. Every check_*.dart '
          'needs exactly one state. A NEW gate cannot be grandfathered '
          '(rule 24) — add mutation_proven with test_path + evidence, or '
          'test_exempt with a reason.'));
      continue;
    }

    switch (entry.state) {
      case LedgerState.grandfathered:
        if (!grandfathered.contains(gate)) {
          violations.add(LedgerViolation(
              gate,
              'is not on the closed grandfather list. That list is enumerated '
              'BY NAME in check_gate_test_ledger.dart and is closed — writing '
              '`grandfathered: $grandfatherDate` does not join it.'));
        } else if (entry.grandfatheredDate != grandfatherDate) {
          violations.add(LedgerViolation(
              gate,
              'grandfathered date is "${entry.grandfatheredDate}", '
              'expected "$grandfatherDate".'));
        }
        break;

      case LedgerState.testExempt:
        if ((entry.reason ?? '').trim().isEmpty) {
          violations.add(
              LedgerViolation(gate, 'test_exempt needs a non-empty reason.'));
        }
        break;

      case LedgerState.mutationProven:
        if ((entry.evidence ?? '').trim().isEmpty) {
          violations.add(LedgerViolation(
              gate,
              'mutation_proven needs non-empty evidence naming what was '
              'neutered and how many tests reddened.'));
        }
        if (entry.testPaths.isEmpty) {
          violations.add(LedgerViolation(
              gate, 'mutation_proven needs at least one test_path.'));
          break;
        }
        var namesGate = false;
        var hasRedPath = false;
        for (final p in entry.testPaths) {
          if (!testFileExists(p)) {
            violations.add(LedgerViolation(gate, 'test_path "$p" does not exist.'));
            continue;
          }
          final src = readTestFile(p);
          if (src == null) continue;
          if (src.contains(gate.replaceAll('.dart', ''))) namesGate = true;
          if (containsRedPathAssertion(src)) hasRedPath = true;
        }
        if (!namesGate) {
          violations.add(LedgerViolation(
              gate, 'no test_path file references this gate by name.'));
        }
        if (!hasRedPath) {
          violations.add(LedgerViolation(
              gate,
              'no test_path file contains a red-path assertion. A test that '
              'only proves the happy path passes whether or not the gate works '
              '— that is exactly what Gate 44 shipped.'));
        }
        break;
    }
  }

  // A ledger entry for a gate that no longer exists is stale bookkeeping.
  for (final gate in ledger.keys.toList()..sort()) {
    if (!gatesOnDisk.contains(gate)) {
      violations.add(LedgerViolation(
          gate, 'has a ledger entry but no scripts/$gate on disk.'));
    }
  }

  return violations;
}
