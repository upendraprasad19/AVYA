// test/contracts/build_apk_bump_flow_test.dart
//
// OI-275 batch B2 (U2/U3): `.claude/commands/build-apk.md` Gate 2 tells the agent how to land a
// versionCode bump - ONE commit through a PR - and lists the steps a classifier can block. A
// document is only worth a test when a stale instruction in it costs real time: the old text
// said "commit on main", which makes the push run the ~39-minute local suite, and the first
// version of this flow named steps in an order that cannot work (merge before the PR exists).
//
// Three kinds of assertion, all honest about being text checks (feedback_source_grep_false_confidence):
//   ORDER      the steps appear in the only order that can work;
//   EXISTENCE  every script / flag the section names is a real thing in the repo, so the
//              document cannot drift away from the tooling it tells the agent to run;
//   MIRROR     `.opencode/command/build-apk.md` carries the same body, so the other tool is not
//              told to follow a flow this file has retired.
// What a text check cannot prove (that the sequence WORKS end to end) is proved elsewhere:
// the merge exemption by test/scripts/gate_input_family_e2e_test.dart (group U1b), the wrapper
// by test/scripts/safe_pr_merge_*_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String section;

  setUpAll(() {
    final md = File('.claude/commands/build-apk.md').readAsStringSync().replaceAll('\r\n', '\n');
    final start = md.indexOf('### Gate 2 —');
    final end = md.indexOf('### Gate 2.5');
    expect(start, greaterThan(-1), reason: 'Gate 2 heading must exist');
    expect(end, greaterThan(start), reason: 'Gate 2.5 heading must follow Gate 2');
    section = md.substring(start, end);
  });

  test('the bump is ONE commit through a PR, in the only order that can work', () {
    final order = <String>[
      'scripts/new-worktree.sh', //  1. a worktree first (CLAUDE.md §4.13)
      'app_constants.dart', //       2. BOTH files edited
      'scripts/safe_commit.sh', //   3. ONE commit
      'scripts/safe_push.sh', //     4. ONE push
      'gh pr create', //             5. a PR can exist only after the push
      'scripts/safe_pr_merge.sh', // 6. merge only after CI is green
      'git merge --ff-only origin/main', // 7. then catch the primary up
      '--from-green', //             8. which --from-green requires
    ];
    var at = 0;
    for (final needle in order) {
      final idx = section.indexOf(needle, at);
      expect(idx, greaterThanOrEqualTo(at),
          reason: '"$needle" must appear in Gate 2, after the previous step; the sequence is only '
              'valid in this order (a merge before the PR/CI, or a push before the commit, fails)');
      at = idx;
    }
  });

  test('says the bump must be ONE commit touching ONLY the two version files', () {
    expect(section, contains('ONE commit'));
    expect(section, contains('Touch NOTHING else'),
        reason: 'a third file silently turns a bare bump into a change that needs a plan-review '
            'record and B-pass (the exemption is all-or-nothing)');
    expect(section, contains('pubspec.yaml'));
    expect(section, contains('lib/core/constants/app_constants.dart'));
  });

  test('NEVER recommends raw gh pr merge or allowing it', () {
    expect(section, contains('never raw `gh pr merge`'));
    // The only allow-rule the document may mention is the wrapper's. An allow-rule for the raw
    // command would let any session merge a red PR (main has no required status checks).
    for (final m in RegExp(r'Bash\(([^)]*)\)').allMatches(section)) {
      expect(m.group(1), 'sh scripts/safe_pr_merge.sh:*',
          reason: 'the only allow-rule Gate 2 may name is the wrapper\'s, never `${m.group(0)}`');
    }
    expect(section, contains("a settings change is the founder's, not the agent's"),
        reason: 'the document must not tell an agent to edit its own permission list');
  });

  test('the push targets the bump BRANCH, never main (a push to main runs the ~39-minute suite)', () {
    expect(section, contains('scripts/safe_push.sh origin bump-<N+1>'),
        reason: 'the push step must name the bump branch; a branch push is what skips the local suite');
    expect(section, isNot(contains('safe_push.sh origin main')),
        reason: 'the pre-B2 flow committed on main and pushed it; that is the ~39-minute path');
    expect(section, isNot(contains('git push origin main')));
  });

  test('lists the steps a classifier or sandbox can block, up front', () {
    expect(section, contains('Tell the founder the whole list'));
    expect(section, contains('Steps a classifier or sandbox can block'));
  });

  test('EXISTENCE: every script the section names exists', () {
    final named = {
      for (final m in RegExp(r'scripts/([A-Za-z0-9_\-]+\.(?:sh|dart))').allMatches(section)) m.group(1)!,
    };
    expect(named, isNotEmpty);
    for (final f in named) {
      expect(File('scripts/$f').existsSync(), isTrue,
          reason: 'build-apk.md Gate 2 tells the agent to run scripts/$f but it does not exist');
    }
    expect(named, containsAll(<String>[
      'new-worktree.sh',
      'safe_commit.sh',
      'safe_push.sh',
      'safe_pr_merge.sh',
    ]));
  });

  test('MIRROR: the .opencode copy of the command carries the same text', () {
    // The other tool reads .opencode/command/build-apk.md. B1 changed one line of the .claude
    // command and missed the copy, and B2 rewrites Gate 2: a stale copy would tell that tool to
    // land a bump the old way (commit on main, the ~39-minute suite, a plan-review record).
    final claude = File('.claude/commands/build-apk.md').readAsStringSync().replaceAll('\r\n', '\n');
    final opencode = File('.opencode/command/build-apk.md').readAsStringSync().replaceAll('\r\n', '\n');
    final header = RegExp(r'^---\ndescription: "[^"\n]*"\n---\n\n').firstMatch(opencode);
    expect(header, isNotNull, reason: 'the opencode copy starts with its own three-line frontmatter block');
    expect(opencode.substring(header!.end), claude,
        reason: '.opencode/command/build-apk.md must carry the same body as .claude/commands/build-apk.md. '
            'Regenerate it: keep the frontmatter block, replace everything after it with the .claude file.');
  });

  test('EXISTENCE: every flag the section names is defined where the tool lives', () {
    final fromGreen = File('.claude/commands/build-apk.md').readAsStringSync();
    expect(RegExp(r'^## --from-green', multiLine: true).hasMatch(fromGreen), isTrue,
        reason: '`--from-green` is named in Gate 2; its section must exist in the same command');
    // The merge exemption the section promises is implemented by the gate it names.
    final gate = File('scripts/check_plan_review_record_exists.dart').readAsStringSync();
    expect(gate, contains('rangeIsVersionBump'),
        reason: 'Gate 2 promises no plan-review record for a bare bump; the keystone gate must '
            'actually call rangeIsVersionBump for merges');
    expect(File('scripts/version_bump_git_lib.dart').readAsStringSync(), contains('bool rangeIsVersionBump('));
  });
}
