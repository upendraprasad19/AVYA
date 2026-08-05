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
}
