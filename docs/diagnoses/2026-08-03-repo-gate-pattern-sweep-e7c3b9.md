---
bug_id: e7c3b9
date: 2026-08-03
batch: repo-gate-pattern-sweep (Unit 2 of the 4-unit batch that succeeded terms-accepted-fix, 2026-08-03)
status: fixed
blast_radius: feature
symptom: >
  The terms-accepted-fix batch (b3f9e7) hit 3 pre-existing gate-tripping
  content bugs only when its commit finally reached the full gate loop for
  the first time (earlier attempts failed before reaching it). A repo-wide
  sweep for siblings of those 3 patterns found: (1) a stale §N cross-doc
  citation that "passes" Gate 26 only by numeric coincidence
  (`lib/shared/widgets/wardroom/CLAUDE.md:94`); (2) 2 sites citing a CLAUDE.md
  §19 that has never existed since a prior renumbering
  (`.claude/skills/debugging/SKILL.md:56,80`), outside Gate 26's scan set
  (`.claude/skills/` isn't walked) so nothing caught them; (3) a genuine gate
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
contract_test_path: >
  Gate 26 (scripts/check_claude_md_citations.dart) has no dedicated test
  file today — verified by glob, none existed before this fix either. The
  regex fix was proven by negative control instead (see
  regression_test_planned) rather than adding a new permanent test file for
  a 2-line regex widening, per the no-gold-plating principle — a full test
  harness would be new scope beyond what this sweep called for.
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
  spec doc explicitly; (2) reword both debugging-skill citations to point at
  docs/playbook/common-pitfalls.md, the fix bug-class 2.17 itself
  prescribes; (3) widen Gate 26's heading + citation regexes from
  `\d+(?:\.\d+)?` to `\d+[a-z]?(?:\.\d+)?` so letter-suffixed sections like
  "2a" are tracked and validated on their own identity instead of silently
  colliding with a numerically-similar unrelated section; (4) extract/trim 4
  narrative comment blocks in restoring_screen.dart that duplicated content
  already fully captured in lib/features/auth/CLAUDE.md or a cited
  diagnose-doc, replacing each with a short pointer (800 -> 767 lines, 33
  lines of real margin restored) — 2 of the 4 trims also corrected content
  that had gone stale relative to the code (the class doc comment said "15
  second safety net" when Theme D had already moved the CTA to 30s); (5) no
  fix for pattern 3 (SoT registry) — swept clean.
regression_test_planned: >
  No new permanent test file (see contract_test_path). Each fix verified
  directly against its own gate/tool: `dart run
  scripts/check_claude_md_citations.dart` — PASS (16 files). Proven to
  DISCRIMINATE, not just coincidentally pass, by negative control:
  temporarily renamed CLAUDE.md's "## 2a." heading to "## 9a." and re-ran the
  gate -> FAIL, 4 broken §2a citations correctly reported (root CLAUDE.md:124
  + supabase/functions/CLAUDE.md ×3) -- proving the widened regex tracks "2a"
  as its own identity rather than resolving via the old accidental "2"
  collision. Restored immediately after (confirmed `git diff CLAUDE.md`
  empty). `dart run scripts/check_god_screen_max_lines.dart` — PASS, "no
  screen exceeds 800 lines" (restoring_screen.dart now 767, 33-line margin,
  vs 0 before). `dart analyze scripts/check_claude_md_citations.dart` and
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
`if (lineCount > _maxLines)` check (`_maxLines = 800`, `scripts/check_god_screen_max_lines.dart:28,97`).
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
line-count trim. Net: 800 → 767 lines, 33 lines of real margin.

**Pattern 3 — SoT registry enclosing-method-name-vs-interior-range:** zero
instances anywhere in the 8438-line registry (562 entries checked; the 7
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
