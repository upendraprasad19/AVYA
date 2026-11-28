---
reviewed_at: 2026-11-26T22:30:00+05:30
staged_against: e474ed8ed10bf508546b3cab1e8c16f4376fde0b
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [guard_without_its_mirror, asserted_fixture_value, writer_reader_drift, unawaited_no_error_sink]
findings_count: 5
verdict: accepted
verdict_note: the Hermes fix commit's own B-pass (hermes-pass skill, 2026-10-25 lesson), delta e77c1933..e474ed8e; 4 fixed, 1 no change needed
---

# Code Review (delta B-pass) — the Hermes fix commit of oi348-landing3c

One fresh Sonnet seat on `git diff e77c1933 e474ed8e` only. 0 P0, 0 P1. It ran the free-slot and wiring
tests (54 green) and `dart analyze` on the repository; no SQL.

## Finding 1 — P2 — guard_without_its_mirror
- **file:line:** test/sql/progress_photos_free_weekly_cap_rollback_verify.sql (R4)
- **claim:** R4 could not see a rollback that dropped 154's `SET search_path` (proconfig reset to NULL), nor a
  leftover caller guard in the body.
- **verification:** `grep -n "proconfig\|auth.role" test/sql/progress_photos_free_weekly_cap_rollback_verify.sql`
- **status:** accepted, fixed: R4 requires `proconfig = ARRAY['search_path=public, pg_temp']` and a body with no
  `auth.role`.

## Finding 2 — P3 — asserted_fixture_value
- **file:line:** test/sql/progress_photos_free_weekly_cap_rollback_verify.sql (R5, R3)
- **claim:** R5 passed on privileges inherited through PUBLIC, so it could not tell a different ACL from 154's.
- **status:** accepted, fixed: R5 compares the ACL as a sorted set (`COLLATE "C"`) with the live string recorded
  2026-11-26. R3 stays: it reddens if the rollback drops 154's own trigger, which is the mistake it guards.

## Finding 3 — P3 — writer_reader_drift (doc)
- **file:line:** test/sql/progress_photos_free_weekly_cap_live_verify.sql:26
- **claim:** the "before the apply" list of expected `fail` lines missed W8b, W10b, W14b.
- **status:** accepted, fixed (with the reason for W10b / W14b), plus a note on the EXECUTE string tags in both
  verify headers.

## Finding 4 — P3 — guard_without_its_mirror
- **file:line:** lib/features/profile/repositories/progress_photo_repository.dart (`progressPhotoServerRefused`)
- **claim:** a bare 408 (proxy request timeout) or 499 (client closed) counted as an answer, though the write may
  still be running behind the proxy.
- **verification:** `flutter test test/contracts/progress_photo_free_slot_test.dart`
- **status:** accepted, fixed: `_isAnswering4xx` excludes 408 and 499 in both branches; truth-table rows 408 /
  499 / 429 / storage 408 / 413. Mutant (408 and 499 counted again): 3 red, `cp` / `cmp` restored.

## Finding 5 — P3 — none
- **claim:** `ownFailedCleanups` keeps a path that was never stored until the app restarts.
- **status:** no change needed: one string per failed write, and a path never listed is never a candidate.

## Founder triage notes
All handled by the author; none reverses a founder decision.

## Tuning entry
- **2026-11-26** - blast-radius catastrophic - 5 findings; 0 false_alarm; tuning: none. A verify script's checks need the same "which mutant turns this red?" question as a contract test: R4 and R5 were each true on a wrong rollback.
