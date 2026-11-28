# Plan: mark the portrait screen feature optional in the Android manifest

Date: 2026-11-22. Branch `manifest-portrait-optional`. Blast radius: **account** (`android/**`, `docs/blast_radius.yaml:674`). Execution mode: inline (one unit, one coordinator).

## Why

`com.yalantis.ucrop.UCropActivity` (the image-crop screen, declared in `android/app/src/main/AndroidManifest.xml`) carries `android:screenOrientation="portrait"`; it is the ONLY orientation lock in the app (`MainActivity` has none and rotates). Android derives a REQUIRED `android.hardware.screen.portrait` feature for the whole app from ANY activity's portrait lock. Play Console, on release 1.0.0+50 (internal testing), warned: "Required hardware feature declarations are restricting your app's availability: `android.hardware.screen.portrait` affects Phone, Tablet, Desktop and Android XR users". Users on devices that cannot show a portrait screen cannot install the app.

## Change (one unit)

1. `AndroidManifest.xml`: add `<uses-feature android:name="android.hardware.screen.portrait" android:required="false" />` as a direct child of `<manifest>`, before `<application>`. The crop activity's portrait lock stays.
2. `test/contracts/android_portrait_feature_optional_test.dart` (presence-only, same style as `android_speech_queries_test.dart`): the element exists with `required="false"`, it is NOT inside `<application>`, and the `UCropActivity` portrait lock is unchanged.

Out of scope: any versionCode bump or build (the founder builds from his laptop; the change rides the next AAB), rotation support, the other implied features.

## Claims to verify (reviewers)

- C1. The `UCropActivity` portrait lock is the only source of the implied feature in THIS manifest (`MainActivity` has no `screenOrientation`), and no other `<uses-feature>` is declared in it. (Round 1 corrected the first draft, which wrongly said MainActivity.)
- C2. No plugin or library manifest declares `android.hardware.screen.portrait` with `required="true"`. Round 1 checked the 23 pub plugins (none declares it; only `mobile_scanner` has a `<uses-feature>`, camera, `required="false"`). Transitive Maven/AAR manifests (UCrop, razorpay, onesignal, firebase, RevenueCat, ML Kit, Health Connect) could NOT be checked on this VPS (empty Gradle cache). The manifest merger can let a library's explicit `required="true"` win over the app's `required="false"`, so the real proof is the next AAB. `/build-apk` does NOT print the merged manifest (round 2 checked; the first draft of this plan wrongly said it did), so the check is by hand and is owned by `docs/operations/GO_LIVE_CHECKLIST.md` row 5.9: `bundletool dump manifest --bundle <aab>` must show the feature with `android:required="false"`, and the Play Console warning must be gone on the first build that carries this change. Failure action: if a library still forces it to required, name the library, add `xmlns:tools="http://schemas.android.com/tools"` to the manifest root (it has only `xmlns:android` today) and a `<uses-feature ... tools:node="replace" />` override; the change is not considered done until the warning is gone.
- C3. A `<uses-feature ... required="false"/>` in the app manifest is the documented way to relax an implied requirement, and it does not change runtime behaviour (the crop screen stays portrait-locked wherever it runs).
- C4. No test, gate, skill or doc reads the manifest in a way this edit breaks (`grep -rn AndroidManifest test/ scripts/ .claude/`), including the `/build-apk` merged-manifest checks.
- C5. The other implied features (camera and microphone from `CAMERA` / `RECORD_AUDIO`) are not what Play flagged on 1.0.0+50 (only `screen.portrait` was listed), and nothing in this change touches them.
- C6. The contract test fails when the protection is neutered (four mutants, each reddening one test: `required="true"`, element deleted, element moved inside `<application>`, the UCropActivity lock dropped).

Out of scope, added after round 1: other implied hardware features. Camera is already optional (`mobile_scanner` declares it `required="false"`); microphone (`RECORD_AUDIO`) stays an implied required feature on purpose: the Console lists only `screen.portrait` today, and a later warning would be its own change.

## Rollback

Revert the commit; the next AAB then carries the old (implied required) feature again. No data, no schema, no cloud state is involved.

## History of this plan

The change was built and pushed (PR #318) BEFORE the tier was measured correctly: `blast_radius_from_diff.dart --staged` fails open and printed `feature`; the merge gate then measured `account`. This plan and its two review rounds were written after the build, against the built diff, and the record says so.
