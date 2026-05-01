import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late String routerSrc;
  late String profileSrc;

  setUpAll(() {
    routerSrc = File('lib/core/router/app_router.dart').readAsStringSync();
    profileSrc =
        File('lib/features/profile/screens/profile_screen.dart').readAsStringSync();
  });

  test('/avya/promise route exists in router', () {
    expect(routerSrc.contains("path: '/avya/promise'"), isTrue,
        reason: 'Router must declare the /avya/promise route');
  });

  test('/avya/promise renders MissionBriefScreen with readOnly: true', () {
    expect(routerSrc.contains('MissionBriefScreen(readOnly: true)'), isTrue,
        reason: 'Route must pass readOnly: true so back arrow shows and CONTINUE hides');
  });

  test('Profile screen has AVYA section header', () {
    expect(profileSrc.contains("SectionHeader('AVYA')"), isTrue,
        reason: 'Profile must have an AVYA section');
  });

  test("Profile AVYA section navigates to /avya/promise", () {
    expect(profileSrc.contains("'/avya/promise'"), isTrue,
        reason: "AVYA's Promise row must push /avya/promise");
  });

  test('Profile AVYA section has Instagram opener', () {
    expect(profileSrc.contains('_openInstagram'), isTrue,
        reason: 'Profile must have an _openInstagram method for the @icanbefitter row');
  });

  test('Profile AVYA section has website link', () {
    expect(profileSrc.contains('icanbefitter.com'), isTrue,
        reason: 'AVYA section must include icanbefitter.com link');
  });
}
