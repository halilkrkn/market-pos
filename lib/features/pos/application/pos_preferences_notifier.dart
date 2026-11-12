import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Kasa arayüzü kullanıcı tercihlerinin değişmez durumu (`OD-04`).
class PosPreferencesState {
  /// Masaüstü sanal numpad görünürlüğü — `OD-04` gereği varsayılan olarak kapalıdır (`false`).
  final bool showVirtualNumpad;

  const PosPreferencesState({this.showVirtualNumpad = false});

  PosPreferencesState copyWith({bool? showVirtualNumpad}) {
    return PosPreferencesState(
      showVirtualNumpad: showVirtualNumpad ?? this.showVirtualNumpad,
    );
  }
}

/// Opsiyonel masaüstü sanal numpad ve POS tercih yöneticisi (`OD-04`).
class PosPreferencesNotifier extends StateNotifier<PosPreferencesState> {
  PosPreferencesNotifier() : super(const PosPreferencesState());

  void toggleVirtualNumpad() {
    state = state.copyWith(showVirtualNumpad: !state.showVirtualNumpad);
  }

  void setVirtualNumpad(bool enabled) {
    state = state.copyWith(showVirtualNumpad: enabled);
  }
}
