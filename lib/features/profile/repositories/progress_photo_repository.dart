import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileObject, FileOptions, PostgrestException, SearchOptions,
        SortBy, StorageException;

import '../../../core/services/subscription_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/ist_date.dart';

/// Thrown by [ProgressPhotoRepository.capture] BEFORE the pick when a free (or
/// lapsed) user already holds this IST week's free photo (OI-348 Landing 3c,
/// founder call 2026-11-26: 1 per IST week; PRO has no cap). The screen shows
/// the weekly-cap snackbar with a GO PRO action.
class PhotoQuotaException implements Exception {
  final int weeklyCap;
  final String message;
  const PhotoQuotaException({
    required this.weeklyCap,
    required this.message,
  });
  @override
  String toString() => message;
}

/// Thrown by [ProgressPhotoRepository.capture] when the SERVER refused the new
/// photo: the caller has no active, unexpired subscription AND already holds
/// this IST week's free photo (the progress-photos free weekly cap migration:
/// the BEFORE INSERT trigger on `storage.objects` for the bucket, 42501, and
/// the BEFORE INSERT trigger on `public.progress_photos`, PostgREST `P0001`,
/// both with the literal `progress_photo_pro_required`). Not a generic
/// failure: the screen decides between "still activating", the weekly-cap
/// snackbar and "couldn't confirm" (OI-314).
class ProgressPhotoProRequiredException implements Exception {
  final String message;
  const ProgressPhotoProRequiredException(
      [this.message = 'progress_photo_pro_required']);
  @override
  String toString() => message;
}

/// Is [error] the server's PRO refusal of a new progress photo? Pure and
/// synchronous on purpose (no server call: three review rounds attacked every
/// verify-based variant).
///
/// CONSERVATIVE: a misread refusal would send a payer to the paywall, while a
/// missed one only costs "Upload failed - try again". So:
///  1. a [PostgrestException] with code `P0001` and `progress_photo_pro_required`
///     in its message (the row trigger);
///  2. a [StorageException] whose message contains `row-level security`
///     (case-insensitive; Storage's wording for a 42501 refusal) or the literal
///     `progress_photo_pro_required` (the storage trigger's own text, should
///     Storage pass it through). Never keyed on the HTTP status;
///  3. the just-paid window: [uploadStage] and [paymentInFlight] and a
///     [StorageException] whose statusCode is '400' or '403' (the subscription
///     row is not written yet). The storage client turns every non-HTTP failure
///     (offline, DNS, timeout) into a [StorageException] whose statusCode is a
///     Dart runtime type name, so those are excluded;
///  4. everything else, including a bare 403 with another message (an expired
///     token also gives 403), is NOT a refusal.
/// The Storage error shape is NOT verified against the live API.
bool isProgressPhotoProRefusal(
  Object error, {
  required bool uploadStage,
  required bool paymentInFlight,
}) {
  if (error is PostgrestException) {
    return error.code == 'P0001' &&
        error.message.contains('progress_photo_pro_required');
  }
  if (error is StorageException) {
    if (error.message.toLowerCase().contains('row-level security') ||
        error.message.contains('progress_photo_pro_required')) {
      return true;
    }
    final code = error.statusCode;
    return uploadStage &&
        paymentInFlight &&
        (code == '400' || code == '403');
  }
  return false;
}

/// Free photos a free (or lapsed) user may HOLD per IST week (founder call
/// 2026-11-26). The server enforces the same number at both doors; PRO has no
/// cap. A deleted photo frees the week's slot (a retake).
const int progressPhotoFreeWeeklyCap = 1;

/// Age below which an object with no row is never treated as an orphan: a
/// capture on another device may have uploaded and not yet inserted its row,
/// a slow upload may still be running, and the age compares the SERVER's
/// `created_at` with this device's clock, which may be fast. An hour covers
/// all three; the cost is that a capture's own failed cleanup can hold a
/// free slot for up to an hour.
const Duration progressPhotoOrphanMinAge = Duration(minutes: 60);

/// The shorter age for an object THIS device uploaded and then failed to
/// clean up (its row insert failed and so did the removal): no other device
/// can be mid-capture on that exact path, so only clock skew is covered.
const Duration progressPhotoOwnOrphanMinAge = Duration(minutes: 2);

/// The longest the client waits on one Storage housekeeping call: the free
/// slot pre-check (the Add spinner waits on it) and each step of a failed
/// capture's cleanup. A timeout is a failure: the pre-check lets the server
/// decide, a cleanup leaves the path to the sweep.
const Duration progressPhotoStorageCallTimeout = Duration(seconds: 10);

final RegExp _httpStatusOnly = RegExp(r'^\d{3}$');

/// A 4xx that a proxy or the client side can produce while the request may
/// still be running behind it (408 request timeout, 499 client closed): not
/// an answer about the write.
bool _isAnswering4xx(String code) =>
    code.startsWith('4') && code != '408' && code != '499';

/// Did the server ANSWER [error] with a refusal, so the write it belongs to
/// certainly did not land? Pure (OI-348 Landing 3c, Hermes C1/C3).
/// - `PostgrestException`: a SQLSTATE or PGRST code is PostgREST's answer
///   (the statement failed). A bare HTTP status is a body postgrest-dart
///   could not read (`postgrest_builder.dart`, a gateway page): only a 4xx
///   counts, a 5xx (502 / 504), a 408 or a 499 may still have committed
///   behind the proxy.
/// - `StorageException`: a numeric 4xx `statusCode` is Storage's answer; a
///   5xx, or the exception's TYPE NAME (`ClientException`: storage_client's
///   `fetch.dart` uses it for a transport failure), is not.
/// - Anything else (timeout, socket) is not an answer.
/// Not an answer = the outcome is unknown: the caller leaves the path to the
/// 2-minute sweep, which reads the row first.
bool progressPhotoServerRefused(Object error) {
  if (error is PostgrestException) {
    final code = error.code;
    if (code == null || code.isEmpty) return false;
    if (_httpStatusOnly.hasMatch(code)) return _isAnswering4xx(code);
    return true;
  }
  if (error is StorageException) {
    final code = error.statusCode ?? '';
    return _httpStatusOnly.hasMatch(code) && _isAnswering4xx(code);
  }
  return false;
}

/// Logs only in a debug build: these lines carry storage paths, which start
/// with the user id (CLAUDE.md 4.4 rule 17; Hermes D2).
void _log(String message) {
  if (kDebugMode) debugPrint(message);
}

/// The `taken_at` value sent to the `timestamptz` column: the instant in UTC,
/// with an explicit `Z`. (OI-322: `toIso8601String()` on a local time carries no
/// offset and Postgres read it as UTC, storing an IST user's value 5.5 h late.)
String progressPhotoTakenAtWire(DateTime takenAt) =>
    takenAt.toUtc().toIso8601String();

/// Monday 00:00 IST of the IST week holding [now], as a UTC instant: the client
/// mirror of the SQL `public.progress_photo_week_start(now())`. Steps back
/// whole days on the UTC INSTANT (IST has no DST, so a day is 24 h) and takes
/// that day's IST midnight with `istMidnightUtc`; the device zone cannot move
/// it.
DateTime progressPhotoWeekStartUtc(DateTime now) {
  final daysFromMonday = istDateOf(now).weekday - 1;
  return istMidnightUtc(now.toUtc().subtract(Duration(days: daysFromMonday)));
}

/// Reads a Storage `created_at` string as an instant. Storage sends an offset
/// (`...Z` or `+00:00`); a value WITHOUT one is read as UTC (a plain
/// `DateTime.parse` would read it as device-local time). Null when unreadable.
DateTime? parseStorageInstant(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(raw);
  return DateTime.tryParse(hasZone ? raw : '${raw}Z')?.toUtc();
}

/// How many of the objects (by their Storage `created_at`) were created in the
/// IST week holding [now]. An unreadable `created_at` is NOT counted: this is
/// the client's courtesy pre-check, the server decides, and a wrong "used"
/// here would block a user with no way past it.
int progressPhotosHeldThisWeek(Iterable<String?> createdAts, DateTime now) {
  final start = progressPhotoWeekStartUtc(now);
  var n = 0;
  for (final raw in createdAts) {
    final at = parseStorageInstant(raw);
    if (at != null && !at.isBefore(start)) n++;
  }
  return n;
}

/// Is a free photo still open this IST week?
bool progressPhotoFreeSlotOpen(Iterable<String?> createdAts, DateTime now) =>
    progressPhotosHeldThisWeek(createdAts, now) < progressPhotoFreeWeeklyCap;

/// The objects (full paths `<userId>/<name>`) that MAY be orphans: created in
/// the IST week holding [now] AND at least [progressPhotoOrphanMinAge] old
/// ([progressPhotoOwnOrphanMinAge] for a path in [ownFailed], one this device
/// uploaded and could not clean up). Whether each really is one (no row) is
/// decided by the caller from a row read; an unreadable `created_at` is never
/// a candidate.
List<String> progressPhotoOrphanCandidates(
  String userId,
  Iterable<FileObject> objects,
  DateTime now, {
  Set<String> ownFailed = const {},
}) {
  final start = progressPhotoWeekStartUtc(now);
  final nowUtc = now.toUtc();
  final out = <String>[];
  for (final o in objects) {
    final at = parseStorageInstant(o.createdAt);
    if (at == null || at.isBefore(start)) continue;
    final path = '$userId/${o.name}';
    final minAge = ownFailed.contains(path)
        ? progressPhotoOwnOrphanMinAge
        : progressPhotoOrphanMinAge;
    if (nowUtc.difference(at) >= minAge) out.add(path);
  }
  return out;
}

/// Storage content type and file extension for a picked file: the picker's
/// own MIME type when it is one the bucket accepts (jpeg / png / webp), else
/// the file name's extension, else JPEG (the picker re-encodes to JPEG when it
/// resizes anything it cannot keep).
({String ext, String mime}) progressPhotoContentType(
    String fileName, String? mimeType) {
  switch (mimeType?.toLowerCase()) {
    case 'image/png':
      return (ext: 'png', mime: 'image/png');
    case 'image/webp':
      return (ext: 'webp', mime: 'image/webp');
    case 'image/jpeg':
    case 'image/jpg':
      return (ext: 'jpg', mime: 'image/jpeg');
  }
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) return (ext: 'png', mime: 'image/png');
  if (lower.endsWith('.webp')) return (ext: 'webp', mime: 'image/webp');
  return (ext: 'jpg', mime: 'image/jpeg');
}

/// Progress photos — cloud-primary (F19).
///
/// Photos are stored in the `progress-photos` Supabase Storage bucket and
/// indexed in the `progress_photos` table (migration 022). Unlike workout
/// logs etc., there's no Hive mirror — the images themselves are too large
/// to keep local, and we only list metadata when the user opens the
/// gallery. Listings are always freshly fetched.
///
/// Free for everyone to view; uploads are 1 per IST week for a free (or
/// lapsed) user and uncapped for PRO (OI-348 Landing 3c). The screen decides
/// which path a tap takes (`gateAndVerify(featureProgressPhotos)`, server
/// verified, rule 19) and asks [ensureFreeSlotOpen] for a free user before
/// anything is picked; the database enforces the cap at both doors whatever
/// the client does. [capture] itself makes no tier decision.
class ProgressPhotoRepository {
  ProgressPhotoRepository._();
  static final ProgressPhotoRepository instance = ProgressPhotoRepository._();

  static const String _bucket = 'progress-photos';

  /// Test seam, called at the start of every [list]: it lets a test prove that a
  /// screen read the user's photos exactly as often as expected. Null in
  /// production.
  @visibleForTesting
  static void Function()? debugOnListForTests;

  SupabaseService get _s => SupabaseService.instance;

  /// Test seams (null in production): let a screen test script the repository's
  /// answers without Supabase. Each is consulted FIRST by its method.
  @visibleForTesting
  static Future<List<Map<String, dynamic>>> Function()? debugListOverride;
  @visibleForTesting
  static Future<bool> Function(String id)? debugDeleteOverride;
  @visibleForTesting
  static Future<String?> Function(ImageSource source, String bodyArea)?
      debugCaptureOverride;

  /// Screen seam for [ensureFreeSlotOpen] (null in production): return
  /// normally for an open slot, throw [PhotoQuotaException] for a used one.
  @visibleForTesting
  static Future<void> Function()? debugEnsureFreeSlotOverride;

  /// Storage seams for the free-slot check and the orphan sweep (null in
  /// production): the user's own folder listing, the row read by storage
  /// path, and the object removal. The clock is `nowWall()` (ist_date.dart;
  /// tests use `setTestClockTo`).
  @visibleForTesting
  static Future<List<FileObject>> Function(String userId)?
      debugListObjectsOverride;
  @visibleForTesting
  static Future<Set<String>> Function(String userId, List<String> paths)?
      debugRowPathsOverride;
  @visibleForTesting
  static Future<void> Function(List<String> paths)? debugRemoveObjectsOverride;

  /// The free user's courtesy pre-check, run by the screen BEFORE the body
  /// area and the picker: throws [PhotoQuotaException] when this IST week's
  /// free photo is already held. This week's orphans (no row, older than
  /// [progressPhotoOrphanMinAge]) are swept first and do not count once
  /// removed. Any failure returns normally: the server decides.
  Future<void> ensureFreeSlotOpen() async {
    final override = debugEnsureFreeSlotOverride;
    if (override != null) return override();
    final userId = _s.currentUser?.id;
    if (userId == null) return;
    final open = await freeSlotOpen(userId)
        .timeout(progressPhotoStorageCallTimeout, onTimeout: () => null);
    if (open == false) {
      throw const PhotoQuotaException(
        weeklyCap: progressPhotoFreeWeeklyCap,
        message: 'Free photo for this week already used.',
      );
    }
  }

  /// Capture a new progress photo.
  ///
  /// - `source`: camera or gallery (user choice)
  /// - `bodyArea`: 'front' | 'side' | 'back' | any user label
  /// - `weightKgAtTime`: current weight snapshot (optional)
  /// - `notes`: optional user note
  ///
  /// Picks at 2048 px on the long side, JPEG quality 85 (founder call
  /// 2026-11-26), uploads the BYTES (web and Android), then inserts the row.
  /// Returns the new row id on success, null on failure or a cancelled pick.
  /// Throws [ProgressPhotoProRequiredException] when the server refused the
  /// photo (see [isProgressPhotoProRefusal]).
  Future<String?> capture({
    required ImageSource source,
    required String bodyArea,
    double? weightKgAtTime,
    String? notes,
  }) async {
    final override = debugCaptureOverride;
    if (override != null) return override(source, bodyArea);

    final userId = _s.currentUser?.id;
    if (userId == null) {
      _log('[ProgressPhotoRepository.capture] no user — abort');
      return null;
    }

    // `uploadStage` is false until the picker has returned a file: a cancelled
    // pick (null) and a picker error are never a server refusal.
    var uploadStage = false;
    String? attemptedPath;
    String? uploadedPath;
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (xfile == null) return null;
      uploadStage = true;

      final type = progressPhotoContentType(xfile.name, xfile.mimeType);
      final bytes = await xfile.readAsBytes();
      final takenAt = nowWall();
      final storagePath =
          '$userId/${takenAt.toIso8601String().replaceAll(':', '-')}_$bodyArea.${type.ext}';

      // Bytes, not dart:io File: a web pick's path is a blob URL that File
      // cannot open (web uploads failed before OI-348 Landing 3c).
      attemptedPath = storagePath;
      await _s.client.storage.from(_bucket).uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              cacheControl: '3600',
              contentType: type.mime,
              upsert: false,
            ),
          );
      uploadStage = false;
      uploadedPath = storagePath;

      final row = await _s.client.from('progress_photos').insert({
        'user_id': userId,
        'storage_path': storagePath,
        'body_area': bodyArea,
        'taken_at': progressPhotoTakenAtWire(takenAt),
        'weight_kg_at_time': weightKgAtTime,
        'notes': notes,
      }).select('id').single();
      return row['id'] as String?;
    } catch (e) {
      _log('[ProgressPhotoRepository.capture] $e');
      if (uploadedPath != null) {
        await cleanupAfterFailedInsert(userId, uploadedPath, e);
      } else if (attemptedPath != null) {
        noteFailedUpload(attemptedPath, e);
      }
      if (isProgressPhotoProRefusal(
        e,
        uploadStage: uploadStage,
        paymentInFlight: SubscriptionService.instance.isPaymentInFlight,
      )) {
        throw const ProgressPhotoProRequiredException();
      }
      return null;
    }
  }

  /// The object of THIS capture was uploaded and its row insert then failed
  /// with [error]. A server answer ([progressPhotoServerRefused]) means the
  /// insert did not commit: clean up now ([removeIfNoRow]). Anything else
  /// (no network, a timeout, a gateway 5xx) may still be running on the
  /// server, where the row can commit AFTER a read that found none, and
  /// removing the object then would leave a row with no picture: the path
  /// goes to the 2-minute sweep ([ownFailedCleanups]), which reads the row
  /// again first. Until then the object holds the free slot (the server
  /// counts it too).
  @visibleForTesting
  Future<void> cleanupAfterFailedInsert(
      String userId, String path, Object error) async {
    if (progressPhotoServerRefused(error)) {
      await removeIfNoRow(userId, path);
    } else {
      ownFailedCleanups.add(path);
    }
  }

  /// The UPLOAD of [path] failed with [error] (Hermes C1). A Storage answer
  /// means nothing was stored. Anything else may have stored the object with
  /// only the response lost: remember the path so the 2-minute sweep (not the
  /// hour) frees the slot if no row ever comes. A path never stored is never
  /// listed, so remembering it costs nothing.
  @visibleForTesting
  void noteFailedUpload(String path, Object error) {
    if (!progressPhotoServerRefused(error)) ownFailedCleanups.add(path);
  }

  /// Remove [path] so it cannot hold the free slot, but ONLY after a
  /// successful read shows no row with that path. Any failure (a timeout
  /// included) removes nothing and remembers the path for the 2-minute sweep.
  @visibleForTesting
  Future<void> removeIfNoRow(String userId, String path) async {
    try {
      final withRow = await _rowPaths(userId, [path])
          .timeout(progressPhotoStorageCallTimeout);
      if (withRow.contains(path)) return;
      await _removeObjects([path]).timeout(progressPhotoStorageCallTimeout);
    } catch (e) {
      // Remembered for this app run: the sweep retries it after
      // [progressPhotoOwnOrphanMinAge] instead of an hour.
      ownFailedCleanups.add(path);
      _log('[ProgressPhotoRepository.capture] orphan kept: $path: $e');
    }
  }

  /// Paths this device uploaded whose cleanup failed (in memory, this app run
  /// only). A path leaves the set once the sweep removed it or found its row.
  @visibleForTesting
  final Set<String> ownFailedCleanups = <String>{};

  /// Is a free photo still open this IST week for [userId]? Null when the
  /// listing failed (unknown: the caller lets the server decide).
  @visibleForTesting
  Future<bool?> freeSlotOpen(String userId) async {
    final List<FileObject> objects;
    try {
      objects = await _listObjects(userId);
    } catch (e) {
      _log('[ProgressPhotoRepository] slot check failed: $e');
      return null;
    }
    final removed = await _sweepOrphans(userId, objects);
    return progressPhotoFreeSlotOpen(
      [
        for (final o in objects)
          if (!removed.contains('$userId/${o.name}')) o.createdAt,
      ],
      nowWall(),
    );
  }

  Future<List<FileObject>> _listObjects(String userId) {
    final o = debugListObjectsOverride;
    if (o != null) return o(userId);
    return _s.client.storage.from(_bucket).list(
          path: userId,
          searchOptions: const SearchOptions(
            limit: 100,
            sortBy: SortBy(column: 'created_at', order: 'desc'),
          ),
        );
  }

  Future<Set<String>> _rowPaths(String userId, List<String> paths) async {
    final o = debugRowPathsOverride;
    if (o != null) return o(userId, paths);
    final rows = await _s.client
        .from('progress_photos')
        .select('storage_path')
        .eq('user_id', userId)
        .inFilter('storage_path', paths);
    return {for (final r in rows) r['storage_path'] as String? ?? ''}
      ..remove('');
  }

  Future<void> _removeObjects(List<String> paths) async {
    final o = debugRemoveObjectsOverride;
    if (o != null) return o(paths);
    await _s.client.storage.from(_bucket).remove(paths);
  }

  /// List all progress photos for the current user, newest first, and let a
  /// failure PROPAGATE. The screen uses this so a failed read is never mistaken
  /// for "no photos" (a lapsed user's photos must not vanish behind the upsell).
  /// Returns `[{id, storage_path, body_area, taken_at, weight_kg_at_time,
  /// signed_url}, ...]`.
  Future<List<Map<String, dynamic>>> listStrict({int limit = 200}) async {
    debugOnListForTests?.call();
    final override = debugListOverride;
    if (override != null) return override();
    final userId = _s.currentUser?.id;
    if (userId == null) return const [];

    final rows = await _s.client
        .from('progress_photos')
        .select()
        .eq('user_id', userId)
        .order('taken_at', ascending: false)
        .limit(limit);

    final out = <Map<String, dynamic>>[];
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw as Map);
      final path = row['storage_path'] as String? ?? '';
      String? signedUrl;
      if (path.isNotEmpty) {
        try {
          signedUrl = await _s.client.storage
              .from(_bucket)
              .createSignedUrl(path, 60 * 60); // 1-hour TTL
        } catch (e) {
          _log('[ProgressPhotoRepository.list] signedUrl failed: $e');
        }
      }
      row['signed_url'] = signedUrl;
      out.add(row);
    }
    return out;
  }

  /// [listStrict] with every failure swallowed into an empty list (the
  /// pre-OI-314 behaviour, kept for any caller that wants "best effort").
  Future<List<Map<String, dynamic>>> list({int limit = 200}) async {
    try {
      return await listStrict(limit: limit);
    } catch (e) {
      _log('[ProgressPhotoRepository.list] $e');
      return const [];
    }
  }

  /// Delete a progress photo (row + storage object).
  Future<bool> delete(String id) async {
    final override = debugDeleteOverride;
    if (override != null) return override(id);
    final userId = _s.currentUser?.id;
    if (userId == null) return false;

    try {
      // Fetch the storage path first so we can delete the object too.
      final rows = await _s.client
          .from('progress_photos')
          .select('storage_path')
          .eq('id', id)
          .eq('user_id', userId)
          .limit(1);
      if (rows.isEmpty) return false;
      final path = rows.first['storage_path'] as String? ?? '';

      await _s.client
          .from('progress_photos')
          .delete()
          .eq('id', id)
          .eq('user_id', userId);

      if (path.isNotEmpty) {
        await removeDeletedPhotoObject(path);
      }
      return true;
    } catch (e) {
      _log('[ProgressPhotoRepository.delete] $e');
      return false;
    }
  }

  /// After [delete] removed a photo's ROW: remove its object. A failure
  /// leaves an object with no row that would hold a free user's slot after
  /// they deleted the photo to retake it (Hermes C2 / D1): the path is
  /// remembered so the next Add's sweep removes it after 2 minutes, not an
  /// hour. An object from an earlier week holds no slot either way.
  @visibleForTesting
  Future<void> removeDeletedPhotoObject(String path) async {
    try {
      await _removeObjects([path]).timeout(progressPhotoStorageCallTimeout);
    } catch (e) {
      ownFailedCleanups.add(path);
      _log('[ProgressPhotoRepository.delete] object kept for the sweep: $path: $e');
    }
  }

  /// Removes this IST week's orphaned Storage objects of the current user: an
  /// object under the user's folder, created this week, at least
  /// [progressPhotoOrphanMinAge] old, with no `progress_photos` row. Such an
  /// object would hold a free user's weekly slot while the gallery shows
  /// nothing (a capture whose app was killed between the upload and the row).
  ///
  /// BOUNDED on purpose: only this week's candidates, rows read by path for
  /// exactly those candidates. (Before OI-348 Landing 3c this compared ALL of
  /// the user's objects with ALL rows: a truncated row read would have
  /// removed real photos.) Any read failure removes nothing. Best effort;
  /// failures are logged and swallowed (the user read included). Run, unawaited,
  /// by a PRO user's Add tap; a free user's Add runs the same `_sweepOrphans`
  /// inside [freeSlotOpen].
  Future<void> cleanupOrphanedStorage() async {
    try {
      final userId = _s.currentUser?.id;
      if (userId == null) return;
      final objects = await _listObjects(userId);
      await _sweepOrphans(userId, objects);
    } catch (e, st) {
      _log(
          '[ProgressPhotoRepository.cleanupOrphanedStorage] scan failed: $e\n$st');
    }
  }

  /// The sweep itself, over a listing the caller already holds. Returns the
  /// paths it REMOVED (empty when nothing was removed or anything failed).
  Future<Set<String>> _sweepOrphans(
      String userId, List<FileObject> objects) async {
    final candidates = progressPhotoOrphanCandidates(userId, objects, nowWall(),
        ownFailed: ownFailedCleanups);
    if (candidates.isEmpty) return const {};
    final Set<String> withRow;
    try {
      withRow = await _rowPaths(userId, candidates);
    } catch (e, st) {
      _log(
          '[ProgressPhotoRepository.cleanupOrphanedStorage] scan failed: $e\n$st');
      return const {};
    }
    ownFailedCleanups.removeAll(withRow);
    final orphans = [
      for (final p in candidates)
        if (!withRow.contains(p)) p,
    ];
    if (orphans.isEmpty) return const {};
    _log(
        '[ProgressPhotoRepository.cleanupOrphanedStorage] found ${orphans.length} orphan(s): $orphans');
    try {
      await _removeObjects(orphans);
      ownFailedCleanups.removeAll(orphans);
      _log(
          '[ProgressPhotoRepository.cleanupOrphanedStorage] removed ${orphans.length} orphan(s)');
      return orphans.toSet();
    } catch (e, st) {
      _log(
          '[ProgressPhotoRepository.cleanupOrphanedStorage] remove failed: $e\n$st');
      return const {};
    }
  }

  /// Returns the count of progress photos for the current user.
  /// Cheap — doesn't hit Storage.
  Future<int> count() async {
    final userId = _s.currentUser?.id;
    if (userId == null) return 0;
    try {
      final rows = await _s.client
          .from('progress_photos')
          .select('id')
          .eq('user_id', userId);
      return rows.length;
    } catch (e) {
      _log('[ProgressPhotoRepository.count] $e');
      return 0;
    }
  }
}
