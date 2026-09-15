---
reviewed_at: 2026-06-08T07:05:00+05:30
staged_against: e3cc9075617a
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill (fresh-context)
lens_set: [revert_correctness, unintended_change, gate_correctness, secrets_in_tree]
findings_count: 7
verdict: accepted
---

# Code Review — e3cc9075617a (std encoding deploy-rot incident fix)

Fresh-context review of the 4-function `encode`-import revert (std@0.224.0 → 0.177.0)
+ the new `check_std_encoding_import_rot.dart` gate. **0 P0.** The revert itself is
confirmed correct (and was already proven by the live deploy + smoke: razorpay-webhook
v20 = 400, verify-payment v14 = 401). All findings triaged below; the staged diff this
file is named against contains the fixes.

## Finding 1/2/7/8/9 — CLEAN
- Revert correctness: std@0.177.0 exports `encode` for both hex.ts + base64.ts; the
  call-site arg types (`Uint8Array`) are compatible; razorpay-webhook:68 decodes the
  hex bytes via `TextDecoder`. Sound.
- No credential literals introduced.
- Gate avoids false-positives on `encodeHex`/`encodeBase64`/`decodeHex`/`decodeBase64`
  (token-split strips `as alias`, exact-matches `encode`/`decode`).
- Gate auto-wired via the `scripts/check_*.dart` glob.

## Finding 4 — P1 (claimed) — FALSE ALARM (verified)
- **claim:** gate threshold `>=210` misses base64 `encode` removed at 0.203.
- **verification:** I directly fetched std@{0.202,0.203,0.209,0.210}/encoding/{base64,hex}.ts.
  `encode` is PRESENT in BOTH modules through 0.209 and ABSENT at 0.210. The reviewer's
  "base64 removed at 0.203" was a hallucinated boundary (the global rule on subagent
  version numbers). The flat `>=210` threshold is CORRECT.
- **status:** false_alarm (gate unchanged)

## Finding 5 — P2 (claimed) — FALSE ALARM (verified)
- **claim:** gate comment "removed at 0.210" is wrong for base64.
- **verification:** same live fetch — base64 `encode` removed at 0.210, so the comment is
  correct. This finding inherits Finding 4's false premise.
- **status:** false_alarm

## Finding 3 / 6 — P2 — FIXED
- **claim:** ai-media-proxy + create-razorpay-order mixed std versions within one file
  (serve@0.224.0 + encoding@0.177.0).
- **fix:** pinned their `serve` import to std@0.177.0 too, so all 4 affected files are
  internally consistent on 0.177.0 (the reviewer's recommended state). These 2 functions
  are not redeployed (running their working old bundles); the source is defused for their
  next deploy. razorpay-webhook + verify-payment were already fully 0.177.0.
- **status:** accepted (fixed)

## Finding 10 — P3 — accepted (project-wide pattern)
- gate uses `Directory('supabase/functions')` relative path + silent SKIP if absent —
  identical to every other `check_*.dart` (e.g. check_schema_column_refs uses
  `Directory('lib')`). Pre-commit runs gates from the repo root, so it's safe. No new
  risk; left consistent with the project pattern.

## Founder triage notes
2 fixed, 2 false_alarm (verified against live std), 5 clean, 1 accepted-as-pattern. The
P1 was refuted by direct verification — exactly the trust-but-verify discipline. No
P0/P1 stands.
