# AVYA Phase 2 — AI Living Dashboard

## Concept
Conversation-driven personalized dashboard accessible from AI Coach screen (button at top near deep analysis toggle). AI generates the dashboard based on user's conversation history — hyper-personalized, evolves over time.

## Core Flow
1. User chats with AI → "give me a back workout"
2. AI generates workout on the fly based on user history
3. Workout appears on the Living Dashboard
4. 60–90 min later: push notification "Did you complete your workout? Just say yes."
5. User replies in chat → AI logs it → dashboard updates → XP awarded

## Dashboard Widgets (user can reorder/hide)
1. Today's AI-generated workout card (tap to start)
2. Daily quests with XP progress
3. Fitness Score (0–1000) with trend
4. Nutrition snapshot
5. Streak + XP bar + Level
6. Active Boss Battle (PRO only)
7. Recent AI insights
8. Badge progress

## Gamification Framework
- **XP System** — earned from workouts, meal logs, conversations, streaks
- **Level System** — Beginner → Athlete → Elite → Legend
- **Daily Quests** — AI-generated from conversation history (2 free / 5 PRO)
- **Streak Multipliers** — 7-day = 1.5x XP, 30-day = badge unlock
- **Fitness Score** — single 0–1000 number (consistency + nutrition + volume + AI engagement)
- **Boss Battles (PRO)** — weekly AI challenge (e.g. "4 workouts + 140g protein every day"). Defeat = badge + 500 XP

## Free vs PRO
- Free: 3 widgets, 2 daily quests, basic fitness score, standard streak
- PRO: full configurable dashboard, all 5 quests, boss battles, streak multipliers, deep AI analysis widget, workout auto-generation from history

## Entry Point
- Phase 2: Button in AI Coach screen (near deep analysis toggle)
- Phase 3: Consider dedicated tab in bottom nav

## Notes
- MVP scope is LOCKED for Phase 1 launch — this is Phase 2 only
- Workout logs from dashboard should integrate directly with existing Train tab
- User can configure widget layout after template is set
