// supabase/functions/_shared/gemini_failure_alert.ts
/**
 * Reports a TERMINAL Gemini failure (every model in ai-proxy's attempt list
 * exhausted) into the existing `public.alerts` table, reusing the
 * `trg_dispatch_critical_alert_notify` trigger (migration 133) that already
 * pushes a `severity='critical'` insert to the founder's Telegram — no new
 * Telegram wiring. Client-facing error text is unchanged; this is
 * additive, admin-only visibility (obs 6, 2026-09-20 brainstorm).
 *
 * Never throws — a failure here must never break the caller's actual
 * error response to the client.
 */

// deno-lint-ignore no-explicit-any
type SupabaseLike = any;

const DEDUP_WINDOW_MINUTES = 30;

function classify(status: number | null): string {
  if (status === 429) {
    return "Check Gemini quota/billing on the Google Cloud project owning GEMINI_API_KEY — a recharge doesn't always attach to the right project or raise RPM limits.";
  }
  if (status === 401 || status === 403) {
    return "Check the GEMINI_API_KEY secret is valid.";
  }
  if (status !== null && status >= 500) {
    return "Likely a transient Gemini-side outage — no action needed unless it persists.";
  }
  return "Unclassified Gemini failure — check function_logs for the full response.";
}

export async function reportGeminiExhaustion(
  client: SupabaseLike,
  source: string,
  lastError: { status: number | null; message: string } | null,
  endpoint?: string,
  // Hermes L34 #4 (2026-09-21): tool-loop.ts's chat path can hit this on the
  // SUMMARIZATION round after an earlier round already queued a real write
  // (e.g. logSet) — the user still got their logged action via the FC2
  // queued-intent acknowledgment, just no chat reply. Without this flag the
  // alert reads identically to a total loss, which is not true and would
  // misdirect triage. Additive only — never changes whether the alert fires
  // or its severity; the underlying Gemini failure is equally real either way.
  extra?: Record<string, unknown>,
): Promise<void> {
  // §4.6 feature-flag protocol (platform-tier path, B-pass finding
  // 2026-09-20): this function's own alerts-table write is new and
  // untested against production alert volume — a secret toggle lets the
  // founder silence it without a redeploy if it turns out to be noisy,
  // while the old (silent) behavior is preserved verbatim when set.
  if (Deno.env.get("DISABLE_GEMINI_FAILURE_ALERT") === "true") return;
  try {
    const status = lastError?.status ?? null;
    const message = lastError?.message ?? "unknown failure (no lastError captured)";
    const suggestedAction = classify(status);
    // `endpoint` names WHICH ai-proxy request type failed (food_text_analysis
    // / scan_meal / cart_auditor) — B-pass finding, 2026-09-20: without it,
    // three otherwise-identical alerts (same source, same dedup key) were
    // indistinguishable except by timestamp, defeating the feature's own
    // stated purpose of fast diagnosis. `source` stays the constant dedup
    // key so the 30-minute window still spans all three endpoints together.
    const summary = `${endpoint ?? source}: Gemini exhausted all attempts — ${
      status !== null ? `HTTP ${status}` : "no HTTP status"
    }: ${message}`.slice(0, 500);

    const dedupWindowStart = new Date(
      Date.now() - DEDUP_WINDOW_MINUTES * 60 * 1000,
    ).toISOString();
    const { data: recent, error: recentErr } = await client
      .from("alerts")
      .select("id")
      .eq("source", source)
      .eq("severity", "critical")
      .is("resolved_at", null)
      .gte("detected_at", dedupWindowStart)
      .limit(1);
    if (recentErr) {
      console.error(`[gemini_failure_alert] dedup check failed for ${source}:`, recentErr);
    }
    const severity = !recentErr && recent && recent.length > 0 ? "warn" : "critical";

    const { error: insertErr } = await client.from("alerts").insert({
      source,
      severity,
      summary,
      context_json: { status, message, endpoint: endpoint ?? null, ...extra },
      suggested_action: suggestedAction,
    });
    if (insertErr) {
      console.error(`[gemini_failure_alert] alerts insert failed for ${source}:`, insertErr);
    }
  } catch (err) {
    console.error(`[gemini_failure_alert] threw for ${source}:`, err);
  }
}
