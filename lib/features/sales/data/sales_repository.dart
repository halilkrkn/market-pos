import 'package:mms_client_storage/mms_client_storage.dart';
import '../../../core/storage/local_database_service.dart';
import '../domain/models/sale_history_filter.dart';

abstract interface class SalesRepository {
  Future<List<LocalSale>> getSales({
    SaleHistoryFilter? filter,
    int limit = 50,
    int offset = 0,
  });

  Future<SaleWithDetails?> getSaleDetail(String saleId);

  Future<void> cancelSale({
    required String saleId,
    required String reason,
    required String deviceId,
  });

  Future<String> refundSale({
    required String saleId,
    required List<RefundItemInput> items,
    required String reason,
    required String deviceId,
  });
}

class LocalSalesRepository implements SalesRepository {
  final LocalDatabaseService _dbService;

  LocalSalesRepository(this._dbService);

  ClientStorageRepository get _repo => _dbService.repository;

  @override
  Future<List<LocalSale>> getSales({
    SaleHistoryFilter? filter,
    int limit = 50,
    int offset = 0,
  }) async {
    return _repo.getSalesHistory(
      startDate: filter?.startDate,
      endDate: filter?.endDate,
      paymentMethod: filter?.paymentMethod,
      status: filter?.status,
      searchQuery: filter?.searchQuery,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<SaleWithDetails?> getSaleDetail(String saleId) async {
    return _repo.getSaleDetail(saleId);
  }

  @override
  Future<void> cancelSale({
    required String saleId,
    required String reason,
    required String deviceId,
  }) async {
    return _repo.cancelSale(
      saleId: saleId,
      reason: reason,
      deviceId: deviceId,
    );
  }

  @override
  Future<String> refundSale({
    required String saleId,
    required List<RefundItemInput> items,
    required String reason,
    required String deviceId,
  }) async {
    return _repo.refundSale(
      saleId: saleId,
      items: items,
      reason: reason,
      deviceId: deviceId,
    );
  }
}
