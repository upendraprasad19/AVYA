---
hermes_pass_id: 2026-09-28-hermes-day-swapper-sync-load
ran_at: 2026-09-28T11:30:00+05:30
batch_scope: origin/main...3b748372 (reviewed), remediated on the merged tree (origin/main 7cb4eb78 merged into the branch)
lens_set: [L1, L11, L14, L15, L16, L21, L22, L23, L31, L34, L35, L37, L39, L40]
agents_dispatched: 7
model_deviation: "Sonnet, max 4 live, not the skill's Opus default — founder's standing rule (2026-09-26) overrides it. 8 lens seats were planned in 2 waves of 4; seat 8 (L35-app) was folded into seat 7, so 7 ran."
findings_total: 20
findings_unique: 18
findings_by_severity: { P0: 1, P1: 11, P2: 4, P3: 4, false_alarm: 0 }
verdict: accepted
---

# Hermes E-pass — day-swapper-sync-load

## Summary

Seven Sonnet seats reviewed the branch against origin/main across 14 lenses,
grouped 1–3 per seat: EF auth and contracts, restore round-trip, migration 148
and forward/back compatibility, swap-row writer/reader, cross-account state,
telemetry coverage and PII, and I/O budget. They returned 20 findings. Two
pairs were the same defect found from two directions (h2F1 = h5F2, h2F2 =
h4F2), which leaves 18 unique. None was a false alarm. Every one reached a
terminal state: fixed with a regression test (mutation-proven where the fix
is code), verified as designed with the design written down, or filed on the
OI board as a pre-existing gap.

**Provenance, stated because it matters.** The seats reviewed the branch at
`3b748372`. While the pass ran, `origin/main` moved 31 commits past the
branch base (h6F1): OI-252 template identity and the B2a-2b telemetry
dual-write fix. Both rewrote functions this branch also changed. The
coordinator merged main into the branch BEFORE remediating, because fixing
h6F2 and h7F1/F2 against pre-merge code would have been fixing code that no
longer existed. The merge resolution itself is a new surface that no seat
saw. It gets its own focused review before the merge commit lands. The
coordinator's context was also compacted mid-pass. Everything below was
re-derived from the seat reports on disk, the SDD ledger and `git`, not from
memory.

## Findings by lens

| # | Sev | Lens | Finding | Terminal state |
|---|---|---|---|---|
| h5F1 | P0 | L16 | `daySwapAllowanceProvider` never re-evaluated on account switch, so account B could be shown A's remaining swaps | fixed `9f5fedf5` — provider watches `authUserIdTokenProvider`; account-switch test red before |
| h2F1 = h5F2 | P1 | L11/L15 | `sync_epoch_seen` sat in the SHARED `configBox`, so one account's epoch suppressed another's resync | fixed `9f5fedf5` — moved to per-user `workoutBox`; per-user epoch test red before (diagnose a9d3f6 addendum) |
| h2F2 = h4F2 | P1 / P2 | L11/L1 | `displaced_<date>` backups are local-only and lost on a new device | **OI-261** — pre-existing since `708d2910` (TemplateService, 2026-04-10); this batch makes the backup travel with a swap but did not create the gap |
| h2F3 | P1 | L39 | two devices converging on the same plan bundle was unproven | fixed `9f5fedf5` — "two devices converge" test; mutation (drop restore-side `recordConfirmed`) red |
| h1F1 | P1 | L23 | `consume-day-swap` is not a pre-write gate | verified by design — spec decision 6 (the swap happens on the phone first, and the server corrects the count); stated in the EF header |
| h1F2 | P3 | L21 | EF header did not state the fail-open semantics | fixed `9f5fedf5` |
| h3F1 | P1 | L35 | migration file, contract test and live-verify runbook disagreed on the migration number (147 vs 148) | fixed — handover files renumbered to 148 (untracked handover; lands at Task 34) |
| h3F2 | P3 | L22 | migration header cited a stale line range and a wrong time unit | fixed — header corrected in the 148 handover file |
| h4F1 | P1 | L1 | carry-forward re-stamps `arranged_at_ms = now`, so a later edit on another device can win the week | verified by design — spec §5.7 carry-forward + accepted residual; now documented in `docs/architecture/sync.md` L3. The finding's "unrelated date" wording is wrong: only an already-arranged date is re-stamped |
| h4F3 | P3 | L37 | swap engine's `isRest` ignored the legacy rest hybrid, so the 3-rest-day warning could be missed | fixed (diagnose c2d8e5) — shared predicate moved to `DaySwapRules`; mutations 1 red / 3 red |
| h5F3 | P2 | L15 | `SwapService._weekLocks` not cleared on user change | verified — deliberate; a comment now explains it (a held lock belongs to an in-flight swap that must finish) |
| h6F1 | P1 | L34 | origin/main moved past the base with conflicting fixes | resolved by merging origin/main before remediation |
| h6F2 | P1 | L40 | a failed coach upsert put raw chat text into `client_errors` (Postgres echoes the row) | fixed (diagnose e8c3a1) — `ErrorTelemetry.redactRowValues` at every off-device sink; mutations 1 red / 6 red |
| h6F3 | P2 | L34 | the dispatcher's day-swap invalidate catch had no telemetry | fixed `9f5fedf5` |
| h7F1 | P1 | L31 | template restore rewrote every template every launch | fixed (diagnose f1c6b4) — write only if changed; kill switch `disable_restore_write_if_changed` |
| h7F2 | P2 | L31 | progress and profile restore rewrote every launch | fixed (diagnose f1c6b4) — same guard; the profile compare ignores the `updated_at` the write itself stamps; mutations 3 red / 1 red |
| h7F3 | P1 | L35-app | the client dropped its completed-row carve-out in favour of migration 148's server guard, so the app must not ship before 148 is live | rollout precondition — Task 34 applies 148 and confirms the completed-day trigger live BEFORE the merge to main (web deploys on push). Recorded in the closure ledger |
| h7F4 | P3 | L35-app | pre-148 schema compatibility of the `sync_epoch` read | verified clean — the bare select degrades to 0, and the app never writes the column |

The coordinator also found one defect no seat flagged: the hybrid-repair
done-flag key began with `schedule_`, which eight readers treat as a day row.
It was renamed to `hybrid_schedule_repair_v1_done` in `9f5fedf5`, with a
test.

## Founder triage

Coordinator verdict `accepted` under auto mode: every finding is terminal,
and none needs a product decision. The founder may override. The items that
DO need the founder are the standing per-action gates in Task 34: the live
apply of migration 148, the EF deploys, the merge to main, and the push.

## Action items

- Task 34 order is binding: apply 148 → verify the trigger live → deploy EFs
  → merge → push.
- OI-261 (displaced backups), OI-262 (parity-gate blind spots).

## Self-evolution (lessons fed to the skill)

1. A long-lived branch must merge main BEFORE the catastrophic review closes.
   Otherwise remediation targets code the merge is about to replace.
2. `git reset` is blocked in agent worktrees. Seats must read other revisions
   with `git show <rev>:<path>`, and the brief says so.
3. Truncated merge output (`| tail`) hid 8 conflicted files. List them with
   `git diff --name-only --diff-filter=U`, never from a tailed log.
4. A per-user flag key must not share a prefix that readers enumerate as rows
   (`schedule_`).
5. A seat's "pre-existing" or "new" claim is a git-history claim. Check it
   with `git log -S` across the whole tree, not a grep of one file (the
   coordinator nearly mis-filed OI-261 by grepping only
   `workout_write_service.dart`).
