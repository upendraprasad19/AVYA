---
branch: notif-prefs
date: 2026-07-26
blast_radius: platform
review_rounds: 3
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/notif-prefs-unit-b-review.md
---

# Plan review — notif-prefs (Unit B)

§4.12 record for the notification-preferences arc. The plan was reviewed **three**
times before a line was written, and the outcome of the third round was a
**split**: ship Unit B alone, sequence the rest.

## Why three rounds, and why the split

The §4.12 signal is explicit — when successive rounds keep surfacing *new*
material issues, the unit is too large. That is exactly what happened, and the
distribution of the findings is what made the split obvious:

| Round | What it found |
|---|---|
| 1 | Refuted five claims I had passed on from subagent research without reading the source, including "no gaming loophole" and "`holdWeek` is prior art". |
| 2 | Found that **round 1's own corrections** introduced two new P0s — a guard that would not compile in any of the four target functions, and invented key names colliding with existing ones. |
| 3 | Found that **round 2's correction** named the wrong template: `protein-gap-alert` is one of only two today-pinned readers, making the proposed guard inert for 16 of 17 live users. |

Every round landed on units C/D/E/F. **Zero** rounds found a defect in Unit B
across all three. That asymmetry is the whole argument: B was converged and the
rest was not, so shipping them together would have held a finished, verified fix
hostage to work that was still moving.

**My split instinct was inverted, and round 3 corrected it.** I had assumed Unit
A (the router fix) was the converged piece. It is the *least* shippable —
`SettingsScreen` is referenced exactly once in `lib/`, by its own route
registration, so nothing navigates to it and bug (b) is latent rather than live;
and it holds no access to the private preference state, so pointing it at the
real route yields a screen where every toggle renders ON and every save is
silently discarded. **A depends on C.**

## Ground truth

Every claim below was verified against live production (`dedsavbjuwgarrhphgnl`)
or the file itself, not against subagent prose — the recurring failure mode
recorded in `feedback_audit_verifier_cannot_trust_own_subagent.md`.

- **0 of 91** `user_daily_snapshots` rows carry `notification_preferences`. No
  writer has ever existed.
- **0 genuinely PRO users app-wide.** All 9 subscription rows are expired; the
  newest `status='active'` row expired 2026-07-13. `users.subscription_status`
  claims 6, all lapsed.
- The six other hand-rolled PRO predicates were each read individually and are
  each correct. An earlier draft also listed `assess-body-composition` — **wrong**,
  relayed unverified and refuted on review.
- The snapshot-contract line citations were re-derived by opening each file, not
  trusted from the YAML.

## Unit B — what shipped

The one bug of the three with **verified live user impact**: `morning-alert`
decided PRO from `users.subscription_status`, a denormalized column with no
expiry term that nothing writes back to `'free'`, so six churned users were
receiving Gemini-generated PRO copy. Diagnose `a7d2e9`.

Ten findings, all terminal, in `docs/audit/notif-prefs-unit-b.closure.yaml`.
Three of them (B8–B10) came from the B-pass and were fixed in the same commit
rather than carried.

Two (B6, B7) were not on the plan at all — they were found by implementing it.
B6 was known from review; **B7 only became visible once B6 was fixed**, because
the gate could not report a false negative on a block it had never parsed. That
is the §4.11 "gate before refactor" rule paying off inside a single commit.

## Sequenced next, nothing dropped

`C+D` → `E` → `F+A+G`, each with its own closure entry when it lands. The
round-3 findings are recorded in the plan file so they are not re-derived,
including the one that matters most: **Unit E must follow
`weekly-recap-ready`'s latest-desc batched read, not `protein-gap-alert`'s
today-pinned one** — and the two toggles currently believed to work
(`protein_alerts`, `morning_checkin`) are inert for the same reason and are
repaired in that unit.

## Not verified

`morning-alert` must be **redeployed** before this fix takes effect in
production. It is live at v27 and this diff is not deployed. That is a live prod
action requiring explicit founder authorization per §4.3, and is recorded as
tier-6 `fixed_in_this_batch` in the diagnose-doc with that caveat stated.

Deno type-checking was not run (`deno` is not on PATH here and no Deno gate
exists in the pre-commit set). The TS is verified by reading and by the repo's
existing static gates.
