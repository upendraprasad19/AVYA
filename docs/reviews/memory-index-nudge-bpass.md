# B-pass / self-consistency review — memory-index-nudge

verdict: accepted

**Scope reviewed:** the `memory-index-nudge` branch diff — `scripts/discipline_hook.dart`
(a new `_memoryIndexNudge()` helper + its wiring into the SessionStart handler) and the
root `CLAUDE.md` §7 discipline-hook row. Blast-radius is **platform** driven **solely** by
the CLAUDE.md path (the hook script alone classifies as `feature`), so per CLAUDE.md §4.3
this is a **self-consistency + logic review**, not an adversarial product bug-hunt.

## Lenses

**1. Fail-silent contract (the load-bearing invariant).** The file's top contract is "these
hooks must NEVER break the session." `_memoryIndexNudge()` wraps its entire body in
`try { … } catch (_) { return ''; }`, and every early-return yields `''`. A missing file,
an unresolvable home dir, an unreadable path, or a mangling mismatch all resolve to `''`
→ no nudge, no throw. The SessionStart handler only ever *appends* the nudge string; it
never changes the compact-reinject or hot-set behavior. **Verdict: safe.** Proven by test
scenario 3 (nonexistent path → reinject present, no crash) and 8 (empty stdin → 0 output).

**2. Threshold correctness (De Morgan).** Guard is `if (bytes <= 18000 && lines <= 150)
return '';` → the nudge fires when `bytes > 18000 OR lines > 150`, matching the plan's
">18,000 bytes or >150 lines." The 18,000-byte trigger sits ~490 B above the 17,510-byte
soft target, giving deliberate hysteresis so a freshly-consolidated index (currently 17,502 B)
does **not** nag. **Verdict: correct.** Proven by scenario 1 (over-cap fires) + 2 (real
17.5 KB index → silent).

**3. Path resolution robustness.** The memory dir lives OUTSIDE the repo at
`~/.claude/projects/<mangled>/memory/MEMORY.md`; `<mangled>` is `Directory.current.path`
with each of `: \ / space` → `-` (verified: `C:\Upendra\Claude Code\Fitness App` →
`C--Upendra-Claude-Code-Fitness-App`). If the algorithm ever drifts from the harness's real
mangling, `existsSync()` is false → `''` (degrades to no-nudge, never a crash). A
`DISCIPLINE_HOOK_MEMORY_PATH` env override exists for testing and is inert in prod (unset).
**Verdict: robust-by-degradation.**

**4. Matcher scope / no settings change.** The nudge folds into the existing
SessionStart(`matcher: "compact"`) registration — no `.claude/settings.json` change. It
fires post-compaction (frequent in exactly the long sessions where index bloat matters); a
forward-compat branch also surfaces it if the matcher is ever broadened to non-compact
sources, and never emits the compact re-inject on a non-compact source. Existing
UserPromptSubmit hot-set + PreToolUse skill-reminder paths are untouched. **Verdict: scoped
correctly** (regression scenarios 4/6 green; non-trigger scenario 5 silent).

**5. Wording self-consistency (the CLAUDE.md §7 row).** The edited row names the new nudge,
the user-level skill path (`~/.claude/skills/consolidate-memory/`), and both retrospectives
(`project_discipline_harness_hooks_2026_06_27.md`, `project_memory_consolidation_2026_07_04.md`).
The `memory/…` external-path convention matches the pre-existing row. No internal
contradiction with the SessionStart-compact wiring described. **Verdict: consistent.**

## Evidence
`dart analyze scripts/discipline_hook.dart` → No issues found. 8-scenario test matrix (over-cap
fires, under-cap/missing-file silent, fail-silence, hot-set/skill/empty-stdin regressions all
intact) → all green. Staged diff = exactly 2 files.

## Findings
None material. The change is a fail-silent, additive tooling nudge + a doc-sync row; no product
code, schema, Edge Function, or auth surface is touched.

verdict: accepted
