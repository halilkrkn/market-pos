class RefundItemInput {
  final String saleItemId;
  final int quantity; // Milli-scale (1000 = 1 adet / 1 kg)
  final String productCondition; // 'SELLABLE', 'DAMAGED'

  const RefundItemInput({
    required this.saleItemId,
    required this.quantity,
    this.productCondition = 'SELLABLE',
  });
}
