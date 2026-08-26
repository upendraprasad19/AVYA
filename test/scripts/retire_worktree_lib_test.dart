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
  int ignoredFiles = 0,
  bool upstreamConfigured = true,
}) =>
    classifyWorktree(
      isPrimary: isPrimary,
      isProtected: isProtected,
      factsReadable: factsReadable,
      merged: merged,
      dirtyFiles: dirtyFiles,
      unpushed: unpushed,
      ignoredFiles: ignoredFiles,
      upstreamConfigured: upstreamConfigured,
    );

void main() {
  group('parseWorktreePorcelain — locked shipped INERT for want of a test', () {
    // Captured verbatim from git 2.53. The ordering is the whole point:
    // `locked` comes AFTER `branch`, so a parser that emits the record on the
    // `branch` line never sees the lock. That is exactly what shipped — and no
    // test referenced `locked`, so nothing caught it. A code comment claimed
    // the feature prevented a failure it still produced.
    const porcelain = 'worktree C:/repo\n'
        'HEAD 1bcae0db\n'
        'branch refs/heads/main\n'
        '\n'
        'worktree C:/repo/.claude/worktrees/w1\n'
        'HEAD 1bcae0db\n'
        'branch refs/heads/w1\n'
        'locked do not touch\n';

    test('locked is captured even though git emits it AFTER branch', () {
      final r = parseWorktreePorcelain(porcelain);
      expect(r, hasLength(2));
      expect(r[0].locked, isFalse);
      expect(r[1].locked, isTrue,
          reason: 'flush must happen on the RECORD boundary, not on `branch`');
      expect(r[1].branch, 'w1');
    });

    test('a bare `locked` line (no reason) is honoured', () {
      final r = parseWorktreePorcelain(
          'worktree C:/w\nHEAD abc\nbranch refs/heads/b\nlocked\n');
      expect(r.single.locked, isTrue);
    });

    test('lock state does not bleed into the NEXT record', () {
      final r = parseWorktreePorcelain(
          'worktree C:/a\nHEAD 1\nbranch refs/heads/a\nlocked\n'
          '\nworktree C:/b\nHEAD 2\nbranch refs/heads/b\n');
      expect(r[0].locked, isTrue);
      expect(r[1].locked, isFalse, reason: 'must reset per record');
    });

    test('detached is COUNTED with an empty branch, never silently dropped', () {
      final r = parseWorktreePorcelain(
          'worktree C:/d\nHEAD abc\ndetached\n');
      expect(r.single.branch, isEmpty);
    });

    test('the LAST record is emitted (no trailing `worktree` line closes it)',
        () {
      expect(parseWorktreePorcelain('worktree C:/only\nHEAD a\nbranch refs/heads/x'),
          hasLength(1));
    });

    test('a bare record (no branch, no detached) is dropped, not mislabelled',
        () {
      expect(parseWorktreePorcelain('worktree C:/bare\nHEAD abc\nbare\n'),
          isEmpty);
    });

    test('empty input yields no records', () {
      expect(parseWorktreePorcelain(''), isEmpty);
    });
  });

  group('classifyWorktree — the four legs', () {
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
    test('empty husk (0 entries) -> removable', () {
      // happy-hawking-9423c2 and opt-e-rank-cron-batch were both empty.
      final d = classifyOrphan(entryCount: 0);
      expect(d.shouldRetire, isTrue);
    });

    test('ONE entry is enough to require human review', () {
      final d = classifyOrphan(entryCount: 1);
      expect(d.shouldRetire, isFalse);
      expect(d.reason, contains('manual review'));
      expect(d.reason, contains('1 entry'), reason: 'singular, and ENTRY not '
          'FILE — a tree of empty dirs is not an empty husk');
    });

    test('a detached repo copy is never auto-removed', () {
      // pr-ag-handoff-gaps: thousands of entries incl. lib/ and docs/, no .git
      // at all. git cannot vouch for it, so "git says it is safe" means nothing.
      final d = classifyOrphan(entryCount: 4146);
      expect(d.shouldRetire, isFalse);
      expect(d.reason, contains('4146 entries'));
      expect(d.reason, contains('no git to vouch'));
    });
  });

  group('no upstream — round-1 fix, round-2 found it untested', () {
    test('retires, but the reason does NOT claim "pushed"', () {
      // The original defect was a reason string announcing a leg that was
      // never evaluated. Retiring is correct (leg 1 proved it merged, so the
      // commits are reachable from main) — CLAIMING it was pushed is not.
      final d = classify(upstreamConfigured: false);
      expect(d.shouldRetire, isTrue);
      expect(d.reason, contains('no upstream configured'));
      expect(d.reason, isNot(contains('+ pushed')),
          reason: 'must not assert a leg it never evaluated');
    });

    test('WITH an upstream the reason does say pushed', () {
      expect(classify().reason, contains('merged + clean + pushed'));
    });

    test('no upstream does NOT override a dirty tree', () {
      expect(classify(upstreamConfigured: false, dirtyFiles: 1).shouldRetire,
          isFalse);
    });
  });

  group('isRegenerableIgnored — round-2 P0: prefix matching destroyed secrets',
      () {
    test('MUST block: paths that merely START with a regenerable name', () {
      // The reproduced P0: `.env` prefix-matched `.envrc` (direnv secrets) and
      // the whole ignored directory `.envs/`, and both were deleted. Because
      // --ignored=matching collapses a directory to ONE entry, a single false
      // positive authorises deleting an unbounded subtree.
      expect(isRegenerableIgnored('.envrc'), isFalse);
      expect(isRegenerableIgnored('.envs/'), isFalse);
      expect(isRegenerableIgnored('my.env'), isFalse);
      expect(isRegenerableIgnored('not-build/important.md'), isFalse);
      expect(isRegenerableIgnored('notes/local.properties.bak'), isFalse);
      expect(isRegenerableIgnored('secrets/'), isFalse);
      expect(isRegenerableIgnored('secrets/creds.txt'), isFalse);
    });

    test('MUST allow: this repo\'s REAL ignored set (measured, all six)', () {
      // Round-2 F2: without the Flutter-generated entries, every worktree where
      // flutter has run is permanently unretirable — the tool goes inert, the
      // opposite failure. This is the complete measured set for a live worktree.
      for (final p in const [
        '.env',
        '.dart_tool/',
        'build/',
        '.flutter-plugins-dependencies',
        'android/local.properties',
        'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java',
      ]) {
        expect(isRegenerableIgnored(p), isTrue, reason: '$p must be regenerable');
      }
    });

    test('MUST BLOCK: a NESTED .env — round-3 P0, and this suite once asserted '
        'the opposite', () {
      // `supabase/.env` is a REAL 518-byte credentials file in this repo,
      // separately ignored at .gitignore:69, so git emits it as its own `!!`
      // entry. Basename-at-any-depth matching classified it regenerable and the
      // tool DESTROYED it in a scratch reproduction.
      //
      // An earlier version of THIS test asserted `supabase/.env` must be
      // regenerable — the suite locked the bug in. Only `new-worktree.sh`'s
      // ROOT `.env` is reconstructible; nothing recreates a nested one.
      expect(isRegenerableIgnored('supabase/.env'), isFalse);
      expect(isRegenerableIgnored('supabase/functions/.env'), isFalse);
      expect(isRegenerableIgnored('secrets/.env'), isFalse,
          reason: "CLAUDE.md's own motivating example");
    });

    test('MUST BLOCK: anything nested under a regenerable DIRECTORY name', () {
      // `p.contains('/build/')` made these destroyable.
      expect(isRegenerableIgnored('android/keystore/build/upload.jks'), isFalse);
      expect(isRegenerableIgnored('x/ios/Flutter/Secrets.plist'), isFalse);
      expect(isRegenerableIgnored('vendor/.dart_tool/'), isFalse);
    });


    test('OI-128: gitignored TEST OUTPUT is regenerable, so a worktree that '
        'merely RAN the suite can still retire', () {
      // Before this, `test/plan_generator/v4_diagnostic_output.md` — written by
      // test/plan_generator/v4_diagnostic_test.dart:234 and ignored at
      // .gitignore:112 — counted as a non-regenerable ignored file, so ANY
      // worktree that had run the full suite was permanently unretirable. Hit
      // live on `auth-class-fixes` (merged, tracked-clean, held by this file
      // alone) and on `open-issues-triage-976962` before it.
      //
      // The set is ENUMERATED FROM .gitignore, not guessed — the completeness
      // rule is "re-run the enumeration to empty", not "the symptom stopped".
      for (final p in const [
        'test/plan_generator/v4_diagnostic_output.md',
        'analyze_output.txt',
        'flutter_test_output.txt',
        'baseline.json',
        'baseline-lints.json',
      ]) {
        expect(isRegenerableIgnored(p), isTrue,
            reason: '$p is test output listed in .gitignore');
      }
    });

    test('OI-128 did NOT widen the matcher: near-misses of the new entries '
        'still BLOCK', () {
      // The new entries must inherit the exact-match rule that three review
      // rounds paid for. If any of these pass, the fix reintroduced prefix or
      // basename matching under a new name.
      expect(isRegenerableIgnored('test/plan_generator/v4_diagnostic_output.md.bak'),
          isFalse);
      expect(isRegenerableIgnored('archive/analyze_output.txt'), isFalse);
    });

    test('the Stop hook marker is regenerable, or every worktree that closes a '
        'batch becomes permanently unretirable', () {
      // Found live 2026-08-26: `.claude/.batch_close_state` (.gitignore:188,
      // written by batch_close_hook.dart:29) is 41 bytes holding one sha, and
      // the hook rewrites it on every fire. It is not precious. But the §5
      // Stop hook writes it into ANY worktree where a batch closes, so before
      // this entry EVERY such worktree reported "1 non-regenerable ignored
      // file" forever — the same silent decay OI-128 fixed for test outputs,
      // reintroduced two days after that hook shipped.
      expect(isRegenerableIgnored('.claude/.batch_close_state'), isTrue);
      // Still EXACT-match only. The three review rounds recorded in the lib
      // header each found a P0 from looser matching, so a neighbour must NOT
      // inherit regenerability.
      expect(isRegenerableIgnored('.claude/.batch_close_state.bak'), isFalse);
      expect(isRegenerableIgnored('.claude/settings.local.json'), isFalse);
      expect(isRegenerableIgnored('backup/.claude/.batch_close_state'), isFalse);
      expect(isRegenerableIgnored('flutter_test_output.txt.orig'), isFalse);
      expect(isRegenerableIgnored('data/baseline.json'), isFalse);
      expect(isRegenerableIgnored('test/plan_generator/'), isFalse,
          reason: 'the DIRECTORY holds tracked fixtures, not just the output');
      // Deliberately absent from the list because it is a PATTERN, not an exact
      // path — the header forbids patterns outright. Asserting it stays FALSE
      // pins that decision, so a later "just add a glob" change reddens here.
      expect(isRegenerableIgnored('test/goldens/home/failures/'), isFalse);
    });

    test('handles Windows backslashes', () {
      expect(isRegenerableIgnored(r'android\local.properties'), isTrue);
      expect(isRegenerableIgnored(r'secrets\creds.txt'), isFalse);
    });
  });

  group('ignored files — git\'s own blind spot (round-1 P0)', () {
    test('a non-regenerable ignored file KEEPS the worktree', () {
      // Verified against real git 2026-08-09: `git status --porcelain` does NOT
      // list ignored files, and `git worktree remove` does NOT refuse on them —
      // it exits 0 and the file is gone. Without this leg the tool silently
      // destroys anything gitignored.
      final d = classify(ignoredFiles: 1);
      expect(d.shouldRetire, isFalse);
      expect(d.reason, contains('non-regenerable ignored'));
      expect(d.reason, contains('does not refuse'));
    });

    test('zero ignored files still retires — the caller filters regenerables',
        () {
      // .env / build/ / .dart_tool exist in EVERY worktree here (§4.13 copies
      // .env in). If those counted, nothing would ever be retirable and the
      // tool would be useless — so the caller excludes them before this point.
      expect(classify(ignoredFiles: 0).shouldRetire, isTrue);
    });

    test('dirty outranks ignored (more specific reason wins)', () {
      expect(classify(dirtyFiles: 2, ignoredFiles: 5).reason,
          contains('2 uncommitted'));
    });
  });

  group('fail-safe direction', () {
    test('every single-dimension failure resolves to KEEP', () {
      // Asymmetry is the whole design: a worktree wrongly kept costs disk; one
      // wrongly removed costs work committed nowhere.
      expect(classify(merged: false).shouldRetire, isFalse);
      expect(classify(dirtyFiles: 1).shouldRetire, isFalse);
      expect(classify(unpushed: 1).shouldRetire, isFalse);
      expect(classify(ignoredFiles: 1).shouldRetire, isFalse);
      expect(classify(factsReadable: false).shouldRetire, isFalse);
      expect(classify(isProtected: true).shouldRetire, isFalse);
      expect(classify(isPrimary: true).shouldRetire, isFalse);
      // ...and only the all-clear retires.
      expect(classify().shouldRetire, isTrue);
    });
  });
}
