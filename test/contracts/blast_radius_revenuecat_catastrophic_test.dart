// test/contracts/blast_radius_revenuecat_catastrophic_test.dart
//
// OI-519 (+51, ADR-0022), B-pass of the U3 commit, finding F5: the Play payment path is catastrophic tier.
//
// revenuecat-webhook, revenuecat-sync and revenuecat-reconcile decide who is PRO from Google Play and send referral
// defers to Google; _shared/revenuecat_mirror.ts is their one writer of a Play subscriptions row. Before the rule they
// matched only the `supabase/functions/**` and `_shared/**` platform catch-alls, so a diff touching only them needed no
// commit-time review file and no hermes pass, unlike razorpay-webhook / verify-payment.
//
// Layers (the shape of blast_radius_clean_orphan_media_catastrophic_test.dart, without the CLI spawn):
//   1. CLASSIFICATION  every file on disk under each directory (DERIVED from the directory) and the mirror is
//                      catastrophic, and it is THIS rule that claims it, not a catch-all that happens to agree.
//   2. ORDER           first match wins: each rule sits above the `supabase/functions/**` catch-all.
//   3. MIRRORS         look-alikes keep their tier: verify-subscription stays account, a sibling whose name only starts
//                      the same is not promoted.
//   4. ROT             each directory exists and holds index.ts and logic.ts.
//
// Run: flutter test test/contracts/blast_radius_revenuecat_catastrophic_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// `as classifier`: that script also defines main().
import '../../scripts/blast_radius_from_diff.dart' as classifier;

const _dirs = [
  'supabase/functions/revenuecat-webhook',
  'supabase/functions/revenuecat-sync',
  'supabase/functions/revenuecat-reconcile',
];
const _mirrorGlob = 'supabase/functions/_shared/revenuecat_mirror*.ts';
const _catchAll = 'supabase/functions/**';

void main() {
  final reg = classifier
      .parseRegistry(File('docs/blast_radius.yaml').readAsStringSync());
  String tier(String p) => classifier.tierFor(p, reg);
  int indexOfGlob(String g) => reg.rules.indexWhere((r) => r.glob == g);
  classifier.TierRule? ruleFor(String p) {
    for (final r in reg.rules) {
      if (classifier.globToRegExp(r.glob).hasMatch(p)) return r;
    }
    return null;
  }

  test('1. every file of the three functions and the mirror is catastrophic, claimed by its own rule', () {
    for (final d in _dirs) {
      final files = Directory(d)
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path.replaceAll(Platform.pathSeparator, '/'))
          .toList();
      expect(files, isNotEmpty, reason: d);
      for (final f in files) {
        expect(tier(f), 'catastrophic', reason: f);
        expect(ruleFor(f)?.glob, '$d/**', reason: f);
      }
    }
    for (final f in [
      'supabase/functions/_shared/revenuecat_mirror.ts',
      'supabase/functions/_shared/revenuecat_mirror_test.ts',
    ]) {
      expect(tier(f), 'catastrophic', reason: f);
      expect(ruleFor(f)?.glob, _mirrorGlob, reason: f);
    }
  });

  test('2. each rule sits above the supabase/functions/** catch-all', () {
    final catchAll = indexOfGlob(_catchAll);
    expect(catchAll, greaterThanOrEqualTo(0));
    for (final g in [..._dirs.map((d) => '$d/**'), _mirrorGlob]) {
      final i = indexOfGlob(g);
      expect(i, greaterThanOrEqualTo(0), reason: 'missing rule $g');
      expect(i, lessThan(catchAll), reason: g);
    }
  });

  test('3. look-alikes keep their tier', () {
    expect(tier('supabase/functions/verify-subscription/index.ts'), 'account');
    expect(ruleFor('supabase/functions/revenuecat-sync-preview/index.ts')?.glob,
        isNot('supabase/functions/revenuecat-sync/**'));
    expect(ruleFor('supabase/functions/_shared/revenuecat_other.ts')?.glob,
        isNot(_mirrorGlob));
  });

  test('4. the directories and the mirror exist', () {
    for (final d in _dirs) {
      expect(File('$d/index.ts').existsSync(), isTrue, reason: d);
      expect(File('$d/logic.ts').existsSync(), isTrue, reason: d);
    }
    expect(File('supabase/functions/_shared/revenuecat_mirror.ts').existsSync(),
        isTrue);
  });
}
