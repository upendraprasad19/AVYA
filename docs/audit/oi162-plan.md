# OI-162 — separate the usage ledger from the conversation log

**Status:** spec, awaiting §4.12.1 ×2 review. No code written.
**Supersedes:** the "Piece 1 (windowed) / Piece 2 (lifetime)" split of the previous version of
this file (kept at `scratchpad/oi162-plan-v3-superseded.md` for the session). That axis did not
partition the set — `countProImageAnalysesToday` belonged to neither piece — and it was drawn on
the wrong property anyway (§1).
**Blast radius:** `platform` at least (migration + 4 Edge Functions + 3 DB triggers), possibly
`catastrophic` — see §10 Q3. Classify with `blast_radius_from_diff.dart` via **stdin** before the
merge; do not trust this line.
**Founder decision recorded 2026-09-04:** two tables. This spec implements that.

---

## 0. The one-sentence problem

`ai_coach_interactions` is simultaneously a **conversation log** (prunable by design) and a
**usage ledger** (whose row count *is* the quota state). `rolling-context`'s nightly summarizer
deletes from it. Deleting a log is correct; deleting a ledger resets every quota derived from it.

---

## 1. Why the previous split was wrong

The superseded version split on **windowed vs lifetime**. Two problems:

1. **It did not partition.** `countProImageAnalysesToday` (windowed, `ai-media-proxy:89`) was
   assigned to neither piece — a §4.2 hole hidden by a clean-looking boundary.
2. **It was the wrong property.** The predicate that actually determines exposure is
   *"can this counter's rows fall outside the newest `KEEP_RECENT` the cron keeps?"* — and under
   that predicate windowed and lifetime counters are **the same class**, which is exactly why they
   take the same remedy.

**A correction to reasoning given in chat:** I said the chat cap was "safe by coincidence, because
cap 10 == `KEEP_RECENT` 10". Too generous. The cron keeps the newest 10 rows **across all
non-`app_event` channels mixed**, not the newest 10 *chat* rows. A user with 9 chat + 1 food-text
row in the surviving window counts 9 and gets another chat turn. Chat is the **least** exposed
site, not an immune one; its only saving grace is that the cron needs ≥50 total rows to fire.

---

## 2. Recurrence (§4.1.5) — this table's counting has failed ≥6 times

Grepped `docs/diagnoses/INDEX.md`. This is not a new bug; it is the seventh instance of a
standing class:

| Bug | Date | What it was |
|---|---|---|
| `0f8d54` | 2026-05-04 | Usage counters diverged from the server rate-limit trigger |
| `26b360` | 2026-05-04 | Counter resets used UTC/device-local instead of IST |
| `7ad009` | 2026-05-11 | **Origin of the `delete-account` counter.** Test recorded as *"n/a — verified via curl"* |
| `7ad0d3` | 2026-05-11 | 7 EF sites used UTC midnight for rate-limit windows |
| `9d12af` | 2026-05-16 | `log-client-error` rate limit silently dropped past threshold |
| `c9e3b1` | 2026-07-29 | OI-45 — `UsageCounterService.increment()`, `read(); write(c+1)` race letting users bypass daily caps |
| `c7a3b9` | 2026-08-20 | `founder_metrics_engagement` counted every channel — 5.3× overcount (migration 120) |

Two things this history establishes that the spec must answer:

- **`7ad009` rotted ~4 months** because its verification was a live `curl`, not a test. Its insert
  has *never once succeeded* (§3). A behavioral test is non-negotiable here.
- **`c9e3b1` is the same race, on the client side.** It already has
  `test/contracts/usage_counter_service_race_behavioral_test.dart`. The server side has no
  equivalent. §7 fixes that; §4 removes the race rather than testing around it.

---

## 3. Ground truth — writers, readers, deleter (§4.1)

Every constant below was read from the file on 2026-09-04, not recalled.
⚠ Two numbers stated in chat were **wrong** and are corrected here: the vision cap is **15**
(not 20) and the PRO image daily cap is **50** (not 20).

### Readers — 8 sites, one shape

| # | Site | Limit | Window | On query error |
|---|---|---|---|---|
| R1 | `ai-media-proxy/index.ts:67-82` → call `:465` | 5 | **lifetime** | **fail-OPEN** |
| R2 | `ai-media-proxy/index.ts:89-104` → call `:505` | 50 | IST day | **fail-OPEN** |
| R3 | `delete-account/index.ts:144-149` | 5 | rolling 60 min | fail-open (deliberate, logged) |
| R4 | `verify-payment/index.ts:223-228` | 20 | rolling 10 min | **fail-OPEN** (no `error` destructured) |
| R5 | `weekly-report/index.ts:93-98` | 1 | **lifetime** | fail-closed (fixed `e4d1b7`, live v26) |
| R6 | `migrations/111_…:47-51` (trigger) | 10 | IST day | raises `P0001` |
| R7 | `migrations/111_…:84-88` (trigger) | **15** | IST day | raises `P0001` |
| R8 | `migrations/113_…:42-46` (trigger) | 50 free / 200 PRO | IST day | raises `P0001` |

### Writers

| Site | State |
|---|---|
| `delete-account/index.ts:174-182` | **BROKEN.** Writes `prompt_snippet`/`response_snippet` (columns do not exist) and omits `user_message` (NOT NULL). Has never inserted a row. Un-awaited, so the error is logged into a void. |
| `verify-payment/index.ts:248-259` | Correct columns; **un-awaited** fire-and-forget |
| `weekly-report/index.ts:587` | Correct; now destructures `error` (`e4d1b7`) |
| `ai-media-proxy` (image rows) | Written on the success path; the `:662` comment confirms the read picks them up next request |

### Deleter

`rolling-context/index.ts:470-471` — `.delete()`, keeping `KEEP_RECENT = 10` (`:28`) once a user
passes `MESSAGE_THRESHOLD = 50` (`:27`). Scoped by the **denylist** `.neq("channel","app_event")`
at `:181`, `:220`, `:256`, `:351`.

### Three findings that fall out of the enumeration

- **F1 — R4 carries the CODE-6/CODE-8 defect fixed yesterday.**
  `const { count: recentAttempts } = await …` never destructures `error`, so a failed query yields
  `null`, and `(null ?? 0) >= 20` is `false`. **A PostgREST failure disables Razorpay
  brute-force protection.** Same family as `e4d1b7`/`f2b9d4`; the mirror was not applied here.
- **F2 — R1/R2's fail-open rationale is inverted.** `ai-media-proxy:64-66` says *"fail-open is
  safer … the LIMIT comparison still gates correctly because 0 < 5"*. Returning `0` means "used
  none of 5", so the gate **passes** and grants a free paid analysis. The comment asserts the
  opposite of what the code does.
- **F3 — `verify-payment:220-221`** documents the decision being reversed here, in as many words:
  *"reusing the existing table so no schema change."*

---

## 4. The design

Two tables, per the founder's decision. One new table; `ai_coach_interactions` unchanged.

```sql
CREATE TABLE public.usage_counters (
  user_id      uuid        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  meter        text        NOT NULL,
  window_start timestamptz NOT NULL,
  count        integer     NOT NULL DEFAULT 0,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, meter, window_start)
);
```

- **One row per (user, meter, window)** — not one row per request. This is the shape Neon's
  Postgres rate-limiting guide and every Redis-backed limiter converge on.
- **Lifetime quotas are a window that never rolls over**: `window_start = 'epoch'`. Keeps the
  founder's two-table decision intact rather than growing a third table.
- **`ON DELETE CASCADE` is mandatory, not incidental.** `delete-account/index.ts:440`'s
  `deleteUser` is the only deletion path and relies on cascade for DPDP compliance. A no-FK table
  would strand quota rows for deleted users — a real defect in an earlier draft of this spec.
- **RLS enabled, no policy.** Only the service role and `SECURITY DEFINER` functions touch it.
  Clients never read it directly; remaining-quota display already comes from the EF response body.

### The one entry point

```sql
CREATE FUNCTION public.consume_quota(
  p_user_id uuid, p_meter text, p_window_start timestamptz, p_limit integer
) RETURNS integer   -- new count, or -1 when the limit is already reached
```

Body is a single `INSERT … ON CONFLICT (user_id, meter, window_start) DO UPDATE
SET count = usage_counters.count + 1 … RETURNING count`, with the limit checked on the returned
value.

**This closes the race for free.** Today every site is `count(*)` → decide → insert: two
concurrent requests both read 4, both proceed, the user gets 6. `c9e3b1` is that exact defect
found on the client side in July. Increment-then-compare is atomic in a single statement, so there
is no window to lose.

Both the EFs (via RPC) and the three triggers call this one function — one implementation, one
place to test.

### Accepted trade-off, stated rather than buried

R3 and R4 are **rolling** windows today (last 60 / last 10 minutes). Fixed-window counters
approximate them, and the standard critique applies: a fixed window permits roughly double the
intended limit across a boundary. Worst case R3 becomes 10/hour instead of 5.

**Accepted deliberately.** Both are defense-in-depth DoS guards, not accounting. Preserving true
rolling windows means storing a timestamp per request — row-per-event, i.e. the shape this spec
exists to remove. Not a deferral: a design decision with a stated cost.

### Retention — a two-sided predicate, deliberately

Old windows are disposable; lifetime rows are not:

```sql
DELETE FROM usage_counters
WHERE window_start <> 'epoch'::timestamptz
  AND window_start < now() - interval '7 days';
```

⚠ **Both conjuncts are load-bearing.** Dropping the first deletes every lifetime entitlement —
i.e. it reintroduces this bug in the new table. This is the two-sided-band class that shipped a
zero-byte-file-passes bug on 2026-08-30; the mirror test in §7 pins it.

### What this buys structurally

`rolling-context` has never heard of `usage_counters`, so its denylist stops being a hazard. A
future counter cannot silently opt into deletion by forgetting a `.neq()` — the failure mode is
removed rather than remembered.

---

## 5. Per-site changes

`ai_coach_interactions` keeps receiving conversation rows exactly as today — including the
`verify_payment_attempt` audit rows if we want them. It simply stops being the thing quotas are
*derived from*.

| # | Change |
|---|---|
| R1 | `countFreeImageAnalyses` → `consume_quota(uid,'free_image','epoch',5)`. **Fail CLOSED** (fixes F2) + `console.error`. |
| R2 | `countProImageAnalysesToday` → `consume_quota(uid,'pro_image',<IST day>,50)`. Fail closed + log. |
| R3 | → `consume_quota(uid,'delete_attempt',<hour bucket>,5)`. Fail-open **preserved** — deliberate and reasoned at `:152-155` (a user exercising a right). |
| R4 | → `consume_quota(uid,'verify_payment',<10-min bucket>,20)`. Destructure `error`; **fail CLOSED** (fixes F1). |
| R5 | → `consume_quota(uid,'weekly_report','epoch',1)`. Already fail-closed; keep. |
| R6-R8 | Triggers call `consume_quota` instead of `count(*)`. Caps unchanged: **10 / 15 / 50-200**. The IST boundary expression is carried over **verbatim** from 111/113 — it is the fix for `7ad0d3` and must not be re-derived. |
| W-`delete-account:174-182` | **Delete** the broken insert. Its only purpose was feeding R3; that job now belongs to `consume_quota`. Deleting it is the fix — repairing the columns would mint a new channel that `rolling-context`'s denylist swallows (§9). |
| W-`verify-payment:248-259` | Keep as an audit row (columns are correct), or delete. **Open question for review — no strong view.** |

### Backfill

Lifetime meters need one, or every existing user's free quota silently resets to 0 on deploy —
the exact bug, shipped as the fix.

```sql
INSERT INTO usage_counters (user_id, meter, window_start, count)
SELECT user_id, 'free_image', 'epoch', count(*) FROM ai_coach_interactions
WHERE channel = 'free_image_analysis' GROUP BY user_id
ON CONFLICT DO NOTHING;
-- same for 'weekly_report' / channel='weekly_report'
```

⚠ **The backfill is a floor, not a truth.** Rows already deleted by the cron are unrecoverable, so
some users get more free usage than they should. Strictly better than resetting everyone, and it
is one-time. Windowed meters need no backfill — their windows roll within the hour.

---

## 6. Gate (§4.11) — ships in an earlier commit

`scripts/check_usage_counter_source.dart`: no `ai_coach_interactions` read may combine
`count: "exact"` with a `channel` filter inside a defined radius, comments stripped first.

- **Structural, not vocabulary.** The matcher verified during review returns **exactly 5 sites,
  0 false positives**. The earlier vocabulary matcher (`rate_limit`, `quota`) fired on two
  *comments* (`ai-proxy:266`, `:729`) and missed 3 real counters. Comment-stripping is mandatory —
  `feedback_source_grep_strip_comments_first.md` exists because of this exact error.
- SQL half: no `count(*) … FROM ai_coach_interactions` in `supabase/migrations/*.sql` outside an
  allowlist of historical migrations (101 and 120 are analytics, not quotas).
- Baseline is **5 + 3 = 8**, never 0. Warn-only for one commit, then hard-fail (§4.11 step 2).
- Rule 24: `mutation_proven: true` in `docs/audit/gate_test_ledger.yaml` with `test_path:` as a
  list and `evidence:` naming what was neutered and how many tests reddened.

---

## 7. Tests

**Rewritten from the previous version, which specified a test `SupabaseTestHelper` cannot run** —
it is anon-key + QA-user JWT, so under RLS-with-no-policy it cannot insert into `usage_counters`,
and asserting CASCADE would require deleting the single shared QA account and permanently redding
CI.

| Test | Asserts |
|---|---|
| `usage_counter_consume_quota_behavioral_test.dart` | Drive an EF via `functions.invoke` with the QA token N times; the N+1th returns 429. The whole chain, not a shape. |
| `usage_counter_survives_prune_behavioral_test.dart` | **The headline.** Seed ≥ `MESSAGE_THRESHOLD` rows, run the summarizer, assert the quota is unchanged. Fails against today's code. |
| `usage_counter_retention_test.dart` | The two-sided predicate: an old window is deleted **and** an `'epoch'` row survives. |
| `usage_counter_cascade_test.dart` | Schema-level `pg_constraint` check for `ON DELETE CASCADE`. No live deletion. |
| `delete_account_attempt_counter_test.dart` | R3 actually increments — the assertion `7ad009` never had. |

**Mutation (rule 21), applied one at a time, each confirmed landed via `grep -c` before running:**

1. Revert R4 to drop the `error` destructure → the F1 test must redden.
2. Drop `window_start <> 'epoch'` from retention → the lifetime-survives test must redden.
3. Revert `consume_quota` to read-then-write → the race test must redden.
4. Point R1 back at `ai_coach_interactions` → the survives-prune test must redden.

⚠ Per rule 21, mutations are **confirmed applied** before the run — this repo has twice recorded a
green run reading as proof when the regex matched nothing.

---

## 8. Ordering

1. Gate, warn-only (§4.11 — must precede the refactor).
2. Migration: table + `consume_quota` + RLS + backfill + retention cron.
   **Needs founder authorization (§4.3).**
3. Triggers R6-R8 (same migration or the next — they are the only writers of their own counters).
4. Edge Functions R1-R5 + writer changes. **Each deploy needs founder authorization.**
5. Flip the gate to hard-fail.
6. `/code-review` B-pass — self-initiated, before the `--no-ff` merge (§4.3).

`backups/applied_migrations.json` and `backups/live_schema_columns.json` both update in the **same
commit** as the migration (§4.5 and the §7 pointer row).
The retention job joins `docs/operations/CRON_REGISTRY.md` (Gate 31) and must use
`_shared/cron_telemetry.ts` if it is dispatched as an Edge Function (§4.5).

---

## 9. Unchanged, and why — handed to OI-153

The **7 unfiltered consumers** of `ai_coach_interactions` are not patched here, because this spec
**removes no channel value from that table and adds none** — `delete-account`'s broken insert is
deleted rather than repaired, precisely so that no new channel is minted. They matter to OI-153,
whose CODE-1 fix *does* mint one:

`rolling-context:181,220,256,351` (denylist → embeds into the SYSTEM prompt, then **deletes** at
`:467-472`) · `compute_coach_signals_for_user` (`028:150-153` `max(created_at)` → `v_days_silent`;
`028:249-253` `count(*)/7.0`) · `get_users_with_message_count` (`010`) · `sync_coach.dart:178` ·
`restore-user-snapshot:252-255` · `daily-snapshot:60-67` (⚠ its own comment: *"the
highest-consequence prompt-injection site in the codebase… this prompt's OUTPUT is written back
into the user's stored profile"*) · `sync_coach.dart:121` (effectively safe — dedup keyed on
`user_message`). **Not a reader:** `founder_metrics_for_admin_api` (verified in source).

---

## 10. Refuted designs — do not re-propose

- **"Just fix the `delete-account` insert columns and ship."** Making it succeed mints a new
  channel value; `rolling-context:351`'s denylist admits it, so the rows get embedded into
  `memory_embeddings` (reaching ai-proxy's **system prompt**) and are then deleted, resetting the
  very counter the rate limit reads. Reproduces the Hermes P1-E/P1-F incident of 2026-08-20.
- **"Count `channel='app'` for the image cap"** (CODE-1). `'app'` is shared with ai-proxy text
  chat, so the cap would throttle PRO users on ordinary chat.
- **A counter table without a FK to `users`.** Creates a DPDP hole — §4.
- **Split by windowed vs lifetime.** Does not partition — §1.
- **A vocabulary-based gate matcher.** 2 false positives, 3 misses — §6.
- **Redis / Upstash.** The correct answer at scale and the first reach of every rate-limiter
  guide, but it adds a runtime dependency to a pre-launch solo-founder app whose entire load fits
  in Postgres. Revisit only if `usage_counters` contention shows up in `pg_stat`.

---

## 11. Open questions for review

1. Keep or drop the `verify_payment_attempt` audit row (§5)?
2. Retention window: 7 days chosen for debuggability. Anything ≥ 2× the longest window (1 day)
   works. Better number?
3. Should `consume_quota` be `SECURITY DEFINER` with `search_path` pinned? Migration 120's
   `SECURITY DEFINER` made that batch **catastrophic**-tier — this may raise the tier, which
   changes the review requirements. If it can be `SECURITY INVOKER` (service-role callers only),
   the tier stays `platform`.
