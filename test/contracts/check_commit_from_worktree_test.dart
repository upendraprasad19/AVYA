// Contract test for the worktree-per-session commit guard
// (scripts/check_commit_from_worktree.dart via scripts/worktree_guard_lib.dart).
//
// Exercises every branch of the pure decision function deterministically — no git
// fixture needed. Guards CLAUDE.md §4.13 (codified 2026-07-07 after 2 cross-session
// file-mixing incidents). Diagnose f0c2d5.

import 'package:flutter_test/flutter_test.dart';
import '../../scripts/worktree_guard_lib.dart';

void main() {
  // Defaults describe the ONLY blocking situation: primary worktree, staged
  // changes, not a merge, not CI, no override. Each named override relaxes one.
  WorktreeGuardResult ev({
    bool isCi = false,
    bool allowOverride = false,
    bool hasStaged = true,
    bool mergeInProgress = false,
    bool isLinkedWorktree = false,
  }) =>
      evaluateWorktreeGuard(
        isCi: isCi,
        allowOverride: allowOverride,
        hasStaged: hasStaged,
        mergeInProgress: mergeInProgress,
        isLinkedWorktree: isLinkedWorktree,
      );

  group('worktree guard — the one blocking case', () {
    test('primary worktree + staged + non-merge + not-CI + no-override → BLOCKED', () {
      final r = ev();
      expect(r.blocked, isTrue);
      expect(r.reason, contains('main worktree'));
    });
  });

  group('worktree guard — every exemption allows the commit', () {
    test('CI → allowed', () => expect(ev(isCi: true).blocked, isFalse));
    test('ALLOW_MAIN_COMMIT override → allowed',
        () => expect(ev(allowOverride: true).blocked, isFalse));
    test('nothing staged → allowed',
        () => expect(ev(hasStaged: false).blocked, isFalse));
    test('merge in progress → allowed (integration into main)',
        () => expect(ev(mergeInProgress: true).blocked, isFalse));
    test('linked worktree → allowed (isolated index)',
        () => expect(ev(isLinkedWorktree: true).blocked, isFalse));
  });

  group('worktree guard — precedence (first match wins)', () {
    test('CI wins even when the primary/staged block condition also holds', () {
      // isCi true + all other fields at their block-eligible values → still allowed.
      expect(ev(isCi: true).blocked, isFalse);
    });
    test('override wins over a linked-vs-primary distinction', () {
      expect(ev(allowOverride: true, isLinkedWorktree: false).blocked, isFalse);
    });
    test('a merge in the primary worktree is allowed (merge beats primary)', () {
      expect(ev(mergeInProgress: true, isLinkedWorktree: false).blocked, isFalse);
    });
  });

  group('worktree guard — exhaustive truth table (32 combinations)', () {
    test('blocked iff (not CI) & (not override) & staged & (not merge) & (not linked)', () {
      for (final ci in [true, false]) {
        for (final ov in [true, false]) {
          for (final st in [true, false]) {
            for (final mg in [true, false]) {
              for (final lk in [true, false]) {
                final expectBlock = !ci && !ov && st && !mg && !lk;
                expect(
                  ev(isCi: ci, allowOverride: ov, hasStaged: st, mergeInProgress: mg, isLinkedWorktree: lk).blocked,
                  expectBlock,
                  reason: 'ci=$ci ov=$ov staged=$st merge=$mg linked=$lk',
                );
              }
            }
          }
        }
      }
    });
  });
}
