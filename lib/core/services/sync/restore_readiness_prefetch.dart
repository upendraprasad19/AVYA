// OI-348 B10 (diagnose a0d5f7): the single-call restore starts its standalone
// `readiness_daily` read at the same time as the `restore-user-snapshot` call,
// so the read (2.8 s on the walk) overlaps the Edge Function instead of adding
// to step B.
//
// Pure, no Hive or Supabase import: the call site passes the read, the two
// restore callbacks and the failure report, so every branch is tested here
// (test/sync/restore_readiness_prefetch_test.dart).

import 'dart:async';

/// The settled result of a started prefetch. A prefetch future NEVER rejects:
/// it is wrapped at creation, so a prefetch nobody consumes (legacy fallback,
/// cancel, owner change) can never surface as an unhandled error.
sealed class ReadinessPrefetchOutcome {
  const ReadinessPrefetchOutcome();
}

final class ReadinessPrefetchOk extends ReadinessPrefetchOutcome {
  const ReadinessPrefetchOk(this.rows);
  final List<Map<String, dynamic>> rows;
}

final class ReadinessPrefetchFailed extends ReadinessPrefetchOutcome {
  const ReadinessPrefetchFailed(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}

abstract final class RestoreReadinessPrefetch {
  /// configBox kill switch: set to `true`, the single-call restore reads
  /// readiness serially in step B again (the pre-B10 order).
  static const String killSwitchKey = 'disable_restore_overlap';

  /// True when [readConfig] says the overlap is switched off. A throwing read
  /// (box closed) keeps the overlap ON, like the other restore switches.
  static bool disabled(Object? Function(String key) readConfig) {
    try {
      return readConfig(killSwitchKey) == true;
    } catch (_) {
      return false;
    }
  }

  /// Starts [read] now and returns its wrapped outcome, or `null` when the
  /// switch is set (the caller then reads in step B, as before). A [read] that
  /// throws synchronously is a failed outcome, never an exception here.
  static Future<ReadinessPrefetchOutcome>? start({
    required Object? Function(String key) readConfig,
    required Future<List<Map<String, dynamic>>> Function() read,
  }) {
    if (disabled(readConfig)) return null;
    return Future<List<Map<String, dynamic>>>.sync(read).then<ReadinessPrefetchOutcome>(
      (rows) => ReadinessPrefetchOk(rows),
      onError: (Object e, StackTrace st) => ReadinessPrefetchFailed(e, st),
    );
  }

  /// Step B: hands the prefetched rows to the restore, or runs the restore's
  /// OWN read when there was no prefetch or it failed (a failure is reported
  /// first). A failed prefetch is never turned into "no rows": that would
  /// restore nothing while the cloud holds rows.
  static Future<void> consume(
    Future<ReadinessPrefetchOutcome>? prefetch, {
    required Future<void> Function(List<Map<String, dynamic>> rows) restoreWithRows,
    required Future<void> Function() restoreWithOwnRead,
    required Future<void> Function(Object error, StackTrace stackTrace) reportFailure,
  }) async {
    if (prefetch == null) return restoreWithOwnRead();
    final outcome = await prefetch;
    switch (outcome) {
      case ReadinessPrefetchOk(:final rows):
        return restoreWithRows(rows);
      case ReadinessPrefetchFailed(:final error, :final stackTrace):
        try {
          await reportFailure(error, stackTrace);
        } catch (_) {}
        return restoreWithOwnRead();
    }
  }
}
