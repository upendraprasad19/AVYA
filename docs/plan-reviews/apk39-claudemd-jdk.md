---
branch: apk39-claudemd-jdk
date: 2026-08-28
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/apk39-claudemd-jdk-bpass.md
---

# Plan-review record — apk39-claudemd-jdk (platform)

Keystone record for the §4.12 merge gate. Platform tier because the change touches root
`CLAUDE.md`, which is path-pinned platform in `docs/blast_radius.yaml`.

## What the branch is

**One row** added to §4.9's "Common process pitfalls" table: `flutter build apk` dies with
`JAVA_HOME is not set` because the Android build has always depended on Android Studio's bundled
JDK, and Android Studio was uninstalled after 2026-08-06. The row carries the fix (JDK 21), the
JDK-17 misreading trap, and the daemon-log diagnostic.

## Why this branch exists at all — the process failure worth recording

**This content first landed as `acd6c818`, a direct commit to `main`.** The keystone gate failed
it, `git-safety`'s advisory precheck surfaced that before the push, and the commit was rewound
(`git reset --mixed ebc65ad3`, nothing had been pushed) and re-landed here.

The reasoning that produced the mistake, stated so it is not repeated: I asserted that
`check_plan_review_record_exists.dart` keys on `HEAD^1..HEAD^2` and therefore cannot apply to a
single-parent commit. **That was true before 2026-07-27 and is false now** — the gate's own error
text cites `be3b4baf` and `8c38c855`, two account-tier auth commits that shipped direct-to-main
while it *"exited before looking"*. The immediately preceding versionCode commit (`dfb725c3`)
passed the gate via the **version-bump exemption** — byte-identical to its parent once the version
token is normalised — not because direct commits are exempt. I generalised from one passing case
whose reason I had not checked.

Also verified while fixing: stacking a merge commit on top would NOT have cleared it. The gate
inspects the pushed **range** and explicitly refuses to narrow to `HEAD^1` (its P2-1 comment), so
`acd6c818` would have stayed visible however commits were piled above it. Rewinding was the only
correct repair.

## Review type

Per §4.3: *"Docs/process-only ≥account changes — e.g. CLAUDE.md edits — take a self-consistency
review of the wording instead of an adversarial bug-hunt."* Docs-only, so: a self-consistency
check of the wording plus a ground-truth audit of every factual claim.

## Round 1 — ground-truth audit

**FINDING, corrected — the central claim was under-verified.** The row said *"every APK +35→+38
used Android Studio's bundled JetBrains Runtime"*, but only ONE log (`daemon-12296`, the +38
build) had actually been read for its `javaHome=`. The other three were inferred from mtimes
matching ship dates — which establishes *when* a daemon ran, not *which JVM* it used.

Audited properly: `javaHome=` enumerated across **all 111** logs in `~/.gradle/daemon/8.14/`.
Every log dated 2026-03-30 → 2026-08-06 reads
`javaHome=C:\Program Files\Android\Android Studio\jbr,javaVersion=21,javaVendor=JetBrains s.r.o.`
The one exception is `daemon-19588` (2026-08-27), today's Microsoft JDK build. The claim holds,
and holds more widely than it was stated.

**Verified accurate:** Android Studio absent (`C:\Program Files\Android` empty of subdirectories);
no JDK anywhere before the install; Android SDK intact at `%LOCALAPPDATA%\Android\Sdk`;
`sourceCompatibility = VERSION_17` at `build.gradle.kts:25-30`; the Windows env-var propagation
trap reproduced; `+39` built clean on Microsoft OpenJDK 21.0.12.1 with Gate 48 and Gate 13 PASS.

## Round 2 — self-consistency of the wording

Three checks, all pass.

1. **Does the row contradict anything already in CLAUDE.md?** §0's build commands do not mention a
   JDK; §4.9's neighbouring "Gradle build hangs silently" row covers `-Xmx` and the Flutter
   lockfile. No overlap, no contradiction — this is a genuinely uncovered failure mode sitting
   next to its closest relative.
2. **Is the Source citation real?** `docs/playbook/common-pitfalls.md` contains the full entry
   (landed in `ebc65ad3`). Not a phantom citation. Gate 26 PASS — all §N citations resolve across
   16 CLAUDE.md/AGENTS.md files and 1688 source files.
3. **Is the advice actionable without further lookup?** The row states the install command, the
   version and why 21 not 17, the diagnostic grep, and the env-var propagation trap. A reader
   hitting this at 2am can act from the row alone.

## Ground truth verified

- 111 Gradle daemon logs enumerated individually for `javaHome=`, not sampled.
- `C:\Program Files\Android` listed: no subdirectories.
- JDK search across `Program Files`, `Program Files (x86)`, `LOCALAPPDATA\Programs`, `.jdks`,
  `.gradle\jdks`: none present pre-install.
- `android/app/build.gradle.kts:25-30` read directly for the VERSION_17 settings.
- Gate 26 (`check_claude_md_citations.dart`) re-run: PASS.
- `+39` artifact: 123,393,833 bytes, md5 `29d54b41ca29f339c8ba57e9806559e4`, Gate 48 PASS
  (`CN=ICANBEFITTER`), Gate 13 PASS (+0.1%).

## Verdict

`converged`. The row is correct and worth having; its one under-verified claim was audited to
ground truth and proved true across a wider set than asserted. The process failure that sent it
down this path is recorded above rather than quietly fixed.
