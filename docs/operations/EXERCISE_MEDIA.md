# Exercise media: the animations, their table and their private bucket

> Batch M1 (diagnose `b4e7a2`, plan `docs/plans/2026-10-27-library-batch-m1-media-data.md`). This file is the operator's
> reference: what exists, who can read it, the commands, the maintenance recipes and the things nobody has observed yet.
> The app side is Batch M2 (OI-440). M2a (2026-10-31) reads the media fields: the calendar day sheet and the active-workout picture sheet
> fetch ONE animation when an exercise is opened, only for a logged-in account. The Wi-Fi bulk prefetch (M2c) is not shipped. See section 9.

## 1. What exists

| Piece | Where | Role |
|---|---|---|
| The animations | the founder's folder `assets/exercise animations/forgetrainer_animations/gifs/wardroom customized gifs/` (untracked): `webp-720/` (animated, 720 x 720), `thumbnails-192/` (static, 192 x 192), `generation-ledger.json` | The source files. 924 exist; 616 are mapped to library rows (253,550,820 bytes, the largest 987,558). Never committed. |
| The provenance table | `scripts/data/library_media_v16.json` | One slug per animation, which library row uses it, every hash and size, and where the file lives on the founder's disk. Built by a tool that reads the real files; a hash is never typed by hand. |
| The builder | `scripts/build_library_media_v16.js` (`--write`, `--check`, `--prune-only`) | Writes and checks the table. Needs the folder, except `--prune-only`. |
| The library fields | `assets/data/exercise_library.json` (v16), written by `scripts/add_library_batch_c_v15.js` (its media stage) | `media_slug`, `media_version`, `media_source` on the 617 mapped rows. |
| The seed | `lib/core/services/seed_service.dart` `_exerciseLibraryVersion = 16` | Installs re-seed the library once on the next launch. |
| The bucket | Storage bucket `exercise-media` on project `dedsavbjuwgarrhphgnl`, created by the migration `165_exercise_media_bucket.sql` (applied 2026-10-27 22:33 IST) | PRIVATE, `image/webp` only, 1,500,000 bytes per object, one read policy. |
| The upload tool | `scripts/upload_exercise_media.js` | Dry run, canary, upload, verify, sign, delete, probes. Pinned to this project and bucket. |
| The proofs | `test/sql/exercise_media_bucket_live_verify.sql`, `test/sql/exercise_media_bucket_wrong_policies_rehearsal.sql`, `test/contracts/exercise_media_bucket_private_test.dart`, `scripts/exercise_media_rehearsal_sql.js` | The role probe and catalog check on the live database; the rehearsal that shows they go red on five wrong setups (including a policy on `storage.buckets` that could flip the bucket public); the text pins; the composer that builds the exact SQL the rehearsal sends (`node scripts/exercise_media_rehearsal_sql.js --file1` or `--file2`, to stdout, nothing written). |

The three library fields are **absent, never `null`, and travel together**: a row carries all three or none, appended last in the order
`media_slug`, `media_version`, `media_source`. `media_source` is the constant `wardroom`. The object name is
`<media_slug>_v<media_version>.webp`; the slug is `<4-digit gif number>-<kebab(name)>`, for example `0103-barbell-standing-ab-rollout`.
In M1 `media_version` is 1 for every file, and a changed file under an existing slug is refused by the builder (objects are immutable).

## 2. Who can read the files (the access model)

The founder's rule: **only a person who has installed the app and logged in can download the animations from the bucket.** Two decisions refine it, both made on purpose (design calls G12 and C8):

- **G12: the stills are readable without a login.** The 616 first frames (192 x 192) are bundled in the app (`assets/exercise_stills/`), so anyone who has the app sees them, signed in or not.
- **C8: a cached animation survives sign-out.** A file already fetched stays on the device (native: files under the app's support folder, `exercise_media/`; web: the Hive lazy box `exerciseMediaBlobs`), and the sign-out wipe (`clearAllData()`) deliberately does not touch it, so a later person on that device can see it. No login is needed to play a file that is already cached; every download still needs one. (The kill-switch flags live in `configBox`, which that wipe DOES clear: section 9.)

- The bucket is **private** (`public = false`). The public route `/storage/v1/object/public/exercise-media/<name>` serves nothing.
- ONE policy exists on `storage.objects` for this bucket, `exercise_media_authenticated_read`: `FOR SELECT TO authenticated`, this bucket only, and only when the JWT is not an anonymous sign-in (`coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false`). There is no policy for `anon` and none for writes.
- The upload tool uses the service-role key, which bypasses row level security. The app never writes here.
- A logged-in user reads with their JWT on `/storage/v1/object/authenticated/exercise-media/<name>` or through a signed URL.
- **Not stopped:** a scraper who signs up (sign-up is open). The app has NO per-account cap: access design A, chosen for M2a, lets any logged-in, non-anonymous account read directly. The controls for that are CAPTCHA at sign-up (OI-445), a usage alert with the Spend Cap decision (OI-444) and, until M2c, on-demand-only delivery plus the session-counter event (section 3). OI-444 and OI-445 stay launch gates.
- **A signed URL is a bearer token:** whoever holds it can fetch until it expires. `--sign` therefore refuses an expiry above 900 seconds and prints the URL to standard output only (never to the report).
- **At the database-role level.** The role probe proves the policy for the roles `anon` and `authenticated` and for a hand-built anonymous-session claim. That Storage maps an anon-key JWT to the role `anon`, and an anonymous sign-in to `is_anonymous: true`, is documented behaviour and UNVERIFIED here; Task 9.2 of the plan sends one real request with the project's anon key and records the status below (section 8).

### The blind spot of the text pins

`test/contracts/exercise_media_bucket_private_test.dart` pins the migration text and every other migration that **names** the bucket or the policy. It has a **blind spot**: a later migration that does not name the bucket (an unscoped policy on `storage.objects` for `anon`, a `GRANT`, an `UPDATE` of `storage.buckets` without the id) is not caught by text. The guard for that class is the role probe: **re-run `test/sql/exercise_media_bucket_live_verify.sql` after any change to a storage policy or grant**, and read its `verdict=` line. The migration header and the test header say the same. Two limits of the probe itself: its write legs run as `authenticated` only, so a write grant to `anon` alone is carried by the `unscoped_write_grants` line alone (read that line too, not only the verdict); and that line is a heuristic over the deparsed policy text (no bucket predicate, a policy naming `exercise-media`, or a negation: `<>`, `!=`, `!~`, `NOT `, `IS DISTINCT`, `~~`), so a range, a positive regex (`~`, `~*`, `SIMILAR TO`) or a function of `bucket_id` that reaches the bucket escapes it.

## 3. The numbers that matter for cost

| Quantity | Value |
|---|---|
| Files mapped / total bytes / largest | 616 / 253,550,820 (253.55 MB) / 987,558 |
| One full-library download | 253.55 MB of **uncached** egress (a private object caches worse: each signed URL is its own cache key) |
| Free plan | 1 GB storage and 5 GB uncached + 5 GB cached egress a month, shared by every bucket: about 19 full downloads a month |
| Pro plan | 250 GB + 250 GB: about 985 full downloads; overage about $0.09 per GB uncached, $0.03 cached |
| Spend Cap (Pro) | ON: over the quota the organization is restricted for **every** user; OFF: the overage is billed. The founder chose OFF with a usage alert (OI-444). |

Until M2c ships there is no prefetch budget and no per-account cap. The control on the egress side is **on-demand-only delivery** (one file, only when a person opens that exercise's sheet) plus the **session counter**: the app sends one `exercise_media_session_over_budget` event the first time a session has downloaded 100 MiB (about 250 files at the average animation size of 412 KB; the query is `select * from client_errors where op_type = 'exercise_media_session_over_budget'`; the row is LOW priority, so a rate-limit cooldown can drop it) and OI-444's usage alert. Before the upload, Task 9.1 of the plan reads the storage total and stops if the total plus 260 MB exceeds 900 MB.

Accepted limits of the app side (each is a decision, none is a defect to fix in M2a): an unwritable store re-downloads the file on every open (after one failed write the app skips the write for 5 minutes); a token that expired while the phone was offline costs one failing refresh per open; recency bumps are persisted only together with a later change to the store; a failing file delete leaves an orphan on disk that the next launch re-adopts as the newest entry, so disk use can exceed the cap, bounded only by the person's taps; after a failed store load the next change persists an index holding only the new entries (earlier blobs become orphans, re-adopted at the next launch); the session alert and the two first-outcome events (`exercise_media_first_refused`, `exercise_media_first_unreachable`) are LOW-priority rows that a rate-limit cooldown can drop; a second `ensure` can download a file once more in a window of milliseconds; and on web `followRedirects: false` is not honoured by the browser adapter (the browser drops `Authorization` on a cross-origin redirect).

## 4. Commands

Run from the repository root with Node 20 or newer. Everything that sends a request to the project needs the service-role key (section 5); the dry run (the default mode) and `--probe-control` need none.

```bash
# the table
node scripts/build_library_media_v16.js --check            # byte equality with the committed table (needs the folder)
node scripts/build_library_media_v16.js --write            # rebuild after the folder, the map or the ledger changed
node scripts/build_library_media_v16.js --prune-only --write   # no folder needed: drop rows absent from the library, flip unused files to unmapped
# the library
node scripts/add_library_batch_c_v15.js --check            # the importer's byte-equality check (includes the media stage)
node scripts/add_library_batch_c_v15.js                    # write the library (media stage on by default)
# the upload tool (see its header for every flag)
node scripts/upload_exercise_media.js                      # DRY RUN: prints the plan, hashes all 616 local files, sends nothing
node scripts/upload_exercise_media.js --probe-key          # which key names the Management API returned (never the key)
node scripts/upload_exercise_media.js --canary --execute --report <path>
node scripts/upload_exercise_media.js --execute --report <path>
node scripts/upload_exercise_media.js --verify
node scripts/upload_exercise_media.js --sign <name,name> --expires 300
node scripts/upload_exercise_media.js --probe-control avatars/<name>
```

- `--report <path>` must lie **outside the repository and outside the primary checkout** (compared after `realpath`, case-folded on Windows and macOS). A missing report changes nothing: every run re-checks the bucket.
- `--execute` is required for any request that changes the bucket. Without it the upload and canary modes print the plan and send nothing; the two delete modes refuse (exit 2) unless `--execute` and `--confirm-bucket exercise-media` are both given.
- The report path is proved writable **before** the first request (a delete mode writes its report last, so an unwritable path would otherwise surface after the DELETE). The check creates and removes an empty file when the report does not exist yet, removes exactly the directories it had to create (on a failed open as well as on success; an empty directory that was already there is never touched), leaves an existing report untouched and refuses a report path that is a symbolic link. A delete mode whose request is cut off still writes the report of what it had done, with `stoppedBy` (the error text, redacted) and, for `--delete-object`, `inFlight`: `{name, deleteStatus}` of the object being deleted when the connection died, with the DELETE's status if it had been answered (`null` when the DELETE itself was cut off, which the server may or may not have executed; `--delete-bucket` records the same doubt as `emptyStatus: null` / `deleteStatus: null`).
- A report is passed through the secret redactor before it is written.
- Upload is `x-upsert: false`. An object that exists with the same sha256 is counted `alreadyEqual` and not re-sent; one with a different sha256 stops the run naming the slug; a quota-style answer (413, or a body naming a quota or limit) stops the run. A cut run is re-run unchanged.
- The upload and verify scope is the `active` files only. `unmapped` and `taken_down` files are never uploaded, verified or signed.
- `--verify` and the canary also send two requests **with no credential** (the public route, and the authenticated route with no Authorization header). Either answering 200 stops the run naming `readable without a login`. Anything other than a plain refusal (400, 401, 403, 404) also stops the run, saying `privacy is NOT shown`: a network error, a 429, a 5xx, a redirect or a 206 proves nothing about privacy and is never counted as private. The second probe is not a policy test (a missing header is refused before row level security is consulted); the policy is proved by the role probe.
- `--verify` against a table with no `active` file is a stop, not a clean "0 of 0".
- `--probe-control <bucket/name>` (bucket `avatars` or `banners`) sends one GET to the public route of a bucket that really is public and prints only the status. It is the positive control that makes the non-200 of the exercise-media probe mean something.
- `--delete-object` refuses the object of an `active` file and, after the DELETE, HEADs the name **with the key** (a keyless HEAD of a private object answers 4xx and would read as gone); a 200 may be CDN lag, so it waits 90 seconds and HEADs again. `--delete-bucket` empties the bucket through the Storage API, then deletes it; it has only ever run against the fake server and is never run live except as the rollback.

## 5. The service-role key

The tool resolves the key in this order and never prints, logs or writes it:

1. the environment variable `SUPABASE_SERVICE_ROLE_KEY`, if set (set it in your shell for the run only);
2. otherwise the Management API (`GET /v1/projects/dedsavbjuwgarrhphgnl/api-keys?reveal=true`) with the access token read from the token **file** (`--token-file`, or the file `.claude/token_path.js` `resolveTokenFile` picks). The `SUPABASE_ACCESS_TOKEN*` variables are **not** read.

A key that is a JWT must carry `ref == dedsavbjuwgarrhphgnl`, or the tool refuses it. `--probe-key` runs step 2 and prints key names, lengths, the HTTP status and `ref ok`. If `SUPABASE_SERVICE_ROLE_KEY` is set in the shell it prints `the Management API was NOT contacted` and probes nothing, so unset the variable to probe the endpoint. The endpoint's behaviour is UNVERIFIED until Task 9.1 records it (section 8); if it answers otherwise, set the environment variable. The git child that finds the primary checkout never receives the service-role key or an access token (`.claude/token_path.js` and `scripts/supabase_token_path_lib.dart` drop them from its environment). Inventory row: `docs/operations/SECRET_INVENTORY.md`.

## 6. Maintenance recipes (the table, the library and the bucket move together)

The table is maintained by recipes, not by hand edits. The shipped media map is never edited by these (the scope script pins its hash); a map edit is Batch M1b's `remap`. CI legs R10 (a) to (h) of `test/contracts/library_media_table_test.dart` check the links; between steps they are red by design, and the PR merges only after the last importer run.

**Hold a mapped row** (the row leaves the library; its file becomes `unmapped`)
1. Set `hold` on the row in `scripts/data/library_batch_c_source.json`.
2. `node scripts/add_library_batch_c_v15.js --media none --library <temp copy>` (`--library` is mandatory with `--media none`).
3. `node scripts/build_library_media_v16.js --prune-only --library <temp copy> --write`.
4. `node scripts/add_library_batch_c_v15.js` (default table).
5. Run the media and C1 contract tests.

**Release a held row** (the row enters the library with its keys; its file becomes `active`)
1. Edit the source (remove the hold; see OI-437 for the other C1 steps).
2. `node scripts/add_library_batch_c_v15.js` (the row enters unmapped; no refusal).
3. `node scripts/build_library_media_v16.js --write` (needs the folder; the file becomes `active`).
4. `node scripts/upload_exercise_media.js --execute --report <path>`, then `--verify`.
5. `node scripts/add_library_batch_c_v15.js` again (the row gets its three keys).
6. Run the tests; bump `_exerciseLibraryVersion` if installs must pick the change up.

**Take down a file** (stop serving it)
1. Add its slug to `_meta.taken_down` in the table.
2. `node scripts/build_library_media_v16.js --write` (its rows are omitted; its status becomes `taken_down`).
3. `node scripts/add_library_batch_c_v15.js` (the keys leave the library).
4. `node scripts/upload_exercise_media.js --delete-object <object name> --execute --confirm-bucket exercise-media --report <path>`.

A takedown stops **new** downloads (the CDN entry is invalidated within about 60 seconds); it does not recall copies already on a device, and it does not purge a cached response whose signed token has not expired.

**Old rows (E ids).** The 285 original rows get animations only from the founder's export, through `node scripts/build_library_media_v16.js --old-rows <path> --write` (a path argument only; the file lives outside the tracked directories). Schema:

```json
{"entries": [{"id": "E050", "gif": "0103", "equipment_checked": true}]}
```

Every entry needs `equipment_checked: true` and a `gif` that has a ledger entry. The builder records the export's sha256, the number of `E` rows written and the number dropped for a taken-down slug in `_meta.old_rows`. The 60 rows whose name equals a Wardroom name are only a draft for the picker: a name says nothing about equipment. See OI-443.

## 7. The bucket migration and its proofs

1. **The migration** `supabase/migrations/165_exercise_media_bucket.sql` is one `DO` block: lock budget, the bucket row (`ON CONFLICT (id) DO UPDATE`), `DROP POLICY IF EXISTS` and `CREATE POLICY exercise_media_authenticated_read`, and a read-back self-check. It was a draft at `docs/plans/library-batch-m/exercise_media_bucket.sql.draft` until its live apply (Gate 14 fails any unledgered file in `supabase/migrations/`); the apply commit moved it and added the ledger entry (`backups/applied_migrations.json`, migration 165). The rehearsal composer and the privacy contract read whichever of the two paths exists, never both.
2. **The rehearsal** (before the apply, aborting, nothing persists; run it off-peak with no sign-in or test session active, because the policy DDL holds table locks until each block ends): `node scripts/exercise_media_rehearsal_sql.js --file1` prints the live-verify file with the migration body inserted twice at its marker comment, comment-stripped, as ONE call; `--file2` prints the wrong-policies file. FILE 2 runs five wrong setups (`TO public`, no `is_anonymous` clause, no bucket scope, `FOR ALL`, and a `FOR UPDATE` policy on `storage.buckets`); each is RED only when its quadruple, its write slots AND its catalog string equal its row, and the pass criterion is `mutated: 5 of 5 reddened` with `verdict=PASS` (the baseline must also read its row). The result lines are `VERIFY_RESULTS` followed by `key=value` lines; compare lines, do not read them.
3. **After the apply and again after the upload:** run the live-verify file alone; expect `verdict=PASS`. The wrong-policies file is **rehearsal only** and is never run after the apply (its first statement raises if the bucket exists).
4. **Rollback is the Storage API, not SQL:** drop the policy (one statement, in the migration's rollback comment), then `node scripts/upload_exercise_media.js --delete-bucket --execute --confirm-bucket exercise-media --report <path>`.
5. **The dashboard is the inventory.** There is no inventory tool for the bucket's contents; Supabase Dashboard → Storage → `exercise-media` is the list. `--verify` checks the 616 objects the table names, not extras.

## 8. What the live project answered (observed 2026-10-27, Task 9 of the plan)

These were assumptions of the tool and the plan until the canary and the bulk upload ran on project `dedsavbjuwgarrhphgnl`. Each has an observed answer now; the tool still stops if one of them changes.

| Assumption | Observed |
|---|---|
| The Management API key endpoint answers with a revealable `service_role` key | HTTP 200; key names `anon` (208 characters), `service_role` (219), `default` (46), `default` (41); `ref ok` (`--probe-key`) |
| `GET /storage/v1/object/authenticated/exercise-media/<name>` with the key reads a private object, and HEAD answers its length | GET 200 with an equal sha256 for the canaries and for all 616 files; HEAD length equals the table (`--verify`: 616 of 616 match) |
| `POST /storage/v1/object/sign/exercise-media/<name>` returns a `signedURL` and its GET reads the object | sign 200; signed GET 200 with an equal sha256 |
| The signed response carries `cache-control` | **No.** It carries `ETag`, `Expires` (the link's own expiry), `Last-Modified`, `Accept-Ranges: bytes` and `Access-Control-Allow-Origin: *`, and no `Cache-Control`, whichever form the object was uploaded with (all three forms tried). The stored object metadata keeps `private, max-age=31536000, immutable` (one distinct value across the 616). The founder agreed to keep the default; the header is not load-bearing because the app keeps files on the device under their object name (M2) |
| A duplicate POST answers 409, or 400 with `statusCode "409"` | HTTP 400 with body `{"statusCode":"409","error":"Duplicate","message":"The resource already exists","code":"KeyAlreadyExists"}` |
| An absent object answers a non-200 HEAD on the authenticated route | HEAD with the key answers **400** (not 404), before the upload and after a DELETE that answered 200 |
| The public route and the authenticated route with no Authorization answer non-200 | Both 400, on the three canaries, on the first of the 616 (`--verify`) and, from the built-in browser pane with no credentials, on three more names |
| The public-route URL shape answers 200 for a public bucket | 200 (`--probe-control` on a banner of the `banners` bucket) |
| An anon-key request to the authenticated route answers non-200 | 400 with body `statusCode "404"`, `Object not found` (the policy hides the object from the `anon` role); the public route answers `Bucket not found`. One request each, with the project's public anon key |
| Anonymous sign-ins are off on the live project | Off (`external_anonymous_users_enabled` false, read at Task 8.3), so the policy's second clause is defence in depth today |
| An animated WebP decodes and animates in a browser | Three files opened from signed links in the built-in browser pane and decoded with `ImageDecoder`: 123,878 bytes / 12 frames, 493,984 bytes (the shared-slug file) / 12 frames, 987,558 bytes (the largest) / 24 frames; all 720 x 720, animated, first and last frame differ. **Not yet seen on a device** (M2) |

Two consequences for M2 (also on OI-440): a forbidden read and an absent object both answer HTTP 400 on the authenticated route, so status alone does not separate "no such file" from "not allowed" and the client treats a refused read of a mapped row as retry-later, not as "no animation"; and nothing on a signed response tells the client how long to keep the bytes, so it caches by object name (the name carries the version, `_v<n>`, so a name never changes content).

Traffic of the first full run: the upload was about 0.25 GB into Storage, the `--verify` about 0.25 GB of egress, the playback check a few MB; against the Free allowance of 5 GB a month that is about a twentieth. Storage now holds 258,172,324 bytes in 639 objects (the bucket 618: 616 animations and the two canary objects `canary-1_v0.webp` and `canary-2_v0.webp`, never referenced; `--verify` checks only the 616).

## 9. What Batch M2a shipped (the app side), and the trap it avoided

**Shipped (2026-10-31, plan `docs/plans/2026-10-28-library-batch-m2-app-delivery.md`).** The calendar day sheet and the active-workout picture sheet show the WebP animation of an exercise that has one; a tile (the 44 px thumb) shows the bundled still. Opening one exercise fetches that ONE file, on any connection, for a logged-in, non-anonymous account only; there is no subscription gate (C7). The Train tab plan list shows no pictures. **Bulk prefetch on Wi-Fi is NOT shipped (M2c, OI-440's second half).**

- **Access design A.** The app reads the authenticated route directly (`GET /storage/v1/object/authenticated/exercise-media/<name>` with the user's access token) through ONE Dio client (`lib/core/services/exercise_media/exercise_media_client.dart`). It never calls `storage.from`, so the trap this section used to describe does not arise: `test/contracts/exercise_media_reads_without_storage_from_test.dart` pins that none of the animation files uses `storage.from`, `.storage.`, `bucket:` or `package:http`, and that none of them gates on the subscription. The signed-link design (an Edge Function issuing short-lived links, counted per account) was not chosen; `exercise_media_authenticated_read` stays.
- **The cache.** Native: files under the application support folder (`exercise_media/`), 150 MB; web: the Hive lazy box `exerciseMediaBlobs`, 60 MB. The store keeps its own index inside its byte store, so clearing the Hive boxes cannot desync it; eviction is by recency (the recency of a cache hit is written together with the next change to the store, so a process killed before that change falls back to the last written order: an accepted limit, section 3). A cached file survives sign-out (C8) and the stills are readable without a login (G12): both are decisions, section 2.
- **Kill switches (both default ON, the flag turns them OFF).** `configBox['disable_exercise_animations'] = true` stops every download and every animated view, and takes the bundled still tile with them (the still is an animation surface, design call C22), so the faces are what they were before M2a: the plate where the row has a drawing, else the monogram. The 617 rows with an animation have no drawing, so with only this switch set their tiles show the monogram and their sheet says NO DRAWING YET; `configBox['disable_exercise_plates'] = true` turns the plates off too, and animations follow it. Both are read at the sink on every call. **`clearAllData()` clears `configBox`, so a sign-out wipe also clears these flags** (G4); a build that must stay off ships the compile-time platform switches instead (`kWebAnimationsFetchEnabled`, `kNativeAnimationsFetchEnabled` in `exercise_media_repository.dart`, both `true` today).
- **Anonymous sessions** read nothing: the client answers `unauthenticated` with zero requests, and that answer never arms a per-name back-off the next account would inherit.
- **A refused read is retry-later.** A forbidden read and an absent object both answer HTTP 400, so a refusal never means "this exercise has no animation": the name is retried after 10 seconds, and only a file the image codec cannot decode is banned for the session.
- **Hardened in the B-pass (2026-10-31).** A response that reports more than the 1.5 MB WebP cap, as received so far or as declared, is cancelled while it streams and counts as refused (the whole body is no longer buffered first). A clock stepped backwards never freezes a cooldown: a stamp in the future is expired, for the 10 s back-off, the 5 min unwritable back-off and the 60 s token-refresh cooldown. An `evict` that runs while a download or a store read is under way is not undone by it (the ban is checked again after both). An index file damaged into invalid UTF-8 reads as an unreadable index, so every blob is re-adopted. The view decodes again, wider, when the sheet grows by more than 1.25x while it is open (never narrower), starts the frozen-frame decode when `autoplay` turns off, evicts a provider that a second answer replaces, treats an unbounded size as the widest decode, and keeps the still on screen until the animation's first frame is decoded.
- **What was observed.** Task 1 findings: `docs/audit/library-m2-spike-findings.md`. S7 is observed (all 924 files in the folder: RIFF size consistent, loop count 0 = infinite). S1 (animation plays on a phone and in Chrome), S2 and S4 (a real user token's read and refusal statuses), S3 and S3b (web CORS), S6 (memory of the 48-frame file) and **S8 (does the web store persist across a reload)** are NOT observed: they need a QA login and a phone, and are owed in the post-merge device and web check. Until S8 is observed, "the second open works offline" on web is unverified. Web ships the direct GET; a CORS refusal there ends as `unreachable` and the still stays.
- **Not shipped.** The Wi-Fi bulk prefetch and its budget (M2c); the hero tile, the full-screen viewer and the keyboard fold (M2b, OI-354); the per-account cap (access design A has none). Until M2c, section 3 names the egress controls.

See OI-440.

## 10. Related board entries

OI-437 (the picture check of the shipped rows and the held-row release steps), OI-440 (M2, app delivery), OI-441 (M1c, intake and versioning), OI-442 (animations created outside the repository), OI-443 (the old-rows export), OI-444 (Supabase plan, Spend Cap, usage alert), OI-445 (CAPTCHA at sign-up).
