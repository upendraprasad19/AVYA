---
reviewed_at: 2026-10-25T19:30:00+05:30
staged_against: d7d0c22d
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 15
verdict: accepted
---

# Code Review (B-pass) - branch oi414-promo-no-gateway-retry (OI-414, a metered call must not be re-sent after a gateway 502/503/504)

Reviewed: the staged diff of the fix commit (16 files): `SupabaseService.callFunction` / `retryColdStart` (`spendsQuotaPerCall`, the early gate, the `_gatewayStatuses` set), the two call sites (`paywall_sheet.dart`, `day_swap_allowance.dart`), the three test files (an extended behavioural group, a real-HTTP forwarding test, a source-pin file), the registry, nested CLAUDE.md, architecture and glossary edits, the plan and the diagnose-doc `a6d2f9`. Three fresh Sonnet seats on three slices (A: wrapper and tests; B: call sites and the census claims; C: docs, governance and ledger); each brief stated an exhaustive command list (read-only git, file reads, named test files) and banned `dart run scripts/*`, the network and every database statement. I did not audit the seats' shell history. The seats reviewed staging hash `9b78023ae1f7` on base `d1292a79`; this file is named for the FINAL staged content (hash `eb8fea69c002`) after the fixes below and a fast-forward to `origin/main` `d7d0c22d` (nine commits, none touching the wrapper; `docs/sot_registry.yaml` auto-merged with disjoint hunks).

Severity count: P0 0 . P1 0 . P2 2 . P3 13. The three seats returned 18 items; three were the same finding found by two seats (A3 = C1, B2 = C2, B3 = C8), so 15 distinct findings are listed. No false alarms. (My in-session tally while triaging said 16: one finding was counted twice.)

**CLAUDE.md 4.6 reading (a compile-time call-site argument as the gate; rollback = revert or drop the argument; fallback = a lazily read Hive key).** No seat rejected it. Seat C (finding 9) required that it be STATED in the diagnose-doc, which now carries it. The author accepts the reading; the fallback is recorded in the plan if the founder rejects it at merge.

## Findings

## Finding 1 - P2 - missing_input / guard_without_its_mirror (seat A)
- **file:line:** `test/contracts/edge_function_cold_start_retry_behavioral_test.dart` group `OI-414 spendsQuotaPerCall`.
- **claim:** the tests name statuses 502, 503, 504, 400, 401, 500 and 0. A status added to the cold-start predicate later (520, 522) and a gate written as `&& !retryOn500` would both survive: no test sends an arbitrary status through a flagged call or combines the flag with `retryOn500` and a gateway status.
- **status:** accepted - fixed: T8 sweeps every status 100-599 on a flagged call (one attempt each, a stop event only for 502/503/504); T9 pins flag + `retryOn500` + 502 (one attempt and the event). Mutants M20 (520 added to `isColdStart` only) and M21 (gate also requires `!retryOn500`) are red.

## Finding 2 - P3 - asserted_fixture_value (seat A)
- **file:line:** `test/contracts/call_function_spends_quota_per_call_behavioral_test.dart` (control test).
- **claim:** the control test sleeps a fixed 2600 ms for a 2000 ms backoff (a slow machine flakes), the flagged test's 3 s timeout is tight, and a neighbouring file's `HttpOverrides` would answer instead of the loopback server.
- **status:** accepted - fixed: the control polls for the second request up to 6 s, the flagged test's timeout is 8 s, `HttpOverrides.global = null` in `setUp`.

## Finding 3 - P3 - writer_reader_drift (seats A and C)
- **file:line:** header of `call_function_spends_quota_per_call_behavioral_test.dart`; the plan.
- **claim:** both cite pin files (`promo_validate_rate_limit_writer_to_reader_test.dart`, `day_swap_allowance_writer_to_reader_test.dart`) that the batch did not touch; the pins live in the new `spends_quota_per_call_source_pins_test.dart`.
- **status:** accepted - fixed in the header and the plan.

## Finding 4 - P2 - writer_reader_drift (seat B)
- **file:line:** plan accepted property A7; `docs/sot_registry.yaml` `day_swap_allowance` description; diagnose-doc tier 2 and impact text.
- **claim:** the day-swap lag was described as "the server can lag the phone by one". It is one per failed call that did not reach the handler: a PRO user can reach limit+N swaps and a second device can swap past a free limit.
- **status:** accepted - fixed in the plan (A7), the registry description, the diagnose-doc (tier 2, impact, a stand-alone A7 bullet) and `supabase/functions/CLAUDE.md` row `day_swap_allowance (server half)`.

## Finding 5 - P3 - writer_reader_drift (seats B and C)
- **file:line:** `docs/naming_conventions.md` (`spendsQuotaPerCall` row), `docs/architecture/payment.md` rule 11.
- **claim:** both state a general rule ("a call that spends a unit per call sets the flag") while `create-razorpay-order` is deliberately unflagged and most other metered calls are open OIs.
- **status:** accepted - fixed: both name the flagged set (`validate-promo`, `consume-day-swap`), the deliberate exception and the ledger as the classification of the rest; the plan gains A8.

## Finding 6 - P3 - writer_reader_drift (seats B and C)
- **file:line:** `lib/core/services/supabase_service.dart` (`retryColdStart` `///` doc and the `callFunction` `//` comment; "stays visible"), `day_swap_allowance.dart`, `paywall_sheet.dart`, the glossary.
- **claim:** "EVERY call that reaches its handler" overstates (the limit stops the spend), the new parameter was undocumented in the `retryColdStart` doc, and "stays visible" over-promises a LOW-priority event that a client cooldown can drop.
- **status:** accepted - fixed with wording "one unit per call, up to its window's limit" and "logged as a LOW-priority event". The word "retry" and "401" were NOT added to the `///` above `callFunction` (`retry_loop_guard_test.dart:46-56` reads it).

## Finding 7 - P3 - missing_input (seat B)
- **file:line:** `lib/shared/widgets/paywall_sheet.dart` `_validatePromoCode`.
- **claim:** `setState` after an `await` with no `mounted` check (pre-existing, not caused by this change; the change shortens the window from up to four sends to one).
- **status:** spawned: filed as OI-434 with a done-when. Not fixed here: it is a separate, pre-existing defect in a screen this batch only passes an argument to.

## Finding 8 - P3 - writer_reader_drift (seat C)
- **file:line:** `test/contracts/tool_dispatcher_day_swap_invalidation_test.dart` lines 21 and 195.
- **claim:** two comments cite `day_swap_allowance.dart:159`, a line that moved when the file grew.
- **status:** accepted - fixed: both name `DaySwapAllowance._write`.

## Finding 9 - P3 - blast_radius_mismatch (seat C)
- **file:line:** diagnose-doc.
- **claim:** the 4.6 feature-flag reading is not stated in the diagnose-doc.
- **status:** accepted - fixed: a bullet stating the gate, the rollback, the direction of the fault and the fallback.

## Finding 10 - P3 - blast_radius_mismatch (seat C)
- **file:line:** plan, blast-radius paragraph.
- **claim:** it says `supabase/functions/CLAUDE.md` is the only platform path; `docs/architecture/functions-detail.md` is platform too (`docs/blast_radius.yaml:125`).
- **status:** accepted - fixed in the plan.

## Finding 11 - P3 - asserted_fixture_value (seat C)
- **file:line:** diagnose-doc mutation section.
- **claim:** it must say the mutation script is session-local and not retained, and either mutate `edge_function_storage_race_retry_test.dart` or say why not.
- **status:** accepted - fixed: the note is in the section and the storage-race test is in the mutated set (7 test files, 69 tests).

## Finding 12 - P3 - writer_reader_drift (seat C)
- **file:line:** plan v3.
- **claim:** the plan no longer matches the built state (M19, the pins' file, the registry sibling key as an inline comment, the day_swap registry edit as a description, the end-to-end test as its own file).
- **status:** accepted - fixed: the plan is synced, including M19-M21, T8/T9, the seventh OI and the ledger counts.

## Finding 13 - P3 - missing_input (seat C)
- **file:line:** `.claude/skills/debugging/bug-classes.md` class 2.5.
- **claim:** CLAUDE.md 5.1 skill self-evolution: the per-call opt-out, the a6d2f9 incident and the tests are not recorded in the class that owns the retry set.
- **status:** accepted - fixed: a "Metered functions" bullet and a prior-incident entry.

## Finding 14 - P3 - writer_reader_drift (seat C)
- **file:line:** closure ledger `reason:` texts (plan section on the ledger).
- **claim:** a `blocked_on_user` reason that names the already-answered scope call is not a user action; each must name a real one (the deploy go, the trade-off decision).
- **status:** accepted - fixed in the ledger. The borderline use of `blocked_on_user` for OI-431..OI-433 (the fix is agent work, only the deploy go is user-only) is stated in the ledger header rather than hidden.

## Finding 15 - P3 - writer_reader_drift (seat C)
- **file:line:** `supabase/functions/CLAUDE.md` rows for `food_text_analysis` and `scan_meal`, `day_swap_allowance (server half)`, and the "Tests pinning the rules here" list.
- **claim:** the `food_text_analysis` and `scan_meal` rows name the caller by file only (no method), the day-swap row does not mention the send-once rule, and the two new test files are not in the pinned-tests list.
- **status:** accepted - fixed: the method names (`AiBreakdownNotifier.analyse`, `ScanMealNotifier.scanImage`), the "sent once, OI-414" clause and both test names added.

## Mutation evidence for the B-pass fixes (rule 21)

After the fixes the mutation set was re-run against the FINAL tests: 21 mutants (M1-M10, M12-M21) plus M11 run apart on the behavioural files only; all red, none survived, no compile error; the source sha256 was restored equal (`grep -c` confirmed each mutant applied: `applied=True` for all). The new mutants M20 (520 added to the cold-start predicate only) is killed by T8 alone, M21 (`&& !retryOn500`) by T9 and the gate-order pin. Baseline before mutation: 69 tests green over the 7 test files. Per-mutant table: diagnose-doc `a6d2f9`.

## Tuning entry

- **2026-10-25** - blast-radius platform - 15 findings (3 seats, 18 raw items, 3 duplicates); 0 false_alarm; tuning: (1) the strongest finding (a status sweep instead of a status list) came from asking "what could be added to the predicate later" of a test that named only the statuses the author had in mind: for any gate that narrows a PREDICATE, lens 6 should ask the seat to sweep the whole input domain (here 100-599) rather than check the listed cases; (2) a doc rule written as a general statement ("a call that spends a unit sets the flag") was contradicted by the author's own deliberate exception two paragraphs away: when a design leaves one sibling out on purpose, grep every doc that states the rule and name the exception in the same edit; (3) a count of reviewer findings kept by hand drifted (16 vs 15): derive the count from the list in the review file, never from the triage notes.
