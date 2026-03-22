# /pre-commit-check — QA checklist before commit

Run the full QA checklist on all files modified since last commit.

## Steps
1. Read `/CLAUDE.md` Section 6 (Coding Rules)
2. Run `git diff --name-only` to get changed files
3. Read each changed file and check against the QA checklist

## BLOCKER Checklist (fix before commit)
1. No inline `isPro` checks — must use `subscriptionService.gate()`
2. Phase 1 never gated under any condition
3. No API keys in client code (check for hardcoded strings)
4. Repository pattern — no direct Hive/Supabase calls from widgets
5. Riverpod for shared state — no `setState` for cross-widget data
6. Hive adapters registered in `main.dart`
7. No hardcoded stats (calories, weights, dates)
8. Switzer font everywhere — no system font usage
9. Electric Cyan #00D4FF — no old green #00e5a0
10. Dark theme — correct background hierarchy
11. No cross-feature imports (only shared/ and core/)
12. Edge Functions validate JWT
13. Loading, error, empty states on all screens
14. `@riverpod` annotations where appropriate

## WARNING Checklist (note but don't block)
1. Design tokens match UI.txt
2. PRO badge uses Champion Gold
3. Null-safe data access throughout
4. try/catch on all async operations

## Output
```
PRE-COMMIT CHECK
─────────────────
✓ 12 files checked
✗ 2 blockers found
⚠ 1 warning found

BLOCKERS:
  lib/features/train/screens/train_screen.dart:42 — inline isPro check
  lib/features/nutrition/providers/nutrition_provider.dart:18 — direct Hive call

WARNINGS:
  lib/features/home/widgets/streak_card.dart:7 — border radius 14, should be 16

VERDICT: FIX BLOCKERS BEFORE COMMIT
```
