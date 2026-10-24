// test/scripts/memory_write_guard_lib_test.dart
//
// Unit tests for the pure predicates behind the memory write-guard hook.
// Mutation-proven (rule 24): see the header comments on each group for what
// was neutered and how many tests reddened.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/memory_write_guard_lib.dart';

void main() {
  group('isMemoryFilePath', () {
    test('matches the harness memory dir', () {
      expect(
        isMemoryFilePath(
            'C:/Users/upend/.claude/projects/foo/memory/feedback_x.md'),
        isTrue,
      );
    });

    test('matches a project-local memory dir', () {
      expect(isMemoryFilePath('memory/project_y.md'), isTrue);
    });

    test('rejects a non-.md file', () {
      expect(isMemoryFilePath('memory/project_y.txt'), isFalse);
    });

    test('rejects an unrelated .md file', () {
      expect(isMemoryFilePath('docs/architecture/sync.md'), isFalse);
    });

    test('handles backslash-separated Windows paths', () {
      expect(
        isMemoryFilePath(r'C:\Users\upend\.claude\projects\foo\memory\x.md'),
        isTrue,
      );
    });
  });

  group('isMemoryIndexPath', () {
    test('matches bare MEMORY.md', () {
      expect(isMemoryIndexPath('MEMORY.md'), isTrue);
    });

    test('matches a full harness path ending in MEMORY.md', () {
      expect(
        isMemoryIndexPath('C:/Users/upend/.claude/projects/foo/memory/MEMORY.md'),
        isTrue,
      );
    });

    test('rejects MEMORY_ARCHIVED.md -- a different contract (append-only archive)', () {
      expect(
        isMemoryIndexPath('C:/Users/upend/.claude/projects/foo/memory/MEMORY_ARCHIVED.md'),
        isFalse,
      );
    });

    test('rejects a topic file', () {
      expect(isMemoryIndexPath('memory/project_foo.md'), isFalse);
    });
  });

  group('isMemoryArchivePath', () {
    test('matches bare MEMORY_ARCHIVED.md', () {
      expect(isMemoryArchivePath('MEMORY_ARCHIVED.md'), isTrue);
    });

    test('matches a full harness path ending in MEMORY_ARCHIVED.md', () {
      expect(
        isMemoryArchivePath('C:/Users/upend/.claude/projects/foo/memory/MEMORY_ARCHIVED.md'),
        isTrue,
      );
    });

    test('rejects MEMORY.md', () {
      expect(isMemoryArchivePath('MEMORY.md'), isFalse);
    });

    test('rejects a topic file', () {
      expect(isMemoryArchivePath('memory/project_foo.md'), isFalse);
    });
  });

  group('validateTopicFile', () {
    const valid = '''
---
name: my-topic
description: a one-line summary
metadata:
  type: project
---

# Body
''';

    test('a well-formed topic file has no issues', () {
      expect(validateTopicFile(valid), isEmpty);
    });

    test('accepts a bare `type:` field (not nested under metadata)', () {
      const bareType = '''
---
name: my-topic
description: a one-line summary
type: feedback
---
''';
      expect(validateTopicFile(bareType), isEmpty);
    });

    test('flags a missing opening delimiter', () {
      const noOpen = '# Just a heading\nNo frontmatter at all.';
      final issues = validateTopicFile(noOpen);
      expect(issues, hasLength(1));
      expect(issues.first.message, contains('opening'));
    });

    test('flags an unclosed frontmatter block', () {
      const unclosed = '---\nname: x\ndescription: y\n\n# body with no closing ---';
      final issues = validateTopicFile(unclosed);
      expect(issues, hasLength(1));
      expect(issues.first.message, contains('never closed'));
    });

    test('flags a missing name field', () {
      const noName = '---\ndescription: y\nmetadata:\n  type: project\n---\n';
      final issues = validateTopicFile(noName);
      expect(issues.map((i) => i.message), contains(contains('`name:`')));
    });

    test('flags a missing description field', () {
      const noDesc = '---\nname: x\nmetadata:\n  type: project\n---\n';
      final issues = validateTopicFile(noDesc);
      expect(issues.map((i) => i.message), contains(contains('`description:`')));
    });

    test('flags a missing type field (neither bare nor nested)', () {
      const noType = '---\nname: x\ndescription: y\n---\n';
      final issues = validateTopicFile(noType);
      expect(issues.map((i) => i.message), contains(contains('`type:`')));
    });

    // MUTATION-PROOF CASE: a hand-written memory file with a metadata block
    // that has OTHER fields but no type at all -- the shape that slipped
    // through during earlier sessions (project_icanbefitter_discipline_
    // patterns_2026_09_23.md carries `node_type: memory` alongside `type:
    // project` -- this proves the guard reads `type:` specifically, not any
    // key under metadata).
    test('does not accept an unrelated nested key as satisfying `type:`', () {
      const wrongKey = '---\nname: x\ndescription: y\nmetadata:\n  node_type: memory\n---\n';
      final issues = validateTopicFile(wrongKey);
      expect(issues.map((i) => i.message), contains(contains('`type:`')));
    });
  });

  group('validateIndexFile', () {
    test('a small well-formed index has no issues', () {
      const small = '# Memory Index\n\n## Section\n- [a](a.md) -- short pointer.\n';
      expect(validateIndexFile(small), isEmpty);
    });

    test('flags a line over the byte cap', () {
      final longLine = '- ${'x' * 650}';
      final issues = validateIndexFile('# H\n$longLine\n', maxLineBytes: 600);
      expect(issues, hasLength(1));
      expect(issues.first.message, contains('over the 600B pointer cap'));
    });

    test('does not flag a heading line regardless of length', () {
      final longHeading = '# ${'x' * 650}';
      expect(validateIndexFile('$longHeading\n', maxLineBytes: 600), isEmpty);
    });

    test('does not flag a blockquote note regardless of length', () {
      final longQuote = '> ${'x' * 650}';
      expect(validateIndexFile('$longQuote\n', maxLineBytes: 600), isEmpty);
    });

    test('flags the whole file exceeding the hard byte cap', () {
      final huge = 'x' * 100;
      final issues = validateIndexFile(huge, hardCapBytes: 50);
      expect(issues.map((i) => i.message), contains(contains('hard cap')));
    });

    test('byte count uses UTF-8 bytes, not UTF-16 code units', () {
      // A multi-byte character (emoji) has more UTF-8 bytes than Dart's
      // String.length would count -- this is the exact class of bug this
      // guard exists to avoid re-introducing (the founder's global CLAUDE.md
      // caps are stated as BYTE counts).
      final line = '- ⚠️' * 100; // ~800 UTF-8 bytes (8B/unit), far fewer UTF-16 units
      final issues = validateIndexFile('$line\n', maxLineBytes: 600);
      expect(issues, isNotEmpty);
    });
  });

  group('validateMemoryWrite dispatch', () {
    test('routes MEMORY.md through the index validator', () {
      final longLine = '- ${'x' * 650}';
      final issues = validateMemoryWrite('memory/MEMORY.md', '$longLine\n');
      expect(issues, isNotEmpty);
      expect(issues.first.message, contains('pointer cap'));
    });

    test('routes a topic file through the frontmatter validator', () {
      final issues = validateMemoryWrite('memory/project_x.md', 'no frontmatter here');
      expect(issues, isNotEmpty);
      expect(issues.first.message, contains('opening'));
    });

    test('returns no issues for a path outside any memory dir', () {
      expect(validateMemoryWrite('docs/foo.md', 'anything at all'), isEmpty);
    });

    // REGRESSION (round-1 review, P1, 2026-09-23): MEMORY_ARCHIVED.md was
    // excluded from isMemoryIndexPath but the dispatch never gave it its own
    // branch, so it fell through to validateTopicFile and failed on "missing
    // opening ---" on EVERY edit -- the most routinely written memory file in
    // this repo's own /consolidate-memory workflow. Uses the real archive
    // file's actual opening line, not a fabricated shape.
    test('MEMORY_ARCHIVED.md is a no-op -- it carries neither contract', () {
      final issues = validateMemoryWrite(
        'C:/Users/upend/.claude/projects/foo/memory/MEMORY_ARCHIVED.md',
        '# Memory Archive Index\n\n> Topic pointers to the on-disk memory files.\n',
      );
      expect(issues, isEmpty);
    });
  });
}
