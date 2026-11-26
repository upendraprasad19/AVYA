---
branch: generator-step1-1bf2
blast_radius: platform
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/generator-step1-1bf2-bpass.md
---

# Plan review — generator-step1-1bf2 (Unit 1B-F2: the core-list overlay copy, OI-495)

Plan: `docs/plans/2026-11-12-generator-1bf2-overlay-copy.md` (v4 plus the build). Founder basis: B1 Ruling 4 (the copy
belongs to the flip; split out of Unit 1B-F under §4.12.1). Tier L (library data, plan engine reader, cloud re-seed),
blast radius platform. The live apply of migration 176 had its own explicit founder go in chat (2026-11-12).

**§4.6 exception (no kill switch), stated here as in the diagnose (`f2c7a9`).** §4.6 names the plan generator among its
triggers. This unit adds no code path to gate: the reader change is an identity on the shipped data (per-row identity
with the old reader, the planted-overlay guard, the 1,010-persona golden and the byte-identical 2,304-plan dump); the one
output change, the injured thin-day top-up, is bounded by the exact sweep ratchet (`f_repeat_pairs30 full_gym` 27 -> 21,
no block rose); the founder ruled the copy into the flip with no gate (B1 Ruling 4). Ship-dark was considered: a data
flag would ship both label sets side by side, which is the overlay this unit removes. Seed window: every generation
path awaits `seedIfNeeded` first, so a device that has not finished its v27 seed is retried on the next launch.

## Review rounds

Four rounds, each one context-blind Sonnet seat. Rounds 1-3 on the plan (3 P1, 1 P1, 1 P1: the E274 pins, the seed
generator's BATCH and tests, the rollback emitter writing an array into a TEXT column, the S1b-3 tests moving to the
applied 175), each folded into the next version. Round 4 on the BUILT diff after review CI was green on 7ca1233b:
converged (0 P0 / P1; one P2, a vacuous pool-identity test cited as proof in four records, removed and the records
corrected; three P3 fixed). Section 6 of the plan logs every round.

## Ground truth

Re-measured on the final tree: golden 1,010 personas equal (ON and the loaded-wins OFF fixture); the 2,304-plan dump
byte-identical to main and to the prototype (sha256 5b3da296...), `audit.json` equal to the prototype's; the core-list,
same-movement and session-budget gates and the six injured sweeps green; the whole `test/contracts/` green locally (the
one red before the ledger entry, migration parity, cleared); mutations red (diagnose `f2c7a9`). Migration 176: rehearsed
in a local docker postgres with 175 as the live state (exactly 12 rows change; the inline rollback restores the
pre-state); live before 934 / 870 / 64 and the 12 old values; live after the same counts, every other row's md5
unchanged, the 12 new values. The rehearsal also measured that Postgres silently casts a text[] literal into the TEXT
column (debugging class 2.154). CI green on 7ca1233b and c19e5792. Closure `docs/audit/generator-step1-1bf2.closure.yaml`.

## B-pass

`docs/reviews/generator-step1-1bf2-bpass.md`: four P3 (a registry range, the ledger timestamp, the rollback emitter's
other columns, a misplaced comment), all fixed in this batch; verdict accepted.
