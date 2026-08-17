// scripts/oi_numbering_lib.dart
//
// Pure logic for scripts/check_oi_numbering_unique.dart. No I/O, no git — so
// the predicate can be tested without building repos.
//
// THE PROBLEM (OI-112, diagnose b7e3d1, and six live instances).
// `build_oi_index.dart:114-115` states it plainly: "OI numbers are minted by
// eyeballing the board's tail. There is no allocator, and until this check
// NOTHING detected a clash." The ceiling is split across open_issues.md and
// closed_issues.md, and a session sees only its own branch — so two branches
// routinely mint the same number for different issues. On 2026-08-13 a branch
// minted OI-106/107/108 against a base whose ceiling was OI-105 while `main`
// advanced to OI-124; the collision was found BY HAND three days later
// (0e4d97cd -> 0cb4120a) and the pushed commit message still cites the old
// numbers.
//
// WHY A THREE-POINT PREDICATE, not "HEAD title != main title".
// A two-point comparison cannot tell a COLLISION from an ordinary title EDIT:
// rewording OI-50 on a branch makes HEAD's OI-50 differ from main's OI-50 and
// would fire a false positive on completely correct work. False positives on a
// blocking gate are how gates get bypassed, so the predicate uses the
// merge-base as well:
//
//   collision  <=>  the branch MINTED the number (absent at merge-base)
//              AND  mainline ALSO has that number
//              AND  the two titles differ
//
// Each leg is load-bearing. Drop leg 1 and every title edit is a collision.
// Drop leg 2 and every newly minted number is a collision. Drop leg 3 and a
// branch that legitimately already contains main's entry (merged, rebased or
// cherry-picked) is a collision.

/// Matches an OI section heading. Kept byte-identical to
/// `scripts/build_oi_index.dart:34` so the two parsers can never disagree about
/// what an entry IS -- a divergence there would make this gate blind to exactly
/// the corruption the index generator reports, and vice versa.
final RegExp oiSectionRe = RegExp(r'^## (OI-\d+)\s*—\s*(.*)$');

/// One OI number carrying two different titles across two boards.
class OiCollision {
  const OiCollision({
    required this.number,
    required this.headTitle,
    required this.mainlineTitle,
  });

  final int number;
  final String headTitle;
  final String mainlineTitle;

  String get id => 'OI-$number';

  @override
  String toString() => '$id\n'
      '    this branch : $headTitle\n'
      '    origin/main : $mainlineTitle';
}

/// One OI number appearing on BOTH the open and the closed board.
class OiCrossFileDuplicate {
  const OiCrossFileDuplicate({
    required this.number,
    required this.openTitle,
    required this.closedTitle,
  });

  final int number;
  final String openTitle;
  final String closedTitle;

  String get id => 'OI-$number';
}

/// Matches the ASCII-only prefix of a heading: `## OI-<digits>`, with no
/// separator and no title.
///
/// This exists to tell "no entries" apart from "could not decode the file",
/// which otherwise look identical -- both yield an empty map, and reporting the
/// second as the first is how a gate says PASS about a board it never read.
/// Every character here is ASCII, so this count survives ANY mis-decoding; the
/// em-dash in [oiSectionRe] does not. A file where this count is > 0 while
/// [parseBoard] returns empty is therefore definitionally broken input, not an
/// empty board. See `_parseStrict` in check_oi_numbering_unique.dart.
final RegExp oiHeadingPrefixRe = RegExp(r'^## OI-\d+');

/// Number of `## OI-N` headings by their ASCII prefix alone, ignoring the
/// separator and title entirely.
int countHeadingPrefixes(String markdown) => markdown
    .split('\n')
    .where((l) => oiHeadingPrefixRe.hasMatch(l.trimRight()))
    .length;

/// Parses `## OI-N — title` headings out of one board file's [markdown].
///
/// Later duplicates within a single file overwrite earlier ones rather than
/// throwing: `build_oi_index.dart:120-136` already owns the within-file
/// duplicate check and reports it far better. Silently tolerating it here keeps
/// the two gates from double-reporting one defect with two different messages.
Map<int, String> parseBoard(String markdown) {
  final out = <int, String>{};
  for (final line in markdown.split('\n')) {
    final m = oiSectionRe.firstMatch(line.trimRight());
    if (m == null) continue;
    final n = int.tryParse(m.group(1)!.substring(3));
    if (n == null) continue;
    out[n] = m.group(2)!.trim();
  }
  return out;
}

/// Merges the open and closed boards into one number-space.
///
/// They ARE one number-space -- `closed_issues.md:3-6` says an OI number is a
/// permanent identifier and nothing there is ever renumbered -- but they live
/// in two files, which is precisely why "eyeball the tail" under-counts.
/// On a key present in both, the OPEN title wins; [crossFileDuplicates] is what
/// reports that condition, so this must not throw.
Map<int, String> mergeBoards(Map<int, String> open, Map<int, String> closed) =>
    <int, String>{...closed, ...open};

/// Numbers present on BOTH boards at once. Always a corruption: an issue is
/// open or closed, never both, and nothing else in the repo checks this.
List<OiCrossFileDuplicate> crossFileDuplicates(
  Map<int, String> open,
  Map<int, String> closed,
) {
  final out = <OiCrossFileDuplicate>[];
  for (final n in open.keys.toList()..sort()) {
    if (closed.containsKey(n)) {
      out.add(OiCrossFileDuplicate(
        number: n,
        openTitle: open[n]!,
        closedTitle: closed[n]!,
      ));
    }
  }
  return out;
}

/// Whitespace- and case-insensitive title comparison.
///
/// A pure reformat or case fix is not a different issue, and calling it one
/// would be a false positive on a blocking gate. Anything beyond that IS
/// treated as a different issue -- the gate's job is to be suspicious.
String normalizeTitle(String s) =>
    s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

/// The three-point predicate. See the header for why each leg exists.
///
/// [base] is the merge-base board union, [head] this branch's, [mainline]
/// origin/main's. Returns collisions sorted by number for stable output.
List<OiCollision> findCollisions({
  required Map<int, String> base,
  required Map<int, String> head,
  required Map<int, String> mainline,
}) {
  final out = <OiCollision>[];
  for (final n in head.keys.toList()..sort()) {
    // Leg 1 -- did THIS branch mint the number? If the merge-base already had
    // it, the branch is editing an existing entry, not minting a new one.
    if (base.containsKey(n)) continue;
    // Leg 2 -- did mainline independently mint it too?
    final mainTitle = mainline[n];
    if (mainTitle == null) continue;
    // Leg 3 -- are they actually different issues? Same title means the branch
    // already carries mainline's entry (merged / rebased / cherry-picked).
    final headTitle = head[n]!;
    if (normalizeTitle(headTitle) == normalizeTitle(mainTitle)) continue;
    out.add(OiCollision(
      number: n,
      headTitle: headTitle,
      mainlineTitle: mainTitle,
    ));
  }
  return out;
}

/// Highest number anywhere across the supplied boards, or 0 when empty.
/// Reported alongside a collision so the fix ("renumber to N+1") needs no
/// second command -- the 0cb4120a renumber had to work this out by hand across
/// two files, and its commit message records doing exactly that.
int nextFreeNumber(Iterable<Map<int, String>> boards) {
  var max = 0;
  for (final b in boards) {
    for (final n in b.keys) {
      if (n > max) max = n;
    }
  }
  return max + 1;
}
