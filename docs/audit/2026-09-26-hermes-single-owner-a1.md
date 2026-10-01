---
hermes_pass_id: 2026-09-26-hermes-single-owner-a1
ran_at: 2026-09-26T19:30:00+05:30
batch_scope: working-tree (branch single-owner-a, staged diff vs base 9939750b)
lens_set: [L1, L21, L23, L29, L37]
agents_dispatched: 5
findings_total: 15
findings_by_severity: { P0: 0, P1: 0, P2: 4, P3: 11, false_alarm: 0 }
verdict: accepted
---

# Hermes Pass — single-owner a1 (prediction quota + input limits + delete-account buckets)

> **Provenance note (this skill's 2026-09-11 and 2026-09-21 lessons).** L1, L21,
> L23 and L29 reported before a context compaction; L37 after it. No finding
> below is carried forward from memory. Each one was re-verified against the
> code or live state before it was fixed or given a terminal state. The
> evidence column names the check. Live checks were plain `SELECT`s on
> `dedsavbjuwgarrhphgnl`: `pg_get_functiondef` for the three cap triggers,
> `pg_policies` for the avatars/banners Storage policies, and a count of
> `ai_coach_interactions` failure rows.

## Why this pass ran
The staged diff classifies **catastrophic** because it touches delete-account.
A catastrophic merge requires `hermes: accepted` in the plan-review record. The
batch redeploys ai-proxy, delete-account, founder-digest and telegram-admin-bot,
so every lens was pointed at the whole files that ship, not only the diff
hunks. Lenses ran in waves of ≤4 (founder rule).

## Summary
- **15 finding records, 12 distinct.** Three are duplicates: L29-F2 = L1-F1,
  and L21-F3 = L29-F4 = L1-F3. **0 P0, 0 P1**, 4 P2 records (3 distinct),
  11 P3 records.
- **Ship-blockers:** none.
- **Fixed in this batch (staged, uncommitted):** 9 distinct findings.
- **Other terminal states:** 1 `upstream_blocked` (L29-F1: pre-existing, owned by
  a3's A0 redesign, which cannot start before a1 merges because both edit
  ai-proxy), 1 `blocked_on_user` (L23-F1: needs the founder to approve unit
  a4), 1 `verified_clean` (L21-F2).
- Signal-to-noise: L1 3/3 · L21 3/3 (1 duplicate) · L23 1/1 · L29 5/5
  (2 duplicates) · L37 3/3. No false alarms.

## Findings by lens

### L1 — writer/reader drift
| # | Sev | Finding | Terminal state · evidence |
|---|---|---|---|
| L1-F1 | P2 | The batch marks a PRO prediction stale when the goal-change regenerate fails. The card then says "Refresh prediction (PRO)", but UPDATE stays disabled because `canRefresh` required 30 days, so the user is stuck for up to a month. The batch introduced this: before, PRO was never marked stale. | **fixed** — `PredictionService.refreshEnabled` (stale ⇒ enabled for PRO), used by `PredictionNotifier.build`. Tests: `prediction_attempt_gate_test.dart` (3) and a pin in `prediction_refresh_outcome_wiring_test.dart`. Mutations Mh5, Mh10 (125b81). |
| L1-F2 | P3 | With `DISABLE_PREDICTION_QUOTA=true` the ledger is never written, so the digest printed "Prediction (3/day): none", which reads as "nobody used it". | **fixed** — the switch's name and rule moved to the import-free `_shared/prediction_quota_switch.ts`. `gatherDigestInput` reports `unmeteredKeys`, and `buildDigestText` prints UNMETERED. Tests in `founder_digest_content_test.ts` and `founder-digest/index_test.ts`. Mutations Mh15, Mh16. |
| L1-F3 | P3 | The PRO 30-day auto-refresh fires on every provider rebuild. Invalidating after a failure rebuilds, which spends another of the 3 attempts; automatic calls alone can use up the cap. | **fixed** — `PredictionAttemptGate`: automatic callers get one attempt per IST day (Hive `prediction_auto_attempt_day`, written before the request), and concurrent requests join the running one. Tests: `prediction_attempt_gate_test.dart` (7 gate tests). Mutations Mh1–Mh4, Mh8, Mh9. |

### L21 — Edge Function semantic correctness
| # | Sev | Finding | Terminal state · evidence |
|---|---|---|---|
| L21-F1 | P3 | Unused `asPrincipalMessage` import in `ai-proxy/index.ts` (left over after the prediction branch moved out). | **fixed** — import removed. The only other user, `prediction_handler.ts`, imports it itself. `deno check ai-proxy` OK. |
| L21-F2 | P3 | The shared validator returns "food_text_analysis: text too long" for any `type` that sends `text`. A chat request with an oversize snapshot and no `message` now gets "Snapshot too large" instead of "Missing 'message'". | **verified_clean** — only food_text sends `text` (`nutrition_provider.dart` request bodies), and the app's chat always sends a message. Both are 400s, and the client matches on "Message too long" / "Snapshot too large" only. |
| L21-F3 | P3 | The auto-refresh can exhaust the prediction cap on its own. | Duplicate of **L1-F3** — fixed there. |

### L23 — authorization / cross-tenant reach
| # | Sev | Finding | Terminal state · evidence |
|---|---|---|---|
| L23-F1 | P3 | After the purge, the deleted user's still-valid access token can re-upload into the PUBLIC `avatars`/`banners` buckets, and nothing sweeps a deleted user's folder. The batch also deleted the old comment admitting the orphan-cleanup cron was "not yet implemented", so the gap was no longer written down. | **blocked_on_user** — unit **a4** (deleted-user Storage sweep) added to `docs/plans/2026-09-26-single-owner-batch-a.md`. The founder approved it on 2026-09-26; the 12 orphans wait for the sweep. Next: ×2 review and Hermes (catastrophic). The gap is now written down again in `purge_user_storage.ts`'s header and the SoT entry. Verified live: the avatars/banners INSERT/UPDATE policies check only `(storage.foldername(name))[1] = auth.uid()` (no existence check), and `clean-orphan-media` removes chat-media only. The token's post-deletion validity follows Supabase's stateless-JWT model; it was not probed live, because probing needs a real account deletion. |

### L29 — failure-path / retry economics
| # | Sev | Finding | Terminal state · evidence |
|---|---|---|---|
| L29-F1 | P2 | Pre-existing: food_text, scan_meal and cart_auditor return **502** on Gemini failure and on invalid JSON. `retryColdStart` retries a 502 three times (and food_text also retries a 500), so one tap can spend up to 4 cap units. | **upstream_blocked** — blocker: a3's A0 redesign owns failure status and refunds for exactly these sites, and a3 cannot start until a1 merges (both edit ai-proxy; plan order a1 → a2 → a3). Reopen when a1 is merged. Added explicitly to a3's scope in the plan, with the six sites located by grep. Verified: `err(502, …)` at the six sites; `retryOn500: true` in `nutrition_provider.dart`. |
| L29-F2 | P2 | A stale PRO prediction's UPDATE button is disabled. | Duplicate of **L1-F1** — fixed there. |
| L29-F3 | P3 | The chat dedup served any recent row with a non-empty reply. The client's automatic retry of a runToolLoop-threw 502 (2 s later) therefore received "[failed] runToolLoop threw" as the coach's reply. | **fixed** — diagnose **e5c9d2**. The pure `_shared/chat_dedup.ts` `dedupDecision` makes a failed row replay the 502 and never re-run, since a re-run would spend another cap unit. Tests: `chat_dedup_test.ts` (5). Mutations Mh13, Mh14. Live: 0 of 275 rows carry the marker (latent). |
| L29-F4 | P3 | No in-flight guard on the auto-refresh; automatic paths can spend all 3 units. | Duplicate of **L1-F3** — fixed there. |
| L29-F5 | P3 | Stale citations in ai-proxy comments: food_text trigger "migration 127", vision/chat triggers "111", "15-cap", and a "line ~348" anchor. | **fixed** — corrected against live `pg_get_functiondef`: food_text 129, vision 132 (ledger since 129), chat 129, vision cap 20. The line anchor became a name reference. |

### L37 — empty-state / null-shape readers
| # | Sev | Finding | Terminal state · evidence |
|---|---|---|---|
| L37-F1 | P2 | Pre-existing, but the extraction copied it to five buckets: one failed `.list()` of a page or subfolder threw, and every path already collected was discarded. Nothing in that bucket was removed, even a listed public avatar, while the deletion returned 200. | **fixed** — the failure is recorded as `<bucket>_list:<path>` and listed paths are still removed (diagnose 40054f). New tests cover a partial-list failure, a remove error, and pages of exactly 1000 and 1001 (`purge_user_storage_test.ts`, 7). Mutation Mh11. Nothing reads the error strings (grep of `supabase/`, `lib/`, `scripts/`). The residual gap is L23-F1 / a4. |
| L37-F2 | P3 | The snapshot cap measured `JSON.stringify`, but the prompt receives `sanitizeJsonForPrompt`, which turns each raw U+2028/U+2029/U+0085 into 6 characters. A 9,998-character snapshot therefore arrives at ~60,000. | **fixed** — `validateAiProxyInput` measures the sanitised text, which is identical for every snapshot without those characters. The prompt-envelope comment that cited the removed chat-branch check was rewritten. Test in `ai_proxy_input_limits_test.ts`. Mutation Mh12. |
| L37-F3 | P3 | Every 429 was read as the prediction cap, so a gateway or platform 429 said "try again tomorrow" and skipped telemetry. | **fixed** — `AiServiceException.code` is carried from the body. Only 429 + `RATE_LIMITED` means `dailyLimitReached`. Tests in `prediction_refresh_outcome_test.dart`. Mutations Mh6, Mh7. |

### Observed outside the lens set
- `storage.objects` carries three identical permissive INSERT policies and
  three identical UPDATE policies for each of `avatars` and `banners`.
  **verified_clean** for this batch: identical expressions OR together to the
  same predicate, so they have no behavioural or security effect. This is the
  same family 7ad038 deduplicated for SELECT.

## Verification of the remediation
- `flutter analyze lib/`: 0 errors, 0 warnings (45 infos, unchanged).
- `deno check --node-modules-dir=none` on ai-proxy, delete-account,
  founder-digest, telegram-admin-bot: all OK.
- `deno test` over `supabase/functions/`: 615 passed, 2 failed. Both failures
  are `AddrInUse` in `future-prediction/index_test.ts` and
  `re-engagement/index_test.ts`, whose modules bind port 8000 on import, and on
  this VPS port 8000 is held by a `docker-proxy`. Neither file is touched by
  this batch. Environmental; CI does not have the conflict.
- 16 mutations (Mh1–Mh16), each applied with its exact-match count checked
  = 1 and restored byte-for-byte. All go red for an assertion reason (no
  compile errors). Mh10 was 0 / 7 against the first version of its pin, which
  has since been tightened (see 125b81).
- The full Flutter suite and the gate loop are re-run after this report; the
  results are recorded in the plan-review record.

## Founder triage
Accepted 2026-09-26. All 9 fixed-in-batch findings + the 2 duplicate closures +
the 1 verified_clean confirmed against the report as written; L29-F1
(upstream_blocked, owned by a3) and L23-F1 (blocked_on_user, unit a4) confirmed
as the correct terminal states — a4 was separately approved the same day
("Approve a4, sweep the 12"). No changes requested.

## Action items
- [x] L1-F1, L1-F2, L1-F3, L21-F1, L29-F3, L29-F5, L37-F1, L37-F2, L37-F3 — fixed in this batch (staged)
- [x] L21-F3, L29-F2, L29-F4 — duplicates, closed by their originals
- [ ] L29-F1 — upstream_blocked: a3 A0 (starts after a1 merges; plan section "a3", Hermes bullet)
- [ ] L23-F1 — blocked_on_user → founder approved unit a4 on 2026-09-26 (orphans wait for the sweep); a4 is planned and reviewed ×2 after a1
- [x] L21-F2 — verified_clean
