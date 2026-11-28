// PRESENCE-ONLY pins on `ProgressPhotoRepository.capture`'s wiring (OI-314, OI-322,
// OI-348 Landing 3c). `capture` needs ImagePicker and Supabase and is not executed
// by a unit test; the behaviour of everything it CALLS is proven in
// progress_photo_client_rules_test.dart (the classifier, the UTC wire value, the
// IST week start, the content type), progress_photo_free_slot_test.dart (the free
// slot check, the sweep and removeIfNoRow through the repository seams) and the
// screen's reaction in progress_photos_free_flow_test.dart. These pins only stop
// the wiring from drifting back (a tier decision inside capture, the 5/day cap, a
// dart:io File upload that fails on web, an offset-less `taken_at`, a refusal
// swallowed into `null`: class 2.49, an uploaded object left behind by a failed
// row insert). They run on COMMENT-STRIPPED source and are mutation-proven in the
// diagnose-doc.
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
    final end = src.indexOf('Future<void> cleanupAfterFailedInsert(');
    expect(end, greaterThan(start));
    capture = src.substring(start, end);
  });

  test('capture makes no tier decision and the 5/day cap is gone', () {
    expect(capture.contains('isPro('), isFalse,
        reason: 'the screen decides the tier; the server enforces the cap');
    expect(capture.contains('freeTier'), isFalse);
    expect(src.contains('progressPhotoDailyCap'), isFalse);
    expect(src.contains('_dailyCap'), isFalse);
    expect(capture.contains("gte('taken_at'"), isFalse,
        reason: 'the old client-only daily count');
  });

  test('the pick is 2048 px on the long side at JPEG quality 85 (founder call)',
      () {
    expect(RegExp(r'maxWidth:\s*2048').hasMatch(capture), isTrue);
    expect(RegExp(r'maxHeight:\s*2048').hasMatch(capture), isTrue);
    expect(RegExp(r'imageQuality:\s*85').hasMatch(capture), isTrue);
    expect(capture.contains('3000'), isFalse);
  });

  test('the upload sends BYTES (web and Android), never a dart:io File', () {
    expect(src.contains("import 'dart:io'"), isFalse);
    expect(capture.contains('File('), isFalse);
    expect(capture.contains('await xfile.readAsBytes()'), isTrue);
    expect(capture.contains('.uploadBinary('), isTrue);
    expect(capture.contains('.upload('), isFalse);
    expect(RegExp(r'contentType:\s*type\.mime').hasMatch(capture), isTrue);
    expect(RegExp(r'upsert:\s*false').hasMatch(capture), isTrue);
    expect(capture.contains('progressPhotoContentType(xfile.name, xfile.mimeType)'),
        isTrue);
  });

  test('taken_at is sent as UTC (OI-322) from the app clock', () {
    expect(capture.contains("'taken_at': progressPhotoTakenAtWire(takenAt)"),
        isTrue);
    expect(capture.contains('final takenAt = nowWall();'), isTrue);
    expect(capture.contains('takenAt.toIso8601String(),'), isFalse,
        reason: 'an offset-less local time is the OI-322 bug');
  });

  test('a failed row insert after a successful upload removes THAT object '
      '(only after a row read), before the refusal is classified', () {
    final uploaded = capture.indexOf('uploadedPath = storagePath;');
    final insert = capture.indexOf(".from('progress_photos').insert(");
    expect(uploaded, greaterThan(capture.indexOf('.uploadBinary(')));
    expect(insert, greaterThan(uploaded),
        reason: 'the path is remembered only once the upload succeeded');
    final catchAt = capture.lastIndexOf('} catch (e) {');
    final tail = capture.substring(catchAt);
    final cleanup =
        tail.indexOf('await cleanupAfterFailedInsert(userId, uploadedPath, e)');
    expect(cleanup, greaterThan(-1));
    expect(tail.indexOf('isProgressPhotoProRefusal('), greaterThan(cleanup));
    // Its branch (a PostgREST answer cleans up now, a transport failure goes
    // to the 2-minute sweep) is BEHAVIOURAL in progress_photo_free_slot_test.
    final rin = src.indexOf('Future<void> removeIfNoRow(');
    final rbody = src.substring(rin, src.indexOf('ownFailedCleanups =', rin));
    final read = rbody.indexOf('await _rowPaths(userId, [path])');
    final guard = rbody.indexOf('if (withRow.contains(path)) return;');
    final remove = rbody.indexOf('await _removeObjects([path])');
    expect(read, greaterThan(-1));
    expect(guard, greaterThan(read));
    expect(remove, greaterThan(guard),
        reason: 'an insert that committed and lost its response keeps its object');
  });

  test('an upload that failed without an answer hands its path to the sweep '
      '(Hermes C1): the path is noted BEFORE the upload, used only when no '
      'object was confirmed', () {
    final attempt = capture.indexOf('attemptedPath = storagePath;');
    expect(attempt, greaterThan(-1));
    expect(capture.indexOf('.uploadBinary('), greaterThan(attempt));
    final tail = capture.substring(capture.lastIndexOf('} catch (e) {'));
    expect(
        tail.contains('} else if (attemptedPath != null) {\n'
            '        noteFailedUpload(attemptedPath, e);'),
        isTrue);
  });

  test('delete hands a failed object removal to removeDeletedPhotoObject '
      '(Hermes C2/D1), whose behaviour is in progress_photo_free_slot_test', () {
    final at = src.indexOf('Future<bool> delete(String id)');
    final body = src.substring(at, src.indexOf('Future<void> removeDeletedPhotoObject(', at));
    expect(body.contains('await removeDeletedPhotoObject(path);'), isTrue);
    expect(body.contains('.remove([path])'), isFalse);
  });

  test('every log line in the repository is debug-only (rule 17; Hermes D2): '
      'paths start with the user id', () {
    expect(RegExp(r'debugPrint\(').allMatches(src).length, 1);
    expect(src.contains('if (kDebugMode) debugPrint(message);'), isTrue);
  });

  test('the free-slot pre-check is bounded: a hung listing lets the server '
      'decide instead of holding the Add spinner (PRESENCE only: '
      'ensureFreeSlotOpen needs a signed-in user)', () {
    final at = src.indexOf('Future<void> ensureFreeSlotOpen()');
    final body = src.substring(at, src.indexOf('Future<String?> capture(', at));
    expect(
        body.contains('await freeSlotOpen(userId)\n'
            '        .timeout(progressPhotoStorageCallTimeout, onTimeout: () => null);'),
        isTrue);
    expect(body.contains('if (open == false) {'), isTrue);
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
    final upload = capture.indexOf('.uploadBinary(');
    final off = capture.lastIndexOf('uploadStage = false;');
    final insert = capture.indexOf(".from('progress_photos').insert(");
    final all = 'pick=$pick on=$on upload=$upload off=$off insert=$insert';
    expect(pick, greaterThan(-1), reason: all);
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
