// test/scripts/gitignore_classification_test.dart
//
// THE CLASS FIX for the recurring unretirable-worktree bug (a9c4f2, 2026-09-04).
//
// Repeatedly now, a gitignored path that repo tooling writes INTO a worktree was
// absent from `regenerableIgnoredPaths`, so `retire_worktree.dart` classified it
// as precious and refused to retire the worktree — forever, silently:
//
//   d7b3e9  2026-08-10  the list and its exact-match rule are born
//   f2a9c7  2026-08-25  test outputs      -> any worktree that RAN the suite
//   b4d7e9  2026-08-27  the Stop marker   -> any worktree that CLOSED a batch
//   a9c4f2  2026-09-04  the CI queue      -> any worktree that ever PUSHED
//   e9b3c7  2026-11-07  the golden comparator's `failures/` dir -> any worktree
//                       that ran a full local `flutter test`; fixed by listing
//                       the one concrete path (docs/diagnoses/ has the record)
//
// b4d7e9's own write-up named this exact test as the durable fix and filed it
// "as an observation rather than built here". It reached no board — a grep of
// docs/audit/OPEN_INDEX.md for gitignore/regenerab/retire/worktree returns
// OI-134/138/139/141 and none of them is this. An observation that is not filed
// is not tracked, and the fourth instance is what that cost.
//
// WHAT THIS ENFORCES. Every literal entry in the repo's .gitignore files is in
// exactly ONE of two buckets: `regenerableIgnoredPaths` (destroyable, the tool
// may delete the worktree holding it) or `deliberatelyPreciousIgnoredPaths`
// below (must block retirement). Adding a .gitignore entry that is in neither
// FAILS this test, which forces the decision at the moment the entry is added —
// which is the moment all four instances were actually born.
//
// WHAT IT DELIBERATELY DOES NOT COVER, said out loud rather than implied:
//   - GLOB entries (`*.log`, `.claude/_payload_*.json`, `test/goldens/**/failures/`).
//     `isRegenerableIgnored` is exact-match by design — three review rounds each
//     found a P0 from looser matching — so a glob can never be regenerable, and
//     the lib header's instruction for that case is to keep the worktree. What
//     a glob PRODUCES is another matter: the concrete path git emits for it
//     (`!! test/goldens/wardroom/failures/`) is listed exactly, like the
//     `*.log` -> `.claude/.gate_failures.log` precedent in the lib. The golden
//     directories are covered by the class guard at the end of the first group
//     and by the two `git check-ignore` pins in the last group, not by the
//     literal parser (a glob is skipped by it).
//   - BARE names in a NESTED .gitignore (`GeneratedPluginRegistrant.java` in
//     android/.gitignore). Without a slash, git matches them at ANY depth, so no
//     single exact path represents them; the real deep path is classified in the
//     lib list instead. Anchored nested entries (`/local.properties`) ARE covered.
//
// A SECOND PROTECTION, and why the list checks above cannot provide it
// (diagnose c6f2a8). Every test above proves the two LISTS agree with each
// other and with the .gitignore text. Delete a secret's .gitignore line AND its
// list entry together and all of them stay green while the secret is no longer
// ignored. So the last group asks git itself whether each known token path is
// ignored, and by which file. It spawns `git`, hence the file-level @Timeout.

@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/retire_worktree_lib.dart';
import '../helpers/spawn.dart';

/// Ignored paths that MUST keep a worktree alive.
///
/// Membership here is a decision, not a default. Grouped by why, because the
/// reason is what a future reader needs in order to move something out.
const deliberatelyPreciousIgnoredPaths = <String>[
  // --- Secrets. Destroying any of these is unrecoverable and was the round-1
  // P0 that created the exact-match rule in the first place (d7b3e9). ---
  '.claude/.alerts.env',
  '.claude/.razorpay_live.env', // live Razorpay key handoff (2026-09-29) — a real
  // secret a human types in by hand, not something any script in this repo
  // regenerates; same shape as .claude/.alerts.env above.
  '.env.dev',
  '.env.local',
  '.env.prod',
  'supabase/.env',
  'supabase/.supabase/',
  '.supabase/', // the root twin of the line above (c6f2a8) — a live token lived here
  'android/key.properties',
  'android/app/upload-keystore.jks',

  // --- Human intent. Each of these exists ONLY because a person deliberately
  // created it, so deleting one silently reverses a choice somebody made. The
  // kill switches are the sharpest case: they sit beside files this very batch
  // made destroyable, under near-identical names. ---
  '.claude/.reconcile_ci.disabled',
  '.claude/.batch_close.disabled',
  '.claude/settings.local.json',
  '.claude/scheduled_tasks.lock',

  // --- Human work product. Not reconstructible by any script. `mockups/` is
  // the live example: it is the one remaining blocker on `readiness-flip` and
  // it SHOULD block. ---
  'mockups/',
  'Knowledgebase/',
  '.hermes/',
  '.superpowers/',
  'assets/New folder/',
  'assets/naval pics/',
  'assets/calisthenics feature.md',

  // --- Third-party / editor / OS artifacts. Regenerable in principle, but by
  // tools OUTSIDE this repo, so nothing here can promise to rebuild them.
  // Classified precious on the fail-safe direction the lib header states:
  // inertness is recoverable, a deleted file is not. If one of these ever
  // blocks a real retirement, the fix is to move that ONE entry down to
  // `regenerableIgnoredPaths` with evidence — never to loosen the matcher. ---
  '.DS_Store',
  '.history',
  '.atom/',
  '.idea/',
  '.svn/',
  '.swiftpm/',
  '.build/',
  '.buildlog/',
  '.pub/',
  '.pub-cache/',
  '.config/',
  'migrate_working_dir/',
  'coverage/',
  'node_modules/zod',
  'node_modules/.deno/',

  // --- Build outputs that are NOT produced in a worktree. §4.3 restricts APK
  // builds to `main` in the primary worktree, so these should never appear in
  // a linked one; if they somehow do, something unusual happened and keeping
  // the worktree is the right answer. ---
  'android/app/debug',
  'android/app/profile',
  'android/app/release',
  'android/.gradle',
  'android/.cxx/',
  'android/captures/',
  'android/gradlew',
  'android/gradlew.bat',

  // --- The worktree root itself. Never nested inside a linked worktree, but
  // classified so the partition below is total. ---
  '.claude/worktrees/',
];

/// Literal (non-glob) entries of one .gitignore, normalised to worktree-relative
/// paths.
///
/// [dirPrefix] is `''` for the root file and `'android/'` for android/.gitignore.
List<String> literalEntries(String path, String dirPrefix) {
  final file = File(path);
  if (!file.existsSync()) return const <String>[];
  final glob = RegExp(r'[*?\[]');
  final out = <String>[];
  for (final rawLine in file.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    // A negation re-includes a path; it is not itself an ignored path.
    if (line.startsWith('!')) continue;
    if (glob.hasMatch(line)) continue;
    // Bare name in a NESTED file: matches at any depth, so no single exact path
    // represents it. See the header.
    if (dirPrefix.isNotEmpty && !line.contains('/')) continue;
    out.add('$dirPrefix${line.replaceFirst(RegExp('^/'), '')}');
  }
  return out;
}

void main() {
  group('gitignore classification — the class fix (a9c4f2)', () {
    late List<String> entries;

    setUpAll(() {
      // Guard the input set explicitly. An empty read would make every
      // assertion below vacuously pass, which is the "an empty input set
      // reports nothing in the same colour as nothing-wrong" trap.
      expect(File('.gitignore').existsSync(), isTrue,
          reason: 'run from the package root, where .gitignore lives');
      entries = <String>[
        ...literalEntries('.gitignore', ''),
        ...literalEntries('android/.gitignore', 'android/'),
      ];
      expect(entries.length, greaterThan(40),
          reason: 'the root .gitignore alone had 52 literal entries on '
              '2026-09-04; a collapse to near-zero means the parser broke, not '
              'that the repo got tidy');
    });

    test('every literal .gitignore entry is deliberately classified as either '
        'regenerable or precious', () {
      final unclassified = <String>[];
      for (final e in entries) {
        final isRegenerable = regenerableIgnoredPaths.contains(e);
        final isPrecious = deliberatelyPreciousIgnoredPaths.contains(e);
        if (!isRegenerable && !isPrecious) unclassified.add(e);
      }
      expect(unclassified, isEmpty,
          reason: 'These .gitignore entries are in neither list, so nobody has '
              'decided whether retirement may destroy them. Add each to '
              'regenerableIgnoredPaths (in scripts/retire_worktree_lib.dart) if '
              'a script in THIS repo rebuilds it, or to '
              'deliberatelyPreciousIgnoredPaths above if not. Do NOT loosen the '
              'matcher. Unclassified: $unclassified');
    });

    test('every directory under test/goldens holding tests has its comparator `failures/` '
        'directory classified as regenerable', () {
      // The Flutter test comparator writes a failed comparison's diff images to
      // `<directory of the test file>/failures/`, and .gitignore:193 ignores
      // them with the GLOB `test/goldens/**/failures/`. The glob itself can
      // never be regenerable (exact-match matcher), so each suite directory
      // must be listed by its concrete path or its worktree is kept forever
      // after a full local run. A second suite added without that listing is
      // exactly the sixth instance of this class repeating.
      final root = Directory('test/goldens');
      expect(root.existsSync(), isTrue, reason: 'run from the package root');
      // EVERY `_test.dart` under test/goldens counts, not only a file that
      // names the comparator: a golden test can reach `matchesGoldenFile`
      // through a helper kept elsewhere, and a symbol-name filter is blind to
      // that (the stock comparator still writes `failures/` next to the test
      // file). The directory is purpose-named and `.gitignore:193` covers
      // nothing else, so listing one extra directory is the cheap error.
      final dirs = <String>{};
      for (final e in root.listSync(recursive: true)) {
        final norm = e.path.replaceAll('\\', '/');
        if (e is! File || !norm.endsWith('_test.dart')) continue;
        dirs.add(norm.substring(0, norm.lastIndexOf('/')));
      }
      // Input-set guard: an empty scan would pass for any reason at all, and
      // the one suite that exists today must be seen.
      expect(dirs, contains('test/goldens/wardroom'),
          reason: 'the scan found no test under test/goldens/wardroom, '
              'so it proves nothing. Found: $dirs');
      final missing = [
        for (final d in dirs)
          if (!regenerableIgnoredPaths.contains('$d/failures/')) '$d/failures/'
      ];
      expect(missing, isEmpty,
          reason: 'These test directories under test/goldens write a `failures/` directory '
              'that is ignored by .gitignore:193 (a glob) but is not in '
              'regenerableIgnoredPaths (scripts/retire_worktree_lib.dart), so a '
              'worktree that ran the suite can never be retired. Add each '
              'concrete path there; do NOT loosen the matcher. Missing: $missing');
    });

    test('the two classifications are disjoint — nothing is both destroyable '
        'and precious', () {
      final both = deliberatelyPreciousIgnoredPaths
          .where(regenerableIgnoredPaths.contains)
          .toList();
      expect(both, isEmpty,
          reason: 'a path in both lists makes the classification meaningless: '
              '$both');
    });

    test('the precious list agrees with the matcher — every entry really does '
        'BLOCK', () {
      // Guards against a precious entry silently becoming destroyable through a
      // change to isRegenerableIgnored rather than to either list.
      for (final p in deliberatelyPreciousIgnoredPaths) {
        expect(isRegenerableIgnored(p), isFalse,
            reason: '$p is classified precious but the matcher would let the '
                'tool delete the worktree holding it');
      }
    });

    test('the precious list has no orphans — every entry is still ignored '
        'somewhere', () {
      // Without this the ledger rots: an entry removed from .gitignore leaves a
      // stale line here that reads as a live decision.
      final ignored = entries.toSet();
      final orphans = deliberatelyPreciousIgnoredPaths
          .where((p) => !ignored.contains(p))
          .toList();
      expect(orphans, isEmpty,
          reason: 'no longer present in any .gitignore — prune them: $orphans');
    });

    test('all four historical instances would now be caught at the moment the '
        '.gitignore entry was added', () {
      // Each of these is a real path from a real instance. The point is not
      // that they are classified TODAY — they are — but that an entry landing
      // in .gitignore classified in neither list fails the first test above.
      for (final p in const [
        'test/plan_generator/v4_diagnostic_output.md', // f2a9c7 / OI-128
        '.claude/.batch_close_state', // b4d7e9
        '.claude/.ci_reconcile_pending.jsonl', // a9c4f2
        '.claude/.ci_reconcile_pending.jsonl.tmp', // a9c4f2, the mirror
      ]) {
        expect(regenerableIgnoredPaths.contains(p), isTrue,
            reason: '$p is written into the worktree by this repo\'s own '
                'tooling and must be destroyable');
      }
      // And the secret that the round-1 P0 actually deleted stays precious.
      expect(deliberatelyPreciousIgnoredPaths.contains('supabase/.env'), isTrue);
    });
  });

  group('paths that must be ignored by the REPO .gitignore itself (tokens: c6f2a8; generated indexes: A2; golden comparator output)', () {
    // Hermetic: no inherited GIT_* (pre-push runs the suite inside a hook, with
    // GIT_DIR/GIT_INDEX_FILE set) and no global/system config, so a developer's
    // own core.excludesFile cannot supply the match. The match SOURCE is then
    // asserted too: `.git/info/exclude` still applies and cannot be switched
    // off by env, but git reports the deciding pattern, and a per-directory
    // .gitignore outranks info/exclude — so a source other than `.gitignore:`
    // means the repo rule is gone.
    // (The GIT_* strip is the shared helper's; only the two pins are ours.)
    Map<String, String> configPins() {
      final empty = File(
          '${Directory.systemTemp.createTempSync('gi_cfg_').path}/gitconfig')
        ..writeAsStringSync('');
      return {
        'GIT_CONFIG_GLOBAL': empty.path,
        'GIT_CONFIG_NOSYSTEM': '1',
      };
    }

    /// git itself says [path] is ignored, and by the repo's own .gitignore (not a machine-local rule).
    void expectIgnoredByRepo(String path, String consequence) {
      final r = runSpawn(
        'git',
        ['check-ignore', '-v', '--no-index', path],
        why: 'git check-ignore on $path (hermetic config)',
        extraEnv: configPins(),
        allowControl: {'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_NOSYSTEM'},
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      expect(r.exitCode, 0, reason: '$path is NOT ignored — $consequence. stderr: ${r.stderr}');
      expect((r.stdout as String).startsWith('.gitignore:'), isTrue,
          reason: 'ignored, but not by the repo .gitignore (matched by: '
              '${r.stdout}) — the protection is machine-local and would '
              'not exist on another clone');
    }

    for (final tokenPath in const [
      '.supabase/supabase access token.txt', // root copy — unignored until c6f2a8
      'supabase/.supabase/supabase access token.txt', // the path the tools read
    ]) {
      test('`$tokenPath` is ignored, and by .gitignore', () {
        expectIgnoredByRepo(
            tokenPath, 'a `git add -A` would stage a live Supabase Management API token');
      });
    }

    // A2 (merge-conflict-treadmill): the two generated indexes are LOCAL BUILD PRODUCTS. Without
    // these lines they show up as untracked files in every worktree, `git add -A` stages them
    // (and check_local_indexes_untracked then fails the commit), and pre-merge-commit.sh takes
    // its tracked path (keyed on `git check-ignore`). The retire list alone cannot prove this:
    // delete the .gitignore line and the list entry survives (the mutation pass found exactly that).
    for (final indexPath in const [
      'docs/audit/OPEN_INDEX.md',
      'docs/diagnoses/INDEX.md',
    ]) {
      test('`$indexPath` (a generated local build product) is ignored, and by .gitignore', () {
        expectIgnoredByRepo(indexPath,
            'a `git add -A` would stage a generated file and bring back the merge conflicts it was untracked to remove');
      });
    }

    // The golden comparator's output. The allowlist entry for the directory is
    // only safe while git really ignores it: delete the glob at .gitignore:193
    // and the retire tool would still call the directory regenerable while
    // `git add -A` stages the diff images. Both spellings git can see are pinned:
    // a file inside, and the exact directory string the tool compares against.
    for (final goldenPath in const [
      'test/goldens/wardroom/failures/x.png',
      'test/goldens/wardroom/failures/',
    ]) {
      test('`$goldenPath` (golden comparator output) is ignored, and by .gitignore', () {
        expectIgnoredByRepo(goldenPath,
            'a `git add -A` would stage the comparator\'s diff images, and the retire allowlist would call an unignored directory regenerable');
      });
    }
  });
}
