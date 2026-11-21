import 'package:mms_client_storage/mms_client_storage.dart';
import '../domain/models/sale_history_filter.dart';

class SalesHistoryState {
  final bool isLoading;
  final List<LocalSale> sales;
  final SaleWithDetails? selectedSaleDetail;
  final SaleHistoryFilter filter;
  final String? errorMessage;
  final String? actionSuccessMessage;

  const SalesHistoryState({
    this.isLoading = false,
    this.sales = const [],
    this.selectedSaleDetail,
    this.filter = const SaleHistoryFilter(),
    this.errorMessage,
    this.actionSuccessMessage,
  });

  /// Toplam satış adedi
  int get totalSalesCount => sales.length;

  /// Brüt satış toplamı (kuruş)
  int get totalGrossAmount =>
      sales.fold(0, (sum, s) => sum + s.totalAmount);

  /// İptal edilen satışların toplamı (kuruş)
  int get totalCancelledAmount => sales
      .where((s) => s.status == 'CANCELLED')
      .fold(0, (sum, s) => sum + s.totalAmount);

  SalesHistoryState copyWith({
    bool? isLoading,
    List<LocalSale>? sales,
    SaleWithDetails? selectedSaleDetail,
    SaleHistoryFilter? filter,
    String? errorMessage,
    String? actionSuccessMessage,
    bool clearSelectedDetail = false,
    bool clearMessages = false,
    bool clearError = false,
  }) {
    return SalesHistoryState(
      isLoading: isLoading ?? this.isLoading,
      sales: sales ?? this.sales,
      selectedSaleDetail:
          clearSelectedDetail ? null : (selectedSaleDetail ?? this.selectedSaleDetail),
      filter: filter ?? this.filter,
      errorMessage: (clearMessages || clearError)
          ? null
          : (errorMessage ?? this.errorMessage),
      actionSuccessMessage:
          clearMessages ? null : (actionSuccessMessage ?? this.actionSuccessMessage),
    );
  }
}
