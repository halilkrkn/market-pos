import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../pos/domain/barcode_input_sanitizer.dart';
import '../domain/external_product_lookup_service.dart';
import '../domain/external_product_suggestion.dart';

/// Open Food Facts API v2 üzerinden yalnızca ürün önerisi getiren salt-okunur istemci.
///
/// Harici API hataları, zaman aşımları veya çevrimdışı koşullar ASLA uncaught
/// istisna fırlatmaz; manuel ürün oluşturma sürecini engellemez.
class OpenFoodFactsClient implements ExternalProductLookupService {
  static const String defaultBaseUrl = 'https://world.openfoodfacts.org';
  static const String userAgentHeader =
      'MarketMMS/1.0 (+https://marketmms.local)';
  static const Duration defaultTimeout = Duration(seconds: 6);

  final http.Client _client;
  final String _baseUrl;
  final Duration timeout;
  final bool _ownsClient;

  OpenFoodFactsClient({
    http.Client? client,
    String baseUrl = defaultBaseUrl,
    this.timeout = defaultTimeout,
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _ownsClient = client == null;

  @override
  Future<ExternalProductLookupResult> lookupByBarcode(String barcode) async {
    final sanitized = BarcodeInputSanitizer.sanitize(barcode);
    if (!sanitized.isValid) {
      return ExternalProductLookupResult.invalidBarcode(
        barcode,
        message: sanitized.errorMessage,
      );
    }

    final cleanBarcode = sanitized.normalized;
    final uri = Uri.parse(
      '$_baseUrl/api/v2/product/${Uri.encodeComponent(cleanBarcode)}.json',
    ).replace(
      queryParameters: const {
        'fields':
            'code,product_name,product_name_tr,brands,categories,image_front_small_url,image_url,ingredients_text_tr,ingredients_text,quantity,nutriments',
      },
    );

    try {
      final response = await _client
          .get(
            uri,
            headers: const {
              'User-Agent': userAgentHeader,
              'Accept': 'application/json',
            },
          )
          .timeout(timeout);

      if (response.statusCode == 404) {
        return ExternalProductLookupResult.notFound(cleanBarcode);
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return ExternalProductLookupResult.error(
          cleanBarcode,
          message:
              'Open Food Facts şu anda yanıt veremedi (HTTP ${response.statusCode}). Ürünü elle tanımlayabilirsiniz.',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return ExternalProductLookupResult.error(
          cleanBarcode,
          message:
              'Open Food Facts yanıtı çözümlenemedi. Ürünü elle tanımlayabilirsiniz.',
        );
      }

      final apiStatus = decoded['status'];
      final productMap = decoded['product'];
      if (apiStatus == 0 || productMap is! Map<String, dynamic>) {
        return ExternalProductLookupResult.notFound(cleanBarcode);
      }

      final suggestion = _parseSuggestion(cleanBarcode, productMap);
      if (suggestion == null) {
        return ExternalProductLookupResult.notFound(cleanBarcode);
      }

      return ExternalProductLookupResult.found(suggestion);
    } on TimeoutException {
      return ExternalProductLookupResult.error(
        cleanBarcode,
        message:
            'Open Food Facts sorgusu zaman aşımına uğradı. Ürünü elle tanımlayabilirsiniz.',
      );
    } on SocketException {
      return ExternalProductLookupResult.error(
        cleanBarcode,
        message:
            'İnternet veya Open Food Facts bağlantısı yok. Çevrimdışı olarak ürünü elle tanımlayabilirsiniz.',
      );
    } on http.ClientException {
      return ExternalProductLookupResult.error(
        cleanBarcode,
        message:
            'Open Food Facts servisine erişilemedi. Ürünü elle tanımlayabilirsiniz.',
      );
    } on FormatException {
      return ExternalProductLookupResult.error(
        cleanBarcode,
        message:
            'Open Food Facts yanıt biçimi geçersiz. Ürünü elle tanımlayabilirsiniz.',
      );
    } catch (_) {
      return ExternalProductLookupResult.error(cleanBarcode);
    }
  }

  ExternalProductSuggestion? _parseSuggestion(
    String barcode,
    Map<String, dynamic> product,
  ) {
    final name = _firstNonEmpty([
      product['product_name_tr'],
      product['product_name'],
    ]);
    final brand = _firstNonEmpty([product['brands']]);
    final categories = _parseCategories(product['categories']);
    final imageUrl = _sanitizeImageUrl(
      _firstNonEmpty([
        product['image_front_small_url'],
        product['image_url'],
      ]),
    );
    final ingredients = _firstNonEmpty([
      product['ingredients_text_tr'],
      product['ingredients_text'],
    ]);
    final quantityText = _firstNonEmpty([product['quantity']]);
    final suggestedUnit = inferStockUnitFromQuantity(quantityText);
    final nutrition = _parseNutrition(product['nutriments']);

    if ((name == null || name.isEmpty) && (brand == null || brand.isEmpty)) {
      return null;
    }

    return ExternalProductSuggestion(
      barcode: barcode,
      productName: name ?? brand ?? barcode,
      brand: brand,
      categories: categories,
      imageUrl: imageUrl,
      ingredientsText: ingredients,
      quantityText: quantityText,
      suggestedUnit: suggestedUnit,
      nutrition: (nutrition == null || nutrition.isEmpty) ? null : nutrition,
    );
  }

  static String? _firstNonEmpty(List<Object?> candidates) {
    for (final c in candidates) {
      if (c is String) {
        final trimmed = c.trim();
        if (trimmed.isNotEmpty) return trimmed;
      }
    }
    return null;
  }

  static List<String> _parseCategories(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return const [];
    final result = <String>[];
    for (final part in raw.split(',')) {
      var clean = part.trim();
      final prefixMatch = RegExp(r'^[a-z]{2,3}:(.+)$').firstMatch(clean);
      if (prefixMatch != null) {
        clean = prefixMatch.group(1)!.trim();
      }
      if (clean.isNotEmpty && !result.contains(clean)) {
        result.add(clean);
      }
    }
    return List.unmodifiable(result);
  }

  static String? _sanitizeImageUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.isEmpty) return null;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    return uri.toString();
  }

  /// Open Food Facts `quantity` alanından MMS stok birim ipucu üretir.
  static String? inferStockUnitFromQuantity(String? quantity) {
    if (quantity == null || quantity.trim().isEmpty) return null;
    final lower = quantity.toLowerCase();
    if (RegExp(r'\bml\b|\d+ml\b').hasMatch(lower)) return 'ml';
    if (RegExp(r'\b(l|lt|litre|liter)\b|\d+l\b').hasMatch(lower)) return 'l';
    if (RegExp(r'\bkg\b|\d+kg\b').hasMatch(lower)) return 'kg';
    if (RegExp(r'\b(g|gr|gram)\b|\d+g\b').hasMatch(lower)) return 'g';
    if (RegExp(r'\b(paket|pack)\b').hasMatch(lower)) return 'paket';
    if (RegExp(r'\b(kutu|box)\b').hasMatch(lower)) return 'kutu';
    return null;
  }

  static NutritionFactsSummary? _parseNutrition(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    return NutritionFactsSummary(
      energyKcal100g: _formatNumber(raw['energy-kcal_100g'], 'kcal'),
      fat100g: _formatNumber(raw['fat_100g'], 'g'),
      carbohydrates100g: _formatNumber(raw['carbohydrates_100g'], 'g'),
      sugars100g: _formatNumber(raw['sugars_100g'], 'g'),
      proteins100g: _formatNumber(raw['proteins_100g'], 'g'),
      salt100g: _formatNumber(raw['salt_100g'], 'g'),
    );
  }

  static String? _formatNumber(Object? val, String unit) {
    num? parsed;
    if (val is num) {
      parsed = val;
    } else if (val is String) {
      parsed = num.tryParse(val.trim().replaceAll(',', '.'));
    }
    if (parsed == null || parsed.isNaN || parsed.isInfinite) return null;
    final fixed = parsed % 1 == 0
        ? parsed.toInt().toString()
        : parsed.toStringAsFixed(1);
    return '$fixed $unit';
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}
