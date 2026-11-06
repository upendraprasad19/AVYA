// test/contracts/paywall_feature_label_test.dart
//
// Contract for OI-76 (paywall half) — `PaywallSheet.feature` is a DISPLAY
// STRING, not a feature id, and one call site was passing an id.
//
// WHY THIS IS A USER-VISIBLE BUG, NOT A LABELLING NIT
// ---------------------------------------------------
// `paywall_sheet.dart` renders the value verbatim into the letterhead
// ("<feature> is a PRO feature") and switches on display strings for the
// subtitle copy. `profile_content.dart` passed
// `AppConstants.featureProgressPhotos` — the literal `'progress_photos'` — so a
// free user tapping a locked notification row was shown:
//
//     "progress_photos is a PRO feature"
//
// plus the generic default subtitle, plus a `paywall_shown` telemetry value
// that split that surface off from every other paywall in the funnel. It was
// the only one of ~25 call sites passing a snake_case constant.
//
// The board entry for OI-76 also claimed §4.4 r19 keyed server-side
// verification off this id. It does not: `showPaywallSheet` is display +
// telemetry only and never reaches `gate()` / `verifyFromServer()`. That claim
// is corrected on the board in the same commit as this test.
//
// This is a SOURCE-GREP test (presence class). It cannot prove rendering, so it
// pins the two things a grep genuinely can: no call site passes an
// `AppConstants.feature*` constant, and every label the notification rows can
// send has real subtitle copy rather than falling through to the default.
//
// Run: flutter test test/contracts/paywall_feature_label_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _paywall = 'lib/shared/widgets/paywall_sheet.dart';
const _profileContent =
    'lib/features/profile/screens/profile/profile_content.dart';
const _settings = 'lib/features/profile/screens/settings_screen.dart';
const _notifSettings =
    'lib/features/profile/screens/notification_settings_screen.dart';

/// The row titles the notification screen can hand to the paywall. These are
/// the exact `title:` values on the two `isProFeature` rows.
const _lockedRowLabels = <String>['Protein Alerts', 'Plateau Check'];

void main() {
  group('OI-76 — paywall receives display strings, never feature ids', () {
    test('no showPaywallSheet call site passes an AppConstants.feature* id',
        () {
      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final src = entity.readAsStringSync();
        if (!src.contains('showPaywallSheet')) continue;

        // Match `feature: AppConstants.featureXxx` in any spacing/line layout.
        final bad = RegExp(r'feature:\s*AppConstants\.feature\w+')
            .allMatches(src)
            .map((m) => m.group(0)!);
        for (final b in bad) {
          offenders.add('${entity.path}: $b');
        }
      }

      expect(offenders, isEmpty,
          reason: 'PaywallSheet renders `feature` verbatim as '
              '"<feature> is a PRO feature" and switches on display strings '
              'for its subtitle. A snake_case id shows the user the raw '
              'identifier and drops to generic copy.\n'
              'Offenders:\n  ${offenders.join("\n  ")}');
    });

    test('every locked notification row label has real subtitle copy', () {
      final paywallSrc = File(_paywall).readAsStringSync();

      for (final label in _lockedRowLabels) {
        expect(paywallSrc, contains("case '$label':"),
            reason: "_featureSubtitle has no case for '$label', so tapping "
                'that locked row falls through to the generic default copy');
      }
    });

    test('the locked rows are the labels the screen actually sends', () {
      final notifSrc = File(_notifSettings).readAsStringSync();

      // Guards the pairing above: if a row title is renamed without adding the
      // matching paywall case, the previous test would still pass against a
      // stale constant. This ties the constant back to the source.
      for (final label in _lockedRowLabels) {
        expect(notifSrc, contains("title: '$label'"),
            reason: 'no notification row is titled "$label" any more — update '
                '_lockedRowLabels and the paywall cases together');
      }
    });

    test('the locked-tap callback carries the tapped row identity', () {
      final notifSrc = File(_notifSettings).readAsStringSync();

      expect(notifSrc, contains('ValueChanged<String>? onProLockedTap'),
          reason: 'a no-arg VoidCallback cannot tell the paywall WHICH locked '
              'row was tapped, so both rows would show one feature\'s copy');
      expect(notifSrc, contains('onLockedTap!(title)'),
          reason: 'the row must pass its own title through');
    });

    test('both entry points into notification settings supply isPro', () {
      // The route defaults `isPro` to false when `extra` is absent, which
      // showed a paying PRO user a lock. Profile passes it; Settings did not.
      for (final path in <String>[_profileContent, _settings]) {
        expect(File(path).readAsStringSync(), contains("'isPro'"),
            reason: '$path pushes /profile/notification-settings without '
                'isPro, so the route defaults it to false and locks the two '
                'PRO rows for a paying user');
      }
    });
  });
}
