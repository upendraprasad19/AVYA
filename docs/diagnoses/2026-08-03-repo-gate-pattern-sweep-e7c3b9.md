---
bug_id: e7c3b9
date: 2026-08-03
batch: repo-gate-pattern-sweep (Unit 2 of the 4-unit batch that succeeded terms-accepted-fix, 2026-08-03)
status: fixed
blast_radius: account
symptom: >
  The terms-accepted-fix batch (b3f9e7) hit 3 pre-existing gate-tripping
  content bugs only when its commit finally reached the full gate loop for
  the first time (earlier attempts failed before reaching it). A repo-wide
  sweep for siblings of those 3 patterns found: (1) a stale §N cross-doc
  citation that "passes" Gate 26 only by numeric coincidence
  (`lib/shared/widgets/wardroom/CLAUDE.md:94`); (2) **20** sites in the
  PRESCRIPTIVE doc/skill zones citing a CLAUDE.md section that does not exist
  (root's real headings are only 0,1,2,2a,3,4,5,6,7) — or, in 2 cases, one
  that exists but is the WRONG section. Spread across
  `.claude/skills/debugging/SKILL.md`, `.claude/commands/build-apk.md`,
  `.claude/agents/writer-reader-drift-detector.md`,
  `.claude/skills/update-docs/references/path-mappings.md`,
  `docs/audit/AUDIT_PLAYBOOK.md`, `docs/audit/LENS_REGISTRY.md`, and
  `docs/naming_conventions.md` (9 of the 20 — and CLAUDE.md §4.7 MANDATES
  reading that file before introducing any name).
  **This count was wrong THREE times before landing:** the original sweep
  claimed 2, round-1 review found a 3rd, round-2 re-derived by grep and found
  5 more, and the B-pass found the grep's own input set was 3 directories
  rather than the mandated-doc set. No gate covers any of these paths — Gate
  26 walks only root CLAUDE.md, AGENTS.md, `lib/**/CLAUDE.md`,
  `supabase/**/CLAUDE.md`. **Scope, stated because it was over-broad once:**
  in-code comments under `lib/`/`test/`/`scripts/`/`supabase/` were NOT swept
  — 138 dead citations remain there, filed as OI-91;
  (3) a genuine gate
  hole — Gate 26's heading/citation regexes had no letter-suffix support, so
  every `§2a` citation (root CLAUDE.md's own "2a. SUPABASE PROJECT" section)
  validated only by accidentally colliding with the unrelated "2. TECH
  STACK" heading, providing zero real protection; (4)
  `lib/features/auth/screens/restoring_screen.dart` sitting at exactly the
  800-line ceiling with zero margin (230/800 lines were comments), one
  addition from tripping Gate 43; (5) the SoT registry's
  enclosing-method-name-vs-interior-range pattern (the third b3f9e7 bug) —
  swept clean, zero recurrences in 562 entries.
concept: repo_gate_content_hygiene
sot_registry_entry: not_applicable — no writer/reader contract touched; this
  batch fixes documentation citations and a validator script's regex, not
  application code. (Pattern 3's sweep found the SoT registry itself clean —
  no entry needed a fix.)
writers: >
  Not applicable — no Hive/Postgres writer touched. The only executable code
  changed is scripts/check_claude_md_citations.dart (Gate 26), a pre-commit
  validator, not an app runtime writer.
readers: >
  Not applicable — same reasoning. Gate 26 itself is the only "reader"
  affected (of CLAUDE.md heading/citation text), and its behavior is the
  subject of this fix.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/scripts/claude_md_citations_letter_suffix_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >
  - Container(color:+decoration:) — n/a, no widget touched.
  - unawaited() without an error sink — n/a, no async code touched.
  - .functions.invoke without FunctionException handling — n/a.
  - Source-grep without stripping comments — n/a, no source-grep test added.
  - BuildContext across an async gap — n/a.
  - Deferral euphemism (§4.2, Gate-DEU) — checked this doc's own prose for
    the banned phrase list (docs/deferral_euphemisms.yaml) before staging;
    none present. (Unit 1's diagnose-doc in this same session's earlier
    commit DID trip Gate-DEU on one of the banned "*batch" provenance
    phrases (docs/deferral_euphemisms.yaml entries #2-4) — a genuine false
    positive on accurate lineage wording, fixed by rewording rather than
    editing the shared phrase list, since weakening a shared gate to unblock
    one's own commit is exactly the kind of self-serving change this
    project's discipline history warns against.)
proposed_fix: >
  5 independent, small fixes: (1) reword the wardroom citation to name the
  spec doc explicitly (and, after round-1 review S4, DROP the `§` sigil there
  entirely — the prose rewording alone left Gate 26 still capturing "3" and
  still resolving it against root's unrelated "## 3. SCREENS", i.e. the
  coincidence the finding was filed against was unchanged); (2) reword the
  §19 citations to point at a live target — the two debugging-skill ones to
  docs/playbook/common-pitfalls.md (the fix bug-class 2.17 itself
  prescribes), and the THIRD one round-1 review caught
  (.claude/commands/build-apk.md:238) to `.claude/skills/debugging/SKILL.md`
  §2.12, which is where that exlog-duplicate content actually lives —
  common-pitfalls.md does not cover it, so pointing there would have swapped
  one dead pointer for another; (3) widen Gate 26's heading + citation regexes from
  `\d+(?:\.\d+)?` to `\d+[a-z]?(?:\.\d+)?` so letter-suffixed sections like
  "2a" are tracked and validated on their own identity instead of silently
  colliding with a numerically-similar unrelated section; (4) extract/trim 4
  narrative comment blocks in restoring_screen.dart that duplicated content
  already fully captured in lib/features/auth/CLAUDE.md or a cited
  diagnose-doc, replacing each with a short pointer (33-line reduction; see
  the line-count note below for the endpoints, which MOVED after this branch
  was refreshed onto a newer main) (800 -> 767 lines at authoring, 33
  lines of real margin restored) — 2 of the 4 trims also corrected content
  that had gone stale relative to the code (the class doc comment said "15
  second safety net" when Theme D had already moved the CTA to 30s); (5) no
  fix for pattern 3 (SoT registry) — swept clean.
regression_test_planned: >
  `test/scripts/claude_md_citations_letter_suffix_test.dart` — 3 tests,
  ADDED in the round-1 fix round. Round 1 left this open as arguable ("a
  2-line regex widening, no gold-plating"); it is not arguable for a GATE —
  with no test, a future revert of `[a-z]?` silently restores the very
  collision this fixed and every §2a citation goes back to validating
  against the unrelated §2. The test drives the REAL script as a subprocess
  against a throwaway fixture dir (the gate resolves all paths from CWD),
  NOT a mirrored copy of the regexes — a copy would keep passing after a
  revert, which is the same false-confidence class as a source-grep test.
  Negative-controlled by execution: reverting citeRegex to the pre-fix
  `§(\d+(?:\.\d+)?)` makes the "THE REGRESSION" case FAIL
  (`Expected: not <0> / Actual: <0>` — the gate accepted a §2a citation with
  no ## 2a. heading), while the other 2 cases correctly stay green; the
  script was then restored from a byte-copy and md5-verified identical.
  Additionally, each fix was verified directly against its own gate/tool:
  `dart run
  scripts/check_claude_md_citations.dart` — PASS (16 files). Proven to
  DISCRIMINATE, not just coincidentally pass, by negative control:
  temporarily renamed CLAUDE.md's "## 2a." heading to "## 9a." and re-ran the
  gate -> FAIL, 4 broken §2a citations correctly reported (root CLAUDE.md:124
  + supabase/functions/CLAUDE.md ×3) -- proving the widened regex tracks "2a"
  as its own identity rather than resolving via the old accidental "2"
  collision. Restored immediately after (confirmed `git diff CLAUDE.md`
  empty). `dart run scripts/check_god_screen_max_lines.dart` — PASS.
  ⚠ CORRECTED after round-1 review (S2/S3): the endpoints below moved when
  this branch was refreshed onto a newer main that had itself added ~24
  lines to the same file. Post-refresh the file is **791** lines (not 767),
  giving **9** lines of margin (not 33) — the 33-line REDUCTION this branch
  contributes is unchanged. Also note the gate's PASS is no longer
  load-bearing evidence on its own: main added restoring_screen.dart to the
  Gate 43 allow-list, so the gate now short-circuits before the
  `lineCount > _maxLines` check and would print OK at any size. The 791
  figure below was confirmed by direct `wc -l`, not by the gate.
  `dart analyze scripts/check_claude_md_citations.dart` and
  `flutter analyze` on the touched lib/ file — 0 issues both.
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "1 lib/ file touched (restoring_screen.dart, comment-only, no logic change). `flutter analyze lib/features/auth/screens/restoring_screen.dart` — 0 issues. `dart analyze scripts/check_claude_md_citations.dart` — 0 issues." }
  - { tier: 2_hive, status: not_applicable, evidence: "No Hive read/write touched anywhere in this batch." }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "No data touched." }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "No supabase/functions/ file touched." }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "No cron touched." }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9_storage, status: not_applicable, evidence: "No bucket/object touched." }
  - { tier: 10_secrets, status: not_applicable, evidence: "No secret touched." }
  - { tier: 11_external_services, status: not_applicable, evidence: "No external service touched." }
  - { tier: 12_client_server_contract, status: not_applicable, evidence: "No client-server contract exists for documentation citations or a pre-commit validator script; nothing here participates in a runtime request/response chain." }
impact_analysis: >
  Zero runtime user impact — every change is either doc-citation wording, a
  validator regex, or comment-only trimming. The value is process-safety:
  Gate 26's §2a hole meant the gate provided ZERO real protection for 7
  citation sites (4 of them within Gate 26's own scan set) despite appearing
  green; a future edit to the "2a" section heading (typo, rename, removal)
  would have silently broken every citing site with the gate still reporting
  PASS. restoring_screen.dart's zero-margin state meant the very next
  necessary comment (e.g. documenting the next bug fixed in this file) would
  have hard-blocked that unrelated future commit at pre-commit time,
  discovered mid-batch rather than proactively.
---

# e7c3b9 — Repo-wide sweep for the 3 gate-tripping patterns b3f9e7 hit

Unit 2 of the 4-unit batch that succeeded diagnose b3f9e7 (terms-accepted-fix,
2026-08-03). Closes the investigation `task_e6fbc0c1` was spawned to run.

## What was actually wrong

b3f9e7's landing hit 3 pre-existing content bugs the gate loop had simply
never exercised against before (earlier commit attempts failed upstream, on
`flutter test`, before reaching the ~72 `check_*.dart` gates). This batch
swept the repo for siblings of each pattern before they surface one at a
time in future unrelated commits.

**Pattern 1 — cross-doc `§N.M` citations that pass Gate 26 by numeric
coincidence, not genuine resolution:**

1. [`lib/shared/widgets/wardroom/CLAUDE.md:94`](lib/shared/widgets/wardroom/CLAUDE.md:94)
   cited "APK Test #4 hotfix §3 U7" — a bare `§3` that numerically resolves
   against root CLAUDE.md's unrelated `## 3. SCREENS (5 Tabs)`, when it
   actually meant `docs/superpowers/specs/2026-04-28-apk-test-4-hotfix-batch-design.md`'s
   own `§3` (`### U7`, confirmed to exist at that doc's line 217). **Fixed**
   by naming the spec doc explicitly.
2. [`.claude/skills/debugging/SKILL.md:56`](.claude/skills/debugging/SKILL.md:56)
   and [`:80`](.claude/skills/debugging/SKILL.md:80) cited a `CLAUDE.md §19
   "COMMON BUGS TO AVOID"` that has not existed since a prior renumbering
   (`grep -n "^## 19" CLAUDE.md` → no match). Never caught by Gate 26 because
   `.claude/skills/*/SKILL.md` files are outside its scan set (only
   `CLAUDE.md`/`AGENTS.md`/nested `*CLAUDE.md` are walked) — genuinely
   dead-ends a reader with no gate to catch it. Ironic: this same file
   documents this exact defect class as its own bug-class 2.17 ("Broken
   intra-doc pointer") and claims a prior sweep fixed 44 instances; these 2
   were apparently missed because nothing re-scans skill files. **Fixed** by
   rewording both to cite `docs/playbook/common-pitfalls.md`, the pattern
   2.17 itself prescribes.
3. **Structural gap — Gate 26 itself had zero real letter-suffix
   support.** Root CLAUDE.md's own `## 2a.` heading
   (`SUPABASE PROJECT — CONFIRMED IDENTITY`) didn't match Gate 26's heading
   regex (`\d+(?:\.\d+)?`, digits/decimal only), so "2a" was never added to
   `knownSections`. Every `§2a` citation "passed" only by the citation
   regex truncating `§2a` to captured group `"2"`, which DOES exist
   (`## 2. TECH STACK`) — an accidental collision, not real validation.
   **Fixed** by widening both `headingRegex` and `citeRegex` in
   `scripts/check_claude_md_citations.dart` (now lines 34 and 57) from
   `\d+(?:\.\d+)?` to `\d+[a-z]?(?:\.\d+)?`. Verified to genuinely
   discriminate now (not just still-accidentally-pass) via negative control
   — see `regression_test_planned`.

**Pattern 2 — screens at risk of the 800-line comment-driven ceiling:**
`lib/features/auth/screens/restoring_screen.dart` was exactly 800 lines
(the same file b3f9e7 already trimmed once), 230 of them (28.75%) `//`/`///`
comments, zero margin — confirmed via `wc -l` + the gate's own
`if (lineCount > _maxLines)` check (`_maxLines = 800`, `scripts/check_god_screen_max_lines.dart:28,103`).
**Fixed** by extracting/trimming the file's 4 largest narrative comment
blocks (class doc-comment, the Theme-D threshold rationale, `_goHome`'s
background-restore rationale, the dc52a4 post-auth-bootstrap relocation
note) down to short pointers at diagnose-docs and
`lib/features/auth/CLAUDE.md`'s already-more-detailed sections — the same
"flag WHERE + WHY-here, don't re-derive the whole argument" principle
b3f9e7 already applied once. Two of the four trims also corrected content
that had drifted stale relative to the code itself (the class doc-comment
still said "15-second safety net" after Theme D moved the escape CTA to
30s with a separate 15s soft hint) — a genuine accuracy fix, not just a
line-count trim. Round-1 review (S1) caught that this trim moved the reader
to `lib/features/auth/CLAUDE.md`, which carried the SAME stale claim in two
places ("15-second CONTINUE escape"); both were corrected here, so the
pointer now leads somewhere accurate rather than relocating the staleness.

Net: **−33 lines**. Endpoints at authoring were 800 → 767; after this branch
was refreshed onto a newer main (which had added ~24 lines to the same
file), they are **824 → 791**, i.e. 9 lines under the ceiling rather than
33. 791 confirmed by direct `wc -l` in the refreshed worktree.

**Follow-up this enables (NOT done in this diff):** main currently keeps
this file passing Gate 43 via an allow-list entry
(`scripts/check_god_screen_max_lines.dart`, added 2026-08-03 with founder
authorization) tracked as **OI-88**, whose own text says the entry should be
removed by a real fix. At 791 the exemption is unnecessary — removing it in
the follow-up commit is what actually closes OI-88 and makes the ceiling
live again for this file. Until then the gate short-circuits on the
allow-list and its PASS proves nothing about this file's size.

**Pattern 3 — SoT registry enclosing-method-name-vs-interior-range:** zero
instances anywhere in the registry **as swept at the authoring base** —
8438 lines / 562 entries then; the file is **8505** lines now, because the
refresh merge added ~67 lines including the three `restoring_screen.dart`
entries whose `line_range:` values this branch itself invalidated (B-pass
P1-A) and had to correct. Those 67 lines were re-checked for the pattern
after the refresh; still zero. (the 7
other `_ensureLocalUser`-adjacent entries are already correctly phrased as
prose, confirming the original b3f9e7 fix generalized). **No fix needed —
verified clean.**

## Related bugs

Same commit-reached-gate-loop-late origin as **b3f9e7** (2026-08-02) — that
batch's 3 content bugs were the seed observations for this sweep, not a
recurrence of b3f9e7 itself.

## Verification

`dart run scripts/check_claude_md_citations.dart` — PASS, 16 files, negative-
control-confirmed discriminating. `dart run scripts/check_god_screen_max_lines.dart`
— PASS, no screen exceeds 800 lines. `flutter analyze` + `dart analyze` on
every touched file — 0 issues.

## Round-1 independent review (context-blind, per CLAUDE.md §4.12)

Verdict: NOT CONVERGED. 2 blocking + 5 should-fix, all resolved in this round.

**The reviewer's most valuable single act was mechanical, not analytical:** it
stripped every `//`-leading and blank line from `main:restoring_screen.dart`
and `HEAD:restoring_screen.dart` and diffed what was left — **542 code lines
on each side, byte-identical**. That is what actually establishes the
"comment-only trim" claim on an auth post-boot path. Reading the diff by eye
would not have.

**B1 (blocking) — the "repo-wide sweep" was not repo-wide.** A THIRD dead
`CLAUDE.md §19` citation survived at
[`.claude/commands/build-apk.md:238`](.claude/commands/build-apk.md:238),
while this doc and closure finding P1-2 both asserted "2 sites" and marked the
pattern closed. Worse placement than the two that were fixed — the operational
build command, i.e. the highest-traffic reader. Fixed, and both artifacts
corrected to say three. The lesson is specific: a sweep that enumerates its
own hits in prose must have that count re-derived by grep at review time, or
the prose becomes the evidence for its own completeness.

**B2 (blocking) — `blast_radius: feature` was wrong; it is `account`.**
`blast_radius_from_diff.dart` over the real branch diff returns `account`
(driven by `lib/features/auth/screens/restoring_screen.dart`), so §4.12's ×2
review + `docs/plan-reviews/repo-gate-pattern-sweep.md` and §4.3's
self-initiated B-pass were all owed and none existed. The wrong field is
precisely what would let a reader conclude none were required. The field is
corrected; the record and B-pass are produced before the merge (round-2
review R2-S2 correctly flagged that this sentence originally claimed them in
the past tense while the file did not yet exist — the same
prose-asserts-its-own-completeness class as B1 below).

**S1 — the trim relocated staleness instead of removing it.** Two of the four
trimmed comment blocks were replaced with pointers to
`lib/features/auth/CLAUDE.md`'s "Post-auth flow" — but that file carried the
SAME stale claim in two places (`:67` "15-second timeout safety: CONTINUE
button surfaces", `:110` "15-second CONTINUE escape") when the code is
`_softHintAfter = 15s` / `_ctaAfter = 30s`
([`restoring_screen.dart:72-73`](lib/features/auth/screens/restoring_screen.dart:72)).
So a maintainer following the new pointer would read the wrong number and
edit the wrong constant. Both sites now state both stages explicitly. This
doc previously claimed the trim *corrected* drift; it corrected the in-file
copy and aimed the reader at an equally-stale doc.

**S2 — stale line-count endpoints** (800→767 at authoring; 824→791 after the
refresh merge) and a drifted script citation (`:97`→`:103`). Corrected in
both this doc and the closure YAML. The −33 delta was always right; only the
endpoints moved.

**S3 — the cited Gate 43 PASS is no longer load-bearing evidence.** At the
authoring base it was real (the file was not allow-listed then). Post-refresh
`main` allow-lists it, so the gate `continue`s before the
`lineCount > _maxLines` check and would print OK at 900 lines. The 791 figure
stands, but on `wc -l`, not on the gate. Both artifacts now say so — a green
check standing in for a measurement is the same class as a source-grep
standing in for a behavioral test.

**S4 — P1-1's fix did not remove the coincidence it was filed against.** The
wardroom citation still carried a bare `§3` that Gate 26 captured and resolved
against root's unrelated `## 3. SCREENS`; its `verification:` field
("check_claude_md_citations.dart — PASS") was vacuous, since it passed
identically before. The `§` sigil is now dropped so the gate stops claiming
jurisdiction over a foreign document's numbering.

**S5 — `contract_test_path:` held justification prose**, which rendered as a
400-character essay in `INDEX.md`'s "Test path" column where every other row
is a path. It now holds the real path (see below).

**Rule 21 — resolved rather than left arguable.** Round 1 flagged the missing
test for the regex change as genuinely rule-either-way. It is not, for a
GATE: nothing prevented a future revert of `[a-z]?` from silently restoring
the collision. `test/scripts/claude_md_citations_letter_suffix_test.dart` now
drives the real script as a subprocess and is negative-controlled by
execution (see `regression_test_planned`).

## Round-2 independent review (runs on the round-1-hardened state, per §4.12)

Verdict: NOT CONVERGED. 1 blocking + 2 should-fix, all resolved.

**R2-B1 (blocking) — B1 recurred one round later, in the same file, against
the lesson round 1 had just written down.** Round 1 found a third dead §19,
rated it blocking, and recorded the rule verbatim: *"a sweep that enumerates
its own hits in prose must have that count re-derived by grep at review time,
or the prose becomes the evidence for its own completeness."* Round 1 then
corrected the count 2 → 3 **by adding the one site it had been handed**, and
did not re-derive. Round 2 ran the grep and found **five more** — including
`.claude/skills/debugging/SKILL.md:502`, a near-verbatim twin of `:56`/`:80`
in the very file the sweep had already edited, and `:265`, a *template* that
instructs every future diagnose-doc to consider adding a "§19 entry".

Actual total: **8** sites (§19 ×6, plus the same class at §22 and §15). The
artifacts had asserted 2, then 3, both times with a `closed_in_commit`
terminal state — which is exactly the state Gate 40 cannot falsify, because
it recomputes the tally from the entries rather than from the repo.

Fixed, and this time completeness is established by a **command whose output
is in the record**, not by a sentence: re-run
`grep -rnoE 'CLAUDE\.md.{0,3}§[0-9]+[a-z]?(\.[0-9]+)?' .claude/ docs/audit/AUDIT_PLAYBOOK.md docs/playbook/`
and filter out §0-§7/§2a. Post-fix it returns exactly 2 hits, both
**provenance rather than pointers** — `docs/playbook/common-pitfalls.md:2`'s
`source:` frontmatter (recording what the file was migrated FROM) and
`SKILL.md:502`, whose new text explicitly says "§19, which no longer exists".
Zero prescriptive dead citations remain.

Targets were chosen per site rather than uniformly, because a repoint to a
wrong-but-live target is worse than the dead one it replaces (it looks
fixed): `:56,80` → `common-pitfalls.md`; `build-apk.md:238` →
`debugging/SKILL.md` §2.12 (common-pitfalls does not cover exlog keys);
`:503` §22 → `CLAUDE.md` §4.4 rule 22 (rule 22 is a numbered rule INSIDE
§4.4, never a section of its own); `writer-reader-drift-detector.md:7` §15 →
`docs/sot_registry.yaml`.

**R2-S1 — round 1's partial YAML edit left P1-2 self-contradictory.** It
updated the entry's `title:` to "THREE sites" but not the `verification:`
("both sites reworded") or `notes:` beneath it — and `notes:` asserted all
sites were pointed at `common-pitfalls.md`, which is *the exact target the
diagnose-doc argues against* for `build-apk.md:238`. A future auditor
reconciling the ledger would have read `notes:` as the record of what was
done, found no exlog content in `common-pitfalls.md`, and "repaired" the
citation back to the dead pointer. All three fields now agree.

**R2-S2 — the doc claimed the plan-review record and B-pass in the past
tense while neither existed yet.** Softened to state when they are produced.
Same class as B1: prose asserting its own completeness.

**Round 2 verified and found sound** (attacked directly, by execution): the
new gate test discriminates under *three* separate mutations — reverting
`citeRegex` alone fails only "THE REGRESSION", reverting `headingRegex` alone
fails only test 1, reverting both fails "THE REGRESSION" — so the two cases
form a complementary pair catching a partial revert of either regex; it
builds its own fixture, leaves no temp dirs, and matches the house
subprocess-gate-test pattern. Also confirmed correct: the §2.12 repoint
genuinely covers the promised content; the `auth/CLAUDE.md` timeout rewrite
matches the code *behaviour* (the reviewer read the timer callbacks, not just
the constant names — `:82-84` fires the soft hint, `:85-87` the CONTINUE CTA);
the wardroom `§` removal leaves the sentence meaningful and the gate silent;
and every changed number (791 / 824 / −33 / `:103` / `account`) re-measured
directly.

## B-pass (self-initiated per §4.3, ≥account) — and the §4.12 split signal

Verdict: rejected → 2 blocking + 2 non-blocking, all resolved. **This is the
third consecutive round to surface NEW material issues** (round 1: 2 blocking;
round 2: 1 blocking; B-pass: 2 blocking). §4.12 names that pattern explicitly
as the signal a unit is too large. The response here is not a fourth patch of
the same claim — it is to **scope the claim to what was actually swept and file
the rest as its own item (OI-91)**, so the record stops asserting more than it
verified.

**P1-A (blocking) — this branch invalidated three SoT-registry entries, and
aimed the drift detector at them in the same commit.** The comment trim removed
33 lines *above* three `restoring_screen.dart` methods whose `line_range:`
values were exactly correct against `main`. Post-trim: `_kickoffRestore`
`106-208`→ actually `91-193`, `_goHome` `226-278`→ `200-252`,
`_onContinueAnyway` `524-556`→ `491-525`. Both registry gates
(`check_sot_registry_completeness.dart:133`, `check_sot_registry_parity.dart:152`)
only assert `end <= lineCount`, and 278/556 stay in bounds under 791 — so both
PASS on a wrong map. Bounds-checking is strictly weaker than correctness
(`feedback_green_check_input_set_width`). Sharpest detail: the same branch
repoints `.claude/agents/writer-reader-drift-detector.md:7` **to that registry**
as "the canonical machine-readable SoT contracts" — it aimed the drift detector
at a map it was simultaneously invalidating. All three corrected against
measured method extents (not a uniform shift — comments inside the methods were
trimmed too, so start and end moved by different amounts).

**P1-B (blocking) — the completeness grep's input set was 3 directories, but
the conclusion was stated unscoped.** Round 2's "8 sites / zero prescriptive
dead citations remain" was true of `.claude/` + `AUDIT_PLAYBOOK.md` +
`docs/playbook/` and false of the repo. The B-pass re-derived repo-wide and
found the miss that matters: **`docs/naming_conventions.md` carries 9**, and
CLAUDE.md **§4.7 mandates reading that file before introducing any name** —
worse placement than several of the 8 already fixed (e.g. `:75` promises
"§15 'User-scoped Hive keys' for the 31-key migrated set"; `:123` promises
"§15 'Hive field-name contract'"). Also `docs/audit/LENS_REGISTRY.md:44`
(mandated by §4.8). All fixed; total in the prescriptive set is **20**, not 8.

**The filter itself was the deeper problem.** "Citations outside §0-§7/§2a" is
structurally blind to the **wrong-but-live** class — a citation resolving to a
real but incorrect section — which is exactly the class this batch argues is
worse than a dead pointer, because it looks fixed. Two were found only by
*reading*: `naming_conventions.md:293` cited "§6 — Coding rules" when §6 is
MULTI-TIER COVERAGE (the rules are §4.4), and
`.claude/skills/update-docs/references/path-mappings.md:21` pointed
"Discipline / process" at §3 = SCREENS instead of §4. Both inside the swept
zone; both invisible to the grep by construction.

**P2-A** — the "8438-line registry" figure was the pre-refresh base; it is 8505
now, and the ~67 added lines include the very three entries P1-A had to fix.
Re-swept; still zero instances of pattern 3. **P2-B** — the §15 repoint landed
on a bullet the next line already covered; merged.

**Residue filed, not buried:** `lib/`, `test/`, `scripts/`, `supabase/`,
`integration_test/` hold **138** dead citations in code comments, which Gate 26
cannot see (it walks markdown contract files, never `.dart` comments). That was
never in this batch's scope — its premise was sweeping siblings of b3f9e7's
doc/skill patterns — so it is filed as **OI-91** with the exact reproduction
command and the explicit warning that 138 is a floor, since the same filter
cannot count the wrong-but-live class.

**Verified sound by the B-pass** (attacked by execution, not inspection): the
comment-only claim re-proven mechanically (542 code lines each side,
md5-identical after stripping comments/blanks, and the strip method itself
validated — zero `/* */` blocks and zero multi-line strings in the file, so no
comment content can hide inside a kept line); the new gate test discriminates
under both single-regex mutations independently; all 20 repoint targets exist
AND deliver what their sentence promises; the `auth/CLAUDE.md` timeout text
matches the timer callbacks; every number re-measured (791 / 824 / −33 / `:103`
/ `account`). One latent item noted and not fixed: `citeRegex` still truncates
3-level cites (`§4.1.5` → `4.1`, passing by prefix collision — the same shape
as the `§2a` bug just fixed), inert today because zero 3-level citations exist
in Gate 26's scan set.
