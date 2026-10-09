# Unit 3 — Gate registry + red/green test rule

**Branch:** `gate-registry` · **Date:** 2026-08-10 · **Tier:** platform · **Status:** CONVERGED after
×2 context-blind review

Closes the two gaps the discipline research surfaced: (a) a gate number is **ambiguous** — "Gate 44"
names two unrelated scripts, so a citation cannot be resolved; (b) a gate can ship with a
**non-discriminating test** — one that passes whether or not the gate works, which is what Gate 44
had.

> **Review record (§4.12).** Every load-bearing finding below was independently re-verified against
> source by the main thread before acceptance (`feedback_audit_verifier_cannot_trust_own_subagent`).
>
> **Round 1** — two context-blind lenses, **3 P0 + 12 lesser**, all confirmed. v1 claimed 4
> collisions and a free Gate 45; both wrong, from one root cause — its input set omitted the closure
> ledgers, a number-minting surface. That made v1 the **sixth** instance of the failure its own §1.2
> was written to end. Round 1 also **inverted** the Gate 44 assignment (v1 read YAML line order as
> chronology) and surfaced a missed 5th collision (Gate 7).
>
> **Round 2 on the hardened plan** — **3 P0 + 5 P1 + 4 P2**; **two of the three P0s were introduced
> by round 1's own corrections**, which is precisely why §4.12 runs #2 on the post-#1 text:
> hard-fail 4's replacement over-fired on 4 existing library files, and source 4's new glob covered 6
> of 24 closure ledgers. Round 2 **inverted no decision** — it independently re-confirmed the Gate 44
> flip, the 5-collision set, the free numbers 49–54, the platform tier, and the A/B/C sequencing.
> Its findings are implementation-spec defects, all closed above before any code was written.
>
> **Two round-2 claims were checked and NOT adopted:** its narrowed regex `^//\s*Gate\s*:?\s*\d`
> still false-fires on `worktree_config_integrity_lib.dart:7` (the canonical form, which matches 0
> files today, is used instead); and its "32 of 84 gates referenced under `test/`" is wrong — a
> per-basename recount gives **33**.
>
> **Convergence call.** §4.12.1 says a unit that keeps yielding new material findings is too large —
> and the response it prescribes is *split and ship the smallest converged piece*, which §4 already
> does (A → B → C, all on this branch, all in this batch). Round 2 changed no decision, only
> specifications; a third round would be reviewing the same design. The B-pass (§6) is the backstop.

---

## 1. GROUND TRUTH

| Fact | Value |
|---|---|
| `scripts/check_*.dart` | **84** |
| Declare a number in their header (first 8 lines, any prose form) | **44** |
| Declare it in the canonical `// Gate: N` form | **0** — see §3.2 |
| Numbered ONLY by `.claude/commands/build-apk.md` | 2 — `check_exlog_key_canonical` (17), `check_nlog_key_canonical` (23) |
| Numbered ONLY by an audit closure YAML | 2 — `check_no_http_package` (**45**), `check_writeservice_only` (**7**) |
| Numbered gate outside `check_*.dart` | 1 — `validate_audit_closure.dart` (40) |
| Emit a runtime `[Gate N]` string | 40 |
| **Number collisions** | **5** — see §2 |
| Referenced by ANY file under `test/` | 33 of 84 |
| Assert a red path anywhere | 6–8 test files repo-wide (see §3.4 — the exact count is not the load-bearing fact) |
| `/build-apk` procedural gates with no script | 1, 2, 3, 3.5, 4, 5, 6 — **reserved** |
| Verified-free numbers | **49, 50, 51, 52, 53, 54** (0 hits across `docs/`, `scripts/`, `lib/`, `test/`, `.claude/`, `CLAUDE.md`) |

### 1.1 There is ONE namespace, not two

An earlier pass concluded `/build-apk` and pre-commit gates were **separate namespaces**, so a flat
registry would *invent* collisions and force harmful renames. **That is wrong.** Verified, and
confirmed independently by both reviewers: `build-apk.md`'s numbered sections 7–17, 23, 48 resolve to
the *same* scripts that declare those numbers in their own headers (7=`sot_registry_completeness`
`:156`, 8=`naming_audit` `:164`, 9=`writeservice_contracts` `:172`, 10=`bugfix_commits_have_diagnose`
`:180`, 13=`apk_size_within_bounds` `:294`, 48=`apk_release_signed` `:302`). One namespace, 1–6 + 3.5
reserved for procedural steps. A flat registry is correct.

### 1.2 Why the collision count moved 1 → 3 → 2 → 3 → 4 → 5

Six wrong answers across this session, each from a **too-narrow input set**: a `sed`/`awk` pair broken
by backslash escaping; a survey matching cross-references (`// Mirrors Gate 17`) as declarations; a
survey globbing `check_*.dart` only (blind to Gate 40); a regex requiring `Gate N` to be followed by
`:—-(` (blind to the `Gate 18.` and `Gate 18)` forms); and finally v1 of this plan, blind to the
closure YAMLs.

All six are `feedback_green_check_input_set_width`. **The canonical format (§3.2) and the widened
input set (§3.3) are the load-bearing parts of this batch** — they are what makes "which script claims
N" mechanically answerable at all, which it currently is not.

---

## 2. THE 5 COLLISIONS

### 2.1 The tiebreak ladder — stated BEFORE it is applied

Highest rung wins; ties fall through. **Rung 4 is a TIME, not a file offset** — v1 used YAML line
order as a proxy for chronology and inverted Gate 44 as a result.

1. The number is baked into an **on-disk artifact filename** the gate reads or writes.
2. The gate **emits `[Gate N]` at runtime** (user-visible behaviour, not prose).
3. A **live operational doc** cites it — `.claude/commands/`, `.claude/skills/`, `docs/operations/`,
   `docs/runbooks/`, `docs/handbook/`, `docs/playbook/`, any `CLAUDE.md`. If both claimants qualify,
   the one with MORE such citations wins; equal counts fall through.
   (`docs/diagnoses/`, `docs/audit/*.yaml`, `closed_issues.md`, `docs/reviews/`, `docs/plan-reviews/`
   are **historical records**, not live docs.)
4. **Earliest mint** — `git log -1 --format=%ad` on the commit named in the minting ledger entry.

### 2.2 Applied

| N | KEEPS it | rung | LOSES it → new | why it loses |
|---|---|---|---|---|
| **7** | `check_sot_registry_completeness.dart` | 2 — emits `[Gate 7]`; also `build-apk.md:156` | `check_writeservice_only.dart` → **49** | No header declaration, no runtime string; its only claim is `2026_05_20_audit_closures.yaml:237,315`. **Missed entirely by v1.** |
| **18** | `check_doc_internal_consistency.dart` | 2 — emits `[Gate 18]` ×4 | `check_reader_manifest_complete.dart` → **50**<br>`check_app_version_matches_pubspec.dart` → **51** | Neither emits a runtime string. Both claim "**build-apk** Gate 18" — and `git log -S "Gate 18" -- .claude/commands/build-apk.md` returns **no commits**, so that section has *never* existed. (v1 said "retired slot"; it was never minted.) |
| **19** | `check_hive_map_field_drift.dart` | 1 — reads/writes `backups/gate19_drift_baseline.txt` (`:45`, `:156`) | `check_schema_payload_parity.dart` → **52** | Both emit `[Gate 19]`, so rung 2 ties (the loser emits it 5×; renumbering rewrites those strings — a real cost, accepted). Rung 1 breaks it: renumbering the winner would orphan a 44 KB on-disk artifact. |
| **23** | `check_secrets_gitignored.dart` | 2 — emits `[Gate 23]` | `check_nlog_key_canonical.dart` → **53** | No header declaration and no runtime string. (It does hold 3 `common-pitfalls.md` citations, so v1's "only claim is the build-apk heading" was wrong — but rung 2 decides before rung 3.) |
| **44** | `check_nested_claude_md_content.dart` | 3 — **2** live citations (`.claude/skills/update-docs/SKILL.md:79`, `lib/CLAUDE.md:74`) vs 1 | `check_device_tests_exist.dart` → **54** | **v1 had this INVERTED.** Neither emits a runtime string. Rung 3 decides on citation count; rung 4 agrees — `18f0296` (Doc3 → nested_claude_md) is **2026-05-21 21:00:22**, `83bd4cb` (T1 → device_tests) is **21:43:40**, 43 min later. v1 read YAML line order (`:365` before `:723`) as chronology and got the opposite answer. Also: `:723` is finding **Doc3**, not "B5 D2" (`:387` is D2). |

**6 scripts renumber.** Separately, `check_exlog_key_canonical` (17), `check_nlog_key_canonical`
(→53), `check_no_http_package` (45) and `check_writeservice_only` (→49) carry **no** header
declaration today — their numbers live only in `build-apk.md` or a closure YAML. All four gain one.

### 2.3 Historical documents are NOT rewritten

Changed: each renumbered script's own source (header + every `[Gate N]` literal), and **live
operational docs citing that script's old number**:

- `.claude/commands/build-apk.md` — the `### Gate 23` section (→53)
- `.claude/skills/debugging/SKILL.md:445` — names `check_schema_payload_parity.dart` as Gate 19 (→52)
- `.claude/skills/writer-reader-drift-detector/SKILL.md:183` — names `check_writeservice_only.dart`
  as Gate 7 (→49). **Round-2 P1-4**: v2 said this script's "only claim" was the closure YAML; it also
  holds this live rung-3 citation. Left unedited, it would assert Gate 7 = `check_writeservice_only`
  while Gate 7 is `check_sot_registry_completeness` — exactly the wrongly-introduced citation §2.3
  exists to prevent.
- `docs/playbook/common-pitfalls.md:28` **only** — the one line that is a script citation
  (`Gate 23 (scripts/check_nlog_key_canonical.dart)`). v2 also listed `:21,37,57`; those are
  2026-05-24 **batch-log prose** ("1 new build gate (Gate 23 wired into build-apk.md)", "Gate 23
  added"), i.e. a record of what was true when written. Editing them would violate this section's own
  second half (round-2 P2-11). A batch log does not become historical-exempt merely by living inside
  a live doc — the granularity is the line, not the file.
- `docs/operations/DEVICE_TESTING.md:164` — Gate 44 → `check_device_tests_exist` (→54)

**NOT edited, contrary to v1** — both cite a *winner*, so editing them would inject a wrong citation:
`docs/audit/LENS_REGISTRY.md:119` (`check_secrets_gitignored`, keeps 23) and all of
`docs/handbook/process/secrets-pattern-audit.md:26,28,43` (same). v1's §5 verification greps for
*residual* hits and would not have caught a *wrongly introduced* one — §5 now checks both directions.

Diagnose-docs, `closed_issues.md`, closure YAMLs, `docs/reviews/`, `docs/plan-reviews/` are left
**verbatim** — they record what was true when written. `GATE_INDEX.md` carries a
**`## Historical aliases`** table so a grep of an old number resolves forward.

**Honest limit** (reviewer P2-12, accepted): for the 5 *collided* numbers the table can only
enumerate candidates. A pre-2026-08-10 citation of "Gate 18" stays ambiguous **by construction** —
the table fixes forward references, not the historical corpus. One case is called out by name in the
table: `CLAUDE.md:474` / `d7b3e9:122` "**the Gate-44 lesson**" resolves to *neither* script — it names
the lesson, not a gate, and no test for either claimant exists in the tree. That prose is left alone.

---

## 3. DESIGN

### 3.1 The registry keys on the FILENAME. The number is an optional alias.

The 40 unnumbered gates get **no** number. The filename is already unique, already the real identity,
already what every wiring surface keys on (`check_gate_scripts_wired.dart:144-149` globs filenames).
Minting 40 numbers would add 40 drift-capable facts and zero information.

**Forward minting rule** (reviewer P2-14, accepted — v1 left this undefined): a new gate takes **no**
number by default; if a `/build-apk` section needs one it takes `max(existing)+1`. The generator
prints the next free number on every run so the rule is executable, and states it in
`GATE_INDEX.md`'s header.

### 3.2 Canonical declaration format — `// Gate: <N>`

A gate that *has* a number declares it once, on its own line, in the first 10 lines:

```dart
// Gate: 44
```

The generator matches `^// Gate: (\d+[a-z]?)$` anchored at both ends, after `\r\n → \n`
normalization.

**Which anchor does what** (v1's rationale was wrong on all three examples — reviewer P2-9):
- `check_adr_index_fresh.dart:1` `// Gate: confirms docs/adr/INDEX.md…` — excluded by **`\d+`**, not
  the end-anchor. It is nonetheless a genuine day-one false-positive candidate for any looser regex.
- `// Mirrors Gate 17` — excluded by the **start anchor**.
- `// Gate 44 — Nested CLAUDE.md content quality` — excluded by the **missing colon**.
- `// Gate: 13 — APK size…` — excluded by the **end anchor**. *This* is the end-anchor's job.

The unit test asserts each exclusion **with its true cause**; v1 would have encoded a false
proposition that passed for the wrong reason.

**CRLF normalization is mandatory even though this repo has zero CRLF files today** (verified: 0 of
84; `.gitattributes` `* text=auto eol=lf` beats `core.autocrlf=true`). Precedent:
`check_sot_behavioral_test_paths.dart:55` normalizes explicitly. Without it a trailing `\r` kills the
`$` anchor, every declaration reads as absent, and the generator emits an index with **zero numbers
and zero collisions — green, and completely wrong**. A CRLF fixture test pins it.

**The 44-header migration is declared work** (~44 files, v1 hid it): every currently-numbered gate
gains a canonical line. This is commit A's bulk and §5 verifies it by count.

### 3.3 `scripts/build_gate_index.dart` → `docs/audit/GATE_INDEX.md`

Same shape and pre-commit wiring as `build_oi_index.dart` / `build_adr_index.dart`. Pure/IO split per
repo convention: `scripts/gate_index_lib.dart` (parsing + collision detection, zero filesystem) + a
thin IO script.

**Input set — six sources. Source 4 is the fix for v1's P0s:**
1. every `scripts/check_*.dart`;
2. explicit `_extraGateScripts` (`validate_audit_closure.dart` today);
3. `.claude/commands/build-apk.md` `### Gate N` sections → the script each runs;
4. **the closure ledgers** — a real minting surface, and the *only* claim Gate 45 and Gate 7 have.
   Missing it produced both v1 P0s. **Round 2 found v2's first cut of this source still blind on two
   axes, both verified and both fixed here:**
   - **File glob:** `docs/audit/*_closures.yaml` matches **6** files; `docs/audit/*.closure.yaml`
     matches **18** more. Both forms must be read — `validate_audit_closure.dart:79-83` already reads
     both, and §6 of this very plan cited that fact while §3.3 contradicted it. This batch's own
     `gate-registry.closure.yaml` is a `.closure.yaml`, so v2 would have excluded its own artifact.
   - **Mint pattern:** both `script.dart (Gate N` **and** the reverse `Gate N (script.dart)` occur.
     Verified reverse-form mints: Gate 24→`check_razorpay_key_flavor`, 42→`check_sot_behavioral_test_paths`,
     44→`check_device_tests_exist` (`oi_unit1_backlog.closure.yaml:70`). None of the three adds a new
     collision — the set stays at 5 — but a one-form regex goes blind the next time one does.
5. `scripts/pre-commit.sh` + `.github/workflows/test.yml` + Gate 33's `_allowList` — wiring facts;
6. references to each gate name anywhere under `test/`.

**A ledger mint is EVIDENCE, not law — added during execution, seen by neither review round.**
Source 4 makes closure ledgers a claim source, but §2.3 also forbids rewriting them. Those two rules
are in direct conflict the moment anything is renumbered, and the real corpus proves it rather than
merely implying it: `2026_05_20_audit_closures.yaml:237,315` mints Gate 7 for
`check_writeservice_only.dart`, which commit B renumbers to 49, so the generator hard-failed on a
collision that **cannot be corrected at its source**. Without a rule the registry is unbuildable
after any renumber.

Rule: a ledger mint creates a claim only for a script that declares **nothing** itself. Once a
script carries `// Gate: N`, its own declaration is authoritative and an older mint is **superseded**
and listed under `## Historical aliases → Superseded ledger mints`.

This is not a loophole, and two tests hold it to that: the collision check still runs across every
canonical declaration (two scripts declaring 49 still hard-fail even when one also has a superseded
mint), and a mint for an **undeclared** script still creates a real claim — which is exactly what
made Gate 45 and Gate 7 discoverable. Mutation: supersede *all* mints → 1 test red. (A first mutation
attempt targeted the `declared.number != mint.number` refinement and reddened nothing; that line
drops a *redundant agreeing* mint and is not protective. Reported rather than quietly recounted.)

**Sources 5 and 6 feed `--verbose` stdout ONLY; they are NOT baked into `GATE_INDEX.md`.** Reviewer
P1-4: baking volatile columns forces the regen trigger to cover `scripts/**` + `test/**` +
`test.yml` — nearly every commit — or the index goes stale while `check_gate_index_fresh` (which runs
on *every* commit via the loop) blocks it. Worse, the model it mirrors rebuilds **in place** and never
restores (`check_adr_index_fresh.dart:22-36`), so a blocked commit is left with an unstaged modified
index nobody asked for. Baking only stable columns makes the trigger exactly cover the inputs.

**Baked columns:** number (or `—`) · script · one-line purpose · ledger state. Plus
`## Historical aliases`, `## Reserved (1–6, 3.5)`, and the next-free-number line.

**HARD-FAILS (exit 1):**
1. two scripts claiming the same number, from *any* of sources 1–4;
2. a `build-apk.md` section number disagreeing with that script's own `// Gate: N`;
3. a closure-YAML mint disagreeing with the script's own `// Gate: N`;
4. **any file under `scripts/` whose first 10 lines carry a CANONICAL declaration
   (`^// Gate: (\d+[a-z]?)$`) but is absent from the index.**
   v1's rule was **vacuous** — it checked that a globbed `check_*.dart` appeared in output generated
   *from that glob*, which cannot fail — yet §6 credited it as the batch's key mitigation. Round 2
   then showed v2's replacement (loose `gate\s*:?\s*\d` over the first 10 lines) **over**-fires: it
   matches 5 non-gate files — `gate_scripts_wired_lib.dart`, `retire_worktree_lib.dart`,
   `worktree_guard_lib.dart`, `worktree_config_integrity_lib.dart` (all four are pure libs whose
   headers *say* "treat only the gate itself as a gate, not this lib") plus `validate_audit_closure.dart`.
   The builder would exit 1 forever, contradicting §7.
   **Round 2's proposed narrowing (`^//\s*Gate\s*:?\s*\d`) is ALSO insufficient** — verified: it
   still matches `worktree_config_integrity_lib.dart`, whose line 7 begins `// Gate 33) treat only
   the gate itself…`. Keying on the **canonical form** is the correct rule: **0 of 84 files match it
   today**, so there are no false positives by construction, and it is not circular — the scan is
   over all of `scripts/`, while the index is built from `check_*` + `_extraGateScripts`. A future
   `validate_*` that declares `// Gate: 55` without registering hard-fails, which is the real risk;
5. a number colliding with a reserved procedural number. `3.5` is not `\d+[a-z]?`, so reserved
   numbers are compared as **strings**, not parsed ints (reviewer P2-11).

`14b` is admitted by `\d+[a-z]?` and does not false-collide with 14. The registry surfaces one live
disagreement it exposes: `check_gate_scripts_wired.dart:60-61` cites "/build-apk skill Gate 14b" but
`build-apk.md` has no such section. Recorded in the index as a known gap; **not** fixed here (it is
not a collision, and widening scope is what round 1 punished).

Freshness: `scripts/check_gate_index_fresh.dart`, mirroring `check_adr_index_fresh.dart`.

### 3.4 Red/green rule + `docs/audit/gate_test_ledger.yaml`

**v1's ledger was unsatisfiable and is redesigned.** Both reviewers independently landed the same P0:
v1 grandfathered 51 gates (= 84 − 33 tested) and required the other 33 to carry
`mutation_proven: true`. But a `test/` reference is not mutation proof — only ~6–8 test files repo-wide
assert a red path at all. Going green on day one would have required **inventing ~26 false
attestations**, converting the ledger from weak-but-honest into an actively false record.

**Fix: grandfather on "not mutation-proven", not "not tested" — so all 84 existing gates are
grandfathered.** The rule binds new gates only. Three states, exactly one per gate:

```yaml
check_worktree_config_integrity.dart:
  mutation_proven: true
  test_path: test/scripts/worktree_config_integrity_lib_test.dart
  evidence: "Neutering the core.worktree probe reddens 4 tests (2 unit + 2 e2e)."
check_device_tests_exist.dart:
  grandfathered: 2026-08-10          # closed list
check_apk_release_signed.dart:
  test_exempt: "Needs a built APK + apksigner + JDK; no fixture is constructible in the suite."
```

`scripts/check_gate_test_ledger.dart` asserts every `check_*.dart` has exactly one state; a non-empty
`test_exempt` reason; and for `mutation_proven: true`:

- **`test_path:` is present and every file it names exists.** It is a **list**, not a scalar — the
  closest precedent (`retire_worktree`, CLAUDE.md §4.13 point 6) is mutation-proven across two files;
- **at least one names the gate script**;
- **at least one contains a red-path assertion**, from this **literal, closed** list of accepted
  forms (v2 left "or an assertion on a violating verdict" undefined, so the implementer would have
  invented one — round-2 P2-9): `exitCode, isNot(0)` · `exitCode, isNonZero` · `exitCode, 1` ·
  `exitCode, 2` · `expect(<x>.isViolation, isTrue)` · `expect(<x>.verdict, Verdict.violation)`.
  A pure `_lib_test.dart` therefore qualifies via the verdict forms — which matters because both of
  this batch's new gates are proven by pure lib tests.

**Membership is ENUMERATED BY NAME, not by date.** v2 said "a `grandfathered:` date equal to
`2026-08-10` and no other — the list is closed". It is not: any future gate could write that same
date and pass, and both gates *this* batch creates are themselves born on 2026-08-10, so the boundary
was ambiguous on day one (round-2 P1-6). The gate instead carries
`const _grandfathered = <String>{ …84 literal filenames… }` and requires any `check_*.dart` **not in
that set** to carry `mutation_proven` or `test_exempt`. A unit test asserts a new name with
`grandfathered: 2026-08-10` FAILS.

Those three are reviewer P2-13's correction and v1 had none of them. They matter because v1's claim
of "the same trust model as Gate 42 / the ship-dark tier" was **false**: Gate 42's *default* branch is
a greppable `behavioral_test_path:` with `presence_only:` as the narrow exception
(`check_sot_behavioral_test_paths.dart:102-117`), and the ship-dark tier sits inside a gate that
independently computes the tier from the diff (`check_plan_review_record_exists.dart:100-160`). v1's
ledger had a bare boolean cross-checkable against nothing — strictly weaker, not equal.

**What this does and does not solve.** A script still cannot prove a mutation was *run*. What it can
now prove is that the test **exists, names the gate, and asserts a failing path** — which is exactly
the class Gate 44 shipped, made mechanically impossible. The residue (was the mutation real?) is
self-attested and read by the ×2 review, same as everywhere else.

**CLAUDE.md §4.4 rule 24:**
> **24. Every NEW `check_*.dart` gate ships mutation-proven.** The same commit adds a test that FAILS
> when the gate's protection is deliberately neutered, and a `mutation_proven: true` entry in
> `docs/audit/gate_test_ledger.yaml` carrying `test_path:` and `evidence:` naming what was neutered
> and how many tests reddened. `check_gate_test_ledger.dart` requires the test to exist, reference the
> gate, and contain a red-path assertion. All 84 gates predating 2026-08-10 are enumerated
> `grandfathered:`; **that list is closed and the gate rejects any other date.**

### 3.5 Wiring

- `pre-commit.sh`: regen `GATE_INDEX.md` when the staged diff touches any of — `scripts/*.dart`
  (**not** just `check_*.dart`: source 2's `validate_audit_closure.dart` and `gate_index_lib.dart`,
  which holds `_extraGateScripts` and the aliases table, both feed **baked** columns and neither
  matches `check_*`), `.claude/commands/build-apk.md`, `docs/audit/*_closures.yaml`,
  **`docs/audit/*.closure.yaml`**, `docs/audit/closed_issues.md`, `docs/audit/gate_test_ledger.yaml`.
  Same shape as the five existing blocks at `pre-commit.sh:66,76,93,103,113`.

  This list is exhaustive over the **baked** inputs — v2 claimed the trigger "exactly covers the
  inputs" while omitting all three of the above (round-2 P1-7). Each gap reproduces the exact failure
  the stable-columns design was chosen to avoid: `check_gate_index_fresh` runs on every commit,
  rebuilds in place, and per `check_adr_index_fresh.dart:20-36` **never restores**, so a stale-index
  block leaves an unstaged modified file nobody asked for.
- Both new gates auto-wire via `for GATE in scripts/check_*.dart` (`pre-commit.sh:174`,
  `.github/workflows/test.yml:158`). No allowlist entry; Gate 33 stays green. Verified: regen blocks
  run **before** the gate loop, so no chicken-and-egg on the first commit.

---

## 4. SEQUENCING — three commits, all on this branch, all in this batch

**§4.11 requires it** (reviewer P0/recommendation, accepted): *"the regression-detection gate script
lives + is wired into pre-commit + CI **before** the first refactor commit lands."* Renumbering 6
scripts **is** the refactor; the generator **is** the detection gate. v1 shipped them in one commit,
violating §4.11 on its face.

This is **commit sequencing, not scope reduction** — §4.2 bans dropping work, not ordering it. A, B
and C all land on `gate-registry` and all merge to `main` in this batch. Nothing here is deferred.

- **Commit A — detection gate.** Canonical format + CRLF normalization + `gate_index_lib.dart` +
  `build_gate_index.dart` + `check_gate_index_fresh.dart` + the 48-header migration + `GATE_INDEX.md`
  generated **with all 5 collisions visible in it**. Zero renumbering risk. Its index is the ground
  truth B is checked against.

  **`build_gate_index.dart` needs its OWN `--warn-only`, not just the freshness gate** (round-2 P0,
  and a flat contradiction in v2): at commit A all 5 collisions still exist, so hard-fail 1 exits 1 —
  and every existing pre-commit regen block is `if ! dart run …; then exit 1; fi`
  (`pre-commit.sh:69-72,86-89,96-99,106-109,116-119`), so **commit A's own hook would block commit A**,
  and the baseline that §4.11 substitution depends on could never be produced. In `--warn-only` the
  builder still *writes* the index with the collisions marked `⚠ COLLISION`; it just exits 0. Commit
  A's regen block passes the flag; commit B removes it. The flag is covered by its own unit test
  (collisions present + `--warn-only` → exit 0 **and** the index contains the collision markers), so
  it cannot silently become a permanent escape hatch.
- **Commit B — the refactor.** The 6 renumberings + the 4 live-doc citation updates +
  `## Historical aliases` + flip the freshness gate to hard-fail.
- **Commit C — the rule.** `gate_test_ledger.yaml` (84 grandfathered + 2 new mutation-proven) +
  `check_gate_test_ledger.dart` + CLAUDE.md rule 24 + §7 pointer row.

§4.11's "warn-only for 24h" is satisfied within the batch by A→B ordering: A's index baselines the
existing violations and B is the commit that clears them. A 24-hour wall-clock soak on a
single-operator repo would be ceremony, not signal — stated explicitly rather than silently skipped.

---

## 5. TESTS

1. `test/scripts/gate_index_lib_test.dart` — pure. Canonical-format matching **with each exclusion
   asserted against its true cause** (§3.2); a CRLF fixture; duplicate detection across all four
   claim sources; build-apk-vs-header and YAML-vs-header disagreement; reserved-number collision
   including the string-compared `3.5`; `14b` admitted without false-colliding with 14.
2. `test/scripts/gate_index_e2e_test.dart` — scratch fixture dir, 3 fake gate scripts: clean → exit 0;
   duplicate `// Gate: 7` → exit 1 naming both; a `scripts/`-resident script matching
   `gate\s*:?\s*\d` but absent from the index → exit 1 (hard-fail 4, the one v1 made vacuous).
   `_cleanEnv()` copied **verbatim** from `test/scripts/worktree_config_integrity_e2e_test.dart:47-54`
   including the `PUSH_BEFORE` clause — `test/contracts/gate_e2e_env_hermetic_test.dart:57-67` asserts
   **all three** of `startsWith('GIT_')`, `startsWith('GITHUB_')` and `PUSH_BEFORE`, so v1's
   "scrub GIT_*/GITHUB_*" would have failed that meta-gate on registration.
3. `test/scripts/gate_test_ledger_lib_test.dart` — pure (named `_lib_test` per convention; v1's
   `gate_test_ledger_test.dart` matched neither). Missing entry → fail; two states → fail;
   `mutation_proven` without `test_path` → fail; a `test_path` file that does not exist → fail;
   exists but no entry names the gate → fail; names it but no red-path assertion → fail; a
   **name not in `_grandfathered`** carrying `grandfathered: 2026-08-10` → fail; a test file that
   passes the name check but fails the red-path check → fail.
4. `test/scripts/gate_index_fresh_test.dart` — **round-2 P1-5**: `check_gate_index_fresh.dart` is a
   NEW gate, so rule 24 binds it, and v2 gave it no test at all — the rule would have failed on its
   first application. Stale index → exit 1; fresh → exit 0.
5. **Register `gate_index_e2e_test.dart` — the ONE new e2e — in `gate_e2e_env_hermetic_test.dart`'s
   hand-enumerated `_helpers`** (v1 said "both e2e files" while naming one).
6. **Mutation proofs, named before execution** (v1 said only "the suite must redden" — below the bar
   CLAUDE.md §4.13 point 6 already set). Expected counts are predictions; any deviation is
   investigated before the commit lands, never rationalized after, and the ACTUAL counts go into the
   ledger's `evidence:`.
   - `gate_index_lib.dart`: make the duplicate-number check `return const []` → expect **≥4** unit
     tests + **1** e2e red.
   - `gate_index_lib.dart`: drop the `\r\n → \n` normalization → expect the CRLF fixture test red.
   - `build_gate_index.dart`: make `--warn-only` unconditional → expect the flag test + **1** e2e red
     (this is what stops the commit-A escape hatch becoming permanent).
   - `check_gate_index_fresh.dart`: make it always exit 0 → expect the stale-index test red.
   - `check_gate_test_ledger.dart`: make the state-count check accept >1 state → expect **≥2** unit
     tests red.
   - `check_gate_test_ledger.dart`: skip the red-path-assertion check → expect **≥1** unit test red.

Note: the new tests live in `test/scripts/`, which pre-commit does **not** run (`pre-commit.sh:62`
runs `test/contracts/` only). "The suite" for these means pre-push + CI.

## 6. REQUIRED ARTIFACTS (v1 omitted all of these)

**Tier is `platform`, deterministically** — `docs/blast_radius.yaml:68` (`CLAUDE.md`) and `:101`
(`scripts/pre-commit.sh`), both edited here. v1's "measure, don't assume" was right in spirit and
pointed the wrong way: the tier is knowable now.

- `docs/plan-reviews/gate-registry.md` — `review_rounds: >= 2`, `ground_truth_verified: true`,
  `verdict: converged`, **`bpass: accepted`** (unconditional at ≥platform,
  `check_plan_review_record_exists.dart:15-24`). `---` frontmatter, line-anchored keys
  (`feedback_plan_review_record_frontmatter_format`).
- Self-initiated `/code-review` B-pass **before** the `--no-ff` merge (§4.3) — not on request.
- `docs/audit/gate-registry.closure.yaml` — §4.2, ≥4 units. Per-entry `terminal_state:`, no
  `deferred:` key. (No clash with the ledger: `validate_audit_closure.dart:79-81` discovers only
  `*_audit_closures.yaml` / `*.closure.yaml`.)
- `docs/naming_conventions.md` glossary — `GATE_INDEX.md`, `gate_test_ledger.yaml`, `// Gate:` (§4.7).
- §5 per-batch walk: `/update-docs`, `MEMORY.md` + `project_*.md` retrospective, worktree retirement,
  skill self-evolution.
- **Commit subjects must NOT begin `fix(`** — no diagnose-doc is owed (rule 22); this is new tooling,
  not a bug fix. Use `feat(gates):` / `refactor(gates):` / `docs(gates):`.
- No OI is open for this work, so no `closes-oi:` trailer.

## 7. VERIFICATION

- `dart run scripts/build_gate_index.dart` → exit 0; `GATE_INDEX.md` has **zero** duplicate numbers.
- Hand-inject a duplicate in a scratch copy → exits non-zero naming both scripts.
- **Header migration count:** `grep -lE '^// Gate: [0-9]+[a-z]?$' scripts/*.dart | wc -l` goes
  **0 → 49**. Any other number is a defect. v2 said 48 and used `grep -clE`, which prints
  filename:count and cannot yield a total (round-2 P1-8). 49 = 44 existing `check_*` declarers + the
  4 with no header claim (`check_exlog_key_canonical`, `check_nlog_key_canonical`,
  `check_no_http_package`, `check_writeservice_only`) + **`validate_audit_closure.dart`**, which the
  `scripts/*.dart` glob includes and which §3.2's "every currently-numbered gate" covers.
- Per renumbered script: `grep -n "Gate <old>"` in its own source → no hits.
- **Both directions, per LINE not per file** (round-2 P2-10). Forward: every live doc citing an old
  number for a renumbered script is updated. Backward: no citation of a *winner* was altered — check
  by grepping the 5 edited files for the winners' numbers before/after, NOT by `git diff --stat`.
  `.claude/skills/debugging/SKILL.md` is the case that proves the point: it holds a loser cite at
  `:445` and winner cites at `:92,152,159,172,182,188,194,223`, so a file-granular assertion is
  unusable there. Untouched entirely: `docs/audit/LENS_REGISTRY.md`, `docs/handbook/`.
- Historical corpus untouched: `git diff --stat` shows no `docs/diagnoses/`, `closed_issues.md`,
  `docs/reviews/`, `docs/plan-reviews/`, `*_closures.yaml` edits.
- Every old number resolves via `## Historical aliases`.
- Gate 33 green; both new gates green; `flutter analyze` clean.
- Full `flutter test` runs once via pre-push (platform tier) + CI — do not hand-run it twice (§4.3).
- Confirm computed tier via `scripts/blast_radius_from_diff.dart` over `main..HEAD` **via stdin**, not
  positional args (`feedback_mistake_blast_radius_positional_mode` — positional args are read as PATHS
  and silently return `feature`).

## 8. RISKS

- **A renumber breaks a live citation, or a winner's citation gets wrongly edited.** §2.3 enumerates
  the bounded set in both directions; §7 greps both directions.
- **The generator's input set is still narrower than reality.** This produced six wrong answers
  (§1.2). Mitigated by hard-fail 4 comparing against an *independent* scan of `scripts/`, not by the
  circular check v1 shipped.
- **The ledger becomes a rubber stamp.** Reduced, not eliminated: three mechanical checks now stand
  behind `mutation_proven` (§3.4). The residue is self-attested and read by the ×2 review.
