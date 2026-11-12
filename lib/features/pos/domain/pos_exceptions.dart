/// Faz 1.2 POS iş kuralları ihlallerini temsil eden saf Dart istisnası.
class PosDomainException implements Exception {
  final String message;

  const PosDomainException(this.message);

  @override
  String toString() => 'PosDomainException: $message';
}
