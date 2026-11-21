// supabase/functions/_shared/write_claim_detector.ts
//
// coach-log-truth (OI-368 / OI-369, plan docs/plans/coach-log-truth.md §2.4):
// a LOG-ONLY detector of write claims in the coach's reply. It never changes
// the reply. It labels a reply that says something is logged / saved / done
// (a closed token list), or that carries one of the prescribed "Queued." lines,
// against the cards THIS reply produced, so the post-deploy measurement can
// read every case from the function log. Counts are approximate by design.

/** What the reply produced, from the handler. */
export interface DetectCtx {
  /** ToolIntent `type`s queued by the tool loop in this reply. */
  typedIntentTypes: string[];
  /** Legacy <ICBF_LOG> actions parsed from this reply (untyped on purpose). */
  legacyActions: unknown[];
  /** A 30 s dedup replay of an earlier reply. */
  replay: boolean;
  /** The user's message ended with "?" (a label only). */
  userAskedQuestion: boolean;
}

export type QueuedLine =
  | "apply_log"
  | "apply_confirm"
  | "apply_each"
  | "apply_save"
  | "apply_swap"
  | "fc2"
  | "confirm"
  | "skip";

export interface WriteClaimDetection {
  /** The first sentence with a claim token, and its marker / negation. */
  token: string | null;
  safe_marker: string | null;
  negation: boolean;
  /** Every sentence with a claim token and neither a marker nor a negation. */
  unsafe_claims: number;
  queued_lines: QueuedLine[];
  typed_log: number;
  typed_other: number;
  legacy_workout: number;
  legacy_auto: number;
  replay: boolean;
  user_question: boolean;
}

/** The closed claim-token list (plan §2.4, §5.5). Labels only. */
export const CLAIM_TOKENS = [
  "logged",
  "saved",
  "recorded",
  "added",
  "tracked",
  "locked in",
  "squared away",
  "on the books",
  "done",
  "swapped",
  "paused",
  "switched",
  "moved",
  "rescheduled",
  "marked",
  "completed",
  "updated",
  "all set",
] as const;

/** The closed safe-marker list: a claim next to one of these is likely not a save claim. */
export const SAFE_MARKERS = [
  "tap",
  "queued",
  "yesterday",
  "ago",
  "last night",
  "last week",
  "last session",
  "as complete",
  "snapshot",
  "will",
  "to log",
  "can log",
] as const;

/** The prescribed lines, each with its label. */
export const QUEUED_LINES: ReadonlyArray<readonly [QueuedLine, string]> = [
  ["apply_log", "Queued. Tap APPLY to log it."],
  ["apply_confirm", "Queued. Tap APPLY to confirm."],
  ["apply_each", "Queued. Tap APPLY on each card."],
  ["apply_save", "Queued. Tap APPLY to save it."],
  ["apply_swap", "Tap APPLY below to swap them."],
  ["fc2", "I've queued that below. Review the details and tap APPLY to confirm."],
  ["confirm", "Queued. Tap CONFIRM to log it."],
  ["skip", "Queued. It logs in 5 seconds unless you tap SKIP."],
];

const TYPED_LOG_TYPES = new Set(["log_set", "log_meal_by_text"]);
const LEGACY_AUTO = new Set([
  "log_water",
  "log_weight",
  "log_food",
  "log_sleep",
  "log_measurement",
]);

function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/** Whole-word, case-insensitive; multi-word phrases match with any spacing. */
function wordRe(phrase: string): RegExp {
  const body = phrase.split(/\s+/).map(escapeRe).join("\\s+");
  return new RegExp(`\\b${body}\\b`, "i");
}

const TOKEN_RES = CLAIM_TOKENS.map((t) => [t, wordRe(t)] as const);
const MARKER_RES = SAFE_MARKERS.map((m) => [m, wordRe(m)] as const);
const NEGATION_RE = /\b(?:not|nothing|no)\b|n't\b/i;

/** Curly apostrophes become straight ones; markdown emphasis goes. */
function normalise(text: string): string {
  return text.replace(/[*_`]/g, "").replace(/[\u2018\u2019]/g, "'");
}

function sentences(text: string): string[] {
  return text.split(/(?<=[.!?])\s+|\n+/).filter((s) => s.trim().length > 0);
}

/** Any run of whitespace (a newline, a double space, a NBSP) matches one space. */
function queuedLinesIn(text: string): QueuedLine[] {
  const found: Array<[number, QueuedLine]> = [];
  const lower = text.replace(/\s+/g, " ").toLowerCase();
  for (const [label, line] of QUEUED_LINES) {
    const needle = line.toLowerCase();
    let i = lower.indexOf(needle);
    while (i >= 0) {
      found.push([i, label]);
      i = lower.indexOf(needle, i + needle.length);
    }
  }
  return found.sort((a, b) => a[0] - b[0]).map(([, l]) => l);
}

/**
 * Pure. Null when the reply has no claim token and no prescribed line;
 * otherwise the labels. Never rewrites anything.
 */
export function detectWriteClaim(
  reply: unknown,
  ctx: DetectCtx,
): WriteClaimDetection | null {
  if (typeof reply !== "string" || reply.length === 0) return null;
  const text = normalise(reply);
  const queued_lines = queuedLinesIn(text);

  let token: string | null = null;
  let safe_marker: string | null = null;
  let negation = false;
  let unsafe_claims = 0;
  // Every sentence is read: a later "Logged." behind a safe first claim
  // still counts in unsafe_claims (B-pass 1ed091ce8263 F1).
  for (const s of sentences(text)) {
    const hit = TOKEN_RES.find(([, re]) => re.test(s));
    if (!hit) continue;
    const marker = MARKER_RES.find(([, re]) => re.test(s))?.[0] ?? null;
    const negated = NEGATION_RE.test(s);
    if (marker === null && !negated) unsafe_claims++;
    if (token === null) {
      token = hit[0];
      safe_marker = marker;
      negation = negated;
    }
  }
  if (token === null && queued_lines.length === 0) return null;

  const types = Array.isArray(ctx.typedIntentTypes) ? ctx.typedIntentTypes : [];
  const actions = Array.isArray(ctx.legacyActions) ? ctx.legacyActions : [];
  const actionName = (a: unknown): unknown =>
    a !== null && typeof a === "object" ? (a as { action?: unknown }).action : undefined;
  return {
    token,
    safe_marker,
    negation,
    unsafe_claims,
    queued_lines,
    typed_log: types.filter((t) => TYPED_LOG_TYPES.has(t)).length,
    typed_other: types.filter((t) => !TYPED_LOG_TYPES.has(t)).length,
    legacy_workout: actions.filter((a) => actionName(a) === "confirm_workout_log").length,
    legacy_auto: actions.filter((a) => {
      const n = actionName(a);
      return typeof n === "string" && LEGACY_AUTO.has(n);
    }).length,
    replay: ctx.replay === true,
    user_question: ctx.userAskedQuestion === true,
  };
}

/** The ctx of a 30 s dedup replay: no typed intents, the stored reply's tags. */
export function replayCtxOf(extracted: { actions: unknown[] }): DetectCtx {
  return {
    typedIntentTypes: [],
    legacyActions: extracted.actions,
    replay: true,
    userAskedQuestion: false,
  };
}

/**
 * One log line per labelled reply: never the reply text, never the user id.
 * Never breaks a reply: any error logs a fixed string and nothing else. The
 * ctx is a thunk so the handler's ctx expressions also run inside the try.
 */
export function logWriteClaimDetection(
  fn: string,
  interactionId: string | null | undefined,
  ruleOn: boolean,
  reply: unknown,
  ctx: () => DetectCtx,
  log: (...args: unknown[]) => void = console.log,
  warn: (...args: unknown[]) => void = console.warn,
): void {
  try {
    const detection = detectWriteClaim(reply, ctx());
    if (detection === null) return;
    log(
      "[write-claim-detect]",
      JSON.stringify({
        fn,
        interaction_id: interactionId ?? null,
        rule_on: ruleOn,
        ...detection,
      }),
    );
  } catch {
    warn("[write-claim-detect] skipped");
  }
}
