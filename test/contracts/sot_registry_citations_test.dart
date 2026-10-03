// Contract test for the diagnose-doc SoT-citation gate
// (scripts/check_sot_registry_citations.dart via scripts/sot_citation_lib.dart).
//
// Exercises every branch of the pure parse/classify logic deterministically —
// no git or filesystem fixture needed for the unit cases — plus ONE assertion
// bound to the real docs/sot_registry.yaml so a parser mutation cannot pass.
//
// Guards CLAUDE.md §4.4 rule 21 + §4.5 (SoT registry update per fix). Born from
// post38-auth-fixes, where three diagnose-docs shipped `sot_registry_entry:`
// values naming concepts that do not exist, while passing
// validate_diagnose_doc.dart — which never checked resolution at all.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/sot_citation_lib.dart';

void main() {
  group('parseConcepts', () {
    test('parses the LIST shape used by docs/sot_registry.yaml', () {
      const yaml = '''
concepts:

  - concept: workout_receipt_rendering
    domain: workout
    behavioral_test_path: test/contracts/x_test.dart

  - concept: auth_hive_owner_agreement
    domain: auth
''';
      expect(parseConcepts(yaml), {'workout_receipt_rendering', 'auth_hive_owner_agreement'});
    });

    test('returns EMPTY for the mapping shape — the gate must refuse on empty', () {
      // The registry is a list of `- concept: x`, NOT a mapping of `x:`.
      // Reading it as a mapping yields zero concepts, which would make every
      // citation in the repo look dangling. The gate treats empty as a parse
      // failure for exactly this reason; this test pins the trap.
      const mappingShaped = '''
concepts:
  workout_receipt_rendering:
    domain: workout
''';
      expect(parseConcepts(mappingShaped), isEmpty);
    });

    test('the REAL registry parses to a non-empty set containing a known concept', () {
      // Ground-truth anchor, independent of anything this test computes.
      // `auth_hive_owner_agreement` is a long-lived concept cited by e5c2d1.
      // If parseConcepts' regex is mutated (e.g. back to the mapping shape),
      // this returns empty and the assertion fails — the discriminator.
      final f = File('docs/sot_registry.yaml');
      expect(f.existsSync(), isTrue, reason: 'registry must exist at repo root');
      final concepts = parseConcepts(f.readAsStringSync());
      expect(concepts, isNotEmpty);
      expect(concepts, contains('auth_hive_owner_agreement'));
    });
  });

  group('citationOf', () {
    test('reads a plain single-line value', () {
      expect(citationOf('bug_id: x\nsot_registry_entry: password_recovery_session\n'),
          'password_recovery_session');
    });

    test('follows a block scalar to its first continuation line', () {
      expect(
        citationOf('sot_registry_entry: >\n  restore_completeness\n  more prose\n'),
        'restore_completeness',
      );
    });

    test('returns null when the field is absent', () {
      expect(citationOf('bug_id: x\nstatus: fixed\n'), isNull);
    });
  });

  group('splitCitation — the real-world shapes found in tracked docs', () {
    test('bare identifier', () {
      expect(splitCitation('password_recovery_session'), ['password_recovery_session']);
    });

    test('comma-separated multi-entry', () {
      expect(splitCitation('workout_receipt_rendering, workout_log_edit_surface'),
          ['workout_receipt_rendering', 'workout_log_edit_surface']);
    });

    test('strips a provenance parenthetical', () {
      // A first version of the gate reported 9 false failures against docs of
      // exactly this shape — the concept was valid, the parenthetical was not
      // stripped.
      expect(splitCitation('phase_progress_current_phase (docs/sot_registry.yaml)'),
          ['phase_progress_current_phase']);
      expect(splitCitation('onboarding_completed_at (docs/sot_registry.yaml:3847) — no new'),
          ['onboarding_completed_at']);
    });

    test('cuts prose at the em-dash, keeping the leading sentinel', () {
      expect(splitCitation('n/a — no Hive/cloud writer contract changed; this is a'), ['n/a']);
      expect(splitCitation('not_applicable — this batch adds process tooling'),
          ['not_applicable']);
    });

    test('drops a trailing # comment', () {
      expect(splitCitation('restore_completeness # see also f7e3a1'), ['restore_completeness']);
    });
  });

  group('classifyCitation', () {
    const concepts = {'auth_hive_owner_agreement', 'log_client_error_payload'};

    test('resolved when the concept exists', () {
      expect(classifyCitation('auth_hive_owner_agreement', concepts), CitationVerdict.resolved);
    });

    test('dangling when identifier-shaped but absent — the defect this gate catches', () {
      for (final missing in const [
        'oauth_signin_completion',
        'notifications_inbox_id_contract',
        'password_recovery_session',
      ]) {
        expect(classifyCitation(missing, concepts), CitationVerdict.dangling,
            reason: '$missing is not in the concept set');
      }
    });

    test('sentinel values are accepted, case-insensitively', () {
      for (final s in const ['n/a', 'N/A', 'not_applicable', 'none', 'null', 'TBD']) {
        expect(classifyCitation(s, concepts), CitationVerdict.sentinel, reason: s);
      }
    });

    test('non-identifier fragments are prose, not silently accepted as resolved', () {
      // 'no'/'No' are negation openers -> sentinel (a declaration), covered
      // separately. These are non-negation, non-identifier fragments.
      for (final p in const ['writer/reader', 'x', 'some thing']) {
        expect(classifyCitation(p, concepts), CitationVerdict.prose, reason: p);
      }
    });
  });

  group('isPostCutoff', () {
    test('boundary is inclusive', () {
      expect(isPostCutoff('2026-08-01-foo-abc123.md'), isTrue);
      expect(isPostCutoff('2026-07-31-foo-abc123.md'), isFalse);
    });

    test('the batch docs this gate was built for are post-cutoff', () {
      expect(isPostCutoff('2026-08-06-notifications-inbox-nonuuid-id-a4f1c8.md'), isTrue);
      expect(isPostCutoff('2026-08-06-google-signin-never-navigates-d3a7c9.md'), isTrue);
      expect(isPostCutoff('2026-08-06-reset-link-device-bound-pkce-c9e2b7.md'), isTrue);
    });

    test('an undated filename is grandfathered, never failed', () {
      // The gate must not hard-fail on a naming convention it cannot read.
      expect(isPostCutoff('INDEX.md'), isFalse);
      expect(isPostCutoff('notes.md'), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // SUBPROCESS tests — these execute the GATE ITSELF (`main()`), not just the
  // pure lib.
  //
  // Added after B-pass 2026-08-08 Finding 3: every test above imports only
  // sot_citation_lib.dart, so the cutoff branching, --strict handling and
  // exit(0)/exit(1) wiring were entirely uncovered. Replacing the gate's
  // `failures` list with a literal `<String>[]` — a total neutering — left the
  // whole suite green. That is presence-only confidence of exactly the shape
  // this gate exists to stop, in the gate's own test.
  //
  // Each case builds a THROWAWAY git repo so the gate's `git ls-files` sees a
  // controlled corpus.
  //
  // ⚠ The ENTIRE GIT_* namespace is scrubbed AND `includeParentEnvironment` is
  // false — see runGateOn. Inside the pre-commit hook this test inherits git's
  // exported vars, which override BOTH `workingDirectory:` AND `-C`, so the
  // fixture would silently operate on the REAL repo
  // (feedback_mistake_git_hook_env_leak). Naming three variables was not
  // enough, and scrubbing without the flag did nothing at all.
  // Regression-check both paths with:
  //   GIT_DIR=$(git rev-parse --git-dir) GIT_WORK_TREE=$(pwd) GIT_PREFIX= \
  //     flutter test test/contracts/sot_registry_citations_test.dart
  group('gate subprocess (main() wiring)', () {
    late String scriptPath;

    setUpAll(() {
      scriptPath = '${Directory.current.path}/scripts/check_sot_registry_citations.dart';
      expect(File(scriptPath).existsSync(), isTrue, reason: 'gate script must exist');
    });

    /// Builds a temp git repo, writes [registry] + one doc, returns the gate's
    /// ProcessResult.
    ProcessResult runGateOn({
      required String registryYaml,
      required String docName,
      required String docBody,
      bool writeRegistry = true,
      List<String> args = const [],
    }) {
      final tmp = Directory.systemTemp.createTempSync('gate44_');
      // Scrub the ENTIRE GIT_* namespace, not a hand-picked few.
      //
      // A first version removed only GIT_DIR / GIT_WORK_TREE / GIT_INDEX_FILE —
      // the three named in feedback_mistake_git_hook_env_leak — and passed
      // standalone but failed all 7 cases inside the pre-commit hook with
      // "fatal: this operation must be run in a work tree". git exports more
      // than those three (GIT_PREFIX, GIT_COMMON_DIR, GIT_OBJECT_DIRECTORY,
      // GIT_ALTERNATE_OBJECT_DIRECTORIES, GIT_CONFIG*, …) and any one of them
      // can re-point a child git at the REAL repo. Enumerating names is the bug;
      // scrubbing the namespace is the fix.
      final env = Map<String, String>.from(Platform.environment)
        ..removeWhere((k, _) => k.toUpperCase().startsWith('GIT_'));

      Directory('${tmp.path}/docs/diagnoses').createSync(recursive: true);
      if (writeRegistry) {
        File('${tmp.path}/docs/sot_registry.yaml').writeAsStringSync(registryYaml);
      }
      File('${tmp.path}/docs/diagnoses/$docName').writeAsStringSync(docBody);

      for (final cmd in [
        ['init'],
        ['config', 'user.email', 't@t.t'],
        ['config', 'user.name', 't'],
        ['add', '-A'],
      ]) {
        final r = Process.runSync('git', cmd,
            workingDirectory: tmp.path,
            environment: env,
            includeParentEnvironment: false);
        expect(r.exitCode, 0, reason: 'git ${cmd.first} failed: ${r.stderr}');
      }

      // runInShell: on Windows the launcher is `dart.bat`, which Process cannot
      // exec directly — without this every case dies with a bare
      // "The system cannot find the file specified" that looks like a gate bug.
      return Process.runSync(
        'dart',
        ['run', scriptPath, ...args],
        workingDirectory: tmp.path,
        environment: env,
        includeParentEnvironment: false,
        runInShell: true,
      );
    }

    const goodRegistry = 'concepts:\n\n  - concept: real_concept\n    domain: x\n';

    test('exit 1 when a POST-cutoff doc cites an absent concept', () {
      final r = runGateOn(
        registryYaml: goodRegistry,
        docName: '2026-08-09-thing-abc123.md',
        docBody: 'sot_registry_entry: no_such_concept\n',
      );
      expect(r.exitCode, 1, reason: 'stdout=${r.stdout} stderr=${r.stderr}');
      expect('${r.stderr}', contains('no_such_concept'));
    });

    test('exit 0 when a POST-cutoff doc cites a real concept', () {
      final r = runGateOn(
        registryYaml: goodRegistry,
        docName: '2026-08-09-thing-abc123.md',
        docBody: 'sot_registry_entry: real_concept\n',
      );
      expect(r.exitCode, 0, reason: 'stdout=${r.stdout} stderr=${r.stderr}');
    });

    test('a POST-cutoff doc DECLARING non-applicability in prose is accepted', () {
      // The real convention, and the false positive that blocked two docs
      // already merged to main (a4f7c2, d7b3e9). A value opening with a
      // negation is the author being MORE explicit, not evading.
      for (final decl in const [
        'Not a Hive/cloud writer-reader storage concept — dev-workflow tooling',
        'Not applicable — no writer contract changed',
        'n/a — pure UI layout',
        'None — process only',
      ]) {
        final r = runGateOn(
          registryYaml: goodRegistry,
          docName: '2026-08-09-thing-abc123.md',
          docBody: 'sot_registry_entry: $decl\n',
        );
        expect(r.exitCode, 0,
            reason: 'declaration must be accepted: "$decl"\nstdout=${r.stdout}');
      }
    });

    test('exit 1 when a POST-cutoff doc hides behind PROSE (Finding 2)', () {
      // The evasion: spaces instead of underscores means "not identifier-shaped",
      // which used to be filed as an unadjudicated WARN even under --strict.
      final r = runGateOn(
        registryYaml: goodRegistry,
        docName: '2026-08-09-thing-abc123.md',
        docBody: 'sot_registry_entry: some brand new concept\n',
      );
      expect(r.exitCode, 1, reason: 'prose must not be an opt-out; stdout=${r.stdout}');
    });

    test('a PRE-cutoff doc with the same dangling citation is grandfathered', () {
      // The discriminator for the cutoff branch: identical body, older name.
      final r = runGateOn(
        registryYaml: goodRegistry,
        docName: '2026-05-04-thing-abc123.md',
        docBody: 'sot_registry_entry: no_such_concept\n',
      );
      expect(r.exitCode, 0, reason: 'stdout=${r.stdout} stderr=${r.stderr}');
    });

    test('backdating the FILENAME does not exempt a doc whose frontmatter is recent (Finding 6)', () {
      final r = runGateOn(
        registryYaml: goodRegistry,
        docName: '2026-05-04-thing-abc123.md',
        docBody: 'date: 2026-08-09\nsot_registry_entry: no_such_concept\n',
      );
      expect(r.exitCode, 1, reason: 'later of filename/frontmatter wins; stdout=${r.stdout}');
    });

    test('exit 1 (FAIL CLOSED) when the registry file is missing (Finding 5)', () {
      final r = runGateOn(
        registryYaml: goodRegistry,
        docName: '2026-08-09-thing-abc123.md',
        docBody: 'sot_registry_entry: real_concept\n',
        writeRegistry: false,
      );
      expect(r.exitCode, 1, reason: 'a missing registry must not silently disable the gate');
    });

    test('an explicit sentinel is accepted post-cutoff', () {
      final r = runGateOn(
        registryYaml: goodRegistry,
        docName: '2026-08-09-thing-abc123.md',
        docBody: 'sot_registry_entry: not_applicable\n',
      );
      expect(r.exitCode, 0, reason: 'stdout=${r.stdout} stderr=${r.stderr}');
    });
  });

  group('end-to-end pipeline', () {
    test('a doc citing an absent concept is classified dangling', () {
      const doc = '''
bug_id: a4f1c8
sot_registry_entry: notifications_inbox_id_contract
status: fixed
''';
      final raw = citationOf(doc);
      expect(raw, isNotNull);
      final tokens = splitCitation(raw!).toList();
      expect(tokens, ['notifications_inbox_id_contract']);
      expect(classifyCitation(tokens.single, {'auth_hive_owner_agreement'}),
          CitationVerdict.dangling);
    });

    test('a doc citing a present concept passes cleanly', () {
      const doc = 'sot_registry_entry: log_client_error_payload (docs/sot_registry.yaml)\n';
      final tokens = splitCitation(citationOf(doc)!).toList();
      expect(tokens, ['log_client_error_payload']);
      expect(classifyCitation(tokens.single, {'log_client_error_payload'}),
          CitationVerdict.resolved);
    });
  });
}
