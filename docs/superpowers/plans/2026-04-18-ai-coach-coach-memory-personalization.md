# AI Coach — `coach_memory` + Personalization (Layers 4 + 5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 20-string heuristic `coaching_notes` with a structured `coach_memory` table that powers identity mirroring (preferred name, communication style, depth/humor preferences, motivation style) and predictive risk signals (dropout, plateau, PRO-upgrade probability), without surfacing them as nudges yet — only enriching the system prompt.

**Architecture:** New `coach_memory` Postgres table (1 row/user) + Hive mirror at `coachBox['coach_memory']` (plain `Map<String, dynamic>`, no Hive adapter — repo doesn't use them). Extraction extends the existing `daily-snapshot` Edge Function (Gemini JSON-mode, nightly). Predictive signals computed nightly by new `compute-coach-signals` Edge Function (pure SQL, zero AI cost). Client-side identity heuristics (Hinglish detection, preferred-name extraction) update Hive in real time, sync up via the existing `pushSnapshot` round-trip.

**Tech Stack:** Flutter + Hive (no adapter generation), Supabase Postgres + Edge Functions (Deno + TypeScript), Gemini 2.5 Flash via existing `_shared/gemini.ts` helper, pg_cron via `net.http_post` pattern (existing in migration 015).

**Spec:** [docs/superpowers/specs/2026-04-18-ai-coach-coach-memory-personalization-design.md](../specs/2026-04-18-ai-coach-coach-memory-personalization-design.md)

**Migration safety:** All schema changes go to a Supabase branch first (per user decision in brainstorm). Production project `dedsavbjuwgarrhphgnl` is touched only after the branch validates green.

---

## File Structure

### Create
| Path | Responsibility |
|---|---|
| `supabase/migrations/027_create_coach_memory.sql` | `coach_memory` table, indexes, RLS, defaults |
| `supabase/migrations/028_compute_coach_signals_cron.sql` | pg_cron schedule for `compute-coach-signals` |
| `supabase/functions/_shared/coach_memory.ts` | Shared helpers: `fetchCoachMemory`, `upsertCoachMemory`, type defs |
| `supabase/functions/compute-coach-signals/index.ts` | Nightly cron Edge Function — pure SQL signal computation |
| `lib/features/ai_coach/models/coach_memory.dart` | `CoachMemory` data class with `toJson`/`fromJson` and Hive read/write helpers (no @HiveType — repo uses Map storage) |
| `lib/features/ai_coach/services/identity_signal_detector.dart` | `IdentitySignalDetector` — Hinglish + preferred-name heuristics |
| `test/ai_coach/identity_signal_detector_test.dart` | Unit tests for heuristics |
| `test/ai_coach/coach_memory_compaction_test.dart` | Unit test verifying `_compactContext` keeps `coach_memory` |
| `test/ai_coach/coach_memory_backfill_test.dart` | Unit test for legacy `coaching_notes` → `coach_memory` migration |

### Modify
| Path | Change |
|---|---|
| `lib/features/ai_coach/repositories/ai_coach_repository.dart` | `buildAiContext()` emits `coach_memory` block; new `detectIdentitySignals(message)` runs in send path; new `backfillCoachMemoryIfNeeded()` runs once |
| `lib/core/services/ai_service.dart` | `_compactContext` trim order — insert `coach_memory` between `coach_notices` and `coaching_notes` truncation |
| `lib/core/services/sync_service.dart` | `pushSnapshot()` reads `coach_memory` from response, writes to `coachBox['coach_memory']` |
| `supabase/functions/daily-snapshot/index.ts` | Extend Gemini extraction prompt with 5 new fields; upsert to `coach_memory`; return `coach_memory` row in response |
| `supabase/functions/ai-proxy/index.ts` | Server-side fetch of `coach_memory`, merge into system-prompt block [3], add identity-mirroring instructions |
| `supabase/functions/morning-alert/index.ts` | Read `preferred_name` + `motivation_style` from `coach_memory`; tag push with `last_proactive_type='morning_brief'` |
| `CLAUDE.md` | Add `coach_memory` to §4 (Hive boxes), §7 (DB schema row count), §11 (AI architecture), §19 (common bugs) |

### Reuse (no changes)
- `supabase/functions/_shared/gemini.ts` — existing `geminiChat` wrapper
- `supabase/functions/_shared/send_notification.ts` — OneSignal helper
- `client_errors` table — log extraction failures
- `lib/core/services/hive_service.dart` — `coachBox` already opened

---

## Task 1 — Migration 027: `coach_memory` table

**Files:**
- Create: `supabase/migrations/027_create_coach_memory.sql`

- [ ] **Step 1: Create the migration file**

```sql
-- supabase/migrations/027_create_coach_memory.sql
-- Creates coach_memory table for AI coach personalization (Layers 4 + 5).
-- One row per user. Backfilled from legacy user_preferences.coaching_notes.

CREATE TABLE IF NOT EXISTS public.coach_memory (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,

  -- Layer 5: Identity mirroring
  preferred_name        text,
  communication_style   text CHECK (communication_style IN ('hinglish','english','formal','casual')),
  humor_tolerance       text CHECK (humor_tolerance IN ('high','low','none')),
  depth_preference      text CHECK (depth_preference IN ('explanation_seeker','action_taker')),
  motivation_style      text CHECK (motivation_style IN ('tough_love','gentle','data_driven')),

  -- Layer 2: Behavioral (backfilled from existing extraction)
  injuries              jsonb DEFAULT '[]'::jsonb,
  food_preferences      jsonb DEFAULT '{}'::jsonb,
  equipment_notes       text,
  excuse_patterns       jsonb DEFAULT '[]'::jsonb,
  lifestyle             jsonb DEFAULT '{}'::jsonb,
  supplement_stack      jsonb DEFAULT '[]'::jsonb,
  peak_activity_hour    int CHECK (peak_activity_hour BETWEEN 0 AND 23),
  weak_day              text CHECK (weak_day IN ('mon','tue','wed','thu','fri','sat','sun')),
  cheat_day_pattern     text,

  -- Layer 4: Predictive signals
  dropout_risk_score        real CHECK (dropout_risk_score BETWEEN 0 AND 1),
  plateau_risk_score        real CHECK (plateau_risk_score BETWEEN 0 AND 1),
  pro_upgrade_probability   real CHECK (pro_upgrade_probability BETWEEN 0 AND 1),
  signals_computed_at       timestamptz,

  -- Operational
  last_proactive_type   text,
  last_extraction_at    timestamptz,
  consent_version       text DEFAULT 'v1',
  private_mode          boolean NOT NULL DEFAULT false,
  coach_notes           text,  -- free-form, NEVER used for training
  updated_at            timestamptz NOT NULL DEFAULT now()
);

-- Indexes for cron job iteration over active users.
CREATE INDEX IF NOT EXISTS idx_coach_memory_signals_computed_at
  ON public.coach_memory (signals_computed_at NULLS FIRST);

CREATE INDEX IF NOT EXISTS idx_coach_memory_dropout_risk
  ON public.coach_memory (dropout_risk_score DESC NULLS LAST);

-- RLS
ALTER TABLE public.coach_memory ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_read_own_coach_memory" ON public.coach_memory
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "users_update_own_coach_memory" ON public.coach_memory
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "users_insert_own_coach_memory" ON public.coach_memory
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Service role bypasses RLS automatically (used by Edge Functions).

-- Auto-update updated_at on any change.
CREATE OR REPLACE FUNCTION public.touch_coach_memory_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_coach_memory_touch
  BEFORE UPDATE ON public.coach_memory
  FOR EACH ROW EXECUTE FUNCTION public.touch_coach_memory_updated_at();

COMMENT ON TABLE public.coach_memory IS
  'AI coach personalization — identity mirroring + predictive signals. One row per user. coach_notes column is NEVER used as training data.';
```

- [ ] **Step 2: Create a Supabase branch (sandbox), apply migration, verify**

Use the Supabase MCP tool — DO NOT use the `supabase` CLI (it's logged into the wrong account per CLAUDE.md §2a).

```
mcp__ba7b5e8e__create_branch  project_id="dedsavbjuwgarrhphgnl"  confirm_cost_id=<from get_cost>  name="coach-memory-027"
```

Capture the returned branch project_id. Then apply migration:

```
mcp__ba7b5e8e__apply_migration  project_id=<branch_project_id>  name="027_create_coach_memory"  query=<contents of 027_create_coach_memory.sql>
```

Verify:

```
mcp__ba7b5e8e__list_tables  project_id=<branch_project_id>  schemas=["public"]
```

Expected: `coach_memory` appears in the list with all columns from the migration.

- [ ] **Step 3: Sanity-check RLS by running a SELECT as anon**

```
mcp__ba7b5e8e__execute_sql  project_id=<branch_project_id>  query="SELECT count(*) FROM public.coach_memory;"
```

Expected: returns 0 (table empty, no error). Then check advisors:

```
mcp__ba7b5e8e__get_advisors  project_id=<branch_project_id>  type="security"
```

Expected: no critical findings on `coach_memory` (the table has RLS enabled).

- [ ] **Step 4: Commit migration**

```bash
git add supabase/migrations/027_create_coach_memory.sql
git commit -m "feat(db): add coach_memory table for AI personalization

Layers 4+5 storage — identity mirroring + predictive signals.
Migration applied to dev branch only; production deferred until
end-to-end verification passes.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 2 — Shared Edge Function helper `_shared/coach_memory.ts`

**Files:**
- Create: `supabase/functions/_shared/coach_memory.ts`

- [ ] **Step 1: Write the helper module**

```ts
// supabase/functions/_shared/coach_memory.ts
// Shared accessors for the coach_memory table. Used by ai-proxy,
// daily-snapshot, compute-coach-signals, morning-alert.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface CoachMemory {
  user_id: string;
  preferred_name: string | null;
  communication_style: "hinglish" | "english" | "formal" | "casual" | null;
  humor_tolerance: "high" | "low" | "none" | null;
  depth_preference: "explanation_seeker" | "action_taker" | null;
  motivation_style: "tough_love" | "gentle" | "data_driven" | null;
  injuries: unknown[];
  food_preferences: Record<string, unknown>;
  equipment_notes: string | null;
  excuse_patterns: unknown[];
  lifestyle: Record<string, unknown>;
  supplement_stack: unknown[];
  peak_activity_hour: number | null;
  weak_day: string | null;
  cheat_day_pattern: string | null;
  dropout_risk_score: number | null;
  plateau_risk_score: number | null;
  pro_upgrade_probability: number | null;
  signals_computed_at: string | null;
  last_proactive_type: string | null;
  last_extraction_at: string | null;
  consent_version: string;
  private_mode: boolean;
  coach_notes: string | null;
  updated_at: string;
}

export type CoachMemoryPatch = Partial<Omit<CoachMemory, "user_id" | "updated_at">>;

export async function fetchCoachMemory(
  supabase: ReturnType<typeof createClient>,
  userId: string,
): Promise<CoachMemory | null> {
  const { data, error } = await supabase
    .from("coach_memory")
    .select("*")
    .eq("user_id", userId)
    .maybeSingle();
  if (error) {
    console.error("[coach_memory.fetch] error:", error.message);
    return null;
  }
  return (data as CoachMemory) ?? null;
}

export async function upsertCoachMemory(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  patch: CoachMemoryPatch,
): Promise<void> {
  // Strip undefined so we don't overwrite existing values with NULL.
  const cleanPatch: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(patch)) {
    if (v !== undefined) cleanPatch[k] = v;
  }
  if (Object.keys(cleanPatch).length === 0) return;

  const { error } = await supabase
    .from("coach_memory")
    .upsert({ user_id: userId, ...cleanPatch }, { onConflict: "user_id" });
  if (error) {
    console.error("[coach_memory.upsert] error:", error.message);
    throw error;
  }
}

/**
 * Renders the coach_memory row as a system-prompt fragment (block [3]
 * of the 7-block context layout). Returns empty string when row is null
 * or private_mode is on.
 */
export function renderCoachMemoryBlock(mem: CoachMemory | null): string {
  if (!mem || mem.private_mode) return "";

  const lines: string[] = ["[3] COACH MEMORY"];
  if (mem.preferred_name) lines.push(`- The user prefers to be called "${mem.preferred_name}".`);
  if (mem.communication_style) {
    lines.push(`- They communicate in ${mem.communication_style} — mirror that tone.`);
  }
  if (mem.depth_preference) {
    const guidance = mem.depth_preference === "action_taker"
      ? "keep replies short and action-focused"
      : "include the why and brief reasoning";
    lines.push(`- They are an ${mem.depth_preference} — ${guidance}.`);
  }
  if (mem.motivation_style) {
    const tone = {
      tough_love: "be direct, no soft padding",
      gentle: "be warm and validating before suggesting",
      data_driven: "lead with the number, then the suggestion",
    }[mem.motivation_style];
    lines.push(`- Motivation style: ${mem.motivation_style} — ${tone}.`);
  }
  if (mem.dropout_risk_score !== null && mem.dropout_risk_score >= 0.5) {
    lines.push(`- Risk: dropout_risk=${mem.dropout_risk_score.toFixed(2)} (be encouraging, do not pile on demands).`);
  }
  if (mem.plateau_risk_score !== null && mem.plateau_risk_score >= 0.5) {
    lines.push(`- Risk: plateau_risk=${mem.plateau_risk_score.toFixed(2)} (acknowledge if user mentions weight stuck).`);
  }
  if (mem.injuries && Array.isArray(mem.injuries) && mem.injuries.length > 0) {
    lines.push(`- Active injuries: ${JSON.stringify(mem.injuries)}.`);
  }
  if (mem.last_proactive_type) {
    lines.push(`- Last proactive nudge sent today: ${mem.last_proactive_type} — do not repeat this type.`);
  }
  return lines.join("\n");
}
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/_shared/coach_memory.ts
git commit -m "feat(edge): add shared coach_memory helpers

fetchCoachMemory + upsertCoachMemory + renderCoachMemoryBlock —
consumed by ai-proxy, daily-snapshot, compute-coach-signals, morning-alert.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3 — Dart `CoachMemory` model (no Hive adapter)

The repo stores everything in `coachBox` as `Map<dynamic, dynamic>` — no `@HiveType` adapters anywhere (verified in `lib/core/services/hive_service.dart:60-63`). So `CoachMemory` is a plain data class with `toJson` / `fromJson` and Hive read/write helpers.

**Files:**
- Create: `lib/features/ai_coach/models/coach_memory.dart`
- Test: `test/ai_coach/coach_memory_model_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ai_coach/coach_memory_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/models/coach_memory.dart';

void main() {
  group('CoachMemory', () {
    test('round-trips through JSON', () {
      final original = CoachMemory(
        userId: 'u1',
        preferredName: 'Upen',
        communicationStyle: 'hinglish',
        depthPreference: 'action_taker',
        motivationStyle: 'data_driven',
        injuries: [{'part': 'shoulder', 'severity': 'mild'}],
        dropoutRiskScore: 0.42,
        privateMode: false,
      );
      final decoded = CoachMemory.fromJson(original.toJson());
      expect(decoded.preferredName, 'Upen');
      expect(decoded.communicationStyle, 'hinglish');
      expect(decoded.dropoutRiskScore, closeTo(0.42, 0.001));
      expect(decoded.injuries, hasLength(1));
    });

    test('fromJson handles null and missing fields', () {
      final mem = CoachMemory.fromJson({'user_id': 'u1'});
      expect(mem.userId, 'u1');
      expect(mem.preferredName, isNull);
      expect(mem.privateMode, isFalse);
      expect(mem.injuries, isEmpty);
    });

    test('merge() overwrites only non-null fields', () {
      final base = CoachMemory(userId: 'u1', preferredName: 'Upen');
      final patch = CoachMemory(userId: 'u1', communicationStyle: 'hinglish');
      final merged = base.merge(patch);
      expect(merged.preferredName, 'Upen');
      expect(merged.communicationStyle, 'hinglish');
    });
  });
}
```

- [ ] **Step 2: Run test to verify FAIL**

```bash
flutter test test/ai_coach/coach_memory_model_test.dart
```

Expected: FAIL — "Target of URI doesn't exist".

- [ ] **Step 3: Implement the model**

```dart
// lib/features/ai_coach/models/coach_memory.dart
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';

/// Structured coach memory — Layer 4 (predictive) + Layer 5 (identity).
///
/// Stored locally as a JSON map at coachBox['coach_memory'] (no Hive
/// adapter — repo uses Map storage). Mirrored to Supabase coach_memory
/// table via daily-snapshot round-trip.
class CoachMemory {
  CoachMemory({
    required this.userId,
    this.preferredName,
    this.communicationStyle,
    this.humorTolerance,
    this.depthPreference,
    this.motivationStyle,
    List<dynamic>? injuries,
    Map<String, dynamic>? foodPreferences,
    this.equipmentNotes,
    List<dynamic>? excusePatterns,
    Map<String, dynamic>? lifestyle,
    List<dynamic>? supplementStack,
    this.peakActivityHour,
    this.weakDay,
    this.cheatDayPattern,
    this.dropoutRiskScore,
    this.plateauRiskScore,
    this.proUpgradeProbability,
    this.signalsComputedAt,
    this.lastProactiveType,
    this.lastExtractionAt,
    this.consentVersion = 'v1',
    this.privateMode = false,
    this.coachNotes,
    this.updatedAt,
  })  : injuries = injuries ?? const [],
        foodPreferences = foodPreferences ?? const {},
        excusePatterns = excusePatterns ?? const [],
        lifestyle = lifestyle ?? const {},
        supplementStack = supplementStack ?? const [];

  final String userId;
  final String? preferredName;
  final String? communicationStyle;
  final String? humorTolerance;
  final String? depthPreference;
  final String? motivationStyle;
  final List<dynamic> injuries;
  final Map<String, dynamic> foodPreferences;
  final String? equipmentNotes;
  final List<dynamic> excusePatterns;
  final Map<String, dynamic> lifestyle;
  final List<dynamic> supplementStack;
  final int? peakActivityHour;
  final String? weakDay;
  final String? cheatDayPattern;
  final double? dropoutRiskScore;
  final double? plateauRiskScore;
  final double? proUpgradeProbability;
  final DateTime? signalsComputedAt;
  final String? lastProactiveType;
  final DateTime? lastExtractionAt;
  final String consentVersion;
  final bool privateMode;
  final String? coachNotes;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        if (preferredName != null) 'preferred_name': preferredName,
        if (communicationStyle != null) 'communication_style': communicationStyle,
        if (humorTolerance != null) 'humor_tolerance': humorTolerance,
        if (depthPreference != null) 'depth_preference': depthPreference,
        if (motivationStyle != null) 'motivation_style': motivationStyle,
        'injuries': injuries,
        'food_preferences': foodPreferences,
        if (equipmentNotes != null) 'equipment_notes': equipmentNotes,
        'excuse_patterns': excusePatterns,
        'lifestyle': lifestyle,
        'supplement_stack': supplementStack,
        if (peakActivityHour != null) 'peak_activity_hour': peakActivityHour,
        if (weakDay != null) 'weak_day': weakDay,
        if (cheatDayPattern != null) 'cheat_day_pattern': cheatDayPattern,
        if (dropoutRiskScore != null) 'dropout_risk_score': dropoutRiskScore,
        if (plateauRiskScore != null) 'plateau_risk_score': plateauRiskScore,
        if (proUpgradeProbability != null) 'pro_upgrade_probability': proUpgradeProbability,
        if (signalsComputedAt != null) 'signals_computed_at': signalsComputedAt!.toIso8601String(),
        if (lastProactiveType != null) 'last_proactive_type': lastProactiveType,
        if (lastExtractionAt != null) 'last_extraction_at': lastExtractionAt!.toIso8601String(),
        'consent_version': consentVersion,
        'private_mode': privateMode,
        if (coachNotes != null) 'coach_notes': coachNotes,
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };

  factory CoachMemory.fromJson(Map<dynamic, dynamic> json) {
    DateTime? parseTs(dynamic v) =>
        v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;
    double? parseDouble(dynamic v) =>
        v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

    return CoachMemory(
      userId: (json['user_id'] ?? '') as String,
      preferredName: json['preferred_name'] as String?,
      communicationStyle: json['communication_style'] as String?,
      humorTolerance: json['humor_tolerance'] as String?,
      depthPreference: json['depth_preference'] as String?,
      motivationStyle: json['motivation_style'] as String?,
      injuries: (json['injuries'] as List?)?.toList() ?? const [],
      foodPreferences: Map<String, dynamic>.from(
          (json['food_preferences'] as Map?) ?? const {}),
      equipmentNotes: json['equipment_notes'] as String?,
      excusePatterns: (json['excuse_patterns'] as List?)?.toList() ?? const [],
      lifestyle: Map<String, dynamic>.from(
          (json['lifestyle'] as Map?) ?? const {}),
      supplementStack: (json['supplement_stack'] as List?)?.toList() ?? const [],
      peakActivityHour: json['peak_activity_hour'] as int?,
      weakDay: json['weak_day'] as String?,
      cheatDayPattern: json['cheat_day_pattern'] as String?,
      dropoutRiskScore: parseDouble(json['dropout_risk_score']),
      plateauRiskScore: parseDouble(json['plateau_risk_score']),
      proUpgradeProbability: parseDouble(json['pro_upgrade_probability']),
      signalsComputedAt: parseTs(json['signals_computed_at']),
      lastProactiveType: json['last_proactive_type'] as String?,
      lastExtractionAt: parseTs(json['last_extraction_at']),
      consentVersion: (json['consent_version'] as String?) ?? 'v1',
      privateMode: (json['private_mode'] as bool?) ?? false,
      coachNotes: json['coach_notes'] as String?,
      updatedAt: parseTs(json['updated_at']),
    );
  }

  /// Returns a new CoachMemory with non-null fields from [patch] overlaid
  /// on top of this instance.
  CoachMemory merge(CoachMemory patch) => CoachMemory(
        userId: userId,
        preferredName: patch.preferredName ?? preferredName,
        communicationStyle: patch.communicationStyle ?? communicationStyle,
        humorTolerance: patch.humorTolerance ?? humorTolerance,
        depthPreference: patch.depthPreference ?? depthPreference,
        motivationStyle: patch.motivationStyle ?? motivationStyle,
        injuries: patch.injuries.isNotEmpty ? patch.injuries : injuries,
        foodPreferences: patch.foodPreferences.isNotEmpty
            ? patch.foodPreferences
            : foodPreferences,
        equipmentNotes: patch.equipmentNotes ?? equipmentNotes,
        excusePatterns: patch.excusePatterns.isNotEmpty
            ? patch.excusePatterns
            : excusePatterns,
        lifestyle: patch.lifestyle.isNotEmpty ? patch.lifestyle : lifestyle,
        supplementStack: patch.supplementStack.isNotEmpty
            ? patch.supplementStack
            : supplementStack,
        peakActivityHour: patch.peakActivityHour ?? peakActivityHour,
        weakDay: patch.weakDay ?? weakDay,
        cheatDayPattern: patch.cheatDayPattern ?? cheatDayPattern,
        dropoutRiskScore: patch.dropoutRiskScore ?? dropoutRiskScore,
        plateauRiskScore: patch.plateauRiskScore ?? plateauRiskScore,
        proUpgradeProbability:
            patch.proUpgradeProbability ?? proUpgradeProbability,
        signalsComputedAt: patch.signalsComputedAt ?? signalsComputedAt,
        lastProactiveType: patch.lastProactiveType ?? lastProactiveType,
        lastExtractionAt: patch.lastExtractionAt ?? lastExtractionAt,
        consentVersion: patch.consentVersion,
        privateMode: patch.privateMode,
        coachNotes: patch.coachNotes ?? coachNotes,
        updatedAt: patch.updatedAt ?? updatedAt,
      );

  /// Hive read helper. Returns null when the key is absent.
  static CoachMemory? readFromBox(Box box) {
    final raw = box.get('coach_memory');
    if (raw is Map) return CoachMemory.fromJson(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        return CoachMemory.fromJson(json.decode(raw) as Map);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Hive write helper.
  Future<void> writeToBox(Box box) => box.put('coach_memory', toJson());
}
```

- [ ] **Step 4: Run test to verify PASS**

```bash
flutter test test/ai_coach/coach_memory_model_test.dart
```

Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/ai_coach/models/coach_memory.dart test/ai_coach/coach_memory_model_test.dart
git commit -m "feat(ai_coach): CoachMemory model with Hive read/write helpers

Plain Dart data class — no Hive adapter (repo uses Map storage).
toJson/fromJson round-trip + merge() for patch application.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 4 — Backfill helper in `AiCoachRepository`

When the user first launches a build with this feature, migrate the legacy `coachBox['coaching_notes']` (a list of free-text strings, max 20) into `coach_memory.coach_notes`.

**Files:**
- Modify: `lib/features/ai_coach/repositories/ai_coach_repository.dart`
- Test: `test/ai_coach/coach_memory_backfill_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ai_coach/coach_memory_backfill_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/features/ai_coach/models/coach_memory.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

void main() {
  setUp(() async {
    Hive.init('./.test_hive');
    await Hive.openBox('coachBox');
    await Hive.openBox('userBox');
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk('coachBox');
    await Hive.deleteBoxFromDisk('userBox');
  });

  test('backfill copies legacy coaching_notes into coach_memory.coach_notes', () async {
    final box = Hive.box('coachBox');
    await box.put('coaching_notes', {
      'notes': ['Mentioned shoulder pain', 'Wants to lose weight'],
      'last_extracted': '2026-04-15T22:00:00Z',
    });
    Hive.box('userBox').put('user_id', 'u1');

    await AiCoachRepository.instance.backfillCoachMemoryIfNeeded();

    final mem = CoachMemory.readFromBox(box);
    expect(mem, isNotNull);
    expect(mem!.coachNotes, contains('shoulder'));
    expect(mem.coachNotes, contains('lose weight'));
  });

  test('backfill is idempotent — second call is a no-op', () async {
    final box = Hive.box('coachBox');
    await box.put('coaching_notes', {'notes': ['a']});
    Hive.box('userBox').put('user_id', 'u1');

    await AiCoachRepository.instance.backfillCoachMemoryIfNeeded();
    final firstUpdated =
        CoachMemory.readFromBox(box)?.updatedAt ?? DateTime(2000);

    await Future.delayed(const Duration(milliseconds: 10));
    await AiCoachRepository.instance.backfillCoachMemoryIfNeeded();
    final secondUpdated =
        CoachMemory.readFromBox(box)?.updatedAt ?? DateTime(2000);

    expect(secondUpdated, equals(firstUpdated));
  });

  test('backfill no-ops when coach_memory already exists', () async {
    final box = Hive.box('coachBox');
    await CoachMemory(userId: 'u1', preferredName: 'Upen').writeToBox(box);
    await box.put('coaching_notes', {'notes': ['should be ignored']});

    await AiCoachRepository.instance.backfillCoachMemoryIfNeeded();

    expect(CoachMemory.readFromBox(box)!.preferredName, 'Upen');
    expect(CoachMemory.readFromBox(box)!.coachNotes, isNull);
  });
}
```

- [ ] **Step 2: Run test to verify FAIL**

```bash
flutter test test/ai_coach/coach_memory_backfill_test.dart
```

Expected: FAIL — `backfillCoachMemoryIfNeeded` is not defined.

- [ ] **Step 3: Add the backfill method to `AiCoachRepository`**

Locate `lib/features/ai_coach/repositories/ai_coach_repository.dart`, add this method (place after `extractCoachingNotes()`, around line 416):

```dart
  /// One-time migration: convert legacy coachBox['coaching_notes'] string
  /// list into coach_memory.coach_notes. Idempotent — no-op if coach_memory
  /// already exists in Hive.
  Future<void> backfillCoachMemoryIfNeeded() async {
    final coachBox = Hive.box('coachBox');
    if (CoachMemory.readFromBox(coachBox) != null) return;

    final userId = Hive.box('userBox').get('user_id') as String?;
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
    debugPrint('[AiCoachRepository] backfilled coach_memory from legacy coaching_notes');
  }
```

Add the import at the top of the file:

```dart
import '../models/coach_memory.dart';
```

- [ ] **Step 4: Wire backfill into app startup**

Locate `lib/main.dart` — find where `HiveService.instance.init()` finishes (around line 41-43). Add immediately after, but BEFORE `runApp(...)`:

```dart
  // One-time backfill of coach_memory from legacy coaching_notes.
  // Safe to call on every launch — idempotent.
  await AiCoachRepository.instance.backfillCoachMemoryIfNeeded();
```

Add the import:

```dart
import 'features/ai_coach/repositories/ai_coach_repository.dart';
```

- [ ] **Step 5: Run test to verify PASS**

```bash
flutter test test/ai_coach/coach_memory_backfill_test.dart
```

Expected: All 3 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/ai_coach/repositories/ai_coach_repository.dart lib/main.dart test/ai_coach/coach_memory_backfill_test.dart
git commit -m "feat(ai_coach): backfill legacy coaching_notes into coach_memory

Idempotent migration — runs once at app launch after Hive init.
Coverage: legacy notes copy, idempotency, no-op when memory exists.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 5 — `IdentitySignalDetector` (heuristics + tests)

Cheap, instant detection of Hinglish + preferred name on every send. Sticky by default (only switches after 3 consecutive same-style messages) to avoid flip-flopping on a single Romanized English word.

**Files:**
- Create: `lib/features/ai_coach/services/identity_signal_detector.dart`
- Test: `test/ai_coach/identity_signal_detector_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ai_coach/identity_signal_detector_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/features/ai_coach/services/identity_signal_detector.dart';

void main() {
  late IdentitySignalDetector det;

  setUp(() => det = IdentitySignalDetector());

  group('Hinglish detection', () {
    test('pure English does NOT flip style', () {
      final s = det.detect('What should I eat for dinner today?');
      expect(s.communicationStyle, isNull);
    });

    test('single Hinglish message alone does not flip (sticky)', () {
      final s = det.detect('yaar today bench dabaya');
      expect(s.communicationStyle, isNull);
    });

    test('three consecutive Hinglish messages flip to hinglish', () {
      det.detect('yaar today bench dabaya');
      det.detect('bhai mera workout kaisa raha');
      final s = det.detect('aaj kya khaaun bata');
      expect(s.communicationStyle, equals('hinglish'));
    });

    test('Devanagari script triggers hinglish on first message', () {
      final s = det.detect('आज वर्कआउट कैसा रहा');
      expect(s.communicationStyle, equals('hinglish'));
    });

    test('one-word match (e.g. "yaar") in English sentence does NOT count as Hinglish', () {
      final s = det.detect('I want to bulk yaar');
      // Only one Hindi-stem word — needs >= 2.
      expect(s.communicationStyle, isNull);
    });
  });

  group('preferred name detection', () {
    test('"call me Upen" extracts preferred name', () {
      final s = det.detect('call me Upen');
      expect(s.preferredName, equals('Upen'));
    });

    test('"my name is Upendra" extracts preferred name', () {
      final s = det.detect('my name is Upendra');
      expect(s.preferredName, equals('Upendra'));
    });

    test('"I\'m Upen" extracts preferred name', () {
      final s = det.detect("I'm Upen");
      expect(s.preferredName, equals('Upen'));
    });

    test('no name pattern returns null', () {
      final s = det.detect('what is my macros today');
      expect(s.preferredName, isNull);
    });

    test('rejects names < 2 chars or > 20 chars', () {
      expect(det.detect('call me X').preferredName, isNull);
      expect(det.detect('call me ${"a" * 25}').preferredName, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify FAIL**

```bash
flutter test test/ai_coach/identity_signal_detector_test.dart
```

Expected: FAIL — class not defined.

- [ ] **Step 3: Implement the detector**

```dart
// lib/features/ai_coach/services/identity_signal_detector.dart

/// Result of analyzing a single user message for identity signals.
class IdentitySignals {
  const IdentitySignals({this.communicationStyle, this.preferredName});
  final String? communicationStyle; // 'hinglish' if flipped this turn
  final String? preferredName;
}

/// Cheap, on-device identity heuristics. Stateful — sticky communication
/// style avoids flipping on a single Romanized English word.
class IdentitySignalDetector {
  // Common Hindi-stem words used in casual Indian English (Hinglish).
  // Detection requires >= 2 of these for one message to count toward
  // the streak. Devanagari script alone always counts.
  static const _hinglishStems = {
    'yaar', 'bhai', 'bro', 'haan', 'nahi', 'kya', 'kaise', 'kaisa',
    'kar', 'karo', 'karna', 'mera', 'tera', 'aaj', 'kal', 'abhi',
    'main', 'mere', 'tum', 'aap', 'bata', 'batao', 'dekh', 'dekho',
    'chal', 'chalo', 'thoda', 'bahut', 'matlab', 'samajh', 'theek',
    'sahi', 'galat', 'achha', 'bura', 'dabaya', 'lagta', 'lagti',
    'khaaun', 'khana', 'pina', 'hua', 'hui', 'tha', 'thi',
  };

  static final _devanagari = RegExp(r'[\u0900-\u097F]');
  static final _wordBoundary = RegExp(r"[a-zA-Z\u0900-\u097F']+");

  static final _namePatterns = <RegExp>[
    RegExp(r"\bcall me ([A-Z][a-zA-Z]{1,19})\b"),
    RegExp(r"\bmy name is ([A-Z][a-zA-Z]{1,19})\b"),
    RegExp(r"\bi['']m ([A-Z][a-zA-Z]{1,19})\b", caseSensitive: false),
    RegExp(r"\bi am ([A-Z][a-zA-Z]{1,19})\b", caseSensitive: false),
  ];

  static const _stickyThreshold = 3;
  int _hinglishStreak = 0;

  IdentitySignals detect(String message) {
    return IdentitySignals(
      communicationStyle: _detectCommunicationStyle(message),
      preferredName: _detectPreferredName(message),
    );
  }

  String? _detectCommunicationStyle(String message) {
    final hasDevanagari = _devanagari.hasMatch(message);
    if (hasDevanagari) {
      _hinglishStreak = _stickyThreshold; // immediate flip
      return 'hinglish';
    }

    final words = _wordBoundary
        .allMatches(message.toLowerCase())
        .map((m) => m.group(0)!)
        .toList();
    final hits = words.where(_hinglishStems.contains).length;

    if (hits >= 2) {
      _hinglishStreak++;
      if (_hinglishStreak >= _stickyThreshold) return 'hinglish';
    } else {
      _hinglishStreak = 0;
    }
    return null;
  }

  String? _detectPreferredName(String message) {
    for (final pattern in _namePatterns) {
      final match = pattern.firstMatch(message);
      if (match != null) {
        final name = match.group(1);
        if (name != null && name.length >= 2 && name.length <= 20) {
          return name;
        }
      }
    }
    return null;
  }

  /// For test reset only.
  void resetStreak() => _hinglishStreak = 0;
}
```

- [ ] **Step 4: Run test to verify PASS**

```bash
flutter test test/ai_coach/identity_signal_detector_test.dart
```

Expected: All 10 tests PASS.

- [ ] **Step 5: Wire detector into the message-send path**

In `lib/features/ai_coach/repositories/ai_coach_repository.dart`, add a private detector instance and a `detectAndPersistIdentitySignals` method. Locate the existing `sendMessage` flow (find where the user message is persisted via `saveUserMessagePending`) and call detection right before:

```dart
// Add to imports
import '../services/identity_signal_detector.dart';

// Add as instance field on the repository class
final IdentitySignalDetector _identityDetector = IdentitySignalDetector();

/// Runs the identity heuristics on a single user message and patches
/// Hive coach_memory in place. No-op if no signals detected.
void detectAndPersistIdentitySignals(String userMessage) {
  final signals = _identityDetector.detect(userMessage);
  if (signals.communicationStyle == null && signals.preferredName == null) return;

  final coachBox = Hive.box('coachBox');
  final userId = Hive.box('userBox').get('user_id') as String?;
  if (userId == null || userId.isEmpty) return;

  final existing = CoachMemory.readFromBox(coachBox) ?? CoachMemory(userId: userId);
  final patched = existing.merge(CoachMemory(
    userId: userId,
    communicationStyle: signals.communicationStyle,
    preferredName: signals.preferredName,
    updatedAt: DateTime.now(),
  ));
  patched.writeToBox(coachBox);
}
```

Then call it from inside `saveUserMessagePending` (or wherever the user's outbound message is first persisted — search for `saveUserMessagePending` to find the exact line).

- [ ] **Step 6: Commit**

```bash
git add lib/features/ai_coach/services/identity_signal_detector.dart \
        lib/features/ai_coach/repositories/ai_coach_repository.dart \
        test/ai_coach/identity_signal_detector_test.dart
git commit -m "feat(ai_coach): identity signal detector (Hinglish + preferred name)

Sticky communication-style detection (3-message streak threshold) +
regex-based name extraction. Wired into sendMessage path; updates
Hive coach_memory in place.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 6 — `buildAiContext` emits `coach_memory` block

**Files:**
- Modify: `lib/features/ai_coach/repositories/ai_coach_repository.dart`

- [ ] **Step 1: Write the failing test**

```dart
// Append to test/ai_coach/coach_memory_backfill_test.dart (same setUp)
test('buildAiContext includes coach_memory when present in Hive', () async {
  Hive.box('userBox').put('user_id', 'u1');
  await CoachMemory(
    userId: 'u1',
    preferredName: 'Upen',
    communicationStyle: 'hinglish',
    dropoutRiskScore: 0.6,
  ).writeToBox(Hive.box('coachBox'));

  final ctx = AiCoachRepository.instance.buildAiContext();
  expect(ctx['coach_memory'], isNotNull);
  expect(ctx['coach_memory']['preferred_name'], equals('Upen'));
  expect(ctx['coach_memory']['communication_style'], equals('hinglish'));
});

test('buildAiContext omits coach_memory when private_mode is true', () async {
  Hive.box('userBox').put('user_id', 'u1');
  await CoachMemory(userId: 'u1', preferredName: 'Upen', privateMode: true)
      .writeToBox(Hive.box('coachBox'));

  final ctx = AiCoachRepository.instance.buildAiContext();
  expect(ctx['coach_memory'], isNull);
});
```

- [ ] **Step 2: Run test to verify FAIL**

```bash
flutter test test/ai_coach/coach_memory_backfill_test.dart
```

Expected: FAIL — `buildAiContext` does not yet include `coach_memory`.

- [ ] **Step 3: Modify `buildAiContext()`**

In `lib/features/ai_coach/repositories/ai_coach_repository.dart`, locate the return Map at lines 28-65. Insert this entry between `'coaching_notes'` and `'fitness_summary'` (so trim order from Task 7 lands correctly):

```dart
      'coach_memory': _getCoachMemoryForContext(),
```

Then add the helper method below the existing `_getCoachingNotes()` private method:

```dart
  /// Returns the coach_memory JSON snapshot for context injection, or
  /// null when private_mode is on / no memory exists.
  Map<String, dynamic>? _getCoachMemoryForContext() {
    final mem = CoachMemory.readFromBox(Hive.box('coachBox'));
    if (mem == null || mem.privateMode) return null;
    return mem.toJson();
  }
```

- [ ] **Step 4: Run test to verify PASS**

```bash
flutter test test/ai_coach/coach_memory_backfill_test.dart
```

Expected: All tests PASS (including the 2 new ones).

- [ ] **Step 5: Commit**

```bash
git add lib/features/ai_coach/repositories/ai_coach_repository.dart \
        test/ai_coach/coach_memory_backfill_test.dart
git commit -m "feat(ai_coach): inject coach_memory into AI context

buildAiContext now emits a 'coach_memory' block. private_mode
short-circuits to null so PRO users opted out are never included.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 7 — `_compactContext` keeps `coach_memory` above the trim line

`coach_memory` is small (~800 bytes max) and load-bearing for personalization, so it must survive trimming. Slot it after `coach_notices` in the drop order (i.e., never dropped by the routine trim — only the final last-resort `fitness_summary` drop precedes it for completeness).

**Files:**
- Modify: `lib/core/services/ai_service.dart`
- Test: `test/ai_coach/coach_memory_compaction_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/ai_coach/coach_memory_compaction_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/ai_service.dart';

void main() {
  test('_compactContext keeps coach_memory when total exceeds 9.5KB', () {
    // Build a context that exceeds 9.5KB through padding fields that are
    // in the trim list, plus a coach_memory block we want to survive.
    final padding = List.generate(200, (i) => {'k$i': 'v$i' * 30});
    final ctx = {
      'profile': {'name': 'Upen', 'goal': 'fat_loss'},
      'coach_memory': {
        'preferred_name': 'Upen',
        'communication_style': 'hinglish',
      },
      'step_history_7d': padding,
      'weight_trend': padding,
      'nutrition_trend': padding,
      'exercise_history': padding,
      'personal_records': padding,
      'coach_notices': padding,
      'coaching_notes': 'a' * 5000,
      'fitness_summary': 'b' * 1000,
    };
    expect(json.encode(ctx).length, greaterThan(9500));

    final compact = AiService.compactForTest(ctx);
    expect(compact['coach_memory'], isNotNull,
        reason: 'coach_memory must survive aggressive trimming');
    expect(compact['coach_memory']['preferred_name'], equals('Upen'));
  });
}
```

- [ ] **Step 2: Run test to verify FAIL**

```bash
flutter test test/ai_coach/coach_memory_compaction_test.dart
```

Expected: FAIL — `compactForTest` not exposed yet (and even if exposed via existing private, the test wouldn't compile).

- [ ] **Step 3: Modify `_compactContext` and add a test seam**

In `lib/core/services/ai_service.dart`, add a static test seam under the existing `_compactContext` method (around line 130). The trim list itself does not need to change — `coach_memory` is already excluded from `trimSteps` by virtue of not being in the list, so the existing logic preserves it. Add only the test seam:

```dart
  /// Test-only seam exposing the private compaction routine.
  @visibleForTesting
  static Map<String, dynamic> compactForTest(Map<String, dynamic> ctx) {
    return AiService._instance._compactContext(ctx);
  }
```

Add the import at the top of `ai_service.dart`:

```dart
import 'package:flutter/foundation.dart';
```

(If already imported, skip.)

Verify the existing `trimSteps` list does NOT contain `'coach_memory'` and the post-trim cleanup never touches the key. (It already doesn't — confirmed lines 98-128.)

- [ ] **Step 4: Run test to verify PASS**

```bash
flutter test test/ai_coach/coach_memory_compaction_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/ai_service.dart test/ai_coach/coach_memory_compaction_test.dart
git commit -m "test(ai_service): verify coach_memory survives _compactContext

Adds @visibleForTesting compactForTest seam and proves coach_memory
is never trimmed even when the snapshot exceeds 9.5KB.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 8 — Extend `daily-snapshot` Gemini extraction

Add 5 new fields to the extraction JSON schema, write them to `coach_memory`, return the row in the response.

**Files:**
- Modify: `supabase/functions/daily-snapshot/index.ts`

- [ ] **Step 1: Extend the extraction prompt**

In `supabase/functions/daily-snapshot/index.ts`, replace the JSON schema in the extraction prompt (lines 70-80) with:

```ts
Return ONLY valid JSON (no markdown, no code fences). Include only fields that were explicitly mentioned:
{
  "diet_preference": "vegetarian|vegan|non_veg|keto|pescatarian",
  "injuries": ["knee","back","shoulder","hip","wrist","ankle"],
  "lifestyle_activity": "desk_job|lightly_active|very_active_job",
  "lifestyle_notes": "brief note on lifestyle context they mentioned",
  "food_preferences": "foods they like, dislike, or are allergic to",
  "schedule_constraints": "schedule constraints they mentioned (e.g. travels on Fridays)",
  "supplement_use": "supplements they mentioned taking",
  "motivation_notes": "motivation patterns, obstacles, or triggers they mentioned",
  "preferred_name": "name the user uses for themselves (e.g. 'Upen' if they say 'call me Upen')",
  "communication_style": "hinglish|english|formal|casual — based on the user's own language register",
  "humor_tolerance": "high|low|none — based on whether they joke back or stay serious",
  "depth_preference": "explanation_seeker|action_taker — do they ask 'why' (explanation_seeker) or just 'tell me what to do' (action_taker)",
  "motivation_style": "tough_love|gentle|data_driven — what kind of coaching tone landed best in this conversation"
}
```

Update the TypeScript `ExtractedFacts` interface near the top of the file to include these new optional string fields.

- [ ] **Step 2: Write a `coach_memory` upsert call after the existing merge**

In the same file, find `mergeCoachingNotes` (around line 114). After the existing `user_preferences.upsert` and `user_profile.upsert`, add a new helper `mergeCoachMemory`:

```ts
import { upsertCoachMemory, fetchCoachMemory } from "../_shared/coach_memory.ts";

async function mergeCoachMemoryFields(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  extracted: ExtractedFacts,
): Promise<void> {
  const patch: Record<string, unknown> = {};
  if (extracted.preferred_name) patch.preferred_name = extracted.preferred_name;
  if (extracted.communication_style) patch.communication_style = extracted.communication_style;
  if (extracted.humor_tolerance) patch.humor_tolerance = extracted.humor_tolerance;
  if (extracted.depth_preference) patch.depth_preference = extracted.depth_preference;
  if (extracted.motivation_style) patch.motivation_style = extracted.motivation_style;
  if (extracted.injuries) patch.injuries = extracted.injuries;
  if (extracted.food_preferences) patch.food_preferences = { raw: extracted.food_preferences };
  patch.last_extraction_at = new Date().toISOString();

  if (Object.keys(patch).length > 1) {
    await upsertCoachMemory(supabase, userId, patch);
  }
}
```

Then call `mergeCoachMemoryFields(supabase, userId, extracted)` immediately after `mergeCoachingNotes(...)` in the existing async extraction block.

- [ ] **Step 3: Return `coach_memory` in the success response**

Locate the success response builder (around line 268-278). Replace it with:

```ts
const memory = await fetchCoachMemory(supabase, userId);
return new Response(
  JSON.stringify({
    status: "success",
    snapshot_date: today,
    coaching_extracted: !!extracted,
    coach_memory: memory,
  }),
  { headers: { ...corsHeaders, "Content-Type": "application/json" } },
);
```

- [ ] **Step 4: Deploy to the Supabase branch**

```
mcp__ba7b5e8e__deploy_edge_function  project_id=<branch_project_id>  name="daily-snapshot"  files=[{name:"index.ts", content:<full file contents>}]
```

- [ ] **Step 5: Manual integration test**

Seed `ai_coach_interactions` on the branch with a few rows that include identity cues:

```
mcp__ba7b5e8e__execute_sql  project_id=<branch>  query="
INSERT INTO public.ai_coach_interactions (user_id, channel, user_message, ai_response, created_at)
VALUES
  ('<test-user-uuid>', 'app', 'yaar bata aaj kya khaaun, call me Upen', 'Sure Upen, ...', now()),
  ('<test-user-uuid>', 'app', 'just tell me what to do, no theory', 'Got it, ...', now()),
  ('<test-user-uuid>', 'app', 'bhai mera workout kaisa raha', 'Strong session, ...', now());
"
```

Invoke the function with a test JWT and verify response contains `coach_memory.preferred_name === 'Upen'`. Then check the table:

```
mcp__ba7b5e8e__execute_sql  project_id=<branch>  query="SELECT preferred_name, communication_style, depth_preference FROM coach_memory WHERE user_id = '<test-user-uuid>';"
```

Expected: row with `preferred_name='Upen'`, `communication_style='hinglish'`, `depth_preference='action_taker'`.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/daily-snapshot/index.ts
git commit -m "feat(daily-snapshot): extract Layer 5 identity fields → coach_memory

Extends Gemini JSON schema with preferred_name, communication_style,
humor_tolerance, depth_preference, motivation_style. Upserts to the
new coach_memory table and returns the row in the response so the
client can mirror it to Hive.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 9 — `SyncService.pushSnapshot()` mirrors `coach_memory` to Hive

**Files:**
- Modify: `lib/core/services/sync_service.dart`

- [ ] **Step 1: Find the response handling in `pushSnapshot`**

Open `lib/core/services/sync_service.dart`. Locate `pushSnapshot()` (around line 15). The current code calls the Edge Function and ignores the response body beyond status. Capture the response JSON and write `coach_memory` to Hive.

- [ ] **Step 2: Modify `pushSnapshot` to capture coach_memory**

Replace the response-handling block (find the line that POSTs to `daily-snapshot`) with:

```dart
final response = await Supabase.instance.client.functions.invoke(
  'daily-snapshot',
  body: {'snapshot_json': snapshot},
);

if (response.status == 200 && response.data is Map) {
  final data = response.data as Map;
  final memJson = data['coach_memory'];
  if (memJson is Map) {
    final mem = CoachMemory.fromJson(memJson);
    await mem.writeToBox(Hive.box('coachBox'));
    debugPrint('[SyncService.pushSnapshot] coach_memory mirrored to Hive');
  }
}
```

Add imports if missing:

```dart
import 'package:hive_flutter/hive_flutter.dart';
import '../../features/ai_coach/models/coach_memory.dart';
```

- [ ] **Step 3: Manual smoke test in dev build**

```bash
flutter run --dart-define-from-file=.env --flavor dev -t lib/main.dart
```

Trigger any nutrition or workout mutation (which fires `pushSnapshot` via fire-and-forget). Watch the console for `[SyncService.pushSnapshot] coach_memory mirrored to Hive`. Then via debug shell or hot reload, verify `Hive.box('coachBox').get('coach_memory')` returns a map.

- [ ] **Step 4: Commit**

```bash
git add lib/core/services/sync_service.dart
git commit -m "feat(sync): mirror coach_memory from snapshot response to Hive

pushSnapshot now reads coach_memory from the daily-snapshot response
and writes it to coachBox['coach_memory'], keeping client and server
in sync after every mutation.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 10 — `ai-proxy` server-side merge of `coach_memory`

**Files:**
- Modify: `supabase/functions/ai-proxy/index.ts`

- [ ] **Step 1: Import the helper and fetch the row after auth**

At the top of `supabase/functions/ai-proxy/index.ts`, add:

```ts
import { fetchCoachMemory, renderCoachMemoryBlock } from "../_shared/coach_memory.ts";
```

Locate the place where `auth.getUser(token)` resolves and `userId` becomes available (search for `auth.getUser`). Immediately after, add:

```ts
const coachMemory = await fetchCoachMemory(supabase, userId);
const coachMemoryBlock = renderCoachMemoryBlock(coachMemory);
```

- [ ] **Step 2: Inject the block into the Gemini system prompt**

Find where the system prompt is assembled (search for the existing `systemPrompt:` argument in the `geminiChat(...)` call). Prepend or append `coachMemoryBlock` so Gemini sees it before the user's message. Recommended placement: right before the existing snapshot JSON injection (so the structured personalization rules govern interpretation of the snapshot).

```ts
const systemPrompt = [
  EXISTING_BASE_SYSTEM_PROMPT,
  coachMemoryBlock,
  // existing snapshot block continues here
].filter(Boolean).join("\n\n");
```

(Adapt to whatever the existing assembly looks like — the principle is: prepend `coachMemoryBlock` to the existing prompt with a blank line.)

- [ ] **Step 3: Deploy to branch and test**

```
mcp__ba7b5e8e__deploy_edge_function  project_id=<branch>  name="ai-proxy"  files=[...]
```

Then send a test chat message via dev build (configured to point at the branch). After a Hinglish exchange, verify the reply uses `Upen` and mirrors casual tone.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/ai-proxy/index.ts
git commit -m "feat(ai-proxy): inject coach_memory block into system prompt

Server-side fetch of coach_memory + render via shared helper.
private_mode short-circuits to empty string. Identity-mirroring
instructions (preferred_name, communication_style, depth, motivation)
now in every chat call.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 11 — `compute-coach-signals` Edge Function + cron schedule

Pure SQL. Reads workout_logs, weight_logs, ai_coach_interactions, sleep_logs, subscriptions. Writes scores to `coach_memory`.

**Files:**
- Create: `supabase/functions/compute-coach-signals/index.ts`
- Create: `supabase/migrations/028_compute_coach_signals_cron.sql`

- [ ] **Step 1: Write the Edge Function**

```ts
// supabase/functions/compute-coach-signals/index.ts
// Nightly cron: computes dropout / plateau / pro_upgrade signals
// for every active user and writes them to coach_memory.
// Pure SQL — no AI cost.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { upsertCoachMemory } from "../_shared/coach_memory.ts";

Deno.serve(async (_req) => {
  const requestId = crypto.randomUUID().split("-")[0];
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Active users: anyone who logged anything in last 21 days OR has an
    // active subscription. Limit per run for safety.
    const { data: users, error } = await supabase.rpc("active_users_for_signals");
    if (error) throw error;

    let processed = 0;
    for (const row of users ?? []) {
      const userId = row.user_id as string;
      const signals = await computeSignalsForUser(supabase, userId);
      await upsertCoachMemory(supabase, userId, {
        ...signals,
        signals_computed_at: new Date().toISOString(),
      });
      processed++;
    }

    return new Response(
      JSON.stringify({ status: "ok", processed, request_id: requestId }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error(`[compute-coach-signals] request_id=${requestId}`, err);
    return new Response(
      JSON.stringify({ error: "Internal server error", request_id: requestId }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});

async function computeSignalsForUser(
  supabase: ReturnType<typeof createClient>,
  userId: string,
) {
  const { data: row } = await supabase.rpc("compute_coach_signals_for_user", {
    p_user_id: userId,
  });
  if (!row || !Array.isArray(row) || row.length === 0) return {};
  const r = row[0] as {
    dropout_risk_score: number | null;
    plateau_risk_score: number | null;
    pro_upgrade_probability: number | null;
  };
  return {
    dropout_risk_score: r.dropout_risk_score,
    plateau_risk_score: r.plateau_risk_score,
    pro_upgrade_probability: r.pro_upgrade_probability,
  };
}
```

- [ ] **Step 2: Write the SQL helper functions and cron schedule**

```sql
-- supabase/migrations/028_compute_coach_signals_cron.sql
-- Helper RPCs + pg_cron schedule for compute-coach-signals.

-- Active users: anyone with activity in the last 21 days OR active sub.
CREATE OR REPLACE FUNCTION public.active_users_for_signals()
RETURNS TABLE(user_id uuid)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT DISTINCT u.id AS user_id
  FROM public.users u
  WHERE EXISTS (
      SELECT 1 FROM public.workout_logs wl
      WHERE wl.user_id = u.id AND wl.date >= now() - interval '21 days'
    )
     OR EXISTS (
      SELECT 1 FROM public.ai_coach_interactions a
      WHERE a.user_id = u.id AND a.created_at >= now() - interval '21 days'
    )
     OR EXISTS (
      SELECT 1 FROM public.subscriptions s
      WHERE s.user_id = u.id AND s.active = true AND s.end_date > now()
    )
  LIMIT 5000;  -- safety ceiling
$$;

-- v1 signal computation (per spec § Predictive Signal Formulas).
CREATE OR REPLACE FUNCTION public.compute_coach_signals_for_user(p_user_id uuid)
RETURNS TABLE(
  dropout_risk_score real,
  plateau_risk_score real,
  pro_upgrade_probability real
)
LANGUAGE sql
SECURITY DEFINER
AS $$
  WITH base AS (
    SELECT
      (SELECT count(*)::real FROM public.workout_logs
        WHERE user_id = p_user_id AND date >= now() - interval '7 days') AS w_now,
      (SELECT count(*)::real / 4 FROM public.workout_logs
        WHERE user_id = p_user_id
          AND date >= now() - interval '35 days'
          AND date <  now() - interval '7 days') AS w_avg,
      coalesce(
        (SELECT extract(day FROM now() - max(created_at))::real
          FROM public.ai_coach_interactions WHERE user_id = p_user_id),
        21
      ) AS days_silent,
      coalesce(
        (SELECT extract(day FROM now() - max(date))::real
          FROM public.weight_logs WHERE user_id = p_user_id),
        14
      ) AS days_no_weigh,
      coalesce(
        (SELECT avg(hours)::real FROM public.sleep_logs
          WHERE user_id = p_user_id AND date >= now() - interval '7 days'),
        7.0
      ) AS sleep_avg,
      (SELECT count(*)::real FROM public.ai_coach_interactions
        WHERE user_id = p_user_id AND created_at >= now() - interval '1 day') AS msgs_today,
      (SELECT
        CASE WHEN current_period_end IS NOT NULL
          THEN extract(day FROM current_period_end - now())::real
          ELSE NULL END
        FROM public.users WHERE id = p_user_id) AS trial_days_remaining,
      (SELECT count(*)::real FROM public.workout_logs
        WHERE user_id = p_user_id
          AND date >= now() - interval '14 days') AS streak_proxy,
      (SELECT bool_or(active) FROM public.subscriptions
        WHERE user_id = p_user_id AND end_date > now()) AS is_pro
  ),
  weight_delta AS (
    SELECT max(weight_kg) - min(weight_kg) AS delta
    FROM public.weight_logs
    WHERE user_id = p_user_id
      AND date >= now() - interval '10 days'
  )
  SELECT
    least(1.0,
      0.4 * greatest(0, (b.w_avg - b.w_now) / nullif(b.w_avg, 0))
    + 0.3 * least(1.0, b.days_silent / 7.0)
    + 0.2 * least(1.0, b.days_no_weigh / 14.0)
    + 0.1 * greatest(0, (6.0 - b.sleep_avg) / 6.0)
    )::real AS dropout_risk_score,

    CASE
      WHEN coalesce(wd.delta, 0) < 0.3 THEN 0.7::real
      ELSE 0.2::real
    END AS plateau_risk_score,

    CASE
      WHEN coalesce(b.is_pro, false) THEN 0.0::real
      WHEN b.trial_days_remaining IS NOT NULL
        AND b.trial_days_remaining < 8
        AND b.msgs_today >= 5
        AND b.streak_proxy >= 5 THEN 0.8::real
      WHEN b.trial_days_remaining IS NOT NULL
        AND b.trial_days_remaining < 15
        AND b.msgs_today >= 3 THEN 0.5::real
      ELSE 0.2::real
    END AS pro_upgrade_probability
  FROM base b, weight_delta wd;
$$;

-- Cron schedule: 02:30 IST = 21:00 UTC daily (after daily-snapshot at 20:30 UTC).
SELECT cron.schedule(
  'compute_coach_signals',
  '0 21 * * *',
  $job$
  SELECT net.http_post(
    url := private.morning_alert_function_url() || '/../compute-coach-signals',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || private.morning_alert_get_service_key()
    ),
    body := '{}'::jsonb
  );
  $job$
);
```

> **Note on URL construction:** the existing `private.morning_alert_function_url()` returns the morning-alert URL. Since URLs share the `/functions/v1/` prefix, derive a sibling helper or hard-code the full URL. If the helper isn't reusable, copy its definition from migration 015 and create `private.compute_coach_signals_function_url()`. Keep the inline approach above only if URL templating works in your Supabase setup; otherwise create a dedicated helper.

- [ ] **Step 3: Apply on branch and verify**

```
mcp__ba7b5e8e__apply_migration  project_id=<branch>  name="028_compute_coach_signals_cron"  query=<contents>
mcp__ba7b5e8e__deploy_edge_function  project_id=<branch>  name="compute-coach-signals"  files=[...]
```

Seed a test user with synthetic gaps:

```
mcp__ba7b5e8e__execute_sql  project_id=<branch>  query="
INSERT INTO public.workout_logs (user_id, date, workout_name)
SELECT '<test-user-uuid>', now() - (n || ' days')::interval, 'test'
FROM generate_series(8, 30) n;  -- 4-week historical baseline, no last-7-day workouts
"
```

Manually invoke the function and check the row:

```
mcp__ba7b5e8e__execute_sql  project_id=<branch>  query="SELECT dropout_risk_score, plateau_risk_score FROM coach_memory WHERE user_id = '<test-user-uuid>';"
```

Expected: `dropout_risk_score > 0.4` (worked out historically, dropped to zero this week → strong signal).

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/compute-coach-signals/index.ts \
        supabase/migrations/028_compute_coach_signals_cron.sql
git commit -m "feat(edge): compute-coach-signals nightly cron

Pure-SQL signal computation for dropout / plateau / pro-upgrade risk.
v1 formulas per spec — no AI cost. Scheduled at 21:00 UTC (02:30 IST)
right after daily-snapshot. Writes scores to coach_memory.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 12 — `morning-alert` personalization

**Files:**
- Modify: `supabase/functions/morning-alert/index.ts`

- [ ] **Step 1: Read coach_memory at the top of the per-user loop**

Add import and read inside the user loop (search for the loop that fetches each user's snapshot):

```ts
import { fetchCoachMemory, upsertCoachMemory } from "../_shared/coach_memory.ts";

const memory = await fetchCoachMemory(supabase, userId);
const name = memory?.preferred_name ?? user.full_name ?? "there";
const tone = memory?.motivation_style ?? "gentle";
```

- [ ] **Step 2: Use `name` + `tone` in copy**

Replace existing greetings with name-aware versions. Example for the PRO branch:

```ts
const greeting = tone === "tough_love"
  ? `${name}, no excuses today. ${baseAlert}`
  : tone === "data_driven"
  ? `${name} — yesterday: sleep ${sleepHrs}hr, ${stepsYday} steps. ${baseAlert}`
  : `Morning ${name}! ${baseAlert}`;
```

- [ ] **Step 3: Tag `last_proactive_type` after a successful push**

After the OneSignal POST resolves successfully:

```ts
await upsertCoachMemory(supabase, userId, {
  last_proactive_type: "morning_brief",
});
```

- [ ] **Step 4: Deploy and smoke test on branch**

```
mcp__ba7b5e8e__deploy_edge_function  project_id=<branch>  name="morning-alert"  files=[...]
```

Manually trigger morning-alert in delivery mode for a seeded user with `preferred_name='Upen'`. Verify push body uses "Upen" and `coach_memory.last_proactive_type = 'morning_brief'` after.

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/morning-alert/index.ts
git commit -m "feat(morning-alert): personalize copy via coach_memory

Reads preferred_name + motivation_style for greeting + tone.
Tags last_proactive_type='morning_brief' after successful push so
future proactive triggers can avoid duplicate same-day pings.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 13 — `CLAUDE.md` documentation updates

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: §4 Hive boxes — add `coach_memory` key**

In §4 of `CLAUDE.md`, find the `coachBox` row in the Hive Boxes table. After the row, add a sub-bullet under coachBox listing keys:

```
| `coachBox` | ai_coach_interactions, coaching_notes, **coach_memory** (CoachMemory JSON), fitness_summary |
```

Or add a new dedicated subsection if the current shape doesn't accommodate.

- [ ] **Step 2: §7 DB schema — bump AI domain row count and add `coach_memory`**

```
| AI (3) | `user_daily_snapshots`, `ai_coach_interactions`, `coach_memory` *(new)* |
```

Then add a paragraph under the schema section:

```markdown
**`coach_memory` table (new — coach personalization, 1 row/user):**
- Layer 4: `dropout_risk_score`, `plateau_risk_score`, `pro_upgrade_probability` (computed nightly by `compute-coach-signals`)
- Layer 5: `preferred_name`, `communication_style`, `humor_tolerance`, `depth_preference`, `motivation_style` (extracted by `daily-snapshot` Gemini call)
- `private_mode=true` short-circuits all reads/writes — never inject into prompts when set.
- `coach_notes` is free-form and **NEVER** used for training data (DPDP commitment).
```

- [ ] **Step 3: §11 AI architecture — document the 7-block prompt**

Add a subsection:

```markdown
### System prompt — 7-block layout (since coach_memory ship)
1. IDENTITY & RULES (static)
2. USER PROFILE
3. **COACH MEMORY** (new — preferred_name, style, risks, last_proactive_type)
4. TODAY'S CONTEXT
5. RECENT HISTORY (fitness_summary + last 5 turns)
6. AVAILABLE TOOLS (placeholder — tool-calling phase TBD)
7. RESPONSE RULES (static)

Block [3] is rendered server-side via `_shared/coach_memory.ts:renderCoachMemoryBlock()` and prepended to the existing system prompt in `ai-proxy`.
```

- [ ] **Step 4: §19 Common bugs — add three new entries**

```markdown
| Coach calls user by wrong name | `coach_memory.preferred_name` not synced. Verify Hive `coachBox['coach_memory']` matches Supabase. Check `pushSnapshot` round-trip captured the response. |
| Coach speaks English when user writes Hinglish | `IdentitySignalDetector` is sticky — needs 3 consecutive Hinglish messages before flipping. Devanagari script flips immediately. Verify Hive write happened in `detectAndPersistIdentitySignals`. |
| Predictive risk scores never appear | `compute-coach-signals` cron only runs on users active in the last 21 days. Manually invoke via `mcp__ba7b5e8e__execute_sql` calling the RPC for the user_id to debug. |
```

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(CLAUDE): document coach_memory + 7-block system prompt

Adds Hive key reference, DB schema entry, 7-block prompt layout,
and three common-bug entries for the new coach_memory pipeline.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 14 — End-to-end verification + production migration

- [ ] **Step 1: Run full Flutter test suite**

```bash
flutter analyze
flutter test
```

Expected: zero analyzer errors, all tests pass (existing + 3 new test files).

- [ ] **Step 2: Manual coach-behavior walkthrough on dev build**

```bash
flutter run --dart-define-from-file=.env --flavor dev -t lib/main.dart
```

Walkthrough script:

1. Open AI Coach.
2. Send: `"call me Upen"` — verify Hive `coach_memory.preferredName == 'Upen'`.
3. Send three Hinglish messages: `"yaar bata aaj kya khaaun"`, `"bhai mera workout kaisa raha"`, `"main thoda thaka hua hoon"`. Verify Hive `coach_memory.communicationStyle == 'hinglish'` after the 3rd.
4. Force a `pushSnapshot` (log a meal). Verify console prints `[SyncService.pushSnapshot] coach_memory mirrored to Hive`.
5. Send `"What's my workout today?"`. Verify reply uses **Upen** and mirrors casual/Hinglish tone.
6. Open Supabase branch dashboard → `coach_memory` table → confirm row matches Hive.

- [ ] **Step 3: No-regression check on existing Edge Functions**

For each — `morning-alert`, `rolling-context`, `daily-snapshot`, `ai-proxy` — invoke against a test user with NO `coach_memory` row. Confirm none throw, all return their normal success response. Graceful null handling is built into the helper (`fetchCoachMemory` returns null cleanly).

- [ ] **Step 4: Apply migrations to PRODUCTION**

After all verification passes, apply both migrations to the live project:

```
mcp__ba7b5e8e__apply_migration  project_id="dedsavbjuwgarrhphgnl"  name="027_create_coach_memory"  query=<...>
mcp__ba7b5e8e__apply_migration  project_id="dedsavbjuwgarrhphgnl"  name="028_compute_coach_signals_cron"  query=<...>
```

Then deploy all three Edge Functions to production:

```
mcp__ba7b5e8e__deploy_edge_function  project_id="dedsavbjuwgarrhphgnl"  name="daily-snapshot"   files=[...]
mcp__ba7b5e8e__deploy_edge_function  project_id="dedsavbjuwgarrhphgnl"  name="ai-proxy"         files=[...]
mcp__ba7b5e8e__deploy_edge_function  project_id="dedsavbjuwgarrhphgnl"  name="morning-alert"    files=[...]
mcp__ba7b5e8e__deploy_edge_function  project_id="dedsavbjuwgarrhphgnl"  name="compute-coach-signals" files=[...]
```

- [ ] **Step 5: Build prod APK (per user's standing rule: APKs are always prod/release)**

```bash
flutter build apk --dart-define-from-file=.env --flavor prod --release -t lib/main.dart
```

Verify build succeeds. Install on a device, run the manual walkthrough from Step 2 against production Supabase.

- [ ] **Step 6: Final commit + delete branch**

```bash
git add -A
git status  # confirm nothing unrelated
git commit -m "chore(coach_memory): production migrations applied + verified

Branch coach-memory-027 validated end-to-end:
- Migration 027 + 028 applied to production
- Edge functions deployed
- Manual walkthrough green on prod APK

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

Delete the Supabase branch (only after PR merged / staging confirmed):

```
mcp__ba7b5e8e__delete_branch  project_id=<branch_project_id>
```

---

## Self-Review

**Spec coverage:**
- §6 Hyper-Personalization Layers 4 + 5 → Tasks 5, 8, 11 ✓
- §7 Data Schema (`coach_memory` table) → Task 1 ✓
- §13 System Prompt restructure (block [3]) → Tasks 2, 6, 10 ✓
- Backfill from legacy `coaching_notes` → Task 4 ✓
- Hive mirror via snapshot round-trip → Task 9 ✓
- `private_mode` short-circuit → Tasks 2 (renderCoachMemoryBlock), 6 (_getCoachMemoryForContext) ✓
- Predictive signal SQL formulas → Task 11 ✓
- Documentation update → Task 13 ✓
- E2E verification → Task 14 ✓

**Placeholder scan:** No "TBD", "TODO", "implement appropriately" found. The one open soft note is the URL helper in Task 11 Step 2 (the `morning_alert_function_url() || '/../compute-coach-signals'` template) — explicitly called out as needing local verification, with the fallback (copy the helper pattern) spelled out.

**Type consistency:** `CoachMemory` field names are camelCase in Dart (`preferredName`, `dropoutRiskScore`) and snake_case on the wire (`preferred_name`, `dropout_risk_score`). `toJson` / `fromJson` translate. `CoachMemory` (TS interface) and `CoachMemory` (Dart class) carry the same fields. `renderCoachMemoryBlock` consumes the TS `CoachMemory` type. Verified consistent.

**Scope check:** No subsystem outside the spec is touched. Tool-calling, additional proactive triggers, cost routing, photo/video features, YouTube demos, `coach_sessions` table — all explicitly deferred per spec § "What This Ship Does NOT Include."

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-04-18-ai-coach-coach-memory-personalization.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
