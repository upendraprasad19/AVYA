---
reviewed_at: 2026-10-27T20:15:00+05:30
staged_against: 2cac0be000e57fc8a14bf6c4d5633898bd2d3aa4
blast_radius: platform
reviewer: claude-sonnet-via-skill (two fresh reviewers: A upload tool / importer / SQL / migration draft / operations doc, B tests / gates / documents / recomputed numbers; then three fresh delta reviewers, each on the diff of the previous fix commit only)
lens_set: [guard_without_its_mirror, missing_input, asserted_fixture_value, writer_reader_drift, blast_radius_mismatch, security_hygiene]
findings_count: 62
verdict: accepted
verdict_note: 0 P0, 3 P1 + 27 P2 + 32 P3 across the B-pass and three delta passes; every finding verified by the author against the files before acting; 61 fixed in the batch, 1 (the migration tier) is a founder decision asked at go (a); 0 false alarms; the SQL files stay unexecuted until the Task 8.4 rehearsal and say so
---

# Code Review (B-pass) — branch `library-batch-m` (Batch M1), `git diff origin/main...HEAD` at `2cac0be000e57fc8a14bf6c4d5633898bd2d3aa4`

Severity count over the whole review: P0 0 · P1 3 · P2 27 · P3 32 (62 findings). First pass: P1 1 · P2 21 · P3 8 (30; two reviewers raised six of the same findings, each counted once at the higher severity). Delta passes: 13, 10 and 9 findings, below.

Method note. Two reviewers with no conversation context, each given a part of the diff, the batch's own claims as numbers to recompute, and an allow-list of read-only commands (no gate run, no network, nothing written into the repository). Reviewer A recomputed every number it was given and matched them; reviewer B recomputed the table, the library, the folder on disk (all 616 hashes and sizes equal the table) and the document counts. Neither could run the SQL: the live verify file and the rehearsal file are still unexecuted against a database, and the author checked their syntax with libpg_query (pglast) only, which proves the text parses and nothing about whether a name exists or a role may do what the text says. The first execution is the Task 8.4 rehearsal. Each fix below was proven by a new test and by a mutation of the thing it protects (rule 21); the tallies are in the diagnose doc, Task 7.

## Finding 1 — P2 — guard_without_its_mirror (the no-credential probes read "could not ask" as "private")

- **file:line:** `scripts/upload_exercise_media.js` `noCredentialProbes` / `assertPrivate` (reviewer A finding 1, reviewer B finding 5).
- **claim:** `assertPrivate` stopped only on status 200 and stored a thrown fetch error as a string, so a dropped connection, a 429, a 5xx, a 3xx or a 206 all passed as "private". The canary or `--verify` ended with exit 0 and the only privacy check of the real HTTP surface read as evidence when the probe had not run.
- **verification:** reviewer A ran a replica (network error, 400, 404, 429, 500, 503, 302 and 206 all passed); reviewer B grepped the test file and found only 200 and 400/404 covered.
- **status:** accepted, fixed. The tool stops unless every probe answers 400, 401, 403 or 404, and any other outcome prints "did not get a clear refusal … privacy is NOT shown". New tests, for `--canary` and for `--verify`: each of the two probes answering 206, 304, 429, 500 or 503 stops the run, and so does a probe whose connection fails; 200 still stops with "readable without a login"; the mirror (400 and 404 pass) stays. Mutation: reverting to `=== 200`, widening the status set and dropping the thrown-error branch each reddened tests (the upload-tool matrix, 25 of 25 red).

## Finding 2 — P2 — guard_without_its_mirror (the privacy contract never looked at `storage.buckets`)

- **file:line:** `test/sql/exercise_media_bucket_live_verify.sql` write-grant detector (every detector was `tablename = 'objects'`); plan R7 and Task 8.3 (reviewer A finding 2).
- **claim:** a dashboard-style policy such as `FOR UPDATE TO authenticated USING (true)` on `storage.buckets` lets any logged-in user run `UPDATE storage.buckets SET public = true WHERE id = 'exercise-media'`; the bucket then serves everyone and FILE 1 still printed `verdict=PASS`.
- **verification:** the text gap is certain (grep of the detectors); whether such a policy exists live is unknown, which is why Task 8.3 now reads the live policies on `storage.buckets` too.
- **status:** accepted, fixed. `buckets` joins the write-grant detector, the probe block gets a leg that runs `UPDATE storage.buckets … WHERE id = 'exercise-media'` as a normal logged-in user and expects 0 rows (write slot `bucket`), and the rehearsal gains a fifth wrong setup (V5, `FOR UPDATE USING (true)` on `storage.buckets`, expected `refused/0/0/1` when `authenticated` holds UPDATE on the table). The probe block is byte-identical in both files (the contract pins it). Honest note: V5 may STOP at the rehearsal if `postgres` cannot create a policy on `storage.buckets` (ownership); that is read first at Task 8.4 and fails closed.

## Finding 3 — P2 — guard_without_its_mirror (the catalog detectors were never shown to fail)

- **file:line:** `test/sql/exercise_media_bucket_wrong_policies_rehearsal.sql` (it computed only the quadruple and the write legs) against `…_live_verify.sql` catalog block (reviewer A finding 3).
- **claim:** `anon_public_select_policies`, `unscoped_write_grants` and the `policy_cmd|roles|has_bucket|has_is_anonymous` string appear in FILE 1's verdict but no FILE 2 variant read them, so a detector with a wrong filter would print `none` forever and be believed.
- **verification:** grep of both files; defence in depth, since the behavioural legs cover the same failures.
- **status:** accepted, fixed. Each variant reads the catalog string before its rollback and carries it in `expected=` (baseline `SELECT|{authenticated}|true|true|none|none`, V1 `…|{public}|…|exercise_media_authenticated_read|none`, V2 no `is_anonymous`, V3 no bucket scope, V4 `ALL`, V5 `…|none|buckets.exercise_media_buckets_wrong`).

## Finding 4 — P2 — asserted_fixture_value ("refused" and "0" decided by message prefix only)

- **file:line:** `…_live_verify.sql` and the rehearsal (the `permission denied for table%` and `new row violates row-level security policy%` matches), reviewer A finding 4.
- **claim:** neither pattern named `objects`, so a different relation's 42501 (for example a trigger or a policy on `storage.prefixes`) read as "refused"/"0" and could make a false PASS; `LIKE '%is_anonymous%'` also treated `_` as a wildcard.
- **verification:** PLAUSIBLE in the reviewer's words (depends on Storage internals); the text gap is certain.
- **status:** accepted, fixed. The matches now name the table (`permission denied for table objects%`, `… for table "objects"%`, `… table buckets%` for the new leg) and the catalog tests use `strpos` instead of `LIKE`.

## Finding 5 — P2 — writer_reader_drift (error message cites a document that does not exist)

- **file:line:** `scripts/add_library_batch_c_v15.js:159` (reviewer A finding 5, reviewer B finding 4).
- **claim:** the held-row message said "see docs/architecture/EXERCISE_MEDIA.md"; the file is `docs/operations/EXERCISE_MEDIA.md`.
- **verification:** `git ls-files` and `ls docs/architecture | grep -i media` (empty).
- **status:** accepted, fixed; the importer test asserts the message path.

## Finding 6 — P2 — writer_reader_drift (`--probe-key` described as more than it does)

- **file:line:** `docs/operations/EXERCISE_MEDIA.md` (probe-key paragraph), plan R14 (4), `modeProbeKey` (reviewer A finding 6, reviewer B finding 12).
- **claim:** both documents said it prints the HTTP status and "runs step 2"; the tool printed no status, and when `SUPABASE_SERVICE_ROLE_KEY` was set it never contacted the Management API, so Task 9.1's purpose (observe the key endpoint) was not served and nothing said so.
- **verification:** read `modeProbeKey` and `resolveKey`.
- **status:** accepted, fixed. `resolveKey` returns the status, `--probe-key` prints `management api http status: <n>`, and when the environment key is used it prints that the Management API was NOT contacted and how to probe it. Documents and plan reworded; tests for both branches.

## Finding 7 — P2 — security_hygiene (the report file bypassed the redactor)

- **file:line:** `scripts/upload_exercise_media.js` `writeReport` (reviewer A finding 7).
- **claim:** every stdout/stderr line passed `redact()` but the report was written as raw `JSON.stringify`, and `body: post.text.slice(0, 300)` puts server text in it; a server that echoed the credential in an error body would have written it to disk.
- **verification:** read the writer and the data path of `post.text`; low likelihood, but the stated invariant is "never written to the report".
- **status:** accepted, fixed (the serialised report goes through `redact()`); test "a repost answer that echoes a secret is redacted in the printed line AND in the report".

## Finding 8 — P2 — security_hygiene (the child `git` inherited the service-role key)

- **file:line:** `.claude/token_path.js` `scrubbedGitEnv` and its Dart twin `scripts/supabase_token_path_lib.dart` (reviewer A finding 8).
- **claim:** the scrubbed environment copied `process.env` and removed only `GIT_*`, so `git worktree list` ran with the key exported.
- **verification:** read both resolvers; no concrete exploit (`worktree list` runs no hooks), more exposure than needed.
- **status:** accepted, fixed in both resolvers (service-role key and every `SUPABASE_ACCESS_TOKEN*` dropped); tests on both sides with mutants (6 of 6 red).

## Finding 9 — P2 — security_hygiene (the report-location guard accepted a directory named `..x`)

- **file:line:** `scripts/upload_exercise_media.js` `isInside` (reviewer A finding 9).
- **claim:** `path.relative` of a path under a directory called `..x` is `..x\…`, which `startsWith('..')` read as "outside".
- **verification:** reproduced with a replica.
- **status:** accepted, fixed (`rel === '..' || rel.startsWith('..' + path.sep)`). Lesson recorded: this worktree lives inside the primary checkout, so a path under the worktree is refused by the primary's check even with the worktree's own check broken, which made the first mutant equivalent; the test therefore uses a `..reportdir` directly under the primary checkout (with teardown and a pre-existence check), and the mutant reddens it.

## Finding 10 — P2 — missing_input (destructive modes ran before the report path was known to be writable)

- **file:line:** `modeDeleteObject`, `modeDeleteBucket`, `checkReportPath` (reviewer A finding 10).
- **claim:** `--report Z:\x\r.json` (a missing drive) or a directory passed the location guard, the bucket was emptied or deleted, and the process then crashed before recording the result.
- **verification:** read the three functions and the callers.
- **status:** accepted, fixed. The report path is proved writable before any request (create the parent, open for append, remove the file again if the check made it); an unwritable path ends with exit 2 "the report path cannot be written (…); nothing was sent". Tests: a path under a file, for both delete modes and the upload modes, and a run that stops later (no key) leaves no file behind while an existing report is kept.

## Finding 11 — P2 — blast_radius_mismatch (the migration's tier is decided by its file name)

- **file:line:** `docs/blast_radius.yaml:92` (`supabase/migrations/*rls*.sql` is catastrophic) against `:107` (`supabase/migrations/**` is platform); planned file `NNN_exercise_media_bucket.sql` (reviewer A finding 11).
- **claim:** the migration creates the single access-control policy of a private bucket whose only purpose is the founder's "no one else" rule, but its name does not match `*rls*`, so no hermes pass and no `rollback_documented` apply.
- **verification:** read the registry; the plan states `platform` openly, so this is a decision to confirm, not a surprise. Precedent migration 154 has `rls` in its name.
- **status:** decision, not a code change. The file keeps `platform` unless the founder says otherwise; the question is asked with the Task 8.4 rehearsal result at go (a) (the slug is only minted at that step, so a rename costs nothing before then).

## Finding 12 — P2 — missing_input (the cache-control choice could not discriminate and defaulted to the CDN-storable form)

- **file:line:** `scripts/upload_exercise_media.js` `CACHE_FORMS` / `DEFAULT_CACHE` (reviewer A finding A).
- **claim:** all three forms contain `max-age=31536000`, so the rule always picked the first (`max-age=31536000`) and the `private, … immutable` form could never win; uploads use `x-upsert false`, so the stored value is fixed for the life of the object, and a signed URL is a bearer link whose cached response outlives its expiry (plan F17: expiring a token does not purge a cached response).
- **verification:** read the constants and the plan's rule.
- **status:** accepted, fixed. The forms are ordered `private, max-age=31536000, immutable`, `max-age=31536000, immutable`, `max-age=31536000` with the default at index 0, and the operations document says what a cached signed response means.

## Finding 13 — P2 — missing_input (fixture inserts into `storage.objects` depend on Storage internals)

- **file:line:** `…_live_verify.sql` fixture block and the rehearsal's (reviewer A finding B, reviewer B plausible A).
- **claim:** the inserts run as `postgres` (fallback `SET LOCAL ROLE service_role`); whether current Storage fires BEFORE INSERT/UPDATE/DELETE triggers that behave for these roles cannot be known here; variant V4 is the only one that expects an UPDATE and a DELETE to succeed, so a trigger error would turn it into STOP.
- **verification:** not provable without running; both reviewers agree it fails closed (blocks go (a)), never a false PASS.
- **status:** accepted as an honest first-run risk, recorded in the diagnose doc and the operations document. Closed by the Task 8.4 rehearsal result, shown to the founder before go (a).

## Finding 14 — P3 — process (FILE 1 was assembled by hand for the rehearsal)

- **file:line:** no committed script inserted the migration body twice and stripped comments (reviewer A finding C).
- **claim:** an operator slip (a leftover `DO $mig$` wrapper) would abort the rehearsal; the stripped call (about 12.5 KB) is above the size the repository once saw the MCP refuse.
- **verification:** read plan Task 8.4 and the byte-equality pin on FILE 2.
- **status:** accepted, fixed. `scripts/exercise_media_rehearsal_sql.js --file1|--file2` prints the comment-stripped SQL to stdout (FILE 1 with the migration body twice at the marker); 15 tests, mutants c01–c16 (c04 was equivalent dead code and was removed, so 15 of 15 red).

## Finding 15 — P1 — writer_reader_drift (a founder decision recorded in two documents against the plan)

- **file:line:** `docs/operations/EXERCISE_MEDIA.md` (Spend Cap row) and `docs/audit/open_issues.md` OI-444, against plan founder call 7 and the closure table (reviewer B finding 1, reviewer A finding D).
- **claim:** the documents said the founder chose Spend Cap OFF; the plan said "recommended: off" and listed the choice as `blocked_on_user`. Whoever read OI-444 would treat the cap as decided.
- **verification:** the founder wrote "Spend cap: off" in chat on 2026-10-27; no committed source recorded it, so the plan and the closure row were the stale side.
- **status:** accepted, fixed toward the founder's statement: plan call 7 and the closure row now say the founder chose OFF in chat on 2026-10-27; the open item left is the dashboard action at store launch (GO_LIVE_CHECKLIST 5.6, OI-444), which stays `blocked_on_user`.

## Finding 16 — P3 — missing_input (an empty table and an empty bucket both read as success)

- **file:line:** `scripts/add_library_batch_c_v15.js:150`; `--verify` in `scripts/upload_exercise_media.js` (reviewer A finding E).
- **claim:** the importer accepted a table with an empty `rows` object and silently stripped all 617 media keys ("media keys on 0 rows"); `--verify` on a table with zero active objects printed `0 of 0`, skipped the probes and exited 0.
- **verification:** read both; CI leg (e) would catch the first only later.
- **status:** accepted, fixed (importer refuses an empty `rows`; `--verify` stops on zero objects); three importer mutants and a verify test, all red.

## Finding 17 — P2 — writer_reader_drift (stale registry line range)

- **file:line:** `docs/sot_registry.yaml` `line_range: 209-238` for `_exerciseLibraryVersion + retiredLibraryIds + pruneRetired` (reviewer B finding 2).
- **claim:** the v16 comment block moved `retiredLibraryIds` to 227 and `pruneRetired` to 243, so the range ended inside `seedIfNeeded`; the parity gate does not see prose method text.
- **verification:** `git show origin/main:` against HEAD and `seed_service.dart`.
- **status:** accepted, fixed (range re-pointed to cover the constant at 128, `seedIfNeeded` at 153, `retiredLibraryIds`, `pruneRetired` and `_seedExercises` 249-267).

## Finding 18 — P2 — asserted_fixture_value (diagnose symptom misstates the denominator)

- **file:line:** `docs/diagnoses/2026-10-27-library-batch-m1-b4e7a2.md:9` (reviewer B finding 3).
- **claim:** "522 of the 617 mapped rows are already shipped"; all 617 are shipped, and 522 is the number of shipped rows with an animation but no picture or identity record (OI-437).
- **verification:** node recount by the reviewer, recounted by the author.
- **status:** accepted, fixed in the diagnose doc.

## Finding 19 — P2 — guard_without_its_mirror (untested guards in the upload tool)

- **file:line:** `localFile()`; the mode checks in `main()`; the non-200 sign answer; a canary re-run where the object exists (reviewer B finding 6).
- **claim:** none had a test, so deleting the guard turned nothing red.
- **verification:** grep of the test file for each.
- **status:** accepted, fixed. New tests: seven bad `versions[0].file` spellings refused before any file is opened, the exclusive-mode checks (`--repost` without `--canary`, `--expires` without `--sign`, `--expires 0`, `901`, non-numeric), a sign answer of 500 (`signStatus`), a canary re-run that skips an equal object and one that stops on different bytes naming the delete mode. Mutants reddened in the 25-mutant matrix.

## Finding 20 — P2 — guard_without_its_mirror (table CI helper sub-clauses without a broken copy)

- **file:line:** `test/helpers/library_media_table_checks.dart` leg (h) `startsWith('webp-720/') || endsWith('.webp') || contains('..')` and the other sub-legs (reviewer B finding 7).
- **claim:** the file header says every leg also runs against a broken copy, but removing `contains('..')` or `endsWith('.webp')` left all 31 tests green, and so did dropping the version-count, version-hash, unknown-status, hash-shape, `frames`, `thumb_bytes`, `old_rows` and `webp_bytes` sub-checks.
- **verification:** the reviewer's list, re-run by the author as mutants.
- **status:** accepted, fixed with a broken copy per sub-clause (`expectLeg(leg, {has})`); mutants t01–t19, 19 of 19 red.

## Finding 21 — P2 — guard_without_its_mirror (builder immutability: the thumbnail half)

- **file:line:** `scripts/build_library_media_v16.js:267` (`prior.webp_sha256 !== animSha || prior.thumb_sha256 !== thumbSha`), `:263` ledger bytes, `:264` frames (reviewer B finding 8).
- **claim:** the one test changed the animation, so dropping the thumbnail comparison, the ledger byte check or the frame check reddened nothing; R3 says a changed thumbnail under an existing slug must stop the run.
- **verification:** read the test and the three lines.
- **status:** accepted, fixed with three tests; mutants b1–b3, 3 of 3 red.

## Finding 22 — P2 — asserted_fixture_value (a "no DELETE" test that could pass on nothing)

- **file:line:** `test/scripts/upload_exercise_media_test.dart` "no mode except the two delete modes issues a DELETE" (reviewer B finding 9).
- **claim:** five modes run and only `fake.deletes isEmpty` is asserted, so five early exits would keep it green.
- **verification:** read the test.
- **status:** accepted, fixed: each run also asserts its exit code and that its first request reached the fake.

## Finding 23 — P2 — guard_without_its_mirror (the single-spawn guard was narrow)

- **file:line:** `test/scripts/upload_exercise_media_test.dart` single-spawn guard (reviewer B finding 10).
- **claim:** it counted one literal spelling of a spawn, so a later `runSpawn(...)`, a literal script path or another variable could reach the real API without a seam.
- **verification:** read the guard.
- **status:** accepted, fixed: it counts fragments (the tool identifier, exactly two spawn sites, no `Process.run/start`, no shell), and mutants that add each spelling redden it.

## Finding 24 — P2 — asserted_fixture_value (two tests could leave debris when the guard regressed)

- **file:line:** the report-path tests in `test/scripts/upload_exercise_media_test.dart` (reviewer B finding 11).
- **claim:** with a regressed guard the tool would write `report_must_not_exist.json` into the repository root or the primary checkout and later runs would go red until it was deleted; the author hit exactly this with a mutant.
- **verification:** the diagnose doc's honest note 2; `git status` and the primary root were clean at review time.
- **status:** accepted, fixed. Every report-path test now targets a path under `pubspec.yaml` (a file), so a regressed guard fails later at "cannot be written" and cannot create a file, and each asserts the guard's own message; the `..reportdir` test cleans up after itself.

## Finding 25 — P3 — writer_reader_drift (operations document: what a mode does without `--execute`)

- **file:line:** `docs/operations/EXERCISE_MEDIA.md` section on `--execute` (reviewer B finding 13).
- **claim:** "Without it a mode prints what it would do" — the delete modes refuse with exit 2; only the upload and canary modes print a plan.
- **verification:** `main()` mode checks.
- **status:** accepted, fixed in the document.

## Finding 26 — P3 — asserted_fixture_value (OI-440 size)

- **file:line:** `docs/audit/open_issues.md` OI-440 (reviewer B finding 14).
- **claim:** "4.4 MB for the 924 in the folder"; measured 4,606,034 bytes, which is 4.6 MB (the plan's unit rule is MB = 10^6).
- **verification:** reviewer measured; author re-summed.
- **status:** accepted, fixed (4.6 MB).

## Finding 27 — P3 — writer_reader_drift (diagnose reader line)

- **file:line:** `docs/diagnoses/2026-10-27-library-batch-m1-b4e7a2.md` reader row (reviewer B finding 15).
- **claim:** it cited `seedIfNeeded … line: 128`; line 128 is the version constant and the method starts at `seed_service.dart:153`.
- **verification:** read the file.
- **status:** accepted, fixed (constant 128, method 153).

## Finding 28 — P3 — asserted_fixture_value (stale test counts in the diagnose doc)

- **file:line:** diagnose doc test-count sentences (reviewer B finding 16).
- **claim:** "24 table tests" and "18 broken copies" against 31 and 27 at review time; labelled "so far".
- **verification:** reviewer counted; counts moved again with the fixes above.
- **status:** accepted, fixed at close-out from the final runs (diagnose Task 7 section), not from this review's numbers.

## Finding 29 — P3 — writer_reader_drift (plan text lags the rehearsal)

- **file:line:** plan Task 8.4 ("mutated: 3 of 3 reddened") against FILE 2 (reviewer B finding 17).
- **claim:** the committed FILE 2 has more variants than the text says.
- **verification:** FILE 2 prints `mutated: <n> of 5 reddened` and pins `v_red = 5`.
- **status:** accepted, fixed in the plan (five variants, `5 of 5`).

## Finding 30 — P3 — writer_reader_drift (glossary rows placed between rows that travel together)

- **file:line:** `docs/naming_conventions.md` (reviewer B finding 18).
- **claim:** the media rows sat between `demo_slug` and `demo_pair`, which the glossary says travel together.
- **verification:** read the glossary.
- **status:** accepted, fixed (media row after `demo_pair`).

## Read and found sound (both reviewers)

Reviewer A read the upload tool, the builder, the importer media stage, the seed constant and reader, the migration draft, both SQL files and the operations document in full and recomputed 5 GB / 253.55 MB = 19.7 and 250 GB / 253.55 MB = about 986; reviewer B recomputed 617 rows, 616 files, 253,550,820 bytes, largest 987,558, 914 library rows with 617 carrying the keys last and in order (stripped of the keys equal to `origin/main` row by row), 209 core rows of which 132 lack a `media_slug`, and the OI-437 reconciliation (529 unrecorded = 522 + 7). Both found: no P0; the project ref, bucket and token path are constants; seam URLs accepted only for the parsed host 127.0.0.1 or localhost, paired, without userinfo; redirects never followed; DELETE only in the two delete modes (each needing `--execute`, `--confirm-bucket exercise-media` and `--report`); `x-upsert false`; the signed-URL host checked and `--sign` limited to active or canary names with an expiry of 1 to 900 seconds; a JWT key must carry the project ref; the migration holds no `anon`, `public` or write policy and its 1500000 equals `_meta.webp_bytes_max`; no test passes on an empty input and no C1 assertion was loosened.

## Delta reviews (each on the diff of the previous fix commit only)

Two further fresh reviewers (no conversation context) each read the diff of the previous fix commit only and were told to find bugs in the fixes. The first read `91ae7c84..9de228a2`, the second `9de228a2..e27be17b`. Each finding was verified by the author against the files (and, where a claim was about behaviour, by running a scratch copy) before acting.

### Delta review 1 — `91ae7c84..9de228a2` — 13 findings: P0 0 · P1 1 · P2 2 · P3 10 (its header said P3 11; the list has ten) — all fixed in `e27be17b`

- **D1-1 — P1 — guard_without_its_mirror (the bucket leg and rehearsal variant V5 could not show what the file said they show).** `test/sql/exercise_media_bucket_live_verify.sql` leg 5d and `…_wrong_policies_rehearsal.sql`. The leg was `UPDATE storage.buckets SET public = true WHERE id = 'exercise-media'`; a WHERE on `id` also needs the row to pass a SELECT policy, `storage.buckets` has none by default, so an UPDATE-only policy (what the dashboard creates) hid from the leg and V5 would have STOPPED at 8.4. Verified against the PostgreSQL rule for UPDATE under row-level security (an UPDATE needs SELECT rights and policies only when a column is read in WHERE, RETURNING or the right side of SET). Fixed: `UPDATE storage.buckets SET public = true;` with no WHERE and a constant on the right of SET, read as `0` or `open`; V5 expects `refused/0/0/open` (or `refused/0/0/0` when `authenticated` lacks UPDATE on the table). Five new contract mutants.
- **D1-2 — P2 — writer_reader_drift** the operations document section 7, plan Task 6.1 and the diagnose doc still described four rehearsal variants and no composer. Fixed (five variants, the composer command).
- **D1-3 — P2 — writer_reader_drift** plan R14 and Task 9.2 still instructed the old cache-control default and order. Fixed (private default, "keep it").
- **D1-4 — P3 — missing_input** report-path spellings (`\\?\` and 8.3 names) and a symbolic link as the report path. Fixed: `realpathSync.native`, a symlink refusal, the probe removes the directories it created; tests including a device-path spelling on Windows.
- **D1-5 — P3 — bad_news_vs_no_news** a delete mode lost its report on a mid-loop network error. Fixed: partial reports for `--delete-object` and `--delete-bucket` with `stoppedBy`.
- **D1-6 — P3 — missing_input** the environment scrub was case-sensitive and covered two names. Fixed: upper-cased comparison, `SUPABASE_*` and credential-looking names, in both twins.
- **D1-7 — P3 — asserted_fixture_value** the composer's comment stripper did not model double-quoted identifiers. Fixed: a branch, an unterminated one is refused.
- **D1-8 — P3 — guard_without_its_mirror** writes by `anon` are never probed; "scoped" means "mentions bucket_id". Partly fixed: the detector also flags a policy naming `exercise-media` or negating the bucket test; no anon INSERT leg was added (the founder's rule is about reads); the limit is now stated in the file header, the operations document and plan R15 (see D2-5).
- **D1-9 — P3 — asserted_fixture_value** the thumbnail size in OI-440 was not what the table records. Fixed: both figures with their sources (616 in the table: 3,102,690 bytes; 924 in the folder: 4,606,034).
- **D1-10 — P3 — process** the composer test used the synchronous spawn helper against plan R12. Fixed (`runSpawnAsync` with a per-call timeout; see D2-9).
- **D1-11 — P3 — missing_input** the rehearsal holds the same table locks as the apply and had no off-peak note. Fixed in the FILE 2 header and plan 8.4.
- **D1-12 — P3 — unsupported_claim** the supabase-js cache-control comment was unsupported and 401/403 were in the refusal set without a test. Fixed (comment reworded; 401 and 403 cases).
- **D1-13 — P3 — writer_reader_drift** plan R15's fixed key list was incomplete. Fixed.

### Delta review 2 — `9de228a2..e27be17b` — 10 findings: P0 0 · P1 1 · P2 2 · P3 7 — all fixed in `4d0fa7cd`

- **D2-1 — P1 — asserted_fixture_value (my slip).** `test/sql/exercise_media_bucket_wrong_policies_rehearsal.sql:27,83`, `test/contracts/exercise_media_bucket_private_test.dart` (`_expectedArrays` and a mutant). I had tightened the unscoped-write check (a write policy naming `exercise-media` is flagged) and checked it only against the live policies; variant 4 (`FOR ALL ... USING (bucket_id = 'exercise-media' ...)`) now reads `objects.exercise_media_authenticated_read` while its expected string still ended in `none`, and the contract pinned that stale literal: Task 8.4 would have read 4 of 5 with CI green. Verified by walking the predicate over the variant policy. Fixed in four places plus a Dart twin of the predicate (`catalog_model`), a whole-predicate pin (`unscoped_predicate`), six in-process mutants, and two mutants of the real files; recorded as bug class 2.136.
- **D2-2 — P2 — wrong_detail** the report-path probe's stop at `firstCreated` never fires on Windows (`mkdirSync(..., {recursive: true})` returns the `\\?\` spelling), so empty parents that were already there were removed. Reproduced by the reviewer in a scratch copy; verified here by a mutant that reproduces the old walk and reddens the new test on Windows. Fixed: the directories to create are listed before the mkdir.
- **D2-3 — P2 — missing_input** the credential-name scrub dropped `GIT_CONFIG_KEY_<n>` but kept `GIT_CONFIG_COUNT`, and git exits 128 on that. Reproduced with git 2.53. Fixed in both twins; bug class 2.137.
- **D2-4 — P3** the probe left its directories behind when the open failed. Fixed (`finally`).
- **D2-5 — P3 — guard_without_its_mirror** the negation test missed `!~~`-style spellings, had unexercised branches and no positive control. Fixed: `<>|!=|!~|NOT |IS DISTINCT|~~`; the heuristic and the authenticated-only write legs are stated in the file header, the operations document and plan R15; the real SQL predicate was run (read-only) over 15 synthetic policy rows: exactly the 10 intended are listed.
- **D2-6 — P3** no whole-expression pin of the predicate. Fixed (`_expectedUnscoped`, flip mutants).
- **D2-7 — P3** the partial `--delete-object` report did not say which object was in flight. Fixed (`inFlight`).
- **D2-8 — P3** three documents lagged the code (FILE 1 header, the report-path bullet, plan 9.2). Fixed.
- **D2-9 — P3** `.timeout` on a `Process.run` future leaves the child running. Fixed: `startSpawn` and `kill()`; the kill path itself is not exercised (it needs a hang), which is stated.
- **D2-10 — P3 — honesty** "run against the live policies it flags none" was recorded nowhere reviewable. Fixed: the query, the 24-policy count and the result are in the diagnose doc (Task 7).

Decision recorded, not a finding: the migration's blast tier (B-pass finding 11) stays a founder decision asked at go (a). The `*rls*` filename rule is raised with it.

### Delta review 3 — `e27be17b..4d0fa7cd` — 9 findings: P0 0 · P1 0 · P2 2 · P3 7 — all fixed in the commit after `4d0fa7cd`

The reviewer walked the six rehearsal catalog strings by hand and again with an independent JavaScript port of the SQL (not the Dart twin): all six equal the expected array. It also confirmed that every in-process mutant `from` string occurs exactly once and trips the id it asserts, that the regex is the same in the pin, the needle and both SQL files, and that the counts (privacy contract 89, upload tool 130, `token_path` 26, composer 17) are right.

- **D3-1 — P2 — writer_reader_drift (a regression I introduced in `4d0fa7cd`).** `scripts/upload_exercise_media.js` listing loop and `finally`. `fs.existsSync` is false for a dangling directory link, so a dangling junction or symlink that is the report's parent was listed as "to create"; the mkdir failed, and the `finally` removed the link, which the old code left alone. Reproduced here in a scratch directory (Windows, Node 24: `existsSync` false, `lstat` true, `rmdirSync` removed the junction). Fixed: the listing uses `lstat` (an entry of any kind ends the walk; ENOENT and ENOTDIR count as missing), and each `rmdir` re-checks that the entry is still a real directory. New test: a dangling directory link as the parent is refused and survives.
- **D3-2 — P2 — asserted_fixture_value** the FILE 1 header and the operations document said a range or LIKE escapes the unscoped-write listing; LIKE is listed since `~~` was added. What escapes: a range, a positive regex (`~`, `~*`, `SIMILAR TO`), a function of `bucket_id`. Fixed in both, and the Dart twin test pins the positive regex and the function as documented gaps.
- **D3-3 — P3 — a test that passes on nothing** the twin's `buckets` case was also listed by the no-bucket-predicate branch, so deleting the table branch kept it green, and `!=` had no case. Fixed (bucket-scoped text; a `!=` case). Mutants: the twin without its buckets branch, without its exercise-media branch.
- **D3-4 — P3** the first two new probe tests cannot redden on Linux CI (the old logic also worked on POSIX); stated in the test.
- **D3-5 — P3** an assertion on `primaryError` that cannot fail (the temp-dir repo is not under `/.claude/worktrees/`); replaced by a null check on the answer.
- **D3-6 — P3** the `GIT_CONFIG_` exemption lets key material reach a local git child (a token in a VALUE, or in an insteadOf KEY); written as an accepted residual in both twins.
- **D3-7 — P3** a policy count (25) in the new bug-class entry, and a diagnose line mixing the 60-test and 89-test descriptions. Fixed.
- **D3-8 — P3** plan Task 9.2 told the executor to re-upload the canary with `--cache-control`, which the canary ignores. Fixed.
- **D3-9 — P3 — bad_news_vs_no_news** `inFlight` lost the DELETE answer when only the HEAD after it was cut off. Fixed: `inFlight` is `{name, deleteStatus}`; new test with a cut HEAD.

## Tuning entry
- **2026-10-27** - blast-radius platform - 62 findings; 0 false_alarm; tuning: brief every delta reviewer with the list of fixtures that encode the changed check's expected output and ask for a hand-walk of each (delta 2's P1 was a stale expected string the author could have found), and brief any reviewer of a tool that touches paths with the Windows spellings (`\\?\`, 8.3 short names, junctions: `existsSync` is false for a dangling link) because two of the three delta rounds found a Windows-only defect in the previous fix.
