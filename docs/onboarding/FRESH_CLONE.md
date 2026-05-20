# Fresh-Clone Setup — `git clone` → running dev flavor

End-to-end checklist for a brand-new checkout of `icanbefitter-app`. Roughly 10 minutes assuming Flutter SDK is already installed. Secret-placement details are centralised in [`docs/operations/SECRET_INVENTORY.md`](../operations/SECRET_INVENTORY.md); this doc only references them.

---

## 1. Prerequisites

- Flutter SDK (stable channel) — `flutter --version` should print 3.x or newer.
- Node.js 18+ — for the Edge-Function deploy scripts under `.claude/`.
- Git + Git Bash (Windows) — `scripts/setup-hooks.sh` is a bash script.
- An Android device or emulator with USB debugging on.

## 2. Clone and install Node deps

```bash
git clone <repo-url> "fitness-app"
cd fitness-app
npm install               # root — package.json carries lint helpers + emit_payload deps
(cd .claude && npm install)   # host-shell deploy scripts (deploy_via_api.js, emit_payload.js)
```

## 3. Wire up the pre-commit hook

`.git/hooks/` is NOT version-controlled. Every fresh clone needs:

```bash
sh scripts/setup-hooks.sh
```

This installs `scripts/pre-commit.sh` as the active hook. The hook blocks any commit while `flutter analyze --no-fatal-infos` or `flutter test` is failing, regenerates `docs/diagnoses/INDEX.md` on diagnose-doc changes, and walks the regression catalog on merge commits. See CLAUDE.md §0 for the bypass policy.

## 4. Fill `.env`

```bash
cp .env.example .env
# Open .env and fill SUPABASE_URL, SUPABASE_ANON_KEY, RAZORPAY_KEY_ID.
```

Canonical values for the fitness-app project (`dedsavbjuwgarrhphgnl`) are listed in [`docs/operations/SECRET_INVENTORY.md`](../operations/SECRET_INVENTORY.md). Use `rzp_test_…` for dev, `rzp_live_…` only for prod release builds.

Environment variables are injected at **build time** via `--dart-define-from-file=.env`. The package `flutter_dotenv` was removed — every `flutter run` / `flutter build` command must include `--dart-define-from-file=.env` or `SUPABASE_URL` compiles to an empty string and auth crashes ("No host specified in URI").

## 5. Drop the Supabase Personal Access Token

Required only if you'll be deploying Edge Functions from this checkout. Token path:

```
supabase/.supabase/supabase access token.txt
```

Gitignored. Source + which Supabase account it authenticates against: [`docs/operations/SECRET_INVENTORY.md`](../operations/SECRET_INVENTORY.md). The `.claude/deploy_via_api.js` script auto-discovers this file.

## 6. Flutter packages

```bash
flutter pub get
```

If you see `riverpod_generator` warnings, ignore them — the project currently writes providers manually (no `.g.dart` files). See CLAUDE.md §0 "Riverpod Code Generation".

## 7. Smoke test

```bash
flutter analyze
flutter test
```

Both should pass cleanly. A non-empty failure list means either a regression on `main` (rare — pre-commit hook should have blocked it) or a missed local step above.

## 8. Run dev flavor

```bash
flutter run --dart-define-from-file=.env --flavor dev -t lib/main.dart
```

You should land on the login screen within ~20 seconds. If you get "No host specified in URI", `--dart-define-from-file=.env` is missing or `.env` is empty.

## 9. Where to go next

- CLAUDE.md §0 — full command reference.
- `docs/architecture/` — sync, AI, database, payment, subscription deep-dives.
- `lib/features/<feature>/CLAUDE.md` — per-feature rules (auto-loaded by Claude Code).
