---
reviewed_at: 2026-11-26T21:00:00+05:30
staged_against: 6766a1015627f37988adf60e7b91119b37b950cc
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 5
verdict: accepted
verdict_note: all five accepted and fixed on the branch (fix commit after 6766a101); 0 P0, 0 P1. Dispatched before PR 360's CI finished because land_pr.sh --ci-only fails on Windows (SIGTERM errno 50); the reviewed head was pushed and locally analyze-clean.
---

# Code Review (B-pass) — oi348-landing3c @ 6766a101

One fresh Sonnet seat, context-blind, the eight lenses, the three-dot diff `origin/main...HEAD` (32 files).
It ran five of the eight allowed test files (286 tests, all green), no SQL, no scripts, no git writes. It found
no way past the weekly cap and no way for the orphan sweep to remove a photo that has a row.

## Finding 1 — P2 — blast_radius_mismatch
- **file:line:** docs/plan-reviews/oi348-landing3c.md:4; docs/blast_radius.yaml:98-101
- **claim:** The record said `blast_radius: account` and "no Hermes". The migration this draft becomes is a
  `SECURITY DEFINER` change on `storage.objects` and `public.progress_photos`, the risk class of migration 154
  (catastrophic by its `*rls*` name). Its planned name matches no catastrophic glob.
- **verification:** `sed -n 52,67p scripts/blast_radius_content_rules_lib.dart`
- **suggested-fix:** name the migration to match `*rls*`, or record the tier.
- **status:** accepted. Author's check: the gates already force it. `contentForcesCatastrophic` grades any
  `supabase/migrations/` file containing `SECURITY DEFINER` as catastrophic at commit
  (`check_code_review_pass_exists.dart`) and at merge (`check_plan_review_record_exists.dart`), so nothing would
  have slipped through, but the record and plan were wrong about the work owed. The record now says
  `catastrophic`, `hermes: pending`; the migration commit takes a staged review and the merge a Hermes pass,
  as 154 did. The file name stays descriptive; the content rule is the binding one.

## Finding 2 — P2 — writer_reader_drift (SoT cites)
- **file:line:** docs/sot_registry.yaml:20412, 20837 (paywall_sheet.dart); 1171, 1195, 1220, 4798, 8356 (subscription_service.dart)
- **claim:** The diff shifts `paywall_sheet.dart` by +1 and `subscription_service.dart` by +2 after line 675; no cite moved. Several were stale on `main` already.
- **verification:** `node <scratchpad>/m3c/spans.js lib/core/services/subscription_service.dart _downgradeLocally verifyFromServer gateAndVerify`
- **status:** accepted. Every cite of both files re-derived from the code (doc comment to closing brace), the
  stale-on-main ones included: `_downgradeLocally` 1256-1318, `verifyFromServer` 1054-1164 (twice),
  `gateAndVerify` 741-864 (its `gate()` shim now :732), `_enforceEntitlementInvariants` 470-526,
  `evaluateEntitlement` 528-570, `writeSubscriptionState` 308-387, `isPro` 391-420, `proStateSnapshot`
  422-448, the event span 235-1318, the constructor `line: 50` (was 17), the `isPaymentInFlight` readers 779 /
  907; `_validatePromoCode` 256-307, the none-mode branch 466-476. Historical audit and diagnose docs keep
  their dated cites.

## Finding 3 — P2 — writer_reader_drift (doc contradiction)
- **file:line:** docs/architecture/subscription.md:100
- **claim:** The 2026-10-05 paragraph still describes the read-only gallery, the locked card and the
  `subscriptions` conjunct beside the new paragraph that supersedes it.
- **verification:** `git grep -n "SUPERSEDED for progress photos" docs/architecture/subscription.md`
- **status:** accepted. The old paragraph opens with a SUPERSEDED note naming what is gone and what still
  holds (the screen gates itself).

## Finding 4 — P2 — guard_without_its_mirror (client cleanup)
- **file:line:** lib/features/profile/repositories/progress_photo_repository.dart (`capture` catch, `removeIfNoRow`)
- **claim:** A row insert that fails without a server answer may still commit after the cleanup's row read
  found none: the object is removed and the late row points at nothing (a broken tile that also holds the
  week). The cleanup calls have no timeout, so the Add spinner can hang.
- **verification:** `flutter test test/contracts/progress_photo_free_slot_test.dart`
- **status:** accepted. `cleanupAfterFailedInsert`: a `PostgrestException` (the server answered, nothing
  committed) cleans up at once; any other failure goes to the 2-minute sweep, which reads the row again first.
  Every cleanup step and the free-slot pre-check are bounded by `progressPhotoStorageCallTimeout` (10 s; the
  pre-check then lets the server decide). Mirror cost, stated in the diagnose doc: a transport-failed upload
  holds the slot for about 2 minutes. Mutations (cp / cmp): PostgREST branch forced [3 red], the old direct
  call restored [1], the row-read timeout dropped [1], the pre-check timeout dropped [1, presence pin].

## Finding 5 — P2 — asserted_fixture_value / missing_input (live verify)
- **file:line:** test/sql/progress_photos_free_weekly_cap_live_verify.sql; test/sql/progress_photos_free_weekly_cap_draft.sql:192
- **claim:** No case for Storage's own role on a signed upload, a nested name, an upsert; the row door's
  `v_week + interval '7 days'` assumes the session time zone.
- **status:** accepted. The bound is now `interval '168 hours'` (an exact width in any session zone; rule-test
  pin and mutant moved with it). W16: a nested name is capped by its folder's owner. The upsert case is
  documented as uncovered on purpose (`upsert: false` in the client; a BEFORE INSERT trigger fires before
  conflict resolution). Storage's own role on a signed upload is added to OI-531 as item (3), closed by the
  founder's web upload after the apply. The uppercase-uuid folder is not reachable by an `authenticated`
  caller (the own-folder policy compares the text) and the client writes `auth.uid()`'s lowercase form.

## Founder triage notes
All five accepted and fixed by the author on the branch; none reverses a founder decision.

## Tuning entry
- **2026-11-26** - blast-radius catastrophic - 5 findings; 0 false_alarm; tuning: none. The seat found the tier mismatch from the glob table alone; the content rule (SECURITY DEFINER forces catastrophic) is in `scripts/blast_radius_content_rules_lib.dart`, not in `docs/blast_radius.yaml`, so a brief should name both.
