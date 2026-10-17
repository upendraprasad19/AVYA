# Audit 4: performance + observability + privacy findings

Auditor: Claude (Opus 4.7). Repo at `C:\Upendra\Claude Code\Fitness App`, branch `main`. No fixes applied — read-only audit.

---

## P0 (release-blocking / data loss / privacy violation)

### P0-1. "Delete Account" does not delete data — DPDP violation
`lib/features/profile/screens/profile_screen.dart:2200-2275`. The DELETE ACCOUNT confirm dialog only:
1. UPDATEs `public.users` `is_deleted=true, deleted_at=now()` (soft flag).
2. Calls `auth.signOut(scope: global)`.
3. Wipes Hive locally.

It does **not**: (a) delete `auth.users` row, (b) cascade any FK-bound user data (`user_profile`, `workout_logs`, `nutrition_logs`, `ai_coach_interactions`, `coach_memory`, `memory_embeddings` — see CLAUDE.md §7), (c) purge Storage objects (progress photos under user-scoped bucket per §10), (d) revoke Razorpay subscription. The auth user remains active; nothing prevents the soft-deleted email from re-signing in. DPDP §17(2) requires actual erasure on request — soft-flag is non-compliant. **Required:** server-side `delete-account` Edge Function that calls `auth.admin.deleteUser(userId)` (CASCADE flows from migration 039 FK), iterates `progress_photos.storage_path` and removes from bucket, deletes any non-cascading rows, and only then signs out.

### P0-2. Splash logo loaded full-bleed without `cacheWidth`/`cacheHeight`
`lib/features/auth/screens/splash_screen.dart:289-292`. `Image.asset('assets/avya_logo.png', fit: BoxFit.cover)` decodes the **400 KB / full-resolution** PNG into a screen-sized texture. On low-end Android (1080×2400) the decode runs on the main isolate and stalls the first frame for 200-400 ms. Same issue: `assets/avya_icon.png` is 159 KB, `assets/founder/upendra.jpg` is 200 KB. Add `cacheWidth: MediaQuery.of(context).size.width.toInt()` (or pre-resize the assets to ~720 px wide and ship a smaller PNG). Cold start budget — the splash's whole purpose is to be instant.

### P0-3. Bundled assets bloat the APK
`pubspec.yaml:106-111` ships:
- `assets/data/exercise_library.json` (426 KB)
- `assets/data/food_database.json` (711 KB after V2 expansion)
- `assets/data/daily_quotes.json` (40 KB)
- `assets/data/workout_quotes.json` (2 KB)
- `assets/avya_logo.png` (400 KB), `assets/avya_icon.png` (159 KB), `assets/founder/upendra.jpg` (200 KB)

Total ~1.9 MB raw; gzip-compressed in APK ~1 MB. This is acceptable for the seed JSON (must be local for first-launch offline seeding per CLAUDE.md §4) but the **logos and founder photo are oversized**. Resize `avya_logo.png` to ~150 KB (currently the asset is 4× larger than needed for any device) and `upendra.jpg` to ~80 KB at quality 80. Confirms `pubspec.yaml` correctly does NOT bundle `Knowledgebase/`, `assets/naval pics/`, or the `.docx`/`.xlsx`/`.pdf` knowledge base files (they're not in the `flutter.assets:` block).

---

## P1 (premium-feel — slow / silent broken / hard to debug)

### P1-1. ~50 silent `catch (_) {}` blocks in SyncService
`lib/core/services/sync_service.dart` lines 161, 344, 371, 427, 437, 482, 514, 544, 691, 738, 803, 833, 863, 1034, 1123, 1131, 1200, 1290, 1298, 1318, 1358, 1365, 1382, 1408, 1437, 1466, 1497, 1525, 1550, 1576, 1630, 1742, 1757, 1968, 1989, 2008, 2023, 2033, 2199, 2233, 2332, 2370. **Mitigating factor verified:** sampled lines 161, 691, 738 — most are inner catches AFTER a `_reportSyncFailure()` call (i.e. they only swallow a failure of the reporter itself). That's fine. **But the count is so high that any genuinely silent path is invisible by inspection.** Recommend a comment marker (`// reporter-fallback`) on each of these so future reviewers can grep for ones missing it.

### P1-2. `e.toString()` shown to user in release without `kDebugMode` guard
- `lib/features/train/screens/preview_workout_screen.dart:86` — preview phase load failure renders `Text(e.toString())` directly. Leaks PostgrestException text + JWT-internal hints to user.
- `lib/features/auth/providers/auth_provider.dart:121` — `errorMessage: '[${e.runtimeType}] ${e.toString().split('\n').first}'`. The `.split('\n').first` mitigates stack trace leakage but `e.runtimeType` (e.g. `PostgrestException`, `AuthRetryableFetchException`) is still exposed in the auth UI. Add a typed-error mapper.
- `lib/features/auth/providers/auth_provider.dart:185` — `'Sign up failed: ${e.toString().split('\n').first}'`. Same.
- `lib/features/ai_coach/screens/ai_coach_screen.dart:1632` — photo upload error shown with `e.toString().substring(0, 80)`. Truncation is not sanitization; `kDebugMode` guard absent.
- `lib/features/ai_coach/widgets/diff_preview/switch_goal_diff.dart:68` — `setState(() => _error = e.toString())` and rendered to UI. Unguarded.

`lib/app.dart:64` correctly uses `kDebugMode ? details.exceptionAsString() : 'Please restart…'` — the pattern exists; just isn't applied uniformly. Note: the "Please restart the app" copy contradicts CLAUDE.md §19 ("Never use 'restart the app' error copy"). Fix copy to "If this keeps happening, contact support" + request_id.

### P1-3. `print(` in production code path
- `lib/features/train/providers/preview_plan_provider.dart:74,80` — two raw `print(` calls. Should be `debugPrint(`. They will ship in release and bypass the debug-only Flutter print stripping.

### P1-4. Edge Function error sanitization — 5 functions lack `request_id` / "Internal server error" pattern
Audit of `supabase/functions/*/index.ts` for both `request_id` and "Internal server error" markers (CLAUDE.md §11):
- `ai-media-proxy/index.ts` — request_id=2, ISE=1 ✅
- `ai-proxy/index.ts` — request_id=6, ISE=1 ✅
- `ai-proxy-pro/index.ts` — **request_id=0, ISE=0** (file is the 410-Gone stub per CLAUDE.md §11; verify it returns generic 410 not raw error. Acceptable.)
- `clean-orphan-media/index.ts` — **request_id=0, ISE=0** ❌ Missing.
- `log-client-error/index.ts` — **request_id=0, ISE=0** ❌ The error reporter itself doesn't log request_ids. Self-referential — if `log-client-error` fails the caller can't correlate.
- `promote-community-item/index.ts` — **request_id=0, ISE=0** ❌
- `video-status/index.ts` — **request_id=0, ISE=0** (deferred/410-stub per CLAUDE.md §19; acceptable.)

Add the §11 pattern to `clean-orphan-media`, `log-client-error`, `promote-community-item`. None are user-facing critical paths but `clean-orphan-media` runs as cron over Storage operations — silent failures = orphan accumulation.

### P1-5. Hive box compaction has a race condition gap
`lib/core/services/hive_service.dart:99-149`. Lifecycle observer is registered correctly at line 70 (`WidgetsBinding.instance.addObserver(this)` inside `init()`) and gate logic at lines 117-122 honours the 7-day window. **Gap:** lines 124-142 iterate `_compactableBoxNames` which includes user-scoped boxes (`workoutBox`, `nutritionBox`, etc.). At line 131 it `continue`s if no user is signed in — but if the user signs out and pauses immediately, `currentOwnerFullId` is null and **no boxes get compacted that pass**. Over months, a sign-out-heavy testing cycle can starve compaction on the user-scoped boxes. Low priority but a future leak.

### P1-6. `notificationsBox` and `coachBox` grow unboundedly
CLAUDE.md §15 documents notificationsBox + coachBox in `_compactableBoxNames` (verified line 87-88). Compaction reclaims dead bytes but does not prune entries. **No retention policy** found for `notificationsBox` (every push-mirrored entry stays forever) or `coachBox` `chat_history_*` keys. On a power user after 6 months: notificationsBox can hit several MB; coachBox is the bigger risk because the AI snapshot fanout reads from it. Add a per-box "retain last N days / N entries" sweep alongside compaction.

### P1-7. Splash blocks navigation on a 3-second floor regardless of device
`splash_screen.dart:91-101` — `Future.wait([_runDeferredInit(), Future.delayed(3000ms)])`. On a fast device with warm cache, init may finish in 600 ms but the user still stares at the splash for 2.4 s. On a cold-start slow device, init may exceed 3 s and the user waits longer than 3 s anyway — so the floor only hurts the fast path. Consider 1500 ms floor + branding fade-out.

### P1-8. `splash._runDeferredInit` fires 6 unawaited futures with no observability
Lines 160, 164, 167, 172, 184, 189 — `pushSnapshot`, `checkAndSync`, `RankService.evaluateAndPromote`, `subscriptionService.refreshFromSupabase`, `_autoGenerateNextPhaseForPro`, `SyncQueue.drain`. Each is fire-and-forget with no top-level error reporter. CLAUDE.md §19 lists three of these as historical regression hotspots ("Daily snapshot not pushing", "Phantom PRO status", "Days/week change not rescheduling"). If any silently fails on a user's device, there's no `client_errors` row to find. `SyncService.checkAndSync` and `_reportSyncFailure` cover most paths internally — verify `pushSnapshot`, `RankService.evaluateAndPromote`, `_autoGenerateNextPhaseForPro` (line 248 swallows to debugPrint) post to log-client-error on failure.

### P1-9. `_autoGenerateNextPhaseForPro` swallows to debugPrint only
`splash_screen.dart:248-250`. If a PRO user's auto-phase-2 generation crashes (corrupt exerciseBox, missing profile field), the user lands on home with no schedule and an empty Today card — and there's no telemetry trace. Wire to `log-client-error` like `_ensureLocalUser` was in Test #3.

---

## P2 (polish)

### P2-1. `progress_photos_screen.dart:253` uses raw `Image.network(url, fit: BoxFit.cover)`
No `cacheWidth`/`cacheHeight`, no error builder, no loading shimmer. CDN images decoded full-resolution per tile. Three `cached_network_image` callsites already exist elsewhere — use it here too.

### P2-2. Founder photo decoded at full resolution
`assets/founder/upendra.jpg` (200 KB, likely ~3000×3000 from camera/HEIC export per CLAUDE.md §13a) is shown at 96 dp on Mission Brief and as a profile avatar elsewhere. Pass `cacheWidth: 256` on every `Image.asset` load to prevent the full bitmap entering memory.

### P2-3. `flutter_dotenv` reference in `pubspec.yaml` comment
Lines 59-60 — comment is correct (package was removed). No action needed; just confirming env-var injection is via `--dart-define-from-file=.env` only.

### P2-4. Cold-start `_safeOpenBox` recovery deletes data on corruption
`hive_service.dart:155-163` — on box-open failure, it deletes the box and re-opens empty. **Acceptable** for the boxes it covers (shared seed boxes — `exerciseBox`/`foodBox` reseed; `syncBox`/`configBox` are app-state). But document it: a corrupted user-scoped box would be wiped silently. Currently shared-only via `_sharedBoxNames` so this is fine, but if `HiveUserSession` ever uses `_safeOpenBox` for user-scoped boxes, a single bad write = silent data loss.

---

## DPDP-specific (separate so user can flag to legal)

### DPDP-1. Account deletion is a soft-flag, not erasure (see P0-1 above)
Flag this to legal. Indian DPDP §17 requires actual erasure, not a deletion flag. Razorpay subscription continues billing after "delete" — separate liability.

### DPDP-2. Consent capture verified ✅
- `terms_accepted_at` + `terms_version` columns exist (migration 032).
- `lib/features/auth/widgets/terms_modal.dart` + sign-up screen capture both.
- `lib/core/constants/app_constants.dart` declares `termsVersion`.
- Round-trip Hive ↔ cloud works per CLAUDE.md §7.

### DPDP-3. Data minimization — generally good but verify
- AI coach snapshot trimmed to <9.5 KB (CLAUDE.md §11) — correct minimization.
- No address book / contacts / device-id collection found in grep.
- Health Connect read scope limited to `READ_STEPS` + `READ_WEIGHT` (`AndroidManifest.xml:11-12`) — minimal. ✅
- Camera + RECORD_AUDIO + READ_MEDIA_IMAGES requested — needed for scan_meal/voice/profile photo. ✅

### DPDP-4. Right to access / portability — not implemented
No "download my data" button found in the profile screen (grep `export|download.*data` came back empty in `lib/features/profile`). DPDP §11 requires data subject access. Lower urgency than P0-1 but legal will eventually flag.

### DPDP-5. Auto Backup exclusion correctly configured ✅
`AndroidManifest.xml:21-23`: `android:allowBackup="false"` + `android:dataExtractionRules` + `android:fullBackupContent`. `data_extraction_rules.xml` excludes `app_flutter` for both cloud-backup and device-transfer. Profile-id mismatch defense-in-depth verified at `splash_screen.dart:117-129` and `subscription_service.dart:91-98`. Good.

---

## Quick wins

1. Add `cacheWidth` to `Image.asset('assets/avya_logo.png', …)` at `splash_screen.dart:289`. 30-min fix, removes 200-400 ms cold-start jank on slow devices.
2. Resize `assets/avya_logo.png` 400 KB → ~80 KB (lossless tooling, same dimensions). 5-min fix, shaves APK and runtime memory.
3. Replace 2 raw `print(` with `debugPrint(` in `preview_plan_provider.dart:74,80`.
4. Wire `clean-orphan-media`, `log-client-error`, `promote-community-item` Edge Functions to the §11 sanitization pattern. Consistency, no behavior change.
5. Wrap `e.toString()` in `kDebugMode` guards at the 4 leak sites listed in P1-2.
6. Fix "Please restart the app" copy at `lib/app.dart:66` to comply with CLAUDE.md §19 rule.

---

## Things checked and clean

- Hive adapter registration order — no custom adapters needed (boxes use raw maps + primitives).
- `HiveService` `WidgetsBindingObserver` registration: `init()` line 70. 7-day gate at lines 117-122. Compaction list excludes seed-only `exerciseBox`/`foodBox`. Correct.
- Profile-id mismatch downgrade enforced in two places: `splash_screen.dart:117-129` AND `subscription_service.dart:89-103`. Belt-and-suspenders.
- Auto Backup exclusion XML present and correct.
- Crashlytics initialized FIRST in `main.dart:31-46`, both `FlutterError.onError` and `PlatformDispatcher.instance.onError` routed.
- HiveOwnershipException atomic-recovery path at `main.dart:99-135`.
- Atomic-logout recovery flag at `main.dart:62-73`.
- `client_errors` / `log-client-error` integration verified in 7 files (sync_service, onboarding_provider, progress_photo_repository, auth_provider, sync_error, sync_queue, app_events_service).
- Auth provider 23505/23503 surfacing wired (`auth_provider.dart:380-386`) per Test #3.
- `cached_network_image` used for chat bubbles + profile identity (the long-lived image surfaces).
- Edge Function error sanitization correctly applied in 28 of 33 functions.
- Term acceptance + version captured cloud-side and Hive-side.
- Health permission scope minimal (`READ_STEPS`, `READ_WEIGHT` only).
- Splash defers Supabase + SeedService + OneSignal off the boot path (`main.dart:88` comment + verified at `splash_screen.dart:106-200`).
