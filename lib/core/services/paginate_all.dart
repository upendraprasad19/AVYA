// lib/core/services/paginate_all.dart
//
// Free-tier "Hold the Line" durability #4 — a pure, testable paginator.
//
// `_restoreScheduledWorkouts` used a single `.range(0, 999)`, which (ascending)
// silently dropped the CURRENT phase from the status merge once a long-term
// holder accumulated > 1000 daily rows (~2.7 yr). This helper pages through the
// full result set. Extracted so the loop is unit-testable WITHOUT a Supabase
// network mock (the `preFetched` inject the restore tests use bypasses the
// fetch path entirely). Test: test/contracts/paginate_all_test.dart.

/// Repeatedly call [fetchPage(offset, pageSize)] until a page shorter than
/// [pageSize] is returned, concatenating every page. A full-length page implies
/// there may be more; a short (or empty) page is the last one.
Future<List<T>> paginateAll<T>({
  required Future<List<T>> Function(int offset, int pageSize) fetchPage,
  int pageSize = 1000,
}) async {
  final out = <T>[];
  var offset = 0;
  while (true) {
    final page = await fetchPage(offset, pageSize);
    out.addAll(page);
    if (page.length < pageSize) break;
    offset += pageSize;
  }
  return out;
}
