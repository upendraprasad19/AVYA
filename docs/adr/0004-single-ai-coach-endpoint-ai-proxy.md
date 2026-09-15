---
adr_id: 0004
title: Single AI coach endpoint via ai-proxy Edge Function
status: accepted
date: 2026-04-15
deciders: Upendra
---

# ADR-0004: Single AI coach endpoint via `ai-proxy` Edge Function

## Context

AI Coach is a core feature. The app needs to:
- Answer free-form coach chat (Gemini 2.5 Flash, tier-gated)
- Run multi-tool dispatching (logPR, swap exercise, scan meal, weekly
  insight)
- Throttle by tier (free trial 15 msg/day, PRO unlimited)
- Hide API keys from client
- Be auditable per-call (latency, cost, errors, model used)
- Support placeholder resolution for streaming UX

Two architectural shapes were considered:
1. **Per-feature endpoints** — `/swap-exercise`, `/scan-meal`,
   `/log-pr`, `/weekly-insight`, etc. — each with its own auth, rate
   limit, prompt, tool-dispatch logic.
2. **Single proxy endpoint** — `/ai-proxy` that receives intent +
   context, dispatches to the right tool internally, returns a unified
   response shape.

## Decision

**Single `ai-proxy` Edge Function** as the entry point for all AI
interactions. The function:
- Authenticates user + tier
- Enforces per-tier rate limit
- Dispatches to internal tool handlers (`_shared/tools/*`)
- Returns a unified `{message, toolCalls[], reasoning?}` shape
- Logs every call to `ai_coach_interactions` for audit + analytics

Currently version v67 (as of 2026-05-23).

## Alternatives considered

1. **Per-feature endpoints (rejected option above).**
   - Pro: smaller blast radius per deploy (a bug in scan-meal can't
     break log-PR).
   - Con: 5+ endpoints to maintain, each with its own auth + rate
     limit + telemetry boilerplate. Tool dispatch logic would be
     duplicated or pushed to a shared helper anyway.
   - Con: prompt engineering becomes per-endpoint; consistency across
     tools (system prompt, brand voice) requires discipline at each.
   - Why we didn't pick it: the duplication cost outweighed the
     blast-radius benefit at our scale. We get blast-radius
     containment from the `requires:` discipline on catastrophic-tier
     paths (ADR-0008 era + `docs/blast_radius.yaml`).

2. **Direct Gemini call from client with key-scoping.** Rejected.
   Impossible — no key-scoping at Gemini API level that prevents quota
   exhaustion or abuse. Keys MUST be server-side.

3. **OpenRouter / abstracted multi-model proxy.** Rejected at this
   time. We've explicitly committed to Gemini (cheap, fast, multi-modal)
   + Cerebras (fast Llama for specific tools). A meta-proxy adds an
   intermediate failure point.

4. **WebSocket streaming proxy.** Considered. Not adopted yet — adds
   real-time complexity (connection state, retry) for an interaction
   that's currently fine as request-response. May revisit when
   reasoning-mode UX needs streaming.

## Consequences

Good:
- **One place to add a tool.** Tool definitions live in
  `_shared/tools/` and get auto-registered. Adding "swap meal slot"
  is a few-line tool file.
- **One auth boundary.** Tier check + rate limit live once.
- **One telemetry sink.** `ai_coach_interactions` table is the canonical
  AI log; every analytics query starts there.
- **System prompt + brand voice live once.** Wardroom Lt-promise tone
  is in one prompt template, not 5.

Bad:
- **Catastrophic-tier surface area.** A bug in `ai-proxy` affects
  every AI surface in the app. Mitigated by:
  - `requires: hermes_pass` (per `docs/blast_radius.yaml`)
  - 8-deep payload archive + git-SHA rollback path
    (`.claude/deploy_via_api.js --rollback`)
  - Contract tests pin the response shape
- **Routing logic complexity grows.** Each new tool adds a routing
  branch. We've grown to ~12 tools and the dispatcher is still
  readable. If we exceed ~25 tools, consider sub-routing.
- **Cold-start cost.** Edge Function isolates have cold-start; our
  current p95 is acceptable but worth monitoring as user base grows.

## Status

Active. ai-proxy v67 live; placeholder resolution + cross-channel
dedup landed Test #16.2.

## See also

- `docs/architecture/ai.md`
- `supabase/functions/ai-proxy/`
- ADR-0002 (Supabase as the cloud)
