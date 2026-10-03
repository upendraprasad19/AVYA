# OI-162 slice 3b — `ai-media-proxy`'s free-image lifetime meter onto `usage_counters`

**Branch** `oi162-slice3b-media-meter` · **parent** diagnose `d3a7f1` · **v3, converged after review rounds 1 + 2**

Scope was fixed by slice 3's §9 after the §4.12.1 split. This plan implements it; it does not
re-open it.

---

## 0. What round 1 changed (5 findings: 2 BLOCKING, 2 MAJOR, 1 MINOR — all accepted)

Every finding was re-verified against the tree before acting; the numbers below are mine, not the
reviewer's.

| # | Finding | Disposition |
|---|---|---|
| F1 | Deleting `getFreeImageAnalysisCount` breaks `usage_quota_ledger_writer_to_reader_test.dart`'s `stillLegacy` map | **ACCEPTED** — §5 row 6b carries the paired map edit; §7 lists the file |
| F2 | The plan said "rewire the concept"; no concept covers this gate | **ACCEPTED, premise corrected** — see below |
| F3 | An OPEN board subsection for this exact bug must be closed by 3b | **ACCEPTED** — §8 |
| F4 | 3a's mutation-safety rules claimed as "inherited", never restated | **ACCEPTED** — §10, restated in full |
| F5 | `:435`/`:468` anchor the open-brace, not the `channel:` literal | **ACCEPTED** — 438/471 throughout |

**F1, verified:** `grep -rn "getFreeImageAnalysisCount" lib/ test/` returns exactly 2 hits — the
definition at `ai_coach_repository.dart:279` and the `stillLegacy` entry at
`usage_quota_ledger_writer_to_reader_test.dart:201`. That map asserts each listed file still
`contains('ai_coach_interactions')`, and **`ai_coach_interactions` appears exactly ONCE in
`ai_coach_repository.dart`, at `:284` — inside the method being deleted.** v1's "grep returns 1
line" was silently scoped to `lib/`. This is the §4.9 grep-the-test-tree class (OI-168) caught
before landing rather than after, which is the entire point of the rule.

**F2, corrected premise — the conclusion survives, the reason changes.** `usage_quota_ledger`
DOES exist (`sot_registry.yaml:10323`), so "no concept exists" is false as stated. But its
`readers:` are only slice 2's three trigger functions, and **slice 3a did not add itself there** —
it registered under the SURFACE concept `weekly_report_pro_gate` (`:10110`). That is the
precedent: one concept per gate, not one shared ledger concept. No concept covers
`ai-media-proxy`'s image gate today (its only registry appearances are under
`llm_prompt_input_sanitization`, which is prompt safety, plus one prose mention in
`usage_quota_ledger`'s description). **So 3b MINTS a concept, and under strict Gate 42 a new entry
needs a real `behavioral_test_path:` or `presence_only: true`.** v1's word "rewire" presumed
something to rewire and would have failed the gate at commit time.

⚠ **Do not cite `usage_quota_ledger`'s `reader_manifest_complete: true` as evidence of anything.**
It is **enforced by nothing in practice** — but the mechanism is NOT the one v2 stated, and round 2
was right to correct it. Gate 50 phase 2 skips a concept only when its `hive.key_prefix` is null,
empty, `startsWith('<')`, or `contains('—')` (`check_reader_manifest_complete.dart:113-119`).
`"n/a"` fires **none** of those, so this concept IS counted and scanned. The scan is simply a
structural no-op: it hunts for the literal string `n/a` in a Hive-read context, which no real code
will ever contain. So the protection is absent, but by vacuity rather than by an exemption — and a
future author must not read `"n/a"` as a script-recognised sentinel the way `<…>` is.

## 0.1 What round 2 changed (1 BLOCKING, 2 MINOR — all accepted, all re-verified by me)

| # | Finding | Disposition |
|---|---|---|
| R2-1 | §5 row 6b was INCOMPLETE — two more assertions in the same test file break | **ACCEPTED** — §5 row 6c |
| R2-2 | §0's Gate 50 mechanism was backwards | **ACCEPTED** — corrected above |
| R2-3 | §8 said the board subsections belong to OI-162; they belong to **OI-153** | **ACCEPTED** — §8 rewritten |

**R2-1 is the one that matters, and it is the MIRROR of round 1's F1.**
`usage_quota_ledger_writer_to_reader_test.dart` holds two further ratchets —
`:133` and `:164`, both `const allowed = {'supabase/functions/weekly-report/index.ts'}` — asserting
that no file outside that set contains the literal `usage_counters` (`:124`) or `consume_quota`
(`:158`). This plan puts BOTH literals into `ai-media-proxy/index.ts`, so both tests fail the
moment the diff lands. Verified: `grep -n "const allowed" …` returns exactly those two lines.

Round 1 found ONE ratchet in that file and I patched it. Neither round 1 nor my own verification
asked the mirror question — **what else in this file is keyed on the same set of files?** — and the
answer was "two more things, twelve lines apart". Instance of
`feedback_mistake_guard_without_its_mirror`: fixing the instance rather than the class. The §7
grep-the-test-tree rule found the FILE; it does not find every assertion inside it.

## 1. The bug, in one paragraph

`ai-media-proxy` gates the free tier's **5 LIFETIME image analyses** by counting rows in
`ai_coach_interactions` with `channel='free_image_analysis'` and **no date bound**
(`countFreeImageAnalyses`, `:67-82`). Those rows are non-`app_event`, so `rolling-context`
summarises and DELETES all but the newest 10 once a user passes 50 messages. A lifetime quota has
no window to survive deletion on, so **a free user who chats enough gets another 5 free Gemini
image analyses, repeatedly.** Identical mechanism to slice 3a's weekly report; different surface.

## 2. Writers and readers, by file:line (§4.1)

**Readers (quota):**
- `:67-82` `countFreeImageAnalyses` — `channel='free_image_analysis'`, NO date bound → the lifetime meter. **Fail-OPEN**: `if (error) return 0` and `catch (_) { return 0 }`.
- `:89-105` `countProImageAnalysesToday` — `channel IN ('pro_image_analysis','image_analysis')`, IST day. Same fail-open shape. **NOT IN SCOPE** — see §6.
- `lib/features/ai_coach/repositories/ai_coach_repository.dart:279` `getFreeImageAnalysisCount` — client twin, counts the same channel. **ZERO PRODUCTION callers**; the only other reference in the repo is the test-map entry named in §0/F1.

**Gate call sites:**
- `:465-466` free gate — `usedSoFar >= FREE_IMAGE_ANALYSIS_LIMIT` (5) → paywall reply, no Gemini call.
- `:505-509` PRO gate — `proUsedToday >= PRO_IMAGE_DAILY_CAP` (50). Out of scope.

**Writers (`ai_coach_interactions`):**
- `:438` `channel: "video_paywall"` — refusal log, not a quota unit. (The enclosing insert opens at `:435`.)
- `:471` `channel: "image_paywall"` — refusal log, not a quota unit. (Insert opens at `:468`.)
- `:669` `channel: interactionChannel` — **the quota unit**. ⚠ A VARIABLE; a literal grep is blind to it. Resolved at `:664-666`: `isFreeImageAnalysis ? "free_image_analysis" : "app"`, where `isFreeImageAnalysis = !isVideo && !isPro`. It is **never** `pro_image_analysis` or `image_analysis`.

**Display re-count:**
- `:687` `freeImageUsed = await countFreeImageAnalyses(...)` — a SECOND full count, after the insert, purely to render "X of 5 free analyses left" into the reply text at `:691`.

## 3. Ground truth verified live (not assumed)

- **No trigger covers this channel.** The three triggers on `ai_coach_interactions` guard, from `pg_get_functiondef`: `enforce_chat_app_daily_limit` → `NEW.channel IS DISTINCT FROM 'app'`; `enforce_food_text_daily_limit` → `'food_text_analysis'`; `enforce_vision_analysis_daily_limit` → `NOT IN ('scan_meal','cart_auditor')`. **None matches `free_image_analysis`**, so an EF-side `consume_quota` cannot double-count against a trigger. This is what settles trigger-vs-EF below.
- **`quota_key` is unconstrained `text`** — no CHECK constraint, so **NO MIGRATION** is required, exactly as in 3a. Migration 130 stays free.
- **Zero client readers** of `free_image_used` / `free_image_remaining` / `free_image_limit` / `gate_reason` (`grep -rn` over `lib/` → no hits). The user-visible number reaches them only through the reply TEXT interpolated at `:691`. So the structured fields are dead weight, but **`freeImageRemaining` itself is user-visible and must stay correct.**

## 4. Design — the slice-3a shape, inherited

§9 of the slice-3 plan states 3b inherits 3a's settled decisions. Concretely:

1. **The gate becomes an ADVISORY READ** of `usage_counters` (`quota_key='free_image_analysis'`, `window_start='epoch'`, `.maybeSingle()`).
2. **The `:669` insert stays VERBATIM and unconditional.** Same argument as 3a: it is the conversation row, and `sync_coach.dart` restores every channel unfiltered. It simply stops feeding the gate.
3. **`consume_quota` runs AFTER the insert**, gated on `isFreeImageAnalysis` **and on the insert having succeeded**.
4. **`consume_quota`'s return value REPLACES the `:687` re-count** — it returns the new `used`, which is exactly the number the display needs. This is the "`:687` double-consume collapse" §9 names: today the EF counts the log twice per request (gate + display); after, it reads one indexed row and gets the post-write count from the RPC.

**Why NOT a trigger, when slice 2 used triggers.** A trigger is the enforcement point wherever one *can* be — and unlike 3a, an INSERT does exist here, so a trigger is genuinely possible. It is rejected for two specific reasons, not by analogy: (a) a trigger cannot return the new count to the EF, so the display would need a *third* round trip, defeating the collapse that is half this slice's value; (b) a trigger RAISES on exhaustion, which would make the `:669` insert throw — and that insert is unconditional by design, so the refusal path would have to be restructured around an exception. The advisory-read + authoritative-consume shape keeps the refusal a plain `return`.

### 4.1 The three outcome states of the advisory read (§4.12.1 round-6 lesson, 3a)

Replacing a `count: "exact"` (2 outcomes: number / error) with a value-select creates a **third**: `data: null, error: null` — the successful read of an ABSENT row.

| state | meaning | behaviour |
|---|---|---|
| row present | real `used` | compare against the limit |
| **absent** (`data:null, error:null`) | never consumed → `used = 0` | **GRANT** |
| error populated | counter unreadable | **DENY** (fail CLOSED — the `:77-81` fix) |

⚠ **Every free user is in the ABSENT state at cutover.** Conflating absent with error would refuse every free user's first image analysis permanently — the exact lockout round 6 caught in 3a. `.maybeSingle()`, never `.single()` (which throws PGRST116 on zero rows).

### 4.2 Fail-closed needs an honest refusal reason

`:77-81`'s `if (error) return 0` is fail-OPEN and is a live defect. Fixing it means a transient DB
error now DENIES. But the existing refusal returns `gate_reason: "free_image_limit_reached"` and
the copy *"you've used all 5"* — which would be a **lie** on a transient error, and the user has
not used all 5.

**Proposed:** a distinct `gate_reason: "quota_unavailable"` with a retry-flavoured reply, so the
fail-closed path is honest. This is the only place the plan adds surface beyond the migration of
the counter. **Flagged for review** — the alternative is to reuse the existing refusal and accept
a misleading message on a rare path.

### 4.3 What the display shows when the consume fails

`consume_quota` returns the new count (≥1) or **`-1`** on exhaustion; an RPC error returns no
number at all. Three cases:

- normal → `freeImageUsed = consumedCount`, `freeImageRemaining = max(0, 5 - consumedCount)`
- `-1` (a race past the advisory gate) → treat as at-limit: `used = 5`, `remaining = 0`
- RPC error → we do not know the count. **Omit the counter line entirely** rather than print a fabricated number. Log `console.error`.

### 4.4 ORDERING — stated, not inherited (F4)

The sequence inside the handler, in order, with the reason each position is load-bearing:

1. **Advisory read** of `usage_counters` → refuse early on at-limit or on error (§4.1). No Gemini
   call, no insert.
2. **Gemini call.**
3. **Insert the conversation row** (`:669`) — unconditional, result destructured into
   `const { error: insertError }`.
4. **`consume_quota`**, gated on `isFreeImageAnalysis && !insertError`.

**Consume must never precede the insert.** 3a's plan states the reason and it transfers verbatim:
there is no transaction spanning the two, so consume-then-insert-fails **burns a LIFETIME unit and
loses the only copy of the work**. The reverse ordering fails safe — an insert that lands with a
failed consume grants one extra analysis, which is the same bounded residual as the advisory race
in §9.2.

## 5. Changes

| # | File | Change |
|---|---|---|
| 1 | `ai-media-proxy/index.ts` `:67-82` | `countFreeImageAnalyses` → reads `usage_counters`; fail CLOSED; `.maybeSingle()`; absent → 0 |
| 2 | `:465` | gate consumes the new advisory read; adds the `quota_unavailable` branch (§4.2) |
| 3 | `:669` | capture the insert's error (`const { error: insertError } = await …`) — today it is discarded |
| 4 | after `:669` | `consume_quota('free_image_analysis', 'epoch', 5)` gated on `isFreeImageAnalysis && !insertError` |
| 5 | `:687` | delete the re-count; derive from the RPC's return per §4.3 |
| 6 | `ai_coach_repository.dart:279` | **DELETE** `getFreeImageAnalysisCount` — zero production callers, reads the old table. Deleting dead code is not a deferral; repointing a method nothing calls would be inventing a reader |
| 6b | `test/contracts/usage_quota_ledger_writer_to_reader_test.dart:~201` | **PAIRED WITH ROW 6** — drop the `ai_coach_repository.dart` entry from `stillLegacy`. Its `contains('ai_coach_interactions')` assertion becomes false the moment row 6 lands (F1). This is the ratchet moving FORWARD (4 legacy readers → 3), not a loosening |
| 6c | same file `:133` and `:164` | **PAIRED WITH ROWS 1–5 (R2-1)** — add `'supabase/functions/ai-media-proxy/index.ts'` to BOTH `allowed` sets: the `usage_counters` ratchet (`:124`) and the `consume_quota` ratchet (`:158`). Mirror weekly-report's existing justifying comment: the advisory read + authoritative consume is the ONLY accepted exception. Also refresh that file's `stillLegacy` reason string for ai-media-proxy (after 3b only `countProImageAnalysesToday` is legacy there) and its "FIVE remain, across four files" header, which becomes three across three. Neither of those two is gate-enforced; both are actively misleading if left |
| 6d | `ai-media-proxy/index.ts:660-662` | Rewrite the comment *"Free image analyses MUST land on 'free_image_analysis' so `countFreeImageAnalyses()` picks them up next request."* — **false after this change.** The channel still drives the conversation log and `sync_coach.dart` restore; it no longer feeds the counter |
| 6e | `:681-683` | Rewrite *"Re-count AFTER insert so the displayed remaining is accurate"* — it documents the code row 5 deletes. Replace with the §4.3 derivation (the RPC's return IS the post-write count) |
| 7 | `scripts/usage_counter_source_lib.dart:154` | allowlist `2 → 1` (the PRO counter remains, OI-153) |
| 8 | `docs/audit/open_issues.md` | close the `:2699` subsection (§8) + OI-153 reconciliation (§6) |
| 9 | `docs/sot_registry.yaml` | **MINT** a concept for this gate, mirroring `weekly_report_pro_gate` (`:10110`): `behavioral_test_path:` pointing at the new contract test **plus** `presence_only: true` with the Deno-EF reason (no importable surface; CI `deno check` is the compile proof). Writers = the `:669` insert (annotated "NO LONGER the writer for the gate") and the `consume_quota` call; reader = the advisory read with its three outcome states |

**No migration. No new secret. No schema change.**

## 6. OI-153 reconciliation — confirmed from code, not memory

`countProImageAnalysesToday` reads `channel IN ('pro_image_analysis','image_analysis')`.
**Nothing writes either value.** The only writer that could is `:669`, whose channel resolves to
`"free_image_analysis"` or `"app"` (`:664-666`). So **the PRO 50/day image cap has never fired.**

**Confirmed a second, independent way — from DATA, not code** (read-only prod query, 2026-09-08):
`select count(*) from ai_coach_interactions where channel in ('pro_image_analysis','image_analysis')`
→ **0**. Not one row has ever been written under either channel. Round 2 independently re-derived
the code half (`grep -rn` over `lib/` + `supabase/functions/` → exactly one hit, the READ at
`:98`). Code says nothing writes it; data says nothing ever did.

Migrating it would therefore *activate* a cap that has never been enforced — a **product
decision**, not a refactor, and correctly out of 3b's scope. This plan records the finding on the
board and leaves the counter and its allowlist entry in place.

⚠ Note the second-order fact while here: a PRO image analysis is logged as `channel: "app"`, which
IS the chat-cap trigger's channel. PRO is exempt (proven live by slice 2's
`slice2_pro_consumes_nothing`), so no quota is consumed today — but the PRO exemption is now the
only thing standing between PRO image analyses and the 10/day chat cap.

## 7. Tests

- **`test/contracts/media_free_image_lifetime_gate_writer_to_reader_test.dart`** (new, source-grep — PRESENCE only): consume under the right key; the epoch sentinel; the gate reads `usage_counters` and no longer counts the channel; `.maybeSingle()` never `.single()`; absent → grant, only error denies; the `:669` insert survives unconditional; insert PRECEDES consume; the consume is gated on the insert result; the re-count is GONE; allowlist ratcheted to 1.
- **`test/sql/oi46_daily_cap_triggers_live_verify.sql`** — add `slice3b_*` ledger assertions mirroring 3a's, labelled as **ledger-invariants, not proof the EF changed**.
- **Repoint, do not delete**, any existing contract that greps the changed lines.
  ⚠ **Run `grep -rln` over `test/` for every changed path BEFORE landing** (OI-168 — the rule that
  was skipped in 3a and cost a push cycle). **Already run for this plan; known affected:**
  - `usage_quota_ledger_writer_to_reader_test.dart` — **THREE separate assertions**, not one: the
    `stillLegacy` map (row 6b) AND the two `allowed`-set ratchets at `:133`/`:164` (row 6c).
    ⚠ Finding the FILE is not finding the assertions. Round 1 found one; round 2 found the other
    two in the same file. After grepping for the file, grep INSIDE it for every set, map, or
    literal keyed on the thing you are changing.
  - `usage_counter_source_lib_test.dart` — derives from `allowedEdgeFunctionSites`, so row 7's
    allowlist ratchet moves it. It already carries a zero-allowance test.
  Re-run the grep after the diff is drafted, since a change can create a new match.
- **Mutation-prove every new assertion**, and confirm each mutation APPLIED. A compile error is not a proof; a zero-red mutation is not proof of coverage (§4.4 rule 21).

## 8. Board reconciliation (F3)

`docs/audit/open_issues.md:2699-2725` holds an OPEN subsection —
*"Folded in 2026-09-03 from OI-162 — the FREE-IMAGE LIFETIME QUOTA resets itself"* — which is
precisely this bug. 3b closes it, mirroring the twin immediately below it at `:2726`
(*"✅ CLOSED 2026-09-06 by OI-162 slice 3a — the WEEKLY-REPORT first-free gate"*).

⚠ **Corrected by round 2 (R2-3): both subsections live under `## OI-153` (at `:2676`), NOT under
OI-162.** v2 asserted OI-162 and was simply wrong — verified with
`awk 'NR<=2699 && /^## /{h=$0;l=NR} END{print h,l}' docs/audit/open_issues.md`.

**No `closes-oi:` is demanded, and this is settled rather than left to commit time.**
`check_closes_oi_cited.dart` diffs only top-level `^## OI-NN` sections against their first
`- **Status**:` line (`_sectionRe`/`_statusRe`, `:33-36`). A `###` subsection carries no status
line and is invisible to it. OI-153's own status stays **OPEN** — correctly, since the dormant PRO
cap is a product decision this slice explicitly does not make (§6, §11) — so no tracked status
moves and the gate cannot fire.

⚠ **Do not propagate the board's stale citations when editing it.** `:2699` cites
`ai-media-proxy/index.ts:62-76` for `countFreeImageAnalyses`; ground truth today is `:67-82`. The
subsection was written 2026-09-03 and the file has shifted since. (Its twin citation, the client
method at `:279`, is still correct.) This plan's line numbers were derived independently against
the current file, not copied from the board.

## 9. Risks

1. **Cutover — structurally real, live blast radius currently ZERO.** Every existing free user
   starts at `used=0` in the new ledger, so anyone who had already spent analyses would get their 5
   back, once. **Measured against prod 2026-09-08 (read-only): `select count(*) from
   ai_coach_interactions where channel = 'free_image_analysis'` → `0`, across `0` distinct users.**
   Nobody has ever consumed one, so the regrant applies to no one. The board recorded the same
   thing on 2026-09-03 ("LATENT, not live"); it still holds. The reasoning is unchanged — a
   backfill from the pruned log would import exactly the corrupted counts this slice exists to stop
   trusting — only the severity is. **Re-measure rather than citing this number**; it is a
   point-in-time read and the mechanism is live the moment the first free image analysis lands.
2. **The advisory-gate race**: two simultaneous requests can both pass the gate; the second `consume_quota` returns `-1`. At most one extra analysis, once. Same accepted residual as 3a.
3. **Fail-closed is a behaviour change** on the error path (was: silently grant). §4.2's honest refusal reason is what keeps it from being a lie.

## 10. Safety rules for verification — restated in full, NOT inherited (F4)

3a's plan carries these at its `:312` and `:351`. They are restated here because a rule referenced
by pointer is a rule nobody reads, and the stakes are strictly HIGHER for this slice: 3b's quota is
also a LIFETIME quota, and **a lifetime unit burned by a test cannot be undone.**

1. **Never run a mutation against PROD.** Mutation experiments run on a Supabase **branch**
   (`create_branch`), the same method 3a used and the same one that let `daily-snapshot` be tested
   safely. A lifetime quota consumed on prod is permanent for that user.
2. **Never spend the shared QA account** (OI-164). It is shared mutable state that CI's live tests
   also depend on — the exact collision that reddened `main` in slice 2, where three
   `ai_proxy_test.dart` tests hit a 10/day cap consumed elsewhere.
3. **A live `execute_sql` READ against prod is fine; a WRITE is not**, absent explicit founder
   authorization for that specific action (§4.3 — plan approval ≠ apply approval).
4. **Deploying `ai-media-proxy` is a separate explicit go.** This plan does not carry deploy
   authorization, and a merged code change is not a deployed one — `weekly-report` sat at live v26
   with merged 3a code until the founder authorized v27 separately.

## 11. Out of scope, explicitly

The PRO image cap (OI-153, product decision) · `delete-account` / `verify-payment` (slice 4,
catastrophic, needs `hermes: accepted`) · removing the unread structured response fields.
