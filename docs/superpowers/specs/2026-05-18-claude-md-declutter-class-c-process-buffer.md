# Class C — Process discipline entries (for new root §3)

> Buffer for entries that should land in root CLAUDE.md §3 during Milestone 6.
> 5 entries (audit summary said "4" but per-entry classification lists 5: 5, 49, 60, 76, 148).

| Pitfall | How to avoid | Source |
|---|---|---|
| Wrong import path | Use relative within features, package: for shared/core. | CLAUDE.md §19 entry 5 |
| Gradle build hangs silently | Check `android/gradle.properties` — `-Xmx` must be ≤4G on 16GB system. 8G causes OOM with no terminal output. Check for `android/hs_err_*.log` crash dumps. Also remove stale `flutter/bin/cache/lockfile` if Flutter commands hang on lock. Use `/build-apk` skill. | CLAUDE.md §19 entry 49 |
| Worktree APK build fails with "Did not find .env" | `.env` is gitignored and not copied when creating a new git worktree. Before `flutter build apk` in a new worktree, copy from the main: `cp "C:/Upendra/Claude Code/Fitness App/.env" <worktree>/.env`. Without it `SUPABASE_URL` compiles to empty string and auth crashes at startup. | CLAUDE.md §19 entry 60 |
| Built APK via `flutter build apk` directly | Always use the `/build-apk` skill. `flutter build apk` can hang silently on this machine (16 GB system, `-Xmx4G` Gradle heap) without emitting output. The skill does pre-flight cleanup (stale `flutter/bin/cache/lockfile`, Gradle caches, JVM crash dumps at `android/hs_err_*.log`) that prevents the hang. Direct Bash `flutter build apk` skips that and occasionally costs 30+ min of debug. See memory `feedback_use_build_apk_skill.md`. | CLAUDE.md §19 entry 76 |
| Master Audit / multi-agent surveys produce false-positive findings | Lesson from audit 2026-05-12 — **3 of 21 Master Audit findings were false alarms** (P1-A `coaching_notes`/`coach_notes` already correct; P1-B sync ordering already fixed in Test #14 / Bug B.1; P1-F terms columns existed on `users` not `user_profile`). Each was caught only by verifying live SQL + reading the actual code path. Rule: **never apply a multi-agent audit finding without first reading the cited file:line AND verifying claimed cloud state via live `information_schema` query.** Cite the verification SQL in the audit report so the next person doesn't re-do the work. Codified in `feedback_audit_findings_require_live_verification.md`. | CLAUDE.md §19 entry 148 |
