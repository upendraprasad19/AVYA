---
bug_id: b3c9d4
date: 2026-09-02
batch: profile-stale-restore
status: fixed
blast_radius: platform
symptom: |
  Founder observed (web, app.icanbefitter.com, signed-in returning session):
  the Home header rendered "UPENDRA" while the Profile tab rendered "User"
  and Edit Profile's Full Name field was BLANK — same account, same app
  session, same Hive key. Every other Edit Profile field (email, gender,
  1988-06-30 DOB, 7:00 AM wake time) rendered correctly, so only `full_name`
  appeared to be missing.

  Live `client_errors` (queried 2026-09-02) shows the app's own probe fired
  THREE times in the same session, and critically it fired for HOME too:

    19:23:27 IST  reader=user_first_name  rawName=<null> hasProfile=true
    19:24:14 IST  reader=edit_profile     rawName=<null>
    19:26:41 IST  reader=edit_profile     rawName=<null>

  The restore timeline for that same session settles the race directly
  (same query, op_type like 'restore%'):

    19:23:23.492  restore_started
    19:23:27.267  profile_full_name_empty_at_read reader=user_first_name
    19:23:31.194  restore_step_done step=A ms=344 path=singlecall
    19:23:31.722  restore_step_done step=C ms=119 path=singlecall

  Home read the name 3.8 SECONDS BEFORE the restore finished. That is the
  bug, timestamped: not a failed read, an early one.

  So Home ALSO read null and rendered "USER" at 19:23; it displayed
  "UPENDRA" by screenshot time only because it self-heals (see root cause).
  Profile has no such heal. The divergence is the bug — not the name.

  ROOT CAUSE — a stale cached provider, not a failed read:

  1. `restoring_screen.dart:304` computes `isReturning` from
     `localProfile['primary_goal'] != null`. The founder is a returning user,
     so `:307` takes the BACKGROUND-restore branch and `:326` navigates to
     /home IMMEDIATELY with the cloud restore still in flight.
  2. Home paints. `home_screen.dart:309` does `ref.watch(userProfileProvider)`
     (it needs `avatar_url`), which INSTANTIATES `UserProfileNotifier`.
     `profile_provider.dart:39` reads Hive ONCE and caches the result. At that
     instant the local profile map holds `primary_goal`, `gender`,
     `date_of_birth` and the wake time — but not `full_name`, which lives on
     the `users` table, not `user_profile`.
  3. The restore finishes; `heal_after_restore.dart:74` calls
     `bumpRestoreCompleted()` (`sync_service.dart:1443`).
  4. `restoreCompletedTick` had exactly ONE UI listener —
     `home_screen.dart:71`. Its handler `_onRestoreTick` (`:74`) calls
     `invalidateOnRetry` (`:141`), which invalidated 15 providers INCLUDING
     `userFirstNameProvider`/`userInitialProvider` but NOT
     `userProfileProvider` (verified: grep count 0 over that method).
  5. Home therefore recovered; `userProfileProvider` kept the pre-restore map
     for the rest of the app session.
  6. Profile tab (`profile_content.dart:11`) watches that same already-built
     notifier and got the stale map -> `'User'`. The Profile screen has NO
     `didChangeDependencies` override, so re-entering the tab never re-reads;
     its `invalidateOnRetry` (`profile/screen.dart:111`) DOES list
     `userProfileProvider` but only runs on an explicit error-retry tap.
  7. Edit Profile (`edit_profile_screen.dart:117`, `ref.read`) got the same
     stale map -> blank field.

  WHY THE PRIOR FIX DID NOT CATCH IT — diagnose d4e9a2 (2026-08-30) shipped
  a token-refresh retry for this exact symptom. Verified this session that
  the fix is BOTH on main AND deployed: the live 24,101,793-byte
  `main.dart.js` at app.icanbefitter.com contains all four post-fix strings
  (`restore_users_row_empty_retrying`, `restore_users_row_retry_succeeded`,
  `restore_users_row_null_via_singlecall`, `_fetchUsersRowForRestore`). Yet
  `client_errors` holds ZERO `restore_users_row_*` rows. The retry never
  engaged, because nothing was failing — the read was merely EARLY.

  Stated precisely, because the short version is weaker than it looks
  (round-1 review finding 3): `restore_users_row_*` is emitted only by
  `_fetchUsersRowForRestore`, which lives on the LEGACY fallback path. The
  founder's restore ran `path=singlecall` (C3) — see the timeline above —
  which injects `tables['users']` directly and bypasses that helper
  entirely, so its silence alone proves nothing. What closes the argument is
  that `restore_users_row_null_via_singlecall`, the probe d4e9a2 added to
  the C3 branch for exactly this, ALSO never fired: the `users` row was
  fetched successfully. Nothing failed anywhere; the readers were early.

  d4e9a2 explicitly examined `_goHome` and ruled the race out. That ruling
  was correct for the case it examined (a private window, where
  `isReturning` is FALSE and the branch awaits the restore) and was
  generalised to a case with the OPPOSITE branch value. Its own evidence
  table contradicted it: every cited row says `hasProfile=true`, which can
  only mean the local profile map already existed — i.e. `isReturning` was
  TRUE and the early-navigation branch was taken.
concept: user_full_name
sot_registry_entry: user_full_name
writers:
  - { file: lib/core/services/sync/sync_profile.dart, method_or_widget: "_restoreUserProfile — merges the users row into the Hive profile map (UNCHANGED by this fix; it is the late writer the readers were racing)", line: 764 }
  - { file: lib/features/auth/screens/restoring/heal_after_restore.dart, method_or_widget: "_healAfterRestoreInBackground — bumpRestoreCompleted() signals the restore landed (UNCHANGED)", line: 74 }
readers:
  - { file: lib/features/profile/providers/profile_provider.dart, method_or_widget: "UserProfileNotifier.build — the ONE Hive read; now the single source the three name providers derive from", line: 39 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: "UserGreetingNotifier.build — was an independent UserRepository.getProfile() read, now derives from userProfileProvider", line: 140 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: "UserFirstNameNotifier.build — was an independent read, now derived; hasProfile probe field now reports profile.isNotEmpty", line: 191 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: "UserInitialNotifier.build — was an independent read, now derived", line: 227 }
  - { file: lib/features/profile/providers/profile_completeness_provider.dart, method_or_widget: "profileCompletenessProvider — was a FOURTH independent Hive read in no invalidateOnRetry list; now derived. full_name is 1 of 10 kTier1Fields, so a missing name renders 94% instead of 100% — the exact figure in the founder's screenshot", line: 36 }
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: "initState — ref.listenManual re-seeds _nameController when the profile heals, only while the field still holds what we seeded", line: 148 }
  - { file: lib/features/profile/screens/profile/profile_content.dart, method_or_widget: "_buildProfileContent — watches userProfileProvider (the stale reader in the report)", line: 11 }
  - { file: lib/features/profile/screens/edit_profile_screen.dart, method_or_widget: "initState — ref.read(userProfileProvider) + the edit_profile probe", line: 122 }
  - { file: lib/shared/mixins/hive_tab_scaffold.dart, method_or_widget: "HiveTabScaffoldMixin.initState/dispose — registers every tab screen as a restoreCompletedTick listener so a completed background restore refreshes ALL tabs, not just Home", line: 142 }
hive_key_prefix: "n/a — single key within userBox['profile'] map, not a prefixed series"
hive_key_formula: "userBox['profile']['full_name']"
sync_methods: [syncProfileNow]
restore_methods: [_restoreUserProfile, _healAfterRestoreInBackground]
cloud_table: users
cloud_columns: [full_name, email]
contract_test_path: test/contracts/profile_provider_single_source_test.dart
ist_handling: "n/a — no date keys, cloud date columns, or counter resets touched by this fix"
provider_invalidations:
  - userProfileProvider
  - profileCompletenessProvider
  - userFirstNameProvider
  - userInitialProvider
  - userGreetingProvider
telemetry_op_types:
  success: []
  failure: [profile_full_name_empty_at_read]
cross_account_guard: |
  Inherited, not re-implemented, and STRENGTHENED by consolidation. Every
  read still lands on `UserRepository.instance.getProfile()` ->
  `HiveService.instance.userBox`, which is wrapped by `wrapUserScopedBox`.
  This fix REMOVES three independent call sites of that read and routes them
  through the single `UserProfileNotifier`, so there are now fewer — not
  more — paths that could observe a box mid-ownership-swap. The
  `ref.watch(authUserIdTokenProvider)` guard (c4055a) is retained explicitly
  on all four providers rather than relied on transitively, so each keeps its
  own auth-change rebuild even if the source provider's guard is ever changed.
forbidden_patterns_checked:
  - "No raw Hive.box( introduced — the change REMOVES three direct UserRepository.getProfile() reads and adds none."
  - "No new .select() or cloud column reference — check_schema_column_refs.dart is unaffected; no network code is touched."
  - "No setState for shared state — the tick handler calls invalidateOnRetry(ref), matching home_screen._onRestoreTick's existing shape, and deliberately NOT retry(), which would flash a skeleton on every tab."
  - "The AI Coach tab is intentionally NOT covered: it does not use HiveTabScaffoldMixin (documented allow-list in scripts/check_tab_screen_uses_hive_scaffold.dart, different mount shape — chat hydration, no skeleton/retry loop). Stated as a known boundary rather than silently omitted."
proposed_fix: |
  Two changes, one principle: ONE source, ONE invalidation.

  1. SINGLE SOURCE (lib/features/home/providers/home_provider.dart) — the
     three name providers stop reading Hive independently and derive from
     `userProfileProvider`:

       - final profile = UserRepository.instance.getProfile();
       + final profile = ref.watch(userProfileProvider);

     Home and Profile then read the SAME notifier instance, so they cannot
     hold different answers about `full_name` — the observed divergence
     becomes structurally impossible rather than merely fixed. The
     null-vs-empty-map delta is faithful: `getProfile()` returns null for an
     absent map, `userProfileProvider` maps that to `{}`, so the probe's
     `hasProfile=` field now reports `profile.isNotEmpty`.
     No new dependency is added — `home_provider.dart:23` already imports
     `profile_provider.dart`.

  2. SINGLE INVALIDATION (lib/shared/mixins/hive_tab_scaffold.dart) — the
     `restoreCompletedTick` listener moves OUT of home_screen and INTO
     HiveTabScaffoldMixin's initState/dispose. All four tab screens already
     mix it in and already override `invalidateOnRetry`, so Nutrition, Train
     and Profile gain a working post-restore refresh they never had, and no
     future tab can be forgotten — the registration is structural rather than
     a per-screen thing to remember. `userProfileProvider` is added to
     home_screen's `invalidateOnRetry` (which also fixes a stale `avatar_url`
     on Home, the same mechanism on a different field).

  WHY ONLY THE THREE NAME PROVIDERS ARE DERIVED, since the obvious question
  is why not every profile reader: `nutritionSummaryProvider`
  (home_provider.dart:561) and `macroTargetsProvider`
  (nutrition_provider.dart:390) also read the profile map independently, and
  both were checked. Neither is left exposed — both are already listed in a
  tab's `invalidateOnRetry` (home_screen and nutrition_screen respectively),
  so change 2 refreshes them. Deriving them as well would couple macro
  recomputation to EVERY profile field change — an avatar upload would
  recompute the day's nutrition summary — which is a real performance
  regression for no correctness gain. The three name providers are pure
  string operations, so coupling them is free. The boundary is cost, not
  scope.

  ⚠ CORRECTED — an earlier draft of this section ended "nothing exposed is
  left unfixed", and round-1 review proved that false. `profileCompleteness
  Provider` (profile_completeness_provider.dart:38) was a FOURTH independent
  `UserRepository.instance.getProfile()` reader — a plain `Provider` that
  cached identically and sat in NO invalidateOnRetry list, so nothing could
  ever heal it. It renders the completeness bar on the SAME Profile screen as
  the wrong name, and because `full_name` is 1 of 10 kTier1Fields weighted
  60%, a missing name costs exactly 6 points — which is why the founder's
  screenshot reads "PROFILE · 94% COMPLETE". It is derived now too, pinned by
  a test asserting that precise 6-point delta. The lesson is the one this doc
  already states about hand-maintained lists: the author enumerated the
  readers he remembered, and an enumeration from memory is not a search.
  `grep -rn "getProfile()" lib/` is.

  3. TWO MORE READERS, added after review: `profileCompletenessProvider`
     derives from the same source; and `edit_profile_screen.dart`'s
     `initState` gains a `ref.listenManual` that re-seeds `_nameController`
     when the profile heals (round-1 finding 5). A TextEditingController
     seeded once cannot react, so a restore landing while Edit Profile is
     OPEN left the field blank — and `_save()` hard-refuses an empty name,
     locking the user out of saving ANY profile edit until they navigated
     away and back. The re-seed fires only while the field still holds
     exactly what we seeded, so an in-progress edit is never clobbered.

  4. BACKGROUND-RESTORE SEAM (B-pass finding 1): the mixin calls a new
     `invalidateOnBackgroundRestore(ref)`, defaulting to `invalidateOnRetry`.
     Nutrition overrides it to EXCLUDE `aiBreakdownProvider`, because
     `ai_mode_body.dart:41` reads that provider's non-null -> null transition
     as "the user committed or cancelled" and pops the Log Food sheet. Right
     for a retry TAP, false for a restore tick — which would have silently
     discarded a just-generated AI food analysis.

  REJECTED, deliberately: making the Hive read itself reactive (box.watch /
  typed AsyncValue absence) is the stronger industry answer and would dissolve
  this class entirely, but it touches every profile reader and per CLAUDE.md
  section 4.11 needs its detection gate landing first. Not folded in here.
regression_test_planned: |
  test/contracts/profile_provider_single_source_test.dart — two groups.

  BEHAVIORAL (the real protection): open Hive, write a profile map WITHOUT
  `full_name` (the pre-restore shape), build a ProviderContainer, read
  userFirstNameProvider (asserting the 'USER' fallback), then write the map
  WITH `full_name` (simulating the restore landing), invalidate ONLY
  `userProfileProvider`, and assert `userFirstNameProvider` now returns
  'UPENDRA'. Pre-fix this FAILS: the name provider held its own Hive snapshot
  and invalidating the source could not reach it. This is the exact
  Home/Profile divergence, reproduced.

  SOURCE-GREP (structural): the three name notifiers contain
  `ref.watch(userProfileProvider)` and NOT `UserRepository.instance
  .getProfile()`; HiveTabScaffoldMixin registers and removes a
  `restoreCompletedTick` listener; home_screen's invalidateOnRetry lists
  `userProfileProvider`.

  MUTATION (rule 21 — mandatory, this batch WROTE these tests): revert each
  derived provider to `UserRepository.instance.getProfile()` in place (the
  exact pre-fix line, not a convenient deletion) and confirm the behavioral
  test reddens; remove the mixin's listener registration and confirm the
  mixin test reddens. Each mutation is confirmed APPLIED via grep -c before
  the run, so a regex that silently matched nothing cannot make a green run
  read as proof.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze over lib/ (NOT per-file — screen.dart declares parts; see CLAUDE.md section 4.9); targeted + full suite green." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "The behavioral test writes and re-writes userBox['profile'] and asserts the derived provider follows; no Hive schema or key change." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change; this is a client-side provider-graph fix." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "Live query 2026-09-02 confirms users.full_name='Upendra' for upendraprasad19@gmail.com — the write side and the cloud value were never wrong." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron reads or writes this path." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy change. RLS was d4e9a2's hypothesis and is NOT implicated here — the reads were succeeding, just early." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No storage object involved (avatar_url is a string field, not a storage call in this path)." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret read." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service in this path." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Deployed-bundle grep proved d4e9a2's code IS live while its telemetry stayed silent — which is what isolated this to a client-side staleness bug rather than a restore-read failure." }
impact_analysis: |
  USER-VISIBLE: the Profile tab and Edit Profile now show the correct name
  once the background restore lands, instead of holding a pre-restore
  snapshot for the whole app session. Home's avatar (`avatar_url`, same
  mechanism) also stops being stale. Nutrition and Train refresh after a
  background restore for the first time.

  SECONDARY, now unblocked: while the name field is blank, `_save()`
  (`edit_profile_screen.dart:1700`) early-returns with "Please enter your
  name." — so the founder could not save ANY profile edit. Verified there is
  no silent data-loss path: the guard blocks the write, it does not persist
  an empty name over the good cloud value.

  BLAST RADIUS platform, for a reason worth stating because two different
  numbers are both correct here. `scripts/blast_radius_from_diff.dart`
  classified the FIRST version of this diff `feature`, because
  `lib/shared/**` is feature-tier by default — so a change to a mixin that 4
  of the 5 tab screens inherit their lifecycle from would have cleared zero
  review gate. That is the same hole the pro_phase_advance.dart rule was
  written to close, so this batch pins `hive_tab_scaffold.dart` to `account`
  in docs/blast_radius.yaml (file-scoped, following that precedent
  verbatim — the directory holds exactly this one file). The CODE's reach is
  therefore account. The DIFF then classifies `platform` because editing
  docs/blast_radius.yaml is itself platform-tier, which is correct and is the
  stricter of the two: it means the full suite and a B-pass run on this
  batch. An earlier draft of this doc asserted platform with no basis at
  all; it happens to be the right answer for the wrong reason, so the
  reasoning is recorded rather than the number alone. Superseded text: the
  registry reserves platform for cross-cutting infrastructure (EF _shared,
  plan_engine), and `scripts/blast_radius_from_diff.dart` classified this diff
  `feature` because `lib/shared/**` is feature-tier by default. Both were
  wrong for this file, in opposite directions. `hive_tab_scaffold.dart` is
  mixed into 4 of the 5 tab screens and owns their lifecycle, so this batch
  ALSO pins it `account` in docs/blast_radius.yaml — file-scoped, following
  the pro_phase_advance.dart precedent. Without that pin a diff touching only
  this mixin would clear zero review gate while changing every tab's refresh
  behaviour, which is precisely the diff this batch wrote.

  RISK OF THE FIX: the new listener makes four tabs invalidate their declared
  provider sets once per completed background restore, where previously only
  Home did. It fires at most once per restore (a ValueNotifier bump), calls
  `invalidateOnRetry(ref)` rather than `retry()` so no skeleton flashes, and
  is `mounted`-guarded and removed in dispose. The providers invalidated are
  each screen's OWN declared set. ⚠ The original wording here — "no provider
  is being invalidated that was not already designed to be" — was WRONG, and
  B-pass finding 1 produced the counter-example: designed for a user-tapped
  retry is not the same as safe for an automatic trigger. That is why the
  background path is now a separate overridable hook rather than the retry
  set itself.

  NOT CLOSED BY THIS FIX, stated explicitly rather than implied: WHY the
  local Hive profile map lacks `full_name` at first paint on a returning
  session. The restore supplies it every session (which is why Home heals),
  so the readers race a late writer; this fix makes every reader observe that
  writer. If the map should have carried `full_name` from the previous
  session's restore, that is a separate durability question about what
  persists between web sessions, and the probe now discriminates it: a
  `profile_full_name_empty_at_read` that fires AFTER this ships means the
  value never landed at all, rather than landed-but-unread.
related_bugs: [d4e9a2, c2e9f4, b2ac5d]
recurrence: |
  Third occurrence of the same SYMPTOM (b2ac5d 2026-05-08 restore missed
  users.full_name; d4e9a2 2026-08-30 token-refresh retry) and the first to
  identify the mechanism as reader staleness rather than a failed read.

  The recurrence class this doc actually closes is broader and worth naming
  for whoever hits the next one: INVALIDATION KEYED ON A HAND-MAINTAINED LIST
  OF CONSUMERS DRIFTS. `home_screen.invalidateOnRetry` was a hand-written list
  of 15 providers; the one it omitted is the one four screens depend on.
  Four providers independently re-reading the same Hive key is what made an
  omission expressible as a visible divergence. The fix is not "remember to
  add it to the list" — it is to make the list shorter than the number of
  ways to get it wrong.

  Second, methodological, and the reason d4e9a2 shipped the wrong fix: a
  symptom probe that cannot DISCRIMINATE causes must not be read as evidence
  for one. `rawName=<null> hasProfile=true` is identical whether the users
  SELECT was RLS-filtered or the read simply beat the restore. And the
  ABSENCE of a new fix's telemetry is a signal, not silence — d4e9a2 planned
  for its retry firing and failing, never for it never running, which is
  exactly what happened for three days.
---

# Profile tab serves a pre-restore profile map for the whole session

See the YAML above for the writer/reader map, the 12-tier check, and the
reasoning. Short version: Home and Profile read the same Hive key through
DIFFERENT providers, only Home was wired to the restore-completed signal, so
Home healed and Profile did not.

## How this was found

Founder reported the name showing on Home but not Profile. The decisive
evidence was live `client_errors`: Home's own probe had fired `rawName=<null>`
three minutes before the screenshot that shows Home rendering the name
correctly. That single row reframed the bug from "Profile can't read the name"
to "both read null, only one recovered", which is a staleness question, not a
read-failure question.

The second decisive check was fetching the DEPLOYED web bundle and grepping it
for d4e9a2's telemetry strings. All four were present — so the previous fix was
live, and its complete silence in `client_errors` proved the diagnosed code
path was never on the execution path at all.

## Why the mixin, not three more listeners

Adding `restoreCompletedTick.addListener` to Nutrition, Train and Profile would
have fixed the same three tabs. It would also have been a fourth hand-maintained
list, in a bug whose root cause is a hand-maintained list. `HiveTabScaffoldMixin`
already owns `initState` and already declares `invalidateOnRetry` as the "refresh
this screen's providers" contract, so registration there is structural: a future
tab screen gets it by mixing in, with nothing to remember.
