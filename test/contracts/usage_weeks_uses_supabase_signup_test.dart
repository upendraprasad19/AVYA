// Bug 2026-05-20 (diagnose c2a91f) regression test — pins UsageWeeksNotifier
// to read SupabaseService.instance.currentUser?.createdAt as the source
// of "how many weeks has this user been around".
//
// Pre-fix it read configBox['first_launch_date']. That key was never
// written anywhere in the codebase, so usageWeeks was always 0 → the
// Weekly Report card on Profile permanently locked at "Available after
// Week 1" and tapping it did nothing.

import 'dart:io';
import 'package:test/test.dart';

String _stripComments(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('UsageWeeksNotifier — source-grep contract', () {
    final src =
        File('lib/features/profile/providers/profile_provider.dart').readAsStringSync();
    final stripped = _stripComments(src);

    test('reads currentUser?.createdAt (post-fix source)', () {
      expect(
        stripped.contains(
            'SupabaseService.instance.currentUser?.createdAt'),
        isTrue,
        reason: 'UsageWeeksNotifier.build() must read the Supabase signup '
            'timestamp via SupabaseService.instance.currentUser?.createdAt. '
            'Same source as rank_service / referral_eligibility / '
            'service_record_section / rank_ladder_screen.',
      );
    });

    test('no longer reads dead configBox[first_launch_date] key', () {
      expect(
        stripped.contains("'first_launch_date'") ||
            stripped.contains('"first_launch_date"'),
        isFalse,
        reason: 'first_launch_date was never written anywhere in the codebase '
            '(verified by repo-wide grep) so reading it always returned null '
            'and usageWeeks was always 0. The key must be gone from production '
            'code (comments are stripped before this check).',
      );
    });

    test('UsageWeeksNotifier exists and is the consumer of the new source',
        () {
      // Locate the notifier class body and confirm createdAt is read inside it
      // (not somewhere unrelated in the file).
      final classIdx = stripped.indexOf('class UsageWeeksNotifier');
      expect(classIdx, isNonNegative,
          reason: 'UsageWeeksNotifier class moved or renamed — re-baseline.');
      // Look ~800 chars from the class start; the build() body is short.
      final end = (classIdx + 1000).clamp(0, stripped.length);
      final body = stripped.substring(classIdx, end);
      expect(
        body.contains('currentUser?.createdAt'),
        isTrue,
        reason: 'The createdAt read must be inside the UsageWeeksNotifier '
            'class body, not a stale reference elsewhere.',
      );
    });
  });

  group('Repo-wide invariant — first_launch_date stays dead', () {
    test('first_launch_date appears nowhere in lib/', () {
      // Walk lib/ and assert no .dart file references the dead key.
      // If anyone re-introduces a writer + reader pair later, they'll do it
      // intentionally and this test will fail loudly so the new contract
      // gets pinned in the registry.
      final dir = Directory('lib');
      final offenders = <String>[];
      for (final f in dir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = _stripComments(f.readAsStringSync());
        if (src.contains("'first_launch_date'") ||
            src.contains('"first_launch_date"')) {
          offenders.add(f.path.replaceAll(r'\', '/'));
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'first_launch_date is intentionally dead. If you need a '
            '"first launch" timestamp, use SupabaseService.instance.currentUser'
            '?.createdAt (5 callsites use it already). If you have a reason '
            'to bring this key back, write a writer + reader pair AND update '
            'this test and docs/sot_registry.yaml.',
      );
    });
  });
}
