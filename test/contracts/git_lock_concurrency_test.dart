// test/contracts/git_lock_concurrency_test.dart
//
// Behavioral coverage for scripts/_git_lock.sh (Unit 3a, discipline-tooling
// hardening batch, 2026-08-03). Proves two concurrent git-mutating operations
// against the SAME repo cannot both hold the lock at once -- under REAL
// process concurrency, not a mocked timing model -- and that the lock is
// reusable once released.
//
// It is NOT reclaimable if its holder is dead: a stale lock is REFUSED with the
// manual clear command printed (OI-92, 2026-08-05). The automatic reclaim that
// earlier revisions carried was removed after failing independent review four
// consecutive times on the same check-then-act shape. Two tests that covered it
// were deleted; see the note where they used to live, near the end of this file.
//
// WHY THIS EXISTS: a 2026-08-03 near-miss saw two safe_commit.sh attempts
// overlap because a `ps`-based liveness check sampled a gap between two
// short-lived subprocess spawns inside the pre-commit gate loop. Benign only
// by luck (both attempts staged byte-identical content). This test would have
// failed on the OLD (lock-free) wrappers.
//
// Runs the real script as a subprocess against a throwaway repo. Environment
// is scrubbed of GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE -- run inside
// pre-commit those are exported by git and override BOTH `workingDirectory:`
// and `git -C`, so without scrubbing every git call here would operate on the
// REAL repo (b7e4c2, feedback_mistake_git_hook_env_leak). Mirrors the pattern
// established in test/contracts/deferral_euphemism_gate_test.dart.

@Timeout(Duration(minutes: 3))
library;

// TIMEOUT RAISED FROM THE 30s DEFAULT (2026-08-13, diagnose 4f2a9e).
// This file spawns real subprocesses (`dart run` / shell), and a cold `dart run`
// costs seconds on its own — VM start plus kernel compile. Under the
// merge-commit regression-catalog walk, which runs ~700 tests concurrently,
// those subprocesses take long enough to blow the 30s PER-TEST default, and the
// walk reports failures for tests that pass standalone every time. Measured: one
// such file takes 33s wall with ZERO contention.
// Applied to the whole subprocess-spawning class, not only the files observed
// failing — fixing just the observed instances is what let this recur twice.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _lockScript = 'scripts/_git_lock.sh';

void main() {
  late String repoRoot;

  Map<String, String> scrubbedEnv() {
    const leaky = {'git_dir', 'git_work_tree', 'git_index_file'};
    return {
      for (final e in Platform.environment.entries)
        if (!leaky.contains(e.key.toLowerCase())) e.key: e.value,
    };
  }

  setUpAll(() {
    repoRoot = Directory.current.path;
    expect(File('$repoRoot/$_lockScript').existsSync(), isTrue);
  });

  ({Directory repo, String holderScript, String proberScript})
      buildScratchRepo() {
    final repo = Directory.systemTemp.createTempSync('git_lock_');
    addTearDown(() {
      if (repo.existsSync()) repo.deleteSync(recursive: true);
    });

    ProcessResult git(List<String> args) => Process.runSync('git', args,
        workingDirectory: repo.path,
        environment: scrubbedEnv(),
        includeParentEnvironment: false,
        runInShell: true);

    expect(git(['init']).exitCode, 0, reason: 'temp repo init failed');
    git(['config', 'user.email', 't@example.com']);
    git(['config', 'user.name', 'T']);

    Directory('${repo.path}/scripts').createSync(recursive: true);
    File('$repoRoot/$_lockScript').copySync('${repo.path}/$_lockScript');

    // Acquires, signals readiness via a marker file (so the test can wait
    // deterministically instead of guessing a sleep duration), holds the
    // lock for up to 5s, then exits -- releasing via the sourced script's
    // own EXIT trap.
    final holderPath = '${repo.path}/holder.sh';
    File(holderPath).writeAsStringSync('''
#!/usr/bin/env sh
set -u
cd "\$(dirname "\$0")"
. ./scripts/_git_lock.sh
git_lock_acquire "holder" || { echo "HOLDER_ACQUIRE_FAILED"; exit 1; }
echo "HOLDER_ACQUIRED \$\$"
touch ready.marker
sleep 5
''');

    // Single acquire attempt; reports outcome and exits immediately
    // (releasing again if it happened to succeed).
    final proberPath = '${repo.path}/prober.sh';
    File(proberPath).writeAsStringSync('''
#!/usr/bin/env sh
set -u
cd "\$(dirname "\$0")"
. ./scripts/_git_lock.sh
if git_lock_acquire "prober"; then
  echo "PROBER_ACQUIRED"
  exit 0
else
  echo "PROBER_REFUSED"
  exit 1
fi
''');

    return (repo: repo, holderScript: holderPath, proberScript: proberPath);
  }

  group('scripts/_git_lock.sh — concurrent acquisition', () {
    test(
        'a second acquire attempt REFUSES while the first holder is alive, '
        'then SUCCEEDS once the holder releases', () async {
      final s = buildScratchRepo();
      final marker = File('${s.repo.path}/ready.marker');

      final holder = await Process.start('sh', [s.holderScript],
          workingDirectory: s.repo.path,
          environment: scrubbedEnv(),
          includeParentEnvironment: false,
          runInShell: true);
      addTearDown(() => holder.kill());

      // Poll for the holder's readiness marker instead of a fixed sleep --
      // a fixed delay would either flake (too short) or waste wall-clock
      // (too long); this proceeds the instant the lock is genuinely held.
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!marker.existsSync()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('holder never signalled readiness within 10s');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      // Contended attempt: holder is alive and sleeping. Must refuse, not
      // race ahead to a second concurrent mkdir/commit.
      final contended = Process.runSync('sh', [s.proberScript],
          workingDirectory: s.repo.path,
          environment: scrubbedEnv(),
          includeParentEnvironment: false,
          runInShell: true);
      final contendedOut = '${contended.stdout}${contended.stderr}';
      expect(contended.exitCode, 1,
          reason: 'A live holder must cause the second attempt to refuse, '
              'never race ahead.\n$contendedOut');
      expect(contendedOut, contains('PROBER_REFUSED'));
      expect(contendedOut, contains('REFUSING'));

      // Let the holder finish naturally (releases via its own EXIT trap).
      final holderExit = await holder.exitCode;
      expect(holderExit, 0, reason: 'holder script itself must exit cleanly');

      // The lock dir must be gone -- proves release actually ran, not just
      // that the holder process happened to die.
      expect(
          Directory('${s.repo.path}/.git/.safe_git_op.lock').existsSync(),
          isFalse,
          reason: 'the lock dir must be removed on release');

      // Reuse: a fresh attempt after release must succeed.
      final after = Process.runSync('sh', [s.proberScript],
          workingDirectory: s.repo.path,
          environment: scrubbedEnv(),
          includeParentEnvironment: false,
          runInShell: true);
      expect(after.exitCode, 0,
          reason: 'the lock must be acquirable again once freed.\n'
              '${after.stdout}${after.stderr}');
      expect(
          '${after.stdout}${after.stderr}', contains('PROBER_ACQUIRED'));
    }, timeout: const Timeout(Duration(seconds: 30)));

    // OI-92 (2026-08-05) INVERTED THIS TEST. It previously asserted that a
    // dead-PID lock was automatically RECLAIMED. The auto-reclaim is gone —
    // it failed independent review four consecutive times on the same
    // check-then-act shape, and no correct version exists with the primitives
    // on this toolchain (`flock` absent; `mv -T` is fail-if-present for
    // directories and replace-unconditionally for files, so "remove theirs AND
    // install mine" cannot be expressed atomically). A dead-holder lock is now
    // REFUSED, with the manual clear printed.
    //
    // This is deliberately asserted as a BEHAVIOUR CHANGE rather than deleted:
    // silently dropping the old test would leave nothing pinning which of the
    // two behaviours is intended, and a future well-meaning "the lock wedges
    // forever, let's auto-clear it" patch would sail through.
    test(
        'a stale lock (holder PID no longer alive) is REFUSED, never '
        'auto-reclaimed, and prints the manual clear command', () async {
      final s = buildScratchRepo();

      // A PID that is genuinely dead: spawn a real process, capture its own
      // PID, and wait for it to exit -- never a guessed/magic number, which
      // could coincidentally collide with a real running process.
      final deadProc =
          await Process.start('sh', ['-c', 'echo \$\$'], runInShell: true);
      final deadPid =
          (await deadProc.stdout.transform(utf8.decoder).join()).trim();
      await deadProc.exitCode;
      expect(deadPid, isNotEmpty);

      // Simulate a crashed holder: hand-create the lock dir naming that
      // now-dead PID, exactly as git_lock_acquire's own holder file does.
      final lockDir = Directory('${s.repo.path}/.git/.safe_git_op.lock');
      lockDir.createSync(recursive: true);
      File('${lockDir.path}/holder').writeAsStringSync(
          'pid=$deadPid\nop=crashed-simulated\nstarted=2000-01-01T00:00:00Z\n');

      final r = Process.runSync('sh', [s.proberScript],
          workingDirectory: s.repo.path,
          environment: scrubbedEnv(),
          includeParentEnvironment: false,
          runInShell: true);
      final out = '${r.stdout}${r.stderr}';
      expect(r.exitCode, isNot(0),
          reason: 'a lock left by a dead PID must be REFUSED (OI-92), never '
              'silently taken over. Acquiring here would mean the auto-reclaim '
              'has been reintroduced.\n$out');
      expect(out, contains('REFUSING'),
          reason: 'the refusal must be explicit.\n$out');
      expect(out, contains('is NOT alive'),
          reason: 'the message must say WHY it refused — that the holder is '
              'dead — or the operator cannot tell a stale lock from a live '
              'one they should wait for.\n$out');
      expect(out, contains('rm -rf'),
          reason: 'refusing without printing the manual clear command would '
              'leave the operator genuinely stuck, which is the one outcome '
              'that would justify auto-reclaim.\n$out');
      expect(out, isNot(contains('Reclaiming stale lock')),
          reason: 'the auto-reclaim path must be gone entirely.\n$out');
    });

    // Round-1 review finding #1 (blocking): git_lock_release used to remove
    // the lock directory unconditionally, with no check that it still
    // belonged to the releasing process. Demonstrated cascade: a
    // false-positive stale-reclaim by process B, followed by process A's
    // (the original, still-legitimate holder) EXIT trap firing and deleting
    // B's now-legitimate lock, let a third process acquire concurrently
    // with B -- the exact race class this whole file exists to prevent,
    // reintroduced one level down. This test does not need to reproduce the
    // full cascade to catch a regression of the fix: it only needs to prove
    // release checks ownership before removing anything, which the
    // cascade's final step depends on.
    test(
        'release does NOT remove a lock dir whose holder file no longer '
        'records this process own pid (an impersonated/overwritten '
        'holder, simulating another process having legitimately taken over '
        'the same lock path)', () {
      final s = buildScratchRepo();
      final scriptPath = '${s.repo.path}/release_owner_check.sh';
      File(scriptPath).writeAsStringSync('''
#!/usr/bin/env sh
set -u
cd "\$(dirname "\$0")"
. ./scripts/_git_lock.sh
git_lock_acquire "release-owner-test" || { echo "ACQUIRE_FAILED"; exit 1; }
LOCK_DIR="\$_GIT_LOCK_DIR"
IMPOSTOR_PID=\$(( \$\$ + 1 ))
{
  echo "pid=\$IMPOSTOR_PID"
  echo "op=impersonator"
  echo "started=2000-01-01T00:00:00Z"
} > "\$LOCK_DIR/holder"
git_lock_release
if [ -d "\$LOCK_DIR" ]; then
  echo "LOCK_DIR_SURVIVED"
else
  echo "LOCK_DIR_REMOVED"
fi
''');

      final r = Process.runSync('sh', [scriptPath],
          workingDirectory: s.repo.path,
          environment: scrubbedEnv(),
          includeParentEnvironment: false,
          runInShell: true);
      final out = '${r.stdout}${r.stderr}';
      expect(out, contains('LOCK_DIR_SURVIVED'),
          reason: 'release must not remove a lock dir whose holder file no '
              'longer records this process pid -- an unconditional removal '
              'here is round-1 review finding #1.\n$out');
      expect(out, contains('no longer owned'),
          reason: 'the refusal must be visible, not a silent no-op.\n$out');
      expect(out, isNot(contains('LOCK_DIR_REMOVED')));
    }, timeout: const Timeout(Duration(seconds: 15)));

    // Round-1 review finding #3 (should-fix, TOCTOU) was originally closed
    // by adding a brief re-read/sleep before the OLD mkdir-then-separate-
    // write design declared a holder-less lock dir stale -- a probe landing
    // in that window used to see the dir present but `holder` missing and
    // treat that as proof of a crashed acquirer, immediately reclaiming.
    // That fix was itself superseded by the round-2 redesign (see the test
    // below and scripts/_git_lock.sh's header): the mkdir-then-write design
    // was replaced entirely by a private-candidate-then-atomic-mv-T-publish
    // design, under which a bare, holder-less directory at the canonical
    // lock path can no longer arise as a legitimate in-flight state AT ALL
    // -- there is no "pause and recheck" step to test anymore, because
    // there is no read-then-decide step in the first place. A stray empty
    // directory at the lock path (only ever possible via something OTHER
    // than this file's own code -- e.g. a leftover from a pre-redesign
    // version, or manual `mkdir` while debugging) is instead handled by the
    // SAME atomic `mv -T` primitive as everything else: POSIX `rename()`
    // permits replacing an EMPTY existing directory outright, and -- unlike
    // the old design -- this is genuinely safe rather than merely
    // convenient, because it is still governed by the same atomicity
    // guarantee. Verified empirically (not assumed) under real concurrent
    // contention before relying on it: 5 parallel processes racing `mv -T`
    // against the SAME pre-existing EMPTY target produced exactly 1 winner
    // and 4 clean, content-intact failures -- identical safety to a fresh
    // no-target-at-all race. This test proves that safety property directly
    // rather than asserting a "pause" that no longer exists in the code.
    //
    // Tests the underlying `mv -T` primitive directly rather than routing
    // through the full git_lock_acquire (which internally retries up to 3
    // times on contention): git_lock_acquire's retry loop means several
    // contenders can legitimately win SEQUENTIALLY within one test run
    // (each acquires, immediately releases via its own EXIT trap since
    // nothing holds the lock open, then a later retry from someone else
    // acquires fresh) -- "count total winners across the run" is not a
    // meaningful safety property there. The actual safety claim is about
    // the primitive itself: of N SIMULTANEOUS claims against the identical
    // pre-existing empty target, at most one may ever succeed. That is what
    // this test pins, matching exactly the manual verification recorded in
    // scripts/_git_lock.sh's header.
    test(
        'the underlying atomic-publish primitive (mv -T) allows exactly one '
        'winner when N processes race it simultaneously against the SAME '
        'pre-existing empty directory', () async {
      final scratch = Directory.systemTemp.createTempSync('mv_t_race_');
      addTearDown(() {
        if (scratch.existsSync()) scratch.deleteSync(recursive: true);
      });

      final targetDir = Directory('${scratch.path}/empty_target')
        ..createSync();
      expect(targetDir.listSync(), isEmpty);

      const contenders = 5;
      final procs = <Process>[];
      for (var i = 0; i < contenders; i++) {
        final candidate = Directory('${scratch.path}/cand_$i')..createSync();
        File('${candidate.path}/holder').writeAsStringSync('pid=CAND$i\n');
        procs.add(await Process.start(
            'mv', ['-T', candidate.path, targetDir.path],
            workingDirectory: scratch.path,
            environment: scrubbedEnv(),
            includeParentEnvironment: false,
            runInShell: true));
      }
      final exitCodes = await Future.wait(procs.map((p) => p.exitCode));

      final winners = exitCodes.where((c) => c == 0).length;
      expect(winners, 1,
          reason: 'exactly one of $contenders simultaneous `mv -T` calls '
              'against the same pre-existing empty target must succeed -- '
              'never zero (the target would wedge every future acquire) '
              'and never more than one (silent double-ownership, the exact '
              'corruption class this file exists to prevent). Exit codes: '
              '$exitCodes');

      // The winner's content must be intact and exclusive -- no merge, no
      // partial write from a loser.
      final holderContent =
          File('${targetDir.path}/holder').readAsStringSync().trim();
      expect(holderContent, matches(RegExp(r'^pid=CAND\d$')));

      // Every loser's own candidate directory must survive untouched (mv
      // must not have partially consumed a losing source).
      var survivors = 0;
      for (var i = 0; i < contenders; i++) {
        final candidate = Directory('${scratch.path}/cand_$i');
        if (candidate.existsSync()) {
          survivors++;
          expect(File('${candidate.path}/holder').readAsStringSync().trim(),
              'pid=CAND$i');
        }
      }
      expect(survivors, contenders - 1,
          reason: 'the 4 losing candidates must all survive intact; only '
              'the 1 winner is consumed by a successful rename.');
    }, timeout: const Timeout(Duration(seconds: 15)));

    // Round-2 review blocking #1: the round-1 TOCTOU fix (test above) only
    // narrowed the mkdir-then-separate-write window, it did not close it.
    // The round-2 reviewer proved this live: a holder delayed past the
    // re-read window gets reclaimed by a second process, and the delayed
    // holder's later write -- targeting a PATH, not the specific object its
    // own mkdir created -- silently clobbers the reclaimer's holder file.
    // Both processes then believe, from their own local state, that they
    // exclusively hold the mutex. The fix replaced the mkdir-then-write
    // design with a private-candidate-then-atomic-mv-T-publish design (see
    // scripts/_git_lock.sh header). This test reproduces the round-2
    // reviewer's EXACT attack -- a real, injected delay on one process,
    // racing a normal instance of the other -- against the CURRENT code,
    // and asserts the cascade no longer occurs.
    test(
        'a slow-to-publish contender cannot clobber a holder that '
        'legitimately published first, even when the slow contender '
        'started first (round-2 cascade repro)', () async {
      final s = buildScratchRepo();

      // Build a "delayed" variant via a targeted replace on the REAL
      // script's actual content (not a hand-duplicated copy), so this test
      // tracks production code rather than a fork that could silently
      // drift from it.
      final realScript = File('$repoRoot/$_lockScript').readAsStringSync();
      const publishLine = 'if mv -T "\$candidate" "\$lock_path" 2>/dev/null; then';
      expect(realScript, contains(publishLine),
          reason: 'this test injects a delay immediately before this exact '
              'line. If the real script no longer contains it, the '
              'injection below would silently no-op and this test would '
              'stop proving anything.');
      final delayedScript =
          realScript.replaceFirst(publishLine, 'sleep 1.5\n$publishLine');
      expect(delayedScript, isNot(equals(realScript)),
          reason: 'the replacement above must actually have matched.');
      File('${s.repo.path}/scripts/_git_lock_delayed.sh')
          .writeAsStringSync(delayedScript);

      final procAPath = '${s.repo.path}/procA.sh';
      File(procAPath).writeAsStringSync('''
#!/usr/bin/env sh
set -u
cd "\$(dirname "\$0")"
. ./scripts/_git_lock_delayed.sh
git_lock_acquire "procA-delayed" || { echo "A_ACQUIRE_FAILED"; exit 1; }
echo "A_ACQUIRED \$\$"
''');

      final procBPath = '${s.repo.path}/procB.sh';
      File(procBPath).writeAsStringSync('''
#!/usr/bin/env sh
set -u
cd "\$(dirname "\$0")"
. ./scripts/_git_lock.sh
git_lock_acquire "procB-normal" || { echo "B_ACQUIRE_FAILED"; exit 1; }
echo "B_ACQUIRED \$\$"
sleep 2
echo "B_FINAL_HOLDER: \$(cat "\$(git rev-parse --git-dir)/.safe_git_op.lock/holder" 2>/dev/null | tr "\\n" ";")"
''');

      final aOut = StringBuffer();
      final procA = await Process.start('sh', [procAPath],
          workingDirectory: s.repo.path,
          environment: scrubbedEnv(),
          includeParentEnvironment: false,
          runInShell: true);
      procA.stdout.transform(utf8.decoder).listen(aOut.write);
      procA.stderr.transform(utf8.decoder).listen(aOut.write);
      addTearDown(() => procA.kill());

      // B starts 300ms after A -- deliberately later -- but A is stalled
      // 1.5s before its publish, so B must win despite the head start.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final bOut = StringBuffer();
      final procB = await Process.start('sh', [procBPath],
          workingDirectory: s.repo.path,
          environment: scrubbedEnv(),
          includeParentEnvironment: false,
          runInShell: true);
      procB.stdout.transform(utf8.decoder).listen(bOut.write);
      procB.stderr.transform(utf8.decoder).listen(bOut.write);
      addTearDown(() => procB.kill());

      final aExit = await procA.exitCode;
      final bExit = await procB.exitCode;

      expect(bExit, 0,
          reason: 'the on-time contender must succeed.\n${bOut.toString()}');
      expect(bOut.toString(), contains('B_ACQUIRED'));
      expect(
          bOut.toString(),
          matches(RegExp(r'B_FINAL_HOLDER: pid=\d+;op=procB-normal;')),
          reason: 'the on-time contender must see its OWN unclobbered '
              'holder content a full 2s after acquiring -- proving the '
              'delayed contender\'s later publish attempt never silently '
              'overwrote it. A failure here reproduces round-2 blocking '
              '#1.\n${bOut.toString()}');
      expect(aExit, 1,
          reason: 'the delayed contender must fail to acquire, not '
              'silently succeed by clobbering the on-time holder.\n'
              '${aOut.toString()}');
      expect(aOut.toString(), contains('A_ACQUIRE_FAILED'));
      expect(aOut.toString(), contains('REFUSING'));
    }, timeout: const Timeout(Duration(seconds: 20)));

    // OI-92 B-pass finding. A trapped signal whose handler does NOT exit runs
    // the handler and then RESUMES execution at the point of interruption.
    // The pre-existing `trap 'git_lock_release' EXIT INT TERM` therefore meant
    // a Ctrl-C released the lock and let the wrapper CARRY ON without it —
    // another process could then acquire and run concurrently, which is exactly
    // the mutual exclusion this file exists to provide. Handlers now release
    // AND exit (128+signum).
    //
    // The kill is issued from INSIDE a shell, not via Dart's Process.kill:
    // on Windows that maps to TerminateProcess and runs no handler at all, so
    // a Dart-issued kill could not distinguish the fixed code from the broken
    // code. Keeping signal delivery inside MSYS2 is what makes this test mean
    // anything on this stack.
    test(
        'a signal (TERM) releases the lock AND terminates — the script must '
        'not resume past the trap and keep running unlocked', () async {
      final s = buildScratchRepo();

      // Holder writes a RESUMED marker only if execution continues past the
      // interrupted sleep. That marker is the whole assertion.
      File('${s.repo.path}/sig_holder.sh').writeAsStringSync('''
#!/usr/bin/env sh
set -u
cd "\$(dirname "\$0")"
. ./scripts/_git_lock.sh
git_lock_acquire "sig-holder" || { echo "SIG_ACQUIRE_FAILED"; exit 1; }
touch ready.marker
sleep 5
touch RESUMED.marker
echo "RESUMED_PAST_TRAP"
''');

      // Driver backgrounds the holder, waits for the lock to be genuinely
      // held, TERMs it, and reports the exit status.
      File('${s.repo.path}/sig_driver.sh').writeAsStringSync('''
#!/usr/bin/env sh
set -u
cd "\$(dirname "\$0")"
sh ./sig_holder.sh &
HPID=\$!
i=0
while [ ! -f ready.marker ] && [ \$i -lt 100 ]; do sleep 0.1; i=\$((i+1)); done
[ -f ready.marker ] || { echo "DRIVER_HOLDER_NEVER_READY"; exit 9; }
kill -TERM \$HPID 2>/dev/null
wait \$HPID
echo "HOLDER_EXIT=\$?"
''');

      final r = Process.runSync('sh', ['${s.repo.path}/sig_driver.sh'],
          workingDirectory: s.repo.path,
          environment: scrubbedEnv(),
          includeParentEnvironment: false,
          runInShell: true);
      final out = '${r.stdout}${r.stderr}';

      expect(out, isNot(contains('DRIVER_HOLDER_NEVER_READY')),
          reason: 'the holder must actually acquire before we signal it.\n$out');

      // THE REGRESSION. With a non-exiting handler the holder resumes past the
      // interrupted sleep and reaches this marker — while no longer holding the
      // lock it released.
      expect(File('${s.repo.path}/RESUMED.marker').existsSync(), isFalse,
          reason: 'the holder resumed past the trap and kept running WITHOUT '
              'the lock it just released. Another process could acquire and '
              'run concurrently.\n$out');
      expect(out, isNot(contains('RESUMED_PAST_TRAP')), reason: out);

      // Cleanup still happened: the lock must be gone, so the next operation
      // is not wedged behind a lock whose owner is dead.
      expect(
          Directory('${s.repo.path}/.git/.safe_git_op.lock').existsSync(),
          isFalse,
          reason: 'the signal handler must still RELEASE, not merely exit — '
              'otherwise every Ctrl-C leaves a lock needing a manual clear.\n'
              '$out');

      // And the lock is genuinely reusable afterwards.
      final after = Process.runSync('sh', [s.proberScript],
          workingDirectory: s.repo.path,
          environment: scrubbedEnv(),
          includeParentEnvironment: false,
          runInShell: true);
      expect(after.exitCode, 0,
          reason: 'a fresh acquire must succeed after a signalled holder '
              'released.\n${after.stdout}${after.stderr}');
    }, timeout: const Timeout(Duration(seconds: 40)));

    // ── REMOVED 2026-08-05 (OI-92) — two tests whose SUBJECT no longer exists ──
    //
    // Both covered the automatic stale-lock reclaim, which this batch deleted
    // rather than patched:
    //
    //   1. "a slow-to-reclaim contender cannot destroy a lock that a faster
    //      contender legitimately reclaimed and republished" — the round-3
    //      cascade repro.
    //   2. "a dead-PID lock younger than the reclaim age floor is refused,
    //      reclaimable once it ages past the floor" — the age-gate layer.
    //
    // They are deleted, not skipped or rewritten, because there is no reclaim
    // left for them to exercise: both asserted `contains('Reclaiming stale
    // lock')`, a string the script no longer emits on any path. Keeping them
    // green would have required re-adding the very machinery OI-92 removed.
    //
    // What replaced their coverage is NOT nothing. The inverted test above
    // ('a stale lock … is REFUSED, never auto-reclaimed') pins the new
    // behaviour from the opposite direction and asserts `isNot(contains(
    // 'Reclaiming stale lock'))`, so reintroducing the auto-reclaim now FAILS
    // a test rather than silently passing. That is the guarantee these two were
    // really protecting: that nobody re-adds a takeover path by accident.
    //
    // The four tests above are untouched and are the ones that matter — they
    // cover the CLAIM path (atomic `mv -T` single-winner under N-way
    // contention, the round-2 slow-publish cascade, alive-holder refusal, and
    // release-ownership). That path was never the defective part; four
    // consecutive review rounds all landed in the reclaim.
  });
}
