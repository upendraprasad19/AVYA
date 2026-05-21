// Tech-debt audit 2026-05-20 finding A10 — CoachMemoryService extracted
// from AiCoachRepository.
//
// Owns identity-signal detection and coaching-notes extraction +
// back-compat backfill. Three responsibilities — all anchored on
// coachBox's singleton sibling keys (coach_memory, coaching_notes).
//
// Why split out: identity-signal detection runs on every outbound user
// message (hot path); coaching-notes extraction runs nightly + on
// extractCoachingNotes(); backfillCoachMemoryIfNeeded runs once at
// app launch from main.dart. None of these belong with the AI-snapshot
// read surface or the chat persistence layer.
//
// Hive contract: every read/write routes through HiveService.instance
// (rule #4 — Hive-first).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import '../models/coach_memory.dart';
import 'identity_signal_detector.dart';
import 'pattern_detector.dart';

/// Identity heuristics + coaching-notes extraction for the AI Coach.
///
/// Singleton — single IdentitySignalDetector instance (carries Hinglish
/// streak state). Streak resets when the active user changes.
class CoachMemoryService {
  CoachMemoryService._();
  static final CoachMemoryService _instance = CoachMemoryService._();
  static CoachMemoryService get instance => _instance;

  final HiveService _hive = HiveService.instance;
  final IdentitySignalDetector _identityDetector = IdentitySignalDetector();
  String? _lastIdentityUserId;

  /// Runs the identity heuristics on a single user message and patches
  /// Hive coach_memory in place. No-op if no signals detected.
  Future<void> detectAndPersistIdentitySignals(String userMessage) async {
    final signals = _identityDetector.detect(userMessage);
    if (signals.communicationStyle == null && signals.preferredName == null) {
      return;
    }

    final userId = HiveService.instance.userBox.get('user_id') as String?;
    if (userId == null || userId.isEmpty) return;

    // Reset detector streak when the active user changes — the singleton
    // detector would otherwise leak Hinglish streak state across sessions.
    if (_lastIdentityUserId != null && _lastIdentityUserId != userId) {
      _identityDetector.resetStreak();
    }
    _lastIdentityUserId = userId;

    try {
      final coachBox = HiveService.instance.coachBox;
      final existing =
          CoachMemory.readFromBox(coachBox) ?? CoachMemory(userId: userId);
      final patched = existing.merge(CoachMemory(
        userId: userId,
        communicationStyle: signals.communicationStyle,
        preferredName: signals.preferredName,
        updatedAt: DateTime.now(),
      ));
      await patched.writeToBox(coachBox);
    } catch (e) {
      // A corrupt coach_memory blob must never crash the message-send hot
      // path. Log and continue — the next successful write will heal it.
      debugPrint('[CoachMemoryService] identity persist failed: $e');
      return;
    }
  }

  /// Extracts coaching notes from today's conversations and persists them.
  /// Called during daily snapshot sync (11PM IST) or on app launch.
  Future<void> extractAndAppendCoachingNotes() async {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final todayMessages = <String>[];
    for (final raw in _hive.coachBox.values) {
      if (raw is! Map) continue;
      final interaction = Map<String, dynamic>.from(raw);
      final createdAt = interaction['created_at'] as String? ?? '';
      if (!createdAt.startsWith(todayStr)) continue;

      final userMsg = interaction['user_message'] as String?;
      final aiResponse = interaction['ai_response'] as String?;
      if (userMsg != null && userMsg.isNotEmpty) {
        todayMessages.add('User: $userMsg');
      }
      if (aiResponse != null && aiResponse.isNotEmpty) {
        todayMessages.add('Coach: $aiResponse');
      }
    }

    if (todayMessages.isEmpty) return;

    // Extract key facts from conversations (local heuristic extraction)
    final facts = <String>[];
    for (final msg in todayMessages) {
      if (msg.startsWith('User:')) {
        final text = msg.substring(5).trim().toLowerCase();
        if (text.contains('hurt') || text.contains('pain') || text.contains('injury') || text.contains('sore')) {
          facts.add('Mentioned discomfort: ${msg.substring(5).trim()}');
        }
        if (text.contains('goal') || text.contains('want to') || text.contains('trying to')) {
          facts.add('Goal update: ${msg.substring(5).trim()}');
        }
        if (text.contains('eat') || text.contains('diet') || text.contains('food') || text.contains('protein')) {
          facts.add('Diet note: ${msg.substring(5).trim()}');
        }
      }
    }

    if (facts.isEmpty) return;

    // Append to existing coaching notes
    final existing = _hive.coachBox.get('coaching_notes');
    final existingNotes = <String>[];
    if (existing is Map) {
      final notesList = existing['notes'] as List?;
      if (notesList != null) {
        existingNotes.addAll(notesList.cast<String>());
      }
    }

    // Keep last 20 notes max
    existingNotes.addAll(facts);
    if (existingNotes.length > 20) {
      existingNotes.removeRange(0, existingNotes.length - 20);
    }

    await _hive.coachBox.put('coaching_notes', {
      'notes': existingNotes,
      'last_extracted': now.toIso8601String(),
    });
    unawaited(SyncService.instance.pushSnapshot());
  }

  /// One-time migration: convert legacy coachBox['coaching_notes'] string
  /// list into coach_memory.coach_notes. Idempotent — no-op if coach_memory
  /// already exists in Hive.
  Future<void> backfillCoachMemoryIfNeeded() async {
    final coachBox = HiveService.instance.coachBox;
    if (CoachMemory.readFromBox(coachBox) != null) return;

    final userId = HiveService.instance.userBox.get('user_id') as String?;
    if (userId == null || userId.isEmpty) return;

    final legacy = coachBox.get('coaching_notes');
    String? merged;
    if (legacy is Map) {
      final notes = legacy['notes'];
      if (notes is List && notes.isNotEmpty) {
        merged = notes.map((n) => n.toString()).join('\n');
      }
    }

    final mem = CoachMemory(
      userId: userId,
      coachNotes: merged,
      lastExtractionAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await mem.writeToBox(coachBox);
    debugPrint(
        '[CoachMemoryService] backfilled coach_memory from legacy coaching_notes');
  }

  /// Returns true if the user hasn't sent a message today yet.
  /// Used to trigger proactive first-message-of-day AI greeting.
  bool isFirstMessageToday() {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final lastGreeting = MigratedKey.read<String>('last_ai_greeting_date');
    return lastGreeting != todayStr;
  }

  /// Marks that the AI has greeted the user today.
  Future<void> markGreetedToday() async {
    await MigratedKey.write(
        'last_ai_greeting_date', istDateStr(DateTime.now()));
  }

  /// Returns the top insight for the dashboard card (highest severity).
  CoachingInsight? getTopInsight() {
    try {
      final insights = PatternDetector.instance.analyze();
      return insights.isNotEmpty ? insights.first : null;
    } catch (e) {
      debugPrint('[CoachMemoryService.getTopInsight] $e');
      return null;
    }
  }
}
