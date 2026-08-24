import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Pins the `verify_jwt` argument of every RUNNABLE `deploy_via_api.js`
/// invocation in the operator runbooks.
///
/// **The defect this exists for.** `docs/operations/FOUNDER_LAPTOP_HANDOFF.md`
/// told the operator to redeploy `ai-proxy` with `verify_jwt=true`. Live config
/// is `false`, and deliberately so: `supabase/functions/ai-proxy/index.ts:26-27`
/// records that it validates the bearer token itself via `auth.getUser(token)`
/// "because of the Supabase middleware bug that 401's valid JWTs".
///
/// `.claude/deploy_via_api.js:337` is `verifyJwt = verifyJwtArg != 'false'` and
/// `:817` ships that value as live function metadata — so running the documented
/// line would have flipped the gateway ON and 401'd every valid token BEFORE the
/// module loads, taking down the AI coach and all food AI for every user.
///
/// It would have failed SILENTLY: `deploy_via_api.js:669` tolerates 401 for
/// `ai-proxy` in its smoke step, so the deploy prints healthy over a dead
/// function. The only other guard is the human-read confirm box at `:853`.
///
/// Corroboration that `false` is correct: across the whole repo, runnable
/// `ai-proxy` invocations read `false` **11 times** and `true` exactly once —
/// the line this test was written to kill.
///
/// **Scope is deliberate.** Only operator RUNBOOKS are enforced. Diagnose-docs,
/// audit files and `docs/superpowers/plans/` are historical records of what was
/// run at the time; rewriting them to match today's config would falsify
/// history, exactly as CLAUDE.md §7 says of the closure ledgers.
///
/// **Why the fixture group exists.** Once a runbook's deploy section is consumed
/// and deleted (FOUNDER_LAPTOP_HANDOFF.md:10-11 instructs precisely that), the
/// runbook scan has an EMPTY input set and would pass vacuously forever — an
/// empty result reporting in the same colour as nothing-wrong. The fixture group
/// proves the validator still bites regardless of what the docs currently hold.

/// Live `verify_jwt` per function slug.
///
/// Read from the Supabase Management API for project `dedsavbjuwgarrhphgnl` on
/// 2026-08-24. Regenerate by listing the project's Edge Functions and reading
/// each `verify_jwt`; update in the SAME commit as any deploy that changes one.
const expectedVerifyJwt = <String, bool>{
  'admin-dashboard-data': true,
  'admin-verify-payment': true,
  'admin-wipe-storage': true,
  'ai-media-proxy': true,
  'ai-proxy': false,
  'ai-proxy-pro': false,
  'assess-body-composition': true,
  'beat-my-coach': true,
  'clean-orphan-media': false,
  'compute-admin-metrics-daily': false,
  'compute-coach-signals': false,
  'create-razorpay-order': false,
  'daily-snapshot': true,
  'delete-account': true,
  'evaluate-rank-promotions': false,
  'expiry-reminder': false,
  'future-prediction': true,
  'get-community-review-items': true,
  'i-see-you-callout': false,
  'log-client-error': true,
  'morning-alert': false,
  'plateau-alert': false,
  'pr-detection': false,
  'proactive-coach-promotion': false,
  'promote-community-item': false,
  'protein-gap-alert': false,
  're-engagement': false,
  'razorpay-webhook': false,
  'redeem-referral': true,
  'restore-user-snapshot': true,
  'rolling-context': false,
  'streak-guardian': false,
  'validate-promo': true,
  'verify-payment': true,
  'verify-subscription': true,
  'video-render-trigger': true,
  'video-status': false,
  'weekly-recalc': false,
  'weekly-recap-ready': false,
  'weekly-report': true,
  'workout-window-closing': false,
};

/// Matches a RUNNABLE invocation: four positional args ending in a literal
/// `true`/`false`. The `<verify_jwt>` placeholder in the CLAUDE.md template
/// forms does not match, which is intended — a placeholder is not runnable.
final _invocation = RegExp(
  r'deploy_via_api\.js\s+(\S+)\s+"?([A-Za-z0-9_-]+)"?\s+\S+\s+(true|false)\b',
);

/// One human-readable line per problem found in [text]. Empty means clean.
///
/// An UNKNOWN slug is a failure, not a skip: a runbook naming a function this
/// map has never heard of is precisely the case where "no answer" must not be
/// reported as "no problem".
List<String> verifyJwtProblems(String text, String label) {
  final problems = <String>[];
  for (final m in _invocation.allMatches(text)) {
    final slug = m.group(2)!;
    final documented = m.group(3) == 'true';
    if (!expectedVerifyJwt.containsKey(slug)) {
      problems.add(
        '$label: slug "$slug" is not in expectedVerifyJwt — add it (read live '
        'config) so this check can answer at all.',
      );
      continue;
    }
    final live = expectedVerifyJwt[slug]!;
    if (documented != live) {
      problems.add(
        '$label: deploys "$slug" with verify_jwt=$documented but live config is '
        '$live. Running this would change live gateway auth for that function.',
      );
    }
  }
  return problems;
}

/// The copy-pasteable operator surfaces. Historical archives are excluded.
const _runbookRoots = <String>['docs/operations', '.claude/skills'];

void main() {
  group('validator mechanism (fixtures — never vacuous)', () {
    test('catches the exact ai-proxy line this test was written to kill', () {
      final problems = verifyJwtProblems(
        'node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl ai-proxy '
        '.claude/_payload_ai-proxy.json true',
        'fixture',
      );
      expect(problems, hasLength(1));
      expect(problems.single, contains('ai-proxy'));
      expect(problems.single, contains('verify_jwt=true'));
    });

    test('accepts the corrected ai-proxy line', () {
      expect(
        verifyJwtProblems(
          'node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl ai-proxy '
          '.claude/_payload_ai-proxy.json false',
          'fixture',
        ),
        isEmpty,
      );
    });

    test('accepts a genuinely verify_jwt=true function, rejects it flipped', () {
      expect(
        verifyJwtProblems(
          'node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl ai-media-proxy '
          '.claude/_payload_ai-media-proxy.json true',
          'fixture',
        ),
        isEmpty,
      );
      expect(
        verifyJwtProblems(
          'node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl ai-media-proxy '
          '.claude/_payload_ai-media-proxy.json false',
          'fixture',
        ),
        hasLength(1),
      );
    });

    test('an unknown slug fails rather than silently passing', () {
      expect(
        verifyJwtProblems(
          'node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl not-a-real-fn '
          'payload.json false',
          'fixture',
        ),
        hasLength(1),
      );
    });

    test('the <verify_jwt> template placeholder is not treated as runnable', () {
      expect(
        verifyJwtProblems(
          'node .claude/deploy_via_api.js dedsavbjuwgarrhphgnl <fn> '
          '.claude/_payload_<fn>.json <verify_jwt>',
          'fixture',
        ),
        isEmpty,
      );
    });
  });

  group('live operator runbooks', () {
    test('every runnable deploy command matches live verify_jwt', () {
      final problems = <String>[];
      for (final root in _runbookRoots) {
        final dir = Directory(root);
        if (!dir.existsSync()) continue;
        for (final f in dir.listSync(recursive: true).whereType<File>()) {
          if (!f.path.endsWith('.md')) continue;
          problems.addAll(
            verifyJwtProblems(
              f.readAsStringSync(),
              f.path.replaceAll(r'\', '/'),
            ),
          );
        }
      }
      expect(
        problems,
        isEmpty,
        reason: 'Runbook deploy command(s) contradict live config:\n'
            '${problems.join('\n')}',
      );
    });
  });

  group('map coverage', () {
    test('expectedVerifyJwt covers every slug used in any runnable command', () {
      final missing = <String>{};
      for (final root in ['docs', '.claude/skills', 'supabase']) {
        final dir = Directory(root);
        if (!dir.existsSync()) continue;
        for (final f in dir.listSync(recursive: true).whereType<File>()) {
          if (!f.path.endsWith('.md') && !f.path.endsWith('.yaml')) continue;
          for (final m in _invocation.allMatches(f.readAsStringSync())) {
            final slug = m.group(2)!;
            if (!expectedVerifyJwt.containsKey(slug)) missing.add(slug);
          }
        }
      }
      expect(
        missing,
        isEmpty,
        reason: 'slugs referenced by a runnable deploy command but absent '
            'from expectedVerifyJwt: ${missing.join(', ')}',
      );
    });
  });
}
