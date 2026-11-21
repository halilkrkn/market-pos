/// Saf Dart tarih/saat biçimlendirme yardımcıları (Dış paket bağımlılığı gerektirmez).
extension DateTimeFormatter on DateTime {
  /// 'dd.MM.yyyy HH:mm' veya 'dd.MM.yyyy HH:mm:ss' biçiminde metne çevirir.
  String toFormattedDateTime({bool includeSeconds = false}) {
    final d = day.toString().padLeft(2, '0');
    final m = month.toString().padLeft(2, '0');
    final y = year.toString();
    final h = hour.toString().padLeft(2, '0');
    final min = minute.toString().padLeft(2, '0');
    if (includeSeconds) {
      final s = second.toString().padLeft(2, '0');
      return '$d.$m.$y $h:$min:$s';
    }
    return '$d.$m.$y $h:$min';
  }

  /// 'dd.MM' biçiminde gün/ay döner.
  String toFormattedShortDate() {
    final d = day.toString().padLeft(2, '0');
    final m = month.toString().padLeft(2, '0');
    return '$d.$m';
  }
}
