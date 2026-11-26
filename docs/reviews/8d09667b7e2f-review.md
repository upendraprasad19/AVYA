---
reviewed_at: 2026-11-26T19:30:00+05:30
staged_against: d2ade669 (origin/main...HEAD, after CI green on PR #358)
blast_radius: feature
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, guard_without_its_mirror, asserted_fixture_value, missing_input, unawaited_no_error_sink, secrets_in_tree]
findings_count: 6
verdict: accepted
---

# Code Review — nutrition-history-v2 (d2ade669)

## Finding 1 — P3 — overflow
- **file:line:** lib/features/nutrition/widgets/history/history_more.dart (monthly row cells)
- **claim:** narrow numeric columns wrap mid-word at 360 dp / text scale 1.3.
- **verification:** screen test "monthly report at 360 dp and text scale 1.3"
- **status:** accepted (fixed: numeric and header cells in a scale-down FittedBox; test added; mutant M19 red)

## Finding 2 — P3 — copy
- **file:line:** history_more.dart weight cell
- **claim:** -0.04 kg printed "−0.0 kg".
- **verification:** v2 test "weight change text never shows a signed zero"
- **status:** accepted (fixed: weightChangeText rounds first; mutant M18 red)

## Finding 3 — P3 — spec
- **file:line:** history_sections.dart HistoryWeightOverlay date row
- **claim:** no mid date label (plan U7 / D8).
- **verification:** grep historyDayLabel in the overlay
- **status:** accepted (fixed: first / mid / last)

## Finding 4 — P3 — spec
- **file:line:** history_sections.dart _SplitPainter
- **claim:** 0/50/100 labels without gridlines (U8).
- **verification:** grep drawLine in _SplitPainter
- **status:** accepted (fixed: three gridlines)

## Finding 5 — P3 — layout / a11y
- **file:line:** history_trend_chart.dart YAxisLabels; overlay Semantics
- **claim:** top/bottom labels ~6 px off their gridlines; overlay summary read twice.
- **verification:** read YAxisLabels
- **status:** accepted (fixed: labels centred on gridlines via Positioned + FractionalTranslation; excludeSemantics on the overlay)

## Finding 6 — P3 — performance
- **file:line:** history_more.dart monthlyRows in build
- **claim:** recomputed on every year tap.
- **verification:** read _HistoryMonthlyReportState.build
- **status:** accepted (fixed: cached until days, weights or today change). Also the two curly-brace infos fixed.

## Founder triage notes
All P3, all fixed in this batch.

## Tuning entry
- **2026-11-26** - blast-radius feature - 6 findings; 0 false_alarm; tuning: none (lens 6 caught two plan lines the build dropped, U7 mid label and U8 gridlines: re-reading the plan unit by unit against the diff is the check that found them).
