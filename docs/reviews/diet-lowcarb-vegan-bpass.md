---
reviewed_at: 2026-11-15T20:38:39+05:30
staged_against: cfefb6f8
blast_radius: account
reviewer: three context-blind Sonnet seats via the code-review skill (A generator and swap logic, B tests and mutants, C asset, seed and docs)
lens_set: [writer_reader_drift, blast_radius_mismatch, secrets_in_tree, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 21
verdict: accepted
verdict_note: no P0 or P1 from any seat; every P2 fixed or accepted with a measurement (below)
---

# B-pass: vegan Low carb plans (PR #285, `diet-lowcarb-vegan`)

Seats ran read-only on the CI-green head cfefb6f8. All three returned ACCEPT.

## Findings and dispositions

| id | sev | claim | disposition |
|---|---|---|---|
| A1 | P2 | The Low carb soy cap of 3 applies to non-vegan plans too | Accepted. Measured: 21 of 700 non-vegan plans (46 of 800 overall) reach 3; gating on vegan costs a preference parameter through the cap function, generator and swap sheet for a 3 % case. Plan section 6. |
| A2 | P2 | The Low carb evening snack's optional `fat` admits ghee, butter, coconut milk | Measured: 213 of 800 plans (336 at lunch, where it is normal). A guard (a snack slot's optional fat must also carry the `snack` role) removed it (0 of 800) but cost vegan protein 2 to 3 points at 200 plans per cell (75 vs 77, 71 vs 74, 69 vs 71 percent), would have lowered ten T10 floor values (largest 0.09) and moved no non-vegan macro. Guard reverted; accepted as a presentation blemish, macro-neutral. Plan section 6 names the fix if a device check shows it matters. |
| A3 | P3 | Tempeh and edamame carry no coherence token | Accepted earlier (plan section 6, R2-7). |
| A4 | P3 | Doc touch-up (garbled sentence in the nested CLAUDE.md) | Fixed. |
| A5 / C-6 | P3 | Chia is in the `nut` family (cap 1) | Accepted, noted in plan section 6. |
| B1 | P2 | `dietFamilyCapFor` pinned only for soy; the plan-level check uses the function as its own oracle | Fixed: literal table, seven families by three strategies. Mutant (older Low carb layer dropped for non-soy families) red, 3 tests. |
| B2 | P2 | The Keto soy clause `<= 2` cannot fail (Keto holds only tofu) | Fixed: tightened to `<= 1` with a comment that the swap-site test is the real Keto cap pin. |
| B3 | P2 | No literal pin of the five new entries; the vegan reach assertion needed only one of five | Fixed: a literal test of roles, family and portions; the vegan Low carb union must contain EACH of the five. Mutants: avocado loses `snack` (red, 2), chia family nut to fat (red, 2), edamame loses `side` (red, 2). |
| B4 | P3 | Floors re-derived: exactly two lowered | Confirmed, no action. |
| B5 | P3 | G3 hashes no role | Accepted: adding it needs a recapture on origin/main; a role relabel on Keto is not a regression this PR can cause (the Keto templates and pools are untouched). |
| B6 | P3 | Swap-site Keto fixture is unrealistic but valid | Accepted. |
| B7 | P3 | `hasLength(19)` literal | Fixed: derived from the catalog. |
| B8 | P3 | G3 adds 800 plans, no file timeout | Accepted: CI is green with it. |
| B9 | P3 | The five new ids are not in the G2 legacy list | Accepted (plan section 6, R2-5). |
| C-1 | P2 | The plan-review record had no `bpass:` field | Fixed in this commit, after this file exists. |
| C-2 | P3 | Stale "measured 2026-11-14 ... raise only" comment above the floors | Fixed. |
| C-3 | P3 | The Low carb template doc comment omits the optional fats | Fixed (one line). |
| C-4 | P3 | Tempeh row energy 192 vs 215 by 4/4/9 | None needed, row unchanged by this diff. |
| C-5 | P3 | Rollback text muddled | Fixed (plan section 6). |
| C-7 | P3 | `feat` commits, no diagnose-doc | Founder's call, recorded in plan section 5b. |

## Verified clean (seat C)

The asset diff is exactly five `false` to `true` flips; the catalog has 170 entries; the five serving descriptions scale without ugly text; every reader of `food_library_version` and `is_everyday` is accounted for; no secret-shaped literal in the diff; the registry ranges moved consistently; the plan-review record satisfies the gate's frontmatter.

## Tuning entry
- **2026-11-15** - blast-radius account - 21 findings; 0 false_alarm; tuning: none (a measured trade-off, A2, was accepted rather than fixed).
