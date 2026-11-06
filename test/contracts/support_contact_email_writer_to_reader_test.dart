// test/contracts/support_contact_email_writer_to_reader_test.dart
//
// SoT contract for support_contact_email (observation-batch-and-digest-
// redesign 2026-09-21 / A7). The support address had drifted to 3 different
// literal strings across 2 files. Comment-stripped so a contract described
// only in a comment cannot satisfy it.
//
// closes-diagnose: (support-email-drift diagnose-doc, this batch)

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const _canonical = 'upendra@icanbefitter.com';
const _staleVariants = ['support@avya.app', 'support@icanbefitter.com'];

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('support_contact_email writer contract', () {
    test('profile screen contact card shows the canonical address', () {
      final content = _strip(
          File('lib/features/profile/screens/profile/screen.dart')
              .readAsStringSync());
      expect(content.contains(_canonical), isTrue,
          reason: 'profile screen must display $_canonical');
    });

    test('delete-account cancel-failure message shows the canonical address',
        () {
      final content = _strip(
          File('lib/features/profile/screens/delete_account_screen.dart')
              .readAsStringSync());
      expect(content.contains(_canonical), isTrue,
          reason: 'delete-account screen must reference $_canonical');
    });

    test('no stale support-email variant remains under lib/features/profile/',
        () {
      final dir = Directory('lib/features/profile');
      final offenders = <String>[];
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final content = _strip(entity.readAsStringSync());
        for (final stale in _staleVariants) {
          if (content.contains(stale)) {
            offenders.add('${entity.path} contains stale "$stale"');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('; '));
    });
  });
}
