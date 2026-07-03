// test/contracts/terms_acceptance_writer_to_reader_test.dart
//
// SoT contract for terms_acceptance (audit-fixwave 2026-07-02 / F15). The DPDP
// ToS/Privacy acceptance write had no drift-protection concept. Comment-stripped.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  final signin = _strip(
      File('lib/features/auth/screens/sign_in_screen.dart').readAsStringSync());
  final boot = _strip(File('lib/core/services/auth_session_bootstrapper.dart')
      .readAsStringSync());

  group('terms_acceptance writer→reader contract', () {
    test('email sign-in stamps terms_accepted_at + terms_version in userBox', () {
      expect(signin.contains("'terms_accepted_at'"), isTrue);
      expect(signin.contains("'terms_version'"), isTrue,
          reason: 'DPDP acceptance must be stamped locally on accept');
    });
    test('bootstrapper projects/hydrates the terms fields', () {
      expect(boot.contains('terms_accepted_at'), isTrue);
      expect(boot.contains('hydrateFromCloud'), isTrue,
          reason: 'the bootstrapper projects terms to cloud + re-hydrates');
    });
  });
}
