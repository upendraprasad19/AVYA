---
adr_id: 0003
title: Riverpod for state management
status: accepted
date: 2026-03-23
deciders: Upendra
---

# ADR-0003: Riverpod for state management

## Context

Cross-platform Flutter app, solo founder. State management choice affects
every widget, every screen, every async flow.

Constraints:
- User-scoped state must clear on sign-out without leaks (cross-account
  Riverpod cache race was Test #15.4 / B1).
- Auth state changes must trigger re-render of every user-scoped
  provider (the `authUserIdTokenProvider` pattern, Test #15.3 / Bug 5
  with 56 providers retrofitted).
- Hive + Supabase reads should fit naturally in the chosen primitive.
- Code-gen is acceptable if it eliminates boilerplate.

## Decision

**Riverpod** (initially `flutter_riverpod` ^2.x with hand-written
providers; `riverpod_generator` available but not yet broadly used).

All shared state goes through Riverpod providers. `setState` is
permitted for purely local widget state. Encoded in CLAUDE.md rule 2.

## Alternatives considered

1. **BLoC / flutter_bloc.** Rejected.
   - Boilerplate-heavy (Events + States + Bloc per concept) without
     code-gen carrying its weight at our scale.
   - Forces an event-sourcing mental model on simple async reads. Hive
     reads are sync; wrapping them in `Bloc<LoadX, XState>` adds
     ceremony for no benefit.
   - Auth re-watch pattern is awkward — you have to bus events.

2. **Provider (the package, predecessor to Riverpod).** Rejected.
   Riverpod was written explicitly to address Provider's compile-time
   safety + scoping limitations. No reason to start with the predecessor.

3. **GetX.** Rejected.
   - Global-singleton-flavored architecture conflicts with the
     user-scoped-state requirement.
   - Larger surface area (DI + state + routing in one); we want
     orthogonal primitives.
   - Community support is rocky; Anthropic engineering best practices
     (eng-practices) favor narrower, well-maintained dependencies.

4. **MobX.** Rejected. Reactive-observable model is fine but Flutter
   integration is less idiomatic than Riverpod; community is smaller;
   migration ergonomics during refactors are worse.

5. **`setState` everywhere + InheritedWidget for shared.** Rejected.
   Hand-rolled InheritedWidget at the scale of 30+ screens becomes
   unmaintainable. We'd reinvent Riverpod badly.

## Consequences

Good:
- **Provider override at test time.** Every test that needs a mock
  Hive box or fake Supabase client can inject via `ProviderContainer`
  + `overrideWithValue`. This is what makes 219 contract tests work.
- **Auth re-watch is one pattern.** Every user-scoped provider's
  `build()` reads `ref.watch(authUserIdTokenProvider)`. Sign-out
  invalidates → all providers rebuild → fresh state.
- **Compile-time safety.** Wrong-type provider read fails at compile.
- **Family providers** for per-id state (a specific exercise log, a
  specific food entry) are idiomatic.

Bad:
- **Cross-account cache race** was a real bug (Test #15.4). The
  combination of Riverpod's keepAlive defaults + Hive's user-scoped
  boxes had a window where stale provider state survived sign-out.
  Closed via two-layer fix (HiveUserSession wrap + auth-watch
  retrofit). Lesson: Riverpod isn't automatic; you have to design
  for auth boundaries.
- **`@riverpod` annotations + code-gen not yet broadly adopted.**
  Most providers are hand-written. Migration to code-gen would
  reduce boilerplate but is multi-batch work; deferred.
- **Provider proliferation.** 56+ user-scoped providers is a lot to
  audit for the auth-watch pattern. Gate `check_singleton_provider_migration.dart`
  enforces; manual audit risk remains.

## Status

Active. The code-gen migration is a candidate for a future batch but
not blocking.

## See also

- CLAUDE.md rule 2
- `feedback_singleton_cross_account_leak.md` (if it exists in handbook)
- Test #15.4 / B1 retro: cross-account Riverpod cache race
- Test #15.3 / Bug 5: 56-provider auth-watch retrofit
