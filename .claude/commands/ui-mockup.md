# /ui-mockup — Side-by-side BEFORE/AFTER HTML mockup

Visualise UI changes as a self-contained HTML mockup before writing any production code. Reads the **actual screen source first** to baseline accurately, then renders the proposed changes alongside in a side-by-side phone-frame layout.

## When to use

- User describes UI changes ("redesign the home header", "merge the macro tiles", "see what this looks like") and wants pixels before approving.
- Multiple UI changes are coming in the same batch — **combine into one mockup file for token efficiency**, never one file per change.
- Need to validate visual direction without touching production Flutter code.

## Steps

1. **Identify the affected screens / widgets** from the user's request.
   Common mappings (verify with grep / glob — don't assume):
   - "home header" → `lib/features/home/screens/home_screen.dart`
   - "today card / macros / today workout" → `lib/features/home/widgets/today_workout_card.dart`
   - "profile" → `lib/features/profile/screens/profile_screen.dart`
   - "rank chip / service record" → `lib/features/profile/widgets/rank_service_record_sheet.dart`
   - "wardroom primitive" → `lib/shared/widgets/wardroom/<name>.dart`

2. **READ THE CODE — baseline accurately, do NOT guess.**
   - `Read` every affected file to see the actual widget tree, padding, typography, colors.
   - Note exact strings, font sizes, padding, border colors, opacity values, conditional renders.
   - If a widget is composed (uses `WardAvatar`, `WardCard`, `StreakBadge`, etc.), read the primitive too.
   - Verify data sources — providers, services — so the BEFORE matches what's actually on device. Example: `userGreetingProvider` returns `'Good morning, Avyaansh.'` (time-aware + first name), NOT `'Welcome back, Avyaansh'`.
   - **Common failure mode**: rendering a card that doesn't exist on that screen. Always confirm a widget is actually rendered before drawing it in BEFORE.

3. **Build the side-by-side HTML mockup.**
   - File path: `docs/mockups/YYYY-MM-DD-<topic>-v<n>.html`
   - Single self-contained HTML file. Only external dependency: Google Fonts (DM Sans + Fraunces + DM Mono).
   - Two phone frames side by side per change cluster: **BEFORE (left, accurate replica)** + **AFTER (right, proposal)**.
   - 360 dp phone frame width to match the project's Android default screen (Wardroom handoff).
   - Use the Wardroom palette as CSS variables (template below). Source of truth = `lib/core/theme/colors.dart` (which mirrors `Knowledgebase/Avya App redesign/design_handoff_wardroom/src/wardroom-tokens.jsx`). **Do NOT use README hex values** — they're rounded for print.
   - Frame labels: BEFORE in `--bad` red, AFTER in `--ok` green.
   - Below the frames: a **"What changed"** panel listing each delta in plain English with token references.

4. **Combine multiple UI changes into ONE file.**
   - If the user has N UI changes (e.g., header redesign + macro merge + profile card), render all N in the same HTML file under separate sections — each with its own BEFORE/AFTER pair.
   - Saves tokens vs. multiple files; lets the user review the full visual language together.
   - Section headers between the change clusters: e.g., `OBS 1 · HOME HEADER`, `OBS 4 · PROFILE STAT CARD`.

5. **Announce + iterate.**
   - The Write tool's hook will surface the file in the Launch preview panel. Tell the user it's visible there and give the file path as a markdown link.
   - Ask 3–5 specific reaction questions on the proposal (font weight, spacing, glyph choice, etc.).
   - Iterate the mockup based on user feedback. **Do NOT touch production code until the visual is locked.**

## Wardroom palette (CSS variables) — copy verbatim

```css
:root {
  --bg: #02070F;
  --bgDeep: #01040A;
  --bgRaise: #04111E;
  --header: #0A1020;
  --card: #06101F;
  --cardHi: #0A1828;
  --input: #0E1E30;
  --border: #1A2C40;
  --line2: rgba(255,250,232,0.08);
  --accent: #D4B270;            /* Campaign Gold — NOT Electric Cyan */
  --accent-33: rgba(212,178,112,0.33);
  --accent-27: rgba(212,178,112,0.27);
  --accent-10: rgba(212,178,112,0.10);
  --textPrimary: #F2EDE4;
  --textDim: #8A9BAA;
  --textMute: #4D6070;
  --textGhost: #2A3848;
  --ok: #7FB4A2;
  --warn: #F0B23E;
  --bad: #D7604E;
  --info: #6FA2C9;
}
```

## Phone frame template

```html
<div class="frame-wrap">
  <div class="frame">
    <div class="frame-inner">
      <div class="status-bar"><span>12:37</span><span class="right">··· · 95%</span></div>
      <!-- screen content -->
    </div>
  </div>
  <div class="frame-label before">▼ BEFORE · current</div>
</div>
```

## Typography

| Role | Font | Size | Weight |
|---|---|---|---|
| Display / numbers | Fraunces | 22–32 sp | w800–w900 |
| Body title | Fraunces | 18–22 sp | w800 |
| Body text | DM Sans | 13–15 sp | w400–w500 |
| Eyebrows / labels | DM Mono | 9–11 sp | w600–w700, +1.2–3 letter-spacing |
| Italic emphasis | Fraunces italic | inline | w500 |

## Naming

`docs/mockups/YYYY-MM-DD-<topic>-v<n>.html`

Examples:
- `2026-05-03-home-header-and-stats-v1.html`
- `2026-05-15-rank-ladder-and-profile-restructure-v1.html`

When iterating on the same topic, bump `v<n>` rather than overwriting (so the user can compare iterations if needed).

## Rules

- **NEVER** invent UI elements that don't exist in the code (e.g., drawing a "Deployments / Service Days / Volume" card on the profile screen if no such widget is rendered there). Confabulating from memory is the canonical failure mode this skill prevents.
- **ALWAYS** read the actual widget files BEFORE rendering BEFORE. Memory is point-in-time; the code is truth.
- **ALWAYS** match Wardroom palette tokens. Campaign Gold `#D4B270`, not Electric Cyan `#00D4FF`.
- **PREFER** combining multiple UI changes into ONE mockup file over separate files (token-efficient, lets user review whole visual language together).
- **AFTER** the user locks the visual, write the formal plan covering all changes — don't jump to code.
- **DO NOT** modify production Flutter code as part of this skill. The output is purely an HTML artefact in `docs/mockups/`.
