---
reviewed_at: 2026-10-18
staged_against: launch-status-note merge 779513f4 (git diff 45250e91 779513f4) plus the working-tree fixes on branch launch-status-record
blast_radius: platform (CLAUDE.md is a platform-tier path; the other files are feature tier)
reviewer: two claude-sonnet reviewers, fresh and context-blind, read-only by an exhaustive command list, run in sequence (round 2 on the post-round-1 state)
lens_set: [documentation_rot, claim_vs_code, writer_reader_drift]
findings_count: 8
verdict: accepted
---

# B-pass review: the launch-status note (`launch-status-note`, fixes on `launch-status-record`)

Date: 2026-10-18. Docs-only change: a "Launch status" sentence in CLAUDE.md section 1, OI-345 / OI-346 wording, an OI-311 third-sighting paragraph, GO_LIVE row 3.5, regenerated OPEN_INDEX.md. No code.

## Why this file exists after the merge

PR #123 merged as `779513f4` and main CI failed its `Plan-review record (>=account merge-to-main)` job: CLAUDE.md classifies as platform tier and the branch had no record. The author had read the diff's tier as `feature` (the classifier was fed the diff on stdin, which it does not read) and ignored the pre-commit line "blast-radius=platform (>=account) -- run /code-review (B-pass) before pushing". This review was run after the merge, for real, and its findings were fixed; it is not a retroactive stamp.

## Round 1 (3 findings, all P3, all fixed)

1. P3 `open_issues.md` OI-311 "Blocked on" still said the second sighting; now "second and third".
2. P3 OI-311 lead-in "The one failure was a single run on main" was already stale; reworded.
3. P3 CLAUDE.md section 1 said `upstream_blocked` without saying that on the OI board it is prose in "Blocked on" with Status OPEN; clause added.

Verified clean in round 1: `_kEnablePhoneEnlist = false` at `sign_in_screen.dart:41`; the third-sighting facts (test name, exit 254, the stderr line, merge 45250e91); OI numbers; OPEN_INDEX line anchors; no contradicting statement in the auth docs or GO_LIVE.

## Round 2 (5 findings: 2 P2, 3 P3, all fixed)

1. P2 OI-311's heading counts July as first and 2026-10-04 as second while the body names 10-13 "Second" and 10-17 "Third": the count contradicted itself. Fixed: the lead-in now lists the four sightings and says the two paragraphs count from 2026-10-04.
2. P2 the third-sighting paragraph stated an inference as fact ("the failing step is the script reading the registry"). Softened to "consistent with ... the origin of the message is still not located".
3. P3 "NOT live in any store" omitted the public web app. Now says the web app is reachable but every existing account is a testing account.
4. P3 OI-346 "Fix (to decide)" still read as an open decision. Now "to decide at store launch; parked".
5. P3 CLAUDE.md grew ~280 characters. `check_context_artifact_budget.dart` run: PASS, 13 within band.

## Not re-reviewed

The round-2 fixes are wording only and were not given a third reviewer. They were checked by grep (OPEN_INDEX regenerated, line anchors unchanged) and the budget gate.
