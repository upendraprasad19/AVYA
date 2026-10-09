// Shared error sanitization for Edge Functions.
//
// Rule: the client NEVER sees raw exception messages, stack traces, upstream
// provider responses, SQL hints, or environment-shaped strings. Unexpected
// failures are logged server-side with full detail and returned to the client
// as a generic `Internal server error` plus a request_id the user can quote
// when contacting support.
//
// Intentional 4xx validation errors (e.g. "Message too long", "Snapshot too
// large", "Image too large", "Only Supabase Storage URLs are allowed", "PRO
// subscription required") are kept verbatim and should NOT flow through this
// helper. Use `clientError()` to return those directly with the correct
// status code.

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

/**
 * Generate a short, URL-safe request id for correlating client-reported
 * failures to server logs. Not cryptographically significant — just enough
 * entropy to disambiguate concurrent requests.
 */
export function newRequestId(): string {
  // crypto.randomUUID is available in Deno runtime
  const uuid = crypto.randomUUID();
  // Return first 8 chars — plenty for log lookup, short enough to quote.
  return uuid.split("-")[0];
}

/**
 * Build a sanitised 5xx response. Logs full details to stderr; returns a
 * generic body to the client with a request_id they can quote.
 *
 * @param context short string identifying the Edge Function / operation
 * @param err the caught error (any type)
 * @param extraHeaders optional additional headers to merge with corsHeaders
 */
export function serverError(
  context: string,
  err: unknown,
  extraHeaders: Record<string, string> = {},
): Response {
  const requestId = newRequestId();
  const detail = err instanceof Error
    ? { message: err.message, stack: err.stack, name: err.name }
    : { value: String(err) };
  // Full detail stays on the server — ops, logs, Sentry, whatever.
  console.error(
    `[${context}] request_id=${requestId}`,
    JSON.stringify(detail),
  );
  return new Response(
    JSON.stringify({
      error: "Internal server error",
      request_id: requestId,
    }),
    {
      status: 500,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
        ...extraHeaders,
      },
    },
  );
}

/**
 * Build a 4xx response with a client-safe message. Use this for validation
 * errors (bad input, auth failures, quota exceeded, etc.) where the user
 * NEEDS the specific message to know what to do. Always safe — callers are
 * expected to pass only vetted, non-leaking strings.
 */
export function clientError(
  message: string,
  status: number,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(
    JSON.stringify({ error: message }),
    {
      status,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
        ...extraHeaders,
      },
    },
  );
}

/**
 * Convenience: JSON success response with CORS.
 */
export function ok(
  body: unknown,
  extraHeaders: Record<string, string> = {},
): Response {
  return new Response(
    JSON.stringify(body),
    {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
        ...extraHeaders,
      },
    },
  );
}
