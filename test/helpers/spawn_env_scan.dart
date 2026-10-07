// test/helpers/spawn_env_scan.dart
//
// The DERIVED half of the spawn-environment manifest (test/contracts/
// spawn_env_manifest_test.dart): a pure scan over `{repo-relative path: source}` that
// reports every environment variable the repo's own tooling READS from the process
// environment. Pure so the manifest test can feed it synthetic sources (one mutant per
// arm) as well as the real tree.
//
// Why a scan and not a list: each earlier fix for an inherited control variable (4f2a9e,
// c3f8e1, d81f3c, d9e4b1) added names to one hand-copied list, and the next variable
// was missed. A hand-picked "env_readers" lookup was rejected twice in plan review for
// the same reason: a lookup is not a census. The scan is only as good as its arms, so
// each arm below exists because a review round found a real read the previous arms
// missed (`ANDROID_DEVICE_ID`, `scripts/run-device-tests.sh:28`, hidden by an `echo`
// line that looked like an assignment).
//
// Arms (the numbering is the plan's, D4):
//   1. Dart literal reads through ANY receiver with an UPPER_SNAKE key, both quote
//      styles, `containsKey` too, in any scripts/*.dart that mentions
//      `Platform.environment` (receivers `env`, `_env`, `vars`, `e` ...).
//   2. Dart ALIAS sites: every `Platform.environment` token not immediately indexed by
//      a literal key. The caller holds an allow-list; a new alias fails until a human
//      classifies it as forwarding the map or reading from it.
//   3. Dart WRAPPER calls: the first string literal of a `_readEnvVar(... allowProcessEnv:
//      true ...)` call is a name read from the process environment.
//   4. Shell reads: `$X`, `${X}`, `${X:-d}` ... A shell assignment is recognised only at
//      statement position with quoted text blanked first (an `echo "set FOO=1"` line is
//      not an assignment); a read written with a default idiom is ALWAYS a candidate (a
//      conditional earlier assignment still leaves an input); a plain read is a
//      candidate when it is not assigned at or before it.
//   5. Shell COMPUTED reads (`eval "...${`, `${!x}`) cannot be resolved to a name: they
//      are reported for an allow-list.
//   6. Node helpers: `process.env.X` / `process.env['X']` in `.claude/*.js`.
//   7. Test-side reads: literal `Platform.environment['X']` in `test/**/*.dart`.
//
// STATED LIMITS: a name read only by an EXTERNAL tool (git's `EMAIL`) is invisible to a
// scan of the repo's own sources and is hand-listed by the manifest test; the seven
// `scripts/*.py|*.js` and two `.claude/*.py` files are out of the input set (no test
// spawns them); the Dart lexer does not follow nested quotes inside `${...}` string
// interpolation.

/// What [scanEnvironmentReads] found.
class EnvScan {
  /// name -> reader sites (`path:line`, with a `(wrapper)` suffix for arm 3).
  final Map<String, Set<String>> names = <String, Set<String>>{};

  /// Arm 2: `path:line` of every `Platform.environment` token not indexed by a literal key.
  final List<String> aliasSites = <String>[];

  /// Arm 5: `path:line  text` of every shell read whose name cannot be resolved.
  final List<String> computedShellReads = <String>[];

  /// Shell reads that matched the builtin set (exempt from `names`, but reported so the
  /// manifest test can require each to be classified).
  final Set<String> shellBuiltinsSeen = <String>{};

  int dartScriptFiles = 0;
  int shellScriptFiles = 0;

  void add(String name, String site) => names.putIfAbsent(name, () => <String>{}).add(site);
}

/// Shell variables set by the shell itself or by the login environment. A read of one is
/// reported in [EnvScan.shellBuiltinsSeen] instead of [EnvScan.names]; the manifest test
/// requires every one seen to be classified, so a new `$USER` or `$TERM` switch cannot
/// pass silently.
const Set<String> shellBuiltinNames = <String>{
  'PWD', 'OLDPWD', 'IFS', 'PATH', 'HOME', 'USER', 'SHELL', 'LINENO', 'RANDOM', 'SECONDS',
  'BASH_SOURCE', 'FUNCNAME', 'OPTARG', 'OPTIND', 'REPLY', 'UID', 'PPID', 'HOSTNAME', 'TERM', 'PS1',
};

final RegExp _upper = RegExp(r'[A-Z][A-Z0-9_]*');

/// Blank the CONTENT of comments and string literals with spaces (newlines kept), so a
/// regex over the result sees only live code, and a position can be mapped back to the
/// original. Ported from the lexer of the census scripts; raw strings and triple quotes
/// are handled, interpolation is not followed. With `blankStrings: false` ONLY comments
/// are blanked and string text is kept (a comment marker inside a string, such as the
/// glob text `lib/shared/repositories/**`, is not a comment: the regex stripper of
/// read_screen_source.dart gets that wrong).
String blankDart(String src, {bool blankStrings = true}) {
  final out = src.split('');
  final n = src.length;
  var i = 0;
  void blankRange(int a, int b) {
    for (var k = a; k < b && k < n; k++) {
      if (out[k] != '\n') out[k] = ' ';
    }
  }

  bool isWord(String c) => RegExp(r'[A-Za-z0-9_]').hasMatch(c);

  while (i < n) {
    final c = src[i];
    if (src.startsWith('//', i)) {
      var j = src.indexOf('\n', i);
      if (j < 0) j = n;
      blankRange(i, j);
      i = j;
      continue;
    }
    if (src.startsWith('/*', i)) {
      var depth = 1;
      var j = i + 2;
      while (j < n && depth > 0) {
        if (src.startsWith('/*', j)) {
          depth++;
          j += 2;
        } else if (src.startsWith('*/', j)) {
          depth--;
          j += 2;
        } else {
          j++;
        }
      }
      blankRange(i, j);
      i = j;
      continue;
    }
    var raw = false;
    int qAt;
    if (c == 'r' && i + 1 < n && (src[i + 1] == "'" || src[i + 1] == '"') && (i == 0 || !isWord(src[i - 1]))) {
      raw = true;
      qAt = i + 1;
    } else if (c == "'" || c == '"') {
      qAt = i;
    } else {
      i++;
      continue;
    }
    final q = src[qAt];
    final triple = src.startsWith(q * 3, qAt);
    var j = qAt + (triple ? 3 : 1);
    while (j < n) {
      if (!raw && src[j] == r'\') {
        j += 2;
        continue;
      }
      if (triple) {
        if (src.startsWith(q * 3, j)) {
          j += 3;
          break;
        }
      } else {
        if (src[j] == q) {
          j += 1;
          break;
        }
        if (src[j] == '\n') break;
      }
      j++;
    }
    if (blankStrings) {
      final from = triple ? qAt + 3 : qAt + 1;
      final to = j - (triple ? 3 : 1);
      blankRange(from, to > qAt + 1 ? to : qAt + 1);
    }
    i = j;
  }
  return out.join();
}

int _lineOf(String text, int pos) => '\n'.allMatches(text.substring(0, pos)).length + 1;

/// Blank the content of quoted spans on one shell line so message text
/// (`echo "set FOO=1"`) can never look like an assignment.
String _unquoteShell(String line) {
  final out = StringBuffer();
  String? q;
  var i = 0;
  while (i < line.length) {
    final c = line[i];
    if (q != null) {
      if (c == r'\' && q == '"') {
        out.write('  ');
        i += 2;
        continue;
      }
      if (c == q) {
        q = null;
        out.write(c);
      } else {
        out.write(' ');
      }
    } else if (c == "'" || c == '"') {
      q = c;
      out.write(c);
    } else {
      out.write(c);
    }
    i++;
  }
  return out.toString();
}

final RegExp _shellAssign = RegExp(
    r'(?:^\s*|[;&|({)]\s*|\b(?:then|do|else|if|elif|while|until)\s+!?\s*)'
    r'(?:export\s+|local\s+|readonly\s+|declare\s+(?:-[a-zA-Z]+\s+)*)?([A-Za-z_]\w*)\+?=');
final RegExp _shellRead = RegExp(r'\$\{?([A-Za-z_]\w*)');
final RegExp _shellLoop =
    RegExp(r'\bfor\s+([A-Za-z_]\w*)\s+in\b|\bread\s+(?:-[a-zA-Z]+\s+)*([A-Za-z_][\w ]*)');

/// Scan [sources] (`repo-relative path -> source text`, forward slashes). The input set is
/// decided by path: top-level `scripts/*.dart` (arms 1-3), top-level `scripts/*.sh`
/// (arms 4-5), `.claude/*.js` (arm 6), `test/**/*.dart` (arm 7).
EnvScan scanEnvironmentReads(Map<String, String> sources) {
  final scan = EnvScan();
  for (final entry in sources.entries) {
    final path = entry.key;
    final orig = entry.value;
    final slashes = '/'.allMatches(path).length;
    if (path.startsWith('scripts/') && slashes == 1 && path.endsWith('.dart')) {
      scan.dartScriptFiles++;
      _scanDartScript(scan, path, orig);
    } else if (path.startsWith('scripts/') && slashes == 1 && path.endsWith('.sh')) {
      scan.shellScriptFiles++;
      _scanShell(scan, path, orig);
    } else if (path.startsWith('.claude/') && slashes == 1 && path.endsWith('.js')) {
      _scanNode(scan, path, orig);
    } else if (path.startsWith('test/') && path.endsWith('.dart')) {
      _scanTestSide(scan, path, orig);
    }
  }
  return scan;
}

void _scanDartScript(EnvScan scan, String path, String orig) {
  final b = blankDart(orig);
  if (!b.contains('Platform.environment')) return;
  bool live(int pos) => b[pos] == orig[pos];
  final index = RegExp('\\b\\w+\\s*\\[\\s*([\'"])(${_upper.pattern})\\1\\s*\\]');
  for (final m in index.allMatches(orig)) {
    if (live(m.start)) scan.add(m.group(2)!, '$path:${_lineOf(orig, m.start)}');
  }
  final contains = RegExp('\\.containsKey\\(\\s*([\'"])(${_upper.pattern})\\1\\s*\\)');
  for (final m in contains.allMatches(orig)) {
    if (live(m.start)) scan.add(m.group(2)!, '$path:${_lineOf(orig, m.start)}');
  }
  // Arm 2: every `Platform.environment` not immediately indexed by a literal key.
  for (final m in RegExp(r'Platform\.environment').allMatches(b)) {
    final tail = orig.substring(m.end, (m.end + 12) > orig.length ? orig.length : m.end + 12);
    if (!RegExp('^\\s*\\[\\s*[\'"]').hasMatch(tail)) {
      scan.aliasSites.add('$path:${_lineOf(orig, m.start)}');
    }
  }
  // Arm 3: wrapper calls that opt in to the process environment.
  for (final m in RegExp(r'_readEnvVar\(').allMatches(b)) {
    var i = m.end;
    var depth = 1;
    while (i < b.length && depth > 0) {
      if (b[i] == '(') depth++;
      if (b[i] == ')') depth--;
      i++;
    }
    final call = orig.substring(m.end, i - 1);
    if (call.contains('allowProcessEnv: true')) {
      final lit = RegExp('^\\s*([\'"])(${_upper.pattern})\\1').firstMatch(call);
      if (lit != null) scan.add(lit.group(2)!, '$path:${_lineOf(orig, m.start)}(wrapper)');
    }
  }
}

void _scanShell(EnvScan scan, String path, String source) {
  final lines = source.split('\n');
  final firstAssign = <String, int>{};
  for (var ln = 1; ln <= lines.length; ln++) {
    final line = lines[ln - 1];
    if (line.trim().startsWith('#')) continue;
    final u = _unquoteShell(line);
    for (final m in _shellAssign.allMatches(u)) {
      firstAssign.putIfAbsent(m.group(1)!, () => ln);
    }
    for (final m in _shellLoop.allMatches(u)) {
      for (final g in [m.group(1), m.group(2)]) {
        if (g != null) {
          for (final nm in g.split(' ').where((e) => e.isNotEmpty)) {
            firstAssign.putIfAbsent(nm, () => ln);
          }
        }
      }
    }
  }
  for (var i = 1; i <= lines.length; i++) {
    final line = lines[i - 1];
    if (line.trim().startsWith('#')) continue;
    if (RegExp(r'eval\s+".*\$\{').hasMatch(line) || RegExp(r'\$\{![A-Za-z_]').hasMatch(line)) {
      final t = line.trim();
      scan.computedShellReads.add('$path:$i  ${t.length > 70 ? t.substring(0, 70) : t}');
    }
    for (final m in _shellRead.allMatches(line)) {
      final n = m.group(1)!;
      final defaultIdiom =
          RegExp('\\\$\\{${RegExp.escape(n)}(?::-|-|:=|=|:\\?|:\\+)').hasMatch(line);
      // A DEFAULT-IDIOM read is always a candidate: a conditional earlier assignment
      // (pre-merge-commit.sh:128) still leaves an input.
      if (firstAssign.containsKey(n) && !defaultIdiom && firstAssign[n]! <= i) continue;
      if (shellBuiltinNames.contains(n)) {
        scan.shellBuiltinsSeen.add(n);
        continue;
      }
      scan.add(n, '$path:$i');
    }
  }
}

void _scanNode(EnvScan scan, String path, String source) {
  final lines = source.split('\n');
  final dot = RegExp(r'process\.env\.([A-Z][A-Z0-9_]*)');
  final idx = RegExp('process\\.env\\[\\s*([\'"])(${_upper.pattern})\\1\\s*\\]');
  for (var i = 1; i <= lines.length; i++) {
    final line = lines[i - 1];
    if (line.trim().startsWith('//') || line.trim().startsWith('*')) continue;
    for (final m in dot.allMatches(line)) {
      scan.add(m.group(1)!, '$path:$i');
    }
    for (final m in idx.allMatches(line)) {
      scan.add(m.group(2)!, '$path:$i');
    }
  }
}

void _scanTestSide(EnvScan scan, String path, String orig) {
  final b = blankDart(orig);
  if (!b.contains('Platform.environment')) return;
  bool live(int pos) => b[pos] == orig[pos];
  final index = RegExp('Platform\\.environment\\s*\\[\\s*([\'"])(${_upper.pattern})\\1\\s*\\]');
  for (final m in index.allMatches(orig)) {
    if (live(m.start)) scan.add(m.group(2)!, '$path:${_lineOf(orig, m.start)}(test)');
  }
}
