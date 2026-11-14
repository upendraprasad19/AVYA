part of '../sync_service.dart';

/// closes-diagnose e5b2a9 — outage-resilience entry point for
/// `SyncRetryController` (the reachability probe).
extension SyncServiceResilience on SyncService {
  /// Does the backend ANSWER at all? Runs only while a failure is pending, so
  /// steady-state cost is zero. The request itself (ONE request, SDK retry
  /// disabled) and its answer/outage classification live in
  /// `backend_probe.dart` so they are behaviourally tested; this adds the session
  /// guard and the 8 s ceiling.
  Future<bool> probeBackendReachable() async {
    try {
      return await _probeBackend()
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _probeBackend() async {
    try {
      // A stale token 401s the probe; a 401 still counts as "answered", but
      // refreshing first keeps the probe honest (CLAUDE.md §4.4 rule 9).
      await _supabase.ensureFreshToken();
      final uid = _supabase.currentUser?.id;
      if (uid == null) return false;
      return await probeBackendWithClient(_supabase.client, uid);
    } catch (_) {
      return false;
    }
  }
}
