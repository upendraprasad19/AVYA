# Spec — Fix failed Vercel deploy (Flutter web, GitHub Git-integration)

- **Date:** 2026-06-05 (IST)
- **Status:** Approved approach (A), spec under review before implementation
- **Blast-radius:** `feature` (web deploy config only; no app/runtime/DB/auth surface)
- **Commit type:** `chore:` (no diagnose-doc required — rule 22 triggers on `fix|bug|regression` only)
- **Owner:** Upendra

---

## 1. Problem

Vercel deploy of the `avya` project fails at **config validation** with:

> The `vercel.json` schema validation failed with the following message: `buildCommand` should NOT be longer than 256 characters

`vercel.json:3` `buildCommand` is **446 characters**. Vercel hard-caps that field at **256** in the `vercel.json` schema. The failure happens *before the build runs* — so Flutter, the env, and the GitHub wiring have never been exercised.

**Evidence**
- `vercel.json` created today in commit `5d7799b` ("chore: vercel.json for Flutter-web Vercel deploy"); first deploy attempt, never validated.
- Vercel project `avya` (team `team_feN71FXGb4pCGQBu9uzll6Wk`), `framework: null` (= "Other" preset, correct for Flutter), Hobby plan.
- No local `.vercel/` link → wired purely via **GitHub Git-integration**: every push to `main` triggers a fresh build in a Linux container, `cwd` = repo root.
- Latest deployment `dpl_ChdycVqy6L2gAd4r8ehKibzZZtXZ` → `readyState: ERROR`, target `production`.

## 2. Root cause

The build logic is inlined as one JSON string. The string cannot be shortened under 256:
the unavoidable parts — clone Flutter (~78) + `export PATH` (~40) + three `--dart-define`s (~136) — total ~254 **before** the `flutter build web` verb. The logic must move out of the JSON string.

## 3. Chosen approach — A: build-script wrapper

Move the command into a committed shell script; reduce `buildCommand` to `bash scripts/vercel_build.sh` (28 chars). This is Vercel's documented pattern for long/dynamic build commands (https://vercel.com/kb/guide/dynamic-build-commands). Keeps Git-integration, version-controls build logic, removes the length ceiling, and gives a place for a fail-fast env-var guard.

**Rejected:**
- **B — split `installCommand` + `buildCommand`.** Workable (call Flutter by relative path `flutter/bin/flutter` since a PATH export in `installCommand` does not survive into the separate `buildCommand` shell), but brittle: `buildCommand` lands ~176/256, so one more `--dart-define` overflows it again. Splits logic awkwardly.
- **C — decouple to GitHub Actions** (`vercel deploy --prebuilt`). Faster repeat builds + full control, but more moving parts + a Vercel token in GH secrets, and abandons the just-configured Git-integration. Future-scale, not today's fix.

## 4. Detailed design — three changes

### 4.1 New file `scripts/vercel_build.sh`

Verbatim relocation of the current command + `set -euo pipefail` + env-var guard. The guard uses an explicit `if` (not `[ ] && …`) for unambiguous `set -e` safety (see §6, loophole L1).

```bash
#!/usr/bin/env bash
# AVYA Vercel build — Flutter web (release).
#
# Invoked by vercel.json "buildCommand": "bash scripts/vercel_build.sh".
# Lives here (not inline) because Vercel hard-caps buildCommand at 256 chars
# and the full command is ~446 — https://vercel.com/kb/guide/dynamic-build-commands.
#
# Vercel deploys via GitHub Git-integration: every push to `main` builds in a
# Linux container, cwd = repo root. Env vars come from the Vercel dashboard
# (Project Settings -> Environment Variables), Production target. All three
# below are client-public (shipped in the web bundle), but MUST be set or they
# compile to empty strings and the app crashes on launch with
# "No host specified in URI" (CLAUDE.md §0).
set -euo pipefail

FLUTTER_VERSION="3.41.4"   # must match dev/CI (CLAUDE.md §0)

# Fail fast if a required build-time env var is missing or empty.
missing=""
for var in SUPABASE_URL SUPABASE_ANON_KEY RAZORPAY_KEY_ID; do
  if [ -z "${!var:-}" ]; then
    missing="$missing $var"
  fi
done
if [ -n "$missing" ]; then
  echo "ERROR: missing required env var(s):$missing" >&2
  echo "Set them in Vercel -> Project Settings -> Environment Variables (Production)." >&2
  exit 1
fi

# Bootstrap the pinned Flutter SDK (reuse Vercel's build cache if present).
if [ -d flutter ]; then
  (cd flutter && git fetch --depth 1 origin "$FLUTTER_VERSION" && git checkout -q "$FLUTTER_VERSION")
else
  git clone https://github.com/flutter/flutter.git --depth 1 -b "$FLUTTER_VERSION" flutter
fi
export PATH="$PWD/flutter/bin:$PATH"

# Build web (release).
flutter config --enable-web
flutter pub get
flutter build web --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=RAZORPAY_KEY_ID="$RAZORPAY_KEY_ID"
```

### 4.2 `vercel.json`

```diff
-  "buildCommand": "if [ -d flutter ]; then (cd flutter && git fetch … --dart-define=RAZORPAY_KEY_ID=$RAZORPAY_KEY_ID",
+  "buildCommand": "bash scripts/vercel_build.sh",
```

`outputDirectory` (`build/web`), `installCommand` (`echo no-install`), and the SPA `rewrites` are unchanged.

### 4.3 `.gitattributes` (new)

```
# Shell scripts must be LF so they run on Linux CI / Vercel builders.
*.sh text eol=lf
```

Verified zero-churn: all 6 tracked `.sh` files are already `i/lf` in the index. This makes the LF guarantee deterministic regardless of any contributor's local `core.autocrlf`.

## 5. Prerequisite — Vercel dashboard env vars (founder action)

Set on the **Production** target (and Preview, if PR previews are wanted):

| Key | Value |
|---|---|
| `SUPABASE_URL` | `https://dedsavbjuwgarrhphgnl.supabase.co` |
| `SUPABASE_ANON_KEY` | (anon JWT from local `.env` line 2 — client-public) |
| `RAZORPAY_KEY_ID` | `.env` has the **test** key `rzp_test_…`; use `rzp_live_…` if the site takes real payments |

If any is missing the guard (§4.1) aborts the build with a clear message instead of shipping a broken app.

## 6. Loophole / failure-mode review

| # | Concern | Verdict |
|---|---|---|
| L1 | `set -e` + `[ -z … ] && missing=…` could abort on the false branch | **Fixed in design** — use explicit `if`. (`false && cmd` is actually exempt from `set -e`, but `if` is unambiguous.) |
| L2 | `set -u` + `${!var:-}` indirect expansion on unset var | Safe — `:-` default guards unset; runs under `bash` (buildCommand invokes `bash`). |
| L3 | CRLF endings break `bash` on Linux | Fixed — `.gitattributes *.sh text eol=lf`; will confirm `git ls-files --eol` shows `i/lf` before push. |
| L4 | Script needs `+x` permission | No — invoked via `bash <file>`, no execute bit needed (also unsettable on Windows). |
| L5 | Secret leakage in build logs | None — no `set -x`; guard echoes var *names* only; values are client-public regardless. |
| L6 | Vercel runs npm install / needs package.json | No — `framework: null` + `installCommand: "echo no-install"` suppress it. |
| L7 | `pubspec.lock` floating deps | Tracked — `flutter pub get` uses locked versions (matches dev/CI). |
| L8 | Output dir / SPA rewrite correctness | `build/web` is Flutter's default; rewrite only fires when no static file matches (assets served directly). Correct. |
| L9 | Base href on `*.vercel.app` root | Default `/` is correct; no `--base-href` needed for root-domain serving. |
| L10 | `flutter pub get`/`build` failures slipping through | `set -e` aborts on any non-zero → Vercel marks build failed. No silent success. |

## 7. Round-2 watch items (first time the build actually runs)

The length error masked everything downstream; these can only be confirmed once the build runs:
- **Flutter web build OOM/timeout** — unlikely (Hobby = 45-min timeout, ~8 GB); watch first build.
- **Deep-link / refresh 404** — verify a non-root route loads after refresh (URL strategy + rewrite). App was driven live via Chrome before, so likely already correct.
- **Razorpay test vs live** — founder decision (§5).
- **Preview-target env vars** — only needed if branch/PR previews are desired.

## 8. Out of scope (not deferred bugs — optimizations on an already-working build)

- **Cache the Flutter SDK** to avoid re-cloning each build (Hobby build-minute savings). The `if [ -d flutter ]` reuse path already helps when Vercel's cache persists.
- **Approach C (GitHub Actions decouple)** if build minutes/time become a constraint.

These are performance optimizations on a build that works without them — revisit only if cost/latency warrants. No in-scope bug is being punted.

## 9. Sequencing

1. Write the 3 file changes (no commit). Show diff.
2. Founder sets the env vars (§5).
3. On explicit "commit/push": stage **only** `vercel.json` + `scripts/vercel_build.sh` + `.gitattributes` (the uncommitted `pubspec.yaml` version bump stays untouched), commit `chore:`, push to `main`.
4. Push auto-triggers Vercel build → watch via Vercel MCP (`get_deployment` / build logs) → report green or handle round-2.
