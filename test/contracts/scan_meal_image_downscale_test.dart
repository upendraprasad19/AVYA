import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scan_meal_section.dart downscales the picked image', () {
    final src = File('lib/features/nutrition/widgets/scan_meal_section.dart').readAsStringSync();
    final call = RegExp(r'picker\.pickImage\(([^)]*)\)').firstMatch(src);
    expect(call, isNotNull, reason: 'pickImage call not found');
    final args = call!.group(1)!;
    expect(args, contains('imageQuality'),
        reason: 'scan_meal_section.dart must downscale the picked image (obs 2, diagnose scan-meal-image-too-large)');
    expect(args, contains('maxWidth'));
  });

  test('cart_auditor_section.dart downscales the picked image', () {
    final src = File('lib/features/nutrition/widgets/cart_auditor_section.dart').readAsStringSync();
    final call = RegExp(r'picker\.pickImage\(([^)]*)\)').firstMatch(src);
    expect(call, isNotNull, reason: 'pickImage call not found');
    final args = call!.group(1)!;
    expect(args, contains('imageQuality'));
    expect(args, contains('maxWidth'));
  });
}
