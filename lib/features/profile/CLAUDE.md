---
scope: profile
parent: ../../../CLAUDE.md
created: 2026-05-18
status: scaffold
---

# Profile — Local Rules

> This file is auto-loaded by Claude Code when working under `lib/features/profile/`.
> Root CLAUDE.md (../../../CLAUDE.md) contains process invariants and a pointer index.

## Single-source-of-truth contracts

(populated in Milestone 2)

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| Progress-photo upload fails with PhotoQuotaException | Daily cap exceeded. Free: 2/day, PRO: 5/day. Enforced at `ProgressPhotoRepository.capture` by counting today's `progress_photos` rows for the user BEFORE pick. UI should catch `PhotoQuotaException`, surface the paywall for free users (`feature: 'progress_photos'`) or a "come back tomorrow" snackbar for PRO. Image quality differs by tier too: 2048/85% free, 3000/95% PRO. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |
| Weekly Report sparkline dips to 0 between weigh-ins | By design only for calories/protein/workouts (zero-fill = genuinely no activity). Weight series is **forward-filled** from last known — if you see it dropping to zero on un-weighed days, `weeklyReportDataProvider` has regressed. | (relocated 2026-05-18 — see docs/diagnoses/INDEX.md) |

## Tests pinning the rules here

(populated in Milestone 6)
