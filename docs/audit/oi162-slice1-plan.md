# OI-162 Slice 1 — the usage-counter table and `consume_quota`, with nothing calling it

**Status:** v3 — hardened against review rounds 1 (2 blocking) and 2 (0 blocking, 2 major,
2 minor). Awaiting a narrow confirmation pass. No code written.
**Round 2's verdict on the architecture:** *"the DEFINER→INVOKER correction itself holds up
under live, adversarial testing."* Its findings were about tracking and test placement, not
design.
**Findings of record:** `docs/plan-reviews/oi162-round1-findings.md` — every finding from both
rounds, with a disposition. Read it rather than trusting any summary here.
**Supersedes for execution:** `docs/audit/oi162-plan.md` (committed `dba59b15`), the
all-at-once design. Its refuted-designs section is still the authority on what not to
re-propose.

**Blast radius: `platform`** — and see §7 step 0 for how to verify that claim, because v1 got
it wrong in a way that reads as verified.

---

## 0. What this slice is

**Infrastructure that nothing calls.** One migration creating `usage_counters` and
`consume_quota()`, plus the detection gate in warn-only. Zero call sites change. Zero
user-visible behaviour changes. All 9 readers keep counting rows in `ai_coach_interactions`
exactly as today.

**Does NOT touch:** `delete-account`, `verify-payment`, `ai-proxy`, `ai-media-proxy`,
`weekly-report`, the three cap triggers, the dormant PRO image cap, or any quota anyone
experiences.

---

## 1. What round 1 changed, and why the design is now better

Round 1 returned two blockers. **Both are resolved by a single change — `SECURITY INVOKER`
instead of `SECURITY DEFINER` — and the result is stronger than what it replaced.**

**Blocker A: the tier claim was false.** `scripts/blast_radius_content_rules_lib.dart`
escalates any migration containing `SECURITY DEFINER` to `catastrophic` regardless of path.
v1's "computed not estimated" ran the classifier against a path that **did not exist on
disk**, so the content rule had nothing to read and failed open to `platform`.

**Blocker B: a false premise handed downstream.** v1 told slice 2 that "triggers fire
regardless of role EXECUTE grants" and not to re-derive it. That is true of the trigger
function *itself* and false for a **nested call** from inside it to a separately-revoked
function — demonstrated by execution: `permission denied for function`.

Under `SECURITY INVOKER` both stop existing: there is no `SECURITY DEFINER` to escalate the
tier, and EXECUTE can be granted broadly because **the grant is no longer the guard — RLS
is**. A function that cannot write is not a privilege-escalation surface no matter who calls
it.

**Verified live on `dedsavbjuwgarrhphgnl` in a rolled-back transaction, not reasoned:**

| Caller | Outcome |
|---|---|
| `service_role` (what the Edge Functions use) | writes OK, returns `1` |
| `authenticated`, **holding EXECUTE** | **BLOCKED `42501`** — `new row violates row-level security policy` |
| `anon`, **holding EXECUTE** | **BLOCKED `42501`** — same |

Probe objects dropped; `usage_counters` / `consume_quota` confirmed non-existent afterwards.

---

## 2. The table

```sql
CREATE TABLE public.usage_counters (
  user_id      uuid        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  quota_key    text        NOT NULL,
  window_start timestamptz NOT NULL,
  used         integer     NOT NULL DEFAULT 0,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, quota_key, window_start)
);

ALTER TABLE public.usage_counters ENABLE ROW LEVEL SECURITY;
-- deliberately NO policy. service_role bypasses RLS; every other role is denied.
-- This is the security boundary — not the EXECUTE grant on consume_quota (§4).
```

**`ON DELETE CASCADE` is load-bearing.** `delete-account/index.ts:440`'s `deleteUser` is the
only deletion path and DPDP compliance relies on cascade. A no-FK table would strand quota
rows for deleted users — a real defect in an earlier draft.

**Column naming, with round 1's corrections applied:**
- `quota_key`, not `meter`. ⚠ v1 justified this as "`Meter` is reserved" —
  **overstated** (round-1 finding G): `naming_conventions.md:210` is a category subheading in
  the UI-primitives section, not an entry in the reserved-domain glossary. The honest reason
  is weaker and still sufficient: `Meter` already names the Ward widget family
  (`WardBar`, `WardSpark`, `WardRing`, …) in docs that auto-load, so reusing it invites
  confusion for no benefit.
- `used`, not `count`. ⚠ v1 claimed `count` is "a PostgREST reserved request parameter" —
  **false** (round-1 finding F): `count` travels in the `Prefer: count=exact` HEADER, so a
  column of that name would not collide. `used` is still preferred because it reads correctly
  in `used >= p_limit` and avoids shadowing the `count()` aggregate inside plpgsql; the v1
  reason was simply wrong.
- Both terms are appended to `docs/naming_conventions.md` in the same commit (§4.7).

---

## 3. `consume_quota` — full body

```sql
CREATE OR REPLACE FUNCTION public.consume_quota(
  p_user_id      uuid,
  p_quota_key    text,
  p_window_start timestamptz,
  p_limit        integer
) RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER          -- NOT DEFINER: see §1 and §4
AS $$
DECLARE
  v_used integer;
BEGIN
  IF p_user_id IS NULL OR p_quota_key IS NULL OR p_window_start IS NULL THEN
    RAISE EXCEPTION 'consume_quota: null argument';
  END IF;
  IF p_limit IS NULL OR p_limit < 0 THEN
    RAISE EXCEPTION 'consume_quota: invalid limit %', p_limit;
  END IF;

  -- p_limit = 0 means "nothing is ever allowed". Without this the unconditional
  -- INSERT arm below returns 1 on the first call, granting one free use — the
  -- arm is not limit-gated, only the ON CONFLICT branch is (round-1 finding E).
  IF p_limit = 0 THEN
    RETURN -1;
  END IF;

  INSERT INTO public.usage_counters AS uc (user_id, quota_key, window_start, used, updated_at)
  VALUES (p_user_id, p_quota_key, p_window_start, 1, now())
  ON CONFLICT (user_id, quota_key, window_start) DO UPDATE
    SET used = uc.used + 1, updated_at = now()
    WHERE uc.used < p_limit
  RETURNING used INTO v_used;

  -- No row RETURNED means the WHERE guard skipped the UPDATE, i.e. already at the
  -- limit. plpgsql leaves v_used NULL there, and NULL is exactly the value that
  -- reads as "fine" at a call site. Convert to an explicit sentinel HERE, once,
  -- rather than trusting every future caller to handle NULL.
  IF NOT FOUND OR v_used IS NULL THEN
    RETURN -1;
  END IF;

  RETURN v_used;
END;
$$;
```

**Contract:** returns the new count (≥1) when allowed; returns **-1** when the quota is
exhausted or `p_limit = 0`. Never returns 0; never returns NULL.

**No `SET search_path`** — round-1 finding H noted v1's `public, pg_temp` diverged from repo
convention. It is moot here: `search_path` hardening exists to stop a `SECURITY DEFINER`
function resolving objects as its owner. An INVOKER function carries no such risk.

**Why `VALUES (…, 1)` and not the column default:** the first call IS a consumption. Relying
on `DEFAULT 0` returns 0 for it, and `0 >= limit` is false for every positive limit — every
quota would grant one extra unit.

**Atomicity, measured not assumed.** Round 1 issued **19 concurrent calls** on one key and got
exactly 1…19 — no duplicates, no gaps, no lost updates. Today every site is `count(*)` →
decide → insert, where two concurrent requests both read 4 and the user gets 6; `c9e3b1`
(2026-07-29) is that defect found on the client side.

---

## 4. Privileges — the guard is RLS, not the grant

```sql
GRANT EXECUTE ON FUNCTION public.consume_quota(uuid, text, timestamptz, integer)
  TO service_role, authenticated;
```

⚠ **That GRANT is REDUNDANT, and `anon` gets EXECUTE for free whether we like it or not** —
round-2 finding 3, verified live:

```
select da.defaclacl from pg_default_acl da join pg_namespace n on n.oid=da.defaclnamespace
where n.nspname='public' and da.defaclobjtype='f';
→ {postgres=X/…, anon=X/…, authenticated=X/…, service_role=X/…}   (both grantors, no PUBLIC entry)
```

This project's schema-level `ALTER DEFAULT PRIVILEGES` grants EXECUTE on **every new
function** in `public` to all four roles the moment it is created — before any GRANT in the
migration runs. It is the same institutional trap `a9d3f1` documents (grants go DIRECT to
roles, which is why `REVOKE … FROM PUBLIC` was a no-op there). The GRANT is kept as
executable documentation of intent; it is not what confers access.

**So the design must not depend on grants at all, and it does not.** Under `SECURITY INVOKER`
the caller's own privileges apply, so `authenticated` *and* `anon` both reach the INSERT and
are both refused by RLS-with-no-policy — identical `42501`, verified §1, with no
existence-oracle difference between a present and an absent row (round 2 probed for one). The
worst any client can do is receive an error.

This is also what makes slice 2 work: its triggers call `consume_quota` as whatever role
performed the INSERT, and a missing EXECUTE grant would fail them with
`permission denied for function` (blocker B). Round 2 confirmed the real call graph is safe —
all three live cap triggers are `prosecdef=false` (INVOKER) and every currently-gated INSERT
is performed by `ai-proxy`'s service-role client — but slice 2 must **demonstrate** that, not
inherit it, because the previous version of this sentence was wrong.

This also removes blocker B: slice 2's cap triggers call `consume_quota` as whatever role
performed the INSERT, and a missing EXECUTE grant would have failed them with
`permission denied for function`. With the grant present, any role may *call* it; only
`service_role` may *write*.

⚠ **The dual-revoke reasoning from v1 §4 is now moot but was NOT wrong** — for a `DEFINER`
function it is correct and both halves are needed (migrations 090/091 and the
`supabase/migrations/CLAUDE.md` pitfalls row document opposite no-ops). It is recorded in the
findings file so a future `SECURITY DEFINER` function here does not re-derive it.

**Mandatory live post-apply verification** (§6 tier 8) — the pitfalls row is explicit that
static review cannot see grant state:

```sql
-- RLS must be ON with zero policies
select relrowsecurity from pg_class where relname = 'usage_counters';
select count(*) from pg_policies where tablename = 'usage_counters';   -- must be 0
-- and the behavioural check, which is what actually matters:
--   as authenticated -> 42501 ; as service_role -> returns 1
```

---

## 5. Retention — a two-sided predicate, deliberately

```sql
DELETE FROM public.usage_counters
WHERE window_start <> 'epoch'::timestamptz
  AND window_start < now() - interval '7 days';
```

Windowed quotas are disposable; lifetime quotas (`window_start = 'epoch'`) must never be
deleted — deleting them reintroduces the original bug inside the new table.

⚠ **Both conjuncts are load-bearing.** This is the two-sided-band class that shipped a
zero-byte-file-passes bug on 2026-08-30: a bound with only one side is a half-finished
thought. The mirror test in §6 pins `'epoch'` survival, not only old-window deletion.

Dispatch: a `pg_cron` entry joining `docs/operations/CRON_REGISTRY.md` (Gate 31). It is
SQL-only, so `_shared/cron_telemetry.ts` does not apply — §4.5 scopes that to cron-dispatched
**Edge Functions**, and the registry already carries SQL-only intra-DB jobs
(`jrd_retention_daily`, `client_errors_retention_daily`, `cron_call_log_cleanup_daily`) as
precedent.

---

## 6. Tests — including one the previous design made impossible

**The INVOKER redesign buys a real behavioural test in CI**, which v1 could not have had.
CI's `Supabase Integration Tests` job authenticates a real QA user against live prod
(`test.yml:388-392`: URL + anon key + test email/password, **no service-role key**). Under
v1's DEFINER-plus-revokes design that client could not call the function at all. Under
INVOKER-plus-grant it **can call it and must be refused by RLS** — so the security property,
the one that matters most, is directly assertable.

| Test | Kind | What it proves |
|---|---|---|
| **`test/edge_functions/usage_counters_rls_denies_client_test.dart`** | **behavioural, runs in CI against live prod** | the QA client `.rpc('consume_quota', …)` is refused with SQLSTATE `42501`. Fails if RLS is disabled, a permissive policy is added, or the function is switched to `SECURITY DEFINER` |
| `test/contracts/usage_counters_infrastructure_test.dart` | source-grep, comments stripped | the migration contains the CASCADE FK, `ENABLE ROW LEVEL SECURITY`, **no** `CREATE POLICY` on this table, `SECURITY INVOKER` (and **not** `SECURITY DEFINER`), the `p_limit = 0` guard, `VALUES (…, 1)`, `WHERE uc.used < p_limit`, and `RETURN -1` |
| same file, mirror assertions | source-grep | retention DELETE has **both** conjuncts; `quota_key`/`used` present, `meter`/`count` absent as column names |
| **live post-apply, recorded in the diagnose-doc** | manual, once | `relrowsecurity` true, 0 policies, the N/N+1 sequence, `'epoch'` survives retention, and **`anon` refused as well as `authenticated`** |

⚠ **The directory is load-bearing, not a detail — round-2 finding 2.** CI's `supabase-tests`
job is the ONLY one carrying live Supabase secrets, and it runs exactly
`flutter test test/supabase/` and `flutter test test/edge_functions/`
(`test.yml:441,465`) — nothing else. A file placed in `test/contracts/` (where its
source-grep sibling correctly belongs) would be picked up only by the credential-less
`analyze-and-unit-test` job, hit the repo-standard `SupabaseTestHelper.hasCredentials`
guard, and **skip forever while reading as green** — making this section's central claim
("runs in CI against live prod") silently false. Precedent for the placement:
`test/edge_functions/pgvector_test.dart`.

⚠ **Assert the SQLSTATE, not the HTTP status.** Verified live against the project's own anon
key: PostgREST returns **HTTP 401** (not 403) with body
`{"code":"42501", … "message":"new row violates row-level security policy…"}`. Assert
`PostgrestException.code == '42501'`. This is exactly the "asserting an error shape nobody has
observed" trap — the shape above was captured by a real request, not inferred.

⚠ **The happy path is still not CI-testable** — it needs service_role, which CI does not
have. Stated precisely, per round-1 finding D: that is a limitation of **this CI
architecture**, not a structural impossibility. An ephemeral Postgres service in CI would
allow it and is a legitimate future option; it is not proposed here because standing up
local-Postgres CI is its own project with its own blast radius.

Precedent for the mixed automated/manual shape:
`test/contracts/admin_metrics_functions_role_revoke_test.dart`, whose header says the same
thing about its own subject. The SoT entry therefore carries `presence_only: true` **for the
source-grep half only** — the RLS test is genuinely behavioural.

**Mutation plan (rule 21), each confirmed applied with `grep -c` before running:** switch
`SECURITY INVOKER` → `DEFINER`; drop `ENABLE ROW LEVEL SECURITY`; add a permissive policy;
delete the `p_limit = 0` guard; change `VALUES (…, 1)` → `(…, 0)`; delete
`WHERE uc.used < p_limit`; delete `RETURN -1`; drop the `<> 'epoch'` conjunct. Each must
redden ≥1 assertion; counts go in the diagnose-doc.

---

## 7. Ordering

**0. Classify the tier against the REAL file, with content, before anything else.** v1's
`platform` claim came from running the classifier on a path that did not exist. The content
rule (`SECURITY DEFINER` → catastrophic) can only fire on a file it can read, and a missing
file silently yields the path tier. **Write the migration, then classify it, then believe the
answer.** If it returns catastrophic, `hermes: accepted` is required and the slice plan
changes.

1. **Gate `check_usage_counter_source.dart` lands FIRST, warn-only** (§4.11). Baseline is
   **not 0**: the structural matcher returns 7 EF sites (5 quota + 2 legitimate
   `rolling-context` prune counts needing an allowlist) plus ≥5 SQL sites across
   026/028/101/111/113/114/120. **Re-derive both by running it; do not inherit them from this
   document.** Applied migrations are immutable, so the SQL allowlist enumerates those files
   permanently by name — the gate's real rule is "no NEW `count(*) FROM ai_coach_interactions`
   in a migration above 127".
2. **Founder authorization for the live apply — BEFORE the first commit attempt.**
   `test/contracts/applied_migrations_parity_test.dart` requires every migration to already
   appear in `backups/applied_migrations.json`, so it cannot be committed until applied.
   Sequencing this late cost a cycle on the food-text batch and on `usage-counter-race`.
3. Apply migration **128** (verified next; note `20260331000001_*.sql` begins with the digits
   "202" and defeats a naive numeric sort — CLAUDE.md §4.9).
4. Run the live checks (§4, §6); paste output into the diagnose-doc.
5. `backups/applied_migrations.json` **and** `backups/live_schema_columns.json` update in the
   SAME commit (§4.5 and the §7 pointer row — a new table adds columns).
6. Flip the gate to hard-fail.
7. `/code-review` B-pass, self-initiated, before the `--no-ff` merge (§4.3).

⚠ **Once applied, migration 128 is immutable — including its comments.** Get the wording right
before applying; a later comment fix invalidates the ledger hash and nothing detects it
(`supabase/migrations/CLAUDE.md`, added 2026-09-04 after exactly that).

---

## 8. What the remaining slices carry

Dispositions for every round-1 finding live in
`docs/plan-reviews/oi162-round1-findings.md`. Summary:

- **Slice 2 — the three cap triggers** (111 chat 10/day, 114 vision 20/day, 127 food-text
  10/200). Server-side only, no EF deploy. Must carry the IST bucket expression **verbatim**
  from 111/113 (finding 13; it is the fix for `7ad0d3`). ⚠ **Must re-verify the nested-EXECUTE
  behaviour on the real trigger** — blocker B showed the naive premise is false, and §4's
  grant is what makes it work; that must be demonstrated, not assumed a second time.
- **Slice 3 — the lifetime meters**: `ai-media-proxy` free-image, `weekly-report`, and the
  client twin `ai_coach_repository.dart:279`. Owns findings 2, 3, 4, 7 — consume-at-success
  vs consume-at-request, and the `:687` display re-count, are design questions to settle
  before a line is written. Needs the lifetime backfill, which is a floor and not a truth
  (pruned rows are unrecoverable).
  ✅ **Findings 2, 3 and 7 are now ON THE BOARD** under OI-153, not only in the review notes
  (round-2 finding 1). They were tracked solely in `docs/plan-reviews/oi162-round1-findings.md`,
  which `OPEN_INDEX.md` does not index and a future session has no reason to open — a §4.2
  deferral in substance regardless of what it was called. Finding 4 was already folded into
  OI-153; these three now sit beside it, in the OI that already owns this file territory.
- **Slice 4 — `delete-account` + `verify-payment`.** `catastrophic` by path glob ⇒
  `hermes: accepted` required (`check_plan_review_record_exists.dart:836`). Carries F1
  (`verify-payment:223` does not destructure `error`, so a PostgREST failure disables Razorpay
  brute-force protection) and the deletion of `delete-account`'s broken insert.
- **OI-153 owns** the dormant PRO image cap (finding 12) — activating a never-enforced cap is
  a product decision, already with the founder.

---

## 9. Open questions for round 2

1. **Retention window: 7 days.** Anything ≥ 2× the longest window (1 day) works. Better?
2. **Is `'epoch'` the right lifetime sentinel**, or should lifetime quotas use a nullable
   `window_start`? `'epoch'` keeps one table and one primary key at the cost of a magic value
   the retention predicate must know about; NULL would need a partial unique index instead of
   a plain PK.
3. **Should `consume_quota` also expose a read-only `peek_quota`?** Slice 3 will likely need
   one (a pre-flight gate that does not consume). Adding it now costs little; adding it later
   is another migration.
