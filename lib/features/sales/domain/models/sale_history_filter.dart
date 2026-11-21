class SaleHistoryFilter {
  final DateTime? startDate;
  final DateTime? endDate;
  final String? paymentMethod; // null / 'CASH' / 'CARD'
  final String? status; // null / 'COMPLETED' / 'CANCELLED' / 'REFUNDED'
  final String? searchQuery;

  const SaleHistoryFilter({
    this.startDate,
    this.endDate,
    this.paymentMethod,
    this.status,
    this.searchQuery,
  });

  SaleHistoryFilter copyWith({
    DateTime? startDate,
    DateTime? endDate,
    String? paymentMethod,
    String? status,
    String? searchQuery,
    bool clearDates = false,
  }) {
    return SaleHistoryFilter(
      startDate: clearDates ? null : (startDate ?? this.startDate),
      endDate: clearDates ? null : (endDate ?? this.endDate),
      paymentMethod: paymentMethod ?? this.paymentMethod,
      status: status ?? this.status,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}
