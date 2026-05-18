---
scope: migrations
parent: ../../CLAUDE.md
created: 2026-05-18
status: scaffold
---

# Supabase Migrations — Local Rules

> This file is auto-loaded by Claude Code when working under `supabase/migrations/`.
> Root CLAUDE.md (../../CLAUDE.md) contains process invariants and a pointer index.

<!-- MIGRATION IN PROGRESS — content from CLAUDE.md will be moved here in Milestone 2 -->

## Single-source-of-truth contracts

(populated in Milestone 2)

## Common pitfalls

| Pitfall | How to avoid | Source |
|---|---|---|
| `null user_id` rows from migration 049 pseudonymization | After Test #11 migration 049, FKs on `user_custom_exercises`, `user_custom_foods`, `community_reviews` (note: column is `reviewer_id`), `food_corrections`, `promo_code_uses` are `ON DELETE SET NULL`. When an account is hard-deleted via `delete-account`, these rows survive with `user_id = NULL` ("deleted user" pseudonymization for community signal preservation). **Read consumers MUST tolerate NULL.** Already-fixed in Test #11 cleanup: `promote-community-item` now guards `if (source.user_id)` before `notifySubmitter`. Any new consumer that joins on user_id must add the same guard or the query risks silent skip / false negative. | CLAUDE.md §19 entry 120 (relocated 2026-05-18) |

## Tests pinning the rules here

(populated in Milestone 6)
