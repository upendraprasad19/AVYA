---
source: CLAUDE.md §14
migrated: 2026-05-18
status: scaffold
---

# Business Rules — Reference

> Free vs PRO feature matrix, phase unlock formula, calorie calculation rules.
> Fetch via Read when adding/changing gated features or BMR/TDEE logic.

## FREE Forever
- Phase 1 workout plan (4 weeks, auto-generated locally — workout + nutrition split)
- Workout template builder + copy week to week
- Food database logging (5,000 items, standard portions)
- Adjustable food portions
- AI food text analysis — 10 text logs/day
- Scan meal camera — 3 scans/day
- Cart Auditor (grocery screenshot) — 1 scan/day
- Weight + body measurements tracking
- Streak counter + water tracking
- Steps + sleep sync (Google Fit / Health Connect)
- AI Coach — 10/day forever, no trial (Gemini 2.5 Flash)
- Voice (mic) input to AI coach — on-device transcription via `speech_to_text`; zero infra cost. Made free 2026-05-03 (Test #9 / F13).
- Telegram bot — free (AI coach over Telegram; same 10/day forever cap, no trial)
- Morning alert — generic push notification
- Weekly nutrition report — first report free (after Week 1)
- Future Prediction card — one card post-onboarding
- Beat My Coach HIIT challenge — 1 per 2 weeks
- Diet plan — preview + swap + save to device + share as PDF (generated from food DB, no AI). Saved plans loadable on re-entry.
- Exercise coaching cues, common mistakes, pro tips — all visible
- Workout Receipt PNG (shareable) — after every completed workout

## PRO — ₹349/month or ₹2,999/year
- Auto-generate new plans after Week 4 (phases 2-12)
- AI food text analysis — 10 text logs/day
- Scan meal camera — 10 scans/day (soft cap warning at 7/10)
- Cart Auditor — 10 scans/day (soft cap warning at 7/10)
- Weekly AI nutrition report + Telegram push (ongoing)
- Future Prediction card — fresh AI prediction every month
- Progress photos (full timeline)
- Unlimited AI coach (Gemini 2.5 Flash — no daily cap, no trial window)
- Audio-First UI (voice notes to AI coach)
- Morning alert — AI-personalised message with yesterday's data
- Adaptive workout recommendations from biometric data (Phase 2)

## Phase Unlock Formula
```
canUnlock = completionRate >= 0.8 AND weeksElapsed >= 4
```

## Calorie Calculation
Hybrid BMR: Katch-McArdle when body fat % available (`370 + 21.6 × lean_mass_kg`), Mifflin-St Jeor fallback. Both apply -50 BMR offset and -100 TDEE offset. Activity level derived from lifestyle + training days → TDEE.
