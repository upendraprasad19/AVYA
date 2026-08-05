---
branch: repo-gate-pattern-sweep
diagnose: e7c3b9
date: 2026-08-05
blast_radius: account
pass: B
verdict: accepted
---

# B-pass — repo-gate-pattern-sweep (Unit 2, diagnose e7c3b9)

Self-initiated per §4.3 (≥account), run by a fresh context-blind reviewer after
two independent review rounds had already landed fixes.

**Initial verdict: rejected** — 2 × P1, 2 × P2. All fixed and re-verified;
**final verdict: accepted**.

The reviewer opened by invoking §4.12 against the batch: three consecutive
rounds each surfacing NEW material issues is the stated signal that a unit is
too large. That framing shaped the response — the resolution below is not a
fourth patch of the same claim, it is scoping the claim to what was actually
swept and filing the remainder as OI-91.

## P1-A — the branch invalidated three SoT-registry entries, and repointed the drift detector at them in the same commit

The comment trim removed 33 lines *above* three `restoring_screen.dart`
methods whose `line_range:` values were exactly correct against `main`:

| registry | says | actual (trimmed) |
|---|---|---|
| `sot_registry.yaml:3940` `_kickoffRestore` | `106-208` | **91-193** |
| `sot_registry.yaml:3896` `_goHome` | `226-278` | **200-252** |
| `sot_registry.yaml:3915` `_onContinueAnyway` | `524-556` | **491-525** |

Both registry gates only assert `end <= lineCount`
(`check_sot_registry_completeness.dart:133`,
`check_sot_registry_parity.dart:152`); 278 and 556 remain in bounds under 791,
so **both PASS on a wrong map**. Bounds-checking is strictly weaker than
correctness — the `feedback_green_check_input_set_width` class.

The sharpest detail: this same branch repoints
`.claude/agents/writer-reader-drift-detector.md:7` **to that registry** as
"the canonical machine-readable SoT contracts". It aimed the drift detector at
a map it was simultaneously invalidating.

Fixed against *measured* method extents rather than a uniform shift — comments
inside the methods were trimmed too, so start and end moved by different
amounts (−15/−26/−33 at the starts; ends differ again).

## P1-B — the completeness grep's input set was 3 directories; the conclusion was stated unscoped

Round 2's "8 sites / zero prescriptive dead citations remain" was true of
`.claude/` + `AUDIT_PLAYBOOK.md` + `docs/playbook/` and false of the repo.
Re-derived repo-wide, the miss that matters: **`docs/naming_conventions.md`
carries 9**, and **CLAUDE.md §4.7 mandates reading that file** before
introducing any name — worse placement than several of the sites already
fixed. (`:75` promises "§15 'User-scoped Hive keys' for the 31-key migrated
set"; `:123` promises "§15 'Hive field-name contract'".) Also
`docs/audit/LENS_REGISTRY.md:44`, mandated by §4.8. All fixed; the swept-set
total is **20**, not 8.

**The filter itself was the deeper defect.** "Citations outside §0-§7/§2a" is
structurally blind to the **wrong-but-live** class — a citation resolving to a
real but *incorrect* section — which is exactly the class this batch argues is
worse than a dead pointer, because it looks fixed. Two were found only by
reading:

- `docs/naming_conventions.md:293` cited "§6 — Coding rules"; §6 is
  MULTI-TIER COVERAGE PROTOCOL. The coding rules are §4.4.
- `.claude/skills/update-docs/references/path-mappings.md:21` routed
  "Discipline / process" to §3 = SCREENS (5 Tabs) instead of §4.

## P2s

- **P2-A** — the "8438-line registry" figure was the pre-refresh base; it is
  **8505** now, and the ~67 added lines contain the very three entries P1-A
  had to fix. Re-swept for pattern 3; still zero.
- **P2-B** — the §15 repoint landed on a bullet the next line already covered
  (`writer-reader-drift-detector.md:7-8` both naming `docs/sot_registry.yaml`).
  Merged into one.

## Residue filed rather than buried

`lib/`, `test/`, `scripts/`, `supabase/`, `integration_test/` hold **138** dead
citations in code comments, invisible to Gate 26 (it walks markdown contract
files, never `.dart` comments). Never in this batch's scope — its premise was
sweeping siblings of b3f9e7's doc/skill patterns — so filed as **OI-91**, with
the exact reproduction command and an explicit note that 138 is a *floor*,
since the same filter cannot count the wrong-but-live class.

## Verified sound (attacked by execution, not inspection)

- **Comment-only claim, re-proven mechanically**: strip `//`/`///`-leading and
  blank lines from `main:` and the worktree version → **542 code lines each
  side, md5-identical**. The reviewer also validated the strip *method* for
  this file (zero `/* */` blocks, zero multi-line strings), so no comment
  content can hide inside a kept line. 824 → 791, −33 exact. No statement,
  condition, import or control-flow change on the auth post-boot path.
- **The new gate test discriminates under both single-regex mutations,
  independently**: reverting `citeRegex` alone → only "THE REGRESSION" fails;
  reverting `headingRegex` alone → only test 1 fails. A genuine complementary
  pair catching a partial revert of either. Drives the real script as a
  subprocess (not a mirrored regex copy), builds its own fixture, depends on
  no ambient repo content, leaks zero temp dirs.
- **All 20 repoint targets exist AND deliver what their sentence promises** —
  including `debugging/SKILL.md` §2.12 genuinely covering `exlogKey`, rogue
  formulas and Gate 17 (confirming `common-pitfalls.md` would have been
  wrong-but-live), and rule 22 genuinely living inside §4.4.
- **`auth/CLAUDE.md`'s timeout rewrite matches behaviour**, read at the timer
  callbacks: `:82` → `_showSoftHint` (15s), `:85` → `_showTimeoutCta` (30s).
- **Every number re-measured**: 791 / 824 / −33 / `check_god_screen_max_lines.dart:103`
  / `account` tier (via the `-` stdin form, avoiding the documented
  positional-args trap). Gates green: 26, 40, 7, SoT parity, diagnose-doc
  validator.

## Latent, noted, not fixed

`citeRegex` still truncates 3-level cites (`§4.1.5` → captures `4.1`, passing
by prefix collision — the same shape as the `§2a` bug this batch fixed). Inert
today: zero 3-level citations exist inside Gate 26's scan set. Recorded here
so it is not rediscovered as novel.
