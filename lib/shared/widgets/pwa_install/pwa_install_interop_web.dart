// Web implementation of the PWA install interop (Unit 3 obs 6). Selected by the
// conditional import in `pwa_install_banner.dart` keyed `dart.library.js_interop`
// (modern web interop — NOT the deprecated dart:html / dart:js used by
// lib/features/dev/plan_xls.dart). The JS hooks (`avyaPwaCanInstall`,
// `avyaPwaPromptInstall`, `avyaPwaIsIosSafari`) are defined inline in
// `web/index.html`, which captures the `beforeinstallprompt` event.

import 'dart:js_interop';

@JS('avyaPwaCanInstall')
external bool _canInstall();

@JS('avyaPwaPromptInstall')
external void _promptInstall();

@JS('avyaPwaIsIosSafari')
external bool _isIosSafari();

bool pwaCanInstall() {
  // The JS hook may not exist yet on a very early frame; guard defensively.
  try {
    return _canInstall();
  } catch (_) {
    return false;
  }
}

Future<void> pwaPromptInstall() async {
  try {
    _promptInstall();
  } catch (_) {
    // The deferred prompt may have been consumed/expired — ignore.
  }
}

bool pwaIsIosSafari() {
  try {
    return _isIosSafari();
  } catch (_) {
    return false;
  }
}
