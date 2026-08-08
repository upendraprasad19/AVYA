// test/scripts/claude_md_citations_letter_suffix_test.dart
//
// Regression coverage for Gate 26's letter-suffixed-section support
// (`scripts/check_claude_md_citations.dart`, repo-gate-pattern-sweep Unit 2,
// diagnose e7c3b9).
//
// WHAT THIS EXISTS TO CATCH. Before the fix, BOTH regexes stopped at digits:
//   headingRegex  ^#{2,3}\s+(\d+(?:\.\d+)?)\.?\s
//   citeRegex     §(\d+(?:\.\d+)?)
// so root CLAUDE.md's real `## 2a.` heading was never added to knownSections,
// and every `§2a` citation truncated to the captured group "2" — which
// coincidentally matches the UNRELATED `## 2.` section. The citations
// therefore "passed" while pointing at the wrong place, and the gate provided
// zero real protection for them. The fix adds `[a-z]?` to both.
//
// WHY A SUBPROCESS TEST RATHER THAN A MIRRORED REGEX. Both regexes are inline
// locals inside the gate's `main()` — not exported, so a unit test cannot
// import them. Re-declaring copies here would pin a COPY and keep passing if
// the real ones were reverted, which is exactly the failure this test exists
// to prevent (`feedback_source_grep_false_confidence.md`: a check is only as
// wide as its input set). So this drives the REAL script as a subprocess.
//
// The gate resolves every path relative to CWD (`File('CLAUDE.md')`,
// `Directory('lib')`, `Directory('supabase')`), so a throwaway fixture
// directory is a complete, honest environment for it.
//
// Run: flutter test test/scripts/claude_md_citations_letter_suffix_test.dart

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String gateScript;
  late Directory fixture;

  setUpAll(() {
    gateScript =
        '${Directory.current.path}/scripts/check_claude_md_citations.dart';
    expect(File(gateScript).existsSync(), isTrue,
        reason: 'the gate under test must exist at its known path');
  });

  setUp(() {
    fixture = Directory.systemTemp.createTempSync('gate26_letter_');
    // The gate walks these two unconditionally — they must exist or it throws.
    Directory('${fixture.path}/lib').createSync(recursive: true);
    Directory('${fixture.path}/supabase').createSync(recursive: true);
  });

  tearDown(() {
    if (fixture.existsSync()) fixture.deleteSync(recursive: true);
  });

  /// Runs the REAL gate with [fixture] as CWD and returns (exitCode, output).
  ({int code, String out}) runGate() {
    final r = Process.runSync(
      'dart',
      ['run', gateScript],
      workingDirectory: fixture.path,
      runInShell: true,
    );
    return (code: r.exitCode, out: '${r.stdout}${r.stderr}');
  }

  void writeRoot(String body) =>
      File('${fixture.path}/CLAUDE.md').writeAsStringSync(body);

  test(
      'a §Na citation resolves against the REAL "## Na." heading and passes',
      () {
    writeRoot('''
# Root

## 2. TECH STACK
body

## 2a. SUPABASE PROJECT — CONFIRMED IDENTITY
body

See §2a for the project identity.
''');
    final r = runGate();
    expect(r.code, 0, reason: 'a §2a citation backed by a real ## 2a. '
        'heading must pass.\n${r.out}');
  });

  test(
      'THE REGRESSION: §Na must NOT be satisfied by an unrelated "## N." '
      'heading when "## Na." does not exist', () {
    // This is the exact pre-fix bug. `## 2.` exists; `## 2a.` does NOT.
    // Pre-fix, citeRegex captured "2", which matched `## 2.` → PASS (wrong).
    // Post-fix it captures "2a", which is absent → FAIL (correct).
    writeRoot('''
# Root

## 2. TECH STACK
body

See §2a for the project identity.
''');
    final r = runGate();
    expect(r.code, isNot(0),
        reason: 'a §2a citation with NO ## 2a. heading must FAIL. If this '
            'passes, the letter suffix is being truncated and §2a is '
            'silently resolving against the unrelated ## 2. section — the '
            'exact defect this gate change fixed.\n${r.out}');
    expect(r.out, contains('2a'),
        reason: 'the failure must name the unresolved section, not a '
            'truncated "2".\n${r.out}');
  });

  test('plain §N and §N.M citations still behave (no collateral change)', () {
    writeRoot('''
# Root

## 4. PROCESS INVARIANTS
body

### 4.1 Observation
body

Good refs: §4 and §4.1.
''');
    final ok = runGate();
    expect(ok.code, 0, reason: 'existing digit-only citations must still '
        'pass unchanged.\n${ok.out}');

    writeRoot('''
# Root

## 4. PROCESS INVARIANTS
body

Bad ref: §9.
''');
    final bad = runGate();
    expect(bad.code, isNot(0),
        reason: 'a genuinely dangling §N must still FAIL — the widened '
            'regex must not have loosened digit-only validation.\n${bad.out}');
  });

  // ------------------------------------------------------------------
  // Code zone (OI-91) — anchored citations in source comments.
  // ------------------------------------------------------------------
  //
  // WHY THESE ASSERT ON OUTPUT, NOT JUST EXIT CODE. `_codeZoneEnforced` is
  // `true` in this commit, but the finding LINE is emitted identically
  // whether the flag is `true` (blocking) or `false` (report-only, the mode
  // used during development to baseline the 138 pre-existing dead citations
  // without failing every commit mid-sweep). Asserting on the line pins the
  // detection logic itself rather than the current mode, so these tests
  // don't need rewriting if the flag is ever toggled again. The two
  // negative-control tests below ALSO assert `r.code == 0` — safe now that
  // enforcement already shipped in this commit, and it closes the gap a
  // pure `isNot(contains(...))` check has: that assertion is satisfied
  // just as well by the gate crashing before it ever ran.
  //
  // WHY THE ESCAPE SEQUENCE RATHER THAN THE LITERAL CHARACTER. The code zone
  // scans `test/`, so an anchored citation written literally in THIS file
  // makes the gate flag its own test — measured, not hypothetical: the first
  // draft of these fixtures took the repo count from 138 to 140. Dart resolves
  // the escape at runtime, so the fixture written to disk still contains the
  // real character the gate matches on, while this source file does not.
  group('code zone — anchored citations in source comments', () {
    /// Root with `## 3.`, `## 4.` and `### 4.4` real; nothing else.
    void writeStandardRoot() => writeRoot('''
# Root

## 3. SCREENS
body

## 4. PROCESS INVARIANTS
body

### 4.4 The coding rules
body
''');

    void writeCode(String relPath, String body) {
      final f = File('${fixture.path}/$relPath');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(body);
    }

    test('flags a dead anchored citation in a .dart comment', () {
      writeStandardRoot();
      writeCode('lib/thing.dart', '// per CLAUDE.md \u00A715, writers fan out\n');
      final r = runGate();
      expect(r.out, contains('lib/thing.dart:1'),
          reason: 'a dead anchored citation in source must be reported — this '
              'is the whole point of the code zone.\n${r.out}');
      expect(r.out, contains('§15'), reason: r.out);
    });

    test(
        'THE FALSE-POSITIVE CONTROL: a section token citing ANOTHER document '
        'is not flagged', () {
      // Measured at filing time: code carries 526 bare section tokens, only
      // 227 of which refer to the root contract file. If the code zone ever
      // regresses to the markdown zone's bare pattern, this fixture — which
      // stands in for the other 299 — starts failing the build.
      writeStandardRoot();
      writeCode('lib/other.dart', '''
// see the apk-test-6 spec §15 for the ordering
// and Plan §12, and DEVICE_TESTING.md §19
''');
      final r = runGate();
      expect(r.code, 0,
          reason: 'the gate must actually run and pass, not merely fail to '
              'mention this path — a crash before the scan starts would '
              'satisfy the contains() check below just as well.\n${r.out}');
      expect(r.out, isNot(contains('lib/other.dart')),
          reason: 'section tokens belonging to OTHER documents must not be '
              'attributed to the root contract file. A bare pattern here '
              'would fail on ~299 real citations.\n${r.out}');
    });

    test('does not flag a LIVE anchored citation', () {
      writeStandardRoot();
      writeCode('lib/live.dart', '// gated per CLAUDE.md \u00A74.4 rule 9\n');
      final r = runGate();
      expect(r.code, 0,
          reason: 'the gate must actually run and pass, not merely fail to '
              'mention this path — a crash before the scan starts would '
              'satisfy the contains() check below just as well.\n${r.out}');
      expect(r.out, isNot(contains('lib/live.dart')),
          reason: 'a citation resolving to a real heading must stay silent.'
              '\n${r.out}');
    });

    test(
        'flags a dead SUBSECTION of a live section — the case OI-91\'s survey '
        'grep is blind to', () {
      // `## 3.` exists but has no subsections, so `§3.1` is dead. OI-91's
      // filter excluded anything starting `§3`, so it never saw this class.
      // The gate validates against REAL headings and catches it for free.
      // Live instance at filing time: lib/core/utils/ist_date.dart:4.
      writeStandardRoot();
      writeCode('lib/sub.dart', '// dates per CLAUDE.md \u00A73.1\n');
      final r = runGate();
      expect(r.out, contains('lib/sub.dart:1'),
          reason: 'a citation to a nonexistent subsection of a REAL section '
              'must be caught. This is strictly more than the survey grep '
              'that produced OI-91\'s count could see.\n${r.out}');
    });
  });
}
