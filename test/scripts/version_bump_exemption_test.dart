// test/scripts/version_bump_exemption_test.dart
//
// Every attack that broke a previous attempt at the OI-58a version-bump
// exemption, as a permanent control.
//
// THE REASON THIS FILE EXISTS. Attempts 1, 2, 3 and 4 each passed every test
// written for them at the time. Round-1 review of attempt 3 named why: the
// suite had a control for each PREVIOUS attempt's failure and none for the
// current one's. So this file is organised by ATTACK, not by attempt — each
// test names the concrete payload that defeated an earlier design, and every
// one was executed against the real helper before being written down.
//
// Pure-function tests on purpose: `isVersionBumpCommit` takes the before/after
// blobs and their git modes as data, so the whole decision is testable without
// spawning git. That is also why the design moved off diff-parsing — a function
// that takes file CONTENT cannot be fooled by how git renders a diff.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/plan_review_record_lib.dart';

const _pubspec = 'pubspec.yaml';
const _constants = 'lib/core/constants/app_constants.dart';

String _pub(String v) =>
    'name: icanbefitter\nversion: $v\ndependencies:\n  foo: ^1.0.0\n';

String _con(String v, {String sameLine = '', String extraBody = ''}) =>
    'class AppConstants {\n'
    "  static const String appVersion = '$v';$sameLine\n"
    '  static const int monthlyPriceInr = 349;\n'
    '  static const int freeAiMessagesPerDay = 10;\n'
    '$extraBody'
    '}\n';

/// Record builder. Defaults to a regular file on both sides, so a test only
/// spells out a mode when the MODE is the thing under test.
VersionBumpFile _f(String path, String? before, String? after,
        {String? beforeMode = '100644', String? afterMode = '100644'}) =>
    (
      path: path,
      before: before,
      after: after,
      beforeMode: beforeMode,
      afterMode: afterMode
    );

void main() {
  group('the release flow must keep working', () {
    test('a genuine bump of both files PASSES', () {
      expect(
          isVersionBumpCommit([_pubspec, _constants], [
            _f(_pubspec, _pub('1.0.0+37'), _pub('1.0.0+38')),
            _f(_constants, _con('1.0.0+37'), _con('1.0.0+38')),
          ]),
          isTrue,
          reason: 'this is `2c4cbddd`, exactly four changed lines');
    });

    test('a pubspec-ONLY bump PASSES', () {
      expect(
          isVersionBumpCommit(
              [_pubspec], [_f(_pubspec, _pub('1.0.0+37'), _pub('1.0.0+38'))]),
          isTrue,
          reason: '17 historical bumps touched pubspec.yaml alone; requiring '
              'both files would redden the release flow');
    });

    test('CRLF line endings do not break a genuine bump', () {
      expect(
          isVersionBumpCommit([_pubspec], [
            _f(_pubspec, 'name: app\r\nversion: 1.0.0+37\r\n',
                'name: app\r\nversion: 1.0.0+38\r\n'),
          ]),
          isTrue,
          reason: 'the repo checks out CRLF on Windows; the version regex must '
              'tolerate the trailing \\r');
    });
  });

  group('attacks that defeated earlier attempts', () {
    test('ATTEMPT-2: bump-shaped PATHS with non-version content', () {
      // `paths.every(allowList.contains)` is an all-of over an ALLOW-LIST, so it
      // accepts every proper subset. A commit touching only app_constants.dart
      // passed at account tier while rewriting prices and free-tier caps.
      expect(
          isVersionBumpCommit([_constants], [
            _f(_constants, _con('1.0.0+37'),
                _con('1.0.0+37').replaceAll('monthlyPriceInr = 349', 'monthlyPriceInr = 1')),
          ]),
          isFalse);
    });

    test('ATTEMPT-3: extra Dart riding the appVersion line', () {
      // The old regex was unanchored and applied with hasMatch — a CONTAINMENT
      // test. Valid Dart, and no formatter gate exists to split the line.
      expect(
          isVersionBumpCommit([_constants], [
            _f(_constants, _con('1.0.0+37'),
                _con('1.0.0+38', sameLine: ' static const bool kBypassProGate = true;')),
          ]),
          isFalse,
          reason: 'normalising the declaration leaves the smuggled constant '
              'behind, so the normalised blobs differ');
    });

    test('ATTEMPT-3: a file git renders with no +/- lines', () {
      // One NUL byte makes a file binary; a `.gitattributes` `-diff` entry does
      // it deliberately. Under diff-parsing that file was never inspected and
      // the OTHER file's version line satisfied a single global flag.
      expect(
          isVersionBumpCommit([_pubspec, _constants], [
            _f(_pubspec, _pub('1.0.0+37'), _pub('1.0.0+38')),
            _f(_constants, _con('1.0.0+37'),
                _con('1.0.0+37', extraBody: '  static const int backdoor = 1;\n')),
          ]),
          isFalse,
          reason: 'blobs are compared per FILE, so a second file mutated behind '
              'a real bump is caught however git renders it');
    });

    test('ATTEMPT-3: payload elsewhere in the file', () {
      expect(
          isVersionBumpCommit([_pubspec], [
            _f(_pubspec, _pub('1.0.0+37'), '${_pub('1.0.0+38')}evil: true\n'),
          ]),
          isFalse);
    });

    test('a NESTED version: key is not the app version', () {
      // `^\s*version:` accepted arbitrary indentation, so a dependency pin under
      // a `hosted:` block satisfied the "top-level app version" rule.
      expect(
          isVersionBumpCommit([_pubspec], [
            _f(_pubspec,
                'name: app\nversion: 1.0.0+37\ndeps:\n  hosted:\n    version: 1.0.0+1\n',
                'name: app\nversion: 1.0.0+37\ndeps:\n  hosted:\n    version: 9.9.9+9\n'),
          ]),
          isFalse);
    });

    test('B-PASS P0-1: a SECOND version token changes freely', () {
      // `hasMatch` (>= 1) plus `replaceAll` collapsed BOTH occurrences to the
      // same placeholder, so the second one's value was unconstrained. Both
      // exempt-eligible files are vulnerable, and only pubspec has a downstream
      // circuit-breaker (`pub` rejects duplicate keys) — Dart does not.
      expect(
          isVersionBumpCommit([_pubspec], [
            _f(_pubspec, 'name: app\nversion: 1.0.0+36\nversion: 9.9.9+1\n',
                'name: app\nversion: 1.0.0+37\nversion: 8.8.8+2\n'),
          ]),
          isFalse,
          reason: 'pubspec: the second top-level version: key mutates silently');

      expect(
          isVersionBumpCommit([_constants], [
            _f(_constants,
                "class AppConstants { static const String appVersion = '1.0.0+36'; }\n"
                    "class Other { static const String appVersion = 'SAFE'; }\n",
                "class AppConstants { static const String appVersion = '1.0.0+37'; }\n"
                    "class Other { static const String appVersion = 'PWNED'; }\n"),
          ]),
          isFalse,
          reason: 'Dart: a second class declaring its own appVersion compiles '
              'fine and nothing downstream would have caught it');
    });

    test('B-PASS P0-2: converting a file to a SYMLINK', () {
      // `git show <rev>:<path>` returns a symlink's TARGET TEXT as if it were
      // file content, so a pubspec.yaml swapped for a symlink whose target reads
      // like a bumped pubspec was granted the exemption. Content cannot see
      // that; the tree mode can.
      expect(
          isVersionBumpCommit([_pubspec], [
            _f(_pubspec, _pub('1.0.0+37'), _pub('1.0.0+38'),
                afterMode: '120000'),
          ]),
          isFalse,
          reason: 'mode 120000 is a symlink, not a file whose content this '
              'comparison can judge');
      expect(
          isVersionBumpCommit([_pubspec], [
            _f(_pubspec, _pub('1.0.0+37'), _pub('1.0.0+38'), afterMode: null),
          ]),
          isFalse,
          reason: 'an unreadable mode is not assumed regular');
    });
  });

  // ── B-pass of OI-275 batch B2, finding F4 ───────────────────────────────────
  // The exemption says a bump is "byte-identical once the version token is normalised". Three
  // things that claim did not actually cover: the file MODE (100644 <-> 100755 are both regular
  // files), the VALUE of the token in app_constants.dart (any text between two quotes), and a
  // leading byte-order mark (a git-reader matter, pinned through the CLI in
  // version_bump_git_lib_test.dart; the pure predicate sees the BOM as a character).
  group('B-pass F4: the "byte-identical" claim holds for the mode, the token value and a BOM', () {
    final bumped = [
      _f(_pubspec, _pub('1.0.0+37'), _pub('1.0.0+38')),
      _f(_constants, _con('1.0.0+37'), _con('1.0.0+38')),
    ];

    test('CONTROL: the unmodified bump is a bump (the three tests below mean nothing otherwise)', () {
      expect(isVersionBumpCommit([_pubspec, _constants], bumped), isTrue);
    });

    test('flipping the executable bit beside a bump is NOT a bump (100644 -> 100755 and back)', () {
      for (final (before, after) in const [('100644', '100755'), ('100755', '100644')]) {
        expect(
            isVersionBumpCommit([_pubspec], [
              _f(_pubspec, _pub('1.0.0+37'), _pub('1.0.0+38'), beforeMode: before, afterMode: after),
            ]),
            isFalse,
            reason: 'a mode change is a change git records; $before -> $after is not "byte-identical"');
      }
    });

    test('MIRROR: a file that is executable on BOTH sides is still a bump (equality, not "must be 100644")', () {
      expect(
          isVersionBumpCommit([_pubspec], [
            _f(_pubspec, _pub('1.0.0+37'), _pub('1.0.0+38'), beforeMode: '100755', afterMode: '100755'),
          ]),
          isTrue,
          reason: 'the rule is that the mode did not change, not that it equals one value');
    });

    test('the appVersion value must stay version-SHAPED: any other string is NOT a bump', () {
      for (final value in const ['x', '', '1.0.0', 'v1.0.0+37', '1.0.0+37-beta', '1.0+37', "1.0.0+37' + 'x"]) {
        expect(
            isVersionBumpCommit([_pubspec, _constants], [
              _f(_pubspec, _pub('1.0.0+37'), _pub('1.0.0+38')),
              _f(_constants, _con('1.0.0+37'), _con(value)),
            ]),
            isFalse,
            reason: "appVersion = '$value' is not major.minor.patch+build; only Gate 51 (commit time) "
                'would notice it disagrees with pubspec');
      }
    });

    test('a byte-order mark gained or lost beside a bump is NOT a bump (the predicate compares it as a character)', () {
      const bom = '\uFEFF';
      expect(
          isVersionBumpCommit([_pubspec], [_f(_pubspec, _pub('1.0.0+37'), '$bom${_pub('1.0.0+38')}')]), isFalse);
      expect(
          isVersionBumpCommit([_pubspec], [_f(_pubspec, '$bom${_pub('1.0.0+37')}', _pub('1.0.0+38'))]), isFalse);
      expect(
          isVersionBumpCommit([_pubspec], [_f(_pubspec, '$bom${_pub('1.0.0+37')}', '$bom${_pub('1.0.0+38')}')]), isTrue,
          reason: 'MIRROR: a BOM that is on both sides changes nothing');
    });
  });

  group('structural rejections', () {
    test('a third file disqualifies even a perfect bump', () {
      expect(
          isVersionBumpCommit([_pubspec, 'lib/features/auth/reset.dart'],
              [_f(_pubspec, _pub('1.0.0+37'), _pub('1.0.0+38'))]),
          isFalse,
          reason: 'the FULL path list is the precondition — an auth edit must '
              'not ride along on a valid bump');
    });

    test('a changed path with no fetched blob is not assumed benign', () {
      expect(
          isVersionBumpCommit([_pubspec, _constants],
              [_f(_pubspec, _pub('1.0.0+37'), _pub('1.0.0+38'))]),
          isFalse,
          reason: 'app_constants.dart changed but was never read — silence is '
              'not evidence of innocence');
    });

    test('creating or deleting either file is not a bump', () {
      expect(
          isVersionBumpCommit(
              [_constants], [_f(_constants, null, _con('1.0.0+38'))]),
          isFalse);
      expect(
          isVersionBumpCommit(
              [_pubspec], [_f(_pubspec, _pub('1.0.0+37'), null)]),
          isFalse);
    });

    test('a no-op commit is not a bump', () {
      expect(
          isVersionBumpCommit(
              [_pubspec], [_f(_pubspec, _pub('1.0.0+37'), _pub('1.0.0+37'))]),
          isFalse,
          reason: '"nothing changed" must not earn an exemption');
    });

    test('a file with no version token at all is not a bump', () {
      expect(
          isVersionBumpCommit([_pubspec],
              [_f(_pubspec, 'name: app\n', 'name: app\nevil: true\n')]),
          isFalse,
          reason: 'normalizeVersionToken returns null, which must reject rather '
              'than compare two unnormalised blobs');
    });

    test('an empty path list is not a bump', () {
      expect(isVersionBumpCommit(const [], const []), isFalse);
    });

    test('a path that differs from a version file only by surrounding whitespace is NOT that file', () {
      // The decision's input must be EXACT. ' pubspec.yaml' (leading space) is a distinct, valid
      // git path that can hold anything; a trimming normaliser turned it into the real version
      // file, so a spoof rode along on a genuine bump under the exemption (found by probing, not
      // by an earlier review). The control must pass first, or the loop below proves nothing.
      final files = [
        _f(_pubspec, _pub('1.0.0+37'), _pub('1.0.0+38')),
        _f(_constants, _con('1.0.0+37'), _con('1.0.0+38')),
      ];
      expect(isVersionBumpCommit([_pubspec, _constants], files), isTrue,
          reason: 'setup: the unspoofed bump is a bump');
      for (final spoof in [
        ' pubspec.yaml',
        'pubspec.yaml ',
        '\tpubspec.yaml',
        '\u00a0pubspec.yaml',
        'pubspec.yaml\r',
        ' lib/core/constants/app_constants.dart',
        'lib/core/constants/app_constants.dart\n',
      ]) {
        expect(isVersionBumpCommit([_pubspec, _constants, spoof], files), isFalse,
            reason: 'a third path ${spoof.codeUnits} is not a version file');
      }
      // A path made ONLY of whitespace is a path too, not "nothing to see".
      expect(isVersionBumpCommit([_pubspec, _constants, ' '], files), isFalse);
    });
  });
}
