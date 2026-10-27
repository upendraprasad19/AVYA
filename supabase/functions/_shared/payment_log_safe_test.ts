// Tests for _shared/payment_log_safe.ts (OI-360, payment-hardening U0): each helper against hostile input.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { boundedText, codeToken, errorName, notesShape, pgErrorCode, razorpayErrorSummary, stackFrames } from "./payment_log_safe.ts";

const SIG = "f3b1c2d4e5a6978812345678abcdef0011223344556677889900aabbccddeeff";

Deno.test("pgErrorCode: a short code passes; details, hint and message never do", () => {
  const err = {
    code: "23503",
    message: `insert or update on table violates foreign key constraint`,
    details: `Key (razorpay_signature)=(${SIG}) is not present`,
    hint: SIG,
  };
  assertEquals(pgErrorCode(err), "23503");
  assertEquals(pgErrorCode({ code: "PGRST116" }), "PGRST116");
  assert(!pgErrorCode(err).includes(SIG));
});

Deno.test("pgErrorCode: non-string, nested, empty, oversized or forged codes -> no_code", () => {
  for (const bad of [
    null, undefined, "23505", 23505, {}, { code: 23505 }, { code: { inner: "23505" } }, { code: "" },
    { code: "x".repeat(10_000) }, { code: "23505\n[verify-payment] forged" }, { code: "a b" }, [{ code: "1" }],
  ]) {
    assertEquals(pgErrorCode(bad), "no_code", JSON.stringify(bad)?.slice(0, 60));
  }
});

Deno.test("errorName: an Error's name only (never its message); otherwise the type", () => {
  const e = new TypeError(`fetch https://api.telegram.org/bot123:SECRET/sendMessage failed ${SIG}`);
  assertEquals(errorName(e), "TypeError");
  assertEquals(errorName(null), "null");
  assertEquals(errorName(undefined), "undefined");
  assertEquals(errorName({ message: SIG }), "object");
  assertEquals(errorName(SIG), "string");
});

Deno.test("boundedText: quoted, escaped, at most n characters of the value", () => {
  assertEquals(boundedText("monthly"), '"monthly"');
  assertEquals(boundedText("a\nb"), '"a\\nb"');
  assert(!boundedText("x\n[razorpay-webhook] forged line").includes("\n"));
  assertEquals(boundedText("x".repeat(10_000)), JSON.stringify("x".repeat(40)));
  assertEquals(boundedText("abcdef", 3), '"abc"');
  assertEquals(boundedText(undefined), '"undefined"');
  assertEquals(boundedText({ a: SIG }), '"[object Object]"');
  // DEL, NEL (C1) and the Unicode line/paragraph separators, which JSON.stringify leaves raw (built from
  // their codes: the characters themselves must never appear in this file).
  for (const code of [0x7f, 0x85, 0x9f, 0x2028, 0x2029, 0x202e, 0x200b, 0xfeff, 0xad]) {
    const out = boundedText("a" + String.fromCharCode(code) + "b");
    assertEquals(out, `"a\\u${code.toString(16).padStart(4, "0")}b"`, `code ${code.toString(16)}`);
    assert([...out].every((ch) => ch.charCodeAt(0) >= 0x20 && ch.charCodeAt(0) < 0x7f), `code ${code.toString(16)}`);
  }
  // EVERY occurrence, not only the first (a forged line needs two separators): several in one value.
  const many = "a" + [0x85, 0x85, 0x2028, 0x7f, 0x202e].map((c) => String.fromCharCode(c)).join("") + "b";
  assertEquals(boundedText(many), '"a\\u0085\\u0085\\u2028\\u007f\\u202eb"');
});

Deno.test("razorpayErrorSummary: status plus string code/reason only", () => {
  const body = JSON.stringify({
    error: {
      code: "BAD_REQUEST_ERROR",
      description: `The payment has already been captured ${SIG}`,
      reason: "payment_already_captured",
      field: "amount",
      metadata: { payment_id: "pay_X", order_id: "order_Y" },
    },
  });
  const s = razorpayErrorSummary(400, body);
  assertEquals(s, 'status=400 code="BAD_REQUEST_ERROR" reason="payment_already_captured"');
  assert(!s.includes(SIG) && !s.includes("pay_X"));
});

Deno.test("razorpayErrorSummary: non-JSON, null, array, string error, a 10 KB body, a non-integer status", () => {
  assertEquals(razorpayErrorSummary(502, "<html>Bad gateway " + SIG + "</html>"), "status=502");
  assertEquals(razorpayErrorSummary(500, "null"), "status=500");
  assertEquals(razorpayErrorSummary(500, "[1,2]"), "status=500");
  assertEquals(razorpayErrorSummary(500, JSON.stringify({ error: SIG })), "status=500");
  assertEquals(razorpayErrorSummary(500, JSON.stringify({ error: [SIG] })), "status=500");
  assertEquals(razorpayErrorSummary("500", "{}"), "status=?");
  const big = razorpayErrorSummary(400, JSON.stringify({ error: { code: "C".repeat(10_000), reason: 7 } }));
  assertEquals(big, `status=400 code=${JSON.stringify("C".repeat(40))}`);
  const nl = razorpayErrorSummary(400, JSON.stringify({ error: { code: "A\n[x] forged" } }));
  assert(!nl.includes("\n"), nl);
});

Deno.test("notesShape: known keys and a count, never values or unknown key names", () => {
  const s = notesShape({ user_id: "11111111-1111-4111-8111-111111111111", plan: "monthly", promo_code: "HALF50", secret_card: SIG });
  assertEquals(s, "keys=[user_id,plan,promo_code] other=1");
  assert(!s.includes(SIG) && !s.includes("secret_card") && !s.includes("HALF50") && !s.includes("1111"));
  assertEquals(notesShape([]), "array(0)");
  assertEquals(notesShape(null), "null");
  assertEquals(notesShape(SIG), "string");
  assertEquals(notesShape(undefined), "undefined");
  assertEquals(notesShape({}), "keys=[] other=0");
});

Deno.test("codeToken: a short plain token passes; anything else is no_code", () => {
  assertEquals(codeToken("23505"), "23505");
  assertEquals(codeToken("bad_rpc_response"), "bad_rpc_response");
  assertEquals(codeToken("TypeError"), "TypeError");
  assertEquals(codeToken("x".repeat(25)), "no_code");
  assertEquals(codeToken("23505\n[verify-payment] forged"), "no_code");
  assertEquals(codeToken(`code ${SIG}`), "no_code");
  assertEquals(codeToken(undefined), "no_code");
  assertEquals(codeToken({ code: "23505" }), "no_code");
});

// hermes H10: the catch-alls log name + frames; the message (which can quote the request body) never appears.
Deno.test("stackFrames: up to n frames, never the message line", () => {
  let err: unknown;
  try {
    JSON.parse('{"payment_id":"pay_SECRETBODY');
  } catch (e) {
    err = e;
  }
  const s = stackFrames(err);
  assert(!s.includes("SECRETBODY"), s);
  assert(!s.includes("SyntaxError"), s);
  const frames = s.split(" | ");
  assert(frames.length >= 1 && frames.length <= 3, s);
  for (const f of frames) assert(f.startsWith("at "), s);
  assertEquals(stackFrames(err, 1).split(" | ").length, 1);
});

// B-pass bfaeb6fb79da finding 1: a message holding a newline and "at " used to come out as a frame.
Deno.test("stackFrames: a message with a newline and 'at ' never becomes a frame", () => {
  let err: unknown;
  try {
    JSON.parse('{"a":\n at SECRETPAY pay_123 and more');
  } catch (e) {
    err = e;
  }
  assert((err as Error).message.includes("\n at SECRETP"), "precondition: the message quotes the body across a newline");
  const s = stackFrames(err);
  assert(!s.includes("SECRET"), s);
  assert(s.startsWith("at "), s);
  const forged = new Error("boom\n    at SECRETFRAME (forged.ts:1:1)");
  const f = stackFrames(forged);
  assert(!f.includes("SECRETFRAME"), f);
  assert(f.startsWith("at "), f);
});

Deno.test("stackFrames: each frame is escaped and bounded; a message the stack lacks is no_stack", () => {
  const e = new Error("m");
  e.stack = "Error: m\n    at f (file\u2028x\u0007.ts:1:1)\n    at " + "g".repeat(400);
  const s = stackFrames(e);
  assert(!s.includes("\u2028") && !s.includes("\u0007"), JSON.stringify(s));
  assert(s.includes("\\u2028") && s.includes("\\u0007"), s);
  assertEquals(s.split(" | ")[1].length, 200);
  const lost = new Error("not in the stack");
  lost.stack = "Error: something else\n    at f (a.ts:1:1)";
  assertEquals(stackFrames(lost), "no_stack");
  const empty = new Error();
  empty.stack = "Error\n    at f (a.ts:1:1)";
  assertEquals(stackFrames(empty), "at f (a.ts:1:1)");
});

// B-pass aabb2b0dbdbb findings 2 and 5: the C1 and format characters are escaped too; a hostile Error never
// makes stackFrames throw inside a catch-all, and a non-string message (whose text cannot be located) is no_stack.
Deno.test("stackFrames: C1 and format characters are escaped in a frame", () => {
  const e = new Error("m");
  e.stack = "Error: m\n    at f (a\u0085b\u202ec\u200bd.ts:1:1)";
  const s = stackFrames(e);
  for (const raw of ["\u0085", "\u202e", "\u200b"]) assert(!s.includes(raw), JSON.stringify(s));
  for (const esc of ["\\u0085", "\\u202e", "\\u200b"]) assert(s.includes(esc), s);
});

Deno.test("stackFrames: throwing getters and a non-string message give no_stack, never a throw", () => {
  const badStack = new Error("m");
  Object.defineProperty(badStack, "stack", { get() { throw new Error("boom"); } });
  assertEquals(stackFrames(badStack), "no_stack");
  const badMessage = new Error("m");
  Object.defineProperty(badMessage, "message", { get() { throw new Error("boom"); } });
  assertEquals(stackFrames(badMessage), "no_stack");
  const odd = new Error("x");
  (odd as unknown as { message: unknown }).message = { toString: () => "x\n at SECRETFRAME" };
  odd.stack = "Error: x\n at SECRETFRAME (forged.ts:1:1)\n    at f (a.ts:1:1)";
  assertEquals(stackFrames(odd), "no_stack");
});

Deno.test("stackFrames: a non-Error, or an Error without frames, is no_stack", () => {
  assertEquals(stackFrames("pay_SECRETBODY"), "no_stack");
  assertEquals(stackFrames({ stack: "at x" }), "no_stack");
  const e = new Error("pay_SECRETBODY");
  e.stack = "Error: pay_SECRETBODY";
  assertEquals(stackFrames(e), "no_stack");
});
