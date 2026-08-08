---
bug_id: b2f7a4
date: 2026-08-07
batch: oi91-claude-md-citations
status: fixed
blast_radius: catastrophic
closes_oi: OI-91
symptom: |
  138 `CLAUDE.md §N` citations in `.dart` / `.ts` / `.sql` / `.js` comments
  pointed at root-CLAUDE.md sections that do not exist. Root's real headings
  are exactly `0, 1, 2, 2a, 3, 4, 5, 6, 7`; the citations named §9-§19.

  Citations are how an agent navigates this repo. A dead one does not fail
  loudly — it sends the reader to a section that isn't there, and the usual
  recovery is to guess, or to conclude the rule was retired.

  A second, worse class was found during the fix and is NOT what OI-91
  described. The 2026-05-18 declutter did not only RELOCATE sections — it
  RENUMBERED them, and reused the vacated numbers for unrelated content:

  | Number | Before 2026-05-18 | After |
  |---|---|---|
  | §4 | DATA ARCHITECTURE (OFFLINE-FIRST) | PROCESS INVARIANTS |
  | §5 | DIRECTORY STRUCTURE | PER-BATCH MAINTENANCE PROTOCOL |
  | §6 | **THE CODING RULES 1-23** | MULTI-TIER COVERAGE PROTOCOL |
  | §7 | **DATABASE SCHEMA (46 Tables)** | WHERE TO FIND DETAILED RULES |

  So a pre-declutter citation of §6 or §7 still resolves to a real heading —
  the wrong one. It reads as correct to a human and is structurally invisible
  to OI-91's own survey grep, which filtered on "outside §0-§7". 11 such
  citations were found by reading. This is the sub-class OI-91 flagged as
  "the dangerous one" and recorded as unmeasured; it is now measured.
concept: |
  claude_md_section_citation — the pointer from a source comment to a numbered
  section of root `CLAUDE.md`. The schema below is writer/reader-shaped because
  this drift IS writer/reader drift; the writer just happens to be a document
  rather than a Hive box.
sot_registry_entry: |
  not_applicable — `docs/sot_registry.yaml` tracks runtime data concepts
  (writer → Hive → reader). This concept has no runtime state. The authority is
  root `CLAUDE.md`'s heading set itself, and it is now machine-enforced by
  Gate 26 rather than by a registry entry.
writers: |
  Root `CLAUDE.md` is the sole writer of the heading set — `CLAUDE.md:22`
  (`## 0.`) through `CLAUDE.md:494` (`## 7.`). Real headings: 0, 1, 2, 2a, 3,
  4, 5, 6, 7 plus the §4.x / §5.1 subsections.
readers: |
  227 anchored citations across `.dart` / `.ts` / `.js` / `.sql` comments in
  `lib/ test/ scripts/ supabase/ integration_test/`. 138 named a section the
  writer no longer has; 11 more named a real section that is the wrong one.
  Highest-density readers: `lib/core/services/sync/**` and
  `lib/features/ai_coach/**` (the old §15 sync contract).
hive_key_prefix: not_applicable — documentation concept, no Hive key.
hive_key_formula: not_applicable — documentation concept, no Hive key.
sync_methods: []
restore_methods: []
cloud_table: not_applicable — nothing is persisted for this concept.
cloud_columns: []
contract_test_path: test/scripts/claude_md_citations_letter_suffix_test.dart
ist_handling: |
  not_applicable — no date, timestamp, or counter reset is involved.
provider_invalidations: |
  not_applicable — no Riverpod provider reads this concept; it is read by
  humans and agents, and now by Gate 26.
telemetry_op_types: []
cross_account_guard: |
  not_applicable — the concept is repo-global and carries no user scope.
forbidden_patterns_checked: |
  - Bare `§N` scanning in the code zone: REJECTED by measurement. 526 bare
    section tokens exist in code and only 227 are root citations, so the bare
    pattern would have produced ~299 false positives and an unbounded
    statute allow-list. The code zone is anchored instead.
  - Blind `sed` substitution across the 138: REJECTED. §19's entries were
    largely DELETED rather than relocated, so a mechanical rewrite would have
    minted 10 fresh pointers to a document that does not contain them.
  - Scoping `supabase/functions/razorpay-webhook/index.ts` out of the sweep to
    hold the batch below catastrophic tier: REJECTED as a euphemised deferral
    under §4.2, and it would have blocked the gate's flip to hard-fail.
  - An allow-list entry for the gate's own test file: REJECTED. The fixtures
    use the `§` escape so the test cannot trip the gate it drives, with
    no allow-list debt of the kind OI-84/OI-88 record.
proposed_fix: |
  Gate first (§4.11), then the sweep it judges, then flip the gate to
  blocking — all in one batch, since the baseline is measured immediately
  rather than needing a 24h soak. Full detail in `fix:` below.
regression_test_planned: |
  `test/scripts/claude_md_citations_letter_suffix_test.dart` — extended with a
  `code zone` group carrying four assertions, of which two are controls: a
  `spec §15` line in a `.dart` file must stay silent (standing in for the 299
  non-root tokens), and a citation to a nonexistent SUBSECTION of a live
  section must be caught. They assert on the finding line rather than the exit
  code so they survive the report-only → blocking flip unchanged.
impact_analysis: |
  No user-facing impact and no runtime behaviour change: every edit is a
  comment, plus one gate script and its test. The cost was borne entirely by
  agents and maintainers navigating the repo — 138 pointers that dead-end, and
  11 that quietly land on the wrong rule, which is the more expensive failure
  because it reads as correct.

  The renumbering collision is the part worth carrying forward: because §4-§7
  were REUSED for different content rather than retired, every pre-2026-05-18
  citation of those four numbers is suspect on sight, and no grep filtered on
  "outside the live range" can see it.
root_cause: |
  The declutter (`docs/superpowers/plans/2026-05-18-claude-md-declutter-plan.md`)
  swept the PRESCRIPTIVE doc zones — `.claude/**`, `docs/naming_conventions.md`,
  `docs/audit/`, `docs/playbook/**` — and fixed 20 citation sites there
  (diagnose `e7c3b9`). It never swept in-code comments.

  Nothing caught the residue because Gate 26
  (`scripts/check_claude_md_citations.dart`) walks only markdown contract
  files: root `CLAUDE.md`, `AGENTS.md`, `lib/**/CLAUDE.md`,
  `supabase/**/CLAUDE.md`. It has never read a `.dart` comment, so it reported
  PASS for 81 days while 138 dead pointers sat in source.

  The renumbering half compounds it: a gate keyed on "does this section
  number exist" would still have passed §6 and §7, because both numbers exist.
fix: |
  Three parts, in §4.11 order (gate first, then the change it judges).

  1. **Gate 26 gains a code zone** (`scripts/check_claude_md_citations.dart`).
     `.dart` / `.ts` / `.js` / `.sql` / `.sh` under `lib/ test/ scripts/
     supabase/ integration_test/`.

     It deliberately does NOT reuse the markdown zone's bare-section pattern.
     Measured: code carries **526** bare section tokens, only **227** of which
     refer to root — the other **299** cite other documents (`Plan` 24,
     `DPDP` 24, `spec` 19, `DEVICE_TESTING.md`, design docs). A bare pattern
     would have failed ~299 times on day one and forced an unbounded
     allow-list. The code zone requires the citation be ANCHORED to the
     filename, using the same shape as OI-91's survey grep so the gate's count
     reconciles with the board's.

     **A nuance on 3 of the swept files, stated rather than left implicit.**
     Migrations 057, 069 and 070 each carry one citation inside a
     `COMMENT ON INDEX ... IS '<text>'` string literal — not a `--` SQL
     comment. All three migrations are already applied
     (`backups/applied_migrations.json`), so the live Postgres catalog for
     `dedsavbjuwgarrhphgnl` retains the OLD text forever unless a fresh
     migration replay or an explicit follow-up `COMMENT ON` statement runs
     against it; only a NEW environment that replays migrations from scratch
     picks up the corrected text. The fix is still right for the file (a
     future reader, and any fresh database, should see the live section
     number, not a dead one) — but "comment-only" is not quite accurate for
     these 3 specific edits, and this diff does not touch prod.

     Both zones resolve against ROOT's headings even when a citation carries a
     nested path prefix. That is not an approximation: **no nested contract
     file defines numbered headings at all** — all 14 use prose headings — so a
     numbered citation is always a root citation. One citation
     (`supabase_functions_no_cerebras_openrouter_test.dart:10`, `lib/CLAUDE.md`
     §11) was a mis-attribution on exactly this point and is corrected.

     Landed report-only, then flipped to blocking in the same batch once the
     sweep was green.

  2. **The sweep — 138 citations, 100 files.** Mapping recovered from the
     declutter plan's own Tasks 2.5-2.13 rather than reconstructed: §15 →
     `docs/architecture/sync.md` (78), §11 → `docs/architecture/ai.md` (19),
     §16 → `payment.md` (8), §14 → `business-rules.md` (8), §12 →
     `plan_engine/CLAUDE.md` (6), §10 → `subscription.md` (4), §13a →
     `onboarding/CLAUDE.md` (2), §9 → `wardroom/CLAUDE.md` (1).

     **§19 (11 citations) could not be mapped mechanically and was the reason
     to read rather than substitute.** OI-91 proposed pointing §19 at
     `docs/playbook/common-pitfalls.md`. Only 1 of the 5 quoted entry titles
     is actually in that file. `2026-05-18-claude-md-declutter-audit.md`
     classifies every §19 entry: Class A/B entries were **deleted because a
     test became their record**, and in 5 cases that test is the very file
     carrying the dead citation. Those now name the retired entry, its class,
     and the surviving record. Blind-mapping them would have produced 10 new
     pointers to a document that does not contain what they claim.

  3. **11 wrong-but-live citations**, found by reading all 77 in-range
     citations: 7 × old-§7 (DATABASE SCHEMA → `docs/architecture/database.md`,
     verified to carry both the v5-UUID namespace at :51 and the FK-direction
     quirk at :43), 3 × old-§6 (coding rules → §4.4, incl. `§6 rule 11/12
     token-first` → `§4.4 rules 11/12`), and one `§0` citation claiming a
     Flutter version pin that §0 does not contain (repointed at
     `.github/workflows/test.yml`).

     Two in-range citations were read and deliberately left unchanged, which
     is a finding rather than an omission: `check_doc_internal_consistency.dart:44`
     cites old §7 knowingly and self-corrects in the same comment, and
     `restore_template_schedule_test.dart:144` reads correctly under the NEW
     §6 (multi-tier coverage).
verification: |
  - OI-91's own survey command returns **0**, down from 138.
  - Gate 26 in enforced mode: PASS across 16 markdown contract files and 1595
    source files.
  - **Negative-controlled by execution, both directions.** Appending one dead
    citation to `lib/core/utils/ist_date.dart` made the gate FAIL naming that
    exact file:line; removing it restored PASS. Not inspected — run.
  - Gate test suite 7/7, including the false-positive control (a `spec §15`
    line in a `.dart` file must stay silent) that stands in for the 299
    non-root tokens, and a control for a dead SUBSECTION of a live section.
  - `flutter analyze`: 0 errors, 0 warnings (242 pre-existing deprecation
    infos, unchanged).
  - The gate independently found one citation the board's grep could not see
    (`ist_date.dart:4` → `§3.1`; §3 exists but has no subsections), which is
    why the gate's baseline read 138 while the board's grep read 137 after the
    first fix. That discrepancy was chased down rather than rounded off.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "100 files rewritten, comments only. flutter analyze (3.41.4, CI-pinned): 0 errors / 0 warnings / 242 pre-existing deprecation infos, unchanged. flutter test test/contracts/ test/scripts/ test/onboarding/ test/critical_flows/ -> 2988 passed, 1 skipped. That suite matters more than usual here: several edited files are source-grep tests that read their own or neighbouring source, so a comment edit could have moved an assertion." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No runtime code path changed. The diff is comments plus one gate script and its test; no Hive box, key or adapter is touched." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "Three migration files edited (057, 069, 070) - comment text only, zero SQL statements changed. Verified by diffing the statement text: byte-identical outside comment lines." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No query, insert, update or backfill authored. No data read or written." }
  - { tier: 5, name: migrations_applied, status: verified, evidence: "No migration applied, so no backups/applied_migrations.json pairing is owed. Separately verified the three edited migration files contain zero occurrences of security definer, so the blast-radius content rule at blast_radius_content_rules_lib.dart:38 does not fire on them - they stay platform via the supabase/migrations glob rather than escalating to catastrophic the way migration 101 did in the Unit 1 batch." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: verified, evidence: "Comment lines rewritten in _shared/cron_telemetry.ts and razorpay-webhook/index.ts. No deploy performed and none owed: the emitted bundles are behaviourally identical, comments being the only delta. Deno type-check over the full tree runs in CI and is the backstop." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron schedule, dispatch or telemetry op_type touched. cron_telemetry.ts keeps its exact runtime behaviour." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "Migration 070's edit is a comment directly above its owner-only policy block; the policy DDL itself is unchanged. No pg_policies state altered." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket, object or storage path touched. The coach-media path layout comment was reworded, not the path." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret, key or Vault entry read, added or rotated." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No OneSignal, Razorpay, Firebase or Gemini configuration touched." }
  - { tier: 12, name: client_server_contract, status: not_applicable, evidence: "No wire contract, payload shape or endpoint touched. Nothing crosses the client-server seam in this diff." }
related_bugs:
  - e7c3b9
recurrence: |
  Second instance of the same class. `e7c3b9` (2026-08-05) swept the
  prescriptive doc zones and its B-pass caught that its completeness grep had
  an input set of 3 directories while its artifacts stated the conclusion
  unscoped — which is what filed OI-91. This batch closes the remaining zone
  AND the renumbering sub-class that neither sweep's grep could see.

  The durable difference this time is the gate: `e7c3b9` fixed sites, this
  fixes sites and makes regrowth fail the build. The class is
  "a check is only as wide as its input set" — the same shape as the
  source-grep-false-confidence family documented at `memory/MEMORY.md:8`.
  (Only two `feedback_*.md` files are actually committed to this repo; the
  rest of that family lives in a harness-local directory a fresh clone cannot
  read, so the class is named in words here rather than by an unfollowable
  filename.)
---

# b2f7a4 — 138 dead §N citations in code, and 11 that pointed at a real but wrong section

## Writers and readers, named before the fix (§4.1)

Unusually for this repo, the "writer" and "reader" here are not code paths —
they are documentation surfaces, and the drift is the same shape.

- **Writer:** root `CLAUDE.md`, whose heading set is the authority. Real
  headings today: `0, 1, 2, 2a, 3, 4, 5, 6, 7` (`CLAUDE.md:22-494`).
- **Readers:** 227 anchored `§N` citations across `.dart` / `.ts` / `.js` /
  `.sql` comments — 138 of which named a section the writer no longer has.
- **The gate that should have caught it:** `check_claude_md_citations.dart:41-50`,
  whose file list was root `CLAUDE.md`, `AGENTS.md`, `lib/**/CLAUDE.md`,
  `supabase/**/CLAUDE.md`. Source comments were never in its input set.

## Why the count moved during the fix

Worth recording, because a moving number normally means a mistake.

| Reading | Value | Why |
|---|---|---|
| Board's survey grep, at filing | 138 | filter: "outside §0-§7" |
| Same grep, after fixing the gate's own dead citation | 137 | the gate cited a dead `§17` in its own statute comment |
| New gate, enforced | 138 | 137 + `ist_date.dart:4 → §3.1`, which the board's filter cannot see |

The gate is strictly more accurate than the grep that produced OI-91's number:
it validates against real headings, so it catches a citation to a nonexistent
SUBSECTION of a live section. It still cannot catch a citation to a real
section that is semantically the wrong one — that half needed reading, and
found 11.

**Why it's 11, not 12.** Two independent reviewers (a B-pass finding and a
plan-review round) each re-derived the §19 count from the diff text and got
12, both by the same mechanism: `test/contracts/supabase_functions_no_cerebras_openrouter_test.dart:10`
carries the bare word "§19" in the same sentence as a real, separately-cited
`§11` ("`lib/CLAUDE.md` §11 model matrix and §19 entry..."), and a diff-level
`grep -c '^-.*§19'` counts that incidental word as a second removed citation
on that file. It isn't one: the code zone's own anchor pattern
(`CLAUDE\.md.{0,3}§N`) requires "CLAUDE.md" within 3 characters of the "§", and
that "§19" sits 20+ characters from the nearest "CLAUDE.md" token — it was
never a live, gate-anchored citation, just prose naming the retired entry
next to the line's real (and separately fixed) `§11` citation. Re-verified
directly against a clean pre-fix extraction (`git archive HEAD | tar -x`,
then the board's own survey regex restricted to `§19`): exactly 11 matches,
11 distinct files, and the grand total across all sections is exactly 138 —
both reproduced fresh, not read from a prior run. The 125-mechanical /
13-judged split in the closure ledger is unaffected: the 13 already accounts
for all 11 §19 files, this file's own dual §11+§19 handling as one judged
fix, and the `ist_date.dart` §3.1 wrong-but-live fix.

## What this does not close

Sub-class 2 is now measured for the code zone, not eliminated as a class. A
citation of `§4.4` that should say `§4.5` still reads as correct to both the
gate and the grep. The gate raises the floor; it does not replace reading.

**Gate 26 has no `docs/` zone.** Both zones (markdown contract files, code
comments) stop at `lib/ test/ scripts/ supabase/ integration_test/` and the
handful of `CLAUDE.md`/`AGENTS.md` files — `docs/**` is scanned by neither,
even though 96 of the 138 rewritten citations in this batch now point INTO
`docs/architecture/*.md`. Those destination files are themselves not immune
to the bug class this batch fixes: `docs/architecture/ai.md:40` carried a
live wrong-but-live citation (`§6 rule 1`, from the same old-§6-is-the-coding-
rules confusion fixed elsewhere in this diff) — found by B-pass, fixed in
this commit, but not by any mechanism that stops a new one from appearing.
Extending Gate 26 to `docs/` needs its own false-positive analysis (prose
docs likely cite external specs/RFCs differently than code comments do) and
is deliberately not bundled into an already-catastrophic-tier diff. Filed as
OI-99.

**The anchored regex has two narrow, currently-inert gaps**, found by two
independent reviewers constructing counter-examples: the `.{0,3}` window
between `CLAUDE.md` and `§` doesn't match natural phrasing with a wider gap
(`"CLAUDE.md, section §19"`, `"CLAUDE.md (§7)"`); and the capture group only
supports one dot, so a fabricated `§4.1.99` truncates to the real `§4.1` and
silently validates. Neither currently produces a wrong result in the swept
zones (checked directly: the one live 2-dot citation in scope, `§4.12.1` in
`lib/shared/services/pro_phase_advance.dart:384`, happens to be semantically
correct even truncated). Left as a known limitation rather than widened here
— widening the anchor window reduces precision in the other direction (see
the 299-non-root-token problem above), and multi-dot support needs its own
negative-test pass.

**Duplicate citations on one line double-report, and interact with the
30-item output cap.** Two identical dead citations on the same source line
(`// CLAUDE.md §15 and CLAUDE.md §15 again`) print as two identical findings
rather than one; more consequentially, `broken.addAll(brokenInCode)` appends
code-zone findings after markdown-zone findings and the combined list is
then `.take(30)` for display. A repo with more than 30 markdown-zone breaks
would silently truncate every code-zone finding from the printed output
(the summary count stays correct; only the itemised list would be short).
Not currently live — both zones report 0 breaks — found by Hermes L26.
Fixing it means reworking the merge/cap logic, which is gate-internals work
outside a citation-content sweep; left as a known limitation rather than
bundled in.

The repo-wide unfollowable-`feedback_*.md`-citation problem (64 sites) is
untouched and is a separate concern — noted here only because OI-91 sits
next to it in the docs-rot class.
