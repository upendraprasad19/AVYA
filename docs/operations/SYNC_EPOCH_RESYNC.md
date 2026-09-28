# sync_epoch resync runbook

> Operator-driven repair lever for the day-swapper + sync-load batch
> (migration `148_sync_noop_suppress_completed_guard_sync_epoch.sql`,
> `docs/adr/0020-sync-sends-only-what-changed.md`). This is a **prod
> data write** — it needs a founder go before running, per CLAUDE.md §4.3
> ("live prod apply needs its own explicit go").

## What it does

Every device's local `SyncSkipIndex` (`lib/core/services/sync/sync_skip_index.dart`)
remembers the fingerprint of the last row it successfully pushed per sync
domain, and skips re-pushing an unchanged row. That is correct as long as the
cloud copy actually reflects what the device last pushed. If the cloud data
for a user is lost, wiped, or restored from an out-of-date backup, every
device's skip index is now WRONG — it believes rows are already correct in
the cloud that are, in fact, stale or missing there, and will never re-push
them on its own.

Bumping `user_progress.sync_epoch` tells every device to throw away its local
skip index and re-send everything once, the next time it launches.

## When to use it

- A `user_progress` row (or any table the sync layer writes) was restored
  from a backup that is older than what devices believe they've already
  pushed.
- A server-side incident wiped or corrupted rows in one of the 17
  sync-skip-covered tables (see the domain table in `docs/architecture/sync.md`)
  for one or more users.
- A migration or manual SQL fix changed rows out from under the skip index's
  assumptions (rare — prefer NOT bumping the epoch for an ordinary schema
  migration; this lever is for data-loss-shaped incidents, not schema
  changes).

Do **not** use it as a routine safety net or a "just in case" periodic job —
see `docs/adr/0020-sync-sends-only-what-changed.md`'s "Rejected" section for
why a periodic full resend was explicitly rejected as the safety net (it can
undo another device's day-swap that landed between resends).

## How

For one user:

```sql
update user_progress
   set sync_epoch = sync_epoch + 1
 where user_id = '<uuid>';
```

For every user (a fleet-wide incident):

```sql
update user_progress
   set sync_epoch = sync_epoch + 1;
```

Run via the Supabase MCP `apply_migration`/`execute_sql` tooling or the
Dashboard SQL editor against the **fitness-app project only**
(`dedsavbjuwgarrhphgnl` — confirm per root CLAUDE.md §2a before running
anything). This is a plain `UPDATE`, not a migration file — it does not get
its own numbered `.sql` file in `supabase/migrations/`.

## What happens next

On that user's (or every user's) next app launch, `SyncService.restoreLightweightAlways`
reads the new `sync_epoch` value (as part of its single `user_progress`
select), compares it against the device-local `configBox['sync_epoch_seen']`
(`SyncService.kSyncEpochSeenKey`), and — because the cloud epoch is now
strictly greater — calls `SyncSkipIndex.clearAll`, which deletes every
domain's stored fingerprint index. The device only advances its own
`sync_epoch_seen` once `ClearAllResult.allSucceeded` is true (diagnose
`a9d3f6`) — a partial clear leaves the seen-epoch untouched, so the very next
launch retries the whole clear rather than silently treating the repair as
done.

With every domain's skip index cleared, the next sync pass for that domain
sees no stored fingerprint for any row, so it pushes every row once — the
skip mechanism behaves exactly as if the device had never synced before, for
one pass, then resumes normal skip-on-match behaviour.

## Cost

One full re-send pass per affected device, once, on its next launch after
the bump — not per subsequent launch. For a single-user incident this is
cheap. For a fleet-wide bump (every user), expect every active device to
push its full current Hive state once in the following hours/days as users
open the app — size this against known total active-device count before
bumping for everyone, not just for the affected subset.

## Verifying it worked

- `select sync_epoch from user_progress where user_id = '<uuid>';` — confirm
  the bump landed.
- After the affected user's next app launch, `configBox['sync_epoch_seen']`
  on that device (not directly queryable from the server) should equal the
  new epoch — check via the app's own debug tooling, or infer it from a
  subsequent full resync of that domain's rows actually reaching the cloud.
- A repeated bump before the previous one has been "seen" by a device is
  harmless — `sync_epoch_seen` only needs to be strictly less than the
  current cloud value to trigger a clear, and a device that missed one bump
  still clears on the next higher value it sees.
