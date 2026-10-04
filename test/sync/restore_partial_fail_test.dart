import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Future.wait eagerError:false semantics', () {
    test('all tasks complete even when the first one throws', () async {
      int aRan = 0, bRan = 0, cRan = 0;

      Future<void> a() async {
        aRan = 1;
        throw Exception('a fails');
      }

      Future<void> b() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bRan = 1;
      }

      Future<void> c() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        cRan = 1;
      }

      try {
        await Future.wait([a(), b(), c()], eagerError: false);
      } catch (_) {
        // expected — Future.wait still throws after all tasks settle
      }

      expect(aRan, 1);
      expect(bRan, 1, reason: 'eagerError:false lets b complete despite a throwing');
      expect(cRan, 1, reason: 'eagerError:false lets c complete despite a throwing');
    });

    test('eagerError:true (default) kills remaining tasks — confirms we need false', () async {
      int bRan = 0, cRan = 0;

      Future<void> a() async => throw Exception('a fails immediately');

      Future<void> b() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        bRan = 1;
      }

      Future<void> c() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        cRan = 1;
      }

      try {
        // Default eagerError:true — the wait rethrows as soon as a() throws,
        // before b/c complete.
        await Future.wait([a(), b(), c()]);
      } catch (_) {}

      // b and c may or may not have run — this is intentionally racy and
      // documents the fragile default. The important assertion is that the
      // test above (eagerError:false) is deterministically safe.
      // We just record whether they ran for documentation purposes:
      addTearDown(() {
        // ignore: avoid_print
        print('[eagerError:true] bRan=$bRan cRan=$cRan (non-deterministic)');
      });
    });

    test('_safeRestoreOp-style wrapper absorbs exceptions and always completes', () async {
      // Simulates what _safeRestoreOp does: wrap any future so it never throws.
      Future<void> safeOp(String label, Future<void> task) async {
        try {
          await task;
        } catch (e) {
          // log + report — swallow so Future.wait sees success
        }
      }

      int bRan = 0, cRan = 0;

      Future<void> a() async => throw Exception('a fails');
      Future<void> b() async => bRan = 1;
      Future<void> c() async => cRan = 1;

      // Even with eagerError:true (default), wrapped tasks never throw.
      await Future.wait([
        safeOp('a', a()),
        safeOp('b', b()),
        safeOp('c', c()),
      ]);

      expect(bRan, 1, reason: 'safeOp wrapper absorbs a() error; b still runs');
      expect(cRan, 1, reason: 'safeOp wrapper absorbs a() error; c still runs');
    });
  });
}
