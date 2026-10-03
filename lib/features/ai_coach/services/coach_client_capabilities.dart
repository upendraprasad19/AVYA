// lib/features/ai_coach/services/coach_client_capabilities.dart
//
// The client's declared capability set, sent with every ai-proxy chat
// request (spec 2026-09-26-day-swapper-design.md §5.8). The server filters
// capability-gated tools (ToolDefinition.requiresCapability) down to those
// the caller declared — an absent/empty field on the server side yields
// exactly today's legacy tool set, so an OLD client (one built before this
// batch) simply never sends this const and never sees swapWorkoutDays.
//
// Each entry MUST match the server's validation pattern (`^[a-z_]{1,48}$`,
// `client_capabilities.ts`) and the list MUST NOT exceed 32 entries — both
// enforced only informally here (test/contracts/coach_client_capabilities_test.dart)
// since the server drops any entry that doesn't parse rather than erroring.

const List<String> kCoachClientCapabilities = <String>[
  'swap_workout_days',
];
