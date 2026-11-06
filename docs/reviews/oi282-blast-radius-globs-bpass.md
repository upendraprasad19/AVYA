---
reviewed_at: 2026-10-04T03:09:00+05:30
staged_against: oi282-blast-radius-globs (HEAD 4259d0ed) vs origin/main
blast_radius: platform
reviewer: fresh-context-blind-agents (Sonnet, two rounds; round 2 on the tree after round 1's fixes)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 19
verdict: accepted
---

# Code Review (B-pass) — the sync engine's core classifies as platform (`oi282-blast-radius-globs`)

Scope: `docs/blast_radius.yaml` (22 platform rules: 21 exact paths, 19 in `lib/core/services/` and 2 for restore merges
hosted outside it, plus `sync_domains/**`; one dead rule repointed; a written three-prong boundary),
`test/contracts/blast_radius_sync_engine_platform_test.dart` (new, 36 tests: derived completeness over
`import` / `export` / `part` across `lib/`, a declined-by-name map, a known-callers map, exactness, rot, a real-CLI check),
`test/scripts/plan_review_record_gate_e2e_test.dart` (six keystone arms), one repointed older test
(`blast_radius_progress_map_writer_paths_test.dart`), the SoT entry, diagnose `f2c8a5`, the closure ledger, OI-282 closed
and OI-301 filed, bug class 2.87 with its index rows, the plan, and the removal of two stray root files. Self-attested
(rule 21): the mutation driver is a scratch script, not in the repo.

## Round 1 (against the staged tree before the folds)

Entry condition (§4.12.8): analyze 0 warnings / 0 errors (343 pre-existing infos), `sh scripts/pre-commit.sh` all gates
passed, full `flutter test` +7553 ~9, all passed (41:51). Result: 0 P0, 1 P1, 5 P2, 4 P3. Every finding was re-verified
by the author against the files (costs, the `part` count and the call sites reproduced); none was a false alarm; all are
fixed in the final tree.

| # | Sev | Lens | Finding | Status |
|---|---|---|---|---|
| 1 | P1 | guard_without_its_mirror | the test's directive reader ignored `part` / `part of` (`sync_service.dart` declares nine part files), so a part placed outside `sync/` and not named `sync_*.dart` was invisible to the derivation and fell to the account catch-all; the test named "sees every shape" had no `part` line (reviewer mutation: 0 red) | fixed: the reader reads `part` / `part of`, the derivation scans all of `lib/`, a synthetic-source shape plus an assertion against the real engine library; killed by M40, M41 |
| 2 | P2 | blast_radius_mismatch | the 60-day cap was written as a uniform filter but attached to one prong; `plan_integrity_reconciler` adds 3 commits alone and `sync_queue` 2, `workout_write_service` (9/5) and `nutrition_write_service` (5/4) stay account on the cap alone; the candidate table omitted them | fixed: three prongs, the cap stated on the third only, table extended |
| 3 | P2 | blast_radius_mismatch | `singleton_lifecycle_registry` was promoted on cross-account isolation, a rationale in the tier definition and the rule's comment but not in the boundary header | fixed: prong 2 |
| 4 | P2 | blast_radius_mismatch | four derived files stay account through pre-existing explicit rules; "claimed" was true for ANY non-catch-all rule, so no reason was recorded and the declined check forbade recording one; two of them meet the verbs (`exlogKey`, `clampRestoredNutritionRow`) | fixed: "decided" means platform OR declined; `_declined` may hold them; reasons and costs written; M49, M54 |
| 5 | P2 | blast_radius_mismatch | `UserRepository.mergeCloudProgress`, a restore merge the engine calls, sat at account via `lib/shared/repositories/**`; the boundary said "services layer" and the derivation read only that layer | fixed: the derivation covers all of `lib/`; the same sweep promoted `notification_prefs_repository.dart` (`adoptFromCloud`); both rules placed above the repository and profile rules (M44-M46, M52, M53) |
| 6 | P2 | writer_reader_drift | the debugging skill requires one index row per new bug class in the same commit; the diff added class 2.87's body only (2.80 and 2.81 also lacked rows) | fixed: three rows |
| 7 | P3 | guard_without_its_mirror | surviving mutations: a keyword with no space, two directives on one line, a stale declined entry, a `*_queue.dart` platform wildcard; loose vacuity floors | fixed: M42, M43, M47, M48 kill them; floors `greaterThan(50)` / `greaterThan(55)` against real 60 / 64 |
| 8 | P3 | asserted_fixture_value | four declined reasons named no engine-called function although the header says each does | fixed: every reason names the call (`MigratedKey.read/write/delete`, `SupabaseService.instance.client`, `ErrorTelemetry.recordNonFatal` and so on), checked against the code |
| 9 | P3 | guard_without_its_mirror | the e2e control (`workout_write_service.dart`) is itself an engine import held at account only by the tunable cap; no arm proved the keystone's own glob engine on the `sync_domains/**` wildcard | fixed: the control is `lib/features/ai_coach/zz_keystone_control.dart`; arms added for the directory glob and for a path outside the services layer (M38, M51-M53) |
| 10 | P3 | blast_radius_mismatch | `scripts/pre-push.sh:172-190` skips the full local suite only at `feature`, so a push touching only `profile_write_service.dart` now runs it; unwritten | fixed: written in the plan (D5) and the diagnose doc; measured cost nil |

Things round 1 tried that HOLD: the keystone rejects for the tier; the with-`bpass` and control arms are green on both
registries; `mergeAndRunGate` defaults reproduce the old record text byte for byte; the keystone's diff uses
`--no-renames`; no duplicate rule; no test counts rules or pins their order; the four copies of the glob engine are
identical (the author diffed them: one comment line differs).

## Round 2 (against the folded tree)

Entry condition: the full gate loop green on the folded tree (analyze 0 warnings / 0 errors, pre-commit all gates
passed, full `flutter test` +7560 ~9). One fresh, context-blind Sonnet reviewer, read-only, with scratch scripts of its
own (an independent directive reader, a 25-case in-memory mutation pass, a cost replica, a four-reader parity check, a
check that each named function in the 21 declined reasons exists). Result: 0 P0, 0 P1, 2 P2, 7 P3. Every finding was
re-verified by the author against the files before it was acted on (the call sites, the totals, the line numbers and
the `part` count all reproduced); none was a false alarm; all are fixed in the final tree.

Round 1's ten findings, re-checked by the reviewer against the folded tree: seven fixed; one partly fixed (#2: the cap's
uneven application survived in the residuals for `auth_session_bootstrapper.dart`, this round's Finding 1); one fixed
in substance with a wording error inside it (#6, this round's Finding 6); one fixed with an unstated consequence (#10,
this round's Finding 8). The reviewer's independent reader derives the same 64 files from 40 roots as the test's.

| # | Sev | Lens | Finding | Status |
|---|---|---|---|---|
| 1 | P2 | guard_without_its_mirror | `auth_session_bootstrapper.dart` runs a second cloud-over-local restore merge (`hydrateFromCloud`: the users row, then `user_progress` through `UserRepository.mergeCloudProgress`; its own comment calls it the twin of `sync_profile.dart`'s `_restoreUserProgress`) yet stayed account on the cost cap, which the registry confines to prong 3; the other reason (a caller, outside the derived set) was a scope choice no test pinned | fixed: callers are a stated scope limit (registry header, test header, diagnose doc), the cost is given only as the price of flipping, and both known callers are pinned in a `_callers` map with its own test; M55-M60 |
| 2 | P2 | blast_radius_mismatch | the `supabase_service.dart` reason named `SupabaseService.instance.client` (spelled that way by two engine files only) and omitted the two functions the engine core calls in it, `callFunction` (cold-start retry) and `ensureFreshToken` (per-owner coalescing), which carry prong 1's "retries, serialises" | fixed: the reason names both and why app-wide transport is declined; a disclosed borderline (promotion costs 0 newly-platform commits but would pull every AI and payments transport change into the sync review) |
| 3 | P3 | blast_radius_mismatch | `sync_state_provider.dart` decides WHEN the engine retries (the 5-minute drain timer, the connectivity drain, the force-retry); "decides none of what is retried" held for WHAT only; disclosed in prose and pinned by no test | fixed: decided by name and pinned in `_callers` (M60); flipping it costs 1 newly-platform commit |
| 4 | P3 | asserted_fixture_value | "716 non-merge commits, 285 already platform" did not reproduce with the stated command (717 / 286); every decision figure did | fixed: re-measured from an absolute window start (a date-only `--since` takes the current time of day); every site corrected |
| 5 | P3 | asserted_fixture_value | the registry's own comment cited "(lines 84, 93)", moved to 89 / 98 by round 1's two new rules; the first re-sweep of moved cites looked only outside the registry | fixed: reworded without numbers |
| 6 | P3 | asserted_fixture_value | bug class 2.87 said `sync_service.dart` "is ten `part` files" (nine `part` directives; a library of ten files) | fixed |
| 7 | P3 | asserted_fixture_value | the plan cited `_validateRecord` as `check_plan_review_record_exists.dart:788-866`; it runs to 868 | fixed |
| 8 | P3 | blast_radius_mismatch | the side effects named the S-tier loss only for `profile_write_service.dart`; `notification_prefs_repository.dart` (feature to platform) loses it more strongly, since the keystone now demands `bpass: accepted` for it | fixed: written in the diagnose doc, plan D5 and the PR |
| 9 | P3 | blast_radius_mismatch | no prong-1 verb holds literally for `sync_domain.dart` (an interface), while equally pure types are declined; the boundary did not say why the contract files are listed | fixed: prong 1 names the contract, error taxonomy and per-domain path flags the engine is built on (`sync_domain`, `sync_error`, `sync_flags`) |

While folding, the author also corrected the test header's count of declined files that lean on the cost cap (two to
three); not a reviewer finding.

Things round 2 tried that HOLD: the four registry readers parse the staged registry to identical rule lists (161 each,
0 glob differences, 0 classifier-versus-keystone tier disagreements over 4,581 tracked paths); 30 tier changes, the
intended set; the cost table's per-file figures (7/3, 5/2, 9/5, 18/7, 1/0, 3/0) and 2 / 3 / 6; "13 call sites register"
with `singleton_lifecycle_registry`; no secret-shaped string, no `functions.invoke`, no `unawaited(` in the added lines;
the two deleted root files are referenced nowhere; the reviewer's 25-mutation pass killed 24 and kept one alive, a new
import inside a DECLINED file, which is the documented one-hop limit.

## Mutations (rule 21)

61 cases against the final text of the registry, both tests and the two caller files, each confirmed applied, run,
restored from a backup and byte-compared: 61 killed, 0 survivors, 0 not applied, 0 restore failures. Against the
registry as of the base commit the contract test (36 tests) is red on 27 and the keystone group on 4 of 6. Grouped
table: diagnose `f2c8a5`, Verification.

## Checked clean

All 4,581 tracked paths classified under the base registry (byte-identical to the checked-in copy) and the new one: exactly
30 change tier and the set is the intended one; 161 rules (139 at base), 111 exact-path, every exact path present and
tracked; the four registry readers parse the new registry to the same rule list; no gate, hook or workflow other than the
merge keystone keys on `bpass`; `feature_flag` is enforced by no gate; the older test that pinned `user_repository.dart`
at account is repointed and no other assertion of an old tier of a moved path exists (grep of `test/`, `scripts/`,
`.github/`, `.claude/`, `supabase/`, non-historical `docs/` and `lib/` comments).

## Accepted residue (self-attested)

- The derivation follows what the engine files reach, one hop: a file reachable only through a DECLINED file is not
  derived (21 such files today, judged by name and importer, not read), and it cannot see a caller of the engine. The
  two known callers are decided by name in `_callers` (`auth_session_bootstrapper.dart`, a second restore writer that
  also calls `mergeCloudProgress`: 6 commits touch it, 3 would be newly platform; `sync_state_provider.dart`: 3 touch
  it, 1 newly platform); any other caller is not found by the test. Written in the test header, the registry header and
  the diagnose doc.
- `supabase_service.dart` (shared transport that carries the engine's cold-start retry and token coalescing) and
  `profile_target_recompute.dart` (passes the cap, not the verb list) are disclosed borderline declines; one rule flips
  each.
- `feature_flag` (a platform-tier requirement) is deliberately not met: registry data, its off state is the old registry,
  no gate enforces it; the founder's merge ratifies the waiver (PR description, diagnose doc).
- Linux behaviour of the new tests was reasoned and read, not executed here; CI runs them on Linux at the merge.
