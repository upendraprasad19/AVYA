# Knowledgebase Pointer

> Tech-debt audit 2026-05-20 finding I13 — bus-factor mitigation.
> The `Knowledgebase/` directory at the repo root is gitignored (line 70
> of root `.gitignore`) along with `assets/*.docx`, `*.xlsx`, `*.pdf`, the
> calisthenics features doc, and naval-rank reference imagery. Founder
> reference materials live there exclusively on the build machine —
> a fresh clone has zero context for what these files meant in design
> decisions.

## What lives in `Knowledgebase/`

Founder reference materials that informed design decisions but never ship
in the APK:

| Asset type | Purpose |
|---|---|
| Exercise spreadsheets | Source library for `exercise_library` (~1,200 entries before seed-trim). The seed JSON in `assets/data/exercise_library.json` is the shipped subset. |
| Calisthenics feature doc | Phase-by-phase progression spec for the bodyweight track. Drove `lib/shared/repositories/plan_engine/` archetype design. |
| Naval rank reference imagery | Visual source for the 11-rank ladder (SD2 → Lt → Cdr → ...). Wardroom design system pulls from these. See `lib/shared/widgets/wardroom/CLAUDE.md` for the JSX SoT for palette/rank insignia. |
| Founder notes / PDFs | Onboarding flow drafts, AI coach prompt experiments pre-Gemini collapse, monetisation strategy spike. |

## Why these are gitignored (not destroyed)

- They're founder-private design source. Not licensed for redistribution.
- They're large (multi-MB binaries) and don't belong in git history.
- They're regenerable / superseded by what's actually shipped in the
  codebase (seed JSON files, the live design system).

## How to restore on a new machine

Pull from the password manager / off-machine backup per
`docs/operations/SECRET_INVENTORY.md` (treat the `Knowledgebase/`
directory like any other local-only secret with a documented restore
source).

## How to add new founder-reference material

1. Drop the file into the appropriate `Knowledgebase/` or `assets/`
   subdirectory.
2. If it's a NEW pattern (new asset type), add a row to the table above.
3. If it informed a design decision that landed in the codebase, cite the
   commit + the code location in the design's diagnose-doc (so future-you
   can trace the rationale).

## Anti-pattern (banned)

- Do NOT inline Knowledgebase content into `docs/architecture/` or
  `CLAUDE.md` "just in case" — those are public-facing and the
  Knowledgebase material isn't licensed for that exposure. Cite by name
  and path; let the reader pull from their local copy.
- Do NOT delete a `Knowledgebase/` file in a sweep without first checking
  whether any design decision references it (grep `docs/` for the
  filename).
