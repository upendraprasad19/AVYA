# Phase 6B: Backend — New Feature Edge Functions

## Agent: @backend-agent
## Deps: Phase 6 (core Edge Functions must exist)

## Tasks

### 6B.1 Rolling Context Optimization
- [ ] Supabase cron (2AM IST daily) OR Edge Function on schedule
- [ ] For each user with >50 messages in ai_coach_interactions:
  - Fetch last 50 messages
  - Call Cerebras Llama 3.1 8B to summarize into a single `fitness_summary` string (~200 tokens)
  - Save summary to user_daily_snapshots.snapshot_json.fitness_summary
  - Delete the raw 50 messages from ai_coach_interactions (keep only last 10 + summary)
- [ ] Cost: ~₹0.01/user/run. Saves ~₹7,000/month at 10K users vs unbounded context.
- [ ] Guard: skip users with <50 messages

### 6B.2 Morning Alert Generator
- [ ] Supabase cron (2AM IST daily) OR Edge Function on schedule
- [ ] For each active user (active in last 7 days):
  - Read yesterday's data from user_daily_snapshots
  - FREE users: generate a generic template message (no AI call)
    - Template: "Good morning {name}! {workout_day_name} is scheduled today. {streak_count} day streak!"
  - PRO users: call Cerebras 120B with yesterday's snapshot → personalized message (~100 tokens)
    - Must reference specific numbers: weight lifted, streak count, today's workout name
  - Store generated message in a new table or user_daily_snapshots field
- [ ] Separate delivery function at 7AM IST:
  - Push notification (FCM) for all users
  - Telegram message for Telegram-connected users
- [ ] Cost: FREE users ₹0/user. PRO users ~₹0.05/user/day.

### 6B.3 Beat My Coach Challenge Generator
- [ ] Edge Function (weekly cron, or triggered from client)
- [ ] Generate a HIIT finisher challenge:
  - Pick 3-5 bodyweight exercises from exercise_library (category: Calisthenics or Cardio)
  - Set random rep counts and a "coach's time" target
  - Format as JSON: {exercises, coach_time, difficulty, tagline}
- [ ] Store in a `challenges` table or return directly to client
- [ ] One new challenge per 2 weeks (beatMyCoachIntervalDays = 14)
- [ ] No AI cost — pure Dart/SQL logic

### 6B.4 Future Prediction Generator
- [ ] Edge Function triggered after onboarding completes (once) AND monthly for PRO
- [ ] Input: user_profile (weight, goal, experience) + user_progress (workouts done, streak)
- [ ] Call Cerebras 120B with structured prompt:
  - "Based on {current_weight}, {goal}, {workouts_per_week}, {current_streak} — predict 90-day outcomes for weight, body fat %, and key lifts"
- [ ] Output: JSON {predicted_weight, predicted_bf, predicted_lifts: {squat, bench, deadlift}, tagline}
- [ ] Client renders the card (not server-rendered)
- [ ] Cost: ~₹0.15/prediction. Once at onboarding + monthly PRO = negligible.

## Completion Criteria
- Rolling context cron runs without error, reduces message count
- Morning alert messages generated and stored by 2:30AM IST
- Morning alerts delivered at 7AM IST via FCM + Telegram
- Beat My Coach generates valid challenge from exercise library
- Future Prediction returns valid JSON with realistic predictions
- All functions have error handling and retry logic
- No API keys exposed client-side

## Reference
- `/CLAUDE.md` Section 11 (AI Architecture), Section 15 (Sync Schedule)
- `lib/core/constants/app_constants.dart` — all limits and feature keys
