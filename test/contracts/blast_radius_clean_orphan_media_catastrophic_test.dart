// test/contracts/blast_radius_clean_orphan_media_catastrophic_test.dart
//
// OI-321 (founder decision 2026-10-11) — `clean-orphan-media` is catastrophic tier.
//
// It is the one scheduled bulk-delete over user files (docs/operations/CRON_REGISTRY.md: "DELETES Storage objects —
// highest-consequence endpoint behind the shared secret"), and its f0b6d8 defect would have deleted a PRO user's chat
// media on an unreadable subscription read (live in v14 when OI-321 was fixed; no loss is known, and none was looked
// for). Before the rule it matched only the `supabase/functions/**` platform catch-all, so a diff that touched only
// that directory needed no hermes pass and no commit-time review file.
//
// Four layers, each answering a different question (the shape of blast_radius_sync_engine_platform_test.dart):
//   1. CLASSIFICATION  every file on disk under the function directory is catastrophic, and it is the NEW rule that
//                      claims it (not a later catch-all that happened to agree). The file list is DERIVED from the
//                      directory, so a file added next to index.ts/logic.ts is covered without editing this test.
//   2. ORDER           first match wins: the rule must sit above the `supabase/functions/**` catch-all, or it would be
//                      dead text that classifies nothing.
//   3. MIRRORS         look-alikes keep their tier: a sibling function whose name merely starts the same, and the
//                      shared subscription helper (seven other non-test files import it, none deletes anything), must NOT be promoted.
//   4. ROT             the glob names a directory; a rename would orphan the rule silently. The directory must exist
//                      and hold the files this rule exists for.
// Four copies of the registry reader exist. This file imports two: the classifier (scripts/blast_radius_from_diff.dart,
// which the prepare-commit-msg hook runs) and the commit-time review gate's copy (scripts/check_code_review_pass_exists.dart,
// which BLOCKS a catastrophic commit without an accepted review). check_blast_radius_coverage.dart's copy is public too but
// is irrelevant to this rule (it only checks that every path has SOME tier). The merge-time keystone
// (check_plan_review_record_exists.dart, which demands `hermes: accepted`) keeps a PRIVATE copy; it is covered end to end by
// the two `catastrophic path (clean-orphan-media/)` cases in test/scripts/plan_review_record_gate_e2e_test.dart.
// All four globToRegExp bodies were read code-identical on 2026-10-11 (plan-review round 2).
// Plus one run of the real classifier CLI.
//
// Run: flutter test test/contracts/blast_radius_clean_orphan_media_catastrophic_test.dart

@Timeout(Duration(minutes: 3))
library;

// The CLI test spawns a real `dart run`; a cold one costs seconds, and under the merge-commit regression walk the
// 30s per-test default is too tight (diagnose 4f2a9e). File-level, so the next subprocess test added here inherits it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// `as classifier`: that script also defines main().
import '../../scripts/blast_radius_from_diff.dart' as classifier;
// `as reviewGate`: the commit-time review-acceptance gate; it also defines main().
import '../../scripts/check_code_review_pass_exists.dart' as reviewGate;
import '../helpers/spawn.dart';

const _glob = 'supabase/functions/clean-orphan-media/**';
const _dir = 'supabase/functions/clean-orphan-media';
const _catchAll = 'supabase/functions/**';

void main() {
  final reg = classifier
      .parseRegistry(File('docs/blast_radius.yaml').readAsStringSync());
  String tier(String p) => classifier.tierFor(p, reg);

  /// The first rule whose glob claims [p], or null when only default_tier would.
  classifier.TierRule? ruleFor(String p) {
    for (final r in reg.rules) {
      if (classifier.globToRegExp(r.glob).hasMatch(p)) return r;
    }
    return null;
  }

  /// Every tracked-or-not file under the function directory, as repo-relative POSIX paths.
  List<String> onDisk() => Directory(_dir)
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path.replaceAll('\\', '/'))
      .toList()
    ..sort();

  group('classification (derived from the directory)', () {
    test('every file under the function directory is catastrophic', () {
      final files = onDisk();
      expect(files, isNotEmpty);
      for (final p in files) {
        expect(tier(p), 'catastrophic', reason: '$p is not catastrophic');
      }
    });

    test('and it is the new rule that claims each one', () {
      for (final p in onDisk()) {
        expect(ruleFor(p)?.glob, _glob,
            reason: '$p is claimed by ${ruleFor(p)?.glob}, not $_glob');
      }
    });

    test('the commit-time review gate\'s own engine reads it as catastrophic too',
        () {
      // That gate decides whether a commit needs a STAGED accepted review. It parses the registry with its own
      // copy of the rules reader, so the classifier test above does not cover it.
      final rules = reviewGate.parseRules(
          File('docs/blast_radius.yaml').readAsStringSync());
      ({String glob, String tier}) gateRule(String p) {
        for (final r in rules) {
          if (reviewGate.globToRegExp(r.glob).hasMatch(p)) {
            return (glob: r.glob, tier: r.tier);
          }
        }
        return (glob: '', tier: 'feature');
      }

      for (final p in onDisk()) {
        expect(gateRule(p), (glob: _glob, tier: 'catastrophic'),
            reason: '$p, per the review gate');
      }
      expect(gateRule('supabase/functions/_shared/subscription.ts').tier,
          'platform',
          reason: 'control: the gate engine also keeps the shared helper platform');
    });

    test('a file that does not exist yet is covered too (a new sibling)', () {
      // tierFor is a pure glob match, so a path never written still classifies: the directory rule, not an
      // exact-path list, is what covers tomorrow's file.
      expect(tier('$_dir/some_future_helper.ts'), 'catastrophic');
      expect(tier('$_dir/nested/deeper/x.ts'), 'catastrophic');
    });

    test('and so is a file of any kind, not only .ts (docs, fixtures, dotfiles)',
        () {
      // The registry comment says "tests and docs in it included". A rule inserted above this one for a file KIND
      // (`*.md`, `fixtures/**`) would otherwise slip through while every .ts probe above stays green.
      for (final name in [
        'README.md',
        'CLAUDE.md',
        'fixtures/sample.json',
        'fixtures/nested/rows.sql',
        '.hidden',
        'nested/.env.example',
        'deno.json',
      ]) {
        expect(tier('$_dir/$name'), 'catastrophic', reason: '$_dir/$name');
      }
    });
  });

  group('order (first match wins)', () {
    test('the rule sits above the supabase/functions/** catch-all', () {
      final globs = reg.rules.map((r) => r.glob).toList();
      expect(globs, contains(_glob));
      expect(globs, contains(_catchAll));
      expect(globs.indexOf(_glob), lessThan(globs.indexOf(_catchAll)),
          reason: 'below the catch-all the rule would classify nothing');
    });

    test('control: the catch-all alone is platform, so the tier did change', () {
      // The sibling that no specific rule names falls to the catch-all. If this ever stops being platform the
      // assertions above could be passing for a different reason.
      expect(ruleFor('supabase/functions/some-unlisted-fn/index.ts')?.glob,
          _catchAll);
      expect(tier('supabase/functions/some-unlisted-fn/index.ts'), 'platform');
    });
  });

  group('mirrors (look-alikes keep their tier)', () {
    test('a sibling whose name only starts the same is not promoted', () {
      expect(tier('supabase/functions/clean-orphan-media-v2/index.ts'),
          'platform');
      expect(tier('supabase/functions/clean-orphan-medias/index.ts'),
          'platform');
    });

    test('the shared subscription helper stays platform', () {
      // readProState lives in _shared/subscription.ts. Seven other non-test files import it and none of them deletes
      // anything, so an edit there stays platform (a B-pass and a plan-review record, no hermes pass) ON PURPOSE:
      // the registry comment records this as a decision, not an oversight.
      expect(tier('supabase/functions/_shared/subscription.ts'), 'platform');
    });

    test('every other catastrophic function rule is untouched', () {
      // The new rule sits between delete-account and admin-*; a botched merge that dropped a neighbour must redden.
      for (final p in <String>[
        'supabase/functions/razorpay-webhook/index.ts',
        'supabase/functions/verify-payment/index.ts',
        'supabase/functions/delete-account/index.ts',
        'supabase/functions/admin-dashboard-data/index.ts',
        'supabase/functions/_shared/cron_auth.ts',
      ]) {
        expect(tier(p), 'catastrophic', reason: '$p lost its catastrophic rule');
      }
    });
  });

  group('rot (the glob names a directory that must still exist)', () {
    test('the directory holds the entry point and the sweep logic', () {
      final names = onDisk().map((p) => p.split('/').last).toSet();
      expect(names, containsAll(<String>['index.ts', 'logic.ts']),
          reason: 'a rename of the directory orphans the rule: update '
              'docs/blast_radius.yaml in the same commit');
    });
  });

  test('the real CLI agrees, and prints the MAX tier of a mixed diff', () {
    String cli(List<String> paths) {
      final r = runSpawn(
        'dart',
        ['run', 'scripts/blast_radius_from_diff.dart', ...paths],
        why: 'blast_radius_from_diff CLI on $paths',
        runInShell: true,
      );
      final m = RegExp(r'Blast-radius:\s*(\w+)')
          .firstMatch((r.stdout as String).trim());
      expect(m, isNotNull, reason: 'no tier printed for $paths:\n${r.stdout}');
      return m!.group(1)!;
    }

    expect(cli(['supabase/functions/_shared/subscription.ts']), 'platform',
        reason: 'control: the shared helper is platform');
    expect(cli(['$_dir/logic.ts']), 'catastrophic');
    for (final order in <List<String>>[
      ['lib/features/home/screens/home_screen.dart', '$_dir/index.ts'],
      ['$_dir/index.ts', 'lib/features/home/screens/home_screen.dart'],
    ]) {
      expect(cli(order), 'catastrophic',
          reason: 'one clean-orphan-media file in a mixed diff makes the whole '
              'diff catastrophic, in either order: $order');
    }
  });
}
