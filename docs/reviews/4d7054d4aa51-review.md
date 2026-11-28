---
reviewed_at: 2026-09-07T08:53:42+05:30
staged_against: 4d7054d4aa51
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, guard_without_its_mirror, asserted_fixture_value, missing_input, blast_radius_mismatch, stale_or_wrong_citation, inert_check]
findings_count: 6
verdict: accepted
---

# Review — 4d7054d4aa51 (OI-162 slice 3a, weekly-report's free-gate onto usage_counters)

Fresh, context-blind adversarial pass over `ca838039` (the fix) and `d382d0f5` (a code-review
skill lens entry) on branch `oi162-slice3-lifetime-meters`, diffed against `main`. NOT YET
DEPLOYED — confirmed live (`dedsavbjuwgarrhphgnl`, `list_edge_functions`): `weekly-report` is at
version 26, and its live source (`get_edge_function`) still contains `previousReportCount` and
zero occurrences of `usage_counters`/`consume_quota` — the old code is what is actually running.

Everything below was independently re-derived, not read off the diff's own comments or the
diagnose-doc's prose:

- Ran both new/changed test files at baseline (13 tests total, all green), then applied five
  separate source mutations directly to `supabase/functions/weekly-report/index.ts`, re-ran the
  suite, and reverted each via `git checkout` before the next (`git status --porcelain` clean
  between every mutation and at the end).
- Live-queried `dedsavbjuwgarrhphgnl` (read-only + one `BEGIN…ROLLBACK` transaction, confirmed
  zero residue after): `usage_counters` schema, `consume_quota`'s live `pg_get_functiondef` body,
  the epoch-literal equality, and a full absent→consume→consume→cleanup-survival cycle against a
  real user id.
- Fetched the pinned `@supabase/supabase-js@2.39.3` → `@supabase/postgrest-js@^1.9.0` source
  (`PostgrestBuilder.ts`) to confirm `.maybeSingle()`'s actual GET-request behavior on 0 rows,
  rather than trusting the code comment's characterization of it.
- Re-ran `scripts/blast_radius_from_diff.dart` correctly (see Finding 6's near-miss) and
  `scripts/check_usage_counter_source.dart`, `scripts/check_sot_registry_completeness.dart`,
  `scripts/check_sot_registry_parity.dart`, `scripts/check_sot_behavioral_test_paths.dart`,
  `scripts/build_bug_index.dart`, `scripts/build_oi_index.dart` against the real tree.

## Findings

### Finding 1 — P1 — the writer/reader quota-key contract test is inert to writer/reader key drift, the exact bug class this OI exists to fix

**Claim under test:** `test/contracts/weekly_report_pro_gate_writer_to_reader_test.dart`'s
`'WRITER: still stamps the channel the READER counts'` test (and its own comment) claims to pin
that "the quota writer must consume the SAME key the reader reads." It asserts three independent
regexes: `channel:\s*"weekly_report"`, `['"]weekly_report_free['"]`, and
`\.eq\(\s*"quota_key"\s*,\s*\w+\s*\)`. None of the three ties the writer's `p_quota_key:` argument
to the reader's `.eq("quota_key", …)` argument — they can each be satisfied by two completely
unrelated identifiers.

**Verification:** mutated the RPC call site only (`supabase/functions/weekly-report/index.ts:679`)
from `p_quota_key: WEEKLY_REPORT_FREE_QUOTA_KEY,` to
`p_quota_key: "totally_different_key_typo",`, leaving the reader (`.eq("quota_key",
WEEKLY_REPORT_FREE_QUOTA_KEY)`) and the constant declaration untouched — i.e. a genuine
writer/reader drift where the two sides silently disagree on the key, which would resurrect
exactly OI-162's headline bug (a write nothing reads, or here worse: a write to a DIFFERENT key
than the one gating the free report, so the gate never closes for anyone):

```
$ sed -i 's/p_quota_key: WEEKLY_REPORT_FREE_QUOTA_KEY,/p_quota_key: "totally_different_key_typo",/' supabase/functions/weekly-report/index.ts
$ flutter test test/contracts/weekly_report_pro_gate_writer_to_reader_test.dart
...
+4: All tests passed!
```
All 4 tests, including the one under test, stayed green. Reverted (`git checkout --`), confirmed
clean.

For contrast, I also reproduced the diagnose-doc's own claimed "Typo the quota_key | 2" mutation
(retyping the string literal *inside* the shared constant declaration:
`"weekly_report_free"` → `"weekly_report_free_TYPO"`) — that one **does** redden exactly 2 tests
(this test plus one in the sibling file), because both reader and writer route through the same
TS identifier and are retyped in lockstep. That mutation is real and correctly caught. But it
cannot detect drift, only a typo at the single declaration site — it is a materially weaker
adversary than "the two call sites stop agreeing," which is the literal definition of the bug
class this whole OI is named for.

**Suggested fix:** add an assertion that the two arguments are the *same token*, e.g. capture the
identifier/literal at the RPC call (`p_quota_key:\s*(\S+?),`) and at the reader
(`\.eq\(\s*"quota_key"\s*,\s*(\S+?)\s*\)`) and assert the two captures are equal — or, more simply,
require that whatever the writer passes to `p_quota_key` is the identical source substring found
at the reader's `.eq("quota_key", …)` call (a single regex spanning both, or two capture-and-
compare `Match` groups). A bare presence check on each side independently cannot express a join.

status: accepted

### Finding 2 — P1 — the "PRO does not consume" test is inert to guard/call-site decoupling

**Claim under test:** `test/contracts/weekly_report_lifetime_meter_test.dart`'s `'PRO does not
consume'` test finds the first textual occurrence of `consume_quota`, takes everything before it,
and asserts `if\s*\(\s*!hasPro\s*\)` appears somewhere in that prefix. It never confirms that
occurrence is the block *wrapping* the actual RPC call — only that the literal string exists
*somewhere earlier in the file*.

**Verification:** inserted a no-op decoy immediately after the `hasPro` definition
(`supabase/functions/weekly-report/index.ts:151`):
```
if (!hasPro) {
  // decoy retained only so a source-grep for the literal pattern still matches
}
```
and then removed the PRO exemption from the real call site (`:677`) by changing
`if (!hasPro) {` to `if (true) {` immediately before the `consume_quota` RPC call — i.e. PRO users
would now also burn the free-tier lifetime unit on every report, exactly the regression the
surrounding comments name explicitly ("consuming unconditionally would burn a PRO user's key on
their first visit and return -1 forever after"):

```
$ flutter test test/contracts/weekly_report_lifetime_meter_test.dart
...
+9: All tests passed!
```
All 9 tests, including `'PRO does not consume'`, stayed green. Reverted, confirmed clean.

**Suggested fix:** anchor the assertion to the specific guard wrapping the RPC call rather than to
"any occurrence of the pattern before this point" — e.g. capture the smallest enclosing
`if (...) {` immediately preceding `consume_quota(` (a bounded backward scan to the nearest
un-closed `if (`) and assert *that* condition is `!hasPro`, or assert there is exactly one
occurrence of the literal `if (!hasPro) {` in the whole file and that it is within N lines of
`consume_quota`.

status: accepted

### Finding 3 — P1 — the new test's SCOPE comment claims a live-behavioral counterpart exists; it does not, and the plan's own mandated pre-deploy verification step appears unexecuted

**Claim under test:** `test/contracts/weekly_report_lifetime_meter_test.dart:10-14`: *"The
behavioural half is `test/sql/oi46_daily_cap_triggers_live_verify.sql`'s `slice3a_*` labels plus a
branch-deployed read-path check — see the plan's §5."* This is a present-tense factual claim that
a specific artifact exists.

**Verification:**
```
$ git diff main...HEAD --stat -- test/sql/
(no output — the file is not touched by this diff at all)

$ grep -ni "slice3a" test/sql/oi46_daily_cap_triggers_live_verify.sql
(no matches)

$ grep -ni "weekly_report" test/sql/oi46_daily_cap_triggers_live_verify.sql
(no matches)
```
The cited file is 573 lines, entirely about OI-46's chat/vision/food_text triggers (migrations
111-114); it has never mentioned weekly-report or OI-162 slice 3a. The plan itself
(`docs/audit/oi162-slice3-plan.md` §5) specifies the missing half precisely: extend that file with
`slice3a_*` assertions (limit-1-not-5, epoch survives cleanup, PRO consumes nothing), **and** a
branch-deployed real-auth-session read-path check, because (round-7 finding 3, same plan)
`weekly-report` calls `supabase.auth.getUser(token)`, so a rolled-back SQL transaction alone
cannot exercise the actual read path the deployed function uses. §6 step 3 orders this explicitly
**before** the B-pass and before any deploy. Neither artifact exists in this diff, and
`list_branches` on `dedsavbjuwgarrhphgnl` shows no preview/dev branch (only the persistent `main`
entry), so no branch-deployed check appears to have run either.

The diagnose-doc's own "Verified live, not argued" section and its 9-row mutation table
correspond only to source-grep assertions plus one direct rolled-back-transaction SQL check
(consume/consume/absent/epoch) — the same shape I independently reproduced myself against
production this session — not to the plan's `slice3a_*` live-harness extension or the branch/app
read-path check.

**What this does and doesn't mean for risk:** I independently closed most of the substantive gap
myself this session — a live rolled-back-transaction cycle against `dedsavbjuwgarrhphgnl`
(absent→1→1→-1→survives-cleanup, using a real user id) and a read of the actual pinned
`postgrest-js` source confirming `.maybeSingle()`'s 0-row GET behavior — so I have no reason to
believe the underlying mechanics are wrong. But that is *my* verification, done today, informally,
outside the repo's checked-in test suite; it is not what the plan required as a checked-in,
re-runnable artifact, and the comment's claim that it already exists is false. Given this repo's
own precedent for exactly this shape of finding (Tuning history, 2026-09-05: *"TRACKING DOCS THAT
ATTEST TO THEMSELVES… every code lens passed; the batch would still have failed [the merge gate]"*
— here no gate reads this specific comment, so nothing mechanically fails, but the same failure
mode of an unearned claim of coverage applies).

**Suggested fix:** either actually extend `test/sql/oi46_daily_cap_triggers_live_verify.sql` with
the planned `slice3a_*` block and perform the branch-deployed read-path check before deploy (per
§6 step 3), or correct the test file's SCOPE comment to state plainly that the live-behavioral
verification described in the plan was not executed as a checked-in artifact, and that the gap is
consciously accepted (with a reason) rather than implied-closed.

status: accepted

### Finding 4 — P2 — the `reportLogError` log message is now false: a failed insert no longer keeps the gate open

**Claim under test:** `supabase/functions/weekly-report/index.ts` (report-log insert failure
branch) still logs: *"report-log insert FAILED for user=… — the first-free-report gate stays open
until this is fixed."* This was accurate pre-fix (the insert WAS the sole writer the count read).
It is not accurate post-fix.

**Verification:** the `consume_quota` call immediately below is gated only on `!hasPro` — it is
NOT conditioned on `reportLogError`:
```
$ sed -n '634,679p' supabase/functions/weekly-report/index.ts
```
shows the insert, its `if (reportLogError) { console.error(...) }` block, and then unconditionally
(for `!hasPro`) the `consume_quota` call, with no branch on `reportLogError` in between. So on an
insert failure the ledger still advances (assuming `consume_quota` itself succeeds) — the gate
**closes** exactly as normal; what is actually lost is the persisted report row (and, per the
surrounding comments, the reinstall-restore copy). The log message describes the opposite failure
mode from the one that can now actually occur.

**Suggested fix:** reword to something like *"report-log insert FAILED for user=… — the ledger
still advanced, so this user's one free report is now spent with no persisted copy; it cannot be
regenerated and will not survive a reinstall."*

status: accepted

### Finding 5 — P2 — `consume_quota` is not gated on the insert's own success, reproducing the exact failure the insert-before-consume ordering exists to prevent

**Claim under test:** the code's own comments justify running the insert *before* `consume_quota`
specifically to avoid "consume-then-insert-fails," which "permanently burns a LIFETIME unit AND
loses the row." But `consume_quota` runs unconditionally on `!hasPro` regardless of whether the
insert immediately above it succeeded or failed (see Finding 4's citation) — there is no
`if (!reportLogError)` anywhere in the block.

**Verification:** read `supabase/functions/weekly-report/index.ts:634-679` directly; confirmed no
variable named `reportLogError` (or any check on it) appears between the insert and the
`consume_quota` call. So the sequence "insert fails independently (e.g. transient PostgREST
error) → consume_quota independently succeeds" produces **the identical outcome** the ordering was
chosen to avoid: a lifetime unit burned and the report row permanently lost (no retry path exists,
since `isFirstReport` will read `false` on every future call). The insert-before-consume ordering
only protects against the *reversed-order* failure; it does nothing about the *independent-failure*
case, because the second write isn't conditioned on the first write's outcome.

This also cuts against the design's own stated philosophy elsewhere ("a denied report is
recoverable, an unbounded Gemini 2.5 Pro call is not" — i.e. prefer under-granting to over-
committing): the current code over-commits the ledger relative to what was actually persisted.

**Suggested fix:** gate the `consume_quota` call on `!reportLogError` as well as `!hasPro` (skip
the consume when the insert failed — the user still received the report in the HTTP response this
one time, and the next call will correctly re-grant since the ledger never advanced), or
explicitly document this as an accepted residual risk the way the diagnose-doc already documents
the "two simultaneous first-ever requests" residual in `impact_analysis`.

status: accepted

### Finding 6 — P3 — the new SKILL.md lens-8 entry is inserted out of its own numbered order

**Claim under test:** `.claude/skills/code-review/SKILL.md`'s lens 8 (`asserted_fixture_value`)
now reads, in this order: *"The sharper question…"* → **"Third question, added 2026-09-06"** →
**"Second sharper question, added 2026-09-05."** The new paragraph is inserted between the
unlabeled first question and the pre-existing "Second sharper question," but is itself labeled
"Third."

**Verification:**
```
$ sed -n '95,155p' .claude/skills/code-review/SKILL.md
```
confirms the literal reading order: unlabeled question, then "**Third question, added
2026-09-06**", then "**Second sharper question, added 2026-09-05**" — "Third" textually precedes
"Second." (The substance of the new paragraph is accurate and consistent with the diagnose-doc's
round-6 near-miss; only the ordinal label/position is wrong.)

**Suggested fix:** either move the new paragraph after "Second sharper question" (making it
correctly the third in reading order) or relabel it to avoid implying a fixed reading sequence.

status: accepted

## Lenses returning clean

- **`missing_input`** (the absent-row path, attacked hardest per the brief): confirmed live
  against `dedsavbjuwgarrhphgnl` that `usage_counters` exists with the exact columns/PK migration
  128 declares, that `consume_quota`'s live `pg_get_functiondef` is byte-identical to migration
  128's source, that zero rows currently exist for `quota_key='weekly_report_free'`, and that
  `'epoch'::timestamptz = '1970-01-01T00:00:00+00:00'::timestamptz` is `true`. Ran a full
  `BEGIN…ROLLBACK` cycle against a real user id: absent read → `used` NULL; first `consume_quota`
  → `1`; the reader's exact filter shape then finds `used=1`; second `consume_quota` → `-1`; the
  row survives the `cleanup_usage_counters()` predicate. Zero residue after rollback (`rows_left:
  0`). Fetched the pinned `postgrest-js@^1.9.0` source directly: for a GET request, `.maybeSingle()`
  sets `Accept: application/json` (not the singular-object header) and post-processes client-side —
  0 elements → `data: null` with no server error, 1 element → unwrapped, >1 elements → a
  client-synthesized `PGRST116` (impossible here: the query's own PK guarantees ≤1 row, and the
  subscription query separately caps at `.limit(1)`). So there is no path by which an absent row
  reaches the error/fail-closed branch — confirmed from the client library's actual algorithm, not
  from the code comment's assertion of it. `hasPro`'s possible shapes were also checked: `.
  maybeSingle()`'s same normalization means `subscription` can only ever be `null` or a plain
  object (never an array, never `undefined`), so the "every shape" concern in the brief resolves to
  exactly the two shapes the existing (unchanged-by-this-diff) `hasPro = subscription && !subError`
  expression already handles correctly.
- **`blast_radius_mismatch`**: `git diff main...HEAD --name-only | dart run
  scripts/blast_radius_from_diff.dart -` → `platform`, matching the task and the diagnose-doc.
  (Near-miss worth recording: my first attempt used `--stdin`, an argument this script does not
  recognize, which silently fell through to "arbitrary file list" mode and misreported `feature` —
  the documented positional-mode trap, hit via a different wrong invocation than the one
  `feedback_mistake_blast_radius_positional_mode.md` names. The plan-review record for this same
  branch independently documents hitting a sibling variant of the same trap. Classifying each
  changed file individually shows only `supabase/functions/weekly-report/index.ts` and
  `supabase/functions/CLAUDE.md` drive the `platform` tier; nothing in the diff is catastrophic
  (no migration, no `SECURITY DEFINER`, no RLS/auth/payment-core change).) No explicit rollback
  section exists in the diagnose-doc, but there is no migration to roll back and the standard
  SHA-pinned Edge-Function redeploy is the repo-wide mechanism for this class of change.
- **`stale_or_wrong_citation`** (all file:line citations in the diff, beyond Finding 3):
  `reports_screen.dart:47` (`_reportCacheKey`, single Hive key, not a list — confirmed alongside
  `:48`'s date key and the single `get`/`put` call sites at `:72-73`/`:144-146`);
  `sync_coach.dart:178-181` (`.from('ai_coach_interactions')`/`.eq('user_id', userId)`/
  `.gte('created_at', since)`, no channel filter — confirmed exact line numbers via grep);
  `ai-media-proxy/index.ts:74` and `:96` (both `count: "exact", head: true`); `ai_coach_repository.
  dart:279` (`getFreeImageAnalysisCount`); `delete-account/index.ts:146` and `verify-payment/index.
  ts:225` (same count shape); migration `128:69` (`consume_quota` definition). All eight citations
  are exact. `related_bugs: [d3a7f1, e7c4b2, e4d1b7, c9e3b1]` plus `c8f229`/`9d12af` in the
  contract-test header all resolve to real, thematically-matching diagnose-docs. The
  "Six readers → five" board-progress note matches the diagnose-doc's own 6-entry `readers:` list
  minus the one this batch fixes. `docs/sot_registry.yaml`'s `weekly_report_pro_gate` entry gates
  clean (`check_sot_registry_completeness.dart`, `check_sot_registry_parity.dart`,
  `check_sot_behavioral_test_paths.dart` all PASS); `docs/diagnoses/INDEX.md` and
  `docs/audit/OPEN_INDEX.md` are both byte-identical to a fresh regeneration
  (`build_bug_index.dart`, `build_oi_index.dart` — `git status --porcelain` empty after each).
- **`writer_reader_drift`** (the shipped code, as opposed to its tests — see Findings 1/2 for the
  *tests'* blind spot): in the CURRENT committed source, writer (`consume_quota` call, `p_quota_key:
  WEEKLY_REPORT_FREE_QUOTA_KEY`) and reader (`.eq("quota_key", WEEKLY_REPORT_FREE_QUOTA_KEY)`) both
  route through the same TS constant, so they cannot currently drift; `window_start` likewise uses
  the same `LIFETIME_WINDOW` literal on both sides. Confirmed no pre-existing Postgres trigger on
  `ai_coach_interactions` fires for `channel='weekly_report'` (all three migration-129 triggers
  short-circuit on other channel values), so there is no double-consumption of the ledger from an
  unrelated trigger.
- **`guard_without_its_mirror`** (the two-call non-atomicity, beyond Findings 4/5): enumerated all
  four insert/consume outcome pairs. Insert-succeeds/consume-succeeds and insert-succeeds/consume-
  fails match the documented, accepted "under-count, recoverable" behavior exactly. The two
  simultaneous first-ever-requests race is explicitly named and accepted in the diagnose-doc's
  `impact_analysis` as a bounded, one-time, ever residual — reasonable given the alternative
  (consuming before the Gemini call) burns a lifetime unit on a model-outage with no refund path.

## Owed, not mine to add

Per this task's instructions: `check_skill_tuning_history.dart` will require a same-dated entry
appended to `.claude/skills/code-review/SKILL.md`'s Tuning history in whatever commit adds this
review file — not added here, left for the orchestrating session.

## Founder triage notes

All 6 accepted, 0 false alarms, all fixed in this batch (§4.2) — no follow-ups spawned.

- **F1 / F2 (inert tests).** Rewritten as ASSOCIATION and CONTAINMENT respectively, then the
  reviewer's OWN two mutations were re-run against the fixes. **F1 reddened. F2 DID NOT** — the
  first fix used a proximity check (`consumeIdx - guard.end < 200`), which the decoy defeats just
  as thoroughly as the original, because a decoy sits *close* to the call by construction.
  Re-fixed as "no other `if (` between the guard and the RPC"; both now redden. That near-miss is
  the tuning entry below.
- **F3 (false SCOPE claim).** Made TRUE rather than deleted: three `slice3a_*` assertions added to
  `test/sql/oi46_daily_cap_triggers_live_verify.sql`, run live (3/3 `ok`), and the retention
  pairing mutation-proven on both halves. The header now also states plainly what they do NOT
  cover — they execute no Edge Function and would pass against the pre-slice-3a code.
- **F4 (false log message)** corrected. **F5 (consume not gated on the insert)** — real logic gap;
  `if (!hasPro)` → `if (!hasPro && !reportLogError)`, mutation-proven.
- **F6 (lens order)** swapped so "Second" precedes "Third".

The reviewer's own closing note — that the tuning-history entry was owed and deliberately not
added by the review — was correct and is honoured in the same commit as this file.
