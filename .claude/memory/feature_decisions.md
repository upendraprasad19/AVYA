# ICANBEFITTER — Feature Decisions
> Finalised in brainstorming session. Source of truth for free/PRO tiers.
> Last updated: 2026-03-24

---

## Pricing
| Plan | Price |
|------|-------|
| Monthly | ₹349/month |
| Yearly | ₹2,999/year |
| Annual saving | ~28% (shown dynamically on PaywallSheet) |

---

## AI Model Stack
| Tier | Model | Notes |
|------|-------|-------|
| AI Coach (free + PRO, merged 2026-04-18) | Gemini 2.5 Flash via single `ai-proxy` endpoint | Free: 10 msg/day forever, no trial (CORRECTED 2026-08-15 — OQ-1 removed the trial window; this row recorded the pre-OQ-1 decision). PRO: unlimited. Server-side gate. |
| Reasoning Tab | RETIRED 2026-04-18 | Chat/Reasoning toggle removed from UI; single coach experience. |
| Weekly Report (PRO) | Gemini 2.5 Pro | Deepest reasoning, once per week per user |
| Vision / Food AI | Gemini 2.5 Flash Lite | Scan Meal + Cart Auditor + body composition + media proxy |

Claude Sonnet as primary coach → **REJECTED** (destroys unit economics at scale).
WhatsApp AI Coach → **DEFERRED** (Telegram focus for now).

---

## Feature Tier Decisions

### FREE — Available to all users

| Feature | Details |
|---------|---------|
| Workout Plan Phase 1 | Auto-generated 4-week plan (workout + nutrition split) from local exercise DB |
| Diet Plan PDF | Preview + swap items + download. Generated from food DB locally. Zero AI cost |
| PRO Tips on Exercises | Coaching cues, common mistakes, breathing cue, pro tip — all visible to everyone |
| Workout Receipt PNG | Shareable card after every completed workout. ICANBEFITTER branding + QR code |
| Beat My Coach HIIT | 1 challenge per 2 weeks. AI generates brutal HIIT finisher as shareable card |
| Future Prediction Card | One AI forecast card post-onboarding. Bold 90-day prediction |
| Steps + Sleep Sync | Google Fit / Health Connect basic sync. Display only |
| Basic Morning Alert | Generic push notification at 7AM. "Time to train — Push Day scheduled." |
| AI Coach (free tier) | 10 messages/day FOREVER on Gemini 2.5 Flash — no trial window (OQ-1, corrected 2026-08-15) |
| First Weekly Nutrition Report | First report after Week 1 only. Subsequent reports → PRO |
| AI Food Text Analysis | 3 logs/day. User types food in plain English → AI parses macros |
| Scan Meal Camera | 3 scans/month. Point camera at plate → Gemini Vision logs macros |
| Cart Auditor | 1 scan/month. Upload Zepto/Blinkit screenshot → macro analysis + swaps |
| Adjustable Food Portions | No gate. Locking this degrades AI context for all users |

---

### PRO — ₹349/month or ₹2,999/year

| Feature | Key | Details |
|---------|-----|---------|
| Phases 2-12 | `phases_2_to_12` | Auto-generate new 4-week plans after Week 4. Unlimited progression |
| Unlimited AI Coach | `ai_coach_unlimited` | Unlimited messages on Gemini 2.5 Flash (same model as free, just no daily cap) |
| AI-Personalised Morning Alert | `morning_alert_pro` | 7AM push referencing specific yesterday's data (weight, workout, streak) |
| Weekly AI Nutrition Report | `weekly_ai_report` | Every week via Telegram + in-app (free = first report only) |
| Monthly Future Prediction | `prediction_monthly` | Fresh AI prediction card every month (free = once at onboarding) |
| ~~Reasoning Tab~~ | ~~`reasoning_tab`~~ | RETIRED 2026-04-18 — Chat/Reasoning toggle removed; single AI coach backend. |
| Progress Photos | `progress_photos` | Full photo timeline in Supabase Storage |
| Voice Notes to AI Coach | `voice_notes` | Push-to-talk in AI Coach screen |
| Scan Meal Camera (PRO) | `scan_meal_pro` | 3 scans/day (soft cap warning at 2/3). Free = 3/month |
| Cart Auditor (PRO) | `cart_auditor_pro` | 3 scans/day (soft cap warning at 2/3). Free = 1/month |
| AI Food Text Analysis (PRO) | `ai_text_log_pro` | 10 logs/day. Free = 3/day |
| Biometric Adaptive Workouts | `adaptive_workouts` | Phase 2. AI adjusts workouts from sleep/HRV data |

---

### SKIPPED — Not building

| Feature | Reason |
|---------|--------|
| WhatsApp AI Coach | Deferred. Telegram focus. Phase 2 add-on at ₹99/month |
| Wall of Shame / Skip Posters | 75% app deletion risk. India shame sensitivity. Skip entirely |
| Hyper-Local Weather Context | 8% repeat use. Solves minority problem. Not worth complexity |
| Claude Sonnet as Primary Coach | ₹3.5L–12L/month at 10K PRO users. Fatal to unit economics |

---

### PHASE 2 — Build after ~2,000 PRO users

| Feature | Notes |
|---------|-------|
| Skin in the Game Wallet | Needs RBI/legal review. Commitment deposit vs. gambling classification under Indian law. Redesign as "Fitness Bond" with illness pause credits. Opt-in after Day 45 |
| AI-Automated Upselling | Plateau detection → auto-pitch PRO. 12.45× ROI. Build after enough data |
| Shadow Rivalries | Needs user base for matching. Introduce after Day 30. "Running with" framing. Never before Day 30 |
| Adaptive Workouts from Biometrics | Steps + sleep already synced (free). Phase 2 adds AI workout adjustments |

---

## Shareable Cards Spec

All 3 shareable cards include:
- **ICANBEFITTER** wordmark (DM Sans w900)
- App logo / branding strip
- QR code → `www.icanbefitter.com` (update to Play Store link before release)
- Generated via Flutter `RepaintBoundary` → PNG → `share_plus` native share sheet

| Card | Trigger | Tier |
|------|---------|------|
| Workout Receipt | After completing workout | FREE |
| Future Prediction | Post-onboarding + monthly | FREE once, PRO monthly |
| Beat My Coach | Every 2 weeks | FREE |

---

## Conversion Architecture

The entire funnel is timed around two events 48 hours apart:

- **Day 28** — Phase 1 complete → Graduation Screen → Phase 2 locked → PRO upsell
- **Day 30** — AI Coach trial expires → AI goes silent → PRO upsell

These two events create maximum urgency together. **Never split them** (e.g. 14-day trial breaks this).

---

## AI Coach Personality Spec

**"Warm Demanding"** — unconditionally invested in user's success, conditionally accepting of choices.
- Curious before critical
- Uses exact numbers (specific weights, dates, streaks) as a form of care
- Culturally fluent: wedding season, Navratri, monsoon, Indian food context
- Never corporate wellness app tone
- Never pure cheerleader, never tough-love drill sergeant
- Target: closes the "I am not a fitness person" identity gap within 21 days

---

## Rolling Context Optimization (Backend)

- 2AM IST cron job
- Summarizes last 50 AI messages → single `fitness_summary` string (~200 tokens)
- Deletes raw messages (keeps last 10)
- Saves to `user_daily_snapshots.snapshot_json.fitness_summary`
- Saves ~₹7,000/month at 10K users vs no context management
- **Build Phase 1** — must be live before AI coach scales
