# OI-154 — a cleared `city` silently reverts on the next sign-in (narrow scope)

Status: **NOT ADOPTED — kept as the record (2026-09-29).** Both plan-review rounds returned NOT CONVERGED; founder deferred the fix as non-critical. Outcome and the options that replace this design live on OI-154 in `docs/audit/open_issues.md`. Do NOT implement v1 (unsound, see section 0); v2 needs the round-2 amendments listed on OI-154. · Branch: `oi-154-profile-clear-tombstone` · Tier: L (sync) · Execution mode: inline (§4.12.7)

## 0. Revision history

- v1 (2026-09-29): "send `''` whenever Hive holds `''`, no tombstone". REJECTED by round 1 (2 material findings, verified against code by the coordinator): `''` in Hive does NOT mean "deliberate clear" — `edit_profile_screen.dart:1864` writes `'city': _cityController.text.trim()` on EVERY save, so anyone who ever saved without a city already holds `city: ''`; and a clear that is killed or offline before the push still reverts.
- v2 (this): a LOCAL clear-intent marker (no cloud column, no migration). §5.

## 1. Decision record (founder, 2026-09-29)

- Scope is NARROW: only fields a user can actually clear through the UI. Verified: that is `city` alone.
- Body-fat "empty box does not clear" is a SEPARATE defect → its own OI, not in this batch.
- Priority P1 → P3 (§2).

## 2. Symptom and blast radius (verified 2026-09-29)

User empties City on Edit Profile and saves. The phone forgets it. Next launch/sign-in the city is back.

Only readers that could notice: `ai_snapshot_builder.dart:107-108` (coach context; already skips empty) and the Edit Profile seed (`edit_profile_screen.dart:213-214`). Nothing in `supabase/functions/` or migrations reads `user_profile.city`. No revenue, auth or data-loss path. P3.

Ruled OUT of this batch (each checked):
- `phone` — no client writer to `users.phone`; not in the `user_profile` payload.
- `avatar_url` / `banner_url` — set-only (`profile_provider.dart:136-140, 214-218`).
- `date_of_birth` / `wake_up_time` / `preferred_workout_time` — `?iso` omits the key when unset (`edit_profile_screen.dart:1866-1868`).
- `injuries` / `equipment_*` — `[]` already means "not answered".
- `body_fat_percent` — `if (_bodyFatController.text.isNotEmpty)` (`:1869`) never reaches sync when cleared. Separate OI.
- The other ~27 guarded fields in `sync_profile.dart:197-255` have no clear affordance. Recorded on OI-154 as a decision, not an oversight.

Live schema (`information_schema`, project `dedsavbjuwgarrhphgnl`, 2026-09-29): `user_profile.city` is `text`, nullable.

## 3. Writer / reader map (round-1-corrected citations)

Local writer of the clear: `edit_profile_screen.dart:1864` → `userProfileProvider.notifier.updateProfile` (`profile_provider.dart:44`) → `UserRepository.updateProfileFields` (`user_repository.dart:152`) → `ProfileWriteService.patchProfile` (`profile_write_service.dart:86`, a MERGE — keeps `''`), which fires `syncProfileNow`.

Cloud writer (the defect): `sync_profile.dart:230` `if (SyncService._hasValue(p['city']))`. `_hasValue('')` is false (`sync_service.dart:2718`), so the key is omitted from the plain `upsert(payload, onConflict: 'user_id')` (`_executeUserProfileUpsert`, `sync_service.dart:821`; legacy direct path `sync_profile.dart:~298`). `UserRepository._sanitize` (`user_repository.dart:1054`) also drops `''` but sits on the ONBOARDING path only.

Reader (re-hydrates): `_restoreUserProfile` merge, `sync_profile.dart:764-767` (cloud non-null wins per key), run on every launch via `restoreLightweightAlways` (`sync_service.dart:1520`, called `:1478`), so the revert is not sign-in-only.

Queue path: `_executeUserProfileMarker` (`sync_service.dart:757`) calls `_syncUserProfile(fromQueue: true)`, so it uses the SAME builder as the direct path (verified by round 1). It re-reads Hive at drain time and `SyncQueue.drain` (`splash_screen.dart:256`) runs unawaited, concurrently with restore.

Other `city` writers: onboarding stores city only when non-empty (`onboarding_provider.dart:487`); replay `sync_service.dart:1383` and `:884` go through `_sanitize` (`user_repository.dart:890`) and cannot emit `''`.

## 4. Prior art

- Diagnose `c3f2d8` (body_fat) fixed the same conflation as a one-off heal of a fabricated value, cloud FIRST then local. Unaffected.
- OI-154's refuted designs: (1) "server null is authoritative" → data loss (`sync_profile.dart:755-757`); (2) per-field sentinel across date/numeric/text[]. This design keeps cloud null NON-authoritative and is scoped to one text field.
- `docs/diagnoses/INDEX.md` grep for cleared/tombstone/revert: no prior `city` instance. Related class only via `c3f2d8`.

## 5. Design v2 — local clear-intent marker (a tombstone that never leaves the device)

State: `userBox['city_clear_pending'] == true`. `userBox` is user-scoped (`wrapUserScopedBox`, `hive_service.dart:234`), so an account swap drops it. Kept OUT of the `profile` map so the restore merge and the payload whitelist never see it.

1. SET — Edit Profile save only, when the city stored BEFORE the save is non-empty AND the new trimmed value is empty. A save that leaves an already-empty city empty sets nothing. Persisted in Hive BEFORE the push, so it survives kill/offline/restart.
2. CLEAR the marker when: (a) a later Edit Profile save stores a non-empty city; (b) a push whose payload carried the clear succeeds (direct path returns normally, or the queue executor returns ok).
3. Builder (`sync_profile.dart:230`): marker pending → include `'city': ''` in the payload; marker absent → the existing `_hasValue` rule, UNCHANGED (so a legacy `''` in Hive is never pushed — this is what defuses finding 1).
4. Restore merge (`sync_profile.dart:764-767`): marker pending → drop `city` from the cloud entries before merging, so a stale cloud `Pune` cannot re-hydrate over the local clear (defuses finding 2, including the marker-drain-vs-restore race). Marker absent → unchanged.
5. Cloud value on clear is `''`, not null: a null is skipped by every other device's restore and its next push would send its own `Pune` back, reverting the clear everywhere. A cloud `''` propagates the clear to other devices' restore (non-null `''` wins). Readers already treat `''` as "no city" (coach builder `isNotEmpty`; seed `?? ''`).
6. Kill switch `SyncService.kDisableProfileCityClearKey = 'disable_profile_city_clear'`, read as `_hive.configBox.get(key) == true` (the `kDisableProfileTargetRecomputeKey` pattern, `sync_service.dart:129`). Set → steps 1, 3, 4 all no-op (verbatim old behavior); a read that throws → old behavior (fail to legacy). Default: not set (feature ON).

No migration, no schema change, no Edge Function change, no live apply.

Stated residuals (not fixed, not hidden):
- Reinstall or Hive wipe BEFORE the clear has ever reached the cloud loses the marker; the city returns. Same as every unsynced local edit in this app.
- Device B holding `Pune` in Hive that PUSHES before it restores can write `Pune` back over A's cloud `''` (last-writer-wins). This is the existing profile-wide semantic, not introduced here.
- A permanently dead-lettered push leaves the marker set; harmless (city stays `''` locally, restore skips cloud city) and cleared by the next successful push or non-empty save.

## 6. Risks the reviewers must attack (round 2)

1. Every code path that could SET or fail to CLEAR the marker; the pre-save "stored city" read races with a concurrent restore.
2. Restore-merge subtraction: is `city` the only key affected; does anything downstream (`recomputeDerivedTargets`, the completeness check) read `city` from the merged map.
3. Success detection: does the direct and queued path expose a reliable "this payload's clear landed" point; can the marker be cleared by a push that did NOT include `city: ''`.
4. New Hive key `city_clear_pending`: any Hive-key allow-list, `user_scoped_hive_keys` SoT concept, or gate (`check_*`) that needs it registered; is it wiped by `clearAllData`.
5. SoT registry: `sync_profile.dart` `line_range` citations at `docs/sot_registry.yaml` (`145-266`, `679-818`) will shift; `user_full_name` (`:4473`) is the closest concept — decide whether `city` needs its own.
6. Is `''` (not null) to the cloud right; construct a failing sequence.

## 7. Test plan (rule 21 + mutate-and-run) — behavioral, real builder/restore/Edit-save seams

1. Clear (stored `Pune` → `''`): marker set; payload carries `city: ''`; success clears marker.
2. Legacy stale-`''` (finding 1): Hive `city:''`, NO marker, cloud `Pune`, unrelated save/weekly sync → payload OMITS city; restore leaves Hive `Pune`.
3. Kill-before-push (finding 2): marker set, restore runs FIRST with cloud `Pune` → Hive stays `''`; push then sends `''`.
4. Queue-drain vs restore race ordering; offline (push fails) keeps marker, later success clears it.
5. Later non-empty save clears marker; a `''`-over-`''` save sets none.
6. Second-device propagation: cloud `''` restore over Hive `Pune` → `''`.
7. Account swap drops the marker. Kill switch ON = byte-identical old payload and old restore.

Mutations to run and report in the diagnose-doc, each must redden for a semantic reason (not a compile error), fixture checked against how the real workflow produces state: builder ignores marker (→ old omit) ; builder sends `''` from Hive `''` without marker (must redden test 2); restore subtraction removed (test 3); marker set unconditionally on any empty save (test 2/5); marker never cleared (test 5); flag inverted.

## 8. Files and process

Product: `edit_profile_screen.dart`, `sync_profile.dart`, `sync_service.dart` (constant). Also `docs/sot_registry.yaml` (line_range shift + clear semantic), `docs/audit/open_issues.md` (OI-154: corrected citations, narrow decision, status), new body-fat OI via `sh scripts/mint_oi.sh`, tests under `test/contracts/` (`profile_city_clear_writer_to_reader_test.dart`), full-template diagnose-doc (recurrence class via `c3f2d8`).

Tier L (sync). Two context-blind plan-review rounds → `docs/plan-reviews/oi-154-profile-clear-tombstone.md` (`review_rounds: ≥2`, `ground_truth_verified: true`, `bpass: accepted`). Full gate loop before any review round that has a diff. No push, merge or build until asked.
