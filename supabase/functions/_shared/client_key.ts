// OI-503 (plan docs/plans/2026-11-13-coach-chat-time-dup.md, section 4 C2;
// migration 178, diagnose d4a7c9).
//
// The phone sends its Hive key of a coach chat turn (`coach_<ms>`, minted by
// mintCoachKey before the AI call) as `client_key`. ai-proxy and ai-media-proxy
// store it on the ai_coach_interactions row, so the restore can write the cloud
// row back AT that key and one turn stays one local row.
//
// The value is CLIENT-CONTROLLED. Anything that is not exactly `coach_` plus 10
// to 16 digits is DROPPED (null) and the insert goes ahead unkeyed: the column's
// CHECK (ai_coach_interactions_client_key_format) uses the same pattern, so a
// bad key can never fail an insert and never break chat. Never throws, never
// logged.
export const CLIENT_KEY_PATTERN = /^coach_[0-9]{10,16}$/;

export function sanitizeClientKey(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  return CLIENT_KEY_PATTERN.test(raw) ? raw : null;
}
