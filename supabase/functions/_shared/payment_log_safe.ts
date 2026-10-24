// _shared/payment_log_safe.ts — what a payment-path log line may carry (OI-360, payment-hardening U0).
//
// The payment functions used to log whole objects: a PostgREST error (its `details` echoes the failing
// row, e.g. a Razorpay signature), a Razorpay error body, the payment notes, the raw request `plan`.
// Platform logs are kept and readable by every dashboard user, so a log line must carry only what an
// operator needs to act: a short error CODE, a type name, the SHAPE of the notes, and client-supplied
// text bounded and quoted so it can neither grow the line nor forge a second one.
//
// Pure: no imports, no I/O. Tests: payment_log_safe_test.ts.

/** A value that is already a code (`23505`, `bad_rpc_response`, an Error name) when it is a short plain token; else `no_code`. */
export function codeToken(v: unknown): string {
  return typeof v === "string" && /^[A-Za-z0-9_]{1,24}$/.test(v) ? v : "no_code";
}

/** The PostgREST / Postgres error code (`23505`, `PGRST116`) when it is a short plain token; else `no_code`. Never details, hint or message. */
export function pgErrorCode(err: unknown): string {
  if (err === null || typeof err !== "object") return "no_code";
  const code = (err as { code?: unknown }).code;
  return typeof code === "string" && /^[A-Za-z0-9_]{1,16}$/.test(code) ? code : "no_code";
}

/** An Error's `name` (never its message, which can carry a URL or a token); otherwise the value's type. */
export function errorName(err: unknown): string {
  if (err instanceof Error) return err.name;
  return err === null ? "null" : typeof err;
}

// JSON.stringify escapes the C0 controls (newline, ESC) but leaves DEL, the C1 range (NEL among them), the
// Unicode line and paragraph separators and the format characters (bidi overrides, zero-width marks) raw: a log
// viewer can break a line on the first ones and visually reorder or hide text with the others.
const UNESCAPED_LINE_BREAKS = /[\u007f-\u009f\u2028\u2029\p{Cf}]/gu;

/** A client- or upstream-supplied value as a quoted, escaped string of at most `n` characters of the value. */
export function boundedText(v: unknown, n = 40): string {
  return JSON.stringify(String(v).slice(0, n))
    .replace(UNESCAPED_LINE_BREAKS, (c) => "\\u" + c.charCodeAt(0).toString(16).padStart(4, "0"));
}

/**
 * A non-2xx Razorpay answer: the status, plus `error.code` and `error.reason` when each is a string (each
 * bounded). Never the description, the field names or anything else from the body.
 */
export function razorpayErrorSummary(status: unknown, bodyText: unknown): string {
  const s = typeof status === "number" && Number.isInteger(status) ? String(status) : "?";
  let parsed: unknown = null;
  try {
    parsed = JSON.parse(String(bodyText));
  } catch {
    return `status=${s}`;
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) return `status=${s}`;
  const e = (parsed as { error?: unknown }).error;
  if (e === null || typeof e !== "object" || Array.isArray(e)) return `status=${s}`;
  const parts = [`status=${s}`];
  const code = (e as { code?: unknown }).code;
  const reason = (e as { reason?: unknown }).reason;
  if (typeof code === "string") parts.push(`code=${boundedText(code.slice(0, 40))}`);
  if (typeof reason === "string") parts.push(`reason=${boundedText(reason.slice(0, 40))}`);
  return parts.join(" ");
}

/** The note keys an app order writes (create-razorpay-order) or Razorpay is known to add. */
const KNOWN_NOTE_KEYS = ["user_id", "plan", "promo_code", "stacks_after", "source", "billing_cycle"] as const;

/**
 * The SHAPE of Razorpay payment notes: which known keys are present, plus how many other keys. Never a value,
 * never an unknown key's name. Razorpay sends `[]` for empty notes; an array, null or a primitive is reported
 * by its type.
 */
export function notesShape(notes: unknown): string {
  if (notes === null) return "null";
  if (Array.isArray(notes)) return `array(${notes.length})`;
  if (typeof notes !== "object") return typeof notes;
  const keys = Object.keys(notes as Record<string, unknown>);
  const known = KNOWN_NOTE_KEYS.filter((k) => keys.includes(k));
  const other = keys.filter((k) => !(KNOWN_NOTE_KEYS as readonly string[]).includes(k)).length;
  return `keys=[${known.join(",")}] other=${other}`;
}
