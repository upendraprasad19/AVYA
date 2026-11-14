# Path Mappings — File Path to Maintenance Target

> Used by the /update-docs skill to map changed files to their maintenance targets.

## File path → nested CLAUDE.md or docs/architecture

| Changed file path glob | Target CLAUDE.md or doc |
|---|---|
| `lib/features/train/**` | `lib/features/train/CLAUDE.md` |
| `lib/features/nutrition/**` | `lib/features/nutrition/CLAUDE.md` |
| `lib/features/home/**` | `lib/features/home/CLAUDE.md` |
| `lib/features/ai_coach/**` | `lib/features/ai_coach/CLAUDE.md` |
| `lib/features/onboarding/**` | `lib/features/onboarding/CLAUDE.md` |
| `lib/features/auth/**` | `lib/features/auth/CLAUDE.md` |
| `lib/core/services/**` | `lib/core/services/CLAUDE.md` |
| `lib/shared/repositories/plan_engine/**` | `lib/shared/repositories/plan_engine/CLAUDE.md` |
| `lib/shared/widgets/wardroom/**` | `lib/shared/widgets/wardroom/CLAUDE.md` |
| `supabase/functions/**` | `supabase/functions/CLAUDE.md` + `docs/architecture/ai.md` if AI Edge Function |
| `supabase/migrations/**` | `supabase/migrations/CLAUDE.md` + `docs/architecture/database.md` if schema change |
| Multi-feature (2+ above) | Consider `docs/architecture/<topic>.md` |
| Discipline / process | Root `CLAUDE.md` §4 (rare) |
