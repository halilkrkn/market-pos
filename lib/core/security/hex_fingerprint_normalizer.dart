/// SHA-256 sertifika / açık anahtar hex parmak izi normalizasyonu (saf Dart).
abstract final class HexFingerprintNormalizer {
  static String normalizeHex(String raw) {
    return raw.replaceAll(':', '').replaceAll(' ', '').trim().toUpperCase();
  }
}
