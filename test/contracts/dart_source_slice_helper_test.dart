library;

// L2b Landing B - the source-slicing helper that every presence pin in the
// measurement tests stands on. A helper that strips too much makes a negative
// pin ("this statement must NOT be here") vacuous, and one that strips too
// little lets a comment satisfy a positive pin, so its edge cases are pinned by
// value (B-pass reviewer B, finding 18).

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_source_slice.dart';

void main() {
  group('stripDartComments', () {
    test('a // comment that mentions /* does not start a block comment', () {
      const src = '''
// matches features/*/providers/ files
final keep = 1;
// and closes */ here
final alsoKeep = 2;
''';
      final out = stripDartComments(src);
      expect(out, contains('final keep = 1;'));
      expect(out, contains('final alsoKeep = 2;'));
      expect(out, isNot(contains('providers')));
    });

    test('a block comment that mentions // is removed up to its */', () {
      const src = 'a(); /* x // y */ b();\nc();\n';
      final out = stripDartComments(src);
      expect(out, contains('a();'));
      expect(out, contains('b();'));
      expect(out, contains('c();'));
      expect(out, isNot(contains('x')));
    });

    test('a // inside a string literal is code, not a comment', () {
      const src = "final u = 'https://example.com/a'; // tail\nfinal v = 1;\n";
      final out = stripDartComments(src);
      expect(out, contains("'https://example.com/a'"));
      expect(out, contains('final v = 1;'));
      expect(out, isNot(contains('tail')));
    });

    test('double-quoted, triple-quoted and raw strings are kept whole', () {
      const src = r'''
final a = "x // not a comment";
final b = """
line // one
line /* two */
""";
final c = r'raw // text \';
final d = 1; // gone
''';
      final out = stripDartComments(src);
      expect(out, contains('"x // not a comment"'));
      expect(out, contains('line // one'));
      expect(out, contains('line /* two */'));
      expect(out, contains(r"r'raw // text \'"));
      expect(out, contains('final d = 1;'));
      expect(out, isNot(contains('gone')));
    });

    test('an interpolation with nested quotes does not end the string', () {
      const src = r'''
final s = 'a ${m['k']} // b ${n["j"]} c'; // tail
final t = 2;
''';
      final out = stripDartComments(src);
      expect(out, contains(r"'a ${m['k']} // b ${n["));
      expect(out, contains('final t = 2;'));
      expect(out, isNot(contains('tail')));
    });

    test('nested block comments are removed as one and newlines are kept', () {
      const src = 'a();\n/* one /* two */ still one\n*/\nb();\n';
      final out = stripDartComments(src);
      expect(out, contains('a();'));
      expect(out, contains('b();'));
      expect(out, isNot(contains('still')));
      expect('\n'.allMatches(out).length, '\n'.allMatches(src).length,
          reason: 'line numbers survive');
    });

    test('an escaped quote does not end a string', () {
      const src = r"final s = 'it\'s // fine'; final t = 1;" '\n';
      final out = stripDartComments(src);
      expect(out, contains(r"'it\'s // fine'"));
      expect(out, contains('final t = 1;'));
    });

    test('an unterminated single-line quote cannot swallow the next lines', () {
      const src = "final bad = 'oops\nfinal next = 1;\n";
      final out = stripDartComments(src);
      expect(out, contains('final next = 1;'));
    });
  });

  group('functionBody / blockBody / countOf', () {
    const src = '''
class A {
  void one() {
    final x = {'a': 1};
    two();
  }
  Future<void> save({required int a, int b = 0}) async {
    keep();
  }
}
''';

    test('functionBody returns the block, skipping the parameter list', () {
      expect(functionBody(src, 'void one('), contains("final x = {'a': 1};"));
      final body = functionBody(src, 'Future<void> save(');
      expect(body, contains('keep();'));
      expect(body, isNot(contains('required')));
    });

    test('functionBody throws for an absent or duplicated header', () {
      expect(() => functionBody(src, 'void nope('), throwsStateError);
      expect(() => functionBody('$src\n$src', 'void one('), throwsStateError);
    });

    test('blockBody returns the class block', () {
      expect(blockBody(src, 'class A'), contains('keep();'));
    });

    test('countOf counts non-overlapping occurrences', () {
      expect(countOf('aaaa', 'aa'), 2);
      expect(countOf('abc', 'x'), 0);
    });
  });
}
