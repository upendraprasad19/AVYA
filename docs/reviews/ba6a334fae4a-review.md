---
reviewed_at: 2026-07-30T18:00:00+05:30
staged_against: ba6a334fae4a
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 3
verdict: accepted
---

# Code Review — ba6a334fae4a

## Hash lineage note (5th shift)

Hash history: `8d5a2f558995` → `19eeb84131e2` → `0d23d5d5811c` → `d7662eb41486`
→ `36920a65321a` → **`ba6a334fae4a` (this file)**. Full history for the first
four shifts is in `36920a65321a-review.md`.

This fifth shift: the second real commit attempt (at hash `36920a65321a`)
FAILED at `scripts/check_hive_map_field_drift.dart` (Gate 19, run via
`pre-commit.sh`'s `check_*.dart` loop) — a genuine, verified false positive.
`sync_service.dart`'s new `_stampProgressVersion` helper reads/writes
`p['streak_progress_version']` on the local `progress` map
(`box.get('progress')`, confirmed by direct read of the surrounding function
body at `sync_service.dart:2158-2170`). Gate 19's heuristic flags this as a
potential `exlog_*`/`wlog_*` field because `sync_service.dart` also contains
`startsWith('exlog_')`/`startsWith('wlog_')` patterns elsewhere (for
unrelated restore/sync code) — the exact same mis-attribution mechanism
already documented and suppressed for `current_streak_days` / `current_phase`
in the gate's own `_alwaysOk` allowlist, both also `user_progress`-map fields
in the same file. Added `streak_progress_version` to `_alwaysOk` with a
justification comment matching the established style; re-ran the gate
directly post-fix: `PASS (571 candidates, all in baseline)`. Also ran every
OTHER `check_*.dart` gate in the loop directly (mirroring the exact
allowlist-skip logic in `pre-commit.sh`) to surface any further failures in
one pass rather than one per costly full-suite re-run — only this gate's own
hash-matching gate itself was stale (expected, self-resolving with this
file). No test-covered logic changed: `_alwaysOk` is a data list with no
dedicated unit test asserting its exact contents (confirmed via grep — the
one hit in `test/` is an unrelated comment citation). Everything below is
identical in substance to `36920a65321a-review.md` and its ancestors.

Live post-apply verification performed before the ledger entry was written
(carried forward, still current): `has_function_privilege` confirms
`anon_can_exec=false`, `authenticated_can_exec=true` for both
`update_user_progress_snapshot` and `update_streak_progress` against
`dedsavbjuwgarrhphgnl`; `pg_proc` catalog confirms both signatures match
source exactly.

## Finding 1 — P3 — monotonic_field_guard (extends writer_reader_drift)
- **file:line:** `supabase/migrations/115_user_progress_snapshot_optimistic_lock.sql:194` (UPDATE branch)
- **claim:** `longest_gap_days` used plain `COALESCE` unlike its two sibling monotonic "record" columns (`total_workouts_done`, `deployments_complete`) in the same UPDATE statement, both of which use `GREATEST(COALESCE(p_x, x), x)`. `longest_gap_days` is the same lifetime-high-water-mark shape, read by `rank_service.dart` and `evaluate-rank-promotions` for disqualification gating.
- **verification:** `grep -n "longest_gap_days\|GREATEST"` confirmed the asymmetry. Reachability: no Hive writer populates `progress['longest_gap_days']` today (dormant, not live-exploitable — scored P3 not P1).
- **status:** accepted — fixed and live: migration's UPDATE branch now `GREATEST`-wraps `longest_gap_days` (mirrored in the SQL test harness's embedded copy, Case 21, 21/21 `ok` pre-apply; deployed function's identical text confirmed via `pg_proc` post-apply).

## Finding 2 — N/A (false_alarm) — writer_reader_drift
- **file:line:** `lib/core/services/sync/sync_restore_completeness.dart` vs `supabase/functions/restore-user-snapshot/index.ts:274`
- **claim (investigated, not confirmed):** Hive key `streak_freeze_used_dates` (singular) vs cloud column `streak_freezes_used_dates` (plural) looked like drift.
- **verification:** Singular is the established, pre-existing Hive-local key (untouched by this diff); plural is cloud-only. The new code follows the pre-existing convention consistently.
- **status:** false_alarm

## Finding 3 — N/A (false_alarm) — blast_radius_mismatch
- **file:line:** `supabase/functions/restore-user-snapshot/index.ts:274` (freezes projection, not yet redeployed) vs client read path
- **claim (investigated, not confirmed):** Client robustness to the OLD deployed EF response shape while the redeploy is pending.
- **verification:** Absent-key access degrades to `cloudVersion == null` → next sync hits a legitimate version-mismatch against the now-live cloud row and self-heals via the existing bounded-retry path. Pinned by `test/contracts/restore_user_snapshot_freezes_projection_parity_test.dart`.
- **status:** false_alarm — tracked as an explicit, tested, self-healing residual requiring its own redeploy (separate authorization).

## Lens: writer_reader_drift — otherwise clean
Every Hive write introduced/touched traced to its cloud reader and vice versa against the now-LIVE RPC signatures (confirmed via `pg_proc`, not just source). `mergeRpcParamsPreferringNonNull`'s contract pinned by 6 behavioral test cases.

## Lens: function_exception_swallow — clean
Every new `.rpc(` call and retry-refetch call verified inside the pre-existing outer try/catch or an intentional documented throw. RPCs are now live.

## Lens: blast_radius_mismatch — clean
Inline rollback present. 21/21 live-Postgres cases pre-apply; migration now APPLIED live with ACL independently re-verified post-apply. `backups/applied_migrations.json` correctly records the real apply per both enforcing gate scripts' exact requirements.

## Lens: secrets_in_tree — clean
No credential-shaped literals anywhere in the staged diff, including the ledger entry and all doc/gate-script edits made resolving this commit's pre-commit gate failures.

## Lens: unawaited_no_error_sink — clean
All 4 new `unawaited(` sites wrap `ErrorTelemetry.logEvent(...)`, which has its own internal error sink. Gate confirms neither new site is flagged.

## Founder triage notes
<leave blank, a human fills this in>
