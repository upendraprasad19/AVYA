/**
 * prediction_quota_switch — the ONE owner of the prediction-quota kill
 * switch's name and its "on" rule. Kept free of imports so founder-digest and
 * telegram-admin-bot can report the switch without bundling Gemini
 * (`prediction_handler.ts` imports `gemini.ts`).
 *
 * `DISABLE_PREDICTION_QUOTA=true` in the Edge Function secrets stops the
 * `prediction_daily` metering without a redeploy (see prediction_handler.ts).
 * Only the exact string "true" turns it on. Read on every call, never at
 * module load.
 */

export const PREDICTION_QUOTA_KILL_SWITCH_ENV = "DISABLE_PREDICTION_QUOTA";

/** Whether an env-var kill switch is on: exactly the string "true". */
export function envSwitchOn(name: string): boolean {
  return Deno.env.get(name) === "true";
}

export function predictionQuotaDisabled(): boolean {
  return envSwitchOn(PREDICTION_QUOTA_KILL_SWITCH_ENV);
}
