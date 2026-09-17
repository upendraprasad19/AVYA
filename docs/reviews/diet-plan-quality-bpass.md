# B-pass review — diet-plan-quality

reviewed_at: 2026-09-17
reviewer: fresh context-blind agent (adversarial, 10 lenses)
diff: git diff main...HEAD (commits 986caf68, 3e3c0da0, 1ae0070f)
blast_radius: platform (food DB schema v3 + generator + seed version)
verdict: CHANGES-REQUIRED at review time -> all findings remediated in-batch -> ACCEPTED

## Findings at review time

1. [BLOCKER] Asset append introduced 4 duplicate food names (Tempeh cooked /
   Seitan cooked / Hemp Seeds / Edamame cooked already existed as F0375,
   F0376, F0477, F1018) breaking the no-duplicate-names contract in
   food_database_v2_test.dart, and all 10 appended rows carried source
   'icanbefitter_seed', inflating the pinned seed-row count 93 -> 103.
   2 RED assertions on main at merge. VERIFIED by running the v2 test.
   REMEDIATION: scripts/fix_bpass_f1_duplicate_rows.dart — 4 duplicate rows
   removed (originals strictly better for hemp 9.6g vs 6.3g / edamame 18.6g
   vs 11.9g per serving; anchor-pool name lookups resolve through the
   originals), remaining 6 re-sourced 'icanbefitter_seed_v3'. v2 test green.

2. [MAJOR] veg preference was still a 9-name blocklist — 187 is_veg=false
   rows leaked through, 117 generator-reachable ('Anda Paratha' into staples
   fillers; chicken variants via Strategy C / _highestProteinFallback). The
   batch had made is_vegan authoritative but left veg on the blocklist —
   identical defect class. REMEDIATION: is_veg now authoritative for the veg
   preference (blocklist = untagged-row fallback), mirroring the vegan fix;
   veg-purity test added to food_database_tagged_test.dart.

3. [MAJOR] _dietPref never set on the saved-plan path (default 'veg') — a
   vegan user loading a saved plan got veg-filtered (dairy-allowed) swap
   alternatives. REMEDIATION: profile read moved into _generatePlan so BOTH
   paths (fresh + saved-load) cache the preference.

4. [MINOR] Recovery swap-ins never registered in usedIds (asymmetric with
   _upgradeWeakAnchors which does both). REMEDIATION: all five swap sites
   (Pass 3 A/B/C, Pass 4, Pass 5) now register the swap-in; swapped-OUT ids
   deliberately stay burned (conservative for variety).

5. [MINOR] _pickAnchor honored neither _isUpf nor meal_fit (latent invariant
   gap — all 28 anchor-pool rows clean today). REMEDIATION: UPF filter added
   to anchor candidates (invariant hardening; no behavioral delta possible
   with current data, covered by the real-DB no-UPF sweep if data flips).
   meal_fit deliberately NOT enforced on curated anchor pools (pools are the
   authority; 'Whey Protein (scoop)' meal_fit=snack vs breakfast-pool is a
   DB editorial note, not a generation bug).

6. [MINOR] Swap sheet: zero alternatives -> silent no-op (newly reachable
   with narrower pools). REMEDIATION: 'No alternatives available' snackbar.

7. [NOTE] Two source-grep tests (saved-plan keys, swap-filter presence) are
   presence-only per r21 — accepted; the behavioral pins live in the
   fixture + real-DB suites. The real-DB no-UPF guard matches the literal
   name 'pringles' — the Maggi-small + jar fixture rows carry the
   behavioral weight in the fixture suite.

8. [NOTE] Verified clean: saved-plan JSON schema unchanged; AH.5 invalidate
   flow intact; putAll re-seed cannot delete custom foods/saved meals;
   version flag written after putAll (failed re-seed retries); no
   cross-call state leak through the generator singleton; fiberTarget
   default matches nutrition_provider.dart:362.

## Post-remediation verification

- 30/30 tests green: food_database_tagged_test (12 incl. veg purity),
  diet_plan_generator_test (4 fixture archetypes), diet_plan_quality_
  constraints_test (10 guards), food_database_v2_test (6, incl. the two
  that were RED at review time).
- New guard added during remediation (day-level Pass 4 trim append — the
  day ceiling can bust while no slot is individually over 1.2x):
  mutation-proven M9 (disabled -> 'balanced maintain seed=1: protein
  surplus 153 vs <= 149.5' RED; enabled -> green).
- Anchor-upgrade day-ceiling guard added (upgraded anchors are
  isAnchor-protected; without the guard the maintain archetype breached
  the ceiling and Pass 4 could not trim it back).
