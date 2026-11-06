// Contract — delete-account erases every bucket the client writes user-owned
// objects into (single-owner audit 2026-09-26, P0 #6).
//
// The defect: delete-account purged a hard-coded list of 3 buckets while the
// client also uploads avatars and banners (profile_provider.dart via
// UserRepository.uploadImage). Both buckets are PUBLIC, so a deleted user's
// photos stayed reachable by URL — 12 such objects were live on 2026-09-26.
// Two lists, two owners, and nothing tying them together.
//
// Now there is one list — `USER_OWNED_BUCKETS` in
// supabase/functions/_shared/user_owned_buckets.ts — and this test ties the
// client to it: every bucket name the client writes to must be on the list.
// The behaviour of the purge itself (every listed bucket, nested paths,
// errors isolated per bucket) is pinned by the Deno test
// supabase/functions/_shared/purge_user_storage_test.ts.

import 'dart:io';

import 'package:test/test.dart';

String _stripDartComments(String s) => s
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i >= 0 ? l.substring(0, i) : l;
    })
    .join('\n');

/// Parameters whose bucket comes from the CALLER: `.from(<param>)` inside a
/// helper. Each is sound only because its callers are scanned by the
/// `bucket:` named-argument form below — adding an entry means reading that
/// helper's call sites once.
const _passThrough = <String, Set<String>>{
  // UserRepository.uploadImage({required String bucket, ...}); its callers
  // pass `bucket: 'avatars'` / `bucket: 'banners'` (profile_provider.dart).
  'lib/shared/repositories/user_repository.dart': {'bucket'},
};

class _Discovery {
  /// bucket name → files naming it.
  final buckets = <String, Set<String>>{};

  /// `file: expression` for every bucket argument that could not be read.
  final unresolved = <String>[];

  /// `file:param` pass-through entries actually seen.
  final passThroughSeen = <String>{};
}

/// Every place [src] names a Storage bucket — `storage.from(X)`,
/// `bucket: X`, `destinationBucket: X` — with X resolved to a bucket name:
/// a string literal, or an identifier with a same-file `IDENT = 'literal'`.
/// NOT keyed on the identifier's name (B-pass c5d659f52986 Finding 3: a const
/// named `_exportsLocation` was invisible to the old `…Bucket =` regex).
/// Anything it cannot read — an expression, a qualified name, a storage
/// handle kept in a variable — is UNRESOLVED and fails the test: a guard that
/// cannot read a value must not pass it.
void _discover(String path, String src, _Discovery out) {
  final consts = <String, String>{
    for (final m in RegExp(r"""\b([_a-zA-Z]\w*)\s*=\s*['"]([a-z0-9_-]+)['"]""")
        .allMatches(src))
      m.group(1)!: m.group(2)!,
  };
  final literal = RegExp(r"""^['"]([a-z0-9_-]+)['"]$""");
  final ident = RegExp(r'^[_a-zA-Z]\w*$');
  void resolve(String rawArg) {
    final arg = rawArg.trim();
    final lit = literal.firstMatch(arg);
    String? name = lit?.group(1);
    if (name == null && ident.hasMatch(arg)) {
      name = consts[arg];
      if (name == null && (_passThrough[path]?.contains(arg) ?? false)) {
        out.passThroughSeen.add('$path:$arg');
        return;
      }
    }
    if (name == null) {
      out.unresolved.add('$path: $arg');
      return;
    }
    out.buckets.putIfAbsent(name, () => <String>{}).add(path);
  }

  for (final m in RegExp(r'storage\s*\.from\(([^)]*)\)').allMatches(src)) {
    resolve(m.group(1)!);
  }
  for (final m in RegExp(r'\b(?:bucket|destinationBucket)\s*:\s*([^,)\n]+)')
      .allMatches(src)) {
    resolve(m.group(1)!);
  }
  // A storage handle used any way but `.storage.from(` hides its bucket.
  for (final m in RegExp(r'\.storage\b(?!\s*\.from\()').allMatches(src)) {
    out.unresolved.add('$path: storage handle at offset ${m.start}');
  }
}

_Discovery _clientDiscovery() {
  final out = _Discovery();
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    _discover(f.path.replaceAll('\\', '/'),
        _stripDartComments(f.readAsStringSync()), out);
  }
  return out;
}

Set<String> _ownedBuckets() {
  final src = File('supabase/functions/_shared/user_owned_buckets.ts')
      .readAsStringSync();
  final list = RegExp(r'USER_OWNED_BUCKETS[^=]*=\s*\[([\s\S]*?)\]')
      .firstMatch(src);
  expect(list, isNotNull, reason: 'USER_OWNED_BUCKETS array not found');
  return RegExp(r'"([a-z0-9_-]+)"')
      .allMatches(list!.group(1)!)
      .map((m) => m.group(1)!)
      .toSet();
}

void main() {
  test('positive control — discovery finds the five buckets live on 2026-09-26',
      () {
    // If this fails, discovery went blind (a refactor changed the call shape)
    // and the subset check below would pass vacuously.
    expect(
      _clientDiscovery().buckets.keys.toSet(),
      containsAll(<String>[
        'avatars',
        'banners',
        'chat-media',
        'coach-media',
        'progress-photos',
      ]),
    );
  });

  test('every bucket argument in lib/ resolves to a name — fail closed', () {
    final d = _clientDiscovery();
    expect(d.unresolved, isEmpty,
        reason: 'These bucket arguments cannot be read statically, so this '
            'test cannot tell whether delete-account purges them. Use a '
            'literal or a same-file string constant, or — for a helper whose '
            'bucket is its caller\'s — add it to _passThrough after checking '
            'that its callers pass `bucket: <literal>`.');
    final listed = {
      for (final e in _passThrough.entries)
        for (final p in e.value) '${e.key}:$p',
    };
    expect(d.passThroughSeen, listed,
        reason: 'a _passThrough entry no longer matches any .from(<param>) — '
            'remove it rather than leave an allowance nothing uses');
  });

  test('the resolver reads constants by VALUE, not by name, and flags the unreadable',
      () {
    final d = _Discovery();
    _discover('lib/fake.dart', """
      static const String _exportsLocation = 'user-exports';
      Future<void> a() => client.storage.from(_exportsLocation).upload(p, b);
      Future<void> b() => client.storage.from(bucketFor(user)).upload(p, b);
      Future<void> c() => client.storage.from(AppConstants.media).upload(p, b);
      Future<void> d() { final s = client.storage; return s.from('x').upload(p, b); }
    """, d);
    expect(d.buckets.keys, contains('user-exports'));
    expect(d.unresolved, hasLength(3),
        reason: 'call, qualified name and aliased handle must each fail closed: '
            '${d.unresolved}');
  });

  test('every bucket the client writes to is purged by delete-account', () {
    final owned = _ownedBuckets();
    final missing = {
      for (final e in _clientDiscovery().buckets.entries)
        if (!owned.contains(e.key)) e.key: e.value,
    };
    expect(missing, isEmpty,
        reason: 'The client names these buckets but delete-account would '
            'leave their objects behind after an account deletion (DPDP §17). '
            'Add each to USER_OWNED_BUCKETS in '
            'supabase/functions/_shared/user_owned_buckets.ts — or, if a '
            'bucket holds no user-owned objects, say so there. Found: '
            '$missing');
  });

  test('delete-account purges through the one list, not a hard-coded array',
      () {
    final handler = _stripDartComments(
        File('supabase/functions/delete-account/index.ts').readAsStringSync());
    // The call's ARGUMENT, not a bare contains(): the import line alone would
    // satisfy contains('USER_OWNED_BUCKETS') while the call passed a literal.
    expect(
        RegExp(r'purgeUserStorage\(\s*admin\.storage,\s*userId,\s*USER_OWNED_BUCKETS\s*,')
            .hasMatch(handler),
        isTrue,
        reason: 'delete-account must pass USER_OWNED_BUCKETS to purgeUserStorage');
    expect(RegExp(r'for\s*\(\s*const\s+bucket\s+of\s+\[').hasMatch(handler),
        isFalse,
        reason: 'a literal bucket array in delete-account is the pre-fix '
            'shape: two lists that drift apart.');
  });
}
