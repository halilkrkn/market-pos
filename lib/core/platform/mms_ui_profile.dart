import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/design_tokens.dart';

/// Uygulamanın çalıştığı kullanıcı arayüzü etkileşim profili.
///
/// Genişlik tabanlı kırılımlardan (`MmsWindowClass`) bağımsız olarak
/// Windows masaüstü klavye/USB-HID ergonomisi ile Android telefon/tablet
/// dokunmatik ergonomisini birbirinden ayırır.
enum MmsPlatformMode {
  desktop,
  mobile,
}

@immutable
class MmsUiProfile {
  final MmsPlatformMode mode;

  const MmsUiProfile.desktop() : mode = MmsPlatformMode.desktop;

  const MmsUiProfile.mobile() : mode = MmsPlatformMode.mobile;

  bool get isMobile => mode == MmsPlatformMode.mobile;

  bool get isDesktop => mode == MmsPlatformMode.desktop;

  /// Windows masaüstünde `[F1]`, `[F2]`, `[F9]`, `[F10]`, `[Esc]` ipuçları gösterilir;
  /// Android telefon/tablette masaüstü klavye kısayol ipuçları gizlenir.
  bool get showKeyboardShortcuts => isDesktop;

  /// Windows masaüstü fonksiyon kısayolları (`F1`, `F2`, `F9`, `F10`) yalnızca masaüstünde aktiftir.
  bool get enableDesktopFunctionShortcuts => isDesktop;

  /// Windows USB HID ve Android Bluetooth/USB-OTG harici barkod okuyucu yakalaması aktiftir.
  bool get enableGlobalHidScannerCapture => true;

  /// Windows'ta USB HID fiziksel barkod okuyucu için sürekli odak korunur;
  /// Android'de ekran klavyesinin kendiliğinden açılmasını önlemek için kapalıdır.
  bool get enableHardwareBarcodeAutofocus => isDesktop;

  /// `enableHardwareBarcodeAutofocus` ile tutarlı olarak barkod alanına otomatik odak dönüşünü belirtir.
  bool get keepBarcodeFieldFocused => isDesktop;

  /// Android/iOS mobil cihazlarda kamera ile barkod tarama desteği aktiftir;
  /// Windows masaüstü profilinde USB HID okuyucu esastır ve kamera düğmeleri gizlenir.
  bool get supportsCameraBarcodeScanning => isMobile;

  /// Android dokunmatik hedefler için katı `>= 48dp` Fitts standardı.
  double get minTouchTarget => isMobile ? 48.0 : 44.0;

  /// Mobil görünüm iskeleti ve tek elle dokunmatik POS akışı kullanılıp kullanılmayacağı.
  /// Masaüstünde daraltılmış pencere (`compact`) taşmaları önlemek için mobil görünüme geçer.
  bool useMobileLayout(MmsWindowClass windowClass) =>
      isMobile || windowClass == MmsWindowClass.compact;

  /// Yalnızca masaüstü geniş ekranda sol Emerald sidebar gösterilir.
  bool showDesktopSidebar(MmsWindowClass windowClass) =>
      isDesktop && windowClass == MmsWindowClass.expanded;

  /// Masaüstü klavye kısayol alt çubuğu yalnızca masaüstü profilinde ve dar olmayan pencerede görünür.
  bool showDesktopShortcutFooter(MmsWindowClass windowClass) =>
      isDesktop && windowClass != MmsWindowClass.compact;

  /// Kompakt telefon genişliğinde alt navigasyon barı, tablette yan `NavigationRail` kullanılır.
  bool useMobileBottomNavigation(MmsWindowClass windowClass) =>
      windowClass == MmsWindowClass.compact;

  /// Çalışan işletim sistemine göre varsayılan UI profilini belirler.
  static MmsUiProfile detectCurrentPlatform({
    bool? isAndroidOverride,
    bool? isIosOverride,
  }) {
    final isAndroid = isAndroidOverride ?? Platform.isAndroid;
    final isIos = isIosOverride ?? Platform.isIOS;
    if (isAndroid || isIos) {
      return const MmsUiProfile.mobile();
    }
    return const MmsUiProfile.desktop();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MmsUiProfile &&
          runtimeType == other.runtimeType &&
          mode == other.mode;

  @override
  int get hashCode => mode.hashCode;
}

/// Platform UI profili sağlayıcısı. Widget/ekran testlerinde kolayca override edilebilir.
final mmsUiProfileProvider = Provider<MmsUiProfile>((ref) {
  return MmsUiProfile.detectCurrentPlatform();
});
