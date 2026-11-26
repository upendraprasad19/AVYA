// test/scripts/resolve_purchase_mode_test.dart
//
// OI-519 (+51) U6, plan docs/plans/2026-11-23-revenuecat-play-billing-51.md section 6: the `/build-apk`
// purchase-mode step. `play_billing` is accepted only with the RevenueCat public Google key in `.env`
// (`REVENUECAT_GOOGLE_API_KEY=goog_...`); `--bundle` still needs a mode; the build ledger records the mode.
//
// PURE: resolveBuildPurchaseMode / envValue (the script imported `as`). SPAWN (one each): the script's own
// exit codes, and verify_versioncode_available.dart --record ... --purchase-mode in a temp project.
//
// Run: flutter test test/scripts/resolve_purchase_mode_test.dart
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/resolve_purchase_mode.dart' as rpm;
import '../helpers/spawn.dart';

const _key = 'REVENUECAT_GOOGLE_API_KEY';

void main() {
  group('resolveBuildPurchaseMode (pure)', () {
    rpm.PurchaseModeResolution r(String? mode, {bool bundle = false, String? env}) =>
        rpm.resolveBuildPurchaseMode(mode: mode, bundle: bundle, envText: env);

    test('razorpay and none pass their define, with or without --bundle', () {
      for (final m in ['razorpay', 'none']) {
        for (final b in [false, true]) {
          final x = r(m, bundle: b);
          expect(x.ok, isTrue, reason: '$m bundle=$b');
          expect(x.defines, ['--dart-define=ANDROID_PURCHASE_MODE=$m']);
        }
      }
    });

    test('play_billing with a goog_ key passes ONE define (the key rides --dart-define-from-file)', () {
      final x = r('play_billing', bundle: true, env: 'A=1\n$_key=goog_abc123\n');
      expect(x.ok, isTrue, reason: x.refusal);
      expect(x.defines, ['--dart-define=ANDROID_PURCHASE_MODE=play_billing']);
      expect(x.defines.join(' ').contains('goog_abc123'), isFalse, reason: 'the key is never printed');
    });

    test('play_billing is REFUSED without a usable key', () {
      for (final env in <String?>[
        null, // no .env
        'A=1\n', // key absent
        '$_key=\n', // empty
        '$_key=goog_\n', // prefix only
        '$_key=appl_abc\n', // the Apple key
        '$_key=sk_secret\n', // a secret key: never in the app
        '# $_key=goog_abc\n', // commented out
        'X$_key=goog_abc\n', // another name
        '$_key=goog_your-public-sdk-key-here\n', // the .env.example placeholder
        '$_key=goog_abc def\n', // a space inside
      ]) {
        final x = r('play_billing', env: env);
        expect(x.ok, isFalse, reason: 'env=$env');
        expect(x.refusal, contains(_key));
      }
    });

    test('quoted values are read', () {
      expect(r('play_billing', env: '$_key="goog_q"\n').ok, isTrue);
      expect(r('play_billing', env: "$_key='goog_q'\n").ok, isTrue);
      expect(rpm.envValue(' $_key = goog_s ', _key), 'goog_s');
    });

    test('--bundle without a mode is REFUSED; an APK without a mode gets no define', () {
      expect(r(null, bundle: true).ok, isFalse);
      final apk = r(null);
      expect(apk.ok, isTrue);
      expect(apk.defines, isEmpty);
    });

    test('purchaseModeArg reads both spellings; a missing value or a repeat is refused', () {
      expect(rpm.purchaseModeArg(['--bundle']), isNull);
      expect(rpm.purchaseModeArg(['--purchase-mode', 'play_billing']), 'play_billing');
      expect(rpm.purchaseModeArg(['--purchase-mode=play_billing', '--bundle']), 'play_billing');
      expect(rpm.purchaseModeArg(['--purchase-mode=Razorpay']), 'razorpay');
      for (final bad in [
        ['--purchase-mode'],
        ['--purchase-mode', '--bundle'],
        ['--purchase-mode=none', '--purchase-mode', 'razorpay'],
      ]) {
        expect(() => rpm.purchaseModeArg(bad), throwsFormatException, reason: '$bad');
      }
      // The = form with an empty value reaches the resolver as '' and is an unknown mode.
      expect(rpm.purchaseModeArg(['--purchase-mode=']), '');
    });

    test('an unknown mode is REFUSED', () {
      for (final m in ['', 'playbilling', 'play-billing', 'stripe']) {
        expect(r(m).ok, isFalse, reason: m);
      }
    });
  });

  group('the scripts (spawned)', () {
    Future<ProcessResult> dart(List<String> args, {String? cwd}) => runSpawnAsync(
          dartBin(),
          ['run', ...args],
          why: args.join(' '),
          workingDirectory: cwd,
          report: (_) {},
        ).timeout(const Duration(minutes: 3), onTimeout: () => throw TimeoutException('spawn timed out'));

    test('resolve_purchase_mode.dart: REFUSED exits 1, a pass prints DEFINES', () async {
      final tmp = Directory.systemTemp.createTempSync('rpm_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final script = File('scripts/resolve_purchase_mode.dart').absolute.path;
      final no = await dart([script, '--purchase-mode', 'play_billing', '--bundle'], cwd: tmp.path);
      expect(no.exitCode, 1, reason: '${no.stdout}\n${no.stderr}');
      expect('${no.stderr}', contains('REFUSED'));
      File('${tmp.path}/.env').writeAsStringSync('$_key=goog_abc\n');
      final yes = await dart([script, '--purchase-mode', 'play_billing', '--bundle'], cwd: tmp.path);
      expect(yes.exitCode, 0, reason: '${yes.stdout}\n${yes.stderr}');
      expect('${yes.stdout}', contains('DEFINES: --dart-define=ANDROID_PURCHASE_MODE=play_billing'));
      expect('${yes.stdout}'.contains('goog_abc'), isFalse);
      final eq = await dart([script, '--purchase-mode=play_billing'], cwd: tmp.path);
      expect(eq.exitCode, 0, reason: '${eq.stdout}\n${eq.stderr}');
      expect('${eq.stdout}', contains('DEFINES: --dart-define=ANDROID_PURCHASE_MODE=play_billing'));
    });

    test('verify_versioncode_available.dart --record aab --purchase-mode play_billing records the mode', () async {
      final tmp = Directory.systemTemp.createTempSync('vvc_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      File('${tmp.path}/pubspec.yaml').writeAsStringSync('name: x\nversion: 1.0.0+51\n');
      Directory('${tmp.path}/backups').createSync();
      File('${tmp.path}/backups/built_versioncodes.json').writeAsStringSync('{}');
      final script = File('scripts/verify_versioncode_available.dart').absolute.path;
      final bad = await dart([script, '--record', 'aab', '--purchase-mode', 'stripe'], cwd: tmp.path);
      expect(bad.exitCode, 1, reason: '${bad.stdout}\n${bad.stderr}');
      expect(File('${tmp.path}/backups/built_versioncodes.json').readAsStringSync(), '{}');
      final twice = await dart([script, '--record', 'aab', '--purchase-mode=none', '--purchase-mode', 'razorpay'],
          cwd: tmp.path);
      expect(twice.exitCode, 1, reason: 'a repeated mode is refused, as by the resolver');
      expect(File('${tmp.path}/backups/built_versioncodes.json').readAsStringSync(), '{}');
      // The = form and any case, exactly as the resolver accepted them before the build.
      final ok = await dart([script, '--record', 'aab', '--purchase-mode=Play_Billing'], cwd: tmp.path);
      expect(ok.exitCode, 0, reason: '${ok.stdout}\n${ok.stderr}');
      final ledger = jsonDecode(File('${tmp.path}/backups/built_versioncodes.json').readAsStringSync())
          as Map<String, dynamic>;
      final entry = ledger['1.0.0+51'] as Map<String, dynamic>;
      expect(entry['artifact'], 'aab');
      expect(entry['purchase_mode'], 'play_billing');
    });
  });

  test('/build-apk runs the helper and no longer refuses play_billing', () {
    final doc = File('.claude/commands/build-apk.md').readAsStringSync();
    expect(doc, contains('dart run scripts/resolve_purchase_mode.dart [--purchase-mode <mode>] [--bundle]'));
    expect(doc, contains('--record aab --purchase-mode <mode>'));
    expect(doc.contains('The RevenueCat build (plan section 8) does not exist yet'), isFalse);
  });
}
