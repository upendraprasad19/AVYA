---
reviewed_at: 2026-09-13T07:20:00+05:30
staged_against: f15fad75 (branch oi153-pro-media-caps @ 2 commits over main 39111d1e; diff hash 88cfc8594fcc)
blast_radius: platform
reviewer: claude-sonnet-via-skill (two context-blind agents — lenses 1-5 + 9/10, and lenses 6-8 mutation-driven)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value, self_attesting_artifact, stale_or_wrong_citation]
findings_count: 6
verdict: accepted
---

# Code Review — oi153-pro-media-caps (B-pass)

Scope: `git diff main...HEAD` at `f15fad75` — 28 files, +2286/−155. Commit 1 `67ba6ba4`
(ai-media-proxy PRO caps on the ledger) and commit 2 `f15fad75` (the `founder-digest` cron EF).
Two fresh Sonnet agents, lens sets split 1-5+9/10 and 6-8 per this skill's 2026-09-08 tuning
(28 files > the ~15-file threshold). Agent B ran 15 mutations (a–n) and restored every file
byte-identically; agent A verified live state through the Management API.

**6 findings (0 P0, 2 P1, 2 P2, 2 P3); 0 false_alarm. All triaged `accepted`; 5 fixed in the
same batch (commit 3), 1 resolved by an existing pin with the refactor declined and the reason
recorded.**

## Finding 1 — P1 — self_attesting_artifact
- **file:line:** `docs/diagnoses/2026-09-12-pro-media-caps-dormant-and-video-uncapped-a9d4e7.md`, `touched_layers_checked` tier 6
- **claim:** the tier-6 evidence said ai-media-proxy was "Deployed on the founder's explicit go, byte-identity verified via the multipart /body endpoint" — while live `ai-media-proxy` is **v23 (2026-09-10)**, the PRE-fix bundle: `countProImageAnalysesToday` ×2, `RATE_LIMITED`, `status: 429` present; `PRO_VIDEO_DAILY_CAP` / `pro_video_daily` / `subscriptionError` / `tier_unavailable` absent. The dormant cap and the uncapped PRO video are live in production until the post-merge deploy.
- **verification:** `list_edge_functions(dedsavbjuwgarrhphgnl)` → ai-media-proxy version 23, `updated_at` 2026-09-10T05:04:57Z; `get_edge_function` source grep as above.
- **suggested-fix:** state the deploy as NOT done at commit time; record the version where it can be recorded after the fact (closure ledger + memory), not in a file that cannot be amended without another commit.
- **status:** accepted — fixed in commit 3 (tier 6 rewritten: not deployed as of the commit, live v23 named, the post-merge deploy pre-authorized and its verification steps listed; the ledger carries the version). The first draft was a template copy written "at the moment of maximum optimism" — the exact shape this skill's 2026-09-10 tuning names.

## Finding 2 — P1 — missing_input / self_attesting_artifact
- **file:line:** `test/contracts/pro_media_daily_caps_writer_to_reader_test.dart:16-19`, `docs/sot_registry.yaml` (`pro_media_daily_caps` `presence_only` justification), `docs/architecture/functionality-flow.md` COACH-20
- **claim:** three places cite `test/sql/oi153_pro_media_caps_live_verify.sql` as the live-ledger proof; the file existed nowhere in the tree. Gate 42 checks that `behavioral_test_path:` / `presence_only:` are non-empty text — it never `existsSync()`s a cited path, so a fabricated one passes silently.
- **verification:** `test -f test/sql/oi153_pro_media_caps_live_verify.sql` → MISSING; `grep -n "existsSync\|File(" scripts/check_sot_behavioral_test_paths.dart` → reads the registry only.
- **suggested-fix:** write the file (BEGIN…ROLLBACK, the `oi46_*` shape) or strike the claim.
- **status:** accepted — the file lands in commit 3 (Part A: `consume_quota` 1..50/-1 and 1..10/-1 on the two PRO keys, key independence, `used` untouched by a refusal, next-IST-day freshness; Part B: migration 132's guard, text AND a behavioural probe that is red before 132; Part C: migration 131's cron row). Parts B/C are runnable only after the apply; the header says so and labels which assertions discriminate the batch's change vs hold under any correct implementation. ⚠ The gate gap itself (Gate 42 does not check existence) is real and filed on the board with the close-out.

## Finding 3 — P2 — guard_without_its_mirror (mutation n)
- **file:line:** `supabase/functions/founder-digest/index.ts`, the lifetime read (`.eq("window_start", LIFETIME_WINDOW).gte("updated_at", …).lt("updated_at", …)`)
- **claim:** mutating the lifetime filter's `updated_at` → `window_start` makes it permanently unsatisfiable (every lifetime row's `window_start` is the 1970 sentinel), so the lifetime section renders "none" forever with zero errors — the exact silent class the three-state rendering exists to prevent — and **0 of 19** tests reddened: the reads sat inside the handler behind `createClient(...)` where no test could reach them.
- **verification:** mutation applied, `deno test … founder-digest/` → 19/19 green; `grep -rn founder-digest test/` → nothing imports `handler`.
- **suggested-fix:** extract the query construction into something a fake builder can drive.
- **status:** accepted — fixed in commit 3: the three reads moved into exported `readDigestSections(client, window)` with a structural `DigestClient` type; every `.from("<table>")` chain stays literal and inline so `check_schema_column_refs.dart` keeps validating the columns (extracting the filters into table-less helpers would have moved them out of that gate's input set). `index_test.ts` gains 7 recording-fake tests pinning each section's table, select list, filter columns, order, limit, and the per-section unreadable state (including the alerts mirror, which a first version of the test missed — mutation n4 `if (error) return []` reddened nothing until the alerts-failing case was added). Mutations n / n2 / n3 / n4 now redden 1 each.

## Finding 4 — P2 — writer_reader_drift (mirror question B)
- **file:line:** `supabase/functions/delete-account/index.ts` (`bucketStartMs = floor(now / 3_600_000) * 3_600_000`) vs `founder-digest/index.ts` `istYesterdayWindow()`
- **claim:** delete-account's hourly buckets are UTC-hour-floored; IST midnight is 18:30Z, so the `[18:00Z, 19:00Z)` bucket straddles the day boundary — attempts in the first 30 minutes of an IST day carry `window_start = 18:00Z < tStart` and are reported on the PREVIOUS day's digest. verify-payment's 10-minute buckets are unaffected (18:30Z is an exact 10-minute boundary).
- **verification:** arithmetic from the two files (reproduced by the reviewer and by the author).
- **suggested-fix:** a comment on the `delete_account` entry; no functional change (same-magnitude shift, nothing lost or doubled).
- **status:** accepted — fixed in commit 3 as the comment (both entries annotated: the slop on `delete_account`, the reason `verify_payment` is exempt).

## Finding 5 — P3 — guard_without_its_mirror (mutation a)
- **file:line:** `supabase/functions/ai-media-proxy/index.ts` `if (isPro) {` (the PRO consume guard) / `test/contracts/pro_media_daily_caps_writer_to_reader_test.dart`
- **claim:** `if (isPro)` → `if (isPro && !isVideo)` — the exact pre-fix defect — reddened 1 of 15, and only through `_span`'s "anchor not found" guard (the literal `if (isPro) {` vanished), not through any assertion about the guard. The banned-literal list held `!isVideo && isPro` (the other operand order) and would not have matched either.
- **verification:** mutation applied, `flutter test …pro_media_daily_caps_writer_to_reader_test.dart` → 14 passed / 1 failed, message `anchor "if (isPro) {" not found`.
- **suggested-fix:** an assertion independent of the literal `if` text.
- **status:** accepted — fixed in commit 3: a 16th test reads the condition of the nearest `if (` above `p_quota_key: proQuotaKey`, pins it to exactly `isPro`, and requires no conditional and no `isVideo` between the guard and the RPC. Mutation a1 (`&& !isVideo`) now reddens 2; a2 (a nested `if (isVideo)` inside the block, which the anchor test cannot see) reddens 1.

## Finding 6 — P3 — DRY / stale_or_wrong_citation
- **file:line:** `LIFETIME_WINDOW = "1970-01-01T00:00:00+00:00"` as an independent literal in `ai-media-proxy/index.ts`, `weekly-report/index.ts`, `founder-digest/index.ts`
- **claim:** three copies of one sentinel; hoist to `_shared/ist_date.ts`.
- **verification:** `grep -n LIFETIME_WINDOW supabase/functions/*/index.ts` → 3 identical values.
- **status:** accepted — no code change, refactor declined with the reason recorded: the three literals are already pinned equal by construction — `founder_digest_caps_mirror_test.dart`'s `_resolveKind` classifies a `p_window_start` as lifetime ONLY when its `const` initializer is that exact string, so a drifted copy in any EF fails the kind assertion; and hoisting would change `weekly-report`'s source, forcing a redeploy of a function outside this batch's deploy set to keep git == live (`feedback_bad_news_vs_no_news`'s deploy-state clause).

## Mirror questions (agent A) — A CLEAN · B FINDING 4 · C CLEAN · D CLEAN · E CLEAN · F CLEAN · G CLEAN

## Mutation ledger (agent B, all restored byte-identically)
| # | file | mutation | red |
|---|---|---|---|
| a | ai-media-proxy | `if (isPro)` → `if (isPro && !isVideo)` | 1/15 (accidental — Finding 5; now 2/16) |
| b | ai-media-proxy | swap KEY ternary arms | 1/15 |
| c | ai-media-proxy | swap CAP ternary arms | 1/15 |
| d | ai-media-proxy | consume block moved after `geminiChat(` | 1/15 |
| e | ai-media-proxy | `proConsumeError` branch → `gated: false` | 1/15 |
| f | ai-media-proxy | delete the `subscriptionError` branch | 2/15 |
| g | ai-media-proxy | `proCount === -1` → `=== 0` | 3/15 |
| h | ai-media-proxy | unconditional `pro_daily_limit: proCap` | 1/15 |
| i | founder-digest | at-cap `>=` → `>` (windowed, lifetime) | 1/19 each |
| j | founder-digest | drop `if (kind === "lifetime") continue` | 1/19 |
| k | founder-digest | unreadable windowed rendered as `[]` | 2/19 |
| l | founder-digest | drop `escapeHtml` in `unreadableLine` | 1/19 |
| m | founder-digest | `telegramErrorSummary` → `String(err)` | 1/19 |
| n | founder-digest | lifetime `.gte("updated_at")` → `.gte("window_start")` | **0/19 → Finding 3 (now 1/26)** |

## Negative results worth keeping
- `consume_quota` EXECUTE is live `{service_role}` only (`has_function_privilege` for anon/authenticated → false) — migration 130's intent holds even though `supabase_migrations.schema_migrations` lists only through 129 (130 was founder-applied through the Management API; a tracking-table gap, not a security gap).
- Every literal in `index_test.ts` and the mirror test was recomputed by hand: `99 (2 users) · at cap 50: 1`, the top-users order, `istClock` → `00:15 `, the 18:29:59Z / 18:30:00Z flip, 2026-09-11 = Friday, all nine caps against their source constants (food_text's CASE cap correctly resolving to null).
- Telegram HTML: every DB/external field interpolated into the message is escaped; the only unescaped interpolations are hardcoded labels, integers and 8-char id prefixes.
- The Telegram send's error path is fully contained: `sendTelegram` never throws, so the handler's outer `catch` (which stringifies) can never see a URL-bearing fetch error.
- `usage_counters` / `alerts` select lists match `backups/live_schema_columns.json` exactly; `paged_fetch`'s "last order key must be unique" holds (the digest orders by the composite PK).
- `lib/` has zero readers of `gated` / `gate_reason` / `pro_daily_*` / `resets_at` — the 200-gated reply is rendered as an ordinary coach bubble, as the batch claims.

## Founder triage notes
All six accepted and resolved as recorded above; no product decision was needed. The two P1s are documentation-truth defects, not code defects — and both are the class this skill's 2026-09-10 and 2026-09-11 entries describe (a claim written before the fact). The pass earned its keep on Finding 3: a read that no test could reach, found only by mutation.
