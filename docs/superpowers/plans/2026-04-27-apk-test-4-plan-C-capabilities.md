# APK Test #4 Plan C — Phase 1 Capabilities + Phase 1 Tool Gap-Fills

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship 5 Phase-1 Captain capabilities (induction is in Plan B; this covers the remaining 4) + 4 new server-side tools for Phase 1 (`getPromotionStatus`, `getFormCues`, `getPRTimeline`, `getExerciseHistory`). Make the coach reach into the user's actual story (induction-day commitment, milestones, rank questions) and respond with depth on temporal queries.

**Architecture:** No new infrastructure. Most work is **prompt engineering inside the Captain's Manual** (extends Plan A's manual file) + **rewriting `weekly-recap-ready`** Edge Function in the Captain's voice + **adding 4 new tools to `_shared/tools/`** registered in `tool_dispatcher`. Plus a single new cron Edge Function for the "I see you" callout heuristic.

**Tech Stack:** TypeScript (Edge Functions), Dart (client display of ceremonies), Supabase cron.

**Spec reference:** `docs/superpowers/specs/2026-04-27-ai-coach-brilliance-design.md` §10.1.

**Estimated effort:** 6-10h.

**Depends on:** Plan A (Captain Manual exists, snapshot keys present), Plan B (induction commitment is captured for why-now recall).

---

## Task C1 — Why-now recall (prompt-only)

**Files:**
- Modify: `supabase/functions/_shared/captain_manual.ts`

When user expresses doubt, low motivation, or asks about progression, Captain references their stored `why_now` answer.

- [ ] **C1.1: Append a sub-section to Section 2 (Lt Cdr Contract) of Captain's Manual**

In `supabase/functions/_shared/captain_manual.ts`, inside Section 2, append:

```
WHY-NOW ANCHOR (prompt-driven, no tool):

snapshot.why_now contains the user's verbatim answer to "Why now? What
triggered this enlistment?" — captured at induction.

When the user shows ANY of these signals:
- doubt about the contract or progression
- low motivation language ("I'm not feeling it", "tired", "what's the point")
- adherence dropping (you can see it in snapshot.cadence + recent_logs)
- asks about giving up, switching goals, or pausing

→ Reference their why_now verbatim, in their own words. Do not paraphrase.

Examples:
- snapshot.why_now = "wedding in October, want to look good in suit"
  Captain: "You said October wedding. We're 18 weeks out. Stand to."
- snapshot.why_now = "want to feel strong, not tired all the time"
  Captain: "You said it yourself: feel strong, not tired. That hasn't changed.
  Don't quit at month 2."

Rules:
- Quote their words. Don't sanitize.
- Do not invoke why_now on routine questions (logging a meal, asking about a swap).
  Reserve for inflection moments.
- If snapshot.why_now is null/empty: skip — never invent one.
```

- [ ] **C1.2: Deploy ai-proxy to pick up the updated Manual**

```bash
cd "C:/Upendra/Claude Code/Fitness App"
node .claude/emit_payload.js ai-proxy --auto --functions-dir "../fitness-app-test-4/supabase/functions"
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl ai-proxy ".claude/_payload_ai-proxy.json" false
```

- [ ] **C1.3: Manual smoke check**

Send chat from a user who has why_now = "wedding in October" and a low-motivation message ("I don't feel like training today"). Verify response references the wedding verbatim.

- [ ] **C1.4: Commit**

```bash
git add supabase/functions/_shared/captain_manual.ts
git commit -m "feat(coach): why-now anchor recall in Section 2 of Captain Manual

Captain references snapshot.why_now verbatim during inflection moments
(doubt, low motivation, adherence drops). Skips on routine queries."
```

---

## Task C2 — Promotion ceremonies in voice

**Files:**
- Modify: `supabase/functions/_shared/captain_manual.ts`
- Modify: `lib/features/profile/services/rank_service.dart` (or wherever rank promotions are detected)
- Modify: `supabase/functions/evaluate-rank-promotions/index.ts`

When user advances rank, the existing toast/notification is replaced with a Captain-voice chat message. The promotion writes a `ai_coach_interactions` row with `channel='promotion_ceremony'` so it surfaces in chat history.

- [ ] **C2.1: Add ceremony format to Captain's Manual Section 4**

Append to Section 4 of `captain_manual.ts`:

```
PROMOTION CEREMONY FORMAT:

When a rank promotion fires (the system inserts an ai_coach_interactions row
with channel='promotion_ceremony'), the message body is the ceremony text.
You do not generate this — it is templated server-side.

Format (templated):
"[OldRankAddress], you've completed [N] sessions and held the line [M] weeks.
Promotion: [NewRankDisplay].
Address change: [NewRankAddress].
Carry on."

Example transitions:
- Recruit → Sailor (Seaman 2→1):
  "Recruit, you've completed 7 sessions and held the line 1 week.
   Promotion: Seaman 1st Class. Address change: Sailor. Carry on."
- Sailor → Petty Officer:
  "Sailor, you've completed 60 sessions and held the line 12 weeks.
   Promotion: Petty Officer. Address change: Petty Officer. Carry on."
- Petty Officer → Sub Lieutenant (workout count track):
  "Petty Officer, 100 workouts on the books. You've crossed onto the
   officer track. Promotion: Sub Lieutenant. Carry on."

After a promotion ceremony, all subsequent messages use the new address.
```

- [ ] **C2.2: Update `evaluate-rank-promotions` to write ai_coach_interactions row**

In `supabase/functions/evaluate-rank-promotions/index.ts`, after a successful insertion into `rank_promotions`, also insert into `ai_coach_interactions`:

```typescript
// After rank promotion succeeds:
const ceremonyText = formatPromotionCeremony({
  oldRankAddress: oldAddress,
  newWorkoutCount: totalWorkouts,
  weeksHeld: weeksActive,
  newRankDisplay,
  newRankAddress,
});

await supabase.from('ai_coach_interactions').insert({
  user_id: userId,
  channel: 'promotion_ceremony',
  message: ceremonyText,
  role: 'assistant',
  created_at: new Date().toISOString(),
});
```

Helper `formatPromotionCeremony` lives in `_shared/ceremony_text.ts` (create new file). Returns the formatted string per Section 4 of the Manual.

- [ ] **C2.3: Update client to surface promotion_ceremony rows**

In the AI Coach screen's chat-history loader (`ai_coach_repository.dart` or similar), include `channel='promotion_ceremony'` rows alongside regular chat. Render them with a subtle gold ring or "PROMOTION" eyebrow to distinguish.

- [ ] **C2.4: Test the ceremony format**

Create `test/ai_coach/promotion_ceremony_format_test.dart` (or test the TypeScript helper if you have a Deno test setup):

```dart
test('Sailor → Petty Officer ceremony format matches manual', () {
  final text = formatPromotionCeremony(
    oldAddress: 'Sailor',
    newWorkoutCount: 60,
    weeksHeld: 12,
    newRankDisplay: 'Petty Officer',
    newRankAddress: 'Petty Officer',
  );
  expect(text, contains('Sailor'));
  expect(text, contains('60 sessions'));
  expect(text, contains('12 weeks'));
  expect(text, contains('Promotion: Petty Officer'));
  expect(text, contains('Carry on.'));
});
```

- [ ] **C2.5: Deploy + commit**

```bash
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl evaluate-rank-promotions ...
git add -A
git commit -m "feat(coach): promotion ceremonies in Captain voice

Server: evaluate-rank-promotions writes ai_coach_interactions row with
channel='promotion_ceremony' on every promotion. Body is formatted via
formatPromotionCeremony helper (Section 4 of Captain Manual).

Client: chat history loader surfaces promotion_ceremony rows alongside
regular chat with gold-ring visual distinction."
```

---

## Task C3 — "I see you" callouts (heuristic-driven)

**Files:**
- Create: `supabase/functions/i-see-you-callout/index.ts`
- Create: `supabase/migrations/043_i_see_you_cron.sql`

Cron-driven. Once daily, scans recent activity for "the Captain noticed something" moments. Writes a coach message via `ai_coach_interactions` if a moment is detected. Uses `_shared/proactive_dedup.ts` to prevent same-day duplicates.

- [ ] **C3.1: Define the moments to detect (heuristics)**

Heuristic list (Phase 1, conservative):
1. **Pre-dawn workout** — workout logged with `started_at` time before 06:00 IST
2. **Festival/wedding nutrition hold** — nutrition logged on a known festival day with protein ≥ 90% of target
3. **PR after bad sleep** — workout PR set when previous night's sleep was < 6h
4. **First in-streak Saturday** — workout logged on a Saturday AFTER 14-day streak first appeared
5. **Recovery after slip** — first workout back after a 3+ day gap

Keep list to 5 for Phase 1. Add more in Phase 2.

- [ ] **C3.2: Implement the Edge Function**

```typescript
// supabase/functions/i-see-you-callout/index.ts
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { shouldSendProactive, markProactiveSent } from "../_shared/proactive_dedup.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (_req) => {
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY);
  const { data: users } = await supabase.from("users").select("id");
  if (!users) return new Response(JSON.stringify({ ok: true, processed: 0 }));

  let sent = 0;
  for (const u of users) {
    const moment = await detectMoment(supabase, u.id);
    if (!moment) continue;
    if (!await shouldSendProactive(supabase, u.id, "i_see_you")) continue;

    await supabase.from("ai_coach_interactions").insert({
      user_id: u.id,
      channel: "proactive_i_see_you",
      role: "assistant",
      message: moment.text,
      created_at: new Date().toISOString(),
    });
    await markProactiveSent(supabase, u.id, "i_see_you");
    sent++;
  }
  return new Response(JSON.stringify({ ok: true, sent }));
});

async function detectMoment(supabase: any, userId: string): Promise<{text: string} | null> {
  // Heuristic 1: Pre-dawn workout (last 24h)
  // Heuristic 2: Festival/wedding day with protein hit
  // Heuristic 3: PR after <6h sleep
  // Heuristic 4: First Saturday after 14-day streak
  // Heuristic 5: First workout back after 3+ day gap
  // ... return first matching moment ...
  return null;
}
```

(Full heuristic SQL queries go inside `detectMoment`. Pattern matches §10.1 idea #4 from spec.)

- [ ] **C3.3: Cron registration migration**

```sql
-- 043_i_see_you_cron.sql
SELECT cron.schedule(
  'i-see-you-daily',
  '0 14 * * *',  -- 14:00 UTC = 19:30 IST, after dinner window
  $$
    SELECT net.http_post(
      url := 'https://dedsavbjuwgarrhphgnl.supabase.co/functions/v1/i-see-you-callout',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || private.morning_alert_get_service_key()
      )
    );
  $$
);
```

- [ ] **C3.4: Deploy + apply migration + commit**

```bash
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl i-see-you-callout ".claude/_payload_i-see-you-callout.json" false
# Then apply migration via MCP
git add -A
git commit -m "feat(coach): i-see-you-callout Edge Function + cron (043)

Daily 19:30 IST scan for 5 'noticed something' moments:
1. Pre-dawn workout
2. Festival nutrition hold
3. PR after bad sleep
4. First Saturday in 14-day streak
5. Recovery after 3+ day slip

Writes ai_coach_interactions row with channel='proactive_i_see_you'.
Dedup'd via proactive_dedup helper (one per user per day per type)."
```

---

## Task C4 — Sunday Strategic Brief (rewrite weekly-recap-ready)

**Files:**
- Modify: `supabase/functions/weekly-recap-ready/index.ts`

Existing function delivers a weekly recap. Rewrite the output to follow Captain voice (briefing-style, mirror tone for misses, strategic for plateaus).

- [ ] **C4.1: Read current implementation**

```bash
grep -n "weekly-recap-ready" -r supabase/functions/
cat supabase/functions/weekly-recap-ready/index.ts | head -100
```

Note: existing function probably calls `gemini-2.5-pro` with a prompt asking for a recap. We rewrite the prompt to invoke The Captain explicitly and follow the briefing format.

- [ ] **C4.2: Update the system prompt for weekly-recap**

```typescript
// In supabase/functions/weekly-recap-ready/index.ts, replace the system prompt with:
import { CAPTAIN_MANUAL } from "../_shared/captain_manual.ts";

const systemPrompt = `${CAPTAIN_MANUAL}

You are delivering the SUNDAY STRATEGIC BRIEF — a weekly briefing the user
receives on Sunday at 21:00 IST. Format:

1. HEADER: "Sunday brief — [date]. Stand to."
2. LAST WEEK VERDICT (3-4 lines, briefing tone):
   - Sessions: X/Y completed, [adherence verdict]
   - Volume: [delta vs prior week]
   - Top lift: [exercise + weight + reps]
   - Nutrition: protein avg vs target, fiber if relevant
3. THIS WEEK MISSION (3-4 lines):
   - Sessions scheduled
   - Risk factors (any known event, festival, low sleep trend)
   - One specific focus point
4. CLOSING: command rhythm. "Carry on." or "Stand to."

VOICE: Use mirror tone if adherence < 80%. Strategic tone if user is on a
plateau. Briefing tone otherwise. NO exclamation marks. NO cheap praise.
`;
```

The user prompt remains the snapshot + week stats injection (existing).

- [ ] **C4.3: Deploy + smoke**

```bash
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl weekly-recap-ready ".claude/_payload_weekly-recap-ready.json" false
```

Manually trigger the function for a test user (via dashboard or curl) and verify output:
- Starts with "Sunday brief — [date]. Stand to."
- Has the 3-section structure
- No exclamation marks
- Tone matches user's actual adherence pattern

- [ ] **C4.4: Commit**

```bash
git add supabase/functions/weekly-recap-ready/index.ts
git commit -m "feat(coach): rewrite weekly-recap-ready as Sunday Strategic Brief

System prompt now imports CAPTAIN_MANUAL and instructs Captain-voice output:
4-section structure (header / last-week verdict / this-week mission / close).
Mirror tone for adherence <80%, strategic for plateaus, briefing default.
No exclamation marks, no cheap praise."
```

---

## Task C5 — Tool: getPromotionStatus

**Files:**
- Create: `supabase/functions/_shared/tools/promotion/get_promotion_status.ts`
- Modify: `supabase/functions/_shared/tools/registry.ts`

Server-side tool the Captain calls when user asks deep rank questions ("how do I get to Lt Cdr?", "what's my pace?", "if I do 5/wk how fast?").

- [ ] **C5.1: Define the tool**

```typescript
// supabase/functions/_shared/tools/promotion/get_promotion_status.ts
import { Tool } from "../../tool_types.ts";

export const getPromotionStatus: Tool = {
  name: "getPromotionStatus",
  description: "Returns full rank ladder progression for the user, including ETA at current and plan cadence. Call when user asks about ranks beyond the immediate next promotion (e.g., 'how do I reach Lieutenant Commander?', 'fastest path to Sub Lt?').",
  parameters: {
    type: "object",
    properties: {
      scenario_cadence: {
        type: "number",
        description: "Optional. Workouts/week to project under. If omitted, returns both at user's actual cadence and at plan cadence.",
      },
    },
  },
  execute: async ({ args, userId, supabase }) => {
    // 1. Read user's current state
    const { data: profile } = await supabase
      .from("user_profile")
      .select("current_rank_code, days_per_week")
      .eq("user_id", userId)
      .single();

    // 2. Compute total workouts ever
    const { count: totalWorkouts } = await supabase
      .from("workout_logs")
      .select("*", { count: "exact", head: true })
      .eq("user_id", userId);

    // 3. Compute current streak (consecutive workouts, or week-active gaps)
    // ... use shared helper or inline ...

    // 4. Compute cadence over last 28 days
    // ... query last 28d workout_logs, divide by 4 ...

    // 5. For each rank in the ladder, return: requirements, current_state, remaining, ETA at current_cadence, ETA at plan_cadence
    return {
      ladder: [
        // { code, display, requirements, achieved, eta_current_cadence, eta_plan_cadence }
      ],
      current_rank_code: profile?.current_rank_code,
      cadence: {
        current_4w: /* computed */,
        plan_target: profile?.days_per_week,
      },
    };
  },
};
```

- [ ] **C5.2: Register in tools registry**

In `supabase/functions/_shared/tools/registry.ts`:

```typescript
import { getPromotionStatus } from "./promotion/get_promotion_status.ts";

export const ALL_TOOLS = [
  // ... existing 20 tools ...
  getPromotionStatus,
];
```

- [ ] **C5.3: Deploy ai-proxy and verify tool is exposed**

```bash
node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl ai-proxy ".claude/_payload_ai-proxy.json" false
```

Send chat: *"How do I get to Lieutenant Commander?"* — verify Gemini calls `getPromotionStatus` (visible in logs/tool_calls JSONB).

- [ ] **C5.4: Commit**

```bash
git add -A
git commit -m "feat(coach): tool getPromotionStatus — full rank ladder + ETA scenarios

Captain calls this when user asks about ranks beyond immediate next.
Returns ladder array with achievement state + ETAs at current and plan
cadence. Routed via Section 8 of Captain Manual."
```

---

## Task C6 — Tool: getFormCues

**Files:**
- Create: `supabase/functions/_shared/tools/exercise/get_form_cues.ts`

Returns coaching cues + common mistakes + breathing cue + pro tip for a named exercise. Reads `exercise_library` table.

- [ ] **C6.1: Implement**

```typescript
export const getFormCues: Tool = {
  name: "getFormCues",
  description: "Returns coaching cues, common mistakes, breathing cue, and pro tip for a named exercise. Call when user asks how to do an exercise, asks for form check, or asks 'what should I focus on for X'.",
  parameters: {
    type: "object",
    properties: {
      exercise_name: { type: "string", description: "Exact or close match to exercise_library.name (e.g., 'Bench Press', 'Romanian Deadlift')" },
    },
    required: ["exercise_name"],
  },
  execute: async ({ args, supabase }) => {
    const { data } = await supabase
      .from("exercise_library")
      .select("name, coaching_cues, common_mistakes, breathing_cue, pro_tip, warmup_protocol")
      .ilike("name", args.exercise_name)
      .limit(1)
      .maybeSingle();
    if (!data) {
      return { found: false, exercise_name: args.exercise_name };
    }
    return { found: true, ...data };
  },
};
```

- [ ] **C6.2: Register + commit**

Register in `registry.ts`. Commit:

```bash
git add -A
git commit -m "feat(coach): tool getFormCues — exercise-specific coaching content"
```

---

## Task C7 — Tool: getPRTimeline + getExerciseHistory

**Files:**
- Create: `supabase/functions/_shared/tools/progress/get_pr_timeline.ts`
- Create: `supabase/functions/_shared/tools/progress/get_exercise_history.ts`

Both query `workout_log_exercises` filtered by exercise + optional date range.

- [ ] **C7.1: Implement getPRTimeline**

```typescript
export const getPRTimeline: Tool = {
  name: "getPRTimeline",
  description: "Returns dated personal-record progression for a specific exercise. Call when user asks about PR history, 'when did I last hit PR', 'PR last year', etc.",
  parameters: {
    type: "object",
    properties: {
      exercise_name: { type: "string" },
      from: { type: "string", description: "ISO date, optional" },
      to: { type: "string", description: "ISO date, optional" },
    },
    required: ["exercise_name"],
  },
  execute: async ({ args, userId, supabase }) => {
    let q = supabase
      .from("workout_log_exercises")
      .select("exercise_id, weight_kg, reps, completed_at")
      .eq("user_id", userId)
      .ilike("exercise_id", args.exercise_name)
      .eq("is_pr", true)
      .order("completed_at", { ascending: false });
    if (args.from) q = q.gte("completed_at", args.from);
    if (args.to) q = q.lte("completed_at", args.to);
    const { data } = await q.limit(50);
    return { prs: data ?? [], count: (data ?? []).length };
  },
};
```

- [ ] **C7.2: Implement getExerciseHistory**

```typescript
export const getExerciseHistory: Tool = {
  name: "getExerciseHistory",
  description: "Returns sets logged for a specific exercise over a date range. Call when user asks 'when did I last bench', 'history of squats', or any temporal exercise query.",
  parameters: {
    type: "object",
    properties: {
      exercise_name: { type: "string" },
      from: { type: "string", description: "ISO date, default 30 days ago" },
      to: { type: "string", description: "ISO date, default today" },
    },
    required: ["exercise_name"],
  },
  execute: async ({ args, userId, supabase }) => {
    const from = args.from ?? new Date(Date.now() - 30 * 86400 * 1000).toISOString().substring(0, 10);
    const to = args.to ?? new Date().toISOString().substring(0, 10);
    const { data } = await supabase
      .from("workout_log_exercises")
      .select("exercise_id, weight_kg, reps, set_number, completed_at")
      .eq("user_id", userId)
      .ilike("exercise_id", args.exercise_name)
      .gte("completed_at", from)
      .lte("completed_at", to)
      .order("completed_at", { ascending: false })
      .limit(100);
    return { sessions: data ?? [], from, to, count: (data ?? []).length };
  },
};
```

- [ ] **C7.3: Register both + deploy + commit**

Register in `registry.ts`. Deploy ai-proxy. Smoke test by chat: *"What was my deadlift PR last March?"* — verify tool call logs.

```bash
git add -A
git commit -m "feat(coach): tools getPRTimeline + getExerciseHistory

Both query workout_log_exercises with optional date ranges. Routed via
Section 8 of Captain Manual when user asks temporal queries (forced tool
call rule, no inference from snapshot)."
```

---

## Self-review

- [ ] Spec §10.1 capabilities covered: induction → Plan B; why-now (C1); promotion ceremonies (C2); "I see you" (C3); Sunday brief (C4)
- [ ] Phase 1 tools from spec §8: getPromotionStatus (C5), getFormCues (C6), getPRTimeline + getExerciseHistory (C7) — 4 of 8. Remaining 4 (`getWeakPoints`, `compareWeeks`, `projectWeightETA`, `oneOffEquipmentOverride`) are spec §12.2 explicitly Phase 2 / Test #5.
- [ ] All Captain-voice content matches Section 1 of Manual (no exclamation marks, briefing rhythm, rank-aware address).
- [ ] Deploy + verify steps included for each Edge Function change.

## Out of scope (handled elsewhere)

- Captain Manual base content → Plan A
- Induction flow → Plan B
- Audit P0/P1 cleanup → Plan D
- Phase 2 capabilities (drydock, shore leave, field expedient, honest mirror, adverse signals) → Test #5
- Phase 3 capabilities (watch log, quarterly, dispatches, rank-aware depth) → Test #6
- Lt Cdr inscription → Test #7
- Remaining 4 tools (`getWeakPoints`, `compareWeeks`, `projectWeightETA`, `oneOffEquipmentOverride`) → Test #5
