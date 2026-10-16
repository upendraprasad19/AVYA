// scripts/check_ci_flutter_version.dart
//
// Gate: CI / dev / Vercel Flutter-version parity.
//
// Root cause of the 2026-06-05 CI outage: `.github/workflows/test.yml` pinned
// Flutter 3.29.x (Dart 3.7.2) while `pubspec.yaml` required `sdk: ^3.11.1`
// (Flutter 3.41.x), so `flutter pub get` died on EVERY CI job and CI was
// silently red for days (it died before any test/gate ran). This gate asserts:
//
//   1. Every `flutter-version:` pin in the CI workflow is identical (no per-job
//      drift).
//   2. The CI pin is an EXACT version (x.y.z) — not a wildcard / channel that
//      lets CI float onto a Dart that violates the pubspec sdk constraint.
//   3. The CI pin equals `scripts/vercel_build.sh`'s FLUTTER_VERSION, so the
//      dev / CI / Vercel toolchains stay in lockstep.
//   4. `pubspec.yaml` still declares an `environment: sdk:` constraint.
//
// It cannot fully verify "this Flutter ships a Dart that satisfies the pubspec
// sdk" without a Flutter→Dart table, but pinning CI == Vercel (the two
// reproducible sources of truth) and forcing an exact pin removes the silent
// drift class that caused the outage.
//
// Exit 0 = pass, Exit 1 = fail. Accepts --warn-only for the 24h smoke window.
//
// Usage: dart run scripts/check_ci_flutter_version.dart

import 'dart:io';

void main(List<String> args) {
  final warnOnly = args.contains('--warn-only');
  final errors = <String>[];

  final workflow = File('.github/workflows/test.yml');
  final vercel = File('scripts/vercel_build.sh');
  final pubspec = File('pubspec.yaml');

  if (!workflow.existsSync()) errors.add('.github/workflows/test.yml missing');
  if (!vercel.existsSync()) errors.add('scripts/vercel_build.sh missing');
  if (!pubspec.existsSync()) errors.add('pubspec.yaml missing');

  String? ciVersion;
  String? vercelVersion;

  if (errors.isEmpty) {
    // 1. CI workflow flutter-version pins (all jobs must agree).
    final wf = workflow.readAsStringSync();
    final ciVersions = RegExp(r"flutter-version:\s*'([^']+)'")
        .allMatches(wf)
        .map((m) => m.group(1)!.trim())
        .toList();
    if (ciVersions.isEmpty) {
      errors.add(
          "no flutter-version: '<pin>' found in .github/workflows/test.yml");
    } else {
      final distinct = ciVersions.toSet();
      if (distinct.length > 1) {
        errors.add('CI jobs pin DIFFERENT flutter-versions: $distinct '
            '— every job must use the same Flutter');
      }
      ciVersion = distinct.first;
    }

    // 2. Vercel FLUTTER_VERSION.
    final vc = vercel.readAsStringSync();
    vercelVersion =
        RegExp(r'FLUTTER_VERSION="([^"]+)"').firstMatch(vc)?.group(1)?.trim();
    if (vercelVersion == null) {
      errors.add('FLUTTER_VERSION="x.y.z" not found in scripts/vercel_build.sh');
    }

    // 3. Exact pin + parity.
    final exactPin = RegExp(r'^\d+\.\d+\.\d+$');
    if (ciVersion != null && !exactPin.hasMatch(ciVersion)) {
      errors.add("CI flutter-version '$ciVersion' is not an exact pin (x.y.z) "
          '— a wildcard/channel lets CI float onto a Dart that can violate the '
          'pubspec sdk constraint (the 2026-06-05 outage)');
    }
    if (ciVersion != null && vercelVersion != null && ciVersion != vercelVersion) {
      errors.add("CI flutter-version '$ciVersion' != Vercel FLUTTER_VERSION "
          "'$vercelVersion' — dev/CI/Vercel toolchains must match");
    }

    // 4. pubspec sdk constraint still present.
    final ps = pubspec.readAsStringSync();
    if (!RegExp(r'\n\s*sdk:\s*\^?\d').hasMatch('\n$ps')) {
      errors.add('pubspec.yaml environment.sdk constraint missing');
    }
  }

  if (errors.isEmpty) {
    stdout.writeln('[check_ci_flutter_version] PASS — CI == Vercel Flutter '
        "pin '$ciVersion' (exact), pubspec sdk constraint present.");
    exit(0);
  }
  final tag =
      warnOnly ? '[check_ci_flutter_version WARN]' : '[check_ci_flutter_version]';
  stderr.writeln('$tag FAIL:');
  for (final e in errors) {
    stderr.writeln('  - $e');
  }
  stderr.writeln('\nFix: pin every `flutter-version:` in '
      '.github/workflows/test.yml to the same exact x.y.z that '
      'scripts/vercel_build.sh uses, and ensure that Flutter ships a Dart '
      'satisfying pubspec environment.sdk.');
  exit(warnOnly ? 0 : 1);
}
