import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';
import '../data/sales_repository.dart';
import '../domain/models/sale_history_filter.dart';
import 'sales_history_state.dart';

class SalesHistoryNotifier extends StateNotifier<SalesHistoryState> {
  final SalesRepository _repository;
  final String _deviceId;
  int _loadEpoch = 0;

  SalesHistoryNotifier(this._repository, this._deviceId)
      : super(const SalesHistoryState()) {
    loadSales();
  }

  Future<void> loadSales({bool silent = false}) async {
    if (!mounted) return;
    final requestEpoch = ++_loadEpoch;
    if (!silent) {
      state = state.copyWith(isLoading: true, clearMessages: true);
    }
    try {
      final filterSnapshot = state.filter;
      final sales = await _repository.getSales(filter: filterSnapshot);
      if (!mounted || requestEpoch != _loadEpoch) return;
      state = state.copyWith(
        isLoading: false,
        sales: sales,
        clearError: true,
      );
    } catch (e) {
      if (!mounted || requestEpoch != _loadEpoch) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Satış geçmişi yüklenirken hata oluştu: $e',
      );
    }
  }

  void setFilter(SaleHistoryFilter newFilter) {
    if (!mounted) return;
    state = state.copyWith(filter: newFilter);
    loadSales();
  }

  Future<void> selectSale(String saleId) async {
    if (!mounted) return;
    state = state.copyWith(isLoading: true, clearMessages: true);
    try {
      final detail = await _repository.getSaleDetail(saleId);
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        selectedSaleDetail: detail,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Fiş detayları yüklenemedi: $e',
      );
    }
  }

  void clearSelectedSale() {
    if (!mounted) return;
    state = state.copyWith(clearSelectedDetail: true);
  }

  Future<bool> cancelSale({
    required String saleId,
    required String reason,
  }) async {
    if (!mounted) return false;
    ++_loadEpoch;
    state = state.copyWith(isLoading: true, clearMessages: true);
    try {
      await _repository.cancelSale(
        saleId: saleId,
        reason: reason,
        deviceId: _deviceId,
      );
      if (!mounted) return false;

      // Listeyi ve seçili fiş detayını yeniden yükle; önceki eski loadSales yanıtları ezmesin
      ++_loadEpoch;
      final sales = await _repository.getSales(filter: state.filter);
      if (!mounted) return false;
      final updatedDetail = await _repository.getSaleDetail(saleId);
      if (!mounted) return false;

      state = state.copyWith(
        isLoading: false,
        sales: sales,
        selectedSaleDetail: updatedDetail,
        actionSuccessMessage:
            'Satış başarıyla iptal edildi ve stoklar iade edildi.',
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Satış iptali başarısız oldu: $e',
      );
      return false;
    }
  }

  Future<bool> refundSale({
    required String saleId,
    required List<RefundItemInput> items,
    required String reason,
  }) async {
    if (!mounted) return false;
    ++_loadEpoch;
    state = state.copyWith(isLoading: true, clearMessages: true);
    try {
      await _repository.refundSale(
        saleId: saleId,
        items: items,
        reason: reason,
        deviceId: _deviceId,
      );
      if (!mounted) return false;

      // Listeyi ve seçili fiş detayını yeniden yükle; önceki eski loadSales yanıtları ezmesin
      ++_loadEpoch;
      final sales = await _repository.getSales(filter: state.filter);
      if (!mounted) return false;
      final updatedDetail = await _repository.getSaleDetail(saleId);
      if (!mounted) return false;

      state = state.copyWith(
        isLoading: false,
        sales: sales,
        selectedSaleDetail: updatedDetail,
        actionSuccessMessage: 'İade işlemi başarıyla tamamlandı.',
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'İade işlemi başarısız oldu: $e',
      );
      return false;
    }
  }
}
