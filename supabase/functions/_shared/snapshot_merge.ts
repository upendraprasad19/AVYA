// supabase/functions/_shared/snapshot_merge.ts
//
// user_daily_snapshots.snapshot_json is written by TWO kinds of callers:
// the client (`daily-snapshot`, a wholesale rebuild from Hive on every app
// sync) and several server-side crons that each own ONE key inside the same
// blob (morning-alert's `morning_alert`, rolling-context's semantic-retrieval
// fields, future-prediction's `future_prediction`, beat-my-coach's fields).
// The cron writers already read-modify-write correctly. The client writer
// did not — it replaced the whole row, so any cron-owned key written earlier
// that day was silently destroyed the next time the client pushed (diagnose
// d8a2f6, recurrence of e4a1b7/OI-98 on a different key).
//
// This merge exists to make the client writer safe: keys the incoming
// payload never mentions survive from the existing row.

/**
 * Merges an incoming client-submitted snapshot over an existing row's
 * snapshot_json. `existing` is spread first so `incoming` wins on any key
 * both sides carry — the client is authoritative for everything it knows
 * about. A key `incoming` never mentions (a server-cron-owned key like
 * `morning_alert`) survives untouched from `existing`.
 */
export function mergeSnapshotJson(
  existing: Record<string, unknown> | null | undefined,
  incoming: Record<string, unknown>,
): Record<string, unknown> {
  return { ...(existing ?? {}), ...incoming };
}
