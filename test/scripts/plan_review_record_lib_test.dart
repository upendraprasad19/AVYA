// test/scripts/plan_review_record_lib_test.dart
//
// FIRST test coverage for the §4.12 keystone gate
// (scripts/check_plan_review_record_exists.dart). Until 2026-07-26 the repo's
// single structural enforcement point for plan quality had ZERO tests — nothing
// pinned the branch-recovery logic it depends on entirely.
//
// Drives the pure helpers directly rather than spawning a git repo: a test that
// creates its own repo, when run inside `pre-commit`, inherits GIT_DIR /
// GIT_WORK_TREE, which override BOTH `workingDirectory:` and `-C <path>`
// (feedback_mistake_git_hook_env_leak).

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/plan_review_record_lib.dart';

const _owner = 'upendraprasad19';

void main() {
  group('classifyMergeSubject — local --no-ff merge', () {
    test('plain branch merge', () {
      final r = classifyMergeSubject("Merge branch 'hold-display-fixes'",
          repoOwner: _owner);
      expect(r.kind, MergeSubjectKind.branchMerge);
      expect(r.branch, 'hold-display-fixes');
    });

    test('branch name containing a slash survives intact', () {
      final r =
          classifyMergeSubject("Merge branch 'feat/second'", repoOwner: _owner);
      expect(r.kind, MergeSubjectKind.branchMerge);
      expect(r.branch, 'feat/second',
          reason: 'the old .split("/").last would have yielded "second"');
    });

    test('trailing "into X" is tolerated', () {
      final r = classifyMergeSubject("Merge branch 'topic' into main",
          repoOwner: _owner);
      expect(r.kind, MergeSubjectKind.branchMerge);
      expect(r.branch, 'topic');
    });

    // REGRESSION (round-2 review P0-1). The first draft of this lib anchored the
    // branch regex with `$` and tolerated only ` into Y`. That rejected THIS
    // repo's dominant convention — `Merge branch 'X' — <description>`, 49 of the
    // 174 merges on main — and would have reddened main on the very next merge,
    // including this batch's own. The round-1 tests missed it because they only
    // ever exercised ` into Y`. These are verbatim subjects from git history.
    for (final subject in const [
      // 904e6961 — the batch immediately before this one.
      "Merge branch 'ci-speed' — never cancel a main run; unserialize the APK job and cache gradle",
      // 342820b3
      "Merge branch 'hold-display-fixes' — hold weeks must not print a stale week or tick a locked chip",
      // ASCII hyphen, to prove this is not an em-dash/encoding quirk.
      "Merge branch 'some-branch' - plain hyphen description",
      "Merge branch 'other' (parenthetical note)",
    ]) {
      test('REGRESSION: real history subject "${subject.substring(0, 34)}…"',
          () {
        final r = classifyMergeSubject(subject, repoOwner: _owner);
        expect(r.kind, MergeSubjectKind.branchMerge,
            reason: 'an end-anchored regex rejects every descriptive merge '
                'subject this repo actually writes');
        expect(r.branch, isNotNull);
        expect(r.branch, isNot(contains('—')),
            reason: 'the description must not leak into the branch name');
      });
    }
  });

  group('classifyMergeSubject — GitHub PR merge', () {
    test('own-owner PR is accepted and keeps the full slashed branch', () {
      final r = classifyMergeSubject(
          'Merge pull request #14 from $_owner/dependabot/pub/build_runner-2.15.0',
          repoOwner: _owner);
      expect(r.kind, MergeSubjectKind.pullRequestMerge);
      expect(r.branch, 'dependabot/pub/build_runner-2.15.0');
    });

    test('fork PR from a different owner is REJECTED', () {
      // The repo is public. A fork branch whose short name collides with an
      // approved record must never be treated as reviewed.
      final r = classifyMergeSubject(
          'Merge pull request #99 from attacker/hold-mechanic',
          repoOwner: _owner);
      expect(r.kind, MergeSubjectKind.foreignPullRequest);
      expect(r.owner, 'attacker');
    });

    test('fails closed when the owner cannot be determined', () {
      final r = classifyMergeSubject(
          'Merge pull request #7 from $_owner/feat/foo',
          repoOwner: null);
      expect(r.kind, MergeSubjectKind.foreignPullRequest,
          reason: 'an unverifiable owner must not be trusted');
    });

    test('the subject shape that reddens main today is now handled', () {
      // Real example already in this repo's history (7c973ee3, an ancestor of
      // main): the old `Merge branch 'X'`-only regex did not match this, so the
      // gate called die() and turned main red on a legitimate PR merge.
      final r = classifyMergeSubject(
          'Merge pull request #3 from $_owner/feat/exercise-selection-v4',
          repoOwner: _owner);
      expect(r.kind, MergeSubjectKind.pullRequestMerge);
      expect(r.branch, 'feat/exercise-selection-v4');
    });
  });

  group('classifyMergeSubject — git pull remote sync', () {
    test('"Merge branch \'main\' of <url>" is a sync, not a landing', () {
      // This DOES match the old regex, yielding branch="main" and demanding
      // docs/plan-reviews/main.md — a self-inflicted red for merely syncing.
      final r = classifyMergeSubject(
          "Merge branch 'main' of https://github.com/$_owner/AVYA",
          repoOwner: _owner);
      expect(r.kind, MergeSubjectKind.remoteSyncMerge);
    });

    test('checked before the plain branch form (ordering matters)', () {
      final r = classifyMergeSubject(
          "Merge branch 'topic' of git@github.com:$_owner/AVYA.git",
          repoOwner: _owner);
      expect(r.kind, MergeSubjectKind.remoteSyncMerge,
          reason: 'the plain-branch regex would also match this prefix');
    });

    // REGRESSION (round-2 review P1-2). The gate PASSES on this kind ONLY when
    // the synced branch is `main`. A non-main branch name here means
    // `git pull origin <feature>` while on main — a real feature landing — and
    // an unconditional pass made any subject ending `' of x'` a craftable
    // bypass that skipped the gate before blast-radius was even computed.
    // The lib still classifies it; the gate is what narrows it, so this test
    // pins the branch NAME the gate keys on.
    test('REGRESSION: a non-main sync is distinguishable from a main sync', () {
      final feature = classifyMergeSubject("Merge branch 'feature' of x",
          repoOwner: _owner);
      expect(feature.kind, MergeSubjectKind.remoteSyncMerge);
      expect(feature.branch, 'feature',
          reason: 'the gate passes only when this is exactly "main"');

      final real = classifyMergeSubject(
          "Merge branch 'main' of github.com:$_owner/AVYA", repoOwner: _owner);
      expect(real.branch, 'main');
    });
  });

  group('classifyMergeSubject — unrecognized', () {
    test('an ordinary commit subject is not a merge shape', () {
      final r = classifyMergeSubject('fix(ci): something', repoOwner: _owner);
      expect(r.kind, MergeSubjectKind.unrecognized);
      expect(r.branch, isNull);
    });

    // REGRESSION (B-pass 2026-07-26). Git ALLOWS a single quote inside a branch
    // name — `git check-ref-format --branch "short-name'z-x"` succeeds — so an
    // ORDINARY `--no-ff` merge of such a branch produces this subject with git's
    // own auto-generated text. A non-lookahead `'([^']+)'` truncates at the
    // embedded quote and silently resolves to the record for `short-name`: a
    // DIFFERENT branch, quite possibly an approved one. That is the accidental
    // twin of the slug collision this batch set out to close, and it must fail
    // loud rather than resolve to the wrong record.
    test('REGRESSION: a quote inside a branch name cannot truncate to another '
        "branch's record", () {
      final r = classifyMergeSubject("Merge branch 'short-name'z-x'",
          repoOwner: _owner);
      expect(r.kind, MergeSubjectKind.unrecognized,
          reason: 'truncating to "short-name" would resolve the WRONG record; '
              'an ambiguous subject must fail loud, not silently mis-resolve');
      expect(r.branch, isNot('short-name'));
    });

    test('the lookahead does not reject any legitimate shape', () {
      // Guard against over-correcting: every real form must still classify.
      expect(classifyMergeSubject("Merge branch 'x'", repoOwner: _owner).kind,
          MergeSubjectKind.branchMerge);
      expect(
          classifyMergeSubject("Merge branch 'x' — desc", repoOwner: _owner)
              .kind,
          MergeSubjectKind.branchMerge);
      expect(
          classifyMergeSubject("Merge branch 'x' into main", repoOwner: _owner)
              .kind,
          MergeSubjectKind.branchMerge);
      expect(
          classifyMergeSubject("Merge branch 'main' of url", repoOwner: _owner)
              .kind,
          MergeSubjectKind.remoteSyncMerge);
    });
  });

  group('recordSlug', () {
    test('flat branch names are unchanged (all 69 tracked records)', () {
      expect(recordSlug('hold-mechanic'), 'hold-mechanic');
      expect(recordSlug('ci-speed'), 'ci-speed');
    });

    test('strips a leading origin/ (the old split-last intent)', () {
      expect(recordSlug('origin/hold-mechanic'), 'hold-mechanic');
    });

    test('maps interior slashes to dashes instead of truncating', () {
      expect(recordSlug('feat/foo'), 'feat-foo');
      expect(recordSlug('dependabot/pub/build_runner-2.15.0'),
          'dependabot-pub-build_runner-2.15.0');
    });

    test('REGRESSION: feat/foo and fix/foo no longer collide', () {
      // The old `.split('/').last` mapped BOTH to `foo`, so one branch's
      // approved record satisfied the other branch's gate.
      expect(recordSlug('feat/foo'), isNot(recordSlug('fix/foo')));
    });
  });

  group('recordBranchFieldMatches — closes the residual slug collision', () {
    const holdMechanicRecord = '''
---
branch: hold-mechanic
blast_radius: platform
review_rounds: 2
verdict: converged
---
''';

    test('accepts the branch the record actually names', () {
      expect(recordBranchFieldMatches(holdMechanicRecord, 'hold-mechanic'),
          isTrue);
    });

    test('REGRESSION: hold/mechanic cannot ride hold-mechanic\'s review', () {
      // recordSlug('hold/mechanic') == 'hold-mechanic', an existing converged,
      // bpass-accepted record for unrelated work. The slug map is not
      // injective, so the record must vouch for the branch by name.
      expect(recordSlug('hold/mechanic'), 'hold-mechanic');
      expect(recordBranchFieldMatches(holdMechanicRecord, 'hold/mechanic'),
          isFalse);
    });

    test('a record with no branch: field vouches for nothing', () {
      expect(recordBranchFieldMatches('---\nverdict: converged\n---', 'x'),
          isFalse);
    });

    // REGRESSION (B-pass 2026-07-26). Scoped to frontmatter, so a record that
    // merely DISCUSSES another branch in its body cannot vouch for it.
    test('REGRESSION: a branch: line in the BODY does not vouch', () {
      const doc = '''
---
branch: real-branch
verdict: converged
---

# Notes

Compare with the earlier work, where:

    branch: impostor-branch

…which is quoted here purely as prose.
''';
      expect(recordBranchFieldMatches(doc, 'real-branch'), isTrue);
      expect(recordBranchFieldMatches(doc, 'impostor-branch'), isFalse,
          reason: 'only the frontmatter declares what this record reviewed');
    });

    test('falls back to whole-file scan when there is no frontmatter', () {
      expect(recordBranchFieldMatches('branch: loose\n', 'loose'), isTrue);
      expect(recordBranchFieldMatches('no fields here\n', 'loose'), isFalse);
    });
  });

  group('Dependabot exemption is content-verified, not name-trusted', () {
    test('branch detection runs on the RAW name, before slug mapping', () {
      expect(isDependabotBranch('dependabot/pub/foo-1.0.0'), isTrue);
      expect(isDependabotBranch(recordSlug('dependabot/pub/foo-1.0.0')), isFalse,
          reason: 'ordering matters: recordSlug() maps the slashes away');
    });

    test('a manifest-only diff qualifies', () {
      expect(dependabotDiffIsManifestOnly(['pubspec.yaml', 'pubspec.lock']),
          isTrue);
    });

    test('REGRESSION: a code file in the diff disqualifies it', () {
      expect(
          dependabotDiffIsManifestOnly(
              ['pubspec.yaml', 'lib/main.dart']),
          isFalse,
          reason: 'a spoofed dependabot/* branch must not smuggle code in');
    });

    test('REGRESSION: workflow edits are NOT exempt', () {
      // Letting a bot rewrite the CI that enforces every other gate would
      // contradict promoting test.yml to platform tier. actions/checkout in
      // particular supplies fetch-depth: 0 to the keystone gate's own job.
      expect(
          dependabotDiffIsManifestOnly(['.github/workflows/test.yml']), isFalse);
    });

    test('an empty diff does not qualify', () {
      expect(dependabotDiffIsManifestOnly([]), isFalse);
      expect(dependabotDiffIsManifestOnly(['  ']), isFalse);
    });

    test('author check accepts real Dependabot identities', () {
      expect(
          allCommitsAuthoredByDependabot(
              ['49699333+dependabot[bot]@users.noreply.github.com']),
          isTrue);
      expect(allCommitsAuthoredByDependabot(['support@dependabot.com']), isTrue);
    });

    test('REGRESSION: a human commit on a dependabot-named branch fails', () {
      expect(
          allCommitsAuthoredByDependabot([
            '49699333+dependabot[bot]@users.noreply.github.com',
            'attacker@example.com',
          ]),
          isFalse,
          reason: 'anyone with push access can name a branch dependabot/x');
    });

    test('no authors at all does not qualify', () {
      expect(allCommitsAuthoredByDependabot([]), isFalse);
    });
  });
}
