---
reviewed_at: 2026-09-22T16:45:00+05:30
staged_against: be6f5e9ed80e
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, guard_without_its_mirror, blast_radius_mismatch, secrets_in_tree, asserted_fixture_value, missing_input, unawaited_no_error_sink]
findings_count: 2
verdict: accepted
---

# Code Review — be6f5e9ed80e

Fresh-agent B-pass over the 3-file staged diff (`tool_dispatcher.dart` +
`test/contracts/tool_dispatcher_telemetry_gaps_test.dart` +
`docs/diagnoses/2026-09-22-tool-dispatcher-telemetry-gaps-b4e7d2.md`). No
prior conversation context. Verified `staged_against` myself via the
skill's documented three-pathspec `git hash-object` command — matches.

## Verification log (what was actually run, not just read)

- Read the full staged diff and the full 1887-line `tool_dispatcher.dart`
  (two `Read` passes, no gaps), plus the full new test file (241 lines).
- `flutter analyze lib/features/ai_coach/services/tool_dispatcher.dart` →
  **No issues found (24.3s)**. This matters beyond confirming the
  diagnose-doc's own claim: the new test file never `import`s
  `tool_dispatcher.dart` — it only `File(...).readAsStringSync()`s it — so
  the 6/6 green test run below does **not** by itself prove the 6
  additions compile. Confirmed no `part`/`part of` directive in the file
  (the known "scoped analyze lies on part files" trap does not apply here).
- `flutter test test/contracts/tool_dispatcher_telemetry_gaps_test.dart` →
  **6/6 green.**
- **Independently re-ran the diagnose-doc's own mutation-proof** rather than
  trusting its self-attestation (CLAUDE.md §4.4 rule 21's "mutate it and run
  it" + the code-review skill's own 2026-09-19 tuning note that a prior
  batch's mutation self-attestation was later found false): deleted the
  3-line `unawaited(ErrorTelemetry.logEvent(...))` addition at the
  `CreateTemplateException` site (line ~1407, the trickiest of the 6 because
  of the sibling generic catch), reran → **exactly test 6 failed**, RED for
  the correctly-attributed reason (`Expected: true / Actual: <false>` on the
  op_type-window assertion, citing the CreateTemplateException-specific
  message, not a generic one), all 5 others stayed green. Confirmed the
  mutation actually applied via `grep -c` of the call-site count (19 → 18).
  Restored the exact original text, `grep -c` back to 19, `git diff --
  lib/features/ai_coach/services/tool_dispatcher.dart` against the index
  came back **empty** (no residue from the cycle), reran → 6/6 green again.
- `git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -`
  (bare stdin form, per this repo's own documented gotcha) →
  `Blast-radius: account` — matches the diagnose-doc's claim.
- `dart run scripts/validate_diagnose_doc.dart
  docs/diagnoses/2026-09-22-tool-dispatcher-telemetry-gaps-b4e7d2.md` →
  **OK, passes validation.**
- Grepped the staged diff for credential-shaped strings (`sk-`, `rzp_live_`,
  `AKIA`, `-----BEGIN`, `api_key`, `service_role`, bearer tokens, etc.) →
  **zero matches.**
- Independently rebuilt, from scratch, the full list of every
  `on \w+Exception catch` (7 sites) and every aggregated
  `errors.isEmpty`/`results.isEmpty`/`scheduled.isEmpty` failure branch
  (6 sites) in the file, and cross-checked against the diagnose-doc's
  claimed 6 fixed sites (see `missing_input` below).
- Read `lib/core/services/error_telemetry.dart` in full for `logEvent`,
  `recordNonFatal`, `isHighPriorityOpType` and the `highPriorityOpTypes`
  list (27 entries) to independently verify signature compatibility and
  the no-collision claim, rather than trusting the diagnose-doc's grep.
- Did **not** run the full `flutter test` suite — per this repo's own
  §4.3 policy ("Don't manually re-run the full `flutter test` when the
  hooks/CI will run it anyway"), that's pre-push/CI's job. See Finding 2
  for what this leaves unverified.

## writer_reader_drift — CLEAN (all 6 additions verified against their exact cited sibling)

- **Site 1** (`execute()`, `on ConcurrentEditException catch (e)`, line 228):
  `'tool_dispatch_${intent.type}_concurrent_edit_failed'` is valid Dart
  interpolation; `intent` is the method parameter of `execute(Ref ref,
  ToolIntent intent)` and is in scope throughout the whole try/catch chain.
  `e.reason` — `ConcurrentEditException` (defined in this same file,
  line 68) has exactly one field, `reason`. Confirmed the window ends at
  the immediately-adjacent `} catch (e, stack) {` (line 234) with nothing
  else between.
- **Site 2** (`_executeSwapExercise`, `on SwapExerciseException catch (e)`,
  line 299): `e.code`/`e.message` confirmed against
  `lib/core/services/swap_service.dart:46-52` — both fields exist.
- **Site 3** (`_executeCreateCustomExercise`, line 574): `e.code`/`e.message`
  confirmed against `lib/features/train/repositories/workout_repository.dart:1660-1666`.
- **Site 4** (`_executeShortenWorkout`, line 601): `e.code`/`e.message`
  confirmed against `swap_service.dart:74-80`.
- **Site 5** (`_executeSwitchGoal` aggregate branch, line 1338): `errors` is
  the `List<String>` declared at line 1242 and populated by the per-date
  loop at lines 1244-1271; in scope at the `results.isEmpty` branch.
- **Site 6** (`_executeCreateCustomTemplate`, `on CreateTemplateException
  catch (e)`, line 1407): `e.code`/`e.message` confirmed against
  `workout_repository.dart:1674-1680`. Confirmed the new call sits strictly
  between `on CreateTemplateException catch (e) {` and the sibling
  `} catch (e, stack) {` two lines below (i.e., inside the typed catch
  only), and uses `tool_dispatch_create_custom_template_validation_failed`
  — textually distinct from the pre-existing generic catch's
  `tool_dispatch_create_custom_template_failed`.
- **Op_type collision sweep** (independent, not delegated to the
  diagnose-doc's own grep): enumerated all 19
  `ErrorTelemetry.logEvent(`/`recordNonFatal(` call sites in the file by
  hand (16 `logEvent` op_types + 3 `recordNonFatal` reasons) — all 19
  literals are textually distinct. For the two DYNAMIC op_types
  (`tool_dispatch_${intent.type}_concurrent_edit_failed` and the
  pre-existing `tool_dispatch_${intent.type}_unexpected_failure`), checked
  every possible `intent.type` value against the 13-case switch in
  `execute()` (`swap_exercise`, `log_set`, `shorten_workout`, …,
  `log_meal_by_text`) — none of the resulting 26 runtime strings collides
  with any static op_type or with each other (the two dynamic templates
  differ in suffix: `_concurrent_edit_failed` vs `_unexpected_failure`).
  Also read the full `highPriorityOpTypes` allowlist
  (`error_telemetry.dart:96-172`, 27 entries) — none is a `tool_dispatch_`
  prefix or literal, so the diagnose-doc's claim that none of the 19
  `tool_dispatch_*` op_types get high-priority (cooldown-bypass) treatment
  holds, confirmed by reading the list myself rather than trusting the grep
  claim in `forbidden_patterns_checked`.

## guard_without_its_mirror

**Confirmed correctly left untouched:** `_executeModifyWorkoutForInjury`'s
inner per-swap-item `on SwapExerciseException catch (e)` (line 631, a
*different* catch than site 2's) and its neighboring generic `catch (e)`
(line 633) both only `errors.add(...)` — the aggregate branch at
`results.isEmpty` (line 652) already telemeters
(`tool_dispatch_modify_workout_for_injury_failed`, pre-existing, untouched
by this diff). This is exactly the shape the diagnose-doc says it is, and
fixing the inner catch too would have double-telemetered every accumulated
error inside one aggregate failure.

## Finding 1 — P3 — guard_without_its_mirror
- **file:line:** `lib/features/ai_coach/services/tool_dispatcher.dart` — all
  6 aggregate-loop methods: `_executeModifyWorkoutForInjury:663` (`else`
  branch), `_executeRescheduleWeek:848`, `_executeGenerateHotelWorkout:921`,
  `_executeRegeneratePlanBlock:1121`, `_executeSwitchGoal:1343` (the site
  this diff just touched one branch above), `_executeScheduleTemplate`
  (implicitly, no `else` needed since it only has the empty/non-empty
  split).
- **claim:** Every one of the 6 aggregate-loop methods (including the one
  this diff just fixed) telemeters ONLY on **total** failure
  (`results.isEmpty`/`scheduled.isEmpty` branch). The **partial**-failure
  branch — some items succeeded, some landed in `errors` — returns
  `ToolExecutionResult.success(data: {..., 'partial_errors': errors})` with
  **no telemetry at all**, silently absorbing the errors into a success
  response. This is a genuine structural mirror of the exact shape this
  diff fixes (a failure signal reaching the user with zero breadcrumb) — it
  is just gated on `success`/`.failure` rather than on which branch, so it
  falls technically outside the diagnose-doc's own stated scope ("returned
  a user-visible `ToolExecutionResult.failure` ... with NO ErrorTelemetry
  call"). It is **pre-existing across all 6 siblings** (not introduced or
  worsened by this diff — `_executeSwitchGoal`'s own partial branch,
  lines 1343-1352, is untouched) and is arguably a distinct product
  decision (does a partial success deserve telemetry?), so I'm not marking
  it a blocker for this diff, but the diagnose-doc's summary ("A user
  hitting one of these 6 paths left zero breadcrumb") is now only true for
  the *total*-failure shape — a partial failure still leaves zero
  breadcrumb, on all 6 methods, after this fix lands.
- **verification:** `grep -n "partial_errors" lib/features/ai_coach/services/tool_dispatcher.dart` — 6 hits, none preceded by an `ErrorTelemetry` call in the same branch.
- **suggested-fix:** Not for this diff. Worth a follow-up task: add a
  LOW-priority `logEvent` (distinct op_type, e.g.
  `tool_dispatch_<action>_partial_failure`) in each partial-success branch,
  mirroring the pattern this diff already established. Flagging for
  founder triage rather than spawning automatically, since it's a scope
  decision (partial success telemetry is arguably noisier / lower-value
  than total-failure telemetry) rather than an unambiguous bug.
- **status:** spawned — filed as task_11039d3d (spawn_task), self-contained
  brief citing this finding + diagnose b4e7d2. Confirmed genuinely
  pre-existing and unworsened by this diff (all 4 untouched sibling methods
  already had this gap before b4e7d2 landed); correctly out of this diff's
  scope, not silently absorbed.

## Finding 2 — P4 — asserted_fixture_value (test-design limitation, not a live bug)
- **file:line:** `test/contracts/tool_dispatcher_telemetry_gaps_test.dart` (whole file)
- **claim:** The test file is a pure source-grep (`File(...).readAsStringSync()`
  + `indexOf` window checks) and **never imports or compiles**
  `tool_dispatcher.dart`. Its 6/6 green result proves the right literal
  tokens sit in the right textual window; it proves **nothing** about
  compilation. A future edit that keeps the literal op_type string and the
  bare `ErrorTelemetry.logEvent(` call in place but breaks the surrounding
  code (e.g., a later rename of `SwapExerciseException.message` →
  `.errorMessage` that a careless find-replace missed at this one call
  site) would stay green here while `flutter analyze` reddens elsewhere —
  the test cannot tell the two apart. This is not unique to this diff (it's
  the same "source-greps prove PRESENCE only" limitation CLAUDE.md §4.4
  rule 21 already names for the whole repo, and this concept is correctly
  declared `sot_registry_entry: not_applicable` so rule 21's
  `behavioral_test_path:` requirement doesn't formally bind it), but it's
  worth stating plainly since the task asked specifically whether a
  wrong-but-textually-similar version could false-pass: yes, on the
  compile axis, though not on the placement axis (the window-scoping itself
  is sound — verified via live mutation on site 6, see Verification log).
  I closed the compile-axis gap for the CURRENT diff myself by running
  `flutter analyze` directly (clean), so this is not a live defect, only a
  standing limitation of what this specific test file can catch going
  forward.
- **verification:** `flutter analyze lib/features/ai_coach/services/tool_dispatcher.dart` (already run, clean — see Verification log); the test file's own imports (`dart:io`, `flutter_test` only, no `tool_dispatcher.dart` import) confirm it cannot catch a compile break.
- **suggested-fix:** None required now. If this concept is ever promoted into `docs/sot_registry.yaml` (currently `not_applicable`), it would need a `behavioral_test_path:` per rule 21 to close this gap permanently (e.g., a widget/unit test that actually triggers one of the 6 exceptions through the real method and asserts a telemetry hook fired).
- **status:** false_alarm — acceptable given `sot_registry_entry: not_applicable`; noted for awareness, no action requested.

## blast_radius_mismatch — CLEAN
`dart run scripts/blast_radius_from_diff.dart -` (bare stdin, fed the
staged file list) returned `Blast-radius: account`, matching the
diagnose-doc's frontmatter exactly. No `SECURITY DEFINER` / migration /
Edge Function content in this diff to trigger a content-rule override, and
the touched file (`lib/features/ai_coach/services/tool_dispatcher.dart`)
is plausibly account-tier by path glob alone.

## secrets_in_tree — CLEAN
Grepped the full staged diff for `sk-`, `rzp_live_`, `AKIA[0-9A-Z]{16}`,
`-----BEGIN`, `api_key`/`secret`/`password` assignments, bearer tokens, and
`service_role` — zero matches. Expected: this diff only adds telemetry
calls with static op_type strings and `${e.code}: ${e.message}`
interpolations; no new literals of any credential shape.

## missing_input — CLEAN (independent 6-vs-6 cross-check, no 7th gap, nothing over-claimed)
Built my own exhaustive list from scratch (not trusting the diagnose-doc's
count) via `grep -n` for `on \w+Exception catch` and
`errors.isEmpty|results.isEmpty|scheduled.isEmpty`:
- 7 typed-exception catches total: line 227 (Concurrent, fixed), 298 (Swap,
  fixed), 573 (CreateCustomExercise, fixed), 600 (ShortenDay, fixed), 631
  (Swap, inside injury loop — correctly untouched, see
  `guard_without_its_mirror` above), 1167 (PausePlan — pre-existing sibling,
  the cited "C5" precedent), 1406 (CreateTemplate, fixed).
- 6 aggregate-failure branches: `_executeModifyWorkoutForInjury` (652,
  pre-existing), `_executeRescheduleWeek` (838, pre-existing),
  `_executeGenerateHotelWorkout` (910, pre-existing),
  `_executeRegeneratePlanBlock` (1110, pre-existing), `_executeSwitchGoal`
  (1330, **fixed by this diff**), `_executeScheduleTemplate` (1503,
  pre-existing).
This is exactly 5 typed catches + 1 aggregate = 6 sites fixed, matching the
diagnose-doc's claim precisely — no 7th untelemetered `.failure(...)` site
of either shape exists in the file, and nothing the diagnose-doc claims to
have fixed is unverifiable (all 6 independently confirmed against the
actual diff hunks). Pure payload-validation early-returns (e.g. "Invalid
swap intent payload") are a structurally different class (never telemetered
anywhere in the file, fixed or unfixed) and are correctly out of scope.

## unawaited_no_error_sink — CLEAN
All 6 new `unawaited(ErrorTelemetry.logEvent(...))` calls: `logEvent`
(`error_telemetry.dart:328-386`) wraps its entire body in its own
`try { ... } catch (_) { /* Swallow — events must never break the host
flow. */ }` — it is its own error sink, matching all 13 pre-existing
sibling call sites in this file. No risk of an unhandled async rejection
from any of the 6 additions.

## Founder triage notes

Triaged by the implementing session (account-tier — verdict is advisory per
`.claude/skills/code-review/SKILL.md` §4, not a blocking gate):
- Finding 1 (P3): spawned as task_11039d3d rather than fixed in this batch —
  genuinely out of scope (a different bug class touching 4 untouched sibling
  methods), matches this project's own no-deferrals discipline (tracked, not
  silently dropped).
- Finding 2 (P4): accepted as `false_alarm` per the reviewer's own reasoning
  — matches the established repo-wide test-design convention for this
  concept class (`sot_registry_entry: not_applicable`), and the compile-axis
  gap it names is independently closed by the separate `flutter analyze`
  step already run twice (once by the implementer, once independently by
  this reviewer).

`verdict:` set to `accepted` — both findings resolved (zero pending), and the
founder has since explicitly directed landing this work (merge, then a
second independent review round to satisfy the §4.12 keystone gate),
which is the founder's own sign-off on the outcome.
