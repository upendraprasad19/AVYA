// test/contracts/blast_radius_data_deleting_paths_catastrophic_test.dart
//
// Founder decision 2026-10-11 ("okay catastrophic"), asked at the close of OI-321 — the two Edge Function paths that
// delete user data and were not yet catastrophic:
//   * `supabase/functions/rolling-context/**`  the nightly cron that summarises, and tries to embed, a user's older
//     `ai_coach_interactions` turns and then DELETES them, keeping the newest ten (the `.delete().in("id", batch)` loop
//     in index.ts; a database row delete, not a Storage one). The embedding is best-effort: a turn whose embedding failed is deleted all the same.
//   * `supabase/functions/_shared/purge_user_storage*.ts`  the account-deletion Storage purge (and its Deno test). Its
//     only production caller, delete-account/index.ts, is already catastrophic, but a diff confined to the purge does
//     not touch that directory and was platform through `_shared/**`.
// Before the rules both classified platform, so a diff that touched only them needed no hermes pass and no
// commit-time review file.
//
// Six layers, each answering a different question (the shape of blast_radius_clean_orphan_media_catastrophic_test.dart):
//   1. CLASSIFICATION  every file on disk under rolling-context/ and every purge_user_storage*.ts is catastrophic, and
//                      it is the NEW rule that claims it (not a later catch-all that happened to agree), per the
//                      classifier AND the commit-time review gate's own copy of the rules reader. File lists are
//                      DERIVED from disk, so a file added later is covered without editing this test.
//   2. ORDER           first match wins: the rolling rule must sit above the `supabase/functions/**` catch-all and the
//                      purge rule above BOTH `_shared/**` and the catch-all, or it would classify nothing.
//   3. MIRRORS         look-alikes keep their tier: the bucket list and the shared helpers stay platform ON PURPOSE
//                      (promoting a shared helper would raise every function that imports it), and the six earlier
//                      catastrophic function rules are untouched.
//   4. ROT             the rules name things that must still be what the tier is for: rolling-context still deletes,
//                      the purge still removes, delete-account still calls it.
//   5. DERIVED         the CLASS, not only the two named paths: a scan of every non-test Edge Function source for a
//                      direct deleting call; each file it finds must be catastrophic, so the next deleter is judged
//                      without anyone editing this test. The matcher has literal self-checks.
//   6. CLI             the real classifier prints the MAX tier of a mixed diff in either path order.
// Four copies of the registry reader exist; this file imports two (the classifier and the commit-time review gate).
// check_blast_radius_coverage.dart's copy is public but irrelevant (it only checks that every path has SOME tier). The
// merge-time keystone (check_plan_review_record_exists.dart, which demands `hermes: accepted`) keeps a PRIVATE copy and
// is covered end to end by the four `catastrophic path (rolling-context/ | purge_user_storage | mixed diff)` cases in
// test/scripts/plan_review_record_gate_e2e_test.dart. The keystone's copy and the commit-time review gate's copy compile
// with `dotAll: true` (the gate's since landing C1, which also made it read its staged paths with `-z`, so git no longer
// C-quotes a name out of its globs: test/contracts/merge_scope_gate_e2e_test.dart G7c); the classifier's copy and the
// coverage checker's do not (a line terminator inside a file name falls through `**` to the default tier in those two;
// OI-337 stays open for the classifier). Only the purge glob is insensitive to it (`[^/]*` and an escaped dot); the
// rolling glob ends in `**`, which compiles to `.*`, so in the two non-dotAll copies a name with a line terminator under
// rolling-context/ would fall through to the default.
//
// Run: flutter test test/contracts/blast_radius_data_deleting_paths_catastrophic_test.dart

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

const _rollingGlob = 'supabase/functions/rolling-context/**';
const _rollingDir = 'supabase/functions/rolling-context';
const _purgeGlob = 'supabase/functions/_shared/purge_user_storage*.ts';
const _shared = 'supabase/functions/_shared';
const _sharedGlob = 'supabase/functions/_shared/**';
const _catchAll = 'supabase/functions/**';

/// A direct deleting call in comment-stripped Edge Function source: the PostgREST `.delete()`, Storage `.remove(`,
/// Auth `.deleteUser(`, SQL `DELETE FROM` in a string, and a raw HTTP DELETE (`method: "DELETE"`). A delete through an
/// RPC, or through some other library, is NOT detected.
final _deleting = RegExp(
    r'\.delete\(\)|\.remove\(|\.deleteUser\(|\bDELETE\s+FROM\b|method\s*:\s*["\x27]DELETE["\x27]',
    caseSensitive: false);

/// Both test-file conventions exist under supabase/functions (`index_test.ts` and `sanitize_for_prompt.test.ts`).
bool _isTestSource(String path) =>
    path.endsWith('_test.ts') || path.endsWith('.test.ts');

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

  /// Every file under the function directory, as repo-relative POSIX paths.
  List<String> rollingOnDisk() => Directory(_rollingDir)
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path.replaceAll('\\', '/'))
      .toList()
    ..sort();

  /// Every `purge_user_storage*.ts` in _shared (the module, its test, and any later split-off).
  List<String> purgeOnDisk() => Directory(_shared)
      .listSync()
      .whereType<File>()
      .map((f) => f.path.replaceAll('\\', '/'))
      .where((p) {
        final n = p.split('/').last;
        return n.startsWith('purge_user_storage') && n.endsWith('.ts');
      })
      .toList()
    ..sort();

  /// Comment-stripped source, so a premise pin cannot be satisfied by prose.
  String code(String path) => File(path)
      .readAsStringSync()
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ')
      .replaceAll(RegExp(r'//[^\n]*'), ' ');

  group('classification (derived from disk)', () {
    test('every file under rolling-context/ is catastrophic, claimed by its own rule',
        () {
      final files = rollingOnDisk();
      expect(files, isNotEmpty);
      for (final p in files) {
        expect(tier(p), 'catastrophic', reason: '$p is not catastrophic');
        expect(ruleFor(p)?.glob, _rollingGlob,
            reason: '$p is claimed by ${ruleFor(p)?.glob}, not $_rollingGlob');
      }
    });

    test('the purge module and its Deno test are catastrophic, claimed by the purge rule',
        () {
      final files = purgeOnDisk();
      expect(files.map((p) => p.split('/').last),
          containsAll(<String>[
            'purge_user_storage.ts',
            'purge_user_storage_test.ts'
          ]),
          reason: 'the derived list must hold the module and its test');
      for (final p in files) {
        expect(tier(p), 'catastrophic', reason: '$p is not catastrophic');
        expect(ruleFor(p)?.glob, _purgeGlob,
            reason: '$p is claimed by ${ruleFor(p)?.glob}, not $_purgeGlob');
      }
    });

    test('the commit-time review gate\'s own engine reads all of them as catastrophic too',
        () {
      // That gate decides whether a commit needs a STAGED accepted review. It parses the registry with its own copy
      // of the rules reader, so the classifier tests above do not cover it.
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

      for (final p in rollingOnDisk()) {
        expect(gateRule(p), (glob: _rollingGlob, tier: 'catastrophic'),
            reason: '$p, per the review gate');
      }
      for (final p in purgeOnDisk()) {
        expect(gateRule(p), (glob: _purgeGlob, tier: 'catastrophic'),
            reason: '$p, per the review gate');
      }
      expect(gateRule('$_shared/user_owned_buckets.ts').tier, 'platform',
          reason: 'control: the gate engine also keeps the bucket list platform');
    });

    test('a file that does not exist yet is covered too (a new sibling or split-off)',
        () {
      // tierFor is a pure glob match, so a path never written still classifies: the rules, not an exact-path list,
      // are what cover tomorrow's file.
      expect(tier('$_rollingDir/some_future_helper.ts'), 'catastrophic');
      expect(tier('$_rollingDir/nested/deeper/x.ts'), 'catastrophic');
      expect(tier('$_shared/purge_user_storage_chunked.ts'), 'catastrophic');
      expect(tier('$_shared/purge_user_storage_chunked_test.ts'), 'catastrophic');
    });

    test('and so is a rolling-context file of any kind, not only .ts (docs, fixtures, dotfiles)',
        () {
      // A rule inserted above the rolling rule for a file KIND (`*.md`, `fixtures/**`) would otherwise slip through
      // while every .ts probe above stays green.
      for (final name in [
        'README.md',
        'CLAUDE.md',
        'fixtures/sample.json',
        'fixtures/nested/rows.sql',
        '.hidden',
        'nested/.env.example',
        'deno.json',
      ]) {
        expect(tier('$_rollingDir/$name'), 'catastrophic',
            reason: '$_rollingDir/$name');
      }
    });
  });

  group('order (first match wins)', () {
    test('the rolling rule sits above the supabase/functions/** catch-all', () {
      final globs = reg.rules.map((r) => r.glob).toList();
      expect(globs, contains(_rollingGlob));
      expect(globs, contains(_catchAll));
      expect(globs.indexOf(_rollingGlob), lessThan(globs.indexOf(_catchAll)),
          reason: 'below the catch-all the rule would classify nothing');
    });

    test('the purge rule sits above BOTH _shared/** and the catch-all', () {
      final globs = reg.rules.map((r) => r.glob).toList();
      expect(globs, contains(_purgeGlob));
      expect(globs, contains(_sharedGlob));
      expect(globs.indexOf(_purgeGlob), lessThan(globs.indexOf(_sharedGlob)),
          reason: 'the purge module lives in _shared/, which the platform '
              'rule `$_sharedGlob` claims first if it sits above');
      expect(globs.indexOf(_purgeGlob), lessThan(globs.indexOf(_catchAll)));
    });

    test('every rule above the rolling rule and above the purge rule is catastrophic', () {
      // The sampled file kinds in the tests above cannot cover a kind nobody thought of (*.yaml, *.txt, *.lock, *.sh,
      // *.js, *.snap, ...): a lower-tier rule for it inserted ABOVE these rules would claim those files first and every
      // sampled assertion would stay green. The registry header says catastrophic globs are listed first; this pins it
      // for exactly the region that can shadow these rules, which also covers clean-orphan-media/** (it sits above the
      // purge rule).
      for (final glob in [_rollingGlob, _purgeGlob]) {
        final idx = reg.rules.indexWhere((r) => r.glob == glob);
        expect(idx, greaterThanOrEqualTo(0), reason: '$glob is not in the registry');
        for (final r in reg.rules.take(idx)) {
          expect(r.tier, 'catastrophic',
              reason: '`${r.glob}` (${r.tier}) sits above `$glob` and would '
                  'claim some of its files first');
        }
      }
    });

    test('control: _shared/** alone and the catch-all alone are platform, so the tier did change',
        () {
      // If either stops being platform the assertions above could be passing for a different reason.
      expect(ruleFor('$_shared/some_unlisted_helper.ts')?.glob, _sharedGlob);
      expect(tier('$_shared/some_unlisted_helper.ts'), 'platform');
      expect(ruleFor('supabase/functions/some-unlisted-fn/index.ts')?.glob,
          _catchAll);
      expect(tier('supabase/functions/some-unlisted-fn/index.ts'), 'platform');
    });
  });

  group('mirrors (look-alikes keep their tier)', () {
    test('a sibling directory whose name only starts the same is not promoted',
        () {
      expect(tier('supabase/functions/rolling-context-v2/index.ts'), 'platform');
      expect(tier('supabase/functions/rolling-contexts/index.ts'), 'platform');
      expect(tier('supabase/functions/rolling/index.ts'), 'platform');
      // A PREFIX on the name must not promote it either (a `*rolling-context/**` wildcard would).
      expect(tier('supabase/functions/old-rolling-context/index.ts'), 'platform');
    });

    test('a different _shared name is not promoted by the purge wildcard', () {
      // Each name closes one way to widen the glob: a prefix (`*purge_user_storage*`), a dropped extension
      // (`purge_user_storage*` would take the .md), a different stem.
      for (final n in [
        'purge_expired.ts',
        'purge.ts',
        'user_purge_storage.ts',
        'old_purge_user_storage.ts',
        'storage_purge.ts',
        'purge_user_storage.md',
        'purge_user_storage.ts.bak',
      ]) {
        expect(tier('$_shared/$n'), 'platform', reason: '$_shared/$n');
      }
    });

    test('LIMIT, pinned so that changing it is a decision: a purge split into a SUBDIRECTORY is platform', () {
      // `*` does not cross `/`, so `purge_user_storage*.ts` claims names directly in _shared/ only. A future split
      // into `_shared/purge_user_storage/...` would not inherit the tier; whoever does that must add a rule (and this
      // test will tell them, because widening the glob to `**` reddens it).
      expect(tier('$_shared/purge_user_storage/chunker.ts'), 'platform');
    });

    test('the bucket list and the shared helpers rolling-context imports stay platform',
        () {
      // Platform ON PURPOSE (the registry comment records it as a decision). The bucket list is tied to the client's
      // writes by delete_account_purges_all_user_buckets_test.dart, and purge_user_storage_test.ts pins its five names,
      // so a change to what it contains also edits a catastrophic file (only a comment-only edit stays platform).
      // Promoting a shared helper would raise every function that imports it, not the delete. Asserted only for
      // files that exist, so a ghost cannot pass.
      for (final n in [
        'user_owned_buckets.ts',
        'embeddings.ts',
        'gemini.ts',
        'gemini_failure_alert.ts',
        'paged_fetch.ts',
        'cron_telemetry.ts',
        'sanitize_for_prompt.ts',
      ]) {
        expect(File('$_shared/$n').existsSync(), isTrue,
            reason: '$_shared/$n no longer exists: update this list');
        expect(tier('$_shared/$n'), 'platform', reason: '$_shared/$n');
      }
    });

    test('every earlier catastrophic function rule is untouched', () {
      // The new rules sit beside admin-* and cron_auth.ts; a botched merge that dropped a neighbour must redden.
      for (final p in <String>[
        'supabase/functions/razorpay-webhook/index.ts',
        'supabase/functions/verify-payment/index.ts',
        'supabase/functions/delete-account/index.ts',
        'supabase/functions/clean-orphan-media/index.ts',
        'supabase/functions/admin-dashboard-data/index.ts',
        'supabase/functions/_shared/cron_auth.ts',
      ]) {
        expect(tier(p), 'catastrophic', reason: '$p lost its catastrophic rule');
      }
    });
  });

  group('rot (the rules name things that must still be what the tier is for)', () {
    test('rolling-context still holds its entry point and test, and still deletes rows',
        () {
      final names = rollingOnDisk().map((p) => p.split('/').last).toSet();
      expect(names, containsAll(<String>['index.ts', 'index_test.ts']),
          reason: 'a rename of the directory orphans the rule: update '
              'docs/blast_radius.yaml in the same commit');
      // The premise of the tier: the function deletes. Comment-stripped, so prose cannot satisfy it.
      final src = code('$_rollingDir/index.ts');
      expect(RegExp(r'\.from\(\s*"ai_coach_interactions"\s*\)\s*\.delete\(\)')
          .hasMatch(src), isTrue,
          reason: 'rolling-context no longer deletes ai_coach_interactions '
              'rows; if the delete moved, move the rule with it');
    });

    test('the purge still removes objects and delete-account still calls it', () {
      final purge = code('$_shared/purge_user_storage.ts');
      expect(purge, contains('export async function purgeUserStorage'));
      expect(RegExp(r'\.remove\(').hasMatch(purge), isTrue,
          reason: 'the purge no longer removes anything; the rule is stale');
      final da = code('supabase/functions/delete-account/index.ts');
      expect(da, contains('../_shared/purge_user_storage.ts'));
      expect(RegExp(r'await\s+purgeUserStorage\(').hasMatch(da), isTrue,
          reason: 'delete-account no longer calls the purge');
    });
  });

  group('derived (the class, not only the two named paths)', () {
    /// Non-test Edge Function sources that call a deleting API directly, found by SCANNING the tree, so a new
    /// deleter (the deleted-user Storage sweep, unit a4 of docs/plans/2026-09-26-single-owner-batch-a.md, will be one)
    /// is judged without anyone editing this test. Comment-stripped, so prose cannot trigger or satisfy it.
    List<String> deleters() => (Directory('supabase/functions')
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => f.path.replaceAll('\\', '/'))
            .where((p) => p.endsWith('.ts') && !_isTestSource(p))
            .where((p) => _deleting.hasMatch(code(p)))
            .toList()
          ..sort());

    /// Path -> reason. Near-empty on purpose (one entry, a test harness): a file that deletes something that is NOT user data (a cache, a temp row)
    /// would have to be named here with its reason, which is the decision this check exists to force.
    const allowlist = <String, String>{
      // OI-341 Piece A test harness: `Deno.remove(<its own temp dir>)` after importing the unmodified origin/main
      // writer copy. It never runs in an Edge Function and touches no user data (only a directory it created with
      // Deno.makeTempDir in the same function). The harness lives in `_shared/` but is imported by tests only.
      'supabase/functions/_shared/payment_writer_harness.ts': 'removes the temp dir it created for a test import',
    };

    test('self-check: the matcher recognises each deleting form and ignores look-alikes', () {
      // Literal inputs, so that dropping or weakening an arm of the regex is noticed even where no file in the tree
      // exercises that arm today (nothing uses `DELETE FROM`; only delete-account uses a raw HTTP DELETE).
      for (final yes in [
        'await s.from(b).remove([p]);',
        'c.from("t").delete().eq("id", 1)',
        'await admin.auth.admin.deleteUser(id)',
        'DELETE FROM t WHERE x = 1',
        'delete from t',
        'fetch(u, { method: "DELETE" })',
        "fetch(u, {method:'DELETE'})",
      ]) {
        expect(_deleting.hasMatch(yes), isTrue, reason: 'should match: $yes');
      }
      for (final no in [
        'cache.delete(key)',
        'const deleted = true',
        'deleteUserAccount(id)',
        'x.removeItem(k)',
        'fetch(u, { method: "GET" })',
      ]) {
        expect(_deleting.hasMatch(no), isFalse, reason: 'should NOT match: $no');
      }
      for (final yes in ['a/b_test.ts', 'a/b.test.ts']) {
        expect(_isTestSource(yes), isTrue, reason: yes);
      }
      for (final no in ['a/index.ts', 'a/latest.ts', 'a/contest.ts']) {
        expect(_isTestSource(no), isFalse, reason: no);
      }
    });

    test('positive control: the scan finds the four known deleters (it cannot go blind)', () {
      expect(
          deleters(),
          containsAll(<String>[
            'supabase/functions/_shared/purge_user_storage.ts',
            'supabase/functions/clean-orphan-media/logic.ts',
            'supabase/functions/delete-account/index.ts',
            'supabase/functions/rolling-context/index.ts',
          ]));
    });

    test('every non-test Edge Function file that deletes is catastrophic', () {
      final notCatastrophic = {
        for (final p in deleters())
          if (tier(p) != 'catastrophic' && !allowlist.containsKey(p)) p: tier(p),
      };
      expect(notCatastrophic, isEmpty,
          reason: 'These files call .delete() / .remove() / deleteUser / DELETE FROM and are below catastrophic. '
              'Add a registry rule in docs/blast_radius.yaml (first match wins, above the platform block), or, if '
              'what they delete is not user data, name each in `allowlist` here with the reason.');
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

    expect(cli(['$_shared/user_owned_buckets.ts']), 'platform',
        reason: 'control: the bucket list is platform');
    expect(cli(['$_rollingDir/index.ts']), 'catastrophic');
    expect(cli(['$_shared/purge_user_storage.ts']), 'catastrophic');
    expect(cli(['$_shared/purge_user_storage_test.ts']), 'catastrophic');
    for (final target in ['$_rollingDir/index.ts', '$_shared/purge_user_storage.ts']) {
      for (final order in <List<String>>[
        ['lib/features/home/screens/home_screen.dart', target],
        [target, 'lib/features/home/screens/home_screen.dart'],
      ]) {
        expect(cli(order), 'catastrophic',
            reason: 'one catastrophic file in a mixed diff makes the whole '
                'diff catastrophic, in either order: $order');
      }
    }
  });
}
