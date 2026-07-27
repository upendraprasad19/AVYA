// scripts/plan_review_record_lib.dart
//
// Pure, dependency-free helpers for the §4.12 keystone gate
// (scripts/check_plan_review_record_exists.dart). Extracted so the branch-
// recovery and exemption logic can be driven directly by unit tests instead of
// through a spawned git repo — the gate had ZERO test coverage until
// 2026-07-26 despite being the repo's single structural enforcement point.
//
// Spawning a real git repo from a test is also actively hazardous here: run
// inside `pre-commit`, such a test inherits GIT_DIR/GIT_WORK_TREE, which
// override BOTH `workingDirectory:` and `-C <path>` (feedback_mistake_git_hook_
// env_leak). Pure functions sidestep that entirely.
//
// No imports on purpose: this file must stay trivially testable.

/// What a merge-commit subject resolved to.
enum MergeSubjectKind {
  /// A local `--no-ff` (or non-fast-forward) merge of a feature branch.
  branchMerge,

  /// A GitHub PR merge whose `owner/` prefix matched the expected repo owner.
  pullRequestMerge,

  /// `git pull` producing `Merge branch 'X' of <url>` — a remote-sync merge,
  /// NOT a feature-branch landing. The incoming commits were already gated when
  /// they were originally pushed, and treating this as a branch landing makes
  /// the gate demand `docs/plan-reviews/main.md`, which reddens main for doing
  /// nothing but syncing.
  ///
  /// The CALLER must additionally require that the synced branch is the branch
  /// being landed on (i.e. `main`). `git pull origin <feature>` while on main
  /// also produces this shape but IS a feature landing, and an unconditional
  /// pass here was a craftable bypass — any subject ending `' of x'` skipped the
  /// gate before blast-radius was even computed (round-2 review, P1-2).
  remoteSyncMerge,

  /// A PR merge whose owner prefix did NOT match. The repo is public: a fork
  /// PR whose branch short-name collides with an existing approved record must
  /// never be silently treated as reviewed.
  foreignPullRequest,

  /// Subject shape the gate does not understand — caller should fail loud.
  unrecognized,
}

class MergeSubject {
  final MergeSubjectKind kind;

  /// Raw branch name as it appeared in the subject (NOT the record slug).
  /// Null for [MergeSubjectKind.unrecognized].
  final String? branch;

  /// Owner prefix, only for the PR forms.
  final String? owner;

  const MergeSubject(this.kind, {this.branch, this.owner});
}

/// `git pull` merge: `Merge branch 'X' of <url>`. Checked FIRST, because it
/// also matches the plain branch-merge shape.
final _remoteSyncRe = RegExp(r"^Merge branch '([^']+)'(?=\s) of \S+");

/// Local merge: `Merge branch 'X'`, with ANY trailing text.
///
/// Deliberately NOT anchored at the end. This repo's dominant merge convention
/// is `Merge branch 'X' — <description>` (49 of the 174 merges on main), and an
/// end-anchored form that tolerated only ` into Y` rejected every one of them —
/// including the commit that shipped the batch immediately before this one
/// (`904e6961`, "Merge branch 'ci-speed' — never cancel a main run…"). That
/// anchor was introduced by THIS batch's own first draft while fixing the
/// PR-merge shape, and would have reddened main on the very next merge.
/// Round-2 review caught it; the round-1 tests missed it because they exercised
/// only the ` into Y` suffix.
///
/// Safe to leave open-ended because [_remoteSyncRe] is tested FIRST — the
/// `'X' of <url>` shape can never fall through to here.
///
/// The `(?=\s|$)` lookahead is load-bearing, not decoration. Git ALLOWS a
/// single quote inside a branch name (`git check-ref-format --branch
/// "short-name'z-x"` succeeds), so an ORDINARY merge of such a branch yields
/// `Merge branch 'short-name'z-x'`. Without the lookahead, `'([^']+)'` stops at
/// the embedded quote and silently resolves to the record for `short-name` — a
/// different, possibly approved branch. Requiring the closing quote to be
/// followed by whitespace or end-of-string makes that truncation unrepresentable:
/// the subject is classified `unrecognized` and the gate fails loud instead.
/// (B-pass finding, 2026-07-26.)
final _branchRe = RegExp(r"^Merge branch '([^']+)'(?=\s|$)");

/// GitHub PR merge: `Merge pull request #N from <owner>/<branch>`.
/// The branch part may itself contain `/` (every `dependabot/...` branch does),
/// so this captures greedily after the FIRST `/` — never `.split('/').last`.
final _pullRe = RegExp(r'^Merge pull request #\d+ from ([^/\s]+)/(\S+)');

/// Classifies a merge-commit subject.
///
/// [repoOwner] is the owner the PR form must match (in CI:
/// `GITHUB_REPOSITORY_OWNER`). When null, the PR form cannot be trusted and is
/// reported as [MergeSubjectKind.foreignPullRequest] — fail closed rather than
/// accept an unverifiable owner.
MergeSubject classifyMergeSubject(String subject, {String? repoOwner}) {
  final sync = _remoteSyncRe.firstMatch(subject);
  if (sync != null) {
    return MergeSubject(MergeSubjectKind.remoteSyncMerge,
        branch: sync.group(1));
  }

  final pr = _pullRe.firstMatch(subject);
  if (pr != null) {
    final owner = pr.group(1)!;
    final branch = pr.group(2)!;
    if (repoOwner != null && owner == repoOwner) {
      return MergeSubject(MergeSubjectKind.pullRequestMerge,
          branch: branch, owner: owner);
    }
    return MergeSubject(MergeSubjectKind.foreignPullRequest,
        branch: branch, owner: owner);
  }

  final br = _branchRe.firstMatch(subject);
  if (br != null) {
    return MergeSubject(MergeSubjectKind.branchMerge, branch: br.group(1));
  }

  return const MergeSubject(MergeSubjectKind.unrecognized);
}

/// Maps a branch name to its `docs/plan-reviews/<slug>.md` filename stem.
///
/// Strips a leading remote prefix (the original intent of the old
/// `.split('/').last`), then maps remaining `/` → `-`. The old form took only
/// the LAST segment, which (a) mangled every slashed branch —
/// `dependabot/pub/build_runner-2.15.0` → `build_runner-2.15.0` — and (b)
/// collided: `feat/foo` and `fix/foo` both resolved to `foo`, so one branch's
/// approved record could satisfy an unrelated branch's gate.
///
/// Note this mapping is not injective either (`a/b` → `a-b` collides with a
/// literal branch `a-b`), which is why the gate ALSO cross-checks the record's
/// own `branch:` field against the recovered name — see
/// [recordBranchFieldMatches].
String recordSlug(String branch) {
  var b = branch;
  const remotePrefix = 'origin/';
  if (b.startsWith(remotePrefix)) b = b.substring(remotePrefix.length);
  return b.replaceAll('/', '-');
}

/// True when the record's own `branch:` field names the branch we recovered.
///
/// Closes the residual `a/b` → `a-b` collision: a branch `hold/mechanic` maps
/// to the slug `hold-mechanic`, which is an EXISTING converged, bpass-accepted
/// record for entirely unrelated work. Without this check that merge would
/// sail through on someone else's review.
///
/// [recordContent] is the raw record file. Returns false when the record
/// declares no `branch:` at all — an un-attributed record cannot vouch for a
/// branch.
/// Scoped to the leading `---` frontmatter block when one is present, so a
/// `branch:` line appearing later in prose or inside a fenced code block cannot
/// vouch for a branch. (B-pass 2026-07-26: safe against all 69 tracked records,
/// but latent fragility — a record that DISCUSSES another branch in its body
/// would otherwise be able to satisfy the check.) Falls back to scanning the
/// whole file when there is no frontmatter, which still fails closed: a record
/// without a `branch:` returns false either way.
bool recordBranchFieldMatches(String recordContent, String branch) {
  final scope = _frontmatter(recordContent) ?? recordContent;
  final m = RegExp(r'^branch:\s*(.+)$', multiLine: true).firstMatch(scope);
  if (m == null) return false;
  return m.group(1)!.trim() == branch;
}

/// Public alias — the keystone gate scopes ALL of its record fields to the
/// frontmatter, not just `branch:` (round-1 review P3-1).
String? recordFrontmatter(String content) => _frontmatter(content);

/// Returns the content between the opening `---` and the next `---`, or null
/// when the file does not open with a frontmatter fence.
String? _frontmatter(String content) {
  final lines = content.split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') return null;
  final end = lines.indexWhere((l) => l.trim() == '---', 1);
  if (end < 0) return null;
  return lines.sublist(1, end).join('\n');
}

/// Dependabot branches are `dependabot/<ecosystem>/<package>-<version>`.
///
/// MUST be tested against the RAW branch name, before [recordSlug] maps the
/// slashes away — `dependabot-pub-foo` would not match this.
bool isDependabotBranch(String branch) => branch.startsWith('dependabot/');

/// Paths a `dependabot/*` branch may touch while skipping the record
/// requirement.
///
/// Deliberately does NOT include `.github/workflows/**`. An Actions-version
/// bump does touch those files, but letting a bot rewrite the CI that enforces
/// every other gate — unreviewed — directly contradicts promoting `test.yml` to
/// platform tier in the same batch. `actions/checkout` in particular supplies
/// `fetch-depth: 0` to the keystone gate's own job. Action bumps therefore
/// still require a record.
const dependabotAllowedPaths = <String>{
  'pubspec.yaml',
  'pubspec.lock',
};

/// True when EVERY changed path is a dependency manifest.
///
/// The exemption is earned by what the diff contains, not by trusting a branch
/// name — anyone with push access can name a local branch `dependabot/x`.
bool dependabotDiffIsManifestOnly(Iterable<String> changedPaths) {
  final paths = changedPaths.map((p) => p.trim()).where((p) => p.isNotEmpty);
  if (paths.isEmpty) return false;
  return paths.every(dependabotAllowedPaths.contains);
}

/// NOTE: `versionBumpAllowedPaths`, `isMechanicalVersionBump` and
/// `requiresFreshRecord` were written for OI-58a/OI-58b and REMOVED again on
/// 2026-07-27 when that half of the batch was split out (CLAUDE.md §4.12.1 —
/// three review rounds each found a new material defect in them, the last being
/// an exemption that accepted any SUBSET of its path allow-list, so a direct
/// commit rewriting prices and free-tier caps in app_constants.dart passed at
/// account tier). They return with the split unit, where the exemption must be
/// CONTENT-verified — every changed LINE a version line — to the same standard
/// as the Dependabot exemption below.

/// True when every commit author on the merged side is Dependabot.
///
/// Second half of the content-verification: the branch NAME is attacker-
/// controlled, so the exemption additionally requires the commits to actually
/// come from the bot. [authors] are `%ae` (author email) values from
/// `git log HEAD^1..HEAD^2`.
bool allCommitsAuthoredByDependabot(Iterable<String> authors) {
  final list = authors.map((a) => a.trim().toLowerCase()).where((a) => a.isNotEmpty).toList();
  if (list.isEmpty) return false;
  return list.every((a) =>
      a == 'support@dependabot.com' ||
      a.endsWith('dependabot[bot]@users.noreply.github.com'));
}
