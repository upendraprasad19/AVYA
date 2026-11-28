// The REAL route table (`AppRouter.router`), resolved without pumping the app.
//
// `RouteConfiguration.findMatch` only walks the route tree: the auth redirect
// runs on navigation and is never reached, and the static initializer builds
// closures, not screens. That makes this the one place a test touches the
// production table — `user_photos_hub_test.dart` proves the back stack in a
// REPLICA of the nesting; this proves the real table registers every location
// the Profile row and the hub navigate to, under `/profile`, inside the
// bottom-navigation shell, with the names the rest of the app uses, AND that each
// location's builder makes the screen it is named for (a route name alone cannot
// tell the hub's builder from Saved's).
//
// What it catches that the source pins in the hub test cannot: a hub moved under
// another route (`/profile/reports/photos`, so `go('/profile/photos')` lands on
// go_router's error page), registered at the top level (no bottom navigation),
// renamed, or built with another screen.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/router/app_router.dart';
import 'package:icanbefitter/features/profile/screens/progress_photos_screen.dart';
import 'package:icanbefitter/features/profile/screens/saved_coach_photos_screen.dart';
import 'package:icanbefitter/features/profile/screens/user_photos_screen.dart';

/// Every route from the outermost match down to the leaf, shell routes included.
List<RouteBase> _chain(RouteMatchList list) {
  final out = <RouteBase>[];
  void walk(RouteMatchBase match) {
    out.add(match.route);
    if (match is ShellRouteMatch) {
      match.matches.forEach(walk);
    }
  }

  list.matches.forEach(walk);
  return out;
}

/// The innermost match: the one whose route builds the screen.
RouteMatchBase _leafMatch(RouteMatchList list) {
  var leaf = list.matches.last;
  while (leaf is ShellRouteMatch) {
    leaf = leaf.matches.last;
  }
  return leaf;
}

void main() {
  RouteMatchList resolve(String location) =>
      AppRouter.router.configuration.findMatch(Uri.parse(location));

  const expected = <(String, String, Type)>[
    ('/profile/photos', 'userPhotos', UserPhotosScreen),
    ('/profile/progress-photos', 'progressPhotos', ProgressPhotosScreen),
    ('/profile/saved-coach-photos', 'savedCoachPhotos', SavedCoachPhotosScreen),
  ];

  for (final (location, name, screen) in expected) {
    testWidgets(
        '$location resolves to `$name`, directly under /profile, inside the '
        'shell, and builds $screen', (tester) async {
      final match = resolve(location);
      expect(match.isError, isFalse,
          reason: '$location must be a registered location');

      final chain = _chain(match);
      final leaf = chain.last as GoRoute;
      expect(leaf.name, name);

      final parent = chain[chain.length - 2] as GoRoute;
      expect(parent.path, '/profile',
          reason: 'the route directly above the leaf is the /profile route');

      expect(chain.whereType<StatefulShellRoute>(), hasLength(1),
          reason: 'inside the bottom-navigation shell, not at the top level');

      // The builder is the production closure; none of these three reads the
      // context or the state, so a bare context is enough to run it.
      await tester.pumpWidget(const SizedBox.shrink());
      final context = tester.element(find.byType(SizedBox));
      final state =
          _leafMatch(match).buildState(AppRouter.router.configuration, match);
      expect(leaf.builder!(context, state).runtimeType, screen,
          reason: '`$name` must build $screen');
    });
  }

  test('the Photos hub is not reachable at any other location', () {
    for (final wrong in [
      '/photos',
      '/profile/reports/photos',
      '/profile/user-photos',
    ]) {
      final match = resolve(wrong);
      final leaf = match.isError ? null : _chain(match).last;
      final name = leaf is GoRoute ? leaf.name : null;
      expect(name, isNot('userPhotos'), reason: wrong);
    }
  });
}
