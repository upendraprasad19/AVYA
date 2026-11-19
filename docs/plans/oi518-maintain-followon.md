# OI-518 follow-on: three founder decisions on the Maintain callout (founder, 2026-11-19)

Branch `oi518-maintain-followon`, revision 4 (plan-review rounds 1 to 3 applied, section 7). Tier M (§4.12.6: the diff leaves
`lib/features/{home,train,nutrition,profile}/**` for the shared rule in `lib/features/onboarding/target_weight_check.dart`).
Blast radius `account` (same paths as OI-518, `docs/blast_radius.yaml:432` and `:670`). Execution mode (§4.12.7): inline, one
worktree; subagents only for plan review and the B-pass (at most 2 at a time, Sonnet, context-blind). No migration, no Edge
Function, no stored key, no schema, no kill switch (§4.6 not triggered; rollback is a revert of the PR). Builds on OI-518 (PR #301,
diagnose `8b48f1`, plan `docs/plans/oi518-maintain-callout.md`); the three items below were its "accepted residue", put to the
founder on 2026-11-19.

## 1. Founder decisions (2026-11-19)

1. **Fractional target label: leave as is.** The new Maintain line keeps one decimal for a fractional target (`74.8 kg`); the chart
   label and the other surfaces keep `toStringAsFixed(0)`. NO code change; the diagnose doc's residue bullet becomes a decision.
2. **Old last weigh-in: add "as of <date>", Maintain only.** When the last weigh-in is MORE than 7 days old, both Maintain lines end
   with ` · as of 3 Nov` (the year is added only when it differs from this year's: ` · as of 28 Dec 2026`). Cut and Build lines are
   unchanged. (The stale off-target line therefore reads `... adjust your nutrition to hold the line · as of 18 Nov`, two separators;
   founder-visible wording, accepted.)
3. **Half-week rule: Maintain skips it.** The `weeksDiff < 0.5` history gate no longer applies to a Maintain goal: the line shows as
   soon as the card has two weigh-ins (the card's own empty state, `filtered.length < 2` in `reports_screen.dart`, is unchanged).
   Cut and Build keep the gate. Real data holds one weigh-in per IST date (`HealthWriteService.logWeight` writes the key
   `weight_<istDate>`, `health_write_service.dart:174`), so the smallest real gap is one day (`weeksDiff` 0.143); a `weeksDiff` of
   0 is a synthetic test input only.

## 2. Writers and readers (named before the change)

No writer changes (`primary_goal`, `target_weight_kg` and the `weight_<istDate>` entries are written exactly as in OI-518). Readers:
`target_weight_check.dart` `projectionCalloutKind` (the gate, line 135 after OI-518), `weight_projection_callout.dart`
`WeightProjectionCallout._onTargetRow` / `_offTargetRow` (the lines) and `WeightProjectionLine` (forwards `now`), copy in
`weight_callout_copy.dart`. The staleness reads the entry's own `date` string (an IST date key) and "today" through the IST helpers
in `lib/core/utils/ist_date.dart` (`istDateStr`, `nowWall` at `:65`, §4.5 "IST throughout"), never `DateTime.now()` arithmetic on a
local-time date. `getWeightEntries` (`nutrition_repository.dart:50-68`) returns the raw entries ascending by `date`, so `entries.last`
is the newest real weigh-in.

Bug-history check (§4.1.5): not a bug fix; three product decisions on the OI-518 card. Related: `8b48f1` (its residue list is
amended here), `b5d2e8`.

## 3. Units

**U1. The rule (`lib/features/onboarding/target_weight_check.dart`, pure).** The history gate becomes
`if (weeksDiff < 0.5 && goal != 'general_fitness') return ProjectionCalloutKind.none;` (the literal `validateTargetWeight` and the
Maintain branch use). Everything else is untouched: the Maintain branch still judges the LAST weigh-in by the 3.0 kg window and
returns `none` for a missing target or weight; Cut / Build / unruled goals keep the gate and every later line byte-identical (the
new expression equals the old one for every non-Maintain goal, and for Maintain at `weeksDiff >= 0.5`). The Maintain branch never
reads `weeksDiff`, so 0, a negative value, NaN or infinity cannot change its result (entries are sorted ascending, so a negative
value cannot occur in real data). Doc comments on `projectionCalloutKind` and the file header say the Maintain branch has no
history gate.

**U2. The words (`lib/core/copy/weight_callout_copy.dart`).** New pure
`WeightCalloutCopy.asOfSuffix({required DateTime lastDay, required DateTime today})` returning ` · as of D Mon` (a space on each
side of U+00B7, written as the escape; day without a leading zero; a three-letter English month from the copy file's OWN 12-name
list, because the copy file may not import `lib/features`; the year appended as ` D Mon YYYY` only when `lastDay.year !=
today.year`). It reads ONLY the `.year`, `.month` and `.day` components of its arguments (no `toLocal` / `toUtc`); `today` supplies
only its `.year`. Both are calendar DATES (the caller passes the IST dates, built from the `YYYY-MM-DD` keys). A `lastDay` after
`today` is undefined: the caller never passes one (it filters future dates). `onTargetLine` / `offTargetLine` are unchanged (the
suffix is appended by the widget), the copy file keeps no `lib/features` import and no `toStringAsFixed`.

**U3. The widget (`lib/features/profile/widgets/weight_projection_callout.dart`).**
- New import `package:icanbefitter/core/utils/ist_date.dart` (`istDateStr`, `nowWall`; `package:` path per rule 15).
- `const int kMaintainStaleAfterDays = 7;` and TWO pure top-level functions; the widget calls ONLY the second, and the pure tests target
  these same functions (no copy of the logic lives in a test):
  - `DateTime? parseDateKeyUtc(String key)`: matches the anchored `^(\d{4})-(\d{2})-(\d{2})$`, builds `DateTime.utc(y, m, d)` and returns
    null unless the components round-trip (so `2026-02-31` and `20261118` are null, never rolled into March). Rejected alternatives,
    named: `DateTime.tryParse` (local midnight) and the near-duplicates `day_swap_rules.dart:43` `utcDate` (throws on garbage) and
    `compass_form_sheet.dart:52` `utcDateFromIstDateStr` (no validation).
  - `String maintainAsOfSuffix({required String lastDateKey, required DateTime now})`: the WHOLE decision, derived once. `today =
    parseDateKeyUtc(istDateStr(now))` (the IST date of the instant `now`, local or UTC, per `ist_date.dart:94`; `istNow()` is never
    used, OI-494), `lastDay = parseDateKeyUtc(lastDateKey)`; returns `''` when either is null or `today - lastDay` in whole days is not
    greater than `kMaintainStaleAfterDays` (so a future date and a 7-day-old one are `''`, an 8-day-old one is stale); otherwise
    `WeightCalloutCopy.asOfSuffix(lastDay: lastDay, today: today)`. The age and the year rule read the same `today` by construction.
- `build` computes the suffix ONCE, only for the Maintain kinds: `final asOf = (kind == onTarget || kind == offTarget) ?
  maintainAsOfSuffix(lastDateKey: last['date'] as String? ?? '', now: now ?? nowWall()) : ''`, and passes `asOf` to `_onTargetRow(lastW,
  asOf)` / `_offTargetRow(lastW, asOf)`, which append it to their text. The clock is `now ?? nowWall()` (the test-clock seam, a plain
  wall clock, not UTC-flagged); the eta branch keeps its own `now ?? DateTime.now()` unchanged, so Cut / Build output is byte-identical.
- The ONE string `last['date'] as String? ?? ''` feeds both the existing local `DateTime.tryParse` (for `weeksDiff`) and the new
  `parseDateKeyUtc`. Real keys are always `YYYY-MM-DD` (`logWeight` writes `istDateStr`, `sync_health.dart:477-486` copies the Postgres
  `date`), so the two agree; a key that `tryParse` accepts and the strict parser rejects (`20261118`, `2026-11-18T10:00:00`, and
  `2026-02-31`, which `tryParse` rolls to March 3: confirmed by a scratch run) draws the line WITHOUT a suffix, deliberately safe. A key
  `tryParse` rejects draws nothing at all (the existing `not-a-date` behaviour, unchanged).
- The widget builds no `YYYY-MM-DD` key from date components (`check_local_date_key_drift.dart`) and computes no `(weight - weight)
  .abs()` (`projection_gate_single_source_test.dart`). `WeightProjectionLine` already forwards `now`; the screen's call is unchanged and
  stays pinned.

## 4. Tests (§4.4 rules 21 and 24)

Clocks. The behavioural test file keeps `_now = DateTime(2031, 3, 5)` as the DEFAULT clock for every non-Maintain test (the eta row
needs it for "Apr 2031"; the stale Cut / Build rows then double as negative controls for "no suffix on Cut / Build"), and adds
`_freshNow = DateTime.utc(2026, 11, 19, 6)` (the day after the last weigh-in) for the Maintain tests. `_Fixture` has a const
constructor and a `DateTime` is not a constant, so it gains a const `bool fresh = false` field; `_pump(tester, f)` pumps with
`f.fresh ? _freshNow : _now`; the Maintain table rows are `const _Fixture(..., fresh: true)`; `pumpLine` in the `WeightProjectionLine`
group takes `{bool fresh = false}` and the Maintain tests (`a Maintain profile reads...`, `an int target`, `the LAST entry decides`,
the padding test) pass `fresh: true`, while the Cut 'Apr 2031' test, the `build_muscle` and no-goal tests, and the 'no target (absent, 0)
or fewer than two weigh-ins draws nothing' test (it asserts nothing is drawn, so either clock works) keep the default. The narrow-width
test and every test in the `Maintain` group use `fresh: true`. A helper `_entriesDated(first, last, {firstDate, lastDate})` builds
weigh-ins with chosen date keys (the existing `_entries` hard-codes 2026-11-04 / 2026-11-18). Only `DateTime.utc` instants are used for
the IST rows. The targeted files run under FOUR zones: `TZ=Asia/Kolkata`, `TZ=UTC`, `TZ=Etc/GMT+12` and `TZ=America/New_York` (the
last has a DST change inside the pinned pure rows).

- `test/onboarding/target_weight_check_test.dart`:
  - The row `m(75, 75, 0.4, 75)` and its test name ("the history gate sits ABOVE the Maintain branch", lines 286-289) are REWRITTEN:
    renamed "Maintain has no history gate"; weeks 0.4 and weeks 0 give `onTarget` in the window and `offTarget` beyond it, and a
    missing target or weight at weeks 0 stays `none` (new rows).
  - NEW Cut and Build rows at the boundary: `k('lose_fat', 80, 79, 0.5, 70)` is `eta` and the Build mirror
    (`k('build_muscle', 75, 76, 0.5, 80)`) is `eta` (these pin `<` against `<=` and the 0.5 literal); the existing 0.4 Cut row (line
    214) stays; an unruled goal keeps the gate with a fixture that is NOT `none` when ungated: `k('recomp', 75, 76, 0.4, 80)` and the
    `''` goal are `none`; and a Build row at weeks 0.4, `k('build_muscle', 75, 76, 0.4, 80)` is `none` (kills a Build-only exemption
    that the 0.5 row cannot see).
- `test/contracts/weight_callout_copy_test.dart`: `asOfSuffix` exact strings built from `const _dot` (never a copy of the production
  literal): a single-digit day (`3 Nov`), a two-digit day (`18 Nov`), the year rule at a boundary (`28 Dec 2026` for today 2027-01-10),
  a same-year pair with differing months (2026-03-03 against 2026-11-26: no year) and a different-year pair with the same month
  (2025-11-18 against 2026-11-26: year), a far-future `today` (2031) so the row does not depend on the wall year, and a loop over ALL
  12 months (day 15) against the expected names; the existing line strings are re-asserted unchanged.
- `test/contracts/maintain_weight_callout_behavioral_test.dart` (besides the clock restructuring above):
  - The existing test 'two weigh-ins under half a week apart draw nothing, even in the band' (lines 299-314) is REWRITTEN: two Maintain
    weigh-ins one day apart (`2026-11-17`, `2026-11-18`, `_freshNow` injected) DRAW the line; the same two weigh-ins for a Cut still draw
    nothing, and so do two Build weigh-ins one day apart; a synthetic same-day Maintain pair draws the line (stated synthetic).
  - NEW staleness rows, each for BOTH `onTarget` and `offTarget` (last weigh-in `2026-11-18` unless stated): age 7 = no suffix; age 8 =
    ` · as of 18 Nov`; a year change (last `2026-12-23` with `now = DateTime.utc(2026,12,31,19,0)` (IST 2027-01-01): `as of 23 Dec
    2026`, which fails if the year is read from `now.year`); the IST day (`now = DateTime.utc(2026,11,25,19,0)` is IST 11-26 so the age
    is 8, while the UTC date would say 7); the double-shift guard (`now = DateTime.utc(2026,11,25,14,0)` is IST 11-25 19:30, age 7, no
    suffix; reading `istDateOf` twice gives 11-26 and a suffix); a future-dated last weigh-in at least 8 days ahead (last `2026-12-05` under `_freshNow`; 1 to 7 days ahead would give `''` even with an
    `.abs()` mutant) draws the line WITHOUT a suffix; keys that
    the local `DateTime.tryParse` ACCEPTS but `parseDateKeyUtc` rejects (these rows pump with a STALE injected clock,
    `now = DateTime.utc(2026,12,1)`, so a lenient parse would yield `as of 18 Nov` and the strict one yields no suffix; under `_freshNow`
    the lenient keys would be 1 day old and prove nothing) (`20261118`, `2026-11-18T10:00:00`, and `2026-02-31`; the key is the LAST entry, the first stays `2026-11-04`; a scratch Dart run on 2026-11-19
    confirmed `tryParse` accepts all three, rolling `2026-02-31` to March 3) draw the line WITHOUT a
    suffix, and the existing `not-a-date` row still draws nothing; stale Cut rows (eta, adjust, reached) and a stale Build row show NO
    suffix (the `_now` default clock makes them stale); a stale Maintain line wraps at 320 px; `WeightProjectionLine` forwards `now` (a
    stale Maintain line through the profile map).
  - A pure pin of `parseDateKeyUtc` and `maintainAsOfSuffix`: null for `''`, a non-date key, `2026-02-31`, `20261118`, `2026-11-18x`,
    ` 2026-11-18`, `12026-11-18`, `2026-12-32`, `2026-13-01`, `2026-00-10`, `2026-04-31` (kills a dropped anchor and a one-component
    round trip); `maintainAsOfSuffix` is `''` for a future date at least 8 days ahead, for age 0, 1 and 7 and an unparseable key, and flips at the IST
    midnight (`now = utc(2026,11,25,18,29)` gives `''`, `utc(2026,11,25,18,31)` gives ` · as of 18 Nov`, which kills a hand-rolled
    +5:00 or +6:00 offset), and the suffix for age 8, a
    month end and a year end; a UTC-flagged and a local `now` give the same result; under every zone the DST row `('2026-03-01',
    now = DateTime.utc(2026,3,9,12))` has age 8 (measured 2026-11-19: `DateTime(2026,3,9).difference(DateTime(2026,3,1)).inDays` is 8 under Asia/Kolkata and 7 under
    `America/New_York`, so a local-midnight difference goes red there).
- Mutations (run and recorded, `grep -c` confirms each applied, a compile error is not a kill; the mutation set runs under the four
  zones where it concerns time): (a) the Maintain exemption removed; (b) the exemption applied to every goal; (c) keyed on a different goal test: `goal != 'lose_fat'` and `goal != 'build_muscle'` (a Build-only or Cut-only exemption); (d) `> 7` to `>= 7`; (e) `> 7` to `> 8`; (f) "today" taken from the UTC components of `now`, from `now.toLocal()`
  (the "local components" variant: for a UTC-flagged instant plain `.year/.month/.day` already IS the UTC variant), from
  `DateTime.now()`, from a hand-rolled +5:00 / +6:00 offset, from a DOUBLE IST shift (`istDateStr(istDateOf(now))`), and the ages taken as a local-midnight difference
  (each variant reported per zone; a variant equal to IST in one zone is reported equivalent there, not as a kill); (g) the suffix dropped from `_offTargetRow` only and from `_onTargetRow` only; (h) the suffix applied to a Cut /
  Build row (each of `eta`, `adjust`, `reached`); (i) the year rule inverted, compared on month, and read from `now.year`; (j) one
  month name swapped, and the list off by one; (k) a future date shows the suffix (the `.abs()` on the age); (l) `now` ignored in the
  staleness read (the same code change as "today from `DateTime.now()`" in a test, reported once) and `WeightProjectionLine` drops `now:`; (m) the staleness read from `entries.first`; (n) the leading zero kept; (o) the
  separator changed; (p) the history gate `<` to `<=`, and its literal 0.5 to 0.6; (q) `lastDay` / `today` swapped in the suffix call; (r) one anchor of the key regex dropped, and the round-trip check reduced to the day only, the month only, or the year only
  (killed by `2026-13-01`, `2026-04-31`, `2026-02-31` and `2026-00-10`; DROPPING the year comparison alone is EQUIVALENT, a roll that
  keeps month and day cannot exist); (s) is not a mutant: computing the suffix for a Cut / Build kind changes nothing observable,
  because only the two Maintain rows read `asOf` (mutant h is the real "Cut / Build gets a suffix" case); (t) `lastDay.year < today.year` for `!=` is EQUIVALENT while the caller never passes a
  future `lastDay`, and is reported so.
  Each non-equivalent mutant must redden at least one test; one that reddens nothing is reported as such.

## 5. Docs and ledgers

- `docs/diagnoses/2026-11-18-weekly-report-maintain-callout-8b48f1.md`: the "Accepted residue" bullets for the chart-label mismatch
  (lines 142-144), the history gate (149-151, which also holds the sentence "one history rule") and the stale last weigh-in (152-154)
  become founder DECISIONS (2026-11-19) naming this branch; the other bullets stay. Statements that describe the old design are
  amended: `proposed_fix` (line 65, "decides Maintain right after the history gate"), the mutation table's rows f and j (row f at line 124: "Maintain branch moved above the history gate" is now the shipped design; row j,
  the gate `<` to `<=`, is now killed by the new Cut / Build 0.5 rows, not the Maintain row) (the former text on row f: "Maintain
  branch moved above the history gate" is now the shipped design, not a mutant), and the frontmatter `ist_handling` ("no date key is
  written or compared; the date sentence keeps DateTime.now()", false once the staleness reads the IST date); the `readers` `line:`
  numbers are re-anchored after the edit. A short pointer says this follow-on carries its own mutation list. No new diagnose doc (a `feat` commit; the commit-msg
  and Gate 10 subject tests match only `fix|bug|regression`). The edited doc must still pass `dart run scripts/validate_diagnose_doc.dart`.
- The file header of `target_weight_check.dart` (lines 18-27) and the doc comment on `projectionCalloutKind` (121-127) say the Maintain
  branch has no history gate; the copy file's header and the widget's header mention the staleness suffix. Comments and string literals
  in the copy file contain neither `features/` nor `//` (the source pin strips at `//`).
- `lib/features/profile/CLAUDE.md` row `goal_target_weight_agreement` and `lib/features/onboarding/CLAUDE.md:122`: the Maintain
  sentence says "no history gate" and "a last weigh-in older than 7 days reads `as of <date>`". `docs/sot_registry.yaml` reader
  semantic for `WeightProjectionCallout` says the same (no `line_range` rows for this concept).
- `docs/naming_conventions.md` §8: the `WeightCalloutCopy` row gains `asOfSuffix` (it lives in the copy file); a NEW row, placed
  directly under the last row and above the horizontal rule, names `kMaintainStaleAfterDays`, `parseDateKeyUtc` and `maintainAsOfSuffix`
  (they live in `weight_projection_callout.dart`). Collision grep for each symbol first.
- Plan-review record `docs/plan-reviews/oi518-maintain-followon.md` (`review_rounds` truthful, `ground_truth_verified: true`,
  `verdict: converged`, and at the merge `bpass: accepted` with `bpass_review:` naming a committed review whose `verdict: accepted`
  line is bare, with a `## Tuning entry`).
- `docs/audit/open_issues.md`: the device check has no board home yet (the OI-518 closed entry points at a "board row" that was never
  added). Add ONE row to the OI-348 device-check list after A21 (`open_issues.md` around line 5416, same shape as A21): OI-518 + this
  follow-on, after `/build-apk`: a Maintain profile inside / beyond the band (falling and rising), a last weigh-in 8 or more days old
  (`as of <date>`), two weigh-ins one day apart (the line shows), a Cut profile with a whole target unchanged; the window must be 1M or
  All (1W drops entries older than 7 days, `reports_screen.dart:751`).
- No OI is minted (the three items were residue of a closed OI, decided now). The commit body carries no `closes-oi:` text. Context-
  artifact budget: `dart run scripts/check_context_artifact_budget.dart` after the doc edits.

## 6. Verification

Whole-project `flutter analyze --no-fatal-infos`, the pre-commit gate loop, targeted tests under the four zones, commit through
`scripts/safe_commit.sh`, PR, `sh scripts/land_pr.sh <pr> --ci-only`, `/code-review` (B-pass, two fresh seats, the mutation seat
after the first seat's fixes) on `ci-green`, the founder's merge go, then `sh scripts/land_pr.sh <pr>`. Device check (the founder, with
the next `/build-apk`, together with the OI-518 check already open): a Maintain profile whose last weigh-in is 8 or more days old (the
line ends `as of <date>`), one with a fresh weigh-in (no suffix), and two weigh-ins one day apart (the line shows; before this change
it did not).

## 7. Findings and where each landed

### Round 1 (two reviewers, revision 1)

| # | Sev | Finding | Landed in |
|---|---|---|---|
| A1 | P1 | no Cut / Build row at exactly 0.5; the only boundary row was the Maintain one this change removes | section 4: new `eta` rows at 0.5, mutation p |
| A2 | P1 | list of rewritten rows incomplete; weeks 0 / 0.4 rows are new; the test name becomes false; the behavioural 'under half a week' test inverts | section 4 rewritten rows named |
| A3 | P1 | unruled-goal fixture must not be `none` when ungated | section 4 `k('recomp', 75, 76, 0.4, 80)` |
| A4 | P1 | `asOfSuffix` underspecified (components, `today` only for the year, future date, own month list, missing month and year mutants) | U2, section 4 |
| A5 / A6 / A7 | P2 | separator literal; two separators on the off line; same-day weigh-ins are synthetic; stale diagnose statements | section 1, section 5, U1 |
| B1 | P1 | clock restructuring incomplete (`_pump`, the table loop, `pumpLine`) | section 4 "Clocks" |
| B2 | P1 | 'under half a week' test named, and it must inject `now` | section 4 rewritten rows |
| B3 | P1 | mutation (f) needs three zones; zone-dependent local instants | section 4 "Clocks" and mutation f |
| B4 | P2 | `nowWall` cite; UTC-date parsing helper; invalid dates; `20261118`; IST year in the suffix | U3, section 4 |
| B5 | P2 | missing mutants (`.abs()`, swapped args, `Line` drops `now`, `reached` row) | section 4 |
| B6 | P2 | naming conventions: symbols live in different files; diagnose bullets | section 5 |

### Round 2 (two fresh reviewers, revision 2)

| # | Sev | Finding | Landed in |
|---|---|---|---|
| C1 | P1 | "today" had no single home; `weighInAgeDays` returned an `int` only | U3: one pure `maintainAsOfSuffix`, the widget computes the suffix once and passes it to both rows |
| C2 / D4 | P1 | `_Fixture` is const; `now: _freshNow` does not compile | section 4 "Clocks": a const `bool fresh` field |
| C3 / D3 | P1 | an unparseable key draws nothing (existing test); the new row needs keys `tryParse` accepts and the strict parser rejects | U3 and section 4: the named keys, last entry only, scratch-run confirmation |
| D1 | P1 | the double IST shift survived | section 4: a 14:00Z row and mutation f variant |
| D2 | P1 | local-midnight difference equivalent in the three zones; the "local components" variant is the UTC variant for a UTC-flagged input | section 4: a fourth zone (`America/New_York`) and a DST row; mutation f wording |
| C4 | P2 | missing `ist_date.dart` import | U3 |
| C5 / C6 / C7 | P2 | two parses of one key; separator style and source-pin traps; the 1W window | U3, section 5, section 6 |
| D5 / D6 | P2 | `_entries` hard-codes dates; the `parseDateKeyUtc` pin left anchor and per-component survivors | section 4 `_entriesDated`, the extra key rows, mutation r |
| D7 / D8 / D9 | P2 | diagnose amendment locations; no board home for the device check; budget | section 5 |

### Round 3 (one reviewer, revision 3)

| # | Sev | Finding | Landed in |
|---|---|---|---|
| E1 | P1 | the lenient-key rows need a stale clock or they prove nothing | section 4 (`now = utc(2026,12,1)`) |
| E2 | P1 | a future date must be at least 8 days ahead to catch an `.abs()` mutant | section 4 pure and widget rows |
| E3 | P1 | no Build row at weeks 0.4 (a Build-only exemption survived) | section 4 U1 rows and the Build one-day pair |
| E4 | P2 | three versus four zones | corrected |
| E5 / E6 / E7 / E8 | P2 | mutants (s) equivalent, (f) and (l) overlap, (c) ambiguous, (r) under-specified | section 4 mutation list |
| E9 | P2 | no IST-midnight boundary row (a +5:00 / +6:00 offset survived) | section 4 18:29Z / 18:31Z rows, mutation f |
| E10 | P2 | diagnose mutation row j attribution | section 5 |
