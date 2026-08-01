- 2026-06-26 · strategic-compact · trigger: batch ship (4 units merged to main: recovery/D/E/AI-chat) + phase boundary (docs phase F next) + deep marathon context · founder: ACCEPTED (ran /compact)
- 2026-07-28 · strategic-compact · trigger: explicit founder invocation at session open, ahead of backlog triage — no batch had shipped yet, so the preserve list was thin (branch + open-OI set only) · founder: ACCEPTED (ran /compact)
- 2026-07-28 · strategic-compact · trigger: batch ship (gate-input-family `0bd234c7` + oi58-version-bump-lines `dd966f55` both merged to main; 16 Edge Functions deployed) + follow-up continuing in-session + heavy context pressure · founder: ACCEPTED (ran /compact)

> **Trigger-tuning note (2026-07-28).** Of three invocations to date, two fired on
> "batch ship + work continues" and one on explicit ask. The batch-ship trigger is
> carrying the skill; the "parallel subagent dispatch returned" condition has never
> fired once. Worth watching whether it ever does before treating it as a real
> trigger rather than an aspirational one.

- 2026-08-01 ~09:15 IST — trigger: **batch ship** (Unit 5 merged `d229c012`, CI green,
  follow-up units continuing in-session) + long session. Founder ACCEPTED (ran /compact).
  Note: the skill's own step-6 logging was blocked that round because plan mode was active
  and only the plan file was writable — this line is the retroactive entry.
- 2026-08-01 ~11:40 IST — trigger: **explicit** (`/strategic-compact`) + context pressure,
  mid-batch with **nothing committed**. Distinct from every prior invocation: previous ones
  fired at a clean boundary where git history WAS the durable record. Here `HEAD` is
  unchanged and the batch lives only as 24 staged files in a worktree + a failure log in
  /tmp, so the preserve-list is load-bearing rather than a convenience. Founder decision:
  pending at time of writing.
  → Tuning signal: the skill's trigger list assumes a *clean* boundary ("last commit landed",
    "batch has shipped"). It has no entry for "context exhausted mid-batch with a red suite",
    which is the riskiest moment to compact and the one most needing a curated preserve-list.
    Worth adding as an explicit trigger.

- 2026-08-01 — /strategic-compact — trigger: batch shipped (Unit 9 / OI-79 complete end-to-end:
  merge `0545f0a5`, CI green on that SHA, 16 Edge Functions deployed + version-verified) plus
  context pressure. A genuinely clean boundary, unlike the same day's earlier invocation where
  nothing was committed. **Founder ACCEPTED** (ran `/compact` after the list was surfaced in chat).
  → Tuning signal (SECOND occurrence): the skill was invoked while **plan mode was active**, which
    forbids writes — so step 6's own logging step could not run, exactly as it could not run
    earlier the same day. Both times it had to be back-filled afterwards. The skill should either
    state that its log entry is deferred under plan mode, or the log-append should not be step 6
    of a skill that is frequently invoked from a read-only context.
  → Process error worth recording: under plan mode I ended the turn with `ExitPlanMode`, treating
    the preserve/drop list as an implementation plan needing approval. It is not — ExitPlanMode's
    own guidance excludes non-code/research tasks. Founder rejected it. The skill's step 4 wants a
    plain chat message and an explicit go-ahead, nothing more. If this skill is invoked in plan
    mode again: surface the list in chat, do not route it through ExitPlanMode.
