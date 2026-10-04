---
title: Code-review audit lenses — the 12+ defaults to skip-proof
category: audit
source_memory: feedback_audit_methodology_lenses.md
last_reviewed: 2026-05-28
---

# Code-review audit lenses — the 12+ defaults to skip-proof

## The class

A default multi-agent code review tends to cover 5 lens dimensions: security, correctness, SoT/architecture, UX, maintainability. That misses the lenses about HOW state transitions (verbs, not nouns): pure-vs-mutating, atomic-vs-racy, enforced-vs-trust-the-caller, with-rate-limit-vs-without, sanitized-vs-raw.

An external review reliably surfaces 12+ findings the default lens set misses. Run them BOTH; cross-check.

## The 12 lenses to add (R1 + R2)

When commissioning a multi-agent code review, the dispatch MUST include these explicit lenses in addition to the default 5:

1. **Perf** — sequential awaits in startup paths, hot-path allocations (`getAll()` materializing whole libraries), unbounded loops, missing indexes, time-to-first-frame contributors. Even when the primary task is "race conditions", add perf as an explicit secondary lens for code running before `runApp()`.

2. **Telemetry coverage** — every catch block under `lib/core/services/`, `lib/shared/repositories/`, and Edge Functions must route errors through a production-observable channel (Crashlytics + `log-client-error`). `debugPrint` inside a `catch` block is a finding, not a feature.

3. **Bundle / artifact size** — for native apps, run `flutter build apk --analyze-size` and diff against a target. Identify top 3 reducible deps. Switch Play Store delivery to App Bundle.

4. **Exhaustive enumeration on contract findings** — when one violation of "X is the sole writer" or "all writes go through Y" is found, immediately grep all callsites of the underlying primitive (`nutritionBox.put`, `Hive.box('foo')`) and enumerate every one. Don't stop at the first hit.

5. **Question every "what looks good"** — for each positive finding, write the assumption it depends on. Then ask: when does that assumption fail? (e.g. "10-min grace window is thoughtful" → assumption: webhook arrives within 10 min → fails when payment provider retries for 24 hours → real finding.)

6. **CQRS / pure-function discipline** — for every method whose name reads like a query (`get*`, `calculate*`, `read*`, `is*`, `has*`), trace whether it actually mutates state. Side-effect-on-read footguns produce unreproducible bugs.

7. **Concurrency on shared state** — for every `getX() → modify → setX()` on shared Hive/Postgres state, identify ALL writers. If there are ≥2 and no atomicity (compareAndSet, version field, RPC, mutex), it's a lost-update race. Especially audit any field touched by both a periodic refill path AND a per-action consume path.

8. **Service-level invariants** — for every business rule ("no 3+ consecutive rest days", "swap source ≠ target", "max 1 freeze per missed day"), identify whether it's enforced at the service layer or only at the UI. UI-only enforcement means any new entry point (AI tool, migrator, restore, deep link) is a backdoor.

9. **Endpoint-by-endpoint rate-limit matrix** — list every Edge Function. Assert each has either a per-user rate limit or an explicit justification for why none is needed. Especially audit endpoints that fan out to paid third-parties (payment cancel, OneSignal POST, Gemini API).

10. **Prompt input sanitization** — every `'$userField'` or `${userField}` interpolation into a prompt is a potential injection vector. Strip control chars, limit to alphanumerics + small allowlist, cap length.

11. **Cron job efficiency** — every cron should have a "skip if no change" predicate, not "recompute everything every run." Recomputing-everything goes from "acceptable today" to "billing alert" without warning.

12. **Telemetry data quality** — accepting telemetry isn't the same as receiving useful telemetry. If the client sends `error.runtimeType.toString()`, the DB will fill with `String`, `_Map<String, dynamic>`, `TypeError`. Check whether data going INTO the table is queryable, or whether it's noise.

## Round 3 additions (L14-L26 in canonical registry)

External Hermes review surfaced more lenses around Edge Functions, schema-vs-payload parity, defense-in-depth, gate strictness:

14. **Edge Function semantic correctness** — read each function top-to-bottom for variable hoisting / TDZ, unreachable branches, missing `await`, exception swallowing.

15. **Schema-vs-payload parity** — after every migration touching column nullability, grep every `.from('<table>').insert|upsert|update` callsite and assert the NOT NULL column is in the payload. Gate: `scripts/check_schema_payload_parity.dart`.

16. **Authorization defense-in-depth on service-role paths** — for each Edge Function using `SUPABASE_SERVICE_ROLE_KEY`, grep every privileged read/write and assert user-scope check immediately precedes it. RLS does NOT apply to service role.

17. **Gate-strictness** — for each `scripts/check_*.dart`, audit every `exit(0)` to assert it's legitimate (silent CI passes are findings).

18. **Intra-document drift** — grep CLAUDE.md / AGENTS.md for known-drift pairs (table count, migration count, edge function count).

19. **Telemetry coverage on async failure legs** — grep every `unawaited(...)` and confirm error sink.

20. **Migration reversibility / forward-compat** — for each migration touching nullability/drop/type, document the staged-rollout breaking window.

21. **Idempotency replay completeness** — for each replay-able write, simulate 3 replays in test.

22. **Empty-state / null-shape readers** — for every consumer of a writer's output, contract test must include `empty | malformed | missing-key | wrong-type` cases.

23. **Cross-account state leak beyond Hive** — sweep in-memory singletons + 3rd-party SDK user-tagged state (NavigatorObserver, Crashlytics user_id, OneSignal external_id, payment-SDK cookies, WebView cookies).

24. **Backup/restore round-trip completeness** — assert every `syncX` has paired `_restoreX` + round-trip test.

25. **PII / privacy in telemetry payloads** — classify every `logEvent` / `recordNonFatal` payload as `NoPII | UserText | UserMedia | UserHealth`. Reject UserHealth/UserMedia unless allowlisted.

26. **Cross-document semantic consistency** — for every cleanup cron, cross-reference the migration that defines the bucket/table purpose.

## Cross-check process

13. **Cross-check audit findings against an independent reviewer.** Across two external rounds: 12 findings the default missed, 2 expansions to existing findings, 1 false alarm caught. The default review caught 11 confirmed criticals the external missed. Both reviews are valuable; neither is sufficient alone. Run cross-check BEFORE handing the report to the user, not after.

## Self-assessment trap

Declaring "comprehensive" is the wrong assessment frame. Don't measure coverage by lens-count, measure by what an independent reviewer would find. After any round, ask "what classes of bug does this audit STILL not cover?" rather than marking it finished.

## References

- Canonical lens registry: `docs/audit/LENS_REGISTRY.md` (53 lenses numbered + dispatch checklist + last-run tracker).
- Related: [`live-verification.md`](live-verification.md), [`verifier-cannot-trust-subagent.md`](verifier-cannot-trust-subagent.md), [`audit-closure-yaml.md`](audit-closure-yaml.md).
