// scripts/build_gate_index.dart
//
// Generates docs/audit/GATE_INDEX.md — the gate registry. Mirrors
// build_oi_index.dart / build_adr_index.dart / build_bug_index.dart in shape
// and pre-commit wiring. All parsing + collision logic lives in the pure
// gate_index_lib.dart; this file is IO only and decides nothing.
//
// Usage:
//   dart run scripts/build_gate_index.dart            # write + hard-fail
//   dart run scripts/build_gate_index.dart --warn-only # write + always exit 0
//   dart run scripts/build_gate_index.dart --verbose   # + wiring/test columns
//
// --warn-only EXISTS FOR EXACTLY ONE COMMIT and is covered by its own test so
// it cannot quietly become permanent. At the commit that introduces this
// registry all 5 pre-existing collisions are still live, so hard-fail 1 would
// exit 1 — and every pre-commit regen block is `if ! dart run …; then exit 1`,
// which means the introducing commit's own hook would block the introducing
// commit, and the baseline the collision-clearing commit is checked against
// could never be produced. In --warn-only the index is still WRITTEN with every
// collision marked; only the exit code is suppressed.
//
// BAKED vs --verbose: the index bakes only stable columns (number, script,
// purpose, ledger state). Wiring facts and test references are printed to
// stdout instead. Baking them would force the pre-commit regen trigger to cover
// scripts/** + test/** + test.yml — nearly every commit — or the index silently
// goes stale while check_gate_index_fresh.dart (which runs on EVERY commit via
// the check_*.dart loop) blocks it, leaving an unstaged modified file behind
// (check_adr_index_fresh.dart:20-36 rebuilds in place and never restores).

import 'dart:io';

import 'gate_index_lib.dart';

const _indexPath = 'docs/audit/GATE_INDEX.md';
const _buildApkPath = '.claude/commands/build-apk.md';
const _ledgerPath = 'docs/audit/gate_test_ledger.yaml';

// Numbered gates that are NOT check_*.dart, so the glob cannot see them. A
// check_*-only input set is how Gate 40 stayed invisible.
const _extraGateScripts = <String>['validate_audit_closure.dart'];

/// Historical numbers that moved. Keyed on the OLD number so a grep of the
/// historical corpus resolves forward. For a number that COLLIDED before the
/// move, this can only enumerate candidates — a pre-2026-08-10 citation of
/// "Gate 18" is ambiguous by construction, and no table can retroactively
/// disambiguate the prose that created the ambiguity.
const _historicalAliases = <String, String>{
  '7': 'kept by check_sot_registry_completeness.dart. '
      'check_writeservice_only.dart also claimed 7 (closure ledger) → now 49.',
  '18': 'kept by check_doc_internal_consistency.dart. Also claimed by '
      'check_reader_manifest_complete.dart → 50 and '
      'check_app_version_matches_pubspec.dart → 51.',
  '19': 'kept by check_hive_map_field_drift.dart (owns '
      'backups/gate19_drift_baseline.txt). check_schema_payload_parity.dart → 52.',
  '23': 'kept by check_secrets_gitignored.dart. '
      'check_nlog_key_canonical.dart (build-apk.md section) → 53.',
  '44': 'kept by check_nested_claude_md_content.dart. '
      'check_device_tests_exist.dart → 54. NOTE: "the Gate-44 lesson" in '
      'CLAUDE.md and diagnose d7b3e9 names the LESSON, not either script — no '
      'test for either claimant exists in the tree. That prose is deliberately '
      'left alone.',
};

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final verbose = args.contains('--verbose');

  final scriptsDir = Directory('scripts');
  if (!scriptsDir.existsSync()) {
    stderr.writeln('[gate-index] FAIL: scripts/ not found. Run from repo root.');
    exit(1);
  }

  // ── sources 1 + 2: the gate scripts themselves ──────────────────────────
  final gateFiles = <String, File>{};
  for (final f in scriptsDir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (name.startsWith('check_') && name.endsWith('.dart')) {
      gateFiles[name] = f;
    }
  }
  for (final name in _extraGateScripts) {
    final f = File('scripts/$name');
    if (f.existsSync()) gateFiles[name] = f;
  }

  final claims = <GateClaim>[];
  final purposes = <String, String>{};
  for (final entry in gateFiles.entries) {
    final src = entry.value.readAsStringSync();
    purposes[entry.key] = extractPurpose(src, entry.key);
    final number = parseCanonicalGateNumber(src);
    if (number != null) {
      claims.add(GateClaim(
        script: entry.key,
        number: number,
        source: ClaimSource.header,
        origin: 'scripts/${entry.key}',
      ));
    }
  }

  // ── source 3: build-apk.md sections ─────────────────────────────────────
  var reserved = <String>{};
  final buildApk = File(_buildApkPath);
  if (buildApk.existsSync()) {
    final parsed = parseBuildApk(buildApk.readAsStringSync());
    claims.addAll(parsed.claims);
    reserved = parsed.reserved;
  }

  // ── source 4: closure ledgers ───────────────────────────────────────────
  // BOTH filename conventions. `*_closures.yaml` matches 6 files;
  // `*.closure.yaml` matches 18 more. validate_audit_closure.dart:79-83 already
  // reads both — a glob covering only the first excludes three quarters of the
  // ledgers, including this batch's own closure file.
  final auditDir = Directory('docs/audit');
  if (auditDir.existsSync()) {
    for (final f in auditDir.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      final isLedger = name.endsWith('_closures.yaml') ||
          name.endsWith('.closure.yaml') ||
          name == 'closed_issues.md';
      if (!isLedger) continue;
      claims.addAll(parseLedgerMints(f.readAsStringSync(), 'docs/audit/$name'));
    }
  }

  // ── verdicts ────────────────────────────────────────────────────────────
  final collisions = findCollisions(claims);
  final disagreements = findDisagreements(claims);
  final reservedConflicts = findReservedConflicts(claims, reserved);

  // Hard-fail 4: a file under scripts/ carrying a CANONICAL declaration but
  // absent from the index. NOT circular — the scan is over all of scripts/,
  // while the index is built from check_* + _extraGateScripts. Keyed on the
  // canonical form specifically: a looser `gate\s*:?\s*\d` over the header
  // window matches 5 non-gate files, four of which are pure libs whose headers
  // explicitly say they are not gates, and the builder would exit 1 forever.
  final unregistered = <String>[];
  for (final f in scriptsDir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (!name.endsWith('.dart') || gateFiles.containsKey(name)) continue;
    if (parseCanonicalGateNumber(f.readAsStringSync()) != null) {
      unregistered.add(name);
    }
  }

  // ── ledger state (populated by the commit that adds the ledger) ──────────
  final ledgerStates = <String, String>{};
  final ledger = File(_ledgerPath);
  if (ledger.existsSync()) {
    String? current;
    for (final raw in ledger.readAsLinesSync()) {
      final line = raw.trimRight();
      if (line.isEmpty || line.trimLeft().startsWith('#')) continue;
      if (!line.startsWith(' ') && line.endsWith(':')) {
        current = line.substring(0, line.length - 1).trim();
        continue;
      }
      if (current == null) continue;
      final t = line.trim();
      for (final key in ['mutation_proven', 'grandfathered', 'test_exempt']) {
        if (t.startsWith('$key:')) ledgerStates[current] = key;
      }
    }
  }

  // ── render ──────────────────────────────────────────────────────────────
  final numberByScript = <String, String>{};
  for (final c in claims) {
    numberByScript.putIfAbsent(c.script, () => c.number);
  }
  final collidedNumbers = collisions.map((c) => c.number).toSet();

  final names = gateFiles.keys.toList()..sort();
  final buf = StringBuffer()
    ..writeln('# Gate index')
    ..writeln()
    ..writeln('> **GENERATED — do not edit by hand.** '
        'Run `dart run scripts/build_gate_index.dart`.')
    ..writeln('> Regenerated automatically by `scripts/pre-commit.sh` when a '
        'baked input changes.')
    ..writeln()
    ..writeln('The registry keys on the **script filename** — that is the real, '
        'already-unique identity that every')
    ..writeln('wiring surface uses. A gate **number is an optional alias**: '
        'most gates have none and do not need one.')
    ..writeln()
    ..writeln('**Forward minting rule.** A new gate takes NO number. If a '
        '`/build-apk` section needs one, it takes')
    ..writeln('the next free number: **${nextFreeNumber(claims, reserved)}**. '
        'Declare it canonically as `// Gate: N` on its')
    ..writeln('own line in the first $canonicalWindowLines lines — that exact '
        'form is the only one this generator reads.')
    ..writeln()
    ..writeln('Total gates: **${names.length}** '
        '(${numberByScript.length} numbered, '
        '${names.length - numberByScript.length} by filename only).')
    ..writeln()
    ..writeln('| Gate | Script | Purpose | Test ledger |')
    ..writeln('|---|---|---|---|');

  for (final name in names) {
    final n = numberByScript[name];
    final mark = (n != null && collidedNumbers.contains(n)) ? ' ⚠ COLLISION' : '';
    final label = n == null ? '—' : '$n$mark';
    final purpose = (purposes[name] ?? '').replaceAll('|', r'\|');
    buf.writeln('| $label | `$name` | $purpose | ${ledgerStates[name] ?? '—'} |');
  }

  buf
    ..writeln()
    ..writeln('## Reserved')
    ..writeln()
    ..writeln('`/build-apk` procedural steps with no script — a gate must never '
        'mint one of these:')
    ..writeln()
    ..writeln((reserved.toList()..sort()).map((r) => '`$r`').join(', '))
    ..writeln()
    ..writeln('## Historical aliases')
    ..writeln()
    ..writeln('Diagnose-docs, `closed_issues.md`, closure ledgers, '
        '`docs/reviews/` and `docs/plan-reviews/` record what was')
    ..writeln('true when written and are never rewritten. Use this table to '
        'resolve an old number found there.')
    ..writeln();
  final aliasKeys = _historicalAliases.keys.toList()
    ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
  for (final k in aliasKeys) {
    buf.writeln('- **Gate $k** — ${_historicalAliases[k]}');
  }

  File(_indexPath).writeAsStringSync(buf.toString());

  // ── report ──────────────────────────────────────────────────────────────
  if (verbose) {
    stdout.writeln('[gate-index] --verbose: wiring + test references');
    final testRefs = _testReferences(names);
    for (final name in names) {
      stdout.writeln('  $name  tests=${testRefs[name] ?? 0}');
    }
  }

  final problems = <String>[];
  for (final c in collisions) {
    problems.add('Gate ${c.number} claimed by ${c.scripts.length} scripts:\n'
        '${c.claims.map((x) => '      - $x').join('\n')}');
  }
  for (final d in disagreements) {
    problems.add('${d.script} is given DIFFERENT numbers by its sources:\n'
        '${d.claims.map((x) => '      - $x').join('\n')}');
  }
  for (final r in reservedConflicts) {
    problems.add('$r mints Gate ${r.number}, reserved for a /build-apk '
        'procedural step.');
  }
  for (final u in unregistered) {
    problems.add('scripts/$u carries a canonical `// Gate:` declaration but is '
        'not in the index. Add it to _extraGateScripts in '
        'build_gate_index.dart, or remove the declaration.');
  }

  if (problems.isEmpty) {
    stdout.writeln('[gate-index] PASS — ${names.length} gates, '
        '${numberByScript.length} numbered, no collisions. '
        'Next free number: ${nextFreeNumber(claims, reserved)}.');
    exit(0);
  }

  final sink = warnOnly ? stdout : stderr;
  sink.writeln('[gate-index] ${problems.length} problem(s):');
  for (final p in problems) {
    sink.writeln('  - $p');
  }
  if (warnOnly) {
    stdout.writeln('[gate-index] --warn-only: index WRITTEN with collisions '
        'marked; exiting 0. This flag is for the introducing commit only.');
    exit(0);
  }
  exit(1);
}

Map<String, int> _testReferences(List<String> gateNames) {
  final counts = <String, int>{};
  final testDir = Directory('test');
  if (!testDir.existsSync()) return counts;
  final blob = StringBuffer();
  for (final f in testDir.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    try {
      blob.writeln(f.readAsStringSync());
    } on FileSystemException {
      stderr.writeln('[gate-index] WARN unreadable: ${f.path}');
    }
  }
  final text = blob.toString();
  for (final name in gateNames) {
    // String implements Pattern, so allMatches is the native String method.
    final base = name.replaceAll('.dart', '');
    counts[name] = base.allMatches(text).length;
  }
  return counts;
}
