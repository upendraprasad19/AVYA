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
      for (final p in const ['no', 'No', 'writer/reader', 'x']) {
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
