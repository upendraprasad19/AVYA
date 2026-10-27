// clean-orphan-media/logic.ts — the testable core of the daily chat-media sweep.
//
// `index.ts` is a thin `serve()` shell that reads env at import time, so it
// cannot be imported by a test. Everything that DECIDES whether an object is
// removed lives here, behind injected dependencies (the consume-day-swap
// pattern).
//
// THE RULE (OI-321, bug class 2.49): an object is removed ONLY when the
// subscription read SUCCEEDED and found no active unexpired row. A failed or
// unreadable read, a thrown rejection, a value outside the union, a malformed
// candidate: each leaves the object where it is, to be retried at the next
// daily run. Retaining is the safe direction; a wrong delete is irreversible
// (a PRO user's chat photo — test/contracts/coach_media_repository_test.dart).
//
// Not `isProUser`: that helper answers `false` on a read error, which is the
// right default for choosing notification copy and the wrong one before a
// delete. See `readProState` in the shared subscription module.

import { type ProState, readProState } from '../_shared/subscription.ts';

/// The one bucket this sweep may touch. `coach-media` is long-term consented
/// retention (migration 070) and must never appear here (diagnose c1ea30).
const CHAT_MEDIA_BUCKET = 'chat-media';

// deno-lint-ignore no-explicit-any
type ClientLike = any;

/// The slice of the Storage client used here.
export interface StorageLike {
  from(bucket: string): {
    remove(paths: string[]): PromiseLike<{ data: unknown; error: unknown }>;
  };
}

export interface OrphanCandidate {
  user_id: string;
  path: string;
}

export interface RemoveOutcome {
  /// null on success.
  error: unknown;
  /// How many objects Storage reports it removed; null when it did not say.
  removed: number | null;
}

export interface SweepDeps {
  readProState: (userId: string) => Promise<ProState>;
  removeObject: (path: string) => Promise<RemoveOutcome>;
}

export interface SweepResult {
  scanned: number;
  deleted: number;
  skippedPro: number;
  skippedUnknown: number;
  failed: number;
  alreadyGone: number;
  /// The first distinct failure code seen (never a user id or a path).
  firstFailure: string | null;
}

/// Removes one object. This is the ONLY `.remove(` in this function folder.
/// A THROWN storage call (transport reset) becomes `{ error }` so one bad
/// object cannot abort the whole run and block every object after it.
export async function removeFromBucket(
  storage: StorageLike,
  bucket: string,
  path: string,
): Promise<RemoveOutcome> {
  try {
    const { data, error } = await storage.from(bucket).remove([path]);
    if (error !== null && error !== undefined) return { error, removed: null };
    return { error: null, removed: Array.isArray(data) ? data.length : null };
  } catch (err) {
    return { error: err, removed: null };
  }
}

function isValidCandidate(c: OrphanCandidate): boolean {
  // The PRO check keys on user_id and the removal on path. The RPC derives the
  // first from the second; requiring them to agree keeps schema or RPC drift
  // from separating the two.
  return typeof c?.user_id === 'string' && c.user_id.length > 0 &&
    typeof c.path === 'string' && c.path.length > 0 &&
    c.path.startsWith(c.user_id + '/');
}

/// A short code for the run summary. A Storage failure is a storage-js
/// `StorageApiError`, which carries a numeric `status` and no `code`; a PostgREST
/// failure carries `code`. Only a plain identifier-shaped value is kept, so a uuid
/// or a path can never reach `cron_call_log`.
function failureCode(error: unknown, fallback: string): string {
  const e = error as { code?: unknown; statusCode?: unknown; status?: unknown } | null;
  for (const v of [e?.code, e?.statusCode, e?.status]) {
    if (typeof v === 'string' || typeof v === 'number') {
      const text = String(v);
      if (/^[A-Za-z0-9_]{1,24}$/.test(text)) return text;
    }
  }
  return fallback;
}

export async function sweepOrphans(
  candidates: readonly OrphanCandidate[],
  deps: SweepDeps,
): Promise<SweepResult> {
  const r: SweepResult = {
    scanned: 0,
    deleted: 0,
    skippedPro: 0,
    skippedUnknown: 0,
    failed: 0,
    alreadyGone: 0,
    firstFailure: null,
  };
  const note = (code: string) => {
    if (r.firstFailure === null) r.firstFailure = code;
  };

  for (const c of candidates) {
    r.scanned++;

    if (!isValidCandidate(c)) {
      r.skippedUnknown++;
      note('invalid_candidate');
      continue;
    }

    // Re-checked per candidate, at delete time: the user may have upgraded
    // since the scan. No per-run cache, on purpose.
    let state: unknown;
    try {
      state = await deps.readProState(c.user_id);
    } catch (_err) {
      state = 'unknown';
    }

    if (state === 'pro') {
      r.skippedPro++;
      continue;
    }
    // Anything that is not exactly "free" — "unknown", or a value outside the
    // union — leaves the object alone.
    if (state !== 'free') {
      r.skippedUnknown++;
      note('read_unknown');
      continue;
    }

    let out: RemoveOutcome;
    try {
      out = await deps.removeObject(c.path);
    } catch (err) {
      out = { error: err ?? 'remove_threw', removed: null };
    }
    if (out.error !== null && out.error !== undefined) {
      r.failed++;
      note(failureCode(out.error, 'remove_error'));
      continue;
    }
    if (out.removed === 0) {
      // The object was already gone between the scan and the removal.
      r.alreadyGone++;
      continue;
    }
    r.deleted++;
  }

  return r;
}

/// The production composition: the real PRO read and the real Storage removal,
/// pinned to the chat-media bucket.
export function runSweep(
  client: ClientLike,
  candidates: readonly OrphanCandidate[],
): Promise<SweepResult> {
  return sweepOrphans(candidates, {
    readProState: (userId) => readProState(client, userId),
    removeObject: (path) => removeFromBucket(client.storage, CHAT_MEDIA_BUCKET, path),
  });
}

/// Text for `cron_call_log.error_summary`. Undefined on a clean run. Counts and
/// one code only: no user id, no path. A run that removed nothing because every
/// object it tried was already gone says so too (`already_gone=N`): that is the
/// "success while doing nothing" shape.
export function runErrorSummary(r: SweepResult): string | undefined {
  const nothingRemoved = r.deleted === 0 && r.alreadyGone > 0;
  if (r.failed === 0 && r.skippedUnknown === 0 && !nothingRemoved) return undefined;
  const base = `skipped_unknown=${r.skippedUnknown} failed=${r.failed} first=${r.firstFailure ?? 'none'}`;
  return nothingRemoved ? `${base} already_gone=${r.alreadyGone}` : base;
}

/// The least number of undecided candidates (unreadable subscription or failed
/// removal) that can make a run count as a systemic failure.
export const SYSTEMIC_MIN_UNDECIDED = 5;

/// True when the run could not do its job: at least SYSTEMIC_MIN_UNDECIDED
/// candidates were left because the subscription was unreadable or the removal
/// failed, AND those are a MAJORITY of what was scanned. Then the cron row ends
/// `failed` (HTTP 500), which pages through `alert_cron_failures`. Without this a
/// systematic outage (a revoked grant on `subscriptions`, a rotated service key, a
/// PostgREST outage at 03:00) would end `success` with zero deletions every day and
/// the free tier's 30-day TTL would silently stop being enforced.
/// It does not page for one transient blip (1 of N) or for one permanently
/// unremovable object (it needs five, and a majority). Same ratio idea as
/// `weekly-recalc` (`errors > processed` => `failed`).
export function isSystematicFailure(r: SweepResult): boolean {
  const undecided = r.skippedUnknown + r.failed;
  return undecided >= SYSTEMIC_MIN_UNDECIDED && undecided * 2 > r.scanned;
}
