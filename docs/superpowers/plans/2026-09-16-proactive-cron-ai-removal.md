# Proactive Cron AI Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the Gemini call from 8 cron-dispatched notification functions and `future-prediction`, replacing AI-generated copy with the already-proven deterministic fallback text (or, for `future-prediction`'s numbers, real trend math), for every user tier with no exception.

**Architecture:** For each function, extract its message-building logic (currently inline inside the `serve()` handler, or already a standalone-but-unexported function) into a new sibling file with NO `serve()`/`Deno.serve()` call, so it can be unit-tested without triggering a port bind. `index.ts` imports from that file; the Gemini `try { geminiChat(...) } catch` wrapper is deleted; the deterministic function's result becomes the unconditional message.

**Tech Stack:** Deno (Supabase Edge Functions), TypeScript, `deno test` (std `testing/asserts.ts`), existing `_shared/subscription.ts` and `_shared/rank_engine.ts` helpers.

**Spec:** `docs/superpowers/specs/2026-09-16-proactive-cron-ai-removal-design.md`

## Global Constraints

- No PRO/free branching for AI usage — full removal, every tier (spec Decision section).
- Every deterministic function this plan touches must be **exported** from a new non-serving sibling file (never `index.ts` directly) so `deno test` can import it without binding a port — mirrors the existing `_shared/rank_engine.ts` pattern used by `evaluate-rank-promotions`.
- Copy text is the EXACT approved text from the spec — do not paraphrase, do not "improve" wording beyond what was approved.
- Every task removes the `geminiChat`/`geminiChatWithTools`/raw Gemini `fetch` call from its function's `index.ts` and pins that removal with a source-shape test (`Deno.readTextFile` + string search) matching the convention already established in `supabase/functions/re-engagement/index_test.ts`.
- `re-engagement` already has `supabase/functions/re-engagement/index_test.ts` — ADD to it, do not create a new file. Every other function's `index_test.ts` is new.
- Run tests with: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/<fn>/`
- Type-check with: `deno check --node-modules-dir=none supabase/functions/<fn>/index.ts`
- Per CLAUDE.md §4.4 rule 21, mutate one assertion per task once (temporarily revert the removal) to confirm the new test actually reddens before trusting it green — note in each task where to do this.

---

### Task 1: `pr-detection` — extract message, remove Gemini call

**Files:**
- Create: `supabase/functions/pr-detection/message.ts`
- Modify: `supabase/functions/pr-detection/index.ts:159-189` (delete Gemini try/catch), `:244-265` (delete — moved to `message.ts`)
- Test: `supabase/functions/pr-detection/index_test.ts` (new)

**Interfaces:**
- Produces: `composeMessage(firstName: string, prs: PrRecord[]): string` from `message.ts`, where `PrRecord = { exercise_id: string; weight_kg: number | null; reps: number | null }`.

- [ ] **Step 1: Write the failing test**

```typescript
// supabase/functions/pr-detection/index_test.ts
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { composeMessage } from "./message.ts";

Deno.test("composeMessage: single PR with weight uses the approved copy", () => {
  const msg = composeMessage("Rahul", [
    { exercise_id: "Bench Press", weight_kg: 82.5, reps: null },
  ]);
  assertEquals(msg, "Rahul — new Bench Press 82.5kg PR. Keep going 💪.");
});

Deno.test("composeMessage: single PR with reps only (no weight) falls back to reps phrasing", () => {
  const msg = composeMessage("Rahul", [
    { exercise_id: "Pull-up", weight_kg: null, reps: 15 },
  ]);
  assertStringIncludes(msg, "Pull-up 15 reps PR");
});

Deno.test("composeMessage: two PRs uses the approved two-PR copy", () => {
  const msg = composeMessage("Rahul", [
    { exercise_id: "Bench Press", weight_kg: 82.5, reps: null },
    { exercise_id: "Squat", weight_kg: 110, reps: null },
  ]);
  assertEquals(msg, "Rahul — new PRs: Bench Press 82.5kg, Squat 110kg. Strong session.");
});

Deno.test("composeMessage: three or more PRs shows the +N more tail", () => {
  const msg = composeMessage("Rahul", [
    { exercise_id: "Bench Press", weight_kg: 82.5, reps: null },
    { exercise_id: "Squat", weight_kg: 110, reps: null },
    { exercise_id: "Deadlift", weight_kg: 140, reps: null },
  ]);
  assertEquals(msg, "Rahul — new PRs: Bench Press 82.5kg, Squat 110kg +1 more. Strong session.");
});

Deno.test("composeMessage: empty PR list returns empty string", () => {
  assertEquals(composeMessage("Rahul", []), "");
});

Deno.test("pr-detection no longer calls Gemini — the geminiChat import and call are gone", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("geminiChat(")) {
    throw new Error("expected geminiChat( to be gone from pr-detection/index.ts");
  }
  if (src.includes("import { geminiChat")) {
    throw new Error("expected the geminiChat import to be removed from pr-detection/index.ts");
  }
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/pr-detection/`
Expected: FAIL — `message.ts` does not exist yet (module not found).

- [ ] **Step 3: Create `message.ts` with the extracted, edited function**

```typescript
// supabase/functions/pr-detection/message.ts

/** Minimal shape composeMessage needs — structurally compatible with the
 * richer PRRow used in index.ts's Supabase row type. */
export interface PrRecord {
  exercise_id: string;
  weight_kg: number | null;
  reps: number | null;
}

export function composeMessage(firstName: string, prs: PrRecord[]): string {
  if (prs.length === 0) return "";

  const fmt = (p: PrRecord) => {
    const weight = p.weight_kg ?? 0;
    const reps = p.reps ?? 0;
    if (weight > 0) {
      return `${p.exercise_id} ${weight}kg`;
    }
    return `${p.exercise_id} ${reps} reps`;
  };

  if (prs.length === 1) {
    return `${firstName} — new ${fmt(prs[0])} PR. Keep going 💪.`;
  }
  if (prs.length === 2) {
    return `${firstName} — new PRs: ${fmt(prs[0])}, ${fmt(prs[1])}. Strong session.`;
  }
  const tail = prs.length - 2;
  return `${firstName} — new PRs: ${fmt(prs[0])}, ${fmt(prs[1])} +${tail} more. Strong session.`;
}
```

- [ ] **Step 4: In `index.ts`, delete the local `composeMessage` (`:244-265`), import it from `./message.ts` instead, and delete the Gemini try/catch (`:159-189`) so `message` is unconditionally `composeMessage(firstName, prs)`**

Delete lines 244-265 (the local function). Add near the top imports:
```typescript
import { composeMessage } from "./message.ts";
```
Replace the block that currently reads (approximately `:157-189`):
```typescript
      const fallbackMessage = composeMessage(firstName, prs);
      let message = fallbackMessage;
      try {
        /* ...geminiChat call... */
      } catch (e) { /* ...warn... */ }
```
with:
```typescript
      const message = composeMessage(firstName, prs);
```
Remove the now-unused `geminiChat`, `MODEL_FLASH`, `captainPrompt`, `sanitizeJsonForPrompt` imports IF they are not used elsewhere in this file — check with `grep -n "geminiChat\|MODEL_FLASH\|captainPrompt\|sanitizeJsonForPrompt" supabase/functions/pr-detection/index.ts` after the edit; remove any import whose only use was the deleted block.

- [ ] **Step 5: Run tests to verify they pass**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/pr-detection/`
Expected: PASS (6 tests)

- [ ] **Step 6: Type-check**

Run: `deno check --node-modules-dir=none supabase/functions/pr-detection/index.ts`
Expected: no errors

- [ ] **Step 7: Mutation check (CLAUDE.md §4.4 rule 21)**

Temporarily re-add `if (src.includes("geminiChat("))` — wait, instead: temporarily restore one `geminiChat(` line into `index.ts` (e.g. a stray comment containing the literal text is NOT enough — add back a real call) and confirm the "no longer calls Gemini" test goes RED. Revert immediately after confirming.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/pr-detection/message.ts supabase/functions/pr-detection/index.ts supabase/functions/pr-detection/index_test.ts
sh ../../scripts/safe_commit.sh "fix(pr-detection): remove Gemini call, use approved fallback copy unconditionally"
```

---

### Task 2: `streak-guardian` — extract message, remove Gemini call

**Files:**
- Create: `supabase/functions/streak-guardian/message.ts`
- Modify: `supabase/functions/streak-guardian/index.ts:270-349` (replace the inline branch chain + Gemini try/catch with a single call to the extracted function)
- Test: `supabase/functions/streak-guardian/index_test.ts` (new)

**Interfaces:**
- Produces: `pickStreakMessage(input: StreakInput): { title: string; message: string }` from `message.ts`, where `StreakInput = { streakDays: number; streakWeeks: number; weight: number | null; targetWeight: number | null }`.

- [ ] **Step 1: Write the failing test**

```typescript
// supabase/functions/streak-guardian/index_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { pickStreakMessage } from "./message.ts";

Deno.test("pickStreakMessage: day 7 milestone", () => {
  const r = pickStreakMessage({ streakDays: 7, streakWeeks: 1, weight: null, targetWeight: null });
  assertEquals(r.title, "1 week strong!");
  assertEquals(r.message, "You've hit 7 days straight — that's the hardest week done. Don't stop now!");
});

Deno.test("pickStreakMessage: day 14 milestone", () => {
  const r = pickStreakMessage({ streakDays: 14, streakWeeks: 2, weight: null, targetWeight: null });
  assertEquals(r.title, "2 weeks! You're building a habit.");
  assertEquals(r.message, "14 days of consistency. Most people quit by now — you didn't. Keep going!");
});

Deno.test("pickStreakMessage: day 30 milestone", () => {
  const r = pickStreakMessage({ streakDays: 30, streakWeeks: 4, weight: null, targetWeight: null });
  assertEquals(r.title, "30-day warrior!");
});

Deno.test("pickStreakMessage: day 50 milestone", () => {
  const r = pickStreakMessage({ streakDays: 50, streakWeeks: 7, weight: null, targetWeight: null });
  assertEquals(r.title, "50 days. Legendary.");
});

Deno.test("pickStreakMessage: day 100 milestone", () => {
  const r = pickStreakMessage({ streakDays: 100, streakWeeks: 14, weight: null, targetWeight: null });
  assertEquals(r.title, "100-DAY STREAK!");
});

Deno.test("pickStreakMessage: every-10-day milestone (e.g. 60) uses the templated title/message", () => {
  const r = pickStreakMessage({ streakDays: 60, streakWeeks: 8, weight: null, targetWeight: null });
  assertEquals(r.title, "60-day milestone!");
  assertEquals(r.message, "60 days of showing up. That's elite. Don't let today be the one you miss.");
});

Deno.test("pickStreakMessage: near goal weight (within 2kg) takes priority over the standard nudge", () => {
  const r = pickStreakMessage({ streakDays: 12, streakWeeks: 1, weight: 70, targetWeight: 71 });
  assertEquals(r.title, "Almost at your goal weight!");
});

Deno.test("pickStreakMessage: standard nudge rotates through 4 variants by streakDays % 4, title fixed", () => {
  const seen = new Set<string>();
  for (const days of [11, 12, 13, 15]) {
    const r = pickStreakMessage({ streakDays: days, streakWeeks: 2, weight: null, targetWeight: null });
    assertEquals(r.title, "Don't break your streak!");
    seen.add(r.message);
  }
  assertEquals(seen.size, 4);
});

Deno.test("streak-guardian no longer calls Gemini", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("geminiChat(")) {
    throw new Error("expected geminiChat( to be gone from streak-guardian/index.ts");
  }
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/streak-guardian/`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `message.ts`**

```typescript
// supabase/functions/streak-guardian/message.ts

export interface StreakInput {
  streakDays: number;
  streakWeeks: number;
  weight: number | null;
  targetWeight: number | null;
}

export interface StreakMessage {
  title: string;
  message: string;
}

const STANDARD_VARIANTS = (weeks: number, days: number): string[] => [
  `It's getting late. Your ${weeks}-week streak is waiting for today's workout.`,
  `${days} days of consistency so far. One workout keeps it alive.`,
  `You didn't come this far to only come this far. ${weeks} weeks and counting!`,
  `Your future self will thank you. Log a workout before midnight to keep your streak.`,
];

export function pickStreakMessage(input: StreakInput): StreakMessage {
  const { streakDays, streakWeeks, weight, targetWeight } = input;

  if (streakDays === 7) {
    return { title: "1 week strong!", message: "You've hit 7 days straight — that's the hardest week done. Don't stop now!" };
  }
  if (streakDays === 14) {
    return { title: "2 weeks! You're building a habit.", message: "14 days of consistency. Most people quit by now — you didn't. Keep going!" };
  }
  if (streakDays === 30) {
    return { title: "30-day warrior!", message: "A full month of training. You're in the top 5% of users. Log today to keep it alive!" };
  }
  if (streakDays === 50) {
    return { title: "50 days. Legendary.", message: "Half a century of consistency. This streak is worth protecting — don't miss today!" };
  }
  if (streakDays === 100) {
    return { title: "100-DAY STREAK!", message: "Triple digits. You're officially unstoppable. One workout away from 101!" };
  }
  if (streakDays % 10 === 0 && streakDays > 10) {
    return {
      title: `${streakDays}-day milestone!`,
      message: `${streakDays} days of showing up. That's elite. Don't let today be the one you miss.`,
    };
  }
  if (weight && targetWeight && Math.abs(weight - targetWeight) < 2) {
    return { title: "Almost at your goal weight!", message: "You're within 2kg of your target. Don't miss today — every session counts now." };
  }

  const variants = STANDARD_VARIANTS(streakWeeks, streakDays);
  return { title: "Don't break your streak!", message: variants[streakDays % variants.length] };
}
```

- [ ] **Step 4: In `index.ts`, replace the inline `title`/`fallbackMessage` if/else-if chain and the Gemini try/catch (`:270-349`) with a call to `pickStreakMessage`**

Add import near the top: `import { pickStreakMessage } from "./message.ts";`

Replace the block (approximately `:270-349`, from `// Fallback: hardcoded English messages...` through the end of the Gemini `catch`) with:
```typescript
      const { title, message } = pickStreakMessage({ streakDays, streakWeeks, weight, targetWeight });
```
Remove now-unused `geminiChat`, `MODEL_FLASH`, `captainPrompt`, `sanitizeJsonForPrompt` imports if this was their only remaining use in the file (check with grep as in Task 1 Step 4).

- [ ] **Step 5: Run tests to verify they pass**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/streak-guardian/`
Expected: PASS (9 tests)

- [ ] **Step 6: Type-check**

Run: `deno check --node-modules-dir=none supabase/functions/streak-guardian/index.ts`

- [ ] **Step 7: Mutation check** — temporarily reorder the `streakDays === 7` check to come AFTER the `% 10 === 0` check (a real defect: day 30 and day 50 would misfire through the 7-day arm's neighbors) and confirm at least one test reddens. Revert.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/streak-guardian/message.ts supabase/functions/streak-guardian/index.ts supabase/functions/streak-guardian/index_test.ts
sh ../../scripts/safe_commit.sh "fix(streak-guardian): remove Gemini call, use approved milestone copy unconditionally"
```

---

### Task 3: `plateau-alert` — extract message, remove Gemini call

**Files:**
- Create: `supabase/functions/plateau-alert/message.ts`
- Modify: `supabase/functions/plateau-alert/index.ts:206-235`
- Test: `supabase/functions/plateau-alert/index_test.ts` (new)

**Interfaces:**
- Produces: `buildPlateauMessage(firstName: string | null): string` from `message.ts`.

- [ ] **Step 1: Write the failing test**

```typescript
// supabase/functions/plateau-alert/index_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { buildPlateauMessage } from "./message.ts";

Deno.test("buildPlateauMessage: with a name, greeting is prefixed", () => {
  assertEquals(
    buildPlateauMessage("Rahul"),
    "Rahul — weight hasn't moved in a while. Before we change anything — are you consistently hitting your daily protein target?",
  );
});

Deno.test("buildPlateauMessage: null name (private mode) omits the greeting", () => {
  assertEquals(
    buildPlateauMessage(null),
    "weight hasn't moved in a while. Before we change anything — are you consistently hitting your daily protein target?",
  );
});

Deno.test("plateau-alert no longer calls Gemini", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("geminiChat(")) {
    throw new Error("expected geminiChat( to be gone from plateau-alert/index.ts");
  }
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/plateau-alert/`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `message.ts`**

```typescript
// supabase/functions/plateau-alert/message.ts

export function buildPlateauMessage(firstName: string | null): string {
  const greeting = firstName ? `${firstName} — ` : "";
  return `${greeting}weight hasn't moved in a while. Before we change anything — are you consistently hitting your daily protein target?`;
}
```

- [ ] **Step 4: In `index.ts`, replace `:206-235` (the `fallbackMessage` const + Gemini try/catch) with a call to `buildPlateauMessage`**

Add import: `import { buildPlateauMessage } from "./message.ts";`

Replace with:
```typescript
      const message = buildPlateauMessage(firstName);
```
Remove now-unused `geminiChat`/`MODEL_FLASH`/`captainPrompt`/`sanitizeJsonForPrompt` imports if unused elsewhere.

- [ ] **Step 5: Run tests to verify they pass**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/plateau-alert/`
Expected: PASS (3 tests)

- [ ] **Step 6: Type-check**

Run: `deno check --node-modules-dir=none supabase/functions/plateau-alert/index.ts`

- [ ] **Step 7: Mutation check** — temporarily change `${greeting}weight` to `${greeting}Weight` and confirm the exact-match test reddens. Revert.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/plateau-alert/message.ts supabase/functions/plateau-alert/index.ts supabase/functions/plateau-alert/index_test.ts
sh ../../scripts/safe_commit.sh "fix(plateau-alert): remove Gemini call, use approved copy unconditionally"
```

---

### Task 4: `protein-gap-alert` — extract message, remove Gemini call

**Files:**
- Create: `supabase/functions/protein-gap-alert/message.ts`
- Modify: `supabase/functions/protein-gap-alert/index.ts:288-320` (delete Gemini try/catch), `:393-408` (move `pickQuickFix` into `message.ts`)
- Test: `supabase/functions/protein-gap-alert/index_test.ts` (new)

**Interfaces:**
- Produces: `pickQuickFix(gap: number, diet: string | null): string` and `buildProteinGapMessage(firstName: string | null, gap: number, diet: string | null): string` from `message.ts`.

- [ ] **Step 1: Write the failing test**

```typescript
// supabase/functions/protein-gap-alert/index_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { buildProteinGapMessage, pickQuickFix } from "./message.ts";

Deno.test("pickQuickFix: >=40g gap, veg", () => {
  assertEquals(pickQuickFix(45, "veg"), "Quick fix: 200g paneer + a glass of milk.");
});
Deno.test("pickQuickFix: >=40g gap, vegan counts as veg", () => {
  assertEquals(pickQuickFix(40, "vegan"), "Quick fix: 200g paneer + a glass of milk.");
});
Deno.test("pickQuickFix: >=40g gap, non-veg", () => {
  assertEquals(pickQuickFix(50, "non_veg"), "Quick fix: 150g chicken breast or 4 boiled eggs.");
});
Deno.test("pickQuickFix: >=20g gap, veg", () => {
  assertEquals(pickQuickFix(25, "veg"), "Quick fix: 100g paneer or a scoop of whey.");
});
Deno.test("pickQuickFix: >=20g gap, non-veg", () => {
  assertEquals(pickQuickFix(20, null), "Quick fix: 100g chicken or 3 boiled eggs.");
});
Deno.test("pickQuickFix: <20g gap, veg", () => {
  assertEquals(pickQuickFix(10, "veg"), "Quick fix: a glass of milk + 30g almonds.");
});
Deno.test("pickQuickFix: <20g gap, non-veg", () => {
  assertEquals(pickQuickFix(5, "eggetarian"), "Quick fix: 2 boiled eggs.");
});

Deno.test("buildProteinGapMessage assembles greeting + gap + quick-fix + CTA", () => {
  const msg = buildProteinGapMessage("Rahul", 45, "veg");
  assertEquals(
    msg,
    "Rahul — 45g short on protein today. Quick fix: 200g paneer + a glass of milk. Want a dinner suggestion?",
  );
});

Deno.test("buildProteinGapMessage: null name omits greeting", () => {
  const msg = buildProteinGapMessage(null, 10, "non_veg");
  assertEquals(msg, "10g short on protein today. Quick fix: 2 boiled eggs. Want a dinner suggestion?");
});

Deno.test("protein-gap-alert no longer calls Gemini", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("geminiChat(")) {
    throw new Error("expected geminiChat( to be gone from protein-gap-alert/index.ts");
  }
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/protein-gap-alert/`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `message.ts`**

```typescript
// supabase/functions/protein-gap-alert/message.ts

/**
 * Diet values from user_profile.diet_preference (Indian app enum):
 *   - 'veg' / 'vegan'  → vegetarian suggestions (paneer, milk, almonds)
 *   - 'eggetarian'     → eggs allowed (treated as non-veg for protein density)
 *   - 'non_veg' / null → all options on the table (chicken, eggs)
 */
export function pickQuickFix(gap: number, diet: string | null): string {
  const isVeg = diet === "veg" || diet === "vegan";
  if (gap >= 40) {
    return isVeg
      ? "Quick fix: 200g paneer + a glass of milk."
      : "Quick fix: 150g chicken breast or 4 boiled eggs.";
  }
  if (gap >= 20) {
    return isVeg
      ? "Quick fix: 100g paneer or a scoop of whey."
      : "Quick fix: 100g chicken or 3 boiled eggs.";
  }
  return isVeg
    ? "Quick fix: a glass of milk + 30g almonds."
    : "Quick fix: 2 boiled eggs.";
}

export function buildProteinGapMessage(firstName: string | null, gap: number, diet: string | null): string {
  const quickFix = pickQuickFix(gap, diet);
  const greeting = firstName ? `${firstName} — ` : "";
  return `${greeting}${gap}g short on protein today. ${quickFix} Want a dinner suggestion?`;
}
```

- [ ] **Step 4: In `index.ts`, delete the local `pickQuickFix` (`:393-408`), import both functions from `./message.ts`, and replace `:288-320` (fallback + Gemini try/catch) with a single call**

Add import: `import { buildProteinGapMessage } from "./message.ts";`
Delete the local `pickQuickFix` function entirely (`:393-408`).
Replace the fallback + Gemini block with:
```typescript
      const message = buildProteinGapMessage(firstName, gap, diet);
```
Remove now-unused `geminiChat`/`MODEL_FLASH`/`captainPrompt`/`sanitizeJsonForPrompt` imports if unused elsewhere.

- [ ] **Step 5: Run tests to verify they pass**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/protein-gap-alert/`
Expected: PASS (10 tests)

- [ ] **Step 6: Type-check**

Run: `deno check --node-modules-dir=none supabase/functions/protein-gap-alert/index.ts`

- [ ] **Step 7: Mutation check** — temporarily swap the `gap >= 40` and `gap >= 20` bucket bodies and confirm at least 2 tests reddens. Revert.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/protein-gap-alert/message.ts supabase/functions/protein-gap-alert/index.ts supabase/functions/protein-gap-alert/index_test.ts
sh ../../scripts/safe_commit.sh "fix(protein-gap-alert): remove Gemini call, use approved copy unconditionally"
```

---

### Task 5: `re-engagement` — extract message, remove Gemini call

**Files:**
- Create: `supabase/functions/re-engagement/message.ts`
- Modify: `supabase/functions/re-engagement/index.ts:320-349`
- Test: `supabase/functions/re-engagement/index_test.ts` (EXTEND — do not create new)

**Interfaces:**
- Produces: `buildReengagementMessage(firstName: string | null): string` from `message.ts`.

- [ ] **Step 1: Write the failing test — ADD to the existing file, do not overwrite it**

Append to `supabase/functions/re-engagement/index_test.ts` (keep every existing test in that file untouched):

```typescript
import { buildReengagementMessage } from "./message.ts";

Deno.test("buildReengagementMessage: with a name", () => {
  assertEquals(
    buildReengagementMessage("Rahul"),
    "Rahul — haven't heard from you in a few days. Everything okay? No judgment — just tell me what happened and we reset.",
  );
});

Deno.test("buildReengagementMessage: null name omits greeting", () => {
  assertEquals(
    buildReengagementMessage(null),
    "haven't heard from you in a few days. Everything okay? No judgment — just tell me what happened and we reset.",
  );
});

Deno.test("re-engagement no longer calls Gemini", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("geminiChat(")) {
    throw new Error("expected geminiChat( to be gone from re-engagement/index.ts");
  }
});
```

(The file already imports `assertEquals` from the same std module — do not add a duplicate import; add `buildReengagementMessage` to the existing `import { mapFallbackCandidates } from "./index.ts";` line's neighborhood as a SEPARATE import from `./message.ts` — keep the two imports on separate lines since they come from different files.)

- [ ] **Step 2: Run test to verify the new tests fail**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/re-engagement/`
Expected: the pre-existing tests still pass; the 3 new ones FAIL — module not found.

- [ ] **Step 3: Create `message.ts`**

```typescript
// supabase/functions/re-engagement/message.ts

export function buildReengagementMessage(firstName: string | null): string {
  const greeting = firstName ? `${firstName} — ` : "";
  return `${greeting}haven't heard from you in a few days. Everything okay? No judgment — just tell me what happened and we reset.`;
}
```

- [ ] **Step 4: In `index.ts`, replace `:320-349` (greeting/fallbackMessage + Gemini try/catch) with a call to `buildReengagementMessage`**

Add import: `import { buildReengagementMessage } from "./message.ts";`

Replace with:
```typescript
      const message = buildReengagementMessage(firstName);
```
Remove now-unused `geminiChat`/`MODEL_FLASH`/`captainPrompt`/`sanitizeJsonForPrompt`/`SILENCE_DAYS_FALLBACK` (if `SILENCE_DAYS_FALLBACK` was only used inside the deleted `userState` object — check remaining usages before removing the constant itself, since it may also gate the SQL query elsewhere in the file).

- [ ] **Step 5: Run tests to verify they pass**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/re-engagement/`
Expected: PASS — all pre-existing tests plus the 3 new ones.

- [ ] **Step 6: Type-check**

Run: `deno check --node-modules-dir=none supabase/functions/re-engagement/index.ts`

- [ ] **Step 7: Mutation check** — temporarily drop the em-dash from the greeting template (`"${firstName} "` instead of `"${firstName} — "`) and confirm the with-a-name test reddens. Revert.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/re-engagement/message.ts supabase/functions/re-engagement/index.ts supabase/functions/re-engagement/index_test.ts
sh ../../scripts/safe_commit.sh "fix(re-engagement): remove Gemini call, use approved copy unconditionally"
```

---

### Task 6: `workout-window-closing` — extract message, remove Gemini call

**Files:**
- Create: `supabase/functions/workout-window-closing/message.ts`
- Modify: `supabase/functions/workout-window-closing/index.ts:293-324` (approximately — verify the exact end of the Gemini catch block when editing)
- Test: `supabase/functions/workout-window-closing/index_test.ts` (new)

**Interfaces:**
- Produces: `buildWindowClosingMessage(firstName: string | null, workoutName: string): string` from `message.ts`.

- [ ] **Step 1: Write the failing test**

```typescript
// supabase/functions/workout-window-closing/index_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { buildWindowClosingMessage } from "./message.ts";

Deno.test("buildWindowClosingMessage: with a name and workout name", () => {
  assertEquals(
    buildWindowClosingMessage("Rahul", "Push Day"),
    "Rahul — haven't seen Push Day logged yet. Still happening? Even 20 mins counts.",
  );
});

Deno.test("buildWindowClosingMessage: null name omits greeting", () => {
  assertEquals(
    buildWindowClosingMessage(null, "your workout"),
    "haven't seen your workout logged yet. Still happening? Even 20 mins counts.",
  );
});

Deno.test("workout-window-closing no longer calls Gemini", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("geminiChat(")) {
    throw new Error("expected geminiChat( to be gone from workout-window-closing/index.ts");
  }
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/workout-window-closing/`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `message.ts`**

```typescript
// supabase/functions/workout-window-closing/message.ts

export function buildWindowClosingMessage(firstName: string | null, workoutName: string): string {
  const greeting = firstName ? `${firstName} — ` : "";
  return `${greeting}haven't seen ${workoutName} logged yet. Still happening? Even 20 mins counts.`;
}
```

- [ ] **Step 4: In `index.ts`, replace the fallback + Gemini try/catch block (starting `:293`) with a call to `buildWindowClosingMessage`**

Add import: `import { buildWindowClosingMessage } from "./message.ts";`

Replace with:
```typescript
      const message = buildWindowClosingMessage(firstName, workoutName);
```
Remove now-unused `geminiChat`/`MODEL_FLASH`/`captainPrompt`/`sanitizeJsonForPrompt`/`sanitizeIdentifier` imports IF `sanitizeIdentifier` was only used inside the deleted Gemini `userState` block — check remaining usages first, since `firstName` itself is built with `sanitizeIdentifier` earlier in the file and that call site stays.

- [ ] **Step 5: Run tests to verify they pass**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/workout-window-closing/`
Expected: PASS (3 tests)

- [ ] **Step 6: Type-check**

Run: `deno check --node-modules-dir=none supabase/functions/workout-window-closing/index.ts`

- [ ] **Step 7: Mutation check** — temporarily change "Even 20 mins counts." to "Even 20 minutes counts." and confirm both value tests redden. Revert.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/workout-window-closing/message.ts supabase/functions/workout-window-closing/index.ts supabase/functions/workout-window-closing/index_test.ts
sh ../../scripts/safe_commit.sh "fix(workout-window-closing): remove Gemini call, use approved copy unconditionally"
```

---

### Task 7: `morning-alert` — export existing templates, delete the AI branch

**Files:**
- Create: `supabase/functions/morning-alert/message.ts`
- Modify: `supabase/functions/morning-alert/index.ts:165-259` (move `generateFreeAlert`), `:261-296` (move `generateProLightAlert`), `:298-339` (delete `generateProAlert` entirely), `:440-478` (collapse the 3-branch dispatch to 2 branches)
- Test: `supabase/functions/morning-alert/index_test.ts` (new)

**Interfaces:**
- Produces: `generateFreeAlert(name: string, snapshotJson: Record<string, unknown> | null): string` and `generateProLightAlert(name: string, primaryGoal: string | null): string` from `message.ts` — same signatures as today, just relocated and exported. `sanitizeIdentifier` and `istDayOfWeek` are imported into `message.ts` from their existing `_shared/` locations (check the current import paths at the top of `morning-alert/index.ts` for the exact module specifiers before writing `message.ts`'s imports).

- [ ] **Step 1: Write the failing test**

```typescript
// supabase/functions/morning-alert/index_test.ts
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { generateFreeAlert, generateProLightAlert } from "./message.ts";

Deno.test("generateFreeAlert: 7-day streak milestone", () => {
  const msg = generateFreeAlert("Rahul", { current_streak_days: 7, today_workout_name: "Push Day" });
  assertStringIncludes(msg, "Rahul, you just hit 7 DAYS straight!");
  assertStringIncludes(msg, "Push Day is up today.");
});

Deno.test("generateFreeAlert: 30-day streak milestone", () => {
  const msg = generateFreeAlert("Rahul", { current_streak_days: 30 });
  assertStringIncludes(msg, "30 DAYS, Rahul!");
});

Deno.test("generateFreeAlert: 100 total workouts milestone", () => {
  const msg = generateFreeAlert("Rahul", { total_workouts_done: 100 });
  assertStringIncludes(msg, "100 WORKOUTS, Rahul!");
});

Deno.test("generateFreeAlert: recent PR with weight", () => {
  const msg = generateFreeAlert("Rahul", { recent_pr_exercise: "Bench Press", recent_pr_weight: 82.5 });
  assertStringIncludes(msg, "You hit a new PR on Bench Press (82.5kg) recently!");
});

Deno.test("generateFreeAlert: near goal weight", () => {
  const msg = generateFreeAlert("Rahul", { current_weight_kg: 70, target_weight_kg: 71 });
  assertStringIncludes(msg, "you're within 2kg of your goal weight!");
});

Deno.test("generateFreeAlert: default path with no milestone still returns a full greeting", () => {
  const msg = generateFreeAlert("Rahul", null);
  assertStringIncludes(msg, "Good morning Rahul!");
  assertStringIncludes(msg, "Ready to crush your goals today?");
});

Deno.test("generateProLightAlert: build_muscle goal", () => {
  const msg = generateProLightAlert("Rahul", "build_muscle");
  assertStringIncludes(msg, "Muscle is built one rep at a time");
});

Deno.test("generateProLightAlert: unrecognised goal falls back to the generic line", () => {
  const msg = generateProLightAlert("Rahul", "something_unrecognised");
  assertStringIncludes(msg, "Today is another opportunity to show up for the goals you set.");
});

Deno.test("morning-alert no longer calls generateProAlert or Gemini", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("generateProAlert")) {
    throw new Error("expected generateProAlert to be fully removed from morning-alert/index.ts");
  }
  if (src.includes("geminiChat(")) {
    throw new Error("expected geminiChat( to be gone from morning-alert/index.ts");
  }
  // Regression guard for the dead-metric class this codebase has already
  // hit once (re-engagement's markFailures lesson): a permanently-0/false
  // counter left behind by deleting the AI path is worse than removing it.
  if (src.includes("aiSucceeded") || src.includes("proAlerts")) {
    throw new Error("expected the dead aiSucceeded/proAlerts bookkeeping to be removed, not left at a permanent 0/false");
  }
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/morning-alert/`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `message.ts` — move `generateFreeAlert` and `generateProLightAlert` verbatim, export both, do NOT include `generateProAlert`**

First check the exact import specifiers at the top of `morning-alert/index.ts` for `sanitizeIdentifier` and `istDayOfWeek` (e.g. `from "../_shared/sanitize_for_prompt.ts"` and `from "../_shared/ist_date.ts"` — confirm exact paths before writing). Then:

```typescript
// supabase/functions/morning-alert/message.ts
import { sanitizeIdentifier } from "../_shared/sanitize_for_prompt.ts";
import { istDayOfWeek } from "../_shared/ist_date.ts";

export function generateFreeAlert(
  name: string,
  snapshotJson: Record<string, unknown> | null,
): string {
  const firstName = sanitizeIdentifier(name?.split(" ")[0], {
    fallback: "Champion",
    maxLen: 32,
  });
  const snap = snapshotJson ?? {};
  const streakWeeks = (snap.current_streak_weeks as number) ?? 0;
  const streakDays = (snap.current_streak_days as number) ?? streakWeeks * 7;
  const todayWorkout = snap.today_workout_name as string | null;
  const totalWorkouts = (snap.total_workouts_done as number) ?? 0;
  const recentPR = snap.recent_pr_exercise as string | null;
  const recentPRWeight = snap.recent_pr_weight as number | null;
  const weight = snap.current_weight_kg as number | null;
  const targetWeight = snap.target_weight_kg as number | null;
  const yesterdayCalories = snap.yesterday_calories as number | null;
  const calorieTarget = snap.daily_calorie_target as number | null;

  if (streakDays === 7) {
    return `${firstName}, you just hit 7 DAYS straight! First week complete — that's the hardest one. ${todayWorkout ? `${todayWorkout} is up today.` : "Keep the momentum!"} Let's make it 14!`;
  }
  if (streakDays === 30) {
    return `30 DAYS, ${firstName}! A full month of consistency. You're in the top 5% of AVYA users. ${todayWorkout ? `${todayWorkout} today — let's go!` : "What a milestone!"}`;
  }
  if (streakDays === 50) {
    return `FIFTY DAYS, ${firstName}! Half a century of showing up for yourself. ${todayWorkout ? `${todayWorkout} is scheduled.` : "Legendary consistency."} You're built different.`;
  }
  if (streakDays === 100) {
    return `${firstName}, 100 DAYS! Triple digits. You've done what 99% of people only dream about. ${todayWorkout ? `Day 101 starts with ${todayWorkout}.` : "Unstoppable."}`;
  }

  if (totalWorkouts === 10) {
    return `Good morning ${firstName}! You've completed 10 workouts total — double digits! ${todayWorkout ? `${todayWorkout} is up next.` : "Keep building!"} Every session counts.`;
  }
  if (totalWorkouts === 50) {
    return `${firstName}, 50 workouts logged! That's serious dedication. ${todayWorkout ? `${todayWorkout} today.` : "You're crushing it."} Here's to the next 50!`;
  }
  if (totalWorkouts === 100) {
    return `100 WORKOUTS, ${firstName}! You've put in the work and it shows. ${todayWorkout ? `${todayWorkout} makes it 101.` : "Triple-digit warrior!"} Incredible.`;
  }

  if (recentPR) {
    const prDetail = recentPRWeight ? ` (${recentPRWeight}kg)` : "";
    return `Good morning ${firstName}! You hit a new PR on ${recentPR}${prDetail} recently! Momentum is real. ${todayWorkout ? `${todayWorkout} today — keep pushing.` : "Ride that wave!"}`;
  }

  if (weight && targetWeight && Math.abs(weight - targetWeight) < 2) {
    return `${firstName}, you're within 2kg of your goal weight! So close. ${todayWorkout ? `${todayWorkout} is scheduled today.` : "Every session brings you closer."} Keep going!`;
  }

  if (yesterdayCalories && calorieTarget && Math.abs(yesterdayCalories - calorieTarget) < 100) {
    return `Good morning ${firstName}! Yesterday you nailed your calorie target (${yesterdayCalories} kcal). ${todayWorkout ? `${todayWorkout} today.` : "Keep that precision going!"} Consistency wins.`;
  }

  let message = `Good morning ${firstName}!`;
  if (todayWorkout) {
    message += ` ${todayWorkout} is scheduled today.`;
  } else {
    message += ` Ready to crush your goals today?`;
  }
  if (streakDays > 0) {
    message += ` ${streakDays}-day streak going strong!`;
  } else if (streakWeeks > 0) {
    message += ` ${streakWeeks} week streak going strong!`;
  }
  const dayOfWeek = istDayOfWeek();
  const motivationalLines = [
    "Make today count!",
    "Consistency beats perfection.",
    "One workout at a time.",
    "Your future self will thank you.",
    "Small steps, big results.",
    "Show up for yourself today.",
    "Every rep matters.",
  ];
  message += ` ${motivationalLines[dayOfWeek]}`;
  return message;
}

export function generateProLightAlert(name: string, primaryGoal: string | null): string {
  const firstName = sanitizeIdentifier(name?.split(" ")[0], {
    fallback: "Champion",
    maxLen: 32,
  });
  const goal = (primaryGoal ?? "").toLowerCase();

  if (goal === "build_muscle" || goal.includes("muscle")) {
    return `Good morning ${firstName}! Muscle is built one rep at a time — and today's another rep on the journey. Train hard, eat enough, and recover well. Let's get after it.`;
  }
  if (goal === "lose_fat" || goal.includes("fat") || goal.includes("loss")) {
    return `Good morning ${firstName}! Fat loss is won at the dinner table and the gym both. Stay disciplined with your calories today and move your body — small daily wins compound fast.`;
  }
  if (goal === "strength" || goal.includes("strong")) {
    return `Good morning ${firstName}! Strength is a long game. Focus on quality reps, log every set, and chase progressive overload. Today is another deposit in the bank.`;
  }
  if (goal.includes("endurance") || goal.includes("cardio")) {
    return `Good morning ${firstName}! Endurance is built mile by mile. Keep showing up, keep moving, and your aerobic base will thank you. Make today count.`;
  }
  if (goal === "general_fitness" || goal.includes("general") || goal.includes("fit")) {
    return `Good morning ${firstName}! Fitness isn't a destination — it's a daily habit. Move your body today, eat well, hydrate, and rest. You've got this.`;
  }

  return `Good morning ${firstName}! Today is another opportunity to show up for the goals you set. Train smart, eat well, and trust the process. Let's go.`;
}
```

- [ ] **Step 4: In `index.ts`: delete `generateFreeAlert` (`:165-259`), `generateProLightAlert` (`:261-296`), and `generateProAlert` (`:298-339`) entirely; import the first two from `./message.ts`; collapse the 3-branch dispatch (`:440-478`) to 2 branches**

Add import: `import { generateFreeAlert, generateProLightAlert } from "./message.ts";`

Replace the block currently reading (approximately `:438-478`):
```typescript
    let alertMessage: string;
    let msgType: "pro" | "pro_light" | "free" = "free";
    let aiSucceeded = false;

    if (isPro && snapshotJson) {
      /* ...generateProAlert + AI-fail fallback... */
    } else if (isPro && !snapshotJson) {
      /* ...pro-light... */
    } else {
      /* ...free... */
    }
```
with:
```typescript
    let alertMessage: string;
    let msgType: "pro_light" | "free" = "free";

    if (isPro && !snapshotJson) {
      // PRO user with no snapshot (e.g. wasn't active enough yesterday) —
      // goal-aware template instead of the generic free copy.
      const { data: profileRow } = await supabaseClient
        .from("user_profile")
        .select("primary_goal")
        .eq("user_id", user.id)
        .single();

      const primaryGoal = profileRow?.primary_goal ?? null;
      const baseProLight = generateProLightAlert(userName, primaryGoal);
      alertMessage = applyTone(baseProLight, userName, tone, snapshotJson);
      msgType = "pro_light";
      proLightAlerts++;
    } else {
      // Everyone else — PRO with a snapshot included, now that there is no
      // AI path left to prefer for them.
      const baseFree = generateFreeAlert(userName, snapshotJson);
      alertMessage = applyTone(baseFree, userName, tone, snapshotJson);
      msgType = "free";
      freeAlerts++;
    }
```
Also update the log line just below (was `:481-483`) to drop `ai_succeeded=${aiSucceeded}` from the template string, and remove the `proAlerts` counter declaration and its increment site(s) — grep the file for `proAlerts` after this edit to confirm none remain, per the dead-metric lesson already pinned in `re-engagement/index_test.ts`.
Remove now-unused `geminiChat`/`MODEL_FLASH`/`captainPrompt`/`sanitizeJsonForPrompt`/`AI_TIMEOUT_MS` imports/constants if this was their only remaining use.

- [ ] **Step 5: Run tests to verify they pass**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/morning-alert/`
Expected: PASS (9 tests)

- [ ] **Step 6: Type-check**

Run: `deno check --node-modules-dir=none supabase/functions/morning-alert/index.ts`

- [ ] **Step 7: Mutation check** — temporarily change the 7-day streak check to `streakDays === 8` and confirm the corresponding test reddens (falls through to the default path, whose assertion no longer matches). Revert.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/morning-alert/message.ts supabase/functions/morning-alert/index.ts supabase/functions/morning-alert/index_test.ts
sh ../../scripts/safe_commit.sh "fix(morning-alert): remove the AI branch, PRO users with a snapshot use the same deterministic template as everyone else"
```

---

### Task 8: `proactive-coach-promotion` — pure `composeCongrats`, fixes the missing-fallback bug as a side effect

**Files:**
- Create: `supabase/functions/proactive-coach-promotion/congrats.ts`
- Modify: `supabase/functions/proactive-coach-promotion/index.ts:224-291` (replace `composeCongrats` entirely), `:140` (call site — now synchronous, no `await` needed but harmless to keep for interface stability, see step 4)
- Test: `supabase/functions/proactive-coach-promotion/index_test.ts` (new)

**Interfaces:**
- Produces: `composeCongrats(ctx: CongratsContext, rankCode: string, variantIndex?: number): string` from `congrats.ts`, where `CongratsContext = { full_name: string | null; total_workouts_done: number; current_streak_weeks: number; primary_goal: string | null }`. `variantIndex` is optional (defaults to a stable pick — see Step 3) so the test can pin all 3 variants deterministically.

- [ ] **Step 1: Write the failing test**

```typescript
// supabase/functions/proactive-coach-promotion/index_test.ts
import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { composeCongrats } from "./congrats.ts";

const CTX = {
  full_name: "Rahul Sharma",
  total_workouts_done: 34,
  current_streak_weeks: 6,
  primary_goal: "build_muscle",
};

Deno.test("composeCongrats: variant 0 uses the approved copy, interpolated", () => {
  const msg = composeCongrats(CTX, "LS", 0);
  assertEquals(
    msg,
    "Rahul — you've been promoted to Leading Seaman. 34 sessions and a 6-week streak got you here. Every rung on this ladder is earned, not given. Keep training toward muscle gain — the next rank is already waiting.",
  );
});

Deno.test("composeCongrats: variant 1 uses the approved copy", () => {
  const msg = composeCongrats(CTX, "LS", 1);
  assertStringIncludes(msg, "Well earned, Rahul. Leading Seaman now");
});

Deno.test("composeCongrats: variant 2 uses the approved copy (with the founder's edit applied)", () => {
  const msg = composeCongrats(CTX, "LS", 2);
  assertStringIncludes(msg, "Rahul, your new rank: Leading Seaman.");
  // The approved edit dropped the word "report" — pin its absence so a
  // regression can't silently reintroduce the pre-edit wording.
  if (msg.includes("report your new rank")) {
    throw new Error("expected the approved edit (dropped 'report') to be present");
  }
});

Deno.test("composeCongrats: unknown rank code falls back to the raw code as the label", () => {
  const msg = composeCongrats(CTX, "ZZZ", 0);
  assertStringIncludes(msg, "promoted to ZZZ");
});

Deno.test("composeCongrats: null full_name falls back to 'soldier'", () => {
  const msg = composeCongrats({ ...CTX, full_name: null }, "LS", 0);
  assertStringIncludes(msg, "soldier —");
});

Deno.test("composeCongrats: with no variantIndex given, still returns one of the 3 approved variants deterministically", () => {
  const a = composeCongrats(CTX, "LS");
  const b = composeCongrats(CTX, "LS");
  assertEquals(a, b, "same ctx + rankCode with no explicit variantIndex must be deterministic, not random per call");
});

Deno.test("proactive-coach-promotion no longer calls Gemini — no fetch to generativelanguage.googleapis.com", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("generativelanguage.googleapis.com")) {
    throw new Error("expected the raw Gemini fetch endpoint to be gone from proactive-coach-promotion/index.ts");
  }
  if (src.includes("GEMINI_API_KEY")) {
    throw new Error("expected the now-unused GEMINI_API_KEY reference to be removed");
  }
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/proactive-coach-promotion/`
Expected: FAIL — module not found.

- [ ] **Step 3: Create `congrats.ts`**

```typescript
// supabase/functions/proactive-coach-promotion/congrats.ts

export interface CongratsContext {
  full_name: string | null;
  total_workouts_done: number;
  current_streak_weeks: number;
  primary_goal: string | null;
}

const RANK_LABELS: Record<string, string> = {
  SD2: "Seaman 2nd Class",
  SD1: "Seaman 1st Class",
  LS: "Leading Seaman",
  PO: "Petty Officer",
  CPO: "Chief Petty Officer",
  MCPO: "Master Chief Petty Officer",
  SubLt: "Sub Lieutenant",
  Lt: "Lieutenant",
  LtCdr: "Lieutenant Commander",
  Cdr: "Commander",
  Capt: "Captain",
};

function goalToCopy(primaryGoal: string | null): string {
  switch (primaryGoal) {
    case "lose_fat":      return "fat loss";
    case "build_muscle":  return "muscle gain";
    case "gain_strength": return "strength";
    case "general_fitness":
    default:              return "general fitness";
  }
}

/** Mirrors index.ts's existing name-sanitisation call — split on whitespace,
 * fall back to "soldier". Kept local to avoid this file depending on the
 * _shared prompt-sanitiser now that there is no prompt to sanitise for. */
function firstNameOf(fullName: string | null): string {
  const raw = fullName?.split(/\s+/)[0];
  return raw && raw.length > 0 ? raw.slice(0, 32) : "soldier";
}

function variant(idx: number, name: string, rank: string, workouts: number, weeks: number, goal: string): string {
  switch (idx) {
    case 0:
      return `${name} — you've been promoted to ${rank}. ${workouts} sessions and a ${weeks}-week streak got you here. Every rung on this ladder is earned, not given. Keep training toward ${goal} — the next rank is already waiting.`;
    case 1:
      return `Well earned, ${name}. ${rank} now — ${workouts} workouts and ${weeks} weeks of showing up don't lie. Stay locked on ${goal} and the next promotion takes care of itself.`;
    default:
      return `${name}, your new rank: ${rank}. ${workouts} sessions logged, ${weeks}-week streak — that's the record that earned it. Keep pushing toward ${goal}. There's more ground to cover.`;
  }
}

export function composeCongrats(ctx: CongratsContext, rankCode: string, variantIndex?: number): string {
  const rankLabel = RANK_LABELS[rankCode] ?? rankCode;
  const name = firstNameOf(ctx.full_name);
  const goal = goalToCopy(ctx.primary_goal);
  // Deterministic default pick when the caller doesn't pin one: stable across
  // repeat calls for the same rank-up (rotates by rank code, not by a clock
  // or RNG, so a retry or a test never sees a different message than before).
  const idx = variantIndex ?? (rankCode.length + ctx.total_workouts_done) % 3;
  return variant(idx, name, rankLabel, ctx.total_workouts_done, ctx.current_streak_weeks, goal);
}
```

- [ ] **Step 4: In `index.ts`, delete the old `composeCongrats` (`:224-291`) and the module-level `RANK_LABELS`/`GEMINI_API_KEY` it used, import the new one from `./congrats.ts`, and update the call site**

Add import: `import { composeCongrats } from "./congrats.ts";`
Delete the old `async function composeCongrats(...)` body (`:224-291`) and the top-level `RANK_LABELS` const (`:61-73`) and `GEMINI_API_KEY` constant/env read — check for any OTHER use of `GEMINI_API_KEY` in this file before removing the env read (grep first).
At the call site (`:140`), change:
```typescript
    const congrats = await composeCongrats(userCtx, rank_code);
```
to:
```typescript
    const congrats = composeCongrats(userCtx, rank_code);
```
`userCtx` must already have the shape `CongratsContext` expects (`full_name`, `total_workouts_done`, `current_streak_weeks`, `primary_goal`) — confirm by reading `loadUserContext`'s return type in the same file; if any field name differs, adjust `congrats.ts`'s `CongratsContext` interface to match the REAL field names rather than renaming the caller's data.

- [ ] **Step 5: Run tests to verify they pass**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/proactive-coach-promotion/`
Expected: PASS (7 tests)

- [ ] **Step 6: Type-check**

Run: `deno check --node-modules-dir=none supabase/functions/proactive-coach-promotion/index.ts`

- [ ] **Step 7: Mutation check** — temporarily change `idx % 3` to `idx % 2` in `congrats.ts` and confirm the "no variantIndex" determinism test still passes but manually verify variant 2 becomes unreachable for at least one rank/workout combination used by the fixed-variant tests (an easier direct mutation: change `RANK_LABELS.LS` to a different string and confirm 3 tests redden). Revert.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/proactive-coach-promotion/congrats.ts supabase/functions/proactive-coach-promotion/index.ts supabase/functions/proactive-coach-promotion/index_test.ts
sh ../../scripts/safe_commit.sh "fix(proactive-coach-promotion): remove Gemini call, always compose a deterministic congrats — closes the missing-fallback gap where a Gemini hiccup silently dropped a user's promotion"
```

---

### Task 9: `future-prediction` (part A) — remove the AI path, `generateLocalPrediction` becomes unconditional

**Files:**
- Modify: `supabase/functions/future-prediction/index.ts:27-125` (delete `generatePrediction`), `:340-360` (collapse the isPro branch)
- Test: `supabase/functions/future-prediction/index_test.ts` (new — Task 10 extends this same file)

**Interfaces:**
- Consumes: nothing new yet — `generateLocalPrediction` keeps its CURRENT synchronous signature `(profile, progress) => Record<string, unknown>` in this task. Task 10 changes that signature; this task only removes the AI branch so each task is independently reviewable.

- [ ] **Step 1: Write the failing test**

```typescript
// supabase/functions/future-prediction/index_test.ts
import { assertEquals } from "https://deno.land/std@0.224.0/testing/asserts.ts";
import { generateLocalPrediction } from "./index.ts";

Deno.test("generateLocalPrediction is exported and still callable with the existing (profile, progress) signature", () => {
  const result = generateLocalPrediction(
    { current_weight_kg: 80, target_weight_kg: 75, primary_goal: "lose_fat", days_per_week: 4 },
    { detected_experience_level: "intermediate", total_workouts_done: 20, current_streak_weeks: 3, current_phase: 2 },
  );
  assertEquals(typeof result.predicted_weight_kg, "number");
  assertEquals(result.source, "local");
});

Deno.test("future-prediction no longer calls Gemini for predictions — generatePrediction and the isPro AI branch are gone", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (src.includes("async function generatePrediction")) {
    throw new Error("expected generatePrediction to be removed from future-prediction/index.ts");
  }
  if (src.includes("geminiChat(")) {
    throw new Error("expected geminiChat( to be gone from future-prediction/index.ts");
  }
  if (/isPro\s*\|\|\s*trigger\s*===\s*"onboarding"/.test(src)) {
    throw new Error("expected the isPro-gates-AI branch to be gone");
  }
});
```

Note: importing `./index.ts` here is safe only because `future-prediction`'s `serve(...)` call reads `Deno.env.get(...)` values that must be set first — check the top of the current file for any `!`-asserted env reads executed at module scope (e.g. `Deno.env.get("SUPABASE_URL")!`) and set them via `Deno.env.set(...)` at the TOP of this test file, BEFORE the `import` line, exactly as `ai-media-proxy/index_test.ts` does — a static top-of-file `import` is safe here specifically because Task 9/10 do not need to dynamically import after setting env (confirm this by checking whether `future-prediction/index.ts` throws synchronously at module scope if an env var is missing; if it does, use the dynamic `await import("./index.ts")` pattern from `ai-media-proxy/index_test.ts` instead of a static import).

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/future-prediction/`
Expected: FAIL — `generateLocalPrediction` is not exported yet.

- [ ] **Step 3: In `index.ts`: delete `generatePrediction` (`:27-125`) entirely, add `export` to `generateLocalPrediction`'s declaration, and collapse the isPro branch**

Delete the whole `async function generatePrediction(...)` block (`:27-125`).
Change `function generateLocalPrediction(` to `export function generateLocalPrediction(`.
Replace (approximately `:340-368`):
```typescript
    const { data: activeSubscription } = await supabaseClient
      .from("subscriptions")
      .select("status")
      .eq("user_id", userId)
      .eq("status", "active")
      .gt("end_date", new Date().toISOString())
      .limit(1)
      .single();

    const isPro = !!activeSubscription;

    let prediction: Record<string, unknown> | null = null;

    if (isPro || trigger === "onboarding") {
      prediction = await generatePrediction(
        profileData as Record<string, unknown>,
        progress as Record<string, unknown>,
      );
    }

    if (!prediction) {
      prediction = generateLocalPrediction(
        profileData as Record<string, unknown>,
        progress as Record<string, unknown>,
      );
    }
```
with:
```typescript
    const prediction = generateLocalPrediction(
      profileData as Record<string, unknown>,
      progress as Record<string, unknown>,
    );
```
Remove the now-unused `geminiChat`/`MODEL_FLASH` import and the `trigger` variable's read IF `trigger` is not used anywhere else in the file (grep first — it is also written into the response metadata a few lines below at `prediction.trigger = trigger;`, so it almost certainly stays; only the subscription-status query and the `isPro`/branch logic are dead).

- [ ] **Step 4: Run tests to verify they pass**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/future-prediction/`
Expected: PASS (2 tests)

- [ ] **Step 5: Type-check**

Run: `deno check --node-modules-dir=none supabase/functions/future-prediction/index.ts`

- [ ] **Step 6: Mutation check** — temporarily reinstate a bare call to a stub `generatePrediction` and confirm the "generatePrediction is removed" test reddens. Revert.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/future-prediction/index.ts supabase/functions/future-prediction/index_test.ts
sh ../../scripts/safe_commit.sh "fix(future-prediction): remove the Gemini prediction path, generateLocalPrediction is now unconditional"
```

---

### Task 10: `future-prediction` (part B) — real trend math in `generateLocalPrediction`

**Files:**
- Create: `supabase/functions/future-prediction/trend.ts`
- Modify: `supabase/functions/future-prediction/index.ts` (rewrite `generateLocalPrediction` to be `async`, take a Supabase client + `userId`, call into `trend.ts`; update its one call site from Task 9 to `await` it and pass the new params)
- Test: `supabase/functions/future-prediction/index_test.ts` (extend — same file Task 9 created)

**Interfaces:**
- Produces from `trend.ts`:
  - `linearRegressionForecast(points: { x: number; y: number }[], forecastXFromLast: number): number | null` — pure. Returns `null` if fewer than 2 points.
  - `predictWeight(rows: { date: string; weight_kg: number }[], fallback: number): number` — needs ≥5 rows spanning ≥14 days, else returns `fallback`.
  - `predictLift(rows: { completed_at: string; weight_kg: number }[], fallback: number): number` — needs ≥2 rows spanning ≥7 days, else returns `fallback`.
  - `predictStreakWeeks(adherenceRate: number | null): number` — `null` (no/insufficient data or the -1.0 error sentinel) returns the existing flat heuristic value passed in by the caller (see below); otherwise `Math.min(13, Math.max(0, Math.round(adherenceRate * 13)))`.
- Consumes (from `_shared/rank_engine.ts`, already exists): `completionRateOverWindow(supabase: SupabaseClient, userId: string, windowWeeks: number): Promise<number>` (returns `-1.0` on error, `0.0`–`1.0` otherwise).

- [ ] **Step 1: Write the failing test — append to the existing `index_test.ts`**

```typescript
import {
  linearRegressionForecast,
  predictLift,
  predictStreakWeeks,
  predictWeight,
} from "./trend.ts";

Deno.test("linearRegressionForecast: perfect line, forecast beyond the data", () => {
  // y = 70 - 0.1*x  (losing 0.1kg per day)
  const points = [{ x: 0, y: 70 }, { x: 10, y: 69 }, { x: 20, y: 68 }, { x: 30, y: 67 }];
  const result = linearRegressionForecast(points, 90 - 30); // 90 days from the LAST point (x=30)
  // forecast at x=90: 70 - 0.1*90 = 61
  assertEquals(result !== null && Math.abs(result - 61) < 0.01, true);
});

Deno.test("linearRegressionForecast: fewer than 2 points returns null", () => {
  assertEquals(linearRegressionForecast([{ x: 0, y: 70 }], 90), null);
  assertEquals(linearRegressionForecast([], 90), null);
});

Deno.test("predictWeight: sufficient history (>=5 rows, >=14 days) uses the regression, not the fallback", () => {
  const rows = [
    { date: "2026-08-01", weight_kg: 80 },
    { date: "2026-08-06", weight_kg: 79.5 },
    { date: "2026-08-11", weight_kg: 79 },
    { date: "2026-08-16", weight_kg: 78.5 },
    { date: "2026-08-21", weight_kg: 78 },
  ];
  const result = predictWeight(rows, 999 /* obviously-not-fallback sentinel */);
  assertEquals(result === 999, false);
});

Deno.test("predictWeight: insufficient history (only 3 rows) returns the fallback verbatim", () => {
  const rows = [
    { date: "2026-08-01", weight_kg: 80 },
    { date: "2026-08-06", weight_kg: 79.5 },
    { date: "2026-08-11", weight_kg: 79 },
  ];
  assertEquals(predictWeight(rows, 76.5), 76.5);
});

Deno.test("predictWeight: enough ROWS but spanning under 14 days still falls back (dense logging over a short window is not a trend)", () => {
  const rows = [
    { date: "2026-08-01", weight_kg: 80 },
    { date: "2026-08-02", weight_kg: 79.9 },
    { date: "2026-08-03", weight_kg: 79.8 },
    { date: "2026-08-04", weight_kg: 79.7 },
    { date: "2026-08-05", weight_kg: 79.6 },
  ];
  assertEquals(predictWeight(rows, 76.5), 76.5);
});

Deno.test("predictLift: 2 PRs spanning >=7 days uses the regression", () => {
  const rows = [
    { completed_at: "2026-07-01T00:00:00Z", weight_kg: 80 },
    { completed_at: "2026-08-01T00:00:00Z", weight_kg: 85 },
  ];
  const result = predictLift(rows, 999);
  assertEquals(result === 999, false);
});

Deno.test("predictLift: fewer than 2 PRs falls back", () => {
  assertEquals(predictLift([{ completed_at: "2026-08-01T00:00:00Z", weight_kg: 80 }], 60), 60);
  assertEquals(predictLift([], 60), 60);
});

Deno.test("predictStreakWeeks: maps adherence rate onto the existing 13-week ceiling", () => {
  assertEquals(predictStreakWeeks(1.0), 13);
  assertEquals(predictStreakWeeks(0.5), 7); // round(0.5*13) = round(6.5) = 7
  assertEquals(predictStreakWeeks(0), 0);
});

Deno.test("predictStreakWeeks: null (insufficient data / error sentinel) falls back to the given flat value", () => {
  assertEquals(predictStreakWeeks(null, 8), 8);
});

Deno.test("generateLocalPrediction is now async and calls the trend helpers (source-shape — the real DB-backed path needs live env)", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  if (!/export\s+async\s+function\s+generateLocalPrediction/.test(src)) {
    throw new Error("expected generateLocalPrediction to be async");
  }
  if (!src.includes("predictWeight(") || !src.includes("predictLift(") || !src.includes("predictStreakWeeks(")) {
    throw new Error("expected generateLocalPrediction to call all three trend.ts helpers");
  }
  if (!src.includes("completionRateOverWindow(")) {
    throw new Error("expected generateLocalPrediction to reuse the existing completionRateOverWindow helper, not reimplement adherence-rate math");
  }
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/future-prediction/`
Expected: FAIL — `trend.ts` does not exist.

- [ ] **Step 3: Create `trend.ts`**

```typescript
// supabase/functions/future-prediction/trend.ts

export interface Point {
  x: number;
  y: number;
}

/**
 * Least-squares linear regression. `forecastXFromLast` is measured from the
 * LAST point in `points` (not from x=0), so callers pass e.g. 90 to mean
 * "90 days after the most recent data point", regardless of how the x-axis
 * itself is scaled.
 */
export function linearRegressionForecast(points: Point[], forecastXFromLast: number): number | null {
  if (points.length < 2) return null;
  const n = points.length;
  const xMean = points.reduce((s, p) => s + p.x, 0) / n;
  const yMean = points.reduce((s, p) => s + p.y, 0) / n;
  let num = 0;
  let den = 0;
  for (const p of points) {
    num += (p.x - xMean) * (p.y - yMean);
    den += (p.x - xMean) * (p.x - xMean);
  }
  if (den === 0) return points[points.length - 1].y; // all same x — no trend, hold last value
  const slope = num / den;
  const intercept = yMean - slope * xMean;
  const lastX = points[points.length - 1].x;
  return intercept + slope * (lastX + forecastXFromLast);
}

const DAY_MS = 24 * 60 * 60 * 1000;

export function predictWeight(rows: { date: string; weight_kg: number }[], fallback: number): number {
  if (rows.length < 5) return fallback;
  const first = new Date(rows[0].date).getTime();
  const last = new Date(rows[rows.length - 1].date).getTime();
  if ((last - first) / DAY_MS < 14) return fallback;
  const points = rows.map((r) => ({ x: (new Date(r.date).getTime() - first) / DAY_MS, y: r.weight_kg }));
  const forecast = linearRegressionForecast(points, 90);
  return forecast === null ? fallback : Math.round(forecast * 10) / 10;
}

export function predictLift(rows: { completed_at: string; weight_kg: number }[], fallback: number): number {
  if (rows.length < 2) return fallback;
  const first = new Date(rows[0].completed_at).getTime();
  const last = new Date(rows[rows.length - 1].completed_at).getTime();
  if ((last - first) / DAY_MS < 7) return fallback;
  const points = rows.map((r) => ({ x: (new Date(r.completed_at).getTime() - first) / DAY_MS, y: r.weight_kg }));
  const forecast = linearRegressionForecast(points, 90);
  return forecast === null ? fallback : Math.round(forecast);
}

export function predictStreakWeeks(adherenceRate: number | null, fallback = 8): number {
  if (adherenceRate === null || adherenceRate < 0) return fallback;
  return Math.min(13, Math.max(0, Math.round(adherenceRate * 13)));
}
```

- [ ] **Step 4: Run the trend.ts unit tests to verify they pass (generateLocalPrediction rewrite comes next, in the same task)**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/future-prediction/`
Expected: the 9 `trend.ts` tests PASS; the `generateLocalPrediction is now async` source-shape test still FAILS (expected — not rewritten yet).

- [ ] **Step 5: Rewrite `generateLocalPrediction` in `index.ts` to be async, DB-backed, and use `trend.ts`**

Add imports:
```typescript
import { predictLift, predictStreakWeeks, predictWeight } from "./trend.ts";
import { completionRateOverWindow } from "../_shared/rank_engine.ts";
```

Replace the existing `export function generateLocalPrediction(...)` body with:
```typescript
export async function generateLocalPrediction(
  supabase: SupabaseClient,
  userId: string,
  profile: Record<string, unknown>,
  progress: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const currentWeight = (profile.current_weight_kg as number) ?? 70;
  const targetWeight = (profile.target_weight_kg as number) ?? currentWeight;
  const goal = (profile.primary_goal as string) ?? "general_fitness";
  const experience = (progress.detected_experience_level as string) ?? "beginner";
  const daysPerWeek = (profile.days_per_week as number) ?? 3;

  // Static formulas stay as the FALLBACK for each field individually —
  // never all-or-nothing.
  const weightFallback = Math.round((currentWeight + (targetWeight - currentWeight) * 0.3) * 10) / 10;
  const liftMultipliers: Record<string, Record<string, number>> = {
    beginner: { squat: 0.8, bench: 0.5, deadlift: 1.0 },
    intermediate: { squat: 1.2, bench: 0.8, deadlift: 1.5 },
    advanced: { squat: 1.5, bench: 1.1, deadlift: 1.8 },
  };
  const multipliers = liftMultipliers[experience] ?? liftMultipliers.beginner;
  const liftFallback = {
    squat: Math.round(currentWeight * multipliers.squat),
    bench: Math.round(currentWeight * multipliers.bench),
    deadlift: Math.round(currentWeight * multipliers.deadlift),
  };
  const streakFallback = Math.min(daysPerWeek >= 4 ? 10 : 8, 13);

  const since90 = new Date(Date.now() - 90 * 24 * 3600 * 1000).toISOString().slice(0, 10);
  const { data: weightRows } = await supabase
    .from("weight_logs")
    .select("date, weight_kg")
    .eq("user_id", userId)
    .gte("date", since90)
    .order("date", { ascending: true });

  const predictedWeight = predictWeight(
    (weightRows ?? []).map((r) => ({ date: r.date as string, weight_kg: r.weight_kg as number })),
    weightFallback,
  );

  async function liftPrediction(matchSubstring: string, fallback: number): Promise<number> {
    const { data: rows } = await supabase
      .from("workout_log_exercises")
      .select("completed_at, weight_kg")
      .eq("user_id", userId)
      .eq("is_pr", true)
      .ilike("exercise_id", `%${matchSubstring}%`)
      .order("completed_at", { ascending: true });
    return predictLift(
      (rows ?? []).map((r) => ({ completed_at: r.completed_at as string, weight_kg: r.weight_kg as number })),
      fallback,
    );
  }

  const [squatKg, benchKg, deadliftKg] = await Promise.all([
    liftPrediction("squat", liftFallback.squat),
    liftPrediction("bench", liftFallback.bench),
    liftPrediction("deadlift", liftFallback.deadlift),
  ]);

  const adherenceRate = await completionRateOverWindow(supabase, userId, 4);
  const predictedStreak = predictStreakWeeks(adherenceRate < 0 ? null : adherenceRate, streakFallback);

  const taglines: Record<string, string[]> = {
    build_muscle: [
      "Stronger than yesterday, every single day.",
      "Your muscles are waiting to grow — let's make it happen.",
    ],
    lose_fat: [
      "Every kg lost is a victory earned.",
      "Your transformation starts with today's workout.",
    ],
    general_fitness: [
      "Fitter, faster, stronger — that's your 90-day story.",
      "The best version of you is 90 days away.",
    ],
    strength: [
      "Prepare to surprise yourself with what you can lift.",
      "Heavy iron, strong mind — your future is powerful.",
    ],
  };
  const goalTaglines = taglines[goal] ?? taglines.general_fitness;
  const tagline = goalTaglines[Math.floor(Math.random() * goalTaglines.length)];

  return {
    predicted_weight_kg: predictedWeight,
    predicted_bf_pct: null,
    predicted_lifts: { squat_kg: squatKg, bench_kg: benchKg, deadlift_kg: deadliftKg },
    predicted_streak_weeks: predictedStreak,
    confidence: "medium",
    tagline,
    source: "local",
  };
}
```

Note the exact `SupabaseClient` type import at the top of `index.ts` (it already imports one for other queries in the file — reuse that same import, do not add a second one).

- [ ] **Step 6: Update the Task 9 call site to await the new signature**

Change:
```typescript
    const prediction = generateLocalPrediction(
      profileData as Record<string, unknown>,
      progress as Record<string, unknown>,
    );
```
to:
```typescript
    const prediction = await generateLocalPrediction(
      supabaseClient,
      userId,
      profileData as Record<string, unknown>,
      progress as Record<string, unknown>,
    );
```
(confirm the exact names `supabaseClient` and `userId` against what's already in scope at that point in the file — they are used by the subscription/profile queries immediately above this call site.)

- [ ] **Step 7: Update the Task 9 "is exported and still callable" test — the signature changed**

Replace that earlier test (from Task 9 Step 1) with:
```typescript
Deno.test("generateLocalPrediction falls back to the static formulas when there is no history at all", async () => {
  let call = 0;
  const stubSupabase = {
    from() {
      return {
        select() { return this; },
        eq() { return this; },
        gte() { return this; },
        ilike() { return this; },
        order() { call++; return Promise.resolve({ data: [] }); },
      };
    },
  } as unknown as Parameters<typeof generateLocalPrediction>[0];

  const result = await generateLocalPrediction(
    stubSupabase,
    "u1",
    { current_weight_kg: 80, target_weight_kg: 75, primary_goal: "lose_fat", days_per_week: 4 },
    { detected_experience_level: "intermediate" },
  );
  assertEquals(result.predicted_weight_kg, 78.5); // 80 + (75-80)*0.3
  assertEquals(result.source, "local");
  assertEquals(call > 0, true);
});
```
Import `generateLocalPrediction` alongside the other `./index.ts` import already at the top of the test file (from Task 9 Step 1) — it is the same import line, just add the name.

- [ ] **Step 8: Run all tests to verify they pass**

Run: `deno test --no-check --allow-all --node-modules-dir=none supabase/functions/future-prediction/`
Expected: PASS (all `trend.ts` tests + the rewritten `generateLocalPrediction` tests + the Task 9 source-shape tests)

- [ ] **Step 9: Type-check**

Run: `deno check --node-modules-dir=none supabase/functions/future-prediction/index.ts`

- [ ] **Step 10: Mutation check** — temporarily change `predictWeight`'s day threshold from `14` to `1` and confirm the "spanning under 14 days still falls back" test reddens. Revert. Separately, temporarily hardcode `predictStreakWeeks` to always return `8` and confirm the "maps adherence rate" test reddens. Revert.

- [ ] **Step 11: Commit**

```bash
git add supabase/functions/future-prediction/trend.ts supabase/functions/future-prediction/index.ts supabase/functions/future-prediction/index_test.ts
sh ../../scripts/safe_commit.sh "feat(future-prediction): real trend math over weight/lift/adherence history, per-field fallback to the existing static formulas"
```

---

## Self-Review

**Spec coverage:** All 9 functions from the spec's "Per-function changes" section have a task (Tasks 1-9, with `future-prediction` split into 9/10 for independent reviewability). Testing section requirements (Gemini-call-absent assertions, behavioral tests, mutation checks) are present in every task. Rollout section (no feature flag, manual verification for the 2 new pieces) — the 2 new pieces are `proactive-coach-promotion`'s templates (Task 8) and `future-prediction`'s trend math (Task 10); both have thorough test coverage as their "manual verification," and a live smoke test against a real or test account before merge is called out below as a final step, not automatable in this plan.

**Placeholder scan:** No TBD/TODO; every step has real code. Two steps ask the implementer to grep-and-confirm a fact before deleting an import (Task 1 Step 4, Task 5 Step 4, Task 6 Step 4, Task 9 Step 3) rather than asserting it outright — this is deliberate, not a placeholder: the exact current import list wasn't re-verified line-by-line for every file in this planning pass, and grepping before deleting is the safe, correct action, not a deferred decision.

**Type consistency:** `composeCongrats`'s `CongratsContext` field names (`full_name`, `total_workouts_done`, `current_streak_weeks`, `primary_goal`) are flagged in Task 8 Step 4 for verification against `loadUserContext`'s actual return shape — this is the one place a real mismatch is plausible, called out explicitly rather than assumed.

**Final step (not its own task — a pre-merge gate, per the spec's Rollout section):** Before the `--no-ff` merge, smoke-test `proactive-coach-promotion` and `future-prediction` against a real or test account (a manual rank-up trigger; a manual forecast-card open with seeded `weight_logs`/`workout_log_exercises` rows), confirm `docs/architecture/ai.md`'s model matrix and `supabase/functions/CLAUDE.md`'s "9 cron functions call Gemini" list are updated to reflect the new count, run the full `scripts/blast_radius_from_diff.dart` classification on the real diff, and complete the ×2 context-blind plan review + self-triggered `/code-review` B-pass per CLAUDE.md §4.12/§4.3.
