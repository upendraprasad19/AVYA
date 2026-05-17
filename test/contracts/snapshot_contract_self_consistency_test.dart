import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Self-consistency test for `docs/snapshot_contract.yaml` — the manifest
/// of every key emitted by `AiCoachRepository.buildAiContext()` and every
/// Edge Function reader.
///
/// This test pins:
///   (a) every entry has at least one of: `readers: [<non-empty>]`,
///       `prompt_passthrough: true`, or `intentionally_orphan: true`
///   (b) every cited file:line resolves (writer + readers)
///   (c) the writer file is the canonical AiCoachRepository
///   (d) the documented summary stats roughly match the body
///
/// This is the prerequisite for OI-03 (the gate that enforces the
/// manifest against live source). If this test fails, the manifest is
/// internally inconsistent and the OI-03 gate cannot trust it.
void main() {
  late String manifest;

  setUpAll(() {
    final f = File('docs/snapshot_contract.yaml');
    expect(f.existsSync(), isTrue,
        reason: 'docs/snapshot_contract.yaml must exist (OI-07 closure)');
    manifest = f.readAsStringSync().replaceAll('\r\n', '\n');
  });

  group('snapshot_contract.yaml self-consistency', () {
    test('writer block points at AiCoachRepository.buildAiContext', () {
      expect(
        manifest.contains(
            'file: lib/features/ai_coach/repositories/ai_coach_repository.dart'),
        isTrue,
        reason: 'writer file must be ai_coach_repository.dart',
      );
      expect(manifest.contains('method: buildAiContext'), isTrue);
    });

    test('every keys: entry has reader-coverage signal', () {
      // Split into per-key blocks. Each block must contain at least one of:
      //   readers: [<non-empty list with at least one map>]
      //   prompt_passthrough: true
      //   intentionally_orphan: true
      final keysSection = _extractSection(manifest, 'keys:');
      expect(keysSection, isNotNull,
          reason: 'manifest must contain a `keys:` section');

      final entries = _splitEntries(keysSection!);
      expect(entries.length, greaterThan(20),
          reason: 'manifest should enumerate >20 keys (writer has ~48)');

      final offenders = <String>[];
      for (final entry in entries) {
        final keyMatch =
            RegExp(r'-\s*key:\s*([a-z_][a-z_0-9]*)').firstMatch(entry);
        if (keyMatch == null) continue;
        final keyName = keyMatch.group(1)!;

        final hasReaders = RegExp(r'readers:\s*\n\s+-\s*\{').hasMatch(entry);
        final hasPassthrough =
            RegExp(r'prompt_passthrough:\s*true').hasMatch(entry);
        final hasIntentional =
            RegExp(r'intentionally_orphan:\s*true').hasMatch(entry);

        if (!hasReaders && !hasPassthrough && !hasIntentional) {
          offenders.add(keyName);
        }
      }

      expect(offenders, isEmpty,
          reason:
              'Every key entry must declare readers: [...], '
              'prompt_passthrough: true, or intentionally_orphan: true. '
              'Offenders: $offenders');
    });

    test('every file:line citation resolves', () {
      // {file: <path>, ... line: <N>} or  {file: <path>, line: <N>, ...}
      final fileLineRegex = RegExp(
        r'\{[^}]*file:\s*([^\s,}]+)[^}]*line:\s*(\d+)[^}]*\}',
      );
      final unresolved = <String>[];
      for (final m in fileLineRegex.allMatches(manifest)) {
        final relPath = m.group(1)!.trim();
        final line = int.parse(m.group(2)!.trim());
        final f = File(relPath);
        if (!f.existsSync()) {
          unresolved.add('$relPath (file does not exist)');
          continue;
        }
        final lineCount = f.readAsLinesSync().length;
        if (line < 1 || line > lineCount) {
          unresolved.add('$relPath:$line (outside [1, $lineCount])');
        }
      }
      expect(unresolved, isEmpty,
          reason: 'Every file:line in the manifest must resolve. '
              'Unresolved: $unresolved');
    });

    test('summary stats are present', () {
      expect(manifest.contains('summary:'), isTrue);
      expect(manifest.contains('total_keys:'), isTrue);
      expect(manifest.contains('edge_functions_audited:'), isTrue);
      expect(manifest.contains('verification_audit_date:'), isTrue);
    });

    test('orphan_readers section is enumerated (not silently empty)', () {
      // The audit MUST surface the morning-alert / streak-guardian /
      // protein-gap-alert nesting-mismatch and missing-writer cases.
      // Empty orphan_readers would mean the audit didn't read them.
      expect(manifest.contains('orphan_readers:'), isTrue);
      // At least one drift_class entry should be enumerated.
      expect(
        manifest.contains('drift_class:'),
        isTrue,
        reason:
            'orphan_readers must enumerate at least one drift_class entry. '
            'If you legitimately have zero orphan readers, document that '
            'with `orphan_readers: []  # audit verified zero` instead of '
            'silently empty.',
      );
    });
  });
}

/// Returns the substring from the line matching [header] (e.g. "keys:")
/// down to the next top-level YAML key (a line starting at column 0 with
/// `^[a-z_]+:`). Null when [header] is not found.
String? _extractSection(String src, String header) {
  final lines = src.split('\n');
  int start = -1;
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].startsWith(header)) {
      start = i + 1;
      break;
    }
  }
  if (start == -1) return null;
  int end = lines.length;
  final topLevel = RegExp(r'^[a-z_][a-z_0-9]*:');
  for (int i = start; i < lines.length; i++) {
    if (topLevel.hasMatch(lines[i])) {
      end = i;
      break;
    }
  }
  return lines.sublist(start, end).join('\n');
}

/// Splits a YAML list-of-maps section on entries starting with `  - key:`.
List<String> _splitEntries(String section) {
  final pattern = RegExp(r'^\s{2}-\s+key:', multiLine: true);
  final matches = pattern.allMatches(section).toList();
  final result = <String>[];
  for (int i = 0; i < matches.length; i++) {
    final start = matches[i].start;
    final end = i + 1 < matches.length ? matches[i + 1].start : section.length;
    result.add(section.substring(start, end));
  }
  return result;
}
