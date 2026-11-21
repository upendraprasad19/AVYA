// Tests for scripts/batch_close_lib.dart — the Stop-hook §5 close-out predicate.
//
// The SILENCERS matter more than the block. A Stop hook that blocks when it
// should not wedges every session, and one that ignores `stop_hook_active` loops
// forever. Those five paths are tested first and individually, so a future edit
// that reorders them cannot silently remove one.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/batch_close_lib.dart';

final _t0 = DateTime(2026, 8, 25, 9, 0);
final _t1 = DateTime(2026, 8, 25, 11, 0);

BatchCloseInputs _inputs({
  int unpushed = 3,
  String? head = 'abc123',
  String? lastReported,
  bool stopActive = false,
  bool kill = false,
  DateTime? retrospective,
  DateTime? oldest,
  List<String> reviews = const [],
  bool hasFix = false,
}) =>
    BatchCloseInputs(
      unpushedCommits: unpushed,
      headSha: head,
      lastReportedSha: lastReported,
      stopHookActive: stopActive,
      killSwitch: kill,
      newestRetrospective: retrospective,
      oldestUnpushedAt: oldest,
      reviewsAdded: reviews,
      hasBugfixCommit: hasFix,
    );

void main() {
  group('silencers — each tested alone', () {
    test('stop_hook_active NEVER blocks (infinite-loop guard)', () {
      final v = evaluateBatchClose(_inputs(stopActive: true));
      expect(v.shouldBlock, isFalse,
          reason: 'blocking on Stop re-triggers Stop; ignoring this flag is an '
              'infinite loop that wedges the session');
      expect(v.rows, isEmpty);
    });

    test('kill switch never blocks', () {
      expect(evaluateBatchClose(_inputs(kill: true)).shouldBlock, isFalse);
    });

    test('no unpushed commits never blocks — the common case', () {
      expect(evaluateBatchClose(_inputs(unpushed: 0)).shouldBlock, isFalse);
    });

    test('git unavailable fails OPEN', () {
      expect(evaluateBatchClose(_inputs(head: null)).shouldBlock, isFalse);
    });

    test('already reported for this HEAD never blocks again', () {
      final v = evaluateBatchClose(
          _inputs(head: 'abc123', lastReported: 'abc123'));
      expect(v.shouldBlock, isFalse,
          reason: 'bounded to one interruption per HEAD, not one per turn');
    });

    test('a DIFFERENT HEAD does block — new commits are a new batch state', () {
      final v =
          evaluateBatchClose(_inputs(head: 'def456', lastReported: 'abc123'));
      expect(v.shouldBlock, isTrue);
    });
  });

  group('the checklist it hands back', () {
    test('blocks with rows when a batch has landed', () {
      final v = evaluateBatchClose(_inputs());
      expect(v.shouldBlock, isTrue);
      final findings = v.rows;
      expect(findings, isNotEmpty);
      expect(v.reason, contains('3 unpushed'));
    });

    test('a retrospective NEWER than the batch marks that row satisfied', () {
      final v = evaluateBatchClose(
          _inputs(oldest: _t0, retrospective: _t1));
      final row = v.rows.firstWhere((r) => r.label.startsWith('project_'));
      expect(row.satisfied, isTrue);
    });

    test('a retrospective OLDER than the batch marks it UNsatisfied', () {
      final v = evaluateBatchClose(
          _inputs(oldest: _t1, retrospective: _t0));
      final row = v.rows.firstWhere((r) => r.label.startsWith('project_'));
      expect(row.satisfied, isFalse);
      expect(row.detail, contains('NO retrospective'));
    });

    test('an unlocatable memory dir is UNVERIFIED, never satisfied', () {
      // The bad-news-vs-no-news distinction: "could not check" must not render
      // the same as "checked and clean". null is the third state.
      final v = evaluateBatchClose(_inputs(oldest: _t0, retrospective: null));
      final row = v.rows.firstWhere((r) => r.label.startsWith('project_'));
      expect(row.satisfied, isNull);
      expect(row.satisfied, isNot(true));
      expect(row.detail, contains('UNVERIFIED'));
    });

    test('a fix commit adds the feedback_*.md row; a chore commit does not', () {
      final withFix = evaluateBatchClose(_inputs(hasFix: true));
      final withoutFix = evaluateBatchClose(_inputs(hasFix: false));
      expect(withFix.rows.where((r) => r.label.startsWith('feedback_')),
          hasLength(1));
      expect(withoutFix.rows.where((r) => r.label.startsWith('feedback_')),
          isEmpty);
    });

    test('rows a script CANNOT determine are present and marked UNVERIFIED', () {
      // These exist precisely because no gate can answer them. If a future edit
      // drops them for being "unverifiable", the checklist stops covering the
      // rows that decayed in the first place.
      final v = evaluateBatchClose(_inputs());
      final claudeMd =
          v.rows.firstWhere((r) => r.label.contains('CLAUDE.md'));
      final worktree =
          v.rows.firstWhere((r) => r.label.contains('Worktree retirement'));
      final scope = v.rows.firstWhere((r) => r.label.contains('Full-suite'));
      expect(claudeMd.satisfied, isNull);
      expect(worktree.satisfied, isNull);
      expect(scope.satisfied, isNull);
    });
  });

  group('renderBlockReason', () {
    test('marks the three states distinguishably', () {
      final v = evaluateBatchClose(_inputs(oldest: _t0, retrospective: _t1));
      final text = renderBlockReason(v);
      expect(text, contains('[x]'), reason: 'satisfied');
      expect(text, contains('[?]'), reason: 'unverified');
      expect(text, contains('§5'));
      expect(text, contains('.claude/.batch_close.disabled'),
          reason: 'the kill switch must be discoverable from the message itself');
    });

    test('an unsatisfied row renders as [ ], distinct from [?]', () {
      final v = evaluateBatchClose(_inputs(oldest: _t1, retrospective: _t0));
      final text = renderBlockReason(v);
      expect(text, contains('[ ] project_'));
    });
  });

  // ── The two bugs round 1 proved were NOT pinned, despite a claim that they
  // were. Both were inline in the hook and therefore unreachable by any test.
  // Extracting them was the real fix; these are the guard.
  group('primaryRootFrom — must use --git-common-dir, never --show-toplevel', () {
    test('strips the /.git suffix to give the PRIMARY root', () {
      expect(
        primaryRootFrom('C:/Upendra/Claude Code/Fitness App/.git'),
        'C:/Upendra/Claude Code/Fitness App',
      );
    });

    test('THE REGRESSION: a --show-toplevel style path yields null, not a root',
        () {
      // --show-toplevel in a linked worktree returns the WORKTREE path with no
      // `/.git` in it. If a future edit swaps the git flag back, this is what
      // catches it: the parse cannot find `/.git` and returns null, which the
      // caller renders UNVERIFIED rather than silently deriving a wrong dir.
      expect(
        primaryRootFrom(
            'C:/Upendra/Claude Code/Fitness App/.claude/worktrees/some-slug'),
        isNull,
      );
    });

    test('a linked worktree common-dir still resolves to the PRIMARY root', () {
      expect(
        primaryRootFrom('C:/Upendra/Claude Code/Fitness App/.git'),
        isNot(contains('worktrees')),
      );
    });

    test('normalises backslashes', () {
      // Built by char code so no editing layer can eat the escape - four
      // scripted edits in this session silently emptied or mangled a
      // backslash pattern, one of which shipped and broke this function.
      final bs = String.fromCharCode(92);
      expect(primaryRootFrom('C:${bs}repo$bs.git'), 'C:/repo');
    });

    test('null / empty / no-.git all yield null', () {
      expect(primaryRootFrom(null), isNull);
      expect(primaryRootFrom('   '), isNull);
      expect(primaryRootFrom('/no/git/here'), isNull);
    });
  });

  group('mangleProjectPath — the harness directory name', () {
    test('matches the real observed harness directory', () {
      expect(
        mangleProjectPath('C:/Upendra/Claude Code/Fitness App'),
        'C--Upendra-Claude-Code-Fitness-App',
      );
    });

    test('THE REGRESSION: the double dash after the drive colon is PRESERVED',
        () {
      // A `-+` collapse yields `C-Upendra-...`, which does not exist, so the
      // lookup returns null and every batch reports UNVERIFIED. The code comment
      // warns against it; this is what makes the warning enforceable.
      final m = mangleProjectPath('C:/Upendra/x');
      expect(m, startsWith('C--'));
      expect(m, isNot(startsWith('C-U')));
    });

    test('spaces and separators each become one dash', () {
      expect(mangleProjectPath('/home/u/my repo'), '-home-u-my-repo');
    });
  });

  // ── chooseRange: the P0 the B-pass found live. origin/main..HEAD alone pulled
  // in THREE unrelated unpushed batches, contaminating every derived row.
  group('chooseRange — must not measure a batch against a stale mainline', () {
    test('THE REGRESSION: local main ahead of origin/main uses main..HEAD', () {
      // The live state when this was found: origin/main..HEAD = 9, main..HEAD = 2.
      // The wide range picked up another batch's review file and fix commits and
      // reported three rows green on somebody else's evidence.
      expect(
        chooseRange(
            mainExists: true, commitsNotInMain: 2, originMainExists: true),
        'main..HEAD',
      );
    });

    test('on main after a merge (nothing beyond main) falls to origin/main', () {
      expect(
        chooseRange(
            mainExists: true, commitsNotInMain: 0, originMainExists: true),
        'origin/main..HEAD',
      );
    });

    test('no main ref at all still works off origin/main', () {
      expect(
        chooseRange(
            mainExists: false, commitsNotInMain: 0, originMainExists: true),
        'origin/main..HEAD',
      );
    });

    test('neither ref resolvable -> null, meaning UNKNOWN', () {
      expect(
        chooseRange(
            mainExists: false, commitsNotInMain: 0, originMainExists: false),
        isNull,
      );
    });

    test('DELIBERATE: an unknown range makes the hook SILENT, not blocking', () {
      // A fresh clone with no mainline has nothing to measure a batch against,
      // and a hook that blocked every turn there would be worse than one that
      // says nothing. The hook maps a null range to unpushedCommits: 0. Pinned
      // so the behaviour stays deliberate rather than accidental — the doc
      // comment on _range() used to claim the opposite.
      expect(evaluateBatchClose(_inputs(unpushed: 0)).shouldBlock, isFalse);
    });
  });
}
