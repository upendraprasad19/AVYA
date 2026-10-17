# Superpowers — plan index

> Generated 2026-05-21. Mod-date buckets are relative to today.
> "ACTIVE" = touched in the last 30 days. "SHIPPED" = touched 30-90 days ago,
> commits landed, no further work expected. "ARCHIVABLE" = older than 90 days.
>
> Buckets are based on filesystem mtime, not git history — a plan that was
> stale until someone re-skimmed it last week shows up as ACTIVE. Re-run this
> sort with `ls -la docs/superpowers/plans/ | sort -k6` to refresh.

## ACTIVE (touched within last 30 days)

| Plan | Last touched | Status |
|---|---|---|
| `2026-05-18-claude-md-declutter-plan.md` | 2026-05-18 | Milestone 6 doc declutter — in-flight as of this index |
| `2026-05-13-sync-service-part-split-plan.md` | 2026-05-15 | Sync service refactor; shipped via Test #16 batch |
| `2026-05-12-apk-test-15-4-batch.md` | 2026-05-13 | Test #15.4 — merged `e541d95` |
| `2026-05-12-apk-test-15-3-cross-account-plan.md` | 2026-05-12 | Test #15.3 hotfix — merged with main batch |
| `2026-05-12-apk-test-15-3-plan.md` | 2026-05-12 | Test #15.3 — merged `c943950` |
| `2026-05-10-apk-test-14-plan.md` | 2026-05-10 | Test #14 — shipped |
| `2026-05-10-process-discipline-plan.md` | 2026-05-10 | Test #13 process bootstrap — shipped |
| `2026-05-06-apk-test-12-5-plan.md` | 2026-05-06 | Test #12.5 — shipped |
| `2026-05-06-apk-test-12-4-plan.md` | 2026-05-06 | Test #12.4 — shipped |
| `2026-05-06-apk-test-12-2-plan.md` | 2026-05-06 | Test #12.2 — shipped |
| `2026-05-06-apk-test-12-plan.md` | 2026-05-06 | Test #12 — shipped |
| `2026-05-04-cross-account-leak-hotfix-plan.md` | 2026-05-04 | Test #11 hotfix — shipped |
| `2026-05-04-apk-test-11-plan.md` | 2026-05-04 | Test #11 — shipped |
| `2026-05-03-apk-test-10-plan.md` | 2026-05-03 | Test #10 — shipped |
| `2026-05-03-test-9-plan.md` | 2026-05-03 | Test #9 — shipped |
| `2026-05-02-apk-test-8-plan.md` | 2026-05-03 | Test #8 — shipped |
| `2026-05-01-apk-test-7-plan.md` | 2026-05-01 | Test #7 — shipped |
| Tests #6 plan-A..plan-G (7 files dated 2026-05-01) | 2026-05-01 | Test #6 — all shipped via merge train |
| Tests #4/#5 hotfix + plan-A..D (8 files dated 2026-04-28) | 2026-05-01 | Test #5 + Test #4 hotfix — all shipped |
| Test #3 plan-A..D + Test #2 plan-A..D (8 files) | 2026-05-01 | Tests #2/#3 — all shipped |
| `2026-04-27-apk-test-4-plan-A-foundation.md` | 2026-05-10 | Test #4 plan-A — shipped |
| `2026-04-27-apk-test-4-plan-B/C/D` | 2026-04-27 | Test #4 plans — shipped |
| `2026-04-24-semantic-retrieval.md` | 2026-04-24 | Semantic retrieval Phase B — LIVE in ai-proxy v45 |

## SHIPPED (touched 30-90 days ago)

| Plan | Last touched | Status |
|---|---|---|
| `2026-04-18-ai-coach-coach-memory-personalization.md` | 2026-04-18 | Coach memory personalisation — shipped |
| `2026-04-15-plan-generator-v4-diagnostic.md` | 2026-04-16 | Plan generator V4 — shipped + locked (CLAUDE.md rule 14) |
| `2026-04-14-exercise-selection-v4.md` | 2026-04-14 | Exercise selection V4 — shipped |
| `2026-04-12-bug-batch-3.md` | 2026-04-16 | Bug batch #3 — shipped |

## ARCHIVABLE (older than 90 days)

(none as of 2026-05-21 — oldest plan is 2026-04-12, 39 days old)

---

## How to use this index

- **Looking for an in-flight plan?** Filter ACTIVE.
- **Auditing what shipped recently?** Filter ACTIVE + SHIPPED — the batch
  retrospectives in `~/.claude/projects/.../memory/MEMORY.md` cite the
  matching plan file for each `apk_test_*_batch.md` entry.
- **Cleaning up the plans/ folder?** Move ARCHIVABLE entries to
  `docs/superpowers/plans/_archived/`. Currently empty; no action needed.

Status frontmatter on individual plans is intentionally NOT being
backfilled for the 49 existing files — the cost outweighs the benefit when
the batch retrospective in MEMORY.md is the canonical "did it ship" answer.
Status frontmatter SHOULD be added to all NEW plans authored from 2026-05-21
onward; see the writing-plans skill for the schema.
