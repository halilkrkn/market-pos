import 'package:mms_client_storage/mms_client_storage.dart' show kCountableStockUnits;

import '../../pos/domain/money.dart';

/// Stok Girişi formunun saf Dart doğrulaması (Faz 2 §4.3).
///
/// Miktar ürünün stok biriminde milli-birime, alış fiyatı kuruşa çevrilir.
/// Para hesaplarında `double` kullanılmaz.
class StockReceiptInput {
  final int? quantityMilli;
  final int? purchasePriceCents;
  final String? note;
  final String? errorMessage;

  const StockReceiptInput._({
    this.quantityMilli,
    this.purchasePriceCents,
    this.note,
    this.errorMessage,
  });

  bool get isValid => errorMessage == null;

  static const int maxNoteLength = 200;

  factory StockReceiptInput.parse({
    required String rawQuantity,
    String? rawPurchasePrice,
    String? rawNote,
    required String stockUnit,
  }) {
    StockReceiptInput fail(String message) => StockReceiptInput._(errorMessage: message);

    final quantityText = rawQuantity.trim();
    if (quantityText.isEmpty) {
      return fail('Gelen miktarı giriniz.');
    }
    final quantityMilli = Money.tryParseQuantityToMilli(quantityText);
    if (quantityMilli == null) {
      return fail('Geçersiz miktar. En fazla 3 ondalık haneli sayı giriniz (ör. 2 veya 1,250).');
    }
    if (quantityMilli <= 0) {
      return fail('Gelen miktar sıfırdan büyük olmalıdır.');
    }
    if (quantityMilli > Money.maxQuantityMilli) {
      return fail('Gelen miktar izin verilen üst sınırı aşıyor.');
    }
    if (kCountableStockUnits.contains(stockUnit) &&
        quantityMilli % Money.quantityScale != 0) {
      return fail('"$stockUnit" biriminde kesirli miktar girilemez.');
    }

    int? purchasePriceCents;
    final priceText = rawPurchasePrice?.trim() ?? '';
    if (priceText.isNotEmpty) {
      purchasePriceCents = Money.tryParseLiraToCents(priceText);
      if (purchasePriceCents == null || purchasePriceCents < 0) {
        return fail('Alış fiyatı geçersiz. Örnek: 7,50');
      }
    }

    final note = rawNote?.trim();
    if (note != null && note.length > maxNoteLength) {
      return fail('Açıklama en fazla $maxNoteLength karakter olabilir.');
    }

    return StockReceiptInput._(
      quantityMilli: quantityMilli,
      purchasePriceCents: purchasePriceCents,
      note: (note == null || note.isEmpty) ? null : note,
    );
  }
}
