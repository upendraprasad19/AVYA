// scripts/local_indexes_lib.dart
//
// Landing A2 of the merge-conflict-treadmill plan (docs/plans/merge-conflict-treadmill.md,
// section 6): the two GENERATED indexes, docs/audit/OPEN_INDEX.md and docs/diagnoses/INDEX.md,
// are LOCAL BUILD PRODUCTS. They are gitignored and untracked, so two branches that each add an
// issue or a diagnose doc can no longer conflict in a file neither of them wrote by hand
// (measured 2026-10-22: OPEN_INDEX.md conflicted in 20 of 52 replayed main-sync merges and
// diagnoses/INDEX.md in 13).
//
// This file is the single home for what both builders, the orchestrator
// (scripts/build_local_indexes.dart) and the SessionStart nudge (scripts/discipline_hook.dart)
// must agree on, so the three can never disagree about what "stale" means:
//   - the input list of each index and the predicate that selects diagnose docs;
//   - the stamp, a sha256 over the "name size mtime" text of every input, written as line 1 of
//     each output (`<!-- local-build: <digest> -->`);
//   - `isStale` / `localIndexReports`, which compare that stamp with the inputs as they are now;
//   - the atomic write (temp file, rename) and its exit code 3.
//
// WHY A STAT STAMP AND NOT A CONTENT HASH. The nudge runs at SessionStart and on bug-shaped
// prompts, spawns nothing and must cost a few milliseconds: it stats each input once and reads
// only the first 256 bytes of each output. A stat digest is therefore a cheap STALENESS
// heuristic, not a proof of content: a `touch`, a checkout that rewrites an unchanged file, or
// a rebase makes an index look stale and the answer is one rebuild. The opposite error (a
// changed input that leaves the digest equal) needs the same size AND the same mtime and is not
// reachable by an edit through the normal tools.
//
// THE STATS ARE CAPTURED BEFORE THE INPUTS ARE READ (review R5D-8). A builder takes the digest
// first and reads second; if an input changes in between, the stamp describes the OLDER state
// and the next staleness check reports stale. Taking the digest after the read would stamp a
// newer mtime on older content, the one direction that hides staleness.
//
// EXIT CODES a builder returns: 0 written, 1 validation failed (nothing written), 3 validation
// passed but the output could not be written (the old output stays). The git hooks print a
// warning and CONTINUE on 3, because the output is ignored and regenerable and the nudge
// already reports a stale index; they BLOCK on 1.
//
// The module is deliberately import-light (dart:convert, dart:io and the sha256 helper only):
// every builder fixture in test/ copies the transitive closure of this file.

import 'dart:convert';
import 'dart:io';

import 'migration_ledger_hash_lib.dart' show sha256Hex;

/// Root-relative paths, `/`-separated on every platform.
const String kOiBoardPath = 'docs/audit/open_issues.md';
const String kOiIndexPath = 'docs/audit/OPEN_INDEX.md';
const String kBugDocsDir = 'docs/diagnoses';
const String kBugIndexPath = 'docs/diagnoses/INDEX.md';

/// Exit code of a builder whose validation passed but whose write failed.
const int kWriteFailedExit = 3;

/// How many bytes of an output the staleness check reads. The stamp is line 1 and is 87 bytes
/// with its newline (86 characters: the 64-digit digest plus the 22 of the comment markers).
const int kStampHeadBytes = 256;

const String _stampPrefix = '<!-- local-build: ';
const String _stampSuffix = ' -->';
final RegExp _stampRe = RegExp(r'^<!-- local-build: ([0-9a-f]{64}) -->\s*$');

/// One generated index: a stable id and where its output lives.
class LocalIndexSpec {
  const LocalIndexSpec(this.id, this.outputPath);

  /// `oi` or `bug`; used in messages and temp-file names.
  final String id;
  final String outputPath;
}

const LocalIndexSpec kOiIndexSpec = LocalIndexSpec('oi', kOiIndexPath);
const LocalIndexSpec kBugIndexSpec = LocalIndexSpec('bug', kBugIndexPath);
const List<LocalIndexSpec> kLocalIndexSpecs = [kOiIndexSpec, kBugIndexSpec];

/// True for a file NAME the diagnose-index builder reads. ONE predicate for the builder, the
/// strict validation and the stamp inputs, so an editor backup (`x.md~`), the generated
/// `INDEX.md` itself and a stray `README.md` / `TEMPLATE.md` never count as a diagnose doc and
/// never make the stamp stale.
bool isDiagnoseDocName(String name) =>
    name.endsWith('.md') &&
    name != 'INDEX.md' &&
    name != 'README.md' &&
    name != 'TEMPLATE.md';

/// The diagnose doc file names under `<root>/docs/diagnoses`, sorted. A directory, a dangling
/// link and an editor lock link named `*.md` are not documents and are skipped. Part of the
/// staleness path (the nudge runs it on every SessionStart): it lists the directory and reads no
/// document, which the STRUCTURE test in local_indexes_e2e_test.dart pins.
List<String> diagnoseDocNames(String root) {
  final dir = Directory('$root/$kBugDocsDir');
  if (!dir.existsSync()) return const <String>[];
  final names = <String>[];
  for (final e in dir.listSync()) {
    if (e is! File) continue;
    final name = e.path.split(RegExp(r'[\\/]')).last;
    if (isDiagnoseDocName(name)) names.add(name);
  }
  names.sort();
  return names;
}

/// The root-relative paths whose stat the stamp of [spec] covers. Sorted by the digest, not
/// here.
List<String> indexInputPaths(String root, LocalIndexSpec spec) {
  switch (spec.id) {
    case 'oi':
      return const [
        kOiBoardPath,
        'scripts/build_oi_index.dart',
        'scripts/local_indexes_lib.dart',
      ];
    case 'bug':
      return [
        for (final n in diagnoseDocNames(root)) '$kBugDocsDir/$n',
        'scripts/build_bug_index.dart',
        'scripts/bug_index_lib.dart',
        'scripts/local_indexes_lib.dart',
      ];
  }
  throw ArgumentError.value(spec.id, 'spec', 'unknown local index');
}

/// A stat reader; [FileStat.statSync] in production, a counting fake in the structural test.
typedef StatFn = FileStat Function(String path);

/// The digest of the stat of every input: sha256 of the sorted `"name size mtimeMs"` lines
/// (`"name missing"` for an input that does not exist). Computed from STAT ONLY, never from
/// contents, and never with `String.hashCode`, which differs between processes.
String statDigest(String root, List<String> inputs,
    {StatFn stat = FileStat.statSync}) {
  final lines = <String>[];
  for (final name in inputs) {
    final st = stat('$root/$name');
    if (st.type == FileSystemEntityType.notFound) {
      lines.add('$name missing');
    } else {
      lines.add('$name ${st.size} ${st.modified.millisecondsSinceEpoch}');
    }
  }
  lines.sort();
  return sha256Hex(utf8.encode(lines.join('\n')));
}

/// Line 1 of an output.
String stampLine(String digest) => '$_stampPrefix$digest$_stampSuffix';

/// The digest in line 1 of [head] (the first bytes of an output), or null when line 1 is not a
/// stamp.
String? parseStamp(String head) {
  final nl = head.indexOf('\n');
  final first = nl < 0 ? head : head.substring(0, nl);
  return _stampRe.firstMatch(first.trimRight())?.group(1);
}

/// Reads at most [maxBytes] from the start of [path]; null when the path is not a readable file.
typedef HeadReader = List<int>? Function(String path, int maxBytes);

List<int>? readHeadBytes(String path, int maxBytes) {
  try {
    final f = File(path).openSync();
    try {
      return f.readSync(maxBytes);
    } finally {
      f.closeSync();
    }
  } catch (_) {
    return null;
  }
}

enum IndexState { fresh, stale, missing }

class IndexReport {
  const IndexReport(this.spec, this.state);
  final LocalIndexSpec spec;
  final IndexState state;
}

/// `fresh` when the stamp in the output equals the digest of the inputs as they are now;
/// `missing` when the output cannot be read as a file; `stale` otherwise (no stamp, or a stamp
/// of an older input state).
IndexState indexState(String root, LocalIndexSpec spec,
    {StatFn stat = FileStat.statSync, HeadReader readHead = readHeadBytes}) {
  final head = readHead('$root/${spec.outputPath}', kStampHeadBytes);
  if (head == null) return IndexState.missing;
  final stamp = parseStamp(utf8.decode(head, allowMalformed: true));
  if (stamp == null) return IndexState.stale;
  final now = statDigest(root, indexInputPaths(root, spec), stat: stat);
  return stamp == now ? IndexState.fresh : IndexState.stale;
}

/// One report per index, in [kLocalIndexSpecs] order.
List<IndexReport> localIndexReports(String root,
    {StatFn stat = FileStat.statSync, HeadReader readHead = readHeadBytes}) {
  return [
    for (final s in kLocalIndexSpecs)
      IndexReport(s, indexState(root, s, stat: stat, readHead: readHead)),
  ];
}

/// True when ANY index is stale or missing. The ONE predicate the orchestrator's self-check and
/// the SessionStart nudge both call.
bool isStale(String root,
    {StatFn stat = FileStat.statSync, HeadReader readHead = readHeadBytes}) {
  return localIndexReports(root, stat: stat, readHead: readHead)
      .any((r) => r.state != IndexState.fresh);
}

/// The output text for [body] stamped with [digest].
String stampedOutput(String digest, String body) => '${stampLine(digest)}\n$body';

/// Writes [content] to `<root>/<outputRel>` ATOMICALLY: a temp file under
/// `<root>/.dart_tool/local_indexes/` is written in full, then renamed over the output. A reader
/// (the nudge, an agent's `Read`, a concurrent hook) therefore sees the old file or the new one,
/// never a half-written one, and the output's inode changes on every rebuild.
///
/// Returns 0 when written and [kWriteFailedExit] when not; the old output is left in place on a
/// failure. A rename that fails is retried ONCE after [retryDelay] (Windows can refuse while
/// another process holds the file). Temp files older than [staleTmpAge] are swept first.
/// [warn] receives one line per failure (stderr by default).
int writeLocalIndex(String root, String outputRel, String content,
    {Duration retryDelay = const Duration(milliseconds: 200),
    Duration staleTmpAge = const Duration(hours: 1),
    void Function(String line)? warn}) {
  void say(String line) {
    final sink = warn;
    if (sink != null) {
      sink(line);
    } else {
      stderr.writeln(line);
    }
  }
  final dest = '$root/$outputRel';
  final tmpDir = Directory('$root/.dart_tool/local_indexes');
  final base = outputRel.split('/').last;
  final tmp = File('${tmpDir.path}/$base.$pid.tmp');
  try {
    tmpDir.createSync(recursive: true);
    _sweepStaleTmp(tmpDir, staleTmpAge);
    tmp.writeAsStringSync(content);
  } catch (e) {
    say('[local-indexes] could not write the temp file for $outputRel: $e');
    _deleteQuietly(tmp);
    return kWriteFailedExit;
  }
  try {
    // A directory at the output path blocks the rename. An EMPTY one is replaced; one with
    // content is reported, never deleted.
    if (FileSystemEntity.typeSync(dest, followLinks: false) ==
        FileSystemEntityType.directory) {
      final d = Directory(dest);
      if (d.listSync().isEmpty) {
        d.deleteSync();
      } else {
        say('[local-indexes] $outputRel is a non-empty directory; refusing to delete it. '
            'Move it away and rebuild.');
        _deleteQuietly(tmp);
        return kWriteFailedExit;
      }
    }
    try {
      tmp.renameSync(dest);
    } on FileSystemException {
      sleep(retryDelay);
      tmp.renameSync(dest);
    }
  } catch (e) {
    say('[local-indexes] could not replace $outputRel (the old output stays): $e');
    _deleteQuietly(tmp);
    return kWriteFailedExit;
  }
  return 0;
}

void _deleteQuietly(File f) {
  try {
    if (f.existsSync()) f.deleteSync(); // file-only: a temp FILE this process created
  } catch (_) {}
}

void _sweepStaleTmp(Directory dir, Duration maxAge) {
  try {
    final cutoff = DateTime.now().subtract(maxAge);
    for (final e in dir.listSync()) {
      if (e is File &&
          e.path.endsWith('.tmp') &&
          e.statSync().modified.isBefore(cutoff)) {
        e.deleteSync();
      }
    }
  } catch (_) {
    // Best effort: a failed sweep never blocks a build.
  }
}
