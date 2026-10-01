---
reviewed_at: 2026-09-13T18:45:00+05:30
staged_against: 1214f9bbb700
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 5
verdict: accepted
---

# Code Review — 1214f9bbb700

Two fresh Sonnet subagents reviewed the staged OI-153 apply commit (30 files,
+1845/−194 before this review's own remediation), lens set split 1-5+10 /
6-8 per the code-review skill's 2026-09-08 tuning (catastrophic tier —
migration 131's COMMENT contains "SECURITY DEFINER"). Brief:
`bpass4_brief.md` (scratchpad). 5 real findings, 0 false alarms, 1
verified_clean. All fixed in this same batch; none deferred.

## Finding 1 — P1 — guard_without_its_mirror / asymmetric mislabel paywall
- **file:line:** supabase/functions/ai-media-proxy/index.ts (pre-fetch video
  paywall block, now removed; `checkFreeImageQuota` extracted)
- **claim:** The Hermes L23 F2 served-MIME reconciliation (already in this
  same commit) only reconciled ONE direction — an image mislabelled as video.
  The pre-fetch video paywall still ran on the RAW, unverified
  `media_type` claim: a free user who mislabelled a real VIDEO as `"image"`
  was paywalled before the fetch on the false claim, denying a legitimate
  free analysis. The naive fix (delete the pre-fetch paywall) would have
  opened a WORSE bug: the pre-fetch free-image-cap check is ALSO gated on
  the same unverified claim, so a free user could bypass the free-image
  lifetime cap entirely by labelling every image "video".
- **verification:** Traced both call sites in source; confirmed the
  pre-fetch free-image-cap check (`if (!isVideo && !isPro)`) shares the same
  claim-gated `isVideo` the video paywall used. Fix: extracted
  `checkFreeImageQuota` as a shared, exported helper; call sites are now
  pre-fetch (fast path, unchanged trigger) AND a NEW post-fetch mirror (after
  `isVideo` reconciliation). `pro_media_daily_caps_writer_to_reader_test.dart`
  rewritten: "the video paywall has EXACTLY ONE site" (`sites.length == 1`)
  and "the free-image cap check has EXACTLY TWO sites, sharing ONE helper"
  (`sites.length == 2`, both calling `checkFreeImageQuota`). Mutation: reverting
  to the two-site video-paywall / one-site free-check shape reddens both new
  tests (2/19); restored byte-identical (sha256 matched the saved
  `amp_index.ts.f2fix` copy).
- **suggested-fix:** Applied — see verification.
- **status:** fixed

## Finding 2 — P1 — staged-vs-working-tree drift (mirrors `feedback_green_check_input_set_width.md`)
- **file:line:** supabase/functions/founder-digest/index.ts (alerts read,
  `.limit(...)`)
- **claim:** An earlier on-disk edit changing the alerts read to a literal
  `.limit(10)` (required by `check_unbounded_cron_reads.dart`, which reads
  only literals, not the `MAX_ALERT_LINES` symbol) was made on disk but never
  re-staged. The actual STAGED/committed content still carried
  `.limit(MAX_ALERT_LINES)` — the exact defect the gate exists to catch,
  silently present in what would have shipped.
- **verification:** `git diff --cached -- supabase/functions/founder-digest/index.ts`
  before the fix showed the working tree and the index disagreeing on this
  line. Re-staged (`git add`); `check_unbounded_cron_reads.dart` now passes
  with the literal in place; `index_test.ts`'s read-shape test pins the
  literal equals `MAX_ALERT_LINES` (so the two can never silently diverge
  again). Same class as `feedback_green_check_input_set_width.md`'s
  `part`-file row: the check that matters ran against a different input
  (disk) than what would actually be committed (index).
- **suggested-fix:** Applied — re-stage; keep the literal/symbol equality
  pinned by a test.
- **status:** fixed

## Finding 3 — P2 — asserted_fixture_value / monotonic-counter misuse
- **file:line:** supabase/functions/founder-digest/index.ts,
  `unlistedTotals(rows)`
- **claim:** For an unlisted quota key not in `DIGEST_KEYS`, the digest
  summed raw `used` across all rows for that key. For a LIFETIME key this is
  wrong: `used` is a cumulative counter, not a bounded day's activity, so
  summing two different users' cumulative totals (e.g. 100 and 5) produces a
  meaningless number (105) rather than anything a reader could act on.
- **verification:** Read `unlistedTotals`'s call sites and the `mode`
  distinction already used elsewhere in the same file for windowed vs
  lifetime keys; confirmed no such distinction existed here. Fix: added a
  `mode: "windowed" | "lifetime"` parameter — windowed sums `used` (correct,
  a bounded day total); lifetime counts DISTINCT movers and reports
  `"<key> N users moved"`. New test "an unlisted LIFETIME key reports
  MOVERS, never a summed cumulative counter" — two users with cumulative
  `used` 100 and 5 assert `"ghost_lifetime 2 users moved"`, never `"105"`.
  Mutation: reverting to bare summation reddens this test (1/33); restored
  byte-identical.
- **suggested-fix:** Applied — see verification.
- **status:** fixed

## Finding 4 — P2 — guard_without_its_mirror / vestigial over-restrictive guard
- **file:line:** supabase/functions/ai-media-proxy/index.ts,
  `fetchImageAsBase64` (pre-check before `parseStorageUrl`, now removed)
- **claim:** A redundant raw-string check
  (`imageUrl.startsWith(STORAGE_PREFIX)`) ran BEFORE `parseStorageUrl` and
  was strictly MORE restrictive than it — it rejected a differently-cased
  host (`EXAMPLE.supabase.co`) or an explicit default port
  (`:443`) that `parseStorageUrl`'s `new URL()`-based normalisation correctly
  accepts as the same origin. A false-rejection bug, not a security gap
  (the redundant check could only narrow admissions, never widen them) —
  but it also made the diagnose-doc's own claim ("the guard and the request
  can no longer see two paths") false while it survived, since two
  origin-checks existed.
- **verification:** Read both checks side by side; confirmed the raw-string
  form cannot match a case-varied host or an explicit `:443` while
  `new URL(...).href` normalises both to the identical string
  `parseStorageUrl` already checks. Fix: deleted the pre-check; folded its
  pinned error message onto `parseStorageUrl`'s `null` branch, which is now
  the ONLY origin check. New test: "a differently-cased host or an explicit
  default port is NOT rejected — parseStorageUrl is the ONLY origin check" —
  both shapes fetched successfully. Mutation: restoring the deleted
  pre-check reddens this test (1/21); restored byte-identical (sha256
  matched the saved `amp_index.ts.f1fix` copy). Live v26 traversal probes
  (403/403/400, unchanged) confirm the deletion did not reopen c7e2a4.
- **suggested-fix:** Applied — see verification.
- **status:** fixed

## Finding 5 — P3 — asserted_fixture_value (verified_clean)
- **file:line:** supabase/functions/founder-digest/index.ts (top-users /
  distinct-mover counting fallback shared across several sections)
- **claim (as raised):** A count-fallback pattern shared by several digest
  sections could, in principle, double-count or under-count the same way
  the lifetime-summation bug (Finding 3) did.
- **verification:** Independently traced all 6 other call sites sharing this
  pattern; confirmed each is windowed (bounded-day, correct to sum) rather
  than lifetime, and the pattern is explicitly documented and tested as
  intentional in `index_test.ts` ("totals, distinct users and at-cap use
  `used >= cap`"). Not a recurrence of Finding 3's defect — Finding 3's bug
  was specifically the LIFETIME-mode omission, which this pattern does not
  have. Consistent with the disposition of similarly low-risk PARTIALs
  (H16/H17/H19) in the Hermes report for this same batch: fixing this in
  isolation would introduce inconsistency with the other 6 sites for no
  behavioural gain.
- **suggested-fix:** none — no defect.
- **status:** verified_clean

## Clean checks (both agents, consolidated)
- `secrets_in_tree`: no credential-shaped literals in the staged diff
  (`grep -nE "sk-|rzp_live_|AKIA|-----BEGIN"` over the staged diff — 0 hits).
- `function_exception_swallow`: no new `.functions.invoke(` call sites in
  the staged diff.
- `blast_radius_mismatch`: migration 131's COMMENT triggers the
  `SECURITY DEFINER` content rule → catastrophic; this review + the Hermes
  E-pass + the plan-review record's `hermes: accepted` field satisfy that
  tier.
- `unawaited_no_error_sink`: no new `unawaited(` in the staged diff.
- `missing_input`: migrations 131/132 apply against live tables that exist
  (`private.cron_get_secret`, `usage_counters`) — confirmed via
  `information_schema` before apply, per the diagnose-docs.

## Founder triage notes
All 5 real findings fixed in this same batch (Findings 1-4) or verified
clean with no code change needed (Finding 5). No `spawn_followup_task`
items — the one genuinely deferred-scope item this batch surfaced (the
fleet-wide `cron_telemetry.ts` redeploy for OI-194) is tracked as OI-194 on
the board, not a code-review finding.
