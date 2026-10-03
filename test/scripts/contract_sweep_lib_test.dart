import 'package:flutter_test/flutter_test.dart';
import '../../scripts/contract_sweep_lib.dart';

// Both `file:` shapes the real registry uses (896 `- file:` items, 176 `- { file: ... }` maps, 0 bare).
const _registry = '''
concepts:

  - concept: phase_adherence_rate
    domain: workout
    behavioral_test_path: test/contracts/phase_adherence_rate_test.dart  # c4d1e2 — pins the paused arm
    writers:
      - file: lib/core/services/workout_schedule_read_service.dart
        line_range: 1-40
    readers:
      - file: lib/features/train/screens/train/screen.dart
        line_range: 10-20
    ist_sites:
      - { file: lib/core/utils/ist_date.dart, line: 12 }

  - concept: subscription_cqrs
    behavioral_test_path: test/contracts/subscription_cqrs_behavioral_test.dart
    behavioral_test_path_cqrs: test/contracts/subscription_cqrs_second_test.dart
    presence_only: true # see test/sql/x.sql
    writers:
      - file: lib/core/services/subscription_service.dart
        line_range: 1-9
''';

bool _all(String _) => true;

void main() {
  group('contentReferenceKeys', () {
    test('basename with extension; parent/basename for ubiquitous names; doc-like by extension EXCEPT the contract-doc dirs; test helpers included', () {
      final keys = contentReferenceKeys([
        'lib/core/services/sync/sync_workout.dart',
        'supabase/functions/ai-proxy/index.ts',
        'lib/main.dart',
        'test/contracts/foo_test.dart',           // arm (c) territory — excluded here
        'docs/superpowers/plans/2026-09-19-x.md', // prose .md — excluded
        'CLAUDE.md',                              // prose .md — excluded: 77 test files reference it (over-selection), and it is pinned platform so pre-push runs the full suite anyway
        'docs/audit/open_issues.md',              // .md under docs/audit/ — a DATA contract with 10 test readers → a key
        'docs/architecture/sync.md',              // .md under docs/architecture/ — 29 test readers → a key
        'test/helpers/h.dart',                    // a test HELPER is a key
        'docs/sot_registry.yaml',                 // docs/ but data — a key
      ]);
      expect(keys, {'sync_workout.dart', 'ai-proxy/index.ts', 'lib/main.dart', 'open_issues.md', 'sync.md', 'h.dart', 'sot_registry.yaml'});
    });
  });

  group('registryTestsFor', () {
    test('selects on a writer `- file:` item, a reader item, and an inline `{ file: }` map; sibling keys; comment-stripped', () {
      expect(registryTestsFor(_registry, {'lib/core/services/subscription_service.dart'}),
          ['test/contracts/subscription_cqrs_behavioral_test.dart', 'test/contracts/subscription_cqrs_second_test.dart']);
      expect(registryTestsFor(_registry, {'lib/features/train/screens/train/screen.dart'}), ['test/contracts/phase_adherence_rate_test.dart']);
      expect(registryTestsFor(_registry, {'lib/core/utils/ist_date.dart'}), ['test/contracts/phase_adherence_rate_test.dart']);
    });
    test('positive control: an unrelated change selects nothing', () {
      expect(registryTestsFor(_registry, {'lib/unrelated.dart'}), isEmpty);
    });
  });

  group('buildSelection', () {
    test('unions the arms, dedupes, sorts, skips non-dart + golden cites, drops absent files, lists unmapped', () {
      final sel = buildSelection(
        changedPaths: [
          'lib/core/services/subscription_service.dart',
          'lib/orphan.dart',
          'test/scripts/a_test.dart',
          'docs/x.md',
          'lib/shared/widgets/ward_card.dart',
        ],
        registryYaml: _registry,
        grepResults: {
          'subscription_service.dart': ['test/contracts/subscription_cqrs_behavioral_test.dart', 'test/widgets/paywall_test.dart', 'test/sql/notes.sql'],
          'orphan.dart': <String>[],
          'ward_card.dart': ['test/goldens/wardroom/ward_card_golden_test.dart'],
        },
        exists: (p) => p != 'test/contracts/subscription_cqrs_second_test.dart',
      );
      expect(sel.fallbackReason, isNull);
      expect(sel.tests, ['test/contracts/subscription_cqrs_behavioral_test.dart', 'test/scripts/a_test.dart', 'test/widgets/paywall_test.dart']);
      expect(sel.skipped, ['test/goldens/wardroom/ward_card_golden_test.dart', 'test/sql/notes.sql']);
      expect(sel.droppedMissing, ['test/contracts/subscription_cqrs_second_test.dart']);
      expect(sel.unmappedChanged, ['lib/orphan.dart']);
    });
    test('a golden-only selection runs NOTHING (a golden-only spawn exits 79 "No tests ran")', () {
      final sel = buildSelection(changedPaths: ['lib/shared/widgets/ward_card.dart'], registryYaml: _registry,
          grepResults: {'ward_card.dart': ['test/goldens/wardroom/ward_card_golden_test.dart']}, exists: _all);
      expect(sel.tests, isEmpty);
      expect(sel.skipped, ['test/goldens/wardroom/ward_card_golden_test.dart']);
    });
    test('RED PATH: unreadable registry falls back to the whole contracts subset', () {
      final sel = buildSelection(changedPaths: ['lib/a.dart'], registryYaml: null, grepResults: {'a.dart': <String>[]}, exists: _all);
      expect(sel.fallbackReason, isNotNull);
      expect(sel.tests, ['test/contracts/']);
    });
    test('RED PATH: a failed git grep (null result) falls back — uncertainty must not look like a clean sweep', () {
      final sel = buildSelection(changedPaths: ['lib/a.dart'], registryYaml: _registry, grepResults: {'a.dart': null}, exists: _all);
      expect(sel.fallbackReason, isNotNull);
      expect(sel.tests, ['test/contracts/']);
    });
    test('RED PATH: a key that was never grepped falls back', () {
      final sel = buildSelection(changedPaths: ['lib/a.dart'], registryYaml: _registry, grepResults: {}, exists: _all);
      expect(sel.fallbackReason, isNotNull);
    });
    test('docs-only change selects nothing and reports no fallback', () {
      final sel = buildSelection(changedPaths: ['docs/x.md'], registryYaml: _registry, grepResults: {}, exists: _all);
      expect(sel.fallbackReason, isNull);
      expect(sel.tests, isEmpty);
      expect(sel.unmappedChanged, isEmpty);
    });
    test('PROSE inside a contract-doc dir is still a key: zero grep hits -> unmapped, no fallback, no tests (by design; 56 of 61 docs/audit/*.md have no test reader)', () {
      final sel = buildSelection(
          changedPaths: ['docs/audit/2026-09-01-hermes-report.md'],
          registryYaml: _registry,
          grepResults: {'2026-09-01-hermes-report.md': <String>[]},
          exists: _all);
      expect(sel.fallbackReason, isNull);
      expect(sel.tests, isEmpty);
      expect(sel.unmappedChanged, ['docs/audit/2026-09-01-hermes-report.md']);
    });
  });
}
