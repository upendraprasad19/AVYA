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
    // Comment-stripped: the Photos row must be live code, not a commented-out one.
    profileSrc = readScreenSourceStripped('profile');
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

  test('Profile has ONE Photos row to the hub; the hub routes to Saved', () {
    // The Saved Photos row moved off the Profile tab into UserPhotosScreen
    // (one "Photos" row on Profile -> hub -> Progress | Saved).
    expect(profileSrc.contains("title: 'Photos'"), isTrue,
        reason: 'Profile must show the single Photos hub row');
    expect(profileSrc.contains("'/profile/photos'"), isTrue,
        reason: 'Photos row must navigate to /profile/photos');
    final hubSrc = File('lib/features/profile/screens/user_photos_screen.dart')
        .readAsStringSync();
    expect(hubSrc.contains("'/profile/saved-coach-photos'"), isTrue,
        reason: 'Hub Saved row must navigate to /profile/saved-coach-photos');
  });
}
