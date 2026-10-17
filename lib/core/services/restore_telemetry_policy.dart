/// closes-diagnose e5b2a9 / closes-oi OI-151 — which successful restore/sync ops
/// earn a `client_errors` row.
///
/// `restore_op_done` was written for EVERY successful op, so 57% of
/// `client_errors` (4,043 of 7,047 rows, 2026-10-01) was "this worked in 80 ms".
/// The row exists to answer "which op is the long pole" (4f8e2d), which only
/// slow ops can. `restore_started` / `restore_completed` bookends are unchanged
/// and still bracket every restore; failures are unchanged.
library;

const Duration kRestoreOpDoneSlowThreshold = Duration(seconds: 2);

bool shouldLogRestoreOpDone(Duration elapsed, {required bool alwaysLog}) =>
    alwaysLog || elapsed >= kRestoreOpDoneSlowThreshold;
