// supabase/functions/_shared/row_model_label.ts
/**
 * The `ai_coach_interactions.model_used` value for a resolved chat turn.
 *
 * Pure so it is unit-testable (`ai-proxy/index.ts` calls `serve()` at module
 * scope and cannot be imported by a test).
 *
 * - A turn whose reply is the hardcoded apology (`hadHardFailure`) is stamped
 *   with the failure SENTINEL, never the real model label. Stamping the real
 *   label let `chat_dedup.ts dedupDecision` replay the apology as a normal 200
 *   reply and let it be restored as history on a cold device (the a1c6b9
 *   history-poisoning class). The sentinel makes dedup return `replay_failure`
 *   and `sync_coach.dart` already excludes `failed` rows on restore.
 * - Otherwise the label comes from the slug of the model that ACTUALLY produced
 *   the last round (`labelForModel`), not from a tier constant: every tier shares
 *   one slug, so `usedFallback ? LITE : FLASH` can no longer tell them apart.
 */
import { labelForModel, MODEL_FLASH } from "./gemini.ts";

export function rowModelLabel(
  hadHardFailure: boolean,
  modelUsed: string | null | undefined,
  failureSentinel: string,
): string {
  if (hadHardFailure) return failureSentinel;
  return labelForModel(modelUsed ?? MODEL_FLASH);
}
