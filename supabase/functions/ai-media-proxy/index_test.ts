/**
 * Deno tests for `ai-media-proxy`'s Storage user-scope guard (OI-28), as
 * hardened by Hermes L23 F1 (2026-09-13, diagnose `c7e2a4`).
 *
 * Run:
 *   deno test --no-check --allow-all --node-modules-dir=none supabase/functions/ai-media-proxy/
 *
 * What is pinned, and why it is a BEHAVIOURAL test rather than a source-grep:
 * the guard used to inspect the string the caller SENT while `fetch` requests
 * the URL as the WHATWG parser RESOLVES it — dot-segments collapsed. Reading
 * the source cannot show that the two disagree; only running the guard and
 * watching what the fetch is handed can. So every case below drives the real
 * `fetchImageAsBase64` with an injected `fetchImpl` that RECORDS the URL it
 * receives, and asserts two things at once: the guard's verdict, and that a
 * fetch — when one happens — is for a path under the caller's own folder.
 *
 * The module reads SUPABASE_URL at import, so the env is set BEFORE the
 * dynamic import; `serve` is `import.meta.main`-guarded and does not run.
 */

import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const PROJECT = "https://example.supabase.co";
Deno.env.set("SUPABASE_URL", PROJECT);
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "test-service-role-key");

const { checkFreeImageQuota, fetchImageAsBase64, handleRequest, HttpError, parseStorageUrl } =
  await import("./index.ts");

const OWN = "11111111-1111-1111-1111-111111111111";
const VICTIM = "22222222-2222-2222-2222-222222222222";
const BASE = `${PROJECT}/storage/v1/object/`;

/** A fetch that never touches the network and records every URL it is handed. */
function recordingFetch(
  calls: string[],
  opts: { contentType?: string; status?: number; body?: Uint8Array<ArrayBuffer> } = {},
): typeof fetch {
  const body = opts.body ?? new Uint8Array([0x89, 0x50, 0x4e, 0x47]);
  return ((input: RequestInfo | URL, _init?: RequestInit) => {
    const url = typeof input === "string"
      ? input
      : input instanceof URL
      ? input.href
      : input.url;
    calls.push(url);
    return Promise.resolve(
      new Response(body, {
        status: opts.status ?? 200,
        headers: {
          "content-type": opts.contentType ?? "image/png",
          "content-length": String(body.byteLength),
        },
      }),
    );
  }) as typeof fetch;
}

async function expectHttpError(
  fn: () => Promise<unknown>,
  status: number,
  errorType: string,
): Promise<void> {
  const err = await assertRejects(fn);
  assert(err instanceof HttpError, `expected HttpError, got ${String(err)}`);
  assertEquals((err as InstanceType<typeof HttpError>).status, status);
  assertEquals((err as InstanceType<typeof HttpError>).errorType, errorType);
}

// ---------------------------------------------------------------------------
// parseStorageUrl — the components are those of the URL as REQUESTED
// ---------------------------------------------------------------------------

Deno.test("parseStorageUrl: the three benign shapes parse to bucket + path + href", () => {
  const cases: Array<[string, string, string]> = [
    [`${BASE}public/chat-media/${OWN}/a.jpg`, "chat-media", `${OWN}/a.jpg`],
    [`${BASE}sign/coach-media/${OWN}/b.jpg?token=abc`, "coach-media", `${OWN}/b.jpg`],
    [`${BASE}authenticated/progress-photos/${OWN}/2026/c.jpg`, "progress-photos", `${OWN}/2026/c.jpg`],
  ];
  for (const [url, bucket, path] of cases) {
    const parsed = parseStorageUrl(url);
    assert(parsed !== null, `expected ${url} to parse`);
    assertEquals(parsed.bucket, bucket);
    assertEquals(parsed.path, path);
    assertEquals(parsed.href, url, "a clean URL normalises to itself");
  }
});

Deno.test("parseStorageUrl: a sign URL keeps its token in href and out of path", () => {
  const parsed = parseStorageUrl(`${BASE}sign/chat-media/${OWN}/a.jpg?token=t0k`);
  assert(parsed !== null);
  assertEquals(parsed.path, `${OWN}/a.jpg`);
  assertStringIncludes(parsed.href, "?token=t0k");
});

Deno.test("parseStorageUrl: dot-segments are RESOLVED before the path is read (L23 F1)", () => {
  // Every spelling the WHATWG parser treats as `..` — the string the caller
  // sent begins with the caller's own folder; the path fetch would request
  // does not.
  const spellings = ["..", "%2e%2e", ".%2e", "%2e.", "%2E%2E"];
  for (const dots of spellings) {
    const parsed = parseStorageUrl(`${BASE}authenticated/chat-media/${OWN}/${dots}/${VICTIM}/x.jpg`);
    assert(parsed !== null, `expected the ${dots} form to still parse as a Storage URL`);
    assertEquals(parsed.path, `${VICTIM}/x.jpg`, `path must be the RESOLVED one for ${dots}`);
    assert(!parsed.path.startsWith(`${OWN}/`), `the raw-string prefix must not survive ${dots}`);
    assertEquals(parsed.href, `${BASE}authenticated/chat-media/${VICTIM}/x.jpg`);
  }
});

Deno.test("parseStorageUrl: enough dot-segments to leave /storage/v1/object/ is not a Storage URL at all", () => {
  const url = `${BASE}authenticated/chat-media/${OWN}/../../../../../../rest/v1/users`;
  assert(url.startsWith(BASE), "the SENT string passes a raw prefix check");
  assertEquals(new URL(url).pathname, "/rest/v1/users", "the REQUESTED path is PostgREST");
  assertEquals(parseStorageUrl(url), null);
});

Deno.test("parseStorageUrl: backslashes are separators to the parser and resolve the same way", () => {
  const parsed = parseStorageUrl(`${BASE}authenticated/chat-media/${OWN}\\..\\${VICTIM}/x.jpg`);
  assert(parsed !== null);
  assertEquals(parsed.path, `${VICTIM}/x.jpg`);
});

Deno.test("parseStorageUrl: an encoded slash is NOT a separator — the segment stays literal", () => {
  // `..%2f` is one opaque segment to the parser; the object cannot exist
  // under that literal key, and the request stays under /storage/v1/object/.
  const parsed = parseStorageUrl(`${BASE}authenticated/chat-media/${OWN}/..%2f${VICTIM}/x.jpg`);
  assert(parsed !== null);
  assertEquals(parsed.path, `${OWN}/..%2f${VICTIM}/x.jpg`);
  assertStringIncludes(parsed.href, "/storage/v1/object/authenticated/chat-media/");
});

Deno.test("fetchImageAsBase64: a differently-cased host or an explicit default port is NOT rejected — parseStorageUrl is the ONLY origin check (B-pass 2026-09-13)", async () => {
  // A vestigial raw-string prefix check used to run BEFORE parseStorageUrl
  // and was strictly narrower: an uppercase host or an explicit `:443`
  // resolve to the identical, correct object under `new URL()`, but failed
  // a raw `.startsWith()` compare and were rejected before parseStorageUrl
  // ever ran. Never a security gap (never MORE permissive) — a real
  // false-rejection bug on a legitimate request shape.
  for (
    const url of [
      `https://EXAMPLE.supabase.co/storage/v1/object/authenticated/chat-media/${OWN}/a.jpg`,
      `https://example.supabase.co:443/storage/v1/object/authenticated/chat-media/${OWN}/a.jpg`,
    ]
  ) {
    const calls: string[] = [];
    const { base64 } = await fetchImageAsBase64(url, OWN, recordingFetch(calls));
    assert(base64.length > 0, `expected ${url} to be fetched, not rejected`);
    assertEquals(calls.length, 1);
  }
});

Deno.test("parseStorageUrl: rejects the non-Storage shapes it always rejected", () => {
  for (
    const url of [
      "not a url",
      `https://evil.example/storage/v1/object/public/chat-media/${OWN}/a.jpg`,
      `${PROJECT}/rest/v1/users`,
      `${BASE}download/chat-media/${OWN}/a.jpg`, // unknown access mode
      `${BASE}public/chat-media`, // no path
      `${BASE}public//a.jpg`, // no bucket
    ]
  ) {
    assertEquals(parseStorageUrl(url), null, `expected null for ${url}`);
  }
});

// ---------------------------------------------------------------------------
// fetchImageAsBase64 — the guard's verdict AND what the fetch is handed
// ---------------------------------------------------------------------------

Deno.test("fetchImageAsBase64: a traversal spelled as the caller's own folder is a 403 and NEVER fetched", async () => {
  for (const dots of ["..", "%2e%2e", ".%2e", "%2e."]) {
    const calls: string[] = [];
    await expectHttpError(
      () =>
        fetchImageAsBase64(
          `${BASE}authenticated/chat-media/${OWN}/${dots}/${VICTIM}/x.jpg`,
          OWN,
          recordingFetch(calls),
        ),
      403,
      "authorization",
    );
    assertEquals(calls, [], `no bytes may leave for the ${dots} form`);
  }
});

Deno.test("fetchImageAsBase64: a traversal out of Storage entirely is a 400 and NEVER fetched", async () => {
  const calls: string[] = [];
  await expectHttpError(
    () =>
      fetchImageAsBase64(
        `${BASE}authenticated/chat-media/${OWN}/../../../../../../rest/v1/users`,
        OWN,
        recordingFetch(calls),
      ),
    400,
    "validation",
  );
  assertEquals(calls, []);
});

Deno.test("fetchImageAsBase64: another user's plain path is still a 403 (OI-28 holds)", async () => {
  const calls: string[] = [];
  await expectHttpError(
    () => fetchImageAsBase64(`${BASE}authenticated/chat-media/${VICTIM}/x.jpg`, OWN, recordingFetch(calls)),
    403,
    "authorization",
  );
  assertEquals(calls, []);
});

Deno.test("fetchImageAsBase64: a prefix that is not a folder boundary is a 403", async () => {
  // `<own>abc/x.jpg` starts with the uid but is someone else's folder.
  const calls: string[] = [];
  await expectHttpError(
    () => fetchImageAsBase64(`${BASE}authenticated/chat-media/${OWN}abc/x.jpg`, OWN, recordingFetch(calls)),
    403,
    "authorization",
  );
  assertEquals(calls, []);
});

Deno.test("fetchImageAsBase64: a disallowed bucket is a 400 before any fetch", async () => {
  const calls: string[] = [];
  await expectHttpError(
    () => fetchImageAsBase64(`${BASE}authenticated/exercise-images/${OWN}/x.jpg`, OWN, recordingFetch(calls)),
    400,
    "validation",
  );
  assertEquals(calls, []);
});

Deno.test("fetchImageAsBase64: a foreign origin is the SSRF 400 before any fetch", async () => {
  const calls: string[] = [];
  await expectHttpError(
    () =>
      fetchImageAsBase64(
        `https://evil.example/storage/v1/object/authenticated/chat-media/${OWN}/x.jpg`,
        OWN,
        recordingFetch(calls),
      ),
    400,
    "validation",
  );
  assertEquals(calls, []);
});

Deno.test("fetchImageAsBase64: the caller's own object is fetched ONCE, at the normalised href, with the service role", async () => {
  const calls: string[] = [];
  const url = `${BASE}sign/chat-media/${OWN}/photo.jpg?token=t0k`;
  const captured: RequestInit[] = [];
  const fetchImpl = ((input: RequestInfo | URL, init?: RequestInit) => {
    captured.push(init ?? {});
    return recordingFetch(calls, { contentType: "image/jpeg; charset=binary" })(input, init);
  }) as typeof fetch;
  const { base64, mimeType } = await fetchImageAsBase64(url, OWN, fetchImpl);
  assertEquals(calls, [url], "a clean URL is requested exactly as sent, token included");
  assertEquals(mimeType, "image/jpeg", "the MIME is the content-type without parameters");
  assertEquals(base64, btoa(String.fromCharCode(0x89, 0x50, 0x4e, 0x47)));
  const headers = captured[0].headers as Record<string, string>;
  assertEquals(headers.Authorization, "Bearer test-service-role-key");
  assertEquals(headers.apikey, "test-service-role-key");
});

Deno.test("fetchImageAsBase64: PROPERTY — whenever a fetch happens, its path is under the caller's own folder", async () => {
  // The invariant the whole guard exists for, checked at the fetch seam
  // rather than at the guard: for every URL a caller could send, either no
  // fetch happens, or the fetched pathname sits under
  // /storage/v1/object/<access>/<bucket>/<own>/.
  const attempts = [
    `${BASE}authenticated/chat-media/${OWN}/x.jpg`,
    `${BASE}authenticated/chat-media/${OWN}/../${VICTIM}/x.jpg`,
    `${BASE}authenticated/chat-media/${OWN}/%2e%2e/${VICTIM}/x.jpg`,
    `${BASE}authenticated/chat-media/${OWN}/./x.jpg`,
    `${BASE}authenticated/chat-media/${OWN}/a/../x.jpg`,
    `${BASE}authenticated/chat-media/${OWN}/../../../../../../rest/v1/users`,
    `${BASE}authenticated/chat-media/${OWN}\\..\\${VICTIM}/x.jpg`,
    `${BASE}authenticated/chat-media/${OWN}/x.jpg#/../${VICTIM}`,
    `${BASE}public/coach-media/${OWN}/..%2f${VICTIM}/x.jpg`,
    `${BASE}authenticated/chat-media/${VICTIM}/../${OWN}/x.jpg`,
  ];
  let fetched = 0;
  for (const url of attempts) {
    const calls: string[] = [];
    try {
      await fetchImageAsBase64(url, OWN, recordingFetch(calls));
    } catch (err) {
      assert(err instanceof HttpError, `only typed refusals may escape: ${String(err)}`);
      assertEquals(calls, [], `a refusal must not have fetched: ${url}`);
      continue;
    }
    fetched += 1;
    assertEquals(calls.length, 1, `exactly one fetch for ${url}`);
    const path = new URL(calls[0]).pathname;
    const under = new RegExp(`^/storage/v1/object/(public|sign|authenticated)/[^/]+/${OWN}/`);
    assert(under.test(path), `fetched OUTSIDE the caller's folder: ${url} -> ${path}`);
  }
  // Positive control — the property must have been exercised on the
  // allow side too, or a guard that refuses everything would pass it.
  assert(fetched >= 4, `expected at least 4 of ${attempts.length} attempts to be fetched, got ${fetched}`);
});

// ---------------------------------------------------------------------------
// checkFreeImageQuota — the free-tier lifetime cap, called from TWO sites
// (B-pass F2, 2026-09-13): pre-fetch for the honest claim=image caller, and
// post-fetch for the caller whose claim said "video" but whose served bytes
// reconciled to an image. Behavioural, not a source-grep: the Dart contract
// pins that both call sites exist and delegate here; this proves the
// delegate itself is correct.
// ---------------------------------------------------------------------------

/**
 * A minimal fake client matching BOTH chains checkFreeImageQuota can reach:
 * `usage_counters` (the read `readFreeImageQuota` makes) and
 * `ai_coach_interactions` (the insert on an at-ceiling refusal).
 */
function fakeUsageCountersClient(
  reply: { used?: number } | { errored: true } | null,
): SupabaseClient {
  const readBuilder: Record<string, unknown> = {};
  for (const m of ["select", "eq"]) {
    readBuilder[m] = (..._args: unknown[]) => readBuilder;
  }
  readBuilder.maybeSingle = () =>
    Promise.resolve(
      reply === null
        ? { data: null, error: null }
        : "errored" in reply
        ? { data: null, error: { message: "usage_counters unreadable" } }
        : { data: { used: reply.used }, error: null },
    );
  const insertBuilder = { insert: (_row: unknown) => Promise.resolve({ data: null, error: null }) };
  return {
    from: (table: string) => (table === "usage_counters" ? readBuilder : insertBuilder),
  } as unknown as SupabaseClient;
}

Deno.test("checkFreeImageQuota: an unreadable ledger fails CLOSED with quota_unavailable, no log row", async () => {
  const client = fakeUsageCountersClient({ errored: true });
  const res = await checkFreeImageQuota(client, "u1", "https://x/y.jpg", "image", "hi");
  assert(res !== null, "must refuse, not proceed");
  const body = await res!.json();
  assertEquals(body.gate_reason, "quota_unavailable");
  assertEquals(body.gated, true);
  assertEquals(res!.status, 200);
  assertEquals(body.free_image_used, undefined, "never a fabricated count on an unreadable read");
});

Deno.test("checkFreeImageQuota: an ABSENT row grants (used = 0), never refuses", async () => {
  const client = fakeUsageCountersClient(null);
  const res = await checkFreeImageQuota(client, "u1", "https://x/y.jpg", "image", "hi");
  assertEquals(res, null, "an absent row is used=0 — every free user's first request must proceed");
});

Deno.test("checkFreeImageQuota: at the ceiling refuses with free_image_limit_reached and the honest count", async () => {
  const client = fakeUsageCountersClient({ used: 5 });
  const res = await checkFreeImageQuota(client, "u1", "https://x/y.jpg", "video", "look at this");
  assert(res !== null);
  const body = await res!.json();
  assertEquals(body.gate_reason, "free_image_limit_reached");
  assertEquals(body.free_image_used, 5);
  assertEquals(body.free_image_limit, 5);
  // The `mediaType` param is used only in the persisted log's text, honestly
  // reflecting the CALLER's claim at the call site (the post-fetch site
  // passes the original media_type even though isVideo has been reconciled
  // to false by then) — not asserted here since it is not in the response.
});

Deno.test("checkFreeImageQuota: under the ceiling proceeds (returns null)", async () => {
  const client = fakeUsageCountersClient({ used: 4 });
  const res = await checkFreeImageQuota(client, "u1", "https://x/y.jpg", "image", "hi");
  assertEquals(res, null);
});

// ---------------------------------------------------------------------------
// handleRequest — the module boots without a server and answers the cheap paths
// ---------------------------------------------------------------------------

Deno.test("handleRequest: OPTIONS is the CORS preflight, GET is 405, no auth is 401", async () => {
  const opt = await handleRequest(new Request("http://localhost/ai-media-proxy", { method: "OPTIONS" }));
  assertEquals(opt.status, 200);
  const get = await handleRequest(new Request("http://localhost/ai-media-proxy", { method: "GET" }));
  assertEquals(get.status, 405);
  const noAuth = await handleRequest(
    new Request("http://localhost/ai-media-proxy", { method: "POST", body: "{}" }),
  );
  assertEquals(noAuth.status, 401);
});

// ---------------------------------------------------------------------------
// OI-238 (sibling of A5/OI-226, f7a2c9) — ai-media-proxy's own geminiChat()
// call had no reportGeminiExhaustion wiring: `lastError` was never
// destructured, so the !rawReply branch structurally could not alert.
//
// `handleRequest` IS exported here, but every test above stops at the auth
// boundary (`supabaseClient.auth.getUser(token)` is a REAL createClient call
// against SUPABASE_URL — nothing in this file injects a fake auth response),
// so driving a real request all the way to the geminiChat branch is not
// reachable with this file's existing test seam. Same SOURCE-GREP approach
// used for the other 4 OI-238 sites (weekly-report, assess-body-composition,
// daily-snapshot, rolling-context) — position-scoped to the `!rawReply`
// branch and comment-stripped before any `.includes()` check.
// ---------------------------------------------------------------------------

function stripComments(s: string): string {
  return s.replace(/\/\*[\s\S]*?\*\//g, " ").replace(/\/\/[^\n]*/g, " ");
}

const rawIndexSource = Deno.readTextFileSync(
  new URL("./index.ts", import.meta.url),
);

Deno.test("ai-media-proxy imports reportGeminiExhaustion", () => {
  assert(
    rawIndexSource.includes(
      'import { reportGeminiExhaustion } from "../_shared/gemini_failure_alert.ts";',
    ),
    "index.ts must import reportGeminiExhaustion",
  );
});

Deno.test("ai-media-proxy destructures lastError from its geminiChat call (OI-238)", () => {
  const callIdx = rawIndexSource.indexOf("await geminiChat({");
  assert(callIdx >= 0, "geminiChat call not found");
  const destructureLine = rawIndexSource.slice(Math.max(0, callIdx - 200), callIdx);
  assert(
    destructureLine.includes("lastError"),
    `expected the geminiChat destructure to include lastError, got: ${destructureLine}`,
  );
});

Deno.test(
  "ai-media-proxy reports Gemini exhaustion on the !rawReply branch, BEFORE the 502 return (OI-238)",
  () => {
    const branchIdx = rawIndexSource.indexOf("if (!rawReply) {");
    assert(branchIdx >= 0, "!rawReply branch not found");
    const branchEnd = rawIndexSource.indexOf("\n    }\n", branchIdx);
    assert(branchEnd >= 0, "could not bound the !rawReply block");
    const rawBlock = rawIndexSource.slice(branchIdx, branchEnd);
    const block = stripComments(rawBlock);

    assert(
      block.includes("reportGeminiExhaustion("),
      "the !rawReply branch must call reportGeminiExhaustion",
    );
    assert(
      block.includes('"ai_proxy_gemini_exhausted"'),
      "must reuse the shared ai-proxy dedup source (live user traffic, same quota)",
    );
    assert(
      block.includes('"ai_media_proxy"'),
      'must tag this call site with endpoint "ai_media_proxy"',
    );
    assert(
      block.includes("lastError ?? null"),
      "must forward the real lastError (or null), not a fabricated value",
    );

    const reportIdx = block.indexOf("reportGeminiExhaustion(");
    const responseIdx = block.indexOf("new Response(");
    assert(
      reportIdx >= 0 && responseIdx >= 0 && reportIdx < responseIdx,
      "the alert must fire BEFORE the 502 Response is returned",
    );
  },
);
