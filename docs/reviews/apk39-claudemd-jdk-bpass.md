---
reviewed_at: 2026-08-28T00:20:00+05:30
staged_against: apk39-claudemd-jdk (one row added to CLAUDE.md §4.9)
blast_radius: platform
reviewer: claude-opus-5 (self-consistency + ground-truth audit)
review_type: self-consistency + ground-truth audit (§4.3 — docs/process-only ≥account change)
findings_count: 3
verdict: accepted
---

# Review — apk39-claudemd-jdk (platform, docs/process-only)

## What was reviewed and how

One row added to root `CLAUDE.md`'s §4.9 "Common process pitfalls" table, documenting that
`flutter build apk` fails with `JAVA_HOME is not set` because the build has always depended on
Android Studio's bundled JDK and Android Studio was uninstalled.

Per §4.3, a docs/process-only ≥account change *"takes a self-consistency review of the wording
instead of an adversarial bug-hunt."* So this is a wording review plus a ground-truth audit of
every factual claim the row makes — labelled as such rather than dressed up as a bug-hunt.

## Findings

### Finding 1 — the row's central claim was UNDER-verified when written — **corrected**

As written, the row asserted *"every APK +35→+38 used Android Studio's bundled JetBrains
Runtime"*. At the time it was committed I had read the `javaHome=` line from **one** log
(`daemon-12296`, the +38 build) and inferred the rest from the fact that the other three logs'
mtimes matched their ship dates. Matching mtimes establish *when* a daemon ran, not *which JVM*
it used — a different claim.

**Audit performed:** enumerated `javaHome=` across **all 111** logs in
`~/.gradle/daemon/8.14/`. Result: every log dated 2026-03-30 → 2026-08-06 reads
`javaHome=C:\Program Files\Android\Android Studio\jbr,javaVersion=21,javaVendor=JetBrains s.r.o.`
The sole exception is `daemon-19588` (2026-08-27) —
`javaHome=C:\Program Files\Microsoft\jdk-21.0.12.101-hotspot,javaVendor=Microsoft`, today's build.

The claim is **true, and true more widely than stated**: not merely +35→+38 but every build in the
machine's entire recorded daemon history, with today's as the first non-JBR build. The row's
wording is kept at "+35→+38" because those are the shipped artifacts a reader can map to
`backups/apk_sizes.json`; the wider fact is recorded here.

### Finding 2 — the JDK-17 trap is stated as a warning, which is correct — **verified**

The row warns "Use 21, not 17" and explains that `sourceCompatibility = VERSION_17` is the
bytecode target rather than the JVM Gradle runs on. Verified against
`android/app/build.gradle.kts:25-30` (`sourceCompatibility`/`targetCompatibility` =
`JavaVersion.VERSION_17`, `jvmTarget = VERSION_17.toString()`) and against the daemon evidence
that the actual JVM was 21 throughout. The warning is load-bearing: **I made this exact error
before the logs corrected me**, so the row documents a mistake that was actually made, not a
hypothetical one.

### Finding 3 — Source column follows the table's convention — **verified**

All sibling rows cite a document. This row cites `docs/playbook/common-pitfalls.md`, and that file
genuinely contains the full entry (added in `ebc65ad3`) — not a phantom citation. Gate 26
(`check_claude_md_citations.dart`) re-run: PASS across 16 CLAUDE.md/AGENTS.md files and 1688
source files.

## Claims verified accurate

- Android Studio absent: `C:\Program Files\Android` exists and contains no subdirectories ✓
- No JDK elsewhere: `Program Files`, `Program Files (x86)`, `LOCALAPPDATA\Programs`, `.jdks`,
  `.gradle\jdks` all searched — none present before the install ✓
- Android **SDK** survives: `%LOCALAPPDATA%\Android\Sdk` holds build-tools, platforms,
  platform-tools, ndk, emulator ✓
- Windows env-var trap: after `winget install`, `JAVA_HOME` read unset in-session while
  `[Environment]::GetEnvironmentVariable('JAVA_HOME','Machine')` returned the correct path ✓
- The fix works: Microsoft OpenJDK 21.0.12.1 built `+39` clean; Gate 48 PASS (release-signed,
  `CN=ICANBEFITTER`), Gate 13 PASS (+0.1% vs +38) ✓
- Nothing in the repo referenced `JAVA_HOME` before this change:
  `git log -S 'JAVA_HOME' -- android/ scripts/ .claude/` returns no config-setting commit ✓

## Verdict

**accepted.** The row's advice is correct and the one under-verified claim has been audited to
ground truth and found true across a wider set than it asserted.
