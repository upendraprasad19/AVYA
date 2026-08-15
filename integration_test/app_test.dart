// ICANBEFITTER — Integration Test Runner
//
// Runs all critical user flow tests against the dev flavor
// (local Supabase + Razorpay test key).
//
// ── How to run ────────────────────────────────────────────────────
//
// Run ALL flows (full suite):
//   flutter test integration_test/ --flavor dev -t lib/main_dev.dart -d <device-id>
//
// Run a single flow in isolation:
//   flutter test integration_test/flows/ai_coach_flow_test.dart \
//     --flavor dev -t lib/main_dev.dart -d <device-id>
//
// ── Prerequisites ─────────────────────────────────────────────────
//
// 1. Local Supabase running:
//      supabase start
//      supabase functions serve --env-file supabase/.env
//
// 2. QA test user created in local Supabase:
//      supabase db reset          # applies seed_qa.sql
//
// 3. Android emulator running:
//      flutter emulators --launch Pixel_5_API_35
//
// ── Test User ─────────────────────────────────────────────────────
//
//   Email:    <SUPABASE_TEST_EMAIL secret>
//   Password: <SUPABASE_TEST_PASSWORD secret>
//   (Created by supabase/seed_qa.sql — local Supabase only)
//
// ── Emulator URL ──────────────────────────────────────────────────
//
//   10.0.2.2:54321  →  local Supabase from Android emulator
//
// ── Flow Summary (9 flows, 80+ tests) ────────────────────────────
//
//  Flow 0: home_flow_test         — Home screen, all 10 widgets
//  Flow 1: auth_flow_test         — Sign in, error handling
//  Flow 2: workout_log_flow_test  — Train tab, phases, PRO gate
//  Flow 3: meal_log_flow_test     — Food search, logging, macros
//  Flow 4: ai_coach_flow_test     — Chat UI, limits, trial, actions
//  Flow 5: pro_gate_flow_test     — Paywall for all PRO features
//  Flow 6: profile_flow_test      — Bio stats, edit, logout
//  Flow 7: data_sync_flow_test    — Hive write → UI update (all tabs)
//  Flow 8: offline_flow_test      — Offline-first guarantee
//  Flow 9: offensive_flow_test    — Input attacks, edge cases, stress

// Each flow file has its own main() and must be run individually, e.g.:
//   flutter test integration_test/flows/home_flow_test.dart \
//     --flavor dev -t lib/main_dev.dart -d emulator-5554
//
// Flow files (do NOT re-export — each defines main() independently):
//   flows/home_flow_test.dart
//   flows/auth_flow_test.dart
//   flows/workout_log_flow_test.dart
//   flows/meal_log_flow_test.dart
//   flows/ai_coach_flow_test.dart
//   flows/pro_gate_flow_test.dart
//   flows/profile_flow_test.dart
//   flows/data_sync_flow_test.dart
//   flows/offline_flow_test.dart
//   flows/offensive_flow_test.dart
