/// Saf Dart para ve milli-birim miktar yardımcıları (`double` YASAK — `OD-01`).
///
/// Tüm parasal değerler kuruş bazlı `int` olarak işlenir ve gösterim standardı
/// `12.50 TL` biçimindedir. Alt kuruş yuvarlamada yalnızca Half-Up uygulanır.
class Money {
  Money._();

  static const int quantityScale = 1000;
  static const int maxQuantityMilli = 1000000000; // 10^9 milli-birim
  static const int maxTotalCents = 100000000000; // Backend üst sınırı
  static const int maxSafeInt = 9223372036854775807; // 2^63 - 1

  static final RegExp _tlSuffixRegex = RegExp(r'\s*tl$', caseSensitive: false);
  static final RegExp _plainDecimalRegex = RegExp(r'^\d+([.,]\d{1,2})?$');
  static final RegExp _commaThousandsDotDecimalRegex = RegExp(
    r'^(\d{1,3}(,\d{3})+\.\d{1,2}|\d{1,3}(,\d{3}){2,})$',
  );
  static final RegExp _dotThousandsCommaDecimalRegex = RegExp(
    r'^(\d{1,3}(\.\d{3})+,\d{1,2}|\d{1,3}(\.\d{3}){2,})$',
  );
  static final RegExp _quantityRegex = RegExp(r'^\d+([.,]\d+)?$');

  /// Half-Up yuvarlama: `((unitPriceCents * quantityMilli) + 500) ~/ 1000`.
  static int calculateLineTotalHalfUp({
    required int unitPriceCents,
    required int quantityMilli,
  }) {
    if (unitPriceCents < 0) {
      throw ArgumentError('Birim fiyat negatif olamaz: $unitPriceCents');
    }
    if (quantityMilli <= 0 || quantityMilli > maxQuantityMilli) {
      throw ArgumentError(
        'Miktar 1 ile $maxQuantityMilli milli-birim arasında olmalıdır: $quantityMilli',
      );
    }
    if (unitPriceCents > 0 &&
        quantityMilli > (maxSafeInt - (quantityScale ~/ 2)) ~/ unitPriceCents) {
      throw ArgumentError(
        'Birim fiyat ve miktar çarpımı tamsayı sınırını aşıyor.',
      );
    }
    return ((unitPriceCents * quantityMilli) + (quantityScale ~/ 2)) ~/
        quantityScale;
  }

  /// İki kuruş tutarını tamsayı taşmasına karşı koruyarak toplar.
  static int safeAddCents(int currentCents, int deltaCents) {
    if (deltaCents > 0 && currentCents > maxSafeInt - deltaCents) {
      throw ArgumentError('Toplam kuruş tutarı tamsayı sınırını aşıyor.');
    }
    if (deltaCents < 0 && currentCents < -maxSafeInt - deltaCents) {
      throw ArgumentError('Kuruş tutarı alt tamsayı sınırını aşıyor.');
    }
    return currentCents + deltaCents;
  }

  /// Kuruş tamsayı değerini `12.50 TL` / `1,250.00 TL` biçiminde formatlar.
  static String formatCents(int cents) {
    final isNegative = cents < 0;
    final absCents = cents.abs();
    final liras = absCents ~/ 100;
    final kurus = (absCents % 100).toString().padLeft(2, '0');
    final groupedLiras = _groupThousands(liras.toString());
    final sign = isNegative ? '-' : '';
    return '$sign$groupedLiras.$kurus TL';
  }

  /// Kuruş değerini TL düzenleme inputu için noktalı düz metne çevirir (`12.50`).
  static String formatCentsInput(int cents) {
    if (cents < 0) {
      throw ArgumentError('Giriş formatı için negatif kuruş desteklenmez.');
    }
    final liras = cents ~/ 100;
    final kurus = (cents % 100).toString().padLeft(2, '0');
    return '$liras.$kurus';
  }

  /// Kullanıcıdan alınan lira metnini floating-point kullanmadan kuruşa çevirir.
  static int parseLiraToCents(String rawInput) {
    var cleaned = rawInput.trim().replaceAll(_tlSuffixRegex, '').trim();
    if (cleaned.isEmpty) {
      throw ArgumentError('Tutar boş olamaz.');
    }
    if (cleaned.startsWith('-') || cleaned.startsWith('+')) {
      throw ArgumentError('Tutar işaretsiz pozitif sayı olmalıdır: "$rawInput"');
    }

    String wholeDigits;
    String fracDigits = '';

    if (_plainDecimalRegex.hasMatch(cleaned)) {
      final normalized = cleaned.replaceAll(',', '.');
      final parts = normalized.split('.');
      wholeDigits = parts[0];
      if (parts.length == 2) {
        fracDigits = parts[1];
      }
    } else if (_commaThousandsDotDecimalRegex.hasMatch(cleaned)) {
      final parts = cleaned.split('.');
      wholeDigits = parts[0].replaceAll(',', '');
      if (parts.length == 2) {
        fracDigits = parts[1];
      }
    } else if (_dotThousandsCommaDecimalRegex.hasMatch(cleaned)) {
      final parts = cleaned.split(',');
      wholeDigits = parts[0].replaceAll('.', '');
      if (parts.length == 2) {
        fracDigits = parts[1];
      }
    } else {
      throw ArgumentError('Geçersiz TL tutar biçimi: "$rawInput"');
    }

    final whole = int.tryParse(wholeDigits);
    if (whole == null) {
      throw ArgumentError('Tutar tam sayı kısmı geçersiz: "$rawInput"');
    }
    final kurus = int.parse(fracDigits.padRight(2, '0'));
    if (whole > (maxTotalCents - kurus) ~/ 100) {
      throw ArgumentError('Tutar izin verilen üst sınırı aşıyor: "$rawInput"');
    }
    return (whole * 100) + kurus;
  }

  /// Geçersiz lira metninde `null` döner.
  static int? tryParseLiraToCents(String rawInput) {
    try {
      return parseLiraToCents(rawInput);
    } catch (_) {
      return null;
    }
  }

  /// Miktar metnini (`"0"`, `"1"`, `"0.345"`, `"1,25"`) milli-birime (ölçek `1000`) çevirir.
  static int parseQuantityToMilli(String rawInput) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Miktar boş olamaz.');
    }
    if (!_quantityRegex.hasMatch(trimmed)) {
      throw ArgumentError('Geçersiz miktar formatı: "$rawInput"');
    }
    final normalized = trimmed.replaceAll(',', '.');
    final parts = normalized.split('.');
    final wholeText = parts[0];
    final fracText = parts.length == 2 ? parts[1] : '';
    if (fracText.length > 3) {
      throw ArgumentError('En fazla 3 ondalık basamak desteklenir: "$rawInput"');
    }

    final whole = int.tryParse(wholeText);
    if (whole == null) {
      throw ArgumentError('Miktar tam sayı kısmı geçersiz: "$rawInput"');
    }
    final frac = fracText.isEmpty ? 0 : int.parse(fracText.padRight(3, '0'));
    if (whole > (maxQuantityMilli - frac) ~/ quantityScale) {
      throw ArgumentError('Miktar izin verilen üst sınırı aşıyor: "$rawInput"');
    }
    return (whole * quantityScale) + frac;
  }

  /// Geçersiz miktar metninde `null` döner.
  static int? tryParseQuantityToMilli(String rawInput) {
    try {
      return parseQuantityToMilli(rawInput);
    } catch (_) {
      return null;
    }
  }

  /// Milli-birim miktarı sade sayısal metne çevirir (`1000 -> "1"`, `500 -> "0.5"`, `345 -> "0.345"`).
  static String formatMilliNumber(int milliUnits) {
    final sign = milliUnits < 0 ? '-' : '';
    final absVal = milliUnits.abs();
    final whole = absVal ~/ quantityScale;
    final rem = absVal % quantityScale;
    if (rem == 0) {
      return '$sign$whole';
    }
    var fracStr = rem.toString().padLeft(3, '0');
    fracStr = fracStr.replaceFirst(RegExp(r'0+$'), '');
    return '$sign$whole.$fracStr';
  }

  /// Milli-birim miktarı birimiyle birlikte formatlar (`"1 adet"`, `"0.345 kg"`).
  static String formatMilliWithUnit(int milliUnits, String unit) {
    return '${formatMilliNumber(milliUnits)} $unit';
  }

  static String _groupThousands(String digits) {
    if (digits.length <= 3) {
      return digits;
    }
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final remaining = digits.length - i;
      if (i > 0 && remaining % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

