---
bug_id: d4e9a2
date: 2026-08-30
batch: profile-phase-fixes
status: fixed
blast_radius: platform
symptom: |
  Founder (upendraprasad19@gmail.com) signed in via a fresh private/incognito
  browser tab (web, so genuinely empty local Hive — the same shape as a fresh
  install). Edit Profile's "Full Name" field rendered blank even though the
  account has been active since 2026-05-01. Confirmed live: `public.users
  .full_name = "Upendra"` in Postgres (verified by direct SQL query), so the
  write side is correct — this is a restore/read-side gap.

  The app's own telemetry probe (`profile_full_name_empty_at_read`, added
  under APK Test #12.8 for exactly this symptom class) confirms it fired for
  this account FOUR times — 2026-08-05 and three times on 2026-08-29
  (`reader=user_first_name` ×2, `reader=edit_profile` ×2 total across both
  dates) — and ALSO for a second, unrelated account (`8c8a1d03…`,
  `anoopdd13@gmail.com`, full_name "Bruce Wayne") twice, on 2026-08-01 and
  2026-08-27 (`reader=user_first_name rawName=<null> hasProfile=true`). All
  6 occurrences are `platform: web`. This is a live, currently-recurring bug
  affecting 2+ real accounts, not a one-off.

  CORRECTED (B-pass review, same batch): this section originally
  misidentified the second account as `amar@gmail.com` — live re-query
  (`select ce.*, u.email, u.full_name from client_errors ce join users u on
  u.id=ce.user_id where op_type='profile_full_name_empty_at_read'`) shows
  the second account is actually `anoopdd13@gmail.com`; `amar@gmail.com` is
  a genuinely different user_id (`0f35f3dd-...`) with zero occurrences of
  this event. The per-account occurrence split (4 founder / 2 other) was
  also corrected from an earlier, wrong 2/3 split. Neither correction
  changes the diagnosis or the fix — only the evidence citation.

  ROOT CAUSE (leading hypothesis — see `forbidden_patterns_checked` for what
  was ruled out first): `_restoreUserProfile`'s `public.users` SELECT
  (full_name + email) had no retry. A token that expires mid-restore comes
  back as EITHER a 401 (thrown, already caught non-fatally) OR an
  RLS-filtered EMPTY result — HTTP 200, `null` — indistinguishable from "no
  such row", no exception at all. The second shape silently dropped
  `full_name` from the profile-map merge while the rest of the restore (from
  `user_profile`) succeeded, which is exactly why `hasProfile=true` but
  `rawName=<null>` at every reader: the profile map exists, `full_name`
  specifically does not.

  This is the SAME ambiguity `AuthSessionBootstrapper.resolveDestination`
  already hit and fixed for a different query (diagnose c2e9f4, its own
  `user_profile` SELECT) via `ensureFreshToken()` + one hard-refresh retry.
  That fix was never extended to this structurally identical query in a
  different file — the recurrence class this diagnose-doc closes.

  RULED OUT before landing on the above (§4.1 — writer/reader named first):
  traced `_goHome`'s fast-path/full-restore branch decision
  (`restoring_screen.dart:296-348`) — a private-window session has an
  empty `userBox.get('profile')`, so `isReturning` is false and it correctly
  takes the "await the full restore" branch, not the background-restore
  fast path. So this is not a navigate-before-restore-completes race; the
  failure is inside the restore call itself.
concept: user_full_name
sot_registry_entry: user_full_name
writers:
  - { file: lib/core/services/sync/sync_profile.dart, method_or_widget: "_fetchUsersRowForRestore — proactive ensureFreshToken() + first select()", line: 688 }
  - { file: lib/core/services/sync/sync_profile.dart, method_or_widget: "_fetchUsersRowForRestore — retry: auth.refreshSession() then select() again on a null first result, wrapped in its own catch (B-pass finding 3)", line: 714 }
  - { file: lib/core/services/sync/sync_profile.dart, method_or_widget: "_restoreUserProfile — else-if branch: C3 single-call null injection logged distinctly, no retry attempted (B-pass finding 1)", line: 603 }
  - { file: lib/core/services/sync/sync_profile.dart, method_or_widget: "_restoreUserProfile — merges usersRow into the Hive profile map (unchanged; now fed by the retrying helper)", line: 648 }
readers:
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: "initState — fullNameAtRead + the profile_full_name_empty_at_read probe", line: 119 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: "UserFirstNameNotifier.build — the user_first_name probe", line: 196 }
hive_key_prefix: "n/a — single key within userBox['profile'] map, not a prefixed series"
hive_key_formula: "userBox['profile']['full_name']"
sync_methods: [syncProfileNow]
restore_methods: [_restoreUserProfile, _fetchUsersRowForRestore]
cloud_table: users
cloud_columns: [full_name, email]
contract_test_path: test/contracts/restore_users_row_retry_test.dart
ist_handling: "n/a — no date keys, cloud date columns, or counter resets touched by this fix"
provider_invalidations: []
telemetry_op_types:
  success: [restore_users_row_retry_succeeded]
  failure: [restore_users_row_token_refresh_failed, restore_users_row_empty_retrying, restore_users_row_retry_still_empty, restore_users_row_retry_threw, restore_users_row_null_via_singlecall]
cross_account_guard: |
  Inherited, not re-implemented. `_restoreUserProfile` writes the merged map
  through `ProfileWriteService.instance.updateProfile(merged, skipSync:
  true)` (sync_profile.dart:649, unchanged), which routes through
  `wrapUserScopedBox` like every other WriteService. This fix only changes
  what feeds that write (the `users` row fetch) — it adds no new Hive access
  and no new cross-account surface.
forbidden_patterns_checked:
  - "No raw Hive.box( — the fix is entirely within the existing network-fetch helper; no new Hive access."
  - "No new .select() column reference — full_name + email were already selected; check_schema_column_refs.dart is unaffected."
  - "The preFetchedUsers (C3 single-call) injection mechanism itself is untouched — _fetchUsersRowForRestore is called ONLY on the identical(preFetchedUsers, _kNoInject) branch, same as the code it replaced. IMPORTANT (B-pass finding 1): this means the retry+telemetry added by this fix is UNREACHABLE on the C3 single-call restore path — the path tried FIRST for every restore (sync_service.dart:1417) — because C3 injects `tables['users']` directly, bypassing the helper entirely. A new else-if branch now logs `restore_users_row_null_via_singlecall` distinctly on that path instead of silently doing nothing; see impact_analysis for the full coverage boundary."
proposed_fix: |
  Extract the inline `users` SELECT (sync_profile.dart:596-615, pre-fix) into
  a new helper, `_fetchUsersRowForRestore`, that mirrors
  `AuthSessionBootstrapper.resolveDestination`'s existing c2e9f4 pattern for
  the identical ambiguity:

  1. Proactively call `_supabase.ensureFreshToken()` before the first select
     (non-fatal on failure — the select may still succeed on the existing
     token; failure is recorded via `restore_users_row_token_refresh_failed`
     so a refresh that fails EVERY restore stays visible).
  2. If the first select returns `null`, that is ambiguous (genuinely no row
     vs. RLS-filtered stale token) — log
     `restore_users_row_empty_retrying`, force a HARD
     `auth.refreshSession()` (not another proactive refresh — a token
     rejected for rotation/revocation/clock-skew needs the forced path,
     same escalation resolveDestination uses), and retry the select once.
  3. Log the retry's outcome distinguishably
     (`restore_users_row_retry_succeeded` /
     `restore_users_row_retry_still_empty`) so the next live occurrence is
     diagnosable from `client_errors` alone, rather than re-deriving this
     investigation.

  A genuinely absent `users` row is not an expected state for an
  authenticated restore (the row is upserted at first sign-in via
  `_ensureLocalUser` / `hydrateFromCloud`), so retrying once on `null`
  before accepting it can only recover a row that is really there — it
  cannot manufacture one.

  `_restoreUserProfile`'s outer try/catch and the merge logic
  (cloud-non-null-then-users-non-null layering, `full_name` wins when
  present) are UNCHANGED — only the network fetch feeding `usersRow` moved.
regression_test_planned: |
  test/contracts/restore_users_row_retry_test.dart — source-grep structural
  test, not a Postgres-touching behavioral one. This repo's own precedent
  for the IDENTICAL retry shape
  (test/contracts/auth_session_bootstrapper_test.dart, "AuthSessionBootstrapper
  source-grep contracts" group) already establishes why: "the heavier
  behavioral tests (Postgres-touching) would require a mocked Supabase
  client we don't have infra for." Asserts: `_restoreUserProfile` delegates
  to `_fetchUsersRowForRestore` (not a bare inline select); the helper calls
  `ensureFreshToken()`; it calls `select()` at least twice with
  `refreshSession()` strictly between them (so a single-shot no-retry
  pre-fix shape fails this on the call count alone); and all three original
  telemetry op_types are present. Extended in the same batch (B-pass
  findings 1 + 3) with two more groups: the C3 single-call null-injection
  branch does NOT call the retrying helper and logs
  `restore_users_row_null_via_singlecall` distinctly; the hard-refresh
  retry is wrapped in its own catch and logs
  `restore_users_row_retry_threw` on a refresh failure, isolated from the
  outer catch's generic `sync_service_if_14` label. Plan-review round 1
  (same batch) added an 8th: it demonstrated by mutation (`return retried;`
  → `return first;`, i.e. reintroducing the exact pre-fix defect) that none
  of the original 7 tests inspect the function's RETURN value — all 7
  stayed green on the reintroduced bug. The new test asserts `return
  retried;` appears (and `return first;` does NOT) after the second
  `select()` call; verified this fails on the same mutation before being
  accepted. Plan-review round 2 then found the MIRROR gap in that same
  test — it pinned what happens AFTER the retry, and nothing pinned the
  guard deciding whether the retry runs at all. Also demonstrated:
  neutering `if (first != null) return first;` to `if (false) return
  first;` left all 8 green, which would force a hard refresh + second
  round-trip on EVERY restore and discard an already-fetched `full_name`
  whenever that forced second call failed transiently. A 9th test pins the
  early return; verified to fail on that mutation before being accepted.
  9/9 green.

  The merge logic itself (which fields win, `usersRow` layered last) is
  UNCHANGED and already covered by the existing
  `test/sync/restore_completeness_test.dart` suite and
  `test/contracts/full_name_backfill_test.dart` — both re-run green, no
  regression there.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze clean on lib/core/services/sync/sync_profile.dart (0 new issues); test/contracts/restore_users_row_retry_test.dart 9/9 green (5 original + 2 for B-pass findings 1/3 + 1 for plan-review round-1 finding 1 + 1 for round-2 finding 2; both review-added tests independently mutation-proven to fail on the exact defect each pins)." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "test/sync/restore_completeness_test.dart (unchanged) still passes — the profile-map merge this fix feeds is untouched and still round-trips." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change; users.full_name/email columns are unchanged." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Live SQL confirmed users.full_name='Upendra' for upendraprasad19@gmail.com (created 2026-05-01) — the write side is correct, isolating this to the restore/read path." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this fix." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron reads or writes this path." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "RLS on users is the SUSPECTED trigger (stale-token filtering), not changed by this fix — the fix works around the ambiguity RLS + token timing produces, it does not alter any policy." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret read." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service in this path." }
  - { tier: 12, name: client_server_contract, status: fixed_in_this_batch, evidence: "Live client_errors query confirmed the exact failure shape (hasProfile=true, rawName=<null>) on 2 real accounts across 4 dates before this fix; the fix's own telemetry (restore_users_row_retry_succeeded/still_empty) makes the next occurrence's outcome directly observable." }
impact_analysis: |
  USER-VISIBLE: an authenticated restore whose `users` SELECT gets
  RLS-filtered by a stale/not-yet-attached post-redirect token now retries
  once behind a hard token refresh before accepting `full_name` as absent —
  recovering the name on Edit Profile and the Home greeting instead of
  silently showing blank/"USER".

  BLAST RADIUS platform (`lib/core/services/sync/**` per
  docs/blast_radius.yaml) — this is the restore path every returning web
  sign-in exercises, so the tier reflects reach, not the size of the change
  (a single retry addition to one already-isolated helper).

  COVERAGE BOUNDARY (B-pass finding 1, same batch): the retry+telemetry
  above is only reachable on the LEGACY fallback restore path — the FOUR
  call sites that call `_restoreUserProfile(userId)` with no
  `preFetchedUsers` argument, so it defaults to `_kNoInject`:
  sync_service.dart:1242/1302/1435 (used when the C3 single-call restore
  faults or the kill-switch is engaged), plus
  sync_profile.dart:880-884's `restoreUserProfileForSyncDomain` (called
  from `sync_domains/profile_sync_domain.dart:40` — currently inert,
  `SyncFlags.useDomainFor('profile')` defaults `FALSE`; the count was
  corrected from three to four by plan-review round 1, same batch — no
  functional gap, this call site already got the fix, only the citation
  was incomplete). The
  C3 single-call restore, tried FIRST for every restore
  (sync_service.dart:1417), injects `tables['users']` directly
  (`preFetchedUsers: row('users')`), bypassing `_fetchUsersRowForRestore`
  entirely — a real `null` there previously triggered no retry AND no
  telemetry at all. Verified this is not itself a live risk: the Edge
  Function behind C3 (`restore-user-snapshot/index.ts`) queries `users`
  through a SERVICE_ROLE client (RLS-immune — the specific ambiguity this
  fix targets cannot arise there) and its `q()` wrapper throws on any real
  Postgres error rather than returning an ambiguous null, so a null
  `tables['users']` there can only mean a genuinely-absent row, not the
  stale-token race. A retry would gain nothing. What WAS missing is
  observability: this batch adds a distinct `restore_users_row_null_via_
  singlecall` event on that branch so a future genuine anomaly on the
  primary restore path is no longer silent.

  RISK OF THE FIX: bounded. The retry can only ever RECOVER a row that
  genuinely exists (a truly absent `users` row is not a legitimate state for
  an authenticated restore — see proposed_fix) — it cannot fabricate
  `full_name`. Worst case on a persistent RLS/token failure: one extra
  network round-trip (a `refreshSession()` + a repeated SELECT) per restore,
  bounded to exactly one retry, no loop.

  NOT CONFIRMED, deliberately stated as a hypothesis rather than a fact:
  that the `users` SELECT specifically hits the RLS/stale-token shape (vs.
  some other silent-empty cause). The evidence is strong (identical failure
  signature to the already-diagnosed c2e9f4 case, same auth/redirect
  timing, all 6 occurrences on `platform: web` where token-freshness races
  are most likely) but this diagnose-doc could not directly observe a failed
  network request from outside the running app. The new telemetry
  (`restore_users_row_empty_retrying` / `_retry_succeeded` /
  `_retry_still_empty`) is what confirms or refutes the hypothesis on the
  next live occurrence — if `_retry_still_empty` fires, the cause is NOT
  token freshness and needs a fresh investigation.
related_bugs: [c2e9f4, 7ad0ce]
recurrence: |
  Same root-cause CLASS as diagnose c2e9f4 (`docs/diagnoses/2026-08-10-resolve-
  destination-failed-read-means-new-user-c2e9f4.md`): a Supabase query
  immediately post-redirect/sign-in can be RLS-filtered by a stale or
  not-yet-attached token, returning an EMPTY result — HTTP 200, `null` — with
  no exception, indistinguishable from "the row genuinely does not exist".
  c2e9f4 fixed this for `resolveDestination`'s `user_profile` SELECT; this is
  the SAME shape recurring in a DIFFERENT file's `users` SELECT, because the
  fix was never generalized past its original call site. Worth naming
  explicitly for whoever finds the NEXT occurrence: any Supabase read
  running in the first few seconds after a redirect/sign-in that returns
  `null`/empty with no matching local evidence of genuine absence is a
  candidate for this same ensureFreshToken + hard-refresh-retry pattern,
  not necessarily "the row doesn't exist".
---

# Edit Profile / Home greeting show blank name despite a correct `users.full_name`

See the YAML above for the full writer/reader map, the 12-tier check, and
the reasoning behind extracting a retrying helper rather than patching the
inline select in place.

## How this was found

Founder asked to investigate why a private-window sign-in showed a blank
Full Name field. Live `users` table query confirmed the cloud value was
correct (`full_name = "Upendra"`), which ruled out a write-side bug and
pointed at restore/read. The app's own `profile_full_name_empty_at_read`
telemetry probe (added under APK Test #12.8 for this exact symptom class)
had already captured the failure live — `rawName=<null>` — for this account
AND a second, unrelated account, across 4 separate dates. That telemetry is
what turned "plausible hypothesis" into "confirmed, currently-recurring,
multi-account bug" before a single line of fix code was written.

## Why a retrying helper, not a broader change

`AuthSessionBootstrapper.resolveDestination` had already solved the
identical ambiguity for a different query. Rather than inventing a new
pattern, this fix copies that one: proactive refresh, retry once behind a
hard refresh on an empty (not just a thrown) result, log the retry's
outcome distinguishably. The alternative — retrying inside
`_restoreUserProfile`'s existing outer catch, or widening its try/catch —
was rejected because that catch already has a DIFFERENT job (letting the
overall profile restore proceed even if the `users` fetch fails entirely),
and folding the retry into it would have made the "did we retry" and "did
the outer restore still proceed" concerns hard to reason about
independently.
