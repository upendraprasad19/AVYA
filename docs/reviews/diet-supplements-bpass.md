---
reviewed_at: 2026-11-15T10:30:00+05:30
staged_against: d5e1c9ca (diet plan Unit 4b-server, PR #281, base b463ceef)
blast_radius: platform
reviewer: claude-sonnet-via-skill (three fresh agents, no conversation context, one lens group each)
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 24
verdict: accepted
verdict_note: no P0 or P1 in any seat; every P2 and P3 fixed except the three accepted with reasons in plan section 13; mutants S1-S21 all red
---

# Code Review (B-pass) — diet plan Unit 4b-server, the supplements passage in the coach manual (`diet-supplements`, PR #281) at d5e1c9ca

Seats: A writer/reader drift and blast radius (every bundler of the manual, the registry ranges, the docs, how the key will travel); B guards and their mirrors, missing input (the three switches and their composition, how the model will read the passage in context, a minor, a vegan, a keto user, `weekly-report`); C tests passing for the wrong reason (assertion by assertion, the vector, the circular mapping check). The coordinator re-checked each finding against the code before acting. Dispositions: plan `docs/plans/diet-supplements.md` section 13.

## P2

- **B1 — missing_input — the header's scope had no end.** "none of the lines below apply" could be read as the rest of the manual. **Fixed:** "none of the bullets directly below, up to the next --- line"; the test pins the phrase and that the passage is the last block of SECTION 5.
- **B2 — guard_without_its_mirror — "a post-workout scoop works too" reads as a second scoop.** **Fixed:** "one scoop a day in total: the plan's shake or a post-workout scoop, not both"; pinned.
- **B3 — the multivitamin line contradicts "Never recommend doses outside the bands above"; the doctor line had no object and came after the coffee line; the coffee line had no bound.** **Fixed:** "the one item with no band above; one standard multivitamin a day as its label says"; the doctor line comes first and reads "Before starting any of this, including the coffee below"; "one cup"; order pinned.
- **A1 — writer_reader_drift — the OI-510 edit told the next editor to delete the whole passage and test, kept a stale title and Blocked-on, and duplicated a sentence.** **Fixed:** the title names the six switches; the sentence says delete the switch, its function and the `replace` branch, KEEP the passage and the rest of the test; Blocked-on for this switch named; the duplicate dropped.
- **C1 — asserted_fixture_value — the card-rows mapping test was circular** (arrays typed in the test, nobody reads `cardRows`, keys not tied to `FOOD_TYPE_KEYS`). **Fixed:** the keys equal `FOOD_TYPE_KEYS`; the plant / fish split is PARSED from the passage sentence; the Dart reader of the vector is a named step of landing 4a (plan section 7). Mutants S16 (a sixth food type), S21 (the clause reworded) red.

## P3

- **B4 / A2 — the age and PRO guarantee was a client promise.** **Fixed:** the header also requires `snapshot.profile.age` 18 or more; the comment, the contract entry and the naming row say the server does not verify the key.
- **B5 — the passage never says which powder or that it is fine on keto.** **Fixed:** "(whey; plant protein for a vegan; fine on keto)".
- **B6 — "Their plan" had no antecedent.** **Fixed:** "The user's plan".
- **A3 — vocabulary: "vegetarians" is not a snapshot key.** **Fixed:** "veg, eggetarian and vegan users; non_veg and pescatarian users"; the test parses exactly that.
- **A4 — with the food-type switch ON the legacy SECTION 7 does not define eggetarian or pescatarian, which the passage names.** **Accepted:** the rollback case of Unit 2b, harmless; said in the code comment.
- **A5 — "the same doses as above" is not true for the multivitamin.** **Fixed:** "the doses above for creatine, vitamin D3, B12 and omega-3".
- **A6 — no PRO / paywall line for the coach.** **Accepted:** the diet strategy has the same shape (precedent, plan section 13); noted for the coach check.
- **A7 — "stack" in file and test names against the glossary rule.** **Fixed:** `supplement_card.json` everywhere.
- **A8 — `supabase/functions/CLAUDE.md` +11.1 % against its recorded baseline (soft band 15 %).** **Fixed:** the row shortened to about 60 % of its size.
- **B7 / C7 — the switch was not exercised through `captainPrompt`.** **Fixed:** a test.
- **B8 — the OI-510 duplicate sentence.** **Fixed** (A1).
- **C2 — a vacuous assertion (the two passages concatenated).** **Fixed:** replaced by "the passage is before the `---` that closes SECTION 5".
- **C3 — the SECTION 5 slice had no index guard.** **Fixed:** both headers asserted found and in order; `s5.length < 4000`.
- **C4 — two tokens dropped their unit and frequency (a weekly to daily B12 change stayed green).** **Fixed:** `500-1000 mcg/wk`, `1000-2000 IU/day`; mutants S17, S18 red.
- **C5 — the digit scan did not see a dose written in words.** **Fixed:** a regex for number words and units; mutant S20 red.
- **C6 — "inert in weekly-report" had no test.** **Fixed:** a presence-only pin that `weekly-report/index.ts` never mentions the key; mutant S19 red.
- **C8 — `withEnv` left ambient `DISABLE_*` variables in place.** **Fixed:** it clears the three first and restores them.

## Mutations

S1-S11 (the first commit) and S12-S21 (the fixes): 21 of 21 red. S12 age condition dropped, S13 scope phrase dropped, S14 one-scoop budget dropped, S15 coffee before the doctor line, S16 a sixth food type, S17 B12 frequency, S18 D3 frequency, S19 weekly-report mentions the key, S20 a dose in words, S21 the vegan mapping.

## Founder triage notes

Not needed: no P0 or P1, no product decision; dispositions in plan section 13.

## Tuning entry
- **2026-11-15** - blast-radius platform - 24 findings; 0 false_alarm; tuning: a prompt passage that says "none of the lines below apply" needs an explicit end, because the model reads the rest of the manual as "below"; seat B found it by reading the passage in its surrounding sections, which no string test can do.
