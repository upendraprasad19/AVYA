---
reviewed_at: 2026-10-31T17:30:00+05:30
staged_against: 8956d92a9bf76ade7565553a2aabaf7737c7864c
blast_radius: platform
reviewer: claude-sonnet-via-skill (two fresh reviewers with no conversation context: A production code, B tests / script / docs / registry / recomputed numbers)
lens_set: [guard_without_its_mirror, unawaited_no_error_sink, writer_reader_drift, missing_input, asserted_fixture_value, blast_radius_mismatch, secrets_in_tree]
findings_count: 28
verdict: accepted
verdict_note: 0 P0, 3 P1 + 3 P2 + 22 P3 (28 distinct; one finding was raised by both reviewers); every finding verified by the author against the files before acting; 25 fixed in the batch, 3 ruled to stand with their cost stated (a store write error evicts one healthy file; a cache hit's recency is written with the next change; a presence-only pin is weaker than a behavioural one by its own header); 0 false alarms; the mutation proof then found one more defect the reviewers could not see (a test that could never fail), fixed in the same batch.
---

# Code Review (B-pass) — branch `library-batch-m2` (Batch M2a), `git diff 8e2cbdc8...HEAD` at `8956d92a9bf76ade7565553a2aabaf7737c7864c`

Severity count over the 28 distinct findings: P0 0 · P1 3 · P2 3 · P3 22. Reviewer A (production code) raised 10 (1 P2, 9 P3), reviewer B (tests, script, docs, registry, numbers) raised 19 (3 P1, 3 P2, 13 P3); the kill-switch wording was found by both and is counted once.

Method note. Two fresh reviewers, each given part of the diff, the neutral batch description, the lenses and a read-only command allow-list (no `flutter`, no `dart`, no network, nothing written into the repository: a full-suite test run held the project). Their "mutant survives" statements were paper walks, so the author re-ran every one as a real mutation after the fix (table at the end). Every finding below was checked by the author against the code before anything was changed. Reviewer numbers (A1 to A10, B1 to B19) are the ones in their reports.

The three P1 are test gaps, not code defects: the scale counts "a protection that does not bite" as P1. The code was right in each; the fix is one test case that fails when the protection is removed.

## Finding 1 — P1 — guard_without_its_mirror (the kill switch read on EVERY call was not pinned) (B1)
- **file:line:** `lib/core/services/exercise_media/exercise_media_repository.dart:61,93`; the only test that varied `enabled` passed the constant `() => false`.
- **claim:** a regression that read the switch once (constructor, or a provider-level snapshot) passed every test, so the incident lever would work only after a restart, against four documents.
- **verification:** author walked the mutant (snapshot in the initializer) through every test; all green.
- **status:** fixed. `[bp1]` flips the switch between calls in both directions and asserts zero client calls and zero store reads while off. Mutant bp1 (snapshot) reddens it.

## Finding 2 — P1 — guard_without_its_mirror (web adoption of a valid, unindexed blob had no positive case) (B2)
- **file:line:** `lib/core/services/exercise_media/exercise_media_store.dart` `_load` (the `adopted == null` branch); `[z]` covered only the failure half.
- **claim:** a mutant that never reads a web blob to measure it passes: after a lost web meta every cached animation would be deleted as an orphan.
- **status:** fixed. `[bp11]` (two valid blobs, no meta: both adopted with their real lengths, zero deletes). Mutant bp11 reddens it.

## Finding 3 — P1 — guard_without_its_mirror (the "retry once after evicting one victim" bound could not be seen) (B3)
- **file:line:** `exercise_media_store.dart` `_putLocked` catch; both pinning cases had exactly one other entry.
- **claim:** an unbounded evict-and-retry loop makes the same two attempts with one victim, so a persistent write failure with N cached files could empty the cache in one `put` and no test noticed.
- **status:** fixed. `[bp12]` seeds three entries, arms a permanent write failure and asserts exactly 2 attempts and exactly one victim gone. Mutant bp12 (unbounded loop) reddens it.

## Finding 4 — P2 — misleading claim (the kill-switch wording promised the still; the code shows the plate or the initials) (A1, B4)
- **file:line:** `plate_flags.dart:29-33`, `docs/operations/EXERCISE_MEDIA.md` (section 9), `docs/naming_conventions.md` (the `disable_exercise_animations` row).
- **claim:** all three said the bundled still shows when only `disable_exercise_animations` is set. Design call C22 and the author's own fallback tests say the opposite: the still is an animation surface and goes with the switch, the plates keep working. The 617 rows with an animation have no drawing, so their tiles show the monogram and the sheet says NO DRAWING YET.
- **verification:** author read the thumb (`_stillFace` only when `PlateFlags.animationsEnabled && media != null`), the sheet and the spec line. The code is right, the three texts were wrong.
- **status:** fixed (texts only), and the consequence for the 617 rows is now stated where an operator will read it.

## Finding 5 — P2 — writer_reader_drift (the registry said `clearAllData()` clears the media files and index) (B5)
- **file:line:** `docs/sot_registry.yaml` (concept `exercise_media_delivery`, second WARNING).
- **claim:** the design (C8), the nested CLAUDE.md, EXERCISE_MEDIA.md and test `[c]` all say neither is touched. The paragraph future writers read first said the opposite.
- **status:** fixed (sentence rewritten).

## Finding 6 — P2 — misleading claim (OI-440 cited a closure ledger and mutation evidence that were not in the tree) (B6)
- **file:line:** `docs/audit/open_issues.md` (OI-440, "Blocked on" and "Done when").
- **claim:** at the reviewed HEAD `docs/audit/library-batch-m2.closure.yaml` did not exist.
- **status:** fixed by writing it in this batch (`docs/audit/library-batch-m2.closure.yaml`, validated by Gate 40), committed before the merge.

## Finding 7 — P3 — blast_radius_mismatch (the board said `account`, the diff computes `platform`) (B18)
- **file:line:** `docs/audit/open_issues.md` OI-440 "Done when" vs `docs/blast_radius.yaml` (`pubspec.yaml`, `hive_service.dart` are platform).
- **status:** fixed (board now says `platform` and why).

## Finding 8 — P3 — missing_input (a backwards clock step froze three cooldowns) (A2)
- **file:line:** `exercise_media_repository.dart:110,145` and `exercise_media_client.dart:135`.
- **claim:** `now.difference(stamp) < window` is true for a stamp in the future, so after the clock is set back a refused name is never asked again, no cache write is attempted for any name, and the token-refresh retry is suppressed (the client one is a static field: the whole process).
- **verification:** author reproduced it: tests `[bp2]`, `[bp2b]`, `[bp7]` failed on the reviewed code.
- **status:** fixed. One helper `_within` in the repository and the same test in the client; a future stamp is expired. Mutants bp2, bp2b and bp7 (the bare comparison back at each site) each redden exactly their own case. New bug class 2.140 in the debugging skill.

## Finding 9 — P3 — guard_without_its_mirror (a cache hit's recency is written only with the next change to the store) (A3)
- **file:line:** `exercise_media_store.dart` `read` bumps `shown` in memory only.
- **claim:** a session that only re-views cached files loses its recency bumps when the process dies.
- **verification:** author found the limit already written in `EXERCISE_MEDIA.md` section 3 ("recency bumps are persisted only together with a later change to the store"); section 9 said "eviction is by recency" without it.
- **status:** ruled to stand. Writing the index on every read would cost a write per open on both backends for a cache that reaches its cap only after about 365 distinct exercises. Cost if wrong: after a crash-heavy period the least-recently-shown order falls back to the last written one. Section 9 now says so.

## Finding 10 — P3 — missing_input (a non-finite size made a layout value look like a bad file) (A4)
- **file:line:** `exercise_animation_view.dart` `_decodeWidth` inside the `try` of `_decodeFirstFrame`.
- **claim:** `.round()` on infinity throws `UnsupportedError`; under reduce-motion the catch evicted and banned a good cached file, on the normal path the answer was silently dropped.
- **status:** fixed. A non-finite width decodes at `kMaxAnimatedDecodeWidth`. `[bp15]`, `[bp15b]`; mutant bp15 reddens both.

## Finding 11 — P3 — writer_reader_drift (the decode width and `autoplay` were frozen at the first answer) (A5)
- **file:line:** `exercise_animation_view.dart` `didUpdateWidget` returned early when only the object name was compared.
- **claim:** a rotation or a web window resize while the sheet is open left an up-scaled low-resolution picture; `autoplay` turning off while bytes were held never started the frozen decode.
- **status:** fixed. `_followLayout`: decode again when the picture needs more than 1.25x the decoded width (never narrower, so a window drag is at most a few re-decodes), evict the replaced provider, start the frozen decode. `[bp16]`, `[bp17]`; mutants bp16 (never), bp16b (any change), bp16c (narrower too), bp16d (no evict) and bp17 each redden.

## Finding 12 — P3 — writer_reader_drift (`_onBytes` replaced the provider without evicting the previous one) (A6)
- **file:line:** `exercise_animation_view.dart` `_onBytes`.
- **claim:** media A, B, A inside one fetch window lets both answers for A pass the guard and the first provider stays in the `ImageCache`. Unreachable in M2a (the sheet's view never swaps media), reachable in M2b.
- **status:** fixed. `[bp18]`; mutant bp18 reddens it. `[bp21]` (A answers late while B is pending) and mutant bp21 ("accept only while no bytes are held") pin the other order.

## Finding 13 — P3 — guard_without_its_mirror (a store write error evicts a healthy file before the cause is known) (A7)
- **file:line:** `exercise_media_store.dart` `_putLocked`.
- **claim:** any exception from the first write, not only out-of-space, evicts the oldest other entry and retries once.
- **status:** ruled to stand, and now pinned by Finding 3's test. The loss is bounded: one file per `put`, and the repository stops attempting `put` for 5 minutes after a failure. Telling "disk full" from "folder unwritable" is not reliable across Android, Windows and IndexedDB, and failing to free space on a real full disk is the worse error. Cost if wrong: a persistently unwritable folder costs one cached animation per 5 minutes of use.

## Finding 14 — P3 — race (an `evict` that overtook an in-flight `ensure` was undone by that ensure's `put`) (A8)
- **file:line:** `exercise_media_repository.dart` `_download` (the put), `ensure` (the hit).
- **claim:** the ban recorded by `evict` was not checked again after the download or after the store read.
- **status:** fixed. The ban is checked again before the put (the bytes are neither stored nor served) and after the read. `[bp3]`, `[bp3b]`; mutants bp3 and bp3b redden them.

## Finding 15 — P3 — missing_input (no cap on the body while it is buffered) (A9)
- **file:line:** `exercise_media_client.dart` `_get`.
- **claim:** `ResponseType.bytes` buffers the whole body and `isWellFormedWebp` rejects an oversized one only after it is read.
- **verification:** author read Dio 5.9.2: `onReceiveProgress` is fired for every response stream, including an in-memory body from the test adapter (it first made the existing "oversized body" case lose its status; the status line is now captured in `validateStatus` so the answer stays `refused` with status 200).
- **status:** fixed. A body that reports more than `kMaxWebpBytes`, received or declared, is cancelled while it streams and counts as refused. `[bp9]`, `[bp9b]`, `[bp9c]` (exactly the cap passes); mutants bp9, bp9b, bp9c, bp9d (unreachable instead of refused) and bp9e (status lost) redden.

## Finding 16 — P3 — blank_frame (the animation replaced the still before its first frame was decoded) (A10)
- **file:line:** `exercise_animation_view.dart` playing `Image`.
- **claim:** an `Image` paints nothing until its first frame decodes while the still fades out over 250 ms; on a slow phone the tile is blank, which the design lists as an anti-goal.
- **status:** fixed. The playing `Image` has a `frameBuilder` that keeps an unkeyed copy of the still until the first frame is there. `[bp19]`; mutant bp19 reddens it. New bug class 2.141.

## Finding 17 — P3 — asserted_fixture_value (the bundle script's copy mode had no test; an empty table passed) (B7)
- **file:line:** `scripts/bundle_exercise_stills.js` `copyAll`, `readTable`.
- **status:** fixed. A staged-source fixture covers the copy, a flipped source byte, a missing thumbnail, an unknown ledger id and a climbing thumbnail path, each asserting that nothing was written; a table that names no stills is a hard stop. Mutants bp26 (no zero-file stop), bp27 (no pre-copy sha check) and bp28 (no path rule) redden.

## Finding 18 — P3 — guard_without_its_mirror (the source-grep family could be walked around) (B8)
- **file:line:** `test/contracts/exercise_media_reads_without_storage_from_test.dart`.
- **claim:** `gateAndVerify` and `proStateSnapshot` were not forbidden, and a new reader outside the `exercise_media` folder was never scanned.
- **status:** fixed, in two steps (see Finding 29): the names are forbidden and a lib-wide completeness test fails for any file that mentions the animation symbols and is neither on the list nor on a one-entry reviewed allow-list. Mutants bp24, bp24b, bp25 redden.

## Finding 19 — P3 — number wrong in docs ("100 MiB (about 100 files)") (B9)
- **status:** fixed ("about 250 files at the average size of 412 KB"; recomputed: 253,550,820 bytes over 616 files).

## Finding 20 — P3 — number wrong on the board (923 thumbnails) (B10)
- **verification:** author recounted the founder's two folders: 924 files each.
- **status:** fixed (OI-443 says 924 and that it was recounted).

## Finding 21 — P3 — writer_reader_drift (registry line ranges were loose) (B11)
- **status:** fixed. All five ranges are now the exact bounds of their symbols (`resolveMedia` 19-32, `ensure` 95-127, `put` 479-482, `_request` 137-145, sheet `build` 137-141).

## Finding 22 — P3 — guard_without_its_mirror (the two first-outcome latches were tested one kind at a time) (B12)
- **status:** fixed. `[bp4]`, `[bp4b]` (refused then unreachable, and the other order). Mutant bp4 (one shared latch) reddens.

## Finding 23 — P3 — guard_without_its_mirror (client tests: the cooldown instance, the web path, the logging control) (B13)
- **status:** fixed. `[bp6]` two client instances share the cooldown (mutant bp6), `[bp8]` web has no 60 s cap (mutant bp8), and `[e]` now proves its capture hooks capture (mutant bp10).

## Finding 24 — P3 — guard_without_its_mirror (view tests: a weak finder, one ordering, fixed sleeps) (B14)
- **status:** fixed. The 44 px test measures the keyed target (mutant bp20 reddens it), `[bp21]` runs the A-late order, and `_settle` polls for a condition instead of trusting one 150 ms sleep.

## Finding 25 — P3 — guard_without_its_mirror (the logEvent leg of the totality guard was unpinned) (B15)
- **status:** fixed. `[bp5]`; mutant bp5 (no `catchError` on the event) reddens it.

## Finding 26 — P3 — asserted_fixture_value (the sign-out test used a different box name from the real one) (B16)
- **status:** fixed. `[c]` opens the real `HiveService.mediaBlobStoreName`; `[bp14]` pins that the name is used exactly three times in `hive_service.dart` and never in `user_repository.dart`. Mutant bp14 (a fourth use as a list) reddens it.

## Finding 27 — P3 — missing_input (a damaged index file threw and emptied the index for the session) (B17)
- **file:line:** `exercise_media_store.dart` `FileExerciseMediaBytesStore.readMeta` (strict UTF-8).
- **status:** fixed. Decoded with `allowMalformed`, so a damaged index reads as unparsable and every blob is re-adopted. `[bp13]`; mutant bp13 reddens it. The reviewer's second point (the fake's `read` is a call-time snapshot while a real file can vanish between `exists()` and `readAsBytes()`) ruled to stand: the real outcome is a null read, which the repository treats as a miss.

## Finding 28 — P3 — asserted_fixture_value (the compile-gated presence pin is weaker than its comment) (B19)
- **file:line:** `test/contracts/exercise_media_fallback_chain_test.dart:255-270`.
- **claim:** the first-`errorBuilder` pin strips only `//` comments and checks substrings within 260 characters, so swapping the branches still passes.
- **status:** ruled to stand. The test is declared PRESENCE ONLY with its reason in its own header (an absent asset hangs the harness, so the face order cannot be run); the behavioural coverage of the face order is in the other cases of that file. Cost if wrong: a swap of the two branches inside `errorBuilder` is caught only in review.

## Finding 29 — P1 — asserted_fixture_value (found by the author's mutation proof: the two new forbidden-word patterns could never match)
- **file:line:** `test/contracts/exercise_media_reads_without_storage_from_test.dart` `[w]`, the `gateAndVerify` and `proStateSnapshot` patterns.
- **claim:** written through a scripted edit, the two word-boundary patterns held literal backspace characters (0x08) instead of backslash-b, so `[w]` stayed green with the forbidden word present. No reviewer saw it: the line renders as correct.
- **verification:** mutants bp24 and bp24b (the word added to the view) SURVIVED; `od -c` on the line showed `\b` as one byte; a byte scan of every changed file found no other control character.
- **status:** fixed in the follow-up commit; re-run, both mutants are killed by `[w]`. The same slip happened once more in a skill log line (fixed, scanned). Recorded in the escape-trap memory class.

## Mutation proof (rule 21), run on HEAD 6b9f5571 with a harness that refuses a mutant whose anchor does not occur exactly once and restores each file byte for byte (git status clean after every run)
38 mutants, one per new protection: 36 killed by the case written for them (bp1, bp2, bp2b, bp3, bp3b, bp4, bp5, bp6, bp7, bp8, bp9, bp9b, bp9c, bp9d, bp9e, bp10, bp11, bp12, bp13, bp14, bp15, bp16, bp16b, bp16c, bp16d, bp17, bp18, bp19, bp20, bp21, bp24, bp24b, bp25, bp26, bp27, bp28); 2 survived by design: bp22 and bp23, the two `_generation++` lines that throw a stale frozen-frame decode away. A real codec's completion order cannot be scripted, so no unit test can see them; the limit is written into the view's header.

## Tuning entry
- **2026-10-31** - blast-radius platform - 28 findings; 0 false_alarm; tuning: ask every reviewer of a batch whose tests use fakes to name, for each protection, the one-line production change that should turn it red and to hand-walk it (reviewer B's three P1 came from exactly that question), and treat any scripted edit that writes a backslash as suspect until a byte scan of the changed files is clean: this batch's only defect no reviewer could see was a test regex written with a backspace character, caught only because the mutation proof added the forbidden word and the pin stayed green.
