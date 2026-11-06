/// The ONE-request "does the backend answer at all?" probe, free of
/// `SyncService` so its behaviour is testable against a stub server.
///
/// closes-diagnose e5b2a9 (B-pass F3 — the probe had no test and the registry
/// cited one). A server that answers "no" (401 / RLS / PGRST301) is REACHABLE; a
/// 5xx / Cloudflare 52x / PGRST000-003 / socket failure is not.
///
/// ONE request per probe: the supabase SDK otherwise retries a GET that is
/// answered 503/520 — or that throws — three more times (1 s, 2 s, 4 s;
/// `postgrest` `_executeWithRetry`), and 503 is the real PGRST002 outage shape.
/// The query therefore opts out with `.retry(enabled: false)`.
library;

import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, SupabaseClient;

import 'sync_retry_controller.dart' show isOutageShapedFailure;

/// Probes the signed-in user's own `users` row (existing RLS) through [client].
Future<bool> probeBackendWithClient(SupabaseClient client, String uid) async {
  try {
    final q = client
        .from('users')
        .select('id')
        .eq('id', uid)
        .limit(1)
        .retry(enabled: false);
    // PostgREST builders are thenables — flatten before awaiting.
    await Future<dynamic>.value(q);
    return true;
  } catch (e) {
    // Only a PostgREST error that is NOT outage-shaped means the server
    // answered. Anything else (socket, timeout, unknown) = unreachable.
    return e is PostgrestException && !isOutageShapedFailure(e);
  }
}
