// Unit 8 (coach-media-consent, OI-25) — route + nav-entry pin for the
// Saved Photos screen.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../helpers/read_screen_source.dart';

void main() {
  late String routerSrc;
  late String profileSrc;

  setUpAll(() {
    routerSrc = File('lib/core/router/app_router.dart').readAsStringSync();
    profileSrc = readScreenSource('profile');
  });

  test('/profile/saved-coach-photos route exists in router', () {
    expect(routerSrc.contains("path: 'saved-coach-photos'"), isTrue,
        reason: 'Router must declare the saved-coach-photos sub-route '
            'under the /profile branch');
    expect(routerSrc.contains('SavedCoachPhotosScreen'), isTrue,
        reason: 'Route must build SavedCoachPhotosScreen');
  });

  test('saved-coach-photos route is nested under the /profile branch', () {
    // Cheap ordering check: the progress-photos sibling route (known to be
    // inside the /profile StatefulShellBranch) must appear BEFORE
    // saved-coach-photos in source, and both before the branch closes at
    // 'delete-account' (the last row in the same routes list per
    // app_router.dart). This guards against the route accidentally being
    // hoisted to top-level (which would drop the bottom-nav shell/tab bar).
    final progressIdx = routerSrc.indexOf("path: 'progress-photos'");
    final savedIdx = routerSrc.indexOf("path: 'saved-coach-photos'");
    final deleteAccountIdx = routerSrc.indexOf("path: 'delete-account'");
    expect(progressIdx, greaterThan(0));
    expect(savedIdx, greaterThan(progressIdx));
    expect(deleteAccountIdx, greaterThan(savedIdx),
        reason: 'saved-coach-photos must sit inside the same nested routes '
            'list as progress-photos and delete-account, not top-level');
  });

  test('Profile REPORTS card has a Saved Photos row navigating to the route',
      () {
    expect(profileSrc.contains("'Saved Photos'"), isTrue,
        reason: 'Profile must show a Saved Photos nav row');
    expect(profileSrc.contains("'/profile/saved-coach-photos'"), isTrue,
        reason: 'Saved Photos row must navigate to /profile/saved-coach-photos');
  });
}
