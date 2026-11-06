// supabase/functions/_shared/ai_limits.ts
/**
 * The ONE TypeScript home of the daily AI caps (Part B, gemini3-limits-caching).
 *
 * ENFORCEMENT is NOT here. The Postgres triggers on `ai_coach_interactions`
 * (migration 153: chat 7/20, vision 4/20) and the `consume_quota` call sites
 * (media caps, food text) enforce. These constants exist so the 429 bodies, the
 * Captain manual and the founder digest read ONE number instead of each typing
 * its own, and so a parity test can tie them to the migration literals
 * (`test/contracts/ai_message_limit_parity_test.dart`, via `readProFreeCap`) and to the
 * Flutter `AppConstants` (`freeAiMessagesPerDay`, `proAiMessagesPerDay`).
 *
 * Changing a number is a THREE-place edit by design: a new migration (enforcement),
 * this file (display), `AppConstants` (client). The parity tests fail until all
 * agree. PRO chat 20 -> 25 is a later founder decision once usage data exists.
 */

/** Chat messages per IST day. Enforced by `enforce_chat_app_daily_limit`. */
export const FREE_CHAT_DAILY_CAP = 7;
export const PRO_CHAT_DAILY_CAP = 20;

/**
 * Scan-meal + cart-auditor COMBINED per IST day (one shared `vision_analysis`
 * budget). Enforced by `enforce_vision_analysis_daily_limit`.
 */
export const FREE_VISION_DAILY_CAP = 4;
export const PRO_VISION_DAILY_CAP = 20;

/** PRO coach-chat media reads per IST day (ai-media-proxy `consume_quota`). */
export const PRO_IMAGE_DAILY_CAP = 10;
export const PRO_VIDEO_DAILY_CAP = 5;

/** Refunds a user can receive per IST day (`refund_quota`'s `refund_budget`). */
export const REFUND_DAILY_BUDGET = 3;

export type AiTier = "free" | "pro";

/** The chat cap for a tier. */
export function chatCapFor(tier: AiTier): number {
  return tier === "pro" ? PRO_CHAT_DAILY_CAP : FREE_CHAT_DAILY_CAP;
}
