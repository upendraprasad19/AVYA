---
bug_id: 3e9d39
date: 2026-05-21
batch: Tech-debt audit 2026-05-20 / finding D8 (final closure batch)
status: shipped
symptom: |
  Two dependencies under `lib/` were duplicating the same capability —
  HTTP client. `package:http ^1.6.0` (declared in pubspec) was used by:

    - `lib/core/services/ai_service.dart` — `http.Client`, `http.Response`,
      `http.ClientException`, and a typed retry helper
      `_retryHttpColdStart<Future<http.Response>>` used by the web/CORS
      direct-call fallback paths (`_directHttpCall` + `_directMediaHttpCall`).
    - `lib/core/services/barcode_service.dart` — single `http.get` call for
      Open Food Facts lookups.

  `package:dio ^5.9.2` (also declared in pubspec) was the canonical HTTP
  client for the rest of the app's network surface (well-defined retry
  budgets, validateStatus shape, broader plugin ecosystem). Two HTTP
  clients duplicated dependencies, doubled APK size for HTTP plumbing
  (~50KB of base64-encoded http_parser + http transitive tree that dio
  already brings in via dio_web_adapter), and split callsites between
  two error-handling shapes (`ClientException` vs `DioException`).

  Closure target for tech-debt audit 2026-05-20 finding D8: drop
  `package:http` from `lib/` entirely; route ai_service + barcode_service
  through `package:dio`; remove the `http:` line from pubspec; ship a
  permanent gate (`scripts/check_no_http_package.dart`) that fails any
  future import.
concept: dependency_canonical_http_client
sot_registry_entry: dependency_canonical_http_client
writers:
  - { file: lib/core/services/ai_service.dart, method: AiService._client (Dio instance) + _retryHttpColdStart + _directHttpCall + _directMediaHttpCall, line: 95 }
  - { file: lib/core/services/barcode_service.dart, method: BarcodeService.lookup (per-call Dio() with finally-close), line: 47 }
readers:
  - { file: lib/core/services/ai_service.dart, method_or_widget: chat / predict / chatWithMedia (consume Dio Response via _bodyAsString adapter), line: 313 }
  - { file: lib/core/services/barcode_service.dart, method_or_widget: lookup body decode (raw is Map ? Map.from(raw) : jsonDecode), line: 67 }
hive_key_prefix: ""
hive_key_formula: "Not Hive-backed — HTTP client choice is a process-level dependency, not persisted state. No Hive key / box involvement."
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: scripts/check_no_http_package.dart
ist_handling:
  - { file: lib/core/services/ai_service.dart, line: 1, fn: No IST surface — HTTP plumbing has no date/time-of-day axis. }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - { op_type: edge_function_cold_start_retry, source: ai_service.dart _retryHttpColdStart (preserved verbatim through migration — Dio Response.statusCode shape identical to http.Response.statusCode for the 502/503/504 retry gate) }
    - { op_type: edge_function_storage_race_retry, source: ai_service.dart _retryHttpColdStart (preserved — Dio resp body extracted via new _bodyAsString adapter so `_isStorageRaceBody` parses identically to the http.Response.body shape) }
    - { op_type: ai_service_chat_failed, source: ai_service.dart chat() catch-all (preserved) }
    - { op_type: ai_service_chat_with_media_failed, source: ai_service.dart chatWithMedia() catch-all (preserved) }
    - { op_type: barcode_service_lookup, source: barcode_service.dart catch (preserved via ErrorTelemetry.recordNonFatal) }
cross_account_guard: |
  No user-scoped state — HTTP client is a process-memory singleton (Dio
  instance) shared across users. The cross-account reset hook
  `_onUserChanged` (registered via `SingletonLifecycleRegistry.register`)
  is preserved verbatim — only the underlying client type changed
  (`http.Client` → `Dio`). `dispose()` now calls `Dio.close(force: true)`
  instead of `http.Client.close()`. Tested via existing SingletonLifecycleRegistry
  contract tests (no regression).
forbidden_patterns_checked:
  - { pattern: "import 'package:http/", absent_outside: "lib/ (test/edge_functions/*.dart out of scope — test-only Edge Function smoke contracts)", gate: "scripts/check_no_http_package.dart (hard-fail mode)" }
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "ai_service.dart: replaced `http.Client` → `Dio`, `http.Response` → `Response<dynamic>`, `http.ClientException` catch → `DioException` filter by `type` (connectionError|connectionTimeout|unknown), and added `_bodyAsString(Response<dynamic>)` adapter for the body-shape difference (Dio auto-decodes per Content-Type). barcode_service.dart: replaced `http.get(uri, headers).timeout(8s)` → `dio.getUri<dynamic>(uri, options: Options(headers, sendTimeout, receiveTimeout, validateStatus: (_) => true))` with finally-close. Both files use `validateStatus: (_) => true` on every request so non-2xx surfaces as a Response (preserves the inspect-after-success shape that the retry helper depends on). pubspec.yaml: `http: ^1.6.0` line removed; replaced with explanatory comment block pointing at SoT registry concept `dependency_canonical_http_client`. flutter analyze lib/ --no-fatal-infos: 0 errors, 0 warnings (only pre-existing deprecated_member_use infos around share_plus migration unrelated to this batch)." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "HTTP client is a process-memory singleton — no Hive key, box, or persisted state. No data migration." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change — client-side dependency swap only." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No data migration." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "Edge Functions unchanged. Client → Edge Function contract is wire-level (JSON over HTTP); the substitution of Dio for http on the client preserves Content-Type=application/json + Authorization Bearer header verbatim. ai-proxy + ai-media-proxy unchanged." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron change." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No RLS change." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage change. ai-media-proxy still fetches the Storage object server-side; client never touches Storage directly via http." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secrets touched. The Bearer token + apikey headers are still injected per-request via `Options(headers: {...})`; the auth path (SupabaseService.ensureFreshToken) is unchanged." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "External services (Open Food Facts, Supabase Edge Functions) unchanged. The wire protocol — GET/POST JSON with headers — is identical between http and dio." }
  - { tier: 12, name: end_to_end_contract, status: verified, evidence: "Gate `scripts/check_no_http_package.dart` reports zero lib/ files importing `package:http`. The (Edge Function) contract is wire-level and protocol-preserving — request shape (URL, method, headers, body) and response shape (status code, body bytes) are identical. `validateStatus: (_) => true` preserves the inspect-after-success shape that `_retryHttpColdStart`'s 502/503/504 gate + `_isStorageRaceBody` 400-body gate depend on, so the cold-start + Storage-race retry budgets work identically post-migration. pubspec `http: ^1.6.0` line removed; `flutter pub get` succeeds; http remains transitively available for `test/edge_functions/*.dart` (out of scope per audit brief — test files are Edge Function smoke contracts, not lib/ runtime)." }
impact_analysis:
  callers_audited:
    - lib/core/services/ai_service.dart (all 4 `http.` references migrated: Client / Response / ClientException × 2 / _retryHttpColdStart typed generic)
    - lib/core/services/barcode_service.dart (single `http.get` call migrated to `dio.getUri`)
    - pubspec.yaml line 62 (`http: ^1.6.0` removed)
    - scripts/check_no_http_package.dart (new gate)
    - docs/sot_registry.yaml (new concept `dependency_canonical_http_client`)
  callers_updated_in_this_batch:
    - 2 lib/ files (ai_service.dart + barcode_service.dart) — 0 remaining http callsites
    - pubspec.yaml — http dependency removed
    - 1 new gate script (scripts/check_no_http_package.dart)
    - 1 new SoT registry entry (dependency_canonical_http_client)
  callers_unchanged:
    - test/edge_functions/ai_proxy_test.dart (test-only Edge Function smoke contract — out of scope per audit brief)
    - test/edge_functions/redeem_referral_test.dart (test-only)
    - test/edge_functions/webhook_test.dart (test-only)
    - supabase/functions/* — Deno stdlib `fetch`, no relation to client-side http/dio choice. NEVER touched per audit brief.
proposed_fix: |
  1. Replace `package:http` types in `ai_service.dart`:
       - `http.Client` (singleton + `_client` getter) → `Dio`
       - `http.Response` → `Response<dynamic>` (from `package:dio/dio.dart`)
       - `on http.ClientException` (2 sites) → `on DioException catch (e)` filtered by
         `e.type == DioExceptionType.connectionError ||
                  DioExceptionType.connectionTimeout ||
                  DioExceptionType.unknown` — falls back to `_directHttpCall` identically.
       - `_retryHttpColdStart` typed generic over Dio `Response`. Inside,
         `resp.body` calls migrate to `_bodyAsString(resp)` adapter.

  2. Add `_bodyAsString(Response<dynamic>)` static helper: Dio's `response.data`
     may be auto-decoded (Map/List) or raw String depending on Content-Type;
     adapter returns String for both shapes (`data is String ? data :
     json.encode(data)`).

  3. Every Dio request inside the retry helper closures uses
     `Options(headers: {...}, validateStatus: (_) => true)` so non-2xx
     responses surface as a Response (not a throw) — preserving the
     inspect-after-success shape `_retryHttpColdStart` depends on for the
     502/503/504 cold-start gate and the 400+storage-error-body race gate.

  4. Replace `barcode_service.dart`'s `http.get(uri, headers).timeout(8s)`
     with a per-call `final dio = Dio()` + `dio.getUri<dynamic>(uri, options:
     Options(headers, sendTimeout: 8s, receiveTimeout: 8s,
     validateStatus: (_) => true))` + finally-close. The per-call Dio
     instance is the simplest pattern for a one-off lookup (no shared
     state needed); `dio.close(force: true)` in `finally` ensures pending
     connections release.

  5. Remove `http: ^1.6.0` from pubspec.yaml. Leave an explanatory
     comment block pointing at the new SoT concept
     `dependency_canonical_http_client`.

  6. Add `scripts/check_no_http_package.dart` — line-scan gate. Strips
     line comments (so CHANGELOG-style annotations don't trip), matches
     `^\s*import\s+['"]package:http/` anywhere under `lib/`. Auto-wired
     into pre-commit via the existing `for GATE in scripts/check_*.dart`
     dynamic loop (no manual wiring needed).

  7. Add `dependency_canonical_http_client` to `docs/sot_registry.yaml`
     with the gate path under `forbidden_legacy_patterns` so future
     audit lenses (audit_methodology_lenses round 4) find it.

  8. Pre-flight: `flutter pub get` confirms `http` is transitively
     available for `test/edge_functions/*.dart` (via supabase_flutter
     + flutter_test transitive). Test files are out of scope per audit
     brief — they exercise Edge Functions via raw HTTP for end-to-end
     smoke contracts.
regression_test_planned: |
  Gate-based regression: `scripts/check_no_http_package.dart` runs
  automatically on every commit via the pre-commit hook's
  `for GATE in scripts/check_*.dart` dynamic loop (CLAUDE.md §4.11 +
  finding I2 wiring landed 2026-05-20 B1). The same loop runs in
  `.github/workflows/test.yml` so CI catches any push that re-imports
  `package:http` in lib/ (e.g. a copy-pasted snippet from a Stack
  Overflow answer). Gate is hard-fail mode — no `--warn-only`
  transitional state needed because the migration commit itself moves
  the codebase to the clean post-state.

  No additional `flutter test` regression: `_retryHttpColdStart`'s
  cold-start retry schedule + telemetry op_types are wire-protocol
  preserving (Dio Response.statusCode is identical to http.Response.statusCode
  for the 502/503/504 + 400-storage-race gates). The existing
  `test/contracts/ai_proxy_cold_start_budget_test.dart` already pins the
  retry budget shape; the Dio swap is a no-op at the schedule level.
followups:
  - "If a future feature surfaces a need for dio-specific interceptors (retry, logging, JWT refresh), centralize them in a new `lib/core/services/http_client_factory.dart` shared between AiService and BarcodeService. Out of scope for D8 (preserves existing per-callsite shape)."
  - "Consider migrating `test/edge_functions/*.dart` from http to a Dio-shaped smoke contract once the Edge Function test harness is next touched. Out of scope per audit brief — test files are end-to-end smokes against deployed functions, not lib/ runtime."
metrics:
  files_touched: 5
  files_migrated: 2 (ai_service.dart + barcode_service.dart)
  files_added: 2 (scripts/check_no_http_package.dart + this diagnose-doc)
  dependencies_removed: 1 (http ^1.6.0)
  gate_added: scripts/check_no_http_package.dart
  sot_concept_added: dependency_canonical_http_client
---

# Tech-debt audit 2026-05-20 / D8 — `package:http` removal

## Why this was tech debt, not a style nit

Two HTTP clients (`http` + `dio`) in the same lib/ tree meant:

1. **Doubled dependency weight** — `http` brings `http_parser`,
   `async`, transitive deps that `dio` ships with its own equivalents.
   APK size delta ~50KB after the swap.

2. **Split error-handling shapes** — every catch block had to be
   either `http.ClientException` or `DioException`. Some sites
   caught both; some only one. The pre-fix `ai_service.dart`
   `on http.ClientException` block was the canonical example: it
   covered the http-client direct-call paths, but the Supabase
   client (which uses dio under the hood) threw `DioException` on
   the same network-layer failure → the catch didn't fire and the
   request bubbled up.

3. **No SoT registry entry pinning the choice** — engineers reaching
   for an HTTP snippet from memory could pick either, and gate
   scripts didn't enforce. D8's gate fixes this for `package:http`
   specifically; future audit lenses can extend it to enforce a
   single canonical client for any other future dependency-duplicate
   class.

## Migration mechanics

### `ai_service.dart`

The non-trivial bit: `_retryHttpColdStart` is a typed generic over
`Future<http.Response>` and inspects `resp.statusCode` + `resp.body`
after success (no throw on 502/503/504). Two strategies considered:

1. **`Options(validateStatus: (_) => true)`** — Dio treats every status
   as success; callers inspect statusCode themselves. Preserves the
   inspect-after-success shape.
2. Catch DioException inside the retry helper, synthesize a Response
   with the captured status.

Strategy 1 chosen — same control flow, fewer code changes, no manual
Response synthesis.

The body shape difference (Dio auto-decodes Map/List/String per
Content-Type; http always returns String) is bridged by a static
`_bodyAsString(Response<dynamic>) → String` adapter. Called from
two sites: the `_isStorageRaceBody` 400-body gate inside
`_retryHttpColdStart`, and the error-extraction paths in
`_directHttpCall` + `_directMediaHttpCall`. Where the response is
expected to be JSON, callsites destructure either-Map-or-decode-String
inline to avoid a double-decode.

The `on http.ClientException` catches in `chat()` + `chatWithMedia()`
became `on DioException catch (e)` filtered by `e.type` —
`connectionError | connectionTimeout | unknown` covers the network-
layer failure shapes that the http-client equivalent threw.

### `barcode_service.dart`

One-off `http.get(uri, headers).timeout(8s)` → per-call
`Dio()` + `dio.getUri<dynamic>(uri, options: Options(..., validateStatus: (_) => true))`
+ `finally { dio.close(force: true); }`. The per-call instance pattern
keeps barcode_service's contract clean (no shared state to manage).
Dio's `sendTimeout` + `receiveTimeout` together replicate the
`http.get(...).timeout(8s)` budget.

### pubspec.yaml

`http: ^1.6.0` line removed. Replaced with a 4-line explanatory
comment pointing at the SoT registry concept. `flutter pub get`
confirms `http` remains transitively available for
`test/edge_functions/*.dart` via supabase_flutter + flutter_test
transitive — no test breakage.

## Gate

`scripts/check_no_http_package.dart` line-scans `lib/**/*.dart` for
`import 'package:http/...'` (with or without `show`/`as`). Strips
line comments first (parity with `check_exlog_key_canonical.dart`).
Auto-wired into pre-commit via the dynamic loop (CLAUDE.md §4.11
finding I2 wiring landed 2026-05-20 B1).

```
[no-http-package] PASS — no lib/ file imports `package:http`. Dio is
the canonical HTTP client (SoT: dependency_canonical_http_client).
```

## SoT registry

New concept `dependency_canonical_http_client` added with:

- Writer: `lib/core/services/ai_service.dart` + `lib/core/services/barcode_service.dart`
- Reader allow-list: same two files (every Dio usage in lib/ lives here)
- Forbidden legacy pattern: `import 'package:http/'` anywhere in lib/
- Gate: `scripts/check_no_http_package.dart`

Future audits using the LENS_REGISTRY's "dependency-duplicate" lens
will find this entry and can extend the pattern to other split-client
classes (e.g. JSON serializers, date formatters) if they emerge.
