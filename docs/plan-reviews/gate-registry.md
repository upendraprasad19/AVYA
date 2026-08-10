---
branch: gate-registry
date: 2026-08-10
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/gate-registry-bpass.md
---

# Plan-review record — gate registry + red/green test rule (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).
Plan: [`docs/superpowers/plans/2026-08-10-gate-registry.md`](../superpowers/plans/2026-08-10-gate-registry.md).

**Tier is platform, deterministically** — `docs/blast_radius.yaml:68` (`CLAUDE.md`) and `:101`
(`scripts/pre-commit.sh`), both edited by this batch. `bpass: accepted` is therefore unconditional
(`check_plan_review_record_exists.dart:14-19`); this is not ship-dark, so `review_rounds: >= 2` binds.

## Ground-truth audit

Every number in the plan's §1 was re-derived in this worktree, and the load-bearing ones were
verified by the main thread directly rather than accepted from subagent prose
(`feedback_audit_verifier_cannot_trust_own_subagent`).

| Claim | Verified how |
|---|---|
| 84 `scripts/check_*.dart` | `ls scripts/check_*.dart \| wc -l` |
| 44 declare a number in any header form | per-file `head -8` + `grep -oE 'Gate [0-9]+[a-z]?'` |
| **0** use the canonical `// Gate: N` form | `grep -clE '^// Gate: [0-9]+[a-z]?$' scripts/*.dart` → 0 |
| 40 emit a runtime `[Gate N]` | `grep -lE "\[Gate [0-9]+[a-z]?\]" scripts/*.dart` |
| 33 of 84 referenced under `test/` | per-basename `grep -rql` loop over `test/` |
| Gate 45 is **taken** by `check_no_http_package.dart` | `2026_05_20_audit_closures.yaml:632` |
| Gate 7 is a **collision** | `2026_05_20_audit_closures.yaml:237,315` vs `check_sot_registry_completeness.dart` (emits `[Gate 7]`) |
| Gate 44 mint order | `git log -1` on `18f0296` (21:00:22) vs `83bd4cb` (21:43:40), 2026-05-21 |
| 49–54 free | 0 hits across `docs/ scripts/ lib/ test/ .claude/ CLAUDE.md` |
| Closure-ledger glob gap | `ls docs/audit/*_closures.yaml` → 6; `*.closure.yaml` → 18 |
| Loose hard-fail-4 regex over-fires | 5 non-gate matches in `scripts/`; the round-2 narrowing still matches `worktree_config_integrity_lib.dart:7` |
| Tier | `docs/blast_radius.yaml:68,101` |

## Round 1 — two context-blind lenses (correctness · design)

**3 P0 + 12 lesser findings. All 3 P0s independently re-verified and upheld.**

| # | Finding | Disposition |
|---|---|---|
| P0 | **Gate 45 is already minted** (`check_no_http_package.dart`) — the plan proposed assigning it | Renumbers moved to 49–54 |
| P0 | **Gate 44 tiebreak inverted** — the plan used YAML *line order* as a proxy for chronology | Flipped: `check_nested_claude_md_content` keeps 44 |
| P0 | **A 5th collision missed entirely** — Gate 7 | Added; `check_writeservice_only` → 49 |
| P1 | Input set omitted `docs/audit/*_closures.yaml` — the single root cause of both P0s above | Added as source 4 |
| P1 | Live-doc edit list incomplete in one direction and **wrong** in the other (2 entries cite the *winner*) | Both directions corrected |
| P1 | Ledger unsatisfiable: grandfathering by "not tested" would force ~26 **false** attestations on day one | Redesigned — grandfather by "not mutation-proven" (all 84) |
| P1 | The 44-header canonical migration was undeclared work | Declared; counted in §7 |
| P1 | Platform-tier obligations (this record, B-pass, closure YAML) all omitted | §6 added |
| P2 | §3.2's end-anchor rationale false for all 3 cited examples | Corrected to name each true cause |
| P2 | "same trust model as Gate 42" was false — the ledger was strictly weaker | Corrected; three mechanical checks added |

Round 1's design lens recommended **SPLIT**, citing §4.11 (*the detection gate lands before the
refactor it detects*). Accepted — §4's A/B/C sequencing is that split.

## Round 2 — on the hardened plan

**3 P0 + 5 P1 + 4 P2. Two of the three P0s were defects introduced by round 1's own corrections** —
the exact reason §4.12 runs review #2 on the post-#1 text rather than the original.

| # | Finding | Introduced by R1? | Disposition |
|---|---|---|---|
| P0 | **Commit A cannot land** — the builder hard-fails on collisions that still exist at A, and every regen block is `if ! dart run …; then exit 1` | no (latent in both versions) | `build_gate_index.dart` gets its own `--warn-only`, covered by a test so it can't become permanent |
| P0 | **Hard-fail 4 over-fires** on 4 `scripts/*_lib.dart` files whose headers explicitly say they are not gates | **yes** | Re-keyed on the canonical form — 0 matches today, so no false positives by construction |
| P0 | **Source 4's glob covers 6 of 24 closure ledgers**, excluding this batch's own `.closure.yaml` | **yes** | Both globs + both mint patterns (`script (Gate N` and `Gate N (script`) |
| P1 | A live rung-3 citation of the Gate 7 loser missed (`writer-reader-drift-detector/SKILL.md:183`) | no | Added to the edit list |
| P1 | `check_gate_index_fresh.dart` is a new gate with **no test** — rule 24 fails on its first application | no | Test + mutation proof added |
| P1 | "The list is closed" was false — a date-equality check closes nothing | no | Enumerated by name: `const _grandfathered` of 84 |
| P1 | Regen trigger did not cover 3 baked-input sources despite claiming "exactly covers" | **yes** | Trigger widened; claim downgraded to an exhaustive list |
| P1 | Header-migration count off by one (`validate_audit_closure.dart`) and the grep can't produce a total | no | 48 → **49**, `grep -lE … \| wc -l` |
| P2 | Red-path assertion undefined; `test_path` scalar where precedent needs a list | no | Literal closed list of forms; `test_path` is a list |
| P2 | Verification was file-granular where the requirement is line-granular | no | Per-line grep over the 5 edited files |
| P2 | 3 of 4 `common-pitfalls.md` edits would rewrite historical batch-log prose | no | Narrowed to `:28` |

**Two round-2 claims checked and NOT adopted** — reported here because a review's own errors belong
in the record:
- Its proposed narrowing `^//\s*Gate\s*:?\s*\d` **still** false-fires on
  `worktree_config_integrity_lib.dart:7` (`// Gate 33) treat only the gate itself as a gate…`).
  Verified directly; the canonical form is used instead.
- "32 of 84 gates referenced under `test/`" — a per-basename recount gives **33**. The plan's figure
  stands.

## Why no round 3

§4.12.1's test is whether successive reviews keep surfacing **new material** issues, and its
prescribed remedy is *split and ship the smallest converged piece* — which §4 already does. Round 1
**inverted decisions** (Gate 44, Gate 45, a missed collision). Round 2 **inverted none**: it
independently re-confirmed the Gate 44 flip, the 5-collision set, the free numbers, the platform
tier, and the A/B/C sequencing, and its findings were implementation specifications, all closed in
the plan before any code was written. A third round would re-review the same design. The self-
initiated B-pass over the real diff (§4.3) is the backstop, and it reads code rather than prose.
