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
): Promise<void> {
  try {
    const status = lastError?.status ?? null;
    const message = lastError?.message ?? "unknown failure (no lastError captured)";
    const suggestedAction = classify(status);
    const summary = `${source}: Gemini exhausted all attempts — ${
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
      context_json: { status, message },
      suggested_action: suggestedAction,
    });
    if (insertErr) {
      console.error(`[gemini_failure_alert] alerts insert failed for ${source}:`, insertErr);
    }
  } catch (err) {
    console.error(`[gemini_failure_alert] threw for ${source}:`, err);
  }
}
