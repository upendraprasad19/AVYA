import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scan_meal_section.dart downscales the picked image with exact values', () {
    final src = File('lib/features/nutrition/widgets/scan_meal_section.dart').readAsStringSync();
    final call = RegExp(r'picker\.pickImage\(([^)]*)\)').firstMatch(src);
    expect(call, isNotNull, reason: 'pickImage call not found');
    final args = call!.group(1)!;

    // Assertion 1: imageQuality must equal 85
    final qualityMatch = RegExp(r'imageQuality:\s*(\d+)').firstMatch(args);
    expect(qualityMatch, isNotNull, reason: 'imageQuality parameter not found');
    final quality = qualityMatch!.group(1)!;
    expect(quality, equals('85'),
        reason: 'scan_meal_section.dart must use imageQuality: 85 for downscaling (obs 2, diagnose scan-meal-image-too-large)');

    // Assertion 2: maxWidth must equal 1600
    final widthMatch = RegExp(r'maxWidth:\s*(\d+)').firstMatch(args);
    expect(widthMatch, isNotNull, reason: 'maxWidth parameter not found');
    final width = widthMatch!.group(1)!;
    expect(width, equals('1600'),
        reason: 'scan_meal_section.dart must use maxWidth: 1600');

    // Assertion 3: maxHeight must equal 1600
    final heightMatch = RegExp(r'maxHeight:\s*(\d+)').firstMatch(args);
    expect(heightMatch, isNotNull, reason: 'maxHeight parameter not found');
    final height = heightMatch!.group(1)!;
    expect(height, equals('1600'),
        reason: 'scan_meal_section.dart must use maxHeight: 1600');
  });

  test('cart_auditor_section.dart downscales the picked image with exact values', () {
    final src = File('lib/features/nutrition/widgets/cart_auditor_section.dart').readAsStringSync();
    final call = RegExp(r'picker\.pickImage\(([^)]*)\)').firstMatch(src);
    expect(call, isNotNull, reason: 'pickImage call not found');
    final args = call!.group(1)!;

    // Assertion 1: imageQuality must equal 85
    final qualityMatch = RegExp(r'imageQuality:\s*(\d+)').firstMatch(args);
    expect(qualityMatch, isNotNull, reason: 'imageQuality parameter not found');
    final quality = qualityMatch!.group(1)!;
    expect(quality, equals('85'),
        reason: 'cart_auditor_section.dart must use imageQuality: 85 for downscaling');

    // Assertion 2: maxWidth must equal 1600
    final widthMatch = RegExp(r'maxWidth:\s*(\d+)').firstMatch(args);
    expect(widthMatch, isNotNull, reason: 'maxWidth parameter not found');
    final width = widthMatch!.group(1)!;
    expect(width, equals('1600'),
        reason: 'cart_auditor_section.dart must use maxWidth: 1600');

    // Assertion 3: maxHeight must equal 1600
    final heightMatch = RegExp(r'maxHeight:\s*(\d+)').firstMatch(args);
    expect(heightMatch, isNotNull, reason: 'maxHeight parameter not found');
    final height = heightMatch!.group(1)!;
    expect(height, equals('1600'),
        reason: 'cart_auditor_section.dart must use maxHeight: 1600');
  });
}
