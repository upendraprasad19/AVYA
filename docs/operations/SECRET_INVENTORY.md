# Secret Inventory

> Tech-debt audit 2026-05-20 finding I7 — bus-factor-1 mitigation.
> Every local-only secret / credential needed to develop, build, or deploy
> from a fresh machine is listed here with its source/restore path.
>
> **This file is committed to the repo and intentionally PUBLIC** — it
> contains NO secret values, only the names + retrieval procedure. The
> actual values live in a password manager (1Password / Bitwarden) under
> the vault entry `icanbefitter-secrets`.

## On-disk secret files (gitignored)

| Path | Purpose | How to recreate on a new machine |
|---|---|---|
| `.env` | Dev-mode runtime defines (Supabase URL, anon key, Razorpay test key) | Copy template from `.env.example` + paste values from password manager → `icanbefitter-secrets > env-dev` |
| `.env.dev` | Same as `.env` but flavor-specific | Same as `.env` |
| `.env.prod` | Production runtime defines — must use `rzp_live_*` Razorpay key | Password manager → `icanbefitter-secrets > env-prod`. **GATE:** `scripts/check_razorpay_key_flavor.dart` asserts `rzp_live_` prefix. |
| `android/key.properties` | Android signing — stores keystore path + password | Password manager → `icanbefitter-secrets > android-keystore`. Plaintext password is fine on a single-machine setup; just NEVER commit. Gate: `scripts/check_secrets_gitignored.dart`. |
| `android/app/release.jks` | Android signing certificate (binary) | Password manager → `icanbefitter-secrets > android-keystore-jks` (binary attachment). Losing this = lose ability to publish updates → must publish under a new package name → lose all installed users. **Make TWO offsite backups.** |
| `supabase/.supabase/supabase access token.txt` | Supabase Management API Personal Access Token (account `myfitnessjourney1988@gmail.com`, org `hwwukmntixflgbxkwavm`) | Supabase Dashboard → top-right avatar → Account → Access Tokens → "Generate new token". Save to password manager `icanbefitter-secrets > supabase-pat`. |

## Edge Function secrets (set in Supabase Dashboard, NOT on disk)

These are stored in Supabase Vault and injected into Edge Function runtimes
via `Deno.env.get()`. To rotate or verify, go to Supabase Dashboard →
Project `dedsavbjuwgarrhphgnl` → Edge Functions → Secrets.

| Secret name | Used by | Last verified |
|---|---|---|
| `ONESIGNAL_APP_ID` | All push-notification senders | 2026-05-20 |
| `ONESIGNAL_REST_API_KEY` | Same | 2026-05-20 |
| `GEMINI_API_KEY` | `ai-proxy`, `ai-media-proxy`, `assess-body-composition` | 2026-05-20 |
| `CEREBRAS_API_KEY_1`, `_2`, `_3` | Legacy fallback (now disused; safe to retain) | 2026-05-20 |
| `RAZORPAY_KEY_SECRET` | `verify-payment`, `razorpay-webhook` | 2026-05-20 |
| `service_role_key` (Vault row, NOT env var) | All cron-dispatched functions via `private.morning_alert_get_service_key()` | 2026-05-20 (drift-fixed 2026-05-15 — see `supabase/functions/CLAUDE.md`) |

## Firebase / OneSignal / Razorpay credentials

| System | Account / Project | How to access |
|---|---|---|
| Firebase | Project `AVYA` | Firebase Console → log in as `myfitnessjourney1988@gmail.com` |
| OneSignal | App `fd37a411-121e-4022-9929-2af68c2371f5` | OneSignal Dashboard → log in as `myfitnessjourney1988@gmail.com` |
| Razorpay (test) | Test mode — keys start `rzp_test_` | Razorpay Dashboard → Settings → API Keys → Test mode |
| Razorpay (live) | Live mode — keys start `rzp_live_` | Razorpay Dashboard → Settings → API Keys → Live mode |
| Twilio | Account created 2026-04-24, NOT yet wired (per `project_pending_twilio_setup.md`) | Twilio Console → log in as `myfitnessjourney1988@gmail.com` |

## New-machine setup checklist

When provisioning a fresh dev box (or restoring after laptop loss), run
through this in order:

1. Clone the repo: `git clone https://github.com/upendraprasad19/icanbefitter.git`
2. Install hooks: `sh scripts/setup-hooks.sh` (gate: `check_hooks_installed.dart`)
3. `npm install` at repo root (deploy scripts in `.claude/` use these deps)
4. Restore `.env`, `.env.dev`, `.env.prod` from password manager
5. Restore `android/key.properties` and `android/app/release.jks` from password manager
6. Restore `supabase/.supabase/supabase access token.txt` from password manager
7. `flutter pub get`
8. `flutter run --dart-define-from-file=.env --flavor dev -t lib/main.dart` — smoke test
9. Confirm Supabase MCP works: deploy a no-op test (use `--dry-run` flag in `.claude/deploy_via_api.js`)

## Rotation cadence

| Secret | Cadence | Last rotated |
|---|---|---|
| Razorpay live key secret | When team composition changes | n/a (solo-founder) |
| Supabase PAT | Annually | 2026-04-20 |
| `service_role_key` (Vault) | When Supabase platform forces it (rare) | last drift detected 2026-05-15 |
| Android signing key | NEVER rotate (would break upgrades for existing users) | original |
| OneSignal REST API key | Annually | not yet — initial provision |
| Gemini API key | When Google rotates it | initial provision |

## Audit history

- 2026-05-20: inventory created, audit closure I7.
