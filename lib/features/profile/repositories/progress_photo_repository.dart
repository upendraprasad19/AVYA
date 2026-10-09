import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, PostgrestException, StorageException;

import '../../../core/services/subscription_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/ist_date.dart';

/// Thrown when a user hits their daily progress-photo upload quota (5 per IST
/// day). The UI catches this and shows a come-back-tomorrow snackbar. Only PRO
/// users reach `capture` (the screen gates the call and the server refuses the
/// rest), so there is no upgrade branch.
class PhotoQuotaException implements Exception {
  final int dailyCap;
  final String message;
  const PhotoQuotaException({
    required this.dailyCap,
    required this.message,
  });
  @override
  String toString() => message;
}

/// Thrown by [ProgressPhotoRepository.capture] when the SERVER refused the new
/// photo because the caller has no active, unexpired subscription (migration
/// 154: the Storage INSERT policy `progress_photos_insert_own`, and the BEFORE
/// INSERT trigger on `public.progress_photos`, PostgREST `P0001`
/// `progress_photo_pro_required`). Not a quota and not a generic failure: the
/// screen decides between the paywall and "still activating" (OI-314).
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
///     in its message (the trigger);
///  2. a [StorageException] whose message contains `row-level security`
///     (case-insensitive; the Storage policy's refusal. Migration 154's header:
///     key on the status OR this message, never on the HTTP status);
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
    if (error.message.toLowerCase().contains('row-level security')) {
      return true;
    }
    final code = error.statusCode;
    return uploadStage &&
        paymentInFlight &&
        (code == '400' || code == '403');
  }
  return false;
}

/// Daily upload cap: 5 per IST day (client-side; a server cap is OI-315).
const int progressPhotoDailyCap = 5;

/// Has [todaysCount] (the user's photos since IST midnight) reached the cap?
/// Pure, so the boundary (4 no, 5 yes, 6 yes) is tested directly.
bool progressPhotoCapReached(int todaysCount) =>
    todaysCount >= progressPhotoDailyCap;

/// The `taken_at` value sent to the `timestamptz` column: the instant in UTC,
/// with an explicit `Z`. (OI-322: `toIso8601String()` on a local time carries no
/// offset and Postgres read it as UTC, storing an IST user's value 5.5 h late.)
String progressPhotoTakenAtWire(DateTime takenAt) =>
    takenAt.toUtc().toIso8601String();

/// Start of the daily-cap window as a UTC ISO string: IST midnight of the day
/// containing [now] (the project counts days in IST; `istMidnightUtc` is
/// independent of the device zone).
String progressPhotoCapWindowStartUtc(DateTime now) =>
    istMidnightUtc(now).toIso8601String();

/// Progress photos — cloud-primary (F19).
///
/// Photos are stored in the `progress-photos` Supabase Storage bucket and
/// indexed in the `progress_photos` table (migration 022). Unlike workout
/// logs etc., there's no Hive mirror — the images themselves are too large
/// to keep local, and we only list metadata when the user opens the
/// gallery. Listings are always freshly fetched.
///
/// PRO-gated at the call sites per docs/architecture/subscription.md (`progress_photos` is in
/// the high-value feature allowlist with server-side verify).
class ProgressPhotoRepository {
  ProgressPhotoRepository._();
  static final ProgressPhotoRepository instance = ProgressPhotoRepository._();

  static const String _bucket = 'progress-photos';

  /// Daily upload cap: 5 per IST day, enforced client-side at capture time.
  /// (A server-side cap is OI-315.) The repository's former free tier (2/day,
  /// 2048 px / 85 %) is gone (founder decision 5, 2026-10-06; OI-314): the screen
  /// gates the call and the server refuses a free caller (migration 154).
  static const int _dailyCap = progressPhotoDailyCap;

  /// Test seam, called at the start of every [list]: it lets a test prove that a
  /// screen which must not read photos (a user the PRO gate refused) did not,
  /// and that a granted one read exactly once. Null in production.
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

  /// Capture a new progress photo.
  ///
  /// - `source`: camera or gallery (user choice)
  /// - `bodyArea`: 'front' | 'side' | 'back' | any user label
  /// - `weightKgAtTime`: current weight snapshot (optional — pulled from
  ///   profile if null)
  /// - `notes`: optional user note
  ///
  /// Returns the new row id on success, null on failure or a cancelled pick.
  /// Throws [PhotoQuotaException] at the daily cap and
  /// [ProgressPhotoProRequiredException] when the server refused the photo
  /// because the caller has no active subscription (see
  /// [isProgressPhotoProRefusal]). The caller (the screen) has already passed
  /// its PRO gate; this method makes no PRO decision of its own.
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
      debugPrint('[ProgressPhotoRepository.capture] no user — abort');
      return null;
    }

    // Daily cap check (audit H8). Count today's (IST) photos for this user
    // before picking. If over-cap, throw and let the UI show the
    // come-back-tomorrow snackbar.
    try {
      final startOfDay = progressPhotoCapWindowStartUtc(nowWall());
      final todays = await _s.client
          .from('progress_photos')
          .select('id')
          .eq('user_id', userId)
          .gte('taken_at', startOfDay);
      if (progressPhotoCapReached(todays.length)) {
        throw const PhotoQuotaException(
          dailyCap: _dailyCap,
          message: 'Daily limit reached ($_dailyCap/day). Come back tomorrow.',
        );
      }
    } on PhotoQuotaException {
      rethrow;
    } catch (e) {
      // Cap-check failure is non-fatal; fall through to upload attempt.
      debugPrint('[ProgressPhotoRepository.capture] cap-check failed: $e');
    }

    // `uploadStage` is false until the picker has returned a file: a cancelled
    // pick (null) and a picker error are never a server refusal.
    var uploadStage = false;
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: 3000,
      );
      if (xfile == null) return null;
      uploadStage = true;

      final file = File(xfile.path);
      final takenAt = nowWall();
      final storagePath =
          '$userId/${takenAt.toIso8601String().replaceAll(':', '-')}_$bodyArea.jpg';

      await _s.client.storage.from(_bucket).upload(
            storagePath,
            file,
            fileOptions: const FileOptions(
              cacheControl: '3600',
              upsert: false,
            ),
          );
      uploadStage = false;

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
      debugPrint('[ProgressPhotoRepository.capture] $e');
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
          debugPrint('[ProgressPhotoRepository.list] signedUrl failed: $e');
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
      debugPrint('[ProgressPhotoRepository.list] $e');
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
        try {
          await _s.client.storage.from(_bucket).remove([path]);
        } catch (e) {
          debugPrint('[ProgressPhotoRepository.delete] storage remove: $e');
          // Row is gone — log the orphaned object so we can clean it up later
          // via cleanupOrphanedStorage(). Uses debugPrint only (no SyncService
          // dependency here); route to client_errors when a lightweight public
          // reporter is wired into this repository.
          debugPrint(
              '[ProgressPhotoRepository.delete] orphaned storage object: $path — $e');
        }
      }
      return true;
    } catch (e) {
      debugPrint('[ProgressPhotoRepository.delete] $e');
      return false;
    }
  }

  /// Scans for orphaned Storage objects — objects that exist in the `progress-photos`
  /// bucket under the user's prefix but have no matching row in `progress_photos`.
  ///
  /// Safe to call fire-and-forget; all failures are logged and swallowed. This is
  /// a best-effort background cleanup that runs when the gallery screen opens after
  /// a delete that failed to remove the Storage object.
  Future<void> cleanupOrphanedStorage() async {
    final userId = _s.currentUser?.id;
    if (userId == null) return;

    try {
      // List all objects in the user's Storage prefix.
      final objects =
          await _s.client.storage.from(_bucket).list(path: userId);

      if (objects.isEmpty) return;

      // Fetch all known storage paths from the DB for this user.
      final rows = await _s.client
          .from('progress_photos')
          .select('storage_path')
          .eq('user_id', userId);
      final knownPaths = {
        for (final r in rows) r['storage_path'] as String? ?? ''
      }..remove('');

      // Remove any Storage object that has no matching DB row.
      final orphans = objects
          .where((o) {
            final fullPath = '$userId/${o.name}';
            return !knownPaths.contains(fullPath);
          })
          .map((o) => '$userId/${o.name}')
          .toList();

      if (orphans.isEmpty) return;

      debugPrint(
          '[ProgressPhotoRepository.cleanupOrphanedStorage] found ${orphans.length} orphan(s): $orphans');

      try {
        await _s.client.storage.from(_bucket).remove(orphans);
        debugPrint(
            '[ProgressPhotoRepository.cleanupOrphanedStorage] removed ${orphans.length} orphan(s)');
      } catch (e, st) {
        // Log failure — this is the gap the audit identified (P2).
        // Route to client_errors when a public reporter is available here.
        debugPrint(
            '[ProgressPhotoRepository.cleanupOrphanedStorage] remove failed: $e\n$st');
      }
    } catch (e, st) {
      debugPrint(
          '[ProgressPhotoRepository.cleanupOrphanedStorage] scan failed: $e\n$st');
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
      debugPrint('[ProgressPhotoRepository.count] $e');
      return 0;
    }
  }
}
