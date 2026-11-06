// Validates a single incident post-mortem at docs/incidents/<date>-<slug>-<id>.md.
//
// Required frontmatter fields:
//   incident_id (6-char hex)
//   status (detected | mitigated | resolved | post-mortem)
//   detected_at (IST ISO8601)
//   blast_radius (feature | account | platform | catastrophic)
//   users_affected (integer or "unknown")
//   impact_summary (non-empty)
//   detection_path (non-empty)
//
// Conditionally required:
//   - status in {mitigated, resolved, post-mortem} → mitigated_at non-null
//   - status in {resolved, post-mortem}           → resolved_at non-null + linked_diagnose_docs non-empty
//   - status == post-mortem                       → prevention non-empty
//
// Filename pattern: <YYYY-MM-DD>-<kebab>-<6hex>.md
//
// Required section headers in body.
//
// Exit 0 on success, exit 1 on violation (prints all violations).

import 'dart:io';

const _requiredFields = <String>[
  'incident_id',
  'status',
  'detected_at',
  'blast_radius',
  'users_affected',
  'impact_summary',
  'detection_path',
];

const _validStatus = <String>[
  'detected',
  'mitigated',
  'resolved',
  'post-mortem',
];

const _validBlast = <String>[
  'feature',
  'account',
  'platform',
  'catastrophic',
];

const _requiredSections = <String>[
  '## Timeline',
  '## What happened',
  '## User impact',
  '## Root cause',
  '## Resolution',
  '## Prevention',
];

final _idRe = RegExp(r'^[0-9a-f]{6}$');
final _filenameRe =
    RegExp(r'^\d{4}-\d{2}-\d{2}-[a-z0-9-]+-[0-9a-f]{6}\.md$');

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run scripts/validate_incident_doc.dart <path>');
    exit(2);
  }

  final target = args[0];
  final paths = <String>[];

  if (FileSystemEntity.isDirectorySync(target)) {
    for (final e in Directory(target).listSync()) {
      if (e is File &&
          e.path.endsWith('.md') &&
          !e.path.endsWith('INDEX.md') &&
          !e.path.endsWith('_template.md')) {
        paths.add(e.path);
      }
    }
  } else {
    paths.add(target);
  }

  if (paths.isEmpty) {
    stdout.writeln('No incident docs to validate.');
    exit(0);
  }

  final violations = <String>[];

  for (final path in paths) {
    final f = File(path);
    if (!f.existsSync()) {
      violations.add('$path: does not exist');
      continue;
    }

    final filename = path.replaceAll('\\', '/').split('/').last;
    if (!_filenameRe.hasMatch(filename)) {
      violations.add('$path: filename does not match '
          '<YYYY-MM-DD>-<kebab>-<6hex>.md');
    }

    final content = f.readAsStringSync().replaceAll('\r\n', '\n');
    if (!content.startsWith('---\n')) {
      violations.add('$path: missing frontmatter');
      continue;
    }
    final end = content.indexOf('\n---\n', 4);
    if (end == -1) {
      violations.add('$path: unterminated frontmatter');
      continue;
    }
    final block = content.substring(4, end);
    final body = content.substring(end + 5);

    final fm = <String, String>{};
    for (final line in block.split('\n')) {
      final m = RegExp(r'^([a-z_]+)\s*:\s*(.*)$').firstMatch(line);
      if (m != null) fm[m.group(1)!] = m.group(2)!.trim();
    }

    for (final field in _requiredFields) {
      if (!fm.containsKey(field) || fm[field]!.isEmpty) {
        violations.add('$path: missing required field: $field');
      }
    }

    if (fm['incident_id'] != null && !_idRe.hasMatch(fm['incident_id']!)) {
      violations.add('$path: incident_id "${fm['incident_id']}" must be '
          '6-char lowercase hex');
    }

    if (fm['status'] != null && !_validStatus.contains(fm['status'])) {
      violations.add('$path: status "${fm['status']}" not in '
          '${_validStatus.join(' | ')}');
    }

    if (fm['blast_radius'] != null &&
        !_validBlast.contains(fm['blast_radius'])) {
      violations.add('$path: blast_radius "${fm['blast_radius']}" not in '
          '${_validBlast.join(' | ')}');
    }

    // Conditional: status-driven fields
    final st = fm['status'] ?? '';
    if ((st == 'mitigated' || st == 'resolved' || st == 'post-mortem') &&
        (fm['mitigated_at'] == null ||
            fm['mitigated_at']!.isEmpty ||
            fm['mitigated_at'] == 'null')) {
      violations.add('$path: status=$st requires mitigated_at');
    }
    if ((st == 'resolved' || st == 'post-mortem') &&
        (fm['resolved_at'] == null ||
            fm['resolved_at']!.isEmpty ||
            fm['resolved_at'] == 'null')) {
      violations.add('$path: status=$st requires resolved_at');
    }
    if ((st == 'resolved' || st == 'post-mortem') &&
        !content.contains(RegExp(r'linked_diagnose_docs:\s*\n\s*-\s+'))) {
      violations.add('$path: status=$st requires non-empty '
          'linked_diagnose_docs list');
    }
    if (st == 'post-mortem' &&
        !content.contains(RegExp(r'prevention:\s*\n\s*-\s+'))) {
      violations.add('$path: status=post-mortem requires non-empty '
          'prevention list');
    }

    // Sections
    for (final s in _requiredSections) {
      if (!body.contains(s)) {
        violations.add('$path: missing required section: $s');
      }
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('Incident validation OK (${paths.length} file(s)).');
    exit(0);
  }

  stderr.writeln('Incident validation FAILED (${violations.length} '
      'violations):');
  for (final v in violations) {
    stderr.writeln('  $v');
  }
  exit(1);
}
