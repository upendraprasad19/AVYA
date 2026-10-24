// Tests for _shared/payment_log_safe.ts (OI-360, payment-hardening U0): each helper against hostile input.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { boundedText, codeToken, errorName, notesShape, pgErrorCode, razorpayErrorSummary } from "./payment_log_safe.ts";

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
