// supabase/functions/_shared/uuid_v5.ts
//
// RFC 4122 UUID version 5 (SHA-1, name-based) over `crypto.subtle`, so no npm
// dependency and no import-map change (L1b plan B3, R3TA).
//
// Why this exists: the Flutter sync derives a workout session's cloud
// `workout_log_exercises.workout_log_id` as `Uuid().v5(SYNC_NAMESPACE,
// 'workout_<IST date>')` (`SyncService._deterministicId`,
// lib/core/services/sync_service.dart:663; `workoutLogIdForDate`). That id is
// the ONE field of a summary row that carries the workout's DAY — `completed_at`
// is the write time (an edited old log carries a recent one). Server readers
// therefore recompute the same ids to select a day window and to attribute a
// row to its day (`_shared/exercise_day.ts`).
//
// Parity is pinned by `uuid_v5_test.ts`: the RFC's own test vector, plus a real
// live `workout_log_id` and the date it was derived from.

/** `SyncService._syncNamespace` (lib/core/services/sync_service.dart:661). */
export const SYNC_NAMESPACE = "6ba7b810-9dad-11d1-80b4-00c04fd430c8";

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.replace(/-/g, "");
  if (!/^[0-9a-fA-F]{32}$/.test(clean)) {
    throw new Error(`uuid_v5: not a UUID: ${hex}`);
  }
  const out = new Uint8Array(16);
  for (let i = 0; i < 16; i++) {
    out[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function bytesToUuid(b: Uint8Array): string {
  const h = Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20, 32)}`;
}

/** UUID v5 of `name` (UTF-8) in `namespace`, lowercase hyphenated. */
export async function uuidV5(
  name: string,
  namespace: string = SYNC_NAMESPACE,
): Promise<string> {
  const ns = hexToBytes(namespace);
  const nameBytes = new TextEncoder().encode(name);
  const data = new Uint8Array(ns.length + nameBytes.length);
  data.set(ns, 0);
  data.set(nameBytes, ns.length);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-1", data));
  const b = digest.slice(0, 16);
  b[6] = (b[6] & 0x0f) | 0x50; // version 5
  b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
  return bytesToUuid(b);
}

/** The cloud `workout_log_id` of an IST date ('YYYY-MM-DD'), as the app writes it. */
export function workoutLogIdForDate(istDate: string): Promise<string> {
  return uuidV5(`workout_${istDate}`);
}
