/// MARKET MMS ana modül hedefleri.
///
/// İleride `go_router` derin bağlantı ihtiyacı doğduğunda doğrudan rota
/// eşlemesi için tek kaynak olarak tanımlanmıştır.
enum AppDestination {
  pos,
  dashboard,
  catalog,
  stock,
  sales,
  diagnostics,
}

extension AppDestinationX on AppDestination {
  int get navIndex => index;

  static AppDestination fromIndex(int index) {
    if (index < 0 || index >= AppDestination.values.length) {
      return AppDestination.pos;
    }
    return AppDestination.values[index];
  }
}
