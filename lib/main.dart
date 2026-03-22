import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();

  // Register Hive adapters here (before opening boxes)
  // TODO: Register adapters as models are created

  // Open all Hive boxes
  await Future.wait([
    Hive.openBox('userBox'),
    Hive.openBox('workoutBox'),
    Hive.openBox('nutritionBox'),
    Hive.openBox('healthBox'),
    Hive.openBox('exerciseBox'),
    Hive.openBox('foodBox'),
    Hive.openBox('customBox'),
    Hive.openBox('coachBox'),
    Hive.openBox('syncBox'),
    Hive.openBox('configBox'),
  ]);

  // TODO: Initialize Supabase
  // await Supabase.initialize(url: '...', anonKey: '...');

  // TODO: Seed data on first launch
  // await SeedService.seedIfNeeded();

  runApp(
    const ProviderScope(
      child: ICanBeFitterApp(),
    ),
  );
}
