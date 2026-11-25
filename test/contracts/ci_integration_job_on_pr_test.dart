// OI-527. The integration job (`Supabase Integration Tests`) ran only on a push to main, so a break was found
// after the merge (PR #328: main red for 14 hours across six merges). It now runs on every pull request of this
// repository, one job at a time across ALL pull requests and main, because every step signs in as one shared QA
// account and deletes its rows. Plan: docs/plans/2026-11-25-ci-integration-on-pr.md.
//
// This file pins the five properties that make that safe, in the workflow text and in the merge wrapper's lists.
// The judgement itself (missing / cancelled / skipped) is tested in test/scripts/safe_pr_merge_lib_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/safe_pr_merge_lib.dart';

const jobKey = 'supabase-tests';
const jobName = 'Supabase Integration Tests';

/// The only step-level `if:` the job may carry: the four-secret guard of its two test steps.
const stepGuard = "if: env.SUPABASE_URL != '' && env.SUPABASE_ANON_KEY != '' && env.SUPABASE_TEST_EMAIL != '' && "
    "env.SUPABASE_TEST_PASSWORD != ''";

const secretNames = ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_TEST_EMAIL', 'SUPABASE_TEST_PASSWORD'];

/// The one `if:` the job may carry (single spaces).
const wantedIf = "(github.event_name == 'push' && github.ref == 'refs/heads/main') || "
    "(github.event_name == 'pull_request' && github.actor != 'dependabot[bot]' && "
    'github.event.pull_request.head.repo.full_name == github.repository)';

/// The lines of top-level job [key] (indent 2), comment-only lines dropped; empty when absent.
List<String> jobBlock(String workflow, String key) {
  final out = <String>[];
  var inside = false;
  for (final line in workflow.split(RegExp(r'\r\n|\r|\n'))) {
    if (RegExp(r'^  [A-Za-z0-9_-]+:\s*$').hasMatch(line)) {
      inside = line == '  $key:';
      continue;
    }
    if (inside && RegExp(r'^\S').hasMatch(line)) inside = false;
    if (inside && !line.trimLeft().startsWith('#')) out.add(line);
  }
  return out;
}

String _uncommented(String workflow) => [
      for (final l in workflow.split(RegExp(r'\r\n|\r|\n')))
        if (!l.trimLeft().startsWith('#')) l,
    ].join('\n');

/// The value of the job-level scalar `    <name>: value` (indent 4), or null.
String? _scalar(List<String> block, String name) {
  final hits = [
    for (final l in block)
      if (l.startsWith('    $name:')) l.substring('    $name:'.length).trim(),
  ];
  return hits.length == 1 ? hits.single : null;
}

/// The `key: value` pairs directly under the job-level `concurrency:` (indent 6); null when there is no such map.
Map<String, String>? _concurrency(List<String> block) {
  final at = block.indexOf('    concurrency:');
  if (at < 0) return null;
  final out = <String, String>{};
  for (final l in block.skip(at + 1)) {
    final m = RegExp(r'^      ([a-z-]+):\s*(.*?)\s*$').firstMatch(l);
    if (m == null) break;
    // A repeated key is reported under its own name, so the caller refuses it (B-pass finding 2).
    final key = out.containsKey(m.group(1)!) ? 'duplicate ${m.group(1)!}' : m.group(1)!;
    out[key] = m.group(2)!;
  }
  return out;
}

/// Every problem with the integration job; empty when it is as the plan says.
List<String> integrationJobProblems(
  String workflow, {
  required List<String> required,
  required List<String> pushOnly,
  required List<String> prTime,
}) {
  final problems = <String>[];
  final block = jobBlock(workflow, jobKey);
  if (block.isEmpty) return ['[job] no top-level job `$jobKey`'];
  if (_scalar(block, 'name') != jobName) problems.add('[name] the job is not named "$jobName"');

  final cond = _scalar(block, 'if')?.replaceAll(RegExp(r'\s+'), ' ');
  if (cond != wantedIf) problems.add('[if] the job-level `if:` is not the pinned expression: $cond');

  final c = _concurrency(block);
  if (c == null) {
    problems.add('[concurrency] no job-level `concurrency:` map');
  } else {
    final group = c['group'] ?? '';
    if (group.isEmpty || group.contains(r'${{') || group.contains(r'$')) {
      problems.add('[group] the group must be ONE literal shared by every pull request and main: "$group"');
    } else if (group.allMatches(_uncommented(workflow)).length != 1) {
      // Counted as plain text, so a quoted spelling in another job is seen too (B-pass finding 2).
      problems.add('[group] "$group" is used by more than one job');
    }
    if (c['cancel-in-progress'] != 'false') problems.add('[cancel] `cancel-in-progress` must be the literal false');
    if (c['queue'] != 'max') problems.add('[queue] `queue` must be max (the default cancels the waiting job)');
    if (c.keys.toSet().difference({'group', 'cancel-in-progress', 'queue'}).isNotEmpty) {
      problems.add('[concurrency] unexpected key(s): ${c.keys.toList()}');
    }
  }

  // The announce step must FAIL on a pull request with a missing secret, before the guarded test steps.
  final text = block.join('\n');
  // Line for line (comment lines are already gone): the branch, its one message, `exit 1`, the old warning branch.
  final failAt = text.indexOf(RegExp(r'\n +if \[ -n "\$MISSING" \] && \[ "\$GITHUB_EVENT_NAME" = "pull_request" \]; then\n'
      r' +echo "::error [^\n]*\n +exit 1\n +elif \[ -n "\$MISSING" \]; then\n'));
  final firstTestStep = text.indexOf('flutter test ');
  if (failAt < 0 || firstTestStep < 0 || failAt > firstTestStep) {
    problems.add('[secrets] the announce step does not `exit 1` on a pull request with a missing secret');
  }

  // A job that gates merges must not be able to pass with a failing test (B-pass finding 1).
  if (text.contains('continue-on-error')) problems.add('[soft] `continue-on-error` in the job');
  final ors = [
    for (final l in block)
      if (l.contains('||') && !l.startsWith('    if:')) l.trim(),
  ];
  if (ors.isNotEmpty) problems.add('[soft] a `||` outside the job-level `if:` can swallow a failure: $ors');
  final stepIfs = [
    for (final l in block)
      if (RegExp(r'^ {6,}(- )?if:').hasMatch(l)) l.trim().replaceFirst(RegExp(r'^- '), ''),
  ];
  if (stepIfs.length != 2 || stepIfs.any((s) => s != stepGuard)) {
    problems.add('[steps] the only step-level `if:` allowed is the four-secret guard, on the two test steps: $stepIfs');
  }
  if ('flutter test '.allMatches(text).length != 2 ||
      !text.contains('flutter test test/supabase/ ') ||
      !text.contains('flutter test test/edge_functions/ ')) {
    problems.add('[steps] the job must run exactly `flutter test test/supabase/` and `flutter test test/edge_functions/`');
  }
  for (final s in secretNames) {
    if (!block.contains('      $s: \${{ secrets.$s }}')) problems.add('[env] $s is not mapped from secrets.$s');
  }

  if (!prTime.contains(jobName)) problems.add('[lists] "$jobName" is not in prTimeSkippableJobs');
  if (pushOnly.contains(jobName)) problems.add('[lists] "$jobName" is in skippedOkJobs (a missing run would be tolerated)');
  if (required.contains(jobName)) problems.add('[lists] "$jobName" is in requiredSuccessJobs (a Dependabot skip would refuse)');
  return problems;
}

void main() {
  final workflow = File('.github/workflows/test.yml').readAsStringSync();
  List<String> problems(String wf, {List<String>? required, List<String>? pushOnly, List<String>? prTime}) =>
      integrationJobProblems(wf,
          required: required ?? requiredSuccessJobs,
          pushOnly: pushOnly ?? skippedOkJobs,
          prTime: prTime ?? prTimeSkippableJobs);

  test('the real workflow and the real lists are as planned', () {
    expect(problems(workflow), isEmpty);
  });

  group('each property is load-bearing', () {
    String sub(String from, String to) {
      // Runs while the group is being declared, where neither expect nor a throw is usable (a throw would fail
      // the whole file to LOAD and hide which property broke). A missing anchor yields a text with no job, so
      // that mutant's own test fails with `[job]` and names itself.
      if (from.allMatches(workflow).length != 1) return 'mutation anchor not found exactly once: $from';
      return workflow.replaceFirst(from, to);
    }

    const ifLine = '    if: $wantedIf\n';
    final mutants = <String, (String token, String wf)>{
      'push-only again': ('[if]', sub(ifLine, "    if: github.event_name == 'push' && github.ref == 'refs/heads/main'\n")),
      'pull requests only (main lost)': (
        '[if]',
        sub("(github.event_name == 'push' && github.ref == 'refs/heads/main') || (github.event_name == 'pull_request'",
            "(github.event_name == 'pull_request'")
      ),
      'Dependabot not excluded': ('[if]', sub(" && github.actor != 'dependabot[bot]'", '')),
      'the PR author instead of the actor': (
        '[if]',
        sub("github.actor != 'dependabot[bot]'", "github.event.pull_request.user.login != 'dependabot[bot]'")
      ),
      'forks not excluded': ('[if]', sub(' && github.event.pull_request.head.repo.full_name == github.repository', '')),
      'no if at all': ('[if]', sub(ifLine, '')),
      'no concurrency': (
        '[concurrency]',
        sub('    concurrency:\n      group: supabase-integration-shared-qa-account\n      cancel-in-progress: false\n      queue: max\n', '')
      ),
      'a group per ref': (
        '[group]',
        sub('      group: supabase-integration-shared-qa-account\n', '      group: supabase-\${{ github.ref }}\n')
      ),
      'cancel in progress': (
        '[cancel]',
        sub('      group: supabase-integration-shared-qa-account\n      cancel-in-progress: false\n',
            '      group: supabase-integration-shared-qa-account\n      cancel-in-progress: true\n')
      ),
      'cancel in progress dropped': (
        '[cancel]',
        sub('      group: supabase-integration-shared-qa-account\n      cancel-in-progress: false\n',
            '      group: supabase-integration-shared-qa-account\n')
      ),
      'the default queue': ('[queue]', sub('      queue: max\n', '')),
      'queue single': ('[queue]', sub('      queue: max\n', '      queue: single\n')),
      'missing secrets only warn on a pull request': (
        '[secrets]',
        sub('            exit 1\n          elif [ -n "\$MISSING" ]; then', '          elif [ -n "\$MISSING" ]; then')
      ),
      'the pull-request branch is gone': (
        '[secrets]',
        sub('if [ -n "\$MISSING" ] && [ "\$GITHUB_EVENT_NAME" = "pull_request" ]; then', 'if false; then')
      ),
      'a duplicate queue key (the last one would win)': (
        '[concurrency]',
        sub('      queue: max\n', '      queue: single\n      queue: max\n')
      ),
      'the test step may fail softly': (
        '[soft]',
        sub('      - name: Run Supabase tests\n', '      - name: Run Supabase tests\n        continue-on-error: true\n')
      ),
      'the job may fail softly': ('[soft]', sub('    timeout-minutes: 15\n    if: (', '    continue-on-error: true\n    timeout-minutes: 15\n    if: (')),
      'a swallowed test failure': ('[soft]', sub('          flutter test test/supabase/ \\\n', '          true || flutter test test/supabase/ \\\n')),
      'the announce step disabled': (
        '[steps]',
        sub('      - name: Announce whether this job verifies anything\n', '      - name: Announce whether this job verifies anything\n        if: false\n')
      ),
      'a test step no longer runs the tests': ('[steps]', sub('          flutter test test/edge_functions/ \\\n', '          echo test/edge_functions/ \\\n')),
      'a secret no longer mapped': ('[env]', sub('      SUPABASE_TEST_PASSWORD: \${{ secrets.SUPABASE_TEST_PASSWORD }}\n', "      SUPABASE_TEST_PASSWORD: ''\n")),
      'exit 1 behind another branch': (
        '[secrets]',
        sub('            exit 1\n          elif [ -n "\$MISSING" ]; then', '            true\n          elif false; then\n            exit 1\n          elif [ -n "\$MISSING" ]; then')
      ),
      'the job renamed': ('[name]', sub('    name: $jobName\n', '    name: Supabase Tests\n')),
    };
    for (final e in mutants.entries) {
      test(e.key, () {
        final p = problems(e.value.$2);
        expect(p.where((x) => x.startsWith(e.value.$1)), isNotEmpty, reason: 'got: $p');
      });
    }

    test('a second job in the same group', () {
      for (final g in ['supabase-integration-shared-qa-account', '"supabase-integration-shared-qa-account"']) {
        final wf = '$workflow\n  other-job:\n    concurrency:\n      group: $g\n';
        expect(problems(wf).single, startsWith('[group]'), reason: g);
      }
    });
    test('the job removed', () {
      expect(problems(workflow.replaceFirst('  $jobKey:\n', '  supabase-tests-old:\n')).single, startsWith('[job]'));
    });
    test('the lists', () {
      expect(problems(workflow, prTime: const []).single, contains('not in prTimeSkippableJobs'));
      expect(problems(workflow, pushOnly: const [jobName]).single, contains('is in skippedOkJobs'));
      expect(problems(workflow, required: const [jobName]).single, contains('is in requiredSuccessJobs'));
    });
    test('a commented-out line is not read as the setting', () {
      final wf = sub('      queue: max\n', '      # queue: max\n');
      expect(problems(wf).where((x) => x.startsWith('[queue]')), isNotEmpty);
    });
  });
}
