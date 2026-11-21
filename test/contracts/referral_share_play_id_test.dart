// U4a: the referral share link pointed at com.icanbefitter.avya, an app id
// that does not exist. The Play listing is the Gradle applicationId. The link
// is compared with android/app/build.gradle.kts so the two cannot drift again.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the share link carries the real applicationId', () {
    final gradle =
        File('android/app/build.gradle.kts').readAsStringSync();
    final id = RegExp(r'applicationId\s*=\s*"([^"]+)"').firstMatch(gradle)!
        .group(1)!;
    final sheet = File('lib/features/profile/screens/invite_friends_sheet.dart')
        .readAsStringSync();
    final links = RegExp(r'play\.google\.com/store/apps/details\?id=([A-Za-z0-9_.]+)')
        .allMatches(sheet)
        .map((m) => m.group(1))
        .toList();
    expect(links, isNotEmpty);
    for (final l in links) {
      expect(l, id);
    }
    expect(sheet.contains('com.icanbefitter.avya'), isFalse);
  });
}
