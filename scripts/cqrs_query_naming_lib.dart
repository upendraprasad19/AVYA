// scripts/cqrs_query_naming_lib.dart
//
// Pure detection logic for the CQRS query-naming gate (OI-44 / L26).
// The CLI lives in `scripts/check_cqrs_query_naming.dart`; the contract test
// imports THIS file directly.
//
// Split out for the same reason as `worktree_guard_lib.dart`: a gate whose
// logic is only reachable by spawning a subprocess is painful to test and
// easy to get wrong. The first attempt at this test did
// `Process.runSync(Platform.resolvedExecutable, ['run', gate])` — but under
// `flutter test` the resolved executable is `flutter_tester`, not `dart`, so
// it spawned hung flutter_tester processes instead of running the gate.
//
// ── What this detects ────────────────────────────────────────────────────
//
// A `get*` / `is*` / `has*` / `calculate*` method, or a Dart getter, reads as
// side-effect-free at every callsite. When it isn't, the damage surfaces
// somewhere unrelated:
//
//   - `WorkoutRepository.calculateCurrentStreak()` silently consumed a streak
//     freeze on EVERY render — three display surfaces called it, so three
//     renders could consume three freezes for one missed day. Split C-14
//     (audit-2026-05-11) into `currentStreak()` + the explicitly-named
//     `consumeMissedDayIfFreezeAvailable()`.
//   - `SubscriptionService.isPro()` downgrades entitlement and fires
//     `onStateChanged`, which `app.dart:47` wires to
//     `ref.invalidate(subscriptionInfoProvider)` — and
//     `SubscriptionInfoNotifier.build()` calls `isPro()`. A provider build
//     invalidates ITSELF.
//
// ── Why not OI-44's own proposed pattern ─────────────────────────────────
//
// The board proposed grepping bodies for `recordNonFatal`. That is a false-
// positive generator, and the 2026-07-29 board correction had to remove
// `RankService.getCurrentRank()` for exactly this reason: its telemetry fires
// ONLY in the exception catch block, and it writes nothing in any branch.
// Reporting an error you failed to answer with is not a mutation. So
// `catch (...) { ... }` blocks are stripped before scanning.
//
// ── Two layers of mutation pattern ───────────────────────────────────────
//
// Rule 4 (repository pattern) makes a raw `box.put(` the RARE shape here —
// nearly every real write goes through a WriteService. A low-level-only gate
// would miss `StreakProgressService.instance.commitConsume(...)`, which is the
// actual write behind this gate's own worked example.
//
// ── Delegation ───────────────────────────────────────────────────────────
//
// Same-file delegation is resolved TRANSITIVELY, because
// `calculateCurrentStreak() => consumeMissedDayIfFreezeAvailable() =>
// _calculateStreak(consume: true)` puts the write two hops from the query.
// Same-file and closure-bounded on purpose: a cross-file resolver is a
// different piece of engineering, and the thin-wrapper shape is what recurs.

import 'dart:io';

/// A query-named member that is allowed to mutate, and why.
///
/// Keyed `relative/path.dart::memberName`. Deleting an entry is how a refactor
/// commit records that it actually closed one — and [staleExemptions] FAILS
/// the gate if a deletion is forgotten, which is what keeps the ledger from
/// becoming a graveyard.
const Map<String, String> cqrsExemptions = {
  'lib/core/services/subscription_service.dart::isPro':
      'OI-44 Unit 6 — DELIBERATE and load-bearing. The cross-account guard '
          '(Hive profile.id != session.id => force-downgrade) is the defensive '
          'layer that catches Auto-Backup entitlement leaks the startup guard '
          '(hive_user_session.dart:221) misses; the expiry branch stamps '
          'pro_lapsed_at for the Home banner. Making this pure would narrow the '
          'guard from "every entitlement decision" to "wherever someone '
          'remembered to wire it" — a leak surface on a payment path. Unit 6 '
          'instead extracts _enforceEntitlementInvariants() + a pure '
          'proStateSnapshot(), routes BUILD METHODS to the pure read, and '
          'leaves this decision entry point behaving exactly as it does today. '
          'Behavioral: test/contracts/subscription_cqrs_behavioral_test.dart',
  'lib/core/services/supabase_service.dart::getOrCreateReferralCode':
      'OI-44 Unit 6 item D — PERMANENT, closed verified_clean. The hidden '
          'write is real (falls through to a live Postgres upsert via '
          '_generateNewCode), but "get-or-create" is a universally understood '
          'idiom that already announces the create, and this is the ONLY '
          'callsite (invite_friends_sheet.dart:64). Renaming buys no '
          'behavioural safety and churns a live payment-adjacent path. '
          'Recording the decision in an enforced ledger rather than in prose is '
          'the point: a board note rots silently, this cannot.',
};

/// Success-path mutation patterns. Each is (regex, human label).
final List<(RegExp, String)> mutationPatterns = [
  // Layer 1 — low-level storage writes.
  (RegExp(r'\bMigratedKey\.(write|delete)\s*\('), 'MigratedKey.write/delete'),
  (RegExp(r'\.\s*put\s*\('), 'Hive box.put()'),
  (RegExp(r'\.\s*putAll\s*\('), 'Hive box.putAll()'),
  (RegExp(r'\.\s*deleteFromDisk\s*\('), 'Hive deleteFromDisk()'),
  (RegExp(r'\.\s*(insert|upsert)\s*\('), 'Supabase insert/upsert'),
  (RegExp(r'\bErrorTelemetry\.logEvent\s*\('), 'ErrorTelemetry.logEvent()'),
  // Layer 2 — this repo's writer vocabulary (docs/naming_conventions.md).
  // The trailing [A-Z] keeps it to named service methods (`commitConsume`,
  // `updateProgress`, `markCompleted`, `patchProfile`) and off a bare
  // `Map.update(` / `List.remove(` on a local collection, which persist
  // nothing.
  (
    RegExp(r'\.\s*(commit|persist|save|update|upsert|write|patch|mark|grant|'
        r'revoke|stamp|reset|consume|log)[A-Z]\w*\s*\('),
    'WriteService/Repository writer call'
  ),
];

class CqrsViolation {
  final String file;
  final int line;
  final String member;
  final String pattern;
  const CqrsViolation(this.file, this.line, this.member, this.pattern);

  String get key => '$file::$member';

  @override
  String toString() => '$file:$line  $member()  — contains $pattern';
}

class CqrsScanResult {
  final List<CqrsViolation> violations;
  final int membersScanned;
  final int filesScanned;
  const CqrsScanResult(this.violations, this.membersScanned, this.filesScanned);

  /// Violations with no exemption entry. [applyExemptions] is false when
  /// scanning a fixture root, since the ledger is keyed on `lib/` paths.
  List<CqrsViolation> unexempted({bool applyExemptions = true}) => violations
      .where((v) => !(applyExemptions && cqrsExemptions.containsKey(v.key)))
      .toList();
}

/// Exemptions that no longer match any live violation — each is a graveyard
/// entry hiding the fact that nobody re-verified it.
List<String> staleExemptions(CqrsScanResult r) {
  final live = r.violations.map((v) => v.key).toSet();
  return cqrsExemptions.keys.where((k) => !live.contains(k)).toList();
}

/// Scan [rootPath] for query-named members that mutate.
///
/// [includeGetters] defaults to TRUE so the library default matches what the
/// wired CLI actually runs — pre-commit and CI invoke the gate with no
/// arguments. A false default would mean the contract test verified a
/// configuration nobody runs (round-1 P2-7).
CqrsScanResult scanRoot(String rootPath, {bool includeGetters = true}) {
  final dir = Directory(rootPath);
  if (!dir.existsSync()) {
    throw ArgumentError('scan root does not exist: $rootPath');
  }

  final violations = <CqrsViolation>[];
  var membersScanned = 0;

  final dartFiles = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in dartFiles) {
    final rel = file.path.replaceAll('\\', '/');
    final src = scrub(file.readAsStringSync());

    // Every member in this file, so same-file delegation can be resolved.
    final bodies = {
      for (final e in findAllDeclarations(src).entries)
        e.key: stripCatchBlocks(e.value),
    };
    final mutators = <String>{
      for (final e in bodies.entries)
        if (mutationLabel(e.value) != null) e.key,
    };
    // Transitive closure — bounded by member count, so it terminates.
    var grew = true;
    while (grew) {
      grew = false;
      for (final e in bodies.entries) {
        if (mutators.contains(e.key)) continue;
        if (delegatesToMutator(e.value, mutators, e.key) != null) {
          mutators.add(e.key);
          grew = true;
        }
      }
    }

    for (final decl in findQueryDeclarations(src, includeGetters)) {
      membersScanned++;
      final body = stripCatchBlocks(decl.body);
      final line = '\n'.allMatches(src.substring(0, decl.nameStart)).length + 1;

      final direct = mutationLabel(body);
      if (direct != null) {
        violations.add(CqrsViolation(rel, line, decl.name, direct));
        continue;
      }
      final callee = delegatesToMutator(body, mutators, decl.name);
      if (callee != null) {
        violations
            .add(CqrsViolation(rel, line, decl.name, 'delegates to $callee()'));
      }
    }
  }

  return CqrsScanResult(violations, membersScanned, dartFiles.length);
}

class Decl {
  final String name;
  final int nameStart;
  final String body;
  const Decl(this.name, this.nameStart, this.body);
}

/// The first mutation pattern present in [body], or null when clean.
String? mutationLabel(String body) {
  for (final (re, label) in mutationPatterns) {
    if (re.hasMatch(body)) return label;
  }
  return null;
}

/// Name of a same-file mutating member this body calls, or null. `self` is
/// excluded so a recursive helper can't accuse itself.
String? delegatesToMutator(String body, Set<String> mutators, String self) {
  for (final name in mutators) {
    if (name == self) continue;
    if (RegExp('\\b${RegExp.escape(name)}\\s*\\(').hasMatch(body)) return name;
  }
  return null;
}

/// Replace comment text and string-literal CONTENTS with spaces, preserving
/// length and newlines so offsets and line numbers stay valid. Without this a
/// `debugPrint('... .put( ...')` reads as a write and a doc comment describing
/// a bug reads as the bug — feedback_source_grep_strip_comments_first.md.
String scrub(String src) {
  final out = List<String>.from(src.split(''));
  var i = 0;
  while (i < src.length) {
    final ch = src[i];
    final next = i + 1 < src.length ? src[i + 1] : '';

    if (ch == '/' && next == '/') {
      while (i < src.length && src[i] != '\n') {
        out[i] = ' ';
        i++;
      }
      continue;
    }
    if (ch == '/' && next == '*') {
      out[i] = ' ';
      out[i + 1] = ' ';
      i += 2;
      while (i < src.length &&
          !(src[i] == '*' && i + 1 < src.length && src[i + 1] == '/')) {
        if (src[i] != '\n') out[i] = ' ';
        i++;
      }
      if (i < src.length) {
        out[i] = ' ';
        if (i + 1 < src.length) out[i + 1] = ' ';
        i += 2;
      }
      continue;
    }
    if (ch == "'" || ch == '"') {
      final triple = src.startsWith(ch * 3, i);
      final delim = triple ? ch * 3 : ch;
      i += delim.length;
      while (i < src.length && !src.startsWith(delim, i)) {
        if (src[i] == r'\' && i + 1 < src.length) {
          out[i] = ' ';
          out[i + 1] = ' ';
          i += 2;
          continue;
        }
        if (src[i] != '\n') out[i] = ' ';
        i++;
      }
      i += delim.length;
      continue;
    }
    i++;
  }
  return out.join();
}

/// Query-named DECLARATIONS (not callsites), with their bodies.
Iterable<Decl> findQueryDeclarations(String src, bool includeGetters) sync* {
  final methodRe = RegExp(r'\b(get|is|has|calculate)[A-Z]\w*\s*\(');
  for (final m in methodRe.allMatches(src)) {
    // A callsite is preceded by `.`; a declaration is preceded by a type.
    if (prevNonSpace(src, m.start) == '.') continue;
    final openParen = m.end - 1;
    final closeParen = matchBracket(src, openParen);
    if (closeParen < 0) continue;
    final body = bodyAfter(src, closeParen + 1);
    if (body == null) continue; // not a declaration — no `{` / `=>` follows
    yield Decl(src.substring(m.start, m.end - 1).trim(), m.start, body);
  }

  if (!includeGetters) return;
  final getterRe = RegExp(r'\bget\s+(\w+)\s*(?=\{|=>)');
  for (final m in getterRe.allMatches(src)) {
    if (prevNonSpace(src, m.start) == '.') continue;
    final body = bodyAfter(src, m.end);
    if (body == null) continue;
    yield Decl(m.group(1)!, m.start, body);
  }
}

/// Every method/getter declaration in [src], name -> body. Used only to decide
/// which same-file members mutate, for delegation resolution.
Map<String, String> findAllDeclarations(String src) {
  const kw = {
    'if', 'for', 'while', 'switch', 'catch', 'return', 'assert', 'super',
    'this', 'new', 'await', 'yield', 'else', 'do', 'in', 'is', 'as', 'set',
  };
  final out = <String, String>{};
  for (final m in RegExp(r'\b(\w+)\s*\(').allMatches(src)) {
    if (prevNonSpace(src, m.start) == '.') continue;
    final name = m.group(1)!;
    if (kw.contains(name)) continue;
    final closeParen = matchBracket(src, m.end - 1);
    if (closeParen < 0) continue;
    final body = bodyAfter(src, closeParen + 1);
    if (body == null) continue;
    out.putIfAbsent(name, () => body);
  }
  for (final m in RegExp(r'\bget\s+(\w+)\s*(?=\{|=>)').allMatches(src)) {
    if (prevNonSpace(src, m.start) == '.') continue;
    final body = bodyAfter(src, m.end);
    if (body == null) continue;
    out.putIfAbsent(m.group(1)!, () => body);
  }
  return out;
}

/// The body starting at [from]: a `{...}` block, or an `=>` expression to `;`.
/// Null when neither follows — meaning the match was not a declaration.
String? bodyAfter(String src, int from) {
  var i = from;
  // Skip modifiers between `)` and the body.
  while (i < src.length) {
    final ch = src[i];
    if (ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t') {
      i++;
      continue;
    }
    if (src.startsWith('async*', i)) {
      i += 6;
      continue;
    }
    if (src.startsWith('async', i)) {
      i += 5;
      continue;
    }
    if (src.startsWith('sync*', i)) {
      i += 5;
      continue;
    }
    break;
  }
  if (i >= src.length) return null;
  if (src[i] == '{') {
    final close = matchBracket(src, i);
    return close < 0 ? null : src.substring(i + 1, close);
  }
  if (src.startsWith('=>', i)) {
    final semi = src.indexOf(';', i);
    return semi < 0 ? null : src.substring(i + 2, semi);
  }
  return null;
}

/// Remove `catch (...) { ... }` blocks — telemetry on a failure path is not a
/// mutation of the query's result (the 2026-07-29 getCurrentRank correction).
String stripCatchBlocks(String body) {
  final out = StringBuffer();
  var i = 0;
  final re = RegExp(r'\bcatch\s*\(');
  while (i < body.length) {
    final m = re.firstMatch(body.substring(i));
    if (m == null) {
      out.write(body.substring(i));
      break;
    }
    out.write(body.substring(i, i + m.start));
    final parenOpen = i + m.end - 1;
    final parenClose = matchBracket(body, parenOpen);
    if (parenClose < 0) {
      out.write(body.substring(i + m.start));
      break;
    }
    var j = parenClose + 1;
    while (j < body.length &&
        (body[j] == ' ' ||
            body[j] == '\n' ||
            body[j] == '\r' ||
            body[j] == '\t')) {
      j++;
    }
    if (j < body.length && body[j] == '{') {
      final blockClose = matchBracket(body, j);
      if (blockClose < 0) break;
      i = blockClose + 1;
    } else {
      i = parenClose + 1;
    }
  }
  return out.toString();
}

/// Index of the bracket matching the one at [open], or -1.
int matchBracket(String src, int open) {
  const pairs = {'(': ')', '{': '}', '[': ']'};
  if (pairs[src[open]] == null) return -1;
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    final ch = src[i];
    if (ch == '(' || ch == '{' || ch == '[') depth++;
    if (ch == ')' || ch == '}' || ch == ']') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

String prevNonSpace(String src, int i) {
  var j = i - 1;
  while (j >= 0 &&
      (src[j] == ' ' || src[j] == '\n' || src[j] == '\r' || src[j] == '\t')) {
    j--;
  }
  return j >= 0 ? src[j] : '';
}
