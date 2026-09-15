---
name: GoRouter clears URL fragment before widget can read it
description: GoRouter's initialLocation calls history.replaceState during runApp(), stripping the URL hash before any widget's initState runs. Fragment-parsing code in initState is always too late.
type: feedback
---

**What I claimed (in b49ed15b):** "Parsing `Uri.base.fragment` in `SplashScreen._runDeferredInit` (called from `initState`) before `Supabase.initialize()` is the earliest possible detection point."

**What's actually true:** GoRouter processes `initialLocation: '/splash'` during widget-tree bootstrap (inside `runApp()`), which calls `history.replaceState()` — stripping the URL hash. By `initState`, it's already gone. The fragment must be read in `main()` before `runApp()`.

**How I went wrong:** Mental model was "fragment check before `Supabase.initialize()` = safe." Never asked "what runs between page load and this check that might consume the fragment?" Assumed `initState` was the earliest code point, forgetting GoRouter runs during Flutter's widget mounting phase which precedes any user widget's `initState`.

**How to avoid next time:** Before reading any browser URL state (fragment, query params, etc.) in a widget's `initState`, verify that no router/framework code has already consumed it. The safe rule: capture in `main()` before `runApp()`; anything inside a widget is suspect. Add a "browser state timing" lens to any code-review that reads `Uri.base.*` inside a widget.
