// test/scripts/teardown_sibling_await_lib_test.dart
//
// Pure-logic tests for scripts/teardown_sibling_await_lib.dart -- the
// tearDown/tearDownAll guard-mirror scanner behind
// scripts/check_teardown_no_unguarded_sibling_await.dart.
//
// These touch no git and no disk -- fixtures are literal Dart source
// snippets, modelled on the real shape from
// feedback_mistake_guard_without_its_mirror.md instance #27
// (2026-09-10): one cleanup await guarded, its sibling in the same block
// bare.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/teardown_sibling_await_lib.dart';

void main() {
  group('findUnguardedSiblingAwaits', () {
    test('BAD: guarded await + bare sibling await in the same tearDown block', () {
      const src = '''
void main() {
  tearDown(() async {
    try {
      await a.delete();
    } catch (_) {}
    await b.signOut();
  });
}
''';
      final findings = findUnguardedSiblingAwaits(src, fileLabel: 'x_test.dart');
      expect(findings, hasLength(1));
      expect(findings.single.file, 'x_test.dart');
      expect(findings.single.describe(), contains('unguarded sibling await'));
    });

    test('GOOD mirror #1: BOTH awaits guarded — not flagged', () {
      const src = '''
void main() {
  tearDown(() async {
    try {
      await a.delete();
    } catch (_) {}
    try {
      await b.signOut();
    } catch (_) {}
  });
}
''';
      expect(
        findUnguardedSiblingAwaits(src, fileLabel: 'x_test.dart'),
        isEmpty,
      );
    });

    test('GOOD mirror #2: BOTH awaits bare, zero guards in the block — not flagged '
        '(a different, wider problem this gate does not claim to cover)', () {
      const src = '''
void main() {
  tearDown(() async {
    await a.delete();
    await b.signOut();
  });
}
''';
      expect(
        findUnguardedSiblingAwaits(src, fileLabel: 'x_test.dart'),
        isEmpty,
      );
    });

    test('GOOD: bare await OUTSIDE any tearDown block, guarded await elsewhere '
        'in the file — not flagged (scope is tearDown/tearDownAll only)', () {
      const src = '''
void main() {
  tearDown(() async {
    try {
      await a.delete();
    } catch (_) {}
  });

  test('does a thing', () async {
    await someUnrelatedBareAwait();
  });
}
''';
      expect(
        findUnguardedSiblingAwaits(src, fileLabel: 'x_test.dart'),
        isEmpty,
      );
    });

    test('BAD: tearDownAll variant is recognized, not just tearDown', () {
      const src = '''
void main() {
  tearDownAll(() async {
    try {
      await a.delete();
    } catch (_) {}
    await b.signOut();
  });
}
''';
      final findings = findUnguardedSiblingAwaits(src, fileLabel: 'x_test.dart');
      expect(findings, hasLength(1));
    });

    test('GOOD: try/finally with no catch does not count as guarded, so a bare '
        'sibling await next to it is not flagged as an INCONSISTENCY (there is '
        'no guard to be inconsistent with)', () {
      const src = '''
void main() {
  tearDown(() async {
    try {
      await a.delete();
    } finally {
      cleanupSync();
    }
    await b.signOut();
  });
}
''';
      expect(
        findUnguardedSiblingAwaits(src, fileLabel: 'x_test.dart'),
        isEmpty,
      );
    });

    test('BAD: two separate tearDown blocks in one file — only the mismatched '
        'one is flagged, the well-guarded one is not', () {
      const src = '''
void main() {
  group('a', () {
    tearDown(() async {
      try {
        await a.delete();
      } catch (_) {}
      try {
        await c.close();
      } catch (_) {}
    });
  });

  group('b', () {
    tearDown(() async {
      try {
        await d.delete();
      } catch (_) {}
      await e.signOut();
    });
  });
}
''';
      final findings = findUnguardedSiblingAwaits(src, fileLabel: 'x_test.dart');
      expect(findings, hasLength(1));
      // Block 'a' (well-guarded) opens its tearDown around line 4; block 'b'
      // (the mismatched one) around line 15. A threshold well clear of both
      // rounding edges proves the SECOND block was the one flagged, not the
      // first -- without hardcoding a brittle exact line number.
      expect(findings.single.teardownLine, greaterThan(12));
    });
  });
}
