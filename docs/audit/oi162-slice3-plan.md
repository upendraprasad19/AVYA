# OI-162 Slice 3 — the lifetime meters onto `usage_counters`

**Status:** v7 — **CONVERGED at round 7.** SPLIT under §4.12.1. Round 1 returned 1B/3M/4m; round 2 returned a NEW
blocking finding plus 4 major. Two consecutive rounds surfacing *new* material issues is the
rule's stated signal that the unit is too large: *"split it and ship the smallest converged
piece, don't review the large thing a fifth time."* Slice 2 took SIX rounds by not heeding it.

**This document is now SLICE 3a — `weekly-report` ONLY.** `ai-media-proxy` becomes slice 3b,
scoped in §9. No code written. Findings in §8.

⚠ **NO MIGRATION IS NEEDED — for 3a or 3b** (round-2 MAJOR 5). Verified live: `usage_counters`
`quota_key` is `text NOT NULL` with **zero CHECK constraints**, so a new key requires no DDL;
`usage_counters`/`consume_quota`/RLS/retention all exist from migration 128; and §1 already
established there is nothing to backfill. **Migration 130 and its live-apply authorization step
are deleted from this plan** — 130 stays free for slice 4 or a concurrent session. This slice is
Edge-Function-only.
**Predecessor:** slice 2 (`c7b95fe5`, CI green) moved the three cap TRIGGERS onto
`consume_quota()`. Those are Postgres triggers; this slice is the first to move **Edge Function**
readers, which is a different problem — see §2.
**Blast radius: `platform`** — COMPUTED, not estimated:
`dart run scripts/blast_radius_from_diff.dart supabase/functions/weekly-report/index.ts
scripts/usage_counter_source_lib.dart docs/sot_registry.yaml` → `platform`. So this slice needs a
plan-review record AND a B-pass, both of which it is getting.

⚠ v2 carried slice 2's line verbatim ("to be computed against the REAL migration file once
written") — stale twice over: this slice writes no migration, and it cited "§7 step 0" when step 0
lives in §6. Round-3 finding 2.

⚠ **And getting this number took three wrong attempts, which is worth recording here because the
tier gates the review depth.** `echo <path> | dart run … .dart` returns `feature` for EVERY path —
including `verify-payment`, which the registry pins `catastrophic` — because **stdin mode needs a
trailing `-`**; without it the script ignores the pipe and classifies whatever is STAGED. Use ARGS
mode for a path that is not staged, and sanity-check with a path whose tier you already know.

---

## 0. Scope — THREE readers, not four, and the fourth is deliberate

| Reader | Quota | Verdict |
|---|---|---|
| `ai-media-proxy:465,687` `countFreeImageAnalyses` | 5 LIFETIME free image analyses | **in scope** |
| `weekly-report:96` previous-report count | 1 LIFETIME free weekly report | **in scope** |
| `ai_coach_repository.dart:279` `getFreeImageAnalysisCount` | client twin of the first | **in scope** |
| `ai-media-proxy:96` `countProImageAnalysesToday` | 50/day PRO image cap | **NOT in scope — OI-153** |

⚠ **Why the PRO image cap is excluded, and why that is not a deferral.** It reads
`channel IN ('pro_image_analysis','image_analysis')` while the only writer stamps
`free_image_analysis` or `app` (`:665`). Reader and writer DISAGREE, so the cap has never fired.
Moving it onto the ledger would not be a refactor — **it would ACTIVATE a 50/day cap on PRO image
chat that has never once applied to a paying user.** That is a product change, it needs a founder
decision, and OI-153 already owns it with `Blocked on: enumerate every channel reader first`.
Pointing at a tracked, blocked item is a terminal disposition, not a punt (§4.2).

⚠ **The BOARD currently says OI-153 owns the free-image LIFETIME fix too, and that must be
reconciled IN THIS BATCH** (round-1 MAJOR 3). `open_issues.md:2696` carries a subsection *"Folded
in 2026-09-03 from OI-162 — the FREE-IMAGE LIFETIME QUOTA resets itself"*, so an auditor reading
`OPEN_INDEX.md` first — which root CLAUDE.md §7 tells every session to do — concludes OI-153 owns
AND BLOCKS this exact work.

⚠ **v2 claimed this was "already argued in `oi162-plan.md:290-303` (§9) and simply never written
to the board". That citation is FALSE** (round-2 MAJOR 4). Verified:
`sed -n '288,304p' docs/audit/oi162-plan.md | grep -ciE "free_image|weekly_report"` → **0**. §9 is
about the 7 unfiltered consumers of `ai_coach_interactions`; it never mentions either quota. And
the board cuts the other way — `open_issues.md:2773` says OI-153 *"already owns `ai-media-proxy` +
`weekly-report` quota territory."*

**So this is a NEW decision this plan is making, not a rebuttal being recovered.** Stated that way
so nobody hunts for a prior argument that does not exist.

The decision, and its evidence: OI-153's blocker is *channel enumeration*, which binds because
OI-153's CODE-1 fix MINTS a new `channel` value — and `channel` IS enumerated in at least three
places (`rolling-context`'s denylist, `coach_interaction_repository.dart:282`'s
`_coachChatChannels`, `founder_metrics_engagement()`). This slice mints no `channel`; it adds a
`quota_key`, and **a repo-wide grep finds no enumeration or allowlist of `quota_key` anywhere**
outside slice 1/2's own migrations and tests. So the blocker's specific rationale does not reach
this work.

**Clean split, to be recorded on the board in this batch:** OI-153 keeps the CHANNEL work (the
PRO cap, CODE-1/CODE-2); OI-162 slice 3 takes the LEDGER work (the lifetime reset) **and the
fail-open**, which OI-153's own subsection says must ship with it.

**The other three are the opposite case: writer and reader AGREE.** Verified by reading both
ends, not inferred — `ai-media-proxy:665` writes `free_image_analysis` and `:76` reads it;
`weekly-report:592` writes `weekly_report` (the audit's CODE-8 calls it "the SOLE writer") and
`:96` reads it.

---

## 1. Live state, and one fact that changes how this must be tested

Full channel census, 2026-09-06:

| channel | rows | users |
|---|---|---|
| `in_app_orphan` | 58 | 8 |
| `app_event` | 32 | 4 |
| `food_text_analysis` | 25 | 5 |
| `app` | 8 | 5 |
| `in_app` | 7 | 7 |
| `promotion_ceremony` | 5 | 5 |
| `scan_meal` | 1 | 1 |

**All four slice-3 channels have ZERO rows.** So does `summarized` — **0 across every channel**,
meaning `rolling-context` has never pruned anything yet (its threshold is 50 non-`app_event` rows
per user; the busiest channel averages ~7).

⚠ **This distinction is load-bearing and I nearly skipped it.** Zero rows could mean *pruned away*
(the bug, live) or *never used* (feature unexercised). The `summarized = 0` column settles it:
**never used.** Consequences:

- The backfill slice 2 needed is **unnecessary here** — there is nothing to seed. State that
  rather than copying slice 2's pattern reflexively.
- **No live data will exercise these paths**, so every behavioural assertion must construct its
  own state. Unlike slice 2, "watch the real counter move" is not available.
- These meters are **correct but dormant**. That is materially different from OI-153's case
  (reader/writer disagree) and the difference should not be blurred.

---

## 2. The design crux: `consume_quota` INCREMENTS, and this path counts TWICE

Today's free-image flow:

```
:465   usedSoFar = countFreeImageAnalyses(...)     ← GATE, before paying for Gemini
:466   if (usedSoFar >= 5) refuse                  ← 402/429
       ... Gemini call ...
:669   insert({channel: 'free_image_analysis'})    ← the row IS the quota unit
:687   freeImageUsed = countFreeImageAnalyses(...) ← RE-COUNT, for the displayed remaining
```

Two `count` calls per request. Both are READS, and a row is written between them — so today the
quota is consumed **at success**, never on a failed Gemini call.

⚠ **Replacing both calls with `consume_quota` would consume TWICE per request** — once at the
gate and once for the display. `consume_quota` has no peek: its only operation increments and
returns the new value. This is the single most likely way to get this slice wrong, and it would
be invisible in any test that makes one request and asserts "the counter went up".

**Proposed shape:**

- `:465` gate → a plain `SELECT used FROM usage_counters` (advisory read, no increment), and it
  must **fail CLOSED** (see below).

⚠ **This DIVERGES from the parent plan and the divergence is deliberate** (round-1 minor 6).
`oi162-plan.md:201` reads as `countFreeImageAnalyses → consume_quota(...)`, i.e. consuming AT THE
GATE — closer to option 3 below. This slice consumes only at the post-Gemini write and leaves the
gate an advisory read, because consuming at the gate burns LIFETIME quota on a Gemini outage with
no refund path. Flagged as a decision rather than left as silent drift.
- `:669` → **the `ai_coach_interactions` insert STAYS, VERBATIM AND UNCONDITIONAL.**
  `consume_quota(...)` is an **ADDITIONAL, separate statement** beside it — never a replacement.
- `:687` display → reuse the value `consume_quota` RETURNED (`RETURNING uc.used`, migration
  128:69-113). The second query disappears entirely rather than becoming a second read.

⚠ **v1 said "`consume_quota` replaces the insert-as-quota-unit" and that wording is a data-loss
instruction** (round-1 BLOCKING). I meant "the row stops BEING the quota unit"; an implementer
reading it would delete the insert. Two independent things break if they do, both verified:

1. **Restore has NO channel filter.** `sync_coach.dart:178-181` is
   `.from('ai_coach_interactions').select().eq('user_id', …).gte('created_at', since)` — it pulls
   back every channel. No row means nothing to restore on a reinstall: a
   `restore_completeness` regression.
2. **For `weekly-report`, the row is the ONLY persisted copy of the report text.**
   `reports_screen.dart:47` caches a single latest report (`weekly_report_cache`), not a list,
   and no other table stores `report.summary`. Deleting that insert destroys every future
   report's content server-side.

This also keeps the slice consistent with its parent plan, `oi162-plan.md:195`:
*"`ai_coach_interactions` keeps receiving conversation rows exactly as today."*

⚠ **ORDER: insert FIRST, `consume_quota` SECOND** (round-2 MAJOR 2). They are two independent
PostgREST calls from Deno with **no transaction spanning them**, and the two orderings are not
equally harmful:

- consume-then-insert-fails → the lifetime unit is charged but the row is missing. That is the
  SAME harm the blocking finding above exists to prevent, reached by a different path.
- insert-then-consume-fails → the ledger under-counts. Recoverable, and the user keeps what they
  paid for.

So: insert, then consume.

⚠ **PRO MUST NOT CONSUME — and v2 never said so** (round-3 finding 6). `weekly-report:118` is
`if (!hasPro && !isFirstReport) return 403`: PRO is **never** refused, so `weekly_report_free`
(limit 1) is a FREE-tier gate only. And `reports_screen.dart:65` fires
`_generateReport(silent: true)` on **every screen open**. Consume unconditionally and a PRO user
burns the key on their first visit, then gets `-1` on every subsequent one — forever.

**This is the SAME asymmetry slice 2 documented for chat** (`enforce_chat_app_daily_limit` returns
before consuming when `is_pro`), and I failed to carry it across. Gate the consume on `!hasPro`,
and record the same consequence slice 2 records: the ledger freezes while PRO, so a same-day
downgrade resumes from the pre-upgrade value.

⚠ **`-1` IS NOT AN ERROR.** `consume_quota` returns `-1` on exhaustion with **no `error` field**
(migration 128:107-109) — a successful RPC. So log a distinct `console.error` ONLY on a genuine
`{error}` from the call; treat `data === -1` as the expected refusal path. Logging `-1` as a
failure would flood production with false alarms on ordinary free-tier second attempts and drown
the real under-counts this logging exists to surface.

**Also in scope, and NOT optional — the fail-OPEN gate** (round-1 MAJOR 2). `:77-81` is
`if (error) return 0;` … `catch (_) { return 0; }`, with a docstring arguing fail-open is safer
"because 0 < 5" — which is precisely when the gate does NOT fire. A DB hiccup currently grants
unlimited free image analyses. **Two independent sources require it ship with the lifetime fix**:
`oi162-plan.md:201` ("R1 … **Fail CLOSED** (fixes F2)") and OI-153's folded-in subsection
("Both must be fixed together"). `weekly-report:100-115` is ALREADY fail-closed, so this is
specifically the `ai-media-proxy` gap. The new advisory SELECT must fail CLOSED — an unreadable
counter refuses, it does not grant.

⚠ **AN ABSENT ROW IS NOT AN UNREADABLE ONE — and conflating them locks out EVERY free user**
(round-6 MAJOR 1, and it is MY OWN earlier fix that created it).

Today's `:93-98` is `count: "exact", head: true`. A count query has no absent-row state: zero
matching rows returns `count: 0, error: null`, unambiguously. **The value-select this slice
introduces creates a third state that did not exist before** — `data: null, error: null`, the
successful read of a row that is not there. Every user is in exactly that state at cutover:
`usage_counters` holds ZERO rows for `weekly_report_free` today.

The fail-closed rule below was written for the ERROR branch. Read carelessly it swallows the
absent branch too, and then `isFirstReport` is never `true` and **every first-time free user is
refused their one free report, permanently.** Not an edge case — the universal cold-start.

**So, explicitly:**
- Use **`.maybeSingle()`**, never `.single()`. ⚠ This file offers BOTH precedents — `.single()`
  at `:163` and `:174`, `.maybeSingle()` at `:83`, `:381`, `:580` — and `.single()` THROWS
  PGRST116 on zero rows, which would arrive as an error and trigger exactly the refusal above.
- **An absent row is a legitimate `used = 0` and must be GRANTED.**
- **Only a populated `error` field fails closed.**

⚠ **This is the guard-without-its-mirror class, and the mirror was created by my own remediation.**
Round 3 said "fail CLOSED" was asserted rather than specified; I specified it forcefully — and
never asked what the newly-possible absent-row state meant under the rule I had just tightened.
Hardening one branch changed what the other branch means.

⚠ **Stated as control flow, not as a property** (round-2 MINOR 7) — v2 asserted the outcome, and
round 1's blocking finding was caused by exactly that kind of vagueness. Copy the shape
`weekly-report:100-115` already uses: on error, force the variable to the value that takes the
REFUSAL branch (there, `isFirstReport = false`) and log distinctly. For `ai-media-proxy`'s new
read that means an unreadable counter yields a used-count that fails `>= LIMIT`, never `0`.

That removes a round-trip and the double-consume in one move.

### The question the ×2 review must settle

The gate at `:465` is advisory, so a request can pass it and then have `consume_quota` return
`-1` at `:669` — **after Gemini has already been paid for.** Three options, none obviously right:

1. **Return the analysis, do not count it.** The user gets what they paid nothing for; the cap
   leaks by at most the concurrency window.
2. **Refuse after the fact** (402). Honest to the cap, wastes the Gemini spend, and shows the
   user a refusal *after* a visible delay.
3. **Consume at the GATE instead**, refunding on failure. Atomic and exact, but inverts today's
   semantics: a Gemini outage would burn lifetime quota, and "lifetime" makes that unrecoverable
   without a manual refund path.

Today's behaviour is closest to (1) — but state it precisely (round-1 minor 5): today's write is
**unconditional and never fails**, which is not the same as "lenient". **I lean (1), preserving
current semantics**, but this is a real product-visible choice on a LIFETIME quota and should not
be settled by whoever writes the migration.

⚠ **This is ONE decision covering BOTH sites, not a per-file choice.** `weekly-report` has the
identical write-after-Gemini shape (Gemini at `:513-521`, write at `:587-599`), so whatever is
decided applies there too. v1 framed it as an `ai-media-proxy` question.

---

## 3. Quota keys and the lifetime window

Two new keys, both LIFETIME, so both use the `'epoch'` sentinel `window_start` slice 1 defined:

| quota_key | limit | window |
|---|---|---|
| `free_image_analysis` | 5 | `'epoch'` (lifetime) |
| `weekly_report_free` | 1 | `'epoch'` (lifetime) |

⚠ **These names DIVERGE from the parent plan and the divergence is now flagged** (round-3 finding
8). `oi162-plan.md:201,205` proposes `'free_image'` (R1, `:201`) / `'weekly_report'` (R5, `:205`); this slice uses
`free_image_analysis` / `weekly_report_free`. No live dependency exists on either — no row carries
these keys yet and `quota_key` has no CHECK constraint — so the cost of choosing is zero today and
non-zero the moment a row lands. `weekly_report_free` is preferred because it names the FREE gate
specifically, which is what the key actually meters now that PRO is exempt. Every other deliberate
divergence in this document is flagged; this one was not, until now.

⚠ **`cleanup_usage_counters` must never touch these.** Its predicate is two-sided —
`window_start <> 'epoch' AND window_start < now() - 7 days` — and slice 1's SoT entry already
flags that dropping the epoch conjunct "recreates the original bug inside the new table". A
lifetime row deleted by retention is the exact failure this whole OI exists to fix, so the
contract test must pin it explicitly rather than trusting the migration text.

⚠ **`ai-media-proxy` will hold TWO quotas and must use TWO keys** — slice 1's SoT entry says so
by name. The PRO cap is out of scope here, but when OI-153 activates it, it takes its own key.

---

## 5. Tests — `weekly-report` ONLY

⚠ v2's table said "both EFs call `consume_quota`" and described a 5-consume ceiling — that is
`ai-media-proxy`'s cap, and "both EFs" cannot be asserted if 3a ships alone (round-3 finding 4).
3a's tests must not depend on 3b landing.

| Test | Kind | Proves |
|---|---|---|
| `test/contracts/weekly_report_lifetime_meter_test.dart` | source-grep, comments stripped | `weekly-report` calls `consume_quota` with `'weekly_report_free'` and `'epoch'`; the `:93-98` read targets `usage_counters`, not `ai_coach_interactions`; the `ai_coach_interactions` insert at `:587-599` is still present and unconditional; the consume is gated on `!hasPro`; the advisory read fails CLOSED |
| same file — **the insert PRECEDES the consume** | source-grep | in the comment-stripped source, the index of the insert's `channel: "weekly_report"` is LESS than the index of `consume_quota(`. ⚠ Source position is a valid proxy for execution order here, verified: `grep -c "Promise.all" weekly-report/index.ts` → **0**, so every query in the file is a sequential `await` |
| same file — **absent-row is granted** | source-grep + live | the advisory read uses `.maybeSingle()` and NOT `.single()`; an absent row yields `used = 0` and takes the GRANT path; only a populated `error` fails closed. ⚠ The source-grep half cannot see runtime behaviour and the existing live harness calls `consume_quota` directly, **bypassing the EF's own read** — so this needs an assertion that exercises the read path itself, on a synthetic user with no row. ⚠ **Mechanism, named rather than left to guess** (round-7 finding 3): this function calls `supabase.auth.getUser(token)` at `:53`, so a branch deploy alone is insufficient — it needs a REAL authenticated session. Reuse the precedent already cited for the mutation method (`docs/superpowers/plans/2026-04-18-ai-coach-coach-memory-personalization.md`): point a dev build at the branch, sign in as a synthetic user, trigger through the app |
| same file — **the allowlist ratchet** | source-grep | `allowedEdgeFunctionSites['supabase/functions/weekly-report/index.ts'] == 0`. ⚠ Verified safe by round 3: weekly-report's one unrelated `ai_coach_interactions` read (`promotion_ceremony` tone selection, `:374-381`) uses a plain `.select("id")` with no `count: "exact"`, so it does NOT trip the matcher. A 0 is achievable and is what converts the gate from permissive to proof-of-landing |
| extend `test/sql/oi46_daily_cap_triggers_live_verify.sql` | live, `BEGIN…ROLLBACK` | **limit 1, not 5**: ONE consume of `weekly_report_free` succeeds and the SECOND returns `-1`; the `'epoch'` row survives `cleanup_usage_counters()`; a synthetic PRO user consumes nothing |

⚠ **Run every new assertion against the code it REPLACES** (root CLAUDE.md §4.9). The starting
state here is zero rows for BOTH implementations, so a "counter did not move" assertion passes
against either — the same vacuity that made 2 of slice 2's 7 assertions worthless. Each assertion
must require a REAL row to exist first.

⚠ **Do not spend the shared QA account** (OI-164). This is a LIFETIME quota: one test consuming
it exhausts it permanently for every future run. Synthetic users, rolled-back transactions.

### Mutation plan (rule 21)

⚠ **v3 DROPPED this and §8 still claimed it FIXED** (round-4 finding 2). The four mutations round
1 demanded were written for `ai-media-proxy`, and rewriting §5 weekly-report-only deleted them
without carrying anything across — a rewrite that REPLACED instead of preserving. Exactly the
shape slice 2's round 3 caught. Restored here, scaled to this slice's simpler surface:

| Mutation | Assertion that must redden |
|---|---|
| Remove the `!hasPro` gate on the consume | "the consume is gated on `!hasPro`" |
| Flip the advisory read's error branch to fail OPEN | "the advisory read fails CLOSED" |
| Delete or make conditional the `ai_coach_interactions` insert | "the insert is present and unconditional" — re-tests round 1's own BLOCKING finding |
| Point the advisory read back at `ai_coach_interactions` / `channel` | "the read targets `usage_counters`" |
| In the live SQL harness, raise the limit past 1, or bypass the PRO skip | the corresponding `slice3a_*` live assertions |
| **Typo the quota_key** — `'weekly_report'` for `'weekly_report_free'` | "calls `consume_quota` with `'weekly_report_free'`" |
| **Replace `'epoch'` with a real timestamp** | "and `'epoch'`" — the SOURCE-GREP half only. ⚠ Round-6 finding 2: v5 also paired this with the live "survives `cleanup_usage_counters()`" assertion, and that pairing is UNEARNED — the predicate is `window_start <> 'epoch' AND window_start < now() - interval '7 days'`, so a row stamped `now()` is as fresh as an epoch row and survives an immediate cleanup identically. The live half only reddens if the mutated row is ALSO backdated past 7 days. Either backdate it or claim only the source-grep half; claiming both would cost a wasted Supabase-branch cycle to discover |
| **Restore the old `count: "exact"` + channel-eq pattern** to `weekly-report` | the allowlist-ratchet assertion — proves the 0 actually fires rather than being sound-by-reading |
| **Conflate absent-row with error** — make the advisory read treat `data: null, error: null` as a refusal | "a first-time user with NO row is GRANTED, not refused" (round-6 MAJOR 1). ⚠ Without this the total-free-tier-lockout failure has no test behind it at all |
| **Swap the insert and `consume_quota` blocks** | "the insert PRECEDES the consume" (round-7 finding 1). ⚠ Nine mutations pinned presence, gating and target; **none pinned ORDER** — yet round 2 established the reversed order is the WORSE failure (consume-then-insert-fails permanently burns a LIFETIME unit *and* loses the row). Every other assertion stays green on a swap |

⚠ **The last three were MISSING from v4 and their absence was the sharpest gap round 5 found.**
The quota-key literal is **the single most important string in this slice**: OI-153's headline
bug IS a key/channel mismatch, this entire OI exists because a quota read and its writer drifted
apart, and the one assertion that would catch a typo'd `weekly_report_free` had no mutation
behind it. Rule 21 is explicit that soundness-by-reading is what mutation exists to replace —
`usage_counter_source_lib.dart`'s ratchet being "mechanically sound on inspection" is precisely
the claim that needs a red run, not a careful read.

Each confirmed APPLIED by an anchor grep BEFORE its run, and each must leave the TypeScript
compiling — **a `deno check` failure is not a mutation proof** (rule 21), and there is no local
Deno, so keep every mutation semantically-wrong-but-valid by inspection.

**Executed on a Supabase BRANCH, never prod** — round 3 verified this is feasible:
`deploy_edge_function` accepts an arbitrary `project_id`, `create_branch` returns its own
`project_ref`, and there is merged precedent
(`docs/superpowers/plans/2026-04-18-ai-coach-coach-memory-personalization.md` step 4 deployed
`daily-snapshot` to a branch). A LIFETIME quota burned by a mutation run against prod **cannot be
undone by a day rolling over**, which is why this is not the place to economise.

## 6. Ordering

0. **No migration.** `quota_key` is unconstrained `text`; `usage_counters`/`consume_quota`/RLS/
   retention all exist from 128; nothing to backfill. **Migration 130 is NOT reserved by this
   slice** — it stays free for slice 4 or a concurrent session.
   ⚠ Round-3 BLOCKING: v2 still listed "write migration 130 / request live-apply authorization"
   here, contradicting its own preamble. An implementer following §6 literally would have written
   an unneeded migration and asked for an unneeded prod authorization.
1. `weekly-report/index.ts`: the advisory fail-closed read at `:93-98`, the PRO exemption, and the
   `consume_quota` call after the existing insert at `:587-599`.
2. `scripts/usage_counter_source_lib.dart`: drop
   `allowedEdgeFunctionSites['supabase/functions/weekly-report/index.ts']` to **0**.
2b. ⚠ **REPOINT the pre-existing SoT-registered test that this redesign breaks** (round-4
   finding 1). `docs/sot_registry.yaml:10068` registers concept `weekly_report_pro_gate` with
   `behavioral_test_path: test/contracts/weekly_report_pro_gate_writer_to_reader_test.dart`, and
   that test pins the CURRENT reader shape — `:49` asserts
   `RegExp(r'count:\s*previousReportCount\s*,\s*error:\s*\w+')`, and another assertion pins
   `.eq("channel","weekly_report")`. Replacing `:93-98` with a `usage_counters` read reddens **at
   least these two — and probably a third** (round-5 finding 1): test 2 at `:58` asserts
   `RegExp(r'isFirstReport\s*=\s*previousReportError\s*\?\s*false')`, and after the redesign
   there is no "previous report" being counted, so an implementer has no reason to keep the name
   `previousReportError`. Verify that ternary once the real read shape exists rather than assuming
   it survives. Repo-wide grep confirms this ONE file is the whole blast radius — the undercount
   is within it, not a second file.
   Update the SoT entry's `readers:` / `line_range:` / `description`, and **REPOINT the
   assertions at the new shape — never delete or loosen them** (root CLAUDE.md §4.9: the
   assertion is still true, it just moved). The writer-side assertion stays green untouched,
   which is itself evidence the insert-stays decision is right.
   ⚠ **Third instance of this class in this OI**, and I have the §4.9 row that prescribes the
   one-line preventative: `grep -rn "<what is moving>" test/` BEFORE landing any move. Not run
   here, again.
3. **Mutation proofs (§5) on a Supabase BRANCH, then the B-pass** — BEFORE any prod deploy.
   ⚠ **Reordered from v4** (round-5 finding 4). v4 deployed at step 3 and reviewed at step 5,
   copying slice 1's ordering — but slice 1 justified that by migration 128 being behaviourally
   INERT ("NOTHING CALLS IT YET", its own header). **This deploy is not inert**: it changes what
   a live free-tier user experiences the moment it lands. An asymmetry that is fine for inert
   infrastructure is not fine for a live gate, and copying the shape without re-checking the
   justification is how a precedent stops being one.
4. **Deploy `weekly-report` — ONE function, and it needs its own explicit founder go.**
   (`ai-media-proxy` is slice 3b and is not deployed here.)
5. SoT registry; `supabase/functions/CLAUDE.md`; **and the OI-153 board reconciliation, named
   subsection by subsection** (round-3 finding 7 — v2 said only "record that the ledger half
   moved", which is not actionable against a board carrying several):
   - `:2723` *"ALSO 2026-09-03 — the WEEKLY-REPORT first-free gate is a lifetime count and resets
     the same way"* → **CLOSES with 3a.** This is exactly 3a's subject.
   - `:2696` *"Folded in 2026-09-03 from OI-162 — the FREE-IMAGE LIFETIME QUOTA resets itself"* →
     **stays open, closes with 3b.**
   - `:2743` *"ALSO folded in — the nightly summarizer RESETS two paid-tier daily caps"* →
     **STALE, not open** (round-5 finding 3, live-verified). ⚠ v4 said "stays open; it is about
     the PRO daily caps, which remain OI-153's channel work" — **wrong twice.** Its premise is
     that those caps are resettable because they count `ai_coach_interactions` rows that
     `rolling-context` prunes. Slice 2's migration 129 already made that structurally impossible:
     `pg_get_functiondef` on all three trigger functions shows they read `usage_counters`
     EXCLUSIVELY, and `rolling-context` never touches that table. (The 4 `ai_coach_interactions`
     mentions left in migration 129 are its one-time backfill INSERTs, not trigger bodies.) It is
     also not "channel work" by this document's own §0 vocabulary — channel work is the
     reader/writer string mismatch; this was ledger-reset work, and it is done.
     **Annotate it superseded by `c7b95fe5`**, but leave its *"THREE DEFECTS MOVED HERE
     2026-09-04"* sub-list open — those are separate and mostly 3b-scoped.
   - OI-153's own headline (the PRO cap reading a channel nothing writes) → **untouched.**
   - **OI-162's own entry** (`:2993`) takes a parallel `PROGRESS` note, matching the precedent
     slice 2 set. Round-4 finding 5 — v3 listed only the OI-153 work.
   ⚠ Read the board at merge time rather than trusting these line numbers — the other session is
   editing the same file today, and a line anchor is the first thing a concurrent edit rots.
6. Plan-review record; merge. (Mutation proofs and the B-pass ran at step 3.)

---

## 7. Open questions for review

1. **The post-Gemini refusal** (§2) — options 1/2/3. I lean 1, and round 4 supplied real
   evidence for weekly-report specifically that was previously only intuition:
   - **PRO is never exposed at all** — it does not call `consume_quota` (§2), so no option
     affects a paying user.
   - **A free user's SECOND sequential request is refused at the gate**, before Gemini: the
     advisory read sees `used=1`. So the only reachable race is **two SIMULTANEOUS first-ever
     requests** — which is plausible rather than adversarial, because
     `reports_screen.dart:64-66` fires `_generateReport(silent: true)` on every `initState`, so a
     remount or backgrounding can produce genuine concurrency.
   - **Option 1's total downside is therefore bounded at ONE extra free Gemini 2.5 Pro report,
     once, ever, per user.** That is materially different from `ai-media-proxy`, where a 5/lifetime
     cap on a far more frequently-called path lets the same race recur.
   **SETTLED FOR 3a** (round-7 finding 2): §6 step 1 adds no refusal branch, so `consume_quota`'s
   return — positive, `-1`, or error — never alters the response. An implementer building from §6
   produces option 1 whether or not they read §7, so labelling it "open" here was a §6-vs-§7
   contradiction of exactly the shape round 3 caught between §9 and §7. **It stays open only for
   3b**, where `ai-media-proxy`'s far more frequent path means the same race recurs rather than
   being a once-ever event.
2. ~~**The client twin's read path**~~ — **MOVED TO 3b (§9)** along with the section it referenced.
   `weekly-report` has no client twin, so this is not 3a's question. (Round-3 finding 9.)
3. ~~**Does `weekly-report` have the same double-count shape?**~~ **ANSWERED — NO** (round 1 read
   all 643 lines): exactly ONE count read (`:93-98`, feeding `isFirstReport` at `:113`) and ONE
   un-rechecked write (`:587-599`). No second query anywhere in the file. So the `:687`-style
   collapse applies to `ai-media-proxy` only.

⚠ **But "just gains a `consume_quota` call beside its existing insert" — v2's whole description
of this file — was a BLOCKING omission** (round-2 finding 1). It describes the WRITE and says
nothing about the READ, and the read is the gate:

```
:93-98   count("exact") … .eq("channel","weekly_report")   ← the quota READ
:113     isFirstReport = (count === 0)
:118     if (!hasPro && !isFirstReport) return 403          ← the actual refusal
```

An implementer following v2 literally would increment `usage_counters` while `:118` kept deciding
from `ai_coach_interactions` — **the ledger moves and nothing reads it, so the headline bug stays
live and the slice ships claiming it fixed.** That is writer/reader drift inside a plan whose
subject is writer/reader drift.

**`:93-98` becomes an advisory `SELECT used FROM usage_counters WHERE quota_key =
'weekly_report_free'`, fail-closed**, exactly like `ai-media-proxy`'s `:465`.

⚠ **And the existing gate would NOT have caught it.** `usage_counter_source_lib.dart:229` is
`else if (count > allowed)` — a CEILING, not a ratchet. An untouched `weekly-report` still reads
as exactly its allowlisted 1 site and PASSES. **So this slice must drop
`allowedEdgeFunctionSites['supabase/functions/weekly-report/index.ts']` to 0 in the same commit**,
which converts the gate from permissive to proof-of-landing.

---

## 8. Round-1 findings of record

Written down because a disposition table that lives only in conversation cannot be checked by
round 2. One BLOCKING, three MAJOR, four MINOR; **zero false alarms** — I verified the four
decisive ones against the files myself before acting.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | **BLOCKING** | v1's "`consume_quota` **replaces** the insert-as-quota-unit" is a data-loss instruction. `sync_coach.dart:178-181` restores with NO channel filter, and `reports_screen.dart:47` caches only ONE latest report — so deleting the insert breaks restore AND destroys the only server-side copy of every weekly report | **FIXED** — §2 now says the insert STAYS verbatim and unconditional; `consume_quota` is ADDITIVE. Both consequences verified by reading the files |
| 2 | MAJOR | `countFreeImageAnalyses` is fail-OPEN (`if (error) return 0`, `catch → 0`), and two independent sources require it ship with the lifetime fix. v1 was silent | **FIXED** — §2 puts it in scope; the new advisory SELECT must fail CLOSED |
| 3 | MAJOR | The board says OI-153 owns AND blocks this exact work; `oi162-plan.md` §9 rebuts the blocker but the board was never updated | **FIXED** — §0 records the split (channel work stays OI-153, ledger work moves here) and §6 step 4 makes the board edit part of the batch |
| 4 | MAJOR | §5's Edge-Function mutation row said "see below" and listed only traps, no method | **FIXED** — four concrete mutations, each with its anchor check and the compile-error caveat |
| 5 | MINOR | The post-Gemini decision was framed per-file; `weekly-report` has the identical shape | **FIXED** — stated as ONE decision covering both sites |
| 6 | MINOR | Undocumented divergence from `oi162-plan.md:201`, which consumes at the GATE | **FIXED** — §2 flags it as a deliberate decision with its reason |
| 7 | MINOR | RLS imprecision: a `SELECT` as `authenticated` returns EMPTY, not `42501`; and the grants already exist, so an RLS policy needs no `GRANT` | **FIXED** — §4 corrected; the option is cheaper than v1 implied |
| 8 | MINOR | `getFreeImageAnalysisCount` has ZERO callers — the client twin is dead code, not a live display path | **FIXED** — §4 corrected; still must not ship broken |

**Round 1 also ANSWERED open question 3** (weekly-report has no double-count — all 643 lines
read) and confirmed clean: the `:465/:669/:687` trace and line numbers, `consume_quota`'s
`RETURNING uc.used`, the live census and the never-used-not-pruned inference, `rolling-context`'s
threshold and denylist, migration 130 free in both schemes, the `'epoch'` sentinel surviving
`cleanup_usage_counters` **by execution in a rolled-back transaction**, and that the two
`ai-media-proxy` caps sit on mutually exclusive `isPro` branches so the partial migration creates
no half-migrated risk.


---

## 9. Slice 3b — `ai-media-proxy`, split out under §4.12.1

**Not dropped, not deferred — scoped here so it is durable, and it starts the moment 3a lands.**
§4.12.1's instruction on a repeated new-material signal is "ship the smallest converged piece",
and `weekly-report` is that piece: ONE read, ONE write, already fail-closed, no `:687` collapse,
no client twin, no board reconciliation. `ai-media-proxy` carries all of those at once, which is
why two rounds kept finding new things in it.

**3a settles the shared design decisions on the simpler surface; 3b inherits them:**
the insert-then-consume ordering, the PRO-does-not-consume rule, fail-closed as control flow, the
advisory-read-plus-authoritative-consume shape, and the branch-based mutation method.

⚠ **The post-Gemini refusal is deliberately NOT on that list** (round-3 finding 5). v2 claimed it
as settled by 3a while §7 still listed it as an open question and §2 said it "should not be
settled by whoever writes the migration" — a three-way contradiction. It stays OPEN, and it is
answerable on 3a's own surface: `weekly-report` has the identical write-after-Gemini shape, so
whichever option is chosen here binds 3b.

### 3b's scope, already established by rounds 1-2 and carried forward verbatim

- **The `:687` double-consume collapse** — gate at `:465` becomes an advisory read; the insert at
  `:669` stays verbatim; `consume_quota`'s return value replaces the `:687` re-count entirely.
- **The fail-OPEN fix** — `:77-81` (`if (error) return 0`, `catch → 0`) is the live defect; two
  independent sources require it ship with the lifetime fix, and `weekly-report` is already
  fail-closed so this gap is `ai-media-proxy`-only.
- **The dead client twin** — `getFreeImageAnalysisCount` has ZERO callers; a correctness question,
  not a live display path. The response-field option needs no new DB surface. ⚠ Round-3 finding 9:
  this was sitting in 3a's main body as "§4. The client twin" AND duplicated here. It is
  `ai-media-proxy`-only (weekly-report has no client twin — `reports_screen.dart` shows no
  remaining-count and makes no per-count fetch), so it lives here alone now. Full detail:

  `ai_coach_repository.dart:279` `getFreeImageAnalysisCount` counts the same channel from the
  client, read-only, for display. It must read `usage_counters`, not `ai_coach_interactions`.

  ⚠ **It has ZERO callers today** (round-1 minor 8): `grep -rn getFreeImageAnalysisCount lib/`
  returns 1 line — its own definition. The "X of 5 left" copy is baked server-side into the reply
  (`ai-media-proxy:692`) and the raw response fields (`:701-705`); the client never queries this
  separately. So this is a **dead-code correctness question, not a live display-path risk**. v1
  overstated the stakes; it still must not ship broken.

  ⚠ **RLS blocks the obvious implementation, but be precise about how** (round-1 minor 7). A
  `SELECT` as `authenticated` returns **EMPTY, not an error** — only the WRITE path throws `42501`.
  Slice 1's "authenticated and anon both refused 42501" is accurate for writes only, and the SoT
  entry inherits that imprecision. Also verified: `anon`/`authenticated`/`service_role` ALREADY
  hold full INSERT/SELECT/UPDATE/DELETE on `usage_counters` via this project's schema-wide default
  privileges — **RLS-with-no-policy is the sole guard and there is no GRANT gap**, which makes the
  RLS-policy option a bare `CREATE POLICY` with no accompanying `GRANT`. Cheaper than v1 implied. Options for the
  review: a `SECURITY DEFINER` read-only RPC (⚠ forces the **catastrophic** tier via the content
  rule, and re-opens the escalation surface slice 1 deliberately avoided); returning the count in
  the `ai-media-proxy` response the client already receives; or a narrow RLS SELECT policy scoped
  to `auth.uid()`.

  **I lean on the response-field option** — it needs no new database surface, and the client only
  ever displays this number immediately after a request that already returns.

  ---
- **The OI-153 board reconciliation** — record the channel/ledger split (§0). ⚠ This is a NEW
  decision, not a recovered rebuttal; v2's citation for it was false.
- **NOT the PRO 50/day image cap** — reader and writer disagree, so migrating it would ACTIVATE a
  cap that has never fired. Stays with OI-153 as a product decision.
- **No migration** — same reasoning as 3a: `quota_key` is unconstrained `text`.

**Remaining after 3a + 3b:** the two catastrophic-tier rate limits in `delete-account` and
`verify-payment` (slice 4, `hermes: accepted` required).

---

## 10. Round-3 findings of record

Round 3 reviewed the SPLIT. Its diagnosis was precise and worth stating in its own words: the
**design** sections (§0-§3, §7) were genuinely re-scoped and their citations verified, while the
**execution** sections an implementer follows mechanically — §5 Tests, §6 Ordering, the
blast-radius line — still carried combined-slice or stale-slice-2 content. **I edited what I was
thinking about, not what someone else would follow.** That is the transferable lesson from this
round, and it is a different failure from rounds 1-2 (which found design defects).

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | **BLOCKING** | §6 still said "write migration 130 / request live-apply authorization", contradicting the preamble's own "no migration needed" | **FIXED** — §6 step 0 now states no migration and releases 130 |
| 2 | MAJOR | The blast-radius line was slice 2's verbatim, cited a §7 step that lives in §6, and referenced a migration that will never exist — so 3a had NO computed tier | **FIXED** — computed `platform`, with the invocation trap recorded |
| 3 | MAJOR | §6 steps 3-4 described both slices' deploys and a client change that is 3b's | **FIXED** — one deploy, `weekly-report` only |
| 4 | MAJOR | §5 said "both EFs" and used `ai-media-proxy`'s 5-consume ceiling; `weekly_report_free` is limit **1** | **FIXED** — §5 rewritten for 3a, limit 1, plus the verified allowlist-ratchet note |
| 5 | MAJOR | §9 claimed the post-Gemini refusal was "settled by 3a" while §7 listed it OPEN and §2 said it must not be settled unilaterally — a three-way contradiction | **FIXED** — removed from the settled list; stays open and binds 3b |
| 6 | MAJOR | Nothing said PRO must not consume. `:118` never refuses PRO and `reports_screen.dart:65` fires on EVERY screen open, so a PRO user would burn the lifetime key on first visit and get `-1` forever after. Also: `-1` is a SUCCESSFUL return, not an error | **FIXED** — consume gated on `!hasPro` (the same asymmetry slice 2 documented for chat, which I failed to carry over); `-1` explicitly excluded from error logging |
| 7 | MODERATE | "Record that the ledger half moved" is not actionable against a board with several subsections | **FIXED** — three named, with a warning that line anchors rot under a concurrent session |
| 8 | MINOR | Quota-key names diverge from the parent plan, unflagged, while every other divergence is flagged | **FIXED** — flagged with its reasoning and its zero-cost-today window |
| 9 | MINOR | §4 "The client twin" was 3b content in 3a's body AND duplicated in §9 | **FIXED** — moved into §9; the dangling §7 reference to it repointed |

**Round 3 also VERIFIED CLEAN, and two of these retire earlier worries:** the Supabase-branch
mutation method is **feasible** (`deploy_edge_function` accepts an arbitrary `project_id`, and
there is merged precedent in `docs/superpowers/plans/2026-04-18-ai-coach-coach-memory-personalization.md`);
and dropping the allowlist to **0** is safe because weekly-report's one unrelated
`ai_coach_interactions` read uses a plain `.select("id")` with no `count: "exact"`, so it does not
trip the matcher. Also confirmed exact: every `weekly-report` and `ai-media-proxy` line citation,
migration 128's PK and `-1` semantics, and that **no Edge Function anywhere calls `consume_quota`
yet** — this is genuinely new integration ground.

---

## 11. Round-5 findings of record

R5 confirmed R4-2 (every listed mutation maps to a real, correctly-quoted assertion — no
hallucinated targets) and found four things. **No BLOCKING since R3**; R5's own verdict was
"narrow, same-session text fixes, not design defects."

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | MODERATE | "reddens both" undercounts — test 2 (`isFirstReport = previousReportError ? false`, `:58`) is a likely third casualty | **FIXED** — reworded to "at least these two, probably a third", with the instruction to verify once the real read shape exists. Repo-wide grep confirms the blast radius is still this ONE file |
| 2 | MAJOR | The mutation plan covered 5 assertions but **not the quota_key literal, the `'epoch'` sentinel, or the allowlist ratchet** | **FIXED** — three mutations added. The quota-key one matters most: OI-153's headline bug IS a key/channel mismatch, so the assertion guarding a typo'd `weekly_report_free` was the one running unproven |
| 3 | MAJOR | §6's board disposition for `:2743` said "stays open, it is PRO daily-cap channel work" — **wrong twice**, live-verified | **FIXED** — marked STALE/superseded by `c7b95fe5`. Its premise (those caps are resettable via `ai_coach_interactions`) was already made impossible by migration 129; and it was ledger work, not channel work |
| 4 | MINOR | §6 deployed a live gate at step 3 and reviewed it at step 5, copying slice 1's ordering | **FIXED** — reordered: mutation proofs + B-pass now precede the deploy. Slice 1's ordering was justified by migration 128 being INERT; this deploy changes live free-tier behaviour the moment it lands |

⚠ **Finding 3 is the one to remember.** It was only findable by querying the live database —
`pg_get_functiondef` on the three trigger functions — and it is an error about **work I shipped
myself four hours earlier**. A board disposition written from the board's own text, without
re-checking whether the world had moved underneath it, was confidently wrong. Same class as the
stale-citation rows in §4.9, arriving through a board entry rather than a code comment.

**Note:** R5's brief asked it to check a "§11" that did not exist — headings run 0,1,2,3,5,6,7,8,
9,10. That was a miscount in MY dispatch, not a plan gap. This section is now §11.

---

## 12. Round-7 findings of record — CONVERGED

R7 verified both R6 fixes hold **against source, not against §11's table**, and independently
re-derived that 3 of the SoT test's 4 blocks break (matching v6's "at least these two, probably a
third"). Its verdict: **CONVERGED** — its three findings were "sub-blocking documentation/coverage
gaps, not implementability or correctness defects."

**All three are fixed here anyway.** §4.2 does not have a "sub-blocking" tier, and one of them
was a genuine hole.

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | MODERATE | **Nine mutations pinned presence, gating and target — none pinned ORDER.** Round 2 established the reversed order is the WORSE failure (a consume-then-insert-fails permanently burns a LIFETIME unit *and* loses the row), yet every assertion stays green on a swap | **FIXED** — a 10th mutation plus a source-position assertion. Valid because `grep -c "Promise.all"` → 0: every query in the file is a sequential `await` |
| 2 | MINOR | §7 called the post-Gemini refusal "open" while §6 — the section an implementer follows — already resolves it by omission | **FIXED** — SETTLED for 3a, open only for 3b. Second instance of the same §6-vs-§7 shape round 3 caught between §9 and §7 |
| 3 | MINOR | The absent-row live assertion named no mechanism, though a precedent exists | **FIXED** — named: `:53` calls `auth.getUser(token)`, so a branch deploy alone is insufficient; reuse the dev-build-pointed-at-branch precedent already cited for the mutation method |

## Convergence trajectory

| Round | Findings |
|---|---|
| 1 | 1 BLOCKING, 3 major, 4 minor |
| 2 | 1 BLOCKING (new), 4 major, 2 minor → **SPLIT under §4.12.1** |
| 3 | 1 BLOCKING, 5 major, 3 minor |
| 4 | 0 blocking, 2 major, 3 minor |
| 5 | 0 blocking, 2 major, 1 moderate, 1 minor |
| 6 | 0 blocking, 1 major, 1 moderate |
| 7 | **0 blocking, 0 major** — 1 moderate, 2 minor, all fixed → **CONVERGED** |

**No BLOCKING since round 3.** The split at round 2 is what turned the curve: rounds 1-3 found
design defects in a unit covering two Edge Functions with different shapes; rounds 4-7 found
progressively smaller gaps in one.

⚠ **The most valuable findings arrived at rounds 5 and 6, not 1 and 2** — the stale board
disposition (findable only by querying live Postgres about work shipped four hours earlier) and
the absent-row lockout (created by my own round-3 remediation). A review process that stopped at
"×2" would have shipped both.

