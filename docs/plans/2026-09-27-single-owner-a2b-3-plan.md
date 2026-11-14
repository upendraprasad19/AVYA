---
unit: a2b-3
parent_plan: docs/plans/2026-09-26-single-owner-batch-a.md
supersedes: docs/plans/2026-09-27-single-owner-a2b-plan.SUPERSEDED.md (split per §4.12.1)
depends_on: none (independent of a2b-1/a2b-2)
blast_radius: account (if implemented) — currently BLOCKED_ON_USER
status: DROPPED (Option A) — founder decision 2026-09-27, per the rationale below.
  terminal_state: verified_clean — no code changes needed; this unit does not
  proceed to implementation and does not need a plan review
date: 2026-09-27
---

# a2b-3 — snapshot_json size bound — DROPPED

**Decision: Option A, drop this unit.** Confirmed during founder review
(2026-09-27) that the actual token-cost-management problem this unit's rationale
was pointing at lives on a COMPLETELY different pipeline than the one this unit
targeted:

- The LIVE chat context actually sent to Gemini on every message is built fresh
  from local Hive data (`AiSnapshotBuilder.buildAiContext()`) and already goes
  through `_compactContext()` (`lib/core/services/ai_service.dart:211`), which has
  a real, working, prioritized trim system (9,500-byte budget; drops step history →
  water → weight trend → nutrition trend → exercise history → PRs → notices →
  truncates coaching_notes → drops fitness_summary as last resort).
- The STORED `user_daily_snapshots.snapshot_json` blob — the thing this unit
  proposed to cap — is a periodic backup copy used only for restore-after-reinstall
  and by the `daily-snapshot` cron job's own extraction logic. Confirmed:
  `ai-proxy`, `ai-media-proxy` and `weekly-report` (the three functions that call
  Gemini) all select ONLY `id` from `user_daily_snapshots` — the stored JSON
  contents never reach a model.

So the size-management mechanism that actually matters for token cost
(`_compactContext`) already exists and works, on a pipeline this unit never
touched. There is no live cost problem on the pipeline this unit DID target, and
no forward-looking gap either. Closes as `verified_clean` per CLAUDE.md §4.10 —
checked and found unnecessary, not deferred.

## Original rationale (kept for the record — superseded, not deleted)

## Why this is blocked

The parent plan's rule 18 called for bounding `snapshot_json` at some size (the
original a2b draft proposed 16 KiB truncation, "per confirmed token-cost math").
Round-1 review (F11) checked this against live data and the actual readers of
`user_daily_snapshots` and found the stated rationale does not hold:

- **Live size distribution (245 rows, text length):** max 10,843 bytes, p95 8,855,
  p50 4,292. Only 3 rows exceed 10K; **zero** exceed 16,384. A 16 KiB bound would
  almost never fire in practice — it is not solving an observed problem at that
  threshold.
- **The stated "token-cost math" premise is itself contradicted by verified fact:**
  `ai-proxy`, `ai-media-proxy` and `weekly-report` — the three functions that call
  Gemini and could plausibly incur a token cost from this data — all select ONLY
  `id` from `user_daily_snapshots`. The stored `snapshot_json` blob reaches no
  model at all. Whatever cost concern motivated this unit, it isn't "this JSON gets
  sent to Gemini and costs tokens," because nothing currently sends it there.
- **Truncating the REQUEST wouldn't even bound the STORED row correctly**, even if
  bounding were still desired for some other reason: `mergeSnapshotJson` keeps
  earlier values for any key a truncated payload drops, and cron-written keys are
  unbounded independent of this client-facing write path — so a request-side
  truncate would silently let dropped keys go STALE rather than actually bounding
  the merged row's total size.
- **The originally-cited trim-order precedent doesn't apply here**: `_compactContext`
  (the function actually named) lives in `lib/core/services/ai_service.dart:196-249`
  and governs what's sent to the CHAT model — a completely different consumer from
  the stored-snapshot readers listed in `docs/snapshot_contract.yaml`. Borrowing its
  trim order for this unit would be applying the wrong precedent.
- **The proposed "usage_counters-style counter" for tracking truncation events is
  not viable as described**: `usage_quota_ledger_writer_to_reader_test.dart`
  forbids any `usage_counters` mention outside its own allowlist, and any write to
  that table other than through `consume_quota`.

## The decision needed from the founder

Given the above, there is no live evidence this unit currently solves a real
problem. Two options:

**Option A — drop this unit entirely.** Nothing currently sends `snapshot_json` to
a model, the live size distribution never approaches any bound worth enforcing
today, and the batch closes this as `verified_clean` (per §4.10 terminal states) —
not a deferral, a genuine "checked and found unnecessary."

**Option B — proceed, but on a corrected basis.** If there's a forward-looking
reason to bound this (e.g. an anticipated future feature that WOULD send
`snapshot_json` to a model, or a storage-cost concern unrelated to tokens), the
design needs to:
- Apply the bound to the MERGED row (`mergedSnapshotJson`), not the incoming
  request payload, so dropped keys either genuinely get removed from the stored
  row or the write is rejected outright — never silently going stale.
- Use a real trim-order precedent from `docs/snapshot_contract.yaml`'s own readers,
  not `_compactContext`'s (chat-model-specific) order.
- Track truncation events via a mechanism that doesn't touch `usage_counters` (a
  plain log line, or a dedicated small counter table if persistence is wanted).
- Correct `docs/sot_registry.yaml:852`'s stale "server limit 10K" line to whatever
  the new real limit is (if any).

## Next step

Ask the founder to choose Option A or B. Per §4.10's `blocked_on_user`/
`verified_clean` terminal states, this is not left open-ended — the batch's closure
requires one of these two answers before this unit can be marked done either way.
