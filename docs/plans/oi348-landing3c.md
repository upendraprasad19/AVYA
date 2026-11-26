# OI-348 Landing 3c — free progress-photo upload (1 per IST week), PRO unlimited

Tier **L** (schema + Storage trigger + subscription-adjacent gate + root CLAUDE.md row). Execution mode: **inline** (one worktree `oi348-landing3c`, one PR). Blast radius at least `account`. Full ×2 plan review, B-pass, record `docs/plan-reviews/oi348-landing3c.md`.

## 0. Founder calls (locked 2026-11-26)

| # | Call |
|---|---|
| Q1 | Free users may upload **1 progress photo per IST week** (Mon 00:00 to Sun 23:59 IST). The SERVER counts, so the app cannot be bypassed. |
| Q2 | Resize so the long side is **2048 px**, good JPEG quality (about 0.5 to 1.5 MB); light, because photos may later feed video or AI. |
| Q3 | PRO has **no upload cap**. Viewing is free for everyone. |
| Q4 | A lapsed PRO is **treated as free**: keeps and sees every photo; new uploads follow the free cap. |

**Decision taken here (stated, founder may overrule):** the free cap counts photos **held** in an IST week, not uploads ever made. Deleting this week's photo opens the slot again (a retake of a bad shot). Storage held stays at most 1 object per week for a free user.

## 1. Ground truth (read 2026-11-26, live `dedsavbjuwgarrhphgnl` + tree at main `8cd4556f`)

- E1 (live) Storage INSERT policy `progress_photos_insert_own` (TO authenticated): own folder AND active unexpired subscription (migration 154). SELECT and DELETE: own folder. **No UPDATE policy** for the bucket.
- E2 (live) `public.progress_photos`: `id, user_id, storage_path, body_area, taken_at (NOT NULL, client-set), weight_kg_at_time, notes, created_at (default now(), nullable)`. Own-row policies for SELECT / INSERT / UPDATE / DELETE (`022_progress_photos.sql:35-42`). Trigger `trg_progress_photo_pro` BEFORE INSERT -> `enforce_progress_photo_pro()` (PRO only, P0001 `progress_photo_pro_required`).
- E3 (live) Bucket `progress-photos`: private, 8 MiB per file, jpeg/png/webp. 1 row, 1 object today.
- E4 (live) `postgres` holds TRIGGER on `storage.objects` (owner `supabase_storage_admin`), `rolbypassrls = true`; existing triggers there: `protect_objects_delete`, `update_objects_updated_at`. PG 17.6.
- E5 Client screen `progress_photos_screen.dart:112-190` decides `granted / readOnly / denied`; a free user with no photos gets `ProLockedOverlay` and no Add (`:375-377`); `_onAddPhoto` (`:408-429`) sends a free user to the paywall; `_capture` asks the body area (`:194`) before `capture`.
- E6 `progress_photo_repository.dart` (main): client 5/day cap (`:170-191`); pick 3000/95; `upload(storagePath, File(xfile.path))` (`:206-218`) — `dart:io File` cannot open a web pick's blob URL, so web uploads fail today; a failed row insert leaves an orphan; `cleanupOrphanedStorage` (`:343-391`) has no caller and compares ALL objects with ALL rows.
- E7 `progress_photos` in `allProFeatures` (`subscription_service.dart:124`) and `_highValueFeatures` (`:695`).
- E8 Storage checks the INSERT policy when a signed upload URL is minted, not when the upload through it lands (unverifiable from repo; the reason for a trigger rather than a policy conjunct).
- E9 Postgres applies RLS `WITH CHECK` after BEFORE ROW triggers (documented Postgres behaviour).
- E10 ADR-0022: an Android build in `PurchaseMode.none` sells nothing; `purchase_literal_inventory_test.dart` counts upgrade words per file (`progress_photos_screen.dart: 1` at `:61`); the screen's three paywall doors are rows 9-11 of `docs/plans/2026-11-20-android-play-billing.md` §5.2.
- E11 OI-315 (open): 5/day cap client-only; sweeper has no caller. OI-316 (open): no recurring check for a dashboard edit of the bucket's policies.

## 2. Server (one migration, drafted at `test/sql/progress_photos_free_weekly_cap_draft.sql`)

Number minted only after the founder's go (`sh scripts/mint_migration.sh --stub progress_photos_free_weekly_cap`; migration-190 draft rule). One `DO` block, `lock_timeout 5s`, four-tag header, inline rollback restoring 154's objects. The draft's header is the full design; summary:

1. `public.progress_photo_week_start(timestamptz)`: Monday 00:00 IST as an instant (`date_trunc('week', p AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata'`), STABLE, pinned path, EXECUTE revoked from PUBLIC / anon / authenticated.
2. **Storage door** `enforce_progress_photo_object_cap()` (SECURITY DEFINER, `search_path = public, pg_temp`, every call schema-qualified) + `trg_progress_photo_object_cap BEFORE INSERT ON storage.objects ... WHEN (NEW.bucket_id = 'progress-photos')`:
   - owner = first folder as uuid; NULL or not a uuid -> RAISE 42501 (fail closed, also for a root-level name);
   - JWT role `anon` or `authenticated` (`auth.role()`, claim-based) and owner IS DISTINCT FROM `auth.uid()` -> `RETURN NEW` at once (RLS refuses next: anon has no INSERT policy, authenticated's is own-folder; no lock on, and no answer about, the other user's week) — round 1 #6, round 2 #1 (a `service_role` JWT carrying another sub, or a NULL-role direct insert, is capped by the folder's OWNER);
   - PRO -> pass; else advisory xact lock on the owner, count by `name LIKE owner || '/%'` (uses the `(bucket_id, name)` index — round 1 #9) and `created_at >= week start`; any -> RAISE 42501 `progress_photo_pro_required`.
3. Storage INSERT policy back to own-folder only.
4. **Row door** `enforce_progress_photo_pro()` (now SECURITY DEFINER; trigger kept, NOT re-created — the 154 tripwire's `ruleDefinitionViolations` stays at one file): `NEW.created_at :=` the created_at of the caller's own object at `NEW.storage_path`, else `now()`, so a photo's week is its OBJECT's week at both doors (Sunday 23:59:50 upload with a Monday row stays Sunday's — round 1 #4); PRO -> pass; else lock, count rows in that IST week; any -> P0001 `progress_photo_pro_required` (the literal shipped +50 clients read).
5. **UPDATE guard** `keep_progress_photo_created_at()` + `trg_progress_photo_created_at_keep BEFORE UPDATE`: `NEW.created_at := OLD.created_at` (the owner UPDATE policy would otherwise let a free user backdate this week's row — round 1 #3).

**Live verify** `test/sql/progress_photos_free_weekly_cap_live_verify.sql` (one always-aborting DO block, the role-window technique of `progress_photos_pro_insert_rule_live_verify.sql`): free first object allowed / second refused (SQLSTATE 42501 + literal); last week's object does not count; PRO many; lapsed = free; non-uuid and root-level name refused; another user's folder -> RLS message, not the trigger's; chat-media insert by a capped free user untouched; row door matrix incl. a row whose object is last week's (allowed), `created_at` taken from the object, UPDATE of `created_at` ignored; deleting... (object DELETE is not possible from SQL: `protect_objects_delete`; covered by the client test and the founder's web check); catalog: `prosecdef`, `proconfig`, `has_function_privilege` false for anon / authenticated on all four functions, policy text, both triggers' definitions incl. `WHEN`.

**Rehearsal (no docker on this machine):** the draft runs once inside an always-aborting DO block on live (`RAISE` at the end, nothing persists, same technique as migration 152's prod dry run), off-peak, with its own founder go; it proves the DDL is accepted (incl. the supautils hooks and CREATE TRIGGER on `storage.objects`) and runs the verify cases against the would-be state in the same transaction.

**154's live verify** (`test/sql/progress_photos_pro_insert_rule_live_verify.sql`) becomes historical: a header line says it describes the pre-Landing-3c rule and is superseded by the new verify; its pin test keeps pinning its text (it is the record of what 154 proved).

## 3. Client

### 3.1 Repository (`progress_photo_repository.dart`)
- 5/day cap deleted (Q3). `PhotoQuotaException(weeklyCap, message)` is the free weekly cap.
- Pure helpers: `progressPhotoFreeWeeklyCap = 1`; `progressPhotoOrphanMinAge = 60 min` (covers another device's in-flight capture, a slow upload, and a fast device clock — round 1 #5); `progressPhotoWeekStartUtc(now)` built on `istDateOf` / `istMidnightUtc` (round 1 #12); `parseStorageInstant` (an offset-less value read as UTC); `progressPhotosHeldThisWeek` / `progressPhotoFreeSlotOpen` (an unreadable `created_at` is not counted: courtesy check only); `progressPhotoOrphanCandidates`; `progressPhotoContentType(name, mimeType)` (picker MIME first, within jpeg/png/webp — round 1 #10).
- `ensureFreeSlotOpen()` (public; the screen calls it BEFORE the body-area sheet — round 1 #11): list own folder (100, newest first), bounded sweep, count; throws `PhotoQuotaException` when used; any failure returns normally (server decides).
- `capture()` makes no tier decision; picks 2048 / 2048 / 85 (Q2); uploads BYTES with `uploadBinary` (fixes E6's web failure); after a failed row insert, `removeIfNoRow` removes the just-uploaded object only when a successful read shows no row for that path.
- `cleanupOrphanedStorage()` keeps its name and log lines (pinned by `test/sync/closeout_maintenance_test.dart`) and is rescoped: this week's objects, older than 60 min, rows read by path for exactly those candidates; any read failure removes nothing.
- Classifier: a `StorageException` carrying the literal `progress_photo_pro_required` is also a refusal.
- Clock: `nowWall()` (dev clock in debug, real time in release; server uses real `now()`: a mismatch is dev-only).

### 3.2 Screen (`progress_photos_screen.dart`)
- `_Access` = `{checking, pro, free}`; everyone gets the gallery or the empty state and the Add button; `ProLockedOverlay` is no longer used here (the widget stays as the design system's PRO locked card; its doc loses "its only user").
- `_onAddPhoto`: `gateAndVerify(featureProgressPhotos)`: `onPro` -> source sheet -> body area -> capture; `onFree` -> `ensureFreeSlotOpen()` first (quota -> snackbar, stop), then the same path.
- Weekly-cap snackbar text (all modes): `This week's free photo is in. Next one from Monday. PRO has no weekly limit.`; action `GO PRO` -> `showPaywallSheet(feature: 'Unlimited Progress Photos')` ONLY when `showsUpgradeAffordance()` (ADR-0022 — round 1 #1).
- `_onProRefused`: payment in flight -> "still activating"; forced verify NOT PRO -> the weekly-cap snackbar + reload (never an automatic paywall); PRO / unreachable -> "couldn't confirm".
- Free caption above the grid and in the empty state: `FREE · 1 PHOTO A WEEK`.
- Copy lives in a new `lib/core/copy/progress_photo_copy.dart` (round 1 #15).

### 3.3 Other surfaces
- `paywall_sheet.dart`: benefit `Unlimited progress photos`; subtitle case `'Unlimited Progress Photos'`: `One free photo a week. PRO has no weekly limit, so every check-in counts.` The old `'Progress Photos'` case is removed (no caller left).
- Hub `user_photos_screen.dart`: subtitle for a non-PRO user `1 free photo a week · PRO unlimited` (display only).
- `subscription_service.dart`: `featureProgressPhotos` stays in both sets; it now means "uploads beyond the free weekly photo". Root `CLAUDE.md` §2 Storage row: `progress photos (free 1/week, PRO unlimited)`; rule 19 stays true.
- §5.2 of the Play-billing plan: rows 9-11 re-described (refusal snackbar, Add free path, overlay gone) and a row for the new GO PRO action (gated by `showsUpgradeAffordance()`).

## 4. Tests (rule 21; each new protection mutated once)

New:
- `test/contracts/progress_photos_free_weekly_cap_rule_test.dart` — draft SQL pinned whole-text (comment/whitespace-insensitive) per object: week-start function, both cap functions, UPDATE guard, both triggers incl. `WHEN`, policy, REVOKEs, rollback; statement inventory; mutants: `WHEN` removed, week bound removed, lock after count, `>= 2` style relaxations, INVOKER, `created_at` from `now()` only, other-folder early return removed, UPDATE guard removed, PRO branch removed.
- `test/sql/progress_photos_free_weekly_cap_live_verify.sql` (above).
- `test/contracts/progress_photos_free_flow_test.dart` (behavioural, screen seams): free with no photos -> empty state + caption + Add; Add (free) -> `ensureFreeSlotOpen` BEFORE the body sheet; open -> capture; used -> snackbar, no body sheet, no capture; GO PRO present in a purchase mode and absent in `none`; PRO -> no slot check; refusal for a free user -> snackbar, no automatic paywall; lapsed with photos -> free.
- Repository behaviour with the Storage seams: 59-min orphan kept, 61-min this week removed, last week kept, row present kept, failed row read removes nothing, failed list -> slot unknown (no throw), removed orphan not counted, `removeIfNoRow` keeps an object whose row exists and keeps it when the read fails.
Updated (red today once the change lands): `progress_photo_client_rules_test.dart` (week start at IST Sun 23:59:59.999 / Mon 00:00, three zones; held-count table; content type; classifier literal leg), `progress_photo_capture_wiring_test.dart` (uploadBinary, no `File(`, 2048/2048/85, no 5/day, `removeIfNoRow` after a failed insert), `progress_photos_screen_gate_test.dart`, `progress_photos_lapsed_flow_test.dart`, `audit_2026_06_07_batch5_regression_test.dart` (F40), `purchase_literal_inventory_test.dart` (counts for the screen and the new copy file), `purchase_surfaces_mode_none_test.dart` (if it pins the screen), `paywall_mode_none_behavioral_test.dart` / `paywall_generic_upgrade_title_behavioral_test.dart` / `paywall_feature_label_test.dart` (new label), `user_photos_hub_test.dart` / `user_photos_gate_behavioral_test.dart` (subtitle), `test/sync/closeout_maintenance_test.dart` (unchanged pins, confirm), `progress_photos_pro_insert_rule_test.dart` (tripwire allow entry for the new migration when the file exists; header line of 154's verify file).

## 5. Docs and boards
- Diagnose doc (full template) `docs/diagnoses/2026-11-26-progress-photos-free-weekly-cap-f3c9a1.md`; `touched_layers_checked` tiers 1, 2 n/a, 3, 5, 8, 9, 12.
- `docs/sot_registry.yaml` (progress-photos rule + screen entries), `lib/features/profile/CLAUDE.md`, `lib/shared/widgets/wardroom/CLAUDE.md` (overlay note), root `CLAUDE.md` §2, `docs/architecture/subscription.md`, `business-rules.md`, `database.md`, `functionality-flow.md`, the Play-billing plan §5.2.
- OI-315 rewritten, not closed: the free cap is now server-side and the sweeper is wired (this week, bounded); PRO uploads stay uncapped by founder call Q3 (storage-cost exposure accepted) and orphans older than the current week are never swept (deliberately bounded). OI-316 gains one sentence: a dashboard or platform drop of `trg_progress_photo_object_cap` reopens the free cap with no alert.
- New OI (minted) for the residuals of §7, each with `reopen_when`.
- `backups/applied_migrations.json`, `backups/live_schema_columns.json` (no column change: confirm) after the apply.

## 6. Order
1. Code + draft SQL + tests + docs on the branch; whole-project `flutter analyze --no-fatal-infos`; gate loop.
2. PR, CI green -> review round 2 on the diff -> B-pass.
3. Founder go: always-aborting live rehearsal (draft + verify cases), then mint, copy (`cmp`), apply, live verify, ledger + snapshot commit.
4. CI green -> founder go to merge -> founder web check on app.icanbefitter.com (free account: first photo in, second refused with the snackbar; PRO: several) — this is also the live check of Storage's error mapping and the signed-upload path.

## 6a. Round 2 folds
- Early return keyed on `auth.role()` (above); live-verify cases: anon into a foreign folder and authenticated into a foreign folder both get the RLS refusal, not the trigger's literal; service_role JWT with another sub is capped by the owner. Mutant: the role test dropped.
- Row door: mutant and live case for the owner-prefix (`o.name LIKE NEW.user_id || '/%'`): a row pointing at another user's object path takes `now()`.
- Header: client-sent `created_at` is discarded on INSERT and kept on UPDATE; the two counts (object vs row) and the delete-object-keep-row path; the trigger FAILS OPEN if dropped (154's conjunct failed closed) — accepted and named on OI-316.
- Rollback restores 154's live ACL (`GRANT EXECUTE ... TO PUBLIC, anon, authenticated, service_role`, read live 2026-11-26); the rehearsal runs the rollback block too.
- Repository: `ownFailedCleanups` (in memory) lets this device's own failed cleanup be swept after 2 minutes instead of 60. Build: `cleanupOrphanedStorage` (the same bounded sweep) also runs, unawaited, on a PRO user's Add (round 1 #13: PRO orphans), and reads the user inside its try so it never throws; OI-315 closes on that (PRO uncapped is founder call Q3).
- §6 step 4 adds a founder two-tab check: a free user uploading in two tabs at once ends with exactly one photo.

## 7. Residuals (go on the board as one minted OI, `upstream_blocked` / `blocked_on_user`)
- Two parallel free uploads: designed (advisory lock + fresh snapshot); the founder's two-tab check (§6a) covers the standard path; reopen when a local Supabase image or a two-session harness is available.
- A device clock hours behind across Monday makes the courtesy pre-check count last week's photo and block a free user until the clock catches up (the server would accept); reopen if a user reports it.
- Storage platform behaviour (error mapping of a trigger 42501; INSERT timing vs the S3 write; TUS / S3-protocol paths): checked by the founder's web upload (§6 step 4) for the standard path only.
- A platform migration dropping a user trigger on `storage.objects`: OI-316's class.
