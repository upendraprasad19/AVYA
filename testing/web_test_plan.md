# ICANBEFITTER — Web App Comprehensive Test Plan

> Last updated: 2026-04-01
> Purpose: Systematic browser + integration test coverage for all app screens and flows.
> Execution strategy: Tier 1 (Flutter integration tests) → Tier 2 (JS batch inspection) → Tier 3 (targeted screenshots only for visual bugs).

---

## Execution Strategy (Token-Optimised)

| Tier | Method | Token Cost | Best For |
|------|--------|------------|----------|
| 1 | `flutter test integration_test/` | Zero (run free after written) | Logic, data flows, math, date handling |
| 2 | `javascript_tool` → IndexedDB inspection | ~1 call per section | Data verification without UI navigation |
| 3 | Targeted screenshot | 1 per screen max | Visual-only bugs |
| Skip | Full page snapshots, per-check screenshots | — | Basic navigation, font checks (1 screenshot covers all) |

**Recommended run order:**
1. `flutter analyze` → catches code bugs before running
2. `flutter test integration_test/` → logic/data regression
3. `flutter run -d chrome` → start dev server
4. JS batch checks (Tier 2) → data verification
5. One screenshot per tab (Tier 3) → visual confirmation
6. Investigate failures only → tokens spent only where bugs found

---

## Section 1 — Auth & Onboarding

| # | Action | Expected | Tier |
|---|--------|----------|------|
| 1.1 | Open app cold | Sign-in screen loads | 3 |
| 1.2 | Sign in with email | Navigates to onboarding or home | 3 |
| 1.3 | Complete onboarding chat | Each step advances; BMR/TDEE saved to Hive | 1 |
| 1.4 | Skip mid-onboarding + return | Resumes from last step, data not lost | 1 |
| 1.5 | Sign in with existing account | Goes directly to Home, onboarding not re-shown | 1 |

---

## Section 2 — Home Screen

| # | Action | Expected | Tier |
|---|--------|----------|------|
| 2.1 | Load Home (no data) | All sections show empty states, no crashes | 3 |
| 2.2 | Load Home (after workout) | Today's workout card shows correct plan | 3 |
| 2.3 | Streak counter | Correct streak value | 1 |
| 2.4 | Weekly calendar strip | 7 days, today highlighted; completed=green, planned=grey | 3 |
| 2.5 | Today's workout card — planned | Template name + duration, Start Workout button | 3 |
| 2.6 | Today's workout card — completed | Shows actual duration (NOT 0 MIN) — **Bug 3a regression** | 1 |
| 2.7 | Nutrition snapshot | Correct macro targets from profile | 1 |
| 2.8 | PR Snapshot — no data | "Log workouts to see your PRs here" | 3 |
| 2.9 | PR Snapshot — with data | Top 3 gold tiles + "See All N Exercise PRs" | 3 |
| 2.10 | PR Snapshot expand/collapse | Toggle works; all PRs in expanded list | 3 |
| 2.11 | Weight sparkline | Last 7 entries plotted correctly | 2 |
| 2.12 | Quick actions | Log Workout / Log Meal / Hydration / Sleep navigate correctly | 3 |
| 2.13 | AI Coach insight card | Shows tip, no crash if no coaching notes | 3 |

---

## Section 3 — Train Screen & Active Workout

| # | Action | Expected | Tier |
|---|--------|----------|------|
| 3.1 | Load Train tab | Current phase + week shown | 3 |
| 3.2 | Week selector | Correct workout days per week | 3 |
| 3.3 | Tap a workout day | Exercise list expands with sets/reps | 3 |
| 3.4 | Start Workout | Opens ActiveWorkoutScreen, timer starts | 3 |
| 3.5 | Exercise — weight_reps | kg + reps fields shown | 3 |
| 3.6 | Exercise — bodyweight_reps | Reps only, no weight field | 3 |
| 3.7 | Exercise — timed | Duration (seconds) field only | 3 |
| 3.8 | Exercise — cardio | Duration (min) + distance (km) fields | 3 |
| 3.9 | Type value + check set | Green border + green fill on inputs — **Bug 1 regression** | 3 |
| 3.10 | Navigate away mid-workout + return | Controller values restored — **Bug 1 regression** | 1 |
| 3.11 | Long-press set badge | Toggles warm-up (W badge, orange tint) | 3 |
| 3.12 | Complete workout | Completion screen shows stats | 3 |
| 3.13 | Completion — duration | Actual time shown (not 0 MIN) | 1 |
| 3.14 | Completion — PRs detected | PR callout with correct exercise + value | 1 |
| 3.15 | Completion — "Review Workout" | Returns to workout; Finish disabled — **Bug 5 regression** | 1 |
| 3.16 | Completion — Finish (already saved) | Button greyed, "Already Saved", no double-log | 1 |
| 3.17 | Share workout receipt | No duplicate exercises — **Bug 4 regression** | 1 |
| 3.18 | Template Builder | Create template, saved to Hive, appears in list | 2 |
| 3.19 | Assign template to multiple dates | Each date shows correct template independently | 2 |
| 3.20 | Reassign a date | Old template gone, new one shows | 2 |
| 3.21 | Same template on multiple dates | Completing one does NOT auto-complete others | 1 |
| 3.22 | Copy week | Each date gets independent copy (not shared reference) | 2 |
| 3.23 | Rest timer | Auto-starts after set check, correct duration | 3 |

---

## Section 4 — Nutrition Screen

| # | Action | Expected | Tier |
|---|--------|----------|------|
| 4.1 | Load Nutrition tab | Today's macros vs target, correct BMR/TDEE | 1 |
| 4.2 | Food search | Results appear, correct items from DB | 3 |
| 4.3 | Select food + adjust quantity | Macros update correctly | 1 |
| 4.4 | Save food log | Appears in Today's Meals, totals correct | 1 |
| 4.5 | Delete food log | Item removed, totals recalculate (no negative values) | 1 |
| 4.6 | Scan Meal (free: 3/month) | PaywallSheet after 3 | 3 |
| 4.7 | AI Text Log (free: 3/day) | Works for first 3, paywall after; counter resets at midnight | 1 |
| 4.8 | Water tracking | Add increments, shows progress, resets on new day | 1 |
| 4.9 | Saved meals | Create, log, delete; macros pre-filled | 1 |
| 4.10 | Diet plan | Generates from food DB, no API call | 1 |

---

## Section 5 — AI Coach Screen

| # | Action | Expected | Tier |
|---|--------|----------|------|
| 5.1 | Load AI Coach | Chat history loads | 3 |
| 5.2 | Send message (free trial) | Response received, no crash | 3 |
| 5.3 | Quick prompt chips | Tap pre-fills message input | 3 |
| 5.4 | 10 msg/day limit (free) | 11th message blocked, counter + paywall shown | 1 |
| 5.5 | Reasoning tab (PRO locked) | PaywallSheet shown, no crash | 3 |
| 5.6 | Context injection | Response references user's actual data | Skip (live API, flaky) |

---

## Section 6 — Profile Screen

| # | Action | Expected | Tier |
|---|--------|----------|------|
| 6.1 | Load Profile | Bio stats shown | 3 |
| 6.2 | Edit Profile | All fields editable | 3 |
| 6.3 | Subscription card — free | Shows upgrade options (₹349/mo + ₹2999/yr) | 3 |
| 6.4 | Badges grid | Shows earned badges, no crash on 0 badges | 3 |
| 6.5 | Progress photos (free) | Locked with PaywallSheet | 3 |
| 6.6 | Reports | Weekly report generates | 1 |
| 6.7 | Logout | Returns to sign-in, auth cleared | 1 |

---

## Section 7 — Cross-Cutting Concerns

| # | Check | Expected | Tier |
|---|-------|----------|------|
| 7.1 | Fonts | DM Sans everywhere | 3 (1 screenshot) |
| 7.2 | Colors | Accent = #00D4FF, never #00e5a0 | 3 (1 screenshot) |
| 7.3 | Empty states | All lists/cards handle 0 items | 3 |
| 7.4 | Loading states | Skeleton shown on async ops | 3 |
| 7.5 | Error states | Retry shown on failure | 3 |
| 7.6 | PRO gates | All PRO features show PaywallSheet (test once, covers all) | 3 |
| 7.7 | Dark theme | No white backgrounds; correct hierarchy | 3 (1 screenshot) |
| 7.8 | Console errors | Zero red errors in DevTools | 2 |
| 7.9 | Navigation | Back button / GoRouter routes work | 3 |
| 7.10 | Scroll performance | No jank on long lists | 3 |
| 7.11 | Responsive layout | 375px → 1440px: no overflow errors | 3 |

---

## Section 8 — Regression: The 6 Bugs Fixed (2026-04-01)

**Run these first. If any fail, stop — APK is broken.**

| Bug | Test | Pass Criteria | Tier |
|-----|------|---------------|------|
| Bug 1: Controller reset | 3.9, 3.10 | Values persist after rebuild; green border on checked sets | 1 |
| Bug 2: Duplicate exercises in share card | 3.17 | Each exercise appears exactly once | 1 |
| Bug 3a: 0 MIN on home | 2.6 | Actual duration shown after completion | 1 |
| Bug 3b: PRs not showing | 2.8–2.10 | All-exercise PRs shown after workout, not just key lifts | 1 |
| Bug 4: No back-to-workout | 3.15, 3.16 | Review Workout returns to workout; Finish disabled if saved | 1 |
| Bug 5: Auto-green stale date | Section 9 | Planned workout NOT auto-completed on new day | 1 |

---

## Section 9 — Date Rollover Testing

**Method:** JS Date injection (non-invasive, no system clock change needed).

```javascript
// Inject in mcp__Claude_in_Chrome__javascript_tool before reload
const RealDate = Date;
class FakeDate extends RealDate {
  constructor(...args) {
    if (args.length === 0) super(2026, 3, 2); // day after test date
    else super(...args);
  }
  static now() { return new RealDate(2026, 3, 2).getTime(); }
}
Date = FakeDate;
```

| # | Scenario | Expected |
|---|----------|----------|
| 9.1 | Complete workout today → advance date → reopen | Shows as **planned**, not completed — **Bug 5 regression** |
| 9.2 | Complete Monday → check Tuesday | Tuesday's different template not auto-greened |
| 9.3 | Streak counter after rollover | Doesn't count stale completed day twice |
| 9.4 | Weekly calendar after rollover | Rolled-over day no longer shows green |

**Alternative method:** DevTools → Application → IndexedDB → workoutBox → set `completed_at` to yesterday → reload.

---

## Section 10 — Crash & Security Testing

### 10a — Input Boundary / Fuzz

| Input | Field | Expected |
|-------|-------|----------|
| `9999` | Weight | Accepted |
| `0` | Reps | Accepted |
| `-1` | Weight | Blocked by FilteringTextInputFormatter |
| `99999999` | Any number | Capped by LengthLimitingTextInputFormatter |
| Empty + check set | All fields blank | No crash, no null write to Hive |
| `abc` | Weight/reps | Blocked by formatter |
| `1.1.1` | Decimal | Blocked — only one `.` allowed |
| 500-char string | Exercise name | Ellipsis, no overflow crash |
| `<script>alert(1)</script>` | Any text | Rendered as literal (Flutter Canvas = no DOM injection) |
| Emoji `💪🏋️` | Exercise name | Renders or truncates gracefully |

### 10b — Race Conditions / Double-Tap

| Scenario | Expected |
|----------|----------|
| Double-tap "Finish Workout" | `isSaved` flag prevents double-log |
| Rapid-tap "Check Set" 5× | Set toggled once, not flickering |
| Rapid-tap "Log Food" save | Single entry, no duplicate |
| Tap "Start Workout" twice | One active workout instance |
| Rapid tab switching | No state corruption |

### 10c — Offline / Degraded State

| Scenario | Expected |
|----------|----------|
| Network offline (DevTools → Offline) | App works fully (Hive-first) |
| Log workout offline | Saved to Hive, queued for sync |
| AI Coach offline | Shows offline message, no crash |
| Supabase auth fails | Stays on sign-in, shows error |
| Sign in offline | Fails gracefully: "Must be online to sign in" |

### 10d — Large Data / Memory

| Scenario | Expected |
|----------|----------|
| 200+ exercise logs | PR Snapshot "See All" scrolls smoothly |
| 1,000+ food entries | Nutrition screen loads without freeze |
| 100+ chat messages | Chat scrolls smoothly |
| Long session (1hr) | No memory leak or slowdown |

---

## Section 11 — Weight Trend Line

| # | Scenario | Expected | Tier |
|---|----------|----------|------|
| 11.1 | 0 entries | Empty state, no crash | 2 |
| 11.2 | 1 entry | Single point, no line | 2 |
| 11.3 | 3–6 entries | Partial sparkline, correct date order | 2 |
| 11.4 | 7+ entries | Last 7 only | 2 |
| 11.5 | Weight going up | Upward trend | 3 |
| 11.6 | Weight going down | Downward trend | 3 |
| 11.7 | Same weight repeated | Flat line, no NaN/divide-by-zero | 1 |
| 11.8 | Large jump (60→120kg) | Scale adjusts, no overflow | 1 |
| 11.9 | Log new weight | Sparkline updates immediately | 2 |

---

## Section 12 — Nutrition: Fiber & Macro Bars

| # | Scenario | Expected | Tier |
|---|----------|----------|------|
| 12.1 | No food logged | All bars at 0%, target shown | 3 |
| 12.2 | Food with 0g fiber | Fiber bar stays at 0 | 1 |
| 12.3 | Food with fiber | Bar fills proportionally | 1 |
| 12.4 | Fiber > target (>100%) | Caps or shows overflow indicator, no crash | 1 |
| 12.5 | All macros | Each bar correct vs target | 1 |
| 12.6 | Delete logged food | All bars recalculate immediately | 1 |
| 12.7 | Target = 0 edge case | No divide-by-zero | 1 |

---

## Section 13 — Weekly Report

| # | Scenario | Expected | Tier |
|---|----------|----------|------|
| 13.1 | Free user, first report | Generates successfully | 1 |
| 13.2 | Free user, second report | PaywallSheet | 1 |
| 13.3 | PRO user | Generates every week | 1 |
| 13.4 | No data logged that week | Shows empty gracefully | 1 |
| 13.5 | Partial data (nutrition only) | Workout section empty, nutrition correct | 1 |
| 13.6 | Content accuracy | Numbers match Hive logs | 1 |
| 13.7 | Date range | Covers correct Mon–Sun | 1 |

---

## Section 14 — Sign Out & Delete Account

| # | Scenario | Expected | Tier |
|---|----------|----------|------|
| 14.1 | Sign out | Returns to sign-in | 3 |
| 14.2 | Sign out — Hive | Auth token cleared; workout/nutrition data retained locally | 2 |
| 14.3 | Sign back in same account | Data restored from Hive | 2 |
| 14.4 | Sign in different account | Previous user's data not visible | 1 |
| 14.5 | Delete account — confirmation | Two-step: "Are you sure?" + confirm | 3 |
| 14.6 | Delete account — Hive wipe | All local boxes cleared | 2 |
| 14.7 | Delete account — Supabase | Auth user deleted | 1 |
| 14.8 | Delete account offline | Fails gracefully: "Must be online to delete" | 1 |

---

## Section 15 — Units Change (kg/lbs, cm/ft)

| # | Scenario | Expected | Tier |
|---|----------|----------|------|
| 15.1 | kg → lbs | All weight displays convert (PRs, weight log, exercise sets, measurements) | 1 |
| 15.2 | cm → ft/in | Profile + onboarding display updates | 1 |
| 15.3 | Internal storage | Always stored as metric (kg, cm) | 2 |
| 15.4 | Log set in lbs mode | Stored as kg internally, displayed as lbs | 1 |
| 15.5 | Switch back to kg | All values display correctly | 1 |
| 15.6 | BMR/TDEE | Uses stored metric values — unaffected by display unit | 1 |
| 15.7 | Food logging (grams) | Grams unchanged by unit setting | 1 |
| 15.8 | PR snapshot after unit change | Values in currently selected unit | 1 |
| 15.9 | Weight sparkline after unit change | Y-axis updates | 3 |

---

## Section 16 — Edit Profile → Cascading Updates

### 16a — Weight / Height / Age → BMR/TDEE

| # | Change | Expected | Tier |
|---|--------|----------|------|
| 16.1 | Update current weight | BMR recalculated on save | 1 |
| 16.2 | Update height | BMR recalculates | 1 |
| 16.3 | Update age (DOB) | BMR recalculates | 1 |
| 16.4 | Update activity level | TDEE changes (multiplier applied) | 1 |
| 16.5 | New TDEE → nutrition targets | Today's calorie/protein/carb/fat targets update on Home + Nutrition | 1 |
| 16.6 | Already logged food today | Existing logs unchanged; target bar moves | 1 |

### 16b — Goal Change → Nutrition + Plan

| # | Change | Expected | Tier |
|---|--------|----------|------|
| 16.7 | build_muscle → lose_fat | Calorie target shifts to deficit | 1 |
| 16.8 | lose_fat → general_fitness | Maintenance calories | 1 |
| 16.9 | Goal change triggers plan regeneration | Confirmation dialog shown first | 3 |
| 16.10 | User cancels | Plan unchanged, goal unchanged | 1 |
| 16.11 | User confirms | New plan generated; Train screen updates | 1 |
| 16.12 | Custom templates assigned | Extra warning listing affected dates shown | 3 |

### 16c — Training Days Change → Plan

| # | Change | Expected | Tier |
|---|--------|----------|------|
| 16.13 | 4 days → 5 days | Confirmation dialog | 3 |
| 16.14 | 5 days → 3 days | Confirmation + "2 days will be removed" | 3 |
| 16.15 | Custom templates on removed days | Warning listing affected dates | 3 |
| 16.16 | Current week mid-progress | Completed days untouched; only future days affected | 1 |
| 16.17 | Equipment change | Confirmation + plan regeneration | 3 |

---

## Section 17 — Loading Times & Performance

### 17a — Targets

| Screen / Action | Target | How to Measure |
|-----------------|--------|----------------|
| Cold launch → Home visible | < 3s | Chrome DevTools Performance tab |
| Tab switch | < 300ms | DevTools timeline |
| Food search (3 chars) | < 500ms | DevTools timeline (IndexedDB read) |
| Active workout load (10 exercises) | < 500ms | DevTools timeline |
| PR Snapshot "See All" expand | < 200ms | DevTools timeline |
| Complete workout → receipt | < 1s | DevTools timeline |
| Weight sparkline render | < 100ms | DevTools timeline |

### 17b — Recommendations

| Issue | Recommendation |
|-------|----------------|
| `workoutBox.values` on every rebuild | Cache provider results; don't scan on every watch |
| Food search on every keystroke | Debounce 300ms |
| Exercise list / PR list as Column | Switch to `ListView.builder` (lazy rendering) |
| `fromActiveWorkout()` on completion | Run in `Isolate.run()` to avoid main thread jank |
| Exercise images | Precache on tab focus |
| Wide provider rebuild scope | Scope providers tightly — avoid full-screen rebuild on small state change |
| Web renderer | Confirm CanvasKit (not HTML renderer) is used |
| Release build | `flutter build web --release` — verifies 99%+ icon font tree-shaking |

---

## Scope Excluded from Web Testing

| Feature | Reason |
|---------|--------|
| Camera / Scan Meal | Web API unreliable for testing |
| Health Connect / Google Fit | Android-only |
| Push notifications / OneSignal | Requires device |
| Razorpay payment WebView | Web behavior differs from mobile |
| Live AI Coach responses | Flaky (external API), test separately |
