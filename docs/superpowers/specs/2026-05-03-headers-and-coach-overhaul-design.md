# Headers + Coach Overhaul — Design Spec

**Date:** 2026-05-03
**Branch (proposed):** `feat/test-9-batch` off `main` (post-Test #8 merge `a394e0c`).
**Companion spec:** [`2026-05-03-sync-fanout-design.md`](2026-05-03-sync-fanout-design.md) covers F1–F7 (sync gap fix + rank chip hit-test). Both specs ship as the **Test #9 batch / one APK** (user instruction 2026-05-03).

**Trigger:** APK Test #8 install observations from `upendraprasad19@gmail.com` surfaced a class of "screen header drift" — every tab has its own bespoke header that's grown to 3–5 rows, status pills float in their own dedicated rows, and the Coach screen specifically has accumulated UX debt (two redundant message counters, generic welcome copy, asymmetric input bar elements, mic gated as PRO despite zero cost). User instruction: "we are drifting from design time and again."

---

## 1. Problem statement

The Wardroom design system already standardizes fonts (Fraunces / DM Sans / JetBrains Mono via `AppTypography`) and color tokens (`AppColors`), and provides a `WardLetterhead` primitive with eyebrow / title / leading / trailing slots. Despite this, every tab implements its own ad-hoc header layout that pushes status badges to dedicated rows below the divider:

| Screen | Rows | Drift |
|---|---|---|
| Home | 4 + 2 gold rules | streak strip on its own row, date duplicated in eyebrow + hero block |
| Train | 5 + 1 hairline | streak strip + status sub-line + progress bar all stacked |
| Nutrition | 3 + 1 gold rule | streak strip on its own row; DIET PLAN already in trailing slot |
| Coach | header + status strip + msg count + trial countdown ≈ 4 strips | two redundant counters; generic welcome text; mic gated PRO at zero infra cost |
| Profile | banner + name row + gold rule + (status strip removed in Test #8) | (locked, no changes this batch) |

The deeper problem isn't visual — it's that **each screen reinvents the same row pattern from scratch**, so every header drift becomes a per-screen fix that has to be repeated across tabs. Five screens × independent code = five separate places where the next eyebrow font, the next status pill placement, the next divider weight will diverge.

Compounding this on the Coach screen specifically:

1. Two message counters render the same information twice: a small `1/15 MESSAGES TODAY` mono row + a larger trial countdown panel `14 msgs left today / 29 days remaining in free trial`.
2. The opening message from the AI coach (`"Hey! I'm your AI fitness coach. Ask me anything about your workouts, nutrition, or fitness goals!"`) is generic SaaS copy at odds with the Wardroom brand voice already established by the Captain's Manual.
3. The input bar has 4 separately-sized buttons in a row with asymmetric heights — visually clumsy.
4. Voice input is gated as PRO (`voice_notes` in `_highValueFeatures`) but the actual implementation uses on-device `speech_to_text` which has **zero cost** to us — gating it discourages engagement for no gain.
5. Media (photo/video) upload is hard-gated PRO before the user can even pick a file, preventing the "try it, see the value, upgrade" conversion lever.

## 2. Goals

- **Standardize header pattern across Home / Train / Nutrition** to a 3-row block: eyebrow (row 1) + title + status (row 2) + screen-specific anchor (row 3) + single hairline.
- **Compact Coach header** to a different shape (smaller title, chat-first) but with the same row-discipline.
- **Drop the streak/freeze pill from Coach** — it adds noise without value on a conversation-first screen.
- **Replace the `THE BRIDGE` AI text avatar** with a captain peaked-cap silhouette SVG.
- **Rewrite the Coach welcome message** in Wardroom voice.
- **Single-bubble input bar** with WhatsApp-style mic↔send morph + push-to-talk recording UX.
- **Voice = free for everyone** — drop `voice_notes` from `_highValueFeatures`; remove lock badge from mic.
- **Free image upload + 5 lifetime free analyses** (then paywall); **free video upload + always-PRO video analysis**; **30-second cap on all video uploads** (free + PRO).
- **30-day TTL on free-user media** with a nightly `clean-orphan-media` cron.
- **Drop lock badges** from mic + paperclip; paywall opens on tap when the user hits a gated capability.

## 3. Non-goals

- **Profile screen header** — locked-no-change for this batch (user call 2026-05-03). The rank chip relocation already shipped in Test #8.
- **Extracting a shared `WardScreenHeader` primitive** — deferred to a future cleanup batch (Test #10 candidate). Per-screen edits ship first; primitive extraction follows once the four screens are visually aligned.
- **Telegram coach channel** — header changes apply to the in-app channel only; Telegram view stays as-is.
- **Server-side speech-to-text (e.g. Whisper)** — voice stays on-device transcription via the existing `speech_to_text` package. No infra change.
- **Audio file uploads to Coach** — out of scope; only image + video.
- **Profile screen drift sweep** — explicitly deferred per user.

## 4. Architecture

### 4.1 — Cross-screen header pattern (F8–F11)

All four screens (Home, Train, Nutrition, Coach) adopt a 3-row max + single-hairline header. The pattern slots vary slightly per screen but the row count and hairline are uniform:

```
ROW 1 — eyebrow (full meta line, mono accent gold)
ROW 2 — title row (Fraunces title + optional trailing element)
ROW 3 — screen-specific anchor (date hero / progress bar / KCAL meter / counter)
─────── single 1px gold hairline ───────
... screen content
```

Per-screen specifics covered in §5.1–5.4. Note the streak pill placement varies (Home row 3 / Train row 2 / Nutrition row 3 / Coach absent) — the locked decision per the Q1/Q2 brainstorm: **flexible standard** ("streak somewhere right-aligned in the header"), not strict ("always row 2 trailing"). Trade-off accepted: eye doesn't always land on streak in the same spot when switching tabs, but every row gets to do one job.

### 4.2 — Coach overhaul (F11–F17)

The Coach screen is treated as a single coherent overhaul covering header, input bar, voice/media gating, and reply copy. Sub-themes are split across F11–F17 only for traceability — they ship as one cohesive change.

Header (F11) follows the cross-screen pattern but with smaller title type (26 sp italic vs 32 sp on other screens) because chat is the primary task and vertical space is at a premium.

Input bar (F12) replaces the existing 4-button row with a single rounded bubble holding text + attach + mic↔send. Gestures + animation per §5.6.

Voice/media gating (F13–F17) restructures the entitlement model:
- **Voice** → free (was PRO; on-device transcription costs zero)
- **Image upload** → free; **5 lifetime free analyses** then paywall
- **Video upload** → free; **always-PRO analysis**; **30 sec cap for everyone** (cost + UX containment)
- **Free-user media** → 30-day TTL via nightly cron

## 5. Components

### 5.1 — Home header (F8)

**File:** `lib/features/home/screens/home_screen.dart` lines ~200–290 + `_buildDateDisplay` ~363–436

Current: 4 rows + 2 gold rules. Eyebrow `DAILY · MON 5 MAY` repeats the date that the large hero block also shows; status pill takes its own row.

Proposed: 3 rows + 1 gold rule.

```
[anchor] DAILY · MON 5 MAY · WK 18 · PHASE 1                          ← row 1: full-width eyebrow
[avatar 44dp]  Good morning, Upendra.                                  ← row 2: avatar + greeting
                                                  🔥 7 DAYS │ ❄ 2     ← row 3: streak right
─────                                                                  ← single gold rule
... weekly calendar / today card / etc.
```

Implementation:

- Replace the existing `WardLetterhead(eyebrow: 'DAILY · MON 5 MAY', title: '$greeting.', leadingAvatar: ...)` callsite with a custom 3-row Column inside the same outer Builder. The eyebrow becomes `'DAILY · ${weekday} ${day} ${month} · WK $weekOfYear · PHASE $currentPhase'` (consolidating the WK/PHASE meta currently in the `_buildDateDisplay` right-side label).
- Move the streak pill from its own `Padding(22, 10, 22, 10)` row down into row 3 of the new header, right-aligned. Keep the existing GestureDetector + StreakExplainerSheet wiring.
- **Delete `_buildDateDisplay()` entirely** — its information is now in the eyebrow. Saves ~40 dp.
- **Delete the second `WardRule(margin: 22, 4, 22, 12)` between date hero and weekly calendar** — single hairline closes the header.

Net vertical savings: ~62 dp.

### 5.2 — Train header (F9)

**File:** `lib/features/train/screens/train_screen.dart` lines ~283–366

Current: 5 rows (eyebrow / title / subtitle / progress bar / status strip) + 1 hairline.

Proposed: 3 rows + 1 hairline.

```
[anchor] TRAIN · WK 1 OF 4 · PHASE 1                                   ← row 1: eyebrow
Foundation                                       🔥 7 DAYS │ ❄ 2      ← row 2: title 32sp + streak right
0 / 6  [████░░░░░░░] 0%                                               ← row 3: subtitle inlined w/ bar
─────                                                                  ← single hairline border
```

Implementation:

- Restructure `_buildPlanHeader` Column children into 3 distinct rows.
- Eyebrow becomes `'TRAIN · WK $selectedWeek OF ${plan.weeks.length} · PHASE $currentPhase'` (adds PHASE meta consolidating from the old subtitle line).
- Title size **bumped from `h2.copyWith(fontSize: 28)` to `h1` (32 sp)** to match the cross-screen standard. Add `maxLines: 1, overflow: TextOverflow.ellipsis` since some phase names will overflow at 32 sp on 360 dp.
- Title row becomes a `Row` with `Expanded(title)` + `WardStatusStrip(streakDays, freezesAvailable)` trailing.
- Subtitle `'$completedDays of $totalWorkoutDays sessions complete'` collapses into a compact `'$completedDays / $totalWorkoutDays'` mono prefix on the progress-bar row.
- Status strip's standalone `WardStatusStrip` block is removed.

Net vertical savings: ~60 dp.

### 5.3 — Nutrition header (F10)

**File:** `lib/features/nutrition/screens/nutrition_screen.dart` lines ~55–110 + `_buildDietPlanButton` ~129+

Current: 3 rows + 1 gold rule. DIET PLAN button already in `WardLetterhead.trailing`; streak strip on its own row below.

Proposed: 3 rows + 1 gold rule. DIET PLAN moves to row 1 right; streak takes row 3 right with KCAL meter.

```
[anchor] GALLEY · MON 5 MAY                                  🍴 DIET PLAN ›   ← row 1: eyebrow + DIET PLAN right
Fueling the plan                                                              ← row 2: title 32sp full width
[████████░░░░░░░] 1820 / 2960 KCAL                          🔥 7 DAYS │ ❄ 2  ← row 3: KCAL bar + streak right
─────                                                                          ← single gold rule
```

Implementation:

- Restructure the Builder Column children to a 3-row Column with explicit `Row` layouts for rows 1 and 3.
- Eyebrow row: full-width `Row` with `Expanded(eyebrow)` + `_buildDietPlanButton()`.
- Title row 2: full-width `Text(title)` only (DIET PLAN moved out, no trailing).
- Anchor row 3: gold `WardBar(pct: kcalConsumed / kcalTarget, ...)` flex left + `Text('$consumed / $target KCAL')` left-aligned mono + `WardStatusStrip(streak, freezes)` right.
- Streak strip's standalone `Padding(22, 8, 22, 4)` block is removed.

Net vertical savings: ~38 dp.

### 5.4 — Coach header (F11)

**File:** `lib/features/ai_coach/screens/ai_coach_screen.dart` `_buildCompactHeader` lines ~369+

Current: 1 dense row (avatar + eyebrow+title col + PRO pill + ⋮ menu) + standalone status strip + standalone msg count + trial countdown when free.

Proposed: 2 rows (eyebrow alone / avatar + title + UPGRADE) + counter glued under UPGRADE. Streak dropped. Two msg counters merged into one. Welcome rewritten.

```
▶ THE BRIDGE · 24/7                                                   ← row 1: eyebrow alone, full width
[ava] Aye Captain                                ↑ UPGRADE  ⋮         ← row 2: avatar + 26sp italic title + UPGRADE + menu
                                                  14 / 15 MSGS · 29 D TRIAL  ← counter glued under UPGRADE, no gap
```

Implementation:

**Avatar (replaces "AI" text):**
- Create `assets/coach/captain_cap.svg` — peaked-cap silhouette in `AppColors.accent` on transparent. Single-color SVG, ~1 KB.
- Render inside the existing 34 dp circular avatar container (gold border + green live dot pulses unchanged).
- `flutter_svg` is already a dependency (used elsewhere); no new package.

**Header structure:**
- Row 1: eyebrow `▶ THE BRIDGE · 24/7` mono accent, full width, no avatar.
- Row 2: `Row` with `[avatar | Expanded(title) | trailing column]` — title is `Text('Aye Captain', style: AppTypography.h3.copyWith(fontSize: 26, fontStyle: italic))`. The trailing column is a vertical 2-row stack: top row = `[UPGRADE pill, ⋮ menu]`, bottom row = `Text('14 / 15 MSGS · 29 D TRIAL', AppTypography.monoXs)` with right alignment, no margin between top and bottom rows.

**Streak removal:**
- Delete the `Padding(22, 8, 22, 8)` block wrapping `WardStatusStrip`. ~38 dp saved.

**Counter consolidation:**
- Delete `_buildMessageCountIndicator` standalone row entirely (its info now lives glued under UPGRADE).
- Keep `_buildTrialCountdown` rendering only for fundamentally different states (e.g. trial expired); the day-count is part of the new compact counter.

**Welcome message rewrite:**
- New copy: `"Bridge here, Recruit. Standing by for orders. Workouts, nutrition, recovery — fire away."` Italic-gold emphasis on the action words.
- Wrap in a card with a `▶ THE BRIDGE` mono eyebrow tag (visually anchors as system-from-bridge, not a regular chat bubble).
- Replace the existing welcome string in `chatHistoryProvider` initial state.

### 5.5 — Coach input bar (F12)

**File:** `lib/features/ai_coach/screens/ai_coach_screen.dart` `_buildInputBar` (currently ~lines 750+)

Current: 4 separate buttons in a `Row` — mic, attach, text input, send. Asymmetric heights, busy.

Proposed: single rounded 48 dp bubble holding `[text input | attach (paperclip) | mic↔send]`. WhatsApp-style mic-to-send morph driven by `controller.text.isNotEmpty`. Long-press mic for push-to-talk recording.

```
┌──────────────────────────────────────────┐
│  Ask your coach…              📎    🎙   │   ← idle: trailing = mic (gold filled)
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│  Hi I'm typing                📎    ↑    │   ← typing: trailing = send (200ms morph)
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│  ⏺ 0:03           ← slide to cancel  🎙* │   ← recording: bubble red, dot blinks, mic pulses red
└──────────────────────────────────────────┘
```

Implementation:

**Layout:**
- Single `Container(decoration: BoxDecoration(color: AppColors.input, border: ..., borderRadius: 24))` 48 dp tall.
- Children: `Row([Expanded(TextField), AttachButton(36dp), TrailingButton(36dp)])`.
- Attach is `Icon(Icons.attach_file)` outline gold on transparent (with optional lock badge — see F17 for badge removal decision).
- Trailing is an `AnimatedSwitcher(duration: 200ms, child: ...)`.

**Mic↔send morph:**
- `ValueListenableBuilder<TextEditingValue>` wraps the trailing slot.
- When `controller.text.trim().isEmpty` → mic icon (`Icon(Icons.mic)`, the same Material glyph WhatsApp uses).
- When `controller.text.trim().isNotEmpty` → send icon (`Icon(Icons.arrow_upward)`).
- Both rendered inside a 36 dp gold-filled circle.
- `AnimatedSwitcher` with `FadeTransition` + slight `ScaleTransition` (1.0 → 1.05 mid-morph) for the swap.

**Recording UX:**
- `GestureDetector` on the mic button captures `onLongPressStart` / `onLongPressMoveUpdate` / `onLongPressEnd`.
- `onLongPressStart`: start `SpeechToText` session (existing wiring per CLAUDE.md "Mic stops after 2-3 seconds" entry — `pauseFor: 5s`, `listenFor: 60s`, `ListenMode.dictation`, `partialResults: true`). Set state `_recording = true` + start a `Ticker` for the timer display.
- During recording: bubble swaps to `RecordingBubbleContent(timer, cancelHint)` — red border, blinking dot, mono timer. Mic button gets a red bg + 1s breathing animation.
- `onLongPressMoveUpdate`: if dx < -50 from start, show "Release to cancel" hint; on release, cancel.
- `onLongPressEnd` (no cancel): stop session, get final transcription, send as a chat message via existing `chatProvider.sendMessage`.
- Tap (no hold): show one-time tooltip `"Hold to record voice message"` via `OverlayEntry`. Don't start a 0.5s recording.

**Asset:** none new. `Icons.mic` and `Icons.arrow_upward` are Material defaults.

### 5.6 — Voice = FREE (F13)

**Files:**
- `lib/core/services/subscription_service.dart` — `_highValueFeatures` set
- `lib/core/constants/app_constants.dart` — feature key constant
- `lib/features/ai_coach/screens/ai_coach_screen.dart` — drop lock badge from mic

**Change:**

- Remove `AppConstants.featureVoiceNotes` from the `_highValueFeatures` set in `subscription_service.dart`.
- Update CLAUDE.md §10: move `voice_notes` from "PRO — ₹349/month or ₹2,999/year" to "FREE Forever".
- Remove the lock badge rendering from the mic button.

**Why this is safe to ship:**

The `speech_to_text` package uses the device's native speech recognition (Google `SpeechRecognizer` on Android, Apple Speech framework on iOS). Transcription happens on-device (or via Google/Apple — never our infra). Cost to us per voice message = same as a typed message (one Gemini call). Gating it added zero margin while reducing engagement.

### 5.7 — Free image upload + 5 lifetime analyses + paywall (F14)

**Files:**
- `lib/features/ai_coach/screens/ai_coach_screen.dart` — drop hard PRO gate on attach button (allow upload regardless of tier)
- `supabase/functions/ai-media-proxy/index.ts` — add free-tier counter logic
- `lib/features/ai_coach/repositories/ai_coach_repository.dart` — read counter for UI display

**Server-side (`ai-media-proxy/index.ts`):**

After the existing JWT check + image storage to Supabase Storage:

```ts
const isPro = await checkUserIsPro(userId);
const isVideo = mediaType === 'video';

if (isVideo && !isPro) {
  // F15 — video analysis is always PRO
  return jsonResponse({
    role: 'assistant',
    content: COPY.videoPaywall,
    mediaUrl: storedUrl,            // photo persists for 30-day TTL
    paywall: { feature: 'video_analysis' }
  });
}

if (!isPro) {
  // F14 — image free-analysis count
  const used = await countRows(supabaseClient, 'ai_coach_interactions', {
    user_id: userId,
    channel: 'free_image_analysis',
  });
  if (used >= 5) {
    return jsonResponse({
      role: 'assistant',
      content: COPY.imagePaywallExhausted,
      mediaUrl: storedUrl,
      paywall: { feature: 'image_analysis' }
    });
  }
}

// Run Gemini Vision analysis (existing flow)
const analysis = await geminiVisionAnalyze(storedUrl, prompt);

if (!isPro && !isVideo) {
  // record the free-tier analysis
  await supabaseClient.from('ai_coach_interactions').insert({
    user_id: userId,
    channel: 'free_image_analysis',
    payload: { storedUrl, analysisLength: analysis.length },
  });
  const remaining = 5 - (used + 1);
  return jsonResponse({
    role: 'assistant',
    content: `${analysis}\n\n${COPY.freeImageCounter(remaining)}`,
    mediaUrl: storedUrl,
  });
}

return jsonResponse({ role: 'assistant', content: analysis, mediaUrl: storedUrl });
```

**Client-side display:**

`AiCoachRepository.fetchFreeImageAnalysisCount()` reads `count(ai_coach_interactions WHERE user_id=current AND channel='free_image_analysis')` for display in the chat reply (server enforces limit; client only displays the count).

### 5.8 — Free video upload + always-PRO analysis + 30 sec cap (F15)

**Files:**
- `lib/features/ai_coach/screens/ai_coach_screen.dart` — picker config
- `supabase/functions/ai-media-proxy/index.ts` — duration validation

**Client-side (Flutter `image_picker`):**

```dart
final XFile? video = await _picker.pickVideo(
  source: ImageSource.gallery,
  maxDuration: const Duration(seconds: 30),
);
```

`maxDuration` limits in-app camera recording to 30 sec. For gallery picks, validate the metadata after pick:

```dart
final videoInfo = await VideoCompress.getMediaInfo(video.path);
final durationMs = videoInfo.duration ?? 0;
if (durationMs > 30000) {
  showSnackbar('Videos must be 30 seconds or less.');
  return;
}
```

**Server-side guard (ai-media-proxy):**

Read the video duration from headers or via `ffprobe` equivalent on the Edge runtime:

```ts
const durationSec = await probeVideoDuration(storedUrl);
if (durationSec > 30) {
  // Delete the stored object before returning — client bypassed the cap
  await supabaseClient.storage.from('coach-media').remove([storagePath]);
  return errorResponse('video too long, max 30s', 400);
}
```

Cap rationale: 30 sec covers form checks, food breakdowns, body comp reads — the legitimate use cases. Anything longer is disproportionately expensive (Gemini Vision scales with video duration) and harder to analyze meaningfully.

### 5.9 — 30-day TTL on free-user media + cron (F16)

**Files:**
- `supabase/migrations/047_clean_orphan_media_cron.sql` (NEW)
- `supabase/functions/clean-orphan-media/index.ts` (NEW)

**Migration:**

```sql
-- 047_clean_orphan_media_cron.sql

-- Schedule a daily 03:00 UTC (08:30 IST) cleanup of free-user media older than 30 days.
SELECT cron.schedule(
  'clean_orphan_media_daily',
  '0 3 * * *',  -- 03:00 UTC daily
  $$
    SELECT net.http_post(
      url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/clean-orphan-media',
      headers := jsonb_build_object(
        'Content-Type','application/json',
        'Authorization','Bearer '||private.morning_alert_get_service_key()
      ),
      body := jsonb_build_object()
    );
  $$
);
```

**Edge Function `clean-orphan-media/index.ts`:**

```ts
// Pseudocode shape; actual auth + paging follows ai-proxy patterns.

const cutoff = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();

// Find storage objects belonging to non-PRO users created before cutoff
const { data: candidates } = await supabaseClient.rpc('find_orphan_coach_media', {
  p_cutoff: cutoff,
});

let deleted = 0;
for (const obj of candidates ?? []) {
  // Re-check user is still non-PRO (they might have upgraded since cron started)
  const isPro = await checkUserIsPro(obj.user_id);
  if (isPro) continue;

  await supabaseClient.storage.from('coach-media').remove([obj.path]);
  deleted++;
}

return jsonResponse({ scanned: candidates.length, deleted });
```

The `find_orphan_coach_media(p_cutoff)` RPC (also defined in migration 047) joins `storage.objects` with `subscriptions` and returns paths owned by free users older than cutoff. Both the SQL function and the Edge Function are idempotent — repeated runs only delete what's still orphan.

### 5.10 — Drop lock badges + paywall on tap + reply copy (F17)

**Files:**
- `lib/features/ai_coach/screens/ai_coach_screen.dart` — remove lock badge widgets from mic + paperclip
- `lib/features/ai_coach/copy/coach_replies.dart` (NEW or `lib/core/copy/...`) — central copy strings

**Lock badges:** the small 🔒 corner badge on attach (and any equivalent on mic pre-F13) is removed. Reasons:
- The UPGRADE pill at the top of the screen already telegraphs the user's free state.
- WhatsApp / ChatGPT / Claude don't put per-button locks. Paywall on tap is the convention.
- Lock badges feel like "you can't have this" rather than "you can have this when you upgrade" — worse for conversion.

**Paywall on tap:** when a free user taps a gated capability, the existing `showPaywallSheet(context, feature: '...')` opens with the appropriate feature label.

**Reply copy templates (new file `coach_replies.dart`):**

```dart
class CoachReplies {
  static const String welcomeBridge =
      'Bridge here, Recruit. Standing by for orders. '
      '*Workouts, nutrition, recovery* — fire away.';

  // F14 — 5 lifetime free image analyses
  static String freeImageCounter(int remaining) {
    if (remaining > 1) {
      return 'ⓘ $remaining of 5 free analyses left. [Upgrade for unlimited →]';
    }
    if (remaining == 1) {
      return 'ⓘ Last free analysis used. [Upgrade for unlimited →]';
    }
    return 'ⓘ You\'ve used your 5 free analyses. [Upgrade →]';
  }

  static const String imagePaywallExhausted =
      'Photo received, Recruit. '
      'You\'ve used your 5 free analyses. '
      '[Upgrade to PRO →] for unlimited image + video reads.';

  // F15 — always-PRO video
  static const String videoPaywall =
      'Video received, Recruit. Bridge sees it. '
      'Video analysis is a *PRO* capability — form checks, technique '
      'breakdowns, posture reviews. [Upgrade →]';
}
```

These constants are imported by both the client (for fallback display) and embedded in the Edge Function reply payloads (via a parallel `coach_replies.ts` constants file in `_shared`). Keeping the strings in code (not in DB / Edge Function memory) makes the localization story easier later.

## 6. Data flow

### 6.1 — Mic↔send state machine (F12)

```
[idle] ──text typed──▶ [text-mode]
   ▲                         │
   │                         │ text cleared
   │ recording sent          ▼
[recording] ◀──long-press──[idle]
   │                         ▲
   ├──release──▶ send transcription ──▶ [idle]
   └──slide left + release──▶ [idle] (cancel)
```

State drives both:
- The trailing icon (`mic` in idle, `arrow_upward` in text-mode, pulsing red `mic` in recording)
- The bubble decoration (default in idle/text-mode, red-bordered in recording)
- The body content (TextField in idle/text-mode, blinking dot + timer + cancel hint in recording)

### 6.2 — Free image analysis quota (F14)

```
free user taps 📎 → media picker → pick image
  ↓
upload to Supabase Storage  ← always succeeds for free + PRO
  ↓
ai-media-proxy receives request
  ↓
isPro?
  yes → analyze + reply (counter not touched)
  no  → query count(ai_coach_interactions WHERE user_id AND channel='free_image_analysis')
        ↓
        count >= 5 → return imagePaywallExhausted reply (no Gemini call)
        count <  5 → analyze + insert counter row + reply with freeImageCounter(remaining)
```

Quota is **lifetime** (never refills). Tracked server-side via row count to make it tamper-resistant.

### 6.3 — Video duration validation (F15)

```
free or PRO user taps 📎 → picks video
  ↓
client picker enforces maxDuration: 30s
  ↓
gallery pick post-validation: ffprobe via VideoCompress
  ↓
if duration > 30s: client reject + show snackbar
  ↓
upload to Supabase Storage
  ↓
ai-media-proxy receives request
  ↓
server-side ffprobe re-check (defense vs client bypass)
  ↓
duration > 30s: delete stored object + return 400
duration <= 30s + free user: store + return videoPaywall reply
duration <= 30s + PRO user: store + analyze + reply
```

### 6.4 — Free-user media TTL (F16)

```
nightly 03:00 UTC cron → POST clean-orphan-media
  ↓
RPC find_orphan_coach_media(cutoff = now - 30 days)
  ↓
returns paths from storage.objects where user is still non-PRO
  ↓
for each: re-check isPro (fresh) → delete from storage if still non-PRO
```

User upgrades to PRO mid-window → next cron run skips them; their media persists indefinitely. User downgrades → next 30-day window applies to anything they upload after downgrade (existing PRO-era media stays per existing retention policy).

## 7. Error handling

- **Header refactors (F8–F11):** pure layout changes; no new error surfaces. Existing providers (greeting, streak, freezes, plan, KCAL) stay untouched. Failure modes inherit from those providers.
- **Mic recording (F12):** `SpeechToText` failures (mic permission denied / hardware unavailable / network drop on cloud-routed transcription) → catch in the existing `try/catch` around the session call, show `SnackBar('Mic unavailable. Try typing instead.')`. Fall back to text input.
- **Image upload (F14):** existing `ai-media-proxy` error envelope (`{error, request_id}`) per the CLAUDE.md "Edge Function Error Sanitization" rule. Client surfaces `"Upload failed — please try again."`
- **Video duration validation (F15):** client-side rejection shows `SnackBar`. Server-side rejection returns `{error: "video too long, max 30s", request_id}` → client maps to `"That video is too long. Maximum 30 seconds."`
- **Cron cleanup (F16):** `clean-orphan-media` per-row failures logged via `_reportSyncFailure`; one row's failure does not block the rest of the batch. Idempotent: failed deletes retried next night.

## 8. Testing strategy

| Layer | Test | Catches |
|---|---|---|
| Widget | `test/home/header_layout_test.dart` (NEW) | Home header is exactly 3 rows + 1 hairline; eyebrow contains DAILY + date + WK + PHASE; no `_buildDateDisplay` callsite |
| Widget | `test/train/header_layout_test.dart` (NEW) | Train header is exactly 3 rows; title is Fraunces 32 sp; subtitle is inlined with progress bar |
| Widget | `test/nutrition/header_layout_test.dart` (NEW) | Nutrition header has DIET PLAN in row 1 right + KCAL bar + streak in row 3 right |
| Widget | `test/ai_coach/header_layout_test.dart` (NEW) | Coach header has eyebrow alone in row 1; counter glued under UPGRADE; no streak strip |
| Widget | `test/ai_coach/input_bar_test.dart` (NEW) | Trailing icon swaps mic↔send on text change; long-press triggers recording state; cancel slide returns to idle |
| Unit | `test/subscription/voice_is_free_test.dart` (NEW) | `_highValueFeatures` does NOT contain `featureVoiceNotes` |
| Contract | `test/contracts/coach_replies_test.dart` (NEW) | `CoachReplies.freeImageCounter(n)` produces correct strings for n=4,1,0 |
| Integration | manual on-device verification post-deploy: (1) Home/Train/Nutrition headers count rows; (2) Coach mic long-press records and sends; (3) free user uploads 6 images, sees 5 analyses + paywall on 6th; (4) free user uploads 31s video, sees client rejection; (5) cron run leaves a free user's photo from day 31 deleted, day 29 photo intact |

The contract test for fan-out coverage from F5 (sync-fanout spec) catches drift in the Hive→cloud direction; these widget tests catch drift in the visual-layout direction.

## 9. Risk register

| Risk | Mitigation |
|---|---|
| Title 32 sp on Train overflows for long phase names ("Hypertrophy Acceleration") | `maxLines: 1, overflow: TextOverflow.ellipsis` on every standardized title. Most phase names fit. Long ones gracefully truncate. |
| Coach welcome message rewrite breaks AI snapshot consistency (the welcome was used by some snapshot field) | Welcome is purely UI, not stored in any snapshot. Verified by grep — only referenced in `chatHistoryProvider` initial state. |
| Mic↔send `AnimatedSwitcher` flicker on rapid text changes | 200 ms morph is fast enough to feel instant; `ValueListenableBuilder` rebuilds only when emptiness changes (not every keystroke). |
| Free user uploads 6 images instantly (5 analyses + paywall on 6th); race condition on counter | Server uses atomic INSERT then count — sequential ordering guaranteed by Postgres. Worst case: user gets a 6th analysis if two uploads race within ms; acceptable. |
| 30-sec video cap rejects a legitimate 31-sec form check, frustrates user | Snackbar copy explains the cap clearly: "Videos must be 30 seconds or less. Try trimming." Client-side cap on camera record means in-app captures never exceed the limit. |
| Cron `clean-orphan-media` deletes a photo a user just uploaded mid-cron-run (race) | RPC returns paths older than `cutoff = now - 30 days`. New uploads have `created_at = now` so they're never within the cutoff window. Race-safe. |
| User upgrades to PRO mid-30-day-window, expects all photos retained | The cron re-checks `isPro` at delete time. If they upgraded between RPC scan and deletion, deletion skips them. |
| Voice = free unlocks abuse vector (someone scripts the API to spam voice messages) | Existing `ai-proxy` per-day rate limit (15 free, unlimited PRO) applies regardless of input modality. Same protection as typed spam. |
| Lock-badge removal confuses users who don't realize media is PRO | Paywall sheet appears on tap with clear "PRO unlocks unlimited image + video analysis" copy. UPGRADE pill at top of screen telegraphs free state. |

## 10. Out of scope

- Profile screen header (locked-no-change per user 2026-05-03)
- `WardScreenHeader` primitive extraction (deferred to Test #10 candidate; ship per-screen edits first)
- Telegram coach channel layout
- Server-side speech-to-text (Whisper)
- Audio-only message uploads (out of scope; only image + video)
- Cross-tab streak placement consistency (intentional flexible standard)
- Localization of `CoachReplies` copy (English-only this batch)
- Cart Auditor / Scan Meal quota changes (different feature, separate gate; left at 3/month free)

## 11. Approval & next step

User locked the F8–F17 scope on 2026-05-03 after iterative mockup review covering Home, Train, Nutrition, Coach (header + input bar + voice/media gating), and explicitly skipped Profile.

**Next:** invoke `superpowers:writing-plans` to convert F1–F17 (this spec + the companion sync-fanout spec) into a single Test #9 implementation plan. Plan should sequence:
1. Sync work first (F1–F7 — lowest risk, validates the codebase before bigger changes)
2. Header refactors per screen (F8–F11 — independent, each verifiable visually)
3. Coach overhaul as one block (F11–F17 — they touch overlapping files, ship together)
4. Cron + Edge Function deploys (F16 + F14/F15 server changes)
5. Manual verification + APK build via `/build-apk` skill

## 12. Scope summary

| # | Theme | Files | Type | Lines |
|---|---|---|---|---|
| F8 | Home header compaction | `home_screen.dart` | Refactor | ~80 (-40 / +40) |
| F9 | Train header compaction + 32 sp title | `train_screen.dart` | Refactor | ~60 (-30 / +30) |
| F10 | Nutrition header compaction | `nutrition_screen.dart` | Refactor | ~50 (-20 / +30) |
| F11 | Coach header restructure + captain-cap avatar + welcome rewrite | `ai_coach_screen.dart` + new SVG asset + chat history initial state | Refactor + asset | ~120 (-80 / +40 + 1 KB asset) |
| F12 | Coach input bar single-bubble + mic↔send morph + recording UX | `ai_coach_screen.dart` | Rewrite | ~250 (replaces ~150) |
| F13 | Voice = free | `subscription_service.dart`, `app_constants.dart`, `CLAUDE.md` | Bug fix | ~6 |
| F14 | Free image upload + 5 lifetime analyses + paywall | `ai-media-proxy/index.ts`, `ai_coach_repository.dart`, `coach_replies.dart` (NEW) | Feature | ~120 |
| F15 | Free video upload + always-PRO + 30 sec cap | `ai_coach_screen.dart`, `ai-media-proxy/index.ts` | Feature | ~80 |
| F16 | 30-day TTL on free-user media + cron | migration 047 + `clean-orphan-media` Edge Function (NEW) | Infra | ~150 |
| F17 | Drop lock badges + paywall on tap + reply copy templates | `ai_coach_screen.dart`, `coach_replies.dart` | Polish | ~40 |
| **Total** | | **~12 files** | | **~960 LOC + 1 migration + 1 new EF + 1 SVG** |

Plus the companion sync-fanout spec (F1–F7): ~165 LOC + 1 contract test.

**Test #9 grand total:** ~1125 LOC + 1 migration + 1 new Edge Function + 1 existing Edge Function update + 1 SVG asset + 6 new test files. Estimate **8–12 hours** of focused work.
