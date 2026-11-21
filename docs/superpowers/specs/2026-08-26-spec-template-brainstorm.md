# Avya Spec Template Brainstorming Session

**Date:** 2026-08-26
**Participants:** Upendra (Founder) + Hermes Agent
**Purpose:** Design a Feature Spec Template workflow that Claude Code must follow before any code changes for Avya

---

## The Template (User-Provided)

```
Feature Spec Template — for directing Claude Code
Fill this out before opening Claude Code. Aim for 10–15 minutes. If a section takes longer than that to answer, the feature is probably too big — cut it or phase it.

0. Discovery Pass (only if you don't already know the codebase)
You often can't fill in Sections 3–4 from memory — you vibe-coded this, not wrote it. That's fine. Do this first, as a separate prompt from the fix:
"Don't write any code. Investigate the codebase for [symptom / feature area]. Tell me: which table(s) store this data, which API route or server action handles it, which files/widgets are involved. Plain-text summary only, no fix."
Then spot-check 1–2 of the files/tables it names yourself before trusting the summary — agents hallucinate plausible-sounding names. Feed only the confirmed facts into Sections 3 and 4.
Optional but compounding: keep a running SCHEMA.md / ARCHITECTURE.md next to your CLAUDE.md that accumulates these facts as you discover them. Each area you've mapped once needs no rediscovery next time.

1. Problem & Goal
What's broken or missing, and for which user (Avya user vs. ICANBEFITTER website visitor vs. Inner Circle member)?
The single measurable outcome that tells you this worked. Not "improve UX" — something you can check.

2. Non-Goals / Guardrails
What this explicitly does NOT include this round.
Files/modules the agent must NOT touch. This is the section people skip — it's what stops Claude Code from "helpfully" refactoring something unrelated while it's in there.

3. Data Model
Exact Supabase tables/columns touched or added. Types, relationships, new migrations.
If there are no schema changes, write "No schema changes" explicitly — don't leave it implied.

4. Interface / Contract
Next.js (website): API route or server action — inputs, outputs, error shapes, status codes.
Flutter (Avya): what state the widget reads, what it writes, what triggers a rebuild, which provider/notifier owns it.

5. User Flow & Edge Cases
Happy path, step by step, in order.
Explicit edge cases: empty state, network failure, auth token expired, Razorpay payment failure, offline/slow connection, race conditions on writes.

6. Acceptance Criteria (Given / When / Then)
Write 3–6. This is what you check the diff against — not "looks right."
Given [context/precondition]
When [user or system action]
Then [expected outcome]

7. Open Questions
Anything genuinely unresolved — tag it. Don't let the agent silently pick an answer for something you haven't decided.

Rules of thumb
Ban vague words: "fast," "clean," "handle it," "robust." If you can't define what they mean concretely, the AI will define it for you — and probably not the way you meant.
Be ruthless about scope. If cutting something means the feature no longer solves the core problem, it stays. Otherwise, it's a non-goal for this round.
Read the full diff against Section 6 before merging. If a criterion isn't visibly satisfied in the code, it isn't done.
```

---

## Key Decisions Needed

### 1. Enforcement Mechanism
**Options discussed:**
- **PreToolUse hook (blocking)** — What I prototyped: blocks Write/Edit/MultiEdit on `lib/`, `supabase/`, `test/` until valid SPEC.md exists. Escape hatch: `ALLOW_NO_SPEC=1`.
- **PreToolUse hook (advisory)** — Same check, but only injects warning context via `additionalContext`, never blocks (exit 0 always).
- **CLAUDE.md instruction** — Add to project CLAUDE.md: "NEVER edit source files without a completed SPEC.md at project root." Relies on agent compliance.
- **Custom slash command** — `/spec` command that creates the template, then `/spec-validate` to check before allowing work.
- **PR template / CI gate** — Enforce at merge time, not edit time.

**Upendra's stance:** Wants enforcement but needs to approve the approach. No building without approval.

### 2. Spec File Location & Naming
- Single `SPEC.md` at project root? (Current hook assumes this)
- Per-feature specs under `specs/<feature-name>/SPEC.md`?
- Linked to git worktrees (one spec per worktree)?

### 3. Validation Strictness
- **Strict:** Must have all 7 sections with meaningful content (>200 chars, ≥2 sections filled beyond headers)
- **Lenient:** Just needs file to exist with Problem & Goal filled
- **Progressive:** Warning first, then block on repeat offenses

### 4. Scope of Enforcement
- **All source files:** `lib/`, `supabase/`, `test/`, `integration_test/`
- **Only feature work:** Not docs, configs, scripts, `.claude/` files
- **Exemptions:** Hotfixes, typo fixes, dependency updates?

### 5. Integration with Existing Workflow
- Works alongside existing hooks: `discipline_hook.dart`, `git_safety_hook.dart`
- Should respect worktree isolation (each worktree gets its own SPEC.md?)
- How does it interact with `/compact` and session resumption?

### 6. Avya-Specific Considerations
- **Supabase migrations:** Section 3 must reference migration files
- **Flutter widgets:** Section 4 needs provider/notifier names, Hive boxes, Riverpod providers
- **Razorpay payments:** Edge cases in Section 5 must cover payment failure, webhook race conditions
- **Multi-user types:** Section 1 must specify Avya user / ICANBEFITTER visitor / Inner Circle member

---

## Open Questions for Upendra

1. **Which enforcement mechanism do you prefer?** (Blocking hook, advisory hook, CLAUDE.md, slash command, CI gate)
2. **Single SPEC.md at root, or per-feature specs?**
3. **How strict should validation be?** (All sections vs. just Problem & Goal)
4. **What files should be exempt?** (Configs, docs, scripts, generated code?)
5. **Should the spec persist across sessions, or reset per task?**
6. **Do you want a "spec review" step where I (Hermes) validate the SPEC.md before Claude Code runs?**
7. **Should the hook also verify the spec matches the actual changes being made?** (e.g., spec says "touch users table" but edit touches exercises table)

---

## Next Steps (Pending Approval)

- [ ] Choose enforcement mechanism
- [ ] Decide spec file strategy
- [ ] Set validation rules
- [ ] Define exemptions
- [ ] Implement chosen approach
- [ ] Test end-to-end with a real feature

---

## Notes

- Current prototype: `scripts/spec_gate_hook.dart` + `.claude/settings.json` entries for Write/Edit/MultiEdit
- Hook blocks with exit code 2 and clear message when no valid SPEC.md
- Escape hatch: `ALLOW_NO_SPEC=1` (per-statement, mirrors git_safety_hook.dart pattern)
- Validation: checks for >200 chars + ≥2 sections with content beyond headers
- **NOT DEPLOYED** — awaiting your approval on approach