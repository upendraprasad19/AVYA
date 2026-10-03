---
bug_id: c7e2a4
date: 2026-09-13
batch: oi153-pro-media-caps
status: fixed
blast_radius: platform
symptom: >
  ai-media-proxy's OI-28 user-scope guard inspected the Storage URL as the
  caller SENT it while `fetch` requests it as the WHATWG URL parser RESOLVES
  it. `…/authenticated/chat-media/<own>/../<victim>/x.jpg` therefore passed
  `parsed.path.startsWith(`${authUserId}/`)` — the raw string does begin with
  the caller's folder — and the runtime, which collapses dot-segments before
  any bytes leave, fetched the VICTIM's object with the service role and sent
  it to Gemini. `%2e%2e` and `.%2e` are the same segment to that parser. Six
  `..` left Storage altogether: the request became `/rest/v1/users` (and
  `/auth/v1/admin/users`) with the service-role bearer — every row, returned
  as "the image", base64-encoded into the model prompt. Pre-existing since
  OI-28's fix (`5e055f`, 2026-05-17); found by the Hermes L23 lens on this
  batch, reproduced with a Deno probe (`new Request(u).url`). Two siblings in
  the same function, same lens, fixed in the same deploy: F2 — the cap KEY,
  the cap and the free-tier video paywall were selected by the client's
  `media_type` while Gemini is told Storage's content-type, so a free caller
  labelling a video "image" walked it past the PRO-only paywall for one
  lifetime image unit and a PRO caller drew a video from the 50/day image
  bucket; F3 — `proDailyUsed = proCount as number` read a `null` RPC result
  as GRANTED (unmetered, unreported).

  Two more real defects found by the B-pass over this same commit (labelled
  BP-1/BP-2 to keep them distinct from the Hermes F1/F2/F3 above), both in
  the same function: BP-1 — a vestigial raw-string prefix check
  (`imageUrl.startsWith(STORAGE_PREFIX)`) ran BEFORE `parseStorageUrl` and
  was strictly MORE restrictive than it (an uppercase host or an explicit
  default port `:443` resolve to the identical, correct object under
  `new URL()` but failed the raw compare) — a real false-rejection bug,
  never a security gap, and one that made this doc's own claim ("the guard
  and the request can no longer see two paths") false while it survived.
  BP-2 — the F2 fix above only reconciled ONE direction: a FREE user who
  mislabelled a real IMAGE as `media_type: "video"` was paywalled on the
  claim BEFORE the fetch, denying a legitimate free analysis; worse, naively
  removing that pre-fetch paywall (the obvious fix) would have let a free
  user bypass the free-image lifetime cap entirely by labelling every image
  "video", since the pre-fetch free-image-cap check is ALSO gated on the
  claim and never ran for them.
concept: pro_media_daily_caps
sot_registry_entry: pro_media_daily_caps
writers:
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method: "sendWithMedia — builds media_url from the chat-media upload's signed URL (the honest client); the guard exists for the DISHONEST client, who can send any string" }
  - { file: supabase/functions/ai-media-proxy/index.ts, method: "parseStorageUrl — NOW parses with `new URL()`, checks the prefix on the normalised href, takes bucket/path from `url.pathname` and returns `href`" }
readers:
  - { file: supabase/functions/ai-media-proxy/index.ts, method: "fetchImageAsBase64 — the OI-28 assertions (prefix, ALLOWED_BUCKETS, `${authUserId}/`) over parseStorageUrl's RESOLVED path, then `fetchImpl(parsed.href)` — the same normalised URL the guard saw; the SSRF check is now `if (!parsed) throw ...` alone (BP-1: the earlier raw-string pre-check is deleted)" }
  - { file: supabase/functions/ai-media-proxy/index.ts, method: "handleRequest — after the fetch, `isVideo = mimeType.startsWith(\"video/\")` when it disagrees with the claim; the ONE post-fetch `if (isVideo && !isPro)` paywall (BP-2: the pre-fetch site is deleted); `const proQuotaKey/proCap` derived BELOW that; the consume branch refuses on `proConsumeError || typeof proCount !== \"number\"`" }
  - { file: supabase/functions/ai-media-proxy/index.ts, method: "checkFreeImageQuota (NEW, exported) — the free-image-lifetime-cap check, extracted so it can be called from BOTH sites: pre-fetch (fast path on the honest claim=image) and post-fetch (BP-2's mirror, for a claim=video caller whose served bytes reconcile to an image)" }
hive_key_prefix: "n/a — server-side guard, no Hive surface"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: storage.objects
cloud_columns: [bucket_id, name]
contract_test_path: supabase/functions/ai-media-proxy/index_test.ts, test/contracts/ai_media_proxy_user_scope_test.dart, test/contracts/ai_media_proxy_ssrf_allowlist_test.dart, test/contracts/ai_media_proxy_status_code_classification_test.dart, test/contracts/pro_media_daily_caps_writer_to_reader_test.dart
ist_handling: "n/a — no date logic in the guard; the cap key/cap derivation moved below the fetch but proWindowStart (istDayStartIso) is unchanged and still computed once at function scope"
provider_invalidations: "none — no client change; a traversal attempt now gets the same generic 403 `authorization` that a plain cross-user URL always got"
telemetry_op_types: >
  console.warn when media_type disagrees with Storage's content-type (NEW —
  the only signal that a client is mislabelling media). console.error on the
  fail-closed consume refusal now also fires for a non-numeric RPC result and
  says what shape arrived (`consume_quota returned <json>, expected an int`).
  A traversal attempt logs as the existing 403 line
  (`type=authorization status=403`) — deliberately not distinguished in the
  response (generic 403, never "whose" URL it was).
cross_account_guard: >
  THE guard. authUserId is the verified JWT subject; the path compared
  against it is now the path fetch will request. The property test pins the
  invariant at the fetch seam: for every URL a caller could send, either no
  fetch happens or the fetched pathname sits under
  /storage/v1/object/<access>/<bucket>/<own>/.
forbidden_patterns_checked: >
  `fetch(imageUrl` — absent (the fetch takes parsed.href). `imageUrl.split(`
  / `tail.split("?")` — absent (no raw-string parsing remains). `proCount as
  number` — absent (pinned by T1). `const isVideo` — absent (a const cannot
  be reconciled; pinned). No `throw new Error(` inside fetchImageAsBase64
  (the Bug-913261 scan, its end anchor repointed to `export async function
  handleRequest(`). BP-1: `imageUrl.startsWith(STORAGE_PREFIX)` — exactly
  ONE occurrence remains, inside `parseStorageUrl` itself (on `url.href`),
  not a second raw pre-check. BP-2: `if (isVideo && !isPro)` — exactly ONE
  occurrence (post-fetch only); `if (!isVideo && !isPro)` — exactly TWO
  occurrences (pre-fetch fast path + post-fetch mirror), both calling
  `checkFreeImageQuota` (pinned by count, so a third site or a missing one
  reddens).
proposed_fix: >
  F1: parse with `new URL(imageUrl)` (unparseable → null → 400), require the
  NORMALISED href to start with the Storage prefix, take bucket/path from
  `url.pathname`, and fetch `parsed.href` — guard and request consume one
  value. The three OI-28 assertions and every pinned literal stay where they
  were. `HttpError`, `fetchImageAsBase64` (with an injectable `fetchImpl`)
  and the handler (`handleRequest`, `serve` under `import.meta.main` — the
  guard founder-digest already boots through) are exported so a Deno test
  can drive the real function without a network or a server. F2: after the
  fetch, `isVideo` becomes Storage's answer when the claim disagrees (warn
  logged), the free-tier paywall is re-checked, and ONLY THEN are
  proQuotaKey/proCap derived — the cap describes the same bytes the model
  is told about; both paywall sites share one helper. F3: the refusal
  condition is `proConsumeError || typeof proCount !== "number"`; the
  success arm assigns the bare value. BP-1: delete the raw-string SSRF
  pre-check; `parseStorageUrl` returning `null` already covers "not a
  Storage URL", correctly (origin-normalised). BP-2: extract the free-image
  cap check into `checkFreeImageQuota` (exported); delete the pre-fetch
  video paywall entirely (it trusted the unverified claim — the exact class
  the served-MIME reconciliation exists to close); call
  `checkFreeImageQuota` from BOTH the existing pre-fetch site (unchanged
  trigger, fast path) and a NEW post-fetch site (mirrors the video-paywall
  reconciliation, so a claim=video/served=image free caller is checked
  against the cap instead of silently bypassing it).
regression_test_planned: >
  supabase/functions/ai-media-proxy/index_test.ts (16 Deno tests, NEW):
  parseStorageUrl resolves `..`/`%2e%2e`/`.%2e`/`%2e.`/`%2E%2E`/backslash
  before reading the path, returns null once the dots leave Storage, keeps
  `..%2f` literal; fetchImageAsBase64 refuses each traversal with 403 and
  the out-of-Storage one with 400 WITHOUT calling fetch, still refuses a
  plain cross-user path / a non-boundary prefix / a foreign bucket / a
  foreign origin, fetches the caller's own object exactly once at the
  normalised href with the service-role headers, and a PROPERTY over ten
  attempts asserts every fetch that happens is under the caller's folder
  (with a positive control that at least four were fetched); handleRequest
  answers OPTIONS/GET/no-auth without a server. Dart:
  pro_media_daily_caps_writer_to_reader_test.dart +2 (the served-MIME
  reconciliation sits after the fetch and before the key/cap derivation,
  which exists exactly once; both paywall sites, one helper) and the consume
  refusal anchor repointed to the two-part condition with the shape-drift
  message and the absent cast pinned;
  ai_media_proxy_status_code_classification_test.dart's region end anchor
  repointed to the named handler export. BP-1: index_test.ts +1 (an
  uppercase host and an explicit `:443` port must now be FETCHED, not
  rejected). BP-2: index_test.ts +4 (checkFreeImageQuota, exported: fail-
  closed on an unreadable ledger with no log row; an absent row grants;
  at-ceiling refuses with the honest count; under-ceiling proceeds — a real
  fake `usage_counters` + `ai_coach_interactions` client, not a source-grep);
  pro_media_daily_caps_writer_to_reader_test.dart's two Hermes-F2 tests
  REWRITTEN (the video paywall now has exactly ONE site; the free-image
  check now has exactly TWO, both delegating to the one helper). Mutation-
  proven — see the body.
touched_layers_checked:
  - { tier: 1, name: client_code, status: verified, evidence: "No lib/ change. sendWithMedia builds media_url from createSignedUrl on the caller's own chat-media path — the honest client never traverses; the fix is for the dishonest one." }
  - { tier: 2, name: hive, status: not_applicable, evidence: "Server-side guard." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change. storage.objects keys are literal strings (no server-side dot resolution), which is why `..%2f` stays harmless once the request is confined to /storage/v1/object/." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Live 2026-09-13: 22 users, 29 alerts rows, usage_counters holds chat_app rows only. No evidence of exploitation was sought in Storage access logs — none are retained beyond the edge logs' window and the probe URL shape is indistinguishable from a 403 there; the window of exposure (OI-28's fix 2026-05-17 → v25) is stated, not measured." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_deploy, status: fixed_in_this_batch, evidence: "ai-media-proxy DEPLOYED as v25 on 2026-09-13 (verify_jwt=true, unchanged) from the worktree bytes on the founder's 2026-09-12 pre-authorization; decoded multipart /body sha256 of index.ts equals the git blob (deploy-rollback skill 6.9); anon-Bearer probe → the module's own 401; real-user-token smoke → the module's own 400 (skill 6.7); a real-user traversal probe against v25 → 403 authorization with no bytes. v25 carries F1/F2/F3 only — BP-1/BP-2 (this same function, B-pass 2026-09-13) are fixed in source but NOT in v25; v26 is the immediate next step and this line is updated with ITS OWN byte-identity + probe evidence once it actually deploys, never described ahead of it. Evidence in docs/audit/oi153-pro-media-caps.closure.yaml OI153-DEPLOY-1." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "Client-invoked function." }
  - { tier: 8, name: rls_policies, status: verified, evidence: "Storage RLS is `(storage.foldername(name))[1] = auth.uid()::text` on the three buckets — irrelevant to the service-role fetch, which is exactly why application code is the only guard (OI-28's premise, unchanged)." }
  - { tier: 9, name: storage, status: fixed_in_this_batch, evidence: "The user-scope assertion now runs over the resolved pathname; the fetch uses the same normalised href. The property test pins the fetch seam." }
  - { tier: 10, name: secrets, status: verified, evidence: "The service-role key is still sent only to this project's origin — the normalised-href prefix check is what guarantees the origin, and the Deno test asserts the headers reach only the caller's own object." }
  - { tier: 11, name: external_services, status: verified, evidence: "Gemini receives the caller's own bytes only; with F2 the MIME it is told and the cap charged now agree." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Response shapes unchanged: 403 authorization (existing), 400 validation (existing), the paywall 200 (existing, now also reachable after the fetch). The success body is unchanged." }
impact_analysis: >
  BEFORE: any authenticated user could read any other user's chat-media /
  coach-media / progress-photos object through the proxy (the bytes went to
  Gemini and the model's description came back as the reply), and could
  point the service-role fetch at PostgREST or GoTrue admin endpoints on
  this project — a P0 by the L23 rubric, live since 2026-05-17. AFTER: the
  guard and the request see one URL; every traversal spelling the WHATWG
  parser knows is refused before any fetch, and a URL that resolves outside
  /storage/v1/object/ is not a Storage URL at all. The honest client is
  unaffected (a clean URL normalises to itself — pinned). Residuals, stated:
  the reconciliation trusts Storage's content-type, which the uploader sets —
  a video uploaded AS image/jpeg reaches Gemini as image/jpeg with video
  bytes and is refused by the model, so the mislabel buys nothing, but the
  proxy does not sniff magic bytes; and the exposure window is bounded by
  dates, not by an access-log census (tier 4).
---

# c7e2a4 — the user-scope guard read the URL as SENT; fetch requests it as RESOLVED

Found by the Hermes L23 lens (service-role authz defence-in-depth) on the
`oi153-pro-media-caps` batch, 2026-09-13 — a pre-existing defect in the file
the batch was already redeploying. Not a recurrence of a diagnosed class
(`docs/diagnoses/INDEX.md` has no traversal / dot-segment entry; OI-28 is the
precedent and is CLOSED), but a clean instance of two recorded feedback
classes: *checked one map, reasoned about another* — the guard validated the
string, the consumer used the parsed URL — and *guard without its mirror* —
OI-28 asked "does the path start with the caller's folder" and never asked
"is the path the one that will be fetched".

## Reproduction

```ts
const u = `${BASE}authenticated/chat-media/${own}/../${victim}/x.jpg`;
u.startsWith(BASE)                          // true  — the raw prefix check
u.substring(BASE.length).split("/").slice(2).join("/").startsWith(`${own}/`)
                                            // true  — the OI-28 assertion
new URL(new Request(u).url).pathname
// "/storage/v1/object/authenticated/chat-media/<victim>/x.jpg" — what fetch sends
```

`%2e%2e`, `.%2e` and `%2e.` behave identically; six `..` yield
`/rest/v1/users`. The probe is `index_test.ts`'s
"enough dot-segments to leave /storage/v1/object/" test, kept as a test so it
can never be forgotten.

## Why the fix is where it is

The guard could have rejected `..` textually. It does not, because a textual
denylist is bounded by what its author can spell (`%2E%2E`? `.%2e`? a
backslash?), while the parser the runtime uses is the definition. So the fix
parses with the same parser and reads the same output: `parseStorageUrl`
returns `href`, and `fetchImageAsBase64` fetches THAT. Guard and request
cannot diverge because there is one value.

`..%2f` is left alone deliberately: to the parser it is one opaque segment,
so the request stays under `/storage/v1/object/…/<own>/`; Storage looks keys
up literally, so the object cannot exist. The test pins that it is NOT
resolved, so nobody "fixes" it into a resolution the runtime does not do.

## F2 and F3 — the same function, the same lens, the same deploy

**F2.** `isVideo` chose the cap key, the cap and the free-tier paywall from
the request body, while the bytes were typed by Storage's `content-type`
(the MIME Gemini is told). The fix makes the cap describe the bytes: after
the fetch, the served type wins, the paywall is re-checked, and only then are
the key and cap derived. Both directions are re-typed — an image labelled
"video" is charged as an image too — because "the cap and the model agree"
is the invariant, not "the client is protected from itself". The residual is
stated in the frontmatter: the content-type is the uploader's; a lie there
reaches Gemini as a lie and is refused by the model, so it buys nothing, but
the proxy does not sniff.

**F3.** `proCount as number` on a `null` read as "granted". The refusal
condition is now the error OR a non-number, and the log line says what shape
arrived so a drift is diagnosable without a redeploy.

## Mutation proof (rule 21)

Each mutation was applied to a copy, the target test run, and the file
restored byte-identically (sha256 equal to the saved v25; the restored run is
16/16 Deno, 18/18 Dart). Every mutated file type-checks — semantically wrong,
never a compile error.

| # | Mutation | Reddened |
|---|---|---|
| M1 | restore the EXACT pre-fix `parseStorageUrl` body (raw-string split, `href: imageUrl`) | Deno: **6 / 16** (both dot-segment tests, backslash, both traversal-refusal tests, the property) |
| M2 | keep the normalised guard, fetch the RAW `imageUrl` | Deno: **0 / 16** — expected and explained below |
| M3 | delete `isVideo = servedAsVideo` (the warn stays) | Dart T1: 1 |
| M4 | move the key/cap derivation back ABOVE the fetch (the pre-fix placement) | Dart T1: 2 |
| M5 | drop the `typeof proCount !== "number"` half of the refusal | Dart T1: 1 |

**M2 reddens nothing, and that is the correct result, not a gap.** With the
guard reading the resolved path, every traversal is refused BEFORE any fetch;
a raw fetch can differ from the href fetch only on URLs that passed the
guard, and for those `new URL(raw).href === parsed.href` by construction —
the property test normalises the recorded URL with the same parser. So
"fetch the href" is a consistency measure that removes the second
representation, not the fix; the fix is M1's leg. Stated here so the
zero-red run is read as "absorbed by design" rather than "covered elsewhere"
(rule 21's third trap).

## Live verification (v25)

Recorded in `docs/audit/oi153-pro-media-caps.closure.yaml` (OI153-DEPLOY-1):
byte-identity of the deployed `index.ts` to the git blob; the anon-Bearer and
real-user smokes; and a real-user traversal probe
(`…/chat-media/<own>/../<other>/x.jpg`) answered by v25 with the generic
403 `authorization` and no bytes.
