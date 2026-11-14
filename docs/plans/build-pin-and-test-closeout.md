# Build pin + test close-out (after PR #140) — v2 (round-1 review folded in)

Branch / worktree `build-pin-and-test-closeout`, based on `main` `37c7498e`. Execution mode:
inline, one writer. Blast radius: **account** (`android/**` → `docs/blast_radius.yaml:561`), so
this plan takes 2 review rounds, `docs/plan-reviews/build-pin-and-test-closeout.md`, and a
self-initiated B-pass.

**Commits (as planned in v2; v3 below replaces this with ONE commit):**
1. `fix(build): pin the Razorpay Android SDK's dynamic dependencies` (U1, closes-diagnose U1 id)
2. `fix(test): widen the restore-paging hang guard under machine load` (U3, closes-diagnose U3 id)
3. `docs(diagnoses): 9b1621 Windows path class, retroactive` + debugging bug-class 2.111 (U2)

Every new diagnose-doc passes `dart run scripts/validate_diagnose_doc.dart` (all required fields;
"slim" only means short `not_applicable` values; no TBD/TODO substrings). Ids are minted with
`openssl rand -hex 3` and checked against `ls docs/diagnoses`.

## U1 — pin the Razorpay SDK's dynamic dependencies

**Symptom.** `main` CI run 39618403587 (`37c7498e`, PR #140's merge) failed Build Check (APK):
"Could not find any matches for com.razorpay:checkout:1.6.+ as no versions of
com.razorpay:checkout are available". The re-run passed. That merge touched no `android/` or
`pubspec.*`.

**Writers of the requirement (not ours).**
- `razorpay_flutter` 1.4.5 (`pubspec.lock:1266`) has `api 'com.razorpay:checkout:1.6.+'` at
  `android/build.gradle:37` in the pub cache. 1.4.1 and 1.4.7 are identical.
- `checkout-1.6.41.pom` declares `com.razorpay:standard-core` with `<version>LATEST</version>`.
  Gradle reads that as `latest.integration`. (Round-1 P1.)

**Reader.** Gradle's resolver, on every Android build (CI Build Check, `/build-apk`, local). Each
dynamic selector forces a fetch of that module's version listing (`maven-metadata.xml`). When a
listing comes back empty or fails, the build fails.

**Measured baseline** (`./gradlew :razorpay_flutter:dependencies --configuration
debugCompileClasspath --refresh-dependencies --debug`, before the fix):
- `checkout:1.6.+ -> 1.6.41`; `standard-core:latest.integration -> 1.7.20`; `core:1.0.20`
  (through standard-core).
- References to the listing in the debug log: `com/razorpay/checkout/maven-metadata.xml` × 35,
  `com/razorpay/standard-core/maven-metadata.xml` × 44, `com/razorpay/core/` × 0.

**What shipped.** Gradle-cache directory dates show `standard-core` 1.7.19 and `core` 1.0.19
were downloaded 2026-09-23 10:58, the day AAB 1.0.0+46 (the last shipped build) was made. 1.7.20
was released 2026-10-14 (Maven `lastUpdated 20261014043907`) and first fetched here by today's
baseline. So builds since Oct 14 silently moved to an SDK version no shipped build has used.

**Fix.** In `android/build.gradle.kts`, add
`subprojects { configurations.configureEach { resolutionStrategy.eachDependency { … } } }`. It
pins `com.razorpay:checkout` → `1.6.41` and `com.razorpay:standard-core` → **`1.7.19`**, each
with `useVersion(...)` and `because(...)`.
- `standard-core` 1.7.19's POM fixes `core` at the static `1.0.19`, so `core` needs no pin.
- Pinning 1.7.19 is a deliberate step back from today's floating 1.7.20, to the version that
  shipped in internal testing. Moving to 1.7.20 later is a deliberate bump plus a device payment
  test.
- `configureEach` covers configurations created later. No `afterEvaluate`: the existing
  `evaluationDependsOn(":app")` already evaluated the projects.
- Rejected: `force(...)` (the listing proof below decides it, not theory); editing or bumping the
  plugin (1.4.7 has the same `1.6.+`).

**Verify.**
1. Behavioural proof: the same `--refresh-dependencies --debug` run after the fix. The count of
   `com/razorpay/[a-z-]*/maven-metadata.xml` references must be **0**, and the report must show
   `checkout -> 1.6.41`, `standard-core -> 1.7.19`, `core 1.0.19`.
2. Regression test `test/contracts/android_dynamic_dependency_pin_test.dart`, deterministic and
   offline:
   (a) In comment-stripped `android/build.gradle.kts`, an `eachDependency` rule names
       `com.razorpay:checkout` and `com.razorpay:standard-core`, each with an exact `\d+\.\d+\.\d+`
       `useVersion`, no `+` and no `latest`.
   (b) `pubspec.lock`'s `razorpay_flutter` version equals the audited `1.4.5`. A plugin bump
       reddens the test and forces a re-audit of new dynamic selectors.
   No SoT entry (build config: `sot_registry_entry: not_applicable`). Gate 42 is not involved.
3. Mutations, each confirmed by `git diff` before the run: remove the pin → red; change
   `1.6.41` → `1.6.+` → red; bump the lock to `1.4.7` → red.
4. Note for CI: editing `android/build.gradle.kts` changes the `~/.gradle` cache key
   (`test.yml:577-581`), so the first CI run after merge downloads cold. A cold-cache flake there
   is not this fix failing; the zero-listing proof is the evidence.

## U2 — retroactive diagnose-doc for the three Windows path fixes (PR #140)

Doc `9b1621`: full template; `related_bugs` cite by FILENAME (`d4e7c2` is used by two files):
`2026-09-27-alert-threshold-test-windows-path-separator-d4a7c1.md`,
`2026-09-30-migration-ledger-057-forward-slash-windows-path-d4e7c2.md`.
- Mutation re-proven on `37c7498e`: 3/3 red with the normalisation reverted (confirmed by
  `git diff`), 30/30 green restored.
- Bug class **2.111** goes in `.claude/skills/debugging/bug-classes.md`, plus its row in the
  SKILL.md index (per the file header).
- No gate. Record the exact measuring command and count in the doc, and say plainly that this
  class has NO automated guard: CI is Linux, so only a Windows full suite catches it.
- Not in scope: OI-167 (nine bug-class numbers already duplicated on `main`). It is tracked; 2.111
  adds no collision.

## U3 — the 50,000-row restore ceiling test timed out under machine load

**Symptom.** In the merge regression-catalog walk, `test/sync/restore_legacy_paging_behavioral_test.dart`
"a table that fills the ceiling emits ONE restore_row_ceiling_hit naming only the table" failed
with `TimeoutException after 0:02:00` (only `_within` can produce 2:00). It takes about 11 s
alone and 40 s for the file. Another session's full suite was loading the machine. It passed on
retry.

**Writer / reader.** The guard `_within` (`:55-57`, `.timeout(const Duration(minutes: 2))`)
versus the per-test `@Timeout(Duration(minutes: 5))` on `library;` (`:1`). The cost comes from
`test/helpers/sync_stub_server.dart:204-233`: `_pagedAnswer` re-filters and re-sorts all 50,000
rows on each of 50 page requests.

**Fix.** Raise `_within` to 4 minutes, still under the 5-minute per-test timeout. That gives
about 22x headroom over the measured run instead of 11x, and a real hang still fails at the guard
with its own message. It also covers the nutrition ceiling test at `:498`, which has the same
exposure.
- Rejected: memoising the stub's sorted page list. The stub is shared by 12 test files and some
  mutate `pagedTables` between requests, so a cache needs invalidation semantics that would be a
  new source of test-infra bugs.
- Rejected: an injectable ceiling (production sync code: `lib/core/services/sync_service.dart:3095`,
  `lib/core/services/sync/sync_nutrition.dart:636`).
- Rejected: retry-on-timeout, which hides hangs.

**Verify.** The file passes alone. Mutation: `_within` at 1 ms reddens the ceiling test with the
guard's TimeoutException. That proves only that the guard is live. The claim is "guard live, bound
< per-test timeout", checked by reading `:1` against `:57`. Diagnose-doc via the validator.

## Gates and close-out
After implementation and before the B-pass: `flutter analyze lib/`, the full `flutter test`
(TZ=Asia/Kolkata, `--exclude-tags golden`), and `sh scripts/pre-commit.sh`. Then the record, the
B-pass, the three commits via `safe_commit.sh`, a PR with auto-fix on, `safe_pr_merge.sh`, and main
CI green. Delete the copied gradle wrapper files (`android/gradlew*`, `android/local.properties`,
`gradle-wrapper.jar`, all gitignored) before retiring the worktree.

## v3 — round 2 (CONVERGED, P3 only) folded in during execution
- Kotlin shape fixed: a `pinnedAndroidDependencies` map looked up by `"${requested.group}:${requested.name}"`,
  declared ABOVE `evaluationDependsOn(":app")`. Test (a) asserts each coordinate's own exact x.y.z
  and that the rule sits in `subprojects { configurations.configureEach` before `evaluationDependsOn`.
- Test (b)'s failure message carries the re-audit recipe. `.github/dependabot.yml` is NOT edited:
  that would make the merge a workflow change, and the message is what a Dependabot PR author sees.
  The lock read tolerates CRLF.
- The SDK pin's "bump later" intention is tracked as **OI-383**.
- Wording: every built AAB (+46..+48, `backups/built_versioncodes.json`) predates 1.7.20 and used
  1.7.19.
- Whole-app measurement: `:app:dependencies --configuration prodDebugRuntimeClasspath
  --refresh-dependencies --debug`, listing every module whose `maven-metadata.xml` is still
  fetched (the release configuration needs the signing key, which is not copied into worktrees).
- Diagnose docs use in-repo `file:line` anchors only; the pub-cache fact is prose.
- Bug classes: 2.111 (Windows path) and 2.112 (floating version in a dependency we do not own),
  with SKILL.md index rows. The missing 2.109/2.110 index rows are backfilled in the same edit.
- Retirement cleanup: delete `android/gradlew`, `android/gradlew.bat`,
  `android/gradle/wrapper/gradle-wrapper.jar` and `android/.gradle/`. `local.properties` is
  regenerable and can stay.
- Commit placement (changed at execution): ONE commit `fix(build): ...` carrying three
  `closes-diagnose:` trailers (a6c3e9 first, the one commit-msg.sh validates; 7e2b5d and 9b1621
  validated by hand with scripts/validate_diagnose_doc.dart). Reason: bug classes 2.111 and 2.112
  and their index rows share two files, so a split would need partial staging.
- B-pass P3 (U3): "22x headroom" was wrong. 11 s is the UNLOADED time, and the loaded run is only
  known to exceed 120 s. The guard is now 8 min and the per-test `@Timeout` 10 min (4x the
  bound that failed); other test files already declare 8 to 14 minutes.
