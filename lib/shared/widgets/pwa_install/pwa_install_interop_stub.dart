// Non-web stub for the PWA install interop (Unit 3 obs 6). On Android/iOS the
// app is installed natively, so there is nothing to prompt — every call is a
// no-op / false. The web implementation lives in `pwa_install_interop_web.dart`
// and is selected via the conditional import in `pwa_install_banner.dart`
// keyed on `dart.library.js_interop` (web-only). This file MUST NOT import
// dart:js_interop / dart:html so the Android/iOS build never references web libs.

/// Whether the browser has a deferred `beforeinstallprompt` ready to fire.
bool pwaCanInstall() => false;

/// Triggers the stashed browser install prompt. No-op off-web.
Future<void> pwaPromptInstall() async {}

/// Whether the page is running in iOS Safari (which never fires
/// `beforeinstallprompt` → needs a manual "Add to Home Screen" hint).
bool pwaIsIosSafari() => false;
