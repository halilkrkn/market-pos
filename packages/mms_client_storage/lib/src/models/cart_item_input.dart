/// S5A-3: Sepet Ürün Girdisi
///
/// Finansal ve operasyonel kesinlik için floating-point (`double`) KESİNLİKLE KULLANILMAZ.
/// Miktar, 3 ondalık hane hassasiyetle ölçeklendirilmiş tamsayıdır (`QUANTITY_SCALE = 1000`).
///
/// Desteklenen kurucular:
/// - `CartItemInput.units(productId, count)`: Tam adet/birim girişi (Örn: 1 adet -> 1000)
/// - `CartItemInput.fractional(productId, milliUnits)`: Doğrudan tamsayı milli-birim (Örn: 500 gram -> 500)
/// - `CartItemInput.fromDecimalString(productId, text)`: Deterministik metin ayrıştırıcı (Örn: "0.5" -> 500, "1.25" -> 1250)
class CartItemInput {
  static const int scale = 1000; // 3 ondalık hane ölçeği (NUMERIC(12, 3))
  static const int maxQuantity = 1000000000; // 1,000,000 birim üst sınır (10^9 milli-birim)

  final String productId;

  /// Milli-birim cinsinden miktar (Örn: 500 = 0.500 kg, 1250 = 1.250 L, 1000 = 1 adet)
  final int quantity;

  CartItemInput({
    required this.productId,
    required this.quantity,
  }) {
    if (productId.isEmpty) {
      throw ArgumentError('Ürün kimliği (productId) boş olamaz.');
    }
    if (quantity <= 0) {
      throw ArgumentError('Ürün miktarı 0 veya negatif olamaz: $quantity');
    }
    if (quantity > maxQuantity) {
      throw ArgumentError('Miktar izin verilen üst sınırı ($maxQuantity) aşıyor: $quantity');
    }
  }

  /// Tam adet/birim bazlı oluşturucu (Örn: 2 adet ekmek -> quantity = 2000)
  factory CartItemInput.units(String productId, int count) {
    if (count <= 0) throw ArgumentError('Adet 0 veya negatif olamaz: $count');
    if (count > (maxQuantity ~/ scale)) {
      throw ArgumentError('Aşırı büyük adet miktarı: $count');
    }
    return CartItemInput(productId: productId, quantity: count * scale);
  }

  /// Kesirli miktar için doğrudan milli-birim oluşturucu (Örn: 500 gram -> milliUnits = 500)
  factory CartItemInput.fractional(String productId, int milliUnits) {
    if (milliUnits <= 0) throw ArgumentError('Milli-birim 0 veya negatif olamaz: $milliUnits');
    if (milliUnits > maxQuantity) {
      throw ArgumentError('Aşırı büyük milli-birim miktarı: $milliUnits');
    }
    return CartItemInput(productId: productId, quantity: milliUnits);
  }

  /// Ondalık metin değerinden deterministik dönüştürücü (Örn: "0.1" -> 100, "0.3" -> 300, "1.25" -> 1250, "999.999" -> 999999)
  /// Floating-point aritmetiği KESİNLİKLE KULLANILMAZ.
  factory CartItemInput.fromDecimalString(String productId, String decimalText) {
    final raw = decimalText.trim();
    if (raw.isEmpty) {
      throw ArgumentError('Miktar metni boş olamaz.');
    }

    // Yalnızca pozitif rakamlar ve tek bir ayırıcı (. veya ,) kabul edilir
    final regex = RegExp(r'^\d+([.,]\d+)?$');
    if (!regex.hasMatch(raw)) {
      throw ArgumentError('Geçersiz miktar metni formatı: "$decimalText". Pozitif ondalık sayı bekleniyor.');
    }

    final normalized = raw.replaceAll(',', '.');
    final parts = normalized.split('.');
    final wholePart = parts[0];
    final fracPart = parts.length > 1 ? parts[1] : '';

    if (fracPart.length > 3) {
      throw ArgumentError('En fazla 3 ondalık basamak desteklenir (NUMERIC(12, 3)): "$decimalText"');
    }

    final whole = int.tryParse(wholePart);
    if (whole == null) {
      throw ArgumentError('Geçersiz tam sayı kısmı: "$wholePart"');
    }

    // Ondalık kısmı 3 basamağa sağdan sıfır ekleyerek (padRight) tamamla: "1" -> "100", "25" -> "250", "999" -> "999"
    final paddedFrac = fracPart.padRight(3, '0');
    final frac = paddedFrac.isEmpty ? 0 : int.parse(paddedFrac);

    final milliUnits = (whole * scale) + frac;
    if (milliUnits <= 0) {
      throw ArgumentError('Miktar 0 veya negatif olamaz: "$decimalText"');
    }
    if (milliUnits > maxQuantity) {
      throw ArgumentError('Miktar izin verilen üst sınırı aşıyor: "$decimalText"');
    }

    return CartItemInput(productId: productId, quantity: milliUnits);
  }

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'quantity': quantity,
      };
}
