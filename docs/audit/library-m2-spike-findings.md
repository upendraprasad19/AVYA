# Batch M2a spike findings (Task 1)

Date: 2026-10-31. Plan: `docs/plans/2026-10-28-library-batch-m2-app-delivery.md` Task 1. Nothing from the spike is kept as code; this file is the whole deliverable.

The founder has not supplied a QA login or a phone in chat, so everything that needs a real user token or a device is `blocked_on_user` (closure ledger). The one check that needs neither was run.

| Id | Question | Result | Consequence |
|---|---|---|---|
| S1 | Does an animated WebP animate inside the Flutter app (web, Android)? | UNOBSERVED (`blocked_on_user`: needs a spike run on a phone and in Chrome) | Both platform switches ship `true` (Task 7); observed in the post-merge device check, Task 10 Step 8 |
| S2 | Status and first bytes of a real object read with a real user's token | UNOBSERVED (`blocked_on_user`: needs the QA login) | M1 already proved the same read with the service key for all 616 files (`docs/operations/EXERCISE_MEDIA.md` section 9); the user-token read is observed in Task 10 Step 8 |
| S3 | CORS answer to an Authorization header on the authenticated GET (web) | UNOBSERVED | Ladder: web ships the direct-GET path with `kWebAnimationsFetchEnabled = true`; a CORS refusal ends `unreachable` and the still stays; the signed-link fallback (Task 6 Step 6) is NOT built; web observation moves to Task 10 Step 8 |
| S3b | CORS answer on `POST /object/sign` (web) | UNOBSERVED | Only matters if S3 is later seen blocked |
| S4 | Status for a bad token versus an absent object | UNOBSERVED | Task 6 keeps one retry rule for all non-200 answers (no narrowing) |
| S5 | Response headers (`cache-control`, `etag`, `content-length`) | Partly known from M1: the signed response carries `ETag`, `Expires`, `Last-Modified`, `Accept-Ranges`, `Access-Control-Allow-Origin: *`, no `Cache-Control` (EXERCISE_MEDIA.md section 9). The authenticated-route headers for a user token are UNOBSERVED | The app caches by object name on the device, so the header is not load-bearing |
| S6 | Memory and first-frame time for the worst-case file `3214-arms-apart-circular-toe-touch` (48 frames) | UNOBSERVED (`blocked_on_user`: needs a phone) | Task 9 builds with the defaults (`kMaxAnimatedDecodeWidth` 720, both switches true); the 360 re-measurement under the S6 rule becomes part of Task 10 Step 8 |
| S7 | RIFF size rule and ANIM loop count | **OBSERVED, see below** | Store predicate keeps the full RIFF size check; loop count is infinite (C10 holds) |
| S8 | Web store byte type and persistence across a reload (`Hive.openLazyBox`, 988,000-byte `Uint8List`) | UNOBSERVED here (needs a Flutter web run) | The web store coerces any `List<int>` (Task 5); persistence is checked against the real web store at Task 10 Step 8; until then the "second open works offline" claim on web is written as unverified |

## S7 detail (observed)

Script: a one-off Node reader over every `*.webp` in `.../wardroom customized gifs/webp-720/` (924 files, a superset of the 616 mapped to library rows). For each file: `RIFF`/`WEBP` magic, `RIFF size + 8 == file length`, the `ANIM` chunk's loop count, the `ANMF` frame count.

- Files scanned: 924. RIFF-size violations: **0**. Non-RIFF files: **0**.
- Loop count: **0 (infinite) on all 924**. Non-zero loop counts: **0**.
- Files with more than 24 frames: 10 of the 924.
- Largest file in the whole folder: 999,800 bytes (`0551_Kettlebell_Squat_Style_Turkish_Get_Up_wardroom_720.webp`), under the 1,500,000 byte ceiling the store uses. The largest of the 616 mapped files is 987,558 (EXERCISE_MEDIA.md).

Verdict: S7 violations are 0, so Task 5 and Task 6 keep the full predicate (length, magic, size field).

## Ledger verdicts

- S3 UNOBSERVED: web direct GET, switch true, no signed-link fallback built.
- S1, S2, S3, S3b, S4, S6, S8: `blocked_on_user`, to be observed in Task 10 Step 8 (post-merge device and web check).
