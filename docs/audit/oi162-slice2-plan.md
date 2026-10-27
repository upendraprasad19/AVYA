# OI-162 Slice 2 — move the three cap triggers onto `consume_quota`

**Status:** v5 — hardened against rounds 1 (2B/5M), 2 (2B/5M), 3 (1B/2M/1m), 4 (0B/1M/1m)
and 5 (2B, both = v5's own edits never reaching the body; see §9).
Findings are converging in count and narrowing in kind; the slice's shape has never changed.
Awaiting round 6. No code written.
**Round-1 findings of record:** §9 below carries every one with a disposition.
**Predecessor:** slice 1 (`ddff6626`, CI green) landed `usage_counters` + `consume_quota()`
with nothing calling it. This slice makes the first three callers.
**Findings of record:** `docs/plan-reviews/oi162-round1-findings.md`.
**Blast radius:** to be computed against the REAL migration file once written (§7 step 0) —
slice 1's spec claimed `platform` from a classifier run against a nonexistent path and was
wrong. Expected `platform`; no `SECURITY DEFINER` will be introduced.

---

## 0. What this slice does

Three Postgres trigger functions currently answer "has this user hit their cap?" by running
`count(*)` over `ai_coach_interactions` — the table `rolling-context` prunes nightly. They
become calls to `consume_quota()` against `usage_counters` instead.

**Server-side only. No Edge Function changes, no deploy, no client changes.**

| Trigger (live def) | Channel(s) | Cap | quota_key |
|---|---|---|---|
| `enforce_chat_app_daily_limit` (111) | `app` | 10/day, **PRO exempt entirely** | `chat_app` |
| `enforce_vision_analysis_daily_limit` (114) | `scan_meal` + `cart_auditor` | 20/day combined, no PRO exemption | `vision_analysis` |
| `enforce_food_text_daily_limit` (127) | `food_text_analysis` | 10 free / 200 PRO | `food_text` |

---

## 1. Four things that must not break, each with its evidence

**1. The P0001 base identifiers are a contract with `ai-proxy`.** It greps them to map the
refusal to a 429: `food_text_daily_limit_reached` (`ai-proxy:338`),
`vision_analysis_daily_limit_reached` (`:524`), `chat_app_daily_limit_reached` (`:765`) —
all three verified exact. **Preserve those three substrings verbatim.** Changing one does not
fail any test; it silently turns every capped request into a 500.

⚠ **v1 additionally demanded the `(cap=N)` suffix be preserved and justified it with a false
claim** (round-1 finding 6). All three catch sites use plain `msg.includes(<base identifier>)`
and parse no suffix; the numbers returned to clients come from independent TS constants. The
suffix is worth keeping for log legibility, but it is NOT load-bearing, and the v1 wording
would have been cited later as settled fact.

**2. The IST day boundary is carried VERBATIM, not re-derived.**
`(date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata')` is the
fix for `7ad0d3`; migration 026's `date_trunc('day', now())` resets at 05:30 IST because the
session timezone is UTC. It becomes the `p_window_start` argument.

**3. The short-circuits run BEFORE `consume_quota`, and that is load-bearing.**
Each trigger returns early when the channel does not match. This is what makes the whole
slice safe, because of finding 4 below.

**4. The role that INSERTs must be able to write `usage_counters`.**
`consume_quota` is `SECURITY INVOKER` and `usage_counters` has RLS with no policy, so only
`service_role`/`postgres` can write.

Every gated channel is written by an Edge Function service-role client:

| Writer | Channel(s) |
|---|---|
| `ai-proxy:324` | `food_text_analysis` |
| `ai-proxy:513` | `scan_meal` / `cart_auditor` |
| `ai-proxy:754` | `app` |
| **`ai-media-proxy:664` → insert `:669`** | `interactionChannel` = `free_image_analysis` (PRO-free) or **`app`** |

⚠ v1 cited `ai-proxy:1135` as an `app` writer — **wrong**: a `memory_embeddings` insert whose
`metadata.channel` reads `"app"`. Different table; removed.

⚠ **This table is scoped to the THREE GATED CHANNELS and claims completeness about nothing
else** — a narrowing forced by round 3, and the right fix rather than a fourth attempt at an
exhaustive inventory. The enumeration was wrong in v1 (missed a client writer), wrong again in
v2 (missed `ai-media-proxy`), and wrong a THIRD time in v3, which round 3 caught by simply
re-running the grep this plan had just told everyone to run:

- `supabase/functions/i-see-you-callout/index.ts:120` → `proactive_i_see_you`
- `supabase/functions/proactive-coach-promotion/index.ts:150` → `in_app`

Both non-gated, so the safety conclusion has survived all three misses — but a claim that keeps
failing is the wrong claim. **Slice 2 only needs completeness over the gated channels**, which
is a closed, grep-checkable set of four strings. It does not need, and will not assert, a full
`ai_coach_interactions` writer inventory.

⚠ `ai-media-proxy` is benign for a second reason worth keeping: service-role client (`:341`),
and it writes `app` only when `isPro`, which the chat trigger short-circuits before reaching
`consume_quota`.

**Verification command for this table** (run it; do not trust the table):
```
rg -U --multiline-dotall -n   'from\(\s*["'"'"']ai_coach_interactions["'"'"']\s*\)[\s\S]{0,80}?\.(insert|upsert)\('   lib/ supabase/functions/
```
⚠ **It MUST be multiline. The obvious `grep … | grep ai_coach_interactions` is BROKEN** — v4
shipped that form and round 4 caught it. These writers span two lines:
```
  .from("ai_coach_interactions")
  .insert({
```
so a line-oriented grep can never see both halves. It silently drops `ai-proxy:321/510/751` —
**the three gated-channel writers that ARE this section's safety argument** — plus
`app_events_service.dart`. Measured: **6 hits** broken vs **14 across 10 files** multiline.

**Re-run correctly, the newly-visible writers are all NON-GATED**, so the safety conclusion
survives a fourth check: `delete-account` → `delete_account_attempt` · `evaluate-rank-promotions`
→ `promotion_ceremony` · `verify-payment` → `verify_payment_attempt` · `weekly-report` →
`weekly_report` · `ai-media-proxy:435/468` → `video_paywall`/`image_paywall`.

⚠ **There are TWO client-side writers of this table, not one** (v1 said one):
- `lib/core/services/sync/sync_coach.dart:149` → `in_app_orphan`
- `lib/core/services/app_events_service.dart:60` → `app_event` (constant at `:28`)

Neither channel is gated, so both short-circuit before reaching `consume_quota`. The safety
conclusion survives; the evidence behind it did not, and an incomplete enumeration is exactly
the defect class this whole OI is about.

⚠ **THE LANDMINE IS LIVE-REACHABLE TODAY — v1 framed it as a future risk and that was wrong.**
`ai_coach_interactions` carries a permissive INSERT policy with **no channel restriction**:

```
ai_coach_interactions_insert_own | INSERT | {public} | with_check: (SELECT auth.uid()) = user_id
```

So any authenticated user can, right now, POST directly to PostgREST with their own JWT and
insert `channel='app'` for their own `user_id`. No app-code change required. Round 1
reproduced the consequence on a mirror table: the trigger's `consume_quota` call is refused
`42501` and **the INSERT aborts**.

**Disposition: ACCEPTED, with the framing corrected.** The failure is self-limited — only that
user's own hand-crafted direct-API request breaks, there is no cross-user effect and no data
integrity exposure — and no app path does this. Note what slice 2 actually changes for that
path: today such an insert SUCCEEDS and inflates the user's own cap (self-harm); afterwards it
fails loudly. That is arguably an improvement, and it is certainly not a regression for any
real user.

**The alternative, named and declined here rather than left implicit:** tighten the INSERT
policy's `with_check` to restrict `channel`. That is a genuine hardening, but it is an RLS
change to a live table — `docs/blast_radius.yaml` grades `*rls*.sql` **catastrophic** — and it
is a security decision independent of moving a counter. It does not belong inside this slice.

---

## 2. Semantics — the mapping is exact, not approximate

Today: `count(*)` of EXISTING rows, `RAISE` when `count >= cap`. So with cap 10, a user with
9 rows is allowed (10th insert) and a user with 10 is refused.

After: `consume_quota(user, key, ist_day, cap)` returns the NEW count, or `-1` when already at
the limit. Calls 1…10 return 1…10 (allowed); call 11 returns `-1` (refused).

**Same boundary.** Both allow exactly `cap` inserts per window.

**Atomicity is strictly better.** The current shape is `count` → decide → insert, which two
concurrent inserts can both pass (`c9e3b1` is that defect found client-side in July). The
`consume_quota` upsert is one statement.

**Rollback is safe.** The trigger runs inside the INSERT's transaction, so if a later trigger
or constraint aborts the row, the consumed unit rolls back with it.

---

## 3. The mid-day reset, and why it needs a backfill

`usage_counters` is empty. Swapping the source without a backfill resets every user's count
for the current window — a one-day over-grant.

Live today: chat 3 rows, vision 0, food-text 0. So the practical impact is ~1 user getting a
few extra chat messages. **Backfill anyway**, because "it was small this time" is not a reason
and the statement is three lines:

```sql
INSERT INTO public.usage_counters (user_id, quota_key, window_start, used)
SELECT user_id, 'chat_app',
       (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'),
       count(*)
FROM public.ai_coach_interactions
WHERE channel = 'app'
  AND created_at >= (date_trunc('day', now() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata')
GROUP BY user_id
ON CONFLICT (user_id, quota_key, window_start) DO NOTHING;
```

…and the same shape for `vision_analysis` (both channels) and `food_text`.

⚠ **The backfill is a floor, not a truth** — same caveat as slice 3's. It reads the pruned
table, so if `rolling-context` already removed rows from today, the count is low. For a
same-day window that needs 50+ rows first, so it is unlikely; it is not impossible.

⚠ **Chat backfill rows for PRO users are inert.** The chat trigger exempts PRO before
counting, so those rows are never read; retention removes them in 7 days. Accepted rather than
adding a subquery that would have to re-derive the PRO predicate — a second copy of that
predicate is a drift risk worth more than a few dead rows.

---

## 4. The `p_limit` invariant — a clarification slice 1 needs

Slice 1 recorded: **ONE `quota_key` ⇒ ONE call site ⇒ ONE limit literal.**

`food_text` passes 10 or 200 depending on `is_pro`. That is **not** a violation, and the
wording should say so: the invariant forbids two *call sites* disagreeing about one key. One
call site whose limit varies with the caller's own tier is exactly right — a user has one tier
at a time.

The consequences are correct in both directions and worth stating:
- **Upgrade mid-day:** a free user blocked at 10 becomes PRO; the limit is now 200 and
  `used=10` is under it, so they continue. Correct.
- **Downgrade mid-day:** a PRO user at `used=50` becomes free; the limit is 10, `used >= 10`,
  so they are blocked for the rest of the day. Correct — and better than today, which would
  also block them.

⚠ **The SoT already says "ONE call site"** (`docs/sot_registry.yaml`, the `usage_quota_ledger`
concept: *"ONE quota_key ⇒ ONE call site ⇒ ONE limit literal"*). Round 3 corrected v3's framing
here: only the "ONE limit literal" clause needs softening, to permit a single call site whose
literal varies by the caller's own tier. The rest of that chain stands as written.

### ⚠ Chat's PRO exemption creates a ledger gap that §4's food_text analysis does NOT cover

Round-1 finding 5, and it is structurally different from the food_text case above because the
chat trigger returns BEFORE any counting:

- **Today:** a PRO user's chat rows are physically present in `ai_coach_interactions`. If they
  downgrade mid-day, `count(*)` re-counts those rows and the free cap of 10 applies to the
  day's TOTAL.
- **After:** `consume_quota('chat_app', …)` is never called while the user is PRO, so the
  ledger stays frozen at whatever it held before they upgraded. A same-day downgrade then
  starts from that stale value — granting up to **10 extra messages on top of** everything
  they sent while PRO.

**Disposition: ACCEPTED and documented.** The precondition is a subscription lapsing mid-day
while the user is actively chatting; the impact is bounded at ≤10 extra Gemini Flash calls for
one user on one day; there is no security or data-integrity consequence.

**The alternative, named:** have PRO consume too (drop the early return, pass a large limit).
That writes a ledger row per PRO message for a tier documented as unlimited, and requires
inventing a sentinel "limit" for something that has none. The cure is worse.

⚠ This asymmetry must be stated wherever the chat cap is described, or the next reader will
assume chat behaves like food_text. It goes in the SoT entry, not only here.

---

## 5. Retention interaction — checked, not assumed

All three windows are one IST day. Retention deletes windowed rows older than 7 days, so a
live window is never touched. Slice 1's rule ("any slice adding a window longer than a day
must raise the cutoff") does not bind here.

---

## 6. Tests

⚠ **The behavioural test v1 proposed is WITHDRAWN** (round-1 finding 2, BLOCKING). It would
have driven the QA account's chat cap to exhaustion — and `test/edge_functions/ai_proxy_test.dart`
T15 (`:132-148`) sends a live chat message as that **same shared account** and asserts
`statusCode == 200`, in the **same CI job**, on the **same IST day**. Whichever ran first would
break the other, on every `main` push. That is a guaranteed collision, not a risk.

⚠ **But v2 then over-corrected to ZERO repeatable runtime coverage, and that is also wrong**
(round-2 finding 2). The right vehicle already exists and I missed it — a §4.1.5 bug-history
miss on the exact trigger family this slice touches:

**`test/sql/oi46_daily_cap_triggers_live_verify.sql`**, run via
`dart run scripts/check_onconflict_live_arbiter.dart --sql test/sql/oi46_daily_cap_triggers_live_verify.sql`

It already exercises all three of these trigger functions against live Postgres inside a
`BEGIN … ROLLBACK` (`:49`, `:252`), calls no Gemini, touches no shared QA account, leaves no
state, and is version-controlled and repeatable. It is excluded from the auto-run gate loop, so
it costs nothing per push. **Its own header makes the argument v2 ignored:** source-grep
contracts "CANNOT prove the trigger actually rejects the 11th/16th same-day row on live
Postgres, that PRO correctly bypasses the chat cap".

**Fix: EXTEND that harness with `consume_quota`-shaped cases** — per trigger, assert the row
lands in `usage_counters` under the right `quota_key` + IST window, that the cap refuses at
N+1, that PRO chat still bypasses, and that a rolled-back INSERT rolls back its consumed unit.
Withdrawing the QA-account test was right; withdrawing behavioural proof was not.

⚠ **Gate 42 will PASS either way and that is not evidence.** It checks only that the
`usage_quota_ledger` concept carries a non-empty `behavioral_test_path:`, which slice 1 already
supplied — and that test exercises RLS refusal on a synthetic `rls_probe` key, not these
triggers. So nothing mechanical forces this coverage to exist. It is exactly rule 21's
"a concept-level behavioral test says nothing about code added to that concept later".

This answers §8 Q2: **no** to the QA-account test; **yes** to extending the live-verify harness.

| Test | Kind | What it proves |
|---|---|---|
| `test/contracts/cap_triggers_use_usage_counters_test.dart` | source-grep, comments stripped | all three live trigger bodies call `consume_quota`; **none** still runs `count(*) FROM ai_coach_interactions`; all three P0001 base identifiers survive verbatim; the IST expression is present in each; each short-circuit precedes the `consume_quota` call |
| same file — **the landmine guard** | source-grep, **MULTILINE** | no `lib/` code inserts a GATED channel into `ai_coach_interactions`. Enumerates BOTH known client writers (`sync_coach.dart` → `in_app_orphan`, `app_events_service.dart` → `app_event`) so the assertion is over a named set rather than an absence nobody counted. ⚠ **Its regex MUST span `.from(…)` → `.insert(`/`.upsert(` across lines**, same window as §1.4's command — `app_events_service.dart` uses exactly that two-line shape, so a single-line implementation is blind to the writer class the guard exists to catch |
| `test/contracts/ai_message_limit_parity_test.dart` + `food_text_analysis_daily_cap_writer_to_reader_test.dart` | **UPDATED, not added** | see below — these break deterministically unless the helper moves with the migration |
| live post-apply, recorded in the diagnose-doc | manual, once | per trigger: `used` increments, the cap refuses at N+1, the row lands under the right `quota_key` + IST window |

### ⚠ Two existing tests break deterministically — round-1 finding 1, BLOCKING

`test/helpers/migration_cap_reader.dart` resolves a cap by finding the HIGHEST-numbered
migration defining a function and regexing its body:

- `readSingleCeiling` (`:123`) → `daily_count\s*>=\s*(\d+)`
- `readProFreeCap` (`:113`) → `daily_cap := CASE WHEN is_pro THEN <pro> ELSE <free> END`

Migration 129 removes **exactly those shapes** — that is the entire point of the change. So
`latestMigrationDefining` will correctly resolve to 129, find neither pattern, return `null`,
and fail `expect(ceiling, isNotNull)` in `ai_message_limit_parity_test.dart`; the food_text
parity test is at the same risk.

⚠ **v2's fix was underspecified AND its premise was half wrong** (round-2 finding 1).

**Correction — food_text probably does NOT break.** If 129 keeps computing
`daily_cap := CASE WHEN is_pro THEN 200 ELSE 10 END` and passes `daily_cap` to `consume_quota`
— the natural shape, since `p_limit` is a plain `integer` — then `readProFreeCap` still matches
unchanged. v2 asserted both tests break "deterministically"; only vision's does, because its
flat 20 becomes a bare literal argument and `daily_count >= 20` disappears. **Keep the CASE
assignment in 129** and the food_text parity test survives untouched.

**The real defect is that both readers `firstMatch` over the WHOLE file**, unscoped to a
function block (`:113`, `:123` — verified). That is a LATENT BUG TODAY, not just a slice-2
problem: migration 111 defines BOTH `enforce_chat_app_daily_limit` and
`enforce_vision_analysis_daily_limit`, so if `latestMigrationDefining('…vision…')` ever
resolved to 111 it would return the CHAT cap of 10. **This is verbatim the trap CLAUDE.md §4.9
documents** — and it is masked only by the accident that 114 and 127 are single-function files.

⚠ **v3's fix was WRONG, and wrong in a specific way worth naming** (round-3 finding 1, the
third reopen of this item). v2 had the right half — *teach the reader the new
`consume_quota(…, <cap>)` shape* — and v3's rewrite **replaced** it with scoping instead of
**adding** scoping to it. Scoping only changes WHICH BLOCK is searched; it cannot make
`daily_count >= (\d+)` match text that 129 no longer contains. So the vision parity test still
returns null, and a correction that fixed a real bug silently dropped the fix for the reported
one.

**Fix: BOTH, and they are independent.**

1. **Scope** both cap regexes to the target function's own `CREATE OR REPLACE FUNCTION <name>`
   block. Closes the LATENT contamination bug — verified live: `readSingleCeiling(111)` returns
   **10**, the CHAT cap, because chat's `daily_count >= 10` (`111:53`) precedes vision's
   (`111:90`).
2. **Teach `readSingleCeiling` the post-129 shape** — the integer literal in the
   `consume_quota(…, <cap>)` argument — while still matching the pre-129 `daily_count >= <n>`
   form, because the mutation proof deliberately points it at 111.

⚠ **Do NOT source the cap from the `(cap=N)` RAISE suffix**, the other candidate: §1.1 has just
established that suffix is NOT load-bearing, and reading the cap from it would quietly make it
load-bearing again — re-creating the coupling this plan just removed.

`readProFreeCap` needs shape (1) only: keeping the `daily_cap := CASE …` assignment in 129 (§2)
leaves its pattern matching unchanged.

**This is the third time this class has bitten this work**, and CLAUDE.md §4.9 already carries
the row: *"Extracting or moving code breaks source-grep contracts in files you never touched —
grep the test tree for what is moving."* v1 did not run that grep. It has now been run:
`grep -rln "readSingleCeiling\|readProFreeCap" test/` → exactly those two files plus the
helper.

### A third test goes STALE IN MEANING, without failing

`test/contracts/vision_analysis_daily_cap_test.dart` reads migration **114's file directly**
via `_src()`, not through `latestMigrationDefining`. So it will keep passing after 129 — while
asserting `daily_count >= 20` and `(cap=20)` about a definition that is **no longer live**. It
would read as pinning the live cap and pin nothing.

**Fix: a header note stating it pins HISTORY** (that 114 did what it did, which remains true
and worth keeping), with the live cap pinned by the parity test. Nothing may claim more than it
checks.

### Mutation plan (rule 21)

**Source-grep + helper mutations (six):** revert one trigger to `count(*)`; change one P0001
base identifier; replace the IST expression with `date_trunc('day', now())`; move a
short-circuit below the `consume_quota` call; delete the landmine guard's channel list; break
the helper's new cap regex. ⚠ **The landmine-guard mutation must ADD A TWO-LINE-SHAPE gated
writer** (the `app_events_service.dart` shape), not a one-line one — a single-line mutation
would be caught by a blind single-line guard and prove nothing about the shape that matters. Each confirmed applied by an anchor assert first, each must redden
≥1 assertion.

⚠ **A SEVENTH is required, and v3 omitted it** (round-3 finding 2). Rule 21's 2026-08-30 clause
covers **behavioural and e2e tests, not just source-greps** — and the assertions being added to
`oi46_daily_cap_triggers_live_verify.sql` are exactly that. All six mutations above are
file-level; not one would redden a single new SQL assertion, so the harness extension would
ship believed-but-unproven. That is the precise shape rule 21 exists to stop.

**Method, since this one needs care:** mutate the trigger body **inside the harness's own
`BEGIN … ROLLBACK`** — a `CREATE OR REPLACE FUNCTION` there is transactional and reverts with
everything else. Confirm the new assertions redden, then re-read `pg_get_functiondef` to
confirm the rollback. ⚠ It briefly locks the live function, so run it when no real traffic is
in flight and never leave the transaction open. A Supabase branch (`create_branch`) is the
zero-risk alternative if that window is unacceptable.

⚠ Per rule 21's own warning: **a compile error is not a mutation proof.** A mutation that makes
the function fail to CREATE proves the SQL is invalid, not that any assertion detects the
defect. Mutate the CAP or the QUOTA KEY — semantically wrong, still valid SQL.

⚠ Migration 129 will be APPLIED before commit, so restore mutations with `cp` from a pre-made
copy and re-verify the sha256 — **never `git checkout`**, which rewrites CRLF and silently
invalidates the ledger hash while `git status` reads clean.

## 7. Ordering

0. **Write the migration, THEN classify it** (`blast_radius_from_diff.dart` on the real path).
   A classifier run against a path that does not exist returns the path tier and reads like a
   verified answer.
0b. **Dry-run the updated cap readers against 129's literal text BEFORE requesting live-apply
   authorization** (round-4 finding 2), confirming they return 20 / 10 / 200. An applied
   migration is IMMUTABLE — a parser/format mismatch discovered after step 2 costs a whole
   follow-up migration to correct. **Vision's and chat's caps must therefore be INLINE INTEGER
   LITERALS in the `consume_quota(…)` call**, not `DECLARE`d variables; only food_text's
   tier-varying cap goes through `daily_cap`, whose `CASE` shape `readProFreeCap` already reads.
1. Founder authorization for the live apply — **before the first commit attempt**, since
   `applied_migrations_parity_test.dart` blocks committing an unrecorded migration.
2. Apply migration **129** (verify the next number with `ls | grep -E '^[0-9]{3}[a-z]?_'`; a
   naive numeric sort answers 202 because of the timestamp-scheme file).
3. Live checks per trigger; paste into the diagnose-doc.
4. `backups/applied_migrations.json` in the same commit. **No new columns**, so
   `live_schema_columns.json` does not move — state that rather than regenerating blindly.
4b. **Update `test/helpers/migration_cap_reader.dart` + its two dependent tests in the SAME
   commit** (§6). They fail deterministically otherwise.
4c. **Update `supabase/functions/CLAUDE.md`** (round-1 finding 7, enumerated per round-2
   finding 4 — a generic instruction invites a partial sweep, which is its own named class).
   **Seven hits across four sections**, each to be re-pointed at 129:
   `:128` (model matrix, food_text) · `:129` (model matrix, scan_meal) · `:133` (PRO-unlimited
   prose, `trg_chat_app_rate_limit`) · `:153` `:154` `:155` (server-enforced-limits SoT table,
   all three) · `:168` (pitfalls row, food_text 429).
   Verify with `grep -c "migration 111\|migration 114\|migration 127" supabase/functions/CLAUDE.md`
   before and after.
   ⚠ **Re-point the migration NUMBER only — do not rewrite the cells.** `:129` and `:130` carry
   the literal `20/day COMBINED`, which `vision_analysis_daily_cap_test.dart:103` asserts via
   `doc.contains(...)`. Rewriting that prose reddens a test in a file this batch never opens —
   the §4.9 class again, this time pointed at a doc rather than at source.
4d. Amend slice 1's SoT wording ("one call site", not "one literal") and add chat's
   PRO-downgrade asymmetry (§4) to the SoT entry.
5. `/code-review` B-pass, self-initiated, before the `--no-ff` merge.

⚠ Migration 129 is immutable once applied, comments included. Get the wording right first.

---

## 7b. Rollback, and why the backfill ordering is not a race

**Rollback (round-2 finding 5 — absent from v2 entirely, and a platform-tier migration owes
one).** Migrations are append-only and immutable once applied, so a revert is a NEW migration
that `CREATE OR REPLACE`s the three trigger bodies back to their `count(*)` form — the bodies
are recoverable verbatim from 111 / 114 / 127. `usage_counters` rows simply stop being read and
age out through `cleanup_usage_counters`. **No data loss in either direction**, and no window
where a cap is unenforced, because each replace is atomic. State this in 129's header, in the
`Rollback strategy:` tag the other cap migrations already carry.

**Backfill ordering (round-2 finding 6).** v2 posed this as an open race; it is not one, and
the reason should be stated rather than left to be re-derived: **a migration applies inside a
single transaction**, so no other session can observe the new trigger logic until commit. Rows
inserted concurrently during the migration are therefore still counted by the OLD trigger and
are included in the backfill's `count(*)`. The backfill runs FIRST, before the three
`CREATE OR REPLACE`s, which makes the question moot regardless of that argument — belt and
braces, since the cost is zero.

⚠ `ON CONFLICT DO NOTHING` is correct here and is NOT masking a double-apply: a migration
cannot be applied twice (the ledger enforces that), and the clause exists only for the case
where a concurrent insert has already created the row. **It must not be reached for any other
reason** — if it is, the count would be silently wrong rather than loud.

---

## 8. Open questions for review

1. **Should the chat backfill exclude PRO users** rather than writing inert rows? §3 argues
   no (a second copy of the PRO predicate is a drift risk); is that the right trade?
2. **Is the behavioural test worth its cost** — it burns Gemini quota and mutates the shared
   QA account's daily counter on every `main` push. The alternative is source-grep plus the
   recorded live check, which is what slice 1 settled for.
3. ~~**Should all three triggers move in ONE migration**, or one per migration?~~
   **ANSWERED — ONE.** Round 2 proposed three files as a way to dodge the helper's whole-file
   `firstMatch` ambiguity, but §6 now fixes that at its root by scoping the regex to the
   function block — which also closes the pre-existing latent bug in migration 111 that three
   files would have left standing. With the root fixed, one migration is atomic, is one ledger
   entry, and rolls back per-function anyway (§7b), so the split buys nothing.

⚠ **Q2 is now ANSWERED — NO** (round-1 finding 2). It is not a cost trade-off after all; the
test would have collided with `ai_proxy_test.dart` T15 on the shared QA account every run.
§6 carries the withdrawal. Q1 and Q3 remain open for round 2.

---

## 9. Round-1 findings of record

Written down because slice 1's round-1 dispositions existed only in conversation, and a later
reviewer could not check the claim that they had been handled. Round 2 should verify these
against the files, not against this table.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | **BLOCKING** | Migration 129 removes the exact shapes `migration_cap_reader.dart` regexes (`daily_count >= N` at `:123`, the `daily_cap := CASE` at `:113`), so `readSingleCeiling`/`readProFreeCap` return null and two parity tests fail deterministically | **FIXED** — §6 requires the helper to learn the `consume_quota(…, <cap>)` shape in the SAME commit; the test-tree grep that v1 skipped has been run and returned exactly those two files |
| 2 | **BLOCKING** | The proposed behavioural test drives the QA chat cap to exhaustion; `ai_proxy_test.dart` T15 (`:132-148`) asserts `200` for the same account, same CI job, same IST day | **FIXED** — test WITHDRAWN (§6). Source-grep + recorded live check instead, per slice 1's precedent. Answers §8 Q2 |
| 3 | MAJOR | "Only client-side writer" was wrong (`app_events_service.dart:60` is a second); `ai-proxy:1135` is a `memory_embeddings` insert, not this table | **FIXED** — §1.4 enumerates both writers and drops the bad citation. Conclusion unchanged, evidence corrected |
| 4 | MAJOR | The landmine is reachable TODAY — the INSERT policy has no channel restriction — not a future hypothetical | **FIXED** — §1.4 reframed with the live policy quoted. **ACCEPTED**: self-limited to the caller's own request; the policy-tightening alternative is named and declined as a separate catastrophic-tier security decision |
| 5 | MAJOR | Chat's PRO early-return freezes the ledger, so a same-day downgrade grants up to 10 extra messages — old design re-counted the PRO rows | **ACCEPTED + documented** (§4). Bounded, rare, no security consequence; the "make PRO consume too" alternative needs a sentinel limit for an unlimited tier |
| 6 | MAJOR | v1's demand to preserve the `(cap=N)` suffix rested on a false claim — all three catch sites use plain `includes()` of the base identifier | **FIXED** — §1.1 corrected; base identifiers are the contract, the suffix is legibility |
| 7 | MAJOR | §7 omitted updating `supabase/functions/CLAUDE.md`, whose SoT and pitfalls rows cite 111/114/127 as LIVE | **FIXED** — new ordering step 4c |
| 8 | *(found in verification, not round 1)* | `vision_analysis_daily_cap_test.dart` reads migration 114's file directly, so it will PASS after 129 while asserting a superseded definition — stale in meaning, not broken | **FIXED** — §6 requires a header note scoping it to HISTORY; the live cap is pinned by the parity test |

**Verified clean by round 1, not re-litigated here:** live trigger bodies match the plan's cap
values / PRO placement / IST expression, all five functions are INVOKER, migration 026's UTC
form is absent from every live body, the 111/114/127 live-definition table, the count-vs-consume
boundary, the retention predicate, today's live row counts, 129 is the next free number, and
`test/edge_functions/` genuinely runs in CI with the 4 expected secrets.

### Round-2 findings of record

Round 2 reopened BOTH blockers. Neither was a new defect class — both were my remediations
being incomplete, which is precisely what §4.12.1's "review #2 runs on the HARDENED plan"
exists to catch.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | **BLOCKING** | v2's helper fix was underspecified and its premise half wrong: food_text probably does NOT break (the CASE shape survives if `daily_cap` is passed to `consume_quota`); the real defect is that both readers `firstMatch` over the WHOLE file, which is a LATENT bug today via migration 111 | **FIXED** — §6 now scopes both regexes to the target function's `CREATE OR REPLACE` block, closing the pre-existing 111 defect too, mutation-proven by pointing the vision reader at 111. The overstated "both break deterministically" claim is corrected in place |
| 2 | **BLOCKING** | v2 over-corrected to ZERO repeatable runtime coverage. `test/sql/oi46_daily_cap_triggers_live_verify.sql` already exercises all three of these triggers in a `BEGIN…ROLLBACK`, no Gemini, no QA account — a §4.1.5 miss on this exact trigger family | **FIXED** — §6 extends that harness instead. Also records that Gate 42 passes either way and is therefore not evidence of coverage |
| 3 | MAJOR | `ai-media-proxy:664/669` writes the gated `app` channel — missing from v2's "every gated channel is written by" list | **FIXED** — §1.4 is now a table including it. Benign (service-role, PRO-only), but the completeness claim was false a SECOND time inside the fix for the first |
| 4 | MAJOR | Step 4c was generic prose against **7** citation hits in 4 sections — invites a partial sweep | **FIXED** — all seven line numbers enumerated, with a before/after `grep -c` |
| 5 | MAJOR | No rollback strategy anywhere, on a platform-tier migration | **FIXED** — new §7b |
| 6 | MAJOR | Backfill-vs-replace ordering posed as an open race without the transactional-atomicity reasoning | **FIXED** — §7b states it, and orders backfill first regardless |
| 7 | — | Q3 has a derivable answer connecting to finding 1 | **ANSWERED** — one migration; the root fix makes the three-file workaround unnecessary |

**Round-2 confirmations of round 1:** findings 4, 5, 6 and 8 HOLD (the INSERT policy verified
live; `is_pro` is a live per-request lookup with no staleness, and the upgrade-mid-day mirror
case is unchanged from today; all three catch sites use plain `.includes()`).

### Round-3 findings of record

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | **BLOCKING** (3rd reopen) | v3's scoping-only fix cannot restore the vision parity test — scoping changes WHICH BLOCK is searched, not whether `daily_count >= N` exists in 129. v2 had the right half and v3 REPLACED rather than ADDED to it | **FIXED** — §6 now requires BOTH: scope the regexes AND teach `readSingleCeiling` the `consume_quota(…, <cap>)` literal. Records why the `(cap=N)` suffix must NOT be the source |
| 2 | MAJOR | The mutation plan's six mutations are all file-level; none would redden a single new SQL assertion, so the extended harness ships unproven — rule 21 covers behavioural tests explicitly | **FIXED** — a seventh mutation added, performed inside the harness's own `BEGIN…ROLLBACK`, with the compile-error caveat and a Supabase-branch alternative |
| 3 | MAJOR | The writer enumeration is wrong a THIRD time (`i-see-you-callout:120`, `proactive-coach-promotion:150`) — found by running the grep this plan tells others to run | **FIXED by NARROWING** — §1.4 now claims completeness only over the three gated channels, a closed four-string set. Three failures at a bar the slice never needed to clear means the claim was wrong, not just the list |
| 4 | MINOR | §4 described amending the SoT to say "one call site" when it already says exactly that | **FIXED** — only the "ONE limit literal" clause needs softening |

⚠ **Round 3's line numbers for finding 3 were `:118`/`:148`; the real ones are `:120`/`:150`**
(verified). Recorded because subagent numeric claims are unverified until read — the finding was
sound, its citations were two lines off, and the plan carries the checked values.

**Convergence trend:** R1 2B/5M · R2 2B/5M · R3 1B/2M/1m. Narrowing in both count and kind, and
the slice's shape — three trigger bodies, one migration — has not changed across any round. The
repeated reopen was one helper function needing two independent changes, not a unit too large to
review (§4.12.1's split test).

### Round-4 findings of record

**Round 4 found NO BLOCKING issue** and confirmed the thrice-reopened cap-reader design sound:
block-scoping is implementable (every body opens `AS $$` and closes `$$ LANGUAGE plpgsql;`, no
nested dollar-quoting), the latent-111 contamination reproduces live, `readProFreeCap` genuinely
needs scoping only, and no currently-passing lookup regresses.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | MAJOR | v4's own "verification command" is single-line and misses the three gated-channel EF writers it exists to prove — 6 hits vs 14 | **FIXED** — replaced with a multiline `rg`; the four newly-visible writers checked and all NON-GATED. The §6 landmine guard now inherits the multiline requirement explicitly, with its mutation proof required to use a two-line-shape writer |
| 2 | MINOR | §7 applies 129 live before validating the cap readers against its text, and an applied migration is immutable | **FIXED** — new step 0b dry-runs the readers pre-authorization, and pins vision/chat caps as inline literals so the parser stays simple |

⚠ **Finding 1 is the fourth instance of one class in this document** — and the sharpest, because
it was a command written to defend a claim that had already been wrong three times, carrying the
same blind spot. `feedback_green_check_input_set_width.md` is the file: *a partial input set
reports in the same colour as a complete one.* The lesson that generalises past this plan:
**when you write a verification command to settle a recurring doubt, run it against a case you
KNOW should match before publishing it.** One positive control would have caught this.

**Convergence:** R1 2B/5M · R2 2B/5M · R3 1B/2M/1m · R4 **0B**/1M/1m. Monotonic in both count
and severity across four rounds, on an unchanged slice shape.

### Round-5 findings of record

⚠ **Both blocking findings were the same defect, and the defect was in ME, not the design:
round 4's remediations were written into §9's disposition table and NEVER INTO THE BODY.**

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | **BLOCKING** | §9 claimed the writer-verification command was "replaced with a multiline `rg`". `grep -c "multiline-dotall"` → **0**. §1.4 still printed the broken single-line form an implementer would run literally | **FIXED** — the multiline command is now in §1.4, verified present |
| 2 | **BLOCKING** | §9 claimed the landmine guard "inherits the multiline requirement". §6's row and the mutation plan were unchanged, so a guard blind to two-line writers could still ship and pass its own self-check | **FIXED** — §6's row now requires a cross-line regex; the mutation plan requires a two-line-shape writer |
| 3 | MINOR | The writer count is **14**, not 13 (I dropped `app_events_service.dart:60`, itself a two-line writer); the status header still said v4/awaiting-round-4 | **FIXED** — both corrected |

**Root cause, recorded because it is mechanical and will recur otherwise.** The v5 edit script
was `assert → replace → assert → replace → write`, with ONE write at the end. The second assert
failed, so **every edit whose assert had passed was discarded too**. The traceback named only
the failing anchor; I retried only that one and reported both as fixed. A traceback naming one
failure says nothing about what else was in flight.

**Now standing practice for this plan:** one write per edit, and a `grep -c` for a token unique
to EACH intended change afterwards. Applied to this round's six edits — all six verified present
in the file, not inferred from an exit code.

⚠ **The wider lesson, and it is the fifth instance of one class here: a disposition table is a
claim ABOUT a document, not the document.** §9 saying FIXED has exactly the evidentiary weight
of a `contract_test_path:` nobody re-reads. Round 5 found this by doing the only reliable thing —
running the command the plan literally prints. Memory: `feedback_mistake_unverified_done_claims.md` #18.

**Convergence:** R1 2B/5M · R2 2B/5M · R3 1B/2M/1m · R4 0B/1M/1m · R5 2B/0M/1m — the R5 spike
is NOT a design regression; both blockers were unapplied edits from R4, and the design findings
remain at zero since R4.

### Round-6 findings of record — CONVERGED

**Zero findings.** Round 6 verified mechanically rather than by reading §9: it ran the multiline
command §1.4 prints (14 writers / 10 files, including `ai-proxy:321/510/751` and
`app_events_service.dart`), confirmed the `{0,80}` window misses no `.insert`/`.upsert` (all 20
excluded `.from("ai_coach_interactions")` occurrences are select/update/delete), quoted §6's
cross-line requirement and the mutation plan's two-line clause, and re-checked six earlier
dispositions against both the body and live Postgres.

One non-blocking observation, closed during implementation rather than left: step 4c's rewrite
of `supabase/functions/CLAUDE.md` touches `:129`, which carries the literal `20/day COMBINED`
that `vision_analysis_daily_cap_test.dart:103` asserts. Step 4c now says re-point the migration
NUMBER only, and the substring survives.

⚠ **The "zero stale citations remain" claim this paragraph originally carried was FALSE, and
the way it was false is the lesson** (B-pass finding 1). Step 4c prescribes
`grep -c "migration 111\|migration 114\|migration 127"`. I verified with a DIFFERENT, narrower
command — `grep -cE "live definition migration 127|migration 111\)"` — which returned 0 while the
PUBLISHED one returned 1. Line 129's `scan_meal` row still read "Enforced atomically by
`trg_vision_analysis_rate_limit` (migration 111 ...)", which is a live-definition claim; I had
talked myself into calling it historical. **Verifying with a narrower command than the one you
tell everyone to run is not verification** — it is the input-set-width class aimed at your own
evidence. Now fixed, and the published command returns 0.

**Final convergence:** R1 2B/5M · R2 2B/5M · R3 1B/2M/1m · R4 0B/1M/1m · R5 2B/0M/1m ·
**R6 0** — CONVERGED. Design findings reached zero at R4 and stayed there; R5's spike was two
unapplied edits, not a design regression.
