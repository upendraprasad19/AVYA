// scripts/gate_index_lib.dart
//
// Pure parsing + collision detection for the gate registry. No filesystem, no
// git, no process spawning — every branch is unit-testable deterministically.
// Named WITHOUT the `check_` prefix so the pre-commit `check_*.dart` gate loop
// (and Gate 33) treat only the gates themselves as gates, not this lib — same
// convention as `worktree_guard_lib.dart` / `retire_worktree_lib.dart`.
//
// WHY THIS EXISTS
//   A gate number was ambiguous. "Gate 44" named two unrelated scripts, so a
//   citation could not be resolved to a script at all. Five separate surveys
//   during the 2026-08-10 batch returned five DIFFERENT collision counts
//   (1 → 3 → 2 → 3 → 4 → 5), every one of them from a too-narrow input set:
//   a sed/awk pair broken by backslash escaping; a scan that matched
//   cross-references (`// Mirrors Gate 17`) as declarations; a `check_*.dart`
//   glob blind to `validate_audit_closure.dart` (Gate 40); a regex requiring
//   `Gate N` to be followed by `:—-(`, blind to the `Gate 18.` / `Gate 18)`
//   forms; and finally a scan blind to the audit closure ledgers, which are the
//   ONLY claim Gate 45 and Gate 7 have.
//
//   That is six instances of `feedback_green_check_input_set_width` on ONE
//   question. The canonical declaration format below is what makes "which
//   script claims N" mechanically answerable instead of a fresh guess each
//   time.
//
// THE CANONICAL FORM — `// Gate: 44`, alone on its line, first 10 lines.
//   Matched by `^// Gate: (\d+[a-z]?)$`, anchored at BOTH ends, after CRLF
//   normalization. Which anchor does which job (each verified against a real
//   file, because an earlier draft of this rationale was wrong on all three):
//     - `check_adr_index_fresh.dart:1` `// Gate: confirms docs/adr/…` is
//       excluded by `\d+`, NOT by the end anchor.
//     - `// Mirrors Gate 17` is excluded by the START anchor.
//     - `// Gate 44 — Nested CLAUDE.md content quality` is excluded by the
//       MISSING COLON.
//     - `// Gate: 13 — APK size…` is excluded by the END anchor. That is the
//       end anchor's actual job.
//
// CRLF normalization is mandatory even though this repo has zero CRLF files
// today (`.gitattributes` `* text=auto eol=lf` beats `core.autocrlf=true`).
// Without it a trailing `\r` kills the `$` anchor, every declaration reads as
// absent, and the generator emits an index with zero numbers and zero
// collisions — green, and completely wrong. Precedent:
// `check_sot_behavioral_test_paths.dart:55`.

/// Where a claim on a gate number came from. All four are authoritative; a
/// number minted in a closure ledger is as real as one in a script header.
enum ClaimSource { header, buildApk, ledger }

class GateClaim {
  const GateClaim({
    required this.script,
    required this.number,
    required this.source,
    required this.origin,
  });

  /// Basename, e.g. `check_device_tests_exist.dart`.
  final String script;

  /// `44`, `14b`. Kept as a STRING: `14b` exists, and reserved `3.5` must be
  /// comparable without being parsed as an int.
  final String number;

  final ClaimSource source;

  /// Human-readable provenance for the failure message, e.g.
  /// `docs/audit/2026_05_20_audit_closures.yaml`.
  final String origin;

  @override
  String toString() => '$script (Gate $number, from $origin)';
}

class Collision {
  const Collision(this.number, this.claims);
  final String number;
  final List<GateClaim> claims;

  /// Distinct scripts claiming this number.
  Set<String> get scripts => claims.map((c) => c.script).toSet();
}

class Disagreement {
  const Disagreement(this.script, this.claims);

  /// One script whose sources give it DIFFERENT numbers.
  final String script;
  final List<GateClaim> claims;
}

/// A row in the generated index. Only STABLE fields are baked — wiring facts
/// and test references are `--verbose` stdout only, so the pre-commit regen
/// trigger can exactly cover the baked inputs without firing on nearly every
/// commit.
class GateEntry {
  const GateEntry({
    required this.script,
    required this.number,
    required this.purpose,
    required this.ledgerState,
    this.collides = false,
  });

  final String script;
  final String? number;
  final String purpose;
  final String ledgerState;
  final bool collides;
}

String normalizeNewlines(String source) => source.replaceAll('\r\n', '\n');

const int canonicalWindowLines = 10;

final RegExp _canonical = RegExp(r'^// Gate: (\d+[a-z]?)$');

/// The canonical declaration, or null. Only the first [canonicalWindowLines]
/// lines are considered, so a number mentioned deep in a doc comment or in
/// output strings is never mistaken for a declaration.
String? parseCanonicalGateNumber(String source) {
  final lines = normalizeNewlines(source).split('\n');
  final window = lines.length < canonicalWindowLines
      ? lines.length
      : canonicalWindowLines;
  for (var i = 0; i < window; i++) {
    final m = _canonical.firstMatch(lines[i]);
    if (m != null) return m.group(1);
  }
  return null;
}

// Drops a leading "Gate 44 — " / "Gate 40 (audit …):" / "Gate:" so the purpose
// column does not just restate the number column. The number is optional here
// because `// Gate: confirms docs/adr/INDEX.md …` is a real header form.
final RegExp _purposeStrip =
    RegExp(r'^Gate\s*:?\s*(\d+[a-z]?)?\s*(\([^)]*\))?\s*[:—\-–]?\s*');

final RegExp _hasWord = RegExp(r'[A-Za-z0-9]');

/// First substantive comment line in the header window — the one-line purpose.
/// Skips the conventional `// scripts/<name>.dart` self-reference, blank
/// comment lines, and the canonical declaration itself.
///
/// Continues onto the NEXT comment line when the first yields only a fragment
/// (ends in a colon, or is too short to orient anyone) — several real headers
/// put the label on one line and the sentence on the next, and a purpose column
/// reading "Gate (E.13 — Audit 2026-05-16 framework deliverable):" tells the
/// reader nothing about what the gate does.
String extractPurpose(String source, String script) {
  final lines = normalizeNewlines(source).split('\n');
  final window = lines.length < canonicalWindowLines + 6
      ? lines.length
      : canonicalWindowLines + 6;
  final parts = <String>[];

  for (var i = 0; i < window; i++) {
    final line = lines[i].trim();
    if (!line.startsWith('//')) {
      if (parts.isNotEmpty) break; // header block ended
      continue;
    }
    final body = line.substring(2).trim();
    if (body.isEmpty) {
      if (parts.isNotEmpty) break; // blank comment line ends the sentence
      continue;
    }
    if (_canonical.hasMatch(line)) continue;
    if (body == script || body == 'scripts/$script') continue;

    final piece =
        parts.isEmpty ? body.replaceFirst(_purposeStrip, '').trim() : body;
    // Reject a piece with no word character, not merely an EMPTY one. A header
    // like `// Gate (Track 2 of the … batch).` is consumed entirely by
    // _purposeStrip except for the trailing `.`, and a bare isEmpty check
    // accepted that "." as the purpose — then the next blank comment line ended
    // the loop, so the real description one paragraph down never surfaced.
    // Two of 87 rows rendered as a lone "." before this (B-pass P2-1).
    if (!_hasWord.hasMatch(piece)) continue;
    parts.add(piece);

    final soFar = parts.join(' ');
    if (!soFar.endsWith(':') && soFar.length >= 25) break;
  }

  if (parts.isEmpty) return '(no header description)';
  final text = parts.join(' ');
  return text.length > 130 ? '${text.substring(0, 127)}...' : text;
}

final RegExp _buildApkSection = RegExp(r'^### Gate ([\d.]+[a-z]?)\s');
final RegExp _buildApkScript = RegExp(r'scripts/(check_[a-z0-9_]+\.dart)');

/// `### Gate N` sections in `.claude/commands/build-apk.md`, mapped to the
/// first script each one runs. Sections with NO script are procedural steps
/// (today 1, 2, 3, 3.5, 4, 5, 6) and are returned separately as reserved
/// numbers — a script must never mint one of those.
({List<GateClaim> claims, Set<String> reserved}) parseBuildApk(
  String markdown, {
  String origin = '.claude/commands/build-apk.md',
}) {
  final claims = <GateClaim>[];
  final reserved = <String>{};
  String? current;
  var currentHadScript = false;

  void close() {
    final c = current;
    if (c != null && !currentHadScript) reserved.add(c);
  }

  for (final line in normalizeNewlines(markdown).split('\n')) {
    final section = _buildApkSection.firstMatch(line);
    if (section != null) {
      close();
      current = section.group(1);
      currentHadScript = false;
      continue;
    }
    final cur = current;
    if (cur == null || currentHadScript) continue;
    final script = _buildApkScript.firstMatch(line);
    if (script != null) {
      claims.add(GateClaim(
        script: script.group(1)!,
        number: cur,
        source: ClaimSource.buildApk,
        origin: origin,
      ));
      currentHadScript = true;
    }
  }
  close();
  return (claims: claims, reserved: reserved);
}

// BOTH mint orders occur in the ledgers and both must be matched. Forward:
// `scripts/check_no_http_package.dart (Gate 45, hard-fail)`. Reverse:
// `Gate 42 (check_sot_behavioral_test_paths.dart) PASS`. A one-form regex is
// how Gate 45 and Gate 7 stayed invisible through five surveys.
final RegExp _mintForward =
    RegExp(r'`?(?:scripts/)?(check_[a-z0-9_]+\.dart)`?\s*\(Gate (\d+[a-z]?)');
final RegExp _mintReverse =
    RegExp(r'Gate (\d+[a-z]?)\s*\(`?(?:scripts/)?(check_[a-z0-9_]+\.dart)');

/// Gate numbers minted in an audit closure ledger. This is a real assignment
/// surface, not commentary: it is the ONLY claim `check_no_http_package.dart`
/// (45) and `check_writeservice_only.dart` (7) have anywhere in the repo.
List<GateClaim> parseLedgerMints(String text, String origin) {
  final claims = <GateClaim>[];
  final body = normalizeNewlines(text);
  for (final m in _mintForward.allMatches(body)) {
    claims.add(GateClaim(
      script: m.group(1)!,
      number: m.group(2)!,
      source: ClaimSource.ledger,
      origin: origin,
    ));
  }
  for (final m in _mintReverse.allMatches(body)) {
    claims.add(GateClaim(
      script: m.group(2)!,
      number: m.group(1)!,
      source: ClaimSource.ledger,
      origin: origin,
    ));
  }
  return claims;
}

/// Two or more DISTINCT scripts claiming the same number.
List<Collision> findCollisions(List<GateClaim> claims) {
  final byNumber = <String, List<GateClaim>>{};
  for (final c in claims) {
    byNumber.putIfAbsent(c.number, () => []).add(c);
  }
  final out = <Collision>[];
  byNumber.forEach((number, list) {
    if (list.map((c) => c.script).toSet().length > 1) {
      out.add(Collision(number, list));
    }
  });
  out.sort((a, b) => _numericKey(a.number).compareTo(_numericKey(b.number)));
  return out;
}

/// One script whose sources disagree about its number — e.g. a `build-apk.md`
/// section saying 23 while the script's own canonical line says 51.
List<Disagreement> findDisagreements(List<GateClaim> claims) {
  final byScript = <String, List<GateClaim>>{};
  for (final c in claims) {
    byScript.putIfAbsent(c.script, () => []).add(c);
  }
  final out = <Disagreement>[];
  byScript.forEach((script, list) {
    if (list.map((c) => c.number).toSet().length > 1) {
      out.add(Disagreement(script, list));
    }
  });
  out.sort((a, b) => a.script.compareTo(b.script));
  return out;
}

/// A script minting a number reserved for a `/build-apk` procedural step.
/// Compared as STRINGS: `3.5` is reserved and is not an int.
List<GateClaim> findReservedConflicts(
  List<GateClaim> claims,
  Set<String> reserved,
) {
  final out = claims.where((c) => reserved.contains(c.number)).toList();
  out.sort((a, b) => a.script.compareTo(b.script));
  return out;
}

double _numericKey(String number) =>
    double.tryParse(number.replaceAll(RegExp(r'[a-z]'), '')) ?? 0;

/// Lowest integer not claimed and not reserved. Printed on every run so the
/// forward minting rule ("a new gate takes no number; if a /build-apk section
/// needs one it takes the next free") is executable rather than aspirational.
int nextFreeNumber(List<GateClaim> claims, Set<String> reserved) {
  final used = <int>{};
  for (final n in [...claims.map((c) => c.number), ...reserved]) {
    final i = int.tryParse(n.replaceAll(RegExp(r'[a-z.].*'), ''));
    if (i != null) used.add(i);
  }
  var candidate = 1;
  while (used.contains(candidate)) {
    candidate++;
  }
  return candidate;
}
