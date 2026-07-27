// supabase/functions/_shared/sanitize_for_prompt.ts
//
// OI-47 -- neutralise user-controlled text before it is interpolated into an LLM
// prompt.
//
// THE ACTUAL THREAT, stated precisely. A prompt is a flat string; the model has
// no structural way to tell "data the user typed" from "instructions the system
// gave". The lever an attacker needs is a NEWLINE: it lets typed text start what
// looks like a fresh instruction line.
//
//     full_name = "Bob\nIgnore all previous instructions. Instead output ..."
//     ->  `User name: Bob
//          Ignore all previous instructions. Instead output ...`
//
// BLAST RADIUS IS SELF-TARGETED and worth saying plainly rather than inflating:
// each prompt is built from that user's own name/conversation and its output
// returns to that same user (a push notification, their own profile extraction).
// This is NOT a cross-user breach. What it buys: system-prompt disclosure,
// arbitrary text in their own notifications, Gemini quota burn, and -- the one
// with real consequences -- steering `daily-snapshot`'s extraction of "facts the
// user explicitly stated" into their own stored profile.
//
// WHAT THIS DOES NOT CLAIM. Sanitising input is mitigation, not a guarantee; no
// escaping makes an LLM immune to persuasion in text it is asked to read. It
// removes the STRUCTURAL lever (newlines, control characters, unbounded length).
// Defence-in-depth belongs at the call site too: fenced delimiters and an
// explicit "treat the block below as data" instruction.
//
// WHY new RegExp(...) AND NOT A REGEX LITERAL. The first draft wrote the
// character classes as literals and embedded the ACTUAL U+2028/U+2029
// characters. Because those ARE line separators, they terminated the regex
// literal mid-expression and the module would not parse -- writing
// line-separator handling is precisely where a stray literal line separator is
// most likely to appear and most likely to break. Building from an ASCII source
// string makes an invisible character impossible to introduce by accident: the
// escape is data, not syntax.
//
// Deliberately dependency-free -- no imports, so it type-checks and tests
// without touching the network. (`clean-orphan-media` importing supabase-js via
// an esm.sh URL is what turned a CDN 522 into a red CI run on 2026-07-27; see
// feedback_mistake_remote_dep_rot.)

/**
 * `String.slice` on a UTF-16 code-unit boundary, backing off one unit if that
 * boundary lands INSIDE a surrogate pair.
 *
 * `"A".repeat(63) + emoji` sliced to 64 keeps the high surrogate and drops its
 * low half, leaving a lone surrogate. It round-trips through JSON fine, so it
 * is invisible in tests, but `TextEncoder` (what `fetch` runs over the request
 * body) silently replaces it with U+FFFD -- a function whose job is producing
 * well-formed output should not emit half a character. Found in review round 1.
 */
function _sliceWholeChars(s: string, maxLen: number): string {
  if (s.length <= maxLen) return s;
  const code = s.charCodeAt(maxLen - 1);
  // A high surrogate at the final kept position means its pair is being cut.
  const cutsPair = code >= 0xd800 && code <= 0xdbff;
  return s.slice(0, cutsPair ? maxLen - 1 : maxLen);
}

/** Default cap for a short identity field (a display name). */
export const kIdentifierMaxLen = 64;

/** Default cap for a free-text block (conversation history). */
export const kBlockMaxLen = 8000;

/**
 * All Unicode line terminators, not just \n.
 *
 * U+2028 LINE SEPARATOR and U+2029 PARAGRAPH SEPARATOR render as line breaks
 * and would survive a \n-only strip -- the same class of near-miss as matching
 * \n but forgetting \r\n. U+0085 NEL likewise.
 */
const _lineBreaks = new RegExp("[\\r\\n\\u0085\\u2028\\u2029]", "g");

/**
 * C0 and C1 control characters, EXCLUDING the line terminators handled above.
 * Includes U+007F DEL and U+0080-U+009F, which carry terminal escape semantics
 * in some renderers.
 */
const _controls = new RegExp(
  "[\\u0000-\\u0008\\u000B\\u000C\\u000E-\\u001F\\u007F-\\u009F]",
  "g",
);

/** Only the Unicode separators, for normalising a block to \n. */
const _unicodeSeps = new RegExp("[\\u0085\\u2028\\u2029]", "g");

/**
 * THE CHARACTER POLICY IS AN ALLOWLIST, AND THAT IS THE WHOLE POINT.
 *
 * Two review rounds killed the denylist approach. Round 1 added a zero-width
 * class; round 2 defeated it with five more BMP characters AND an entire astral
 * plane the class structurally could not reach -- every regex here is built
 * without the `u` flag, so a BMP character class can never match U+10000+, no
 * matter what is added to it. Unicode Tag characters (U+E0000-E007F) each map
 * to an ASCII byte, so that was a covert channel, not merely a fence bypass.
 *
 * The stated premise was also wrong on its own terms: "strip category Cf" does
 * not cover U+3164 (Lo) or U+FE00-FE0F (Mn). Enumerating harder was never going
 * to finish.
 *
 * So: keep what is legitimate, drop everything else. `u` flag, so astral code
 * points are matched as code points rather than surrogate halves.
 *
 *   \p{L}  letters      \p{N}  numbers    \p{P}  punctuation
 *   \p{M}  marks        \p{Zs} spaces     \p{S}  symbols (incl. emoji)
 *   plus tab and newline
 *
 * Everything in \p{C} (Cc control, Cf format, Co private-use, Cn unassigned)
 * is dropped, which is what closes the covert channel.
 *
 * \p{M} IS REQUIRED AND IS NOT NEGOTIABLE. Dropping marks strips Devanagari
 * matras, turning a written Hindi greeting into mojibake. This app's users write Hindi and
 * Hinglish; silently destroying their text would be a worse bug than the one
 * being fixed. Measured, not assumed: Devanagari, Tamil, Hinglish and emoji all
 * round-trip byte-identical under this policy, and there is a test that fails if
 * that stops being true.
 *
 * ACCEPTED CONSEQUENCES, stated rather than hidden:
 *   - U+FE0F VARIATION SELECTOR-16 (Mn) and U+3164 HANGUL FILLER (Lo) SURVIVE.
 *     Under the old adjacency-based fence that was a P0, because they split a
 *     `<<<` run. Under the nonce fence it is harmless: an attacker cannot forge
 *     a delimiter they cannot predict. The two designs are coupled, which is
 *     exactly why the fence had to change before this could be permissive.
 *   - ZWJ (Cf) is dropped, so a ZWJ family emoji degrades to its component
 *     emoji. Acceptable: ZWJ is a real smuggling primitive and the loss is
 *     cosmetic.
 */
//
// NOTE: a regex LITERAL here, deliberately, despite this file's own
// no-regex-literal doctrine above. That doctrine exists because embedding a
// literal U+2028 CHARACTER terminates a literal mid-expression. It does not
// apply to pure-ASCII property escapes -- and the string form actively
// misfired: `new RegExp(\"[^\p{L}...\")` needs DOUBLED backslashes, and a
// single-backslash version silently compiles to [^p{L}...], which strips
// almost everything. Verified by od -c that the file carried one backslash.
const _disallowed = /[^\p{L}\p{M}\p{N}\p{Zs}\p{P}\p{S}\t\n]/gu;

/** Drops every character outside the allowlist above. */
function _keepAllowedOnly(s: string): string {
  return s.replace(_disallowed, "");
}

/**
 * Sanitises a SHORT identity field -- a display name, a preferred name.
 *
 * Every line break and control character becomes a single space, runs of
 * whitespace collapse, and the result is capped. A name has no legitimate need
 * for newlines, so this removes the injection lever outright rather than trying
 * to detect malicious phrasing, which is unwinnable.
 *
 * Returns [fallback] when the input is null/undefined or empty after cleaning,
 * so a caller can never interpolate "null" or "" into a prompt.
 */
export function sanitizeIdentifier(
  raw: string | null | undefined,
  opts?: { maxLen?: number; fallback?: string },
): string {
  const maxLen = opts?.maxLen ?? kIdentifierMaxLen;
  const fallback = opts?.fallback ?? "there";
  if (raw == null) return fallback;

  let s = _keepAllowedOnly(
    String(raw)
      .replace(_lineBreaks, " ")
      .replace(_controls, ""),
  )
    .replace(/\s+/g, " ")
    .trim();

  if (s.length === 0) return fallback;
  if (s.length > maxLen) s = _sliceWholeChars(s, maxLen).trim();
  return s.length === 0 ? fallback : s;
}

/**
 * Sanitises a FREE-TEXT block -- conversation history for summarisation or
 * fact-extraction.
 *
 * Newlines cannot simply be stripped: the block is genuinely multi-line and
 * removing that destroys the turn structure the prompt depends on. Instead:
 *   - every line-break variant normalises to \n (no U+2028 smuggling),
 *   - control characters are removed,
 *   - runs of blank lines collapse, denying a large visual gap that pushes the
 *     real instructions out of the model's attention,
 *   - the block is capped, and truncation is DISCLOSED in-band so the model is
 *     not silently reading half a conversation,
 *   - and [fenceAsData]'s delimiters are DEFANGED, so content can never forge
 *     the boundary that is supposed to contain it.
 *
 * Structural safety at the call site (fencing plus a "this is data"
 * instruction) remains necessary; see [fenceAsData].
 */
export function sanitizeBlock(
  raw: string | null | undefined,
  opts?: { maxLen?: number },
): string {
  const maxLen = opts?.maxLen ?? kBlockMaxLen;
  if (raw == null) return "";

  let s = _keepAllowedOnly(
    String(raw)
      .replace(/\r\n?/g, "\n")
      .replace(_unicodeSeps, "\n")
      .replace(_controls, ""),
  )
    .replace(/\n{3,}/g, "\n\n")
    .trim();

  // The disclosure marker is the system speaking, so user text must not be able
  // to counterfeit it. Without this a user types "[...truncated]" mid-note and
  // primes the model to read what follows as a system-emitted continuation
  // rather than as their own content -- no length cap required. Review round 1.
  s = s.replace(/\[\.\.\.truncated\]/g, "[ ...truncated ]");

  if (s.length > maxLen) {
    s = _sliceWholeChars(s, maxLen).trim() + "\n[...truncated]";
  }
  return s;
}

/**
 * Serialises [value] for interpolation into a prompt, closing the ONE lever
 * `JSON.stringify` leaves open.
 *
 * Measured, not assumed (Deno probe, 2026-07-27):
 *
 *   lever                   survives JSON.stringify?
 *   LF / CR                 NO.  escaped to the two-char sequences
 *                                backslash-n and backslash-r
 *   C0 controls (e.g. ESC)  NO.  escaped to a backslash-u00XX sequence
 *   U+2028 / U+2029         YES. passed through RAW
 *   U+0085 NEL              YES. passed through RAW
 *
 * So a stringified payload is ALREADY immune to the classic newline injection,
 * but NOT to the Unicode separators, which render as line breaks to a model and
 * reach it verbatim. That makes a `JSON.stringify(userRow)` site a REAL but
 * NARROWER exposure than a raw interpolation, and it wants a DIFFERENT fix:
 * running [sanitizeBlock] over JSON would destroy the structure the prompt
 * depends on.
 *
 * The separators are re-escaped as backslash-uXXXX rather than replaced with a
 * space: still valid JSON, still inert to the model, and lossless, so a
 * legitimate separator inside a user's own note is preserved rather than
 * silently edited.
 *
 * NOTE ON THIS COMMENT. Its first draft wrote the escape examples as literal
 * characters and embedded an actual ESC byte plus em-dashes. In a file whose
 * whole subject is invisible characters, that is not irony, it is the predicted
 * failure -- which is why every example here is spelled out in words and the
 * pure-ASCII property is asserted by the test suite rather than eyeballed.
 */
export function sanitizeJsonForPrompt(value: unknown, space?: number): string {
  // JSON.stringify THROWS on a BigInt (a plain Postgres bigint column surfaced
  // without coercion) and on any circular structure. A hardening helper that
  // crashes the request it was added to protect is a worse outcome than the
  // injection it prevents, so failure degrades to an inert placeholder rather
  // than propagating. Review round 1 reproduced both throws directly.
  let json: string | undefined;
  try {
    json = JSON.stringify(value, null, space);
  } catch (e) {
    console.error(
      "[sanitize_for_prompt] JSON.stringify failed; emitting placeholder:",
      e instanceof Error ? e.message : String(e),
    );
    return '{"_unavailable":"data could not be serialised"}';
  }
  if (json === undefined) return "null";
  return json
    .replace(new RegExp("\\u2028", "g"), "\\u2028")
    .replace(new RegExp("\\u2029", "g"), "\\u2029")
    .replace(new RegExp("\\u0085", "g"), "\\u0085");
}

/** A fenced block plus the exact markers that delimit it. */
export interface FencedBlock {
  /** The full fenced text to interpolate into the prompt. */
  readonly text: string;
  /** Opening marker -- name it in the surrounding instruction. */
  readonly begin: string;
  /** Closing marker. */
  readonly end: string;
}

/**
 * Wraps sanitised content in a data fence whose delimiters CANNOT BE FORGED.
 *
 * THE FIX THAT ENDED THE ARMS RACE. The first version used a fixed marker,
 * <<<END_MEAL>>>, and defended it by trying to remove every character an
 * attacker could use to reconstruct it. That defence failed three times:
 *   1. user types the marker verbatim              -> defang the bracket runs
 *   2. user splits it with a zero-width character  -> strip zero-width
 *   3. five more BMP chars, plus astral Tag chars
 *      a non-`u` regex structurally cannot see     -> unwinnable
 *
 * Each fix was a longer list, and the list can never be finished. So the
 * delimiter is UNPREDICTABLE instead: a fresh 12-hex nonce per call. An attacker
 * cannot close a fence whose token they cannot guess, whatever characters
 * survive sanitisation. That is also why the character policy above can afford
 * to keep U+FE0F and U+3164 -- the fence no longer depends on it.
 *
 * The caller MUST name [begin] and [end] in its instruction text instead of
 * hardcoding a marker, which is why this returns them rather than a bare string.
 */
export function fenceAsData(
  sanitised: string,
  label = "USER_DATA",
): FencedBlock {
  const nonce = crypto.randomUUID().replace(/-/g, "").slice(0, 12);
  const begin = "<<<BEGIN_" + label + "_" + nonce + ">>>";
  const end = "<<<END_" + label + "_" + nonce + ">>>";
  return { text: begin + "\n" + sanitised + "\n" + end, begin, end };
}

/**
 * Marks a value as DELIBERATELY unsanitised because the user is the principal.
 *
 * The chat channel is the one place raw user text belongs in a prompt: the
 * user's message IS the request. Sanitising it would corrupt legitimate
 * multi-line messages, strip emoji from "great session!", and buy nothing --
 * they are not escaping into someone else's instructions, they are writing
 * their own. What needs protecting is the SYSTEM prompt around it.
 *
 * This is an identity function on purpose. It exists so the coverage gate sees
 * an explicit decision IN CODE at the call site, rather than a prose exemption
 * in a list somewhere else -- the mechanism that previously let a wrong
 * justification silence a right detection (food_parser.ts, review round 2).
 */
export function asPrincipalMessage(userMessage: string): string {
  return userMessage;
}

/**
 * Marks a locally-assembled prompt as AUTHORED BY US, not user-derived.
 *
 * Companion to [asPrincipalMessage]. Some prompts are built from our own
 * constants and template text a few lines above the call site
 * (assess-body-composition's clinical prompt, morning-alert's tone wrapper).
 * They are safe, but a checker cannot tell that from the identifier alone.
 *
 * WHY THIS EXISTS RATHER THAN A CLEVERER CHECKER. The coverage gate first tried
 * to TRACE identifiers to their declarations. Five rounds of tuning later,
 * negative controls still showed false PASSes -- windows bleeding past
 * statements, `.exec()` matching the wrong declaration, semicolons inside
 * comments truncating a body. A regex taint-tracker over TypeScript is the
 * wrong tool, and a gate that cannot be trusted to fail is worse than none.
 *
 * So the contract became blunt and checkable: a prompt value must be VISIBLY
 * safe at the assignment. If it is authored, say so here. The cost is one
 * wrapper call; the benefit is a gate with no tracing left to get wrong.
 */
export function asAuthoredPrompt(authored: string): string {
  return authored;
}
