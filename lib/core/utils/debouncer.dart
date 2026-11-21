import 'dart:async';

/// Arama girişi ve hızlı kullanıcı etkileşimlerinde gereksiz yeniden
/// sorgulama ve arayüz tazelemelerini azaltan dispose-güvenli geciktirici.
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({this.delay = const Duration(milliseconds: 250)});

  bool get isPending => _timer?.isActive ?? false;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void runImmediate(void Function() action) {
    _timer?.cancel();
    _timer = null;
    action();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    cancel();
  }
}
