// Validates a single ADR file at docs/adr/NNNN-*.md.
//
// Usage:
//   dart run scripts/validate_adr.dart docs/adr/0001-hive-first-storage.md
//   dart run scripts/validate_adr.dart docs/adr/   # validate all
//
// Checks:
// - Frontmatter present + parses as YAML-like header
// - Required fields: adr_id, title, status, date, deciders
// - status ∈ {proposed, accepted, superseded by NNNN, deprecated}
// - adr_id is a 4-digit zero-padded integer matching the filename prefix
// - Filename matches `NNNN-<kebab>.md`
// - Has required section headers: Context, Decision, Alternatives considered,
//   Consequences, Status
// - "superseded by NNNN" target ADR file exists
// - Numbering is monotonic across the whole adr/ dir (no gaps, no duplicates)
//
// Exit 0 on success, exit 1 on first violation (prints all violations first).

import 'dart:io';

const _requiredFields = <String>[
  'adr_id',
  'title',
  'status',
  'date',
  'deciders',
];

const _requiredSections = <String>[
  '## Context',
  '## Decision',
  '## Alternatives considered',
  '## Consequences',
  '## Status',
];

final _statusEnum = RegExp(
  r'^(proposed|accepted|superseded by \d{4}|deprecated)$',
);

final _filenameRe = RegExp(r'^(\d{4})-[a-z0-9-]+\.md$');

class Violation {
  final String path;
  final String message;
  Violation(this.path, this.message);
  @override
  String toString() => '$path: $message';
}

void main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run scripts/validate_adr.dart <path>');
    exit(2);
  }

  final target = args[0];
  final paths = <String>[];

  if (FileSystemEntity.isDirectorySync(target)) {
    final dir = Directory(target);
    for (final e in dir.listSync()) {
      if (e is File &&
          e.path.endsWith('.md') &&
          !e.path.endsWith('INDEX.md') &&
          !e.path.endsWith('README.md')) {
        paths.add(e.path);
      }
    }
    paths.sort();
  } else {
    paths.add(target);
  }

  final violations = <Violation>[];
  final seenIds = <int, String>{};

  for (final path in paths) {
    final f = File(path);
    if (!f.existsSync()) {
      violations.add(Violation(path, 'file does not exist'));
      continue;
    }

    // Normalize CRLF → LF so Windows-saved files parse identically to LF.
    final content = f.readAsStringSync().replaceAll('\r\n', '\n');
    // Normalize path separators (Windows uses \ but CLI may pass /).
    final normalized = path.replaceAll('\\', '/');
    final filename = normalized.split('/').last;
    final fnMatch = _filenameRe.firstMatch(filename);
    if (fnMatch == null) {
      violations.add(Violation(path,
          'filename does not match NNNN-<kebab>.md pattern'));
      continue;
    }
    final fileIdStr = fnMatch.group(1)!;
    final fileId = int.parse(fileIdStr);

    // Parse frontmatter
    if (!content.startsWith('---\n')) {
      violations.add(Violation(path, 'missing frontmatter delimiter'));
      continue;
    }
    final endIdx = content.indexOf('\n---\n', 4);
    if (endIdx == -1) {
      violations.add(Violation(path, 'unterminated frontmatter'));
      continue;
    }
    final frontmatter = content.substring(4, endIdx);
    final body = content.substring(endIdx + 5);

    final fm = <String, String>{};
    for (final line in frontmatter.split('\n')) {
      final m = RegExp(r'^([a-z_]+)\s*:\s*(.+)$').firstMatch(line);
      if (m != null) {
        fm[m.group(1)!] = m.group(2)!.trim();
      }
    }

    for (final field in _requiredFields) {
      if (!fm.containsKey(field) || fm[field]!.isEmpty) {
        violations.add(Violation(path, 'missing required field: $field'));
      }
    }

    // adr_id matches filename
    if (fm.containsKey('adr_id')) {
      final fmId = int.tryParse(fm['adr_id']!.padLeft(4, '0'));
      if (fmId == null) {
        violations.add(Violation(path, 'adr_id is not an integer'));
      } else if (fmId != fileId) {
        violations.add(Violation(path,
            'adr_id ($fmId) does not match filename ($fileId)'));
      } else {
        if (seenIds.containsKey(fmId)) {
          violations.add(Violation(path,
              'duplicate adr_id $fmId (also in ${seenIds[fmId]})'));
        } else {
          seenIds[fmId] = path;
        }
      }
    }

    // status enum
    if (fm.containsKey('status')) {
      if (!_statusEnum.hasMatch(fm['status']!)) {
        violations.add(Violation(path,
            'status "${fm['status']}" not in enum {proposed, accepted, superseded by NNNN, deprecated}'));
      }
      // "superseded by NNNN" target existence is checked in the cross-file
      // pass below, after all ADRs in the dir have been collected.
    }

    // sections
    for (final section in _requiredSections) {
      if (!body.contains(section)) {
        violations.add(Violation(path, 'missing required section: $section'));
      }
    }
  }

  // Cross-file: numbering monotonic from 0001
  if (paths.length > 1) {
    final ids = seenIds.keys.toList()..sort();
    for (var i = 0; i < ids.length; i++) {
      final expected = i + 1;
      if (ids[i] != expected) {
        violations.add(Violation(seenIds[ids[i]]!,
            'numbering gap: expected ADR-$expected, got ADR-${ids[i]}'));
        break;
      }
    }
  }

  // Cross-file: superseded targets exist
  for (final path in paths) {
    final content =
        File(path).readAsStringSync().replaceAll('\r\n', '\n');
    final m = RegExp(r'^status:\s*superseded by (\d{4})$', multiLine: true)
        .firstMatch(content);
    if (m != null) {
      final supId = int.parse(m.group(1)!);
      if (!seenIds.containsKey(supId)) {
        violations.add(Violation(path,
            'superseded by ADR-$supId but no such ADR file exists'));
      }
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('ADR validation OK (${paths.length} file(s) checked).');
    exit(0);
  }

  stderr.writeln('ADR validation FAILED (${violations.length} violations):');
  for (final v in violations) {
    stderr.writeln('  $v');
  }
  exit(1);
}
