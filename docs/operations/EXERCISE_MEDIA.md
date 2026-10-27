# Exercise media: the animations, their table and their private bucket

> Batch M1 (diagnose `b4e7a2`, plan `docs/plans/2026-10-27-library-batch-m1-media-data.md`). This file is the operator's
> reference: what exists, who can read it, the commands, the maintenance recipes and the things nobody has observed yet.
> The app side is Batch M2 (OI-440); nothing in `lib/` reads the media fields yet.

## 1. What exists

| Piece | Where | Role |
|---|---|---|
| The animations | the founder's folder `assets/exercise animations/forgetrainer_animations/gifs/wardroom customized gifs/` (untracked): `webp-720/` (animated, 720 x 720), `thumbnails-192/` (static, 192 x 192), `generation-ledger.json` | The source files. 924 exist; 616 are mapped to library rows (253,550,820 bytes, the largest 987,558). Never committed. |
| The provenance table | `scripts/data/library_media_v16.json` | One slug per animation, which library row uses it, every hash and size, and where the file lives on the founder's disk. Built by a tool that reads the real files; a hash is never typed by hand. |
| The builder | `scripts/build_library_media_v16.js` (`--write`, `--check`, `--prune-only`) | Writes and checks the table. Needs the folder, except `--prune-only`. |
| The library fields | `assets/data/exercise_library.json` (v16), written by `scripts/add_library_batch_c_v15.js` (its media stage) | `media_slug`, `media_version`, `media_source` on the 617 mapped rows. |
| The seed | `lib/core/services/seed_service.dart` `_exerciseLibraryVersion = 16` | Installs re-seed the library once on the next launch. |
| The bucket | Storage bucket `exercise-media` on project `dedsavbjuwgarrhphgnl`, created by the migration `NNN_exercise_media_bucket.sql` | PRIVATE, `image/webp` only, 1,500,000 bytes per object, one read policy. |
| The upload tool | `scripts/upload_exercise_media.js` | Dry run, canary, upload, verify, sign, delete, probes. Pinned to this project and bucket. |
| The proofs | `test/sql/exercise_media_bucket_live_verify.sql`, `test/sql/exercise_media_bucket_wrong_policies_rehearsal.sql`, `test/contracts/exercise_media_bucket_private_test.dart` | The role probe on the live catalog; the rehearsal that shows the probe goes red on wrong policies; the text pins. |

The three library fields are **absent, never `null`, and travel together**: a row carries all three or none, appended last in the order
`media_slug`, `media_version`, `media_source`. `media_source` is the constant `wardroom`. The object name is
`<media_slug>_v<media_version>.webp`; the slug is `<4-digit gif number>-<kebab(name)>`, for example `0103-barbell-standing-ab-rollout`.
In M1 `media_version` is 1 for every file, and a changed file under an existing slug is refused by the builder (objects are immutable).

## 2. Who can read the files (the access model)

The founder's rule: **only a person who has installed the app and logged in reaches the animations, no one else.**

- The bucket is **private** (`public = false`). The public route `/storage/v1/object/public/exercise-media/<name>` serves nothing.
- ONE policy exists on `storage.objects` for this bucket, `exercise_media_authenticated_read`: `FOR SELECT TO authenticated`, this bucket only, and only when the JWT is not an anonymous sign-in (`coalesce(((select auth.jwt()) ->> 'is_anonymous')::boolean, false) = false`). There is no policy for `anon` and none for writes.
- The upload tool uses the service-role key, which bypasses row level security. The app never writes here.
- A logged-in user reads with their JWT on `/storage/v1/object/authenticated/exercise-media/<name>` or through a signed URL.
- **Not stopped:** a scraper who signs up (sign-up is open). The controls for that are a per-account cap (M2, OI-440), CAPTCHA at sign-up (OI-445) and a usage alert with the Spend Cap decision (OI-444).
- **A signed URL is a bearer token:** whoever holds it can fetch until it expires. `--sign` therefore refuses an expiry above 900 seconds and prints the URL to standard output only (never to the report).
- **At the database-role level.** The role probe proves the policy for the roles `anon` and `authenticated` and for a hand-built anonymous-session claim. That Storage maps an anon-key JWT to the role `anon`, and an anonymous sign-in to `is_anonymous: true`, is documented behaviour and UNVERIFIED here; Task 9.2 of the plan sends one real request with the project's anon key and records the status below (section 8).

### The blind spot of the text pins

`test/contracts/exercise_media_bucket_private_test.dart` pins the migration text and every other migration that **names** the bucket or the policy. It has a **blind spot**: a later migration that does not name the bucket (an unscoped policy on `storage.objects` for `anon`, a `GRANT`, an `UPDATE` of `storage.buckets` without the id) is not caught by text. The guard for that class is the role probe: **re-run `test/sql/exercise_media_bucket_live_verify.sql` after any change to a storage policy or grant**, and read its `verdict=` line. The migration header and the test header say the same.

## 3. The numbers that matter for cost

| Quantity | Value |
|---|---|
| Files mapped / total bytes / largest | 616 / 253,550,820 (253.55 MB) / 987,558 |
| One full-library download | 253.55 MB of **uncached** egress (a private object caches worse: each signed URL is its own cache key) |
| Free plan | 1 GB storage and 5 GB uncached + 5 GB cached egress a month, shared by every bucket: about 19 full downloads a month |
| Pro plan | 250 GB + 250 GB: about 985 full downloads; overage about $0.09 per GB uncached, $0.03 cached |
| Spend Cap (Pro) | ON: over the quota the organization is restricted for **every** user; OFF: the overage is billed. The founder chose OFF with a usage alert (OI-444). |

M2's Wi-Fi prefetch budget is the control on the egress side. Before the upload, Task 9.1 of the plan reads the storage total and stops if the total plus 260 MB exceeds 900 MB.

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
- `--execute` is required for any request that changes the bucket. Without it a mode prints what it would do.
- Upload is `x-upsert: false`. An object that exists with the same sha256 is counted `alreadyEqual` and not re-sent; one with a different sha256 stops the run naming the slug; a quota-style answer (413, or a body naming a quota or limit) stops the run. A cut run is re-run unchanged.
- The upload and verify scope is the `active` files only. `unmapped` and `taken_down` files are never uploaded, verified or signed.
- `--verify` and the canary also send two requests **with no credential** (the public route, and the authenticated route with no Authorization header). Either answering 200 stops the run naming `readable without a login`. The second is not a policy test (a missing header is refused before row level security is consulted); the policy is proved by the role probe.
- `--probe-control <bucket/name>` (bucket `avatars` or `banners`) sends one GET to the public route of a bucket that really is public and prints only the status. It is the positive control that makes the non-200 of the exercise-media probe mean something.
- `--delete-object` refuses the object of an `active` file and, after the DELETE, HEADs the name **with the key** (a keyless HEAD of a private object answers 4xx and would read as gone); a 200 may be CDN lag, so it waits 90 seconds and HEADs again. `--delete-bucket` empties the bucket through the Storage API, then deletes it; it has only ever run against the fake server and is never run live except as the rollback.

## 5. The service-role key

The tool resolves the key in this order and never prints, logs or writes it:

1. the environment variable `SUPABASE_SERVICE_ROLE_KEY`, if set (set it in your shell for the run only);
2. otherwise the Management API (`GET /v1/projects/dedsavbjuwgarrhphgnl/api-keys?reveal=true`) with the access token read from the token **file** (`--token-file`, or the file `.claude/token_path.js` `resolveTokenFile` picks). The `SUPABASE_ACCESS_TOKEN*` variables are **not** read.

A key that is a JWT must carry `ref == dedsavbjuwgarrhphgnl`, or the tool refuses it. `--probe-key` runs step 2 and prints key names, lengths, the HTTP status and `ref ok`. The endpoint's behaviour is UNVERIFIED until Task 9.1 records it (section 8); if it answers otherwise, set the environment variable. Inventory row: `docs/operations/SECRET_INVENTORY.md`.

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

1. **The migration** `supabase/migrations/NNN_exercise_media_bucket.sql` is one `DO` block: lock budget, the bucket row (`ON CONFLICT (id) DO UPDATE`), `DROP POLICY IF EXISTS` and `CREATE POLICY exercise_media_authenticated_read`, and a read-back self-check. Until its live apply it is a draft at `docs/plans/library-batch-m/exercise_media_bucket.sql.draft` (Gate 14 fails any unledgered file in `supabase/migrations/`); the apply commit moves it and adds the ledger entry.
2. **The rehearsal** (before the apply, aborting, nothing persists): the live-verify file with the migration body inserted twice at its marker comment, as ONE comment-stripped call; then the wrong-policies file, whose four variants (`TO public`, no `is_anonymous` clause, no bucket scope, `FOR ALL`) must each go RED with their exact quadruple. The result lines are `VERIFY_RESULTS` followed by `key=value` lines; compare lines, do not read them.
3. **After the apply and again after the upload:** run the live-verify file alone; expect `verdict=PASS`. The wrong-policies file is **rehearsal only** and is never run after the apply (its first statement raises if the bucket exists).
4. **Rollback is the Storage API, not SQL:** drop the policy (one statement, in the migration's rollback comment), then `node scripts/upload_exercise_media.js --delete-bucket --execute --confirm-bucket exercise-media --report <path>`.
5. **The dashboard is the inventory.** There is no inventory tool for the bucket's contents; Supabase Dashboard → Storage → `exercise-media` is the list. `--verify` checks the 616 objects the table names, not extras.

## 8. Not yet observed (recorded by Task 9 of the plan, then moved up)

These are what the tool and the plan assume and nobody has seen on the live project. Each is a stop condition in the plan if it turns out otherwise.

| Assumption | Where it is tested |
|---|---|
| `GET /storage/v1/object/authenticated/exercise-media/<name>` with the key reads a private object (and HEAD answers its length) | canary, Task 9.2 |
| `POST /storage/v1/object/sign/exercise-media/<name>` returns a `signedURL` relative to `/storage/v1`, and its GET carries `cache-control` | canary, Task 9.2 |
| A duplicate POST answers 409, or 400 with `statusCode "409"` | `--canary --repost`, Task 9.2 |
| An absent object answers a non-200 HEAD on the authenticated route | canary, Task 9.2 |
| The public route and the authenticated route with no Authorization answer non-200 | canary and `--verify` |
| The public-route URL shape answers 200 for a public bucket | `--probe-control`, Task 9.2 |
| An anon-key request to the authenticated route answers non-200 | one request, Task 9.2 |
| Anonymous sign-ins are off on the live project (otherwise the policy's second clause is the only gate against a no-email sign-up) | Task 8.3 |
| The Management API key endpoint answers with a revealable `service_role` key | `--probe-key`, Task 9.1 |
| The winning `cache-control` form on the signed-URL response (the default is `max-age=31536000`) | canary, Task 9.2 |
| An animated WebP decodes and animates in a browser and on a device | playback check, Task 9.4 (no one has decoded one yet) |

## 9. The trap for Batch M2

A `lib/` file that names the bucket through `storage.from` trips `test/contracts/delete_account_purges_all_user_buckets_test.dart` until `supabase/functions/_shared/user_owned_buckets.ts` gets the documented "holds no user-owned objects" treatment (that test's failure message says how), or the app reads the bucket without `storage.from`. M2 also chooses between short-lived signed links issued by an Edge Function that counts them per account (after which it drops `exercise_media_authenticated_read`) and an uncapped logged-in reader; the first read of a real object with a real user JWT happens only in M2. See OI-440.

## 10. Related board entries

OI-437 (the picture check of the shipped rows and the held-row release steps), OI-440 (M2, app delivery), OI-441 (M1c, intake and versioning), OI-442 (animations created outside the repository), OI-443 (the old-rows export), OI-444 (Supabase plan, Spend Cap, usage alert), OI-445 (CAPTCHA at sign-up).
