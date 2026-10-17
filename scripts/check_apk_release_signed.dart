// scripts/check_apk_release_signed.dart
//
// Gate: 48
//
// Gate 48: the built APK is signed with the RELEASE certificate, not the
// Android debug key.
//
// Why this exists (2026-06-05): android/app/build.gradle.kts:67-73 falls back
// to the DEBUG signing key when `key.properties` is absent — and
// `key.properties` is gitignored (android/.gitignore:12). So an APK built from
// a worktree / fresh clone is silently DEBUG-signed. A debug-signed APK CANNOT
// update over the user's release-signed install (Android rejects it as "App not
// installed"), so the user silently stays on the old version. The founder's
// +32 build never reached the phone for exactly this class of reason; +33 was
// release-signed and installs cleanly. This gate makes a debug-signed (or
// wrong-keystore) release APK a hard build failure instead of a silent ship.
//
// What it asserts (post-build, via apksigner):
//   - the signer cert is NOT the Android debug cert ("CN=Android Debug"), AND
//   - the signer cert SHA-256 == the pinned release cert (so a DIFFERENT
//     keystore — debug or any other — also fails). The org name is a softer
//     secondary signal.
//
// Pin maintenance: if you intentionally rotate the release/upload keystore,
// update kExpectedSha256 below (apksigner verify --print-certs prints it).
//
// Exit 0 = pass (release-signed with the pinned cert) or SKIP (no APK / no
//          tooling in a non-release dry run).
// Exit 1 = fail (debug-signed, wrong cert, or — in --release mode — the APK or
//          the verification tooling is missing).
//
// Usage:
//   dart run scripts/check_apk_release_signed.dart            # dry run (skip if no APK/tools)
//   dart run scripts/check_apk_release_signed.dart --release  # /build-apk post-build (strict)
//
// Wiring: build-only gate — runs from the /build-apk skill post-build, NOT from
// pre-commit/CI (needs a built APK + apksigner + a JDK). Listed in the
// pre-commit.sh case-skip block AND check_gate_scripts_wired.dart allowlist.

import 'dart:io';

/// The pinned release/upload certificate SHA-256 (lowercase hex, no colons).
/// Captured 2026-06-05 from the +33 release build
/// (CN=ICANBEFITTER, O=ICANBEFITTER). Update on a deliberate keystore rotation.
const String kExpectedSha256 =
    '436eacbb5cdcd7876fd9819ff5d37dde97bbc7be17e1cd2498f27ba4d2f322d8';

/// Expected organisation substring in the signer DN (softer secondary signal).
const String kExpectedOrg = 'ICANBEFITTER';

/// The Android debug cert's signature DN substring.
const String kDebugMarker = 'Android Debug';

/// Parsed signer fields from `apksigner verify --print-certs` output.
class SignerInfo {
  final String? dn;
  final String? sha256;
  const SignerInfo(this.dn, this.sha256);
}

/// PURE — extract the signer DN + SHA-256 from apksigner output. Handles both
/// the "Signer #1 certificate DN:" and "V2 Signer: certificate DN:" prefixes.
SignerInfo parseSigner(String apksignerOutput) {
  String? dn;
  String? sha;
  for (final raw in apksignerOutput.split('\n')) {
    final line = raw.trim();
    final lower = line.toLowerCase();
    if (dn == null && lower.contains('certificate dn:')) {
      dn = line.substring(line.toLowerCase().indexOf('certificate dn:') + 15).trim();
    } else if (sha == null && lower.contains('certificate sha-256 digest:')) {
      sha = line
          .substring(line.toLowerCase().indexOf('certificate sha-256 digest:') + 27)
          .trim()
          .toLowerCase()
          .replaceAll(':', '')
          .replaceAll(' ', '');
    }
  }
  return SignerInfo(dn, sha);
}

class Verdict {
  final bool ok;
  final String message;
  const Verdict(this.ok, this.message);
}

/// PURE — decide pass/fail from the parsed signer fields. Testable without
/// apksigner. `expectedSha` empty ('') disables the exact-pin check (org +
/// not-debug only).
Verdict evaluateSigner(
  SignerInfo info, {
  String expectedSha = kExpectedSha256,
  String expectedOrg = kExpectedOrg,
  String debugMarker = kDebugMarker,
}) {
  if (info.dn == null && info.sha256 == null) {
    return const Verdict(false,
        'could not parse a signer certificate from apksigner output (unsigned or unexpected format).');
  }
  final dn = info.dn ?? '';
  if (dn.toLowerCase().contains(debugMarker.toLowerCase())) {
    return Verdict(false,
        'APK is DEBUG-signed (DN: $dn). A debug-signed APK cannot update over the release install. '
        'Ensure android/key.properties + release.jks are present in the build dir (they are gitignored — '
        'copy them into any worktree/clone before building).');
  }
  if (expectedSha.isNotEmpty) {
    if (info.sha256 == null) {
      return const Verdict(false, 'no certificate SHA-256 in apksigner output to match against the pin.');
    }
    if (info.sha256 != expectedSha.toLowerCase()) {
      return Verdict(false,
          'signer cert SHA-256 mismatch.\n  got:      ${info.sha256}\n  expected: $expectedSha\n'
          '  DN: $dn\n  If you deliberately rotated the keystore, update kExpectedSha256 in this gate. '
          'Otherwise this APK was built with the wrong/another keystore and will NOT update over the release install.');
    }
    return Verdict(true, 'release-signed, cert SHA-256 matches the pin (DN: $dn).');
  }
  // No pin: fall back to org + not-debug.
  if (expectedOrg.isNotEmpty && !dn.toLowerCase().contains(expectedOrg.toLowerCase())) {
    return Verdict(false, 'signer DN does not contain "$expectedOrg" and is not debug — unexpected keystore (DN: $dn).');
  }
  return Verdict(true, 'release-signed (DN: $dn).');
}

void main(List<String> args) async {
  final releaseMode = args.contains('--release');
  final projectRoot = Directory.current.path;
  final apkPath = '$projectRoot/build/app/outputs/flutter-apk/app-prod-release.apk';

  // ── 1. APK present? ────────────────────────────────────────────────────────
  if (!File(apkPath).existsSync()) {
    if (releaseMode) {
      stderr.writeln('[Gate 48] FAIL — --release set but APK not found at $apkPath. Build first.');
      exit(1);
    }
    stdout.writeln('[Gate 48] SKIP — APK not found (run after build). Exit 0.');
    exit(0);
  }

  // ── 2. Locate apksigner + a JDK ────────────────────────────────────────────
  final apksigner = _findApksigner();
  final javaHome = _findJavaHome();
  if (apksigner == null || javaHome == null) {
    final what = [
      if (apksigner == null) 'apksigner (Android SDK build-tools)',
      if (javaHome == null) 'a JDK (set JAVA_HOME or install Android Studio)',
    ].join(' + ');
    if (releaseMode) {
      stderr.writeln('[Gate 48] FAIL — cannot verify signer on a release build: missing $what.');
      exit(1);
    }
    stdout.writeln('[Gate 48] SKIP — cannot verify (missing $what); non-release dry run. Exit 0.');
    exit(0);
  }

  // ── 3. Run apksigner ───────────────────────────────────────────────────────
  final env = Map<String, String>.from(Platform.environment)..['JAVA_HOME'] = javaHome;
  ProcessResult res;
  try {
    res = await Process.run(apksigner, ['verify', '--print-certs', apkPath],
        environment: env, runInShell: true);
  } catch (e) {
    if (releaseMode) {
      stderr.writeln('[Gate 48] FAIL — apksigner invocation error: $e');
      exit(1);
    }
    stdout.writeln('[Gate 48] SKIP — apksigner invocation error ($e); non-release dry run. Exit 0.');
    exit(0);
  }
  final out = '${res.stdout}\n${res.stderr}';

  // ── 4. Evaluate ────────────────────────────────────────────────────────────
  final verdict = evaluateSigner(parseSigner(out));
  if (verdict.ok) {
    stdout.writeln('[Gate 48] PASS — ${verdict.message}');
    exit(0);
  }
  stderr.writeln('\n[Gate 48] FAIL — ${verdict.message}');
  exit(1);
}

// ── Tooling discovery ─────────────────────────────────────────────────────────

String? _findApksigner() {
  final exe = Platform.isWindows ? 'apksigner.bat' : 'apksigner';
  final roots = <String>[
    if (Platform.environment['ANDROID_HOME'] != null) Platform.environment['ANDROID_HOME']!,
    if (Platform.environment['ANDROID_SDK_ROOT'] != null) Platform.environment['ANDROID_SDK_ROOT']!,
    if (Platform.isWindows && Platform.environment['LOCALAPPDATA'] != null)
      '${Platform.environment['LOCALAPPDATA']}\\Android\\Sdk',
    if (!Platform.isWindows && Platform.environment['HOME'] != null) ...[
      '${Platform.environment['HOME']}/Android/Sdk',
      '${Platform.environment['HOME']}/Library/Android/sdk',
    ],
  ];
  for (final root in roots) {
    final bt = Directory('$root${Platform.pathSeparator}build-tools');
    if (!bt.existsSync()) continue;
    final versions = bt.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path)); // ascending → last is newest
    for (final v in versions.reversed) {
      final cand = File('${v.path}${Platform.pathSeparator}$exe');
      if (cand.existsSync()) return cand.path;
    }
  }
  return null;
}

String? _findJavaHome() {
  bool valid(String? home) {
    if (home == null || home.isEmpty) return false;
    final bin = Platform.isWindows ? 'java.exe' : 'java';
    return File('$home${Platform.pathSeparator}bin${Platform.pathSeparator}$bin').existsSync();
  }

  final fromEnv = Platform.environment['JAVA_HOME'];
  if (valid(fromEnv)) return fromEnv;
  final candidates = <String>[
    if (Platform.isWindows) 'C:\\Program Files\\Android\\Android Studio\\jbr',
    if (Platform.isMacOS) '/Applications/Android Studio.app/Contents/jbr/Contents/Home',
    if (Platform.isLinux) '/opt/android-studio/jbr',
  ];
  for (final c in candidates) {
    if (valid(c)) return c;
  }
  return null;
}
