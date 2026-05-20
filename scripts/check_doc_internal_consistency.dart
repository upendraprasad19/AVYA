// scripts/check_doc_internal_consistency.dart
//
// Gate 18: known-drift pairs across CLAUDE.md + AGENTS.md must agree.
//
// Closes OI-35 (audit-2026-05-17 Hermes F10). CLAUDE.md §2 claimed
// "21 tables" while §7 header said "46 Tables" — internal drift that
// would silently mislead any agent reading §2 first. AGENTS.md
// mirrored the §2 stale figure.
//
// **Drift pair scheme:** each pair is `(label, locations)` where
// locations is a list of `(file, regex)`. The regex must extract a
// SINGLE numeric / string capture from each location. The gate fails
// if the captures disagree.
//
// **Add a new pair** when CLAUDE.md cites a number/count in multiple
// places that should match. Examples currently covered:
//   - Database table count
//   - Hive box compaction count
//
// Usage:
//   dart run scripts/check_doc_internal_consistency.dart
//
// Exit codes:
//   0 — every pair agrees
//   1 — at least one pair drifted (details on stderr)

import 'dart:io';

class DriftLocation {
  final String file;
  final RegExp pattern;
  final String label;
  DriftLocation(this.file, this.pattern, this.label);
}

class DriftPair {
  final String name;
  final List<DriftLocation> locations;
  DriftPair(this.name, this.locations);
}

// NOTE (audit 2026-05-20 B1): Pinned-pattern set updated after Milestone-6
// CLAUDE.md decluttering + AGENTS.md deprecation. The original patterns
// targeted CLAUDE.md §7 "DATABASE SCHEMA (N Tables)" header + AGENTS.md
// tech stack table — both surfaces no longer exist (§7 is now "WHERE TO
// FIND DETAILED RULES"; AGENTS.md is an 11-line deprecation banner).
//
// Reduced to one canonical surface: CLAUDE.md §2 Tech Stack table.
// `hive_compaction_box_count` removed entirely — the §19 Hive bloat row
// was relocated in the same decluttering and no longer has a single
// canonical pin. Re-add it if a new canonical surface emerges.
final _pairs = <DriftPair>[
  DriftPair(
    'database_table_count',
    [
      DriftLocation(
        'CLAUDE.md',
        RegExp(r'\| Database \| Supabase Postgres \((\d+) tables'),
        'CLAUDE.md §2 Tech Stack',
      ),
    ],
  ),
];

void main(List<String> args) {
  final failures = <String>[];

  for (final pair in _pairs) {
    final captures = <String, String>{}; // location label → captured value
    for (final loc in pair.locations) {
      final file = File(loc.file);
      if (!file.existsSync()) {
        failures.add(
            '[$pair.name] FAIL — referenced file does not exist: ${loc.file}');
        continue;
      }
      final src = file.readAsStringSync();
      final match = loc.pattern.firstMatch(src);
      if (match == null) {
        failures.add(
            '[${pair.name}] FAIL — pattern did not match in ${loc.label}: ${loc.pattern.pattern}');
        continue;
      }
      captures[loc.label] = match.group(1)!;
    }

    final uniqueValues = captures.values.toSet();
    if (uniqueValues.length > 1) {
      failures.add(
          '[${pair.name}] FAIL — drift detected: ' +
              captures.entries.map((e) => '${e.key}="${e.value}"').join(', '));
    } else if (uniqueValues.length == 1 && captures.length > 1) {
      stdout.writeln(
          '[Gate 18] PASS — ${pair.name}: all ${captures.length} locations agree on "${uniqueValues.first}"');
    } else if (captures.length == 1) {
      // Single-location pair (advisory presence check).
      stdout.writeln(
          '[Gate 18] PASS — ${pair.name}: only 1 location pinned, value="${captures.values.first}"');
    }
  }

  if (failures.isEmpty) {
    stdout.writeln('[Gate 18] PASS — all ${_pairs.length} drift pairs agree.');
    exit(0);
  } else {
    stderr.writeln('[Gate 18] ${failures.length} drift failure(s):');
    for (final f in failures) {
      stderr.writeln('  $f');
    }
    exit(1);
  }
}
