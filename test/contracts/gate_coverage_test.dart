// Regression test for audit 2026-05-16 / F8.1 (gate coverage) + E.8 (dead
// code deletions) + E.9 (inline isPro audit).
//
// Bugs:
// - F8.1: `featurePhotoAnalysis` was documented as PRO in CLAUDE.md §14
//   but had ZERO `gate()` callsites. Free users could silently upload
//   photos to AI coach chat; ai-media-proxy server-side check produced
//   a hard error rather than a paywall.
// - E.8 dead code: 3 feature constants (featureActiveWorkoutMode,
//   featureVoiceNotes, featureDietPlanPdf) had 0 callsites + were
//   documented as FREE in CLAUDE.md §14. Plus MySubmissionsScreen +
//   softDeleteAccount had 0 callers for 3 weeks.
// - E.9: 9 `if (isPro)` widget locations were audited per-callsite.
//   ALL VERIFIED OK — 4 are constructor-prop reads with reactive callers,
//   3 are action callbacks (read fresh at action time is correct), 2 are
//   notifier methods (no UI-reactivity bug). The audit (Agent 7 F8.3)
//   surfaced the pattern as worth checking, not as a confirmed bug.
//   This test pins the verified-OK state.
//
// closes-diagnose: 2026-05-16-gate-coverage-and-dead-code

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/read_screen_source.dart';

void main() {
  group('Audit-2026-05-16 / E.8 + F8.1 — gate coverage + dead code', () {
    test('featurePhotoAnalysis HAS a client gate() callsite', () {
      // F8.1 fix — entry point at _pickImage in ai_coach_screen.dart now
      // routes through SubscriptionService.gate(featurePhotoAnalysis, ...).
      final src =
          readScreenSource('ai_coach');
      final hasGate =
          RegExp(r'\.gate\([^)]*featurePhotoAnalysis').hasMatch(src);
      expect(hasGate, isTrue,
          reason:
              'Pre-fix _pickImage had no client paywall — free users could '
              'tap "send photo" and only fail at ai-media-proxy server '
              'response. F8.1 closes by routing through SubscriptionService.gate().');
    });

    test('3 dead feature constants no longer exist', () {
      final src =
          File('lib/core/constants/app_constants.dart').readAsStringSync();
      // Match: `static const String featureActiveWorkoutMode =` (definition).
      // Free in audit comment doesn't count.
      final activeWorkoutDef = RegExp(
        r'static\s+const\s+String\s+featureActiveWorkoutMode\s*=',
      ).hasMatch(src);
      final voiceNotesDef = RegExp(
        r'static\s+const\s+String\s+featureVoiceNotes\s*=',
      ).hasMatch(src);
      final dietPlanPdfDef = RegExp(
        r'static\s+const\s+String\s+featureDietPlanPdf\s*=',
      ).hasMatch(src);
      expect(activeWorkoutDef, isFalse,
          reason:
              'featureActiveWorkoutMode was deleted in audit-2026-05-16 E.8 '
              '(free since Test #2 Q6 / 2026-04-25, 0 callsites for 3 weeks).');
      expect(voiceNotesDef, isFalse,
          reason:
              'featureVoiceNotes was deleted in audit-2026-05-16 E.8 '
              '(free since Test #9 F13, 0 callsites since).');
      expect(dietPlanPdfDef, isFalse,
          reason:
              'featureDietPlanPdf was deleted in audit-2026-05-16 E.8 '
              '(documented FREE per CLAUDE.md §14, 0 callsites ever).');
    });

    test('MySubmissionsScreen file no longer exists', () {
      final file = File('lib/features/profile/screens/my_submissions_screen.dart');
      expect(file.existsSync(), isFalse,
          reason:
              'audit-2026-05-16 E.8 deleted MySubmissionsScreen. '
              'Canonical screen is /profile/submissions (SubmissionsScreen).');
    });

    test('softDeleteAccount method no longer exists', () {
      final src =
          File('lib/shared/repositories/user_repository.dart').readAsStringSync();
      expect(src.contains('static Future<void> softDeleteAccount'), isFalse,
          reason:
              'audit-2026-05-16 E.8 deleted softDeleteAccount. Hard-delete '
              'via delete-account Edge Function is canonical.');
    });

    test('legacy /profile/my-submissions route is gone from app_router', () {
      final src = File('lib/core/router/app_router.dart').readAsStringSync();
      expect(src.contains("'my-submissions'"), isFalse,
          reason:
              'audit-2026-05-16 E.8 removed the legacy route. Founder '
              'approved NEEDS_DECISION 2 Option A after 3 weeks of zero '
              'deep-link hits in client_errors.');
      // Detect ACTIVE references (constructor calls + type annotations),
      // not the audit comment that documents the removal.
      expect(src.contains('const MySubmissionsScreen('), isFalse,
          reason:
              'No remaining MySubmissionsScreen() constructor call in router. '
              '(Audit-comment references are allowed — they document the removal.)');
      expect(src.contains('my_submissions_screen.dart'), isFalse,
          reason:
              'Stale import of deleted file must not linger in the router.');
    });

    test('E.9 — inline `if (isPro)` widget sites are bounded to known callsites', () {
      // Audit Agent 7 F8.3 flagged 9 `if (isPro)` sites as POTENTIAL_BUG.
      // Phase C per-callsite verification showed all 9 are actually correct:
      //   - 4 constructor-prop sites (caller watches subscriptionInfoProvider)
      //   - 3 action callbacks (read fresh at action time is correct)
      //   - 2 notifier methods (no UI-reactivity bug)
      // This test bounds the count to prevent silent regrowth.
      const featurePaths = [
        'lib/features/ai_coach/providers/ai_coach_provider.dart',
        'lib/features/profile/screens/edit_profile_screen.dart',
        'lib/features/profile/screens/notification_settings_screen.dart',
        'lib/features/profile/widgets/weekly_report_card.dart',
      ];
      int total = 0;
      for (final p in featurePaths) {
        final src = File(p).readAsStringSync();
        total += RegExp(r'if\s*\(\s*isPro\b').allMatches(src).length;
      }
      // Split screens (audit-2026-05-20 / C4) — read folder contents.
      for (final screen in const ['ai_coach', 'profile']) {
        final src = readScreenSource(screen);
        total += RegExp(r'if\s*\(\s*isPro\b').allMatches(src).length;
      }
      expect(total, lessThanOrEqualTo(12),
          reason:
              'Inline `if (isPro)` count grew beyond the audit-verified '
              'set (was 9). Any new site MUST be audited: is the read in '
              'a build method (then needs `ref.watch(subscriptionInfoProvider).isPro`) '
              'or in a callback / notifier method (read-fresh is correct)? '
              'Update this test bound only after per-site verification. '
              'Found $total.');
    });
  });
}
