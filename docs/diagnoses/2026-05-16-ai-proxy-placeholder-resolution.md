---
bug_id: 2026-05-16-ai-proxy-placeholder-resolution
date: 2026-05-16
batch: APK Test #16.2 / Phase E (audit 2026-05-16) — E.5.2
status: fixed
regression_test: test/contracts/ai_proxy_placeholder_resolution_test.dart
---

## Symptom

`ai_coach_interactions` table accumulated stuck rows with `model_used='pending'` and empty `ai_response`. Live audit on 2026-05-16 found 8 such rows spanning 2026-05-11 → 2026-05-15 (4 on `food_text_analysis` channel + 4 paired client `in_app_orphan` rows that are tracked separately in E.5.3).

These were:
- Counted by the dedup window (correctly, for 60s) → past 60s, useless noise.
- Counted in analytics row counts → inflated `food_text_analysis` activity.
- Polluting any future restore or context-building query that reads `model_used`.

Phase A finding A-1 originally framed these as "ai_response IS NOT NULL but model_used='pending'" — closer inspection revealed `ai_response = ''` (empty string, not NULL) in all 8 cases, meaning the rows were FAILED Gemini calls where nothing got written back to the placeholder.

## Root cause

`supabase/functions/ai-proxy/index.ts` reserves a placeholder row BEFORE calling Gemini for `food_text_analysis` (so the trigger `trg_food_text_rate_limit` can count attempts atomically — Test #11 M1 pattern):

```ts
.insert({
  user_id: userId,
  channel: 'food_text_analysis',
  ai_response: '',
  model_used: 'pending',
  tokens_used: 0,
})
```

Pre-fix the placeholder UPDATE only happened on the **success** branch, and even there it was fire-and-forget:

```ts
.update({...}).eq('id', reservationId)
.then((r) => { if (r.error) console.error(...) });
```

Three failure modes never resolved the placeholder:
1. `!content` (Gemini returned no content) → `return err(502, ...)` immediately. Placeholder orphaned.
2. `JSON.parse(content)` throws (Gemini returned non-JSON) → `} catch (_) { return err(502, ...) }`. Placeholder orphaned.
3. Even on success, a network blip during the fire-and-forget UPDATE silently lost the resolution.

Modes 1+2 fully explain the 8 stuck rows on prod (Gemini 502 storm 2026-05-11 → 15).

## Fix

`supabase/functions/ai-proxy/index.ts` food_text_analysis branch now declares a local helper:

```ts
const resolvePlaceholder = async (
  finalModel: string,
  finalResponse: string,
  tokens: number,
): Promise<void> => {
  if (!reservationId) return;
  const { error } = await supabaseClient
    .from('ai_coach_interactions')
    .update({ ai_response: finalResponse, model_used: finalModel, tokens_used: tokens })
    .eq('id', reservationId);
  if (error) {
    const requestId = crypto.randomUUID().split('-')[0];
    console.error(`[ai-proxy.food] placeholder resolution failed request_id=${requestId} model=${finalModel}:`, error);
  }
};
```

Every exit branch now `await`s the helper with a terminal `model_used` value:
- **Success:** `LABEL_FLASH` or `LABEL_FLASH_LITE` + parsed JSON.
- **Gemini failure (`!content`):** `'failed_gemini'` + `{"error":"Gemini returned no content"}`.
- **Parse failure (JSON.parse throws):** `'failed_parse'` + `{"error":"non-JSON response","raw":"<first 500 chars>"}` so future post-mortem can see what Gemini actually emitted.

Cost: one extra round-trip per call (~30-80 ms) to await the UPDATE. Worth it — eliminates the orphan class.

## Verification

- New contract test: `test/contracts/ai_proxy_placeholder_resolution_test.dart` (4 sub-tests).
  - `resolvePlaceholder helper is defined` ✓
  - `Gemini-no-content branch resolves to failed_gemini` ✓
  - `JSON-parse-failure branch resolves to failed_parse` ✓
  - `success branch awaits resolvePlaceholder (not fire-and-forget)` ✓ (≥3 await calls, no legacy `.then()` shape)
- All 4/4 PASS via `flutter test`.
- One-shot SQL backfill of the historical 8 stuck rows already applied via E.17 (relabeled to `failed_legacy`).
- Deploy via `.claude/deploy_via_api.js` to v66 → live verification via repeat of Phase A NULL-count probe after a real food_text_analysis Gemini failure.

## Follow-ups

- The `in_app_orphan` paired-row class is tracked separately in E.5.3 (cross-channel dedup in `sync_coach.dart`).
- Phase A finding A-1 reframed in `phase-c-verification-log.md` — `ai_response=''` not NULL — corrected.
- Future hardening: extend resolvePlaceholder pattern to other Edge Function placeholder reservations (scan_meal, cart_auditor) if they ever adopt the same pre-Gemini reservation pattern.

## Class lesson

Any placeholder-row pattern needs a "resolves on EVERY exit branch" invariant. The fire-and-forget shortcut to save one round-trip on the success path is not worth the orphan class on failure paths. When tokens are billed by an external API regardless of outcome, the local DB row MUST close to a terminal state regardless of outcome — same shape as a 2PC commit log.
