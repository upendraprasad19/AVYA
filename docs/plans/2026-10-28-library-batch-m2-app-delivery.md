# Batch M2 plan: exercise animations in the app (OI-440 and OI-354)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline, founder lock) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> Status: r1, 2026-10-28 (not yet reviewed). Review history: none yet. The plan-review record will state the rounds actually run.
> **Goal:** a signed-in user sees the exercise animation wherever a plate shows today (plan list, calendar day sheet, active workout), the active workout gets the OI-354 hero tile and full-screen viewer, the files are fetched and cached by ONE class, bulk download happens on Wi-Fi only, and a kill switch restores today's behaviour.
> **Architecture:** a resolver turns an exercise name into `{media_slug, media_version}`; one HTTP class reads the private bucket over plain HTTP with the user's token; a store keeps the files (files on native, a Hive lazy box on web) with a size cap that never evicts the current plan window; a repository serves `ensure(name)` and runs the Wi-Fi prefetch; widgets show the bundled 192 px still first and swap in the animation when the file is on the phone.
> **Tech stack:** Flutter, Riverpod (hand-written providers), Hive, `package:http` (already a dependency), `connectivity_plus`, Supabase Storage (plain HTTP, never `storage.from`).
> **Spec:** `docs/superpowers/specs/2026-10-28-exercise-animations-app-delivery-design.md` (design r2 plus the 11-held/148-applied patch; calls C1 to C23 are cited below as C-numbers). Parent: `docs/superpowers/specs/2026-10-21-exercise-library-comprehensive-design.md`. Builds on `docs/plans/2026-10-27-library-batch-m1-media-data.md` and `docs/operations/EXERCISE_MEDIA.md`.
> Branch and worktree `library-batch-m2` (from main `8e2cbdc8`; the design is committed as `090ff39c`). Plan-review record `docs/plan-reviews/library-batch-m2.md` (`branch: library-batch-m2`), B-pass file `docs/reviews/library-batch-m2-bpass.md` (its `verdict:` line BARE once accepted, and a dated `## Tuning entry`).
> Execution: INLINE (decided at batch start, section 4.12.7; not switched mid-batch). Reviewers and the B-pass are fresh Sonnet subagents, at most 4 at once. Blast radius `platform` (`pubspec.yaml` gets an asset entry; `docs/blast_radius.yaml:614-615`); confirm with `blast_radius_from_diff.dart` fed on BARE stdin (`-`) at close-out. Every commit goes through `sh scripts/safe_commit.sh "<msg>"` (files staged first, one positional argument, no attribution lines), the one push through `sh scripts/safe_push.sh` over HTTPS at PR time only. **Mutation cycles** (rule 21) on a file that is not committed yet: copy it first (`cp f <scratchpad>/f.bak`), mutate, confirm the mutation applied (`grep -c`), run, restore with `cp`, then `cmp`; never `git checkout --` (`feedback_mistake_mutation_restore_discards_uncommitted_fixes.md`). Commit each task BEFORE mutating its files.
> **Split rule (section 4.12.1):** the plan is written as Part A (delivery, still tiles, animated sheet, kill switch; Tasks 1 to 9, ends in a mergeable state) and Part B (OI-354 hero tile and viewer; Tasks 10 to 13, needs only Part A's repository). If review round 2 still finds new material issues in Part B, Part B leaves this plan and becomes its own branch and plan; Part A ships alone.

## Global Constraints (every task includes these)

- G1. Hive-first and offline-first: no widget waits for the network; widgets never call Storage or Hive directly; the fetch class is a service behind a Riverpod provider (root rules 1, 4).
- G2. The app reads the bucket ONLY by plain HTTP GET on `/storage/v1/object/authenticated/exercise-media/<media_slug>_v<media_version>.webp` with the user's session token, inside ONE class (C12). `storage.from` and `.storage` never appear in the new files; `test/contracts/delete_account_purges_all_user_buckets_test.dart` is not edited.
- G3. A refused or failed read is "retry later", never "no animation" (C4): on this route a forbidden read and an absent object both answer HTTP 400.
- G4. Kill switches (C22): animations are active only when `disable_exercise_plates` is unset AND `disable_exercise_animations` is unset; with either set the surface behaves as it does today.
- G5. Free to every tier (C7); no `subscription.gate()`.
- G6. Fonts DM Sans, Wardroom palette, dark theme (rules 10 to 12). All new copy goes through `lib/shared/widgets/wardroom/CLAUDE.md` before it is written.
- G7. Date keys use `lib/core/utils/ist_date.dart` (the daily prefetch ceiling resets on the IST date).
- G8. Library rows can hold any JSON type: guard every read with `is String` / `is int`.
- G9. Tile widgets rebuild about once a second on the active workout screen: resolve in `initState` / `didUpdateWidget`, never in `build()`.
- G10. No change to `plan_generator.dart`, the library JSON, the seed or any Edge Function. No migration. No live apply, so no live-apply go is needed for the app part.
- G11. **The sites that show a plate today (verified 2026-10-28 by `grep -rn "ExercisePlateThumb\|ExercisePlateSheet" lib`):** the calendar day sheet (`day_detail_sheet.dart:250`, opened from `home_screen.dart:513`), the active workout header (`exercise_card.dart:1105`) and its "VIEW PLATE" door (`coaching_content_panel.dart:137`). `ExpandableDayCard` (`expandable_day_card.dart:230`, the design's "plan list" site) is imported by NO file under `lib/` (`grep -rn "expandable_day_card" lib` is empty; its class is defined and never built), and no widget under `lib/features/train/screens/train/` draws a plate, so **the Train tab's plan list shows no pictures today**. M2 follows the founder's rule ("wherever the plates are visible right now"): the dead card inherits the shared thumb's change for free and is not tested for reachability; adding a picture to the Train tab's list is new UI and is NOT in this plan (put to the founder as a question).

## Review Focus (input classes the tests below pin; the reviewer checks each deliberately)

1. A row whose `media_slug` is a String but `media_version` is missing, 0, a double or a string: no delivery attempt, today's plate or initials (Task 4).
2. The token expires between two opens: the first read answers 400 or 401, the client refreshes once and retries once, then reports "refused" without looping (Task 6).
3. Two widgets ask for the same file at once (plan list and sheet): one download, both get the bytes (Task 7).
4. The cap is reached while the current plan window fills the store: the store goes over the cap rather than evict a window file, and says so (Task 5).
5. Connectivity reports `[wifi, mobile]`, `[]`, or `[other]`: prefetch runs only when the list holds `wifi` or `ethernet` and the platform is not web (Task 8).

## File map

Create:
- `lib/core/services/exercise_media/exercise_media_client.dart`: the one HTTP class (C12).
- `lib/core/services/exercise_media/exercise_media_store.dart`: store interface, file-backed native store, Hive-lazy-box web store, index and eviction.
- `lib/core/services/exercise_media/exercise_media_repository.dart`: `ensure`, in-flight dedupe, backoff, byte counters, daily prefetch ceiling.
- `lib/core/services/exercise_media/exercise_media_prefetch_policy.dart`: pure decisions (Wi-Fi gate, plan window, ceiling).
- `lib/shared/providers/exercise_media_provider.dart`: Riverpod providers for the client, store and repository.
- `lib/shared/widgets/exercise_plate/exercise_media_resolver.dart`: `ExerciseMedia` and `resolveMedia(name)`.
- `lib/shared/widgets/exercise_plate/exercise_animation_view.dart`: still-then-animation widget (reduce-motion branch, decode at display size).
- `scripts/bundle_exercise_stills.js` and `assets/exercise_stills/<media_slug>.webp` (616 files, 3,102,690 bytes).
- Part B: `lib/features/train/screens/active_workout/exercise_hero_tile.dart` and `exercise_media_viewer.dart` (normal libraries beside the `part of 'screen.dart'` files), `docs/mockups/2026-10-28-active-workout-hero-tile.html`.
- Tests under `test/contracts/` (named per task).

Modify: `pubspec.yaml` (asset entry), `lib/core/services/hive_service.dart` (web blob box), `lib/shared/widgets/exercise_plate/plate_flags.dart`, `exercise_plate_thumb.dart`, `exercise_plate_sheet.dart`, `lib/features/train/screens/active_workout/{screen,exercise_card,coaching_content_panel}.dart` (Part B), `docs/sot_registry.yaml`, `docs/operations/EXERCISE_MEDIA.md` (section 9), `docs/audit/open_issues.md` (OI-440, OI-354), nested `CLAUDE.md` files named in Task 14.

## Part A: delivery, still tiles, animated sheet, kill switch

### Task 1: Throwaway spike, then the findings file (nothing from the spike is kept as code)

**Why first (design section 9):** four things were never observed: an animated WebP animating inside the Flutter app (phone and web), a real user's token reading a real object through plain HTTP, the browser's CORS answer to an Authorization header, and the answer to a bad or expired token.

**Files:**
- Create (committed): `docs/audit/library-m2-spike-findings.md`.
- Create (NOT committed, deleted at the end of the task): `lib/spike_m2_main.dart`, run with `flutter run --dart-define-from-file=.env --flavor dev -t lib/spike_m2_main.dart` (phone) and `-d chrome` without a flavor (web).

**Interfaces:** Produces the findings table that Tasks 5, 6 and 9 read: S1 animates (yes/no per platform), S2 status and first bytes, S3 CORS verdict, S4 bad-token status, S5 response headers, S6 first-frame time and memory feel.

- [ ] **Step 1: Write the spike entry point.** One screen: sign in is NOT built; it reuses the app's own session. Buttons: (a) GET one real object with the user's token and show status, `content-type`, `cache-control`, `etag`, byte count; (b) `Image.memory(bytes, cacheWidth: 360)` and a frame counter from `ui.instantiateImageCodec` (`frameCount`); (c) the same GET with no Authorization header, with `Bearer invalid`, and with the anon key as bearer; (d) the same GET from the browser build.
- [ ] **Step 2: Run on web (built-in browser) with a QA account.** Credentials come from the founder in chat or the project's own seed or fixture files, never typed from memory and never the founder's real password. Record S1 (web), S2, S3, S4, S5.
- [ ] **Step 3: Run on a phone.** Android device or emulator through the founder: if neither can be reached in this session, this step is `blocked_on_user` (list it in the closure table) and Part A may proceed to Task 2 to Task 8 in the meantime; Task 9's device step waits for it. Record S1 (Android), S6.
- [ ] **Step 4: Write `docs/audit/library-m2-spike-findings.md`** with a table of S1 to S6, the raw status lines, and the ladder verdict: if S3 is "blocked", Task 6 Step 7 applies; if S1 is "no" on a platform, that platform ships stills only (C14 b) and Task 9 Step 5 applies.
- [ ] **Step 5: Delete the spike file, confirm `git status --short` shows only the findings file, commit** `docs(library): Batch M2 spike findings - animated WebP, token read, CORS, bad-token answers`.

Expected: findings committed; no `lib/` change.

### Task 2: Bundle the 616 stills

**Files:**
- Create: `scripts/bundle_exercise_stills.js`, `assets/exercise_stills/*.webp` (616), `test/contracts/exercise_stills_bundle_test.dart`.
- Modify: `pubspec.yaml` (add `    - assets/exercise_stills/` after the `assets/exercise_plates/` line at `pubspec.yaml:132`).

**Interfaces:** Produces the asset path rule `assets/exercise_stills/<media_slug>.webp` (Task 4 reads it as `ExerciseMedia.stillAsset`). The script takes `--src <dir>` (required: the founder's `.../wardroom customized gifs` folder lives only in the primary checkout, never at a relative path from a worktree, M1 fact F1) and `--check`.

- [ ] **Step 1: Write the failing test** `exercise_stills_bundle_test.dart`: (a) for each of the 616 `files[slug]` in `scripts/data/library_media_v16.json`, `assets/exercise_stills/<slug>.webp` exists, its size equals `thumb_bytes`, its sha256 equals `thumb_sha256`; (b) the directory holds exactly 616 files (no extras); (c) **mirror:** every library row in `assets/data/exercise_library.json` that carries a non-empty `media_slug` has a still (617 rows, 616 slugs); (d) `pubspec.yaml` lists `assets/exercise_stills/`; (e) the total size is 3,102,690 bytes.
- [ ] **Step 2: Run it.** Expected: FAIL (directory missing).
- [ ] **Step 3: Implement `scripts/bundle_exercise_stills.js`:** for each slug read `versions[0].file`, derive the still as `thumbnails-192/` plus the file name with `_720` replaced by `_192` (observed: `0001_Three_Quarter_Situp_wardroom_192.webp`), verify sha256 against `thumb_sha256`, copy to `assets/exercise_stills/<slug>.webp`; `--check` verifies the repo copy only.
- [ ] **Step 4: Run the script with `--src` set to the primary checkout folder, add the pubspec entry, run the test.** Expected: PASS.
- [ ] **Step 5: Mutate:** flip one byte of a copy of one still in the scratchpad's test fixture path used by a second test case "a still whose hash differs is reported" (the test calls the script's `--check` against a temp dir). Expected: that case FAILS on the mutated file. Restore.
- [ ] **Step 6: Commit** `feat(library): Batch M2 Task 2 - bundle the 616 exercise stills (3.1 MB) with a hash test`.

### Task 3: Kill switch

**Files:** Modify `lib/shared/widgets/exercise_plate/plate_flags.dart`; Test `test/contracts/exercise_animation_flags_test.dart`.

**Interfaces:** Produces `PlateFlags.animationsEnabled` (static getter, bool). Consumed by Tasks 9, 11, 12.

- [ ] **Step 1: Write the failing test.** With a Hive `configBox`: (plates unset, animations unset) -> true; (plates set) -> false; (animations set) -> false; (both set) -> false; no Hive at all -> true (same guard as `platesEnabled`, `plate_flags.dart:37-44`). **Mirror:** `platesEnabled` is unchanged by `disable_exercise_animations`.
- [ ] **Step 2: Run.** Expected: FAIL (getter missing).
- [ ] **Step 3: Implement** `static bool get animationsEnabled` with the same try/catch shape as `platesEnabled`, reading `configBox.get('disable_exercise_animations') != true` AND `platesEnabled`. Update the file header comment (kill switch, default ON feature, how to disable).
- [ ] **Step 4: Run.** Expected: PASS. **Mutation:** drop the `platesEnabled &&` term; the "plates set" case must FAIL. Restore, `cmp`.
- [ ] **Step 5: Commit** `feat(library): Batch M2 Task 3 - disable_exercise_animations kill switch`.

### Task 4: Resolver

**Files:** Create `lib/shared/widgets/exercise_plate/exercise_media_resolver.dart`; Test `test/contracts/exercise_media_resolver_test.dart`.

**Interfaces:**
- Produces `class ExerciseMedia { final String slug; final int version; String get objectName; String get stillAsset; }` and `ExerciseMedia? resolveMedia(String exerciseName)`.
- Consumes `ExerciseRepository.instance.getByExactName(String) -> Map<String, dynamic>?` (`exercise_repository.dart:48`, exact name, alias fallback).

- [ ] **Step 1: Write the failing test** (copy the Hive and path_provider harness from `test/contracts/exercise_plate_resolver_test.dart`). Cases: slug `0103-barbell-standing-ab-rollout` + version 1 -> `objectName == '0103-barbell-standing-ab-rollout_v1.webp'`, `stillAsset == 'assets/exercise_stills/0103-barbell-standing-ab-rollout.webp'`; slug present and version missing, `0`, `1.0` (double), `'1'` (string) -> null; slug `''`, `'  '`, `7` (int), `null` -> null; unknown name -> null; a name that matches only through `name_aliases` -> the media of the surviving row (inherits `getByExactName`); a community row (map with `media_slug: 42`) does not throw.
- [ ] **Step 2: Run.** Expected: FAIL (file missing).
- [ ] **Step 3: Implement.** `is String` + trim, `is int && >= 1`; no Flutter imports (same rule as `plate_resolver.dart`). Do NOT touch `plate_resolver.dart` or `resolvePlate`.
- [ ] **Step 4: Run.** Expected: PASS. **Mutation:** change `is int` to `is num`; the `1.0` case must FAIL. Restore, `cmp`.
- [ ] **Step 5: Commit** `feat(library): Batch M2 Task 4 - resolveMedia reads media_slug and media_version with type guards`.

### Task 5: Store (files on native, Hive lazy box on web), index, cap

**Files:** Create `lib/core/services/exercise_media/exercise_media_store.dart`; Modify `lib/core/services/hive_service.dart`; Test `test/contracts/exercise_media_store_behavioral_test.dart`.

**Interfaces:**
- Produces `abstract class ExerciseMediaBytesStore { Future<Uint8List?> read(String name); Future<void> write(String name, Uint8List bytes); Future<void> delete(String name); }` with `FileExerciseMediaBytesStore(Directory dir)` and `HiveExerciseMediaBytesStore(LazyBox box)`.
- Produces `class ExerciseMediaStore { ExerciseMediaStore({required ExerciseMediaBytesStore bytes, required Box index, int capBytes = 150 * 1024 * 1024, DateTime Function() now}); Future<Uint8List?> read(String name); Future<void> put(String name, Uint8List bytes, {required Set<String> pinned}); bool has(String name); int get totalBytes; }`. The index lives under `configBox['exercise_media_index_v1']` as `{name: {bytes: int, shown: epochMs}}`. `read` bumps `shown`.
- Produces `HiveService.mediaBlobBox` (a `LazyBox`, opened in `init()` only when `kIsWeb`, name `exerciseMediaBlobs`; otherwise a `StateError` like `getBox`). It is a CACHE box, not user data: it is not user-scoped (C8) and is added to no wipe list.
- Eviction rule: after a `put`, while `totalBytes > capBytes`, evict the entry with the smallest `shown` whose name is NOT in `pinned`; if every remaining entry is pinned, stop and keep the overage (Review Focus 4). Never delete the entry just written.

- [ ] **Step 1: Write the failing test** with an in-memory `ExerciseMediaBytesStore` fake and a Hive temp box for the index. Cases: put then read round-trips; `has` is true after put; `read` of an unknown name -> null; cap 100 bytes with three 40-byte entries put in order a, b, c and `pinned = {}` -> `a` evicted, `b`,`c` kept; same with `pinned = {a}` -> `b` evicted; **all pinned** (cap 100, pinned {a, b, c}) -> nothing evicted, `totalBytes == 120`; the entry just written is never the victim; `read(a)` bumps its recency so `b` is evicted first; the index survives re-creating the `ExerciseMediaStore` over the same boxes (restart); a corrupted index value (a String) is treated as empty and rebuilt without throwing; writing the same name twice does not double-count bytes. File store: a temp directory round trip, `delete` of a missing name does not throw.
- [ ] **Step 2: Run.** Expected: FAIL (file missing).
- [ ] **Step 3: Implement** the interface, both byte stores and `HiveService.mediaBlobBox` (`await Hive.openLazyBox('exerciseMediaBlobs')` inside `init()` under `if (kIsWeb)`, with the same corrupt-box recovery shape as `_safeOpenBox`, `hive_service.dart:182-193`).
- [ ] **Step 4: Run.** Expected: PASS. **Mutations (two):** (a) remove the `pinned` check from the victim choice; the pinned cases must FAIL; (b) make eviction skip the recency order (pick the first); the recency case must FAIL.
- [ ] **Step 5: Commit** `feat(library): Batch M2 Task 5 - exercise media store with a 150 MB cap that never evicts the plan window`.

### Task 6: The one HTTP class

**Files:** Create `lib/core/services/exercise_media/exercise_media_client.dart`; Test `test/contracts/exercise_media_client_behavioral_test.dart`, `test/contracts/exercise_media_reads_without_storage_from_test.dart`.

**Interfaces:**
- Produces `enum MediaFetchOutcome { fetched, refused, unreachable }` and `class MediaFetchResult { final MediaFetchOutcome outcome; final Uint8List? bytes; final int? status; }`.
- Produces `class ExerciseMediaClient { ExerciseMediaClient({http.Client? httpClient, Future<String?> Function({bool forceRefresh})? tokenProvider, String? baseUrl, Duration timeout = const Duration(seconds: 30)}); Future<MediaFetchResult> fetch(String objectName); }`.
- Consumes `AppConstants.supabaseUrl` and `AppConstants.supabaseAnonKey` (`lib/core/constants/app_constants.dart:11-12`); default `tokenProvider` calls `SupabaseService.instance.ensureFreshToken()` (`supabase_service.dart:324`) and, when `forceRefresh`, `SupabaseService.instance.client.auth.refreshSession()` (the neighbour pattern is `ai_coach_provider.dart:1013`).

- [ ] **Step 1: Write the failing tests** with `MockClient` (`package:http/testing.dart`; precedent in `test/contracts/password_recovery_code_flow_behavioral_test.dart`). Cases: 200 with a body starting `RIFF....WEBP` -> `fetched` with the bytes; the request is `GET <base>/storage/v1/object/authenticated/exercise-media/<name>` with headers `Authorization: Bearer <token>` and `apikey: <anon>`; 400 then 200 -> exactly two requests, the second after `tokenProvider(forceRefresh: true)`, outcome `fetched`; 400 then 400 -> exactly two requests, outcome `refused`, NOT three; 401 and 403 and 404 behave like 400; no token (`null`) -> outcome `refused` with ZERO requests; a 200 whose body is not a WebP (starts with `{"error"`) -> `refused`; 500 and a thrown `SocketException` and a timeout -> `unreachable`; a 200 with an empty body -> `refused`. The source-grep test strips comments first (`feedback_source_grep_strip_comments_first.md`) and asserts that none of the new files under `lib/core/services/exercise_media/`, `lib/shared/widgets/exercise_plate/exercise_media_resolver.dart`, `exercise_animation_view.dart` or `lib/shared/providers/exercise_media_provider.dart` contains `storage.from` or `.storage.` and no named argument `bucket:` / `destinationBucket:` (the detector in `delete_account_purges_all_user_buckets_test.dart:85-93` matches `storage.from(`, any other `.storage` use and those two argument names; the bucket name appears in the new code only inside the URL path string) (presence-only; its behavioural twin is the client test above).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** with the WebP magic check (`RIFF` at 0 to 3, `WEBP` at 8 to 11). `refresh once, retry once` is a loop bound of 2, not recursion. On any `refused` or `unreachable`, no exception escapes.
- [ ] **Step 4: Run.** Expected: PASS. **Mutations:** (a) change the loop bound to 3; the 400-then-400 case must FAIL; (b) drop the magic check; the non-WebP-200 case must FAIL. Restore, `cmp`.
- [ ] **Step 5: Run the existing `delete_account_purges_all_user_buckets_test.dart`** untouched. Expected: PASS (nothing in `lib/` names the bucket through `storage.from`; the string `exercise-media` appears only inside a URL path).
- [ ] **Step 6: Commit** `feat(library): Batch M2 Task 6 - one HTTP class reads the private exercise-media bucket with the user's token`.
- [ ] **Step 7 (only if Task 1 recorded S3 = blocked):** add `_fetchViaSignedLink` to the same class: `POST /storage/v1/object/sign/exercise-media/<name>` over plain HTTP with the user's token and body `{"expiresIn": 60}`, then GET the returned link; the web build uses it first. Add the matching `MockClient` case (sign call then GET) and its mutation (swap the order). Commit separately.

### Task 7: Repository and providers

**Files:** Create `lib/core/services/exercise_media/exercise_media_repository.dart`, `lib/shared/providers/exercise_media_provider.dart`; Test `test/contracts/exercise_media_repository_behavioral_test.dart`.

**Interfaces:**
- Consumes `ExerciseMediaClient.fetch`, `ExerciseMediaStore.read/put/has`, `ExerciseMedia` (Task 4).
- Produces `class ExerciseMediaRepository { ExerciseMediaRepository({required ExerciseMediaClient client, required ExerciseMediaStore store, DateTime Function() now, void Function(String event, String message) telemetry}); Future<Uint8List?> ensure(ExerciseMedia media, {bool onDemand = true, Set<String> pinned = const {}}); Future<void> prefetch(List<ExerciseMedia> media, {required Set<String> pinned}); int get bytesToday; Map<String,int> get counters; }`.
- Produces providers `exerciseMediaClientProvider`, `exerciseMediaStoreProvider`, `exerciseMediaRepositoryProvider` (`Provider`, hand-written, no codegen).

Behaviour: `ensure` returns stored bytes at once when present; otherwise ONE in-flight download per `objectName` (concurrent callers share a `Future`); on `fetched` it stores and returns the bytes; on `refused` or `unreachable` it returns null and records a failure time so the next `ensure` for that name within a back-off window (first value 30 s, doubling to 10 min, reset by a success) returns null WITHOUT a request, except that `onDemand: true` always tries once more when the back-off window has passed. Every fetched byte count is added to the day counter keyed by `istDateStr(now())` (`lib/core/utils/ist_date.dart`) and reported with `telemetry('exercise_media_download', '<onDemand|prefetch> <bytes>')` (`ErrorTelemetry.logEvent(String opType, {String? message})`, `error_telemetry.dart:386`). `prefetch` stops when `bytesToday` reaches 60 MB (C6); an on-demand fetch is counted but never blocked by the ceiling (C13).

- [ ] **Step 1: Write the failing test** with a fake client (counts calls, scripted results) and a real store over in-memory bytes. Cases: stored -> zero client calls; missing -> one call, then stored; two concurrent `ensure` of one name -> ONE client call, both get the bytes (Review Focus 3); `refused` -> null, and a second `ensure` inside the back-off -> zero new calls; after the back-off a call is made; `onDemand` after the ceiling is reached still fetches; `prefetch` stops at the ceiling (use a 100-byte test ceiling through a constructor parameter `dailyPrefetchCeilingBytes`); the counter resets on a new IST date; telemetry is called once per fetched file with the byte count; **mirror:** a `refused` result never writes anything to the store and never records the name as "absent" (G3: a later success still works).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS. **Mutations:** (a) remove the in-flight map; the concurrency case must FAIL; (b) treat `refused` as a permanent absence; the mirror case must FAIL; (c) apply the ceiling to on-demand; that case must FAIL. Restore, `cmp` each.
- [ ] **Step 5: Commit** `feat(library): Batch M2 Task 7 - exercise media repository: dedupe, back-off, counters, daily prefetch ceiling`.

### Task 8: Wi-Fi prefetch policy and its trigger

**Files:** Create `lib/core/services/exercise_media/exercise_media_prefetch_policy.dart`; Modify `lib/features/train/screens/train/screen.dart` (`_TrainScreenState`, the Train tab: the screen where the plan is first on screen; its section files are `part of` it, so run `flutter analyze lib/`, not the single file); Test `test/contracts/exercise_media_prefetch_policy_test.dart`.

**Interfaces:**
- Produces `bool shouldBulkPrefetch({required List<ConnectivityResult> connectivity, required bool isWeb})` (pure): true only when `!isWeb` and the list contains `ConnectivityResult.wifi` or `ConnectivityResult.ethernet`.
- Produces `List<ExerciseMedia> planWindowMedia({required List<String> exerciseNames})`-style helper `Set<String> windowObjectNames(...)` is NOT needed: the trigger collects names with `workoutScheduleReadServiceProvider` (`service_providers.dart:114`) calling `getScheduleForDate(DateTime)` (`workout_schedule_read_service.dart:985`) for today and the next 6 days, reading each row's `exercises[].exercise_name` (the shape `_exerciseNamesOfRow` parses, `:869-873`), then `resolveMedia` on each, de-duplicated by `objectName`. The same list is the `pinned` set passed to `prefetch`.

- [ ] **Step 1: Write the failing test.** Cases: `[wifi]` native -> true; `[ethernet]` -> true; `[wifi, mobile]` -> true; `[mobile]` -> false; `[]` -> false; `[other]` -> false; `[none]` -> false; `[wifi]` with `isWeb: true` -> false (C20). A second test (widget or provider level, fake connectivity) proves the trigger: with `[mobile]` no `prefetch` call happens; with `[wifi]` one call with the de-duplicated window (a name repeated across two days appears once).
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** the policy and the one trigger call after the plan list first builds (post-frame, not awaited by the UI, errors swallowed through `ErrorTelemetry.recordNonFatal` like the neighbours). Connectivity is read with `Connectivity().checkConnectivity()`; the prefetch also re-checks when `onConnectivityChanged` fires while the plan screen is alive, and pauses when the list stops matching.
- [ ] **Step 4: Run.** Expected: PASS. **Mutations:** (a) make the empty list return true (fail-open); the `[]` and `[other]` cases must FAIL; (b) drop the `isWeb` term; the web case must FAIL. Restore, `cmp`.
- [ ] **Step 5: Commit** `feat(library): Batch M2 Task 8 - Wi-Fi-only plan-window prefetch (never on web, fail closed)`.

### Task 9: Animation view, still tile, animated sheet

**Files:** Create `lib/shared/widgets/exercise_plate/exercise_animation_view.dart`; Modify `exercise_plate_thumb.dart`, `exercise_plate_sheet.dart`; Test `test/contracts/exercise_animation_view_test.dart`, `test/contracts/exercise_media_fallback_chain_test.dart` (copy the harness of `exercise_plate_widgets_test.dart`: lazy Hive open, path_provider mock, first test renders every font family).

**Interfaces:**
- Produces `class ExerciseAnimationView extends ConsumerStatefulWidget { const ExerciseAnimationView({super.key, required this.media, required this.exerciseName, required this.size, this.autoplay = true, this.fit = BoxFit.contain}); }`. It shows `Image.asset(media.stillAsset)` at once, asks `exerciseMediaRepositoryProvider` for `ensure(media, onDemand: true)` once in `initState` / `didUpdateWidget`, and when bytes arrive cross-fades to the animation decoded at display size (`Image.memory(bytes, cacheWidth: (size * devicePixelRatio).round(), gaplessPlayback: true)`); on null it keeps the still. Under `MediaQuery.disableAnimationsOf(context)` it decodes frame 0 only (`ui.instantiateImageCodec`, `getNextFrame`, `RawImage`) and shows a play button (Wardroom icon button, 44 px minimum touch target) that starts the animation on tap. Stills that fail to load fall through to `ExerciseMonogram`.
- Thumb change (`exercise_plate_thumb.dart:65-94`): face order is (1) `PlateFlags.platesEnabled` false -> monogram; (2) `PlateFlags.animationsEnabled` and `resolveMedia(name) != null` -> the bundled still in the SAME 44 px rounded frame, border and background as the plate tile (C15), `errorBuilder` -> plate if `hasArtwork` else monogram; (3) plate; (4) monogram. The media is resolved in `initState` and `didUpdateWidget` beside `_plate` (G9).
- Sheet change (`exercise_plate_sheet.dart:131-165`): when `PlateFlags.animationsEnabled` and `resolveMedia(exerciseName) != null`, the picture area is ONE `ExerciseAnimationView` in a square `AspectRatio(1)` frame (`size` from `LayoutBuilder`), replacing the START and END drawings; the cues and breathing blocks below are unchanged. Otherwise the existing branches run byte for byte.

- [ ] **Step 1: Write the failing tests.** Fallback chain (thumb): row with media + both flags unset -> an `Image` asset of the still; row with media and `disable_exercise_animations` -> the plate (when `demo_slug`) else monogram; row with media and `disable_exercise_plates` -> monogram (the three combinations of C22); row with plate only -> unchanged; row with neither -> monogram; media row whose still asset is missing -> plate or monogram, no exception. Animation view: a fake repository returning null keeps the still and shows no error box; returning bytes swaps to the memory image (find by key `exercise-animation-playing`); under reduce-motion (`MediaQuery(disableAnimations: true)`) it shows `exercise-animation-frozen` and a play button, and tapping the button swaps to the playing key. Sheet: a media row shows exactly one `ExerciseAnimationView` and no `SvgPicture`; a plate-only row shows today's START/END; `show()` with `disable_exercise_plates` still returns without opening.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement** thumb, view and sheet.
- [ ] **Step 4: Run these tests and the existing `exercise_plate_widgets_test.dart`, `exercise_plate_sheet_test.dart`, `exercise_plate_badge_sites_test.dart`.** Expected: all PASS (the OFF behaviour is today's behaviour).
- [ ] **Step 5 (stills-only platform):** if Task 1 recorded S1 = "no" on a platform, `ExerciseAnimationView` on that platform skips the fetch and renders the still at the large size; add the case with a platform override in the test. Otherwise record "not needed" in the ledger.
- [ ] **Step 6: Mutations:** (a) in the thumb, test `animationsEnabled` before `platesEnabled`-false monogram (swap order); the plates-off combination must FAIL; (b) in the view, ignore `disableAnimationsOf`; the reduce-motion case must FAIL; (c) in the view, swap the swap-in condition so null bytes show an error box; the null case must FAIL. Restore, `cmp` each.
- [ ] **Step 7: Commit** `feat(library): Batch M2 Task 9 - still tiles and the animated sheet, with the fallback chain and both kill switches`.

**Checkpoint A (end of Part A):** the batch is mergeable here. Run the full gate loop for the checkpoint (Task 14 Step 1) only if the split rule fires; otherwise continue.

## Part B: OI-354 hero tile and full-screen viewer

### Task 10: Mockup (founder gate, C18)

**Files:** Create `docs/mockups/2026-10-28-active-workout-hero-tile.html` through the `/ui-mockup` skill.

- [ ] **Step 1:** load `lib/shared/widgets/wardroom/CLAUDE.md` and OI-354's text (`docs/audit/open_issues.md`, `## OI-354`) first (root section 4 discipline-before-skill). Invoke `/ui-mockup`. Show these states side by side with the BEFORE: still, loading, playing, reduce-motion with play button, typing fold (44 px thumb), the full-screen viewer (animation edge to edge, form and cues below, sticky BACK TO WORKOUT), and the superset case (hero on the focused card only, the partner compact). Copy is ENLARGE, BACK TO WORKOUT, and the play button label; the brand check may change "VIEW PLATE" (design section 8).
- [ ] **Step 2: Send the file to the founder (`SendUserFile`) and STOP.** This is a founder gate: Tasks 11 to 13 do not start until the founder approves the mockup in chat. Record `blocked_on_user` if it is not answered in the session.
- [ ] **Step 3: Commit the approved mockup** `docs(library): Batch M2 Task 10 - active workout hero tile and viewer mockup (founder-approved)`.

### Task 11: `isFocused` and the hero tile

**Files:** Create `lib/features/train/screens/active_workout/exercise_hero_tile.dart` (a normal library, NOT a `part`: it imports the providers and `ExerciseAnimationView` and exposes one public widget); Modify `lib/features/train/screens/active_workout/screen.dart` (the `_ExerciseCard(` build site, where `isExpanded: isExpanded,` is passed at about `:670`, passes the new flag) and `exercise_card.dart` (`part of 'screen.dart'`; run `flutter analyze lib/`, the single-file analyze reports clean on a tree that does not compile); Test `test/features/train/log_exercise/exercise_hero_tile_test.dart` beside `card_harness.dart`.

**Interfaces:** `_ExerciseCard` (private, `exercise_card.dart:~64`) gains `final bool isFocused` (default `false`), true only where `exIdx == _effectiveFocusedIndex(data)` (`screen.dart:312-324`); NOT derived from `isExpanded` (`:329-341` marks superset partners expanded too). The test seam `debugExerciseCardHostForTest` (`exercise_card.dart:~1780`, `@visibleForTesting`, the only way a test reaches the private card) gains `bool isFocused = false` and passes it through; tests build the card with that host and the `card_harness.dart` helpers (`SeededNotifier`, `exercise(...)`; fonts before any path_provider mock; Hive-writing taps inside `runAsync`, see `harness_spike_test.dart`). `ExerciseHeroTile({required String exerciseName, required ExerciseMedia media, required VoidCallback onEnlarge, required bool folded})` is the square tile (about half the card width) with a centred ENLARGE overlay.

Rules (C16): the hero shows only when `widget.isExpanded && widget.isFocused && !widget.moveModeActive && PlateFlags.animationsEnabled && resolveMedia(name) != null`; while it shows, the card's 44 px header thumb is hidden; a card for a row with no media keeps the compact header and thumb unchanged; all exercises done -> the last card is focused and its hero shows the still (autoplay false).

- [ ] **Step 1: Write the failing test** (build the card through `debugExerciseCardHostForTest` and `card_harness.dart`, as `test/features/train/log_exercise/log_exercise_card_test.dart` does). Cases: focused + expanded + media -> one hero; expanded + NOT focused (superset partner) -> no hero, thumb present; focused + move mode -> no hero; focused + no media -> no hero, thumb present; `disable_exercise_animations` set -> no hero, today's header; a screen with a two-exercise superset where both have media -> exactly ONE `ExerciseAnimationView` in the tree with autoplay; all done -> hero present with autoplay false.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run these and the existing active-workout card tests.** Expected: PASS.
- [ ] **Step 5: Mutations:** (a) derive the hero from `isExpanded` instead of `isFocused`; the superset case must FAIL; (b) drop the `moveModeActive` term; the move-mode case must FAIL. Restore, `cmp`.
- [ ] **Step 6: Commit** `feat(library): Batch M2 Task 11 - OI-354 hero tile on the focused active-workout card only`.

### Task 12: Keyboard fold

**Files:** Modify `exercise_card.dart` (or the hero tile); Test `test/contracts/exercise_hero_fold_test.dart`.

- [ ] **Step 1: Write the failing test:** with `MediaQuery(viewInsets: EdgeInsets.only(bottom: 300))` the hero shows `folded: true` (the 44 px thumb in its place); with `viewInsets.bottom == 0` it is unfolded. The fold does not depend on `_logMode` (C21): the case runs with log mode on and off.
- [ ] **Step 2 to 4:** run (FAIL), implement `MediaQuery.viewInsetsOf(context).bottom > 0` on the focused card only, run (PASS).
- [ ] **Step 5: Mutation:** tie the fold to `_logMode`; the log-mode-off case must FAIL. Restore.
- [ ] **Step 6: Commit** `feat(library): Batch M2 Task 12 - the hero folds while the keyboard is open`.
- [ ] **Device check owed (not a unit test):** the tapped set field stays visible and under the finger; if it jumps, the fold shrinks the tile instead of removing it (C21). Record in the ledger as `blocked_on_user` until a device pass.

### Task 13: Full-screen viewer and routing (C17)

**Files:** Create `lib/features/train/screens/active_workout/exercise_media_viewer.dart`; Modify `exercise_card.dart` (the header thumb `onTap`, `:1105-1118`), the hero's ENLARGE, `coaching_content_panel.dart:134-147` (the "VIEW PLATE" door); Test `test/contracts/exercise_media_viewer_routing_test.dart`.

**Interfaces:** `ExerciseMediaViewer.show(BuildContext, String exerciseName)` pushes a full-screen route (not a bottom sheet): the `ExerciseAnimationView` edge to edge, the form cues and breathing cue below (reuse the sheet's cue parsing; extract it to a shared function `exerciseCuesOf(Map<String,dynamic>?)` in the same commit so there is ONE copy, and repoint `exercise_plate_sheet.dart`), a sticky BACK TO WORKOUT. A new function `showExercisePicture(BuildContext, String name)` decides: `PlateFlags.animationsEnabled && resolveMedia(name) != null` -> viewer, else `ExercisePlateSheet.show` (which itself returns at once when plates are off). The three active-workout doors call `showExercisePicture`. The plan list and calendar sites keep `ExercisePlateSheet.show` unchanged.

- [ ] **Step 1: Write the failing test:** active-workout thumb tap, hero ENLARGE and VIEW PLATE each open the viewer for a media row and the sheet for a plate-only row; the plan-list tile and the calendar tile open the sheet even for a media row; with `disable_exercise_animations` set every door opens today's sheet; with `disable_exercise_plates` set nothing opens; BACK TO WORKOUT pops to the workout; the viewer shows the cues the sheet shows for the same row (shared function).
- [ ] **Step 2 to 4:** run (FAIL), implement, run (PASS), plus `exercise_plate_sheet_test.dart`. `test/contracts/exercise_plate_badge_sites_test.dart` WILL go red: it requires the stripped source of `exercise_card.dart` (lines 23 to 25) and `coaching_content_panel.dart` (lines 43 to 45) to contain `ExercisePlateSheet.show`, and those two files now call `showExercisePicture`. REPOINT, never loosen: for those two files require `showExercisePicture` instead, and add one case asserting that the stripped source of the file defining `showExercisePicture` contains `ExercisePlateSheet.show` (so the fallback door still exists); `expandable_day_card.dart` and `day_detail_sheet.dart` keep the original assertion. Run `flutter analyze lib/`.
- [ ] **Step 5: Mutation:** route the plan-list tile through `showExercisePicture`; the "plan list opens the sheet" case must FAIL. Restore.
- [ ] **Step 6: Commit** `feat(library): Batch M2 Task 13 - full-screen viewer and picture-door routing on the active workout`.

## Close-out

### Task 14: Registry, docs, gates, reviews, merge

- [ ] **Step 1: Full gate loop (root 4.12.8), exactly what pre-push runs:** `flutter analyze --no-fatal-infos` (the WHOLE project), `TZ=Asia/Kolkata flutter test` (VPS) or the Windows equivalent, `sh scripts/pre-commit.sh`. Read the counts, not the colours. Fix anything red before dispatching a reviewer.
- [ ] **Step 2: SoT registry.** Add concept `exercise_media_delivery` to `docs/sot_registry.yaml` (writer: `ExerciseMediaRepository.ensure` into `ExerciseMediaStore`; reader: `ExerciseAnimationView`; `behavioral_test_path: test/contracts/exercise_media_repository_behavioral_test.dart`, `contract_test_path: test/contracts/exercise_media_client_behavioral_test.dart`). Gate 42 resolves the cited paths.
- [ ] **Step 3: Docs.** `docs/operations/EXERCISE_MEDIA.md` section 9 (replace "the trap for Batch M2" with what shipped, the findings of Task 1, the kill switches, the cap and ceiling values); OI-440 and OI-354 (state, `Verified:` with this date and the method); nested `CLAUDE.md` for `lib/shared/widgets/exercise_plate/` if one exists and `lib/core/services/CLAUDE.md` (one row each, only if a feature contract changed). Diagnose-docs are not needed (no `fix(...)` commit); a feature commit is not matched by rule 22.
- [ ] **Step 4: Plan-review record** `docs/plan-reviews/library-batch-m2.md` (frontmatter between `---` lines, `review_rounds: ≥2`, `ground_truth_verified: true`, bare `verdict: converged`, `bpass: accepted`); name check `feedback_plan_review_filename_must_use_full_recordslug.md`; grep the CITED file before the merge (`feedback_plan_review_record_frontmatter_format.md`).
- [ ] **Step 5: B-pass** with `/code-review` (fresh Sonnet), file `docs/reviews/library-batch-m2-bpass.md`.
- [ ] **Step 6: One push, one PR, merge** with `sh scripts/safe_pr_merge.sh <pr>`; right after `gh pr create`, `get_status` then `set_monitor` (auto_fix + address_comments true). Then retire the worktree (root 4.13.8) and write `project_library_batch_m2_app_delivery.md` (retrospective) plus the `MEMORY.md` pointer and archive the in-flight file.
- [ ] **Step 7: Owed after merge, on the board, not in this plan:** the device check (fold, memory, playback on a low-end phone), OI-443 data step (148 pairs, live upload needs the founder's go, seed bump), the 11 held pairs, the picture check of the 529, OI-444, OI-445.

## Closure

| Item | Terminal state | Where |
|---|---|---|
| Tasks 2 to 9, 11, 13, 14 | `closed_in_commit` | the task commits |
| Task 1 phone step | `blocked_on_user` until the founder (or an emulator) runs it | findings file |
| Task 10 mockup approval | `blocked_on_user` | chat |
| Task 12 device check of the fold | `blocked_on_user` | ledger |
| OI-443 data step, 11 held pairs, 529 picture check | `upstream_blocked` / `blocked_on_user` | OI-443 |
| OI-444, OI-445 | `blocked_on_user` | the board |

## Self-review (author, 2026-10-28)

- Spec coverage: C1 (Task 9), C2 (Task 2), C3 (Task 9), C4 (Tasks 6, 7), C5 (Task 5), C6 and C13 (Tasks 7, 8), C7 (G5), C8 (Task 5), C9 and C22 (Tasks 3, 9, 11, 13), C10 and C11 (Task 9), C12 (Task 6), C14 (Tasks 1, 6, 9), C15 (Task 9), C16 (Task 11), C17 (Task 13), C18 (Task 10), C19 and C23 (Task 14 Step 7), C20 (Task 8), C21 (Task 12).
- Honest limit: the widget tests prove the swap, the ladder and the reduce-motion branch; that the animation actually MOVES is observed in Task 1 and on a device, not proved by a unit test (there is no animated WebP fixture in the repository).
- Type consistency: `ExerciseMedia.objectName` and `.stillAsset` (Task 4) are the names Tasks 7, 8, 9 and 11 use; `MediaFetchOutcome` (Task 6) is the type Task 7 branches on.
