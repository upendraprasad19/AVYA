# Cleanup batch — triage (post-merge, post-H38)

Date: 2026-05-11
Author: Claude
Purpose: Answer "lets do this meticulously. do you have anything waiting on me?"

Inventory taken from `docs/diagnoses/2026-05-11-phase8-cleanup-7ad0da.md`
("What's deferred to a future batch") + verified against current repo
state on `main` HEAD `b9e027a`.

## TL;DR

| Group | Items | Who's blocked? |
|-------|-------|---------------|
| A — Claude autonomous, zero decisions | 4 | nobody |
| B — Needs ONE founder call before Claude can start | 5 | you |
| C — Pure founder action (Claude can't do) | 2 | you |

---

## Group A — Claude autonomous (start anytime, no input needed)

These are mechanical. Each ships as its own commit; no scope-creep risk.

### A-1. `.env.example` `rzp_live_` → `rzp_test_` (1 line)
File: `.env.example:3` currently shows `RAZORPAY_KEY_ID=rzp_live_your-key-here`.
Should be `rzp_test_` for the placeholder. One-line edit + commit.
Effort: <1 minute.

### A-2. 21 remaining `debugPrint` catches → `ErrorTelemetry.recordNonFatal`
The H-42 retrofit closed 7 hot-path services in Phase 8. The grandfathered
allowlist in `test/contracts/no_silent_debugprint_in_services_test.dart`
still has 21 entries — all `lib/core/services/*` + `lib/shared/repositories/*`.
Pattern is the same in each file: add `import 'dart:async';` +
`import 'error_telemetry.dart';`, replace `catch (e) { debugPrint(...) }`
with `catch (e, st) { debugPrint(...); unawaited(ErrorTelemetry.recordNonFatal(e, st, reason: '<unique_op_type>')); }`.
Each file = its own commit + diagnose doc (per CLAUDE.md rule 22).
Effort: ~3-4 hours sequential. Could parallelize into ~5 commits if I batch
2-4 files per commit (cohesion: same subsystem).

### A-3. Wardroom barrel doc sync
CLAUDE.md §9 says "28 primitives"; actual count in
`lib/shared/widgets/wardroom/wardroom.dart` is 36 exports.
Update the §9 table to enumerate all 36 + their files + their purpose.
Effort: ~30 minutes.

### A-4. CLAUDE.md §7 table list refresh
§7 says "37 Tables". Actual count via `list_tables`: likely higher after
migrations 044, 045, 047, 049, 050b, 052-059. Refresh the count + the
domain table + the FK-quirk notes (especially after migration 049
moved 5 community FKs to `ON DELETE SET NULL`).
Effort: ~30 minutes.

---

## Group B — Needs ONE founder call before I can start

Each of these has a fork in the road. Once you pick, I do the work.

### B-1. Web manifest branding (`web/manifest.json` + `web/index.html`)
Current state: still says `"icanbefitter"` / "A new Flutter project" /
Flutter-blue theme color `#0175C2`.

**Decision needed:**
- `name` + `short_name`: pick one — `AVYA` / `ICANBEFITTER` / `AVYA — Wardroom Fitness` / other?
- `description`: 1-line tagline (current "A new Flutter project" needs to go)
- `theme_color` + `background_color`: I'd recommend `#02070F` (AppColors.bg) + `#D4B270` (AppColors.accent) — confirm?

Effort once decided: ~10 minutes.

### B-2. R8/ProGuard enabling (`android/app/build.gradle.kts:67-79`)
Current state: `isMinifyEnabled` not set → defaults to FALSE for release.
`proguardFiles` are configured but ignored. APK ships unminified at 100.3 MB.

**Decision needed:** Enable R8 minification + add keep-rules for Razorpay,
OneSignal, Hive (TypeAdapters), Riverpod (codegen), Supabase
(gotrue/postgrest reflection), Crashlytics native, AndroidX Health Connect?

**Risk:** Reflection-based libraries can silently NPE in release if the
keep-rules miss a class. Enabling R8 always needs a full release-APK
verification cycle on-device (login → onboarding → log workout → AI coach →
payment → photo upload → restore from cloud). I cannot just enable + ship.

**Expected reward:** 100 MB → ~65-75 MB (Hermes estimate).

**My recommendation:** YES enable + ship in same APK cycle as the size
analysis (B-5). Pair them. The cycle of "enable R8 → ship test APK →
hit one missing keep rule → ship +1 → repeat" usually takes 1-2 APK
test cycles to converge.

Effort once decided: ~2-3 hours (initial keep-rules write) + iterative
fixes during APK testing.

### B-3. `analysis_options.yaml` lint wire-up
Current state: only `flutter_lints` defaults; empty `rules:` block.

**Decision needed:** Enable which rules? Three candidate sets:
- **Minimal:** `unawaited_futures: true` + `avoid_dynamic_calls: true` + `prefer_const_constructors: true`. Catches CLAUDE.md §6 violations. Estimated ~50-100 existing offenders.
- **Recommended:** Above + `prefer_single_quotes` + `require_trailing_commas` + `directives_ordering`. Estimated ~500+ existing offenders.
- **Aggressive:** Full `package:lints/recommended.yaml`. Estimated ~2000+ existing offenders.

**Risk:** Big-bang lint enable will block `flutter analyze` (pre-commit
hook) on every commit until all offenders are fixed. Standard fix: enable
with `// ignore_for_file:` allowlist, retrofit one file at a time.

**My recommendation:** Minimal. Catches the highest-value bugs (unawaited
fire-and-forget syncs, dynamic-call NPEs) without a months-long retrofit.

Effort once decided: ~1 hour wire-up + ~4-8 hours retrofit per rule level.

### B-4. Major dependency bumps
13 direct deps outdated. The non-trivial ones (major-version-behind):
- `image_cropper` 8.1 → 12.2 (4 majors — breaking API changes expected)
- `share_plus` 10.1 → 13.1 (3 majors)
- `firebase_core` 3.15 → 4.7
- `firebase_crashlytics` 4.3 → 5.2
- `mobile_scanner` 6.0 → 7.2

**Decision needed:** One bump per commit (slow, safe) OR all-five-in-one
batch (fast, riskier — if any one breaks, hard to bisect)?

**My recommendation:** One per commit. Each ships with its own diagnose
+ test pass + manual verification of the affected feature (image_cropper
= avatar/banner upload; share_plus = receipt share; mobile_scanner = barcode
+ cart auditor; firebase = Crashlytics + push).

Effort: ~1-2 hours per dep depending on breaking changes (image_cropper
4 majors is the riskiest).

### B-5. `sync_service.dart` 4572-line file split

**Status:** CLOSED 2026-05-13 — split landed on branch
`refactor/sync-service-part-split` (10 commits, awaiting merge to main).
Chose **domain split** with 8 part files under
`lib/core/services/sync/`. Root file went from 5104 → ~1339 lines
(74% reduction). Mechanism: Dart `part`/`part of` + per-domain
`extension SyncService<Domain> on SyncService { ... }`. Spec:
`docs/superpowers/specs/2026-05-13-sync-service-part-split-design.md`.
Plan: `docs/superpowers/plans/2026-05-13-sync-service-part-split-plan.md`.

**Scope adjustment from plan:** Task 10 (extract infrastructure helpers
`_reportSyncFailure` / `_safeRestoreOp` / `_setTimestamp` etc. to a 9th
part file) was DROPPED at execution time after discovering Dart cannot
dispatch instance methods across extensions of the same type. Those
helpers stay on the SyncService class body where every domain part file
can call them via `this._foo(...)`. Net: 8 part files instead of 9, but
the refactor goal (split for readability) is achieved.

**Process notes for future refactors:** the test-surface impact was
~10× the plan's estimate (66 contract-test references to
`sync_service.dart` across 41 files, vs the plan's awareness of 2). Most
broke on the first extraction. Required interstitial Task 1.5 to add a
`loadSyncServiceSource()` helper at `test/contracts/_sync_service_source.dart`
and migrate 37 test files to call it. Future part-file splits should
audit `grep -rl sync_service.dart test/` BEFORE the first extraction
commit, not after.

---

Single class doing 7 sync ops + 6 restore ops + helpers + idempotency +
fan-out + retry logic.

**Decision needed:** Module boundaries. Three candidate splits:
- **By verb:** `sync_service/{syncers, restorers, helpers, idempotency, retry}.dart`. Mechanical, low-risk.
- **By domain:** `sync_service/{workout, nutrition, health, custom_items, profile, freezes, inbox, diet_plan}.dart`. Reflects audit's "fan-out contract" model.
- **Hybrid:** Domain-first with shared `_helpers.dart`.

**Risk:** This file is the source of truth for half the project's
correctness. Hermes audit (R2) flagged it as the #1 refactor risk —
"any split needs paired contract tests AND a real APK ship cycle to
validate". I do NOT recommend doing this in the same batch as anything
else.

**My recommendation:** Defer until after the next APK ship + bake-time.
Schedule its own named batch.

Effort once decided: ~6-10 hours core split + ~4 hours test updates +
1 APK ship cycle to validate.

---

## Group C — Pure founder action (I cannot do these)

### C-1. APK size analysis (`flutter build apk --analyze-size`)
Running this IS an APK build. Per your standing rule "do not build APK
without approval", I cannot run it autonomously.

**Action you can take:** Approve a build cycle. I run it, capture the
per-dep contribution table, file findings + diagnose. No deployment —
just a measurement build.

OR fold it into the next real APK ship cycle: enable R8 (B-2) +
analyze-size flag on the same `/build-apk` invocation.

### C-2. Phase 7 integration test BODIES
10 scaffolds shipped under `integration_test/flows/`. Bodies need a
device-CI provider.

**Decision needed:** Which provider?
- **Firebase Test Lab** — Google-owned, $1-5/run for a 10-test suite, paid via Firebase billing tied to fitness-app account.
- **BrowserStack** — premium, ~$30/mo for the App Live tier.
- **Local-only / WSL** — free, but no CI gate (manual run before each ship).
- **Skip device-CI; rely on manual on-device testing per APK** — what we've been doing.

**My recommendation:** Skip device-CI for now. Manual APK testing has
caught everything so far. Re-evaluate when the user base grows past
~1000 active devices (where regression cost > CI cost).

---

## What's pending on YOU after this triage

If you want minimum founder input:

1. **Approve Group A start** — I run A-1 through A-4 as 4 commits, ~5 hours total. No further input needed during.
2. **Pick B-1 brand strings** — name + short_name + description + theme colors (5 fields, can do in 2 minutes).
3. **Pick B-3 lint level** — minimal / recommended / aggressive.
4. **Defer B-2 (R8) and B-5 (sync_service split) until I batch them with a real APK ship cycle.**
5. **Defer C-1 + C-2 — both need explicit ship/CI approval; not blocking.**

If you want maximum throughput:

- Tell me to start Group A immediately while you decide B-1 / B-3 strings.
- B-4 (dep bumps) is fine to do one-per-day in parallel with other work.

## Items NOT in scope (already shipped or N/A)

- ProGuard rules file — exists at `android/app/proguard-rules.pro` but unused until B-2.
- `_intentionallyShared` keys (pending_referral_code, logout_in_progress) — these are correctly excluded; not cleanup work.
- Test #11 / Test #12 / Test #12.5 / Test #12.6 follow-ups — already shipped.
- `delete-account` flow — shipped Test #11.
