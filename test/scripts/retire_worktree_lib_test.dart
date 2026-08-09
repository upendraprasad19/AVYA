// test/scripts/retire_worktree_lib_test.dart
//
// Pure-logic tests for scripts/retire_worktree_lib.dart — the predicate behind
// worktree retirement. Touches no git, so no environment can change the
// answers. The e2e counterpart that runs the real binary against real linked
// worktrees is test/scripts/retire_worktree_e2e_test.dart; both are required,
// because unit-testing a helper certifies the helper, not the command.
//
// The scenarios below are the ACTUAL 2026-08-09 population, not invented
// shapes. If any of these regress, real uncommitted work becomes deletable.

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/retire_worktree_lib.dart';

/// Convenience: the common "healthy retirable worktree" baseline, with each
/// test overriding only the dimension under examination.
RetireDecision classify({
  bool isPrimary = false,
  bool isProtected = false,
  bool factsReadable = true,
  bool merged = true,
  int dirtyFiles = 0,
  int unpushed = 0,
}) =>
    classifyWorktree(
      isPrimary: isPrimary,
      isProtected: isProtected,
      factsReadable: factsReadable,
      merged: merged,
      dirtyFiles: dirtyFiles,
      unpushed: unpushed,
    );

void main() {
  group('classifyWorktree — the three legs', () {
    test('merged + clean + pushed -> RETIRE', () {
      final d = classify();
      expect(d.shouldRetire, isTrue);
      expect(d.reason, contains('merged + clean + pushed'));
    });

    test('THE KILLER CASE: merged but 14 uncommitted files -> KEEP', () {
      // This single assertion encodes why train-signout-notif-bugs survived on
      // 2026-08-09. Its branch classified as MERGED by tip while the working
      // tree held 14 uncommitted files. A merge-only sweep destroys them.
      // If this test ever goes green while returning RETIRE, real work dies.
      final d = classify(merged: true, dirtyFiles: 14);
      expect(d.shouldRetire, isFalse);
      expect(d.reason, contains('14 uncommitted'));
      expect(d.reason, contains('merge status does not see these'));
    });

    test('a SINGLE dirty file is enough to keep', () {
      // admin-dashboard and memory-consolidation-log each had exactly 1.
      // Thresholds are how "mostly clean" becomes "deleted".
      expect(classify(dirtyFiles: 1).shouldRetire, isFalse);
    });

    test('not merged -> KEEP even when spotlessly clean', () {
      // workout-6-close: 0 dirty files, unmerged branch.
      final d = classify(merged: false, dirtyFiles: 0);
      expect(d.shouldRetire, isFalse);
      expect(d.reason, contains('not merged'));
    });

    test('merged + clean but unpushed commits -> KEEP', () {
      final d = classify(unpushed: 2);
      expect(d.shouldRetire, isFalse);
      expect(d.reason, contains('2 unpushed'));
    });
  });

  group('classifyWorktree — absolute protections short-circuit', () {
    test('primary worktree is never retired, whatever its state', () {
      final d = classify(isPrimary: true, merged: true, dirtyFiles: 0);
      expect(d.shouldRetire, isFalse);
      expect(d.reason, contains('primary'));
    });

    test('protected list wins over a fully-retirable state', () {
      final d = classify(isProtected: true);
      expect(d.shouldRetire, isFalse);
      expect(d.reason, contains('protected'));
    });

    test('primary outranks protected (precedence is deterministic)', () {
      expect(classify(isPrimary: true, isProtected: true).reason,
          contains('primary'));
    });
  });

  group('classifyWorktree — unreadable is NOT clean', () {
    test('unreadable facts -> KEEP, never retired', () {
      // The conflation this guards against: treating "could not ask" as
      // "asked, and the answer was clean". dirtyFiles reads 0 in both cases,
      // which is precisely why factsReadable is a separate input.
      final d = classify(factsReadable: false, merged: true, dirtyFiles: 0);
      expect(d.shouldRetire, isFalse);
      expect(d.reason, contains('unanswered'));
    });

    test('unreadable outranks merged/clean/pushed all being satisfied', () {
      expect(
          classify(factsReadable: false, merged: true, dirtyFiles: 0, unpushed: 0)
              .shouldRetire,
          isFalse);
    });
  });

  group('classifyOrphan — far more conservative than registered worktrees', () {
    test('empty husk (0 files) -> removable', () {
      // happy-hawking-9423c2 and opt-e-rank-cron-batch were both 0 files.
      final d = classifyOrphan(fileCount: 0);
      expect(d.shouldRetire, isTrue);
    });

    test('ONE file is enough to require human review', () {
      final d = classifyOrphan(fileCount: 1);
      expect(d.shouldRetire, isFalse);
      expect(d.reason, contains('manual review'));
    });

    test('a detached repo copy is never auto-removed', () {
      // pr-ag-handoff-gaps: 1,945 files incl. lib/ and docs/, no .git at all.
      // git cannot vouch for it, so "git says it is safe" means nothing here.
      final d = classifyOrphan(fileCount: 1945);
      expect(d.shouldRetire, isFalse);
      expect(d.reason, contains('1945'));
      expect(d.reason, contains('no git to vouch'));
    });
  });

  group('fail-safe direction', () {
    test('every single-dimension failure resolves to KEEP', () {
      // Asymmetry is the whole design: a worktree wrongly kept costs disk; one
      // wrongly removed costs work committed nowhere.
      expect(classify(merged: false).shouldRetire, isFalse);
      expect(classify(dirtyFiles: 1).shouldRetire, isFalse);
      expect(classify(unpushed: 1).shouldRetire, isFalse);
      expect(classify(factsReadable: false).shouldRetire, isFalse);
      expect(classify(isProtected: true).shouldRetire, isFalse);
      expect(classify(isPrimary: true).shouldRetire, isFalse);
      // ...and only the all-clear retires.
      expect(classify().shouldRetire, isTrue);
    });
  });
}
