part of 'screen.dart';

extension _ExportData on _ProfileScreenState {

  // ── #10 Export Data ─────────────────────────────────────────────

  Future<void> _exportData() async {
    final hive = HiveService.instance;
    final data = <String, dynamic>{
      'exported_at': DateTime.now().toIso8601String(),
      'profile': Map<String, dynamic>.from(hive.userBox.get('profile') as Map? ?? {}),
      'workout_logs_count': hive.workoutBox.length,
      'nutrition_logs_count': hive.nutritionBox.length,
      'health_logs_count': hive.healthBox.length,
    };

    // Collect workout logs
    final workouts = <Map<String, dynamic>>[];
    for (final raw in hive.workoutBox.values) {
      if (raw is Map) workouts.add(Map<String, dynamic>.from(raw));
    }
    data['workout_logs'] = workouts;

    // Collect nutrition logs
    final nutrition = <Map<String, dynamic>>[];
    for (final raw in hive.nutritionBox.values) {
      if (raw is Map) nutrition.add(Map<String, dynamic>.from(raw));
    }
    data['nutrition_logs'] = nutrition;

    // Collect health logs
    final health = <Map<String, dynamic>>[];
    for (final raw in hive.healthBox.values) {
      if (raw is Map) health.add(Map<String, dynamic>.from(raw));
    }
    data['health_logs'] = health;

    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    // Write to a temp file to avoid OOM on large exports
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/avya_export_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(jsonStr);
    await Share.shareXFiles([XFile(file.path)], subject: 'AVYA Fit Data Export');
  }
}
