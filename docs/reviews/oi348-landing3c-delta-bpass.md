---
reviewed_at: 2026-11-28T21:55:00+05:30
staged_against: dd778790 (changes after 22baa6da, including merge cd0711da)
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 3
verdict: accepted
---

# Code Review: changes after 22baa6da (OI-348 Landing 3c, PR #360)

One fresh, context-blind, read-only Sonnet seat, run after CI went green on `dd778790`. 0 P0, 0 P1, 1 P2, 2 P3.
The author re-read the code behind each. The seat also disabled the Windows branch of `applySuiteZone` itself and
got the 4 red tests that diagnose d0b7e4 states.

## Finding 1 — P2 — blast_radius_mismatch (merge before apply)
- **claim:** this head's client and copy assume the free cap is live. The SQL is still a draft; live migration 154
  requires an active subscription. If the branch merged first (a push to `main` deploys the web app), a free user's
  first photo would be refused and `ProgressPhotosScreen._onProRefused` would say the week's free photo is used.
  No mechanical check enforces the order; CI is green without the apply.
- **status:** no code change. The order is plan section 6: step 3 (rehearsals, apply, live verify, ledger entry, its
  own commit) comes before step 4 (merge). Each needs the founder's separate go. PR #360 must not merge before the
  apply.

## Finding 2 — P3 — guard_without_its_mirror
- **claim:** the "no Unlimited on the paywall surfaces" test did not read `lib/core/copy/progress_photo_copy.dart`,
  which now holds the progress-photo paywall strings. The seat's mutant passed 118 tests.
- **status:** fixed (the file added to the path list). Mutation run: `paywallSubtitle` changed to an "Unlimited"
  line (grep count 1): 1 test red, naming the file. Restored byte for byte (cmp). Clean: 24 passed across this file
  and the free-flow file.

## Finding 3 — P3 — stale test title
- **claim:** a title in `progress_photos_free_flow_test.dart` still said "Unlimited Progress Photos".
- **status:** fixed (title says "No-Limit Progress Photos"; no assertion changed).

## Founder triage notes
None: no finding changes a founder decision.

## Tuning entry
- **2026-11-28** - blast-radius platform - 3 findings; 0 false_alarm; tuning: none. The seat checked a word ban's
  file list against where the banned surface's strings now live, and mutated there.
