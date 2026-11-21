// Regression contract for bug d5e1b9 (Obs#1, 2026-06-13 founder report): a brand-
// new signup saw restore-flavored copy ("Loading profile & plan" / "Pulling your
// dispatch.") on the post-auth RestoringScreen — it has nothing to restore. The
// title now shows a neutral/setup status unless _useRestoreLabel is set, which
// only the returning-user GoHome path (_goHome) sets. Source-grep, comment-
// stripped (RestoringScreen's Supabase/Hive/provider deps make a behavioral
// widget test impractical; the resolveDestination logic is tested separately in
// auth_session_bootstrapper_test).

import '../helpers/read_screen_source.dart';

import 'package:flutter_test/flutter_test.dart';

String _strip(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s
      .split('\n')
      .map((line) {
        final m = RegExp(r'(?<!:)//').firstMatch(line);
        return m == null ? line : line.substring(0, m.start);
      })
      .join('\n');
  return s;
}

void main() {
  final src = _strip(
      readRestoringScreenSource());

  test('d5e1b9 — the restore-label title is gated on _useRestoreLabel', () {
    expect(src.contains('_useRestoreLabel'), isTrue,
        reason: 'a flag must gate restore-flavored copy to returning users only');
    // The live restore label (restoreProgressLabel) must be guarded by the flag,
    // not rendered unconditionally: a `_useRestoreLabel` reference must precede
    // the restoreProgressLabel ValueListenableBuilder.
    final flagIdx = src.indexOf('_useRestoreLabel');
    final labelIdx = src.indexOf('restoreProgressLabel');
    expect(flagIdx, isNot(-1));
    expect(labelIdx, isNot(-1));
    expect(flagIdx, lessThan(labelIdx),
        reason: 'the _useRestoreLabel gate must precede (guard) the restore label');
  });

  test('d5e1b9 — new signup gets a setup status, returning user flips the flag',
      () {
    expect(src.contains('Setting up your account'), isTrue,
        reason: 'StartMissionBrief / mid-onboarding must show account-setup copy');
    expect(RegExp(r'_useRestoreLabel\s*=\s*true').hasMatch(src), isTrue,
        reason: 'the returning-user GoHome path (_goHome) must enable the restore label');
  });
}
