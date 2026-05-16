// scripts/check_app_version_matches_pubspec.dart
//
// Build-gate script: asserts `AppConstants.appVersion` in
// lib/core/constants/app_constants.dart matches the `version:` line in
// pubspec.yaml. Run as part of `/build-apk` Gate 18.
//
// Background — audit 2026-05-16 F10.1:
//   `AppConstants.appVersion` was hardcoded `'1.0.0+23'` and never bumped while
//   APKs +24/+25/+26 shipped. 358 telemetry rows in 30 days were mis-labelled,
//   breaking the ability to correlate client_errors to specific builds.
//
// Exits 0 on parity; exits 1 with a clear error message on drift.

import 'dart:io';

void main() {
  final pubspec = File('pubspec.yaml');
  final constants = File('lib/core/constants/app_constants.dart');

  if (!pubspec.existsSync()) {
    stderr.writeln('[check_app_version_matches_pubspec] pubspec.yaml not found at expected path');
    exit(2);
  }
  if (!constants.existsSync()) {
    stderr.writeln('[check_app_version_matches_pubspec] lib/core/constants/app_constants.dart not found');
    exit(2);
  }

  final versionLineRe = RegExp(r'^\s*version:\s*([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)\s*$', multiLine: true);
  final pubspecMatch = versionLineRe.firstMatch(pubspec.readAsStringSync());
  if (pubspecMatch == null) {
    stderr.writeln('[check_app_version_matches_pubspec] could not parse `version:` line in pubspec.yaml');
    exit(2);
  }
  final pubspecVersion = pubspecMatch.group(1)!;

  final constRe = RegExp(r"static\s+const\s+String\s+appVersion\s*=\s*'([^']+)'\s*;");
  final constMatch = constRe.firstMatch(constants.readAsStringSync());
  if (constMatch == null) {
    stderr.writeln('[check_app_version_matches_pubspec] could not parse AppConstants.appVersion');
    exit(2);
  }
  final constVersion = constMatch.group(1)!;

  if (pubspecVersion == constVersion) {
    stdout.writeln('[check_app_version_matches_pubspec] OK — both at $pubspecVersion');
    exit(0);
  }

  stderr.writeln(
    '[check_app_version_matches_pubspec] FAIL — pubspec.yaml is $pubspecVersion but '
    'AppConstants.appVersion is $constVersion. Bump the constant to match before shipping.\n'
    'Fix: edit lib/core/constants/app_constants.dart and set appVersion = \'$pubspecVersion\'.',
  );
  exit(1);
}
