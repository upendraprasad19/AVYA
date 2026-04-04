# E2E Test: AI Coach

## Setup
- User must be signed in and onboarded
- Navigate to AI Coach tab
- User should be within 30-day free trial period

---

## E16: Send Message (Free Tier)

**Frontend:**
1. Navigate to AI Coach tab
2. `preview_snapshot` → verify chat UI loaded (input field visible)
3. `preview_fill` message input with "Hello, what should I eat today?"
4. `preview_click` Send button
5. Wait 5 seconds for Edge Function response

**Backend:**
```sql
SELECT user_message, ai_response, model_used, created_at
FROM ai_coach_interactions
WHERE user_id = '<USER_ID>'
ORDER BY created_at DESC
LIMIT 1;
```
- **PASS:** Row exists with user_message containing "eat today" and ai_response non-empty
- **NOTE:** Interaction may be stored locally in Hive first; Supabase entry depends on sync

---

## E17: Response Renders in Chat

**Frontend:**
1. After sending message in E16
2. `preview_snapshot` → look for AI response bubble

- **PASS:** AI response text visible in chat (not just loading indicator)
- **FAIL:** Shows error message, loading spinner stuck, or empty response

---

## E18: Context Injection — AI Knows User's Goal

**Frontend:**
1. `preview_fill` message input with "What is my primary fitness goal? Answer in one sentence."
2. `preview_click` Send
3. Wait 5 seconds
4. `preview_snapshot`

- **PASS:** Response mentions "muscle" or "build_muscle" or "strength" (user's goal from onboarding)
- **FAIL:** Generic response with no reference to user's profile

---

## E19: Daily Limit Check (15 messages/day)

**NOTE:** This test requires sending 15 messages. Run selectively.

**Frontend:**
1. Send 14 more quick messages ("hi" x14)
2. After 15th message, send another
3. `preview_snapshot`

- **PASS:** PaywallSheet or "daily limit reached" message appears
- **FAIL:** 16th message goes through without limit

---

## E20: Prompt Chips Visible

**Frontend:**
1. Navigate to AI Coach tab (fresh state)
2. `preview_snapshot` → look for quick prompt chips/suggestions

- **PASS:** Prompt chips visible (e.g., "What should I eat?", "Summarize my week")
- **FAIL:** No prompt suggestions shown

---

## E21: pgvector Memory Storage (PRO Only)

**NOTE:** Requires PRO subscription. Skip for free users.

**Setup:** Set user as PRO via:
```sql
UPDATE users SET subscription_status = 'pro' WHERE id = '<USER_ID>';
INSERT INTO subscriptions (user_id, plan, status, start_date, end_date)
VALUES ('<USER_ID>', 'monthly', 'active', NOW(), NOW() + INTERVAL '30 days');
```

**Frontend:**
1. Send a distinctive message: "I always workout at 6am and prefer morning sessions"
2. Wait 5 seconds
3. Send: "When do I usually workout?"
4. Wait 5 seconds
5. `preview_snapshot`

**Backend:**
```sql
SELECT content, source_type FROM memory_embeddings
WHERE user_id = '<USER_ID>'
ORDER BY created_at DESC
LIMIT 5;
```
- **PASS:** Memory embedding exists containing "morning" or "6am"
- **PASS (alt):** AI response to second message references morning/6am (memory retrieval working)

**Cleanup:**
```sql
UPDATE users SET subscription_status = 'free' WHERE id = '<USER_ID>';
DELETE FROM subscriptions WHERE user_id = '<USER_ID>';
```
