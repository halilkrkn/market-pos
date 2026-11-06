/// MARKET MMS - Genel İstemci Sabitleri
class AppConstants {
  static const String appName = 'Market Management System (MMS)';
  static const String appVersion = '1.0.0';

  // Varsayılan Yerel Master Hub Bağlantı Bilgileri
  static const String defaultBackendHost = '127.0.0.1';
  static const int defaultBackendPort = 8080;
  static const String defaultBackendBaseUrl = 'http://127.0.0.1:8080';

  // Windows İstemci Varsayılan Cihaz Kimliği
  static const String defaultDeviceId = 'POS-WIN-01';
  static const String defaultDeviceRole = 'CASHIER_DESKTOP';

  // Veritabanı ve Depolama
  static const String localDatabaseName = 'client_local.db';
  static const String appDataFolderName = 'MarketMMS';

  // Ağ Zaman Aşımı (ms)
  static const Duration defaultTimeout = Duration(seconds: 5);
}
