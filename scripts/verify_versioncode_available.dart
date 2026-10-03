// scripts/verify_versioncode_available.dart
//
// Build-time helper for /build-apk — NOT a pre-commit/CI gate, and
// deliberately NOT named check_*.dart (that prefix pulls in rule 24's
// mutation-proof + gate_test_ledger.yaml requirement, which is scoped to
// the repo-wide commit-gate loop; this script only ever runs from inside
// the /build-apk skill).
//
// Born from 2026-09-15: the build-apk skill's Gate 2 ("versionCode bumped
// vs last shipped") only compares the CURRENT versionCode against past
// "bump versionCode" commits. It cannot see a versionCode that was already
// built/uploaded to Play Console OUTSIDE that commit trail — which is
// exactly what happened to +40, +41 and +42 (each bumped away reactively,
// after Play Console reported it already used, and +42 itself was
// consumed by a build the git history has no trace of). Gate 2 read as a
// clean pass immediately before that mistake was made. See
// feedback_mistake_versioncode_gate2_blind_spot.md.
//
// This script closes the gap for everything built THROUGH /build-apk from
// here on: every successful build records its versionCode into
// backups/built_versioncodes.json (via --record), and every future build
// checks the current versionCode against that ledger (plus the existing
// backups/apk_sizes.json, which already records every shipped APK's
// version). It cannot see a versionCode consumed by a manual/out-of-band
// upload — nothing local can — so treat a PASS here as "not known to be
// already built by this pipeline", not as a Play-Console guarantee.
//
// Usage:
//   dart run scripts/verify_versioncode_available.dart               # check only
//   dart run scripts/verify_versioncode_available.dart --record apk  # check + record artifact=apk
//   dart run scripts/verify_versioncode_available.dart --record aab  # check + record artifact=aab

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final projectRoot = Directory.current.path;
  final ledgerPath = '$projectRoot/backups/built_versioncodes.json';
  final apkSizesPath = '$projectRoot/backups/apk_sizes.json';

  final recordIdx = args.indexOf('--record');
  final shouldRecord = recordIdx != -1;
  final artifact =
      (shouldRecord && recordIdx + 1 < args.length) ? args[recordIdx + 1] : null;
  if (shouldRecord && (artifact != 'apk' && artifact != 'aab')) {
    stderr.writeln(
        '[versioncode-guard] ERROR — --record requires "apk" or "aab" (got: ${artifact ?? '<none>'}).');
    exit(1);
  }

  final version = _readPubspecVersion(projectRoot);
  if (version == null) {
    stderr.writeln(
        '[versioncode-guard] ERROR — could not read version: from pubspec.yaml.');
    exit(1);
  }

  final ledgerFile = File(ledgerPath);
  Map<String, dynamic> ledger;
  if (!ledgerFile.existsSync()) {
    ledger = <String, dynamic>{};
  } else {
    try {
      ledger = jsonDecode(ledgerFile.readAsStringSync()) as Map<String, dynamic>;
    } catch (e) {
      stderr.writeln(
          '[versioncode-guard] ERROR — could not parse backups/built_versioncodes.json: $e');
      exit(1);
    }
  }

  final apkSizesFile = File(apkSizesPath);
  Set<String> shippedApkVersions = <String>{};
  if (apkSizesFile.existsSync()) {
    try {
      final sizes =
          jsonDecode(apkSizesFile.readAsStringSync()) as Map<String, dynamic>;
      shippedApkVersions = sizes.keys.toSet();
    } catch (_) {
      // apk_sizes.json is checked elsewhere (Gate 13); a parse failure here
      // is not this script's job to report — just skip the extra signal.
    }
  }

  final alreadyInLedger = ledger.containsKey(version);
  final alreadyShippedApk = shippedApkVersions.contains(version);

  if (alreadyInLedger || alreadyShippedApk) {
    final entry = alreadyInLedger ? ledger[version] as Map<String, dynamic>? : null;
    stderr.writeln(
        '[versioncode-guard] FAIL — $version was already built by this pipeline.');
    if (entry != null) {
      stderr.writeln(
          '  Recorded: artifact=${entry['artifact']}, built_at=${entry['built_at']}'
          '${entry['note'] != null ? ', note=${entry['note']}' : ''}');
    }
    if (alreadyShippedApk) {
      stderr.writeln('  Also present in backups/apk_sizes.json (shipped APK).');
    }
    stderr.writeln(
        '  Bump versionCode in pubspec.yaml AND lib/core/constants/app_constants.dart'
        ' (check_app_version_matches_pubspec.dart enforces they match) before building again.');
    exit(1);
  }

  stdout.writeln(
      '[versioncode-guard] PASS — $version not previously built by this pipeline.'
      ' (This cannot see a manual/out-of-band Play Console upload — if you already'
      ' uploaded this versionCode outside /build-apk, bump it before proceeding.)');

  if (shouldRecord) {
    final now = DateTime.now().toUtc().toIso8601String();
    ledger[version] = {
      'artifact': artifact,
      'built_at': now,
    };
    ledgerFile
      ..createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(ledger));
    stdout.writeln('[versioncode-guard] RECORDED — $version (artifact=$artifact).');
  }
}

String? _readPubspecVersion(String projectRoot) {
  final pubspecFile = File('$projectRoot/pubspec.yaml');
  if (!pubspecFile.existsSync()) return null;
  for (final line in pubspecFile.readAsLinesSync()) {
    if (line.startsWith('version:')) {
      return line.replaceFirst('version:', '').trim();
    }
  }
  return null;
}
