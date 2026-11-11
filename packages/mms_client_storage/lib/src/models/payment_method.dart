/// Kanonik ödeme yöntemi sözleşmesi (`DATA_MODEL.md` & `BR-PAY-01`).
///
/// Yeni tüm işlemlerde yalnızca `'CASH'` ve `'CARD'` değerleri kabul edilir.
/// Önceki `'CREDIT_CARD'` ve `'NAKIT'` değerleri yeni satış ve sync sözleşmesinde
/// geçersiz kabul edilip reddedilir; yalnızca tarihsel kayıtların salt-okunur
/// incelenmesi için [tryParseLegacyReadOnly] sağlanır.
enum PaymentMethod {
  cash('CASH'),
  card('CARD');

  const PaymentMethod(this.code);

  /// Yerel SQLite, Outbox JSON payload ve Backend API tel sözleşmesi değeri.
  final String code;

  /// Sözleşmede geçerli olan kanonik metin değerleri.
  static const List<String> canonicalCodes = ['CASH', 'CARD'];

  /// Yalnızca kanonik `'CASH'` ve `'CARD'` değerlerini kabul eder.
  /// Eksik, `null`, metin dışı, küçük harf veya eski değerlerde (`'CREDIT_CARD'`,
  /// `'NAKIT'`) [ArgumentError] fırlatır.
  static PaymentMethod parse(Object? raw) {
    if (raw is! String) {
      throw ArgumentError(
        'Ödeme yöntemi metin tipinde ve yalnızca "CASH" veya "CARD" olmalıdır. Gelen tip: ${raw.runtimeType}',
      );
    }
    return switch (raw) {
      'CASH' => PaymentMethod.cash,
      'CARD' => PaymentMethod.card,
      _ => throw ArgumentError(
          'Geçersiz ödeme yöntemi: "$raw". Yalnızca "CASH" veya "CARD" kabul edilir.',
        ),
    };
  }

  /// Kanonik `'CASH'` / `'CARD'` eşleşirse [PaymentMethod], aksi halde `null` döner.
  static PaymentMethod? tryParse(Object? raw) {
    if (raw == 'CASH') return PaymentMethod.cash;
    if (raw == 'CARD') return PaymentMethod.card;
    return null;
  }

  /// Değerin kesin kanonik `'CASH'` veya `'CARD'` olup olmadığını kontrol eder.
  static bool isCanonical(Object? raw) => raw == 'CASH' || raw == 'CARD';

  /// Tarihsel kalıcı DB kayıtlarını veri kaybı olmadan okumak için salt-okunur yardımcı.
  ///
  /// Yeni satış oluşturmada veya API kabul doğrulamasında kesinlikle kullanılmaz.
  static PaymentMethod? tryParseLegacyReadOnly(Object? raw) {
    return switch (raw) {
      'CASH' || 'NAKIT' => PaymentMethod.cash,
      'CARD' || 'CREDIT_CARD' => PaymentMethod.card,
      _ => null,
    };
  }
}

