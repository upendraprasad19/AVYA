# Phase 6: Backend Edge Functions

## Agent: @backend-agent
## Deps: Phase 1 (Database tables must exist)

## Tasks

### 6.1 AI Proxy (Free Users)
- [ ] `supabase/functions/ai-proxy/index.ts`
- [ ] Validate JWT
- [ ] Check: user within 30-day trial? Under 15 msg/day?
- [ ] 3-tier fallback: Cerebras Llama 8B → Groq Llama 4 → Gemini Flash Lite
- [ ] 3-second timeout per tier
- [ ] Return: `{ reply, model_used, tokens_used }`
- [ ] Rate limit: 15 msg/day for free users

### 6.2 AI Proxy PRO
- [ ] `supabase/functions/ai-proxy-pro/index.ts`
- [ ] Validate JWT
- [ ] Verify isPro from subscriptions table
- [ ] Direct call to Cerebras gpt-oss-120B
- [ ] Return: `{ reply, model_used, tokens_used }`

### 6.3 Razorpay Webhook
- [ ] `supabase/functions/razorpay-webhook/index.ts`
- [ ] Verify HMAC-SHA256 signature (MANDATORY)
- [ ] Write to subscriptions table
- [ ] Return 200 only after successful write
- [ ] Env vars: RAZORPAY_KEY_SECRET

### 6.4 Daily Snapshot Receiver
- [ ] `supabase/functions/daily-snapshot/index.ts`
- [ ] Receives compiled snapshot JSON from client
- [ ] UPSERT into user_daily_snapshots (user_id + date = unique)
- [ ] Validate JWT

### 6.5 Weekly Experience Recalculation
- [ ] `supabase/functions/weekly-recalc/index.ts`
- [ ] Cron trigger (Sunday 2AM IST)
- [ ] For each active user: pull last 4 weeks of workout_logs
- [ ] Score: weight progression, completion rate, exercise complexity, consistency
- [ ] Output: beginner / intermediate / advanced
- [ ] UPDATE user_progress.detected_experience_level

## Completion Criteria
- All 5 Edge Functions deployed and callable
- AI proxy returns valid responses with fallback
- Razorpay webhook verifies HMAC correctly
- Snapshot receiver upserts without error
- Weekly recalc updates experience levels

## Env Vars Required
```
OPENROUTER_API_KEY
CEREBRAS_API_KEY
RAZORPAY_KEY_SECRET
SUPABASE_URL
SUPABASE_SERVICE_ROLE_KEY
```
