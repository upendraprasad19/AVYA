// test/contracts/spawn_env_manifest_test.dart
//
// Completeness of the control-variable list is DERIVED, two-way, and cannot pass
// vacuously (class 2.56; docs/plans/spawn-tests-env-and-stderr.md D4).
//
// The scan (test/helpers/spawn_env_scan.dart) reads every environment variable the
// repo's own scripts, `.claude/*.js` helpers and tests read from the process
// environment. This file holds the HAND classification of each name found, and
// checks both directions:
//   found ⊆ classified   a new `Platform.environment['NEW_SWITCH']` / `${NEW:-}` fails
//                        here until a human decides whether a spawned test may
//                        inherit it
//   classified ⊆ found   a stale entry fails (EMAIL is the one hand-listed external
//                        reader: no repo script reads it)
// plus floors and per-arm anchors (a scanner that returns {} must not pass), and the
// STRIPPED set must equal what `scrubbedChildEnvironment` really removes.
//
// THE CLAIM IS BOUNDED. It covers what the repo's own code reads. Variables an external
// tool reads (git's HOME / ~/.gitconfig, XDG_*) are not derivable from the repo's
// sources and are not claimed; a scenario that needs them pinned removes or sets them.

@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/regression_catalog_lib.dart';
import '../helpers/spawn.dart';
import '../helpers/spawn_env_scan.dart';

// ── The hand classification (literals, independent of the exported constants) ──────

/// A spawned test must NOT inherit these: a repo script (or git, or GitHub Actions)
/// treats them as a control switch, an operator escape hatch, a secret or a build input.
const _stripped = <String>{
  // git / GitHub owned (matched by prefix)
  'GIT_SSH_COMMAND', 'GITHUB_ACTIONS', 'GITHUB_EVENT_PATH', 'GITHUB_REF', 'GITHUB_REPOSITORY_OWNER',
  // repo-owned families (matched by prefix)
  'CONTRACT_SWEEP_NESTED', 'CONTRACT_SWEEP_SKIP',
  'DISCIPLINE_HOOK_MEMORY_PATH', 'DISCIPLINE_HOOK_SYNC_SKIP',
  'MINT_MIG_GH_BIN', 'MINT_MIG_OWNER_REPO', 'MINT_MIG_REMOTE', 'MINT_MIG_TEST_HOOK_BEFORE_PUSH',
  'MINT_MIG_TRANSPORT',
  'MINT_OI_GH_BIN', 'MINT_OI_OWNER_REPO', 'MINT_OI_REMOTE', 'MINT_OI_TEST_HOOK_BEFORE_PUSH',
  'MINT_OI_TRANSPORT',
  'PRE_COMMIT_FULL', 'PRE_COMMIT_LEGACY', 'PRE_COMMIT_GATE_JOBS', 'PRE_PUSH_FULL',
  // exact names
  'ALLOW_MAIN_COMMIT', 'ALLOW_RAW_GIT', 'FOUNDER_APPROVED_NO_VERIFY', 'PUSH_BEFORE',
  'SUPABASE_ACCESS_TOKEN', 'SUPABASE_ACCESS_TOKEN_FITNESS', 'SUPABASE_SERVICE_ROLE_KEY',
  'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'RAZORPAY_KEY_ID', 'USDA_API_KEY',
  '_SKIP_RENDER_CHECK', 'ANDROID_DEVICE_ID',
};

/// Read by an EXTERNAL tool only (git's author-identity fallback; d9e4b1): stripped,
/// hand-listed, exempt from the "classified ⊆ found" direction.
const _externalReader = <String>{'EMAIL'};

/// The child needs these. HOME and USERPROFILE are also BEHAVIOUR inputs
/// (`batch_close_hook.dart:98`, `discipline_hook.dart:190` choose which memory files are
/// read); they are kept because git, dart and the toolchain need them, and a scenario
/// that must pin them uses `remove` / `extra`. PATH is kept for the same reason (the toolchain
/// needs it); the spawn tests READ it from their own environment to give a synthetic child one
/// (test/contracts/spawn_helper_test.dart), which is why the derived scan now sees the name.
const _kept = <String>{'HOME', 'USERPROFILE', 'LOCALAPPDATA', 'ANDROID_HOME', 'ANDROID_SDK_ROOT', 'JAVA_HOME', 'PATH'};

/// A LOCATOR, not a control switch (`scripts/_dart_bin.sh:85`): the canonical scrub KEEPS
/// it, the helper REMOVES it from every spawned child (the two-level rule).
const _locator = <String>{'DART_BIN_OVERRIDE'};

/// Shell variables the scan sees as reads but that are assigned in their own file or
/// function (a function body reading a global, an `eval` assignment, a loop variable):
/// not inputs.
const _localShell = <String>{
  'TIER', 'REMOTE_SHA', '_BPASS_CLAIM', '_BPASS_CONTENT', '_BPASS_FILE', '_PRE_TIER',
  '_REC_CONTENT', '_REC', 'holder_started', 'owner_pid', 'n', 'unfiled', '_v',
};

/// Variables the shell sets itself; the scan reports them separately and each must be
/// classified (a new `$USER` / `$TERM` switch must not be exempted silently).
const _shellBuiltin = <String>{'PWD'};

/// Arm 2: every `Platform.environment` token that is not indexed by a literal key. A new
/// alias fails until a human says whether the file FORWARDS the map to a child, READS keys
/// through it (those names are found by arm 1), or is the allow-listed WRAPPER.
const Map<String, ({int count, String kind})> _aliasAllowList = {
  'scripts/check_alerts.dart': (count: 1, kind: 'wrapper'),
  'scripts/check_apk_release_signed.dart': (count: 1, kind: 'forwards'),
  'scripts/check_commit_from_worktree.dart': (count: 1, kind: 'reads'),
  'scripts/check_regression_catalog.dart': (count: 1, kind: 'forwards'),
  'scripts/contract_sweep.dart': (count: 2, kind: 'forwards and reads'),
  'scripts/discipline_hook.dart': (count: 1, kind: 'forwards'),
  'scripts/git_safety_hook.dart': (count: 1, kind: 'reads'),
  'scripts/retire_worktree.dart': (count: 1, kind: 'forwards'),
  'scripts/supabase_token_path_lib.dart': (count: 1, kind: 'forwards'),
};

/// Arm 5: shell reads whose NAME is computed (`eval "...${`, `${!x}`) cannot be resolved by
/// a scan; each is allow-listed with the names it can produce, and every listed name must
/// be classified. Replaces v2's wrong claim that these were "covered because they appear
/// literally".
const Map<String, ({int count, Set<String> names})> _computedAllowList = {
  'scripts/pre-commit.sh': (count: 1, names: {'PRE_COMMIT_FULL', 'PRE_COMMIT_LEGACY'}),
  'scripts/vercel_build.sh': (count: 1, names: {'SUPABASE_URL', 'SUPABASE_ANON_KEY', 'RAZORPAY_KEY_ID'}),
};

Set<String> get _classified =>
    {..._stripped, ..._externalReader, ..._kept, ..._locator, ..._localShell};

/// Every file the scan reads: top-level `scripts/*.dart|*.sh`, `.claude/*.js`, `test/**/*.dart`.
Map<String, String> _realSources() {
  final out = <String, String>{};
  String rel(FileSystemEntity e) => e.path.replaceAll(r'\', '/');
  for (final e in Directory('scripts').listSync()) {
    if (e is File && (e.path.endsWith('.dart') || e.path.endsWith('.sh'))) out[rel(e)] = e.readAsStringSync();
  }
  for (final e in Directory('.claude').listSync()) {
    if (e is File && e.path.endsWith('.js')) out[rel(e)] = e.readAsStringSync();
  }
  for (final e in Directory('test').listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) out[rel(e)] = e.readAsStringSync();
  }
  return out;
}

/// D2 recursion guard. `CONTRACT_SWEEP_NESTED` exists so a test that runs the REAL
/// pre-push hook cannot recurse (`scripts/contract_sweep.dart:14-16`); stripping it from
/// a test child moves that guard from "inherited" to "declared". A test file is
/// recursion-capable when its comment-stripped source EXECUTES the hook (`sh
/// scripts/pre-push.sh`, `bash ...`, `exec sh ...`) or spawns the sweep runner itself
/// (it has a `Process.` spawn and names `scripts/contract_sweep.dart`); such a file must
/// carry `CONTRACT_SWEEP_SKIP` or `--flutter-bin`. Files that merely READ or COPY the
/// hook as text are not flagged.
bool recursionCapable(String strippedSource) {
  final spawns = RegExp(r'Process\.(run|runSync|start)\(').hasMatch(strippedSource) ||
      RegExp(r'\b(runSpawn|runSpawnAsync|startSpawn)\(').hasMatch(strippedSource);
  final executesHook = RegExp(r'\b(?:sh|bash)\s+scripts/pre-push\.sh').hasMatch(strippedSource);
  final spawnsSweep = spawns && strippedSource.contains('scripts/contract_sweep.dart');
  return executesHook || spawnsSweep;
}

/// A REAL declaration, not a mention: the kill switch set as an environment entry
/// (`env['CONTRACT_SWEEP_SKIP'] = ...` or a `'CONTRACT_SWEEP_SKIP': ...` map entry), or the
/// runner given `--flutter-bin` as an argument string. A `reason:` string that merely names
/// the variable (pre_push_analyze_always_e2e_test.dart:163 does) must NOT satisfy it, or
/// deleting the real declaration would leave this pin green.
bool recursionGuarded(String strippedSource) =>
    RegExp('[\'"]CONTRACT_SWEEP_SKIP[\'"]\\s*(\\]\\s*=|:)').hasMatch(strippedSource) ||
    RegExp('[\'"]--flutter-bin[\'"]').hasMatch(strippedSource);

void main() {
  late Map<String, String> sources;
  late EnvScan scan;

  setUpAll(() {
    sources = _realSources();
    scan = scanEnvironmentReads(sources);
  });

  group('the derived scan over the REAL tree', () {
    test('FLOORS: the scan cannot pass vacuously', () {
      expect(scan.dartScriptFiles, greaterThan(150), reason: 'scripts/*.dart scanned');
      expect(scan.shellScriptFiles, greaterThan(10), reason: 'scripts/*.sh scanned');
      expect(scan.names.length, greaterThanOrEqualTo(40), reason: 'distinct names found');
    });

    test('ANCHORS: every arm finds the name it is known to find', () {
      bool at(String name, String needle) => (scan.names[name] ?? <String>{}).any((s) => s.contains(needle));
      expect(at('ALLOW_RAW_GIT', 'scripts/git_safety_hook.dart'), isTrue, reason: 'arm 1, literal read');
      expect(at('GITHUB_REPOSITORY_OWNER', 'scripts/check_plan_review_record_exists.dart'), isTrue,
          reason: 'arm 1, read through a local alias receiver');
      expect(at('PRE_COMMIT_FULL', 'scripts/pre-commit.sh'), isTrue, reason: 'arm 4, default idiom');
      expect(at('ANDROID_DEVICE_ID', 'scripts/run-device-tests.sh'), isTrue,
          reason: 'arm 4, plain read next to an echo line that LOOKS like an assignment');
      expect(at('SUPABASE_SERVICE_ROLE_KEY', '(wrapper)'), isTrue, reason: 'arm 3, _readEnvVar wrapper');
      expect(at('SUPABASE_URL', 'scripts/vercel_build.sh'), isTrue, reason: 'arm 4');
      expect(at('SUPABASE_ACCESS_TOKEN', '.claude/'), isTrue, reason: 'arm 6, Node helper');
      expect(at('DART_BIN_OVERRIDE', '(test)'), isTrue, reason: 'arm 7, test-side read');
    });

    test('found ⊆ classified: every name the repo reads is classified by a human', () {
      final unclassified = scan.names.keys.toSet().difference(_classified);
      expect(unclassified, isEmpty,
          reason: 'A script now reads these from the process environment. Decide whether a spawned '
              'test may inherit each: add it to _stripped (and to childEnvStrippedNames / the prefix '
              'list in scripts/regression_catalog_lib.dart) if a script treats it as a control switch, '
              'secret or build input; to _kept / _locator / _localShell otherwise. Sites: '
              '${{for (final n in unclassified) n: scan.names[n]!.toList()..sort()}}');
    });

    test('classified ⊆ found: a stale entry fails (EMAIL is the one hand-listed external reader)', () {
      final stale = _classified.difference(_externalReader).difference(scan.names.keys.toSet());
      expect(stale, isEmpty, reason: 'no script reads these any more; remove them from the manifest');
    });

    test('shell builtins seen are exactly the classified set (a new \$USER / \$TERM switch is visible)', () {
      expect(scan.shellBuiltinsSeen, _shellBuiltin);
    });

    test('arm 2: Platform.environment alias sites match the allow-list, both ways', () {
      final byFile = <String, int>{};
      for (final site in scan.aliasSites) {
        final file = site.substring(0, site.lastIndexOf(':'));
        byFile[file] = (byFile[file] ?? 0) + 1;
      }
      expect(byFile, {for (final e in _aliasAllowList.entries) e.key: e.value.count},
          reason: 'a new alias must be classified (forwards the map to a child, or reads keys through '
              'it); a stale entry must go');
    });

    test('arm 5: computed shell reads match the allow-list, both ways, and every listed name is classified', () {
      final byFile = <String, int>{};
      for (final site in scan.computedShellReads) {
        final file = site.substring(0, site.indexOf(':'));
        byFile[file] = (byFile[file] ?? 0) + 1;
      }
      expect(byFile, {for (final e in _computedAllowList.entries) e.key: e.value.count});
      final listed = {for (final e in _computedAllowList.values) ...e.names};
      expect(listed.difference(_classified), isEmpty);
    });

    test('the classification sets are disjoint (a name has ONE decision)', () {
      final sets = [_stripped, _externalReader, _kept, _locator, _localShell, _shellBuiltin];
      final seen = <String>{};
      for (final s in sets) {
        expect(seen.intersection(s), isEmpty);
        seen.addAll(s);
      }
    });
  });

  group('the STRIPPED set is what the scrub really removes (d)', () {
    test('scrubbedChildEnvironment over a parent holding every classified name', () {
      final parent = {for (final n in {..._classified, ..._shellBuiltin}) n: 'x', 'PATH': '/p'};
      final left = scrubbedChildEnvironment(parent).keys.toSet();
      final removed = parent.keys.toSet().difference(left);
      expect(removed, {..._stripped, ..._externalReader},
          reason: 'the manifest says STRIPPED; the scrub must remove exactly that, no more, no less');
      expect(left.containsAll({..._kept, ..._locator, ..._localShell, ..._shellBuiltin, 'PATH'}), isTrue);
    });

    test('the two-level rule: the canonical scrub KEEPS DART_BIN_OVERRIDE, the helper REMOVES it', () {
      expect(scrubbedChildEnvironment({'DART_BIN_OVERRIDE': '/d'}).keys, ['DART_BIN_OVERRIDE']);
      expect(hermeticEnvironment(parent: {'DART_BIN_OVERRIDE': '/d'}), isEmpty);
    });

    test('the lib\'s exported lists equal the manifest\'s hand classification, both ways', () {
      // (d) proves the scrub removes every classified name; this proves it removes NOTHING the
      // manifest does not know about, and that the hand-listed external reader is the same set.
      expect(childEnvExternalReaders.toSet(), _externalReader);
      final exact = _stripped.where((n) => !childEnvStrippedPrefixes.any(n.toUpperCase().startsWith)).toSet();
      expect(childEnvStrippedNames.toSet(), exact,
          reason: 'childEnvStrippedNames must be exactly the stripped names no prefix covers');
      expect(childEnvStrippedPrefixes.toSet(), {
        'GIT_', 'GITHUB_', 'CONTRACT_SWEEP_', 'PRE_COMMIT_', 'PRE_PUSH_', 'DISCIPLINE_HOOK_', 'MINT_OI_', 'MINT_MIG_',
      });
    });

    test('EMAIL (an external reader: git\'s author-identity fallback, d9e4b1) is stripped', () {
      expect(scrubbedChildEnvironment({'EMAIL': 'a@b', 'PATH': '/p'}).keys, ['PATH']);
      expect(hermeticEnvironment(parent: {'email': 'a@b', 'PATH': '/p'}).keys, ['PATH']);
    });

    test('every classified-STRIPPED name is stripped by the HELPER too', () {
      final parent = {for (final n in {..._stripped, ..._externalReader}) n: 'x'};
      expect(hermeticEnvironment(parent: parent), isEmpty);
    });
  });

  group('D2 recursion pin: a test that runs the real pre-push hook declares its guard', () {
    test('every recursion-capable test file carries CONTRACT_SWEEP_SKIP or --flutter-bin', () {
      final capable = <String>[];
      final unguarded = <String>[];
      for (final e in sources.entries) {
        if (!e.key.startsWith('test/') || !e.key.endsWith('.dart')) continue;
        if (e.key == 'test/contracts/spawn_env_manifest_test.dart') continue; // this file names the patterns
        final stripped = blankDart(e.value, blankStrings: false);
        if (recursionCapable(stripped)) {
          capable.add(e.key);
          if (!recursionGuarded(stripped)) unguarded.add(e.key);
        }
      }
      expect(capable.toSet(), {
        'test/scripts/pre_push_analyze_always_e2e_test.dart',
        // OI-275 B1: runs a verbatim COPY of the hook with stdin fixtures; guarded by CONTRACT_SWEEP_SKIP=1.
        'test/scripts/pre_push_branch_push_skip_e2e_test.dart',
        'test/scripts/contract_sweep_e2e_test.dart',
      }, reason: 'the detector must find exactly the tests that execute the hook or spawn the sweep runner');
      expect(unguarded, isEmpty,
          reason: 'these tests run the real pre-push hook (or the sweep runner) without declaring '
              'CONTRACT_SWEEP_SKIP / --flutter-bin: now that the helper strips CONTRACT_SWEEP_NESTED '
              'they can recurse');
    });

    test('the detector, on synthetic sources', () {
      expect(recursionCapable("Process.runSync('sh', ['-c', 'exec sh scripts/pre-push.sh < /dev/null']);"), isTrue);
      expect(recursionCapable("runSpawn('bash', ['-c', 'bash scripts/pre-push.sh']);"), isTrue);
      expect(recursionCapable("Process.runSync('dart', ['run', 'scripts/contract_sweep.dart']);"), isTrue);
      // reads or copies the hook as text: not capable
      expect(recursionCapable("File('scripts/pre-push.sh').readAsStringSync();"), isFalse);
      expect(recursionCapable("File('scripts/pre-push.sh').copySync(dest);"), isFalse);
      // names the runner but never spawns anything
      expect(recursionCapable("expect(src, contains('scripts/contract_sweep.dart'));"), isFalse);
      expect(recursionGuarded("env['CONTRACT_SWEEP_SKIP'] = '1';"), isTrue);
      expect(recursionGuarded("['run', runner, '--flutter-bin', stub]"), isTrue);
      expect(recursionGuarded("exec sh scripts/pre-push.sh"), isFalse);
      expect(recursionGuarded("env['CONTRACT_SWEEP_SKIP'] = '1';"), isTrue);
      expect(recursionGuarded("{'CONTRACT_SWEEP_SKIP': '1'}"), isTrue);
      // a mention is not a declaration
      expect(recursionGuarded("reason: 'the sweep line must be reached (CONTRACT_SWEEP_SKIP=1 makes it exit)'"), isFalse);
      expect(recursionGuarded("// pass --flutter-bin to avoid recursion"), isFalse);
    });
  });

  group('each scan arm, on synthetic sources (one per hole review found)', () {
    EnvScan scanOne(String path, String src) => scanEnvironmentReads({path: src});
    Set<String> names(EnvScan s) => s.names.keys.toSet();

    test('arm 4: shell default idioms, := and a plain read are candidates', () {
      final s = scanOne('scripts/x.sh', r'''
echo "${A_IDIOM:-d}"
: "${B_ASSIGN_DEFAULT:=0}"
if [ -n "$C_PLAIN" ]; then echo hi; fi
''');
      expect(names(s), {'A_IDIOM', 'B_ASSIGN_DEFAULT', 'C_PLAIN'});
    });

    test('arm 4: a plain read beside an echo line that LOOKS like an assignment is still a read '
        '(the ANDROID_DEVICE_ID shape)', () {
      final s = scanOne('scripts/x.sh', r'''
echo "pick one first; ANDROID_DEVICE_ID=XYZ ./run.sh"
adb -s "$ANDROID_DEVICE_ID" devices
''');
      expect(names(s), {'ANDROID_DEVICE_ID'});
    });

    test('arm 4: negative controls: assigned-before-read, a loop variable and a comment are not inputs', () {
      final s = scanOne('scripts/x.sh', r'''
# uses $ONLY_IN_COMMENT here
LOCAL_ONE=1
echo "$LOCAL_ONE"
for item in a b; do echo "$item"; done
''');
      expect(names(s), isEmpty);
    });

    test('arm 4: a COMMENTED assignment is not an assignment, and a commented read is not a read', () {
      final s = scanOne('scripts/x.sh', r'''
# FOO_COMMENTED=1
# note; FOO_COMMENTED_SEMI=1
echo "$FOO_COMMENTED"
echo "$FOO_COMMENTED_SEMI"
# echo "$ONLY_IN_COMMENT"
''');
      expect(names(s), {'FOO_COMMENTED', 'FOO_COMMENTED_SEMI'},
          reason: 'a comment must not count as the assignment that hides the real read');
    });

    test('arm 4: a default-idiom read is a candidate even after a conditional assignment', () {
      final s = scanOne('scripts/x.sh', r'''
if [ -z "$1" ]; then SWITCH=1; fi
: "${SWITCH:=0}"
''');
      expect(names(s), {'SWITCH'}, reason: 'pre-merge-commit.sh:128 / :131 (_SKIP_RENDER_CHECK) shape');
    });

    test('arm 4: a shell builtin is reported separately, not as an input', () {
      final s = scanOne('scripts/x.sh', r'echo "$USER $PWD"');
      expect(names(s), isEmpty);
      expect(s.shellBuiltinsSeen, {'USER', 'PWD'});
    });

    test('arm 5: eval and \${!var} computed reads are reported, not resolved', () {
      final s = scanOne('scripts/x.sh', r'''
for _h in A B; do eval "_v=\${$_h:-}"; done
if [ -z "${!var:-}" ]; then echo missing; fi
''');
      expect(s.computedShellReads, hasLength(2));
    });

    test('arm 1: Dart literal reads through any receiver and quote style, and containsKey', () {
      final s = scanOne('scripts/x.dart', r'''
import 'dart:io';
void main() {
  final env = Platform.environment;
  final vars = Platform.environment;
  print(env['A_SINGLE']);
  print(vars["B_DOUBLE"]);
  print(_env['C_UNDERSCORE']);
  print(vars.containsKey("D_CONTAINS"));
}
''');
      expect(names(s), {'A_SINGLE', 'B_DOUBLE', 'C_UNDERSCORE', 'D_CONTAINS'});
    });

    test('arm 1: a map that is not in a Platform.environment file, a string and a comment stay quiet', () {
      expect(names(scanOne('scripts/x.dart', "void f(Map m) { m['NOT_ENV']; m.containsKey('ALSO_NOT'); }")), isEmpty);
      expect(
          names(scanOne('scripts/x.dart', r'''
import 'dart:io';
// Platform.environment['IN_COMMENT']
const s = "Platform.environment['IN_STRING']";
void f() => Platform.environment['REAL_ONE'];
''')),
          {'REAL_ONE'});
    });

    test('arm 1: containsKey in a comment or a string is not a read either', () {
      final s = scanOne('scripts/x.dart', r'''
import 'dart:io';
// env.containsKey('IN_COMMENT_CK')
const s = "env.containsKey('IN_STRING_CK')";
bool f() => Platform.environment.containsKey('REAL_CK');
''');
      expect(names(s), {'REAL_CK'});
    });

    test('arm 2: an alias of Platform.environment is reported; an indexed read is not', () {
      final s = scanOne('scripts/x.dart', r'''
import 'dart:io';
final vars = Platform.environment;
final one = Platform.environment['INDEXED'];
final spread = {...Platform.environment};
''');
      expect(s.aliasSites, hasLength(2));
      expect(names(s), {'INDEXED'});
    });

    test('arm 3: a wrapper call that opts in to the process environment is a name; one that does not is not', () {
      final s = scanOne('scripts/x.dart', r'''
import 'dart:io';
void f() {
  final m = Platform.environment;
  _readEnvVar('WRAPPED_NAME', allowProcessEnv: true);
  _readEnvVar('NOT_PROCESS_ENV');
}
''');
      expect(names(s), {'WRAPPED_NAME'});
    });

    test('arm 6: Node helpers read process.env.X and process.env["X"]', () {
      final s = scanOne('.claude/x.js', "const a = process.env.NODE_ONE;\nconst b = process.env['NODE_TWO'];\n// process.env.IN_COMMENT\n");
      expect(names(s), {'NODE_ONE', 'NODE_TWO'});
    });

    test('arm 7: a test-side Platform.environment read is a name', () {
      final s = scanOne('test/x_test.dart', "import 'dart:io';\nvoid main() { Platform.environment['TEST_SIDE']; }\n");
      expect(names(s), {'TEST_SIDE'});
    });

    test('the scanner reports nothing for nothing (a vacuous scan is detectable by the floors)', () {
      expect(scanEnvironmentReads(const {}).names, isEmpty);
    });
  });
}
