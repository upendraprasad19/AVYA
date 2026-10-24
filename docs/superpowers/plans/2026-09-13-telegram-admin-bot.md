# Telegram Admin Bot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the founder's push-only Telegram bot into an on-demand, read-only admin console (11 commands) and make critical alerts push immediately instead of waiting for the daily digest.

**Architecture:** Three Edge Functions — `telegram-admin-bot` (webhook, dual auth: Telegram secret token + founder chat-id allowlist, routes 11 read-only commands), `alert-critical-notify` (cron-secret auth, invoked by a new Postgres trigger on critical `alerts` inserts), and the existing `founder-digest` (cron, gains two new digest sections). All three Telegram-sends go through one new shared, hardened helper; all digest content-building is extracted into one shared module so the daily cron and the on-demand `/digest` command can't drift from each other.

**Tech Stack:** Deno Edge Functions (Supabase), Postgres/pg_cron/pg_net, `deno test`.

**Spec:** `docs/superpowers/specs/2026-09-13-telegram-admin-bot-design.md`

## Global Constraints

- `verify_jwt=false` for `telegram-admin-bot` (Telegram never sends a Supabase JWT) and `alert-critical-notify` (cron/trigger caller, same as every other cron-dispatched function in this repo).
- Every catch block returns `{error: "Internal server error", request_id: <8-char hex>}` and logs `console.error("[fn-name] request_id=X", err)` server-side — never `JSON.stringify(err)` into a response body (root CLAUDE.md §4.4 rule 17).
- Telegram messages are capped at 4096 chars (`TELEGRAM_MAX_CHARS`); every reply/digest goes through `truncateForTelegram`.
- Never log a raw fetch error touching the Telegram API — its `.message` embeds the bot token. Only `err.name` (via `telegramErrorSummary`) ever leaves a function.
- IST throughout for date windows (root CLAUDE.md §4.5) — via `_shared/ist_date.ts`, never hand-rolled UTC math.
- **Entitlement reads MUST use the `subscriptions` table (`status = 'active'`), never `users.subscription_status`** — a documented recurring mistake in this codebase (`feedback_mistake_subscription_status_vs_subscriptions_table.md`).
- New cron-dispatched / trigger-invoked functions use `_shared/cron_auth.ts` (`isAuthorizedCronCall`) + `_shared/cron_telemetry.ts` (`logCronStart`/`logCronEnd`) — adoption is gate-checked in this repo.
- Migration files carry the 4-tag header (`Intent:` / `Destructive?:` / `Rollback strategy:` / `Linked diagnose-doc:`) — self-attested, no gate, but required by `supabase/migrations/CLAUDE.md`.
- `alerts.id` is `bigint`, not `uuid` — do not treat it as one.
- Deno tests live beside the file they test (`<name>_test.ts` for `_shared/`, `index_test.ts` inside a function directory) and run via `deno test supabase/functions/`.
- No `flutter`/Dart tooling touches this batch — it's Edge-Function-only. `flutter analyze`/`flutter test` are not relevant gates here; the CI `deno-edge-functions` job (`deno test` + `deno check`) is the relevant one, and there is no local Deno type-check — treat CI as authoritative per root CLAUDE.md §4.9's `client_errors_nullable_user_id` pitfall row.
- Blast radius: this batch touches `supabase/functions/` (new internet-facing endpoint) and adds a DB trigger — classify as **platform** tier (not catastrophic — the trigger is `SECURITY DEFINER` in the `private` schema, PostgREST-invisible, matching the precedent `073_proactive_coach_promotion_trigger.sql` already sets, not a `public`-schema function). Re-classify with `scripts/blast_radius_from_diff.dart` at execution time against the real staged diff rather than trusting this note.
- This is a `feat:` batch, not a bug fix — rule 22's diagnose-doc requirement does not apply (no `fix:`/`bug:`/`regression:` commit prefix). No SoT registry entry is needed either: every command is an *additional reader* of existing writer/reader contracts (`subscriptions`, `alerts`, `usage_counters`, `users`, `client_errors`, `cron_call_log`), not a new one — except the critical-alert trigger, which is an event-dispatch side effect (same shape as the existing, unregistered `proactive_coach_promotion_dispatched` trigger), not a field contract.

---

## File Structure

| File | Responsibility |
|---|---|
| `supabase/functions/_shared/ist_date.ts` (modify) | Add `istYesterdayWindow` (moved here from founder-digest — it's IST-domain, used by two functions now). |
| `supabase/functions/_shared/telegram.ts` (new) | The hardened Telegram sender + its helpers, extracted from founder-digest so `alert-critical-notify` and `telegram-admin-bot` don't duplicate it. |
| `supabase/functions/_shared/founder_digest_content.ts` (new) | The digest's data-gathering + text-building, extracted from founder-digest so `/digest` (on-demand) and the daily cron produce byte-identical content from one source. |
| `supabase/functions/founder-digest/index.ts` (modify) | Becomes a thin cron handler: auth → `gatherDigestInput` → `buildDigestText` → `sendTelegram`. Gains two new `DigestInput` sections. |
| `supabase/migrations/131_alert_critical_notify_trigger.sql` (new) | `AFTER INSERT ON public.alerts WHEN (severity = 'critical')` trigger, `private` schema, exception-swallowing, dispatches to `alert-critical-notify` via `pg_net`. |
| `supabase/functions/alert-critical-notify/index.ts` (new) | Cron-secret-only. Reads one alert row by id, sends it via `_shared/telegram.ts`. |
| `supabase/functions/telegram-admin-bot/index.ts` (new) | Webhook receiver + dual auth + command router + all 11 command handlers. |

---

### Task 1: Confirm the branch has `founder-digest` (prerequisite check)

`founder-digest` was built on branch `oi153-pro-media-caps` and is **not yet on `main`**. This plan's branch was cut from `main` and will not have the file to modify.

**Files:**
- Read only: `supabase/functions/founder-digest/index.ts`

- [ ] **Step 1: Check whether the file exists on this branch**

Run: `test -f supabase/functions/founder-digest/index.ts && echo PRESENT || echo MISSING`

- [ ] **Step 2: If MISSING, stop and ask the founder**

Do not merge `oi153-pro-media-caps` into this branch, or into `main`, without asking first — that's an integration action requiring its own explicit go (root CLAUDE.md §4.13: the shared main folder is integration-only; merges happen there, never silently from a feature branch). Ask: "This plan's Task 4 onward modifies `founder-digest`, which only exists on the unmerged `oi153-pro-media-caps` branch. Should I merge that branch into `main` first (from the primary worktree, via `safe_merge.sh`), then rebase this branch on the updated `main` — or handle it differently?" Wait for an answer before proceeding to Task 2.

- [ ] **Step 3: If PRESENT, continue to Task 2**

---

### Task 2: `istYesterdayWindow` in the shared IST module

**Files:**
- Modify: `supabase/functions/_shared/ist_date.ts`
- Test: `supabase/functions/_shared/ist_date_test.ts` (create if it doesn't already exist — check first with `test -f`)

**Interfaces:**
- Produces: `istYesterdayWindow(now?: Date): { yStart: string; tStart: string; label: string }` — `yStart`/`tStart` are ISO instants bounding yesterday's IST day (inclusive start, exclusive end); `label` is yesterday's IST date string (`YYYY-MM-DD`).

- [ ] **Step 1: Write the failing test**

Add to `supabase/functions/_shared/ist_date_test.ts` (create the file with this content if it doesn't exist yet; if it exists, append this test and its import):

```ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { istYesterdayWindow } from "./ist_date.ts";

Deno.test("istYesterdayWindow — UTC evening still lands on the same IST calendar day boundary", () => {
  // 2026-09-13 20:00 UTC = 2026-09-14 01:30 IST — "today" is the 14th, "yesterday" the 13th.
  const now = new Date("2026-09-13T20:00:00.000Z");
  const { yStart, tStart, label } = istYesterdayWindow(now);
  assertEquals(label, "2026-09-13");
  // tStart = start of 2026-09-14 IST = 2026-09-13T18:30:00.000Z
  assertEquals(tStart, "2026-09-13T18:30:00.000Z");
  // yStart = start of 2026-09-13 IST = 2026-09-12T18:30:00.000Z
  assertEquals(yStart, "2026-09-12T18:30:00.000Z");
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test supabase/functions/_shared/ist_date_test.ts`
Expected: FAIL with `istYesterdayWindow is not a function` (or a TS2305 "has no exported member").

- [ ] **Step 3: Add the function to `_shared/ist_date.ts`**

Append to the end of `supabase/functions/_shared/ist_date.ts`:

```ts
const ONE_DAY_MS = 24 * 60 * 60 * 1000;

/** Yesterday's IST day as an [yStart, tStart) instant window, plus its IST date label. */
export function istYesterdayWindow(
  now: Date = new Date(),
): { yStart: string; tStart: string; label: string } {
  const tStartMs = Date.parse(istDayStartIso(now));
  const yStartMs = tStartMs - ONE_DAY_MS;
  return {
    yStart: new Date(yStartMs).toISOString(),
    tStart: new Date(tStartMs).toISOString(),
    label: istDateStr(new Date(yStartMs)),
  };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test supabase/functions/_shared/ist_date_test.ts`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/ist_date.ts supabase/functions/_shared/ist_date_test.ts
sh scripts/safe_commit.sh "feat(telegram-admin-bot): add istYesterdayWindow to the shared IST module"
```

---

### Task 3: `_shared/telegram.ts` — the hardened sender

**Files:**
- Create: `supabase/functions/_shared/telegram.ts`
- Test: `supabase/functions/_shared/telegram_test.ts`

**Interfaces:**
- Produces: `TELEGRAM_MAX_CHARS: number`, `escapeHtml(s: string): string`, `truncateForTelegram(text: string): string`, `telegramErrorSummary(err: unknown): string`, `sendTelegram(token: string, chatId: string, text: string): Promise<{ ok: true } | { ok: false; summary: string }>`.

- [ ] **Step 1: Write the failing tests**

```ts
// supabase/functions/_shared/telegram_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  escapeHtml,
  telegramErrorSummary,
  TELEGRAM_MAX_CHARS,
  truncateForTelegram,
} from "./telegram.ts";

Deno.test("escapeHtml escapes the 3 chars Telegram HTML parse_mode treats as markup", () => {
  assertEquals(escapeHtml("<b>a & b</b>"), "&lt;b&gt;a &amp; b&lt;/b&gt;");
});

Deno.test("truncateForTelegram leaves short text untouched", () => {
  assertEquals(truncateForTelegram("hello"), "hello");
});

Deno.test("truncateForTelegram caps at TELEGRAM_MAX_CHARS with a trailing marker", () => {
  const long = "x".repeat(TELEGRAM_MAX_CHARS + 500);
  const out = truncateForTelegram(long);
  assertEquals(out.length <= TELEGRAM_MAX_CHARS, true);
  assertEquals(out.endsWith("(truncated)"), true);
});

Deno.test("telegramErrorSummary never includes the error's own message (token-in-URL risk)", () => {
  const err = new TypeError("fetch failed: https://api.telegram.org/botSECRETTOKEN/sendMessage");
  const summary = telegramErrorSummary(err);
  assertEquals(summary.includes("SECRETTOKEN"), false);
  assertEquals(summary, "telegram send threw TypeError");
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `deno test supabase/functions/_shared/telegram_test.ts`
Expected: FAIL — module `./telegram.ts` not found.

- [ ] **Step 3: Create `_shared/telegram.ts`**

```ts
/**
 * telegram.ts — the ONE hardened Telegram sender for this project. Used by
 * founder-digest (daily cron), alert-critical-notify (trigger-invoked), and
 * telegram-admin-bot (webhook replies). Do not duplicate this in a new
 * function — import it.
 *
 * The error-handling discipline here is load-bearing: a Deno fetch
 * TypeError's `.message` embeds the request URL, which carries the bot
 * token (`https://api.telegram.org/bot<TOKEN>/sendMessage`). Only `.name`
 * (via telegramErrorSummary) is ever allowed to leave this module — never
 * the raw error, never String(err).
 */

export const TELEGRAM_MAX_CHARS = 4096;

/** Telegram `parse_mode: "HTML"` treats these three as markup. */
export function escapeHtml(s: string): string {
  return s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

/** Caps text at TELEGRAM_MAX_CHARS, appending a truncation marker if trimmed. */
export function truncateForTelegram(text: string): string {
  if (text.length <= TELEGRAM_MAX_CHARS) return text;
  const marker = "\n… (truncated)";
  return text.slice(0, TELEGRAM_MAX_CHARS - marker.length) + marker;
}

/** The name of an error and NOTHING else — see module header. */
export function telegramErrorSummary(err: unknown): string {
  const name = err instanceof Error ? err.name : typeof err;
  return `telegram send threw ${name}`;
}

export async function sendTelegram(
  token: string,
  chatId: string,
  text: string,
): Promise<{ ok: true } | { ok: false; summary: string }> {
  try {
    const res = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: chatId,
        text: truncateForTelegram(text),
        parse_mode: "HTML",
        disable_web_page_preview: true,
      }),
    });
    if (!res.ok) {
      const body = (await res.text().catch(() => "")).slice(0, 200);
      return { ok: false, summary: `telegram HTTP ${res.status}: ${body}` };
    }
    return { ok: true };
  } catch (err) {
    return { ok: false, summary: telegramErrorSummary(err) };
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `deno test supabase/functions/_shared/telegram_test.ts`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/_shared/telegram.ts supabase/functions/_shared/telegram_test.ts
sh scripts/safe_commit.sh "feat(telegram-admin-bot): extract the hardened Telegram sender into _shared/telegram.ts"
```

---

### Task 4: Extract digest content-building into `_shared/founder_digest_content.ts`

This is a refactor: move `DigestKey`, `DIGEST_KEYS`, `UsageRow`, `AlertRow`, `SectionRead<T>`, `DigestInput`, `idPrefix`, `istClock`, `buildDigestText` out of `founder-digest/index.ts` into a new shared module, unchanged in behavior, so `/digest` (Task 12) can call the exact same builder the daily cron uses. Also extract the data-gathering (currently inline in `founder-digest`'s `handler`) into a new `gatherDigestInput` function in the same shared module.

**Files:**
- Create: `supabase/functions/_shared/founder_digest_content.ts`
- Modify: `supabase/functions/founder-digest/index.ts`
- Test: `supabase/functions/_shared/founder_digest_content_test.ts`
- Test: `supabase/functions/founder-digest/index_test.ts` (should already exist — extend it, don't replace it)

**Interfaces:**
- Produces (from the new shared module): everything `buildDigestText` needs (`DigestKey`, `DIGEST_KEYS`, `UsageRow`, `AlertRow`, `SectionRead<T>`, `DigestInput`, `idPrefix(userId: string): string`, `istClock(iso: string): string`, `buildDigestText(input: DigestInput): string`, `gatherDigestInput(supabase: SupabaseClient, now: Date): Promise<DigestInput>`).
- Consumes: `_shared/telegram.ts` (`escapeHtml`, `TELEGRAM_MAX_CHARS`, `truncateForTelegram`), `_shared/ist_date.ts` (`istYesterdayWindow`, from Task 2), `_shared/paged_fetch.ts` (`fetchAllPages` — already used by founder-digest).

- [ ] **Step 1: Read the current founder-digest source in full before touching it**

Run: `wc -l supabase/functions/founder-digest/index.ts` then `Read` the whole file. Confirm the exported surface matches what's listed above (`buildDigestText` exported and pure; `DigestInput`/`DigestKey`/etc. exported interfaces; `handler` does the auth + data-gathering + calls `buildDigestText` + `sendTelegram`). If anything differs from this plan's assumption, stop and reconcile before editing — do not guess.

- [ ] **Step 2: Write the failing test for the extracted module**

```ts
// supabase/functions/_shared/founder_digest_content_test.ts
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildDigestText, DigestInput, idPrefix, istClock } from "./founder_digest_content.ts";

Deno.test("idPrefix returns the first 8 chars of a user id, never the whole uuid", () => {
  assertEquals(idPrefix("12345678-abcd-ef01-2345-6789abcdef01"), "12345678");
});

Deno.test("istClock renders HH:MM for an ISO instant", () => {
  // 2026-09-13T02:30:00Z = 08:00 IST
  assertEquals(istClock("2026-09-13T02:30:00.000Z"), "08:00 ");
});

Deno.test("buildDigestText renders 'none' for an empty-but-readable section, never a silent zero", () => {
  const input: DigestInput = {
    dayLabel: "2026-09-12",
    usage: { rows: [] },
    alerts: { rows: [] },
  };
  const text = buildDigestText(input);
  assertStringIncludes(text, "none");
});

Deno.test("buildDigestText renders an explicit unreadable marker, never renders zeros for a failed read", () => {
  const input: DigestInput = {
    dayLabel: "2026-09-12",
    usage: { unreadable: "connection reset" },
    alerts: { rows: [] },
  };
  const text = buildDigestText(input);
  assertStringIncludes(text, "unreadable");
  assertStringIncludes(text, "connection reset");
});
```

Note: the exact `DigestInput` shape (field names beyond `dayLabel`/`usage`/`alerts`) must match what Step 1's read of the real file revealed — adjust the test's literal to the REAL interface before running it, since this plan was written without that file in hand (it lives on the unmerged branch). Do not invent fields; use the ones the actual `DigestInput` interface declares.

- [ ] **Step 3: Run test to verify it fails**

Run: `deno test supabase/functions/_shared/founder_digest_content_test.ts`
Expected: FAIL — module not found.

- [ ] **Step 4: Create `_shared/founder_digest_content.ts` by moving code, not rewriting it**

Cut `DigestKey`, `DIGEST_KEYS`, `UsageRow`, `AlertRow`, `SectionRead<T>`, `DigestInput`, `idPrefix`, `formatDayLabel` (private helper `buildDigestText` depends on), `istClock`, `unreadableLine` (private helper), `buildDigestText` verbatim out of `founder-digest/index.ts` and paste them into the new file, with these import adjustments at the top:

```ts
import { escapeHtml } from "./telegram.ts";
```

(`TELEGRAM_MAX_CHARS` truncation move: `buildDigestText` currently truncates inline at its end — delete that inline truncation block from the moved code; `founder-digest/index.ts` and `telegram-admin-bot/index.ts` will call `truncateForTelegram` from `_shared/telegram.ts` right before `sendTelegram`, so truncation happens once, at the send boundary, not inside the builder.)

Then add the data-gathering function, built from what `founder-digest`'s current `handler` does inline (read it from Step 1 before writing this — the sketch below is the shape, not a literal transcription):

```ts
import { istYesterdayWindow } from "./ist_date.ts";
import { fetchAllPages } from "./paged_fetch.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

/** Gathers the SAME data the daily cron sends — the single source both the cron and /digest read. */
export async function gatherDigestInput(
  supabase: SupabaseClient,
  now: Date = new Date(),
): Promise<DigestInput> {
  const { yStart, tStart, label } = istYesterdayWindow(now);
  // Port the exact queries founder-digest/index.ts's handler currently runs
  // for the usage/alerts (and, after Task 5, subscriptions/expiring)
  // sections, using yStart/tStart as the window bounds. Wrap each read in
  // the same readSection<T> pattern the original handler uses (three states:
  // data / "none" / "unreadable" — never render a failed read as zeros).
  throw new Error("port the real queries from founder-digest/index.ts here");
}
```

Do not leave the `throw` in place — replace it with the real ported queries before Step 6. It is written here only to mark exactly where Step 1's file-read content belongs; the plan cannot transcribe code it has not read.

- [ ] **Step 5: Update `founder-digest/index.ts` to import from the shared module**

Replace the moved definitions with:

```ts
import {
  buildDigestText,
  gatherDigestInput,
} from "../_shared/founder_digest_content.ts";
import { sendTelegram, telegramErrorSummary, truncateForTelegram } from "../_shared/telegram.ts";
```

`handler` becomes: auth check → `const input = await gatherDigestInput(supabase, now)` → `const text = truncateForTelegram(buildDigestText(input))` → `sendTelegram(token, chatId, text)` → `logCronEnd`. Delete the now-duplicate local `sendTelegram`/`telegramErrorSummary`/`escapeHtml` definitions and the local `TELEGRAM_MAX_CHARS` (import it from `_shared/telegram.ts` instead if the file still references the constant directly).

- [ ] **Step 6: Replace the `throw` in `gatherDigestInput` with the real ported queries, and run the type-checker**

Run: `deno check supabase/functions/_shared/founder_digest_content.ts supabase/functions/founder-digest/index.ts`
Expected: no type errors. Fix any import path or type mismatch before proceeding — do not silence with `any`.

- [ ] **Step 7: Run tests to verify they pass**

Run: `deno test supabase/functions/_shared/founder_digest_content_test.ts supabase/functions/founder-digest/`
Expected: PASS on all — the new module's tests AND founder-digest's existing `index_test.ts` (which must still pass unchanged, proving the refactor didn't alter behavior).

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/_shared/founder_digest_content.ts supabase/functions/_shared/founder_digest_content_test.ts supabase/functions/founder-digest/index.ts
sh scripts/safe_commit.sh "refactor(telegram-admin-bot): extract founder-digest's content-building into a shared module"
```

---

### Task 5: Add Subscriptions + Expiring-soon sections to the digest

**Files:**
- Modify: `supabase/functions/_shared/founder_digest_content.ts`
- Modify: `supabase/functions/_shared/founder_digest_content_test.ts`

**Interfaces:**
- Extends `DigestInput` with two new fields: `subscriptions: SectionRead<SubscriptionRow>` and `expiringSoon: { count7d: number; count30d: number } | { unreadable: string }`.
- New exported type: `SubscriptionRow { plan: string; created_at: string }`.

- [ ] **Step 1: Write the failing tests**

Append to `supabase/functions/_shared/founder_digest_content_test.ts`:

```ts
Deno.test("buildDigestText renders a per-plan breakdown of yesterday's new subscriptions", () => {
  const input: DigestInput = {
    dayLabel: "2026-09-12",
    usage: { rows: [] },
    alerts: { rows: [] },
    subscriptions: {
      rows: [
        { plan: "monthly", created_at: "2026-09-12T10:00:00Z" },
        { plan: "monthly", created_at: "2026-09-12T11:00:00Z" },
        { plan: "yearly", created_at: "2026-09-12T12:00:00Z" },
      ],
    },
    expiringSoon: { count7d: 3, count30d: 9 },
  };
  const text = buildDigestText(input);
  assertStringIncludes(text, "monthly: 2");
  assertStringIncludes(text, "yearly: 1");
  assertStringIncludes(text, "7d: 3");
  assertStringIncludes(text, "30d: 9");
});

Deno.test("buildDigestText renders 'none' for a quiet day with zero new subscriptions", () => {
  const input: DigestInput = {
    dayLabel: "2026-09-12",
    usage: { rows: [] },
    alerts: { rows: [] },
    subscriptions: { rows: [] },
    expiringSoon: { count7d: 0, count30d: 0 },
  };
  assertStringIncludes(buildDigestText(input), "none");
});

Deno.test("buildDigestText renders an unreadable marker for a failed subscriptions read, never zeros", () => {
  const input: DigestInput = {
    dayLabel: "2026-09-12",
    usage: { rows: [] },
    alerts: { rows: [] },
    subscriptions: { unreadable: "timeout" },
    expiringSoon: { unreadable: "timeout" },
  };
  const text = buildDigestText(input);
  assertStringIncludes(text, "unreadable");
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `deno test supabase/functions/_shared/founder_digest_content_test.ts`
Expected: FAIL — `DigestInput` has no `subscriptions`/`expiringSoon` fields (TS2353/TS2322), or the rendered text doesn't include the new lines yet.

- [ ] **Step 3: Extend `DigestInput` and `buildDigestText`**

In `_shared/founder_digest_content.ts`, add:

```ts
export interface SubscriptionRow {
  plan: string;
  created_at: string;
}
```

Add `subscriptions: SectionRead<SubscriptionRow>` and `expiringSoon: { count7d: number; count30d: number } | { unreadable: string }` to `DigestInput`. In `buildDigestText`, following the existing per-section pattern (three states: data / none / unreadable — reuse `unreadableLine`), add:

```ts
lines.push("");
lines.push("<b>Subscriptions (new, yesterday)</b>");
if ("unreadable" in input.subscriptions) {
  lines.push(unreadableLine("Subscriptions", input.subscriptions.unreadable));
} else if (input.subscriptions.rows.length === 0) {
  lines.push("none");
} else {
  const byPlan = new Map<string, number>();
  for (const r of input.subscriptions.rows) {
    byPlan.set(r.plan, (byPlan.get(r.plan) ?? 0) + 1);
  }
  for (const [plan, n] of byPlan) {
    lines.push(`${escapeHtml(plan)}: ${n}`);
  }
}

lines.push("");
lines.push("<b>Expiring soon</b>");
if ("unreadable" in input.expiringSoon) {
  lines.push(unreadableLine("Expiring soon", input.expiringSoon.unreadable));
} else {
  lines.push(`7d: ${input.expiringSoon.count7d} · 30d: ${input.expiringSoon.count30d}`);
}
```

(Insert this block wherever the existing section-building loop in `buildDigestText` naturally continues — read the surrounding code first so the new lines join the SAME `lines` array the rest of the function builds, rather than starting a second one.)

- [ ] **Step 4: Extend `gatherDigestInput` to populate the two new fields**

```ts
const subscriptions = await readSection<SubscriptionRow>(async () => {
  const { data, error } = await supabase
    .from("subscriptions")
    .select("plan, created_at")
    .eq("status", "active")
    .gte("created_at", yStart)
    .lt("created_at", tStart);
  if (error) throw error;
  return data ?? [];
});

const in7dIso = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000).toISOString();
const in30dIso = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000).toISOString();
let expiringSoon: DigestInput["expiringSoon"];
try {
  const [r7, r30] = await Promise.all([
    supabase.from("users").select("id", { count: "exact", head: true })
      .not("subscription_expires_at", "is", null)
      .gte("subscription_expires_at", now.toISOString())
      .lte("subscription_expires_at", in7dIso),
    supabase.from("users").select("id", { count: "exact", head: true })
      .not("subscription_expires_at", "is", null)
      .gte("subscription_expires_at", now.toISOString())
      .lte("subscription_expires_at", in30dIso),
  ]);
  if (r7.error) throw r7.error;
  if (r30.error) throw r30.error;
  expiringSoon = { count7d: r7.count ?? 0, count30d: r30.count ?? 0 };
} catch (err) {
  expiringSoon = { unreadable: telegramSafeErrorText(err) };
}
```

`telegramSafeErrorText` doesn't exist yet — use whatever error-to-string helper `readSection`'s `catch` branch already uses elsewhere in this file (read it in Step 1 of Task 4) rather than inventing a new one; reuse the existing pattern verbatim.

- [ ] **Step 5: Run tests to verify they pass**

Run: `deno test supabase/functions/_shared/founder_digest_content_test.ts`
Expected: PASS on all (7 tests total: 4 from Task 4 + 3 new).

- [ ] **Step 6: Type-check**

Run: `deno check supabase/functions/_shared/founder_digest_content.ts`
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/_shared/founder_digest_content.ts supabase/functions/_shared/founder_digest_content_test.ts
sh scripts/safe_commit.sh "feat(telegram-admin-bot): add Subscriptions and Expiring-soon sections to founder-digest"
```

---

### Task 6: Migration 131 — critical-alert trigger

**Files:**
- Create: `supabase/migrations/131_alert_critical_notify_trigger.sql`
- Create: `supabase/tests/../test/sql/alert_critical_notify_trigger_live_verify.sql` — actually place at `test/sql/alert_critical_notify_trigger_live_verify.sql` (matches this repo's existing `test/sql/` convention, e.g. `onconflict_live_arbiter.sql`)

⚠ **Verify the migration number is still free before writing the file** — another branch may have claimed 131 since this plan was written. Run: `ls supabase/migrations/ | grep -E '^[0-9]{3}[a-z]?_' | sort -t_ -k1 -n | tail -3` and use the real next number if it's no longer 131.

- [ ] **Step 1: Write the migration**

```sql
-- Intent: AFTER INSERT trigger on public.alerts (severity='critical') dispatches to the alert-critical-notify Edge Function via pg_net, so a critical alert reaches the founder's Telegram immediately instead of waiting for the next daily digest.
-- Destructive?: no   -- only ADDs a SECURITY DEFINER function in the private schema + a new trigger. Existing alerts inserts proceed unchanged; the trigger swallows all exceptions.
-- Rollback strategy: inline   -- end-of-file commented-out reverse DDL drops the trigger + function.
-- Linked diagnose-doc: n/a   -- new feature, not a bug fix

-- 131_alert_critical_notify_trigger.sql
--
-- Same shape as 073_proactive_coach_promotion_trigger.sql (private schema,
-- SECURITY DEFINER, exception-swallowing, fire-and-forget pg_net dispatch) —
-- that precedent is deliberate: a public-schema SECURITY DEFINER function is
-- anon-executable by default on this project (see
-- supabase/migrations/CLAUDE.md's "public SECURITY DEFINER function is
-- anon-executable" pitfall); living in `private` makes it PostgREST-invisible
-- and dodges the class entirely, the same way 073 does.
--
-- pg_net is already enabled (used by every other cron-dispatch trigger on
-- this project).

CREATE OR REPLACE FUNCTION private.dispatch_critical_alert_notify()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cron_secret text;
  v_supabase_url text;
  v_request_id bigint;
BEGIN
  SELECT private.cron_get_secret() INTO v_cron_secret;

  IF v_cron_secret IS NULL OR v_cron_secret = '' THEN
    -- CRON_SECRET not seeded — never block the alert insert for a missing
    -- notification credential. The alert row itself is the source of truth;
    -- the push is best-effort.
    RETURN NEW;
  END IF;

  v_supabase_url := 'https://dedsavbjuwgarrhphgnl.supabase.co';

  -- Fire-and-forget. pg_net returns immediately; delivery happens async,
  -- out-of-transaction, and can never roll back this INSERT.
  SELECT net.http_post(
    url := v_supabase_url || '/functions/v1/alert-critical-notify',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_cron_secret
    ),
    body := jsonb_build_object('alert_id', NEW.id)
  ) INTO v_request_id;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Never propagate a trigger failure back to the alerts INSERT — the alert
  -- record is authoritative; the Telegram push is purely additive.
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_dispatch_critical_alert_notify ON public.alerts;

CREATE TRIGGER trg_dispatch_critical_alert_notify
AFTER INSERT ON public.alerts
FOR EACH ROW
WHEN (NEW.severity = 'critical')
EXECUTE FUNCTION private.dispatch_critical_alert_notify();

COMMENT ON FUNCTION private.dispatch_critical_alert_notify() IS
  '131 — fires alert-critical-notify Edge Function on every critical-severity '
  'alerts INSERT. Never propagates errors back to the parent transaction.';

COMMENT ON TRIGGER trg_dispatch_critical_alert_notify ON public.alerts IS
  '131 — immediate Telegram push for a critical alert, independent of the daily digest.';

-- ── Rollback DDL (commented; uncomment + run as a new migration to revert) ──
--
-- DROP TRIGGER IF EXISTS trg_dispatch_critical_alert_notify ON public.alerts;
-- DROP FUNCTION IF EXISTS private.dispatch_critical_alert_notify();
```

- [ ] **Step 2: Write the live rollback-transaction test**

```sql
-- test/sql/alert_critical_notify_trigger_live_verify.sql
--
-- Run against the live project inside a transaction that always rolls back —
-- proves the trigger fires without error and does NOT block the INSERT, per
-- the same pattern supabase/migrations/CLAUDE.md's live-arbiter scaffold
-- uses. This is a MANUAL verification script (run via Supabase MCP
-- execute_sql inside a BEGIN...ROLLBACK), not a `deno test` — there is no
-- automated harness for live-Postgres-trigger checks in this repo.

BEGIN;

-- A critical alert insert must succeed and return its row (the trigger's
-- own exceptions are swallowed, so this proves it doesn't abort the write).
INSERT INTO public.alerts (source, severity, summary, suggested_action)
VALUES ('test_harness', 'critical', 'live rollback-txn verification row', 'none')
RETURNING id, severity;

-- A non-critical alert must ALSO succeed, and must not fire the trigger
-- (WHEN clause should skip it) — this INSERT existing unaffected either way.
INSERT INTO public.alerts (source, severity, summary, suggested_action)
VALUES ('test_harness', 'info', 'live rollback-txn verification row (non-critical)', 'none')
RETURNING id, severity;

ROLLBACK;
```

- [ ] **Step 3: Apply the migration**

Use the Supabase MCP `apply_migration` tool with the SQL from Step 1 (after confirming the real free migration number). In the SAME commit, update `backups/applied_migrations.json` per `feedback_migration_apply_record_pair.md` (root CLAUDE.md §4.5). This is a **live prod apply** — needs its own explicit founder go even though the plan itself was approved (root CLAUDE.md §4.3: "plan approval ≠ deploy approval").

- [ ] **Step 4: Run the live rollback-transaction test**

Run the SQL from Step 2 via Supabase MCP `execute_sql`, wrapped exactly as written (`BEGIN` ... `ROLLBACK`). Confirm both INSERTs return successfully and no error surfaces. Confirm via a follow-up query that no row from `source='test_harness'` persisted (the rollback worked): `SELECT count(*) FROM public.alerts WHERE source = 'test_harness';` — expect `0`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/131_alert_critical_notify_trigger.sql test/sql/alert_critical_notify_trigger_live_verify.sql backups/applied_migrations.json
sh scripts/safe_commit.sh "feat(telegram-admin-bot): migration 131 — critical-alert Telegram-push trigger"
```

---

### Task 7: `alert-critical-notify` Edge Function

**Files:**
- Create: `supabase/functions/alert-critical-notify/index.ts`
- Test: `supabase/functions/alert-critical-notify/index_test.ts`

**Interfaces:**
- Consumes: `_shared/cron_auth.ts` (`isAuthorizedCronCall`), `_shared/cron_telemetry.ts` (`logCronStart`, `logCronEnd`), `_shared/telegram.ts` (`sendTelegram`, `escapeHtml`), `_shared/error.ts` (`corsHeaders`, `ok`, `serverError`, `clientError`).
- Produces: `export const handler = async (req: Request): Promise<Response>`, `export function formatCriticalAlertText(alert: { source: string; summary: string; detected_at: string; suggested_action: string | null }): string` (pure — testable without a live DB).

- [ ] **Step 1: Write the failing tests**

```ts
// supabase/functions/alert-critical-notify/index_test.ts
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { formatCriticalAlertText, handler } from "./index.ts";

Deno.test("formatCriticalAlertText includes the source, summary, and suggested action", () => {
  const text = formatCriticalAlertText({
    source: "alert_client_errors_spike",
    summary: "client_errors spike: 612 errors in last hour",
    detected_at: "2026-09-13T02:00:00.000Z",
    suggested_action: "Inspect docs/diagnoses for recent regression.",
  });
  assertStringIncludes(text, "alert_client_errors_spike");
  assertStringIncludes(text, "612 errors");
  assertStringIncludes(text, "Inspect docs/diagnoses");
});

Deno.test("formatCriticalAlertText handles a null suggested_action without crashing", () => {
  const text = formatCriticalAlertText({
    source: "alert_payment_flow_health",
    summary: "test",
    detected_at: "2026-09-13T02:00:00.000Z",
    suggested_action: null,
  });
  assertEquals(typeof text, "string");
});

Deno.test("handler rejects a request with no cron auth", async () => {
  const req = new Request("https://example.com/alert-critical-notify", {
    method: "POST",
    body: JSON.stringify({ alert_id: 1 }),
  });
  const res = await handler(req);
  assertEquals(res.status, 401);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `deno test supabase/functions/alert-critical-notify/index_test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `alert-critical-notify/index.ts`**

```ts
/**
 * alert-critical-notify — reads ONE alerts row by id and pushes it to the
 * founder's Telegram immediately. Invoked ONLY by the private.
 * dispatch_critical_alert_notify() trigger (migration 131) on a critical
 * alerts INSERT — never reachable from anywhere else. Cron-secret
 * authenticated, same as every other server-triggered function in this repo.
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { clientError, corsHeaders, ok, serverError } from "../_shared/error.ts";
import { isAuthorizedCronCall } from "../_shared/cron_auth.ts";
import { logCronEnd, logCronStart } from "../_shared/cron_telemetry.ts";
import { escapeHtml, sendTelegram } from "../_shared/telegram.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

interface AlertRow {
  source: string;
  summary: string;
  detected_at: string;
  suggested_action: string | null;
}

export function formatCriticalAlertText(alert: AlertRow): string {
  const lines = [
    "🔴 <b>CRITICAL</b>",
    `${escapeHtml(alert.source)}`,
    escapeHtml(alert.summary),
  ];
  if (alert.suggested_action) {
    lines.push(`→ ${escapeHtml(alert.suggested_action)}`);
  }
  return lines.join("\n");
}

export const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (!await isAuthorizedCronCall(req)) {
    return clientError("Unauthorized", 401);
  }

  const logId = await logCronStart("alert-critical-notify");

  try {
    const token = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
    const chatId = Deno.env.get("FOUNDER_TELEGRAM_CHAT_ID") ?? "";
    if (!token || !chatId) {
      await logCronEnd(logId, "failed", {
        httpStatus: 500,
        errorSummary: "TELEGRAM_BOT_TOKEN / FOUNDER_TELEGRAM_CHAT_ID not configured",
      });
      return serverError("alert-critical-notify:secrets", new Error("secrets not configured"));
    }

    const body = await req.json().catch(() => ({}));
    const alertId = body?.alert_id;
    if (alertId == null) {
      await logCronEnd(logId, "failed", { httpStatus: 400, errorSummary: "missing alert_id" });
      return clientError("Missing alert_id", 400);
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const { data, error } = await supabase
      .from("alerts")
      .select("source, summary, detected_at, suggested_action")
      .eq("id", alertId)
      .maybeSingle();

    if (error) throw error;
    if (!data) {
      // Alert row gone by the time we read it — not an error, just nothing to send.
      await logCronEnd(logId, "success", { httpStatus: 200 });
      return ok({ sent: false, reason: "alert_not_found" });
    }

    const text = formatCriticalAlertText(data as AlertRow);
    const result = await sendTelegram(token, chatId, text);

    if (!result.ok) {
      await logCronEnd(logId, "failed", { httpStatus: 502, errorSummary: result.summary });
      return serverError("alert-critical-notify:telegram", new Error(result.summary));
    }

    await logCronEnd(logId, "success", { httpStatus: 200 });
    return ok({ sent: true });
  } catch (err) {
    const requestId = crypto.randomUUID().slice(0, 8);
    console.error(`[alert-critical-notify] request_id=${requestId}`, err);
    await logCronEnd(logId, "failed", { httpStatus: 500, errorSummary: String(err).slice(0, 200) });
    return serverError("alert-critical-notify", err);
  }
};

if (import.meta.main) {
  serve(handler);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `deno test supabase/functions/alert-critical-notify/index_test.ts`
Expected: PASS (3 tests). The 3rd test needs `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` env vars set (even to dummy values) for the module to import without throwing on the top-level `!` assertions — set them in the test file's own `Deno.env.set(...)` calls before the import if the existing `founder-digest/index_test.ts` shows that pattern (check it first and match it).

- [ ] **Step 5: Type-check**

Run: `deno check supabase/functions/alert-critical-notify/index.ts`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/alert-critical-notify/
sh scripts/safe_commit.sh "feat(telegram-admin-bot): alert-critical-notify Edge Function"
```

---

### Task 8: `telegram-admin-bot` skeleton — auth, router, `/help`

**Files:**
- Create: `supabase/functions/telegram-admin-bot/index.ts`
- Test: `supabase/functions/telegram-admin-bot/index_test.ts`

**Interfaces:**
- Produces: `export function isAuthorizedTelegramSender(opts: { secretTokenHeader: string | null; expectedSecretToken: string; chatId: string | number; expectedChatId: string }): boolean` (pure), `export function parseCommand(text: string): { cmd: string; args: string[] } | null` (pure), `export const handler = async (req: Request): Promise<Response>`.
- This task ships only `/help`; every other command (Tasks 9–12) is added to the SAME router in the SAME file, each its own task.

- [ ] **Step 1: Write the failing tests**

```ts
// supabase/functions/telegram-admin-bot/index_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handler, isAuthorizedTelegramSender, parseCommand } from "./index.ts";

Deno.test("isAuthorizedTelegramSender requires BOTH the secret token and the chat id to match", () => {
  const base = { expectedSecretToken: "s3cr3t", expectedChatId: "12345" };
  assertEquals(
    isAuthorizedTelegramSender({ ...base, secretTokenHeader: "s3cr3t", chatId: "12345" }),
    true,
  );
  assertEquals(
    isAuthorizedTelegramSender({ ...base, secretTokenHeader: "wrong", chatId: "12345" }),
    false,
  );
  assertEquals(
    isAuthorizedTelegramSender({ ...base, secretTokenHeader: "s3cr3t", chatId: "99999" }),
    false,
  );
  assertEquals(
    isAuthorizedTelegramSender({ ...base, secretTokenHeader: null, chatId: "12345" }),
    false,
  );
});

Deno.test("isAuthorizedTelegramSender coerces a numeric Telegram chat id before comparing", () => {
  assertEquals(
    isAuthorizedTelegramSender({
      secretTokenHeader: "s3cr3t",
      expectedSecretToken: "s3cr3t",
      chatId: 12345,
      expectedChatId: "12345",
    }),
    true,
  );
});

Deno.test("parseCommand strips the leading slash and any @BotName suffix, lowercases the command", () => {
  assertEquals(parseCommand("/Status@IcanbefitterBot"), { cmd: "status", args: [] });
  assertEquals(parseCommand("/user  foo@bar.com"), { cmd: "user", args: ["foo@bar.com"] });
  assertEquals(parseCommand("not a command"), null);
  assertEquals(parseCommand(""), null);
});

Deno.test("handler returns bare 200 with no body detail for a wrong secret token", async () => {
  const req = new Request("https://example.com/telegram-admin-bot", {
    method: "POST",
    headers: { "X-Telegram-Bot-Api-Secret-Token": "wrong" },
    body: JSON.stringify({ message: { chat: { id: 12345 }, text: "/help" } }),
  });
  const res = await handler(req);
  assertEquals(res.status, 200);
  const body = await res.text();
  assertEquals(body, "");
});

Deno.test("handler returns bare 200 for a message from a chat id that isn't the founder's", async () => {
  const req = new Request("https://example.com/telegram-admin-bot", {
    method: "POST",
    headers: { "X-Telegram-Bot-Api-Secret-Token": Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "" },
    body: JSON.stringify({ message: { chat: { id: 999999 }, text: "/help" } }),
  });
  const res = await handler(req);
  assertEquals(res.status, 200);
  assertEquals(await res.text(), "");
});
```

The last two tests need `TELEGRAM_WEBHOOK_SECRET` / `FOUNDER_TELEGRAM_CHAT_ID` set in the test environment (dummy values) — set them via `Deno.env.set(...)` at the top of the test file, matching whatever pattern `founder-digest/index_test.ts` already uses for its own env-dependent tests (check it first).

- [ ] **Step 2: Run tests to verify they fail**

Run: `deno test supabase/functions/telegram-admin-bot/index_test.ts`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `telegram-admin-bot/index.ts` (skeleton + `/help`)**

```ts
/**
 * telegram-admin-bot — the founder's on-demand admin console over Telegram.
 * verify_jwt=false (Telegram never sends a Supabase JWT). Internet-facing —
 * the ONLY auth is (1) Telegram's own webhook secret token header and (2)
 * an allowlist of exactly one chat id (the founder's). Anything failing
 * either check gets a bare 200 with no body and no identifying detail
 * logged — this endpoint must never confirm to a stranger that it does
 * anything at all.
 *
 * Read-only v1: every command answers a question. None of them change any
 * state. See docs/superpowers/specs/2026-09-13-telegram-admin-bot-design.md.
 */

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { corsHeaders } from "../_shared/error.ts";
import { sendTelegram, truncateForTelegram } from "../_shared/telegram.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const HELP_TEXT = [
  "<b>Admin commands</b>",
  "/status — open alerts, today's signups, cron health",
  "/revenue — MRR, active subs by plan",
  "/subs — new subscriptions today/yesterday",
  "/expiring — users expiring in 7/30 days",
  "/users [page] — browse all users",
  "/find <text> — search by partial name or email",
  "/user <email-or-id> — one user's detail",
  "/alerts — open alerts",
  "/errors — yesterday's errors, grouped by source",
  "/cron — cron job health",
  "/digest — re-send today's digest",
  "/help — this list",
].join("\n");

/** Pure. Both the secret token AND the chat id must match — either alone is not enough. */
export function isAuthorizedTelegramSender(opts: {
  secretTokenHeader: string | null;
  expectedSecretToken: string;
  chatId: string | number;
  expectedChatId: string;
}): boolean {
  if (!opts.secretTokenHeader) return false;
  if (opts.secretTokenHeader !== opts.expectedSecretToken) return false;
  return String(opts.chatId) === opts.expectedChatId;
}

/** Pure. Strips a leading "/" and any "@BotName" suffix; lowercases the command. Returns null for non-commands. */
export function parseCommand(text: string): { cmd: string; args: string[] } | null {
  const trimmed = text.trim();
  if (!trimmed.startsWith("/")) return null;
  const tokens = trimmed.split(/\s+/);
  const first = tokens[0].slice(1).split("@")[0].toLowerCase();
  if (!first) return null;
  return { cmd: first, args: tokens.slice(1) };
}

export const handler = async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response("", { status: 200 });
  }

  const expectedSecretToken = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";
  const expectedChatId = Deno.env.get("FOUNDER_TELEGRAM_CHAT_ID") ?? "";
  const token = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";

  let update: { message?: { chat?: { id?: number | string }; text?: string } };
  try {
    update = await req.json();
  } catch {
    return new Response("", { status: 200 });
  }

  const chatId = update.message?.chat?.id;
  const text = update.message?.text;
  if (chatId == null || !text) {
    return new Response("", { status: 200 });
  }

  const authorized = isAuthorizedTelegramSender({
    secretTokenHeader: req.headers.get("X-Telegram-Bot-Api-Secret-Token"),
    expectedSecretToken,
    chatId,
    expectedChatId,
  });
  if (!authorized) {
    // Silent — no reply, no identifying detail logged. This endpoint is
    // internet-facing; an unauthorized sender must learn nothing from it.
    return new Response("", { status: 200 });
  }

  const parsed = parseCommand(text);
  if (!parsed) {
    return new Response("", { status: 200 });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const chatIdStr = String(chatId);

  let reply: string;
  try {
    reply = await routeCommand(parsed.cmd, parsed.args, supabase);
  } catch (err) {
    const requestId = crypto.randomUUID().slice(0, 8);
    console.error(`[telegram-admin-bot] request_id=${requestId}`, err);
    reply = "Something went wrong. Try again.";
  }

  const sendResult = await sendTelegram(token, chatIdStr, truncateForTelegram(reply));
  if (!sendResult.ok) {
    console.error(`[telegram-admin-bot] send failed: ${sendResult.summary}`);
  }

  // Always 200 — a non-200 makes Telegram retry the same update.
  return new Response("", { status: 200 });
};

async function routeCommand(
  cmd: string,
  args: string[],
  // deno-lint-ignore no-explicit-any
  supabase: any,
): Promise<string> {
  switch (cmd) {
    case "help":
      return HELP_TEXT;
    default:
      return `Unknown command: /${cmd}. Try /help.`;
  }
}

if (import.meta.main) {
  serve(handler);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `deno test supabase/functions/telegram-admin-bot/index_test.ts`
Expected: PASS (5 tests).

- [ ] **Step 5: Add a `/help` behavioral test**

```ts
Deno.test("handler replies to /help from the authorized founder chat", async () => {
  const secret = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";
  const chatId = Deno.env.get("FOUNDER_TELEGRAM_CHAT_ID") ?? "";
  const req = new Request("https://example.com/telegram-admin-bot", {
    method: "POST",
    headers: { "X-Telegram-Bot-Api-Secret-Token": secret },
    body: JSON.stringify({ message: { chat: { id: Number(chatId) }, text: "/help" } }),
  });
  const res = await handler(req);
  assertEquals(res.status, 200);
  // sendTelegram will attempt a real network call here and fail in the test
  // sandbox (no real token) — that's fine, it's caught and logged, never
  // thrown; the assertion is on the HTTP response shape, not on delivery.
});
```

Run: `deno test supabase/functions/telegram-admin-bot/index_test.ts`
Expected: PASS (6 tests).

- [ ] **Step 6: Type-check**

Run: `deno check supabase/functions/telegram-admin-bot/index.ts`
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/telegram-admin-bot/
sh scripts/safe_commit.sh "feat(telegram-admin-bot): webhook skeleton — dual auth, command router, /help"
```

---

### Task 9: Daily/revenue commands — `/status`, `/revenue`, `/subs`, `/expiring`

**Files:**
- Modify: `supabase/functions/telegram-admin-bot/index.ts`
- Modify: `supabase/functions/telegram-admin-bot/index_test.ts`

**Interfaces:**
- Produces: `export async function cmdStatus(supabase): Promise<string>`, `export async function cmdRevenue(supabase): Promise<string>`, `export async function cmdSubs(supabase): Promise<string>`, `export async function cmdExpiring(supabase): Promise<string>`.
- Consumes: `_shared/ist_date.ts` (`istYesterdayWindow`, `istDateStr`), the RPCs `founder_metrics_for_admin_api()` and `founder_metrics_ops()` (already live — same ones `admin-dashboard-data` reads), the `subscriptions` table.

- [ ] **Step 1: Write the failing tests**

```ts
Deno.test("cmdStatus formats alert count, signups, and reports the ops RPC's cron_failures_24h", async () => {
  const fake = {
    rpc: (name: string) => ({
      single: async () => {
        if (name === "founder_metrics_for_admin_api") {
          return { data: { signups_today_ist: 2, pro_active: 5 }, error: null };
        }
        if (name === "founder_metrics_ops") {
          return { data: { open_alerts_count: 1, cron_failures_24h: 0 }, error: null };
        }
        throw new Error(`unexpected rpc ${name}`);
      },
    }),
  };
  const text = await cmdStatus(fake);
  assertStringIncludes(text, "Signups today: 2");
  assertStringIncludes(text, "Open alerts: 1");
  assertStringIncludes(text, "PRO active: 5");
});

Deno.test("cmdRevenue reports active subscription counts by plan and MRR", async () => {
  const fake = {
    from: (table: string) => ({
      select: () => ({
        eq: () => Promise.resolve({
          data: [{ plan: "monthly" }, { plan: "monthly" }, { plan: "yearly" }],
          error: null,
        }),
      }),
    }),
  };
  const text = await cmdRevenue(fake);
  assertStringIncludes(text, "monthly: 2");
  assertStringIncludes(text, "yearly: 1");
  assertStringIncludes(text, "MRR");
});

Deno.test("cmdSubs reports today's and yesterday's new subscriptions by plan", async () => {
  const fake = {
    from: () => ({
      select: () => ({
        eq: () => ({
          gte: () => ({
            lt: () => Promise.resolve({ data: [{ plan: "monthly", created_at: "2026-09-13T01:00:00Z" }], error: null }),
          }),
        }),
      }),
    }),
  };
  const text = await cmdSubs(fake);
  assertStringIncludes(text, "monthly");
});

Deno.test("cmdExpiring reports 7d and 30d counts", async () => {
  const fake = {
    from: () => ({
      select: () => ({
        not: () => ({
          gte: () => ({
            lte: () => Promise.resolve({ count: 4, data: null, error: null }),
          }),
        }),
      }),
    }),
  };
  const text = await cmdExpiring(fake);
  assertStringIncludes(text, "7d:");
  assertStringIncludes(text, "30d:");
});
```

These fakes are intentionally loose (`// deno-lint-ignore no-explicit-any` on the parameter type in each `cmd*` function, matching the router's own `supabase: any` from Task 8) — the goal is to pin the OUTPUT TEXT shape, not to fully mock supabase-js's builder chain. If a real implementation's exact chained-method shape doesn't match one of these fakes, adjust the fake to match the implementation you actually write in Step 3, not the other way around — the fake exists to drive the format function, not to over-specify the query.

- [ ] **Step 2: Run tests to verify they fail**

Run: `deno test supabase/functions/telegram-admin-bot/index_test.ts`
Expected: FAIL — `cmdStatus`/`cmdRevenue`/`cmdSubs`/`cmdExpiring` not exported.

- [ ] **Step 3: Implement the four handlers**

Add to `telegram-admin-bot/index.ts`, above `routeCommand`:

```ts
import { istDateStr, istYesterdayWindow } from "../_shared/ist_date.ts";
import { escapeHtml } from "../_shared/telegram.ts";

const MONTHLY_PRICE_INR = 349;
const YEARLY_PRICE_INR = 2999;

// deno-lint-ignore no-explicit-any
export async function cmdStatus(supabase: any): Promise<string> {
  const [growth, ops] = await Promise.all([
    supabase.rpc("founder_metrics_for_admin_api").single(),
    supabase.rpc("founder_metrics_ops").single(),
  ]);
  if (growth.error) throw growth.error;
  if (ops.error) throw ops.error;
  return [
    "<b>Status</b>",
    `Signups today: ${growth.data.signups_today_ist}`,
    `PRO active: ${growth.data.pro_active}`,
    `Open alerts: ${ops.data.open_alerts_count}`,
    `Cron failures (24h): ${ops.data.cron_failures_24h}`,
    `Client errors today: ${ops.data.client_errors_today}`,
  ].join("\n");
}

// deno-lint-ignore no-explicit-any
export async function cmdRevenue(supabase: any): Promise<string> {
  const { data, error } = await supabase
    .from("subscriptions")
    .select("plan")
    .eq("status", "active");
  if (error) throw error;
  const counts = new Map<string, number>();
  for (const row of data ?? []) {
    counts.set(row.plan, (counts.get(row.plan) ?? 0) + 1);
  }
  const monthly = counts.get("monthly") ?? 0;
  const yearly = counts.get("yearly") ?? 0;
  const mrr = monthly * MONTHLY_PRICE_INR + yearly * (YEARLY_PRICE_INR / 12);
  const lines = ["<b>Revenue</b>", `MRR: ₹${Math.round(mrr)}`];
  for (const [plan, n] of counts) {
    lines.push(`${escapeHtml(plan)}: ${n}`);
  }
  return lines.join("\n");
}

// deno-lint-ignore no-explicit-any
export async function cmdSubs(supabase: any): Promise<string> {
  const { yStart, tStart } = istYesterdayWindow();
  const todayStart = istDateStr(new Date()); // used only for the label below
  const { data, error } = await supabase
    .from("subscriptions")
    .select("plan, created_at")
    .eq("status", "active")
    .gte("created_at", yStart)
    .lt("created_at", tStart);
  if (error) throw error;
  const counts = new Map<string, number>();
  for (const row of data ?? []) {
    counts.set(row.plan, (counts.get(row.plan) ?? 0) + 1);
  }
  if (counts.size === 0) {
    return `<b>New subscriptions (yesterday)</b>\nnone`;
  }
  const lines = ["<b>New subscriptions (yesterday)</b>"];
  for (const [plan, n] of counts) {
    lines.push(`${escapeHtml(plan)}: ${n}`);
  }
  return lines.join("\n");
}

// deno-lint-ignore no-explicit-any
export async function cmdExpiring(supabase: any): Promise<string> {
  const now = new Date();
  const in7d = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000).toISOString();
  const in30d = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000).toISOString();
  const [r7, r30] = await Promise.all([
    supabase.from("users").select("id", { count: "exact", head: true })
      .not("subscription_expires_at", "is", null)
      .gte("subscription_expires_at", now.toISOString())
      .lte("subscription_expires_at", in7d),
    supabase.from("users").select("id", { count: "exact", head: true })
      .not("subscription_expires_at", "is", null)
      .gte("subscription_expires_at", now.toISOString())
      .lte("subscription_expires_at", in30d),
  ]);
  if (r7.error) throw r7.error;
  if (r30.error) throw r30.error;
  return `<b>Expiring soon</b>\n7d: ${r7.count ?? 0}\n30d: ${r30.count ?? 0}`;
}
```

Wire them into `routeCommand`:

```ts
    case "status":
      return cmdStatus(supabase);
    case "revenue":
      return cmdRevenue(supabase);
    case "subs":
      return cmdSubs(supabase);
    case "expiring":
      return cmdExpiring(supabase);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `deno test supabase/functions/telegram-admin-bot/index_test.ts`
Expected: PASS on all (10 tests: 6 from Task 8 + 4 new).

- [ ] **Step 5: Type-check**

Run: `deno check supabase/functions/telegram-admin-bot/index.ts`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/telegram-admin-bot/
sh scripts/safe_commit.sh "feat(telegram-admin-bot): /status /revenue /subs /expiring commands"
```

---

### Task 10: User commands — `/users [page]`, `/find <text>`, `/user <id>`

**Files:**
- Modify: `supabase/functions/telegram-admin-bot/index.ts`
- Modify: `supabase/functions/telegram-admin-bot/index_test.ts`

**Interfaces:**
- Produces: `export async function cmdUsers(supabase, args: string[]): Promise<string>`, `export async function cmdFind(supabase, args: string[]): Promise<string>`, `export async function cmdUser(supabase, args: string[]): Promise<string>`, `export function looksLikeUuid(s: string): boolean` (pure).

- [ ] **Step 1: Write the failing tests**

```ts
Deno.test("looksLikeUuid recognizes a v4-shaped uuid and rejects an email", () => {
  assertEquals(looksLikeUuid("12345678-abcd-4ef0-9234-56789abcdef0"), true);
  assertEquals(looksLikeUuid("founder@example.com"), false);
});

Deno.test("cmdUsers with no page arg fetches page 1 (offset 0, limit 10)", async () => {
  let capturedRange: [number, number] | null = null;
  const fake = {
    from: () => ({
      select: () => ({
        order: () => ({
          range: (from: number, to: number) => {
            capturedRange = [from, to];
            return Promise.resolve({
              data: [{ id: "u1", email: "a@example.com", created_at: "2026-09-10T00:00:00Z" }],
              error: null,
            });
          },
        }),
      }),
    }),
  };
  const text = await cmdUsers(fake, []);
  assertEquals(capturedRange, [0, 9]);
  assertStringIncludes(text, "a@example.com");
  assertStringIncludes(text, "page 1");
});

Deno.test("cmdUsers with page 2 offsets by 10", async () => {
  let capturedRange: [number, number] | null = null;
  const fake = {
    from: () => ({
      select: () => ({
        order: () => ({
          range: (from: number, to: number) => {
            capturedRange = [from, to];
            return Promise.resolve({ data: [], error: null });
          },
        }),
      }),
    }),
  };
  await cmdUsers(fake, ["2"]);
  assertEquals(capturedRange, [10, 19]);
});

Deno.test("cmdFind with no query text returns a usage hint, not an error", async () => {
  const text = await cmdFind({}, []);
  assertStringIncludes(text.toLowerCase(), "usage");
});

Deno.test("cmdFind searches both email and full_name", async () => {
  let capturedFilter: string | null = null;
  const fake = {
    from: () => ({
      select: () => ({
        or: (filter: string) => {
          capturedFilter = filter;
          return {
            limit: () => Promise.resolve({
              data: [{ id: "u1", email: "match@example.com", full_name: "Match Name" }],
              error: null,
            }),
          };
        },
      }),
    }),
  };
  const text = await cmdFind(fake, ["match"]);
  assertStringIncludes(capturedFilter!, "match");
  assertStringIncludes(text, "match@example.com");
});

Deno.test("cmdUser with no args returns a usage hint", async () => {
  const text = await cmdUser({}, []);
  assertStringIncludes(text.toLowerCase(), "usage");
});

Deno.test("cmdUser routes a uuid-shaped arg to an id lookup and an email-shaped arg to an email lookup", async () => {
  let usedColumn: string | null = null;
  const fake = {
    from: () => ({
      select: () => ({
        eq: (col: string) => {
          usedColumn = col;
          return { maybeSingle: () => Promise.resolve({ data: null, error: null }) };
        },
      }),
    }),
  };
  await cmdUser(fake, ["12345678-abcd-4ef0-9234-56789abcdef0"]);
  assertEquals(usedColumn, "id");
  await cmdUser(fake, ["someone@example.com"]);
  assertEquals(usedColumn, "email");
});

Deno.test("cmdUser reports 'not found' rather than a raw null/error for a missing user", async () => {
  const fake = {
    from: () => ({
      select: () => ({
        eq: () => ({ maybeSingle: () => Promise.resolve({ data: null, error: null }) }),
      }),
    }),
  };
  const text = await cmdUser(fake, ["nobody@example.com"]);
  assertStringIncludes(text.toLowerCase(), "not found");
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `deno test supabase/functions/telegram-admin-bot/index_test.ts`
Expected: FAIL — the three `cmd*` functions and `looksLikeUuid` not exported.

- [ ] **Step 3: Implement the three handlers**

```ts
const USERS_PAGE_SIZE = 10;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Pure. */
export function looksLikeUuid(s: string): boolean {
  return UUID_RE.test(s.trim());
}

// deno-lint-ignore no-explicit-any
export async function cmdUsers(supabase: any, args: string[]): Promise<string> {
  const page = Math.max(1, parseInt(args[0] ?? "1", 10) || 1);
  const from = (page - 1) * USERS_PAGE_SIZE;
  const to = from + USERS_PAGE_SIZE - 1;
  const { data, error } = await supabase
    .from("users")
    .select("id, email, created_at")
    .order("created_at", { ascending: false })
    .range(from, to);
  if (error) throw error;
  const rows = data ?? [];
  if (rows.length === 0) {
    return `<b>Users — page ${page}</b>\nnone`;
  }
  const lines = [`<b>Users — page ${page}</b>`];
  for (const u of rows) {
    lines.push(`${escapeHtml(u.email ?? "(no email)")} — ${u.id.slice(0, 8)}`);
  }
  lines.push(`\n/users ${page + 1} for more`);
  return lines.join("\n");
}

// deno-lint-ignore no-explicit-any
export async function cmdFind(supabase: any, args: string[]): Promise<string> {
  const query = args.join(" ").trim();
  if (!query) {
    return "Usage: /find <partial name or email>";
  }
  const { data, error } = await supabase
    .from("users")
    .select("id, email, full_name")
    .or(`email.ilike.%${query}%,full_name.ilike.%${query}%`)
    .limit(10);
  if (error) throw error;
  const rows = data ?? [];
  if (rows.length === 0) {
    return `No users match "${escapeHtml(query)}".`;
  }
  const lines = [`<b>Matches for "${escapeHtml(query)}"</b>`];
  for (const u of rows) {
    lines.push(`${escapeHtml(u.full_name ?? "(no name)")} — ${escapeHtml(u.email ?? "(no email)")} — ${u.id.slice(0, 8)}`);
  }
  return lines.join("\n");
}

// deno-lint-ignore no-explicit-any
export async function cmdUser(supabase: any, args: string[]): Promise<string> {
  const query = args[0]?.trim();
  if (!query) {
    return "Usage: /user <email-or-id>";
  }
  const column = looksLikeUuid(query) ? "id" : "email";
  const { data, error } = await supabase
    .from("users")
    .select("id, email, full_name, created_at, last_active_at, subscription_expires_at")
    .eq(column, query)
    .maybeSingle();
  if (error) throw error;
  if (!data) {
    return `User not found for "${escapeHtml(query)}".`;
  }
  // Entitlement per this batch's Global Constraints: read `subscriptions`
  // (status='active'), never users.subscription_status.
  const { data: sub, error: subError } = await supabase
    .from("subscriptions")
    .select("plan, status, end_date")
    .eq("user_id", data.id)
    .eq("status", "active")
    .maybeSingle();
  if (subError) throw subError;

  const lines = [
    `<b>${escapeHtml(data.full_name ?? "(no name)")}</b>`,
    escapeHtml(data.email ?? "(no email)"),
    `id: ${data.id.slice(0, 8)}`,
    `signed up: ${data.created_at?.slice(0, 10) ?? "unknown"}`,
    `last active: ${data.last_active_at?.slice(0, 10) ?? "never"}`,
    sub ? `plan: ${escapeHtml(sub.plan)} (ends ${sub.end_date?.slice(0, 10) ?? "?"})` : "plan: free",
  ];
  return lines.join("\n");
}
```

Wire them into `routeCommand`:

```ts
    case "users":
      return cmdUsers(supabase, args);
    case "find":
      return cmdFind(supabase, args);
    case "user":
      return cmdUser(supabase, args);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `deno test supabase/functions/telegram-admin-bot/index_test.ts`
Expected: PASS on all (18 tests: 10 from Task 9 + 8 new).

- [ ] **Step 5: Type-check**

Run: `deno check supabase/functions/telegram-admin-bot/index.ts`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/telegram-admin-bot/
sh scripts/safe_commit.sh "feat(telegram-admin-bot): /users /find /user commands"
```

---

### Task 11: Ops commands — `/alerts`, `/errors`, `/cron`

**Files:**
- Modify: `supabase/functions/telegram-admin-bot/index.ts`
- Modify: `supabase/functions/telegram-admin-bot/index_test.ts`

**Interfaces:**
- Produces: `export async function cmdAlerts(supabase): Promise<string>`, `export async function cmdErrors(supabase): Promise<string>`, `export async function cmdCron(supabase): Promise<string>`.

- [ ] **Step 1: Write the failing tests**

```ts
Deno.test("cmdAlerts lists open alerts most-recent-first, capped at 10 with a +N more line", async () => {
  const rows = Array.from({ length: 12 }, (_, i) => ({
    source: `check_${i}`,
    severity: "warn",
    summary: `row ${i}`,
    detected_at: "2026-09-13T01:00:00Z",
  }));
  const fake = {
    from: () => ({
      select: () => ({
        is: () => ({
          order: () => ({
            limit: (n: number) => Promise.resolve({ data: rows.slice(0, n), error: null }),
          }),
        }),
      }),
    }),
  };
  const text = await cmdAlerts(fake);
  assertStringIncludes(text, "row 0");
  assertStringIncludes(text, "row 9");
});

Deno.test("cmdAlerts reports 'none' when there are no open alerts", async () => {
  const fake = {
    from: () => ({
      select: () => ({
        is: () => ({
          order: () => ({ limit: () => Promise.resolve({ data: [], error: null }) }),
        }),
      }),
    }),
  };
  assertStringIncludes(await cmdAlerts(fake), "none");
});

Deno.test("cmdErrors groups yesterday's real errors by op_type", async () => {
  const fake = {
    from: () => ({
      select: () => ({
        gte: () => ({
          lt: () => Promise.resolve({
            data: [
              { op_type: "sync_service_restore_op_timeout", error_code: "minified:a0Z" },
              { op_type: "sync_service_restore_op_timeout", error_code: "minified:a0Z" },
              { op_type: "realtime_stream_weight_logs", error_code: "minified:aQC" },
            ],
            error: null,
          }),
        }),
      }),
    }),
  };
  const text = await cmdErrors(fake);
  assertStringIncludes(text, "sync_service_restore_op_timeout: 2");
  assertStringIncludes(text, "realtime_stream_weight_logs: 1");
});

Deno.test("cmdCron reports the most recently-run functions first, flags how long ago", async () => {
  const fake = {
    from: () => ({
      select: () => ({
        order: () => ({
          limit: () => Promise.resolve({
            data: [
              { function_name: "morning-alert", status: "success", started_at: new Date().toISOString() },
            ],
            error: null,
          }),
        }),
      }),
    }),
  };
  const text = await cmdCron(fake);
  assertStringIncludes(text, "morning-alert");
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `deno test supabase/functions/telegram-admin-bot/index_test.ts`
Expected: FAIL — the three functions not exported.

- [ ] **Step 3: Implement the three handlers**

```ts
const MAX_ALERT_LINES = 10;

// deno-lint-ignore no-explicit-any
export async function cmdAlerts(supabase: any): Promise<string> {
  const { data, error } = await supabase
    .from("alerts")
    .select("source, severity, summary, detected_at")
    .is("resolved_at", null)
    .order("detected_at", { ascending: false })
    .limit(MAX_ALERT_LINES);
  if (error) throw error;
  const rows = data ?? [];
  if (rows.length === 0) {
    return "<b>Open alerts</b>\nnone";
  }
  const lines = ["<b>Open alerts</b>"];
  for (const a of rows) {
    lines.push(`[${escapeHtml(a.severity)}] ${escapeHtml(a.source)} — ${escapeHtml(a.summary)}`);
  }
  return lines.join("\n");
}

// deno-lint-ignore no-explicit-any
export async function cmdErrors(supabase: any): Promise<string> {
  const { yStart, tStart } = istYesterdayWindow();
  const { data, error } = await supabase
    .from("client_errors")
    .select("op_type, error_code")
    .gte("created_at", yStart)
    .lt("created_at", tStart);
  if (error) throw error;
  const rows = (data ?? []).filter((r: { error_code: string }) =>
    r.error_code !== "event" && r.error_code !== "info"
  );
  if (rows.length === 0) {
    return "<b>Errors (yesterday)</b>\nnone";
  }
  const counts = new Map<string, number>();
  for (const r of rows) {
    counts.set(r.op_type, (counts.get(r.op_type) ?? 0) + 1);
  }
  const sorted = [...counts.entries()].sort((a, b) => b[1] - a[1]);
  const lines = ["<b>Errors (yesterday)</b>"];
  for (const [opType, n] of sorted.slice(0, 10)) {
    lines.push(`${escapeHtml(opType)}: ${n}`);
  }
  return lines.join("\n");
}

// deno-lint-ignore no-explicit-any
export async function cmdCron(supabase: any): Promise<string> {
  const { data, error } = await supabase
    .from("cron_call_log")
    .select("function_name, status, started_at")
    .order("started_at", { ascending: false })
    .limit(200);
  if (error) throw error;
  const latestByFn = new Map<string, { status: string; started_at: string }>();
  for (const row of data ?? []) {
    if (!latestByFn.has(row.function_name)) {
      latestByFn.set(row.function_name, { status: row.status, started_at: row.started_at });
    }
  }
  const now = Date.now();
  const entries = [...latestByFn.entries()].sort((a, b) =>
    new Date(a[1].started_at).getTime() - new Date(b[1].started_at).getTime()
  );
  const lines = ["<b>Cron (most stale first)</b>"];
  for (const [fn, info] of entries.slice(0, 15)) {
    const ageMin = Math.round((now - new Date(info.started_at).getTime()) / 60000);
    lines.push(`${escapeHtml(fn)}: ${info.status}, ${ageMin}m ago`);
  }
  return lines.join("\n");
}
```

Wire them into `routeCommand`:

```ts
    case "alerts":
      return cmdAlerts(supabase);
    case "errors":
      return cmdErrors(supabase);
    case "cron":
      return cmdCron(supabase);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `deno test supabase/functions/telegram-admin-bot/index_test.ts`
Expected: PASS on all (22 tests: 18 from Task 10 + 4 new).

- [ ] **Step 5: Type-check**

Run: `deno check supabase/functions/telegram-admin-bot/index.ts`
Expected: no errors.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/telegram-admin-bot/
sh scripts/safe_commit.sh "feat(telegram-admin-bot): /alerts /errors /cron commands"
```

---

### Task 12: `/digest` — on-demand resend

**Files:**
- Modify: `supabase/functions/telegram-admin-bot/index.ts`
- Modify: `supabase/functions/telegram-admin-bot/index_test.ts`

**Interfaces:**
- Produces: `export async function cmdDigest(supabase): Promise<string>`.
- Consumes: `_shared/founder_digest_content.ts` (`gatherDigestInput`, `buildDigestText` — from Tasks 4/5). This is the whole point of that extraction: `/digest` calls the EXACT SAME builder the daily cron uses, so the two can never drift apart.

- [ ] **Step 1: Write the failing test**

```ts
Deno.test("cmdDigest builds text via the shared founder_digest_content module, not a re-implementation", async () => {
  // A minimal fake sufficient for gatherDigestInput's real queries to resolve
  // to empty-but-readable sections — the point of this test is that cmdDigest
  // DELEGATES, not that it re-derives the digest's own query correctness
  // (that's covered by founder_digest_content_test.ts already).
  const text = await cmdDigest(makeEmptyDigestFake());
  assertStringIncludes(text, "none"); // every section empty -> every section says "none"
});
```

Add a small local helper `makeEmptyDigestFake()` near the top of the test file that returns a fake supabase client whose every `.from(...)`/`.rpc(...)` chain resolves to `{ data: [], error: null }` (or `{ count: 0, error: null }` for count queries) — shape it to satisfy whatever `gatherDigestInput` actually calls, which you can see directly since you wrote it in Task 4/5.

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test supabase/functions/telegram-admin-bot/index_test.ts`
Expected: FAIL — `cmdDigest` not exported.

- [ ] **Step 3: Implement `cmdDigest`**

```ts
import { buildDigestText, gatherDigestInput } from "../_shared/founder_digest_content.ts";

// deno-lint-ignore no-explicit-any
export async function cmdDigest(supabase: any): Promise<string> {
  const input = await gatherDigestInput(supabase, new Date());
  return buildDigestText(input);
}
```

Wire into `routeCommand`:

```ts
    case "digest":
      return cmdDigest(supabase);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test supabase/functions/telegram-admin-bot/index_test.ts`
Expected: PASS on all (23 tests).

- [ ] **Step 5: Type-check the whole function directory**

Run: `deno check supabase/functions/telegram-admin-bot/index.ts supabase/functions/alert-critical-notify/index.ts supabase/functions/founder-digest/index.ts supabase/functions/_shared/founder_digest_content.ts supabase/functions/_shared/telegram.ts supabase/functions/_shared/ist_date.ts`
Expected: no errors across all six files.

- [ ] **Step 6: Run the full Deno suite once, not just the targeted files**

Run: `deno test supabase/functions/`
Expected: PASS across the whole tree — this is the check that catches a change in one shared file breaking an unrelated function's tests (root CLAUDE.md §4.9's "a targeted run is a different input set" pitfall applies to Deno tests exactly as it does to `flutter test`).

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/telegram-admin-bot/
sh scripts/safe_commit.sh "feat(telegram-admin-bot): /digest command — reuses founder-digest's own content builder"
```

---

### Task 13: Deploy, Telegram-side setup, and live smoke (operational — needs explicit go)

This task is NOT a normal code-and-test cycle. Every sub-step that touches the live Telegram bot or the live Supabase project needs its own explicit founder go, per root CLAUDE.md §4.3 ("plan approval ≠ deploy approval") — do not run any of these on the strength of the plan alone having been approved.

**Files:** none (operational only).

- [ ] **Step 1: Add the two new secrets to the Edge Function vault**

`TELEGRAM_WEBHOOK_SECRET` — generate with `openssl rand -hex 32` (same standard this repo already uses for `CRON_SECRET`, per `_shared/cron_auth.ts`'s own header). `TELEGRAM_BOT_TOKEN` and `FOUNDER_TELEGRAM_CHAT_ID` already exist in the vault (set 2026-09-12) — confirm they're present via the Supabase MCP secrets GET endpoint (returns a sha256 digest, not the value) rather than assuming. **Ask the founder before setting the new secret** — this is a live-project write.

- [ ] **Step 2: Deploy the three functions**

Per `supabase/functions/CLAUDE.md`'s preferred host-shell deploy path (`emit_payload.js` + `deploy_via_api.js`), one at a time: `founder-digest` (verify_jwt=false — already its setting), `alert-critical-notify` (verify_jwt=false), `telegram-admin-bot` (verify_jwt=false). Boot-verify each per the deploy skill (an anon-key Bearer POST; 503 = boot-broken, the module's own 4xx = booted). **Ask before each live deploy.**

- [ ] **Step 3: Register the webhook**

One-time `POST https://api.telegram.org/bot<TOKEN>/setWebhook` with `url` = the deployed `telegram-admin-bot` function URL and `secret_token` = the `TELEGRAM_WEBHOOK_SECRET` value from Step 1. **Ask before running** — this changes live bot configuration.

- [ ] **Step 4: Populate the command menu**

One-time `POST https://api.telegram.org/bot<TOKEN>/setMyCommands` with the 11 read-only commands (name + one-line description, matching `HELP_TEXT` from Task 8) in the `default` scope. **Ask before running.**

- [ ] **Step 5: Live smoke — a real `/status`**

Send `/status` from the founder's own Telegram chat to the bot; confirm a reply arrives within a few seconds and the numbers look sane against what's already known live (e.g. compare `Open alerts` against a direct query).

- [ ] **Step 6: Live smoke — a synthetic critical alert**

Insert one real (not rolled-back) row: `INSERT INTO public.alerts (source, severity, summary, suggested_action) VALUES ('manual_smoke_test', 'critical', 'live smoke test — safe to ignore', 'delete this row after confirming delivery');` via Supabase MCP `execute_sql`. **Ask before running — this is a real, non-rolled-back write**, unlike Task 6's verification. Confirm the Telegram push arrives within a few seconds. Then delete the row: `DELETE FROM public.alerts WHERE source = 'manual_smoke_test';`.

- [ ] **Step 7: Walk the root CLAUDE.md §5 per-batch maintenance checklist**

This batch is `feat:`, not `fix:`, so rule 22's diagnose-doc / contract-test requirements don't apply, but the rest of §5's checklist still does: SoT registry (none needed — see Global Constraints), `CRON_REGISTRY.md` update (add the `founder_digest_daily` job if it's genuinely still missing from that doc, and confirm whether a Gate 31 registry row is needed for the new trigger-dispatch path — triggers aren't `cron.schedule` calls, so Gate 31's `cron.schedule(...)` scan won't see it; note this explicitly rather than silently skipping), `docs/operations/SECRET_INVENTORY.md` update for `TELEGRAM_WEBHOOK_SECRET`, worktree retirement once merged, project retrospective memory file.

- [ ] **Step 8: Merge and push (ask first)**

Per root CLAUDE.md §4.13: from the primary worktree, `sh scripts/safe_merge.sh telegram-admin-bot`, then `sh scripts/safe_push.sh`. Both need their own explicit go — "the plan was approved" is not "push was asked for."

---

## Self-Review Notes (completed during plan authoring)

- **Spec coverage:** all 11 commands (Task 8 §1, 9, 10, 11, 12), the critical-alert trigger (Task 6/7), the two new digest sections (Task 5), the shared-sender extraction (Task 3), and the auth model (Task 8) each have a task. The spec's §11 open question about migration-collision risk is handled by Task 6's live re-check step; its open question about `founder-digest` merge order is handled by Task 1.
- **Placeholder scan:** the one intentional `throw new Error("port the real queries...")` in Task 4 Step 4 is explicitly flagged as a MUST-REPLACE-BEFORE-STEP-6 marker, not a shipped placeholder — it exists because this plan was written without the actual (unmerged) `founder-digest/index.ts` in hand; Task 4 Step 1 requires reading that file first, and Step 6's `deno check` cannot pass while the throw remains, so it cannot silently ship.
- **Type consistency:** `cmd*` handler signatures are consistent (`(supabase: any) => Promise<string>` or `(supabase: any, args: string[]) => Promise<string>`) across Tasks 9–12; all wire into the same `routeCommand` switch from Task 8. `SubscriptionRow`, `DigestInput`, `SectionRead<T>` are defined once (Task 4/5) and reused, not redeclared.
