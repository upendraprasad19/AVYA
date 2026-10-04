import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SearchOptions;

import '../../../core/services/error_telemetry.dart';
import '../../../core/services/subscription_service.dart';
import '../../../core/services/supabase_service.dart';

/// Coach-media consent (Unit 8, OI-25).
///
/// A user can opt to keep a photo they sent the AI coach for future
/// reference. On consent, [saveForLater] copies the blob from the
/// transient `chat-media` bucket (30-day TTL for free users, purged by the
/// `clean-orphan-media` cron) into the long-term `coach-media` bucket
/// (migration 070). No metadata table — `list()` reads directly from
/// Storage, mirroring `ProgressPhotoRepository.list()`'s signed-URL
/// pattern even though that repository is table-backed and this isn't.
///
/// Founder's original design note (migration 070 header, 2026-05-17):
/// "i intend to store coach uploaded media. We ask user does he want to
/// store the pic for future reference and on consent we save it."
class CoachMediaRepository {
  CoachMediaRepository._();
  static final CoachMediaRepository instance = CoachMediaRepository._();

  static const String _sourceBucket = 'chat-media';
  static const String _destBucket = 'coach-media';

  SupabaseService get _s => SupabaseService.instance;

  /// Copies [chatMediaPath] (a path within `chat-media`, e.g.
  /// `<uid>/<ms>.jpg`) into `coach-media` at the SAME relative path — both
  /// buckets share the `<user_id>/<filename>` RLS layout (migration 070 for
  /// `coach-media`; migration 116 added the matching `chat-media` DELETE-own
  /// policy this method's cleanup step needs), so no new path scheme is
  /// needed.
  ///
  /// Keeps the `chat-media` source until the copy confirms success. Then:
  /// IF the caller is on the free tier at that exact moment, the source is
  /// deleted immediately (it would otherwise wait up to 30 days for
  /// `clean-orphan-media`, needlessly duplicating storage once a permanent
  /// copy exists) — in practice this branch fires only for a PRO user who
  /// downgrades in the narrow window between uploading a photo (photo
  /// attach is PRO-gated at every LIVE entry point — `recording_body.dart`'s
  /// `_onTapAttach` (what the real input-bar attach button calls) and
  /// `media_picker.dart`'s own `SubscriptionService.gate` call in
  /// `_pickImage`; `attach_button.dart` is an older attach-button build
  /// that is `// ignore: unused_element` dead code, not a live gate, per
  /// its own comment — B-pass finding 2026-07-30, this doc previously
  /// miscited it as one of the live gates — so a free user can never
  /// originate one of these photos) and tapping Save on it; this is a
  /// real, if rare, path, not dead code. PRO users (the common case) keep
  /// both — the
  /// `clean-orphan-media` cron already skips PRO users unconditionally
  /// (`rechecksIsPro` in `supabase/functions/clean-orphan-media/index.ts`),
  /// so this mirrors, rather than special-cases, that existing behaviour.
  ///
  /// Returns true only when the copy itself succeeds (or is confirmed to
  /// have already succeeded on a prior attempt — see the retry-idempotency
  /// note below) — a failed post-copy source cleanup is logged and
  /// swallowed (non-fatal: the permanent copy already exists; a leftover
  /// `chat-media` source is not user-visible and self-heals via the 30-day
  /// cron for free users, or is legitimately retained for PRO).
  Future<bool> saveForLater(String chatMediaPath) async {
    final userId = _s.currentUser?.id;
    if (userId == null) {
      debugPrint('[CoachMediaRepository.saveForLater] no user — abort');
      return false;
    }
    // Defense-in-depth ownership assertion — RLS enforces this server-side
    // too (coach_media_insert_own / chat_media policies), but failing
    // fast client-side avoids a round-trip on a plainly-wrong path.
    if (!chatMediaPath.startsWith('$userId/')) {
      debugPrint(
          '[CoachMediaRepository.saveForLater] path not owned by caller — abort');
      return false;
    }

    try {
      await _s.client.storage
          .from(_sourceBucket)
          .copy(chatMediaPath, chatMediaPath, destinationBucket: _destBucket);
    } catch (e) {
      // Round-2 review (2026-07-30) — a `.copy()` whose server-side write
      // succeeded but whose response the client never received (network
      // blip / app backgrounded mid-request) makes a RETRY see whatever
      // error the server returns for a destination that already exists.
      // The op is idempotent by content (same source, same deterministic
      // path), so before reporting failure, confirm the destination is
      // genuinely still missing — if it's already there, this call already
      // achieved its goal and should return success, not a spurious error
      // + telemetry event for a photo the user's earlier tap already saved.
      if (await _destinationExists(chatMediaPath)) {
        debugPrint(
            '[CoachMediaRepository.saveForLater] copy errored but '
            'destination already exists — treating as success: $e');
      } else {
        debugPrint('[CoachMediaRepository.saveForLater] copy failed: $e');
        // Mirrors media_picker.dart's own upload-failure telemetry — this
        // is the closest analog (the core mutating Storage op this
        // repository exists to perform, failing), so a systemic issue
        // (e.g. an RLS misconfiguration) is founder-visible without
        // relying on user reports
        // (feedback_operational_observability_first.md).
        final errStr = e.toString();
        unawaited(ErrorTelemetry.logEvent(
          'coach_media_save_for_later_failed',
          message: errStr.length > 500 ? errStr.substring(0, 500) : errStr,
        ));
        return false;
      }
    }

    final isPro = SubscriptionService.instance.isPro();
    if (!isPro) {
      try {
        await _s.client.storage.from(_sourceBucket).remove([chatMediaPath]);
      } catch (e) {
        debugPrint(
            '[CoachMediaRepository.saveForLater] source cleanup failed: $e');
      }
    }
    return true;
  }

  /// Round-2 review (2026-07-30) — checks whether [chatMediaPath]'s basename
  /// already exists at the same relative path in `coach-media`, used ONLY to
  /// distinguish a genuine copy failure from a retry-after-already-succeeded
  /// (see [saveForLater]). Any error here (e.g. the list call itself fails)
  /// is treated as "doesn't exist" — the conservative direction, since it
  /// falls through to reporting the original copy error rather than
  /// masking it.
  Future<bool> _destinationExists(String path) async {
    final parts = path.split('/');
    if (parts.length < 2) return false;
    final folder = parts.first;
    final fileName = parts.sublist(1).join('/');
    try {
      final objects = await _s.client.storage.from(_destBucket).list(
            path: folder,
            searchOptions: SearchOptions(search: fileName, limit: 1),
          );
      return objects.any((o) => o.name == fileName);
    } catch (e) {
      debugPrint('[CoachMediaRepository._destinationExists] $e');
      return false;
    }
  }

  /// Lists saved coach-media photos for the current user, newest first.
  /// Returns `[{path, name, created_at, signed_url}, ...]`. No DB table —
  /// reads directly from Storage (mirrors `ProgressPhotoRepository.list()`'s
  /// signed-URL pattern).
  Future<List<Map<String, dynamic>>> list({int limit = 200}) async {
    final userId = _s.currentUser?.id;
    if (userId == null) return const [];

    try {
      final objects =
          await _s.client.storage.from(_destBucket).list(path: userId);
      final sorted = [...objects]
        ..sort((a, b) =>
            (b.createdAt ?? '').compareTo(a.createdAt ?? ''));

      final out = <Map<String, dynamic>>[];
      for (final obj in sorted.take(limit)) {
        final path = '$userId/${obj.name}';
        String? signedUrl;
        try {
          signedUrl = await _s.client.storage
              .from(_destBucket)
              .createSignedUrl(path, 60 * 60); // 1-hour TTL
        } catch (e) {
          debugPrint('[CoachMediaRepository.list] signedUrl failed: $e');
        }
        out.add({
          'path': path,
          'name': obj.name,
          'created_at': obj.createdAt,
          'signed_url': signedUrl,
        });
      }
      return out;
    } catch (e) {
      debugPrint('[CoachMediaRepository.list] $e');
      return const [];
    }
  }

  /// Deletes a saved coach-media photo (Storage object only — no DB row).
  Future<bool> delete(String path) async {
    final userId = _s.currentUser?.id;
    if (userId == null || !path.startsWith('$userId/')) return false;
    try {
      await _s.client.storage.from(_destBucket).remove([path]);
      return true;
    } catch (e) {
      debugPrint('[CoachMediaRepository.delete] $e');
      return false;
    }
  }
}
