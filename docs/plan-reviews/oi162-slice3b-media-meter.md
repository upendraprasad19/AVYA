---
branch: oi162-slice3b-media-meter
date: 2026-09-08
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/4b31af31a792-review.md
---

# Plan-review record — OI-162 slice 3b, the ai-media-proxy free-image lifetime meter (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`, COMPUTED** — `dart run scripts/blast_radius_from_diff.dart <13 changed paths>`
→ `platform`. ⚠ **The `-` trap fired again**, on a session that had already read slice 3a's record
documenting it: piping paths in WITHOUT the trailing `-` makes the script classify the STAGED set
instead, which was empty, so it printed nothing. Then a `grep -v "Running build hooks"` filter
DELETED the answer, because the build-hooks banner prints on the SAME LINE as the result. Two
independent ways to read silence as an answer, stacked. Recorded again because reading the warning
was demonstrably not enough to avoid it.

## Rounds

**Round 1 — 5 findings (2 BLOCKING, 2 MAJOR, 1 MINOR). All accepted; every one re-verified by me
against the tree before acting.**

- **F1 (BLOCKING)** — deleting the zero-caller `getFreeImageAnalysisCount` breaks the `stillLegacy`
  map in `usage_quota_ledger_writer_to_reader_test.dart`, because `ai_coach_interactions` appears
  **exactly once** in `ai_coach_repository.dart` (`:284`) — inside the method being deleted. The
  plan's "grep returns 1 line" had been silently scoped to `lib/`.
- **F2 (MAJOR)** — the plan said "rewire the SoT concept"; no concept covered this gate, so it is a
  MINT. **Premise corrected by me:** `usage_quota_ledger` DOES exist, but slice 3a registered under
  the SURFACE concept `weekly_report_pro_gate`, so one-concept-per-gate is the precedent.
- **F3 (MAJOR)** — an OPEN board subsection for this exact bug had to be closed by 3b.
- **F4 (BLOCKING)** — 3a's mutation-safety rules were claimed as "inherited" and never restated.
- **F5 (MINOR)** — `:435`/`:468` anchor the insert open-brace; the `channel:` literals are 438/471.

**Round 2, on the HARDENED plan — 1 BLOCKING, 2 MINOR. All accepted, all re-verified.**

- **R2-1 (BLOCKING)** — round 1's fix was INCOMPLETE **in the file it had just patched**. The same
  test holds two more ratchets (`:133`, `:164`, both
  `const allowed = {'supabase/functions/weekly-report/index.ts'}`) asserting no other file contains
  `usage_counters` or `consume_quota`. This diff puts both literals into `ai-media-proxy`.
- **R2-2 (MINOR)** — the plan's account of WHY Gate 50 does not protect `usage_quota_ledger` was
  backwards. `"n/a"` is not a recognised placeholder; the concept IS scanned, and the scan is a
  structural no-op. Conclusion unchanged, mechanism corrected.
- **R2-3 (MINOR)** — the board subsections belong to `## OI-153`, not OI-162 as the plan claimed.

**Convergence.** 5 → 3, and round 2's blocking finding was the same CLASS as round 1's (a ratchet in
one file), not a new class. The unit is small and bounded — one EF function, one deleted dead
method, docs. Converged rather than split (§4.12.1's split trigger is successive rounds surfacing
*new* material classes).

## The lesson this batch is worth remembering for

**Round 1 found ONE ratchet in that test file and I fixed it. Neither round 1 nor my own
verification asked the mirror question — *what else in this file is keyed on the same set?* — and
the answer was "two more, twelve and forty lines away."** The §4.9 grep-the-test-tree rule finds the
FILE; it does not find every assertion inside it. Instance of
`feedback_mistake_guard_without_its_mirror`: fixed the instance, not the class.

## B-pass (`docs/reviews/4b31af31a792-review.md`) — 3 findings, 0 P0/P1, 0 false alarms

All three fixed in-batch. Two were stale citations; one was a coverage gap on the new user-facing
copy, now closed by two tests including a client/server byte-identity check that is itself
mutation-proven (shortening one phrase in the TS copy reddens it).

**The finding worth carrying forward is the P3, because of HOW it survived.** After renaming the
contract test I ran a sweep for the old name and it reported "none". The sweep was
`grep -rn --include=*.md --include=*.yaml`; the surviving reference was in a `.sql` file. A
verification narrower than the thing being verified returns zero and looks exactly like a clean
result. **That shape fired FOUR times in this session** — a `lib/`-scoped grep quoted as repo-wide
in the plan; a `^\s+`-anchored warning count that missed a real warning (the line has no leading
space); a blast-radius run whose answer a `grep -v` filter deleted, because the build-hooks banner
shares the result's line; and this. Re-verified with `git grep` across all tracked files, unfiltered.

The P2 is OI-167's class recurring: a citation correct when written and wrong in the same commit
that shipped it, because the diff inserted ~83 lines above the cited line. Fixed by citing the
SYMBOL rather than the line, and the row now records its own drift in place.

## Ground truth verified (read-only, live)

- **No trigger covers `free_image_analysis`.** All three `ai_coach_interactions` triggers read from
  `pg_get_functiondef`; none matches this channel, so an EF-side `consume_quota` cannot double-count.
- **`quota_key` is unconstrained `text`** — no migration needed; 130 stays free.
- **Live prod, 2026-09-08:** `free_image_analysis` rows = **0** across **0** users (so the cutover
  regrant affects nobody — the bug was latent); `pro_image_analysis`/`image_analysis` rows = **0**
  (confirming OI-153's dormancy from DATA as well as from code); `weekly_report_free` ledger rows =
  **0** (slice 3a's consume has never executed in production).
- **`ai-media-proxy` is live at v21** and this change is NOT deployed.

## Mutation proof (§4.4 rule 21)

Six mutations, each CONFIRMED APPLIED by a token grep before running, each reddening exactly one
assertion, all restored to 10/10 green: quota-key retarget, epoch→real timestamp, fail-closed
reverted to fail-open, the `!interactionLogError` conjunct dropped, a DECOY GUARD between the real
guard and the RPC, and the allowlist left un-ratcheted. None was a compile error (the assertions are
source greps over TypeScript, which `flutter test` never compiles), so every red is an assertion
failing for its own reason. The decoy-guard mutation was checked BY NAME — it is precisely what
defeated slice 3a's first attempt at that assertion, which tested PROXIMITY rather than containment.

## Gates

Full local gate loop (`sh scripts/pre-commit.sh`) run BEFORE dispatching the B-pass, per §4.12.5 —
it caught **Gate 9** (`check_writeservice_contracts`), which requires the contract test to be named
`<concept>_writer_to_reader_test.dart`. The test was renamed and all six references repointed.
`flutter analyze lib/` then surfaced a WARNING of my own making: deleting the method orphaned its
`supabase_service.dart` import, which would have failed the push with §4.9's opaque
`failed to push some refs`. Removed; now 0 warnings / 0 errors, 44 pre-existing infos.

## Not done, and why — carried openly rather than silently

- **The `slice3b_*` SQL assertions were RUN LIVE 2026-09-09** (founder-authorized per §4.3 / §10.3):
  **3/3 `ok`**, sequence `1 2 3 4 5 | sixth=-1`, rollback verified clean afterwards. The
  `check_onconflict_live_arbiter.dart` wrapper 403s on the Management API — the same
  token-privilege failure the SQL file's own header records from 2026-07-30 — so it ran via direct
  `execute_sql`. ⚠ Still only ledger behaviour-invariants: they execute no Edge Function and would
  pass against the pre-3b code.
- **The Edge Function is NOT deployed.** Live is v21. Deploy needs separate authorization; a merged
  code change is not a deployed one, exactly as `weekly-report` sat at v26 with 3a's code merged.
