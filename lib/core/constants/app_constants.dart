/// MARKET MMS - Genel İstemci Sabitleri
class AppConstants {
  static const String appName = 'Market Management System (MMS)';
  static const String appVersion = '1.0.2';

  // Varsayılan Yerel Master Hub Bağlantı Bilgileri (Port 8945 veya derleme ortam değişkeni)
  static const String defaultBackendHost =
      String.fromEnvironment('MMS_HUB_HOST', defaultValue: '127.0.0.1');
  static const int defaultBackendPort =
      int.fromEnvironment('MMS_HUB_PORT', defaultValue: 8945);
  static const String defaultBackendBaseUrl = String.fromEnvironment(
    'MMS_HUB_URL',
    defaultValue: 'https://127.0.0.1:8945',
  );

  /// Derleme zamanında açıkça tanımlanmış `MMS_HUB_URL` ortam değişkeni;
  /// tanımlanmadıysa boş string döner (Android'de loopback fallback kullanılmaz).
  static const String configuredBackendBaseUrl = String.fromEnvironment(
    'MMS_HUB_URL',
    defaultValue: '',
  );

  /// Yalnızca masaüstü/Windows istemcisinde kullanılan yerel loopback fallback adresi.
  static String get windowsLocalhostFallbackUrl =>
      'https://$defaultBackendHost:$defaultBackendPort';

  // Cihaz Kimliği ve Yetkilendirme Belirteci
  static const String defaultDeviceId = String.fromEnvironment(
    'MMS_DEVICE_ID',
    defaultValue: 'POS-WIN-01',
  );
  static const String defaultDeviceRole = 'CASHIER_DESKTOP';
  /// SEC (Faz 7B): Derlemeye gömülü varsayılan token kaldırıldı. Cihaz token'ı yalnızca
  /// eşleştirme (pairing) sonrası OS güvenli deposundan (DPAPI / Android Keystore) okunur.
  /// Yerel geliştirme için açıkça `--dart-define=MMS_DEVICE_TOKEN=...` verilebilir;
  /// verilmezse boş kalır ve token yoksa senkronizasyon fail-closed durur.
  static const String defaultDeviceToken = String.fromEnvironment(
    'MMS_DEVICE_TOKEN',
    defaultValue: '',
  );

  // Veritabanı ve Depolama
  static const String localDatabaseName = 'client_local.db';
  static const String appDataFolderName = 'MarketMMS';

  // Ağ Zaman Aşımı (ms)
  static const Duration defaultTimeout = Duration(seconds: 5);
}
