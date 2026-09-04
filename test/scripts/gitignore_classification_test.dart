// test/scripts/gitignore_classification_test.dart
//
// THE CLASS FIX for the recurring unretirable-worktree bug (a9c4f2, 2026-09-04).
//
// Four times now, a gitignored path that repo tooling writes INTO a worktree was
// absent from `regenerableIgnoredPaths`, so `retire_worktree.dart` classified it
// as precious and refused to retire the worktree — forever, silently:
//
//   d7b3e9  2026-08-10  the list and its exact-match rule are born
//   f2a9c7  2026-08-25  test outputs      -> any worktree that RAN the suite
//   b4d7e9  2026-08-27  the Stop marker   -> any worktree that CLOSED a batch
//   a9c4f2  2026-09-04  the CI queue      -> any worktree that ever PUSHED
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
//     the lib header's instruction for that case is to keep the worktree.
//   - BARE names in a NESTED .gitignore (`GeneratedPluginRegistrant.java` in
//     android/.gitignore). Without a slash, git matches them at ANY depth, so no
//     single exact path represents them; the real deep path is classified in the
//     lib list instead. Anchored nested entries (`/local.properties`) ARE covered.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/retire_worktree_lib.dart';

/// Ignored paths that MUST keep a worktree alive.
///
/// Membership here is a decision, not a default. Grouped by why, because the
/// reason is what a future reader needs in order to move something out.
const deliberatelyPreciousIgnoredPaths = <String>[
  // --- Secrets. Destroying any of these is unrecoverable and was the round-1
  // P0 that created the exact-match rule in the first place (d7b3e9). ---
  '.claude/.alerts.env',
  '.env.dev',
  '.env.local',
  '.env.prod',
  'supabase/.env',
  'supabase/.supabase/',
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
  'deno.lock',
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
}
