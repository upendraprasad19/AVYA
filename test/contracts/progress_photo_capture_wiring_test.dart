// PRESENCE-ONLY pins on `ProgressPhotoRepository.capture`'s wiring (OI-314, OI-322).
// `capture` needs ImagePicker and Supabase and is not executed by a unit test; the
// behaviour of everything it CALLS is proven in progress_photo_client_rules_test.dart
// (the classifier, the UTC wire value, the IST cap window) and the screen's reaction
// in progress_photos_lapsed_flow_test.dart. These pins only stop the wiring from
// drifting back (the old free branch, a device-local window, an offset-less
// `taken_at`, a refusal swallowed into `null`: class 2.49). They run on
// COMMENT-STRIPPED source and are mutation-proven in the diagnose-doc.
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';

import '../helpers/read_screen_source.dart';

void main() {
  late String src;
  late String capture;

  setUpAll(() {
    src = readSourceFileStripped(
        'lib/features/profile/repositories/progress_photo_repository.dart');
    final start = src.indexOf('Future<String?> capture(');
    expect(start, greaterThanOrEqualTo(0));
    final end = src.indexOf('Future<List<Map<String, dynamic>>> listStrict(');
    expect(end, greaterThan(start));
    capture = src.substring(start, end);
  });

  test('the free tier is gone: no isPro read, no second cap, no quality tiers', () {
    expect(src.contains('_freeDailyCap'), isFalse);
    expect(capture.contains('isPro('), isFalse,
        reason: 'capture makes no PRO decision; the screen gates the call and '
            'the server refuses the rest');
    expect(capture.contains('2048'), isFalse);
    expect(RegExp(r'imageQuality:\s*95').hasMatch(capture), isTrue);
    expect(RegExp(r'maxWidth:\s*3000').hasMatch(capture), isTrue);
    expect(src.contains('static const int _dailyCap = progressPhotoDailyCap;'), isTrue);
  });

  test('the cap window is the IST day and taken_at is sent as UTC (OI-322)', () {
    expect(
        capture.contains('progressPhotoCapWindowStartUtc(nowWall())'), isTrue);
    expect(capture.contains("gte('taken_at', startOfDay)"), isTrue);
    expect(capture.contains("'taken_at': progressPhotoTakenAtWire(takenAt)"),
        isTrue);
    expect(capture.contains('final takenAt = nowWall();'), isTrue,
        reason: 'the stored instant and the cap window read the same clock');
    expect(capture.contains('takenAt.toIso8601String(),'), isFalse,
        reason: 'an offset-less local time is the OI-322 bug');
    expect(capture.contains('DateTime(now.year'), isFalse,
        reason: 'the device-local midnight window is the OI-322 bug');
  });

  test('the cap query is the user\'s own rows since IST midnight, and the cap '
      'decision is the pure boundary function', () {
    final eq = capture.indexOf(".eq('user_id', userId)");
    final gte = capture.indexOf(".gte('taken_at', startOfDay)");
    expect(eq, greaterThan(-1), reason: 'the cap must count THIS user\'s rows');
    expect(gte, greaterThan(eq));
    expect(capture.contains('progressPhotoCapReached(todays.length)'), isTrue);
    expect(capture.contains('todays.length >='), isFalse);
    expect(RegExp(r'const int progressPhotoDailyCap = 5;').hasMatch(src), isTrue);
  });

  test('the window function is IST midnight and never a device-local DateTime', () {
    final a = src.indexOf('String progressPhotoCapWindowStartUtc(DateTime now)');
    expect(a, greaterThan(-1));
    final body = src.substring(a, src.indexOf(';', a) + 1);
    expect(body.contains('istMidnightUtc(now)'), isTrue);
    expect(body.contains('DateTime('), isFalse,
        reason: 'a device-local midnight is the OI-322 bug and passes the pure '
            'test under the CI zone (Asia/Kolkata)');
    expect(body.contains('toLocal'), isFalse);
  });

  test('the catch hands the failure to the classifier and THROWS on a refusal; '
      'it never swallows it into null', () {
    final catchAt = capture.lastIndexOf('} catch (e) {');
    expect(catchAt, greaterThan(-1));
    final tail = capture.substring(catchAt);
    final classify = tail.indexOf('isProgressPhotoProRefusal(');
    final throwAt = tail.indexOf('throw const ProgressPhotoProRequiredException()');
    final returnNull = tail.lastIndexOf('return null;');
    expect(classify, greaterThan(-1));
    expect(throwAt, greaterThan(classify));
    expect(returnNull, greaterThan(throwAt),
        reason: 'the refusal must be thrown BEFORE the generic null return');
    expect(tail.contains('uploadStage: uploadStage'), isTrue);
    expect(
        tail.contains(
            'paymentInFlight: SubscriptionService.instance.isPaymentInFlight'),
        isTrue,
        reason: 'the just-paid leg reads the real in-flight flag; a constant '
            'false here would silently disable it');
  });

  test('uploadStage is true only between the picker and the end of the upload',
      () {
    final pick = capture.indexOf('if (xfile == null) return null;');
    final on = capture.indexOf('uploadStage = true;');
    final upload = capture.indexOf('.upload(');
    final off = capture.lastIndexOf('uploadStage = false;');
    final insert = capture.indexOf(".from('progress_photos').insert(");
    final all = 'pick=$pick on=$on upload=$upload off=$off insert=$insert';
    expect(pick, greaterThan(-1), reason: all);
    expect(on, greaterThan(pick), reason: all);
    expect(on, greaterThan(pick), reason: 'a cancelled pick is never a refusal');
    expect(upload, greaterThan(on));
    expect(off, greaterThan(upload));
    expect(insert, greaterThan(off));
    expect(RegExp(r'var uploadStage = false;').hasMatch(capture), isTrue);
  });

  test('no server call, no verify and no timeout lives in the repository', () {
    expect(src.contains('verifyFromServer'), isFalse,
        reason: 'three review rounds attacked every verify-based variant; the '
            'classifier is pure and the screen owns any server question');
    expect(src.contains('gateAndVerify'), isFalse);
  });

  test('list() is a swallowing wrapper over listStrict(), which propagates', () {
    final strictStart = src.indexOf('Future<List<Map<String, dynamic>>> listStrict(');
    final listStart = src.indexOf('Future<List<Map<String, dynamic>>> list(');
    expect(strictStart, greaterThan(-1));
    expect(listStart, greaterThan(strictStart));
    final strict = src.substring(strictStart, listStart);
    // The signed-URL loop keeps its own per-photo try/catch (a grey tile); the
    // ROW read must not sit inside any try.
    final rowsAt = strict.indexOf('final rows = await');
    expect(rowsAt, greaterThan(-1));
    expect(strict.substring(0, rowsAt).contains('try'), isFalse,
        reason: 'listStrict must let a failed row read propagate: the screen '
            'must never read a failed read as "no photos" (class 2.49)');
    expect(strict.indexOf('try {'), greaterThan(rowsAt));
    final list = src.substring(listStart, src.indexOf('Future<bool> delete('));
    expect(list.contains('await listStrict('), isTrue);
    expect(list.contains('return const [];'), isTrue);
  });
}
