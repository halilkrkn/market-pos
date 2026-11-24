import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/user_friendly_error_mapper.dart';
import '../domain/barcode_input_sanitizer.dart';
import '../domain/cart_state.dart';
import '../domain/money.dart';
import '../domain/pos_exceptions.dart';
import '../domain/pos_product.dart';
import '../domain/pos_repository.dart';

/// POS sepet, barkod ve atomik satış tamamlama durum yöneticisi (`BR-POS`, `BR-PAY`).
class CartNotifier extends StateNotifier<CartState> {
  final PosRepository repository;
  final String Function() readDeviceId;
  final bool Function()? isHubOffline;
  final Future<void> Function()? onSaleCommitted;
  bool _isCompletingSale = false;

  CartNotifier({
    required this.repository,
    required this.readDeviceId,
    this.isHubOffline,
    this.onSaleCommitted,
  }) : super(CartState.empty());

  /// Barkod okutulduğunda yerel katalogdan sorgular; pasif ve bilinmeyen barkodları reddeder (`OD-03`, `R-01`).
  Future<bool> scanBarcode(String rawBarcode) async {
    final sanitized = BarcodeInputSanitizer.sanitize(rawBarcode);
    if (!sanitized.isValid) {
      if (!mounted) return false;
      state = state.copyWith(
        errorMessage: sanitized.errorMessage,
        infoMessage: null,
      );
      return false;
    }

    try {
      final result = await repository.findByBarcode(sanitized.normalized);
      if (!mounted) return false;
      switch (result.status) {
        case BarcodeLookupStatus.found:
          return addProduct(result.product!);
        case BarcodeLookupStatus.inactiveProduct:
          state = state.copyWith(
            errorMessage:
                'Pasif ürün satışa eklenemez: ${result.product?.name ?? sanitized.normalized}.',
            infoMessage: null,
          );
          return false;
        case BarcodeLookupStatus.notFoundOffline:
          state = state.copyWith(
            errorMessage:
                'Barkod yerel katalogda bulunamadı (${result.barcode}). Tanımsız ürün doğrudan sepete eklenemez; ürünü Ürünler ekranından ekleyebilir veya Master Hub ile senkronize edebilirsiniz.',
            infoMessage: null,
          );
          return false;
      }
    } on PosDomainException catch (e) {
      state = state.copyWith(errorMessage: e.message, infoMessage: null);
      return false;
    } catch (e, stack) {
      debugPrint(
        UserFriendlyErrorMapper.redactSecrets(
          '[CartNotifier] Barkod sorgu hatası: $e\n$stack',
        ),
      );
      state = state.copyWith(
        errorMessage: 'Barkod sorgulanırken beklenmeyen bir hata oluştu.',
        infoMessage: null,
      );
      return false;
    }
  }

  /// Doğrulanmış yerel katalog ürününü sepete ekler (`BR-POS-02`).
  bool addProduct(
    PosProduct product, {
    int quantityMilli = Money.quantityScale,
  }) {
    try {
      state = state.addProduct(product, quantityMilli: quantityMilli);
      return true;
    } on PosDomainException catch (e) {
      state = state.copyWith(errorMessage: e.message, infoMessage: null);
      return false;
    } on ArgumentError catch (e) {
      state = state.copyWith(
        errorMessage: e.message?.toString() ?? 'Geçersiz ürün bilgisi.',
        infoMessage: null,
      );
      return false;
    }
  }

  void incrementProduct(String productId) {
    try {
      state = state.incrementProduct(productId);
    } on PosDomainException catch (e) {
      state = state.copyWith(errorMessage: e.message, infoMessage: null);
    } on ArgumentError catch (e) {
      state = state.copyWith(
        errorMessage: e.message?.toString() ?? 'Miktar artırılamadı.',
        infoMessage: null,
      );
    }
  }

  void decrementProduct(String productId) {
    try {
      state = state.decrementProduct(productId);
    } on PosDomainException catch (e) {
      state = state.copyWith(errorMessage: e.message, infoMessage: null);
    }
  }

  /// F2 / satır içi miktar düzenlemesini milli ölçekte (1000) günceller; `0` ise satırı siler.
  bool updateQuantityFromInput({
    required String productId,
    required String rawQuantity,
  }) {
    final parsedMilli = Money.tryParseQuantityToMilli(rawQuantity);
    if (parsedMilli == null) {
      state = state.copyWith(
        errorMessage:
            'Geçersiz miktar girdisi. En fazla 3 ondalık haneli sayı giriniz (ör. 1, 0.5, 0.345).',
        infoMessage: null,
      );
      return false;
    }

    try {
      state = state.setQuantity(productId: productId, quantityMilli: parsedMilli);
      return true;
    } on PosDomainException catch (e) {
      state = state.copyWith(errorMessage: e.message, infoMessage: null);
      return false;
    } on ArgumentError catch (e) {
      state = state.copyWith(
        errorMessage: e.message?.toString() ?? 'Miktar güncellenemedi.',
        infoMessage: null,
      );
      return false;
    }
  }

  void removeProduct(String productId) {
    state = state.removeProduct(productId);
  }

  void selectProduct(String? productId) {
    state = state.selectProduct(productId);
  }

  void clearCart() {
    state = CartState.empty(infoMessage: 'Sepet temizlendi.');
  }

  void clearMessages() {
    state = state.copyWith(errorMessage: null, infoMessage: null);
  }

  /// Kanonik `PaymentMethod` (`CASH` / `CARD`) doğrulamasıyla satışı atomik kaydeder (`BR-POS-07`).
  Future<PosCompletedSale?> completeSale({
    required PaymentMethod paymentMethod,
    int? cashReceivedCents,
    bool externalPosConfirmed = false,
  }) async {
    // Eş zamanlı mükerrer satış gönderimini henüz hiçbir await öncesi kilitle
    if (_isCompletingSale || state.isProcessing) {
      return null;
    }
    _isCompletingSale = true;

    try {
      if (!state.canCheckout) {
        state = state.copyWith(
          errorMessage: state.isEmpty
              ? 'Satış tamamlanabilmesi için sepette en az bir ürün olmalıdır.'
              : 'Toplam satış tutarı 0.00 TL\'den büyük olmalıdır.',
          infoMessage: null,
        );
        return null;
      }

      if (paymentMethod == PaymentMethod.cash) {
        if (cashReceivedCents == null || cashReceivedCents < state.totalCents) {
          state = state.copyWith(
            errorMessage: 'Alınan nakit tutar toplam satış tutarından az olamaz.',
            infoMessage: null,
          );
          return null;
        }
      } else {
        if (cashReceivedCents != null) {
          state = state.copyWith(
            errorMessage: 'Kart satışında nakit tutar alanı boş olmalıdır.',
            infoMessage: null,
          );
          return null;
        }
        if (!externalPosConfirmed) {
          state = state.copyWith(
            errorMessage:
                'Kart ödemesi için tutarın harici POS terminaline elle girildiğini teyit ediniz.',
            infoMessage: null,
          );
          return null;
        }
      }

      state = state.copyWith(
        isProcessing: true,
        errorMessage: null,
        infoMessage: null,
      );

      final PosCompletedSale completed;
      try {
        completed = await repository.completeOfflineSale(
          deviceId: readDeviceId(),
          cart: state,
          paymentMethod: paymentMethod,
          cashReceivedCents: cashReceivedCents,
          externalPosConfirmed: externalPosConfirmed,
        );
      } on PosDomainException catch (e) {
        state = state.copyWith(
          isProcessing: false,
          errorMessage: e.message,
        );
        return null;
      } on ArgumentError catch (e) {
        state = state.copyWith(
          isProcessing: false,
          errorMessage: e.message?.toString() ?? 'Satış verileri geçersiz.',
        );
        return null;
      } on StateError catch (e) {
        state = state.copyWith(
          isProcessing: false,
          errorMessage: e.message,
        );
        return null;
      } catch (e, stack) {
        debugPrint(
          UserFriendlyErrorMapper.redactSecrets(
            '[CartNotifier] Satış kaydetme hatası: $e\n$stack',
          ),
        );
        state = state.copyWith(
          isProcessing: false,
          errorMessage:
              'Satış yerel veritabanına kaydedilemedi. Lütfen tekrar deneyin.',
        );
        return null;
      }

      final methodLabel =
          completed.paymentMethod == PaymentMethod.cash ? 'Nakit' : 'Kart';
      final changeNote = completed.cashChangeCents != null
          ? ' • Para Üstü: ${Money.formatCents(completed.cashChangeCents!)}'
          : '';
      final offline = isHubOffline?.call() ?? false;
      final completionMessage = offline
          ? 'Satış çevrimdışı kaydedildi ($methodLabel • ${Money.formatCents(completed.totalAmountCents)}$changeNote). Bağlantı sağlandığında otomatik senkronize edilecektir.'
          : 'Satış tamamlandı ($methodLabel • ${Money.formatCents(completed.totalAmountCents)}$changeNote).';

      state = CartState.empty(
        lastCompletedSale: completed,
        infoMessage: completionMessage,
      );

      // Veritabanı işlemi kesinleştikten sonra callback hatası satışı geri almaz/başarısız göstermez
      if (onSaleCommitted != null) {
        try {
          await onSaleCommitted!();
        } catch (e, stack) {
          debugPrint(
            UserFriendlyErrorMapper.redactSecrets(
              '[CartNotifier] Satış sonrası durum yenileme hatası (satış kaydedildi): $e\n$stack',
            ),
          );
        }
      }
      return completed;
    } finally {
      _isCompletingSale = false;
    }
  }
}

