---
branch: oi153-pro-media-caps
date: 2026-09-13
blast_radius: platform
review_rounds: 4
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/88cfc8594fcc-review.md
---

# Plan-review record — OI-153: PRO media caps on the ledger + the founder's daily digest (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`, COMPUTED** — `git diff main...HEAD --name-only | dart run
scripts/blast_radius_from_diff.dart -` → `platform` on the branch diff (28 files at the B-pass, the
same answer for the staged set of every commit). The two migrations this batch applies (131 cron
row, 132 a `CREATE OR REPLACE` of one trigger) were classified from SCRATCH COPIES before being
written into the tree (§4.9's fail-open row): neither contains `SECURITY DEFINER` — 131 uses a
literal function URL rather than a `private.<fn>_function_url()` definer helper for exactly that
reason — so the content rule does not lift either to catastrophic. No Hermes pass is owed.

## Rounds

The full round-by-round tables, every disposition and every author-side verification are in the
spec, `docs/audit/oi153-plan.md` (§ "Rounds"). Summary here so the record stands alone.

**Round 1 — 14 REAL (0 P0, 4 P1, 10 P2), 6 FALSE_ALARM.** The P1s redesigned the gate: an advisory
read followed by consume-after-delivery does not bound Gemini spend under concurrency (N in-flight
requests past the read all reach Gemini) → consume-FIRST, placed after the Storage fetch and before
the Gemini call; the ledger census's direct-`usage_counters` allowlist had to gain the digest; the
digest's 4-key cap map was membership, not completeness, over a 9-section template → `DIGEST_KEYS`
enumerates every key and a mirror test pins the set both ways; `orderBy: string[]` fails `deno
check` → `OrderKey[]`. Every finding was re-verified by the author against the tree before adoption
(subagents hallucinate constants — line numbers, the census scan scope, the `OrderKey` type).

**Author pass between rounds (not a round).** Round 2's first dispatch died on an API usage limit.
Re-verifying every cited file:line before re-dispatching found one guard-without-mirror gap of the
plan's own making: the "unlimited" reword covered ONE of THREE such strings in the copy mirror pair.

**Round 2, on the hardened plan — 13 (0 P0, 3 P1, 10 P2).** New material issues introduced BY the
round-1 corrections: migration 132 would have errored every test in `cap_triggers_use_usage_counters_test.dart`
at `setUpAll` (it asserted all three triggers resolve to the SAME file) → per-trigger resolution
with the backfill pinned to 129 by name; `as const` on `DIGEST_KEYS` makes `k.cap` TS2339; the
copy-mirror extractor's `[^'"]*` breaks on apostrophes; a `fetchImageAsBase64(` anchor hit the
declaration, not the call; `quota_unavailable` is a substring of `pro_quota_unavailable`; the
subscriptions-read error was DISCARDED (a PostgREST fault routed paying users down the free path)
→ `tier_unavailable`, fail closed; `-1` leaves the ledger row untouched so the digest cannot count
refusals — "at cap" is the signal.

**Round 3 — 5 (0 P0, 1 P1, 4 P2).** The import cycle (the proxy imports `coach_replies.ts`, so the
copy cannot import the cap constant) → cap copies become FUNCTIONS taking the number; `.rpc(` split
across lines defeats a single-line anchor → the mirror test anchors on `p_quota_key:\s*(\w+)`;
`videoPaywall` omitted from the mirror; `=== -1` ambiguous with the free branch's; M8 had no site;
T4/T5 had no mutation → M13/M14.

**Round 4, bounded to the test/spec layer — 5 (0 P0, 0 P1, 5 P2), no design choice among them.**
Spec-precision corrections only: migration 102's `_function_url` shape, the `security\s+definer`
content rule's case-insensitivity, the absence of a migration-header gate, an unquoted
`cron.unschedule(<…>)` escaping Gate 31's raw scan, the registry row format.

**Convergence.** 14 → 13 → 5 → 5 findings; MECHANISM findings 1 → 0 → 0 → 0. Round 4 surfaced no
new class. §4.12.1's split trigger (successive rounds surfacing new material classes) did not fire:
rounds 2–3 were the corrections' own defects, round 4 was wording.

## Ground truth (verified live, project `dedsavbjuwgarrhphgnl`)

Before design: 0 rows on either channel the H-23 gate counted, in the table's whole history (the cap
had never fired); `subscriptions` read error discarded in the pre-fix code; `channel` nullable with
default `'app'` and 0 NULL rows; all 12 writers pass a guarded literal; `consume_quota` EXECUTE is
`{service_role}` only (130 applied 2026-09-11 by the founder through the Management API — it is
NOT in `supabase_migrations.schema_migrations`, a tracking gap the B-pass re-confirmed, not a
security gap); pg_cron 1.6.4 (named `cron.schedule` upserts); `private.cron_get_secret()` exists;
29 cron jobs, max jobid 37 (`usage_counters_retention_daily`, which the committed snapshot did not
yet carry — regenerated in the apply commit); `alerts` holds 29 rows, none since 2026-07-27.

At the B-pass (2026-09-13): live `ai-media-proxy` is **v23 (2026-09-10), the PRE-fix bundle** — the
diagnose-doc's tier-6 line had claimed the deploy was done and was corrected (B-pass finding 1).
The deploy is the last step of this batch, after the merge, pre-authorized by the founder on
2026-09-12 together with the merge, the `founder-digest` deploy and migrations 131 + 132.

## B-pass (platform → required)

`docs/reviews/88cfc8594fcc-review.md` — two context-blind agents over the branch diff at
`f15fad75`, 15 mutations run and restored. **6 findings (0 P0, 2 P1, 2 P2, 2 P3), 0 false alarms,
all accepted.** The mechanism finding: the digest's reads lived inside the handler where NO test
could reach them, so mutating the lifetime filter to a column that can never match reddened
nothing → reads extracted into `readDigestSections`, driven by a recording fake client (7 new Deno
tests; mutations n/n2/n3/n4 redden 1 each). The two P1s were documentation-truth defects (a deploy
claimed before it happened; a cited SQL file that did not yet exist) — both fixed in the same docs
commit, the SQL file written and landed with this record.

## What this record does NOT claim

- The ai-media-proxy deploy: post-merge, recorded in `docs/audit/oi153-pro-media-caps.closure.yaml`
  and the project memory, not here.
- Migrations 131/132 and the `founder-digest` deploy: the apply commit that follows this one
  carries the files, `backups/applied_migrations.json`, the regenerated cron snapshot and the
  CRON_REGISTRY row; each applied on the founder's already-given go.
- Runtime behaviour of the Edge Functions: source-greps + `deno check` (local, whole tree) +
  the Deno unit tests + the deploy-time smokes. The live ledger behaviour is
  `test/sql/oi153_pro_media_caps_live_verify.sql` (Part A runnable now; B/C after the apply).
