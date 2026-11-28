# APK Test #6 Plan E — Mission Brief Polish

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mission Brief screen renders the locked 95-word copy in Upendra's voice with proper italic-gold emphasis on key phrases. Founder photo asset bundled correctly so the empty circle bug (#1) is fixed.

**Architecture:** Two surgical fixes — copy text replacement in MissionBriefScreen widget + asset bundling fix in pubspec.yaml.

**Estimated effort:** 1-2h.

**Spec reference:** `docs/superpowers/specs/2026-05-01-apk-test-6-batch-design.md` §8.

---

## Task E-1 — Audit founder photo asset state

**Files:** 
- `assets/founder/upendra.jpg` (verify existence)
- `pubspec.yaml` (flutter.assets section)

**Steps:**

- [ ] **E-1.1** Check whether `assets/founder/upendra.jpg` exists in the repo:
  ```bash
  ls -la "C:/Upendra/Claude Code/fitness-app-test-4/assets/founder/" 2>&1
  ```
  Document finding: **exists / missing / wrong format**.

- [ ] **E-1.2** Verify `pubspec.yaml` includes `assets/founder/` in flutter.assets:
  ```bash
  grep -A 10 "flutter:" "C:/Upendra/Claude Code/fitness-app-test-4/pubspec.yaml" | grep -E "assets|founder"
  ```
  Document finding: **entry present / missing**.

- [ ] **E-1.3** If asset is missing, instruct user to provide `upendra.jpg` (JPEG, ≥200×200 px recommended for quality at 80dp CircleAvatar). Place at `assets/founder/upendra.jpg`. If pubspec.yaml entry is missing, proceed to Task E-2.

- [ ] **E-1.4** Commit findings in session memory or working notes for next step.

---

## Task E-2 — Fix asset bundling (if needed)

**Files:** `pubspec.yaml`

**Steps:**

- [ ] **E-2.1** If `assets/founder/` is NOT in pubspec.yaml flutter.assets, add it. Open `pubspec.yaml`:
  ```bash
  cat "C:/Upendra/Claude Code/fitness-app-test-4/pubspec.yaml" | grep -A 20 "flutter:"
  ```

- [ ] **E-2.2** Locate the flutter.assets section. Add entry if missing:
  ```yaml
  flutter:
    assets:
      - assets/data/
      - assets/founder/  # NEW
      - assets/images/
      - ...
  ```

- [ ] **E-2.3** Use the Edit tool to add the line (if missing). Expected output: pubspec.yaml now includes `- assets/founder/` on its own line under flutter.assets.

- [ ] **E-2.4** Run Flutter analyze to confirm no issues:
  ```bash
  cd "C:/Upendra/Claude Code/fitness-app-test-4" && flutter analyze lib/features/onboarding/screens/mission_brief_screen.dart 2>&1 | head -20
  ```
  Expected: 0 errors (file may not exist yet, or exist but is unchanged at this point).

---

## Task E-3 — Replace Mission Brief copy

**Files:** `lib/features/onboarding/screens/mission_brief_screen.dart`

**Steps:**

- [ ] **E-3.1** Read current MissionBriefScreen widget code to understand the structure (layout, current text, how the photo is rendered):
  ```bash
  cat "C:/Upendra/Claude Code/fitness-app-test-4/lib/features/onboarding/screens/mission_brief_screen.dart" | head -150
  ```

- [ ] **E-3.2** Identify the Text widget that renders the mission copy. Replace body text with the locked 95-word copy using RichText for italic-gold emphasis. Complete Dart widget code below:

```dart
RichText(
  text: TextSpan(
    style: AppTypography.bodyL.copyWith(
      color: AppColors.textPrimary,
      height: 1.6,
    ),
    children: [
      TextSpan(text: 'Welcome aboard.\n\nYou\'re not joining an app. You\'re reporting in.\n\n'),
      TextSpan(
        text: 'For 14 years I trained men in the Indian Navy. Discipline ',
      ),
      TextSpan(
        text: 'isn\'t motivation',
        style: AppTypography.bodyL.copyWith(
          color: AppColors.accent,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w500,
          height: 1.6,
        ),
      ),
      TextSpan(
        text: ' — it\'s structure. A plan you can follow when you don\'t feel like it.\n\nThat\'s what AVYA is. The discipline of military training. The science of certified coaching. Built for the long haul.\n\nYou do the work. ',
      ),
      TextSpan(
        text: 'AVYA holds the discipline',
        style: AppTypography.bodyL.copyWith(
          color: AppColors.accent,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w500,
          height: 1.6,
        ),
      ),
      TextSpan(
        text: '.\n\n',
      ),
      TextSpan(
        text: 'Show up. Earn promotions. Become the man who lasts',
        style: AppTypography.bodyL.copyWith(
          color: AppColors.accent,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w500,
          height: 1.6,
        ),
      ),
      TextSpan(
        text: '.\n\nThe AI runs the drills. ',
      ),
      TextSpan(
        text: 'The playbook is mine',
        style: AppTypography.bodyL.copyWith(
          color: AppColors.accent,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w500,
          height: 1.6,
        ),
      ),
      TextSpan(
        text: '.\n\n',
      ),
    ],
  ),
)
```

- [ ] **E-3.3** Below the RichText, add the "Jai Hind." line in Fraunces italic gold:

```dart
SizedBox(height: 24),
Text(
  'Jai Hind.',
  style: GoogleFonts.fraunces(
    fontSize: 14,
    fontStyle: FontStyle.italic,
    color: AppColors.accent,
    fontWeight: FontWeight.w500,
  ),
)
```

- [ ] **E-3.4** Below "Jai Hind.", add the signature (right-aligned):

```dart
SizedBox(height: 8),
Align(
  alignment: Alignment.centerRight,
  child: Text(
    '— Upendra',
    style: AppTypography.mono.copyWith(
      color: AppColors.textPrimary,
      fontSize: 12,
    ),
  ),
)
```

- [ ] **E-3.5** Use the Edit tool to replace the old body Text widget(s) with the RichText + Jai Hind + Upendra stack. Ensure indentation matches surrounding code.

---

## Task E-4 — Verify Instagram link still renders

**Files:** `lib/features/onboarding/screens/mission_brief_screen.dart`

**Steps:**

- [ ] **E-4.1** Check existing code for the Instagram link widget below the signature. It should read: `Daily wins on Instagram → @icanbefitter` with @icanbefitter as a tappable gold underlined link.

- [ ] **E-4.2** If the link widget exists, preserve it. Confirm it's positioned **below** the "— Upendra" signature line.

- [ ] **E-4.3** If the link is missing, add it below the signature using `GestureDetector` + `InkWell`:

```dart
SizedBox(height: 12),
GestureDetector(
  onTap: () => launchUrl(
    Uri.parse('instagram://user?username=icanbefitter'),
    mode: LaunchMode.externalApplication,
  ).catchError((_) => launchUrl(
    Uri.parse('https://instagram.com/icanbefitter'),
  )),
  child: Text.rich(
    TextSpan(
      text: 'Daily wins on Instagram → ',
      style: AppTypography.bodySm.copyWith(color: AppColors.textDim),
      children: [
        TextSpan(
          text: '@icanbefitter',
          style: AppTypography.bodySm.copyWith(
            color: AppColors.accent,
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  ),
)
```

- [ ] **E-4.4** Document: Instagram link present and verified / added / not needed.

---

## Task E-5 — Visual smoke test + commit

**Files:** `lib/features/onboarding/screens/mission_brief_screen.dart`, `pubspec.yaml`

**Steps:**

- [ ] **E-5.1** Run Flutter analyze on the modified file:
  ```bash
  cd "C:/Upendra/Claude Code/fitness-app-test-4" && flutter analyze lib/features/onboarding/screens/mission_brief_screen.dart 2>&1
  ```
  Expected: 0 errors, 0 warnings (or only pre-existing lint items).

- [ ] **E-5.2** **On-device verification steps** (execute after APK install):
  - Open app → sign up with test email
  - Reach "Mission Brief" screen (step 00 onboarding)
  - **Verify:** founder photo loads in the 80dp CircleAvatar (not an empty circle / no broken image icon)
  - **Verify:** body copy reads exactly as locked above, with italic-gold emphasis on the 4 key phrases
  - **Verify:** "Jai Hind." appears in italic Fraunces gold below body
  - **Verify:** "— Upendra" signature right-aligned below
  - **Verify:** Instagram link taps and opens IG app (or web fallback)
  - **Verify:** no layout overflow, text fits screen at 360dp width (portrait phone)

- [ ] **E-5.3** If photo fails to load, check: (a) `assets/founder/upendra.jpg` exists, (b) pubspec.yaml has `- assets/founder/` entry, (c) run `flutter clean && flutter pub get` then rebuild.

- [ ] **E-5.4** Stage changes:
  ```bash
  cd "C:/Upendra/Claude Code/fitness-app-test-4" && git add -A
  ```

- [ ] **E-5.5** Commit with Co-Authored-By trailer:
  ```bash
  cd "C:/Upendra/Claude Code/fitness-app-test-4" && git commit -m "$(cat <<'EOF'
  fix(onboarding): Mission Brief photo + copy locked in voice

  - Add founder photo asset path to pubspec.yaml flutter.assets
  - Replace MissionBriefScreen body text with 95-word locked copy
  - Italic-gold emphasis on 4 key phrases (isn't motivation, AVYA holds discipline, Show up..., playbook is mine)
  - Fraunces italic gold "Jai Hind."
  - Right-aligned signature "— Upendra"
  - Preserve Instagram link (Daily wins on Instagram → @icanbefitter)

  Closes obs #1 (founder photo missing), #2 (copy too AI slob).

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

- [ ] **E-5.6** Verify commit succeeded:
  ```bash
  cd "C:/Upendra/Claude Code/fitness-app-test-4" && git log --oneline -1
  ```
  Expected: new commit appears with "fix(onboarding): Mission Brief" subject.

---

## Self-review

| Item | Status |
|---|---|
| Spec §8 coverage | ✓ Photo asset (#1) + locked copy (#2) + italic-gold emphasis + Jai Hind + signature + IG link |
| Placeholder scan | ✓ No `TODO`, `FIXME`, `XXX`, or `hardcoded` patterns in code snippets |
| RichText syntax | ✓ Complete Dart widget, copy-pasteable, no pseudocode |
| Bash commands | ✓ All shell commands explicit and executable |
| Commit HEREDOC | ✓ Co-Authored-By trailer included |
| Task granularity | ✓ 5 independent tasks, each with checkbox steps |

**Total estimated effort:** 1-2h (30min asset audit + pubspec fix, 30min copy replacement + RichText build, 15min Instagram verification, 15min smoke test + commit).

**Deferral note:** None. Plan E is self-contained and independent of Plans A–D.
