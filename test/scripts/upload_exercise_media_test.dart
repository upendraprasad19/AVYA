// Batch M1 (plan R7, R14, Task 5): scripts/upload_exercise_media.js against a FAKE Storage API and a FAKE Management API,
// both a Dart HttpServer on the loopback interface. Every spawn of the tool goes through the ONE helper `_Rig.run`, which
// always passes --base-url, --management-url, --token-file (a path that does not exist unless the test needs a token),
// --table (a fixture table) and --wardroom-dir (a fixture folder), so no test can reach the real api.supabase.com, read the
// founder's real token file or touch the committed table. A source-grep leg at the end pins that there is exactly one spawn
// of the tool in this file.
//
// Run: flutter test test/scripts/upload_exercise_media_test.dart
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../scripts/migration_ledger_hash_lib.dart' show sha256Hex;
import '../helpers/spawn.dart';
import '../helpers/webp_fixture.dart';

const _tool = 'scripts/upload_exercise_media.js';
const _projectRef = 'dedsavbjuwgarrhphgnl';
const _accessToken = 'fake-access-token-XYZ123-NOT-A-REAL-TOKEN';
const _mgmtErrorBody = 'management-error-body-LEAK-CANARY';
const _anonValue = 'anon-key-value-NOT-A-REAL-KEY';

String _b64(Map<String, Object> m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
String _jwt(String ref, String tag) => '${_b64({'alg': 'HS256'})}.${_b64({'ref': ref, 'role': 'service_role'})}.sig$tag';

class _Seen {
  _Seen(this.method, this.path, this.query, this.headers, this.body);
  final String method;
  final String path;
  final String query;
  final Map<String, String> headers;
  final List<int> body;
}

/// A fake Storage + Management API. Behaviours are plain fields a test sets before spawning the tool.
class _Fake {
  _Fake(this.key);

  final String key;
  late HttpServer server;
  final seen = <_Seen>[];
  final objects = <String, Uint8List>{};
  final cacheOf = <String, String>{};

  // Behaviours.
  final headStatus = <String, int>{}; // forced HEAD status for a name
  final headSeq = <String, List<int>>{}; // consumed one per HEAD of a name (then the normal answer)
  final postStatus = <String, int>{}; // forced POST status (the object is not stored)
  final postBody = <String, String>{};
  final cutPost = <String>{}; // destroy the connection on the first POST of a name
  int publicStatus = 400; // exercise-media on the public route
  int noAuthStatus = 400; // the authenticated route with no Authorization header
  int controlStatus = 200; // avatars / banners on the public route
  int signStatus = 200;
  String? signedUrlOverride;
  int mgmtStatus = 200;
  bool revealed = true;
  bool existsGivesDuplicate400 = false;

  String get url => 'http://127.0.0.1:${server.port}';

  List<_Seen> where(bool Function(_Seen) f) => seen.where(f).toList();
  List<_Seen> get posts => where((r) => r.method == 'POST' && r.path.startsWith('/storage/v1/object/exercise-media/'));
  List<_Seen> get deletes => where((r) => r.method == 'DELETE');

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
  }

  Future<void> stop() => server.close(force: true);

  void _json(HttpResponse res, int status, Object body) {
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final body = await req.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    final headers = <String, String>{};
    req.headers.forEach((n, v) => headers[n.toLowerCase()] = v.join(','));
    final path = req.uri.path;
    seen.add(_Seen(req.method, path, req.uri.query, headers, body));
    final bearer = headers['authorization'] ?? '';
    final hasKey = bearer == 'Bearer $key' && headers['apikey'] == key;
    const objPrefix = '/storage/v1/object/exercise-media/';
    const authPrefix = '/storage/v1/object/authenticated/exercise-media/';
    const signPrefix = '/storage/v1/object/sign/exercise-media/';
    const pubPrefix = '/storage/v1/object/public/';
    try {
      if (path == '/v1/projects/$_projectRef/api-keys') {
        if (bearer != 'Bearer $_accessToken') {
          _json(res, 401, {'message': _mgmtErrorBody});
        } else if (mgmtStatus != 200) {
          _json(res, mgmtStatus, {'message': _mgmtErrorBody});
        } else {
          _json(res, 200, [
            {'name': 'anon', 'api_key': _anonValue},
            {'name': 'service_role', 'api_key': revealed ? key : null},
          ]);
        }
      } else if (path.startsWith(authPrefix)) {
        final name = path.substring(authPrefix.length);
        if (req.method == 'HEAD' || req.method == 'GET') {
          if (!hasKey && bearer.isEmpty) {
            if (noAuthStatus == 200 && objects.containsKey(name)) {
              _serve(res, req.method, name);
            } else {
              _json(res, noAuthStatus == 200 ? 404 : noAuthStatus, {'statusCode': '400', 'message': 'no authorization'});
            }
          } else if (!hasKey) {
            _json(res, 401, {'message': 'bad key'});
          } else {
            final seq = headSeq[name];
            final forced = req.method == 'HEAD' && seq != null && seq.isNotEmpty ? seq.removeAt(0) : headStatus[name];
            if (req.method == 'HEAD' && forced != null) {
              res.statusCode = forced;
            } else if (objects.containsKey(name)) {
              _serve(res, req.method, name);
            } else {
              res.statusCode = 404;
            }
          }
        } else {
          res.statusCode = 405;
        }
      } else if (path.startsWith(objPrefix) && req.method == 'POST') {
        final name = path.substring(objPrefix.length);
        if (!hasKey) {
          _json(res, 401, {'message': 'bad key'});
        } else if (cutPost.remove(name)) {
          final socket = await res.detachSocket(writeHeaders: false);
          socket.destroy();
          return;
        } else if (postStatus.containsKey(name)) {
          res.statusCode = postStatus[name]!;
          res.write(postBody[name] ?? '{"statusCode":"${postStatus[name]}"}');
        } else if (objects.containsKey(name)) {
          if (existsGivesDuplicate400) {
            _json(res, 400, {'statusCode': '409', 'error': 'Duplicate', 'message': 'The resource already exists'});
          } else {
            _json(res, 409, {'statusCode': '409', 'error': 'Duplicate'});
          }
        } else {
          objects[name] = Uint8List.fromList(body);
          cacheOf[name] = headers['cache-control'] ?? '';
          _json(res, 200, {'Key': 'exercise-media/$name'});
        }
      } else if (path.startsWith(objPrefix) && req.method == 'DELETE') {
        final name = path.substring(objPrefix.length);
        if (!hasKey) {
          _json(res, 401, {'message': 'bad key'});
        } else {
          objects.remove(name);
          _json(res, 200, {'message': 'Successfully deleted'});
        }
      } else if (path.startsWith(signPrefix) && req.method == 'POST') {
        final name = path.substring(signPrefix.length);
        if (!hasKey) {
          _json(res, 401, {'message': 'bad key'});
        } else if (signStatus != 200) {
          _json(res, signStatus, {'message': 'sign refused'});
        } else {
          _json(res, 200, {'signedURL': signedUrlOverride ?? '/object/sign/exercise-media/$name?token=tok-$name'});
        }
      } else if (path.startsWith(signPrefix) && req.method == 'GET') {
        final name = path.substring(signPrefix.length);
        if (objects.containsKey(name) && req.uri.queryParameters['token'] == 'tok-$name') {
          res.headers.set('cache-control', cacheOf[name] ?? '');
          _serve(res, 'GET', name);
        } else {
          res.statusCode = 400;
        }
      } else if (path.startsWith(pubPrefix) && req.method == 'GET') {
        final rest = path.substring(pubPrefix.length);
        final bucket = rest.split('/').first;
        if (bucket == 'exercise-media') {
          final name = rest.substring('exercise-media/'.length);
          if (publicStatus == 200 && objects.containsKey(name)) {
            _serve(res, 'GET', name);
          } else {
            res.statusCode = publicStatus == 200 ? 404 : publicStatus;
          }
        } else {
          res.statusCode = controlStatus;
        }
      } else if (path == '/storage/v1/bucket/exercise-media/empty' && req.method == 'POST') {
        objects.clear();
        _json(res, 200, {'message': 'Successfully emptied'});
      } else if (path == '/storage/v1/bucket/exercise-media' && req.method == 'DELETE') {
        _json(res, 200, {'message': 'Successfully deleted'});
      } else {
        res.statusCode = 404;
      }
    } finally {
      await res.close();
    }
  }

  void _serve(HttpResponse res, String method, String name) {
    final bytes = objects[name]!;
    res.statusCode = 200;
    res.headers.contentType = ContentType('image', 'webp');
    res.contentLength = bytes.length;
    if (method != 'HEAD') res.add(bytes);
  }
}

class _Rig {
  _Rig();

  late Directory dir;
  late FixtureWardroom ward;
  late Map<String, dynamic> table;
  late _Fake fake;
  late String key;
  final entries = <FixtureEntry>[
    FixtureEntry(number: '0103', name: 'Barbell Standing Ab Rollout', animSize: 3000, thumbSize: 500, seed: 1),
    FixtureEntry(number: '3643', name: "Farmer's Walk", animSize: 3500, thumbSize: 600, seed: 2),
    FixtureEntry(number: '0007', name: 'Alternate Lateral Pulldown', animSize: 4000, thumbSize: 700, seed: 3),
    FixtureEntry(number: '6000', name: 'Alias One', animSize: 2500, thumbSize: 800, seed: 4),
    FixtureEntry(number: '0555', name: 'Taken Down One', animSize: 2600, thumbSize: 900, seed: 5),
  ];

  String get tablePath => '${dir.path}/table.json';
  String get tokenPath => '${dir.path}/access-token.txt';
  String get missingToken => '${dir.path}/no-such-token.txt';
  String get reportPath => '${dir.path}/out/report.json';

  /// slug, object name and local bytes of a fixture entry.
  String slugOf(String number) => (table['files'] as Map<String, dynamic>).keys.firstWhere((k) => k.startsWith('$number-'));
  String localPath(String number) {
    final file = (((table['files'] as Map<String, dynamic>)[slugOf(number)] as Map<String, dynamic>)['versions'] as List).first as Map<String, dynamic>;
    return '${ward.dir.path}/${file['file']}';
  }

  String objOf(String number) => '${slugOf(number)}_v1.webp';
  List<int> bytesOf(String number) =>
      File(localPath(number)).readAsBytesSync();
  List<String> get activeObjects => [objOf('0103'), objOf('3643'), objOf('0007')];

  Future<void> setUp() async {
    dir = Directory.systemTemp.createTempSync('uem_');
    key = _jwt(_projectRef, 'KEYSIGNATURE0001');
    ward = writeFixtureWardroom(Directory('${dir.path}/ward')..createSync(), entries);
    final files = <String, dynamic>{};
    final rows = <String, String>{};
    final status = {'0103': 'active', '3643': 'active', '0007': 'active', '6000': 'unmapped', '0555': 'taken_down'};
    for (final e in ward.entries) {
      final number = (e['id'] as String).substring(0, 4);
      final name = e['name'] as String;
      final slug = '$number-${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '')}';
      final animRel = (e['outputs'] as Map)['animation'] as String;
      final anim = File('${ward.dir.path}/$animRel').readAsBytesSync();
      files[slug] = {
        'frames': 12,
        'gif': number,
        'ledger_id': e['id'],
        'source_gif_sha256': (e['sourceSHA256'] as String),
        'status': status[number],
        'thumb_bytes': (e['thumbnailValidation'] as Map)['bytes'],
        'thumb_sha256': (e['thumbnailValidation'] as Map)['SHA256'],
        'versions': [
          {'file': animRel, 'media_version': 1, 'webp_bytes': anim.length, 'webp_sha256': sha256Hex(anim)},
        ],
        'webp_bytes': anim.length,
        'webp_sha256': sha256Hex(anim),
      };
      if (status[number] == 'active') rows['G$number'] = slug;
    }
    table = {
      '_meta': {'bucket': 'exercise-media', 'old_rows': null, 'taken_down': ['0555-taken-down-one'], 'webp_bytes_max': 1500000},
      'files': files,
      'rows': rows,
    };
    writeTable();
    fake = _Fake(key);
    await fake.start();
  }

  void writeTable() => File(tablePath).writeAsStringSync(jsonEncode(table));

  Future<void> tearDown() async {
    await fake.stop();
    dir.deleteSync(recursive: true);
  }

  /// THE one spawn of the tool in this file. [seams] false omits the loopback seams (only for refusal tests that never
  /// reach the network); [withKey] puts the fake service-role key in the child's environment.
  Future<ProcessResult> run(
    List<String> args, {
    bool seams = true,
    bool withKey = true,
    String? tokenFile,
    Map<String, String> env = const {},
    Set<String> allow = const {},
  }) {
    return runSpawnAsync(
      'node',
      [
        _tool,
        ...args,
        '--table', tablePath,
        '--wardroom-dir', ward.dir.path,
        if (seams) ...['--base-url', fake.url, '--management-url', fake.url],
        '--token-file', tokenFile ?? missingToken,
      ],
      why: 'upload_exercise_media.js ${args.join(' ')} against a fake server',
      extraEnv: {if (withKey) 'SUPABASE_SERVICE_ROLE_KEY': key, ...env},
      allowControl: {if (withKey) 'SUPABASE_SERVICE_ROLE_KEY', ...allow},
      report: (_) {},
    ).timeout(const Duration(seconds: 90), onTimeout: () => throw TimeoutException('tool run timed out'));
  }

  Map<String, dynamic> readReport() => jsonDecode(File(reportPath).readAsStringSync()) as Map<String, dynamic>;
}

String _all(ProcessResult r) => '${r.stdout}\n${r.stderr}';

/// Nothing the tool printed or wrote may contain a secret.
void _expectNoSecrets(_Rig rig, ProcessResult r, {List<String> extra = const []}) {
  final blob = StringBuffer(_all(r));
  if (File(rig.reportPath).existsSync()) blob.write(File(rig.reportPath).readAsStringSync());
  for (final s in [rig.key, rig.key.split('.').last, _accessToken, _mgmtErrorBody, _anonValue, ...extra]) {
    expect(blob.toString().contains(s), isFalse, reason: 'the output or the report contains a secret: $s');
  }
}

void main() {
  late _Rig rig;
  setUp(() async {
    rig = _Rig();
    await rig.setUp();
  });
  tearDown(() => rig.tearDown());

  group('default mode: the dry run', () {
    test('prints the plan, needs no key, sends nothing and exits 0', () async {
      final r = await rig.run([], withKey: false);
      expect(r.exitCode, 0, reason: _all(r));
      expect(r.stdout, contains('plan: 3 objects'));
      expect(r.stdout, contains('ok 3, missing 0, sha mismatch 0'));
      expect(rig.fake.seen, isEmpty, reason: 'the dry run must send nothing');
    });

    test('exits non-zero, sending nothing, when one local file is missing and another changed', () async {
      File(rig.localPath('0103')).deleteSync();
      File(rig.localPath('3643')).writeAsBytesSync(webpBytes(3500, 99));
      final r = await rig.run([], withKey: false);
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(r.stdout, contains('missing 1'));
      expect(r.stdout, contains('sha mismatch 1'));
      expect(rig.fake.seen, isEmpty);
    });

    test('unmapped and taken_down files are not in the plan', () async {
      final r = await rig.run([], withKey: false);
      expect(r.stdout, contains('3 objects'));
      expect(r.stdout, isNot(contains('alias-one')));
    });
  });

  group('argument guards', () {
    test('--execute with no key source exits non-zero before any request', () async {
      final r = await rig.run(['--execute', '--report', rig.reportPath], withKey: false);
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(rig.fake.seen, isEmpty);
    });

    test('--execute without --report is refused', () async {
      final r = await rig.run(['--execute']);
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(rig.fake.seen, isEmpty);
    });

    test('a report path inside the repository is refused', () async {
      final r = await rig.run(['--execute', '--report', '${Directory.current.path}/report_must_not_exist.json']);
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(File('${Directory.current.path}/report_must_not_exist.json').existsSync(), isFalse);
      expect(rig.fake.seen, isEmpty);
    });

    test('a report path inside the primary checkout is refused', () async {
      final wt = await runSpawnAsync('git', ['worktree', 'list', '--porcelain'],
              why: 'primary checkout for the report-path test', report: (_) {})
          .timeout(const Duration(seconds: 30));
      final primary = RegExp(r'^worktree (.+)$', multiLine: true).firstMatch(wt.stdout as String)!.group(1)!.trim();
      final r = await rig.run(['--execute', '--report', '$primary/report_must_not_exist.json']);
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(File('$primary/report_must_not_exist.json').existsSync(), isFalse);
      expect(rig.fake.seen, isEmpty);
    });

    test('a report path written with backslashes inside the repository is refused (win32)', () async {
      final r = await rig.run(['--execute', '--report', '${Directory.current.path.replaceAll('/', r'\')}\\report_must_not_exist.json']);
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(rig.fake.seen, isEmpty);
    }, skip: Platform.isWindows ? false : 'backslash paths are a Windows spelling');

    test('a report path with a different drive-letter case inside the repository is refused (win32)', () async {
      final p = Directory.current.path;
      final flipped = '${p[0] == p[0].toUpperCase() ? p[0].toLowerCase() : p[0].toUpperCase()}${p.substring(1)}';
      final r = await rig.run(['--execute', '--report', '$flipped/report_must_not_exist.json']);
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(rig.fake.seen, isEmpty);
    }, skip: Platform.isWindows ? false : 'drive letters are a Windows spelling');

    test('--base-url without --management-url, and the reverse, are refused', () async {
      final a = await rig.run(['--base-url', rig.fake.url], seams: false);
      expect(a.exitCode, isNot(0), reason: _all(a));
      final b = await rig.run(['--management-url', rig.fake.url], seams: false);
      expect(b.exitCode, isNot(0), reason: _all(b));
      expect(rig.fake.seen, isEmpty);
    });

    for (final bad in ['https://example.com', 'http://127.0.0.1@evil.com/', 'http://localhost.evil.com', 'http://evil.com:80']) {
      test('a non-localhost seam host is refused: $bad', () async {
        final r = await rig.run(['--base-url', bad, '--management-url', bad], seams: false);
        expect(r.exitCode, isNot(0), reason: _all(r));
        expect(rig.fake.seen, isEmpty);
      });
    }

    test('an unknown flag is refused, and so is --bucket', () async {
      final a = await rig.run(['--no-such-flag']);
      expect(a.exitCode, isNot(0), reason: _all(a));
      final b = await rig.run(['--bucket', 'avatars']);
      expect(b.exitCode, isNot(0), reason: _all(b));
      expect(rig.fake.seen, isEmpty);
    });

    test('a key whose JWT ref is another project is refused', () async {
      final other = _jwt('someotherprojectref0', 'OTHERSIG');
      final r = await rig.run(['--execute', '--report', rig.reportPath], withKey: false, env: {'SUPABASE_SERVICE_ROLE_KEY': other}, allow: {'SUPABASE_SERVICE_ROLE_KEY'});
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(rig.fake.seen, isEmpty);
    });

    test('a cache-control form containing public is refused; another form is sent as given', () async {
      final bad = await rig.run(['--execute', '--report', rig.reportPath, '--cache-control', 'public, max-age=60']);
      expect(bad.exitCode, isNot(0), reason: _all(bad));
      expect(rig.fake.seen, isEmpty);
      final ok = await rig.run(['--execute', '--report', rig.reportPath, '--cache-control', 'max-age=60']);
      expect(ok.exitCode, 0, reason: _all(ok));
      expect(rig.fake.posts.every((p) => p.headers['cache-control'] == 'max-age=60'), isTrue);
    });
  });

  group('the key', () {
    test('from the environment: the upload works and nothing printed or written contains the key', () async {
      final r = await rig.run(['--execute', '--report', rig.reportPath]);
      expect(r.exitCode, 0, reason: _all(r));
      _expectNoSecrets(rig, r);
    });

    test('from the fake Management API with an access-token FILE; the access-token variables are ignored', () async {
      File(rig.tokenPath).writeAsStringSync('$_accessToken\n');
      final r = await rig.run(
        ['--execute', '--report', rig.reportPath],
        withKey: false,
        tokenFile: rig.tokenPath,
        env: {'SUPABASE_ACCESS_TOKEN_FITNESS': 'wrong-env-token', 'SUPABASE_ACCESS_TOKEN': 'wrong-env-token-2'},
        allow: {'SUPABASE_ACCESS_TOKEN_FITNESS', 'SUPABASE_ACCESS_TOKEN'},
      );
      expect(r.exitCode, 0, reason: _all(r));
      final mgmt = rig.fake.where((s) => s.path.startsWith('/v1/'));
      expect(mgmt, hasLength(1));
      expect(mgmt.single.headers['authorization'], 'Bearer $_accessToken', reason: 'the token comes from the file, never from the environment');
      _expectNoSecrets(rig, r);
    });

    test('a Management API error stops the run and its body is never echoed', () async {
      File(rig.tokenPath).writeAsStringSync('$_accessToken\n');
      rig.fake.mgmtStatus = 500;
      final r = await rig.run(['--probe-key'], withKey: false, tokenFile: rig.tokenPath);
      expect(r.exitCode, isNot(0), reason: _all(r));
      _expectNoSecrets(rig, r);
    });

    test('a Management API answer with no revealed service_role key stops the run', () async {
      File(rig.tokenPath).writeAsStringSync('$_accessToken\n');
      rig.fake.revealed = false;
      final r = await rig.run(['--probe-key'], withKey: false, tokenFile: rig.tokenPath);
      expect(r.exitCode, isNot(0), reason: _all(r));
      _expectNoSecrets(rig, r);
    });

    test('--probe-key prints only the key names, their lengths, the source and ref ok', () async {
      File(rig.tokenPath).writeAsStringSync('$_accessToken\n');
      final r = await rig.run(['--probe-key'], withKey: false, tokenFile: rig.tokenPath);
      expect(r.exitCode, 0, reason: _all(r));
      expect(r.stdout, contains('anon (length ${_anonValue.length})'));
      expect(r.stdout, contains('service_role (length ${rig.key.length})'));
      expect(r.stdout, contains('ref ok'));
      _expectNoSecrets(rig, r);
    });

    test('--probe-key with the key in the environment prints the source and ref ok', () async {
      final r = await rig.run(['--probe-key']);
      expect(r.exitCode, 0, reason: _all(r));
      expect(r.stdout, contains('environment'));
      expect(r.stdout, contains('ref ok'));
      _expectNoSecrets(rig, r);
      expect(rig.fake.seen, isEmpty, reason: 'a key from the environment needs no request');
    });
  });

  group('--execute: the upload', () {
    test('POSTs <slug>_v1.webp with image/webp, the default cache-control and x-upsert false; the report lists the outcome', () async {
      final r = await rig.run(['--execute', '--report', rig.reportPath]);
      expect(r.exitCode, 0, reason: _all(r));
      expect(rig.fake.posts, hasLength(3));
      for (final p in rig.fake.posts) {
        expect(p.headers['content-type'], 'image/webp');
        expect(p.headers['cache-control'], 'max-age=31536000');
        expect(p.headers['x-upsert'], 'false');
        expect(p.headers['authorization'], 'Bearer ${rig.key}');
      }
      expect(rig.fake.posts.map((p) => p.path.split('/').last).toSet(), rig.activeObjects.toSet());
      for (final n in ['0103', '3643', '0007']) {
        expect(rig.fake.objects[rig.objOf(n)], rig.bytesOf(n), reason: 'the stored object is the local file');
      }
      final report = rig.readReport();
      expect((report['uploaded'] as List), hasLength(3));
      expect(report['alreadyEqual'], isEmpty);
      expect(report['failed'], isEmpty);
    });

    test('an object that exists with the same sha256 is alreadyEqual and not re-sent', () async {
      rig.fake.objects[rig.objOf('0103')] = Uint8List.fromList(rig.bytesOf('0103'));
      final r = await rig.run(['--execute', '--report', rig.reportPath]);
      expect(r.exitCode, 0, reason: _all(r));
      expect(rig.fake.posts.map((p) => p.path.split('/').last), isNot(contains(rig.objOf('0103'))));
      final report = rig.readReport();
      expect(report['alreadyEqual'], [rig.objOf('0103')]);
      expect((report['uploaded'] as List), hasLength(2));
    });

    test('an object that exists with a different sha256 stops the run naming the slug', () async {
      rig.fake.objects[rig.objOf('0103')] = Uint8List.fromList(webpBytes(3000, 77));
      final r = await rig.run(['--execute', '--report', rig.reportPath]);
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(_all(r), contains(rig.slugOf('0103')));
      expect(rig.fake.posts, isEmpty, reason: 'nothing is sent after a mismatch');
    });

    for (final status in [400, 404]) {
      test('a HEAD answering $status is "absent": the object is POSTed', () async {
        rig.fake.headStatus[rig.objOf('0103')] = status;
        final r = await rig.run(['--execute', '--report', rig.reportPath]);
        expect(r.exitCode, 0, reason: _all(r));
        expect(rig.fake.posts.map((p) => p.path.split('/').last), contains(rig.objOf('0103')));
      });
    }

    test('a POST that answers 409 after an absent HEAD is re-checked by GET: equal means alreadyEqual', () async {
      final name = rig.objOf('3643');
      rig.fake.headStatus[name] = 404; // HEAD says absent, the object is there
      rig.fake.objects[name] = Uint8List.fromList(rig.bytesOf('3643'));
      final r = await rig.run(['--execute', '--report', rig.reportPath]);
      expect(r.exitCode, 0, reason: _all(r));
      expect(rig.readReport()['alreadyEqual'], [name]);
    });

    test('a 400 whose body carries statusCode 409 is the same duplicate, re-checked by GET', () async {
      final name = rig.objOf('3643');
      rig.fake.existsGivesDuplicate400 = true;
      rig.fake.headStatus[name] = 404;
      rig.fake.objects[name] = Uint8List.fromList(rig.bytesOf('3643'));
      final r = await rig.run(['--execute', '--report', rig.reportPath]);
      expect(r.exitCode, 0, reason: _all(r));
      expect(rig.readReport()['alreadyEqual'], [name]);
    });

    test('a duplicate whose bytes differ stops the run naming the slug', () async {
      final name = rig.objOf('3643');
      rig.fake.headStatus[name] = 404;
      rig.fake.objects[name] = Uint8List.fromList(webpBytes(3500, 55));
      final r = await rig.run(['--execute', '--report', rig.reportPath]);
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(_all(r), contains(rig.slugOf('3643')));
    });

    test('a 413 stops the run naming the status; the files after it are not attempted', () async {
      rig.fake.postStatus[rig.objOf('0103')] = 413;
      final r = await rig.run(['--execute', '--report', rig.reportPath]);
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(_all(r), contains('413'));
      expect(rig.fake.posts, hasLength(1), reason: 'the run must stop at the first 413');
    });

    test('a quota-style body (not a 413) stops the run as well', () async {
      rig.fake.postStatus[rig.objOf('0103')] = 400;
      rig.fake.postBody[rig.objOf('0103')] = '{"statusCode":"400","message":"storage quota exceeded"}';
      final r = await rig.run(['--execute', '--report', rig.reportPath]);
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(rig.fake.posts, hasLength(1));
    });

    for (final deleteReport in [false, true]) {
      test('a second --execute after the connection was cut at file 3 continues and ends with every file present'
          '${deleteReport ? ' (report deleted in between)' : ''}', () async {
        rig.fake.cutPost.add(rig.objOf('0007'));
        final first = await rig.run(['--execute', '--report', rig.reportPath]);
        expect(first.exitCode, isNot(0), reason: _all(first));
        expect(rig.fake.objects.keys.toSet(), {rig.objOf('0103'), rig.objOf('3643')});
        if (deleteReport) File(rig.reportPath).deleteSync();
        final second = await rig.run(['--execute', '--report', rig.reportPath]);
        expect(second.exitCode, 0, reason: _all(second));
        expect(rig.fake.objects.keys.toSet(), rig.activeObjects.toSet());
        final report = rig.readReport();
        expect((report['alreadyEqual'] as List), hasLength(2));
        expect(report['uploaded'], [rig.objOf('0007')]);
      });
    }

    test('--only restricts the run to those active slugs; an unmapped or unknown slug is refused', () async {
      final r = await rig.run(['--execute', '--report', rig.reportPath, '--only', '${rig.slugOf('0103')},${rig.slugOf('3643')}']);
      expect(r.exitCode, 0, reason: _all(r));
      expect(rig.fake.objects.keys.toSet(), {rig.objOf('0103'), rig.objOf('3643')});
      final bad = await rig.run(['--execute', '--report', rig.reportPath, '--only', rig.slugOf('6000')]);
      expect(bad.exitCode, isNot(0), reason: _all(bad));
    });

    test('unmapped and taken_down files are neither uploaded nor verified', () async {
      final r = await rig.run(['--execute', '--report', rig.reportPath]);
      expect(r.exitCode, 0, reason: _all(r));
      expect(rig.fake.objects.keys.any((k) => k.startsWith('6000-') || k.startsWith('0555-')), isFalse);
      final v = await rig.run(['--verify']);
      expect(v.exitCode, 0, reason: _all(v));
      expect(rig.fake.where((s) => s.path.contains('6000-') || s.path.contains('0555-')), isEmpty);
    });

    test('the tool sends the file named by the table: a missing file or a sha mismatch is refused', () async {
      final file = File(rig.localPath('0103'));
      file.writeAsBytesSync(webpBytes(3000, 123));
      final r = await rig.run(['--execute', '--report', rig.reportPath]);
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(rig.fake.posts.map((p) => p.path.split('/').last), isNot(contains(rig.objOf('0103'))));
      file.deleteSync();
      final r2 = await rig.run(['--execute', '--report', rig.reportPath]);
      expect(r2.exitCode, isNot(0), reason: _all(r2));
    });

    test('no mode except the two delete modes issues a DELETE', () async {
      await rig.run(['--execute', '--report', rig.reportPath]);
      await rig.run(['--verify']);
      await rig.run(['--sign', rig.objOf('0103')]);
      await rig.run(['--canary', '--execute', '--report', rig.reportPath]);
      await rig.run([]);
      expect(rig.fake.deletes, isEmpty);
    });
  });

  group('--canary', () {
    test('--canary without --execute sends nothing', () async {
      final r = await rig.run(['--canary']);
      expect(r.exitCode, 0, reason: _all(r));
      expect(rig.fake.seen, isEmpty);
    });

    test('uploads exactly three canary objects with the three cache forms; the report carries every observation', () async {
      final r = await rig.run(['--canary', '--execute', '--report', rig.reportPath]);
      expect(r.exitCode, 0, reason: _all(r));
      expect(rig.fake.posts.map((p) => p.path.split('/').last), ['canary-1_v0.webp', 'canary-2_v0.webp', 'canary-3_v0.webp']);
      expect(rig.fake.posts.map((p) => p.headers['cache-control']).toList(),
          ['max-age=31536000', 'max-age=31536000, immutable', 'private, max-age=31536000, immutable']);
      final report = rig.readReport();
      final canaries = (report['canaries'] as List).cast<Map<String, dynamic>>();
      expect(canaries, hasLength(3));
      for (final c in canaries) {
        expect(c['headBeforePost'], 404);
        expect(c['postStatus'], 200);
        expect((c['authenticatedGet'] as Map)['sha'], 'equal');
        expect(c['signStatus'], 200);
        expect((c['signedGet'] as Map)['status'], 200);
        expect((c['signedGet'] as Map)['sha'], 'equal');
        expect(c['probes'], {'publicRoute': 400, 'noAuthorization': 400});
      }
      expect((canaries[1]['signedGet'] as Map)['cacheControl'], 'max-age=31536000, immutable');
      _expectNoSecrets(rig, r, extra: ['token=tok-']);
    });

    test('the three smallest thumbnails are the canaries', () async {
      final r = await rig.run(['--canary', '--execute', '--report', rig.reportPath]);
      expect(r.exitCode, 0, reason: _all(r));
      final sizes = (rig.entries.map((e) => e.thumbSize).toList()..sort()).take(3).toList();
      final stored = ['canary-1_v0.webp', 'canary-2_v0.webp', 'canary-3_v0.webp'].map((n) => rig.fake.objects[n]!.length).toList();
      expect(stored, sizes);
    });

    test('a 200 from the public-route probe stops the run, naming "readable without a login"', () async {
      rig.fake.publicStatus = 200;
      final r = await rig.run(['--canary', '--execute', '--report', rig.reportPath]);
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(_all(r), contains('readable without a login'));
    });

    test('a 200 from the no-Authorization probe stops the run, naming "readable without a login"', () async {
      rig.fake.noAuthStatus = 200;
      final r = await rig.run(['--canary', '--execute', '--report', rig.reportPath]);
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(_all(r), contains('readable without a login'));
    });

    for (final s in [400, 404]) {
      test('probes answering $s pass', () async {
        rig.fake.publicStatus = s;
        rig.fake.noAuthStatus = s;
        final r = await rig.run(['--canary', '--execute', '--report', rig.reportPath]);
        expect(r.exitCode, 0, reason: _all(r));
      });
    }

    test('--canary --repost --execute POSTs canary-1 again and prints the status and body of the answer', () async {
      expect((await rig.run(['--canary', '--execute', '--report', rig.reportPath])).exitCode, 0);
      final before = rig.fake.posts.length;
      final r = await rig.run(['--canary', '--repost', '--execute', '--report', rig.reportPath]);
      expect(r.exitCode, 0, reason: _all(r));
      expect(rig.fake.posts.length, before + 1);
      expect(rig.fake.posts.last.path.endsWith('canary-1_v0.webp'), isTrue);
      expect(r.stdout, contains('status 409'));
      expect(r.stdout, contains('Duplicate'));
    });
  });

  group('--verify', () {
    Future<void> uploadAll() async => expect((await rig.run(['--execute', '--report', rig.reportPath])).exitCode, 0);

    test('a clean bucket exits 0', () async {
      await uploadAll();
      final r = await rig.run(['--verify']);
      expect(r.exitCode, 0, reason: _all(r));
      expect(r.stdout, contains('verify: 3 of 3'));
    });

    test('a missing object exits non-zero', () async {
      await uploadAll();
      rig.fake.objects.remove(rig.objOf('3643'));
      final r = await rig.run(['--verify']);
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(_all(r), contains(rig.slugOf('3643')));
    });

    test('a wrong length exits non-zero', () async {
      await uploadAll();
      rig.fake.objects[rig.objOf('3643')] = Uint8List.fromList(rig.bytesOf('3643').sublist(0, 3000));
      final r = await rig.run(['--verify']);
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(_all(r), contains('wrong length'));
    });

    test('a wrong sha exits non-zero', () async {
      await uploadAll();
      rig.fake.objects[rig.objOf('3643')] = Uint8List.fromList(webpBytes(3500, 66));
      final r = await rig.run(['--verify']);
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(_all(r), contains('wrong sha256'));
    });

    test('a 200 from the public-route probe or the no-Authorization probe exits non-zero', () async {
      await uploadAll();
      rig.fake.publicStatus = 200;
      final a = await rig.run(['--verify']);
      expect(a.exitCode, isNot(0), reason: _all(a));
      expect(_all(a), contains('readable without a login'));
      rig.fake.publicStatus = 400;
      rig.fake.noAuthStatus = 200;
      final b = await rig.run(['--verify']);
      expect(b.exitCode, isNot(0), reason: _all(b));
      expect(_all(b), contains('readable without a login'));
    });

    test('probes answering 400 and 404 pass', () async {
      await uploadAll();
      rig.fake.publicStatus = 404;
      rig.fake.noAuthStatus = 400;
      expect((await rig.run(['--verify'])).exitCode, 0);
    });

    test('the no-Authorization probe sends no Authorization and no apikey header', () async {
      await uploadAll();
      rig.fake.seen.clear();
      await rig.run(['--verify']);
      final probes = rig.fake.where((s) => s.method == 'GET' && s.path.startsWith('/storage/v1/object/authenticated/') && !s.headers.containsKey('authorization'));
      expect(probes, isNotEmpty, reason: 'the keyless probe of the authenticated route must be sent');
      expect(probes.every((s) => !s.headers.containsKey('apikey')), isTrue);
    });
  });

  group('--sign', () {
    test('mints a signed URL per valid active or canary name and prints it to stdout only', () async {
      final r = await rig.run(['--sign', '${rig.objOf('0103')},canary-2_v0.webp', '--expires', '600']);
      expect(r.exitCode, 0, reason: _all(r));
      expect(r.stdout, contains('${rig.objOf('0103')} ${rig.fake.url}/storage/v1/object/sign/exercise-media/${rig.objOf('0103')}?token='));
      expect(r.stdout, contains('canary-2_v0.webp '));
      expect(r.stderr, isNot(contains('token=')));
      final signs = rig.fake.where((s) => s.method == 'POST' && s.path.startsWith('/storage/v1/object/sign/'));
      expect(signs, hasLength(2));
      expect(jsonDecode(utf8.decode(signs.first.body)), {'expiresIn': 600});
      expect(File(rig.reportPath).existsSync(), isFalse);
    });

    test('the default expiry is 300 seconds', () async {
      await rig.run(['--sign', rig.objOf('0103')]);
      final signs = rig.fake.where((s) => s.path.startsWith('/storage/v1/object/sign/'));
      expect(jsonDecode(utf8.decode(signs.single.body)), {'expiresIn': 300});
    });

    test('refuses --expires 901, a bad name and a missing key, each with nothing sent', () async {
      final a = await rig.run(['--sign', rig.objOf('0103'), '--expires', '901']);
      expect(a.exitCode, isNot(0), reason: _all(a));
      final b = await rig.run(['--sign', '../avatars/x.webp']);
      expect(b.exitCode, isNot(0), reason: _all(b));
      final c = await rig.run(['--sign', rig.objOf('0103')], withKey: false);
      expect(c.exitCode, isNot(0), reason: _all(c));
      expect(rig.fake.seen, isEmpty);
    });

    test('refuses an unmapped or taken_down slug', () async {
      final a = await rig.run(['--sign', rig.objOf('6000')]);
      expect(a.exitCode, isNot(0), reason: _all(a));
      final b = await rig.run(['--sign', rig.objOf('0555')]);
      expect(b.exitCode, isNot(0), reason: _all(b));
      expect(rig.fake.seen, isEmpty);
    });

    test('refuses a signed path whose host differs from the base URL', () async {
      rig.fake.signedUrlOverride = 'http://127.0.0.1:1/object/sign/exercise-media/x?token=evil';
      final r = await rig.run(['--sign', rig.objOf('0103')]);
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(r.stdout, isNot(contains('token=evil')));
    });
  });

  group('--probe-control', () {
    test('a 200 exits 0, prints the status only and sends no credential', () async {
      final r = await rig.run(['--probe-control', 'avatars/some-image.png']);
      expect(r.exitCode, 0, reason: _all(r));
      expect(r.stdout, contains('control status 200'));
      expect(_all(r), isNot(contains('some-image')));
      final sent = rig.fake.seen.single;
      expect(sent.path, '/storage/v1/object/public/avatars/some-image.png');
      expect(sent.headers.containsKey('authorization'), isFalse);
      expect(sent.headers.containsKey('apikey'), isFalse);
    });

    test('a 404 exits non-zero', () async {
      rig.fake.controlStatus = 404;
      final r = await rig.run(['--probe-control', 'banners/missing.png']);
      expect(r.exitCode, isNot(0), reason: _all(r));
    });

    for (final bad in ['exercise-media/x.webp', 'progress-photos/x.webp', 'avatars/../x', 'avatars/a b.png', 'avatars/%2e%2e/x', 'avatars/']) {
      test('is refused with nothing sent: $bad', () async {
        final r = await rig.run(['--probe-control', bad]);
        expect(r.exitCode, isNot(0), reason: _all(r));
        expect(rig.fake.seen, isEmpty);
      });
    }
  });

  group('the delete modes', () {
    Future<void> uploadAll() async => expect((await rig.run(['--execute', '--report', rig.reportPath])).exitCode, 0);

    test('are refused without --execute or without --confirm-bucket exercise-media', () async {
      for (final args in [
        ['--delete-object', 'canary-1_v0.webp', '--confirm-bucket', 'exercise-media'],
        ['--delete-object', 'canary-1_v0.webp', '--execute'],
        ['--delete-object', 'canary-1_v0.webp', '--execute', '--confirm-bucket', 'avatars'],
        ['--delete-bucket', '--confirm-bucket', 'exercise-media'],
        ['--delete-bucket', '--execute'],
      ]) {
        final r = await rig.run([...args, '--report', rig.reportPath]);
        expect(r.exitCode, isNot(0), reason: '${args.join(' ')}: ${_all(r)}');
      }
      expect(rig.fake.seen, isEmpty);
    });

    test('--delete-object refuses the object of an active file', () async {
      await uploadAll();
      final r = await rig.run(['--delete-object', rig.objOf('0103'), '--execute', '--confirm-bucket', 'exercise-media', '--report', rig.reportPath]);
      expect(r.exitCode, isNot(0), reason: _all(r));
      expect(rig.fake.objects.containsKey(rig.objOf('0103')), isTrue);
      expect(rig.fake.deletes, isEmpty);
    });

    for (final bad in ['../avatars/x.webp', 'a/b.webp', '%2e%2e', 'x.png', 'CANARY-1_v0.webp', 'canary-4_v0.webp']) {
      test('--delete-object refuses the name $bad with nothing sent', () async {
        final r = await rig.run(['--delete-object', bad, '--execute', '--confirm-bucket', 'exercise-media', '--report', rig.reportPath]);
        expect(r.exitCode, isNot(0), reason: _all(r));
        expect(rig.fake.seen, isEmpty);
      });
    }

    test('--delete-object deletes, then HEADs WITH the key and prints the status', () async {
      expect((await rig.run(['--canary', '--execute', '--report', rig.reportPath])).exitCode, 0);
      rig.fake.seen.clear();
      final r = await rig.run(['--delete-object', 'canary-1_v0.webp', '--execute', '--confirm-bucket', 'exercise-media', '--report', rig.reportPath]);
      expect(r.exitCode, 0, reason: _all(r));
      expect(rig.fake.objects.containsKey('canary-1_v0.webp'), isFalse);
      expect(r.stdout, contains('DELETE 200, HEAD with key 404'));
      final heads = rig.fake.where((s) => s.method == 'HEAD');
      expect(heads, hasLength(1));
      expect(heads.single.headers['authorization'], 'Bearer ${rig.key}');
      expect(heads.single.headers['apikey'], rig.key);
    });

    test('a HEAD that answers 200 once and then 404 passes after the second HEAD', () async {
      expect((await rig.run(['--canary', '--execute', '--report', rig.reportPath])).exitCode, 0);
      rig.fake.seen.clear();
      rig.fake.headSeq['canary-1_v0.webp'] = [200, 404];
      final r = await rig.run(['--delete-object', 'canary-1_v0.webp', '--execute', '--confirm-bucket', 'exercise-media', '--report', rig.reportPath],
          env: {'EXERCISE_MEDIA_RETRY_WAIT_MS': '50'});
      expect(r.exitCode, 0, reason: _all(r));
      expect(rig.fake.where((s) => s.method == 'HEAD'), hasLength(2));
    });

    test('a HEAD that keeps answering 200 exits non-zero', () async {
      expect((await rig.run(['--canary', '--execute', '--report', rig.reportPath])).exitCode, 0);
      rig.fake.headSeq['canary-1_v0.webp'] = [200, 200];
      final r = await rig.run(['--delete-object', 'canary-1_v0.webp', '--execute', '--confirm-bucket', 'exercise-media', '--report', rig.reportPath],
          env: {'EXERCISE_MEDIA_RETRY_WAIT_MS': '50'});
      expect(r.exitCode, isNot(0), reason: _all(r));
    });

    test('after --delete-object of an unmapped object a re-run sends nothing for that name and --verify still exits 0', () async {
      final unmapped = rig.objOf('6000');
      rig.fake.objects[unmapped] = Uint8List.fromList(rig.bytesOf('6000'));
      final d = await rig.run(['--delete-object', unmapped, '--execute', '--confirm-bucket', 'exercise-media', '--report', rig.reportPath]);
      expect(d.exitCode, 0, reason: _all(d));
      rig.fake.seen.clear();
      await uploadAll();
      expect(rig.fake.where((s) => s.path.endsWith(unmapped)), isEmpty);
      expect((await rig.run(['--verify'])).exitCode, 0);
    });

    test('--delete-bucket empties through the API and then deletes the bucket', () async {
      final r = await rig.run(['--delete-bucket', '--execute', '--confirm-bucket', 'exercise-media', '--report', rig.reportPath]);
      expect(r.exitCode, 0, reason: _all(r));
      final calls = rig.fake.seen.map((s) => '${s.method} ${s.path}').toList();
      expect(calls, ['POST /storage/v1/bucket/exercise-media/empty', 'DELETE /storage/v1/bucket/exercise-media']);
    });
  });

  group('the file itself', () {
    test('exactly one spawn of the tool exists in this file, and it is the helper that adds the seams', () {
      final src = File('test/scripts/upload_exercise_media_test.dart').readAsStringSync();
      final spawnCall = 'runSpawn${'Async'}(';
      final withTool = RegExp('${RegExp.escape(spawnCall)}\\s*\'node\',\\s*\\[\\s*_tool,').allMatches(src).length;
      expect(withTool, 1, reason: 'a second spawn of the tool could reach the real API');
      expect(src.contains("'--base-url', fake.url, '--management-url', fake.url"), isTrue);
    });
  });
}
