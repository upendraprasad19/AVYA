// Fixture for test/contracts/cqrs_query_naming_gate_test.dart.
//
// NOT part of the app. Every member below is a DELIBERATE violation of the
// CQRS query-naming rule, one per detection shape, so the gate can be proven
// to discriminate rather than merely to pass.
//
// Verifying a gate by planting a violation in a real lib/ file and reverting
// it is how Unit 7's round-2 reviewer silently wiped a batch's work (diagnose
// d4e7c2). A committed fixture makes the negative control repeatable and
// harmless.
//
// Expected: the gate reports EXACTLY the 4 members marked VIOLATION and none
// of the ones marked CLEAN.

// ignore_for_file: unused_element, unused_local_variable

class _FakeBox {
  void put(String k, Object v) {}
  void putAll(Map<String, Object> m) {}
}

class _FakeWriter {
  void commitSomething() {}
}

class MigratedKey {
  static void write(String k, Object v) {}
  static void delete(String k) {}
}

class ErrorTelemetry {
  static void logEvent(String name, {String? message}) {}
  static void recordNonFatal(Object e, StackTrace st, {String? reason}) {}
}

class Fixture {
  final _FakeBox _box = _FakeBox();
  final _FakeWriter _writer = _FakeWriter();

  // VIOLATION 1 — direct low-level Hive write in a get*-named method.
  int getCountAndCache() {
    _box.put('count', 1);
    return 1;
  }

  // VIOLATION 2 — MigratedKey.write in an is*-named method.
  bool isReadyAndStamp() {
    MigratedKey.write('ready', true);
    return true;
  }

  // VIOLATION 3 — repository-pattern writer call in a has*-named method.
  // This is the shape a low-level-only gate would miss: rule 4 routes nearly
  // every real write through a WriteService, so `.commitX()` IS the write.
  bool hasPendingAndCommit() {
    _writer.commitSomething();
    return true;
  }

  // VIOLATION 4 — TWO-hop same-file delegation. Neither this body nor its
  // direct callee contains a write; the write is a further hop down. This is
  // the `calculateCurrentStreak() => consumeMissedDayIfFreezeAvailable() =>
  // _calculateStreak(consume: true)` shape.
  int calculateViaDelegate() => _hopOne();
  int _hopOne() => _hopTwo();
  int _hopTwo() {
    _box.putAll({'a': 1});
    return 1;
  }

  // CLEAN 1 — telemetry ONLY in the catch block. Reporting an error you
  // failed to answer with is not a mutation of the query's result. This is
  // exactly why the 2026-07-29 board correction removed
  // `RankService.getCurrentRank()` from OI-44's finding list; a gate that
  // flags this reintroduces a false positive the board already retired.
  int getValueWithCatchTelemetry() {
    try {
      return 1;
    } catch (e, st) {
      // Both shapes, so the control covers the real getCurrentRank pattern
      // (recordNonFatal-in-catch) AND the stricter logEvent/write case.
      ErrorTelemetry.recordNonFatal(e, st, reason: 'get_value_failed');
      ErrorTelemetry.logEvent('failed', message: '$e');
      MigratedKey.write('failed', true);
      return 0;
    }
  }

  // CLEAN 2 — the write text appears only inside a STRING and a COMMENT.
  // Without comment/string scrubbing a source-grep reads prose as code — the
  // feedback_source_grep_strip_comments_first.md class.
  // Counter-example for the linter: _box.put('nope', 1);
  String getDescription() {
    final doc = "call _box.put('x', 1) to persist, or MigratedKey.write(...)";
    return doc;
  }

  // CLEAN 3 — a genuinely pure query that merely READS.
  int getPureCount() {
    final n = 1 + 1;
    return n;
  }

  // CLEAN 4 — mutating, but HONESTLY NAMED. The verb admits the write, so
  // there is nothing to flag. The gate must not police every writer, only
  // ones wearing a query name.
  void commitSomethingHonestly() {
    _box.put('k', 1);
  }
}
