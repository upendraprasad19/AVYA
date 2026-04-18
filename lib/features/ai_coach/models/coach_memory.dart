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
