// supabase/functions/_shared/gemini_fake_fetch.ts
//
// Test helper (NOT a test — no `_test` suffix): a scripted `fetch` stub that
// records the request URL AND parsed body of EVERY attempt. Call-count-only
// fakes stay green when an attempt list is wrong (`attempts.push(model)` still
// makes two calls); recording the model slug + request body per attempt is what
// lets a test pin WHICH model got WHICH thinkingConfig / history.

export interface FakeCall {
  /** Model slug parsed from the request URL. */
  model: string;
  // deno-lint-ignore no-explicit-any
  body: any;
}

export type FakeReply =
  | { status: number; json?: unknown; text?: string }
  | "throw";

export function okText(text: string, usage: Record<string, unknown> = { totalTokenCount: 5 }): FakeReply {
  return {
    status: 200,
    json: { candidates: [{ content: { parts: [{ text }] } }], usageMetadata: usage },
  };
}

/** A functionCall turn exactly as Gemini 3 sends it (signature BESIDE functionCall). */
export function okToolCall(
  name: string,
  args: Record<string, unknown>,
  thoughtSignature?: string,
): FakeReply {
  const part: Record<string, unknown> = { functionCall: { name, args } };
  if (thoughtSignature !== undefined) part.thoughtSignature = thoughtSignature;
  return {
    status: 200,
    json: { candidates: [{ content: { parts: [part] } }], usageMetadata: { totalTokenCount: 7 } },
  };
}

export function httpError(status: number, message = `HTTP ${status}`): FakeReply {
  return {
    status,
    text: JSON.stringify({ error: { code: status, message, status: status === 404 ? "NOT_FOUND" : "ERR" } }),
  };
}

/**
 * Install the stub. `script` is consumed in order; running past its end repeats
 * the last entry. Returns the recorded calls and a restore fn.
 */
export function installFakeFetch(script: FakeReply[]): {
  calls: FakeCall[];
  restore: () => void;
} {
  const original = globalThis.fetch;
  const calls: FakeCall[] = [];
  globalThis.fetch = ((input: unknown, init?: { body?: string }): Promise<Response> => {
    const url = String(input);
    const model = /models\/([^:]+):/.exec(url)?.[1] ?? "?";
    calls.push({ model, body: init?.body ? JSON.parse(init.body) : null });
    const reply = script[Math.min(calls.length - 1, script.length - 1)];
    if (reply === "throw") return Promise.reject(new TypeError("network down"));
    return Promise.resolve({
      ok: reply.status < 400,
      status: reply.status,
      text: () => Promise.resolve(reply.text ?? ""),
      json: () => Promise.resolve(reply.json ?? {}),
    } as unknown as Response);
  }) as typeof fetch;
  return { calls, restore: () => (globalThis.fetch = original) };
}
