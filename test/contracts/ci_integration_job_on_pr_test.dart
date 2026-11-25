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
    out[m.group(1)!] = m.group(2)!;
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
    } else if (RegExp('group:\\s*${RegExp.escape(group)}\\s*\$', multiLine: true).allMatches(workflow).length != 1) {
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
  final failAt = text.indexOf(RegExp(r'if \[ -n "\$MISSING" \] && \[ "\$GITHUB_EVENT_NAME" = "pull_request" \]; then\n(?:.*\n)*?\s+exit 1\n\s+elif \[ -n "\$MISSING" \]; then'));
  final firstTestStep = text.indexOf('flutter test ');
  if (failAt < 0 || firstTestStep < 0 || failAt > firstTestStep) {
    problems.add('[secrets] the announce step does not `exit 1` on a pull request with a missing secret');
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
      'the job renamed': ('[name]', sub('    name: $jobName\n', '    name: Supabase Tests\n')),
    };
    for (final e in mutants.entries) {
      test(e.key, () {
        final p = problems(e.value.$2);
        expect(p.where((x) => x.startsWith(e.value.$1)), isNotEmpty, reason: 'got: $p');
      });
    }

    test('a second job in the same group', () {
      final wf = '$workflow\n  other-job:\n    concurrency:\n      group: supabase-integration-shared-qa-account\n';
      expect(problems(wf).single, startsWith('[group]'));
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
