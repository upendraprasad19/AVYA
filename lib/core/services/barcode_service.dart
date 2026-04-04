import 'dart:convert';
import 'package:http/http.dart' as http;

/// Nutritional data returned from a barcode lookup.
class BarcodeFood {
  final String name;
  final String? brand;
  final double caloriesPer100g;
  final double proteinPer100g;
  final double carbsPer100g;
  final double fatPer100g;
  final double fiberPer100g;
  final String? servingDesc;
  final double servingG;

  const BarcodeFood({
    required this.name,
    this.brand,
    required this.caloriesPer100g,
    required this.proteinPer100g,
    required this.carbsPer100g,
    required this.fatPer100g,
    required this.fiberPer100g,
    this.servingDesc,
    this.servingG = 100,
  });

  double caloriesForServing(double grams) => caloriesPer100g * grams / 100;
  double proteinForServing(double grams) => proteinPer100g * grams / 100;
  double carbsForServing(double grams) => carbsPer100g * grams / 100;
  double fatForServing(double grams) => fatPer100g * grams / 100;
  double fiberForServing(double grams) => fiberPer100g * grams / 100;
}

/// Calls Open Food Facts API to look up a product by barcode.
class BarcodeService {
  BarcodeService._();
  static final instance = BarcodeService._();

  static const _baseUrl = 'https://world.openfoodfacts.net/api/v3/product';

  Future<BarcodeFood?> lookup(String barcode) async {
    try {
      final uri = Uri.parse('$_baseUrl/$barcode.json');
      final response = await http
          .get(uri, headers: {'User-Agent': 'ICANBEFITTER/1.0'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['status'] != 'success') return null;

      final product = json['product'] as Map<String, dynamic>? ?? {};
      final nutriments = product['nutriments'] as Map<String, dynamic>? ?? {};

      final name = (product['product_name'] as String?)?.trim() ?? '';
      if (name.isEmpty) return null;

      double parseNutriment(String key) => switch (nutriments[key]) {
            num n => n.toDouble(),
            _ => 0.0,
          };

      // energy-kcal_100g preferred; fall back to energy_100g (kJ) → /4.184
      double calories = parseNutriment('energy-kcal_100g');
      if (calories == 0) calories = parseNutriment('energy_100g') / 4.184;

      final servingSize =
          (product['serving_size'] as String?)?.replaceAll(RegExp(r'[^0-9.]'), '') ?? '';
      final servingG = double.tryParse(servingSize) ?? 100.0;

      return BarcodeFood(
        name: name,
        brand: (product['brands'] as String?)?.split(',').first.trim(),
        caloriesPer100g: calories,
        proteinPer100g: parseNutriment('proteins_100g'),
        carbsPer100g: parseNutriment('carbohydrates_100g'),
        fatPer100g: parseNutriment('fat_100g'),
        fiberPer100g: parseNutriment('fiber_100g'),
        servingDesc: product['serving_size'] as String?,
        servingG: servingG > 0 ? servingG : 100,
      );
    } catch (_) {
      return null;
    }
  }
}
