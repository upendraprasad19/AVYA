# OI-493 Landing B: the same meal logged twice adds two entries (draft, reviewed after Landing A lands)

Split from `docs/plans/oi493-nutrition-parity.md` rev 2 (§4.12.1). Founder decision F4 (2026-11-12): "if we are logging
same meal twice it should log twice", for the coach and the screen. Own worktree from main after Landing A, own two plan
reviews, B-pass and record. Closes OI-493 (with Landing A's ledger rows). Blast radius `account` (shared writer, migrator).

## Findings carried from plan review #1 (both seats), to design against
- Key choice and `put` must not be separated by an `await` (Hive 2.2.3 keystore inserts synchronously); serialise
  `logMeal`'s choose-key-and-put with a lock and test two un-awaited `logMeal` calls -> two rows (mutant: an
  `await Future.delayed(Duration.zero)` between them).
- Delete then UNDO: `restoreLastDeleted` (`nutrition_write_service.dart:576-590`) and `restoreFoodLog` (:866-880) put
  blindly; a relog inside the 10 s UNDO window takes the deleted key and UNDO overwrites it. Restore into the first free
  occurrence when the key is taken.
- `NlogKeyMigrator` (`nlog_key_migrator.dart:22-115`) recomputes keys with `String.hashCode` on the UTC date of
  `logged_at` and keeps only the latest per key: on a device that has not run v7 it would collapse occurrence rows, and it
  already rewrites every current-shape row today. Skip rows whose key is already current-shape
  (`^nlog_\d{4}-\d{2}-\d{2}_(breakfast|lunch|dinner|snacks)_[0-9a-f]{8}$`); decide and test the pre-v5 hashCode-shaped
  current keys (testers only; state the residual or handle it).
- Double dispatch: the tool marker is stamped after success (`tool_dispatcher.dart:107-131`); add an in-flight set by
  intent id so two concurrent `execute` calls of one intent log once.
- Double taps on the screen (recent list, search result, barcode, AI-text save) now add twice: add an in-flight guard per
  control (disabled until `logMeal` returns).
- Zero override: `logMeal` falls back to the Atwater total when an override is 0 (`scan_meal_section.dart:447`,
  `AiBreakdownNotifier.saveMeal`, the coach tool pass overrides); all-zero macros stay 0; test both.
- Totals vs items: a passed override can differ from the item sum and jumps after `editLog`; decide (normalise or keep).
- `moveMealLog` (:408-445) keeps its merge-on-collision; add an occurrence-1 move case to
  `nutrition_log_retag_writer_to_reader_test.dart`.
- Restore on a second device collapses two occurrence rows into one row with two items (one cloud row per slot); per-serving
  delete on that device removes both. Accepted residual, documented; P12 asserts the restored key is current-shape.
- `meals_today` lists two identical entries twice; acceptable (it is two servings).
