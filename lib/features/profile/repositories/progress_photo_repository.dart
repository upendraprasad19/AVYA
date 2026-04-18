import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../../core/services/subscription_service.dart';
import '../../../core/services/supabase_service.dart';

/// Thrown when a user hits their daily progress-photo upload quota.
/// The UI catches this and surfaces the appropriate paywall / retry-
/// tomorrow snackbar.
class PhotoQuotaException implements Exception {
  final int dailyCap;
  final bool isPro;
  final String message;
  const PhotoQuotaException({
    required this.dailyCap,
    required this.isPro,
    required this.message,
  });
  @override
  String toString() => message;
}

/// Progress photos — cloud-primary (F19).
///
/// Photos are stored in the `progress-photos` Supabase Storage bucket and
/// indexed in the `progress_photos` table (migration 022). Unlike workout
/// logs etc., there's no Hive mirror — the images themselves are too large
/// to keep local, and we only list metadata when the user opens the
/// gallery. Listings are always freshly fetched.
///
/// PRO-gated at the call sites per CLAUDE.md §10 (`progress_photos` is in
/// the high-value feature allowlist with server-side verify).
class ProgressPhotoRepository {
  ProgressPhotoRepository._();
  static final ProgressPhotoRepository instance = ProgressPhotoRepository._();

  static const String _bucket = 'progress-photos';

  /// Daily upload caps — enforced at capture time.
  /// Free: 2/day. PRO: 5/day.
  /// (Lifetime cap is deferred; revisit at 10K users.)
  static const int _freeDailyCap = 2;
  static const int _proDailyCap = 5;

  SupabaseService get _s => SupabaseService.instance;

  /// Capture a new progress photo.
  ///
  /// - `source`: camera or gallery (user choice)
  /// - `bodyArea`: 'front' | 'side' | 'back' | any user label
  /// - `weightKgAtTime`: current weight snapshot (optional — pulled from
  ///   profile if null)
  /// - `notes`: optional user note
  ///
  /// Returns the new row id on success, null on failure.
  Future<String?> capture({
    required ImageSource source,
    required String bodyArea,
    double? weightKgAtTime,
    String? notes,
  }) async {
    final userId = _s.currentUser?.id;
    if (userId == null) {
      debugPrint('[ProgressPhotoRepository.capture] no user — abort');
      return null;
    }

    // Daily cap check (audit H8). Count today's existing photos for this
    // user before picking. If over-cap, throw and let the UI surface
    // the paywall / try-tomorrow snackbar.
    final isPro = SubscriptionService.instance.isPro();
    final dailyCap = isPro ? _proDailyCap : _freeDailyCap;
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
      final todays = await _s.client
          .from('progress_photos')
          .select('id')
          .eq('user_id', userId)
          .gte('taken_at', startOfDay);
      if (todays.length >= dailyCap) {
        throw PhotoQuotaException(
          dailyCap: dailyCap,
          isPro: isPro,
          message: isPro
              ? 'Daily limit reached ($dailyCap/day). Come back tomorrow.'
              : 'Daily limit reached ($dailyCap/day). Upgrade to PRO for $_proDailyCap/day.',
        );
      }
    } on PhotoQuotaException {
      rethrow;
    } catch (e) {
      // Cap-check failure is non-fatal; fall through to upload attempt.
      debugPrint('[ProgressPhotoRepository.capture] cap-check failed: $e');
    }

    try {
      // Tier-differentiated image quality at pick time (audit H8).
      // Free → 2048 / 85%  (~500 KB, retina-sharp on phones).
      // PRO  → 3000 / 95%  (~1.5 MB, headroom for future video render).
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: source,
        imageQuality: isPro ? 95 : 85,
        maxWidth: isPro ? 3000 : 2048,
      );
      if (xfile == null) return null;

      final file = File(xfile.path);
      final takenAt = DateTime.now();
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

      final row = await _s.client.from('progress_photos').insert({
        'user_id': userId,
        'storage_path': storagePath,
        'body_area': bodyArea,
        'taken_at': takenAt.toIso8601String(),
        'weight_kg_at_time': weightKgAtTime,
        'notes': notes,
      }).select('id').single();
      return row['id'] as String?;
    } catch (e) {
      debugPrint('[ProgressPhotoRepository.capture] $e');
      return null;
    }
  }

  /// List all progress photos for the current user, newest first.
  /// Returns `[{id, storage_path, body_area, taken_at, weight_kg_at_time,
  /// signed_url}, ...]`.
  Future<List<Map<String, dynamic>>> list({int limit = 200}) async {
    final userId = _s.currentUser?.id;
    if (userId == null) return const [];

    try {
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
    } catch (e) {
      debugPrint('[ProgressPhotoRepository.list] $e');
      return const [];
    }
  }

  /// Delete a progress photo (row + storage object).
  Future<bool> delete(String id) async {
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
          // Row is gone — orphan object is a later cleanup concern.
        }
      }
      return true;
    } catch (e) {
      debugPrint('[ProgressPhotoRepository.delete] $e');
      return false;
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
