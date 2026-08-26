---
branch: oi98-notification-prefs
date: 2026-08-26
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/885ebd47f4c0-review.md
---

# Plan-review record — oi98-notification-prefs (platform)

Keystone record for the §4.12 merge gate. **Platform**, measured with
`blast_radius_from_diff.dart` over the staged set, not assumed:
`docs/blast_radius.yaml:61` (`_shared/**`), `:62` (`supabase/migrations/**`),
`:63` (`lib/core/services/sync/**`). Hermes is **not** required — that is
catastrophic-only, and nothing here touches `razorpay-webhook/`,
`verify-payment/`, `delete-account/` or a `SECURITY DEFINER` object. Migration
123's RPC is deliberately `SECURITY INVOKER` for exactly that reason, among
others.

## What this batch is

OI-98 — a notification the user switched off comes back on. Two mechanisms:

1. **No restore leg existed at all.** `grep -rn "restoreNotificationPrefs" lib/
   test/` → zero hits. A device with no local record emitted all ten keys as
   `{'enabled': true}` — its empty Hive box and "the user enabled everything"
   were the same value — and the wholesale snapshot upsert replaced the server's
   stored copy with that default. Destroyed, not merely unread.
2. **Newest-row-wins, with four writers.** All ten server readers took the
   user's newest `user_daily_snapshots` row with no fall-through, while
   `rolling-context` (02:30 IST, every user), `future-prediction` and
   `beat-my-coach` create a preference-less row when the day has none. Live at
   batch start: **3 of the 5 users** who had ever stored a preference were being
   ignored outright, no reinstall involved.

The fix MOVES the concept to `user_preferences.notification_preferences`
(migration 122) with a per-key additive write (migration 123), adds the missing
restore leg, and repoints all ten server readers — keeping the snapshot as a
temporary read fallback whose retirement is tracked as **OI-141**.

## Review history — three rounds, and each one changed the design

**This record's `review_rounds: 3` is not a formality. Rounds 1 and 2 each
BLOCKED, and every blocking finding was a defect in my own plan, not in the
inherited one.**

**Round 1 — BLOCK, 12 findings, 3 blocking.** Killed the padded-emission design:
`profile/screen.dart:192-209` returns a **five-key** default using the *legacy
singular* `workout_reminder`, and the first toggle persists it — so padding to
ten keys would have pushed five **fabricated** `true` values that then overwrite
another device's real `false`. Also refuted the plan's reinstall threat model:
`AndroidManifest.xml:21` `allowBackup="false"` plus the data-extraction rules
mean session and Hive die together, so `splash_screen.dart:189` cannot poison
anything pre-sign-in. That incidentally **answered OI-98's own `Blocked on:`**,
which had required the reinstall ordering be established before a fix was
designed — and it resolves opposite to the board's assumption. It further found
the dominant failure (mechanism 2 above), which the board had never recorded.

**Round 2 — BLOCK, 3 P0s, two of them introduced by round 1's corrections.**
The exact failure mode §4.12.1 says a second round exists to catch. It also
diagnosed **OI-80** in one read (`check_snapshot_contract.dart:252`'s `fn:`
capture is `[\w-]+`, which cannot match `/`), showing the gate validates 8 of 26
declared citations while printing a count implying full coverage.

**Founder decision after round 2: move the data rather than patch the
container.** Two revisions had leaked in two different places for one reason —
a wholesale-replaced document cannot represent *"I know these three settings and
nothing about the other seven"*, which is exactly a reinstalled device's state.
That decision **deleted** work: no multi-row reduce, no newest-row-wins
handling, no shadowing, and no new detector gate, because the failure mode stops
existing rather than needing to be caught.

**Round 3 — BLOCK on the NEW architecture, 2 P0s.** Confirmed the core premise
empirically (a partial upsert really does leave sibling columns intact) and then
found the write path did not work: `_syncUserPreferences` opened with
`if (prefs == null) return;` on a Hive key written ONLY by the restore leg, so
the feature would have shipped **inert for 12 of 18 live users** with every
planned test passing. Evidence: `UserRepository.savePreferences` has **zero**
call sites, and all 6 `user_preferences` rows carry `preferred_language='English'`
(the column DEFAULT) with none at the `'en'` the client writes — the client has
never created a row. Second P0: the same upsert named `coaching_notes`
unconditionally, nulling a column owned by two Edge Functions including the BF%
rate-limit stamp.

**B-pass on the implementation — 6 findings, 1 P0, all fixed in-batch.**
`docs/reviews/885ebd47f4c0-review.md`, verdict `accepted`, zero false alarms.
The P0 is the one worth recording: migration 122 moved the concept out of a
wholesale-replaced blob and **left the write side with the identical defect**,
because a jsonb column is also replaced wholesale. Per-key merge had been
applied on the RESTORE side and wholesale replace left on the WRITE side —
`feedback_mistake_guard_without_its_mirror`, found inside the fix for a bug of
that same class. Closed by migration 123's merge RPC. Its Finding 6 named *why*
it survived: nothing in the suite asserted the shape of what the client sends.

## Ground truth — verified, not assumed

- Migration 122 applied live under explicit founder authorization and confirmed
  via `information_schema`: `notification_preferences | jsonb | is_nullable=YES
  | column_default=null`.
- Live counts re-run by me at batch start: 126 snapshot rows / 18 users, 14 rows
  carrying the key across 5 users, **0 rows with any key set to `false`**, 3
  users whose newest row lacks the key while an older row has it.
- The zero-`false` fact is what makes the whole move lossless, and it is
  point-in-time: OI-141 requires re-running that query immediately before the
  fallback is retired.
- Schema snapshot regenerated after **diffing** rather than overwriting: zero
  columns dropped since the 2026-06-08 capture, so purely additive.
- Gates green: schema column-refs (837 refs, 0 drift), Gate 42 (118 concepts),
  Gate 11 (58 sync/restore methods), Gate 40 (17/17 terminal), OI numbering.
- Tests: 15/15 in the new behavioral file, 35/35 across the five notification
  files. **Mutation-proven twice** — cloud-wins in the merge reddens 4;
  reinstating the two removed upsert columns reddens 4. Both mutations verified
  applied and verified removed rather than trusted.

## Known gaps, stated rather than glossed

- **The Edge Function changes are not type-checked.** Deno is not installed on
  this machine and the repo's EF tests are source-greps, not compilation. First
  real verification is the deploy's boot check.
- **`degraded` is batch-wide, not per-user.** A transient failure now skips
  every candidate for that cron run rather than one user. Same direction
  (skip rather than risk an unwanted push), self-healing next run, but a wider
  blast radius for a transient fault than the per-user queries it replaced.
- **Two items are `blocked_on_user` in the closure ledger, by design**: the ten
  Edge Function deploys (§4.3 — separate explicit authorization, and it is ten
  because Deno bundles `_shared` at deploy) and the snapshot fallback's
  retirement (gated on APK +39 adoption, tracked as OI-141 with a named,
  checkable trigger per §4.6).
- **OI-80 is diagnosed but untouched.** This batch no longer depends on that
  file. The diagnosis is attached to the board entry so it is cheap next time.
