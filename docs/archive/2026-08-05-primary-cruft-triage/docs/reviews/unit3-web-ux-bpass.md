---
reviewed_at: 2026-06-14T00:30:00+05:30
staged_against: unit3-web-ux (pre-merge)
blast_radius: feature
reviewer: claude-sonnet-via-code-review-skill (fresh, context-blind)
lens_set: [pwa_widget_lifecycle, conditional_import_symbol_parity, health_gate_completeness, quote_call_sites, js_hook_name_match, secrets, unawaited_sink]
findings_count: 2
verdict: accepted
---

# Code Review (B-pass) — Unit 3 web-UX

Fresh context-blind Sonnet pass over the staged diff (health web gate, quote-from-exercises +
word-bounded keywords, PWA install banner). JS-interop already passed `flutter analyze` +
`flutter build web`; the pass weighted runtime logic the build can't catch (the `PwaInstallBanner`
StatefulWidget). **No P0/P1.** 2 P2 cosmetic findings.

## Findings
### Finding 1 — P2/note — `quote_picker.dart` `\bRUN` open-ended — NOT FIXED (intended)
`\bRUN` matches Run/Running/Runner (all cardio — desired) and correctly rejects "grunt". Tightening to
`\bRUN\b` would BREAK "Running"→cardio. The "RUNE" edge is speculative (no such exercise). Left as-is.

### Finding 8 — P2 — `biometric_sync_card.dart` "APP ONLY" chip color — RESOLVED
The web "APP ONLY" chip's fill+text color was still driven by `isSyncEnabled`; a returning mobile user
(isSyncEnabled=true) viewing on web would see gold-on-transparent (inconsistent). Fixed: `(isSyncEnabled
&& !kIsWeb)` so the web chip is always the dimmed gold-fill + dark-text disabled state.

## Clean lenses (verified by the reviewer)
- PwaInstallBanner: Timer null-safe on mobile + `mounted`-guarded on fire + cancelled in dispose;
  `!kIsWeb` early-return leaves safe field state; `_install` async setState is `mounted`-guarded;
  `_dismiss` is synchronous; never renders in the Android app (`!kIsWeb` first build guard).
- Conditional import: stub + web export the same 3 symbols/signatures; `dart.library.js_interop` key;
  `@JS('avya*')` names match `index.html` exactly.
- Health gate: all 4 native methods `kIsWeb`-guarded (isEnabled correctly unguarded); the card disabled
  state leaves no web path to `toggleSync`.
- Quote: all 3 call sites pass exercise names; `categoryForExercises` empty/all-general handled;
  tie-break deterministic (insertion order); regexes well-formed.
- No secrets; no unawaited-without-sink.

## Verdict
ACCEPTED — Finding 8 fixed; Finding 1 is intended behavior. Re-analyze on commit via pre-commit.
