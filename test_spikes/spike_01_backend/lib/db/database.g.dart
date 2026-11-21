// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ProductsTable extends Products with TableInfo<$ProductsTable, Product> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _barcodeMeta =
      const VerificationMeta('barcode');
  @override
  late final GeneratedColumn<String> barcode = GeneratedColumn<String>(
      'barcode', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<int> price = GeneratedColumn<int>(
      'price', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _priceVersionIdMeta =
      const VerificationMeta('priceVersionId');
  @override
  late final GeneratedColumn<String> priceVersionId = GeneratedColumn<String>(
      'price_version_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pv_init'));
  static const VerificationMeta _stockMeta = const VerificationMeta('stock');
  @override
  late final GeneratedColumn<int> stock = GeneratedColumn<int>(
      'stock', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _stockUnitMeta =
      const VerificationMeta('stockUnit');
  @override
  late final GeneratedColumn<String> stockUnit = GeneratedColumn<String>(
      'stock_unit', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('adet'));
  static const VerificationMeta _pricingUnitMeta =
      const VerificationMeta('pricingUnit');
  @override
  late final GeneratedColumn<String> pricingUnit = GeneratedColumn<String>(
      'pricing_unit', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('adet'));
  static const VerificationMeta _conversionFactorNumeratorMeta =
      const VerificationMeta('conversionFactorNumerator');
  @override
  late final GeneratedColumn<int> conversionFactorNumerator =
      GeneratedColumn<int>('conversion_factor_numerator', aliasedName, false,
          type: DriftSqlType.int,
          requiredDuringInsert: false,
          defaultValue: const Constant(1));
  static const VerificationMeta _conversionFactorDenominatorMeta =
      const VerificationMeta('conversionFactorDenominator');
  @override
  late final GeneratedColumn<int> conversionFactorDenominator =
      GeneratedColumn<int>('conversion_factor_denominator', aliasedName, false,
          type: DriftSqlType.int,
          requiredDuringInsert: false,
          defaultValue: const Constant(1));
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        barcode,
        name,
        price,
        priceVersionId,
        stock,
        stockUnit,
        pricingUnit,
        conversionFactorNumerator,
        conversionFactorDenominator,
        isActive,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'products';
  @override
  VerificationContext validateIntegrity(Insertable<Product> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('barcode')) {
      context.handle(_barcodeMeta,
          barcode.isAcceptableOrUnknown(data['barcode']!, _barcodeMeta));
    } else if (isInserting) {
      context.missing(_barcodeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('price')) {
      context.handle(
          _priceMeta, price.isAcceptableOrUnknown(data['price']!, _priceMeta));
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('price_version_id')) {
      context.handle(
          _priceVersionIdMeta,
          priceVersionId.isAcceptableOrUnknown(
              data['price_version_id']!, _priceVersionIdMeta));
    }
    if (data.containsKey('stock')) {
      context.handle(
          _stockMeta, stock.isAcceptableOrUnknown(data['stock']!, _stockMeta));
    } else if (isInserting) {
      context.missing(_stockMeta);
    }
    if (data.containsKey('stock_unit')) {
      context.handle(_stockUnitMeta,
          stockUnit.isAcceptableOrUnknown(data['stock_unit']!, _stockUnitMeta));
    }
    if (data.containsKey('pricing_unit')) {
      context.handle(
          _pricingUnitMeta,
          pricingUnit.isAcceptableOrUnknown(
              data['pricing_unit']!, _pricingUnitMeta));
    }
    if (data.containsKey('conversion_factor_numerator')) {
      context.handle(
          _conversionFactorNumeratorMeta,
          conversionFactorNumerator.isAcceptableOrUnknown(
              data['conversion_factor_numerator']!,
              _conversionFactorNumeratorMeta));
    }
    if (data.containsKey('conversion_factor_denominator')) {
      context.handle(
          _conversionFactorDenominatorMeta,
          conversionFactorDenominator.isAcceptableOrUnknown(
              data['conversion_factor_denominator']!,
              _conversionFactorDenominatorMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {barcode},
      ];
  @override
  Product map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Product(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      barcode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}barcode'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      price: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}price'])!,
      priceVersionId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}price_version_id'])!,
      stock: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}stock'])!,
      stockUnit: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}stock_unit'])!,
      pricingUnit: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}pricing_unit'])!,
      conversionFactorNumerator: attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}conversion_factor_numerator'])!,
      conversionFactorDenominator: attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}conversion_factor_denominator'])!,
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ProductsTable createAlias(String alias) {
    return $ProductsTable(attachedDatabase, alias);
  }
}

class Product extends DataClass implements Insertable<Product> {
  final String id;
  final String barcode;
  final String name;
  final int price;
  final String priceVersionId;
  final int stock;
  final String stockUnit;
  final String pricingUnit;
  final int conversionFactorNumerator;
  final int conversionFactorDenominator;
  final bool isActive;
  final DateTime updatedAt;
  const Product(
      {required this.id,
      required this.barcode,
      required this.name,
      required this.price,
      required this.priceVersionId,
      required this.stock,
      required this.stockUnit,
      required this.pricingUnit,
      required this.conversionFactorNumerator,
      required this.conversionFactorDenominator,
      required this.isActive,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['barcode'] = Variable<String>(barcode);
    map['name'] = Variable<String>(name);
    map['price'] = Variable<int>(price);
    map['price_version_id'] = Variable<String>(priceVersionId);
    map['stock'] = Variable<int>(stock);
    map['stock_unit'] = Variable<String>(stockUnit);
    map['pricing_unit'] = Variable<String>(pricingUnit);
    map['conversion_factor_numerator'] =
        Variable<int>(conversionFactorNumerator);
    map['conversion_factor_denominator'] =
        Variable<int>(conversionFactorDenominator);
    map['is_active'] = Variable<bool>(isActive);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProductsCompanion toCompanion(bool nullToAbsent) {
    return ProductsCompanion(
      id: Value(id),
      barcode: Value(barcode),
      name: Value(name),
      price: Value(price),
      priceVersionId: Value(priceVersionId),
      stock: Value(stock),
      stockUnit: Value(stockUnit),
      pricingUnit: Value(pricingUnit),
      conversionFactorNumerator: Value(conversionFactorNumerator),
      conversionFactorDenominator: Value(conversionFactorDenominator),
      isActive: Value(isActive),
      updatedAt: Value(updatedAt),
    );
  }

  factory Product.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Product(
      id: serializer.fromJson<String>(json['id']),
      barcode: serializer.fromJson<String>(json['barcode']),
      name: serializer.fromJson<String>(json['name']),
      price: serializer.fromJson<int>(json['price']),
      priceVersionId: serializer.fromJson<String>(json['priceVersionId']),
      stock: serializer.fromJson<int>(json['stock']),
      stockUnit: serializer.fromJson<String>(json['stockUnit']),
      pricingUnit: serializer.fromJson<String>(json['pricingUnit']),
      conversionFactorNumerator:
          serializer.fromJson<int>(json['conversionFactorNumerator']),
      conversionFactorDenominator:
          serializer.fromJson<int>(json['conversionFactorDenominator']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'barcode': serializer.toJson<String>(barcode),
      'name': serializer.toJson<String>(name),
      'price': serializer.toJson<int>(price),
      'priceVersionId': serializer.toJson<String>(priceVersionId),
      'stock': serializer.toJson<int>(stock),
      'stockUnit': serializer.toJson<String>(stockUnit),
      'pricingUnit': serializer.toJson<String>(pricingUnit),
      'conversionFactorNumerator':
          serializer.toJson<int>(conversionFactorNumerator),
      'conversionFactorDenominator':
          serializer.toJson<int>(conversionFactorDenominator),
      'isActive': serializer.toJson<bool>(isActive),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Product copyWith(
          {String? id,
          String? barcode,
          String? name,
          int? price,
          String? priceVersionId,
          int? stock,
          String? stockUnit,
          String? pricingUnit,
          int? conversionFactorNumerator,
          int? conversionFactorDenominator,
          bool? isActive,
          DateTime? updatedAt}) =>
      Product(
        id: id ?? this.id,
        barcode: barcode ?? this.barcode,
        name: name ?? this.name,
        price: price ?? this.price,
        priceVersionId: priceVersionId ?? this.priceVersionId,
        stock: stock ?? this.stock,
        stockUnit: stockUnit ?? this.stockUnit,
        pricingUnit: pricingUnit ?? this.pricingUnit,
        conversionFactorNumerator:
            conversionFactorNumerator ?? this.conversionFactorNumerator,
        conversionFactorDenominator:
            conversionFactorDenominator ?? this.conversionFactorDenominator,
        isActive: isActive ?? this.isActive,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Product copyWithCompanion(ProductsCompanion data) {
    return Product(
      id: data.id.present ? data.id.value : this.id,
      barcode: data.barcode.present ? data.barcode.value : this.barcode,
      name: data.name.present ? data.name.value : this.name,
      price: data.price.present ? data.price.value : this.price,
      priceVersionId: data.priceVersionId.present
          ? data.priceVersionId.value
          : this.priceVersionId,
      stock: data.stock.present ? data.stock.value : this.stock,
      stockUnit: data.stockUnit.present ? data.stockUnit.value : this.stockUnit,
      pricingUnit:
          data.pricingUnit.present ? data.pricingUnit.value : this.pricingUnit,
      conversionFactorNumerator: data.conversionFactorNumerator.present
          ? data.conversionFactorNumerator.value
          : this.conversionFactorNumerator,
      conversionFactorDenominator: data.conversionFactorDenominator.present
          ? data.conversionFactorDenominator.value
          : this.conversionFactorDenominator,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Product(')
          ..write('id: $id, ')
          ..write('barcode: $barcode, ')
          ..write('name: $name, ')
          ..write('price: $price, ')
          ..write('priceVersionId: $priceVersionId, ')
          ..write('stock: $stock, ')
          ..write('stockUnit: $stockUnit, ')
          ..write('pricingUnit: $pricingUnit, ')
          ..write('conversionFactorNumerator: $conversionFactorNumerator, ')
          ..write('conversionFactorDenominator: $conversionFactorDenominator, ')
          ..write('isActive: $isActive, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      barcode,
      name,
      price,
      priceVersionId,
      stock,
      stockUnit,
      pricingUnit,
      conversionFactorNumerator,
      conversionFactorDenominator,
      isActive,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Product &&
          other.id == this.id &&
          other.barcode == this.barcode &&
          other.name == this.name &&
          other.price == this.price &&
          other.priceVersionId == this.priceVersionId &&
          other.stock == this.stock &&
          other.stockUnit == this.stockUnit &&
          other.pricingUnit == this.pricingUnit &&
          other.conversionFactorNumerator == this.conversionFactorNumerator &&
          other.conversionFactorDenominator ==
              this.conversionFactorDenominator &&
          other.isActive == this.isActive &&
          other.updatedAt == this.updatedAt);
}

class ProductsCompanion extends UpdateCompanion<Product> {
  final Value<String> id;
  final Value<String> barcode;
  final Value<String> name;
  final Value<int> price;
  final Value<String> priceVersionId;
  final Value<int> stock;
  final Value<String> stockUnit;
  final Value<String> pricingUnit;
  final Value<int> conversionFactorNumerator;
  final Value<int> conversionFactorDenominator;
  final Value<bool> isActive;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ProductsCompanion({
    this.id = const Value.absent(),
    this.barcode = const Value.absent(),
    this.name = const Value.absent(),
    this.price = const Value.absent(),
    this.priceVersionId = const Value.absent(),
    this.stock = const Value.absent(),
    this.stockUnit = const Value.absent(),
    this.pricingUnit = const Value.absent(),
    this.conversionFactorNumerator = const Value.absent(),
    this.conversionFactorDenominator = const Value.absent(),
    this.isActive = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductsCompanion.insert({
    required String id,
    required String barcode,
    required String name,
    required int price,
    this.priceVersionId = const Value.absent(),
    required int stock,
    this.stockUnit = const Value.absent(),
    this.pricingUnit = const Value.absent(),
    this.conversionFactorNumerator = const Value.absent(),
    this.conversionFactorDenominator = const Value.absent(),
    this.isActive = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        barcode = Value(barcode),
        name = Value(name),
        price = Value(price),
        stock = Value(stock);
  static Insertable<Product> custom({
    Expression<String>? id,
    Expression<String>? barcode,
    Expression<String>? name,
    Expression<int>? price,
    Expression<String>? priceVersionId,
    Expression<int>? stock,
    Expression<String>? stockUnit,
    Expression<String>? pricingUnit,
    Expression<int>? conversionFactorNumerator,
    Expression<int>? conversionFactorDenominator,
    Expression<bool>? isActive,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (barcode != null) 'barcode': barcode,
      if (name != null) 'name': name,
      if (price != null) 'price': price,
      if (priceVersionId != null) 'price_version_id': priceVersionId,
      if (stock != null) 'stock': stock,
      if (stockUnit != null) 'stock_unit': stockUnit,
      if (pricingUnit != null) 'pricing_unit': pricingUnit,
      if (conversionFactorNumerator != null)
        'conversion_factor_numerator': conversionFactorNumerator,
      if (conversionFactorDenominator != null)
        'conversion_factor_denominator': conversionFactorDenominator,
      if (isActive != null) 'is_active': isActive,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductsCompanion copyWith(
      {Value<String>? id,
      Value<String>? barcode,
      Value<String>? name,
      Value<int>? price,
      Value<String>? priceVersionId,
      Value<int>? stock,
      Value<String>? stockUnit,
      Value<String>? pricingUnit,
      Value<int>? conversionFactorNumerator,
      Value<int>? conversionFactorDenominator,
      Value<bool>? isActive,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return ProductsCompanion(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      price: price ?? this.price,
      priceVersionId: priceVersionId ?? this.priceVersionId,
      stock: stock ?? this.stock,
      stockUnit: stockUnit ?? this.stockUnit,
      pricingUnit: pricingUnit ?? this.pricingUnit,
      conversionFactorNumerator:
          conversionFactorNumerator ?? this.conversionFactorNumerator,
      conversionFactorDenominator:
          conversionFactorDenominator ?? this.conversionFactorDenominator,
      isActive: isActive ?? this.isActive,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (barcode.present) {
      map['barcode'] = Variable<String>(barcode.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (price.present) {
      map['price'] = Variable<int>(price.value);
    }
    if (priceVersionId.present) {
      map['price_version_id'] = Variable<String>(priceVersionId.value);
    }
    if (stock.present) {
      map['stock'] = Variable<int>(stock.value);
    }
    if (stockUnit.present) {
      map['stock_unit'] = Variable<String>(stockUnit.value);
    }
    if (pricingUnit.present) {
      map['pricing_unit'] = Variable<String>(pricingUnit.value);
    }
    if (conversionFactorNumerator.present) {
      map['conversion_factor_numerator'] =
          Variable<int>(conversionFactorNumerator.value);
    }
    if (conversionFactorDenominator.present) {
      map['conversion_factor_denominator'] =
          Variable<int>(conversionFactorDenominator.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductsCompanion(')
          ..write('id: $id, ')
          ..write('barcode: $barcode, ')
          ..write('name: $name, ')
          ..write('price: $price, ')
          ..write('priceVersionId: $priceVersionId, ')
          ..write('stock: $stock, ')
          ..write('stockUnit: $stockUnit, ')
          ..write('pricingUnit: $pricingUnit, ')
          ..write('conversionFactorNumerator: $conversionFactorNumerator, ')
          ..write('conversionFactorDenominator: $conversionFactorDenominator, ')
          ..write('isActive: $isActive, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SalesTable extends Sales with TableInfo<$SalesTable, Sale> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SalesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _deviceIdMeta =
      const VerificationMeta('deviceId');
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
      'device_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _clientSeqMeta =
      const VerificationMeta('clientSeq');
  @override
  late final GeneratedColumn<int> clientSeq = GeneratedColumn<int>(
      'client_seq', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _totalAmountMeta =
      const VerificationMeta('totalAmount');
  @override
  late final GeneratedColumn<int> totalAmount = GeneratedColumn<int>(
      'total_amount', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _paymentMethodMeta =
      const VerificationMeta('paymentMethod');
  @override
  late final GeneratedColumn<String> paymentMethod = GeneratedColumn<String>(
      'payment_method', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _serverSeqMeta =
      const VerificationMeta('serverSeq');
  @override
  late final GeneratedColumn<int> serverSeq = GeneratedColumn<int>(
      'server_seq', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('COMPLETED'));
  static const VerificationMeta _cancelReasonMeta =
      const VerificationMeta('cancelReason');
  @override
  late final GeneratedColumn<String> cancelReason = GeneratedColumn<String>(
      'cancel_reason', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _cancelledAtMeta =
      const VerificationMeta('cancelledAt');
  @override
  late final GeneratedColumn<DateTime> cancelledAt = GeneratedColumn<DateTime>(
      'cancelled_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        deviceId,
        clientSeq,
        totalAmount,
        paymentMethod,
        serverSeq,
        status,
        cancelReason,
        cancelledAt,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sales';
  @override
  VerificationContext validateIntegrity(Insertable<Sale> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(_deviceIdMeta,
          deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta));
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('client_seq')) {
      context.handle(_clientSeqMeta,
          clientSeq.isAcceptableOrUnknown(data['client_seq']!, _clientSeqMeta));
    } else if (isInserting) {
      context.missing(_clientSeqMeta);
    }
    if (data.containsKey('total_amount')) {
      context.handle(
          _totalAmountMeta,
          totalAmount.isAcceptableOrUnknown(
              data['total_amount']!, _totalAmountMeta));
    } else if (isInserting) {
      context.missing(_totalAmountMeta);
    }
    if (data.containsKey('payment_method')) {
      context.handle(
          _paymentMethodMeta,
          paymentMethod.isAcceptableOrUnknown(
              data['payment_method']!, _paymentMethodMeta));
    } else if (isInserting) {
      context.missing(_paymentMethodMeta);
    }
    if (data.containsKey('server_seq')) {
      context.handle(_serverSeqMeta,
          serverSeq.isAcceptableOrUnknown(data['server_seq']!, _serverSeqMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('cancel_reason')) {
      context.handle(
          _cancelReasonMeta,
          cancelReason.isAcceptableOrUnknown(
              data['cancel_reason']!, _cancelReasonMeta));
    }
    if (data.containsKey('cancelled_at')) {
      context.handle(
          _cancelledAtMeta,
          cancelledAt.isAcceptableOrUnknown(
              data['cancelled_at']!, _cancelledAtMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Sale map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Sale(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      deviceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_id'])!,
      clientSeq: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}client_seq'])!,
      totalAmount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}total_amount'])!,
      paymentMethod: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payment_method'])!,
      serverSeq: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}server_seq']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      cancelReason: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cancel_reason']),
      cancelledAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}cancelled_at']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $SalesTable createAlias(String alias) {
    return $SalesTable(attachedDatabase, alias);
  }
}

class Sale extends DataClass implements Insertable<Sale> {
  final String id;
  final String deviceId;
  final int clientSeq;
  final int totalAmount;
  final String paymentMethod;
  final int? serverSeq;
  final String status;
  final String? cancelReason;
  final DateTime? cancelledAt;
  final DateTime createdAt;
  const Sale(
      {required this.id,
      required this.deviceId,
      required this.clientSeq,
      required this.totalAmount,
      required this.paymentMethod,
      this.serverSeq,
      required this.status,
      this.cancelReason,
      this.cancelledAt,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['device_id'] = Variable<String>(deviceId);
    map['client_seq'] = Variable<int>(clientSeq);
    map['total_amount'] = Variable<int>(totalAmount);
    map['payment_method'] = Variable<String>(paymentMethod);
    if (!nullToAbsent || serverSeq != null) {
      map['server_seq'] = Variable<int>(serverSeq);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || cancelReason != null) {
      map['cancel_reason'] = Variable<String>(cancelReason);
    }
    if (!nullToAbsent || cancelledAt != null) {
      map['cancelled_at'] = Variable<DateTime>(cancelledAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  SalesCompanion toCompanion(bool nullToAbsent) {
    return SalesCompanion(
      id: Value(id),
      deviceId: Value(deviceId),
      clientSeq: Value(clientSeq),
      totalAmount: Value(totalAmount),
      paymentMethod: Value(paymentMethod),
      serverSeq: serverSeq == null && nullToAbsent
          ? const Value.absent()
          : Value(serverSeq),
      status: Value(status),
      cancelReason: cancelReason == null && nullToAbsent
          ? const Value.absent()
          : Value(cancelReason),
      cancelledAt: cancelledAt == null && nullToAbsent
          ? const Value.absent()
          : Value(cancelledAt),
      createdAt: Value(createdAt),
    );
  }

  factory Sale.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Sale(
      id: serializer.fromJson<String>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      clientSeq: serializer.fromJson<int>(json['clientSeq']),
      totalAmount: serializer.fromJson<int>(json['totalAmount']),
      paymentMethod: serializer.fromJson<String>(json['paymentMethod']),
      serverSeq: serializer.fromJson<int?>(json['serverSeq']),
      status: serializer.fromJson<String>(json['status']),
      cancelReason: serializer.fromJson<String?>(json['cancelReason']),
      cancelledAt: serializer.fromJson<DateTime?>(json['cancelledAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'clientSeq': serializer.toJson<int>(clientSeq),
      'totalAmount': serializer.toJson<int>(totalAmount),
      'paymentMethod': serializer.toJson<String>(paymentMethod),
      'serverSeq': serializer.toJson<int?>(serverSeq),
      'status': serializer.toJson<String>(status),
      'cancelReason': serializer.toJson<String?>(cancelReason),
      'cancelledAt': serializer.toJson<DateTime?>(cancelledAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Sale copyWith(
          {String? id,
          String? deviceId,
          int? clientSeq,
          int? totalAmount,
          String? paymentMethod,
          Value<int?> serverSeq = const Value.absent(),
          String? status,
          Value<String?> cancelReason = const Value.absent(),
          Value<DateTime?> cancelledAt = const Value.absent(),
          DateTime? createdAt}) =>
      Sale(
        id: id ?? this.id,
        deviceId: deviceId ?? this.deviceId,
        clientSeq: clientSeq ?? this.clientSeq,
        totalAmount: totalAmount ?? this.totalAmount,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        serverSeq: serverSeq.present ? serverSeq.value : this.serverSeq,
        status: status ?? this.status,
        cancelReason:
            cancelReason.present ? cancelReason.value : this.cancelReason,
        cancelledAt: cancelledAt.present ? cancelledAt.value : this.cancelledAt,
        createdAt: createdAt ?? this.createdAt,
      );
  Sale copyWithCompanion(SalesCompanion data) {
    return Sale(
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      clientSeq: data.clientSeq.present ? data.clientSeq.value : this.clientSeq,
      totalAmount:
          data.totalAmount.present ? data.totalAmount.value : this.totalAmount,
      paymentMethod: data.paymentMethod.present
          ? data.paymentMethod.value
          : this.paymentMethod,
      serverSeq: data.serverSeq.present ? data.serverSeq.value : this.serverSeq,
      status: data.status.present ? data.status.value : this.status,
      cancelReason: data.cancelReason.present
          ? data.cancelReason.value
          : this.cancelReason,
      cancelledAt:
          data.cancelledAt.present ? data.cancelledAt.value : this.cancelledAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Sale(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('clientSeq: $clientSeq, ')
          ..write('totalAmount: $totalAmount, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('serverSeq: $serverSeq, ')
          ..write('status: $status, ')
          ..write('cancelReason: $cancelReason, ')
          ..write('cancelledAt: $cancelledAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, deviceId, clientSeq, totalAmount,
      paymentMethod, serverSeq, status, cancelReason, cancelledAt, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Sale &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.clientSeq == this.clientSeq &&
          other.totalAmount == this.totalAmount &&
          other.paymentMethod == this.paymentMethod &&
          other.serverSeq == this.serverSeq &&
          other.status == this.status &&
          other.cancelReason == this.cancelReason &&
          other.cancelledAt == this.cancelledAt &&
          other.createdAt == this.createdAt);
}

class SalesCompanion extends UpdateCompanion<Sale> {
  final Value<String> id;
  final Value<String> deviceId;
  final Value<int> clientSeq;
  final Value<int> totalAmount;
  final Value<String> paymentMethod;
  final Value<int?> serverSeq;
  final Value<String> status;
  final Value<String?> cancelReason;
  final Value<DateTime?> cancelledAt;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const SalesCompanion({
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.clientSeq = const Value.absent(),
    this.totalAmount = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.serverSeq = const Value.absent(),
    this.status = const Value.absent(),
    this.cancelReason = const Value.absent(),
    this.cancelledAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SalesCompanion.insert({
    required String id,
    required String deviceId,
    required int clientSeq,
    required int totalAmount,
    required String paymentMethod,
    this.serverSeq = const Value.absent(),
    this.status = const Value.absent(),
    this.cancelReason = const Value.absent(),
    this.cancelledAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        deviceId = Value(deviceId),
        clientSeq = Value(clientSeq),
        totalAmount = Value(totalAmount),
        paymentMethod = Value(paymentMethod);
  static Insertable<Sale> custom({
    Expression<String>? id,
    Expression<String>? deviceId,
    Expression<int>? clientSeq,
    Expression<int>? totalAmount,
    Expression<String>? paymentMethod,
    Expression<int>? serverSeq,
    Expression<String>? status,
    Expression<String>? cancelReason,
    Expression<DateTime>? cancelledAt,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (clientSeq != null) 'client_seq': clientSeq,
      if (totalAmount != null) 'total_amount': totalAmount,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (serverSeq != null) 'server_seq': serverSeq,
      if (status != null) 'status': status,
      if (cancelReason != null) 'cancel_reason': cancelReason,
      if (cancelledAt != null) 'cancelled_at': cancelledAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SalesCompanion copyWith(
      {Value<String>? id,
      Value<String>? deviceId,
      Value<int>? clientSeq,
      Value<int>? totalAmount,
      Value<String>? paymentMethod,
      Value<int?>? serverSeq,
      Value<String>? status,
      Value<String?>? cancelReason,
      Value<DateTime?>? cancelledAt,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return SalesCompanion(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      clientSeq: clientSeq ?? this.clientSeq,
      totalAmount: totalAmount ?? this.totalAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      serverSeq: serverSeq ?? this.serverSeq,
      status: status ?? this.status,
      cancelReason: cancelReason ?? this.cancelReason,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (clientSeq.present) {
      map['client_seq'] = Variable<int>(clientSeq.value);
    }
    if (totalAmount.present) {
      map['total_amount'] = Variable<int>(totalAmount.value);
    }
    if (paymentMethod.present) {
      map['payment_method'] = Variable<String>(paymentMethod.value);
    }
    if (serverSeq.present) {
      map['server_seq'] = Variable<int>(serverSeq.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (cancelReason.present) {
      map['cancel_reason'] = Variable<String>(cancelReason.value);
    }
    if (cancelledAt.present) {
      map['cancelled_at'] = Variable<DateTime>(cancelledAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SalesCompanion(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('clientSeq: $clientSeq, ')
          ..write('totalAmount: $totalAmount, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('serverSeq: $serverSeq, ')
          ..write('status: $status, ')
          ..write('cancelReason: $cancelReason, ')
          ..write('cancelledAt: $cancelledAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SaleItemsTable extends SaleItems
    with TableInfo<$SaleItemsTable, SaleItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SaleItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _saleIdMeta = const VerificationMeta('saleId');
  @override
  late final GeneratedColumn<String> saleId = GeneratedColumn<String>(
      'sale_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES sales (id)'));
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES products (id)'));
  static const VerificationMeta _quantityMeta =
      const VerificationMeta('quantity');
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
      'quantity', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _unitPriceMeta =
      const VerificationMeta('unitPrice');
  @override
  late final GeneratedColumn<int> unitPrice = GeneratedColumn<int>(
      'unit_price', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _totalPriceMeta =
      const VerificationMeta('totalPrice');
  @override
  late final GeneratedColumn<int> totalPrice = GeneratedColumn<int>(
      'total_price', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, saleId, productId, quantity, unitPrice, totalPrice];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sale_items';
  @override
  VerificationContext validateIntegrity(Insertable<SaleItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('sale_id')) {
      context.handle(_saleIdMeta,
          saleId.isAcceptableOrUnknown(data['sale_id']!, _saleIdMeta));
    } else if (isInserting) {
      context.missing(_saleIdMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta,
          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(_quantityMeta,
          quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta));
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('unit_price')) {
      context.handle(_unitPriceMeta,
          unitPrice.isAcceptableOrUnknown(data['unit_price']!, _unitPriceMeta));
    } else if (isInserting) {
      context.missing(_unitPriceMeta);
    }
    if (data.containsKey('total_price')) {
      context.handle(
          _totalPriceMeta,
          totalPrice.isAcceptableOrUnknown(
              data['total_price']!, _totalPriceMeta));
    } else if (isInserting) {
      context.missing(_totalPriceMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SaleItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SaleItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      saleId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sale_id'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      quantity: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}quantity'])!,
      unitPrice: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}unit_price'])!,
      totalPrice: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}total_price'])!,
    );
  }

  @override
  $SaleItemsTable createAlias(String alias) {
    return $SaleItemsTable(attachedDatabase, alias);
  }
}

class SaleItem extends DataClass implements Insertable<SaleItem> {
  final String id;
  final String saleId;
  final String productId;
  final int quantity;
  final int unitPrice;
  final int totalPrice;
  const SaleItem(
      {required this.id,
      required this.saleId,
      required this.productId,
      required this.quantity,
      required this.unitPrice,
      required this.totalPrice});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['sale_id'] = Variable<String>(saleId);
    map['product_id'] = Variable<String>(productId);
    map['quantity'] = Variable<int>(quantity);
    map['unit_price'] = Variable<int>(unitPrice);
    map['total_price'] = Variable<int>(totalPrice);
    return map;
  }

  SaleItemsCompanion toCompanion(bool nullToAbsent) {
    return SaleItemsCompanion(
      id: Value(id),
      saleId: Value(saleId),
      productId: Value(productId),
      quantity: Value(quantity),
      unitPrice: Value(unitPrice),
      totalPrice: Value(totalPrice),
    );
  }

  factory SaleItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SaleItem(
      id: serializer.fromJson<String>(json['id']),
      saleId: serializer.fromJson<String>(json['saleId']),
      productId: serializer.fromJson<String>(json['productId']),
      quantity: serializer.fromJson<int>(json['quantity']),
      unitPrice: serializer.fromJson<int>(json['unitPrice']),
      totalPrice: serializer.fromJson<int>(json['totalPrice']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'saleId': serializer.toJson<String>(saleId),
      'productId': serializer.toJson<String>(productId),
      'quantity': serializer.toJson<int>(quantity),
      'unitPrice': serializer.toJson<int>(unitPrice),
      'totalPrice': serializer.toJson<int>(totalPrice),
    };
  }

  SaleItem copyWith(
          {String? id,
          String? saleId,
          String? productId,
          int? quantity,
          int? unitPrice,
          int? totalPrice}) =>
      SaleItem(
        id: id ?? this.id,
        saleId: saleId ?? this.saleId,
        productId: productId ?? this.productId,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        totalPrice: totalPrice ?? this.totalPrice,
      );
  SaleItem copyWithCompanion(SaleItemsCompanion data) {
    return SaleItem(
      id: data.id.present ? data.id.value : this.id,
      saleId: data.saleId.present ? data.saleId.value : this.saleId,
      productId: data.productId.present ? data.productId.value : this.productId,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      unitPrice: data.unitPrice.present ? data.unitPrice.value : this.unitPrice,
      totalPrice:
          data.totalPrice.present ? data.totalPrice.value : this.totalPrice,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SaleItem(')
          ..write('id: $id, ')
          ..write('saleId: $saleId, ')
          ..write('productId: $productId, ')
          ..write('quantity: $quantity, ')
          ..write('unitPrice: $unitPrice, ')
          ..write('totalPrice: $totalPrice')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, saleId, productId, quantity, unitPrice, totalPrice);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SaleItem &&
          other.id == this.id &&
          other.saleId == this.saleId &&
          other.productId == this.productId &&
          other.quantity == this.quantity &&
          other.unitPrice == this.unitPrice &&
          other.totalPrice == this.totalPrice);
}

class SaleItemsCompanion extends UpdateCompanion<SaleItem> {
  final Value<String> id;
  final Value<String> saleId;
  final Value<String> productId;
  final Value<int> quantity;
  final Value<int> unitPrice;
  final Value<int> totalPrice;
  final Value<int> rowid;
  const SaleItemsCompanion({
    this.id = const Value.absent(),
    this.saleId = const Value.absent(),
    this.productId = const Value.absent(),
    this.quantity = const Value.absent(),
    this.unitPrice = const Value.absent(),
    this.totalPrice = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SaleItemsCompanion.insert({
    required String id,
    required String saleId,
    required String productId,
    required int quantity,
    required int unitPrice,
    required int totalPrice,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        saleId = Value(saleId),
        productId = Value(productId),
        quantity = Value(quantity),
        unitPrice = Value(unitPrice),
        totalPrice = Value(totalPrice);
  static Insertable<SaleItem> custom({
    Expression<String>? id,
    Expression<String>? saleId,
    Expression<String>? productId,
    Expression<int>? quantity,
    Expression<int>? unitPrice,
    Expression<int>? totalPrice,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (saleId != null) 'sale_id': saleId,
      if (productId != null) 'product_id': productId,
      if (quantity != null) 'quantity': quantity,
      if (unitPrice != null) 'unit_price': unitPrice,
      if (totalPrice != null) 'total_price': totalPrice,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SaleItemsCompanion copyWith(
      {Value<String>? id,
      Value<String>? saleId,
      Value<String>? productId,
      Value<int>? quantity,
      Value<int>? unitPrice,
      Value<int>? totalPrice,
      Value<int>? rowid}) {
    return SaleItemsCompanion(
      id: id ?? this.id,
      saleId: saleId ?? this.saleId,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      totalPrice: totalPrice ?? this.totalPrice,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (saleId.present) {
      map['sale_id'] = Variable<String>(saleId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (unitPrice.present) {
      map['unit_price'] = Variable<int>(unitPrice.value);
    }
    if (totalPrice.present) {
      map['total_price'] = Variable<int>(totalPrice.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SaleItemsCompanion(')
          ..write('id: $id, ')
          ..write('saleId: $saleId, ')
          ..write('productId: $productId, ')
          ..write('quantity: $quantity, ')
          ..write('unitPrice: $unitPrice, ')
          ..write('totalPrice: $totalPrice, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StockMovementsTable extends StockMovements
    with TableInfo<$StockMovementsTable, StockMovement> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StockMovementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES products (id)'));
  static const VerificationMeta _quantityMeta =
      const VerificationMeta('quantity');
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
      'quantity', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
      'unit', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('adet'));
  static const VerificationMeta _movementTypeMeta =
      const VerificationMeta('movementType');
  @override
  late final GeneratedColumn<String> movementType = GeneratedColumn<String>(
      'movement_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _referenceIdMeta =
      const VerificationMeta('referenceId');
  @override
  late final GeneratedColumn<String> referenceId = GeneratedColumn<String>(
      'reference_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _purchasePriceMeta =
      const VerificationMeta('purchasePrice');
  @override
  late final GeneratedColumn<int> purchasePrice = GeneratedColumn<int>(
      'purchase_price', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        productId,
        quantity,
        unit,
        movementType,
        referenceId,
        purchasePrice,
        note,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stock_movements';
  @override
  VerificationContext validateIntegrity(Insertable<StockMovement> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta,
          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(_quantityMeta,
          quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta));
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('unit')) {
      context.handle(
          _unitMeta, unit.isAcceptableOrUnknown(data['unit']!, _unitMeta));
    }
    if (data.containsKey('movement_type')) {
      context.handle(
          _movementTypeMeta,
          movementType.isAcceptableOrUnknown(
              data['movement_type']!, _movementTypeMeta));
    } else if (isInserting) {
      context.missing(_movementTypeMeta);
    }
    if (data.containsKey('reference_id')) {
      context.handle(
          _referenceIdMeta,
          referenceId.isAcceptableOrUnknown(
              data['reference_id']!, _referenceIdMeta));
    } else if (isInserting) {
      context.missing(_referenceIdMeta);
    }
    if (data.containsKey('purchase_price')) {
      context.handle(
          _purchasePriceMeta,
          purchasePrice.isAcceptableOrUnknown(
              data['purchase_price']!, _purchasePriceMeta));
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StockMovement map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StockMovement(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      quantity: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}quantity'])!,
      unit: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}unit'])!,
      movementType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}movement_type'])!,
      referenceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reference_id'])!,
      purchasePrice: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}purchase_price']),
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $StockMovementsTable createAlias(String alias) {
    return $StockMovementsTable(attachedDatabase, alias);
  }
}

class StockMovement extends DataClass implements Insertable<StockMovement> {
  final String id;
  final String productId;
  final int quantity;
  final String unit;
  final String movementType;
  final String referenceId;
  final int? purchasePrice;
  final String? note;
  final DateTime createdAt;
  const StockMovement(
      {required this.id,
      required this.productId,
      required this.quantity,
      required this.unit,
      required this.movementType,
      required this.referenceId,
      this.purchasePrice,
      this.note,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_id'] = Variable<String>(productId);
    map['quantity'] = Variable<int>(quantity);
    map['unit'] = Variable<String>(unit);
    map['movement_type'] = Variable<String>(movementType);
    map['reference_id'] = Variable<String>(referenceId);
    if (!nullToAbsent || purchasePrice != null) {
      map['purchase_price'] = Variable<int>(purchasePrice);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  StockMovementsCompanion toCompanion(bool nullToAbsent) {
    return StockMovementsCompanion(
      id: Value(id),
      productId: Value(productId),
      quantity: Value(quantity),
      unit: Value(unit),
      movementType: Value(movementType),
      referenceId: Value(referenceId),
      purchasePrice: purchasePrice == null && nullToAbsent
          ? const Value.absent()
          : Value(purchasePrice),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdAt: Value(createdAt),
    );
  }

  factory StockMovement.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StockMovement(
      id: serializer.fromJson<String>(json['id']),
      productId: serializer.fromJson<String>(json['productId']),
      quantity: serializer.fromJson<int>(json['quantity']),
      unit: serializer.fromJson<String>(json['unit']),
      movementType: serializer.fromJson<String>(json['movementType']),
      referenceId: serializer.fromJson<String>(json['referenceId']),
      purchasePrice: serializer.fromJson<int?>(json['purchasePrice']),
      note: serializer.fromJson<String?>(json['note']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productId': serializer.toJson<String>(productId),
      'quantity': serializer.toJson<int>(quantity),
      'unit': serializer.toJson<String>(unit),
      'movementType': serializer.toJson<String>(movementType),
      'referenceId': serializer.toJson<String>(referenceId),
      'purchasePrice': serializer.toJson<int?>(purchasePrice),
      'note': serializer.toJson<String?>(note),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  StockMovement copyWith(
          {String? id,
          String? productId,
          int? quantity,
          String? unit,
          String? movementType,
          String? referenceId,
          Value<int?> purchasePrice = const Value.absent(),
          Value<String?> note = const Value.absent(),
          DateTime? createdAt}) =>
      StockMovement(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        quantity: quantity ?? this.quantity,
        unit: unit ?? this.unit,
        movementType: movementType ?? this.movementType,
        referenceId: referenceId ?? this.referenceId,
        purchasePrice:
            purchasePrice.present ? purchasePrice.value : this.purchasePrice,
        note: note.present ? note.value : this.note,
        createdAt: createdAt ?? this.createdAt,
      );
  StockMovement copyWithCompanion(StockMovementsCompanion data) {
    return StockMovement(
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      unit: data.unit.present ? data.unit.value : this.unit,
      movementType: data.movementType.present
          ? data.movementType.value
          : this.movementType,
      referenceId:
          data.referenceId.present ? data.referenceId.value : this.referenceId,
      purchasePrice: data.purchasePrice.present
          ? data.purchasePrice.value
          : this.purchasePrice,
      note: data.note.present ? data.note.value : this.note,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StockMovement(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('quantity: $quantity, ')
          ..write('unit: $unit, ')
          ..write('movementType: $movementType, ')
          ..write('referenceId: $referenceId, ')
          ..write('purchasePrice: $purchasePrice, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, productId, quantity, unit, movementType,
      referenceId, purchasePrice, note, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StockMovement &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.quantity == this.quantity &&
          other.unit == this.unit &&
          other.movementType == this.movementType &&
          other.referenceId == this.referenceId &&
          other.purchasePrice == this.purchasePrice &&
          other.note == this.note &&
          other.createdAt == this.createdAt);
}

class StockMovementsCompanion extends UpdateCompanion<StockMovement> {
  final Value<String> id;
  final Value<String> productId;
  final Value<int> quantity;
  final Value<String> unit;
  final Value<String> movementType;
  final Value<String> referenceId;
  final Value<int?> purchasePrice;
  final Value<String?> note;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const StockMovementsCompanion({
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.quantity = const Value.absent(),
    this.unit = const Value.absent(),
    this.movementType = const Value.absent(),
    this.referenceId = const Value.absent(),
    this.purchasePrice = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StockMovementsCompanion.insert({
    required String id,
    required String productId,
    required int quantity,
    this.unit = const Value.absent(),
    required String movementType,
    required String referenceId,
    this.purchasePrice = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        productId = Value(productId),
        quantity = Value(quantity),
        movementType = Value(movementType),
        referenceId = Value(referenceId);
  static Insertable<StockMovement> custom({
    Expression<String>? id,
    Expression<String>? productId,
    Expression<int>? quantity,
    Expression<String>? unit,
    Expression<String>? movementType,
    Expression<String>? referenceId,
    Expression<int>? purchasePrice,
    Expression<String>? note,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (quantity != null) 'quantity': quantity,
      if (unit != null) 'unit': unit,
      if (movementType != null) 'movement_type': movementType,
      if (referenceId != null) 'reference_id': referenceId,
      if (purchasePrice != null) 'purchase_price': purchasePrice,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StockMovementsCompanion copyWith(
      {Value<String>? id,
      Value<String>? productId,
      Value<int>? quantity,
      Value<String>? unit,
      Value<String>? movementType,
      Value<String>? referenceId,
      Value<int?>? purchasePrice,
      Value<String?>? note,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return StockMovementsCompanion(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      movementType: movementType ?? this.movementType,
      referenceId: referenceId ?? this.referenceId,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (movementType.present) {
      map['movement_type'] = Variable<String>(movementType.value);
    }
    if (referenceId.present) {
      map['reference_id'] = Variable<String>(referenceId.value);
    }
    if (purchasePrice.present) {
      map['purchase_price'] = Variable<int>(purchasePrice.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StockMovementsCompanion(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('quantity: $quantity, ')
          ..write('unit: $unit, ')
          ..write('movementType: $movementType, ')
          ..write('referenceId: $referenceId, ')
          ..write('purchasePrice: $purchasePrice, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProcessedOperationsTable extends ProcessedOperations
    with TableInfo<$ProcessedOperationsTable, ProcessedOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProcessedOperationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _operationIdMeta =
      const VerificationMeta('operationId');
  @override
  late final GeneratedColumn<String> operationId = GeneratedColumn<String>(
      'operation_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _deviceIdMeta =
      const VerificationMeta('deviceId');
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
      'device_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _idempotencyKeyMeta =
      const VerificationMeta('idempotencyKey');
  @override
  late final GeneratedColumn<String> idempotencyKey = GeneratedColumn<String>(
      'idempotency_key', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _clientSeqMeta =
      const VerificationMeta('clientSeq');
  @override
  late final GeneratedColumn<int> clientSeq = GeneratedColumn<int>(
      'client_seq', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _operationTypeMeta =
      const VerificationMeta('operationType');
  @override
  late final GeneratedColumn<String> operationType = GeneratedColumn<String>(
      'operation_type', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _requestHashMeta =
      const VerificationMeta('requestHash');
  @override
  late final GeneratedColumn<String> requestHash = GeneratedColumn<String>(
      'request_hash', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _hashVersionMeta =
      const VerificationMeta('hashVersion');
  @override
  late final GeneratedColumn<String> hashVersion = GeneratedColumn<String>(
      'hash_version', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _resultPayloadMeta =
      const VerificationMeta('resultPayload');
  @override
  late final GeneratedColumn<String> resultPayload = GeneratedColumn<String>(
      'result_payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _processedAtMeta =
      const VerificationMeta('processedAt');
  @override
  late final GeneratedColumn<DateTime> processedAt = GeneratedColumn<DateTime>(
      'processed_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        operationId,
        deviceId,
        idempotencyKey,
        clientSeq,
        operationType,
        requestHash,
        hashVersion,
        resultPayload,
        processedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'processed_operations';
  @override
  VerificationContext validateIntegrity(Insertable<ProcessedOperation> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('operation_id')) {
      context.handle(
          _operationIdMeta,
          operationId.isAcceptableOrUnknown(
              data['operation_id']!, _operationIdMeta));
    } else if (isInserting) {
      context.missing(_operationIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(_deviceIdMeta,
          deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta));
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('idempotency_key')) {
      context.handle(
          _idempotencyKeyMeta,
          idempotencyKey.isAcceptableOrUnknown(
              data['idempotency_key']!, _idempotencyKeyMeta));
    } else if (isInserting) {
      context.missing(_idempotencyKeyMeta);
    }
    if (data.containsKey('client_seq')) {
      context.handle(_clientSeqMeta,
          clientSeq.isAcceptableOrUnknown(data['client_seq']!, _clientSeqMeta));
    }
    if (data.containsKey('operation_type')) {
      context.handle(
          _operationTypeMeta,
          operationType.isAcceptableOrUnknown(
              data['operation_type']!, _operationTypeMeta));
    }
    if (data.containsKey('request_hash')) {
      context.handle(
          _requestHashMeta,
          requestHash.isAcceptableOrUnknown(
              data['request_hash']!, _requestHashMeta));
    }
    if (data.containsKey('hash_version')) {
      context.handle(
          _hashVersionMeta,
          hashVersion.isAcceptableOrUnknown(
              data['hash_version']!, _hashVersionMeta));
    }
    if (data.containsKey('result_payload')) {
      context.handle(
          _resultPayloadMeta,
          resultPayload.isAcceptableOrUnknown(
              data['result_payload']!, _resultPayloadMeta));
    } else if (isInserting) {
      context.missing(_resultPayloadMeta);
    }
    if (data.containsKey('processed_at')) {
      context.handle(
          _processedAtMeta,
          processedAt.isAcceptableOrUnknown(
              data['processed_at']!, _processedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {operationId};
  @override
  ProcessedOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProcessedOperation(
      operationId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}operation_id'])!,
      deviceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_id'])!,
      idempotencyKey: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}idempotency_key'])!,
      clientSeq: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}client_seq']),
      operationType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}operation_type']),
      requestHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}request_hash']),
      hashVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}hash_version']),
      resultPayload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}result_payload'])!,
      processedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}processed_at'])!,
    );
  }

  @override
  $ProcessedOperationsTable createAlias(String alias) {
    return $ProcessedOperationsTable(attachedDatabase, alias);
  }
}

class ProcessedOperation extends DataClass
    implements Insertable<ProcessedOperation> {
  final String operationId;
  final String deviceId;
  final String idempotencyKey;
  final int? clientSeq;
  final String? operationType;
  final String? requestHash;
  final String? hashVersion;
  final String resultPayload;
  final DateTime processedAt;
  const ProcessedOperation(
      {required this.operationId,
      required this.deviceId,
      required this.idempotencyKey,
      this.clientSeq,
      this.operationType,
      this.requestHash,
      this.hashVersion,
      required this.resultPayload,
      required this.processedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['operation_id'] = Variable<String>(operationId);
    map['device_id'] = Variable<String>(deviceId);
    map['idempotency_key'] = Variable<String>(idempotencyKey);
    if (!nullToAbsent || clientSeq != null) {
      map['client_seq'] = Variable<int>(clientSeq);
    }
    if (!nullToAbsent || operationType != null) {
      map['operation_type'] = Variable<String>(operationType);
    }
    if (!nullToAbsent || requestHash != null) {
      map['request_hash'] = Variable<String>(requestHash);
    }
    if (!nullToAbsent || hashVersion != null) {
      map['hash_version'] = Variable<String>(hashVersion);
    }
    map['result_payload'] = Variable<String>(resultPayload);
    map['processed_at'] = Variable<DateTime>(processedAt);
    return map;
  }

  ProcessedOperationsCompanion toCompanion(bool nullToAbsent) {
    return ProcessedOperationsCompanion(
      operationId: Value(operationId),
      deviceId: Value(deviceId),
      idempotencyKey: Value(idempotencyKey),
      clientSeq: clientSeq == null && nullToAbsent
          ? const Value.absent()
          : Value(clientSeq),
      operationType: operationType == null && nullToAbsent
          ? const Value.absent()
          : Value(operationType),
      requestHash: requestHash == null && nullToAbsent
          ? const Value.absent()
          : Value(requestHash),
      hashVersion: hashVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(hashVersion),
      resultPayload: Value(resultPayload),
      processedAt: Value(processedAt),
    );
  }

  factory ProcessedOperation.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProcessedOperation(
      operationId: serializer.fromJson<String>(json['operationId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      idempotencyKey: serializer.fromJson<String>(json['idempotencyKey']),
      clientSeq: serializer.fromJson<int?>(json['clientSeq']),
      operationType: serializer.fromJson<String?>(json['operationType']),
      requestHash: serializer.fromJson<String?>(json['requestHash']),
      hashVersion: serializer.fromJson<String?>(json['hashVersion']),
      resultPayload: serializer.fromJson<String>(json['resultPayload']),
      processedAt: serializer.fromJson<DateTime>(json['processedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'operationId': serializer.toJson<String>(operationId),
      'deviceId': serializer.toJson<String>(deviceId),
      'idempotencyKey': serializer.toJson<String>(idempotencyKey),
      'clientSeq': serializer.toJson<int?>(clientSeq),
      'operationType': serializer.toJson<String?>(operationType),
      'requestHash': serializer.toJson<String?>(requestHash),
      'hashVersion': serializer.toJson<String?>(hashVersion),
      'resultPayload': serializer.toJson<String>(resultPayload),
      'processedAt': serializer.toJson<DateTime>(processedAt),
    };
  }

  ProcessedOperation copyWith(
          {String? operationId,
          String? deviceId,
          String? idempotencyKey,
          Value<int?> clientSeq = const Value.absent(),
          Value<String?> operationType = const Value.absent(),
          Value<String?> requestHash = const Value.absent(),
          Value<String?> hashVersion = const Value.absent(),
          String? resultPayload,
          DateTime? processedAt}) =>
      ProcessedOperation(
        operationId: operationId ?? this.operationId,
        deviceId: deviceId ?? this.deviceId,
        idempotencyKey: idempotencyKey ?? this.idempotencyKey,
        clientSeq: clientSeq.present ? clientSeq.value : this.clientSeq,
        operationType:
            operationType.present ? operationType.value : this.operationType,
        requestHash: requestHash.present ? requestHash.value : this.requestHash,
        hashVersion: hashVersion.present ? hashVersion.value : this.hashVersion,
        resultPayload: resultPayload ?? this.resultPayload,
        processedAt: processedAt ?? this.processedAt,
      );
  ProcessedOperation copyWithCompanion(ProcessedOperationsCompanion data) {
    return ProcessedOperation(
      operationId:
          data.operationId.present ? data.operationId.value : this.operationId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      idempotencyKey: data.idempotencyKey.present
          ? data.idempotencyKey.value
          : this.idempotencyKey,
      clientSeq: data.clientSeq.present ? data.clientSeq.value : this.clientSeq,
      operationType: data.operationType.present
          ? data.operationType.value
          : this.operationType,
      requestHash:
          data.requestHash.present ? data.requestHash.value : this.requestHash,
      hashVersion:
          data.hashVersion.present ? data.hashVersion.value : this.hashVersion,
      resultPayload: data.resultPayload.present
          ? data.resultPayload.value
          : this.resultPayload,
      processedAt:
          data.processedAt.present ? data.processedAt.value : this.processedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProcessedOperation(')
          ..write('operationId: $operationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('clientSeq: $clientSeq, ')
          ..write('operationType: $operationType, ')
          ..write('requestHash: $requestHash, ')
          ..write('hashVersion: $hashVersion, ')
          ..write('resultPayload: $resultPayload, ')
          ..write('processedAt: $processedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      operationId,
      deviceId,
      idempotencyKey,
      clientSeq,
      operationType,
      requestHash,
      hashVersion,
      resultPayload,
      processedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProcessedOperation &&
          other.operationId == this.operationId &&
          other.deviceId == this.deviceId &&
          other.idempotencyKey == this.idempotencyKey &&
          other.clientSeq == this.clientSeq &&
          other.operationType == this.operationType &&
          other.requestHash == this.requestHash &&
          other.hashVersion == this.hashVersion &&
          other.resultPayload == this.resultPayload &&
          other.processedAt == this.processedAt);
}

class ProcessedOperationsCompanion extends UpdateCompanion<ProcessedOperation> {
  final Value<String> operationId;
  final Value<String> deviceId;
  final Value<String> idempotencyKey;
  final Value<int?> clientSeq;
  final Value<String?> operationType;
  final Value<String?> requestHash;
  final Value<String?> hashVersion;
  final Value<String> resultPayload;
  final Value<DateTime> processedAt;
  final Value<int> rowid;
  const ProcessedOperationsCompanion({
    this.operationId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.idempotencyKey = const Value.absent(),
    this.clientSeq = const Value.absent(),
    this.operationType = const Value.absent(),
    this.requestHash = const Value.absent(),
    this.hashVersion = const Value.absent(),
    this.resultPayload = const Value.absent(),
    this.processedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProcessedOperationsCompanion.insert({
    required String operationId,
    required String deviceId,
    required String idempotencyKey,
    this.clientSeq = const Value.absent(),
    this.operationType = const Value.absent(),
    this.requestHash = const Value.absent(),
    this.hashVersion = const Value.absent(),
    required String resultPayload,
    this.processedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : operationId = Value(operationId),
        deviceId = Value(deviceId),
        idempotencyKey = Value(idempotencyKey),
        resultPayload = Value(resultPayload);
  static Insertable<ProcessedOperation> custom({
    Expression<String>? operationId,
    Expression<String>? deviceId,
    Expression<String>? idempotencyKey,
    Expression<int>? clientSeq,
    Expression<String>? operationType,
    Expression<String>? requestHash,
    Expression<String>? hashVersion,
    Expression<String>? resultPayload,
    Expression<DateTime>? processedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (operationId != null) 'operation_id': operationId,
      if (deviceId != null) 'device_id': deviceId,
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      if (clientSeq != null) 'client_seq': clientSeq,
      if (operationType != null) 'operation_type': operationType,
      if (requestHash != null) 'request_hash': requestHash,
      if (hashVersion != null) 'hash_version': hashVersion,
      if (resultPayload != null) 'result_payload': resultPayload,
      if (processedAt != null) 'processed_at': processedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProcessedOperationsCompanion copyWith(
      {Value<String>? operationId,
      Value<String>? deviceId,
      Value<String>? idempotencyKey,
      Value<int?>? clientSeq,
      Value<String?>? operationType,
      Value<String?>? requestHash,
      Value<String?>? hashVersion,
      Value<String>? resultPayload,
      Value<DateTime>? processedAt,
      Value<int>? rowid}) {
    return ProcessedOperationsCompanion(
      operationId: operationId ?? this.operationId,
      deviceId: deviceId ?? this.deviceId,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      clientSeq: clientSeq ?? this.clientSeq,
      operationType: operationType ?? this.operationType,
      requestHash: requestHash ?? this.requestHash,
      hashVersion: hashVersion ?? this.hashVersion,
      resultPayload: resultPayload ?? this.resultPayload,
      processedAt: processedAt ?? this.processedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (operationId.present) {
      map['operation_id'] = Variable<String>(operationId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (idempotencyKey.present) {
      map['idempotency_key'] = Variable<String>(idempotencyKey.value);
    }
    if (clientSeq.present) {
      map['client_seq'] = Variable<int>(clientSeq.value);
    }
    if (operationType.present) {
      map['operation_type'] = Variable<String>(operationType.value);
    }
    if (requestHash.present) {
      map['request_hash'] = Variable<String>(requestHash.value);
    }
    if (hashVersion.present) {
      map['hash_version'] = Variable<String>(hashVersion.value);
    }
    if (resultPayload.present) {
      map['result_payload'] = Variable<String>(resultPayload.value);
    }
    if (processedAt.present) {
      map['processed_at'] = Variable<DateTime>(processedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProcessedOperationsCompanion(')
          ..write('operationId: $operationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('idempotencyKey: $idempotencyKey, ')
          ..write('clientSeq: $clientSeq, ')
          ..write('operationType: $operationType, ')
          ..write('requestHash: $requestHash, ')
          ..write('hashVersion: $hashVersion, ')
          ..write('resultPayload: $resultPayload, ')
          ..write('processedAt: $processedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DevicesTable extends Devices with TableInfo<$DevicesTable, Device> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta =
      const VerificationMeta('deviceId');
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
      'device_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _tokenHashMeta =
      const VerificationMeta('tokenHash');
  @override
  late final GeneratedColumn<String> tokenHash = GeneratedColumn<String>(
      'token_hash', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _saltMeta = const VerificationMeta('salt');
  @override
  late final GeneratedColumn<String> salt = GeneratedColumn<String>(
      'salt', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
      'is_active', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_active" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _isConfirmedMeta =
      const VerificationMeta('isConfirmed');
  @override
  late final GeneratedColumn<bool> isConfirmed = GeneratedColumn<bool>(
      'is_confirmed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_confirmed" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _lastUsedAtMeta =
      const VerificationMeta('lastUsedAt');
  @override
  late final GeneratedColumn<DateTime> lastUsedAt = GeneratedColumn<DateTime>(
      'last_used_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _expiresAtMeta =
      const VerificationMeta('expiresAt');
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
      'expires_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _lastProductSyncAtMeta =
      const VerificationMeta('lastProductSyncAt');
  @override
  late final GeneratedColumn<DateTime> lastProductSyncAt =
      GeneratedColumn<DateTime>('last_product_sync_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _lastCommittedClientSeqMeta =
      const VerificationMeta('lastCommittedClientSeq');
  @override
  late final GeneratedColumn<int> lastCommittedClientSeq = GeneratedColumn<int>(
      'last_committed_client_seq', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _maxSeenClientSeqMeta =
      const VerificationMeta('maxSeenClientSeq');
  @override
  late final GeneratedColumn<int> maxSeenClientSeq = GeneratedColumn<int>(
      'max_seen_client_seq', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastCommittedAtMeta =
      const VerificationMeta('lastCommittedAt');
  @override
  late final GeneratedColumn<DateTime> lastCommittedAt =
      GeneratedColumn<DateTime>('last_committed_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
      'role', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('CASHIER'));
  @override
  List<GeneratedColumn> get $columns => [
        deviceId,
        name,
        tokenHash,
        salt,
        isActive,
        isConfirmed,
        createdAt,
        lastUsedAt,
        expiresAt,
        lastProductSyncAt,
        lastCommittedClientSeq,
        maxSeenClientSeq,
        lastCommittedAt,
        role
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'devices';
  @override
  VerificationContext validateIntegrity(Insertable<Device> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(_deviceIdMeta,
          deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta));
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('token_hash')) {
      context.handle(_tokenHashMeta,
          tokenHash.isAcceptableOrUnknown(data['token_hash']!, _tokenHashMeta));
    } else if (isInserting) {
      context.missing(_tokenHashMeta);
    }
    if (data.containsKey('salt')) {
      context.handle(
          _saltMeta, salt.isAcceptableOrUnknown(data['salt']!, _saltMeta));
    } else if (isInserting) {
      context.missing(_saltMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('is_confirmed')) {
      context.handle(
          _isConfirmedMeta,
          isConfirmed.isAcceptableOrUnknown(
              data['is_confirmed']!, _isConfirmedMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('last_used_at')) {
      context.handle(
          _lastUsedAtMeta,
          lastUsedAt.isAcceptableOrUnknown(
              data['last_used_at']!, _lastUsedAtMeta));
    }
    if (data.containsKey('expires_at')) {
      context.handle(_expiresAtMeta,
          expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta));
    }
    if (data.containsKey('last_product_sync_at')) {
      context.handle(
          _lastProductSyncAtMeta,
          lastProductSyncAt.isAcceptableOrUnknown(
              data['last_product_sync_at']!, _lastProductSyncAtMeta));
    }
    if (data.containsKey('last_committed_client_seq')) {
      context.handle(
          _lastCommittedClientSeqMeta,
          lastCommittedClientSeq.isAcceptableOrUnknown(
              data['last_committed_client_seq']!, _lastCommittedClientSeqMeta));
    }
    if (data.containsKey('max_seen_client_seq')) {
      context.handle(
          _maxSeenClientSeqMeta,
          maxSeenClientSeq.isAcceptableOrUnknown(
              data['max_seen_client_seq']!, _maxSeenClientSeqMeta));
    }
    if (data.containsKey('last_committed_at')) {
      context.handle(
          _lastCommittedAtMeta,
          lastCommittedAt.isAcceptableOrUnknown(
              data['last_committed_at']!, _lastCommittedAtMeta));
    }
    if (data.containsKey('role')) {
      context.handle(
          _roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId};
  @override
  Device map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Device(
      deviceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      tokenHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}token_hash'])!,
      salt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}salt'])!,
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      isConfirmed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_confirmed'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      lastUsedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}last_used_at']),
      expiresAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}expires_at']),
      lastProductSyncAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime,
          data['${effectivePrefix}last_product_sync_at']),
      lastCommittedClientSeq: attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_committed_client_seq'])!,
      maxSeenClientSeq: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}max_seen_client_seq'])!,
      lastCommittedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_committed_at']),
      role: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}role'])!,
    );
  }

  @override
  $DevicesTable createAlias(String alias) {
    return $DevicesTable(attachedDatabase, alias);
  }
}

class Device extends DataClass implements Insertable<Device> {
  final String deviceId;
  final String name;
  final String tokenHash;
  final String salt;
  final bool isActive;
  final bool isConfirmed;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;
  final DateTime? lastProductSyncAt;
  final int lastCommittedClientSeq;
  final int maxSeenClientSeq;
  final DateTime? lastCommittedAt;
  final String role;
  const Device(
      {required this.deviceId,
      required this.name,
      required this.tokenHash,
      required this.salt,
      required this.isActive,
      required this.isConfirmed,
      required this.createdAt,
      this.lastUsedAt,
      this.expiresAt,
      this.lastProductSyncAt,
      required this.lastCommittedClientSeq,
      required this.maxSeenClientSeq,
      this.lastCommittedAt,
      required this.role});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['name'] = Variable<String>(name);
    map['token_hash'] = Variable<String>(tokenHash);
    map['salt'] = Variable<String>(salt);
    map['is_active'] = Variable<bool>(isActive);
    map['is_confirmed'] = Variable<bool>(isConfirmed);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastUsedAt != null) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt);
    }
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<DateTime>(expiresAt);
    }
    if (!nullToAbsent || lastProductSyncAt != null) {
      map['last_product_sync_at'] = Variable<DateTime>(lastProductSyncAt);
    }
    map['last_committed_client_seq'] = Variable<int>(lastCommittedClientSeq);
    map['max_seen_client_seq'] = Variable<int>(maxSeenClientSeq);
    if (!nullToAbsent || lastCommittedAt != null) {
      map['last_committed_at'] = Variable<DateTime>(lastCommittedAt);
    }
    map['role'] = Variable<String>(role);
    return map;
  }

  DevicesCompanion toCompanion(bool nullToAbsent) {
    return DevicesCompanion(
      deviceId: Value(deviceId),
      name: Value(name),
      tokenHash: Value(tokenHash),
      salt: Value(salt),
      isActive: Value(isActive),
      isConfirmed: Value(isConfirmed),
      createdAt: Value(createdAt),
      lastUsedAt: lastUsedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUsedAt),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
      lastProductSyncAt: lastProductSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastProductSyncAt),
      lastCommittedClientSeq: Value(lastCommittedClientSeq),
      maxSeenClientSeq: Value(maxSeenClientSeq),
      lastCommittedAt: lastCommittedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCommittedAt),
      role: Value(role),
    );
  }

  factory Device.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Device(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      name: serializer.fromJson<String>(json['name']),
      tokenHash: serializer.fromJson<String>(json['tokenHash']),
      salt: serializer.fromJson<String>(json['salt']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      isConfirmed: serializer.fromJson<bool>(json['isConfirmed']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastUsedAt: serializer.fromJson<DateTime?>(json['lastUsedAt']),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
      lastProductSyncAt:
          serializer.fromJson<DateTime?>(json['lastProductSyncAt']),
      lastCommittedClientSeq:
          serializer.fromJson<int>(json['lastCommittedClientSeq']),
      maxSeenClientSeq: serializer.fromJson<int>(json['maxSeenClientSeq']),
      lastCommittedAt: serializer.fromJson<DateTime?>(json['lastCommittedAt']),
      role: serializer.fromJson<String>(json['role']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'name': serializer.toJson<String>(name),
      'tokenHash': serializer.toJson<String>(tokenHash),
      'salt': serializer.toJson<String>(salt),
      'isActive': serializer.toJson<bool>(isActive),
      'isConfirmed': serializer.toJson<bool>(isConfirmed),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastUsedAt': serializer.toJson<DateTime?>(lastUsedAt),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
      'lastProductSyncAt': serializer.toJson<DateTime?>(lastProductSyncAt),
      'lastCommittedClientSeq': serializer.toJson<int>(lastCommittedClientSeq),
      'maxSeenClientSeq': serializer.toJson<int>(maxSeenClientSeq),
      'lastCommittedAt': serializer.toJson<DateTime?>(lastCommittedAt),
      'role': serializer.toJson<String>(role),
    };
  }

  Device copyWith(
          {String? deviceId,
          String? name,
          String? tokenHash,
          String? salt,
          bool? isActive,
          bool? isConfirmed,
          DateTime? createdAt,
          Value<DateTime?> lastUsedAt = const Value.absent(),
          Value<DateTime?> expiresAt = const Value.absent(),
          Value<DateTime?> lastProductSyncAt = const Value.absent(),
          int? lastCommittedClientSeq,
          int? maxSeenClientSeq,
          Value<DateTime?> lastCommittedAt = const Value.absent(),
          String? role}) =>
      Device(
        deviceId: deviceId ?? this.deviceId,
        name: name ?? this.name,
        tokenHash: tokenHash ?? this.tokenHash,
        salt: salt ?? this.salt,
        isActive: isActive ?? this.isActive,
        isConfirmed: isConfirmed ?? this.isConfirmed,
        createdAt: createdAt ?? this.createdAt,
        lastUsedAt: lastUsedAt.present ? lastUsedAt.value : this.lastUsedAt,
        expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
        lastProductSyncAt: lastProductSyncAt.present
            ? lastProductSyncAt.value
            : this.lastProductSyncAt,
        lastCommittedClientSeq:
            lastCommittedClientSeq ?? this.lastCommittedClientSeq,
        maxSeenClientSeq: maxSeenClientSeq ?? this.maxSeenClientSeq,
        lastCommittedAt: lastCommittedAt.present
            ? lastCommittedAt.value
            : this.lastCommittedAt,
        role: role ?? this.role,
      );
  Device copyWithCompanion(DevicesCompanion data) {
    return Device(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      name: data.name.present ? data.name.value : this.name,
      tokenHash: data.tokenHash.present ? data.tokenHash.value : this.tokenHash,
      salt: data.salt.present ? data.salt.value : this.salt,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      isConfirmed:
          data.isConfirmed.present ? data.isConfirmed.value : this.isConfirmed,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastUsedAt:
          data.lastUsedAt.present ? data.lastUsedAt.value : this.lastUsedAt,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      lastProductSyncAt: data.lastProductSyncAt.present
          ? data.lastProductSyncAt.value
          : this.lastProductSyncAt,
      lastCommittedClientSeq: data.lastCommittedClientSeq.present
          ? data.lastCommittedClientSeq.value
          : this.lastCommittedClientSeq,
      maxSeenClientSeq: data.maxSeenClientSeq.present
          ? data.maxSeenClientSeq.value
          : this.maxSeenClientSeq,
      lastCommittedAt: data.lastCommittedAt.present
          ? data.lastCommittedAt.value
          : this.lastCommittedAt,
      role: data.role.present ? data.role.value : this.role,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Device(')
          ..write('deviceId: $deviceId, ')
          ..write('name: $name, ')
          ..write('tokenHash: $tokenHash, ')
          ..write('salt: $salt, ')
          ..write('isActive: $isActive, ')
          ..write('isConfirmed: $isConfirmed, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('lastProductSyncAt: $lastProductSyncAt, ')
          ..write('lastCommittedClientSeq: $lastCommittedClientSeq, ')
          ..write('maxSeenClientSeq: $maxSeenClientSeq, ')
          ..write('lastCommittedAt: $lastCommittedAt, ')
          ..write('role: $role')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      deviceId,
      name,
      tokenHash,
      salt,
      isActive,
      isConfirmed,
      createdAt,
      lastUsedAt,
      expiresAt,
      lastProductSyncAt,
      lastCommittedClientSeq,
      maxSeenClientSeq,
      lastCommittedAt,
      role);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Device &&
          other.deviceId == this.deviceId &&
          other.name == this.name &&
          other.tokenHash == this.tokenHash &&
          other.salt == this.salt &&
          other.isActive == this.isActive &&
          other.isConfirmed == this.isConfirmed &&
          other.createdAt == this.createdAt &&
          other.lastUsedAt == this.lastUsedAt &&
          other.expiresAt == this.expiresAt &&
          other.lastProductSyncAt == this.lastProductSyncAt &&
          other.lastCommittedClientSeq == this.lastCommittedClientSeq &&
          other.maxSeenClientSeq == this.maxSeenClientSeq &&
          other.lastCommittedAt == this.lastCommittedAt &&
          other.role == this.role);
}

class DevicesCompanion extends UpdateCompanion<Device> {
  final Value<String> deviceId;
  final Value<String> name;
  final Value<String> tokenHash;
  final Value<String> salt;
  final Value<bool> isActive;
  final Value<bool> isConfirmed;
  final Value<DateTime> createdAt;
  final Value<DateTime?> lastUsedAt;
  final Value<DateTime?> expiresAt;
  final Value<DateTime?> lastProductSyncAt;
  final Value<int> lastCommittedClientSeq;
  final Value<int> maxSeenClientSeq;
  final Value<DateTime?> lastCommittedAt;
  final Value<String> role;
  final Value<int> rowid;
  const DevicesCompanion({
    this.deviceId = const Value.absent(),
    this.name = const Value.absent(),
    this.tokenHash = const Value.absent(),
    this.salt = const Value.absent(),
    this.isActive = const Value.absent(),
    this.isConfirmed = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.lastProductSyncAt = const Value.absent(),
    this.lastCommittedClientSeq = const Value.absent(),
    this.maxSeenClientSeq = const Value.absent(),
    this.lastCommittedAt = const Value.absent(),
    this.role = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DevicesCompanion.insert({
    required String deviceId,
    required String name,
    required String tokenHash,
    required String salt,
    this.isActive = const Value.absent(),
    this.isConfirmed = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.lastProductSyncAt = const Value.absent(),
    this.lastCommittedClientSeq = const Value.absent(),
    this.maxSeenClientSeq = const Value.absent(),
    this.lastCommittedAt = const Value.absent(),
    this.role = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : deviceId = Value(deviceId),
        name = Value(name),
        tokenHash = Value(tokenHash),
        salt = Value(salt);
  static Insertable<Device> custom({
    Expression<String>? deviceId,
    Expression<String>? name,
    Expression<String>? tokenHash,
    Expression<String>? salt,
    Expression<bool>? isActive,
    Expression<bool>? isConfirmed,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastUsedAt,
    Expression<DateTime>? expiresAt,
    Expression<DateTime>? lastProductSyncAt,
    Expression<int>? lastCommittedClientSeq,
    Expression<int>? maxSeenClientSeq,
    Expression<DateTime>? lastCommittedAt,
    Expression<String>? role,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (name != null) 'name': name,
      if (tokenHash != null) 'token_hash': tokenHash,
      if (salt != null) 'salt': salt,
      if (isActive != null) 'is_active': isActive,
      if (isConfirmed != null) 'is_confirmed': isConfirmed,
      if (createdAt != null) 'created_at': createdAt,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (lastProductSyncAt != null) 'last_product_sync_at': lastProductSyncAt,
      if (lastCommittedClientSeq != null)
        'last_committed_client_seq': lastCommittedClientSeq,
      if (maxSeenClientSeq != null) 'max_seen_client_seq': maxSeenClientSeq,
      if (lastCommittedAt != null) 'last_committed_at': lastCommittedAt,
      if (role != null) 'role': role,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DevicesCompanion copyWith(
      {Value<String>? deviceId,
      Value<String>? name,
      Value<String>? tokenHash,
      Value<String>? salt,
      Value<bool>? isActive,
      Value<bool>? isConfirmed,
      Value<DateTime>? createdAt,
      Value<DateTime?>? lastUsedAt,
      Value<DateTime?>? expiresAt,
      Value<DateTime?>? lastProductSyncAt,
      Value<int>? lastCommittedClientSeq,
      Value<int>? maxSeenClientSeq,
      Value<DateTime?>? lastCommittedAt,
      Value<String>? role,
      Value<int>? rowid}) {
    return DevicesCompanion(
      deviceId: deviceId ?? this.deviceId,
      name: name ?? this.name,
      tokenHash: tokenHash ?? this.tokenHash,
      salt: salt ?? this.salt,
      isActive: isActive ?? this.isActive,
      isConfirmed: isConfirmed ?? this.isConfirmed,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      lastProductSyncAt: lastProductSyncAt ?? this.lastProductSyncAt,
      lastCommittedClientSeq:
          lastCommittedClientSeq ?? this.lastCommittedClientSeq,
      maxSeenClientSeq: maxSeenClientSeq ?? this.maxSeenClientSeq,
      lastCommittedAt: lastCommittedAt ?? this.lastCommittedAt,
      role: role ?? this.role,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (tokenHash.present) {
      map['token_hash'] = Variable<String>(tokenHash.value);
    }
    if (salt.present) {
      map['salt'] = Variable<String>(salt.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (isConfirmed.present) {
      map['is_confirmed'] = Variable<bool>(isConfirmed.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (lastProductSyncAt.present) {
      map['last_product_sync_at'] = Variable<DateTime>(lastProductSyncAt.value);
    }
    if (lastCommittedClientSeq.present) {
      map['last_committed_client_seq'] =
          Variable<int>(lastCommittedClientSeq.value);
    }
    if (maxSeenClientSeq.present) {
      map['max_seen_client_seq'] = Variable<int>(maxSeenClientSeq.value);
    }
    if (lastCommittedAt.present) {
      map['last_committed_at'] = Variable<DateTime>(lastCommittedAt.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DevicesCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('name: $name, ')
          ..write('tokenHash: $tokenHash, ')
          ..write('salt: $salt, ')
          ..write('isActive: $isActive, ')
          ..write('isConfirmed: $isConfirmed, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('lastProductSyncAt: $lastProductSyncAt, ')
          ..write('lastCommittedClientSeq: $lastCommittedClientSeq, ')
          ..write('maxSeenClientSeq: $maxSeenClientSeq, ')
          ..write('lastCommittedAt: $lastCommittedAt, ')
          ..write('role: $role, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DeviceAuditLogsTable extends DeviceAuditLogs
    with TableInfo<$DeviceAuditLogsTable, DeviceAuditLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeviceAuditLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _deviceIdMeta =
      const VerificationMeta('deviceId');
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
      'device_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
      'action', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _detailsMeta =
      const VerificationMeta('details');
  @override
  late final GeneratedColumn<String> details = GeneratedColumn<String>(
      'details', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, deviceId, action, details, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'device_audit_logs';
  @override
  VerificationContext validateIntegrity(Insertable<DeviceAuditLog> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('device_id')) {
      context.handle(_deviceIdMeta,
          deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta));
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('action')) {
      context.handle(_actionMeta,
          action.isAcceptableOrUnknown(data['action']!, _actionMeta));
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('details')) {
      context.handle(_detailsMeta,
          details.isAcceptableOrUnknown(data['details']!, _detailsMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DeviceAuditLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeviceAuditLog(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      deviceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_id'])!,
      action: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}action'])!,
      details: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}details']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $DeviceAuditLogsTable createAlias(String alias) {
    return $DeviceAuditLogsTable(attachedDatabase, alias);
  }
}

class DeviceAuditLog extends DataClass implements Insertable<DeviceAuditLog> {
  final int id;
  final String deviceId;
  final String action;
  final String? details;
  final DateTime createdAt;
  const DeviceAuditLog(
      {required this.id,
      required this.deviceId,
      required this.action,
      this.details,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['device_id'] = Variable<String>(deviceId);
    map['action'] = Variable<String>(action);
    if (!nullToAbsent || details != null) {
      map['details'] = Variable<String>(details);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  DeviceAuditLogsCompanion toCompanion(bool nullToAbsent) {
    return DeviceAuditLogsCompanion(
      id: Value(id),
      deviceId: Value(deviceId),
      action: Value(action),
      details: details == null && nullToAbsent
          ? const Value.absent()
          : Value(details),
      createdAt: Value(createdAt),
    );
  }

  factory DeviceAuditLog.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeviceAuditLog(
      id: serializer.fromJson<int>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      action: serializer.fromJson<String>(json['action']),
      details: serializer.fromJson<String?>(json['details']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'action': serializer.toJson<String>(action),
      'details': serializer.toJson<String?>(details),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  DeviceAuditLog copyWith(
          {int? id,
          String? deviceId,
          String? action,
          Value<String?> details = const Value.absent(),
          DateTime? createdAt}) =>
      DeviceAuditLog(
        id: id ?? this.id,
        deviceId: deviceId ?? this.deviceId,
        action: action ?? this.action,
        details: details.present ? details.value : this.details,
        createdAt: createdAt ?? this.createdAt,
      );
  DeviceAuditLog copyWithCompanion(DeviceAuditLogsCompanion data) {
    return DeviceAuditLog(
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      action: data.action.present ? data.action.value : this.action,
      details: data.details.present ? data.details.value : this.details,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeviceAuditLog(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('action: $action, ')
          ..write('details: $details, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, deviceId, action, details, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeviceAuditLog &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.action == this.action &&
          other.details == this.details &&
          other.createdAt == this.createdAt);
}

class DeviceAuditLogsCompanion extends UpdateCompanion<DeviceAuditLog> {
  final Value<int> id;
  final Value<String> deviceId;
  final Value<String> action;
  final Value<String?> details;
  final Value<DateTime> createdAt;
  const DeviceAuditLogsCompanion({
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.action = const Value.absent(),
    this.details = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  DeviceAuditLogsCompanion.insert({
    this.id = const Value.absent(),
    required String deviceId,
    required String action,
    this.details = const Value.absent(),
    this.createdAt = const Value.absent(),
  })  : deviceId = Value(deviceId),
        action = Value(action);
  static Insertable<DeviceAuditLog> custom({
    Expression<int>? id,
    Expression<String>? deviceId,
    Expression<String>? action,
    Expression<String>? details,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (action != null) 'action': action,
      if (details != null) 'details': details,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  DeviceAuditLogsCompanion copyWith(
      {Value<int>? id,
      Value<String>? deviceId,
      Value<String>? action,
      Value<String?>? details,
      Value<DateTime>? createdAt}) {
    return DeviceAuditLogsCompanion(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      action: action ?? this.action,
      details: details ?? this.details,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (details.present) {
      map['details'] = Variable<String>(details.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeviceAuditLogsCompanion(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('action: $action, ')
          ..write('details: $details, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ProductPriceHistoriesTable extends ProductPriceHistories
    with TableInfo<$ProductPriceHistoriesTable, ProductPriceHistory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductPriceHistoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES products (id)'));
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<int> price = GeneratedColumn<int>(
      'price', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _validFromMeta =
      const VerificationMeta('validFrom');
  @override
  late final GeneratedColumn<DateTime> validFrom = GeneratedColumn<DateTime>(
      'valid_from', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _validUntilMeta =
      const VerificationMeta('validUntil');
  @override
  late final GeneratedColumn<DateTime> validUntil = GeneratedColumn<DateTime>(
      'valid_until', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, productId, price, validFrom, validUntil, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'product_price_histories';
  @override
  VerificationContext validateIntegrity(
      Insertable<ProductPriceHistory> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta,
          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('price')) {
      context.handle(
          _priceMeta, price.isAcceptableOrUnknown(data['price']!, _priceMeta));
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('valid_from')) {
      context.handle(_validFromMeta,
          validFrom.isAcceptableOrUnknown(data['valid_from']!, _validFromMeta));
    } else if (isInserting) {
      context.missing(_validFromMeta);
    }
    if (data.containsKey('valid_until')) {
      context.handle(
          _validUntilMeta,
          validUntil.isAcceptableOrUnknown(
              data['valid_until']!, _validUntilMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProductPriceHistory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductPriceHistory(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      price: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}price'])!,
      validFrom: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}valid_from'])!,
      validUntil: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}valid_until']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $ProductPriceHistoriesTable createAlias(String alias) {
    return $ProductPriceHistoriesTable(attachedDatabase, alias);
  }
}

class ProductPriceHistory extends DataClass
    implements Insertable<ProductPriceHistory> {
  final String id;
  final String productId;
  final int price;
  final DateTime validFrom;
  final DateTime? validUntil;
  final DateTime createdAt;
  const ProductPriceHistory(
      {required this.id,
      required this.productId,
      required this.price,
      required this.validFrom,
      this.validUntil,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_id'] = Variable<String>(productId);
    map['price'] = Variable<int>(price);
    map['valid_from'] = Variable<DateTime>(validFrom);
    if (!nullToAbsent || validUntil != null) {
      map['valid_until'] = Variable<DateTime>(validUntil);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ProductPriceHistoriesCompanion toCompanion(bool nullToAbsent) {
    return ProductPriceHistoriesCompanion(
      id: Value(id),
      productId: Value(productId),
      price: Value(price),
      validFrom: Value(validFrom),
      validUntil: validUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(validUntil),
      createdAt: Value(createdAt),
    );
  }

  factory ProductPriceHistory.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductPriceHistory(
      id: serializer.fromJson<String>(json['id']),
      productId: serializer.fromJson<String>(json['productId']),
      price: serializer.fromJson<int>(json['price']),
      validFrom: serializer.fromJson<DateTime>(json['validFrom']),
      validUntil: serializer.fromJson<DateTime?>(json['validUntil']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productId': serializer.toJson<String>(productId),
      'price': serializer.toJson<int>(price),
      'validFrom': serializer.toJson<DateTime>(validFrom),
      'validUntil': serializer.toJson<DateTime?>(validUntil),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ProductPriceHistory copyWith(
          {String? id,
          String? productId,
          int? price,
          DateTime? validFrom,
          Value<DateTime?> validUntil = const Value.absent(),
          DateTime? createdAt}) =>
      ProductPriceHistory(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        price: price ?? this.price,
        validFrom: validFrom ?? this.validFrom,
        validUntil: validUntil.present ? validUntil.value : this.validUntil,
        createdAt: createdAt ?? this.createdAt,
      );
  ProductPriceHistory copyWithCompanion(ProductPriceHistoriesCompanion data) {
    return ProductPriceHistory(
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      price: data.price.present ? data.price.value : this.price,
      validFrom: data.validFrom.present ? data.validFrom.value : this.validFrom,
      validUntil:
          data.validUntil.present ? data.validUntil.value : this.validUntil,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductPriceHistory(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('price: $price, ')
          ..write('validFrom: $validFrom, ')
          ..write('validUntil: $validUntil, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, productId, price, validFrom, validUntil, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductPriceHistory &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.price == this.price &&
          other.validFrom == this.validFrom &&
          other.validUntil == this.validUntil &&
          other.createdAt == this.createdAt);
}

class ProductPriceHistoriesCompanion
    extends UpdateCompanion<ProductPriceHistory> {
  final Value<String> id;
  final Value<String> productId;
  final Value<int> price;
  final Value<DateTime> validFrom;
  final Value<DateTime?> validUntil;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ProductPriceHistoriesCompanion({
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.price = const Value.absent(),
    this.validFrom = const Value.absent(),
    this.validUntil = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductPriceHistoriesCompanion.insert({
    required String id,
    required String productId,
    required int price,
    required DateTime validFrom,
    this.validUntil = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        productId = Value(productId),
        price = Value(price),
        validFrom = Value(validFrom);
  static Insertable<ProductPriceHistory> custom({
    Expression<String>? id,
    Expression<String>? productId,
    Expression<int>? price,
    Expression<DateTime>? validFrom,
    Expression<DateTime>? validUntil,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (price != null) 'price': price,
      if (validFrom != null) 'valid_from': validFrom,
      if (validUntil != null) 'valid_until': validUntil,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductPriceHistoriesCompanion copyWith(
      {Value<String>? id,
      Value<String>? productId,
      Value<int>? price,
      Value<DateTime>? validFrom,
      Value<DateTime?>? validUntil,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return ProductPriceHistoriesCompanion(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      price: price ?? this.price,
      validFrom: validFrom ?? this.validFrom,
      validUntil: validUntil ?? this.validUntil,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (price.present) {
      map['price'] = Variable<int>(price.value);
    }
    if (validFrom.present) {
      map['valid_from'] = Variable<DateTime>(validFrom.value);
    }
    if (validUntil.present) {
      map['valid_until'] = Variable<DateTime>(validUntil.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductPriceHistoriesCompanion(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('price: $price, ')
          ..write('validFrom: $validFrom, ')
          ..write('validUntil: $validUntil, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductSyncSessionsTable extends ProductSyncSessions
    with TableInfo<$ProductSyncSessionsTable, ProductSyncSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductSyncSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _deviceIdMeta =
      const VerificationMeta('deviceId');
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
      'device_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _productCountMeta =
      const VerificationMeta('productCount');
  @override
  late final GeneratedColumn<int> productCount = GeneratedColumn<int>(
      'product_count', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _syncedAtMeta =
      const VerificationMeta('syncedAt');
  @override
  late final GeneratedColumn<DateTime> syncedAt = GeneratedColumn<DateTime>(
      'synced_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _isAcknowledgedMeta =
      const VerificationMeta('isAcknowledged');
  @override
  late final GeneratedColumn<bool> isAcknowledged = GeneratedColumn<bool>(
      'is_acknowledged', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_acknowledged" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _acknowledgedAtMeta =
      const VerificationMeta('acknowledgedAt');
  @override
  late final GeneratedColumn<DateTime> acknowledgedAt =
      GeneratedColumn<DateTime>('acknowledged_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        deviceId,
        productCount,
        syncedAt,
        isAcknowledged,
        acknowledgedAt,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'product_sync_sessions';
  @override
  VerificationContext validateIntegrity(Insertable<ProductSyncSession> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(_deviceIdMeta,
          deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta));
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('product_count')) {
      context.handle(
          _productCountMeta,
          productCount.isAcceptableOrUnknown(
              data['product_count']!, _productCountMeta));
    } else if (isInserting) {
      context.missing(_productCountMeta);
    }
    if (data.containsKey('synced_at')) {
      context.handle(_syncedAtMeta,
          syncedAt.isAcceptableOrUnknown(data['synced_at']!, _syncedAtMeta));
    } else if (isInserting) {
      context.missing(_syncedAtMeta);
    }
    if (data.containsKey('is_acknowledged')) {
      context.handle(
          _isAcknowledgedMeta,
          isAcknowledged.isAcceptableOrUnknown(
              data['is_acknowledged']!, _isAcknowledgedMeta));
    }
    if (data.containsKey('acknowledged_at')) {
      context.handle(
          _acknowledgedAtMeta,
          acknowledgedAt.isAcceptableOrUnknown(
              data['acknowledged_at']!, _acknowledgedAtMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProductSyncSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProductSyncSession(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      deviceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_id'])!,
      productCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}product_count'])!,
      syncedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}synced_at'])!,
      isAcknowledged: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_acknowledged'])!,
      acknowledgedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}acknowledged_at']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $ProductSyncSessionsTable createAlias(String alias) {
    return $ProductSyncSessionsTable(attachedDatabase, alias);
  }
}

class ProductSyncSession extends DataClass
    implements Insertable<ProductSyncSession> {
  final String id;
  final String deviceId;
  final int productCount;
  final DateTime syncedAt;
  final bool isAcknowledged;
  final DateTime? acknowledgedAt;
  final DateTime createdAt;
  const ProductSyncSession(
      {required this.id,
      required this.deviceId,
      required this.productCount,
      required this.syncedAt,
      required this.isAcknowledged,
      this.acknowledgedAt,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['device_id'] = Variable<String>(deviceId);
    map['product_count'] = Variable<int>(productCount);
    map['synced_at'] = Variable<DateTime>(syncedAt);
    map['is_acknowledged'] = Variable<bool>(isAcknowledged);
    if (!nullToAbsent || acknowledgedAt != null) {
      map['acknowledged_at'] = Variable<DateTime>(acknowledgedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ProductSyncSessionsCompanion toCompanion(bool nullToAbsent) {
    return ProductSyncSessionsCompanion(
      id: Value(id),
      deviceId: Value(deviceId),
      productCount: Value(productCount),
      syncedAt: Value(syncedAt),
      isAcknowledged: Value(isAcknowledged),
      acknowledgedAt: acknowledgedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(acknowledgedAt),
      createdAt: Value(createdAt),
    );
  }

  factory ProductSyncSession.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProductSyncSession(
      id: serializer.fromJson<String>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      productCount: serializer.fromJson<int>(json['productCount']),
      syncedAt: serializer.fromJson<DateTime>(json['syncedAt']),
      isAcknowledged: serializer.fromJson<bool>(json['isAcknowledged']),
      acknowledgedAt: serializer.fromJson<DateTime?>(json['acknowledgedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'productCount': serializer.toJson<int>(productCount),
      'syncedAt': serializer.toJson<DateTime>(syncedAt),
      'isAcknowledged': serializer.toJson<bool>(isAcknowledged),
      'acknowledgedAt': serializer.toJson<DateTime?>(acknowledgedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ProductSyncSession copyWith(
          {String? id,
          String? deviceId,
          int? productCount,
          DateTime? syncedAt,
          bool? isAcknowledged,
          Value<DateTime?> acknowledgedAt = const Value.absent(),
          DateTime? createdAt}) =>
      ProductSyncSession(
        id: id ?? this.id,
        deviceId: deviceId ?? this.deviceId,
        productCount: productCount ?? this.productCount,
        syncedAt: syncedAt ?? this.syncedAt,
        isAcknowledged: isAcknowledged ?? this.isAcknowledged,
        acknowledgedAt:
            acknowledgedAt.present ? acknowledgedAt.value : this.acknowledgedAt,
        createdAt: createdAt ?? this.createdAt,
      );
  ProductSyncSession copyWithCompanion(ProductSyncSessionsCompanion data) {
    return ProductSyncSession(
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      productCount: data.productCount.present
          ? data.productCount.value
          : this.productCount,
      syncedAt: data.syncedAt.present ? data.syncedAt.value : this.syncedAt,
      isAcknowledged: data.isAcknowledged.present
          ? data.isAcknowledged.value
          : this.isAcknowledged,
      acknowledgedAt: data.acknowledgedAt.present
          ? data.acknowledgedAt.value
          : this.acknowledgedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProductSyncSession(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('productCount: $productCount, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('isAcknowledged: $isAcknowledged, ')
          ..write('acknowledgedAt: $acknowledgedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, deviceId, productCount, syncedAt,
      isAcknowledged, acknowledgedAt, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProductSyncSession &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.productCount == this.productCount &&
          other.syncedAt == this.syncedAt &&
          other.isAcknowledged == this.isAcknowledged &&
          other.acknowledgedAt == this.acknowledgedAt &&
          other.createdAt == this.createdAt);
}

class ProductSyncSessionsCompanion extends UpdateCompanion<ProductSyncSession> {
  final Value<String> id;
  final Value<String> deviceId;
  final Value<int> productCount;
  final Value<DateTime> syncedAt;
  final Value<bool> isAcknowledged;
  final Value<DateTime?> acknowledgedAt;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ProductSyncSessionsCompanion({
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.productCount = const Value.absent(),
    this.syncedAt = const Value.absent(),
    this.isAcknowledged = const Value.absent(),
    this.acknowledgedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductSyncSessionsCompanion.insert({
    required String id,
    required String deviceId,
    required int productCount,
    required DateTime syncedAt,
    this.isAcknowledged = const Value.absent(),
    this.acknowledgedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        deviceId = Value(deviceId),
        productCount = Value(productCount),
        syncedAt = Value(syncedAt);
  static Insertable<ProductSyncSession> custom({
    Expression<String>? id,
    Expression<String>? deviceId,
    Expression<int>? productCount,
    Expression<DateTime>? syncedAt,
    Expression<bool>? isAcknowledged,
    Expression<DateTime>? acknowledgedAt,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (productCount != null) 'product_count': productCount,
      if (syncedAt != null) 'synced_at': syncedAt,
      if (isAcknowledged != null) 'is_acknowledged': isAcknowledged,
      if (acknowledgedAt != null) 'acknowledged_at': acknowledgedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductSyncSessionsCompanion copyWith(
      {Value<String>? id,
      Value<String>? deviceId,
      Value<int>? productCount,
      Value<DateTime>? syncedAt,
      Value<bool>? isAcknowledged,
      Value<DateTime?>? acknowledgedAt,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return ProductSyncSessionsCompanion(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      productCount: productCount ?? this.productCount,
      syncedAt: syncedAt ?? this.syncedAt,
      isAcknowledged: isAcknowledged ?? this.isAcknowledged,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (productCount.present) {
      map['product_count'] = Variable<int>(productCount.value);
    }
    if (syncedAt.present) {
      map['synced_at'] = Variable<DateTime>(syncedAt.value);
    }
    if (isAcknowledged.present) {
      map['is_acknowledged'] = Variable<bool>(isAcknowledged.value);
    }
    if (acknowledgedAt.present) {
      map['acknowledged_at'] = Variable<DateTime>(acknowledgedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductSyncSessionsCompanion(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('productCount: $productCount, ')
          ..write('syncedAt: $syncedAt, ')
          ..write('isAcknowledged: $isAcknowledged, ')
          ..write('acknowledgedAt: $acknowledgedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RefundsTable extends Refunds with TableInfo<$RefundsTable, Refund> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RefundsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _saleIdMeta = const VerificationMeta('saleId');
  @override
  late final GeneratedColumn<String> saleId = GeneratedColumn<String>(
      'sale_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES sales (id)'));
  static const VerificationMeta _deviceIdMeta =
      const VerificationMeta('deviceId');
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
      'device_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _clientSeqMeta =
      const VerificationMeta('clientSeq');
  @override
  late final GeneratedColumn<int> clientSeq = GeneratedColumn<int>(
      'client_seq', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _totalRefundAmountMeta =
      const VerificationMeta('totalRefundAmount');
  @override
  late final GeneratedColumn<int> totalRefundAmount = GeneratedColumn<int>(
      'total_refund_amount', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _paymentMethodMeta =
      const VerificationMeta('paymentMethod');
  @override
  late final GeneratedColumn<String> paymentMethod = GeneratedColumn<String>(
      'payment_method', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
      'reason', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        saleId,
        deviceId,
        clientSeq,
        totalRefundAmount,
        paymentMethod,
        reason,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'refunds';
  @override
  VerificationContext validateIntegrity(Insertable<Refund> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('sale_id')) {
      context.handle(_saleIdMeta,
          saleId.isAcceptableOrUnknown(data['sale_id']!, _saleIdMeta));
    } else if (isInserting) {
      context.missing(_saleIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(_deviceIdMeta,
          deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta));
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('client_seq')) {
      context.handle(_clientSeqMeta,
          clientSeq.isAcceptableOrUnknown(data['client_seq']!, _clientSeqMeta));
    } else if (isInserting) {
      context.missing(_clientSeqMeta);
    }
    if (data.containsKey('total_refund_amount')) {
      context.handle(
          _totalRefundAmountMeta,
          totalRefundAmount.isAcceptableOrUnknown(
              data['total_refund_amount']!, _totalRefundAmountMeta));
    } else if (isInserting) {
      context.missing(_totalRefundAmountMeta);
    }
    if (data.containsKey('payment_method')) {
      context.handle(
          _paymentMethodMeta,
          paymentMethod.isAcceptableOrUnknown(
              data['payment_method']!, _paymentMethodMeta));
    } else if (isInserting) {
      context.missing(_paymentMethodMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(_reasonMeta,
          reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta));
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Refund map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Refund(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      saleId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sale_id'])!,
      deviceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_id'])!,
      clientSeq: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}client_seq'])!,
      totalRefundAmount: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}total_refund_amount'])!,
      paymentMethod: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payment_method'])!,
      reason: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reason'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $RefundsTable createAlias(String alias) {
    return $RefundsTable(attachedDatabase, alias);
  }
}

class Refund extends DataClass implements Insertable<Refund> {
  final String id;
  final String saleId;
  final String deviceId;
  final int clientSeq;
  final int totalRefundAmount;
  final String paymentMethod;
  final String reason;
  final DateTime createdAt;
  const Refund(
      {required this.id,
      required this.saleId,
      required this.deviceId,
      required this.clientSeq,
      required this.totalRefundAmount,
      required this.paymentMethod,
      required this.reason,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['sale_id'] = Variable<String>(saleId);
    map['device_id'] = Variable<String>(deviceId);
    map['client_seq'] = Variable<int>(clientSeq);
    map['total_refund_amount'] = Variable<int>(totalRefundAmount);
    map['payment_method'] = Variable<String>(paymentMethod);
    map['reason'] = Variable<String>(reason);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  RefundsCompanion toCompanion(bool nullToAbsent) {
    return RefundsCompanion(
      id: Value(id),
      saleId: Value(saleId),
      deviceId: Value(deviceId),
      clientSeq: Value(clientSeq),
      totalRefundAmount: Value(totalRefundAmount),
      paymentMethod: Value(paymentMethod),
      reason: Value(reason),
      createdAt: Value(createdAt),
    );
  }

  factory Refund.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Refund(
      id: serializer.fromJson<String>(json['id']),
      saleId: serializer.fromJson<String>(json['saleId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      clientSeq: serializer.fromJson<int>(json['clientSeq']),
      totalRefundAmount: serializer.fromJson<int>(json['totalRefundAmount']),
      paymentMethod: serializer.fromJson<String>(json['paymentMethod']),
      reason: serializer.fromJson<String>(json['reason']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'saleId': serializer.toJson<String>(saleId),
      'deviceId': serializer.toJson<String>(deviceId),
      'clientSeq': serializer.toJson<int>(clientSeq),
      'totalRefundAmount': serializer.toJson<int>(totalRefundAmount),
      'paymentMethod': serializer.toJson<String>(paymentMethod),
      'reason': serializer.toJson<String>(reason),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Refund copyWith(
          {String? id,
          String? saleId,
          String? deviceId,
          int? clientSeq,
          int? totalRefundAmount,
          String? paymentMethod,
          String? reason,
          DateTime? createdAt}) =>
      Refund(
        id: id ?? this.id,
        saleId: saleId ?? this.saleId,
        deviceId: deviceId ?? this.deviceId,
        clientSeq: clientSeq ?? this.clientSeq,
        totalRefundAmount: totalRefundAmount ?? this.totalRefundAmount,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        reason: reason ?? this.reason,
        createdAt: createdAt ?? this.createdAt,
      );
  Refund copyWithCompanion(RefundsCompanion data) {
    return Refund(
      id: data.id.present ? data.id.value : this.id,
      saleId: data.saleId.present ? data.saleId.value : this.saleId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      clientSeq: data.clientSeq.present ? data.clientSeq.value : this.clientSeq,
      totalRefundAmount: data.totalRefundAmount.present
          ? data.totalRefundAmount.value
          : this.totalRefundAmount,
      paymentMethod: data.paymentMethod.present
          ? data.paymentMethod.value
          : this.paymentMethod,
      reason: data.reason.present ? data.reason.value : this.reason,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Refund(')
          ..write('id: $id, ')
          ..write('saleId: $saleId, ')
          ..write('deviceId: $deviceId, ')
          ..write('clientSeq: $clientSeq, ')
          ..write('totalRefundAmount: $totalRefundAmount, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('reason: $reason, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, saleId, deviceId, clientSeq,
      totalRefundAmount, paymentMethod, reason, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Refund &&
          other.id == this.id &&
          other.saleId == this.saleId &&
          other.deviceId == this.deviceId &&
          other.clientSeq == this.clientSeq &&
          other.totalRefundAmount == this.totalRefundAmount &&
          other.paymentMethod == this.paymentMethod &&
          other.reason == this.reason &&
          other.createdAt == this.createdAt);
}

class RefundsCompanion extends UpdateCompanion<Refund> {
  final Value<String> id;
  final Value<String> saleId;
  final Value<String> deviceId;
  final Value<int> clientSeq;
  final Value<int> totalRefundAmount;
  final Value<String> paymentMethod;
  final Value<String> reason;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const RefundsCompanion({
    this.id = const Value.absent(),
    this.saleId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.clientSeq = const Value.absent(),
    this.totalRefundAmount = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.reason = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RefundsCompanion.insert({
    required String id,
    required String saleId,
    required String deviceId,
    required int clientSeq,
    required int totalRefundAmount,
    required String paymentMethod,
    required String reason,
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        saleId = Value(saleId),
        deviceId = Value(deviceId),
        clientSeq = Value(clientSeq),
        totalRefundAmount = Value(totalRefundAmount),
        paymentMethod = Value(paymentMethod),
        reason = Value(reason);
  static Insertable<Refund> custom({
    Expression<String>? id,
    Expression<String>? saleId,
    Expression<String>? deviceId,
    Expression<int>? clientSeq,
    Expression<int>? totalRefundAmount,
    Expression<String>? paymentMethod,
    Expression<String>? reason,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (saleId != null) 'sale_id': saleId,
      if (deviceId != null) 'device_id': deviceId,
      if (clientSeq != null) 'client_seq': clientSeq,
      if (totalRefundAmount != null) 'total_refund_amount': totalRefundAmount,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (reason != null) 'reason': reason,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RefundsCompanion copyWith(
      {Value<String>? id,
      Value<String>? saleId,
      Value<String>? deviceId,
      Value<int>? clientSeq,
      Value<int>? totalRefundAmount,
      Value<String>? paymentMethod,
      Value<String>? reason,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return RefundsCompanion(
      id: id ?? this.id,
      saleId: saleId ?? this.saleId,
      deviceId: deviceId ?? this.deviceId,
      clientSeq: clientSeq ?? this.clientSeq,
      totalRefundAmount: totalRefundAmount ?? this.totalRefundAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      reason: reason ?? this.reason,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (saleId.present) {
      map['sale_id'] = Variable<String>(saleId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (clientSeq.present) {
      map['client_seq'] = Variable<int>(clientSeq.value);
    }
    if (totalRefundAmount.present) {
      map['total_refund_amount'] = Variable<int>(totalRefundAmount.value);
    }
    if (paymentMethod.present) {
      map['payment_method'] = Variable<String>(paymentMethod.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RefundsCompanion(')
          ..write('id: $id, ')
          ..write('saleId: $saleId, ')
          ..write('deviceId: $deviceId, ')
          ..write('clientSeq: $clientSeq, ')
          ..write('totalRefundAmount: $totalRefundAmount, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('reason: $reason, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RefundItemsTable extends RefundItems
    with TableInfo<$RefundItemsTable, RefundItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RefundItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _refundIdMeta =
      const VerificationMeta('refundId');
  @override
  late final GeneratedColumn<String> refundId = GeneratedColumn<String>(
      'refund_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES refunds (id)'));
  static const VerificationMeta _saleItemIdMeta =
      const VerificationMeta('saleItemId');
  @override
  late final GeneratedColumn<String> saleItemId = GeneratedColumn<String>(
      'sale_item_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES products (id)'));
  static const VerificationMeta _quantityMeta =
      const VerificationMeta('quantity');
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
      'quantity', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _unitPriceMeta =
      const VerificationMeta('unitPrice');
  @override
  late final GeneratedColumn<int> unitPrice = GeneratedColumn<int>(
      'unit_price', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _refundAmountMeta =
      const VerificationMeta('refundAmount');
  @override
  late final GeneratedColumn<int> refundAmount = GeneratedColumn<int>(
      'refund_amount', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _productConditionMeta =
      const VerificationMeta('productCondition');
  @override
  late final GeneratedColumn<String> productCondition = GeneratedColumn<String>(
      'product_condition', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('SELLABLE'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        refundId,
        saleItemId,
        productId,
        quantity,
        unitPrice,
        refundAmount,
        productCondition,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'refund_items';
  @override
  VerificationContext validateIntegrity(Insertable<RefundItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('refund_id')) {
      context.handle(_refundIdMeta,
          refundId.isAcceptableOrUnknown(data['refund_id']!, _refundIdMeta));
    } else if (isInserting) {
      context.missing(_refundIdMeta);
    }
    if (data.containsKey('sale_item_id')) {
      context.handle(
          _saleItemIdMeta,
          saleItemId.isAcceptableOrUnknown(
              data['sale_item_id']!, _saleItemIdMeta));
    }
    if (data.containsKey('product_id')) {
      context.handle(_productIdMeta,
          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
    } else if (isInserting) {
      context.missing(_productIdMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(_quantityMeta,
          quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta));
    } else if (isInserting) {
      context.missing(_quantityMeta);
    }
    if (data.containsKey('unit_price')) {
      context.handle(_unitPriceMeta,
          unitPrice.isAcceptableOrUnknown(data['unit_price']!, _unitPriceMeta));
    } else if (isInserting) {
      context.missing(_unitPriceMeta);
    }
    if (data.containsKey('refund_amount')) {
      context.handle(
          _refundAmountMeta,
          refundAmount.isAcceptableOrUnknown(
              data['refund_amount']!, _refundAmountMeta));
    } else if (isInserting) {
      context.missing(_refundAmountMeta);
    }
    if (data.containsKey('product_condition')) {
      context.handle(
          _productConditionMeta,
          productCondition.isAcceptableOrUnknown(
              data['product_condition']!, _productConditionMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RefundItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RefundItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      refundId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}refund_id'])!,
      saleItemId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sale_item_id']),
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      quantity: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}quantity'])!,
      unitPrice: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}unit_price'])!,
      refundAmount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}refund_amount'])!,
      productCondition: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}product_condition'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $RefundItemsTable createAlias(String alias) {
    return $RefundItemsTable(attachedDatabase, alias);
  }
}

class RefundItem extends DataClass implements Insertable<RefundItem> {
  final String id;
  final String refundId;
  final String? saleItemId;
  final String productId;
  final int quantity;
  final int unitPrice;
  final int refundAmount;
  final String productCondition;
  final DateTime createdAt;
  const RefundItem(
      {required this.id,
      required this.refundId,
      this.saleItemId,
      required this.productId,
      required this.quantity,
      required this.unitPrice,
      required this.refundAmount,
      required this.productCondition,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['refund_id'] = Variable<String>(refundId);
    if (!nullToAbsent || saleItemId != null) {
      map['sale_item_id'] = Variable<String>(saleItemId);
    }
    map['product_id'] = Variable<String>(productId);
    map['quantity'] = Variable<int>(quantity);
    map['unit_price'] = Variable<int>(unitPrice);
    map['refund_amount'] = Variable<int>(refundAmount);
    map['product_condition'] = Variable<String>(productCondition);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  RefundItemsCompanion toCompanion(bool nullToAbsent) {
    return RefundItemsCompanion(
      id: Value(id),
      refundId: Value(refundId),
      saleItemId: saleItemId == null && nullToAbsent
          ? const Value.absent()
          : Value(saleItemId),
      productId: Value(productId),
      quantity: Value(quantity),
      unitPrice: Value(unitPrice),
      refundAmount: Value(refundAmount),
      productCondition: Value(productCondition),
      createdAt: Value(createdAt),
    );
  }

  factory RefundItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RefundItem(
      id: serializer.fromJson<String>(json['id']),
      refundId: serializer.fromJson<String>(json['refundId']),
      saleItemId: serializer.fromJson<String?>(json['saleItemId']),
      productId: serializer.fromJson<String>(json['productId']),
      quantity: serializer.fromJson<int>(json['quantity']),
      unitPrice: serializer.fromJson<int>(json['unitPrice']),
      refundAmount: serializer.fromJson<int>(json['refundAmount']),
      productCondition: serializer.fromJson<String>(json['productCondition']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'refundId': serializer.toJson<String>(refundId),
      'saleItemId': serializer.toJson<String?>(saleItemId),
      'productId': serializer.toJson<String>(productId),
      'quantity': serializer.toJson<int>(quantity),
      'unitPrice': serializer.toJson<int>(unitPrice),
      'refundAmount': serializer.toJson<int>(refundAmount),
      'productCondition': serializer.toJson<String>(productCondition),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  RefundItem copyWith(
          {String? id,
          String? refundId,
          Value<String?> saleItemId = const Value.absent(),
          String? productId,
          int? quantity,
          int? unitPrice,
          int? refundAmount,
          String? productCondition,
          DateTime? createdAt}) =>
      RefundItem(
        id: id ?? this.id,
        refundId: refundId ?? this.refundId,
        saleItemId: saleItemId.present ? saleItemId.value : this.saleItemId,
        productId: productId ?? this.productId,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        refundAmount: refundAmount ?? this.refundAmount,
        productCondition: productCondition ?? this.productCondition,
        createdAt: createdAt ?? this.createdAt,
      );
  RefundItem copyWithCompanion(RefundItemsCompanion data) {
    return RefundItem(
      id: data.id.present ? data.id.value : this.id,
      refundId: data.refundId.present ? data.refundId.value : this.refundId,
      saleItemId:
          data.saleItemId.present ? data.saleItemId.value : this.saleItemId,
      productId: data.productId.present ? data.productId.value : this.productId,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      unitPrice: data.unitPrice.present ? data.unitPrice.value : this.unitPrice,
      refundAmount: data.refundAmount.present
          ? data.refundAmount.value
          : this.refundAmount,
      productCondition: data.productCondition.present
          ? data.productCondition.value
          : this.productCondition,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RefundItem(')
          ..write('id: $id, ')
          ..write('refundId: $refundId, ')
          ..write('saleItemId: $saleItemId, ')
          ..write('productId: $productId, ')
          ..write('quantity: $quantity, ')
          ..write('unitPrice: $unitPrice, ')
          ..write('refundAmount: $refundAmount, ')
          ..write('productCondition: $productCondition, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, refundId, saleItemId, productId, quantity,
      unitPrice, refundAmount, productCondition, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RefundItem &&
          other.id == this.id &&
          other.refundId == this.refundId &&
          other.saleItemId == this.saleItemId &&
          other.productId == this.productId &&
          other.quantity == this.quantity &&
          other.unitPrice == this.unitPrice &&
          other.refundAmount == this.refundAmount &&
          other.productCondition == this.productCondition &&
          other.createdAt == this.createdAt);
}

class RefundItemsCompanion extends UpdateCompanion<RefundItem> {
  final Value<String> id;
  final Value<String> refundId;
  final Value<String?> saleItemId;
  final Value<String> productId;
  final Value<int> quantity;
  final Value<int> unitPrice;
  final Value<int> refundAmount;
  final Value<String> productCondition;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const RefundItemsCompanion({
    this.id = const Value.absent(),
    this.refundId = const Value.absent(),
    this.saleItemId = const Value.absent(),
    this.productId = const Value.absent(),
    this.quantity = const Value.absent(),
    this.unitPrice = const Value.absent(),
    this.refundAmount = const Value.absent(),
    this.productCondition = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RefundItemsCompanion.insert({
    required String id,
    required String refundId,
    this.saleItemId = const Value.absent(),
    required String productId,
    required int quantity,
    required int unitPrice,
    required int refundAmount,
    this.productCondition = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        refundId = Value(refundId),
        productId = Value(productId),
        quantity = Value(quantity),
        unitPrice = Value(unitPrice),
        refundAmount = Value(refundAmount);
  static Insertable<RefundItem> custom({
    Expression<String>? id,
    Expression<String>? refundId,
    Expression<String>? saleItemId,
    Expression<String>? productId,
    Expression<int>? quantity,
    Expression<int>? unitPrice,
    Expression<int>? refundAmount,
    Expression<String>? productCondition,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (refundId != null) 'refund_id': refundId,
      if (saleItemId != null) 'sale_item_id': saleItemId,
      if (productId != null) 'product_id': productId,
      if (quantity != null) 'quantity': quantity,
      if (unitPrice != null) 'unit_price': unitPrice,
      if (refundAmount != null) 'refund_amount': refundAmount,
      if (productCondition != null) 'product_condition': productCondition,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RefundItemsCompanion copyWith(
      {Value<String>? id,
      Value<String>? refundId,
      Value<String?>? saleItemId,
      Value<String>? productId,
      Value<int>? quantity,
      Value<int>? unitPrice,
      Value<int>? refundAmount,
      Value<String>? productCondition,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return RefundItemsCompanion(
      id: id ?? this.id,
      refundId: refundId ?? this.refundId,
      saleItemId: saleItemId ?? this.saleItemId,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      refundAmount: refundAmount ?? this.refundAmount,
      productCondition: productCondition ?? this.productCondition,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (refundId.present) {
      map['refund_id'] = Variable<String>(refundId.value);
    }
    if (saleItemId.present) {
      map['sale_item_id'] = Variable<String>(saleItemId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
    }
    if (unitPrice.present) {
      map['unit_price'] = Variable<int>(unitPrice.value);
    }
    if (refundAmount.present) {
      map['refund_amount'] = Variable<int>(refundAmount.value);
    }
    if (productCondition.present) {
      map['product_condition'] = Variable<String>(productCondition.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RefundItemsCompanion(')
          ..write('id: $id, ')
          ..write('refundId: $refundId, ')
          ..write('saleItemId: $saleItemId, ')
          ..write('productId: $productId, ')
          ..write('quantity: $quantity, ')
          ..write('unitPrice: $unitPrice, ')
          ..write('refundAmount: $refundAmount, ')
          ..write('productCondition: $productCondition, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HubMetadataTable extends HubMetadata
    with TableInfo<$HubMetadataTable, HubMetadataData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HubMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'hub_metadata';
  @override
  VerificationContext validateIntegrity(Insertable<HubMetadataData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  HubMetadataData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HubMetadataData(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $HubMetadataTable createAlias(String alias) {
    return $HubMetadataTable(attachedDatabase, alias);
  }
}

class HubMetadataData extends DataClass implements Insertable<HubMetadataData> {
  final String key;
  final String value;
  final DateTime updatedAt;
  const HubMetadataData(
      {required this.key, required this.value, required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  HubMetadataCompanion toCompanion(bool nullToAbsent) {
    return HubMetadataCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory HubMetadataData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HubMetadataData(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  HubMetadataData copyWith({String? key, String? value, DateTime? updatedAt}) =>
      HubMetadataData(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  HubMetadataData copyWithCompanion(HubMetadataCompanion data) {
    return HubMetadataData(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HubMetadataData(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HubMetadataData &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class HubMetadataCompanion extends UpdateCompanion<HubMetadataData> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const HubMetadataCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HubMetadataCompanion.insert({
    required String key,
    required String value,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<HubMetadataData> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HubMetadataCompanion copyWith(
      {Value<String>? key,
      Value<String>? value,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return HubMetadataCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HubMetadataCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$SpikeDatabase extends GeneratedDatabase {
  _$SpikeDatabase(QueryExecutor e) : super(e);
  $SpikeDatabaseManager get managers => $SpikeDatabaseManager(this);
  late final $ProductsTable products = $ProductsTable(this);
  late final $SalesTable sales = $SalesTable(this);
  late final $SaleItemsTable saleItems = $SaleItemsTable(this);
  late final $StockMovementsTable stockMovements = $StockMovementsTable(this);
  late final $ProcessedOperationsTable processedOperations =
      $ProcessedOperationsTable(this);
  late final $DevicesTable devices = $DevicesTable(this);
  late final $DeviceAuditLogsTable deviceAuditLogs =
      $DeviceAuditLogsTable(this);
  late final $ProductPriceHistoriesTable productPriceHistories =
      $ProductPriceHistoriesTable(this);
  late final $ProductSyncSessionsTable productSyncSessions =
      $ProductSyncSessionsTable(this);
  late final $RefundsTable refunds = $RefundsTable(this);
  late final $RefundItemsTable refundItems = $RefundItemsTable(this);
  late final $HubMetadataTable hubMetadata = $HubMetadataTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        products,
        sales,
        saleItems,
        stockMovements,
        processedOperations,
        devices,
        deviceAuditLogs,
        productPriceHistories,
        productSyncSessions,
        refunds,
        refundItems,
        hubMetadata
      ];
}

typedef $$ProductsTableCreateCompanionBuilder = ProductsCompanion Function({
  required String id,
  required String barcode,
  required String name,
  required int price,
  Value<String> priceVersionId,
  required int stock,
  Value<String> stockUnit,
  Value<String> pricingUnit,
  Value<int> conversionFactorNumerator,
  Value<int> conversionFactorDenominator,
  Value<bool> isActive,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$ProductsTableUpdateCompanionBuilder = ProductsCompanion Function({
  Value<String> id,
  Value<String> barcode,
  Value<String> name,
  Value<int> price,
  Value<String> priceVersionId,
  Value<int> stock,
  Value<String> stockUnit,
  Value<String> pricingUnit,
  Value<int> conversionFactorNumerator,
  Value<int> conversionFactorDenominator,
  Value<bool> isActive,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

final class $$ProductsTableReferences
    extends BaseReferences<_$SpikeDatabase, $ProductsTable, Product> {
  $$ProductsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SaleItemsTable, List<SaleItem>>
      _saleItemsRefsTable(_$SpikeDatabase db) =>
          MultiTypedResultKey.fromTable(db.saleItems,
              aliasName: 'products__id__sale_items__product_id');

  $$SaleItemsTableProcessedTableManager get saleItemsRefs {
    final manager = $$SaleItemsTableTableManager($_db, $_db.saleItems)
        .filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_saleItemsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$StockMovementsTable, List<StockMovement>>
      _stockMovementsRefsTable(_$SpikeDatabase db) =>
          MultiTypedResultKey.fromTable(db.stockMovements,
              aliasName: 'products__id__stock_movements__product_id');

  $$StockMovementsTableProcessedTableManager get stockMovementsRefs {
    final manager = $$StockMovementsTableTableManager($_db, $_db.stockMovements)
        .filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_stockMovementsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$ProductPriceHistoriesTable,
      List<ProductPriceHistory>> _productPriceHistoriesRefsTable(
          _$SpikeDatabase db) =>
      MultiTypedResultKey.fromTable(db.productPriceHistories,
          aliasName: 'products__id__product_price_histories__product_id');

  $$ProductPriceHistoriesTableProcessedTableManager
      get productPriceHistoriesRefs {
    final manager = $$ProductPriceHistoriesTableTableManager(
            $_db, $_db.productPriceHistories)
        .filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_productPriceHistoriesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$RefundItemsTable, List<RefundItem>>
      _refundItemsRefsTable(_$SpikeDatabase db) =>
          MultiTypedResultKey.fromTable(db.refundItems,
              aliasName: 'products__id__refund_items__product_id');

  $$RefundItemsTableProcessedTableManager get refundItemsRefs {
    final manager = $$RefundItemsTableTableManager($_db, $_db.refundItems)
        .filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_refundItemsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$ProductsTableFilterComposer
    extends Composer<_$SpikeDatabase, $ProductsTable> {
  $$ProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get barcode => $composableBuilder(
      column: $table.barcode, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get priceVersionId => $composableBuilder(
      column: $table.priceVersionId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get stock => $composableBuilder(
      column: $table.stock, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get stockUnit => $composableBuilder(
      column: $table.stockUnit, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pricingUnit => $composableBuilder(
      column: $table.pricingUnit, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get conversionFactorNumerator => $composableBuilder(
      column: $table.conversionFactorNumerator,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get conversionFactorDenominator => $composableBuilder(
      column: $table.conversionFactorDenominator,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  Expression<bool> saleItemsRefs(
      Expression<bool> Function($$SaleItemsTableFilterComposer f) f) {
    final $$SaleItemsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.saleItems,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SaleItemsTableFilterComposer(
              $db: $db,
              $table: $db.saleItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> stockMovementsRefs(
      Expression<bool> Function($$StockMovementsTableFilterComposer f) f) {
    final $$StockMovementsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.stockMovements,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$StockMovementsTableFilterComposer(
              $db: $db,
              $table: $db.stockMovements,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> productPriceHistoriesRefs(
      Expression<bool> Function($$ProductPriceHistoriesTableFilterComposer f)
          f) {
    final $$ProductPriceHistoriesTableFilterComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.productPriceHistories,
            getReferencedColumn: (t) => t.productId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$ProductPriceHistoriesTableFilterComposer(
                  $db: $db,
                  $table: $db.productPriceHistories,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }

  Expression<bool> refundItemsRefs(
      Expression<bool> Function($$RefundItemsTableFilterComposer f) f) {
    final $$RefundItemsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.refundItems,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RefundItemsTableFilterComposer(
              $db: $db,
              $table: $db.refundItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ProductsTableOrderingComposer
    extends Composer<_$SpikeDatabase, $ProductsTable> {
  $$ProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get barcode => $composableBuilder(
      column: $table.barcode, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get priceVersionId => $composableBuilder(
      column: $table.priceVersionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get stock => $composableBuilder(
      column: $table.stock, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get stockUnit => $composableBuilder(
      column: $table.stockUnit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pricingUnit => $composableBuilder(
      column: $table.pricingUnit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get conversionFactorNumerator => $composableBuilder(
      column: $table.conversionFactorNumerator,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get conversionFactorDenominator => $composableBuilder(
      column: $table.conversionFactorDenominator,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$ProductsTableAnnotationComposer
    extends Composer<_$SpikeDatabase, $ProductsTable> {
  $$ProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get barcode =>
      $composableBuilder(column: $table.barcode, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<String> get priceVersionId => $composableBuilder(
      column: $table.priceVersionId, builder: (column) => column);

  GeneratedColumn<int> get stock =>
      $composableBuilder(column: $table.stock, builder: (column) => column);

  GeneratedColumn<String> get stockUnit =>
      $composableBuilder(column: $table.stockUnit, builder: (column) => column);

  GeneratedColumn<String> get pricingUnit => $composableBuilder(
      column: $table.pricingUnit, builder: (column) => column);

  GeneratedColumn<int> get conversionFactorNumerator => $composableBuilder(
      column: $table.conversionFactorNumerator, builder: (column) => column);

  GeneratedColumn<int> get conversionFactorDenominator => $composableBuilder(
      column: $table.conversionFactorDenominator, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> saleItemsRefs<T extends Object>(
      Expression<T> Function($$SaleItemsTableAnnotationComposer a) f) {
    final $$SaleItemsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.saleItems,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SaleItemsTableAnnotationComposer(
              $db: $db,
              $table: $db.saleItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> stockMovementsRefs<T extends Object>(
      Expression<T> Function($$StockMovementsTableAnnotationComposer a) f) {
    final $$StockMovementsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.stockMovements,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$StockMovementsTableAnnotationComposer(
              $db: $db,
              $table: $db.stockMovements,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> productPriceHistoriesRefs<T extends Object>(
      Expression<T> Function($$ProductPriceHistoriesTableAnnotationComposer a)
          f) {
    final $$ProductPriceHistoriesTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.productPriceHistories,
            getReferencedColumn: (t) => t.productId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$ProductPriceHistoriesTableAnnotationComposer(
                  $db: $db,
                  $table: $db.productPriceHistories,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }

  Expression<T> refundItemsRefs<T extends Object>(
      Expression<T> Function($$RefundItemsTableAnnotationComposer a) f) {
    final $$RefundItemsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.refundItems,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RefundItemsTableAnnotationComposer(
              $db: $db,
              $table: $db.refundItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ProductsTableTableManager extends RootTableManager<
    _$SpikeDatabase,
    $ProductsTable,
    Product,
    $$ProductsTableFilterComposer,
    $$ProductsTableOrderingComposer,
    $$ProductsTableAnnotationComposer,
    $$ProductsTableCreateCompanionBuilder,
    $$ProductsTableUpdateCompanionBuilder,
    (Product, $$ProductsTableReferences),
    Product,
    PrefetchHooks Function(
        {bool saleItemsRefs,
        bool stockMovementsRefs,
        bool productPriceHistoriesRefs,
        bool refundItemsRefs})> {
  $$ProductsTableTableManager(_$SpikeDatabase db, $ProductsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> barcode = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> price = const Value.absent(),
            Value<String> priceVersionId = const Value.absent(),
            Value<int> stock = const Value.absent(),
            Value<String> stockUnit = const Value.absent(),
            Value<String> pricingUnit = const Value.absent(),
            Value<int> conversionFactorNumerator = const Value.absent(),
            Value<int> conversionFactorDenominator = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductsCompanion(
            id: id,
            barcode: barcode,
            name: name,
            price: price,
            priceVersionId: priceVersionId,
            stock: stock,
            stockUnit: stockUnit,
            pricingUnit: pricingUnit,
            conversionFactorNumerator: conversionFactorNumerator,
            conversionFactorDenominator: conversionFactorDenominator,
            isActive: isActive,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String barcode,
            required String name,
            required int price,
            Value<String> priceVersionId = const Value.absent(),
            required int stock,
            Value<String> stockUnit = const Value.absent(),
            Value<String> pricingUnit = const Value.absent(),
            Value<int> conversionFactorNumerator = const Value.absent(),
            Value<int> conversionFactorDenominator = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductsCompanion.insert(
            id: id,
            barcode: barcode,
            name: name,
            price: price,
            priceVersionId: priceVersionId,
            stock: stock,
            stockUnit: stockUnit,
            pricingUnit: pricingUnit,
            conversionFactorNumerator: conversionFactorNumerator,
            conversionFactorDenominator: conversionFactorDenominator,
            isActive: isActive,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$ProductsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: (
              {saleItemsRefs = false,
              stockMovementsRefs = false,
              productPriceHistoriesRefs = false,
              refundItemsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (saleItemsRefs) db.saleItems,
                if (stockMovementsRefs) db.stockMovements,
                if (productPriceHistoriesRefs) db.productPriceHistories,
                if (refundItemsRefs) db.refundItems
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (saleItemsRefs)
                    await $_getPrefetchedData<Product, $ProductsTable,
                            SaleItem>(
                        currentTable: table,
                        referencedTable:
                            $$ProductsTableReferences._saleItemsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProductsTableReferences(db, table, p0)
                                .saleItemsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.productId == item.id),
                        typedResults: items),
                  if (stockMovementsRefs)
                    await $_getPrefetchedData<Product, $ProductsTable,
                            StockMovement>(
                        currentTable: table,
                        referencedTable: $$ProductsTableReferences
                            ._stockMovementsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProductsTableReferences(db, table, p0)
                                .stockMovementsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.productId == item.id),
                        typedResults: items),
                  if (productPriceHistoriesRefs)
                    await $_getPrefetchedData<Product, $ProductsTable,
                            ProductPriceHistory>(
                        currentTable: table,
                        referencedTable: $$ProductsTableReferences
                            ._productPriceHistoriesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProductsTableReferences(db, table, p0)
                                .productPriceHistoriesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.productId == item.id),
                        typedResults: items),
                  if (refundItemsRefs)
                    await $_getPrefetchedData<Product, $ProductsTable,
                            RefundItem>(
                        currentTable: table,
                        referencedTable:
                            $$ProductsTableReferences._refundItemsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ProductsTableReferences(db, table, p0)
                                .refundItemsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.productId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$ProductsTableProcessedTableManager = ProcessedTableManager<
    _$SpikeDatabase,
    $ProductsTable,
    Product,
    $$ProductsTableFilterComposer,
    $$ProductsTableOrderingComposer,
    $$ProductsTableAnnotationComposer,
    $$ProductsTableCreateCompanionBuilder,
    $$ProductsTableUpdateCompanionBuilder,
    (Product, $$ProductsTableReferences),
    Product,
    PrefetchHooks Function(
        {bool saleItemsRefs,
        bool stockMovementsRefs,
        bool productPriceHistoriesRefs,
        bool refundItemsRefs})>;
typedef $$SalesTableCreateCompanionBuilder = SalesCompanion Function({
  required String id,
  required String deviceId,
  required int clientSeq,
  required int totalAmount,
  required String paymentMethod,
  Value<int?> serverSeq,
  Value<String> status,
  Value<String?> cancelReason,
  Value<DateTime?> cancelledAt,
  Value<DateTime> createdAt,
  Value<int> rowid,
});
typedef $$SalesTableUpdateCompanionBuilder = SalesCompanion Function({
  Value<String> id,
  Value<String> deviceId,
  Value<int> clientSeq,
  Value<int> totalAmount,
  Value<String> paymentMethod,
  Value<int?> serverSeq,
  Value<String> status,
  Value<String?> cancelReason,
  Value<DateTime?> cancelledAt,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

final class $$SalesTableReferences
    extends BaseReferences<_$SpikeDatabase, $SalesTable, Sale> {
  $$SalesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SaleItemsTable, List<SaleItem>>
      _saleItemsRefsTable(_$SpikeDatabase db) =>
          MultiTypedResultKey.fromTable(db.saleItems,
              aliasName: 'sales__id__sale_items__sale_id');

  $$SaleItemsTableProcessedTableManager get saleItemsRefs {
    final manager = $$SaleItemsTableTableManager($_db, $_db.saleItems)
        .filter((f) => f.saleId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_saleItemsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$RefundsTable, List<Refund>> _refundsRefsTable(
          _$SpikeDatabase db) =>
      MultiTypedResultKey.fromTable(db.refunds,
          aliasName: 'sales__id__refunds__sale_id');

  $$RefundsTableProcessedTableManager get refundsRefs {
    final manager = $$RefundsTableTableManager($_db, $_db.refunds)
        .filter((f) => f.saleId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_refundsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$SalesTableFilterComposer
    extends Composer<_$SpikeDatabase, $SalesTable> {
  $$SalesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get clientSeq => $composableBuilder(
      column: $table.clientSeq, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get totalAmount => $composableBuilder(
      column: $table.totalAmount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get paymentMethod => $composableBuilder(
      column: $table.paymentMethod, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serverSeq => $composableBuilder(
      column: $table.serverSeq, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cancelReason => $composableBuilder(
      column: $table.cancelReason, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get cancelledAt => $composableBuilder(
      column: $table.cancelledAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  Expression<bool> saleItemsRefs(
      Expression<bool> Function($$SaleItemsTableFilterComposer f) f) {
    final $$SaleItemsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.saleItems,
        getReferencedColumn: (t) => t.saleId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SaleItemsTableFilterComposer(
              $db: $db,
              $table: $db.saleItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> refundsRefs(
      Expression<bool> Function($$RefundsTableFilterComposer f) f) {
    final $$RefundsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.refunds,
        getReferencedColumn: (t) => t.saleId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RefundsTableFilterComposer(
              $db: $db,
              $table: $db.refunds,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SalesTableOrderingComposer
    extends Composer<_$SpikeDatabase, $SalesTable> {
  $$SalesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get clientSeq => $composableBuilder(
      column: $table.clientSeq, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get totalAmount => $composableBuilder(
      column: $table.totalAmount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get paymentMethod => $composableBuilder(
      column: $table.paymentMethod,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serverSeq => $composableBuilder(
      column: $table.serverSeq, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cancelReason => $composableBuilder(
      column: $table.cancelReason,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get cancelledAt => $composableBuilder(
      column: $table.cancelledAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$SalesTableAnnotationComposer
    extends Composer<_$SpikeDatabase, $SalesTable> {
  $$SalesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get clientSeq =>
      $composableBuilder(column: $table.clientSeq, builder: (column) => column);

  GeneratedColumn<int> get totalAmount => $composableBuilder(
      column: $table.totalAmount, builder: (column) => column);

  GeneratedColumn<String> get paymentMethod => $composableBuilder(
      column: $table.paymentMethod, builder: (column) => column);

  GeneratedColumn<int> get serverSeq =>
      $composableBuilder(column: $table.serverSeq, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get cancelReason => $composableBuilder(
      column: $table.cancelReason, builder: (column) => column);

  GeneratedColumn<DateTime> get cancelledAt => $composableBuilder(
      column: $table.cancelledAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> saleItemsRefs<T extends Object>(
      Expression<T> Function($$SaleItemsTableAnnotationComposer a) f) {
    final $$SaleItemsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.saleItems,
        getReferencedColumn: (t) => t.saleId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SaleItemsTableAnnotationComposer(
              $db: $db,
              $table: $db.saleItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> refundsRefs<T extends Object>(
      Expression<T> Function($$RefundsTableAnnotationComposer a) f) {
    final $$RefundsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.refunds,
        getReferencedColumn: (t) => t.saleId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RefundsTableAnnotationComposer(
              $db: $db,
              $table: $db.refunds,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SalesTableTableManager extends RootTableManager<
    _$SpikeDatabase,
    $SalesTable,
    Sale,
    $$SalesTableFilterComposer,
    $$SalesTableOrderingComposer,
    $$SalesTableAnnotationComposer,
    $$SalesTableCreateCompanionBuilder,
    $$SalesTableUpdateCompanionBuilder,
    (Sale, $$SalesTableReferences),
    Sale,
    PrefetchHooks Function({bool saleItemsRefs, bool refundsRefs})> {
  $$SalesTableTableManager(_$SpikeDatabase db, $SalesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SalesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SalesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SalesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> deviceId = const Value.absent(),
            Value<int> clientSeq = const Value.absent(),
            Value<int> totalAmount = const Value.absent(),
            Value<String> paymentMethod = const Value.absent(),
            Value<int?> serverSeq = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> cancelReason = const Value.absent(),
            Value<DateTime?> cancelledAt = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SalesCompanion(
            id: id,
            deviceId: deviceId,
            clientSeq: clientSeq,
            totalAmount: totalAmount,
            paymentMethod: paymentMethod,
            serverSeq: serverSeq,
            status: status,
            cancelReason: cancelReason,
            cancelledAt: cancelledAt,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String deviceId,
            required int clientSeq,
            required int totalAmount,
            required String paymentMethod,
            Value<int?> serverSeq = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> cancelReason = const Value.absent(),
            Value<DateTime?> cancelledAt = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SalesCompanion.insert(
            id: id,
            deviceId: deviceId,
            clientSeq: clientSeq,
            totalAmount: totalAmount,
            paymentMethod: paymentMethod,
            serverSeq: serverSeq,
            status: status,
            cancelReason: cancelReason,
            cancelledAt: cancelledAt,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$SalesTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: (
              {saleItemsRefs = false, refundsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (saleItemsRefs) db.saleItems,
                if (refundsRefs) db.refunds
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (saleItemsRefs)
                    await $_getPrefetchedData<Sale, $SalesTable, SaleItem>(
                        currentTable: table,
                        referencedTable:
                            $$SalesTableReferences._saleItemsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SalesTableReferences(db, table, p0).saleItemsRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.saleId == item.id),
                        typedResults: items),
                  if (refundsRefs)
                    await $_getPrefetchedData<Sale, $SalesTable, Refund>(
                        currentTable: table,
                        referencedTable:
                            $$SalesTableReferences._refundsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SalesTableReferences(db, table, p0).refundsRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.saleId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$SalesTableProcessedTableManager = ProcessedTableManager<
    _$SpikeDatabase,
    $SalesTable,
    Sale,
    $$SalesTableFilterComposer,
    $$SalesTableOrderingComposer,
    $$SalesTableAnnotationComposer,
    $$SalesTableCreateCompanionBuilder,
    $$SalesTableUpdateCompanionBuilder,
    (Sale, $$SalesTableReferences),
    Sale,
    PrefetchHooks Function({bool saleItemsRefs, bool refundsRefs})>;
typedef $$SaleItemsTableCreateCompanionBuilder = SaleItemsCompanion Function({
  required String id,
  required String saleId,
  required String productId,
  required int quantity,
  required int unitPrice,
  required int totalPrice,
  Value<int> rowid,
});
typedef $$SaleItemsTableUpdateCompanionBuilder = SaleItemsCompanion Function({
  Value<String> id,
  Value<String> saleId,
  Value<String> productId,
  Value<int> quantity,
  Value<int> unitPrice,
  Value<int> totalPrice,
  Value<int> rowid,
});

final class $$SaleItemsTableReferences
    extends BaseReferences<_$SpikeDatabase, $SaleItemsTable, SaleItem> {
  $$SaleItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SalesTable _saleIdTable(_$SpikeDatabase db) =>
      db.sales.createAlias('sale_items__sale_id__sales__id');

  $$SalesTableProcessedTableManager get saleId {
    final $_column = $_itemColumn<String>('sale_id')!;

    final manager = $$SalesTableTableManager($_db, $_db.sales)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_saleIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $ProductsTable _productIdTable(_$SpikeDatabase db) =>
      db.products.createAlias('sale_items__product_id__products__id');

  $$ProductsTableProcessedTableManager get productId {
    final $_column = $_itemColumn<String>('product_id')!;

    final manager = $$ProductsTableTableManager($_db, $_db.products)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$SaleItemsTableFilterComposer
    extends Composer<_$SpikeDatabase, $SaleItemsTable> {
  $$SaleItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get quantity => $composableBuilder(
      column: $table.quantity, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get unitPrice => $composableBuilder(
      column: $table.unitPrice, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get totalPrice => $composableBuilder(
      column: $table.totalPrice, builder: (column) => ColumnFilters(column));

  $$SalesTableFilterComposer get saleId {
    final $$SalesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.saleId,
        referencedTable: $db.sales,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SalesTableFilterComposer(
              $db: $db,
              $table: $db.sales,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$ProductsTableFilterComposer get productId {
    final $$ProductsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableFilterComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SaleItemsTableOrderingComposer
    extends Composer<_$SpikeDatabase, $SaleItemsTable> {
  $$SaleItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get quantity => $composableBuilder(
      column: $table.quantity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get unitPrice => $composableBuilder(
      column: $table.unitPrice, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get totalPrice => $composableBuilder(
      column: $table.totalPrice, builder: (column) => ColumnOrderings(column));

  $$SalesTableOrderingComposer get saleId {
    final $$SalesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.saleId,
        referencedTable: $db.sales,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SalesTableOrderingComposer(
              $db: $db,
              $table: $db.sales,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$ProductsTableOrderingComposer get productId {
    final $$ProductsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableOrderingComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SaleItemsTableAnnotationComposer
    extends Composer<_$SpikeDatabase, $SaleItemsTable> {
  $$SaleItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<int> get unitPrice =>
      $composableBuilder(column: $table.unitPrice, builder: (column) => column);

  GeneratedColumn<int> get totalPrice => $composableBuilder(
      column: $table.totalPrice, builder: (column) => column);

  $$SalesTableAnnotationComposer get saleId {
    final $$SalesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.saleId,
        referencedTable: $db.sales,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SalesTableAnnotationComposer(
              $db: $db,
              $table: $db.sales,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$ProductsTableAnnotationComposer get productId {
    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableAnnotationComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SaleItemsTableTableManager extends RootTableManager<
    _$SpikeDatabase,
    $SaleItemsTable,
    SaleItem,
    $$SaleItemsTableFilterComposer,
    $$SaleItemsTableOrderingComposer,
    $$SaleItemsTableAnnotationComposer,
    $$SaleItemsTableCreateCompanionBuilder,
    $$SaleItemsTableUpdateCompanionBuilder,
    (SaleItem, $$SaleItemsTableReferences),
    SaleItem,
    PrefetchHooks Function({bool saleId, bool productId})> {
  $$SaleItemsTableTableManager(_$SpikeDatabase db, $SaleItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SaleItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SaleItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SaleItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> saleId = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<int> quantity = const Value.absent(),
            Value<int> unitPrice = const Value.absent(),
            Value<int> totalPrice = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SaleItemsCompanion(
            id: id,
            saleId: saleId,
            productId: productId,
            quantity: quantity,
            unitPrice: unitPrice,
            totalPrice: totalPrice,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String saleId,
            required String productId,
            required int quantity,
            required int unitPrice,
            required int totalPrice,
            Value<int> rowid = const Value.absent(),
          }) =>
              SaleItemsCompanion.insert(
            id: id,
            saleId: saleId,
            productId: productId,
            quantity: quantity,
            unitPrice: unitPrice,
            totalPrice: totalPrice,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$SaleItemsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({saleId = false, productId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (saleId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.saleId,
                    referencedTable:
                        $$SaleItemsTableReferences._saleIdTable(db),
                    referencedColumn:
                        $$SaleItemsTableReferences._saleIdTable(db).id,
                  ) as T;
                }
                if (productId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.productId,
                    referencedTable:
                        $$SaleItemsTableReferences._productIdTable(db),
                    referencedColumn:
                        $$SaleItemsTableReferences._productIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$SaleItemsTableProcessedTableManager = ProcessedTableManager<
    _$SpikeDatabase,
    $SaleItemsTable,
    SaleItem,
    $$SaleItemsTableFilterComposer,
    $$SaleItemsTableOrderingComposer,
    $$SaleItemsTableAnnotationComposer,
    $$SaleItemsTableCreateCompanionBuilder,
    $$SaleItemsTableUpdateCompanionBuilder,
    (SaleItem, $$SaleItemsTableReferences),
    SaleItem,
    PrefetchHooks Function({bool saleId, bool productId})>;
typedef $$StockMovementsTableCreateCompanionBuilder = StockMovementsCompanion
    Function({
  required String id,
  required String productId,
  required int quantity,
  Value<String> unit,
  required String movementType,
  required String referenceId,
  Value<int?> purchasePrice,
  Value<String?> note,
  Value<DateTime> createdAt,
  Value<int> rowid,
});
typedef $$StockMovementsTableUpdateCompanionBuilder = StockMovementsCompanion
    Function({
  Value<String> id,
  Value<String> productId,
  Value<int> quantity,
  Value<String> unit,
  Value<String> movementType,
  Value<String> referenceId,
  Value<int?> purchasePrice,
  Value<String?> note,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

final class $$StockMovementsTableReferences extends BaseReferences<
    _$SpikeDatabase, $StockMovementsTable, StockMovement> {
  $$StockMovementsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $ProductsTable _productIdTable(_$SpikeDatabase db) =>
      db.products.createAlias('stock_movements__product_id__products__id');

  $$ProductsTableProcessedTableManager get productId {
    final $_column = $_itemColumn<String>('product_id')!;

    final manager = $$ProductsTableTableManager($_db, $_db.products)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$StockMovementsTableFilterComposer
    extends Composer<_$SpikeDatabase, $StockMovementsTable> {
  $$StockMovementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get quantity => $composableBuilder(
      column: $table.quantity, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get unit => $composableBuilder(
      column: $table.unit, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get movementType => $composableBuilder(
      column: $table.movementType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get purchasePrice => $composableBuilder(
      column: $table.purchasePrice, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  $$ProductsTableFilterComposer get productId {
    final $$ProductsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableFilterComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$StockMovementsTableOrderingComposer
    extends Composer<_$SpikeDatabase, $StockMovementsTable> {
  $$StockMovementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get quantity => $composableBuilder(
      column: $table.quantity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get unit => $composableBuilder(
      column: $table.unit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get movementType => $composableBuilder(
      column: $table.movementType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get purchasePrice => $composableBuilder(
      column: $table.purchasePrice,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get note => $composableBuilder(
      column: $table.note, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  $$ProductsTableOrderingComposer get productId {
    final $$ProductsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableOrderingComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$StockMovementsTableAnnotationComposer
    extends Composer<_$SpikeDatabase, $StockMovementsTable> {
  $$StockMovementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<String> get movementType => $composableBuilder(
      column: $table.movementType, builder: (column) => column);

  GeneratedColumn<String> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => column);

  GeneratedColumn<int> get purchasePrice => $composableBuilder(
      column: $table.purchasePrice, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ProductsTableAnnotationComposer get productId {
    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableAnnotationComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$StockMovementsTableTableManager extends RootTableManager<
    _$SpikeDatabase,
    $StockMovementsTable,
    StockMovement,
    $$StockMovementsTableFilterComposer,
    $$StockMovementsTableOrderingComposer,
    $$StockMovementsTableAnnotationComposer,
    $$StockMovementsTableCreateCompanionBuilder,
    $$StockMovementsTableUpdateCompanionBuilder,
    (StockMovement, $$StockMovementsTableReferences),
    StockMovement,
    PrefetchHooks Function({bool productId})> {
  $$StockMovementsTableTableManager(
      _$SpikeDatabase db, $StockMovementsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StockMovementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StockMovementsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StockMovementsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<int> quantity = const Value.absent(),
            Value<String> unit = const Value.absent(),
            Value<String> movementType = const Value.absent(),
            Value<String> referenceId = const Value.absent(),
            Value<int?> purchasePrice = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              StockMovementsCompanion(
            id: id,
            productId: productId,
            quantity: quantity,
            unit: unit,
            movementType: movementType,
            referenceId: referenceId,
            purchasePrice: purchasePrice,
            note: note,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String productId,
            required int quantity,
            Value<String> unit = const Value.absent(),
            required String movementType,
            required String referenceId,
            Value<int?> purchasePrice = const Value.absent(),
            Value<String?> note = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              StockMovementsCompanion.insert(
            id: id,
            productId: productId,
            quantity: quantity,
            unit: unit,
            movementType: movementType,
            referenceId: referenceId,
            purchasePrice: purchasePrice,
            note: note,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$StockMovementsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({productId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (productId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.productId,
                    referencedTable:
                        $$StockMovementsTableReferences._productIdTable(db),
                    referencedColumn:
                        $$StockMovementsTableReferences._productIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$StockMovementsTableProcessedTableManager = ProcessedTableManager<
    _$SpikeDatabase,
    $StockMovementsTable,
    StockMovement,
    $$StockMovementsTableFilterComposer,
    $$StockMovementsTableOrderingComposer,
    $$StockMovementsTableAnnotationComposer,
    $$StockMovementsTableCreateCompanionBuilder,
    $$StockMovementsTableUpdateCompanionBuilder,
    (StockMovement, $$StockMovementsTableReferences),
    StockMovement,
    PrefetchHooks Function({bool productId})>;
typedef $$ProcessedOperationsTableCreateCompanionBuilder
    = ProcessedOperationsCompanion Function({
  required String operationId,
  required String deviceId,
  required String idempotencyKey,
  Value<int?> clientSeq,
  Value<String?> operationType,
  Value<String?> requestHash,
  Value<String?> hashVersion,
  required String resultPayload,
  Value<DateTime> processedAt,
  Value<int> rowid,
});
typedef $$ProcessedOperationsTableUpdateCompanionBuilder
    = ProcessedOperationsCompanion Function({
  Value<String> operationId,
  Value<String> deviceId,
  Value<String> idempotencyKey,
  Value<int?> clientSeq,
  Value<String?> operationType,
  Value<String?> requestHash,
  Value<String?> hashVersion,
  Value<String> resultPayload,
  Value<DateTime> processedAt,
  Value<int> rowid,
});

class $$ProcessedOperationsTableFilterComposer
    extends Composer<_$SpikeDatabase, $ProcessedOperationsTable> {
  $$ProcessedOperationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get operationId => $composableBuilder(
      column: $table.operationId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get idempotencyKey => $composableBuilder(
      column: $table.idempotencyKey,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get clientSeq => $composableBuilder(
      column: $table.clientSeq, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get operationType => $composableBuilder(
      column: $table.operationType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get requestHash => $composableBuilder(
      column: $table.requestHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get hashVersion => $composableBuilder(
      column: $table.hashVersion, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get resultPayload => $composableBuilder(
      column: $table.resultPayload, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get processedAt => $composableBuilder(
      column: $table.processedAt, builder: (column) => ColumnFilters(column));
}

class $$ProcessedOperationsTableOrderingComposer
    extends Composer<_$SpikeDatabase, $ProcessedOperationsTable> {
  $$ProcessedOperationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get operationId => $composableBuilder(
      column: $table.operationId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get idempotencyKey => $composableBuilder(
      column: $table.idempotencyKey,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get clientSeq => $composableBuilder(
      column: $table.clientSeq, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get operationType => $composableBuilder(
      column: $table.operationType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get requestHash => $composableBuilder(
      column: $table.requestHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get hashVersion => $composableBuilder(
      column: $table.hashVersion, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get resultPayload => $composableBuilder(
      column: $table.resultPayload,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get processedAt => $composableBuilder(
      column: $table.processedAt, builder: (column) => ColumnOrderings(column));
}

class $$ProcessedOperationsTableAnnotationComposer
    extends Composer<_$SpikeDatabase, $ProcessedOperationsTable> {
  $$ProcessedOperationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get operationId => $composableBuilder(
      column: $table.operationId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get idempotencyKey => $composableBuilder(
      column: $table.idempotencyKey, builder: (column) => column);

  GeneratedColumn<int> get clientSeq =>
      $composableBuilder(column: $table.clientSeq, builder: (column) => column);

  GeneratedColumn<String> get operationType => $composableBuilder(
      column: $table.operationType, builder: (column) => column);

  GeneratedColumn<String> get requestHash => $composableBuilder(
      column: $table.requestHash, builder: (column) => column);

  GeneratedColumn<String> get hashVersion => $composableBuilder(
      column: $table.hashVersion, builder: (column) => column);

  GeneratedColumn<String> get resultPayload => $composableBuilder(
      column: $table.resultPayload, builder: (column) => column);

  GeneratedColumn<DateTime> get processedAt => $composableBuilder(
      column: $table.processedAt, builder: (column) => column);
}

class $$ProcessedOperationsTableTableManager extends RootTableManager<
    _$SpikeDatabase,
    $ProcessedOperationsTable,
    ProcessedOperation,
    $$ProcessedOperationsTableFilterComposer,
    $$ProcessedOperationsTableOrderingComposer,
    $$ProcessedOperationsTableAnnotationComposer,
    $$ProcessedOperationsTableCreateCompanionBuilder,
    $$ProcessedOperationsTableUpdateCompanionBuilder,
    (
      ProcessedOperation,
      BaseReferences<_$SpikeDatabase, $ProcessedOperationsTable,
          ProcessedOperation>
    ),
    ProcessedOperation,
    PrefetchHooks Function()> {
  $$ProcessedOperationsTableTableManager(
      _$SpikeDatabase db, $ProcessedOperationsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProcessedOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProcessedOperationsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProcessedOperationsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> operationId = const Value.absent(),
            Value<String> deviceId = const Value.absent(),
            Value<String> idempotencyKey = const Value.absent(),
            Value<int?> clientSeq = const Value.absent(),
            Value<String?> operationType = const Value.absent(),
            Value<String?> requestHash = const Value.absent(),
            Value<String?> hashVersion = const Value.absent(),
            Value<String> resultPayload = const Value.absent(),
            Value<DateTime> processedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProcessedOperationsCompanion(
            operationId: operationId,
            deviceId: deviceId,
            idempotencyKey: idempotencyKey,
            clientSeq: clientSeq,
            operationType: operationType,
            requestHash: requestHash,
            hashVersion: hashVersion,
            resultPayload: resultPayload,
            processedAt: processedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String operationId,
            required String deviceId,
            required String idempotencyKey,
            Value<int?> clientSeq = const Value.absent(),
            Value<String?> operationType = const Value.absent(),
            Value<String?> requestHash = const Value.absent(),
            Value<String?> hashVersion = const Value.absent(),
            required String resultPayload,
            Value<DateTime> processedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProcessedOperationsCompanion.insert(
            operationId: operationId,
            deviceId: deviceId,
            idempotencyKey: idempotencyKey,
            clientSeq: clientSeq,
            operationType: operationType,
            requestHash: requestHash,
            hashVersion: hashVersion,
            resultPayload: resultPayload,
            processedAt: processedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ProcessedOperationsTableProcessedTableManager = ProcessedTableManager<
    _$SpikeDatabase,
    $ProcessedOperationsTable,
    ProcessedOperation,
    $$ProcessedOperationsTableFilterComposer,
    $$ProcessedOperationsTableOrderingComposer,
    $$ProcessedOperationsTableAnnotationComposer,
    $$ProcessedOperationsTableCreateCompanionBuilder,
    $$ProcessedOperationsTableUpdateCompanionBuilder,
    (
      ProcessedOperation,
      BaseReferences<_$SpikeDatabase, $ProcessedOperationsTable,
          ProcessedOperation>
    ),
    ProcessedOperation,
    PrefetchHooks Function()>;
typedef $$DevicesTableCreateCompanionBuilder = DevicesCompanion Function({
  required String deviceId,
  required String name,
  required String tokenHash,
  required String salt,
  Value<bool> isActive,
  Value<bool> isConfirmed,
  Value<DateTime> createdAt,
  Value<DateTime?> lastUsedAt,
  Value<DateTime?> expiresAt,
  Value<DateTime?> lastProductSyncAt,
  Value<int> lastCommittedClientSeq,
  Value<int> maxSeenClientSeq,
  Value<DateTime?> lastCommittedAt,
  Value<String> role,
  Value<int> rowid,
});
typedef $$DevicesTableUpdateCompanionBuilder = DevicesCompanion Function({
  Value<String> deviceId,
  Value<String> name,
  Value<String> tokenHash,
  Value<String> salt,
  Value<bool> isActive,
  Value<bool> isConfirmed,
  Value<DateTime> createdAt,
  Value<DateTime?> lastUsedAt,
  Value<DateTime?> expiresAt,
  Value<DateTime?> lastProductSyncAt,
  Value<int> lastCommittedClientSeq,
  Value<int> maxSeenClientSeq,
  Value<DateTime?> lastCommittedAt,
  Value<String> role,
  Value<int> rowid,
});

class $$DevicesTableFilterComposer
    extends Composer<_$SpikeDatabase, $DevicesTable> {
  $$DevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tokenHash => $composableBuilder(
      column: $table.tokenHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get salt => $composableBuilder(
      column: $table.salt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isConfirmed => $composableBuilder(
      column: $table.isConfirmed, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastUsedAt => $composableBuilder(
      column: $table.lastUsedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
      column: $table.expiresAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastProductSyncAt => $composableBuilder(
      column: $table.lastProductSyncAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastCommittedClientSeq => $composableBuilder(
      column: $table.lastCommittedClientSeq,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get maxSeenClientSeq => $composableBuilder(
      column: $table.maxSeenClientSeq,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastCommittedAt => $composableBuilder(
      column: $table.lastCommittedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnFilters(column));
}

class $$DevicesTableOrderingComposer
    extends Composer<_$SpikeDatabase, $DevicesTable> {
  $$DevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tokenHash => $composableBuilder(
      column: $table.tokenHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get salt => $composableBuilder(
      column: $table.salt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isConfirmed => $composableBuilder(
      column: $table.isConfirmed, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastUsedAt => $composableBuilder(
      column: $table.lastUsedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
      column: $table.expiresAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastProductSyncAt => $composableBuilder(
      column: $table.lastProductSyncAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastCommittedClientSeq => $composableBuilder(
      column: $table.lastCommittedClientSeq,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get maxSeenClientSeq => $composableBuilder(
      column: $table.maxSeenClientSeq,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastCommittedAt => $composableBuilder(
      column: $table.lastCommittedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role => $composableBuilder(
      column: $table.role, builder: (column) => ColumnOrderings(column));
}

class $$DevicesTableAnnotationComposer
    extends Composer<_$SpikeDatabase, $DevicesTable> {
  $$DevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get tokenHash =>
      $composableBuilder(column: $table.tokenHash, builder: (column) => column);

  GeneratedColumn<String> get salt =>
      $composableBuilder(column: $table.salt, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<bool> get isConfirmed => $composableBuilder(
      column: $table.isConfirmed, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUsedAt => $composableBuilder(
      column: $table.lastUsedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastProductSyncAt => $composableBuilder(
      column: $table.lastProductSyncAt, builder: (column) => column);

  GeneratedColumn<int> get lastCommittedClientSeq => $composableBuilder(
      column: $table.lastCommittedClientSeq, builder: (column) => column);

  GeneratedColumn<int> get maxSeenClientSeq => $composableBuilder(
      column: $table.maxSeenClientSeq, builder: (column) => column);

  GeneratedColumn<DateTime> get lastCommittedAt => $composableBuilder(
      column: $table.lastCommittedAt, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);
}

class $$DevicesTableTableManager extends RootTableManager<
    _$SpikeDatabase,
    $DevicesTable,
    Device,
    $$DevicesTableFilterComposer,
    $$DevicesTableOrderingComposer,
    $$DevicesTableAnnotationComposer,
    $$DevicesTableCreateCompanionBuilder,
    $$DevicesTableUpdateCompanionBuilder,
    (Device, BaseReferences<_$SpikeDatabase, $DevicesTable, Device>),
    Device,
    PrefetchHooks Function()> {
  $$DevicesTableTableManager(_$SpikeDatabase db, $DevicesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> deviceId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> tokenHash = const Value.absent(),
            Value<String> salt = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<bool> isConfirmed = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> lastUsedAt = const Value.absent(),
            Value<DateTime?> expiresAt = const Value.absent(),
            Value<DateTime?> lastProductSyncAt = const Value.absent(),
            Value<int> lastCommittedClientSeq = const Value.absent(),
            Value<int> maxSeenClientSeq = const Value.absent(),
            Value<DateTime?> lastCommittedAt = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DevicesCompanion(
            deviceId: deviceId,
            name: name,
            tokenHash: tokenHash,
            salt: salt,
            isActive: isActive,
            isConfirmed: isConfirmed,
            createdAt: createdAt,
            lastUsedAt: lastUsedAt,
            expiresAt: expiresAt,
            lastProductSyncAt: lastProductSyncAt,
            lastCommittedClientSeq: lastCommittedClientSeq,
            maxSeenClientSeq: maxSeenClientSeq,
            lastCommittedAt: lastCommittedAt,
            role: role,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String deviceId,
            required String name,
            required String tokenHash,
            required String salt,
            Value<bool> isActive = const Value.absent(),
            Value<bool> isConfirmed = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime?> lastUsedAt = const Value.absent(),
            Value<DateTime?> expiresAt = const Value.absent(),
            Value<DateTime?> lastProductSyncAt = const Value.absent(),
            Value<int> lastCommittedClientSeq = const Value.absent(),
            Value<int> maxSeenClientSeq = const Value.absent(),
            Value<DateTime?> lastCommittedAt = const Value.absent(),
            Value<String> role = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DevicesCompanion.insert(
            deviceId: deviceId,
            name: name,
            tokenHash: tokenHash,
            salt: salt,
            isActive: isActive,
            isConfirmed: isConfirmed,
            createdAt: createdAt,
            lastUsedAt: lastUsedAt,
            expiresAt: expiresAt,
            lastProductSyncAt: lastProductSyncAt,
            lastCommittedClientSeq: lastCommittedClientSeq,
            maxSeenClientSeq: maxSeenClientSeq,
            lastCommittedAt: lastCommittedAt,
            role: role,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$DevicesTableProcessedTableManager = ProcessedTableManager<
    _$SpikeDatabase,
    $DevicesTable,
    Device,
    $$DevicesTableFilterComposer,
    $$DevicesTableOrderingComposer,
    $$DevicesTableAnnotationComposer,
    $$DevicesTableCreateCompanionBuilder,
    $$DevicesTableUpdateCompanionBuilder,
    (Device, BaseReferences<_$SpikeDatabase, $DevicesTable, Device>),
    Device,
    PrefetchHooks Function()>;
typedef $$DeviceAuditLogsTableCreateCompanionBuilder = DeviceAuditLogsCompanion
    Function({
  Value<int> id,
  required String deviceId,
  required String action,
  Value<String?> details,
  Value<DateTime> createdAt,
});
typedef $$DeviceAuditLogsTableUpdateCompanionBuilder = DeviceAuditLogsCompanion
    Function({
  Value<int> id,
  Value<String> deviceId,
  Value<String> action,
  Value<String?> details,
  Value<DateTime> createdAt,
});

class $$DeviceAuditLogsTableFilterComposer
    extends Composer<_$SpikeDatabase, $DeviceAuditLogsTable> {
  $$DeviceAuditLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get details => $composableBuilder(
      column: $table.details, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$DeviceAuditLogsTableOrderingComposer
    extends Composer<_$SpikeDatabase, $DeviceAuditLogsTable> {
  $$DeviceAuditLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get details => $composableBuilder(
      column: $table.details, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$DeviceAuditLogsTableAnnotationComposer
    extends Composer<_$SpikeDatabase, $DeviceAuditLogsTable> {
  $$DeviceAuditLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get details =>
      $composableBuilder(column: $table.details, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$DeviceAuditLogsTableTableManager extends RootTableManager<
    _$SpikeDatabase,
    $DeviceAuditLogsTable,
    DeviceAuditLog,
    $$DeviceAuditLogsTableFilterComposer,
    $$DeviceAuditLogsTableOrderingComposer,
    $$DeviceAuditLogsTableAnnotationComposer,
    $$DeviceAuditLogsTableCreateCompanionBuilder,
    $$DeviceAuditLogsTableUpdateCompanionBuilder,
    (
      DeviceAuditLog,
      BaseReferences<_$SpikeDatabase, $DeviceAuditLogsTable, DeviceAuditLog>
    ),
    DeviceAuditLog,
    PrefetchHooks Function()> {
  $$DeviceAuditLogsTableTableManager(
      _$SpikeDatabase db, $DeviceAuditLogsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DeviceAuditLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DeviceAuditLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DeviceAuditLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> deviceId = const Value.absent(),
            Value<String> action = const Value.absent(),
            Value<String?> details = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              DeviceAuditLogsCompanion(
            id: id,
            deviceId: deviceId,
            action: action,
            details: details,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String deviceId,
            required String action,
            Value<String?> details = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              DeviceAuditLogsCompanion.insert(
            id: id,
            deviceId: deviceId,
            action: action,
            details: details,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$DeviceAuditLogsTableProcessedTableManager = ProcessedTableManager<
    _$SpikeDatabase,
    $DeviceAuditLogsTable,
    DeviceAuditLog,
    $$DeviceAuditLogsTableFilterComposer,
    $$DeviceAuditLogsTableOrderingComposer,
    $$DeviceAuditLogsTableAnnotationComposer,
    $$DeviceAuditLogsTableCreateCompanionBuilder,
    $$DeviceAuditLogsTableUpdateCompanionBuilder,
    (
      DeviceAuditLog,
      BaseReferences<_$SpikeDatabase, $DeviceAuditLogsTable, DeviceAuditLog>
    ),
    DeviceAuditLog,
    PrefetchHooks Function()>;
typedef $$ProductPriceHistoriesTableCreateCompanionBuilder
    = ProductPriceHistoriesCompanion Function({
  required String id,
  required String productId,
  required int price,
  required DateTime validFrom,
  Value<DateTime?> validUntil,
  Value<DateTime> createdAt,
  Value<int> rowid,
});
typedef $$ProductPriceHistoriesTableUpdateCompanionBuilder
    = ProductPriceHistoriesCompanion Function({
  Value<String> id,
  Value<String> productId,
  Value<int> price,
  Value<DateTime> validFrom,
  Value<DateTime?> validUntil,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

final class $$ProductPriceHistoriesTableReferences extends BaseReferences<
    _$SpikeDatabase, $ProductPriceHistoriesTable, ProductPriceHistory> {
  $$ProductPriceHistoriesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $ProductsTable _productIdTable(_$SpikeDatabase db) => db.products
      .createAlias('product_price_histories__product_id__products__id');

  $$ProductsTableProcessedTableManager get productId {
    final $_column = $_itemColumn<String>('product_id')!;

    final manager = $$ProductsTableTableManager($_db, $_db.products)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$ProductPriceHistoriesTableFilterComposer
    extends Composer<_$SpikeDatabase, $ProductPriceHistoriesTable> {
  $$ProductPriceHistoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get validFrom => $composableBuilder(
      column: $table.validFrom, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get validUntil => $composableBuilder(
      column: $table.validUntil, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  $$ProductsTableFilterComposer get productId {
    final $$ProductsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableFilterComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ProductPriceHistoriesTableOrderingComposer
    extends Composer<_$SpikeDatabase, $ProductPriceHistoriesTable> {
  $$ProductPriceHistoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get validFrom => $composableBuilder(
      column: $table.validFrom, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get validUntil => $composableBuilder(
      column: $table.validUntil, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  $$ProductsTableOrderingComposer get productId {
    final $$ProductsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableOrderingComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ProductPriceHistoriesTableAnnotationComposer
    extends Composer<_$SpikeDatabase, $ProductPriceHistoriesTable> {
  $$ProductPriceHistoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<DateTime> get validFrom =>
      $composableBuilder(column: $table.validFrom, builder: (column) => column);

  GeneratedColumn<DateTime> get validUntil => $composableBuilder(
      column: $table.validUntil, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$ProductsTableAnnotationComposer get productId {
    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableAnnotationComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ProductPriceHistoriesTableTableManager extends RootTableManager<
    _$SpikeDatabase,
    $ProductPriceHistoriesTable,
    ProductPriceHistory,
    $$ProductPriceHistoriesTableFilterComposer,
    $$ProductPriceHistoriesTableOrderingComposer,
    $$ProductPriceHistoriesTableAnnotationComposer,
    $$ProductPriceHistoriesTableCreateCompanionBuilder,
    $$ProductPriceHistoriesTableUpdateCompanionBuilder,
    (ProductPriceHistory, $$ProductPriceHistoriesTableReferences),
    ProductPriceHistory,
    PrefetchHooks Function({bool productId})> {
  $$ProductPriceHistoriesTableTableManager(
      _$SpikeDatabase db, $ProductPriceHistoriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductPriceHistoriesTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductPriceHistoriesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductPriceHistoriesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<int> price = const Value.absent(),
            Value<DateTime> validFrom = const Value.absent(),
            Value<DateTime?> validUntil = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductPriceHistoriesCompanion(
            id: id,
            productId: productId,
            price: price,
            validFrom: validFrom,
            validUntil: validUntil,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String productId,
            required int price,
            required DateTime validFrom,
            Value<DateTime?> validUntil = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductPriceHistoriesCompanion.insert(
            id: id,
            productId: productId,
            price: price,
            validFrom: validFrom,
            validUntil: validUntil,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$ProductPriceHistoriesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({productId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (productId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.productId,
                    referencedTable: $$ProductPriceHistoriesTableReferences
                        ._productIdTable(db),
                    referencedColumn: $$ProductPriceHistoriesTableReferences
                        ._productIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$ProductPriceHistoriesTableProcessedTableManager
    = ProcessedTableManager<
        _$SpikeDatabase,
        $ProductPriceHistoriesTable,
        ProductPriceHistory,
        $$ProductPriceHistoriesTableFilterComposer,
        $$ProductPriceHistoriesTableOrderingComposer,
        $$ProductPriceHistoriesTableAnnotationComposer,
        $$ProductPriceHistoriesTableCreateCompanionBuilder,
        $$ProductPriceHistoriesTableUpdateCompanionBuilder,
        (ProductPriceHistory, $$ProductPriceHistoriesTableReferences),
        ProductPriceHistory,
        PrefetchHooks Function({bool productId})>;
typedef $$ProductSyncSessionsTableCreateCompanionBuilder
    = ProductSyncSessionsCompanion Function({
  required String id,
  required String deviceId,
  required int productCount,
  required DateTime syncedAt,
  Value<bool> isAcknowledged,
  Value<DateTime?> acknowledgedAt,
  Value<DateTime> createdAt,
  Value<int> rowid,
});
typedef $$ProductSyncSessionsTableUpdateCompanionBuilder
    = ProductSyncSessionsCompanion Function({
  Value<String> id,
  Value<String> deviceId,
  Value<int> productCount,
  Value<DateTime> syncedAt,
  Value<bool> isAcknowledged,
  Value<DateTime?> acknowledgedAt,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$ProductSyncSessionsTableFilterComposer
    extends Composer<_$SpikeDatabase, $ProductSyncSessionsTable> {
  $$ProductSyncSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get productCount => $composableBuilder(
      column: $table.productCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isAcknowledged => $composableBuilder(
      column: $table.isAcknowledged,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get acknowledgedAt => $composableBuilder(
      column: $table.acknowledgedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$ProductSyncSessionsTableOrderingComposer
    extends Composer<_$SpikeDatabase, $ProductSyncSessionsTable> {
  $$ProductSyncSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get productCount => $composableBuilder(
      column: $table.productCount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get syncedAt => $composableBuilder(
      column: $table.syncedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isAcknowledged => $composableBuilder(
      column: $table.isAcknowledged,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get acknowledgedAt => $composableBuilder(
      column: $table.acknowledgedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$ProductSyncSessionsTableAnnotationComposer
    extends Composer<_$SpikeDatabase, $ProductSyncSessionsTable> {
  $$ProductSyncSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get productCount => $composableBuilder(
      column: $table.productCount, builder: (column) => column);

  GeneratedColumn<DateTime> get syncedAt =>
      $composableBuilder(column: $table.syncedAt, builder: (column) => column);

  GeneratedColumn<bool> get isAcknowledged => $composableBuilder(
      column: $table.isAcknowledged, builder: (column) => column);

  GeneratedColumn<DateTime> get acknowledgedAt => $composableBuilder(
      column: $table.acknowledgedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ProductSyncSessionsTableTableManager extends RootTableManager<
    _$SpikeDatabase,
    $ProductSyncSessionsTable,
    ProductSyncSession,
    $$ProductSyncSessionsTableFilterComposer,
    $$ProductSyncSessionsTableOrderingComposer,
    $$ProductSyncSessionsTableAnnotationComposer,
    $$ProductSyncSessionsTableCreateCompanionBuilder,
    $$ProductSyncSessionsTableUpdateCompanionBuilder,
    (
      ProductSyncSession,
      BaseReferences<_$SpikeDatabase, $ProductSyncSessionsTable,
          ProductSyncSession>
    ),
    ProductSyncSession,
    PrefetchHooks Function()> {
  $$ProductSyncSessionsTableTableManager(
      _$SpikeDatabase db, $ProductSyncSessionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductSyncSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductSyncSessionsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductSyncSessionsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> deviceId = const Value.absent(),
            Value<int> productCount = const Value.absent(),
            Value<DateTime> syncedAt = const Value.absent(),
            Value<bool> isAcknowledged = const Value.absent(),
            Value<DateTime?> acknowledgedAt = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductSyncSessionsCompanion(
            id: id,
            deviceId: deviceId,
            productCount: productCount,
            syncedAt: syncedAt,
            isAcknowledged: isAcknowledged,
            acknowledgedAt: acknowledgedAt,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String deviceId,
            required int productCount,
            required DateTime syncedAt,
            Value<bool> isAcknowledged = const Value.absent(),
            Value<DateTime?> acknowledgedAt = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProductSyncSessionsCompanion.insert(
            id: id,
            deviceId: deviceId,
            productCount: productCount,
            syncedAt: syncedAt,
            isAcknowledged: isAcknowledged,
            acknowledgedAt: acknowledgedAt,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ProductSyncSessionsTableProcessedTableManager = ProcessedTableManager<
    _$SpikeDatabase,
    $ProductSyncSessionsTable,
    ProductSyncSession,
    $$ProductSyncSessionsTableFilterComposer,
    $$ProductSyncSessionsTableOrderingComposer,
    $$ProductSyncSessionsTableAnnotationComposer,
    $$ProductSyncSessionsTableCreateCompanionBuilder,
    $$ProductSyncSessionsTableUpdateCompanionBuilder,
    (
      ProductSyncSession,
      BaseReferences<_$SpikeDatabase, $ProductSyncSessionsTable,
          ProductSyncSession>
    ),
    ProductSyncSession,
    PrefetchHooks Function()>;
typedef $$RefundsTableCreateCompanionBuilder = RefundsCompanion Function({
  required String id,
  required String saleId,
  required String deviceId,
  required int clientSeq,
  required int totalRefundAmount,
  required String paymentMethod,
  required String reason,
  Value<DateTime> createdAt,
  Value<int> rowid,
});
typedef $$RefundsTableUpdateCompanionBuilder = RefundsCompanion Function({
  Value<String> id,
  Value<String> saleId,
  Value<String> deviceId,
  Value<int> clientSeq,
  Value<int> totalRefundAmount,
  Value<String> paymentMethod,
  Value<String> reason,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

final class $$RefundsTableReferences
    extends BaseReferences<_$SpikeDatabase, $RefundsTable, Refund> {
  $$RefundsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SalesTable _saleIdTable(_$SpikeDatabase db) =>
      db.sales.createAlias('refunds__sale_id__sales__id');

  $$SalesTableProcessedTableManager get saleId {
    final $_column = $_itemColumn<String>('sale_id')!;

    final manager = $$SalesTableTableManager($_db, $_db.sales)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_saleIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$RefundItemsTable, List<RefundItem>>
      _refundItemsRefsTable(_$SpikeDatabase db) =>
          MultiTypedResultKey.fromTable(db.refundItems,
              aliasName: 'refunds__id__refund_items__refund_id');

  $$RefundItemsTableProcessedTableManager get refundItemsRefs {
    final manager = $$RefundItemsTableTableManager($_db, $_db.refundItems)
        .filter((f) => f.refundId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_refundItemsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$RefundsTableFilterComposer
    extends Composer<_$SpikeDatabase, $RefundsTable> {
  $$RefundsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get clientSeq => $composableBuilder(
      column: $table.clientSeq, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get totalRefundAmount => $composableBuilder(
      column: $table.totalRefundAmount,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get paymentMethod => $composableBuilder(
      column: $table.paymentMethod, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get reason => $composableBuilder(
      column: $table.reason, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  $$SalesTableFilterComposer get saleId {
    final $$SalesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.saleId,
        referencedTable: $db.sales,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SalesTableFilterComposer(
              $db: $db,
              $table: $db.sales,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> refundItemsRefs(
      Expression<bool> Function($$RefundItemsTableFilterComposer f) f) {
    final $$RefundItemsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.refundItems,
        getReferencedColumn: (t) => t.refundId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RefundItemsTableFilterComposer(
              $db: $db,
              $table: $db.refundItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$RefundsTableOrderingComposer
    extends Composer<_$SpikeDatabase, $RefundsTable> {
  $$RefundsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get clientSeq => $composableBuilder(
      column: $table.clientSeq, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get totalRefundAmount => $composableBuilder(
      column: $table.totalRefundAmount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get paymentMethod => $composableBuilder(
      column: $table.paymentMethod,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get reason => $composableBuilder(
      column: $table.reason, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  $$SalesTableOrderingComposer get saleId {
    final $$SalesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.saleId,
        referencedTable: $db.sales,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SalesTableOrderingComposer(
              $db: $db,
              $table: $db.sales,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$RefundsTableAnnotationComposer
    extends Composer<_$SpikeDatabase, $RefundsTable> {
  $$RefundsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get clientSeq =>
      $composableBuilder(column: $table.clientSeq, builder: (column) => column);

  GeneratedColumn<int> get totalRefundAmount => $composableBuilder(
      column: $table.totalRefundAmount, builder: (column) => column);

  GeneratedColumn<String> get paymentMethod => $composableBuilder(
      column: $table.paymentMethod, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$SalesTableAnnotationComposer get saleId {
    final $$SalesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.saleId,
        referencedTable: $db.sales,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SalesTableAnnotationComposer(
              $db: $db,
              $table: $db.sales,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> refundItemsRefs<T extends Object>(
      Expression<T> Function($$RefundItemsTableAnnotationComposer a) f) {
    final $$RefundItemsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.refundItems,
        getReferencedColumn: (t) => t.refundId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RefundItemsTableAnnotationComposer(
              $db: $db,
              $table: $db.refundItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$RefundsTableTableManager extends RootTableManager<
    _$SpikeDatabase,
    $RefundsTable,
    Refund,
    $$RefundsTableFilterComposer,
    $$RefundsTableOrderingComposer,
    $$RefundsTableAnnotationComposer,
    $$RefundsTableCreateCompanionBuilder,
    $$RefundsTableUpdateCompanionBuilder,
    (Refund, $$RefundsTableReferences),
    Refund,
    PrefetchHooks Function({bool saleId, bool refundItemsRefs})> {
  $$RefundsTableTableManager(_$SpikeDatabase db, $RefundsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RefundsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RefundsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RefundsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> saleId = const Value.absent(),
            Value<String> deviceId = const Value.absent(),
            Value<int> clientSeq = const Value.absent(),
            Value<int> totalRefundAmount = const Value.absent(),
            Value<String> paymentMethod = const Value.absent(),
            Value<String> reason = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RefundsCompanion(
            id: id,
            saleId: saleId,
            deviceId: deviceId,
            clientSeq: clientSeq,
            totalRefundAmount: totalRefundAmount,
            paymentMethod: paymentMethod,
            reason: reason,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String saleId,
            required String deviceId,
            required int clientSeq,
            required int totalRefundAmount,
            required String paymentMethod,
            required String reason,
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RefundsCompanion.insert(
            id: id,
            saleId: saleId,
            deviceId: deviceId,
            clientSeq: clientSeq,
            totalRefundAmount: totalRefundAmount,
            paymentMethod: paymentMethod,
            reason: reason,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$RefundsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({saleId = false, refundItemsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (refundItemsRefs) db.refundItems],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (saleId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.saleId,
                    referencedTable: $$RefundsTableReferences._saleIdTable(db),
                    referencedColumn:
                        $$RefundsTableReferences._saleIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (refundItemsRefs)
                    await $_getPrefetchedData<Refund, $RefundsTable,
                            RefundItem>(
                        currentTable: table,
                        referencedTable:
                            $$RefundsTableReferences._refundItemsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$RefundsTableReferences(db, table, p0)
                                .refundItemsRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.refundId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$RefundsTableProcessedTableManager = ProcessedTableManager<
    _$SpikeDatabase,
    $RefundsTable,
    Refund,
    $$RefundsTableFilterComposer,
    $$RefundsTableOrderingComposer,
    $$RefundsTableAnnotationComposer,
    $$RefundsTableCreateCompanionBuilder,
    $$RefundsTableUpdateCompanionBuilder,
    (Refund, $$RefundsTableReferences),
    Refund,
    PrefetchHooks Function({bool saleId, bool refundItemsRefs})>;
typedef $$RefundItemsTableCreateCompanionBuilder = RefundItemsCompanion
    Function({
  required String id,
  required String refundId,
  Value<String?> saleItemId,
  required String productId,
  required int quantity,
  required int unitPrice,
  required int refundAmount,
  Value<String> productCondition,
  Value<DateTime> createdAt,
  Value<int> rowid,
});
typedef $$RefundItemsTableUpdateCompanionBuilder = RefundItemsCompanion
    Function({
  Value<String> id,
  Value<String> refundId,
  Value<String?> saleItemId,
  Value<String> productId,
  Value<int> quantity,
  Value<int> unitPrice,
  Value<int> refundAmount,
  Value<String> productCondition,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

final class $$RefundItemsTableReferences
    extends BaseReferences<_$SpikeDatabase, $RefundItemsTable, RefundItem> {
  $$RefundItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $RefundsTable _refundIdTable(_$SpikeDatabase db) =>
      db.refunds.createAlias('refund_items__refund_id__refunds__id');

  $$RefundsTableProcessedTableManager get refundId {
    final $_column = $_itemColumn<String>('refund_id')!;

    final manager = $$RefundsTableTableManager($_db, $_db.refunds)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_refundIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $ProductsTable _productIdTable(_$SpikeDatabase db) =>
      db.products.createAlias('refund_items__product_id__products__id');

  $$ProductsTableProcessedTableManager get productId {
    final $_column = $_itemColumn<String>('product_id')!;

    final manager = $$ProductsTableTableManager($_db, $_db.products)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$RefundItemsTableFilterComposer
    extends Composer<_$SpikeDatabase, $RefundItemsTable> {
  $$RefundItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get saleItemId => $composableBuilder(
      column: $table.saleItemId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get quantity => $composableBuilder(
      column: $table.quantity, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get unitPrice => $composableBuilder(
      column: $table.unitPrice, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get refundAmount => $composableBuilder(
      column: $table.refundAmount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productCondition => $composableBuilder(
      column: $table.productCondition,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  $$RefundsTableFilterComposer get refundId {
    final $$RefundsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.refundId,
        referencedTable: $db.refunds,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RefundsTableFilterComposer(
              $db: $db,
              $table: $db.refunds,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$ProductsTableFilterComposer get productId {
    final $$ProductsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableFilterComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$RefundItemsTableOrderingComposer
    extends Composer<_$SpikeDatabase, $RefundItemsTable> {
  $$RefundItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get saleItemId => $composableBuilder(
      column: $table.saleItemId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get quantity => $composableBuilder(
      column: $table.quantity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get unitPrice => $composableBuilder(
      column: $table.unitPrice, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get refundAmount => $composableBuilder(
      column: $table.refundAmount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productCondition => $composableBuilder(
      column: $table.productCondition,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  $$RefundsTableOrderingComposer get refundId {
    final $$RefundsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.refundId,
        referencedTable: $db.refunds,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RefundsTableOrderingComposer(
              $db: $db,
              $table: $db.refunds,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$ProductsTableOrderingComposer get productId {
    final $$ProductsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableOrderingComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$RefundItemsTableAnnotationComposer
    extends Composer<_$SpikeDatabase, $RefundItemsTable> {
  $$RefundItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get saleItemId => $composableBuilder(
      column: $table.saleItemId, builder: (column) => column);

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<int> get unitPrice =>
      $composableBuilder(column: $table.unitPrice, builder: (column) => column);

  GeneratedColumn<int> get refundAmount => $composableBuilder(
      column: $table.refundAmount, builder: (column) => column);

  GeneratedColumn<String> get productCondition => $composableBuilder(
      column: $table.productCondition, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$RefundsTableAnnotationComposer get refundId {
    final $$RefundsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.refundId,
        referencedTable: $db.refunds,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RefundsTableAnnotationComposer(
              $db: $db,
              $table: $db.refunds,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$ProductsTableAnnotationComposer get productId {
    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.products,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ProductsTableAnnotationComposer(
              $db: $db,
              $table: $db.products,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$RefundItemsTableTableManager extends RootTableManager<
    _$SpikeDatabase,
    $RefundItemsTable,
    RefundItem,
    $$RefundItemsTableFilterComposer,
    $$RefundItemsTableOrderingComposer,
    $$RefundItemsTableAnnotationComposer,
    $$RefundItemsTableCreateCompanionBuilder,
    $$RefundItemsTableUpdateCompanionBuilder,
    (RefundItem, $$RefundItemsTableReferences),
    RefundItem,
    PrefetchHooks Function({bool refundId, bool productId})> {
  $$RefundItemsTableTableManager(_$SpikeDatabase db, $RefundItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RefundItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RefundItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RefundItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> refundId = const Value.absent(),
            Value<String?> saleItemId = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<int> quantity = const Value.absent(),
            Value<int> unitPrice = const Value.absent(),
            Value<int> refundAmount = const Value.absent(),
            Value<String> productCondition = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RefundItemsCompanion(
            id: id,
            refundId: refundId,
            saleItemId: saleItemId,
            productId: productId,
            quantity: quantity,
            unitPrice: unitPrice,
            refundAmount: refundAmount,
            productCondition: productCondition,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String refundId,
            Value<String?> saleItemId = const Value.absent(),
            required String productId,
            required int quantity,
            required int unitPrice,
            required int refundAmount,
            Value<String> productCondition = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RefundItemsCompanion.insert(
            id: id,
            refundId: refundId,
            saleItemId: saleItemId,
            productId: productId,
            quantity: quantity,
            unitPrice: unitPrice,
            refundAmount: refundAmount,
            productCondition: productCondition,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$RefundItemsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({refundId = false, productId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (refundId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.refundId,
                    referencedTable:
                        $$RefundItemsTableReferences._refundIdTable(db),
                    referencedColumn:
                        $$RefundItemsTableReferences._refundIdTable(db).id,
                  ) as T;
                }
                if (productId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.productId,
                    referencedTable:
                        $$RefundItemsTableReferences._productIdTable(db),
                    referencedColumn:
                        $$RefundItemsTableReferences._productIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$RefundItemsTableProcessedTableManager = ProcessedTableManager<
    _$SpikeDatabase,
    $RefundItemsTable,
    RefundItem,
    $$RefundItemsTableFilterComposer,
    $$RefundItemsTableOrderingComposer,
    $$RefundItemsTableAnnotationComposer,
    $$RefundItemsTableCreateCompanionBuilder,
    $$RefundItemsTableUpdateCompanionBuilder,
    (RefundItem, $$RefundItemsTableReferences),
    RefundItem,
    PrefetchHooks Function({bool refundId, bool productId})>;
typedef $$HubMetadataTableCreateCompanionBuilder = HubMetadataCompanion
    Function({
  required String key,
  required String value,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$HubMetadataTableUpdateCompanionBuilder = HubMetadataCompanion
    Function({
  Value<String> key,
  Value<String> value,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$HubMetadataTableFilterComposer
    extends Composer<_$SpikeDatabase, $HubMetadataTable> {
  $$HubMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$HubMetadataTableOrderingComposer
    extends Composer<_$SpikeDatabase, $HubMetadataTable> {
  $$HubMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$HubMetadataTableAnnotationComposer
    extends Composer<_$SpikeDatabase, $HubMetadataTable> {
  $$HubMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$HubMetadataTableTableManager extends RootTableManager<
    _$SpikeDatabase,
    $HubMetadataTable,
    HubMetadataData,
    $$HubMetadataTableFilterComposer,
    $$HubMetadataTableOrderingComposer,
    $$HubMetadataTableAnnotationComposer,
    $$HubMetadataTableCreateCompanionBuilder,
    $$HubMetadataTableUpdateCompanionBuilder,
    (
      HubMetadataData,
      BaseReferences<_$SpikeDatabase, $HubMetadataTable, HubMetadataData>
    ),
    HubMetadataData,
    PrefetchHooks Function()> {
  $$HubMetadataTableTableManager(_$SpikeDatabase db, $HubMetadataTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HubMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HubMetadataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HubMetadataTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              HubMetadataCompanion(
            key: key,
            value: value,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              HubMetadataCompanion.insert(
            key: key,
            value: value,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$HubMetadataTableProcessedTableManager = ProcessedTableManager<
    _$SpikeDatabase,
    $HubMetadataTable,
    HubMetadataData,
    $$HubMetadataTableFilterComposer,
    $$HubMetadataTableOrderingComposer,
    $$HubMetadataTableAnnotationComposer,
    $$HubMetadataTableCreateCompanionBuilder,
    $$HubMetadataTableUpdateCompanionBuilder,
    (
      HubMetadataData,
      BaseReferences<_$SpikeDatabase, $HubMetadataTable, HubMetadataData>
    ),
    HubMetadataData,
    PrefetchHooks Function()>;

class $SpikeDatabaseManager {
  final _$SpikeDatabase _db;
  $SpikeDatabaseManager(this._db);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db, _db.products);
  $$SalesTableTableManager get sales =>
      $$SalesTableTableManager(_db, _db.sales);
  $$SaleItemsTableTableManager get saleItems =>
      $$SaleItemsTableTableManager(_db, _db.saleItems);
  $$StockMovementsTableTableManager get stockMovements =>
      $$StockMovementsTableTableManager(_db, _db.stockMovements);
  $$ProcessedOperationsTableTableManager get processedOperations =>
      $$ProcessedOperationsTableTableManager(_db, _db.processedOperations);
  $$DevicesTableTableManager get devices =>
      $$DevicesTableTableManager(_db, _db.devices);
  $$DeviceAuditLogsTableTableManager get deviceAuditLogs =>
      $$DeviceAuditLogsTableTableManager(_db, _db.deviceAuditLogs);
  $$ProductPriceHistoriesTableTableManager get productPriceHistories =>
      $$ProductPriceHistoriesTableTableManager(_db, _db.productPriceHistories);
  $$ProductSyncSessionsTableTableManager get productSyncSessions =>
      $$ProductSyncSessionsTableTableManager(_db, _db.productSyncSessions);
  $$RefundsTableTableManager get refunds =>
      $$RefundsTableTableManager(_db, _db.refunds);
  $$RefundItemsTableTableManager get refundItems =>
      $$RefundItemsTableTableManager(_db, _db.refundItems);
  $$HubMetadataTableTableManager get hubMetadata =>
      $$HubMetadataTableTableManager(_db, _db.hubMetadata);
}
