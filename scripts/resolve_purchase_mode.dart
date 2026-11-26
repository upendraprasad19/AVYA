// scripts/resolve_purchase_mode.dart: the `/build-apk` purchase-mode step (ADR-0022; OI-519 plan
// docs/plans/2026-11-23-revenuecat-play-billing-51.md section 6). A build HELPER, not a gate: it runs once
// at the start of `/build-apk`, before any gate or clean, and prints the `--dart-define` arguments the build
// command must carry.
//
//   dart run scripts/resolve_purchase_mode.dart [--purchase-mode <razorpay|none|play_billing>] [--bundle]
//
// Rules:
//   * `--bundle` without `--purchase-mode` -> REFUSED (a Play upload must name what it sells).
//   * an unknown mode -> REFUSED.
//   * `--purchase-mode <v>` and `--purchase-mode=<v>` are both read; a missing value or a second occurrence is
//     REFUSED (an unread `=` form once built an APK as `none` with no word: B-pass seat A, 2026-11-24).
//   * `play_billing` -> `.env` must carry `REVENUECAT_GOOGLE_API_KEY=goog_<letters and digits>` (the RevenueCat
//     PUBLIC Google SDK key; the `.env.example` placeholder, with its hyphens, does not pass); else REFUSED. Without it the app's Play body cannot load and the binary sells
//     nothing. The key's value is never printed.
//   * no mode on an APK -> no define (a release build resolves to `none`).
// Exit 0 with `DEFINES: <args>` on stdout, or exit 1 with `REFUSED: <reason>` on stderr.

import 'dart:io';

const List<String> kPurchaseModes = ['razorpay', 'none', 'play_billing'];
const String kRevenueCatKeyName = 'REVENUECAT_GOOGLE_API_KEY';

/// The outcome: [defines] when allowed, else [refusal].
class PurchaseModeResolution {
  const PurchaseModeResolution.ok(this.defines) : refusal = null;
  const PurchaseModeResolution.refused(this.refusal) : defines = const [];
  final List<String> defines;
  final String? refusal;
  bool get ok => refusal == null;
}

/// The shape of a RevenueCat public Google SDK key.
final RegExp kRevenueCatGoogleKeyShape = RegExp(r'^goog_[A-Za-z0-9]+$');

/// PURE. The `--purchase-mode` value in [args] (`--purchase-mode <v>` or `--purchase-mode=<v>`), trimmed and
/// lower-cased; null when absent. A missing value or a second occurrence throws [FormatException].
String? purchaseModeArg(List<String> args) {
  String? found;
  var seen = 0;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String? v;
    if (a == '--purchase-mode') {
      if (i + 1 >= args.length || args[i + 1].startsWith('--')) {
        throw const FormatException('--purchase-mode needs a value');
      }
      v = args[++i];
    } else if (a.startsWith('--purchase-mode=')) {
      v = a.substring('--purchase-mode='.length);
    } else {
      continue;
    }
    if (++seen > 1) throw const FormatException('--purchase-mode given more than once');
    found = v.trim().toLowerCase();
  }
  return found;
}

/// PURE. The value of [key] in a `.env` text (`KEY=value`, optional quotes, `#` comment lines), or null.
String? envValue(String envText, String key) {
  for (final raw in envText.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    if (line.substring(0, eq).trim() != key) continue;
    var v = line.substring(eq + 1).trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    return v;
  }
  return null;
}

/// PURE. [mode] is the `--purchase-mode` value (null = absent); [envText] the `.env` contents (null = no file).
PurchaseModeResolution resolveBuildPurchaseMode({
  required String? mode,
  required bool bundle,
  required String? envText,
}) {
  if (mode == null) {
    return bundle
        ? const PurchaseModeResolution.refused(
            '--bundle needs --purchase-mode (a Play upload must name what it sells)')
        : const PurchaseModeResolution.ok([]);
  }
  if (!kPurchaseModes.contains(mode)) {
    return PurchaseModeResolution.refused(
        'unknown --purchase-mode "$mode" (one of ${kPurchaseModes.join(', ')})');
  }
  final defines = ['--dart-define=ANDROID_PURCHASE_MODE=$mode'];
  if (mode == 'play_billing') {
    final key = envText == null ? null : envValue(envText, kRevenueCatKeyName);
    if (key == null || !kRevenueCatGoogleKeyShape.hasMatch(key)) {
      return const PurchaseModeResolution.refused(
          'play_billing needs $kRevenueCatKeyName=goog_... in .env (the RevenueCat public Google key); '
          'without it the binary sells nothing');
    }
    // The key reaches the build through --dart-define-from-file=.env, which every build already passes:
    // no second define, so the value is never printed or typed on a command line.
  }
  return PurchaseModeResolution.ok(defines);
}

void main(List<String> args) {
  final String? mode;
  try {
    mode = purchaseModeArg(args);
  } on FormatException catch (e) {
    stderr.writeln('REFUSED: ${e.message}');
    exit(1);
  }
  final env = File('.env');
  final r = resolveBuildPurchaseMode(
    mode: mode,
    bundle: args.contains('--bundle'),
    envText: env.existsSync() ? env.readAsStringSync() : null,
  );
  if (!r.ok) {
    stderr.writeln('REFUSED: ${r.refusal}');
    exit(1);
  }
  stdout.writeln('DEFINES: ${r.defines.join(' ')}');
  stdout.writeln('PURCHASES: ${mode ?? 'none (no define; a release build resolves to none)'}');
}
