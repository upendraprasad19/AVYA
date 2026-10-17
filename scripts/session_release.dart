import 'dart:io';

// SessionEnd hook: release this session's claim
//
// Mirrors ICANBEFITTER's claude-session-guard.mjs release mode.
// Fails OPEN — every error path exits 0. A hook that wedges a session
// is worse than the omission it prevents.
//
// Currently a placeholder that always succeeds. Future versions will:
// - Clear any session-scoped locks or claims from .git/claude-sessions/
// - Clean up temporary state files

void main() {
  // Exit 0: success. All error paths should exit 0 (fail-open).
  exit(0);
}
