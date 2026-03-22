# /build — Trigger Autonomous Build Pipeline

Start the fully autonomous build pipeline via the Manager Agent.

## What Happens
1. Manager Agent reads `CLAUDE.md` and `.claude/tasks/BUILD_ORDER.md`
2. Finds the first phase with status `[ ]` where all dependencies are `[x]`
3. Spawns the assigned subagent(s) — parallel where deps allow
4. Collects output → runs QA → advances or retries
5. Repeats until all phases are `[x]`
6. Delivers final summary

## You (the user) will:
- See one-line status updates at each phase boundary
- Only be asked questions for: ambiguous requirements, API keys needed, or persistent QA failures
- NOT need to say "next" or "continue" — the pipeline runs autonomously

## Build Order
```
Phase 0: Project Init           [x] (already done)
Phase 1: Database (21 tables)   → @database-agent
Phase 2: Seed Data              → @database-agent
Phase 3: Auth + Onboarding      → @auth-agent
Phase 4: Core Services          → general
Phase 5: 5 Screens (PARALLEL)   → @screen-agent ×5
Phase 6: Backend Edge Functions  → @backend-agent
Phase 7: Monetisation            → general
Phase 8: Full QA Pass            → @qa-agent
Phase 9: Polish + Launch         → general
```

## To Start
Spawn the Manager Agent with this prompt:
"Read CLAUDE.md and .claude/tasks/BUILD_ORDER.md. Execute the autonomous build pipeline. Start from the first incomplete phase."
