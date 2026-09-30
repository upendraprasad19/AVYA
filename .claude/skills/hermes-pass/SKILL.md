---
name: hermes-pass
description: End-of-batch deep cross-lens review using parallel Opus subagents. Auto-suggested by /update-docs when batch blast-radius ≥ account. Run manually via /hermes-pass. Names from the 2026-05-17 Hermes external cross-check that caught 13 P0/P1 findings my own verifier missed.
type: process
priority: high
self-evolving: true
---

# Hermes Pass (E-pass) — Per-Batch Multi-Lens Deep Review

> Track 1 of the 2026-05-28 six-industry-gap closure batch. **Per-batch deep reviewer.** Different from `/review` (per-commit lightweight reviewer).

## 0. When to invoke

- **Auto-suggested** by `/update-docs` walk when batch's max blast-radius ≥ `account`
- **Manual** any time: `/hermes-pass [--lenses=L1,L21,L29]` (founder picks lens subset; default = "p0-blockers" set = L1, L21, L22, L23)
- **Required** before APK build for batches with any `catastrophic`-tier commit (per `docs/blast_radius.yaml` `requires:` list)
- **Skip**: doc-only batches; cosmetic refactors; isolated bug-fix batches with blast-radius `feature` for all commits

## 1. The contract

Produces `docs/audit/<date>-hermes-<batch-name>.md` — one consolidated report from parallel lens dispatches.

### Output format

```markdown
---
hermes_pass_id: 2026-05-28-hermes-<batch-slug>
ran_at: 2026-05-28T19:45:00+05:30
batch_scope: <commit-sha-range or working-tree>
lens_set: [L1, L2, L8, L21, L22, L23, L29, L34]
agents_dispatched: 8
findings_total: <count>
findings_by_severity: { P0: N, P1: N, P2: N, false_alarm: N }
verdict: pending  # → accepted | spawn_followup_batch | block_ship
---

# Hermes Pass — <batch-name>

## Summary
- N P0 findings, N P1, N P2, N false_alarm
- Ship-blockers: [list of P0s]
- Spawn-followups: [list]

## Findings by lens
### L1 — writer_reader_drift
[findings...]

### L21 — Edge Function semantic correctness
[findings...]

[…]

## Founder triage
<filled in by founder>

## Action items
Every finding takes exactly ONE terminal state — there is no "later" bucket
(CLAUDE.md §4.2; same shape as the closure-YAML `terminal_state:` invariant).
- [ ] <fix in this batch> — owner
- [ ] <upstream_blocked: what blocks it, where it is tracked> — owner
- [ ] <blocked_on_user: the exact decision needed> — owner
- [ ] <verified_clean: why it is a non-finding> — owner
- [ ] <filed as OI-NN on docs/audit/open_issues.md> — owner
```

> The second line used to read `<spawn follow-up batch for: ...>`, offering a <!-- deu-quote: records what the line said before it was fixed -->
> deferral bucket in the template of the deepest review the repo runs. Replaced
> 2026-08-17 when the euphemism gate was widened to sweep skills in full.

## 2. Lens registry

Hermes draws from the full **53-lens** `docs/audit/LENS_REGISTRY.md`. Each invocation picks a subset (default: 4-8 lenses from the "p0-blockers" + most relevant for the batch's blast-radius profile).

### Recommended lens sets

| Trigger | Lens set |
|---|---|
| Default (`--lenses` omitted) | L1, L21, L22, L23 (p0-blockers) |
| Payment / auth batch | L1, L2, L21, L22, L23, L29, L40 |
| Sync / restore batch | L1, L11, L15, L16, L37, L39 |
| Migration / schema batch | L1, L14, L22, L35 |
| New Edge Function | L21, L22, L23, L31, L40 |
| Refactor (no behaviour change) | L1, L25, L26, L34 |
| Quarterly comprehensive | `--all` (all 53) |

## 3. Dispatch protocol

When invoked:

1. Collect batch scope: `git log <last-merge-or-base>..HEAD --name-only` if on a feature branch; else `git diff main..HEAD --name-only`.
2. Compute aggregate blast-radius across all touched paths via `scripts/blast_radius_from_diff.dart`.
3. Determine lens set: founder-specified `--lenses=...`, or pick by-batch-shape from the table above.
4. **Dispatch N parallel Opus subagents** via `Agent({subagent_type: 'general-purpose', model: 'opus', ...})` — ONE PER LENS. Each agent:
   - Gets the lens charter from `LENS_REGISTRY.md`
   - Gets the batch's diff or list of changed files
   - Returns 0-5 findings in structured format (file:line / verbatim quote / REAL|FALSE_ALARM|PARTIAL / cite-precedent)
   - Reports cap: 800 words per agent
   - Does NOT propose fixes (that's consolidation phase)
5. **Master agent (Opus)** consolidates: dedup findings, rank by severity, write final report.
6. Output written to `docs/audit/<date>-hermes-<batch>.md`.

## 4. Triage workflow

Founder reviews the report. Per finding, mark:
- `accepted` — fix in same batch (per `feedback_no_deferrals.md`)
- `false_alarm` — annotated reason; tune lens prompt for next time
- `spawn_followup_task` — new batch (DOCUMENTED, not deferred — see `feedback_no_deferrals_recurrence.md` for the distinction)

Verdict:
- `accepted` — all findings resolved (fixed, annotated, or spawned). Batch can ship.
- `block_ship` — at least one P0 not yet resolved. Batch cannot ship.
- `spawn_followup_batch` — P0 findings exist but founder explicitly authorizes a follow-up batch within 24h. <!-- deu-quote: founder-authorized escape, not an agent deferral -->
  **Founder-authorized only.** §4.2 bans the AGENT choosing to defer; it does not
  remove the founder's authority to schedule. An agent may never select this
  verdict on its own — the authorization has to exist in chat first, and the
  finding still lands on `docs/audit/open_issues.md` with the 24h window stated,
  so it is a tracked commitment rather than a note in a report.

## 5. Cost / latency expectations

- 4-lens default: ~$0.50-1.50, 2-4 minutes wall-clock with parallel dispatch
- 8-lens batch: ~$1-3, 4-8 minutes
- `--all` (53 lenses): ~$8-15, 15-30 minutes — reserved for quarterly comprehensive

Budget is OK per founder Q&A. If a single pass produces > $5 cost, log it in self-evolution.

## 6. Anti-patterns (DO NOT)

- Run Hermes per-commit. That's `/review`'s job. Hermes is per-BATCH.
- Skip the master consolidation step — N raw lens reports without dedup overwhelms founder.
- Pass conversation context to lens agents (must be fresh, same rule as `/review`).
- Re-use stale lens findings — every invocation runs fresh lenses.
- Tag every finding as P0 (anchoring). Lenses must rate per their own severity rubric.
- Skip Hermes on "small" batches with catastrophic-tier changes. Catastrophic = mandatory regardless of size.

## 7. Self-evolution

Append after each invocation:
- date / batch / lens set / findings count / dispatch cost / wall-clock
- Lens-level signal-to-noise ratio (real findings / total per lens)
- Any new lens that should be added to LENS_REGISTRY (with charter)
- Any lens that consistently produces noise → flag for retirement or tuning

## 8. History

> The 2026-05-17 Hermes external cross-check (Phase A → D batch) caught 13 P0/P1 findings my own verification subagent missed — including 3 payment-blocking TDZ + SSRF + NOT NULL bugs. That cross-check was MANUAL and ad-hoc. This skill codifies it as a repeatable pass.

> **First invocation: 2026-06-01** — derive-only AI-coach tool-surface batch (platform tier). Targeted 8-lens set (L1, L14, L21, L26, L28, L34, L37, L40), 8 parallel Opus agents. Findings: 1 P1 + 3 P2 + 1 false_alarm. The P1 (L37) — the batch's own a9c3e2 snapshot-budget fix re-breached the 10000-char server cap because `enrichContextForQuery` re-inflated the payload AFTER the trim — was a correct-cap-at-the-wrong-pipeline-point gap that 5 clean lenses AND the per-commit B-pass had missed; fixed in-batch. Validated the skill's premise (a deep multi-lens pass catches what a single reviewer misses). Report: `docs/audit/2026-06-01-hermes-derive-only-coach.md`. Lesson: run L37 on any batch that adds a size/budget cap — verify the cap sits at the LAST mutation before the bounded sink.

> **2026-09-11 — OI-162 slice 4 (windowed counters: delete-account + verify-payment rate limits, migration 130 ACL), catastrophic tier.** 9-lens set (L1, L2, L14, L21, L22, L23, L29, L35, L40), 9 parallel Opus agents. Findings: 3 P1 + 4 P2 + 5 P3 + 4 false_alarm/verified_clean. All fixed, filed, or verified clean in-batch — zero deferrals. Report: `docs/audit/2026-09-11-hermes-oi162-slice4-windowed-counters.md`.
> **Lesson — a consolidated report written after a context compaction must RE-VERIFY every finding, never recall one.** The compaction between dispatch and consolidation destroyed the raw per-lens transcripts. L14 had no surviving triage note at all — rather than infer or omit it, it was re-checked live from scratch (a single `pg_constraint` query against the actual `ON CONFLICT` arbiter) and came back clean in under a minute. L22 and L35 independently found the same defect (a discriminator test whose SQLSTATE-only check degenerated to a tautology once migration 130 shipped); the fix required two fresh live probes (via `SET LOCAL ROLE authenticated` inside `BEGIN…ROLLBACK`, no DDL) to get the ACTUAL current error message text rather than guess at Postgres's wording. L2's table-grants finding was carried forward from this session's OWN pre-compaction summary and, re-verified live before filing, turned out to need correction on two specific points the summary had gotten wrong (a migration's own narrowing attempt that silently didn't take; a table whose RLS-enabled state has no traceable origin in the migration history) — a same-session, self-authored summary is not exempt from the same live-verification discipline external subagent output gets. **Cost note:** re-verifying 3 findings live (L14, the L22/L35 message-text pair, L2's ACL snapshot) took roughly 6 read-only queries total, all `BEGIN…ROLLBACK` or plain `SELECT`, none requiring live-apply authorization — cheap insurance against writing a permanent, cited artifact from a guess.

> **2026-09-13 — OI-153 (PRO media caps on the ledger + the founder's daily Telegram digest; migrations 131/132), catastrophic tier — by CONTENT, not by path: applied migration 131's COMMENT says "SECURITY DEFINER" and the content rule reads comments.** 8-lens set (L1, L14, L21, L22, L23, L31, L35, L40), 8 parallel Opus agents over the branch diff (333 KB) AND the staged apply set (197 KB). Findings: **1 P0 + 2 P1 + 16 P2, 0 false_alarm, 3 PARTIAL**; wall-clock ≈ 25 min; cost unmetered but above the 8-lens estimate (two large diffs per agent). Signal-to-noise: L23 3/3 · L31 4/4 · L22 2/2 · L21 1/1 · L40 3/3 · L1 2/2 · L14 0/1 · L35 0/1. 16 fixed in-batch (ai-media-proxy v25, founder-digest v2, docs/board), 1 filed with the fleet-redeploy decision stated for the founder (OI-194), 3 verified clean. Report: `docs/audit/2026-09-13-hermes-oi153-pro-media-caps.md`.
> **Lesson 1 — run L23 on ANY batch that REDEPLOYS a service-role function, whether or not the batch touched its guard.** The P0 (`c7e2a4`: the OI-28 user-scope guard read the Storage URL as SENT while `fetch` requests it as RESOLVED — `<own>/../<victim>/x.jpg` fetched the victim's object with the service role; six `..` reached `/rest/v1/users`) pre-dated the batch by four months, survived two B-passes and four plan-review rounds, and was found only because one lens's charter is "for each service-role path, try to reach another user's data". A diff-scoped review cannot see it; the batch redeployed the function twice before the lens ran.
> **Lesson 2 — hand a lens the FUNCTION, not the diff, when the batch redeploys it.** The brief gave every agent the two diffs; L23 found the P0 by reading the whole file anyway. For a redeploy the unit of risk is the bundle that ships, so the unit of review is the file.
> **Lesson 3 — a guard and its consumer must read the SAME representation** (the string the client sent vs the URL the runtime parses). Added to the code-review skill's lens 6 as the "representation mirror"; the tell is a guard on a raw string feeding a call that parses.

> **2026-09-21 — observation-batch-and-digest-redesign (Part B digest redesign, migrations 138/139/140), catastrophic tier — self-triggered, not founder-requested.** The trigger itself is a lesson: the batch was headed straight to commit/push/merge with no plan-review record at all until re-reading `check_plan_review_record_exists.dart`'s own source (not CLAUDE.md's prose paraphrase of it) surfaced the `hermes: accepted` hard-requirement at catastrophic tier. 8-lens set (L1, L21, L22, L23, L31, L34, L35, L40), 8 parallel Opus agents. Findings: **2 P0 + 3 P1 + 6 P2, 1 false_alarm** (see the report's own provenance note — this pass's consolidation happened after a context compaction destroyed the raw per-lens transcripts, so every finding here is backed by a fix artifact produced while resolving it, not by recalled prose; the false_alarm count is a floor, not a full reconstruction). Signal-to-noise by lens: L31 1/1 (the P0) · L1 3/3 · L23 4/4 (incl. the 2nd P0) · L21 4/4 · L22 2/2 · L35 2/2 · L34 1/2 (1 real, 1 false_alarm). All 11 real findings fixed in-batch; 2 genuinely pre-existing, out-of-scope findings filed as OI-238/OI-239 rather than scope-creeping the batch. Report: `docs/audit/2026-09-21-hermes-observation-batch-and-digest-redesign.md`.
> **Lesson 1 — a Hermes pass can find a bug THIS SAME BATCH introduced hours earlier, and that bug can already be live.** `alert_cron_failures` (migration 139) shipped, was self-B-passed, and was already misfiring in production (a real Telegram page on stale data, `public.alerts` id=40) before this pass ran migrations 139→140 later the SAME session. A per-commit B-pass reviews the diff against its own stated intent; it does not re-derive "what happens to a crashed-and-never-updated row" from first principles the way a dedicated lens (L31, cron efficiency) does. Don't assume a batch's own earlier self-review already covered what a cross-cutting lens is chartered to find.
> **Lesson 2 — writing a Hermes report AFTER a context compaction is now a repeated, not a one-off, situation (2nd instance after OI-162 slice 4's 2026-09-11 entry above).** The same discipline applied there — re-verify from a live artifact, never recall from a summary — generalizes to "reconstruct the report from the FIXES you already made and verified, not from memory of what the agents said." Every finding in this report cites a diagnose-doc with its own mutation-proof or live-SQL verification, produced DURING the fix, not during report-writing after the fact.
> **Lesson 3 — a fix's own EXPLANATORY COMMENT can silently break an unrelated source-grep test's scan window.** Widening `rolling-context`'s retry-reduction comment from one line to eleven pushed the `retries:` argument from 763 to 1489 chars past the `geminiChat({` anchor `gemini_backoff_retry_test.ts`'s `assertSoleCallSiteHasRetries` scans from — the pre-existing test (checking the WRONG value, `retries: 2`, since the fix changed it to `1`) failed for the RIGHT reason by accident, and fixing only the expected value would have left it silently unable to ever pass again. Same class this repo's own CLAUDE.md §4.9 already names for line-count shifts above a cited line; this is the comment-length variant of it, caught only because the corrected assertion was actually run, not just edited to match the new value.

> **2026-09-26 — single-owner a1 (prediction quota + ai-proxy input limits + delete-account bucket list), catastrophic tier via delete-account.** 5-lens set (L1, L21, L23, L29, L37), 5 Opus agents in waves of ≤4 (founder rule 2026-09-26). Findings: **0 P0 / 0 P1 / 4 P2 / 11 P3 records, 12 distinct, 0 false_alarm.** 9 fixed in-batch, 1 upstream_blocked (the pre-existing nutrition 502 retry spend, owned by the next unit, which cannot start until this one merges), 1 blocked_on_user (a deleted-user Storage sweep, proposed as a new unit), 1 verified_clean. Signal-to-noise 100% on every lens. Report: `docs/audit/2026-09-26-hermes-single-owner-a1.md`.
> **Lesson 1 — a B-pass REMEDIATION creates reader states nobody reviewed, so run L1 on the remediation, not only the original diff.** The B-pass fix "mark a PRO prediction stale when the regenerate fails" was correct, and it created a state (PRO + stale) that the UPDATE button's reader had never had to handle: it still required 30 days. The card told the user to refresh while the button was disabled. Same shape as code-review lens 8's third question ("the remediation created the mirror"), found one review layer later.
> **Lesson 2 — when a quota counts ATTEMPTS, list every caller that spends without a tap.** Three lenses (L1, L21, L29) independently found that the 30-day auto-refresh, which fires from a provider rebuild, could spend the whole 3/day cap on its own. The server was correct; the budget had to live with the automatic callers. The check: grep every call site of the metered method and ask which ones a user did not trigger (post-frame callbacks, `.then` on a save, invalidate-then-rebuild loops).
> **Lesson 3 — the 2026-06-01 L37 lesson recurred on a different transformation: measure the cap at the LAST mutation before the sink.** The snapshot cap measured `JSON.stringify` while the prompt receives `sanitizeJsonForPrompt`, which expands three Unicode separators sixfold. Second instance of the same class, so L37 stays in the default set for any batch that touches a size cap or the path to one.
> **Lesson 4 — a Deno suite that imports a function's `index.ts` fails with `AddrInUse` on any host that already holds port 8000** (here, a docker-proxy on the VPS). It is environmental, not a regression, but it looks like one: check `ss -ltnp | grep :8000` before reading those two failures as batch-caused.

> **2026-09-28 — day-swapper-sync-load (one swap engine for Train/Home/coach + the OI-237 sync-load fix; migration 148), catastrophic tier via 148's content rule.** 14 lenses (L1, L11, L14, L15, L16, L21, L22, L23, L31, L34, L35, L37, L39, L40) grouped 1–3 per seat, 7 **Sonnet** seats in waves of ≤4. That is a recorded deviation from this skill's Opus default, under the founder's standing Sonnet-only rule. 20 findings (1 P0, 11 P1, 4 P2, 4 P3), 18 unique, **0 false alarms**. Every one is terminal: fixed and mutation-proven, verified by design and written down, or filed (OI-261). Report: `docs/audit/2026-09-28-hermes-day-swapper-sync-load.md`. Signal per lens: L15/L16 (cross-account state) found the P0 and one P1; L31 (I/O budget) and L40 (PII) each found a real fix; L1 found one by-design item whose wording overstated its reach.
> **Lesson 1 — merge main into a long-lived branch BEFORE the catastrophic pass closes, not after.** `origin/main` moved 31 commits during the pass and rewrote two functions the seats had reviewed. Remediating the reviewed revision would have fixed code the merge then replaced. Merge first, remediate on the merged tree, and treat the merge resolution as a new surface that needs its own look.
> **Lesson 2 — seats in agent worktrees cannot `git reset`** (the classifier blocks it). Put `git show <rev>:<path>` in the brief as the way to read another revision, or a seat stalls on its first checkout.
> **Lesson 3 — a seat's "pre-existing" or "new in this batch" is a HISTORY claim.** Check it with `git log -S <token>` over the whole tree. The coordinator nearly filed `displaced_<date>` as new because one file on main had no hits; the key has been written by `TemplateService` since 2026-04-10.
> **Lesson 4 — the coordinator is a reviewer too.** The one defect no seat named (a per-user flag key starting with `schedule_`, which eight readers enumerate as day rows) turned up while fixing a seat's finding in the same file. Read the neighbours of every line you touch during remediation.

> **2026-09-29 - oi-182-202-subscription-state (payment grace window + dropping the `users` subscription mirror columns), catastrophic tier.** 6-lens set (L1, L21, L22, L23, L29, L35), 6 parallel Opus agents with no DB access. Findings: 14, all terminal (11 fixed in-batch, 3 blocked_on_user, 0 false_alarm). Report: `docs/audit/2026-09-29-hermes-oi-182-202-subscription-state.md`.
> **Lesson 1 - for any live-change-then-merge sequence, ask what a deploy from `main` does AFTER the live step.** L35 found that live schema would sit ahead of `main` (which still writes the dropped column), so any session deploying from a main-lineage tree would break the payment webhook. Four plan-review rounds and a B-pass audited the plan's own ordering and never asked the mirror question.
> **Lesson 2 - a "readers of the dropped columns" inventory misses readers of the derived semantic.** `expiry-reminder` never named either column and was still wrong about renewals; L1 found it.
> **Lesson 3 - a consolidation written after a compaction must not invent severities.** The L1/L21/L23 ratings did not survive; the report says so and lists the fix artifact per finding instead.
