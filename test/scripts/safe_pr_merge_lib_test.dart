// test/scripts/safe_pr_merge_lib_test.dart
//
// Unit tests for the PURE decision core of scripts/safe_pr_merge.dart
// (scripts/safe_pr_merge_lib.dart): given a PR head's GitHub check-runs, may the
// PR be merged?  `main` has no required status checks, so this evaluator IS the
// control (OI-275). It must FAIL CLOSED, and its job names must match the real
// workflow.
//
// FIXTURE: test/scripts/fixtures/safe_pr_merge_pr96_check_runs.json is a TRIMMED
// copy of the real `gh api repos/upendraprasad19/AVYA/commits/691d826b/check-runs`
// response for PR #96's head (captured 2026-10-10): eight check-runs, including a
// third-party `Vercel Preview Comments` (app slug `vercel`) and two push-only jobs
// that are `skipped` on a pull_request run. A hand-written fixture would encode my
// assumptions about the shape; this encodes GitHub's.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/safe_pr_merge_lib.dart';

List<Map<String, dynamic>> _fixture() {
  final raw = File('test/scripts/fixtures/safe_pr_merge_pr96_check_runs.json').readAsStringSync();
  return parseCheckRuns(raw);
}

/// A copy of the fixture with the github-actions check named [name] replaced.
List<Map<String, dynamic>> _with(String name, {String? status, Object? conclusion = _keep}) {
  return _fixture().map((r) {
    if (r['name'] != name) return r;
    final c = Map<String, dynamic>.from(r);
    if (status != null) c['status'] = status;
    if (!identical(conclusion, _keep)) c['conclusion'] = conclusion;
    return c;
  }).toList();
}

const Object _keep = Object();

Map<String, dynamic> _run(int id, String name,
        {String status = 'completed', String? conclusion = 'success', String slug = 'github-actions'}) =>
    {
      'id': id,
      'name': name,
      'status': status,
      'conclusion': conclusion,
      'app': {'slug': slug},
    };

void main() {
  group('the real PR #96 fixture', () {
    test('parses to 8 check-runs including the third-party one', () {
      final runs = _fixture();
      expect(runs.length, 8);
      expect(runs.map((r) => (r['app'] as Map)['slug']).toSet(), {'github-actions', 'vercel'});
    });

    test('is mergeable: required jobs success, push-only jobs skipped, Vercel ignored', () {
      final d = evaluateCheckRuns(_fixture());
      expect(d.ok, isTrue, reason: d.reasons.join('; '));
    });
  });

  group('every REQUIRED job is load-bearing', () {
    for (final job in requiredSuccessJobs) {
      test('"$job" failed -> refuse, naming the job', () {
        final d = evaluateCheckRuns(_with(job, conclusion: 'failure'));
        expect(d.ok, isFalse);
        expect(d.reasons.join(' '), contains('"$job"'));
      });
      test('"$job" still running -> refuse', () {
        final d = evaluateCheckRuns(_with(job, status: 'in_progress', conclusion: null));
        expect(d.ok, isFalse);
        expect(d.reasons.join(' '), contains('not finished'));
      });
      test('"$job" skipped -> refuse (skipped is only allowed for push-only jobs)', () {
        expect(evaluateCheckRuns(_with(job, conclusion: 'skipped')).ok, isFalse);
      });
      test('"$job" with ANY non-success conclusion -> refuse (the predicate is "!= success")', () {
        // Pins `!= 'success'` against a weaker `== 'failure' || == 'skipped'`, which
        // would wave through a timed-out / action-required / stale job.
        for (final c in ['timed_out', 'action_required', 'startup_failure', 'stale', 'neutral']) {
          final d = evaluateCheckRuns(_with(job, conclusion: c));
          expect(d.ok, isFalse, reason: '"$job" concluded $c must refuse');
          expect(d.reasons.join(' '), contains('concluded $c'));
        }
      });
      test('"$job" missing -> refuse', () {
        final d = evaluateCheckRuns(_fixture().where((r) => r['name'] != job).toList());
        expect(d.ok, isFalse);
        expect(d.reasons.join(' '), contains('"$job" has no check-run'));
      });
    }
  });

  group('push-only jobs', () {
    for (final job in skippedOkJobs) {
      test('"$job" skipped or success is fine; failed or running refuses; missing is tolerated', () {
        expect(evaluateCheckRuns(_with(job, conclusion: 'skipped')).ok, isTrue);
        expect(evaluateCheckRuns(_with(job, conclusion: 'success')).ok, isTrue);
        expect(evaluateCheckRuns(_with(job, conclusion: 'failure')).ok, isFalse);
        expect(evaluateCheckRuns(_with(job, status: 'in_progress', conclusion: null)).ok, isFalse);
        expect(evaluateCheckRuns(_fixture().where((r) => r['name'] != job).toList()).ok, isTrue);
      });
    }
  });

  group('fail closed on anything unreadable', () {
    test('null (the lookup failed) refuses', () {
      final d = evaluateCheckRuns(null);
      expect(d.ok, isFalse);
      expect(d.reasons.join(' '), contains('unknown is not green'));
    });
    test('no check-runs at all refuses', () => expect(evaluateCheckRuns([]).ok, isFalse));
    test('only third-party check-runs refuse (no GitHub Actions run exists)', () {
      expect(evaluateCheckRuns([_run(1, 'Vercel Preview Comments', slug: 'vercel')]).ok, isFalse);
    });
  });

  group('other checks are a floor, not a ceiling', () {
    test('an unknown github-actions check that FAILED refuses (a matrix shard, a new job)', () {
      final d = evaluateCheckRuns([..._fixture(), _run(99, 'Unit Tests shard 3/4', conclusion: 'failure')]);
      expect(d.ok, isFalse);
      expect(d.reasons.join(' '), contains('Unit Tests shard 3/4'));
    });
    test('an unknown github-actions check still RUNNING refuses', () {
      expect(
          evaluateCheckRuns([..._fixture(), _run(99, 'New job', status: 'queued', conclusion: null)]).ok,
          isFalse);
    });
    test('an unknown github-actions check that passed is fine', () {
      expect(evaluateCheckRuns([..._fixture(), _run(99, 'New job')]).ok, isTrue);
    });
    test('an unlisted job whose ONLY run was cancelled refuses (mirror of the required-job rule)', () {
      // A timed-out job is reported as cancelled; without this an unlisted shard
      // that timed out would be silently ignored.
      final d = evaluateCheckRuns(
          [..._fixture(), _run(99, 'Unit Tests shard 3/4', conclusion: 'cancelled')]);
      expect(d.ok, isFalse);
      expect(d.reasons.join(' '), contains('"Unit Tests shard 3/4" has only cancelled runs'));
    });
    test('an unlisted job cancelled once and then re-run to success is fine', () {
      expect(
          evaluateCheckRuns([
            ..._fixture(),
            _run(98, 'Unit Tests shard 3/4', conclusion: 'cancelled'),
            _run(99, 'Unit Tests shard 3/4'),
          ]).ok,
          isTrue);
    });
    test('a FAILED third-party check is ignored', () {
      expect(evaluateCheckRuns([..._fixture(), _run(99, 'Vercel', conclusion: 'failure', slug: 'vercel')]).ok,
          isTrue);
    });
  });

  group('re-runs: the latest non-cancelled run per name wins', () {
    test('old failure then newer success -> ok', () {
      final runs = _fixture().where((r) => r['name'] != 'Unit Tests').toList()
        ..add(_run(10, 'Unit Tests', conclusion: 'failure'))
        ..add(_run(11, 'Unit Tests'));
      expect(evaluateCheckRuns(runs).ok, isTrue);
    });
    test('old success then NEWER failure -> refuse (order of the list must not matter)', () {
      final base = _fixture().where((r) => r['name'] != 'Unit Tests').toList();
      final a = [...base, _run(10, 'Unit Tests'), _run(11, 'Unit Tests', conclusion: 'failure')];
      final b = [...base, _run(11, 'Unit Tests', conclusion: 'failure'), _run(10, 'Unit Tests')];
      expect(evaluateCheckRuns(a).ok, isFalse);
      expect(evaluateCheckRuns(b).ok, isFalse);
    });
    test('a cancelled newer run does not erase an older success', () {
      final runs = _fixture().where((r) => r['name'] != 'Unit Tests').toList()
        ..add(_run(10, 'Unit Tests'))
        ..add(_run(11, 'Unit Tests', conclusion: 'cancelled'));
      expect(evaluateCheckRuns(runs).ok, isTrue);
    });
    test('a job with ONLY a cancelled run is not a result -> refuse', () {
      final runs = _fixture().where((r) => r['name'] != 'Unit Tests').toList()
        ..add(_run(10, 'Unit Tests', conclusion: 'cancelled'));
      final d = evaluateCheckRuns(runs);
      expect(d.ok, isFalse);
      expect(d.reasons.join(' '), contains('only cancelled'));
    });
  });

  group('splitJsonValues / parseCheckRuns', () {
    test('two concatenated pages (what `gh api --paginate` prints) are both read', () {
      final p1 = jsonEncode({'total_count': 2, 'check_runs': [_run(1, 'Analyze')]});
      final p2 = jsonEncode({'total_count': 2, 'check_runs': [_run(2, 'Unit Tests')]});
      expect(parseCheckRuns('$p1$p2').map((r) => r['name']), ['Analyze', 'Unit Tests']);
      expect(parseCheckRuns('$p1\n$p2\n').length, 2);
    });
    test('braces and escaped quotes inside strings do not confuse the scanner', () {
      final tricky = jsonEncode({
        'check_runs': [_run(1, 'weird } name { with "quotes" \\ and ]')]
      });
      expect(parseCheckRuns('$tricky$tricky').length, 2);
      expect(parseCheckRuns(tricky).first['name'], 'weird } name { with "quotes" \\ and ]');
    });
    test('truncated input throws (the caller then refuses)', () {
      final p = jsonEncode({'check_runs': [_run(1, 'Analyze')]});
      expect(() => parseCheckRuns(p.substring(0, p.length - 3)), throwsFormatException);
    });
    test('empty input and a page without check_runs throw', () {
      expect(() => parseCheckRuns(''), throwsFormatException);
      expect(() => parseCheckRuns('{"message":"Not Found"}'), throwsFormatException);
    });
    test('an extra closing brace throws', () {
      expect(() => splitJsonValues('{"a":1}}'), throwsFormatException);
    });
    test('total_count that disagrees with the parsed runs throws (a dropped or duplicated page)', () {
      final one = jsonEncode({'total_count': 3, 'check_runs': [_run(1, 'Analyze')]});
      expect(() => parseCheckRuns(one), throwsFormatException);
      final dup = jsonEncode({'total_count': 1, 'check_runs': [_run(1, 'Analyze')]});
      expect(() => parseCheckRuns('$dup$dup'), throwsFormatException);
      expect(parseCheckRuns(dup).length, 1);
    });
  });

  group('parseChangedFiles', () {
    test('flattens paginated arrays and includes a rename\'s previous path', () {
      final p1 = jsonEncode([
        {'filename': 'lib/a.dart'},
        {'filename': 'lib/b.dart', 'previous_filename': '.github/workflows/old.yml'},
      ]);
      final p2 = jsonEncode([
        {'filename': 'docs/x.md'}
      ]);
      expect(parseChangedFiles('$p1$p2'), ['lib/a.dart', 'lib/b.dart', '.github/workflows/old.yml', 'docs/x.md']);
    });
    test('an entry without filename, a non-array page, or empty input throws', () {
      expect(() => parseChangedFiles('[{"sha":"x"}]'), throwsFormatException);
      expect(() => parseChangedFiles('{"message":"Not Found"}'), throwsFormatException);
      expect(() => parseChangedFiles(''), throwsFormatException);
    });
  });

  group('evaluateChangedFiles (the PR edits its own CI)', () {
    test('no .github/ path is fine', () {
      expect(evaluateChangedFiles(['lib/a.dart', 'docs/x.md'], allowWorkflowChange: false).ok, isTrue);
      expect(evaluateChangedFiles([], allowWorkflowChange: false).ok, isTrue);
    });
    test('a .github/ path refuses and names it, unless acknowledged', () {
      final files = ['lib/a.dart', '.github/workflows/test.yml'];
      final d = evaluateChangedFiles(files, allowWorkflowChange: false);
      expect(d.ok, isFalse);
      expect(d.reasons.join(' '), contains('.github/workflows/test.yml'));
      expect(d.reasons.join(' '), contains('--allow-workflow-change'));
      final a = evaluateChangedFiles(files, allowWorkflowChange: true);
      expect(a.ok, isTrue);
      expect(a.warnings.join(' '), contains('.github/workflows/test.yml'));
    });
    test('composite actions and other .github/ files count too; a lookalike path does not', () {
      expect(evaluateChangedFiles(['.github/actions/setup/action.yml'], allowWorkflowChange: false).ok, isFalse);
      expect(evaluateChangedFiles(['docs/.github/notes.md', 'github/x.yml'], allowWorkflowChange: false).ok, isTrue);
    });
    test('an unreadable list (null) refuses even when acknowledged', () {
      expect(evaluateChangedFiles(null, allowWorkflowChange: false).ok, isFalse);
      expect(evaluateChangedFiles(null, allowWorkflowChange: true).ok, isFalse);
    });
  });

  group('evaluatePr', () {
    final sha = 'a' * 40;
    Map<String, dynamic> pr({String state = 'OPEN', bool draft = false, String mergeable = 'MERGEABLE',
            String status = 'CLEAN', String? head, String base = 'main'}) =>
        {
          'state': state,
          'isDraft': draft,
          'mergeable': mergeable,
          'mergeStateStatus': status,
          'headRefOid': head ?? sha,
          'baseRefName': base,
        };

    test('a base of main or develop is ok; anything else is refused (CI does not run for it)', () {
      expect(evaluatePr(pr(base: 'main'), checkedSha: sha).ok, isTrue);
      expect(evaluatePr(pr(base: 'develop'), checkedSha: sha).ok, isTrue);
      final d = evaluatePr(pr(base: 'release/1'), checkedSha: sha);
      expect(d.ok, isFalse);
      expect(d.reasons.join(' '), contains('not main/develop'));
      expect(evaluatePr({...pr(), 'baseRefName': null}, checkedSha: sha).ok, isFalse);
    });

    test('an open, clean PR is ok', () => expect(evaluatePr(pr(), checkedSha: sha).ok, isTrue));
    test('MERGED / CLOSED refuse', () {
      expect(evaluatePr(pr(state: 'MERGED'), checkedSha: sha).ok, isFalse);
      expect(evaluatePr(pr(state: 'CLOSED'), checkedSha: sha).ok, isFalse);
    });
    test('a draft refuses', () => expect(evaluatePr(pr(draft: true), checkedSha: sha).ok, isFalse));
    test('conflicts refuse', () => expect(evaluatePr(pr(mergeable: 'CONFLICTING'), checkedSha: sha).ok, isFalse));
    test('UNKNOWN mergeability is not itself a refusal (GitHub computes it lazily)', () {
      expect(evaluatePr(pr(mergeable: 'UNKNOWN'), checkedSha: sha).ok, isTrue);
    });
    test('a head that moved while checking refuses', () {
      final d = evaluatePr(pr(head: 'b' * 40), checkedSha: sha);
      expect(d.ok, isFalse);
      expect(d.reasons.join(' '), contains('head moved'));
    });
    test('BEHIND main warns but does not refuse', () {
      final d = evaluatePr(pr(status: 'BEHIND'), checkedSha: sha);
      expect(d.ok, isTrue);
      expect(d.warnings, isNotEmpty);
    });
    test('null (unreadable PR) refuses', () => expect(evaluatePr(null, checkedSha: sha).ok, isFalse));
  });

  group('the job names are the REAL workflow job names', () {
    // Parse `name:` of every top-level job in .github/workflows/test.yml.
    Set<String> workflowJobNames() {
      final names = <String>{};
      for (final line in File('.github/workflows/test.yml').readAsLinesSync()) {
        final m = RegExp(r'^    name: (.+?)\s*$').firstMatch(line);
        if (m != null) names.add(m.group(1)!);
      }
      return names;
    }

    test('every name this evaluator relies on exists in test.yml', () {
      final names = workflowJobNames();
      for (final n in [...requiredSuccessJobs, ...skippedOkJobs]) {
        expect(names, contains(n),
            reason: 'safe_pr_merge_lib.dart names "$n" but .github/workflows/test.yml has no job '
                'with that name:. A renamed job would make every merge refuse (or, if the name '
                'were treated as optional, silently ignore a job).');
      }
    });

    test('MIRROR: every job in test.yml is classified here (a new job must be a conscious decision)', () {
      final classified = {...requiredSuccessJobs, ...skippedOkJobs};
      final unclassified = workflowJobNames().difference(classified);
      expect(unclassified, isEmpty,
          reason: 'test.yml has job(s) $unclassified that safe_pr_merge_lib.dart does not name. '
              'Add each to requiredSuccessJobs (must be green to merge) or skippedOkJobs '
              '(push-only). Unnamed jobs are still judged by the "other checks" rule, but a '
              'job that gates quality should be listed on purpose.');
    });
  });
}
