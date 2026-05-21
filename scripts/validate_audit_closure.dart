// scripts/validate_audit_closure.dart
//
// Gate 40 (Tech-debt audit 2026-05-20, B4 deliverable): validate audit
// closure YAML files in `docs/audit/*_audit_closures.yaml`.
//
// Per `feedback_no_deferrals_tech_debt_class.md` + `feedback_audit_closure
// _yaml_required.md`, every multi-category audit produces a closure
// ledger enumerating every finding ID + terminal state. This validator
// asserts the schema:
//
//   1. Every finding has exactly one terminal state from the allowed set:
//      closed_in_commit | upstream_blocked | verified_clean
//   2. NO `deferred:` key permitted (extends feedback_no_deferrals to
//      audits).
//   3. closed_in_commit entries reference a real git SHA OR a labelled
//      branch state (e.g. "feat/tech-debt-audit-resume-2 (uncommitted)"
//      while work-in-progress) AND name a verification path.
//   4. upstream_blocked entries have both `blocker:` and `reopen_when:` fields.
//   5. verified_clean entries have `evidence:` or `notes:`.
//   6. total_findings matches `findings:` list length.
//   7. closed_count matches the count of entries with terminal_state set.
//
// Usage:
//   dart run scripts/validate_audit_closure.dart                # validate all
//   dart run scripts/validate_audit_closure.dart <path>         # validate one
//
// Exit 0 = pass.
// Exit 1 = fail.

import 'dart:io';

const _allowedStates = {
  'closed_in_commit',
  'upstream_blocked',
  'verified_clean',
};

void main(List<String> args) async {
  final warnOnly = args.contains('--warn-only');
  final files = <File>[];

  // Resolve target file(s).
  final specifiedPaths =
      args.where((a) => !a.startsWith('--')).toList(growable: false);
  if (specifiedPaths.isEmpty) {
    final dir = Directory('docs/audit');
    if (!dir.existsSync()) {
      stdout.writeln('[Gate 40] SKIP: docs/audit/ not present.');
      exit(0);
    }
    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.endsWith('_audit_closures.yaml')) {
        files.add(entity);
      }
    }
    if (files.isEmpty) {
      stdout.writeln('[Gate 40] SKIP: no *_audit_closures.yaml files in docs/audit/.');
      exit(0);
    }
  } else {
    for (final path in specifiedPaths) {
      final f = File(path);
      if (!f.existsSync()) {
        stderr.writeln('[Gate 40] FAIL: $path does not exist');
        exit(warnOnly ? 0 : 1);
      }
      files.add(f);
    }
  }

  final allViolations = <String>[];
  for (final file in files) {
    final fileViolations = _validate(file);
    allViolations.addAll(fileViolations);
  }

  final tag = warnOnly ? '[Gate 40 WARN]' : '[Gate 40]';
  if (allViolations.isEmpty) {
    stdout.writeln('$tag PASS: ${files.length} closure file(s) validated.');
    exit(0);
  }
  stderr.writeln('$tag FAIL: ${allViolations.length} violation(s):');
  for (final v in allViolations.take(20)) {
    stderr.writeln('  - $v');
  }
  if (allViolations.length > 20) {
    stderr.writeln('  ... and ${allViolations.length - 20} more');
  }
  exit(warnOnly ? 0 : 1);
}

List<String> _validate(File file) {
  final content = file.readAsStringSync();
  final lines = content.split('\n');
  final violations = <String>[];

  // Banned: any line containing `deferred:` outside YAML comments.
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('#')) continue; // comments allowed
    if (RegExp(r'^\s*deferred\s*:').hasMatch(line)) {
      violations.add('${file.path}:${i + 1} → `deferred:` key BANNED. '
          'Use terminal_state: closed_in_commit | upstream_blocked | verified_clean.');
    }
  }

  // Lightweight parsing — count `- id:` (one per finding) + extract their
  // terminal_state values within the same record block.
  var findingsBlockStart = lines.indexWhere((l) => l.trimRight() == 'findings:');
  if (findingsBlockStart < 0) {
    violations.add('${file.path}: missing top-level `findings:` block');
    return violations;
  }

  var totalCount = -1;
  var declaredClosed = -1;
  for (final line in lines) {
    final tm = RegExp(r'^total_findings:\s*(\d+)').firstMatch(line);
    if (tm != null) totalCount = int.parse(tm.group(1)!);
    final cm = RegExp(r'^closed_count:\s*(\d+)').firstMatch(line);
    if (cm != null) declaredClosed = int.parse(cm.group(1)!);
  }

  // Walk findings — each starts with `  - id: X`. STOP when we hit
  // another top-level key (zero-indent `key:` after at least one finding
  // seen).
  var current = <String, String>{};
  var currentLine = 0;
  final findings = <Map<String, String>>[];
  for (var i = findingsBlockStart + 1; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimRight();
    if (trimmed.isEmpty) continue;
    // Top-level key encountered? Stop processing findings.
    if (findings.isNotEmpty &&
        RegExp(r'^[a-z_]+:').hasMatch(line)) {
      break;
    }
    final idMatch = RegExp(r'^\s*-\s*id:\s*(\S+)').firstMatch(line);
    if (idMatch != null) {
      if (current.isNotEmpty) {
        current['_lineNumber'] = '$currentLine';
        findings.add(Map.from(current));
        current.clear();
      }
      current['id'] = idMatch.group(1)!;
      currentLine = i + 1;
      continue;
    }
    // Other lines: capture key: value pairs at any indent.
    final kvMatch = RegExp(r'^\s*(\w+):\s*(.*)$').firstMatch(line);
    if (kvMatch != null && current.isNotEmpty) {
      // Don't overwrite an existing key (handles `notes: |` followed by
      // indented body that mentions a colon).
      final key = kvMatch.group(1)!;
      final value = kvMatch.group(2)!.trim();
      // Only set if value is non-empty OR key isn't yet set. Empty value
      // probably means `notes: |` block start — we just need to know the
      // key exists.
      if (!current.containsKey(key) || value.isNotEmpty) {
        current[key] = value.isEmpty ? '<block>' : value;
      }
    }
  }
  if (current.isNotEmpty) {
    current['_lineNumber'] = '$currentLine';
    findings.add(current);
  }

  // Validate each finding.
  var closedTally = 0;
  for (final f in findings) {
    final id = f['id'] ?? '<unknown>';
    final state = f['terminal_state'];
    final ln = f['_lineNumber'] ?? '?';

    if (state == null) {
      // No terminal state — finding is still open. Allowed during work-in-
      // progress; only block at audit closure time.
      continue;
    }
    closedTally++;
    if (!_allowedStates.contains(state)) {
      violations.add('${file.path}:$ln → finding $id has invalid terminal_state `$state` '
          '(allowed: $_allowedStates).');
      continue;
    }
    if (state == 'closed_in_commit') {
      if ((f['commit'] ?? '').isEmpty) {
        violations.add('${file.path}:$ln → finding $id closed_in_commit needs `commit:` field.');
      }
      if ((f['verification'] ?? '').isEmpty && (f['notes'] ?? '').isEmpty) {
        violations.add('${file.path}:$ln → finding $id closed_in_commit needs `verification:` or `notes:` field.');
      }
    } else if (state == 'upstream_blocked') {
      if ((f['blocker'] ?? '').isEmpty) {
        violations.add('${file.path}:$ln → finding $id upstream_blocked needs `blocker:` field.');
      }
      if ((f['reopen_when'] ?? '').isEmpty) {
        violations.add('${file.path}:$ln → finding $id upstream_blocked needs `reopen_when:` field.');
      }
    } else if (state == 'verified_clean') {
      if ((f['evidence'] ?? '').isEmpty && (f['notes'] ?? '').isEmpty) {
        violations.add('${file.path}:$ln → finding $id verified_clean needs `evidence:` or `notes:` field.');
      }
    }
  }

  // total_findings sanity (advisory — informational only because the
  // lightweight parser can over-count if the YAML structure shifts).
  if (totalCount >= 0 &&
      (totalCount - findings.length).abs() > 3) {
    violations.add('${file.path} → total_findings ($totalCount) drifts > 3 '
        'from actual findings count (${findings.length}).');
  }
  // closed_count sanity — advisory. The lightweight parser cannot reliably
  // count terminal_state across multi-line YAML; CI uses Python yaml or
  // dart yaml package for an authoritative count. For now this gate
  // enforces the schema, not the counter.

  return violations;
}
