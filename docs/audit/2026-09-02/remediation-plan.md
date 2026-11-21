# Tech-debt audit 2026-09-02 — remediation plan

> ## ⛔ STATUS: NOT CONVERGED after ×2 review — §4.12.1 SPLIT rule invoked
>
> **Round 1: 6 BLOCKING. Round 2: 5 BLOCKING — and FOUR of the five were defects *inside round 1's
> corrections*.** All verified against source by the main thread; none were reviewer error.
>
> §4.12.1 states the rule for exactly this: *"When successive reviews keep surfacing new material
> issues, that is the signal the unit is too large — **split it and ship the smallest converged
> piece**, don't review the large thing a fifth time."*
>
> **A round 3 on this document is the wrong move.** The evidence that it would not converge:
>
> | Correction | Round 1 said | Round 2 found |
> |---|---|---|
> | ARCH-1 blast radius | "6 fields" → corrected to **20** | still wrong — `_hasNumber` adds **13** more = **33**, including `body_fat_percent`, the precedent the design is anchored on |
> | ARCH-1 design | "server-side null authoritative" → rejected as data loss | replacement offers a **sentinel** branch the restore path cannot express (no valid non-null sentinel for `date`/`numeric`/`text[]`); only a tombstone + migration works, which the plan never scoped |
> | INFRA-2 scope | "5 gates run nowhere" | **6** — `check_test_runtime_budget.dart` (skip at `pre-commit.sh:338`, `test.yml:248`, 0 hits in `build-apk.md`) |
> | Ledger (R1-3) | restored 3 dropped findings | restored the **count**, not the **work** — INFRA-12 has `closed_in_commit` and no specified fix |
> | INFRA-13 (new in v2) | — | its fix **fires on the gate's own source** (6 hits / 3 files) and is a platform-tier matching change filed under doc rot |
>
> **The recurring mechanism in my own work, stated plainly:** every correction widened an enumeration
> by re-running the *same* query rather than asking what *other* predicate, file, or scope holds
> members of the set. 6→20→33 fields; 5→6 gates; `channel` readers inside `supabase/functions/` then
> outside it. This is the audit's own central finding — *a green check is only as wide as its input
> set* — reproduced three times by the person writing the report about it.
>
> **Recommended disposition: split (see §11). Do not execute any unit from this document as written.**

---

## (v2 body below — retained as the input to the split, not as an approved plan)


- **Branch:** `techdebt-audit-sep02`
- **Baseline:** `a2a7694c` (main), gates green (`bash scripts/pre-commit.sh` → exit 0)
- **Trigger:** CLAUDE.md §4.10 "after any 3+-batch landing"
- **Findings:** **83** (81 agent-surfaced + INFRA-12 + INFRA-13, both main-thread)
- **Status:** PLAN ONLY. Founder directed "full plan first, execute nothing yet" (2026-09-02).
  Round 1 review complete (6 BLOCKING, all accepted + verified). **Round 2 pending** (§4.12.1 requires
  review #2 to run on THIS hardened version, not the original).

---

## 0. Round-1 corrections — what changed and why

Round 1 returned **6 BLOCKING**. I verified every one against source before accepting; all six held.
Two would have shipped a regression worse than the bug they fixed.

| # | What the v1 plan got wrong | Verified at |
|---|---|---|
| R1-1 | CODE-1's fix would drop PRO image turns out of **two `channel` allowlists outside `supabase/functions/`** — the coach's replayed history and a live prod metric | `coach_interaction_repository.dart:282,306`; `migrations/120_...sql:125` |
| R1-4 | ARCH-1's proposed fix (**"server-side null authoritative"**) would wipe unsynced local edits on every sign-in — **data loss**, strictly worse than the stale-value bug | `sync_profile.dart:755-757` |
| R1-2 | Deleting `import_map.json` silently disables Gate 27's **floating-pin scan** (it is wrapped in `if (importMap.existsSync())`) — during the very unit that converges pins | `check_import_map_present.dart:17-21, 62, 71` |
| R1-3 | **3 findings dropped** (TEST-1, TEST-11, INFRA-12); the "68" was arithmetic, not enumeration | `grep -o` in the v1 plan → 0 / 0 / 1 |
| R1-5 | INFRA-2 un-dormants 5 gates whose allowlist names **pre-existing violations** with no terminal state | `check_gate_scripts_wired.dart:62-77` |
| R1-6 | INFRA-11 as a hard-fail before INFRA-2 **wedges every commit repo-wide**; §4.11's warn-only step was omitted from both new gates | §4.11 point 2 |

⚠ **The meta-lesson, recorded because it is the plan's own thesis turned on itself:** three of the six
blockers are *an enumeration that stopped at the window it was looking at* — exactly the defect this
audit documents in the codebase. I enumerated `channel` readers inside `supabase/functions/` and
missed two outside it; I read `_hasValue` in a 9-line window and reported 6 of **20** guarded fields;
I totalled the ledger by arithmetic twice. **Say the input set out loud before citing any count.**

**Round-1 items also resolved by running things:**
- `check_snapshot_contract.dart` **now PASSES** ("57 keys checked, 4 reader citations") — its
  allowlist comment claiming "1 reader-contract violation tracked separately" is **stale**. One fewer
  unknown in R1-5's scope.
- `check_unawaited_has_error_sink.dart` → **81+ findings, exit 0 (audit-only mode)**.

**New finding surfaced while verifying R1-5 → INFRA-13** (see §5).

---

## 1. Why this plan is shaped the way it is

> **The code is in better shape than the safety net.** Of the top ten findings, eight are *something
> green because it does not run or cannot fail.*

The Documentation pass supplies the control: **every GATED numeric claim held; nearly every UNGATED
one drifted.** Hence Unit 5 fixes doc rot with a gate, not by hand.

⚠ **The priority formula `(I+R)×(6−E)` under-ranks two findings** by penalising effort: ARCH-1
(silent user-data reversion, 24) and CODE-11 (destructive snapshot overwrite, 24). Sequencing
overrides the formula where user-visible correctness is at stake.

⚠ **Scale context (live-verified 2026-09-03):** this is a **pre-launch** app — `ai_coach_interactions`
holds 8 rows on the coach channels, all plain text chat, and **zero** `free_image_analysis`. Nothing
here is currently harming users. That does not reduce severity (an inoperative control is still
inoperative) but it means sequencing is driven by cost-to-fix and risk-of-regression, **not** by
firefighting.

---

## 2. Unit 0 — Wiring trust (NEW, promoted by R1-6 + R1-10)

**Why this is now first, ahead of Unit 1:** Unit 1 ships a *new gate*. INFRA-2 proves a gate can be
wired to a runner that never invokes it, and INFRA-11 proves nothing checks that claim. Building
Unit 1's gate on that mechanism first would be building on the defect.

| Finding | Pri | Fix |
|---|---|---|
| INFRA-11 | 21 | Gate 33's allowlist entries must name a runner FILE; the gate asserts the gate's filename appears in it. Free-text reasons become unrepresentable. |
| INFRA-2 | 36 | The 5 gates that run nowhere |

**Landing rule (R1-6):** INFRA-11 and INFRA-2 land in **ONE commit**, or INFRA-11 ships `--warn-only`
first and flips to hard-fail in the commit that fixes INFRA-2. A hard-fail INFRA-11 landing alone
blocks every commit in the repo — including the other active session's.

**INFRA-2 scope, stated honestly (R1-5).** INFRA-2 closes **the wiring**. Running the five gates
surfaces pre-existing violations their allowlist already names: *"1 unapplied migration"*, *"3
schema-arbiter conflicts"*, *"1 missing test for swap_undo_snackbar"* (the snapshot-contract one is
**stale** — that gate now passes). **Each violation the gates report becomes a numbered finding
appended to THIS ledger before the batch closes** — not a future batch. Three of the five need live
DB / build state, so the enumeration runs as Unit 0's first action, under founder authorization
(§4.3), not now.

**Terminal state: `closed_in_commit` for both.**

---

## 3. Unit 1 — Paid-feature gates that FAIL OPEN

**Why:** every item is a security/cost control that does not hold; all are effort 1–2; fixing them
pre-launch is cheap and fixing them after a bill is not.

| Finding | Pri | Fix |
|---|---|---|
| CODE-1 | 40 | PRO image cap counts `pro_image_analysis`; nothing writes it (prod: 0 rows) |
| CODE-3 | 30 | Free-image counter returns 0 on error; docstring's `0 < 5` reasoning is inverted |
| CODE-4 | 30 | The counter insert enforcing CODE-3 discards its result |
| CODE-6 | 30 | `checkPro` swallows errors unlogged — paying user silently loses PRO tools |
| CODE-7 | 30 | delete-account rate-limit counter is a floating `.then()` |
| CODE-8 | 30 | weekly-report PRO gate falls open → free user gets a Gemini 2.5 **Pro** report |
| CODE-2 | 28 | PRO+video matches neither branch — most expensive request type uncapped |

### 3.1 CODE-1 — the fix, corrected by R1-1

**Rejected: (a) change the read to count `channel='app'`.** `'app'` is shared with ai-proxy text chat
(`ai-proxy/index.ts:705, :1086`), so the cap would throttle PRO users on ordinary chat. Round 1
independently confirmed this rejection is correct.

**Adopted: (b) change the write** so the PRO image path stamps `'pro_image_analysis'` —
**plus two same-commit updates that v1 missed.** Stamping a new channel value drops those rows out of
two allowlists:
1. `lib/features/ai_coach/repositories/coach_interaction_repository.dart:282` —
   `static const Set<String> _coachChatChannels = {'app', 'chat', 'in_app_orphan'};`, applied at
   `:306`. Without the update, **the coach silently forgets image conversations it currently
   remembers.**
2. `supabase/migrations/120_engagement_metric_channel_filter_and_hold_telemetry.sql:125` —
   `and channel in ('app', 'chat', 'in_app_orphan')` inside `founder_metrics_engagement()`. Without
   the update, **a live founder metric under-counts.**

Trigger side is clean — `migrations/111:74` `IF NEW.channel IS DISTINCT FROM 'app' THEN RETURN NEW;`.

⚠ **Collision check required before scheduling:** updating `founder_metrics_engagement()` means a new
prod migration redefining a function that **migration 120 owns**, and migration 120 belongs to the
**in-flight backend-CPU-starvation batch** (applied to prod, code unmerged, Hermes `block_ship`).
Coordinate before writing it.

⚠ **§1.1's old open question is resolved:** zero `free_image_analysis` rows are explained by the
feature being unused, **not** by a second broken write. CODE-1 and CODE-3 are **separate** defects
needing separate fixes and separate tests.

### 3.2 L29 rate-limit matrix — folded in here (R1-7)

v1 declared L29 terminal by citing OI-93 and OI-142. **Both are deploy-artifact issues and neither
mentions rate limits** — that was a deferral in a costume (§4.2). Unit 1 is already editing every
rate-limited endpoint, so the L29 matrix (endpoint × server limit × client limit × over-limit
response × telemetry-on-over) is built **here**, and any eighth defect it finds is appended to this
ledger.

### 3.3 Deliverables
- Diagnose-doc per finding (rule 22) with `closes-diagnose:` in each commit body.
- Behavioral regression tests that **force the error path** and assert the request is REFUSED. A
  happy-path-only test re-creates the bug class.
- **Mutation-proof each test** (rule 21): break the fix in place, confirm the test reddens, record
  what was mutated and how many reddened. Confirm the mutation actually applied.
- **New gate `check_ef_limit_fails_closed.dart`** — flags a count-helper returning a permissive
  default on error, and a `{ count }` destructure with no `error` binding at a gating call site.
  Ships mutation-proven with a `gate_test_ledger.yaml` entry (rule 24), in an **earlier commit** than
  the fixes, **`--warn-only` first then flipped** (§4.11 point 2 — omitted in v1, R1-6).
- **Deploy authorization required** — plan approval ≠ deploy approval (§4.3).

**Terminal state for all 7: `closed_in_commit`.**

---

## 4. Unit 2 — Gates and tests that cannot fail

| Finding | Pri | Fix |
|---|---|---|
| TEST-2 | 30 | Credential guard renders as a PASS in 5 files (the OI-105 class) |
| TEST-3 | 28 | `hasLength(3)` makes the timeout guard FAIL when extended; 1 live escapee |
| TEST-4 | 25 | `dart_test.yaml` has no repo-wide `timeout:` |
| INFRA-4 | 25 | Gate 42 silently passes if `sot_registry.yaml` is renamed |
| TEST-1 | 24 | **~129 `integration_test/` tests executed by no gate** (dropped in v1 — R1-3) |
| TEST-5 | 20 | Gate 42 never resolves `behavioral_test_path:` to disk |
| ARCH-6 | 20 | Gate 46's "catches an 8th singleton" vs a hardcoded const of 7 |
| TEST-6 | 20 | Contract test named for delegation asserts `expect(true, isTrue)` |
| TEST-11 | 16 | `auth_flow` T5 early-returns on a tautology (dropped in v1 — R1-3) |
| CODE-14 | 15 | Gate 20 advisory 3.5 months; tracker OI-44 is CLOSED and unrelated. Live: **81+** findings |
| INFRA-5 | 15 | Ack loop for 20 stale `info` alerts. **Silence itself is verified correct — not a defect** |
| TEST-7 | 5 | Flutter scaffold placeholder `expect(true, true)` |
| TEST-13 | 5 | One undocumented `skip:` |

**TEST-3 + TEST-4 are BOTH done (R1-9).** v1 suggested TEST-4 might make TEST-3 redundant. It does
not: a repo-wide timeout *raises the floor* for genuinely hung tests, and CLAUDE.md's own pitfall row
records `await`-in-`testWidgets` hangs surfacing at 6m35s / 4m55s. Land TEST-4 as a backstop **and**
fix TEST-3 by deriving the guarded set from "every file under `test/scripts/` that spawns a
subprocess" rather than a frozen `hasLength(3)`.

**TEST-1 needs a decision, not just a fix.** ~129 tests that have never run may not even compile.
Sequence: (1) run them once to establish truth, (2) fix or delete what is broken, (3) wire the
surviving set into a runner. Step 1 needs `--dart-define-from-file=.env` and a device.

**INFRA-5 carries exactly ONE terminal state (`closed_in_commit`).** v1 assigned it `verified_clean`
in §2 and counted it under `closed_in_commit` in §6 — breaking its own one-state rule (R1-3). The
*silence* is verified correct behaviour and that evidence goes in `notes:`; the *ack loop* is the
work that closes it.

**Terminal state for all: `closed_in_commit`.**

---

## 5. Unit 3 — Sync + Edge Function correctness

| Finding | Pri | Note |
|---|---|---|
| ARCH-3 | 30 | 24h backoff step unreachable; cited test is a phantom |
| ARCH-4 | 30 | `_executeUserProfileUpsert` missing the cross-account guard both siblings carry |
| ARCH-2 | 28 | Retry queue drains on 2 of 4 documented triggers; `connectivity_plus` absent |
| CODE-10 | 25 | Partial cron runs logged `success` |
| **ARCH-1** | 24 | **Cleared profile field silently reverts on every sign-in** |
| CODE-11 | 24 | Unchecked read → spread-merge can wipe a day's snapshot |
| CODE-5 | 24 | Fire-and-forget embedding write; `EdgeRuntime.waitUntil` used nowhere |
| ARCH-5 | 20 | 6 AI-coach planner singletons with no lifecycle reset |
| CODE-9 | 20 | IST date + `Z` suffix — 5h30m window drift |
| ARCH-9 | 20 | Rest-day rule duplicated into a widget (service copy authoritative) |
| ARCH-7 | 16 | `drain()` documented idempotent, no re-entrancy guard |
| ARCH-10 | 16 | Migration header enforced only for the seed migration |
| CODE-12 | 16 | morning-alert idempotency contract inverted vs its header |
| ARCH-8 | 12 | `swapDays` quota check/increment split by 3 awaits (call site guarded) |

### 5.1 ARCH-1 — fix corrected by R1-4 (v1's proposal caused data loss)

**REJECTED (v1's own proposal): "make restore's `if (e.value != null)` respect a server-side null as
authoritative."** `sync_profile.dart:755-757` documents why that guard exists — *"cloud non-null
fields overwrite Hive; cloud nulls don't wipe Hive values (preserves local-only edits that haven't
synced up yet)."* Removing it wipes every never-synced field on every sign-in
(`sync_service.dart:1326`). **That is data loss; the current bug only preserves a stale value.**

**Root cause, stated precisely:** `_hasValue` is one predicate answering two questions — *"absent,
don't touch"* and *"explicitly cleared."* `city` is a symptom.

**Adopted direction:** an explicit cleared-set (tombstone or per-field sentinel) so "cleared" and
"absent" stay distinguishable **in both directions**, leaving the null-merge guard intact.

⚠ **Blast radius re-derived: `grep -c "_hasValue(p\[" sync_profile.dart` → 20 guarded fields
(`:197-241`), not the 6 the findings file reported from a 9-line window.**
⚠ **`equipment_owned` (`:223`) must be EXCLUDED** — its omission is deliberate ("must not overwrite a
cloud value with `[]` on every sync"); a blanket manifest would re-open that fixed bug.
⚠ Design against the `c3f2d8` precedent (which fixed `body_fat_percent` by clearing cloud first) so
the two mechanisms converge rather than diverge again.

Regression test must cover the whole chain — write `''` → push → read cloud → restore → assert still
empty. A payload-shape assertion would pass while the bug survives.

**Terminal state for all: `closed_in_commit`.**

---

## 6. Unit 4 — Supply chain + build toolchain (includes the seeded Semgrep item)

| Finding | Pri | Fix |
|---|---|---|
| INFRA-1 / DEP-5 | 32 | **No SAST and no SCA anywhere.** Seeded item, confirmed 3× |
| DEP-8 | 30 | CI builds APK on JDK 17; machine + CLAUDE.md require JDK 21 |
| DEP-2 | 24 | `@supabase/supabase-js` at 3 versions (37× 2.39.3, 1× 2.42.0, 2× 2.45.4) |
| DEP-3 | 24 | 3 `deno.land/std` versions; `std@0.177.0` (Feb 2023) on the payment path |
| DEP-9 | 24 | `deno.lock` untracked — URL pins fix the version, never the bytes |
| DEP-1 | 21 | `import_map.json` is inert — 0 imports resolve through it |
| DEP-6 | 20 | 84 packages locked below available |
| DEP-4 | 15 | L47 (`jose` ≥5.9) vacuously satisfied — jose imported nowhere |
| DEP-11 | 15 | 3 unused direct deps |
| DEP-13 | 12 | `cached_network_image` + `go_router` majors pending |
| CODE-13 | 10 | 13 dead constants |

### 6.1 Semgrep, scoped honestly
Scope to **`supabase/functions/` (Deno/TS) only**. Dart support in Semgrep/Opengrep is thin and `lib/`
already has ~95 bespoke gates plus `flutter analyze`. Semgrep (Apache-2.0) suffices; Opengrep only
matters for the paywalled ruleset.

**SCA is the wider, unseeded half:** `dependabot.yml` covers `pub` (:13) and `github-actions` (:51)
only. Add npm. Deno has no first-class Dependabot ecosystem, so **DEP-9 (committing `deno.lock`) is
what makes Deno deps auditable at all** — the two are coupled: commit the lockfile, then scanning has
something to scan.

### 6.2 DEP-1 — sequencing corrected by R1-2
v1 recommended deleting `import_map.json` and retiring Gate 27. **Gate 27 asserts THREE things**
(`check_import_map_present.dart:17-21`): the file exists; it pins `@supabase/supabase-js`, `std`,
`zod`, `jose`; and **no EF imports a floating `@N` pin** — that third scan is wrapped in
`if (importMap.existsSync())` at `:62`. Deleting the file disables the floating-pin detector **during
the very unit that converges those pins**, inverting §4.11.

**Corrected order:** (1) make the floating-pin scan **unconditional**, independent of the map's
existence; (2) converge DEP-2/DEP-3 with the detector live; (3) only then decide the map's fate.
DEP-4 must state explicitly that the `jose`/`zod` pin assertions go with it.

**Terminal states:** `closed_in_commit`, except **DEP-7** → `blocked_on_user` (the
`pub upgrade --dry-run` resolve is runnable without the founder; only the **unpin decision** is
blocked — R1-12 refinement), and **DEP-10** → `verified_clean` (pin discipline correct across all 5
CI jobs and matches local; age alone is not a defect).

---

## 7. Unit 5 — Documentation rot, fixed by GATE not by hand

| Finding | Pri | Claimed → Measured |
|---|---|---|
| DOC-3 | 28 | "47 tables" ×3 → **50** live; 3 tables undocumented |
| DOC-15 | 28 | 3 named `health_write_service` methods do not exist; 4 real ones omitted |
| DOC-16 | 28 | 3 nested CLAUDE.md cite `test/contracts/` files that do not exist |
| DOC-1 | 25 | 90/76/78-of-90 → **95/81/83-of-95** |
| DOC-17 | 25 | `profile_screen.dart` → does not exist |
| INFRA-7 | 20 | 14 nested CLAUDE.md (207 KB) outside the context budget |
| DOC-7 | 20 | 3 of 4 `memory/` citations dangle |
| DOC-8 | 20 | 12 nested CLAUDE.md under `lib/`, §7 lists 10 |
| DOC-2 | 20 | `pre-commit.sh` says 89/75/77 |
| DOC-19 | 20 | Validator allows 4 terminal states; docs say 3 |
| TEST-8 | 20 | `presence_only:` — claimed 6, actual **10** |
| DOC-18 | 18 | Rule 14 protects `plan_generator.dart` — now a 5-line shim |
| TEST-9 | 18 | 3 `presence_only:` entries are Hive-backed → convenience, not infeasibility |
| INFRA-3 | 15 | Same gate counts, third surface |
| DOC-4 | 15 | "49 of 87" → **49 of 96** |
| DOC-5 | 15 | 5 test-count claims understate |
| TEST-10 | 15 | Registry-cited test documents a removed mechanism |
| INFRA-12 | 24 | Opaque `error_code` — `minified:a0Y` ×47, `String` ×22 (dropped in v1 — R1-3) |
| INFRA-13 | 20 | **NEW** — deferral euphemisms in `.dart` source, invisible to their own gate |
| DOC-6 | 10 | "two `feedback_*.md` committed" → **1** |
| DOC-9 | 10 | "81 of 164" → **87 of 177** |

### 7.1 INFRA-13 (new, surfaced while verifying R1-5)
`scripts/check_gate_scripts_wired.dart:62-77` contains *"tracked separately"* (×4) and *"dedicated
remediation batches"* — §4.2's banned deferral semantics. `check_no_deferral_euphemism.dart:15-16`
scans only **(1)** staged added lines in `*.md` and **(2)** a full sweep of CLAUDE.md +
`.claude/skills/**/SKILL.md`. **It never scans `.dart` source**, so the gate that exists to catch
deferral euphemisms is blind to the ones living in gate source. Fix: extend the sweep to
`scripts/*.dart` comments.

### 7.2 The structural fix, and its honest limits
`check_claude_md_numeric_claims.dart` re-derives claimed counts from source of truth: gate count,
GATE_INDEX total, `presence_only:` count, `docs/reviews/` split, nested-CLAUDE.md count, lens count.

⚠ **Two things that gate does NOT cover (R1-8):**
- **DOC-15/16/17 are not count drift** — they are nonexistent method names, test paths and file
  paths. Gate 26 resolves only `§N` headings. **The gate must therefore ALSO resolve file-path and
  test-path citations** (mechanically identical to the `File.existsSync` checks used to verify them),
  or the 9 unsampled `lib/**/CLAUDE.md` files get a hand sweep. v1 claimed the gate was "the
  systematic answer" for those files; it was not.
- **DOC-3 (table count) cannot be gated** — it needs live DB access, which a pre-commit gate must not
  require. Fix the three prose surfaces by hand and state the limitation rather than implying cover.

⚠ **12 vs 14 nested CLAUDE.md is two scopes, not a contradiction (R1-11):** `find lib -name CLAUDE.md`
→ **12**; all non-root CLAUDE.md repo-wide → **14** (adds `supabase/functions/`,
`supabase/migrations/`). DOC-8 uses the first, INFRA-7 the second. Both are stated with their scope.

**DOC-18 is an invariant edit, not a doc edit** — rule 14's protected path must be repointed at
`lib/shared/repositories/plan_engine/plan_generator.dart`.

**Terminal state for all: `closed_in_commit`.**

---

## 8. Terminal states — the closed==N ledger (Gate 40)

⚠ **The closure YAML is NOT created until every finding is terminal.** Gate 40's closed==N invariant
(`validate_audit_closure.dart:307-314`) validates *all* `docs/audit/*_audit_closures.yaml` on **every
commit in the repo**, so a half-filled ledger would block every commit including the other active
session's. Findings live in `findings-by-lens.md` until the batch closes.

**Population, enumerated per unit (not derived by subtraction — R1-3):**

| Unit | Members | n |
|---|---|---|
| 0 — Wiring trust | INFRA-11, INFRA-2 | 2 |
| 1 — Fail-open gates | CODE-1,2,3,4,6,7,8 | 7 |
| 2 — Can't-fail gates/tests | INFRA-4, INFRA-5, TEST-1,2,3,4,5,6,7,11,13, ARCH-6, CODE-14 | 13 |
| 3 — Sync + EF correctness | ARCH-1,2,3,4,5,7,8,9,10, CODE-5,9,10,11,12 | 14 |
| 4 — Supply chain | INFRA-1, DEP-1,2,3,4,5,6,8,9,11,13, CODE-13 | 12 |
| 5 — Doc rot | DOC-1,2,3,4,5,6,7,8,9,15,16,17,18,19, INFRA-3,7,12,13, TEST-8,9,10 | 21 |
| **`closed_in_commit`** | | **69** |

| State | Count | Members |
|---|---|---|
| `closed_in_commit` | 69 | the six units above |
| `verified_clean` | 11 | INFRA-8, INFRA-9, INFRA-10, DEP-10, DEP-12, TEST-14, DOC-10, DOC-11, DOC-12, DOC-13, DOC-14 |
| `blocked_on_user` | 3 | TEST-12 (Patrol run on a device), INFRA-6 (Firebase Console), DEP-7 (unpin decision only) |
| `upstream_blocked` | 0 | — |
| **Total** | **83** | 69 + 11 + 3 = 83, closed == N ✓ |

Cross-check: INFRA 13 + ARCH 10 + TEST 14 + CODE 14 + DEP 13 + DOC 19 = **83** ✓

Required fields (drafted from the validator, not the docs): `closed_in_commit` → `commit:` +
(`verification:`|`notes:`) · `upstream_blocked` → `blocker:` + `reopen_when:` · `blocked_on_user` →
`reason:` · `verified_clean` → `evidence:`|`notes:`.

---

## 9. Founder decisions required before execution

1. **Approve this plan** (round 2 review runs on it first).
2. **Edge Function deploys** (Unit 1) need explicit per-action authorization — §4.3.
3. **Live-DB gate runs** (Unit 0's enumeration: `check_migrations_live`,
   `check_onconflict_live_arbiter`, `check_two_user_cross_account`) need authorization.
4. **DEP-7** — unpin `share_plus` to 13.x, or keep the pin and correct the stale memory file?
5. **DEP-1** — after the floating-pin scan is made unconditional, delete `import_map.json` or wire
   the 40 EFs to it?
6. **Migration-120 collision** (§3.1) — coordinate with the in-flight backend-CPU-starvation batch.
7. **TEST-12 / INFRA-6** — confirm `blocked_on_user` with a stated reopen trigger.

## 10. Not in scope — terminal, with the mis-citations corrected

- **L23 service-role adjacency** — **OI-73** covers ~10 EFs on the pre-`9ab9f42b` cron auth gate.
  ⚠ R1-7 is right that the remainder is unowned: **file a new OI** for the EFs OI-73 does not name,
  rather than calling it "partially covered".
- **L53 EF deploy reversibility** — genuinely covered by **OI-93** + **OI-142**.
- **~~L29 rate-limit matrix~~** — **NOT covered by those OIs (R1-7). Moved INTO Unit 1 (§3.2).**
- **L31 cron efficiency** — owned by the in-flight backend-CPU-starvation batch (migration 120
  applied to prod, code unmerged, Hermes `block_ship`). Re-auditing would collide with active work.
- **The 9 unsampled `lib/**/CLAUDE.md`** — covered by §7.2's extended gate **only if** it resolves
  path/symbol citations; otherwise they get a hand sweep in Unit 5. No longer hand-waved.

---

## 11. The split (§4.12.1) — proposed disposition

The 83 findings are real and verified. What failed review is **this document as a single unit of
work**, not the findings. Split into independently-shippable slices; each gets its OWN ×2 review at
its own (much smaller) size, where convergence is achievable.

### Slice A — "fail closed" (SMALLEST CONVERGED PIECE — ship first)
**CODE-6, CODE-7, CODE-8.** Three different Edge Functions, one shape each: destructure the `error`,
await the write, fail CLOSED instead of open.
- `ai-proxy/index.ts:88,96` — `checkPro` swallows errors → PRO user loses tools
- `delete-account/index.ts:174-190` — rate-limit counter is a floating `.then()`
- `weekly-report/index.ts:86,92,95` — missing `error` destructure → free user gets a Gemini Pro report

**Why this is the converged piece:** no shared expression between them, no channel-vocabulary change,
no schema change, no migration, no allowlist interaction. Round 2 confirmed the evidence *"reproduces
verbatim at every cited line"* and raised **zero** blockers against these three. Effort 1 each.
Needs: 3 diagnose-docs, 3 mutation-proven fail-path tests, `check_ef_limit_fails_closed.dart`
(warn-only → flip), and EF deploy authorization (§4.3).

### Slice B — channel vocabulary (CODE-1, CODE-2) — needs one enumeration first
Blocked on a complete, independently-derived enumeration of **every** reader of
`ai_coach_interactions.channel` — two rounds each found readers the previous missed
(`supabase/functions/`, then `coach_interaction_repository.dart:282` + `migrations/120:125`, then the
`"image_analysis"` second dead channel and the CODE-1/CODE-2 **shared ternary** at
`ai-media-proxy:663-665`). Also carries a migration-120 collision risk with the in-flight
backend-CPU batch. **Enumerate to empty, then plan.**

### Slice C — ARCH-1 cleared-vs-absent — needs a design spec, not a plan entry
Three enumerations produced three wrong blast radii (6 → 20 → **33**), and both proposed designs were
refuted (null-authoritative = data loss; sentinel = inexpressible for `date`/`numeric`/`text[]`). The
real shape is a tombstone column + migration + restore-side subtraction, spanning **both**
`_hasValue` (20) and `_hasNumber` (13), excluding `equipment_owned`, and converging with `c3f2d8`.
That is a design document with its own review, not a row in a table.

### Slice D — wiring trust (INFRA-11, INFRA-2) — re-enumerate first
Scope is **6** gates, not 5. Re-derive mechanically (`comm` the pre-commit skip block against
`build-apk.md` invocations) rather than copying the finding's number, and decide whether INFRA-11's
schema needs an explicit `runner: manual` state before it can be hard-fail.

### Slice E — doc-count gate + mechanical corrections
DOC-1, DOC-2, DOC-4, DOC-5, DOC-6, DOC-9, TEST-8, INFRA-3 — pure count corrections plus
`check_claude_md_numeric_claims.dart`. Genuinely mechanical and low-risk.
**Excludes** DOC-15/16/17 (dangling path/symbol citations — need the gate extended to resolve paths),
INFRA-12 and INFRA-13 (both misfiled here; INFRA-13 is platform-tier and its fix currently fires on
the gate's own source).

### Ledger consequence
The single `2026_09_02_audit_closures.yaml` still enumerates all 83 with terminal states — the split
changes **which commit** closes each entry, not whether it closes. `closed_in_commit` entries name
their slice's commit. **Nothing here becomes a deferral: every finding keeps a terminal state in this
audit's ledger, and the ledger is not written until all 83 are terminal (§8).**

### Also owed, from round 2, before any slice ships
- **INFRA-SEED-1 has no terminal state** (`findings-by-lens.md:25` demands one) — it is an alias of
  INFRA-1/DEP-5; record it as such or give it its own state.
- **INFRA-1 and DEP-5 are the same finding** counted once in Unit 4's 12 — state the alias.
- **INFRA-9's `verified_clean` rests on an allowlist its own evidence marks "unverified"**; verify or
  move it to `closed_in_commit`.
- Repoint the CODE-1 trigger citation to `migrations/111:20` (not `:74`), and note `111:50-52` counts
  on `channel='app'` while `111:33-36` exempts PRO — which is the actual reason the trigger is clean.
