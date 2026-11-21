// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'client_database.dart';

// ignore_for_file: type=lint
class $LocalCategoriesTable extends LocalCategories
    with TableInfo<$LocalCategoriesTable, LocalCategory> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalCategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _parentIdMeta =
      const VerificationMeta('parentId');
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
      'parent_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES local_categories (id)'));
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
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, parentId, isActive, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_categories';
  @override
  VerificationContext validateIntegrity(Insertable<LocalCategory> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(_parentIdMeta,
          parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
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
  LocalCategory map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalCategory(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      parentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parent_id']),
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $LocalCategoriesTable createAlias(String alias) {
    return $LocalCategoriesTable(attachedDatabase, alias);
  }
}

class LocalCategory extends DataClass implements Insertable<LocalCategory> {
  final String id;
  final String name;
  final String? parentId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  const LocalCategory(
      {required this.id,
      required this.name,
      this.parentId,
      required this.isActive,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalCategoriesCompanion toCompanion(bool nullToAbsent) {
    return LocalCategoriesCompanion(
      id: Value(id),
      name: Value(name),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalCategory.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalCategory(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'parentId': serializer.toJson<String?>(parentId),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalCategory copyWith(
          {String? id,
          String? name,
          Value<String?> parentId = const Value.absent(),
          bool? isActive,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      LocalCategory(
        id: id ?? this.id,
        name: name ?? this.name,
        parentId: parentId.present ? parentId.value : this.parentId,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  LocalCategory copyWithCompanion(LocalCategoriesCompanion data) {
    return LocalCategory(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalCategory(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('parentId: $parentId, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, parentId, isActive, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalCategory &&
          other.id == this.id &&
          other.name == this.name &&
          other.parentId == this.parentId &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class LocalCategoriesCompanion extends UpdateCompanion<LocalCategory> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> parentId;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalCategoriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.parentId = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalCategoriesCompanion.insert({
    required String id,
    required String name,
    this.parentId = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name);
  static Insertable<LocalCategory> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? parentId,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (parentId != null) 'parent_id': parentId,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalCategoriesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String?>? parentId,
      Value<bool>? isActive,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return LocalCategoriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
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
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
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
    return (StringBuffer('LocalCategoriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('parentId: $parentId, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalProductsTable extends LocalProducts
    with TableInfo<$LocalProductsTable, LocalProduct> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _barcodeMeta =
      const VerificationMeta('barcode');
  @override
  late final GeneratedColumn<String> barcode = GeneratedColumn<String>(
      'barcode', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryIdMeta =
      const VerificationMeta('categoryId');
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
      'category_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES local_categories (id)'));
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
  static const VerificationMeta _vatRateMeta =
      const VerificationMeta('vatRate');
  @override
  late final GeneratedColumn<int> vatRate = GeneratedColumn<int>(
      'vat_rate', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(20));
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
        categoryId,
        price,
        priceVersionId,
        stock,
        stockUnit,
        pricingUnit,
        conversionFactorNumerator,
        conversionFactorDenominator,
        vatRate,
        isActive,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_products';
  @override
  VerificationContext validateIntegrity(Insertable<LocalProduct> instance,
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
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
          _categoryIdMeta,
          categoryId.isAcceptableOrUnknown(
              data['category_id']!, _categoryIdMeta));
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
    if (data.containsKey('vat_rate')) {
      context.handle(_vatRateMeta,
          vatRate.isAcceptableOrUnknown(data['vat_rate']!, _vatRateMeta));
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
  LocalProduct map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalProduct(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      barcode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}barcode']),
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      categoryId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category_id']),
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
      vatRate: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}vat_rate'])!,
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $LocalProductsTable createAlias(String alias) {
    return $LocalProductsTable(attachedDatabase, alias);
  }
}

class LocalProduct extends DataClass implements Insertable<LocalProduct> {
  final String id;
  final String? barcode;
  final String name;
  final String? categoryId;
  final int price;
  final String priceVersionId;
  final int stock;
  final String stockUnit;
  final String pricingUnit;
  final int conversionFactorNumerator;
  final int conversionFactorDenominator;
  final int vatRate;
  final bool isActive;
  final DateTime updatedAt;
  const LocalProduct(
      {required this.id,
      this.barcode,
      required this.name,
      this.categoryId,
      required this.price,
      required this.priceVersionId,
      required this.stock,
      required this.stockUnit,
      required this.pricingUnit,
      required this.conversionFactorNumerator,
      required this.conversionFactorDenominator,
      required this.vatRate,
      required this.isActive,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || barcode != null) {
      map['barcode'] = Variable<String>(barcode);
    }
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || categoryId != null) {
      map['category_id'] = Variable<String>(categoryId);
    }
    map['price'] = Variable<int>(price);
    map['price_version_id'] = Variable<String>(priceVersionId);
    map['stock'] = Variable<int>(stock);
    map['stock_unit'] = Variable<String>(stockUnit);
    map['pricing_unit'] = Variable<String>(pricingUnit);
    map['conversion_factor_numerator'] =
        Variable<int>(conversionFactorNumerator);
    map['conversion_factor_denominator'] =
        Variable<int>(conversionFactorDenominator);
    map['vat_rate'] = Variable<int>(vatRate);
    map['is_active'] = Variable<bool>(isActive);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalProductsCompanion toCompanion(bool nullToAbsent) {
    return LocalProductsCompanion(
      id: Value(id),
      barcode: barcode == null && nullToAbsent
          ? const Value.absent()
          : Value(barcode),
      name: Value(name),
      categoryId: categoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(categoryId),
      price: Value(price),
      priceVersionId: Value(priceVersionId),
      stock: Value(stock),
      stockUnit: Value(stockUnit),
      pricingUnit: Value(pricingUnit),
      conversionFactorNumerator: Value(conversionFactorNumerator),
      conversionFactorDenominator: Value(conversionFactorDenominator),
      vatRate: Value(vatRate),
      isActive: Value(isActive),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalProduct.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalProduct(
      id: serializer.fromJson<String>(json['id']),
      barcode: serializer.fromJson<String?>(json['barcode']),
      name: serializer.fromJson<String>(json['name']),
      categoryId: serializer.fromJson<String?>(json['categoryId']),
      price: serializer.fromJson<int>(json['price']),
      priceVersionId: serializer.fromJson<String>(json['priceVersionId']),
      stock: serializer.fromJson<int>(json['stock']),
      stockUnit: serializer.fromJson<String>(json['stockUnit']),
      pricingUnit: serializer.fromJson<String>(json['pricingUnit']),
      conversionFactorNumerator:
          serializer.fromJson<int>(json['conversionFactorNumerator']),
      conversionFactorDenominator:
          serializer.fromJson<int>(json['conversionFactorDenominator']),
      vatRate: serializer.fromJson<int>(json['vatRate']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'barcode': serializer.toJson<String?>(barcode),
      'name': serializer.toJson<String>(name),
      'categoryId': serializer.toJson<String?>(categoryId),
      'price': serializer.toJson<int>(price),
      'priceVersionId': serializer.toJson<String>(priceVersionId),
      'stock': serializer.toJson<int>(stock),
      'stockUnit': serializer.toJson<String>(stockUnit),
      'pricingUnit': serializer.toJson<String>(pricingUnit),
      'conversionFactorNumerator':
          serializer.toJson<int>(conversionFactorNumerator),
      'conversionFactorDenominator':
          serializer.toJson<int>(conversionFactorDenominator),
      'vatRate': serializer.toJson<int>(vatRate),
      'isActive': serializer.toJson<bool>(isActive),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalProduct copyWith(
          {String? id,
          Value<String?> barcode = const Value.absent(),
          String? name,
          Value<String?> categoryId = const Value.absent(),
          int? price,
          String? priceVersionId,
          int? stock,
          String? stockUnit,
          String? pricingUnit,
          int? conversionFactorNumerator,
          int? conversionFactorDenominator,
          int? vatRate,
          bool? isActive,
          DateTime? updatedAt}) =>
      LocalProduct(
        id: id ?? this.id,
        barcode: barcode.present ? barcode.value : this.barcode,
        name: name ?? this.name,
        categoryId: categoryId.present ? categoryId.value : this.categoryId,
        price: price ?? this.price,
        priceVersionId: priceVersionId ?? this.priceVersionId,
        stock: stock ?? this.stock,
        stockUnit: stockUnit ?? this.stockUnit,
        pricingUnit: pricingUnit ?? this.pricingUnit,
        conversionFactorNumerator:
            conversionFactorNumerator ?? this.conversionFactorNumerator,
        conversionFactorDenominator:
            conversionFactorDenominator ?? this.conversionFactorDenominator,
        vatRate: vatRate ?? this.vatRate,
        isActive: isActive ?? this.isActive,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  LocalProduct copyWithCompanion(LocalProductsCompanion data) {
    return LocalProduct(
      id: data.id.present ? data.id.value : this.id,
      barcode: data.barcode.present ? data.barcode.value : this.barcode,
      name: data.name.present ? data.name.value : this.name,
      categoryId:
          data.categoryId.present ? data.categoryId.value : this.categoryId,
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
      vatRate: data.vatRate.present ? data.vatRate.value : this.vatRate,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalProduct(')
          ..write('id: $id, ')
          ..write('barcode: $barcode, ')
          ..write('name: $name, ')
          ..write('categoryId: $categoryId, ')
          ..write('price: $price, ')
          ..write('priceVersionId: $priceVersionId, ')
          ..write('stock: $stock, ')
          ..write('stockUnit: $stockUnit, ')
          ..write('pricingUnit: $pricingUnit, ')
          ..write('conversionFactorNumerator: $conversionFactorNumerator, ')
          ..write('conversionFactorDenominator: $conversionFactorDenominator, ')
          ..write('vatRate: $vatRate, ')
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
      categoryId,
      price,
      priceVersionId,
      stock,
      stockUnit,
      pricingUnit,
      conversionFactorNumerator,
      conversionFactorDenominator,
      vatRate,
      isActive,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalProduct &&
          other.id == this.id &&
          other.barcode == this.barcode &&
          other.name == this.name &&
          other.categoryId == this.categoryId &&
          other.price == this.price &&
          other.priceVersionId == this.priceVersionId &&
          other.stock == this.stock &&
          other.stockUnit == this.stockUnit &&
          other.pricingUnit == this.pricingUnit &&
          other.conversionFactorNumerator == this.conversionFactorNumerator &&
          other.conversionFactorDenominator ==
              this.conversionFactorDenominator &&
          other.vatRate == this.vatRate &&
          other.isActive == this.isActive &&
          other.updatedAt == this.updatedAt);
}

class LocalProductsCompanion extends UpdateCompanion<LocalProduct> {
  final Value<String> id;
  final Value<String?> barcode;
  final Value<String> name;
  final Value<String?> categoryId;
  final Value<int> price;
  final Value<String> priceVersionId;
  final Value<int> stock;
  final Value<String> stockUnit;
  final Value<String> pricingUnit;
  final Value<int> conversionFactorNumerator;
  final Value<int> conversionFactorDenominator;
  final Value<int> vatRate;
  final Value<bool> isActive;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalProductsCompanion({
    this.id = const Value.absent(),
    this.barcode = const Value.absent(),
    this.name = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.price = const Value.absent(),
    this.priceVersionId = const Value.absent(),
    this.stock = const Value.absent(),
    this.stockUnit = const Value.absent(),
    this.pricingUnit = const Value.absent(),
    this.conversionFactorNumerator = const Value.absent(),
    this.conversionFactorDenominator = const Value.absent(),
    this.vatRate = const Value.absent(),
    this.isActive = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalProductsCompanion.insert({
    required String id,
    this.barcode = const Value.absent(),
    required String name,
    this.categoryId = const Value.absent(),
    required int price,
    this.priceVersionId = const Value.absent(),
    required int stock,
    this.stockUnit = const Value.absent(),
    this.pricingUnit = const Value.absent(),
    this.conversionFactorNumerator = const Value.absent(),
    this.conversionFactorDenominator = const Value.absent(),
    this.vatRate = const Value.absent(),
    this.isActive = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        price = Value(price),
        stock = Value(stock);
  static Insertable<LocalProduct> custom({
    Expression<String>? id,
    Expression<String>? barcode,
    Expression<String>? name,
    Expression<String>? categoryId,
    Expression<int>? price,
    Expression<String>? priceVersionId,
    Expression<int>? stock,
    Expression<String>? stockUnit,
    Expression<String>? pricingUnit,
    Expression<int>? conversionFactorNumerator,
    Expression<int>? conversionFactorDenominator,
    Expression<int>? vatRate,
    Expression<bool>? isActive,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (barcode != null) 'barcode': barcode,
      if (name != null) 'name': name,
      if (categoryId != null) 'category_id': categoryId,
      if (price != null) 'price': price,
      if (priceVersionId != null) 'price_version_id': priceVersionId,
      if (stock != null) 'stock': stock,
      if (stockUnit != null) 'stock_unit': stockUnit,
      if (pricingUnit != null) 'pricing_unit': pricingUnit,
      if (conversionFactorNumerator != null)
        'conversion_factor_numerator': conversionFactorNumerator,
      if (conversionFactorDenominator != null)
        'conversion_factor_denominator': conversionFactorDenominator,
      if (vatRate != null) 'vat_rate': vatRate,
      if (isActive != null) 'is_active': isActive,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalProductsCompanion copyWith(
      {Value<String>? id,
      Value<String?>? barcode,
      Value<String>? name,
      Value<String?>? categoryId,
      Value<int>? price,
      Value<String>? priceVersionId,
      Value<int>? stock,
      Value<String>? stockUnit,
      Value<String>? pricingUnit,
      Value<int>? conversionFactorNumerator,
      Value<int>? conversionFactorDenominator,
      Value<int>? vatRate,
      Value<bool>? isActive,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return LocalProductsCompanion(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      price: price ?? this.price,
      priceVersionId: priceVersionId ?? this.priceVersionId,
      stock: stock ?? this.stock,
      stockUnit: stockUnit ?? this.stockUnit,
      pricingUnit: pricingUnit ?? this.pricingUnit,
      conversionFactorNumerator:
          conversionFactorNumerator ?? this.conversionFactorNumerator,
      conversionFactorDenominator:
          conversionFactorDenominator ?? this.conversionFactorDenominator,
      vatRate: vatRate ?? this.vatRate,
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
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
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
    if (vatRate.present) {
      map['vat_rate'] = Variable<int>(vatRate.value);
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
    return (StringBuffer('LocalProductsCompanion(')
          ..write('id: $id, ')
          ..write('barcode: $barcode, ')
          ..write('name: $name, ')
          ..write('categoryId: $categoryId, ')
          ..write('price: $price, ')
          ..write('priceVersionId: $priceVersionId, ')
          ..write('stock: $stock, ')
          ..write('stockUnit: $stockUnit, ')
          ..write('pricingUnit: $pricingUnit, ')
          ..write('conversionFactorNumerator: $conversionFactorNumerator, ')
          ..write('conversionFactorDenominator: $conversionFactorDenominator, ')
          ..write('vatRate: $vatRate, ')
          ..write('isActive: $isActive, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalProductBarcodesTable extends LocalProductBarcodes
    with TableInfo<$LocalProductBarcodesTable, LocalProductBarcode> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalProductBarcodesTable(this.attachedDatabase, [this._alias]);
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
          GeneratedColumn.constraintIsAlways('REFERENCES local_products (id)'));
  static const VerificationMeta _barcodeMeta =
      const VerificationMeta('barcode');
  @override
  late final GeneratedColumn<String> barcode = GeneratedColumn<String>(
      'barcode', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isPrimaryMeta =
      const VerificationMeta('isPrimary');
  @override
  late final GeneratedColumn<bool> isPrimary = GeneratedColumn<bool>(
      'is_primary', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_primary" IN (0, 1))'),
      defaultValue: const Constant(true));
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
      [id, productId, barcode, isPrimary, isActive, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_product_barcodes';
  @override
  VerificationContext validateIntegrity(
      Insertable<LocalProductBarcode> instance,
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
    if (data.containsKey('barcode')) {
      context.handle(_barcodeMeta,
          barcode.isAcceptableOrUnknown(data['barcode']!, _barcodeMeta));
    } else if (isInserting) {
      context.missing(_barcodeMeta);
    }
    if (data.containsKey('is_primary')) {
      context.handle(_isPrimaryMeta,
          isPrimary.isAcceptableOrUnknown(data['is_primary']!, _isPrimaryMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
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
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {barcode},
      ];
  @override
  LocalProductBarcode map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalProductBarcode(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      barcode: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}barcode'])!,
      isPrimary: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_primary'])!,
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_active'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $LocalProductBarcodesTable createAlias(String alias) {
    return $LocalProductBarcodesTable(attachedDatabase, alias);
  }
}

class LocalProductBarcode extends DataClass
    implements Insertable<LocalProductBarcode> {
  final String id;
  final String productId;
  final String barcode;
  final bool isPrimary;
  final bool isActive;
  final DateTime createdAt;
  const LocalProductBarcode(
      {required this.id,
      required this.productId,
      required this.barcode,
      required this.isPrimary,
      required this.isActive,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_id'] = Variable<String>(productId);
    map['barcode'] = Variable<String>(barcode);
    map['is_primary'] = Variable<bool>(isPrimary);
    map['is_active'] = Variable<bool>(isActive);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  LocalProductBarcodesCompanion toCompanion(bool nullToAbsent) {
    return LocalProductBarcodesCompanion(
      id: Value(id),
      productId: Value(productId),
      barcode: Value(barcode),
      isPrimary: Value(isPrimary),
      isActive: Value(isActive),
      createdAt: Value(createdAt),
    );
  }

  factory LocalProductBarcode.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalProductBarcode(
      id: serializer.fromJson<String>(json['id']),
      productId: serializer.fromJson<String>(json['productId']),
      barcode: serializer.fromJson<String>(json['barcode']),
      isPrimary: serializer.fromJson<bool>(json['isPrimary']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productId': serializer.toJson<String>(productId),
      'barcode': serializer.toJson<String>(barcode),
      'isPrimary': serializer.toJson<bool>(isPrimary),
      'isActive': serializer.toJson<bool>(isActive),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  LocalProductBarcode copyWith(
          {String? id,
          String? productId,
          String? barcode,
          bool? isPrimary,
          bool? isActive,
          DateTime? createdAt}) =>
      LocalProductBarcode(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        barcode: barcode ?? this.barcode,
        isPrimary: isPrimary ?? this.isPrimary,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt ?? this.createdAt,
      );
  LocalProductBarcode copyWithCompanion(LocalProductBarcodesCompanion data) {
    return LocalProductBarcode(
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      barcode: data.barcode.present ? data.barcode.value : this.barcode,
      isPrimary: data.isPrimary.present ? data.isPrimary.value : this.isPrimary,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalProductBarcode(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('barcode: $barcode, ')
          ..write('isPrimary: $isPrimary, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, productId, barcode, isPrimary, isActive, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalProductBarcode &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.barcode == this.barcode &&
          other.isPrimary == this.isPrimary &&
          other.isActive == this.isActive &&
          other.createdAt == this.createdAt);
}

class LocalProductBarcodesCompanion
    extends UpdateCompanion<LocalProductBarcode> {
  final Value<String> id;
  final Value<String> productId;
  final Value<String> barcode;
  final Value<bool> isPrimary;
  final Value<bool> isActive;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const LocalProductBarcodesCompanion({
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.barcode = const Value.absent(),
    this.isPrimary = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalProductBarcodesCompanion.insert({
    required String id,
    required String productId,
    required String barcode,
    this.isPrimary = const Value.absent(),
    this.isActive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        productId = Value(productId),
        barcode = Value(barcode);
  static Insertable<LocalProductBarcode> custom({
    Expression<String>? id,
    Expression<String>? productId,
    Expression<String>? barcode,
    Expression<bool>? isPrimary,
    Expression<bool>? isActive,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (barcode != null) 'barcode': barcode,
      if (isPrimary != null) 'is_primary': isPrimary,
      if (isActive != null) 'is_active': isActive,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalProductBarcodesCompanion copyWith(
      {Value<String>? id,
      Value<String>? productId,
      Value<String>? barcode,
      Value<bool>? isPrimary,
      Value<bool>? isActive,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return LocalProductBarcodesCompanion(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      barcode: barcode ?? this.barcode,
      isPrimary: isPrimary ?? this.isPrimary,
      isActive: isActive ?? this.isActive,
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
    if (barcode.present) {
      map['barcode'] = Variable<String>(barcode.value);
    }
    if (isPrimary.present) {
      map['is_primary'] = Variable<bool>(isPrimary.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
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
    return (StringBuffer('LocalProductBarcodesCompanion(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('barcode: $barcode, ')
          ..write('isPrimary: $isPrimary, ')
          ..write('isActive: $isActive, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalSalesTable extends LocalSales
    with TableInfo<$LocalSalesTable, LocalSale> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSalesTable(this.attachedDatabase, [this._alias]);
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
        status,
        cancelReason,
        cancelledAt,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_sales';
  @override
  VerificationContext validateIntegrity(Insertable<LocalSale> instance,
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
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {deviceId, clientSeq},
      ];
  @override
  LocalSale map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSale(
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
  $LocalSalesTable createAlias(String alias) {
    return $LocalSalesTable(attachedDatabase, alias);
  }
}

class LocalSale extends DataClass implements Insertable<LocalSale> {
  final String id;
  final String deviceId;
  final int clientSeq;
  final int totalAmount;
  final String paymentMethod;
  final String status;
  final String? cancelReason;
  final DateTime? cancelledAt;
  final DateTime createdAt;
  const LocalSale(
      {required this.id,
      required this.deviceId,
      required this.clientSeq,
      required this.totalAmount,
      required this.paymentMethod,
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

  LocalSalesCompanion toCompanion(bool nullToAbsent) {
    return LocalSalesCompanion(
      id: Value(id),
      deviceId: Value(deviceId),
      clientSeq: Value(clientSeq),
      totalAmount: Value(totalAmount),
      paymentMethod: Value(paymentMethod),
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

  factory LocalSale.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSale(
      id: serializer.fromJson<String>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      clientSeq: serializer.fromJson<int>(json['clientSeq']),
      totalAmount: serializer.fromJson<int>(json['totalAmount']),
      paymentMethod: serializer.fromJson<String>(json['paymentMethod']),
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
      'status': serializer.toJson<String>(status),
      'cancelReason': serializer.toJson<String?>(cancelReason),
      'cancelledAt': serializer.toJson<DateTime?>(cancelledAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  LocalSale copyWith(
          {String? id,
          String? deviceId,
          int? clientSeq,
          int? totalAmount,
          String? paymentMethod,
          String? status,
          Value<String?> cancelReason = const Value.absent(),
          Value<DateTime?> cancelledAt = const Value.absent(),
          DateTime? createdAt}) =>
      LocalSale(
        id: id ?? this.id,
        deviceId: deviceId ?? this.deviceId,
        clientSeq: clientSeq ?? this.clientSeq,
        totalAmount: totalAmount ?? this.totalAmount,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        status: status ?? this.status,
        cancelReason:
            cancelReason.present ? cancelReason.value : this.cancelReason,
        cancelledAt: cancelledAt.present ? cancelledAt.value : this.cancelledAt,
        createdAt: createdAt ?? this.createdAt,
      );
  LocalSale copyWithCompanion(LocalSalesCompanion data) {
    return LocalSale(
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      clientSeq: data.clientSeq.present ? data.clientSeq.value : this.clientSeq,
      totalAmount:
          data.totalAmount.present ? data.totalAmount.value : this.totalAmount,
      paymentMethod: data.paymentMethod.present
          ? data.paymentMethod.value
          : this.paymentMethod,
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
    return (StringBuffer('LocalSale(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('clientSeq: $clientSeq, ')
          ..write('totalAmount: $totalAmount, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('status: $status, ')
          ..write('cancelReason: $cancelReason, ')
          ..write('cancelledAt: $cancelledAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, deviceId, clientSeq, totalAmount,
      paymentMethod, status, cancelReason, cancelledAt, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSale &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.clientSeq == this.clientSeq &&
          other.totalAmount == this.totalAmount &&
          other.paymentMethod == this.paymentMethod &&
          other.status == this.status &&
          other.cancelReason == this.cancelReason &&
          other.cancelledAt == this.cancelledAt &&
          other.createdAt == this.createdAt);
}

class LocalSalesCompanion extends UpdateCompanion<LocalSale> {
  final Value<String> id;
  final Value<String> deviceId;
  final Value<int> clientSeq;
  final Value<int> totalAmount;
  final Value<String> paymentMethod;
  final Value<String> status;
  final Value<String?> cancelReason;
  final Value<DateTime?> cancelledAt;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const LocalSalesCompanion({
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.clientSeq = const Value.absent(),
    this.totalAmount = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.status = const Value.absent(),
    this.cancelReason = const Value.absent(),
    this.cancelledAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSalesCompanion.insert({
    required String id,
    required String deviceId,
    required int clientSeq,
    required int totalAmount,
    required String paymentMethod,
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
  static Insertable<LocalSale> custom({
    Expression<String>? id,
    Expression<String>? deviceId,
    Expression<int>? clientSeq,
    Expression<int>? totalAmount,
    Expression<String>? paymentMethod,
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
      if (status != null) 'status': status,
      if (cancelReason != null) 'cancel_reason': cancelReason,
      if (cancelledAt != null) 'cancelled_at': cancelledAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSalesCompanion copyWith(
      {Value<String>? id,
      Value<String>? deviceId,
      Value<int>? clientSeq,
      Value<int>? totalAmount,
      Value<String>? paymentMethod,
      Value<String>? status,
      Value<String?>? cancelReason,
      Value<DateTime?>? cancelledAt,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return LocalSalesCompanion(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      clientSeq: clientSeq ?? this.clientSeq,
      totalAmount: totalAmount ?? this.totalAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
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
    return (StringBuffer('LocalSalesCompanion(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('clientSeq: $clientSeq, ')
          ..write('totalAmount: $totalAmount, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('status: $status, ')
          ..write('cancelReason: $cancelReason, ')
          ..write('cancelledAt: $cancelledAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalSaleItemsTable extends LocalSaleItems
    with TableInfo<$LocalSaleItemsTable, LocalSaleItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalSaleItemsTable(this.attachedDatabase, [this._alias]);
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
          GeneratedColumn.constraintIsAlways('REFERENCES local_sales (id)'));
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES local_products (id)'));
  static const VerificationMeta _productNameSnapshotMeta =
      const VerificationMeta('productNameSnapshot');
  @override
  late final GeneratedColumn<String> productNameSnapshot =
      GeneratedColumn<String>('product_name_snapshot', aliasedName, false,
          type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _unitSnapshotMeta =
      const VerificationMeta('unitSnapshot');
  @override
  late final GeneratedColumn<String> unitSnapshot = GeneratedColumn<String>(
      'unit_snapshot', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('adet'));
  static const VerificationMeta _priceVersionIdMeta =
      const VerificationMeta('priceVersionId');
  @override
  late final GeneratedColumn<String> priceVersionId = GeneratedColumn<String>(
      'price_version_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pv_init'));
  static const VerificationMeta _unitPriceMeta =
      const VerificationMeta('unitPrice');
  @override
  late final GeneratedColumn<int> unitPrice = GeneratedColumn<int>(
      'unit_price', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _quantityMeta =
      const VerificationMeta('quantity');
  @override
  late final GeneratedColumn<int> quantity = GeneratedColumn<int>(
      'quantity', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _totalPriceMeta =
      const VerificationMeta('totalPrice');
  @override
  late final GeneratedColumn<int> totalPrice = GeneratedColumn<int>(
      'total_price', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        saleId,
        productId,
        productNameSnapshot,
        unitSnapshot,
        priceVersionId,
        unitPrice,
        quantity,
        totalPrice
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_sale_items';
  @override
  VerificationContext validateIntegrity(Insertable<LocalSaleItem> instance,
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
    if (data.containsKey('product_name_snapshot')) {
      context.handle(
          _productNameSnapshotMeta,
          productNameSnapshot.isAcceptableOrUnknown(
              data['product_name_snapshot']!, _productNameSnapshotMeta));
    } else if (isInserting) {
      context.missing(_productNameSnapshotMeta);
    }
    if (data.containsKey('unit_snapshot')) {
      context.handle(
          _unitSnapshotMeta,
          unitSnapshot.isAcceptableOrUnknown(
              data['unit_snapshot']!, _unitSnapshotMeta));
    }
    if (data.containsKey('price_version_id')) {
      context.handle(
          _priceVersionIdMeta,
          priceVersionId.isAcceptableOrUnknown(
              data['price_version_id']!, _priceVersionIdMeta));
    }
    if (data.containsKey('unit_price')) {
      context.handle(_unitPriceMeta,
          unitPrice.isAcceptableOrUnknown(data['unit_price']!, _unitPriceMeta));
    } else if (isInserting) {
      context.missing(_unitPriceMeta);
    }
    if (data.containsKey('quantity')) {
      context.handle(_quantityMeta,
          quantity.isAcceptableOrUnknown(data['quantity']!, _quantityMeta));
    } else if (isInserting) {
      context.missing(_quantityMeta);
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
  LocalSaleItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalSaleItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      saleId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sale_id'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      productNameSnapshot: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}product_name_snapshot'])!,
      unitSnapshot: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}unit_snapshot'])!,
      priceVersionId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}price_version_id'])!,
      unitPrice: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}unit_price'])!,
      quantity: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}quantity'])!,
      totalPrice: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}total_price'])!,
    );
  }

  @override
  $LocalSaleItemsTable createAlias(String alias) {
    return $LocalSaleItemsTable(attachedDatabase, alias);
  }
}

class LocalSaleItem extends DataClass implements Insertable<LocalSaleItem> {
  final String id;
  final String saleId;
  final String productId;
  final String productNameSnapshot;
  final String unitSnapshot;
  final String priceVersionId;
  final int unitPrice;
  final int quantity;
  final int totalPrice;
  const LocalSaleItem(
      {required this.id,
      required this.saleId,
      required this.productId,
      required this.productNameSnapshot,
      required this.unitSnapshot,
      required this.priceVersionId,
      required this.unitPrice,
      required this.quantity,
      required this.totalPrice});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['sale_id'] = Variable<String>(saleId);
    map['product_id'] = Variable<String>(productId);
    map['product_name_snapshot'] = Variable<String>(productNameSnapshot);
    map['unit_snapshot'] = Variable<String>(unitSnapshot);
    map['price_version_id'] = Variable<String>(priceVersionId);
    map['unit_price'] = Variable<int>(unitPrice);
    map['quantity'] = Variable<int>(quantity);
    map['total_price'] = Variable<int>(totalPrice);
    return map;
  }

  LocalSaleItemsCompanion toCompanion(bool nullToAbsent) {
    return LocalSaleItemsCompanion(
      id: Value(id),
      saleId: Value(saleId),
      productId: Value(productId),
      productNameSnapshot: Value(productNameSnapshot),
      unitSnapshot: Value(unitSnapshot),
      priceVersionId: Value(priceVersionId),
      unitPrice: Value(unitPrice),
      quantity: Value(quantity),
      totalPrice: Value(totalPrice),
    );
  }

  factory LocalSaleItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalSaleItem(
      id: serializer.fromJson<String>(json['id']),
      saleId: serializer.fromJson<String>(json['saleId']),
      productId: serializer.fromJson<String>(json['productId']),
      productNameSnapshot:
          serializer.fromJson<String>(json['productNameSnapshot']),
      unitSnapshot: serializer.fromJson<String>(json['unitSnapshot']),
      priceVersionId: serializer.fromJson<String>(json['priceVersionId']),
      unitPrice: serializer.fromJson<int>(json['unitPrice']),
      quantity: serializer.fromJson<int>(json['quantity']),
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
      'productNameSnapshot': serializer.toJson<String>(productNameSnapshot),
      'unitSnapshot': serializer.toJson<String>(unitSnapshot),
      'priceVersionId': serializer.toJson<String>(priceVersionId),
      'unitPrice': serializer.toJson<int>(unitPrice),
      'quantity': serializer.toJson<int>(quantity),
      'totalPrice': serializer.toJson<int>(totalPrice),
    };
  }

  LocalSaleItem copyWith(
          {String? id,
          String? saleId,
          String? productId,
          String? productNameSnapshot,
          String? unitSnapshot,
          String? priceVersionId,
          int? unitPrice,
          int? quantity,
          int? totalPrice}) =>
      LocalSaleItem(
        id: id ?? this.id,
        saleId: saleId ?? this.saleId,
        productId: productId ?? this.productId,
        productNameSnapshot: productNameSnapshot ?? this.productNameSnapshot,
        unitSnapshot: unitSnapshot ?? this.unitSnapshot,
        priceVersionId: priceVersionId ?? this.priceVersionId,
        unitPrice: unitPrice ?? this.unitPrice,
        quantity: quantity ?? this.quantity,
        totalPrice: totalPrice ?? this.totalPrice,
      );
  LocalSaleItem copyWithCompanion(LocalSaleItemsCompanion data) {
    return LocalSaleItem(
      id: data.id.present ? data.id.value : this.id,
      saleId: data.saleId.present ? data.saleId.value : this.saleId,
      productId: data.productId.present ? data.productId.value : this.productId,
      productNameSnapshot: data.productNameSnapshot.present
          ? data.productNameSnapshot.value
          : this.productNameSnapshot,
      unitSnapshot: data.unitSnapshot.present
          ? data.unitSnapshot.value
          : this.unitSnapshot,
      priceVersionId: data.priceVersionId.present
          ? data.priceVersionId.value
          : this.priceVersionId,
      unitPrice: data.unitPrice.present ? data.unitPrice.value : this.unitPrice,
      quantity: data.quantity.present ? data.quantity.value : this.quantity,
      totalPrice:
          data.totalPrice.present ? data.totalPrice.value : this.totalPrice,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalSaleItem(')
          ..write('id: $id, ')
          ..write('saleId: $saleId, ')
          ..write('productId: $productId, ')
          ..write('productNameSnapshot: $productNameSnapshot, ')
          ..write('unitSnapshot: $unitSnapshot, ')
          ..write('priceVersionId: $priceVersionId, ')
          ..write('unitPrice: $unitPrice, ')
          ..write('quantity: $quantity, ')
          ..write('totalPrice: $totalPrice')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, saleId, productId, productNameSnapshot,
      unitSnapshot, priceVersionId, unitPrice, quantity, totalPrice);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalSaleItem &&
          other.id == this.id &&
          other.saleId == this.saleId &&
          other.productId == this.productId &&
          other.productNameSnapshot == this.productNameSnapshot &&
          other.unitSnapshot == this.unitSnapshot &&
          other.priceVersionId == this.priceVersionId &&
          other.unitPrice == this.unitPrice &&
          other.quantity == this.quantity &&
          other.totalPrice == this.totalPrice);
}

class LocalSaleItemsCompanion extends UpdateCompanion<LocalSaleItem> {
  final Value<String> id;
  final Value<String> saleId;
  final Value<String> productId;
  final Value<String> productNameSnapshot;
  final Value<String> unitSnapshot;
  final Value<String> priceVersionId;
  final Value<int> unitPrice;
  final Value<int> quantity;
  final Value<int> totalPrice;
  final Value<int> rowid;
  const LocalSaleItemsCompanion({
    this.id = const Value.absent(),
    this.saleId = const Value.absent(),
    this.productId = const Value.absent(),
    this.productNameSnapshot = const Value.absent(),
    this.unitSnapshot = const Value.absent(),
    this.priceVersionId = const Value.absent(),
    this.unitPrice = const Value.absent(),
    this.quantity = const Value.absent(),
    this.totalPrice = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalSaleItemsCompanion.insert({
    required String id,
    required String saleId,
    required String productId,
    required String productNameSnapshot,
    this.unitSnapshot = const Value.absent(),
    this.priceVersionId = const Value.absent(),
    required int unitPrice,
    required int quantity,
    required int totalPrice,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        saleId = Value(saleId),
        productId = Value(productId),
        productNameSnapshot = Value(productNameSnapshot),
        unitPrice = Value(unitPrice),
        quantity = Value(quantity),
        totalPrice = Value(totalPrice);
  static Insertable<LocalSaleItem> custom({
    Expression<String>? id,
    Expression<String>? saleId,
    Expression<String>? productId,
    Expression<String>? productNameSnapshot,
    Expression<String>? unitSnapshot,
    Expression<String>? priceVersionId,
    Expression<int>? unitPrice,
    Expression<int>? quantity,
    Expression<int>? totalPrice,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (saleId != null) 'sale_id': saleId,
      if (productId != null) 'product_id': productId,
      if (productNameSnapshot != null)
        'product_name_snapshot': productNameSnapshot,
      if (unitSnapshot != null) 'unit_snapshot': unitSnapshot,
      if (priceVersionId != null) 'price_version_id': priceVersionId,
      if (unitPrice != null) 'unit_price': unitPrice,
      if (quantity != null) 'quantity': quantity,
      if (totalPrice != null) 'total_price': totalPrice,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalSaleItemsCompanion copyWith(
      {Value<String>? id,
      Value<String>? saleId,
      Value<String>? productId,
      Value<String>? productNameSnapshot,
      Value<String>? unitSnapshot,
      Value<String>? priceVersionId,
      Value<int>? unitPrice,
      Value<int>? quantity,
      Value<int>? totalPrice,
      Value<int>? rowid}) {
    return LocalSaleItemsCompanion(
      id: id ?? this.id,
      saleId: saleId ?? this.saleId,
      productId: productId ?? this.productId,
      productNameSnapshot: productNameSnapshot ?? this.productNameSnapshot,
      unitSnapshot: unitSnapshot ?? this.unitSnapshot,
      priceVersionId: priceVersionId ?? this.priceVersionId,
      unitPrice: unitPrice ?? this.unitPrice,
      quantity: quantity ?? this.quantity,
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
    if (productNameSnapshot.present) {
      map['product_name_snapshot'] =
          Variable<String>(productNameSnapshot.value);
    }
    if (unitSnapshot.present) {
      map['unit_snapshot'] = Variable<String>(unitSnapshot.value);
    }
    if (priceVersionId.present) {
      map['price_version_id'] = Variable<String>(priceVersionId.value);
    }
    if (unitPrice.present) {
      map['unit_price'] = Variable<int>(unitPrice.value);
    }
    if (quantity.present) {
      map['quantity'] = Variable<int>(quantity.value);
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
    return (StringBuffer('LocalSaleItemsCompanion(')
          ..write('id: $id, ')
          ..write('saleId: $saleId, ')
          ..write('productId: $productId, ')
          ..write('productNameSnapshot: $productNameSnapshot, ')
          ..write('unitSnapshot: $unitSnapshot, ')
          ..write('priceVersionId: $priceVersionId, ')
          ..write('unitPrice: $unitPrice, ')
          ..write('quantity: $quantity, ')
          ..write('totalPrice: $totalPrice, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalStockMovementsTable extends LocalStockMovements
    with TableInfo<$LocalStockMovementsTable, LocalStockMovement> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalStockMovementsTable(this.attachedDatabase, [this._alias]);
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
          GeneratedColumn.constraintIsAlways('REFERENCES local_products (id)'));
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
  static const String $name = 'local_stock_movements';
  @override
  VerificationContext validateIntegrity(Insertable<LocalStockMovement> instance,
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
  LocalStockMovement map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalStockMovement(
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
  $LocalStockMovementsTable createAlias(String alias) {
    return $LocalStockMovementsTable(attachedDatabase, alias);
  }
}

class LocalStockMovement extends DataClass
    implements Insertable<LocalStockMovement> {
  final String id;
  final String productId;
  final int quantity;
  final String unit;
  final String movementType;
  final String referenceId;
  final int? purchasePrice;
  final String? note;
  final DateTime createdAt;
  const LocalStockMovement(
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

  LocalStockMovementsCompanion toCompanion(bool nullToAbsent) {
    return LocalStockMovementsCompanion(
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

  factory LocalStockMovement.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalStockMovement(
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

  LocalStockMovement copyWith(
          {String? id,
          String? productId,
          int? quantity,
          String? unit,
          String? movementType,
          String? referenceId,
          Value<int?> purchasePrice = const Value.absent(),
          Value<String?> note = const Value.absent(),
          DateTime? createdAt}) =>
      LocalStockMovement(
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
  LocalStockMovement copyWithCompanion(LocalStockMovementsCompanion data) {
    return LocalStockMovement(
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
    return (StringBuffer('LocalStockMovement(')
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
      (other is LocalStockMovement &&
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

class LocalStockMovementsCompanion extends UpdateCompanion<LocalStockMovement> {
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
  const LocalStockMovementsCompanion({
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
  LocalStockMovementsCompanion.insert({
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
  static Insertable<LocalStockMovement> custom({
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

  LocalStockMovementsCompanion copyWith(
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
    return LocalStockMovementsCompanion(
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
    return (StringBuffer('LocalStockMovementsCompanion(')
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

class $LocalRefundsTable extends LocalRefunds
    with TableInfo<$LocalRefundsTable, LocalRefund> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalRefundsTable(this.attachedDatabase, [this._alias]);
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
          GeneratedColumn.constraintIsAlways('REFERENCES local_sales (id)'));
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
  static const String $name = 'local_refunds';
  @override
  VerificationContext validateIntegrity(Insertable<LocalRefund> instance,
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
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {deviceId, clientSeq},
      ];
  @override
  LocalRefund map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalRefund(
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
  $LocalRefundsTable createAlias(String alias) {
    return $LocalRefundsTable(attachedDatabase, alias);
  }
}

class LocalRefund extends DataClass implements Insertable<LocalRefund> {
  final String id;
  final String saleId;
  final String deviceId;
  final int clientSeq;
  final int totalRefundAmount;
  final String paymentMethod;
  final String reason;
  final DateTime createdAt;
  const LocalRefund(
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

  LocalRefundsCompanion toCompanion(bool nullToAbsent) {
    return LocalRefundsCompanion(
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

  factory LocalRefund.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalRefund(
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

  LocalRefund copyWith(
          {String? id,
          String? saleId,
          String? deviceId,
          int? clientSeq,
          int? totalRefundAmount,
          String? paymentMethod,
          String? reason,
          DateTime? createdAt}) =>
      LocalRefund(
        id: id ?? this.id,
        saleId: saleId ?? this.saleId,
        deviceId: deviceId ?? this.deviceId,
        clientSeq: clientSeq ?? this.clientSeq,
        totalRefundAmount: totalRefundAmount ?? this.totalRefundAmount,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        reason: reason ?? this.reason,
        createdAt: createdAt ?? this.createdAt,
      );
  LocalRefund copyWithCompanion(LocalRefundsCompanion data) {
    return LocalRefund(
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
    return (StringBuffer('LocalRefund(')
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
      (other is LocalRefund &&
          other.id == this.id &&
          other.saleId == this.saleId &&
          other.deviceId == this.deviceId &&
          other.clientSeq == this.clientSeq &&
          other.totalRefundAmount == this.totalRefundAmount &&
          other.paymentMethod == this.paymentMethod &&
          other.reason == this.reason &&
          other.createdAt == this.createdAt);
}

class LocalRefundsCompanion extends UpdateCompanion<LocalRefund> {
  final Value<String> id;
  final Value<String> saleId;
  final Value<String> deviceId;
  final Value<int> clientSeq;
  final Value<int> totalRefundAmount;
  final Value<String> paymentMethod;
  final Value<String> reason;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const LocalRefundsCompanion({
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
  LocalRefundsCompanion.insert({
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
  static Insertable<LocalRefund> custom({
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

  LocalRefundsCompanion copyWith(
      {Value<String>? id,
      Value<String>? saleId,
      Value<String>? deviceId,
      Value<int>? clientSeq,
      Value<int>? totalRefundAmount,
      Value<String>? paymentMethod,
      Value<String>? reason,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return LocalRefundsCompanion(
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
    return (StringBuffer('LocalRefundsCompanion(')
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

class $LocalRefundItemsTable extends LocalRefundItems
    with TableInfo<$LocalRefundItemsTable, LocalRefundItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalRefundItemsTable(this.attachedDatabase, [this._alias]);
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
          GeneratedColumn.constraintIsAlways('REFERENCES local_refunds (id)'));
  static const VerificationMeta _saleItemIdMeta =
      const VerificationMeta('saleItemId');
  @override
  late final GeneratedColumn<String> saleItemId = GeneratedColumn<String>(
      'sale_item_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES local_sale_items (id)'));
  static const VerificationMeta _productIdMeta =
      const VerificationMeta('productId');
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
      'product_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES local_products (id)'));
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
  static const String $name = 'local_refund_items';
  @override
  VerificationContext validateIntegrity(Insertable<LocalRefundItem> instance,
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
    } else if (isInserting) {
      context.missing(_saleItemIdMeta);
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
  LocalRefundItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalRefundItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      refundId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}refund_id'])!,
      saleItemId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sale_item_id'])!,
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
  $LocalRefundItemsTable createAlias(String alias) {
    return $LocalRefundItemsTable(attachedDatabase, alias);
  }
}

class LocalRefundItem extends DataClass implements Insertable<LocalRefundItem> {
  final String id;
  final String refundId;
  final String saleItemId;
  final String productId;
  final int quantity;
  final int unitPrice;
  final int refundAmount;
  final String productCondition;
  final DateTime createdAt;
  const LocalRefundItem(
      {required this.id,
      required this.refundId,
      required this.saleItemId,
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
    map['sale_item_id'] = Variable<String>(saleItemId);
    map['product_id'] = Variable<String>(productId);
    map['quantity'] = Variable<int>(quantity);
    map['unit_price'] = Variable<int>(unitPrice);
    map['refund_amount'] = Variable<int>(refundAmount);
    map['product_condition'] = Variable<String>(productCondition);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  LocalRefundItemsCompanion toCompanion(bool nullToAbsent) {
    return LocalRefundItemsCompanion(
      id: Value(id),
      refundId: Value(refundId),
      saleItemId: Value(saleItemId),
      productId: Value(productId),
      quantity: Value(quantity),
      unitPrice: Value(unitPrice),
      refundAmount: Value(refundAmount),
      productCondition: Value(productCondition),
      createdAt: Value(createdAt),
    );
  }

  factory LocalRefundItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalRefundItem(
      id: serializer.fromJson<String>(json['id']),
      refundId: serializer.fromJson<String>(json['refundId']),
      saleItemId: serializer.fromJson<String>(json['saleItemId']),
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
      'saleItemId': serializer.toJson<String>(saleItemId),
      'productId': serializer.toJson<String>(productId),
      'quantity': serializer.toJson<int>(quantity),
      'unitPrice': serializer.toJson<int>(unitPrice),
      'refundAmount': serializer.toJson<int>(refundAmount),
      'productCondition': serializer.toJson<String>(productCondition),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  LocalRefundItem copyWith(
          {String? id,
          String? refundId,
          String? saleItemId,
          String? productId,
          int? quantity,
          int? unitPrice,
          int? refundAmount,
          String? productCondition,
          DateTime? createdAt}) =>
      LocalRefundItem(
        id: id ?? this.id,
        refundId: refundId ?? this.refundId,
        saleItemId: saleItemId ?? this.saleItemId,
        productId: productId ?? this.productId,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        refundAmount: refundAmount ?? this.refundAmount,
        productCondition: productCondition ?? this.productCondition,
        createdAt: createdAt ?? this.createdAt,
      );
  LocalRefundItem copyWithCompanion(LocalRefundItemsCompanion data) {
    return LocalRefundItem(
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
    return (StringBuffer('LocalRefundItem(')
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
      (other is LocalRefundItem &&
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

class LocalRefundItemsCompanion extends UpdateCompanion<LocalRefundItem> {
  final Value<String> id;
  final Value<String> refundId;
  final Value<String> saleItemId;
  final Value<String> productId;
  final Value<int> quantity;
  final Value<int> unitPrice;
  final Value<int> refundAmount;
  final Value<String> productCondition;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const LocalRefundItemsCompanion({
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
  LocalRefundItemsCompanion.insert({
    required String id,
    required String refundId,
    required String saleItemId,
    required String productId,
    required int quantity,
    required int unitPrice,
    required int refundAmount,
    this.productCondition = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        refundId = Value(refundId),
        saleItemId = Value(saleItemId),
        productId = Value(productId),
        quantity = Value(quantity),
        unitPrice = Value(unitPrice),
        refundAmount = Value(refundAmount);
  static Insertable<LocalRefundItem> custom({
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

  LocalRefundItemsCompanion copyWith(
      {Value<String>? id,
      Value<String>? refundId,
      Value<String>? saleItemId,
      Value<String>? productId,
      Value<int>? quantity,
      Value<int>? unitPrice,
      Value<int>? refundAmount,
      Value<String>? productCondition,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return LocalRefundItemsCompanion(
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
    return (StringBuffer('LocalRefundItemsCompanion(')
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

class $LocalPriceHistoryTable extends LocalPriceHistory
    with TableInfo<$LocalPriceHistoryTable, LocalPriceHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalPriceHistoryTable(this.attachedDatabase, [this._alias]);
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
          GeneratedColumn.constraintIsAlways('REFERENCES local_products (id)'));
  static const VerificationMeta _oldPriceMeta =
      const VerificationMeta('oldPrice');
  @override
  late final GeneratedColumn<int> oldPrice = GeneratedColumn<int>(
      'old_price', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _newPriceMeta =
      const VerificationMeta('newPrice');
  @override
  late final GeneratedColumn<int> newPrice = GeneratedColumn<int>(
      'new_price', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _priceVersionIdMeta =
      const VerificationMeta('priceVersionId');
  @override
  late final GeneratedColumn<String> priceVersionId = GeneratedColumn<String>(
      'price_version_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
      'source', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('MANUAL_UI'));
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
      'reason', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _changedAtMeta =
      const VerificationMeta('changedAt');
  @override
  late final GeneratedColumn<DateTime> changedAt = GeneratedColumn<DateTime>(
      'changed_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      defaultValue: currentDateAndTime);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        productId,
        oldPrice,
        newPrice,
        priceVersionId,
        source,
        reason,
        changedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_price_history';
  @override
  VerificationContext validateIntegrity(
      Insertable<LocalPriceHistoryData> instance,
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
    if (data.containsKey('old_price')) {
      context.handle(_oldPriceMeta,
          oldPrice.isAcceptableOrUnknown(data['old_price']!, _oldPriceMeta));
    } else if (isInserting) {
      context.missing(_oldPriceMeta);
    }
    if (data.containsKey('new_price')) {
      context.handle(_newPriceMeta,
          newPrice.isAcceptableOrUnknown(data['new_price']!, _newPriceMeta));
    } else if (isInserting) {
      context.missing(_newPriceMeta);
    }
    if (data.containsKey('price_version_id')) {
      context.handle(
          _priceVersionIdMeta,
          priceVersionId.isAcceptableOrUnknown(
              data['price_version_id']!, _priceVersionIdMeta));
    } else if (isInserting) {
      context.missing(_priceVersionIdMeta);
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta,
          source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    }
    if (data.containsKey('reason')) {
      context.handle(_reasonMeta,
          reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta));
    }
    if (data.containsKey('changed_at')) {
      context.handle(_changedAtMeta,
          changedAt.isAcceptableOrUnknown(data['changed_at']!, _changedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalPriceHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalPriceHistoryData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      productId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}product_id'])!,
      oldPrice: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}old_price'])!,
      newPrice: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}new_price'])!,
      priceVersionId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}price_version_id'])!,
      source: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source'])!,
      reason: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reason']),
      changedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}changed_at'])!,
    );
  }

  @override
  $LocalPriceHistoryTable createAlias(String alias) {
    return $LocalPriceHistoryTable(attachedDatabase, alias);
  }
}

class LocalPriceHistoryData extends DataClass
    implements Insertable<LocalPriceHistoryData> {
  final String id;
  final String productId;
  final int oldPrice;
  final int newPrice;
  final String priceVersionId;
  final String source;
  final String? reason;
  final DateTime changedAt;
  const LocalPriceHistoryData(
      {required this.id,
      required this.productId,
      required this.oldPrice,
      required this.newPrice,
      required this.priceVersionId,
      required this.source,
      this.reason,
      required this.changedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['product_id'] = Variable<String>(productId);
    map['old_price'] = Variable<int>(oldPrice);
    map['new_price'] = Variable<int>(newPrice);
    map['price_version_id'] = Variable<String>(priceVersionId);
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || reason != null) {
      map['reason'] = Variable<String>(reason);
    }
    map['changed_at'] = Variable<DateTime>(changedAt);
    return map;
  }

  LocalPriceHistoryCompanion toCompanion(bool nullToAbsent) {
    return LocalPriceHistoryCompanion(
      id: Value(id),
      productId: Value(productId),
      oldPrice: Value(oldPrice),
      newPrice: Value(newPrice),
      priceVersionId: Value(priceVersionId),
      source: Value(source),
      reason:
          reason == null && nullToAbsent ? const Value.absent() : Value(reason),
      changedAt: Value(changedAt),
    );
  }

  factory LocalPriceHistoryData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalPriceHistoryData(
      id: serializer.fromJson<String>(json['id']),
      productId: serializer.fromJson<String>(json['productId']),
      oldPrice: serializer.fromJson<int>(json['oldPrice']),
      newPrice: serializer.fromJson<int>(json['newPrice']),
      priceVersionId: serializer.fromJson<String>(json['priceVersionId']),
      source: serializer.fromJson<String>(json['source']),
      reason: serializer.fromJson<String?>(json['reason']),
      changedAt: serializer.fromJson<DateTime>(json['changedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'productId': serializer.toJson<String>(productId),
      'oldPrice': serializer.toJson<int>(oldPrice),
      'newPrice': serializer.toJson<int>(newPrice),
      'priceVersionId': serializer.toJson<String>(priceVersionId),
      'source': serializer.toJson<String>(source),
      'reason': serializer.toJson<String?>(reason),
      'changedAt': serializer.toJson<DateTime>(changedAt),
    };
  }

  LocalPriceHistoryData copyWith(
          {String? id,
          String? productId,
          int? oldPrice,
          int? newPrice,
          String? priceVersionId,
          String? source,
          Value<String?> reason = const Value.absent(),
          DateTime? changedAt}) =>
      LocalPriceHistoryData(
        id: id ?? this.id,
        productId: productId ?? this.productId,
        oldPrice: oldPrice ?? this.oldPrice,
        newPrice: newPrice ?? this.newPrice,
        priceVersionId: priceVersionId ?? this.priceVersionId,
        source: source ?? this.source,
        reason: reason.present ? reason.value : this.reason,
        changedAt: changedAt ?? this.changedAt,
      );
  LocalPriceHistoryData copyWithCompanion(LocalPriceHistoryCompanion data) {
    return LocalPriceHistoryData(
      id: data.id.present ? data.id.value : this.id,
      productId: data.productId.present ? data.productId.value : this.productId,
      oldPrice: data.oldPrice.present ? data.oldPrice.value : this.oldPrice,
      newPrice: data.newPrice.present ? data.newPrice.value : this.newPrice,
      priceVersionId: data.priceVersionId.present
          ? data.priceVersionId.value
          : this.priceVersionId,
      source: data.source.present ? data.source.value : this.source,
      reason: data.reason.present ? data.reason.value : this.reason,
      changedAt: data.changedAt.present ? data.changedAt.value : this.changedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalPriceHistoryData(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('oldPrice: $oldPrice, ')
          ..write('newPrice: $newPrice, ')
          ..write('priceVersionId: $priceVersionId, ')
          ..write('source: $source, ')
          ..write('reason: $reason, ')
          ..write('changedAt: $changedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, productId, oldPrice, newPrice,
      priceVersionId, source, reason, changedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalPriceHistoryData &&
          other.id == this.id &&
          other.productId == this.productId &&
          other.oldPrice == this.oldPrice &&
          other.newPrice == this.newPrice &&
          other.priceVersionId == this.priceVersionId &&
          other.source == this.source &&
          other.reason == this.reason &&
          other.changedAt == this.changedAt);
}

class LocalPriceHistoryCompanion
    extends UpdateCompanion<LocalPriceHistoryData> {
  final Value<String> id;
  final Value<String> productId;
  final Value<int> oldPrice;
  final Value<int> newPrice;
  final Value<String> priceVersionId;
  final Value<String> source;
  final Value<String?> reason;
  final Value<DateTime> changedAt;
  final Value<int> rowid;
  const LocalPriceHistoryCompanion({
    this.id = const Value.absent(),
    this.productId = const Value.absent(),
    this.oldPrice = const Value.absent(),
    this.newPrice = const Value.absent(),
    this.priceVersionId = const Value.absent(),
    this.source = const Value.absent(),
    this.reason = const Value.absent(),
    this.changedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalPriceHistoryCompanion.insert({
    required String id,
    required String productId,
    required int oldPrice,
    required int newPrice,
    required String priceVersionId,
    this.source = const Value.absent(),
    this.reason = const Value.absent(),
    this.changedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        productId = Value(productId),
        oldPrice = Value(oldPrice),
        newPrice = Value(newPrice),
        priceVersionId = Value(priceVersionId);
  static Insertable<LocalPriceHistoryData> custom({
    Expression<String>? id,
    Expression<String>? productId,
    Expression<int>? oldPrice,
    Expression<int>? newPrice,
    Expression<String>? priceVersionId,
    Expression<String>? source,
    Expression<String>? reason,
    Expression<DateTime>? changedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (productId != null) 'product_id': productId,
      if (oldPrice != null) 'old_price': oldPrice,
      if (newPrice != null) 'new_price': newPrice,
      if (priceVersionId != null) 'price_version_id': priceVersionId,
      if (source != null) 'source': source,
      if (reason != null) 'reason': reason,
      if (changedAt != null) 'changed_at': changedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalPriceHistoryCompanion copyWith(
      {Value<String>? id,
      Value<String>? productId,
      Value<int>? oldPrice,
      Value<int>? newPrice,
      Value<String>? priceVersionId,
      Value<String>? source,
      Value<String?>? reason,
      Value<DateTime>? changedAt,
      Value<int>? rowid}) {
    return LocalPriceHistoryCompanion(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      oldPrice: oldPrice ?? this.oldPrice,
      newPrice: newPrice ?? this.newPrice,
      priceVersionId: priceVersionId ?? this.priceVersionId,
      source: source ?? this.source,
      reason: reason ?? this.reason,
      changedAt: changedAt ?? this.changedAt,
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
    if (oldPrice.present) {
      map['old_price'] = Variable<int>(oldPrice.value);
    }
    if (newPrice.present) {
      map['new_price'] = Variable<int>(newPrice.value);
    }
    if (priceVersionId.present) {
      map['price_version_id'] = Variable<String>(priceVersionId.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (changedAt.present) {
      map['changed_at'] = Variable<DateTime>(changedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalPriceHistoryCompanion(')
          ..write('id: $id, ')
          ..write('productId: $productId, ')
          ..write('oldPrice: $oldPrice, ')
          ..write('newPrice: $newPrice, ')
          ..write('priceVersionId: $priceVersionId, ')
          ..write('source: $source, ')
          ..write('reason: $reason, ')
          ..write('changedAt: $changedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxOperationsTable extends OutboxOperations
    with TableInfo<$OutboxOperationsTable, OutboxOperation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxOperationsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _clientSeqMeta =
      const VerificationMeta('clientSeq');
  @override
  late final GeneratedColumn<int> clientSeq = GeneratedColumn<int>(
      'client_seq', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _operationTypeMeta =
      const VerificationMeta('operationType');
  @override
  late final GeneratedColumn<String> operationType = GeneratedColumn<String>(
      'operation_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _payloadHashMeta =
      const VerificationMeta('payloadHash');
  @override
  late final GeneratedColumn<String> payloadHash = GeneratedColumn<String>(
      'payload_hash', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _occurredAtMeta =
      const VerificationMeta('occurredAt');
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
      'occurred_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('PENDING'));
  static const VerificationMeta _attemptCountMeta =
      const VerificationMeta('attemptCount');
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
      'attempt_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _nextRetryAtMeta =
      const VerificationMeta('nextRetryAt');
  @override
  late final GeneratedColumn<DateTime> nextRetryAt = GeneratedColumn<DateTime>(
      'next_retry_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _lastErrorMeta =
      const VerificationMeta('lastError');
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
      'last_error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
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
        operationId,
        deviceId,
        clientSeq,
        operationType,
        payload,
        payloadHash,
        occurredAt,
        status,
        attemptCount,
        nextRetryAt,
        lastError,
        acknowledgedAt,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_operations';
  @override
  VerificationContext validateIntegrity(Insertable<OutboxOperation> instance,
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
    if (data.containsKey('client_seq')) {
      context.handle(_clientSeqMeta,
          clientSeq.isAcceptableOrUnknown(data['client_seq']!, _clientSeqMeta));
    } else if (isInserting) {
      context.missing(_clientSeqMeta);
    }
    if (data.containsKey('operation_type')) {
      context.handle(
          _operationTypeMeta,
          operationType.isAcceptableOrUnknown(
              data['operation_type']!, _operationTypeMeta));
    } else if (isInserting) {
      context.missing(_operationTypeMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('payload_hash')) {
      context.handle(
          _payloadHashMeta,
          payloadHash.isAcceptableOrUnknown(
              data['payload_hash']!, _payloadHashMeta));
    } else if (isInserting) {
      context.missing(_payloadHashMeta);
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
          _occurredAtMeta,
          occurredAt.isAcceptableOrUnknown(
              data['occurred_at']!, _occurredAtMeta));
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
          _attemptCountMeta,
          attemptCount.isAcceptableOrUnknown(
              data['attempt_count']!, _attemptCountMeta));
    }
    if (data.containsKey('next_retry_at')) {
      context.handle(
          _nextRetryAtMeta,
          nextRetryAt.isAcceptableOrUnknown(
              data['next_retry_at']!, _nextRetryAtMeta));
    }
    if (data.containsKey('last_error')) {
      context.handle(_lastErrorMeta,
          lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta));
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
  Set<GeneratedColumn> get $primaryKey => {operationId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {deviceId, clientSeq},
      ];
  @override
  OutboxOperation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxOperation(
      operationId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}operation_id'])!,
      deviceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_id'])!,
      clientSeq: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}client_seq'])!,
      operationType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}operation_type'])!,
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      payloadHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload_hash'])!,
      occurredAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}occurred_at'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      attemptCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}attempt_count'])!,
      nextRetryAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}next_retry_at']),
      lastError: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_error']),
      acknowledgedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}acknowledged_at']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $OutboxOperationsTable createAlias(String alias) {
    return $OutboxOperationsTable(attachedDatabase, alias);
  }
}

class OutboxOperation extends DataClass implements Insertable<OutboxOperation> {
  final String operationId;
  final String deviceId;
  final int clientSeq;
  final String operationType;
  final String payload;
  final String payloadHash;
  final DateTime occurredAt;
  final String status;
  final int attemptCount;
  final DateTime? nextRetryAt;
  final String? lastError;
  final DateTime? acknowledgedAt;
  final DateTime createdAt;
  const OutboxOperation(
      {required this.operationId,
      required this.deviceId,
      required this.clientSeq,
      required this.operationType,
      required this.payload,
      required this.payloadHash,
      required this.occurredAt,
      required this.status,
      required this.attemptCount,
      this.nextRetryAt,
      this.lastError,
      this.acknowledgedAt,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['operation_id'] = Variable<String>(operationId);
    map['device_id'] = Variable<String>(deviceId);
    map['client_seq'] = Variable<int>(clientSeq);
    map['operation_type'] = Variable<String>(operationType);
    map['payload'] = Variable<String>(payload);
    map['payload_hash'] = Variable<String>(payloadHash);
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    map['status'] = Variable<String>(status);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || nextRetryAt != null) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || acknowledgedAt != null) {
      map['acknowledged_at'] = Variable<DateTime>(acknowledgedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  OutboxOperationsCompanion toCompanion(bool nullToAbsent) {
    return OutboxOperationsCompanion(
      operationId: Value(operationId),
      deviceId: Value(deviceId),
      clientSeq: Value(clientSeq),
      operationType: Value(operationType),
      payload: Value(payload),
      payloadHash: Value(payloadHash),
      occurredAt: Value(occurredAt),
      status: Value(status),
      attemptCount: Value(attemptCount),
      nextRetryAt: nextRetryAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextRetryAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      acknowledgedAt: acknowledgedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(acknowledgedAt),
      createdAt: Value(createdAt),
    );
  }

  factory OutboxOperation.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxOperation(
      operationId: serializer.fromJson<String>(json['operationId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      clientSeq: serializer.fromJson<int>(json['clientSeq']),
      operationType: serializer.fromJson<String>(json['operationType']),
      payload: serializer.fromJson<String>(json['payload']),
      payloadHash: serializer.fromJson<String>(json['payloadHash']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
      status: serializer.fromJson<String>(json['status']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextRetryAt: serializer.fromJson<DateTime?>(json['nextRetryAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      acknowledgedAt: serializer.fromJson<DateTime?>(json['acknowledgedAt']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'operationId': serializer.toJson<String>(operationId),
      'deviceId': serializer.toJson<String>(deviceId),
      'clientSeq': serializer.toJson<int>(clientSeq),
      'operationType': serializer.toJson<String>(operationType),
      'payload': serializer.toJson<String>(payload),
      'payloadHash': serializer.toJson<String>(payloadHash),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
      'status': serializer.toJson<String>(status),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextRetryAt': serializer.toJson<DateTime?>(nextRetryAt),
      'lastError': serializer.toJson<String?>(lastError),
      'acknowledgedAt': serializer.toJson<DateTime?>(acknowledgedAt),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  OutboxOperation copyWith(
          {String? operationId,
          String? deviceId,
          int? clientSeq,
          String? operationType,
          String? payload,
          String? payloadHash,
          DateTime? occurredAt,
          String? status,
          int? attemptCount,
          Value<DateTime?> nextRetryAt = const Value.absent(),
          Value<String?> lastError = const Value.absent(),
          Value<DateTime?> acknowledgedAt = const Value.absent(),
          DateTime? createdAt}) =>
      OutboxOperation(
        operationId: operationId ?? this.operationId,
        deviceId: deviceId ?? this.deviceId,
        clientSeq: clientSeq ?? this.clientSeq,
        operationType: operationType ?? this.operationType,
        payload: payload ?? this.payload,
        payloadHash: payloadHash ?? this.payloadHash,
        occurredAt: occurredAt ?? this.occurredAt,
        status: status ?? this.status,
        attemptCount: attemptCount ?? this.attemptCount,
        nextRetryAt: nextRetryAt.present ? nextRetryAt.value : this.nextRetryAt,
        lastError: lastError.present ? lastError.value : this.lastError,
        acknowledgedAt:
            acknowledgedAt.present ? acknowledgedAt.value : this.acknowledgedAt,
        createdAt: createdAt ?? this.createdAt,
      );
  OutboxOperation copyWithCompanion(OutboxOperationsCompanion data) {
    return OutboxOperation(
      operationId:
          data.operationId.present ? data.operationId.value : this.operationId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      clientSeq: data.clientSeq.present ? data.clientSeq.value : this.clientSeq,
      operationType: data.operationType.present
          ? data.operationType.value
          : this.operationType,
      payload: data.payload.present ? data.payload.value : this.payload,
      payloadHash:
          data.payloadHash.present ? data.payloadHash.value : this.payloadHash,
      occurredAt:
          data.occurredAt.present ? data.occurredAt.value : this.occurredAt,
      status: data.status.present ? data.status.value : this.status,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextRetryAt:
          data.nextRetryAt.present ? data.nextRetryAt.value : this.nextRetryAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      acknowledgedAt: data.acknowledgedAt.present
          ? data.acknowledgedAt.value
          : this.acknowledgedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxOperation(')
          ..write('operationId: $operationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('clientSeq: $clientSeq, ')
          ..write('operationType: $operationType, ')
          ..write('payload: $payload, ')
          ..write('payloadHash: $payloadHash, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('lastError: $lastError, ')
          ..write('acknowledgedAt: $acknowledgedAt, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      operationId,
      deviceId,
      clientSeq,
      operationType,
      payload,
      payloadHash,
      occurredAt,
      status,
      attemptCount,
      nextRetryAt,
      lastError,
      acknowledgedAt,
      createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxOperation &&
          other.operationId == this.operationId &&
          other.deviceId == this.deviceId &&
          other.clientSeq == this.clientSeq &&
          other.operationType == this.operationType &&
          other.payload == this.payload &&
          other.payloadHash == this.payloadHash &&
          other.occurredAt == this.occurredAt &&
          other.status == this.status &&
          other.attemptCount == this.attemptCount &&
          other.nextRetryAt == this.nextRetryAt &&
          other.lastError == this.lastError &&
          other.acknowledgedAt == this.acknowledgedAt &&
          other.createdAt == this.createdAt);
}

class OutboxOperationsCompanion extends UpdateCompanion<OutboxOperation> {
  final Value<String> operationId;
  final Value<String> deviceId;
  final Value<int> clientSeq;
  final Value<String> operationType;
  final Value<String> payload;
  final Value<String> payloadHash;
  final Value<DateTime> occurredAt;
  final Value<String> status;
  final Value<int> attemptCount;
  final Value<DateTime?> nextRetryAt;
  final Value<String?> lastError;
  final Value<DateTime?> acknowledgedAt;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const OutboxOperationsCompanion({
    this.operationId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.clientSeq = const Value.absent(),
    this.operationType = const Value.absent(),
    this.payload = const Value.absent(),
    this.payloadHash = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.status = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.acknowledgedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxOperationsCompanion.insert({
    required String operationId,
    required String deviceId,
    required int clientSeq,
    required String operationType,
    required String payload,
    required String payloadHash,
    required DateTime occurredAt,
    this.status = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.acknowledgedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : operationId = Value(operationId),
        deviceId = Value(deviceId),
        clientSeq = Value(clientSeq),
        operationType = Value(operationType),
        payload = Value(payload),
        payloadHash = Value(payloadHash),
        occurredAt = Value(occurredAt);
  static Insertable<OutboxOperation> custom({
    Expression<String>? operationId,
    Expression<String>? deviceId,
    Expression<int>? clientSeq,
    Expression<String>? operationType,
    Expression<String>? payload,
    Expression<String>? payloadHash,
    Expression<DateTime>? occurredAt,
    Expression<String>? status,
    Expression<int>? attemptCount,
    Expression<DateTime>? nextRetryAt,
    Expression<String>? lastError,
    Expression<DateTime>? acknowledgedAt,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (operationId != null) 'operation_id': operationId,
      if (deviceId != null) 'device_id': deviceId,
      if (clientSeq != null) 'client_seq': clientSeq,
      if (operationType != null) 'operation_type': operationType,
      if (payload != null) 'payload': payload,
      if (payloadHash != null) 'payload_hash': payloadHash,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (status != null) 'status': status,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextRetryAt != null) 'next_retry_at': nextRetryAt,
      if (lastError != null) 'last_error': lastError,
      if (acknowledgedAt != null) 'acknowledged_at': acknowledgedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxOperationsCompanion copyWith(
      {Value<String>? operationId,
      Value<String>? deviceId,
      Value<int>? clientSeq,
      Value<String>? operationType,
      Value<String>? payload,
      Value<String>? payloadHash,
      Value<DateTime>? occurredAt,
      Value<String>? status,
      Value<int>? attemptCount,
      Value<DateTime?>? nextRetryAt,
      Value<String?>? lastError,
      Value<DateTime?>? acknowledgedAt,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return OutboxOperationsCompanion(
      operationId: operationId ?? this.operationId,
      deviceId: deviceId ?? this.deviceId,
      clientSeq: clientSeq ?? this.clientSeq,
      operationType: operationType ?? this.operationType,
      payload: payload ?? this.payload,
      payloadHash: payloadHash ?? this.payloadHash,
      occurredAt: occurredAt ?? this.occurredAt,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      lastError: lastError ?? this.lastError,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      createdAt: createdAt ?? this.createdAt,
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
    if (clientSeq.present) {
      map['client_seq'] = Variable<int>(clientSeq.value);
    }
    if (operationType.present) {
      map['operation_type'] = Variable<String>(operationType.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (payloadHash.present) {
      map['payload_hash'] = Variable<String>(payloadHash.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextRetryAt.present) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
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
    return (StringBuffer('OutboxOperationsCompanion(')
          ..write('operationId: $operationId, ')
          ..write('deviceId: $deviceId, ')
          ..write('clientSeq: $clientSeq, ')
          ..write('operationType: $operationType, ')
          ..write('payload: $payload, ')
          ..write('payloadHash: $payloadHash, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('lastError: $lastError, ')
          ..write('acknowledgedAt: $acknowledgedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClientSyncStatesTable extends ClientSyncStates
    with TableInfo<$ClientSyncStatesTable, ClientSyncState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClientSyncStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta =
      const VerificationMeta('deviceId');
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
      'device_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _currentClientSeqMeta =
      const VerificationMeta('currentClientSeq');
  @override
  late final GeneratedColumn<int> currentClientSeq = GeneratedColumn<int>(
      'current_client_seq', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastSyncedSeqMeta =
      const VerificationMeta('lastSyncedSeq');
  @override
  late final GeneratedColumn<int> lastSyncedSeq = GeneratedColumn<int>(
      'last_synced_seq', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastServerSaleSeqMeta =
      const VerificationMeta('lastServerSaleSeq');
  @override
  late final GeneratedColumn<int> lastServerSaleSeq = GeneratedColumn<int>(
      'last_server_sale_seq', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastProductSyncAtMeta =
      const VerificationMeta('lastProductSyncAt');
  @override
  late final GeneratedColumn<DateTime> lastProductSyncAt =
      GeneratedColumn<DateTime>('last_product_sync_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _lastSalesSyncAtMeta =
      const VerificationMeta('lastSalesSyncAt');
  @override
  late final GeneratedColumn<DateTime> lastSalesSyncAt =
      GeneratedColumn<DateTime>('last_sales_sync_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _pendingSyncSessionIdMeta =
      const VerificationMeta('pendingSyncSessionId');
  @override
  late final GeneratedColumn<String> pendingSyncSessionId =
      GeneratedColumn<String>('pending_sync_session_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
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
        deviceId,
        currentClientSeq,
        lastSyncedSeq,
        lastServerSaleSeq,
        lastProductSyncAt,
        lastSalesSyncAt,
        pendingSyncSessionId,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'client_sync_states';
  @override
  VerificationContext validateIntegrity(Insertable<ClientSyncState> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(_deviceIdMeta,
          deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta));
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('current_client_seq')) {
      context.handle(
          _currentClientSeqMeta,
          currentClientSeq.isAcceptableOrUnknown(
              data['current_client_seq']!, _currentClientSeqMeta));
    }
    if (data.containsKey('last_synced_seq')) {
      context.handle(
          _lastSyncedSeqMeta,
          lastSyncedSeq.isAcceptableOrUnknown(
              data['last_synced_seq']!, _lastSyncedSeqMeta));
    }
    if (data.containsKey('last_server_sale_seq')) {
      context.handle(
          _lastServerSaleSeqMeta,
          lastServerSaleSeq.isAcceptableOrUnknown(
              data['last_server_sale_seq']!, _lastServerSaleSeqMeta));
    }
    if (data.containsKey('last_product_sync_at')) {
      context.handle(
          _lastProductSyncAtMeta,
          lastProductSyncAt.isAcceptableOrUnknown(
              data['last_product_sync_at']!, _lastProductSyncAtMeta));
    }
    if (data.containsKey('last_sales_sync_at')) {
      context.handle(
          _lastSalesSyncAtMeta,
          lastSalesSyncAt.isAcceptableOrUnknown(
              data['last_sales_sync_at']!, _lastSalesSyncAtMeta));
    }
    if (data.containsKey('pending_sync_session_id')) {
      context.handle(
          _pendingSyncSessionIdMeta,
          pendingSyncSessionId.isAcceptableOrUnknown(
              data['pending_sync_session_id']!, _pendingSyncSessionIdMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId};
  @override
  ClientSyncState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClientSyncState(
      deviceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}device_id'])!,
      currentClientSeq: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}current_client_seq'])!,
      lastSyncedSeq: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_synced_seq'])!,
      lastServerSaleSeq: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}last_server_sale_seq'])!,
      lastProductSyncAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime,
          data['${effectivePrefix}last_product_sync_at']),
      lastSalesSyncAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_sales_sync_at']),
      pendingSyncSessionId: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}pending_sync_session_id']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ClientSyncStatesTable createAlias(String alias) {
    return $ClientSyncStatesTable(attachedDatabase, alias);
  }
}

class ClientSyncState extends DataClass implements Insertable<ClientSyncState> {
  final String deviceId;
  final int currentClientSeq;
  final int lastSyncedSeq;
  final int lastServerSaleSeq;
  final DateTime? lastProductSyncAt;
  final DateTime? lastSalesSyncAt;
  final String? pendingSyncSessionId;
  final DateTime updatedAt;
  const ClientSyncState(
      {required this.deviceId,
      required this.currentClientSeq,
      required this.lastSyncedSeq,
      required this.lastServerSaleSeq,
      this.lastProductSyncAt,
      this.lastSalesSyncAt,
      this.pendingSyncSessionId,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['current_client_seq'] = Variable<int>(currentClientSeq);
    map['last_synced_seq'] = Variable<int>(lastSyncedSeq);
    map['last_server_sale_seq'] = Variable<int>(lastServerSaleSeq);
    if (!nullToAbsent || lastProductSyncAt != null) {
      map['last_product_sync_at'] = Variable<DateTime>(lastProductSyncAt);
    }
    if (!nullToAbsent || lastSalesSyncAt != null) {
      map['last_sales_sync_at'] = Variable<DateTime>(lastSalesSyncAt);
    }
    if (!nullToAbsent || pendingSyncSessionId != null) {
      map['pending_sync_session_id'] = Variable<String>(pendingSyncSessionId);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ClientSyncStatesCompanion toCompanion(bool nullToAbsent) {
    return ClientSyncStatesCompanion(
      deviceId: Value(deviceId),
      currentClientSeq: Value(currentClientSeq),
      lastSyncedSeq: Value(lastSyncedSeq),
      lastServerSaleSeq: Value(lastServerSaleSeq),
      lastProductSyncAt: lastProductSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastProductSyncAt),
      lastSalesSyncAt: lastSalesSyncAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSalesSyncAt),
      pendingSyncSessionId: pendingSyncSessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(pendingSyncSessionId),
      updatedAt: Value(updatedAt),
    );
  }

  factory ClientSyncState.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClientSyncState(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      currentClientSeq: serializer.fromJson<int>(json['currentClientSeq']),
      lastSyncedSeq: serializer.fromJson<int>(json['lastSyncedSeq']),
      lastServerSaleSeq: serializer.fromJson<int>(json['lastServerSaleSeq']),
      lastProductSyncAt:
          serializer.fromJson<DateTime?>(json['lastProductSyncAt']),
      lastSalesSyncAt: serializer.fromJson<DateTime?>(json['lastSalesSyncAt']),
      pendingSyncSessionId:
          serializer.fromJson<String?>(json['pendingSyncSessionId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'currentClientSeq': serializer.toJson<int>(currentClientSeq),
      'lastSyncedSeq': serializer.toJson<int>(lastSyncedSeq),
      'lastServerSaleSeq': serializer.toJson<int>(lastServerSaleSeq),
      'lastProductSyncAt': serializer.toJson<DateTime?>(lastProductSyncAt),
      'lastSalesSyncAt': serializer.toJson<DateTime?>(lastSalesSyncAt),
      'pendingSyncSessionId': serializer.toJson<String?>(pendingSyncSessionId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ClientSyncState copyWith(
          {String? deviceId,
          int? currentClientSeq,
          int? lastSyncedSeq,
          int? lastServerSaleSeq,
          Value<DateTime?> lastProductSyncAt = const Value.absent(),
          Value<DateTime?> lastSalesSyncAt = const Value.absent(),
          Value<String?> pendingSyncSessionId = const Value.absent(),
          DateTime? updatedAt}) =>
      ClientSyncState(
        deviceId: deviceId ?? this.deviceId,
        currentClientSeq: currentClientSeq ?? this.currentClientSeq,
        lastSyncedSeq: lastSyncedSeq ?? this.lastSyncedSeq,
        lastServerSaleSeq: lastServerSaleSeq ?? this.lastServerSaleSeq,
        lastProductSyncAt: lastProductSyncAt.present
            ? lastProductSyncAt.value
            : this.lastProductSyncAt,
        lastSalesSyncAt: lastSalesSyncAt.present
            ? lastSalesSyncAt.value
            : this.lastSalesSyncAt,
        pendingSyncSessionId: pendingSyncSessionId.present
            ? pendingSyncSessionId.value
            : this.pendingSyncSessionId,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  ClientSyncState copyWithCompanion(ClientSyncStatesCompanion data) {
    return ClientSyncState(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      currentClientSeq: data.currentClientSeq.present
          ? data.currentClientSeq.value
          : this.currentClientSeq,
      lastSyncedSeq: data.lastSyncedSeq.present
          ? data.lastSyncedSeq.value
          : this.lastSyncedSeq,
      lastServerSaleSeq: data.lastServerSaleSeq.present
          ? data.lastServerSaleSeq.value
          : this.lastServerSaleSeq,
      lastProductSyncAt: data.lastProductSyncAt.present
          ? data.lastProductSyncAt.value
          : this.lastProductSyncAt,
      lastSalesSyncAt: data.lastSalesSyncAt.present
          ? data.lastSalesSyncAt.value
          : this.lastSalesSyncAt,
      pendingSyncSessionId: data.pendingSyncSessionId.present
          ? data.pendingSyncSessionId.value
          : this.pendingSyncSessionId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClientSyncState(')
          ..write('deviceId: $deviceId, ')
          ..write('currentClientSeq: $currentClientSeq, ')
          ..write('lastSyncedSeq: $lastSyncedSeq, ')
          ..write('lastServerSaleSeq: $lastServerSaleSeq, ')
          ..write('lastProductSyncAt: $lastProductSyncAt, ')
          ..write('lastSalesSyncAt: $lastSalesSyncAt, ')
          ..write('pendingSyncSessionId: $pendingSyncSessionId, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      deviceId,
      currentClientSeq,
      lastSyncedSeq,
      lastServerSaleSeq,
      lastProductSyncAt,
      lastSalesSyncAt,
      pendingSyncSessionId,
      updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClientSyncState &&
          other.deviceId == this.deviceId &&
          other.currentClientSeq == this.currentClientSeq &&
          other.lastSyncedSeq == this.lastSyncedSeq &&
          other.lastServerSaleSeq == this.lastServerSaleSeq &&
          other.lastProductSyncAt == this.lastProductSyncAt &&
          other.lastSalesSyncAt == this.lastSalesSyncAt &&
          other.pendingSyncSessionId == this.pendingSyncSessionId &&
          other.updatedAt == this.updatedAt);
}

class ClientSyncStatesCompanion extends UpdateCompanion<ClientSyncState> {
  final Value<String> deviceId;
  final Value<int> currentClientSeq;
  final Value<int> lastSyncedSeq;
  final Value<int> lastServerSaleSeq;
  final Value<DateTime?> lastProductSyncAt;
  final Value<DateTime?> lastSalesSyncAt;
  final Value<String?> pendingSyncSessionId;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ClientSyncStatesCompanion({
    this.deviceId = const Value.absent(),
    this.currentClientSeq = const Value.absent(),
    this.lastSyncedSeq = const Value.absent(),
    this.lastServerSaleSeq = const Value.absent(),
    this.lastProductSyncAt = const Value.absent(),
    this.lastSalesSyncAt = const Value.absent(),
    this.pendingSyncSessionId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClientSyncStatesCompanion.insert({
    required String deviceId,
    this.currentClientSeq = const Value.absent(),
    this.lastSyncedSeq = const Value.absent(),
    this.lastServerSaleSeq = const Value.absent(),
    this.lastProductSyncAt = const Value.absent(),
    this.lastSalesSyncAt = const Value.absent(),
    this.pendingSyncSessionId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId);
  static Insertable<ClientSyncState> custom({
    Expression<String>? deviceId,
    Expression<int>? currentClientSeq,
    Expression<int>? lastSyncedSeq,
    Expression<int>? lastServerSaleSeq,
    Expression<DateTime>? lastProductSyncAt,
    Expression<DateTime>? lastSalesSyncAt,
    Expression<String>? pendingSyncSessionId,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (currentClientSeq != null) 'current_client_seq': currentClientSeq,
      if (lastSyncedSeq != null) 'last_synced_seq': lastSyncedSeq,
      if (lastServerSaleSeq != null) 'last_server_sale_seq': lastServerSaleSeq,
      if (lastProductSyncAt != null) 'last_product_sync_at': lastProductSyncAt,
      if (lastSalesSyncAt != null) 'last_sales_sync_at': lastSalesSyncAt,
      if (pendingSyncSessionId != null)
        'pending_sync_session_id': pendingSyncSessionId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClientSyncStatesCompanion copyWith(
      {Value<String>? deviceId,
      Value<int>? currentClientSeq,
      Value<int>? lastSyncedSeq,
      Value<int>? lastServerSaleSeq,
      Value<DateTime?>? lastProductSyncAt,
      Value<DateTime?>? lastSalesSyncAt,
      Value<String?>? pendingSyncSessionId,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return ClientSyncStatesCompanion(
      deviceId: deviceId ?? this.deviceId,
      currentClientSeq: currentClientSeq ?? this.currentClientSeq,
      lastSyncedSeq: lastSyncedSeq ?? this.lastSyncedSeq,
      lastServerSaleSeq: lastServerSaleSeq ?? this.lastServerSaleSeq,
      lastProductSyncAt: lastProductSyncAt ?? this.lastProductSyncAt,
      lastSalesSyncAt: lastSalesSyncAt ?? this.lastSalesSyncAt,
      pendingSyncSessionId: pendingSyncSessionId ?? this.pendingSyncSessionId,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (currentClientSeq.present) {
      map['current_client_seq'] = Variable<int>(currentClientSeq.value);
    }
    if (lastSyncedSeq.present) {
      map['last_synced_seq'] = Variable<int>(lastSyncedSeq.value);
    }
    if (lastServerSaleSeq.present) {
      map['last_server_sale_seq'] = Variable<int>(lastServerSaleSeq.value);
    }
    if (lastProductSyncAt.present) {
      map['last_product_sync_at'] = Variable<DateTime>(lastProductSyncAt.value);
    }
    if (lastSalesSyncAt.present) {
      map['last_sales_sync_at'] = Variable<DateTime>(lastSalesSyncAt.value);
    }
    if (pendingSyncSessionId.present) {
      map['pending_sync_session_id'] =
          Variable<String>(pendingSyncSessionId.value);
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
    return (StringBuffer('ClientSyncStatesCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('currentClientSeq: $currentClientSeq, ')
          ..write('lastSyncedSeq: $lastSyncedSeq, ')
          ..write('lastServerSaleSeq: $lastServerSaleSeq, ')
          ..write('lastProductSyncAt: $lastProductSyncAt, ')
          ..write('lastSalesSyncAt: $lastSalesSyncAt, ')
          ..write('pendingSyncSessionId: $pendingSyncSessionId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalClientSettingsTable extends LocalClientSettings
    with TableInfo<$LocalClientSettingsTable, LocalClientSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalClientSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _settingKeyMeta =
      const VerificationMeta('settingKey');
  @override
  late final GeneratedColumn<String> settingKey = GeneratedColumn<String>(
      'setting_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _hubUrlMeta = const VerificationMeta('hubUrl');
  @override
  late final GeneratedColumn<String> hubUrl = GeneratedColumn<String>(
      'hub_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _hubIdMeta = const VerificationMeta('hubId');
  @override
  late final GeneratedColumn<String> hubId = GeneratedColumn<String>(
      'hub_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
      'source', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastVerifiedAtMeta =
      const VerificationMeta('lastVerifiedAt');
  @override
  late final GeneratedColumn<DateTime> lastVerifiedAt =
      GeneratedColumn<DateTime>('last_verified_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [settingKey, hubUrl, hubId, source, lastVerifiedAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_client_settings';
  @override
  VerificationContext validateIntegrity(Insertable<LocalClientSetting> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('setting_key')) {
      context.handle(
          _settingKeyMeta,
          settingKey.isAcceptableOrUnknown(
              data['setting_key']!, _settingKeyMeta));
    } else if (isInserting) {
      context.missing(_settingKeyMeta);
    }
    if (data.containsKey('hub_url')) {
      context.handle(_hubUrlMeta,
          hubUrl.isAcceptableOrUnknown(data['hub_url']!, _hubUrlMeta));
    }
    if (data.containsKey('hub_id')) {
      context.handle(
          _hubIdMeta, hubId.isAcceptableOrUnknown(data['hub_id']!, _hubIdMeta));
    }
    if (data.containsKey('source')) {
      context.handle(_sourceMeta,
          source.isAcceptableOrUnknown(data['source']!, _sourceMeta));
    }
    if (data.containsKey('last_verified_at')) {
      context.handle(
          _lastVerifiedAtMeta,
          lastVerifiedAt.isAcceptableOrUnknown(
              data['last_verified_at']!, _lastVerifiedAtMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {settingKey};
  @override
  LocalClientSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalClientSetting(
      settingKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}setting_key'])!,
      hubUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}hub_url']),
      hubId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}hub_id']),
      source: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source']),
      lastVerifiedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_verified_at']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $LocalClientSettingsTable createAlias(String alias) {
    return $LocalClientSettingsTable(attachedDatabase, alias);
  }
}

class LocalClientSetting extends DataClass
    implements Insertable<LocalClientSetting> {
  final String settingKey;
  final String? hubUrl;
  final String? hubId;
  final String? source;
  final DateTime? lastVerifiedAt;
  final DateTime updatedAt;
  const LocalClientSetting(
      {required this.settingKey,
      this.hubUrl,
      this.hubId,
      this.source,
      this.lastVerifiedAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['setting_key'] = Variable<String>(settingKey);
    if (!nullToAbsent || hubUrl != null) {
      map['hub_url'] = Variable<String>(hubUrl);
    }
    if (!nullToAbsent || hubId != null) {
      map['hub_id'] = Variable<String>(hubId);
    }
    if (!nullToAbsent || source != null) {
      map['source'] = Variable<String>(source);
    }
    if (!nullToAbsent || lastVerifiedAt != null) {
      map['last_verified_at'] = Variable<DateTime>(lastVerifiedAt);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  LocalClientSettingsCompanion toCompanion(bool nullToAbsent) {
    return LocalClientSettingsCompanion(
      settingKey: Value(settingKey),
      hubUrl:
          hubUrl == null && nullToAbsent ? const Value.absent() : Value(hubUrl),
      hubId:
          hubId == null && nullToAbsent ? const Value.absent() : Value(hubId),
      source:
          source == null && nullToAbsent ? const Value.absent() : Value(source),
      lastVerifiedAt: lastVerifiedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastVerifiedAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory LocalClientSetting.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalClientSetting(
      settingKey: serializer.fromJson<String>(json['settingKey']),
      hubUrl: serializer.fromJson<String?>(json['hubUrl']),
      hubId: serializer.fromJson<String?>(json['hubId']),
      source: serializer.fromJson<String?>(json['source']),
      lastVerifiedAt: serializer.fromJson<DateTime?>(json['lastVerifiedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'settingKey': serializer.toJson<String>(settingKey),
      'hubUrl': serializer.toJson<String?>(hubUrl),
      'hubId': serializer.toJson<String?>(hubId),
      'source': serializer.toJson<String?>(source),
      'lastVerifiedAt': serializer.toJson<DateTime?>(lastVerifiedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  LocalClientSetting copyWith(
          {String? settingKey,
          Value<String?> hubUrl = const Value.absent(),
          Value<String?> hubId = const Value.absent(),
          Value<String?> source = const Value.absent(),
          Value<DateTime?> lastVerifiedAt = const Value.absent(),
          DateTime? updatedAt}) =>
      LocalClientSetting(
        settingKey: settingKey ?? this.settingKey,
        hubUrl: hubUrl.present ? hubUrl.value : this.hubUrl,
        hubId: hubId.present ? hubId.value : this.hubId,
        source: source.present ? source.value : this.source,
        lastVerifiedAt:
            lastVerifiedAt.present ? lastVerifiedAt.value : this.lastVerifiedAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  LocalClientSetting copyWithCompanion(LocalClientSettingsCompanion data) {
    return LocalClientSetting(
      settingKey:
          data.settingKey.present ? data.settingKey.value : this.settingKey,
      hubUrl: data.hubUrl.present ? data.hubUrl.value : this.hubUrl,
      hubId: data.hubId.present ? data.hubId.value : this.hubId,
      source: data.source.present ? data.source.value : this.source,
      lastVerifiedAt: data.lastVerifiedAt.present
          ? data.lastVerifiedAt.value
          : this.lastVerifiedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalClientSetting(')
          ..write('settingKey: $settingKey, ')
          ..write('hubUrl: $hubUrl, ')
          ..write('hubId: $hubId, ')
          ..write('source: $source, ')
          ..write('lastVerifiedAt: $lastVerifiedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(settingKey, hubUrl, hubId, source, lastVerifiedAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalClientSetting &&
          other.settingKey == this.settingKey &&
          other.hubUrl == this.hubUrl &&
          other.hubId == this.hubId &&
          other.source == this.source &&
          other.lastVerifiedAt == this.lastVerifiedAt &&
          other.updatedAt == this.updatedAt);
}

class LocalClientSettingsCompanion extends UpdateCompanion<LocalClientSetting> {
  final Value<String> settingKey;
  final Value<String?> hubUrl;
  final Value<String?> hubId;
  final Value<String?> source;
  final Value<DateTime?> lastVerifiedAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const LocalClientSettingsCompanion({
    this.settingKey = const Value.absent(),
    this.hubUrl = const Value.absent(),
    this.hubId = const Value.absent(),
    this.source = const Value.absent(),
    this.lastVerifiedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalClientSettingsCompanion.insert({
    required String settingKey,
    this.hubUrl = const Value.absent(),
    this.hubId = const Value.absent(),
    this.source = const Value.absent(),
    this.lastVerifiedAt = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : settingKey = Value(settingKey),
        updatedAt = Value(updatedAt);
  static Insertable<LocalClientSetting> custom({
    Expression<String>? settingKey,
    Expression<String>? hubUrl,
    Expression<String>? hubId,
    Expression<String>? source,
    Expression<DateTime>? lastVerifiedAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (settingKey != null) 'setting_key': settingKey,
      if (hubUrl != null) 'hub_url': hubUrl,
      if (hubId != null) 'hub_id': hubId,
      if (source != null) 'source': source,
      if (lastVerifiedAt != null) 'last_verified_at': lastVerifiedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalClientSettingsCompanion copyWith(
      {Value<String>? settingKey,
      Value<String?>? hubUrl,
      Value<String?>? hubId,
      Value<String?>? source,
      Value<DateTime?>? lastVerifiedAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return LocalClientSettingsCompanion(
      settingKey: settingKey ?? this.settingKey,
      hubUrl: hubUrl ?? this.hubUrl,
      hubId: hubId ?? this.hubId,
      source: source ?? this.source,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (settingKey.present) {
      map['setting_key'] = Variable<String>(settingKey.value);
    }
    if (hubUrl.present) {
      map['hub_url'] = Variable<String>(hubUrl.value);
    }
    if (hubId.present) {
      map['hub_id'] = Variable<String>(hubId.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (lastVerifiedAt.present) {
      map['last_verified_at'] = Variable<DateTime>(lastVerifiedAt.value);
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
    return (StringBuffer('LocalClientSettingsCompanion(')
          ..write('settingKey: $settingKey, ')
          ..write('hubUrl: $hubUrl, ')
          ..write('hubId: $hubId, ')
          ..write('source: $source, ')
          ..write('lastVerifiedAt: $lastVerifiedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ClientDatabase extends GeneratedDatabase {
  _$ClientDatabase(QueryExecutor e) : super(e);
  $ClientDatabaseManager get managers => $ClientDatabaseManager(this);
  late final $LocalCategoriesTable localCategories =
      $LocalCategoriesTable(this);
  late final $LocalProductsTable localProducts = $LocalProductsTable(this);
  late final $LocalProductBarcodesTable localProductBarcodes =
      $LocalProductBarcodesTable(this);
  late final $LocalSalesTable localSales = $LocalSalesTable(this);
  late final $LocalSaleItemsTable localSaleItems = $LocalSaleItemsTable(this);
  late final $LocalStockMovementsTable localStockMovements =
      $LocalStockMovementsTable(this);
  late final $LocalRefundsTable localRefunds = $LocalRefundsTable(this);
  late final $LocalRefundItemsTable localRefundItems =
      $LocalRefundItemsTable(this);
  late final $LocalPriceHistoryTable localPriceHistory =
      $LocalPriceHistoryTable(this);
  late final $OutboxOperationsTable outboxOperations =
      $OutboxOperationsTable(this);
  late final $ClientSyncStatesTable clientSyncStates =
      $ClientSyncStatesTable(this);
  late final $LocalClientSettingsTable localClientSettings =
      $LocalClientSettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        localCategories,
        localProducts,
        localProductBarcodes,
        localSales,
        localSaleItems,
        localStockMovements,
        localRefunds,
        localRefundItems,
        localPriceHistory,
        outboxOperations,
        clientSyncStates,
        localClientSettings
      ];
}

typedef $$LocalCategoriesTableCreateCompanionBuilder = LocalCategoriesCompanion
    Function({
  required String id,
  required String name,
  Value<String?> parentId,
  Value<bool> isActive,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$LocalCategoriesTableUpdateCompanionBuilder = LocalCategoriesCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<String?> parentId,
  Value<bool> isActive,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

final class $$LocalCategoriesTableReferences extends BaseReferences<
    _$ClientDatabase, $LocalCategoriesTable, LocalCategory> {
  $$LocalCategoriesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $LocalCategoriesTable _parentIdTable(_$ClientDatabase db) =>
      db.localCategories
          .createAlias('local_categories__parent_id__local_categories__id');

  $$LocalCategoriesTableProcessedTableManager? get parentId {
    final $_column = $_itemColumn<String>('parent_id');
    if ($_column == null) return null;
    final manager =
        $$LocalCategoriesTableTableManager($_db, $_db.localCategories)
            .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_parentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$LocalProductsTable, List<LocalProduct>>
      _localProductsRefsTable(_$ClientDatabase db) =>
          MultiTypedResultKey.fromTable(db.localProducts,
              aliasName: 'local_categories__id__local_products__category_id');

  $$LocalProductsTableProcessedTableManager get localProductsRefs {
    final manager = $$LocalProductsTableTableManager($_db, $_db.localProducts)
        .filter((f) => f.categoryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_localProductsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$LocalCategoriesTableFilterComposer
    extends Composer<_$ClientDatabase, $LocalCategoriesTable> {
  $$LocalCategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  $$LocalCategoriesTableFilterComposer get parentId {
    final $$LocalCategoriesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.parentId,
        referencedTable: $db.localCategories,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalCategoriesTableFilterComposer(
              $db: $db,
              $table: $db.localCategories,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> localProductsRefs(
      Expression<bool> Function($$LocalProductsTableFilterComposer f) f) {
    final $$LocalProductsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.localProducts,
        getReferencedColumn: (t) => t.categoryId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalProductsTableFilterComposer(
              $db: $db,
              $table: $db.localProducts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$LocalCategoriesTableOrderingComposer
    extends Composer<_$ClientDatabase, $LocalCategoriesTable> {
  $$LocalCategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  $$LocalCategoriesTableOrderingComposer get parentId {
    final $$LocalCategoriesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.parentId,
        referencedTable: $db.localCategories,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalCategoriesTableOrderingComposer(
              $db: $db,
              $table: $db.localCategories,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LocalCategoriesTableAnnotationComposer
    extends Composer<_$ClientDatabase, $LocalCategoriesTable> {
  $$LocalCategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$LocalCategoriesTableAnnotationComposer get parentId {
    final $$LocalCategoriesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.parentId,
        referencedTable: $db.localCategories,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalCategoriesTableAnnotationComposer(
              $db: $db,
              $table: $db.localCategories,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> localProductsRefs<T extends Object>(
      Expression<T> Function($$LocalProductsTableAnnotationComposer a) f) {
    final $$LocalProductsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.localProducts,
        getReferencedColumn: (t) => t.categoryId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalProductsTableAnnotationComposer(
              $db: $db,
              $table: $db.localProducts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$LocalCategoriesTableTableManager extends RootTableManager<
    _$ClientDatabase,
    $LocalCategoriesTable,
    LocalCategory,
    $$LocalCategoriesTableFilterComposer,
    $$LocalCategoriesTableOrderingComposer,
    $$LocalCategoriesTableAnnotationComposer,
    $$LocalCategoriesTableCreateCompanionBuilder,
    $$LocalCategoriesTableUpdateCompanionBuilder,
    (LocalCategory, $$LocalCategoriesTableReferences),
    LocalCategory,
    PrefetchHooks Function({bool parentId, bool localProductsRefs})> {
  $$LocalCategoriesTableTableManager(
      _$ClientDatabase db, $LocalCategoriesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalCategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalCategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalCategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> parentId = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalCategoriesCompanion(
            id: id,
            name: name,
            parentId: parentId,
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<String?> parentId = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalCategoriesCompanion.insert(
            id: id,
            name: name,
            parentId: parentId,
            isActive: isActive,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$LocalCategoriesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {parentId = false, localProductsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (localProductsRefs) db.localProducts
              ],
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
                if (parentId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.parentId,
                    referencedTable:
                        $$LocalCategoriesTableReferences._parentIdTable(db),
                    referencedColumn:
                        $$LocalCategoriesTableReferences._parentIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (localProductsRefs)
                    await $_getPrefetchedData<LocalCategory,
                            $LocalCategoriesTable, LocalProduct>(
                        currentTable: table,
                        referencedTable: $$LocalCategoriesTableReferences
                            ._localProductsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$LocalCategoriesTableReferences(db, table, p0)
                                .localProductsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.categoryId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$LocalCategoriesTableProcessedTableManager = ProcessedTableManager<
    _$ClientDatabase,
    $LocalCategoriesTable,
    LocalCategory,
    $$LocalCategoriesTableFilterComposer,
    $$LocalCategoriesTableOrderingComposer,
    $$LocalCategoriesTableAnnotationComposer,
    $$LocalCategoriesTableCreateCompanionBuilder,
    $$LocalCategoriesTableUpdateCompanionBuilder,
    (LocalCategory, $$LocalCategoriesTableReferences),
    LocalCategory,
    PrefetchHooks Function({bool parentId, bool localProductsRefs})>;
typedef $$LocalProductsTableCreateCompanionBuilder = LocalProductsCompanion
    Function({
  required String id,
  Value<String?> barcode,
  required String name,
  Value<String?> categoryId,
  required int price,
  Value<String> priceVersionId,
  required int stock,
  Value<String> stockUnit,
  Value<String> pricingUnit,
  Value<int> conversionFactorNumerator,
  Value<int> conversionFactorDenominator,
  Value<int> vatRate,
  Value<bool> isActive,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$LocalProductsTableUpdateCompanionBuilder = LocalProductsCompanion
    Function({
  Value<String> id,
  Value<String?> barcode,
  Value<String> name,
  Value<String?> categoryId,
  Value<int> price,
  Value<String> priceVersionId,
  Value<int> stock,
  Value<String> stockUnit,
  Value<String> pricingUnit,
  Value<int> conversionFactorNumerator,
  Value<int> conversionFactorDenominator,
  Value<int> vatRate,
  Value<bool> isActive,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

final class $$LocalProductsTableReferences extends BaseReferences<
    _$ClientDatabase, $LocalProductsTable, LocalProduct> {
  $$LocalProductsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $LocalCategoriesTable _categoryIdTable(_$ClientDatabase db) =>
      db.localCategories
          .createAlias('local_products__category_id__local_categories__id');

  $$LocalCategoriesTableProcessedTableManager? get categoryId {
    final $_column = $_itemColumn<String>('category_id');
    if ($_column == null) return null;
    final manager =
        $$LocalCategoriesTableTableManager($_db, $_db.localCategories)
            .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$LocalProductBarcodesTable,
      List<LocalProductBarcode>> _localProductBarcodesRefsTable(
          _$ClientDatabase db) =>
      MultiTypedResultKey.fromTable(db.localProductBarcodes,
          aliasName: 'local_products__id__local_product_barcodes__product_id');

  $$LocalProductBarcodesTableProcessedTableManager
      get localProductBarcodesRefs {
    final manager = $$LocalProductBarcodesTableTableManager(
            $_db, $_db.localProductBarcodes)
        .filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_localProductBarcodesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$LocalSaleItemsTable, List<LocalSaleItem>>
      _localSaleItemsRefsTable(_$ClientDatabase db) =>
          MultiTypedResultKey.fromTable(db.localSaleItems,
              aliasName: 'local_products__id__local_sale_items__product_id');

  $$LocalSaleItemsTableProcessedTableManager get localSaleItemsRefs {
    final manager = $$LocalSaleItemsTableTableManager($_db, $_db.localSaleItems)
        .filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_localSaleItemsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$LocalStockMovementsTable,
      List<LocalStockMovement>> _localStockMovementsRefsTable(
          _$ClientDatabase db) =>
      MultiTypedResultKey.fromTable(db.localStockMovements,
          aliasName: 'local_products__id__local_stock_movements__product_id');

  $$LocalStockMovementsTableProcessedTableManager get localStockMovementsRefs {
    final manager = $$LocalStockMovementsTableTableManager(
            $_db, $_db.localStockMovements)
        .filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_localStockMovementsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$LocalRefundItemsTable, List<LocalRefundItem>>
      _localRefundItemsRefsTable(_$ClientDatabase db) =>
          MultiTypedResultKey.fromTable(db.localRefundItems,
              aliasName: 'local_products__id__local_refund_items__product_id');

  $$LocalRefundItemsTableProcessedTableManager get localRefundItemsRefs {
    final manager = $$LocalRefundItemsTableTableManager(
            $_db, $_db.localRefundItems)
        .filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_localRefundItemsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$LocalPriceHistoryTable,
      List<LocalPriceHistoryData>> _localPriceHistoryRefsTable(
          _$ClientDatabase db) =>
      MultiTypedResultKey.fromTable(db.localPriceHistory,
          aliasName: 'local_products__id__local_price_history__product_id');

  $$LocalPriceHistoryTableProcessedTableManager get localPriceHistoryRefs {
    final manager = $$LocalPriceHistoryTableTableManager(
            $_db, $_db.localPriceHistory)
        .filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_localPriceHistoryRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$LocalProductsTableFilterComposer
    extends Composer<_$ClientDatabase, $LocalProductsTable> {
  $$LocalProductsTableFilterComposer({
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

  ColumnFilters<int> get vatRate => $composableBuilder(
      column: $table.vatRate, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  $$LocalCategoriesTableFilterComposer get categoryId {
    final $$LocalCategoriesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.categoryId,
        referencedTable: $db.localCategories,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalCategoriesTableFilterComposer(
              $db: $db,
              $table: $db.localCategories,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> localProductBarcodesRefs(
      Expression<bool> Function($$LocalProductBarcodesTableFilterComposer f)
          f) {
    final $$LocalProductBarcodesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.localProductBarcodes,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalProductBarcodesTableFilterComposer(
              $db: $db,
              $table: $db.localProductBarcodes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> localSaleItemsRefs(
      Expression<bool> Function($$LocalSaleItemsTableFilterComposer f) f) {
    final $$LocalSaleItemsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.localSaleItems,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalSaleItemsTableFilterComposer(
              $db: $db,
              $table: $db.localSaleItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> localStockMovementsRefs(
      Expression<bool> Function($$LocalStockMovementsTableFilterComposer f) f) {
    final $$LocalStockMovementsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.localStockMovements,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalStockMovementsTableFilterComposer(
              $db: $db,
              $table: $db.localStockMovements,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> localRefundItemsRefs(
      Expression<bool> Function($$LocalRefundItemsTableFilterComposer f) f) {
    final $$LocalRefundItemsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.localRefundItems,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalRefundItemsTableFilterComposer(
              $db: $db,
              $table: $db.localRefundItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> localPriceHistoryRefs(
      Expression<bool> Function($$LocalPriceHistoryTableFilterComposer f) f) {
    final $$LocalPriceHistoryTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.localPriceHistory,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalPriceHistoryTableFilterComposer(
              $db: $db,
              $table: $db.localPriceHistory,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$LocalProductsTableOrderingComposer
    extends Composer<_$ClientDatabase, $LocalProductsTable> {
  $$LocalProductsTableOrderingComposer({
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

  ColumnOrderings<int> get vatRate => $composableBuilder(
      column: $table.vatRate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  $$LocalCategoriesTableOrderingComposer get categoryId {
    final $$LocalCategoriesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.categoryId,
        referencedTable: $db.localCategories,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalCategoriesTableOrderingComposer(
              $db: $db,
              $table: $db.localCategories,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LocalProductsTableAnnotationComposer
    extends Composer<_$ClientDatabase, $LocalProductsTable> {
  $$LocalProductsTableAnnotationComposer({
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

  GeneratedColumn<int> get vatRate =>
      $composableBuilder(column: $table.vatRate, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$LocalCategoriesTableAnnotationComposer get categoryId {
    final $$LocalCategoriesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.categoryId,
        referencedTable: $db.localCategories,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalCategoriesTableAnnotationComposer(
              $db: $db,
              $table: $db.localCategories,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> localProductBarcodesRefs<T extends Object>(
      Expression<T> Function($$LocalProductBarcodesTableAnnotationComposer a)
          f) {
    final $$LocalProductBarcodesTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.localProductBarcodes,
            getReferencedColumn: (t) => t.productId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$LocalProductBarcodesTableAnnotationComposer(
                  $db: $db,
                  $table: $db.localProductBarcodes,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }

  Expression<T> localSaleItemsRefs<T extends Object>(
      Expression<T> Function($$LocalSaleItemsTableAnnotationComposer a) f) {
    final $$LocalSaleItemsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.localSaleItems,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalSaleItemsTableAnnotationComposer(
              $db: $db,
              $table: $db.localSaleItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> localStockMovementsRefs<T extends Object>(
      Expression<T> Function($$LocalStockMovementsTableAnnotationComposer a)
          f) {
    final $$LocalStockMovementsTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.localStockMovements,
            getReferencedColumn: (t) => t.productId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$LocalStockMovementsTableAnnotationComposer(
                  $db: $db,
                  $table: $db.localStockMovements,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }

  Expression<T> localRefundItemsRefs<T extends Object>(
      Expression<T> Function($$LocalRefundItemsTableAnnotationComposer a) f) {
    final $$LocalRefundItemsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.localRefundItems,
        getReferencedColumn: (t) => t.productId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalRefundItemsTableAnnotationComposer(
              $db: $db,
              $table: $db.localRefundItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> localPriceHistoryRefs<T extends Object>(
      Expression<T> Function($$LocalPriceHistoryTableAnnotationComposer a) f) {
    final $$LocalPriceHistoryTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.localPriceHistory,
            getReferencedColumn: (t) => t.productId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$LocalPriceHistoryTableAnnotationComposer(
                  $db: $db,
                  $table: $db.localPriceHistory,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }
}

class $$LocalProductsTableTableManager extends RootTableManager<
    _$ClientDatabase,
    $LocalProductsTable,
    LocalProduct,
    $$LocalProductsTableFilterComposer,
    $$LocalProductsTableOrderingComposer,
    $$LocalProductsTableAnnotationComposer,
    $$LocalProductsTableCreateCompanionBuilder,
    $$LocalProductsTableUpdateCompanionBuilder,
    (LocalProduct, $$LocalProductsTableReferences),
    LocalProduct,
    PrefetchHooks Function(
        {bool categoryId,
        bool localProductBarcodesRefs,
        bool localSaleItemsRefs,
        bool localStockMovementsRefs,
        bool localRefundItemsRefs,
        bool localPriceHistoryRefs})> {
  $$LocalProductsTableTableManager(
      _$ClientDatabase db, $LocalProductsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String?> barcode = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> categoryId = const Value.absent(),
            Value<int> price = const Value.absent(),
            Value<String> priceVersionId = const Value.absent(),
            Value<int> stock = const Value.absent(),
            Value<String> stockUnit = const Value.absent(),
            Value<String> pricingUnit = const Value.absent(),
            Value<int> conversionFactorNumerator = const Value.absent(),
            Value<int> conversionFactorDenominator = const Value.absent(),
            Value<int> vatRate = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalProductsCompanion(
            id: id,
            barcode: barcode,
            name: name,
            categoryId: categoryId,
            price: price,
            priceVersionId: priceVersionId,
            stock: stock,
            stockUnit: stockUnit,
            pricingUnit: pricingUnit,
            conversionFactorNumerator: conversionFactorNumerator,
            conversionFactorDenominator: conversionFactorDenominator,
            vatRate: vatRate,
            isActive: isActive,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String?> barcode = const Value.absent(),
            required String name,
            Value<String?> categoryId = const Value.absent(),
            required int price,
            Value<String> priceVersionId = const Value.absent(),
            required int stock,
            Value<String> stockUnit = const Value.absent(),
            Value<String> pricingUnit = const Value.absent(),
            Value<int> conversionFactorNumerator = const Value.absent(),
            Value<int> conversionFactorDenominator = const Value.absent(),
            Value<int> vatRate = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalProductsCompanion.insert(
            id: id,
            barcode: barcode,
            name: name,
            categoryId: categoryId,
            price: price,
            priceVersionId: priceVersionId,
            stock: stock,
            stockUnit: stockUnit,
            pricingUnit: pricingUnit,
            conversionFactorNumerator: conversionFactorNumerator,
            conversionFactorDenominator: conversionFactorDenominator,
            vatRate: vatRate,
            isActive: isActive,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$LocalProductsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {categoryId = false,
              localProductBarcodesRefs = false,
              localSaleItemsRefs = false,
              localStockMovementsRefs = false,
              localRefundItemsRefs = false,
              localPriceHistoryRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (localProductBarcodesRefs) db.localProductBarcodes,
                if (localSaleItemsRefs) db.localSaleItems,
                if (localStockMovementsRefs) db.localStockMovements,
                if (localRefundItemsRefs) db.localRefundItems,
                if (localPriceHistoryRefs) db.localPriceHistory
              ],
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
                if (categoryId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.categoryId,
                    referencedTable:
                        $$LocalProductsTableReferences._categoryIdTable(db),
                    referencedColumn:
                        $$LocalProductsTableReferences._categoryIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (localProductBarcodesRefs)
                    await $_getPrefetchedData<LocalProduct, $LocalProductsTable,
                            LocalProductBarcode>(
                        currentTable: table,
                        referencedTable: $$LocalProductsTableReferences
                            ._localProductBarcodesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$LocalProductsTableReferences(db, table, p0)
                                .localProductBarcodesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.productId == item.id),
                        typedResults: items),
                  if (localSaleItemsRefs)
                    await $_getPrefetchedData<LocalProduct, $LocalProductsTable,
                            LocalSaleItem>(
                        currentTable: table,
                        referencedTable: $$LocalProductsTableReferences
                            ._localSaleItemsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$LocalProductsTableReferences(db, table, p0)
                                .localSaleItemsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.productId == item.id),
                        typedResults: items),
                  if (localStockMovementsRefs)
                    await $_getPrefetchedData<LocalProduct, $LocalProductsTable,
                            LocalStockMovement>(
                        currentTable: table,
                        referencedTable: $$LocalProductsTableReferences
                            ._localStockMovementsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$LocalProductsTableReferences(db, table, p0)
                                .localStockMovementsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.productId == item.id),
                        typedResults: items),
                  if (localRefundItemsRefs)
                    await $_getPrefetchedData<LocalProduct, $LocalProductsTable,
                            LocalRefundItem>(
                        currentTable: table,
                        referencedTable: $$LocalProductsTableReferences
                            ._localRefundItemsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$LocalProductsTableReferences(db, table, p0)
                                .localRefundItemsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.productId == item.id),
                        typedResults: items),
                  if (localPriceHistoryRefs)
                    await $_getPrefetchedData<LocalProduct, $LocalProductsTable,
                            LocalPriceHistoryData>(
                        currentTable: table,
                        referencedTable: $$LocalProductsTableReferences
                            ._localPriceHistoryRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$LocalProductsTableReferences(db, table, p0)
                                .localPriceHistoryRefs,
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

typedef $$LocalProductsTableProcessedTableManager = ProcessedTableManager<
    _$ClientDatabase,
    $LocalProductsTable,
    LocalProduct,
    $$LocalProductsTableFilterComposer,
    $$LocalProductsTableOrderingComposer,
    $$LocalProductsTableAnnotationComposer,
    $$LocalProductsTableCreateCompanionBuilder,
    $$LocalProductsTableUpdateCompanionBuilder,
    (LocalProduct, $$LocalProductsTableReferences),
    LocalProduct,
    PrefetchHooks Function(
        {bool categoryId,
        bool localProductBarcodesRefs,
        bool localSaleItemsRefs,
        bool localStockMovementsRefs,
        bool localRefundItemsRefs,
        bool localPriceHistoryRefs})>;
typedef $$LocalProductBarcodesTableCreateCompanionBuilder
    = LocalProductBarcodesCompanion Function({
  required String id,
  required String productId,
  required String barcode,
  Value<bool> isPrimary,
  Value<bool> isActive,
  Value<DateTime> createdAt,
  Value<int> rowid,
});
typedef $$LocalProductBarcodesTableUpdateCompanionBuilder
    = LocalProductBarcodesCompanion Function({
  Value<String> id,
  Value<String> productId,
  Value<String> barcode,
  Value<bool> isPrimary,
  Value<bool> isActive,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

final class $$LocalProductBarcodesTableReferences extends BaseReferences<
    _$ClientDatabase, $LocalProductBarcodesTable, LocalProductBarcode> {
  $$LocalProductBarcodesTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $LocalProductsTable _productIdTable(_$ClientDatabase db) => db
      .localProducts
      .createAlias('local_product_barcodes__product_id__local_products__id');

  $$LocalProductsTableProcessedTableManager get productId {
    final $_column = $_itemColumn<String>('product_id')!;

    final manager = $$LocalProductsTableTableManager($_db, $_db.localProducts)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$LocalProductBarcodesTableFilterComposer
    extends Composer<_$ClientDatabase, $LocalProductBarcodesTable> {
  $$LocalProductBarcodesTableFilterComposer({
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

  ColumnFilters<bool> get isPrimary => $composableBuilder(
      column: $table.isPrimary, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  $$LocalProductsTableFilterComposer get productId {
    final $$LocalProductsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.localProducts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalProductsTableFilterComposer(
              $db: $db,
              $table: $db.localProducts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LocalProductBarcodesTableOrderingComposer
    extends Composer<_$ClientDatabase, $LocalProductBarcodesTable> {
  $$LocalProductBarcodesTableOrderingComposer({
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

  ColumnOrderings<bool> get isPrimary => $composableBuilder(
      column: $table.isPrimary, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  $$LocalProductsTableOrderingComposer get productId {
    final $$LocalProductsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.localProducts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalProductsTableOrderingComposer(
              $db: $db,
              $table: $db.localProducts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LocalProductBarcodesTableAnnotationComposer
    extends Composer<_$ClientDatabase, $LocalProductBarcodesTable> {
  $$LocalProductBarcodesTableAnnotationComposer({
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

  GeneratedColumn<bool> get isPrimary =>
      $composableBuilder(column: $table.isPrimary, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$LocalProductsTableAnnotationComposer get productId {
    final $$LocalProductsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.localProducts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalProductsTableAnnotationComposer(
              $db: $db,
              $table: $db.localProducts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LocalProductBarcodesTableTableManager extends RootTableManager<
    _$ClientDatabase,
    $LocalProductBarcodesTable,
    LocalProductBarcode,
    $$LocalProductBarcodesTableFilterComposer,
    $$LocalProductBarcodesTableOrderingComposer,
    $$LocalProductBarcodesTableAnnotationComposer,
    $$LocalProductBarcodesTableCreateCompanionBuilder,
    $$LocalProductBarcodesTableUpdateCompanionBuilder,
    (LocalProductBarcode, $$LocalProductBarcodesTableReferences),
    LocalProductBarcode,
    PrefetchHooks Function({bool productId})> {
  $$LocalProductBarcodesTableTableManager(
      _$ClientDatabase db, $LocalProductBarcodesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalProductBarcodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalProductBarcodesTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalProductBarcodesTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<String> barcode = const Value.absent(),
            Value<bool> isPrimary = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalProductBarcodesCompanion(
            id: id,
            productId: productId,
            barcode: barcode,
            isPrimary: isPrimary,
            isActive: isActive,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String productId,
            required String barcode,
            Value<bool> isPrimary = const Value.absent(),
            Value<bool> isActive = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalProductBarcodesCompanion.insert(
            id: id,
            productId: productId,
            barcode: barcode,
            isPrimary: isPrimary,
            isActive: isActive,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$LocalProductBarcodesTableReferences(db, table, e)
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
                    referencedTable: $$LocalProductBarcodesTableReferences
                        ._productIdTable(db),
                    referencedColumn: $$LocalProductBarcodesTableReferences
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

typedef $$LocalProductBarcodesTableProcessedTableManager
    = ProcessedTableManager<
        _$ClientDatabase,
        $LocalProductBarcodesTable,
        LocalProductBarcode,
        $$LocalProductBarcodesTableFilterComposer,
        $$LocalProductBarcodesTableOrderingComposer,
        $$LocalProductBarcodesTableAnnotationComposer,
        $$LocalProductBarcodesTableCreateCompanionBuilder,
        $$LocalProductBarcodesTableUpdateCompanionBuilder,
        (LocalProductBarcode, $$LocalProductBarcodesTableReferences),
        LocalProductBarcode,
        PrefetchHooks Function({bool productId})>;
typedef $$LocalSalesTableCreateCompanionBuilder = LocalSalesCompanion Function({
  required String id,
  required String deviceId,
  required int clientSeq,
  required int totalAmount,
  required String paymentMethod,
  Value<String> status,
  Value<String?> cancelReason,
  Value<DateTime?> cancelledAt,
  Value<DateTime> createdAt,
  Value<int> rowid,
});
typedef $$LocalSalesTableUpdateCompanionBuilder = LocalSalesCompanion Function({
  Value<String> id,
  Value<String> deviceId,
  Value<int> clientSeq,
  Value<int> totalAmount,
  Value<String> paymentMethod,
  Value<String> status,
  Value<String?> cancelReason,
  Value<DateTime?> cancelledAt,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

final class $$LocalSalesTableReferences
    extends BaseReferences<_$ClientDatabase, $LocalSalesTable, LocalSale> {
  $$LocalSalesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$LocalSaleItemsTable, List<LocalSaleItem>>
      _localSaleItemsRefsTable(_$ClientDatabase db) =>
          MultiTypedResultKey.fromTable(db.localSaleItems,
              aliasName: 'local_sales__id__local_sale_items__sale_id');

  $$LocalSaleItemsTableProcessedTableManager get localSaleItemsRefs {
    final manager = $$LocalSaleItemsTableTableManager($_db, $_db.localSaleItems)
        .filter((f) => f.saleId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_localSaleItemsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$LocalRefundsTable, List<LocalRefund>>
      _localRefundsRefsTable(_$ClientDatabase db) =>
          MultiTypedResultKey.fromTable(db.localRefunds,
              aliasName: 'local_sales__id__local_refunds__sale_id');

  $$LocalRefundsTableProcessedTableManager get localRefundsRefs {
    final manager = $$LocalRefundsTableTableManager($_db, $_db.localRefunds)
        .filter((f) => f.saleId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_localRefundsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$LocalSalesTableFilterComposer
    extends Composer<_$ClientDatabase, $LocalSalesTable> {
  $$LocalSalesTableFilterComposer({
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

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cancelReason => $composableBuilder(
      column: $table.cancelReason, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get cancelledAt => $composableBuilder(
      column: $table.cancelledAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  Expression<bool> localSaleItemsRefs(
      Expression<bool> Function($$LocalSaleItemsTableFilterComposer f) f) {
    final $$LocalSaleItemsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.localSaleItems,
        getReferencedColumn: (t) => t.saleId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalSaleItemsTableFilterComposer(
              $db: $db,
              $table: $db.localSaleItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> localRefundsRefs(
      Expression<bool> Function($$LocalRefundsTableFilterComposer f) f) {
    final $$LocalRefundsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.localRefunds,
        getReferencedColumn: (t) => t.saleId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalRefundsTableFilterComposer(
              $db: $db,
              $table: $db.localRefunds,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$LocalSalesTableOrderingComposer
    extends Composer<_$ClientDatabase, $LocalSalesTable> {
  $$LocalSalesTableOrderingComposer({
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

class $$LocalSalesTableAnnotationComposer
    extends Composer<_$ClientDatabase, $LocalSalesTable> {
  $$LocalSalesTableAnnotationComposer({
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

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get cancelReason => $composableBuilder(
      column: $table.cancelReason, builder: (column) => column);

  GeneratedColumn<DateTime> get cancelledAt => $composableBuilder(
      column: $table.cancelledAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> localSaleItemsRefs<T extends Object>(
      Expression<T> Function($$LocalSaleItemsTableAnnotationComposer a) f) {
    final $$LocalSaleItemsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.localSaleItems,
        getReferencedColumn: (t) => t.saleId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalSaleItemsTableAnnotationComposer(
              $db: $db,
              $table: $db.localSaleItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> localRefundsRefs<T extends Object>(
      Expression<T> Function($$LocalRefundsTableAnnotationComposer a) f) {
    final $$LocalRefundsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.localRefunds,
        getReferencedColumn: (t) => t.saleId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalRefundsTableAnnotationComposer(
              $db: $db,
              $table: $db.localRefunds,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$LocalSalesTableTableManager extends RootTableManager<
    _$ClientDatabase,
    $LocalSalesTable,
    LocalSale,
    $$LocalSalesTableFilterComposer,
    $$LocalSalesTableOrderingComposer,
    $$LocalSalesTableAnnotationComposer,
    $$LocalSalesTableCreateCompanionBuilder,
    $$LocalSalesTableUpdateCompanionBuilder,
    (LocalSale, $$LocalSalesTableReferences),
    LocalSale,
    PrefetchHooks Function({bool localSaleItemsRefs, bool localRefundsRefs})> {
  $$LocalSalesTableTableManager(_$ClientDatabase db, $LocalSalesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSalesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSalesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSalesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> deviceId = const Value.absent(),
            Value<int> clientSeq = const Value.absent(),
            Value<int> totalAmount = const Value.absent(),
            Value<String> paymentMethod = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> cancelReason = const Value.absent(),
            Value<DateTime?> cancelledAt = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalSalesCompanion(
            id: id,
            deviceId: deviceId,
            clientSeq: clientSeq,
            totalAmount: totalAmount,
            paymentMethod: paymentMethod,
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
            Value<String> status = const Value.absent(),
            Value<String?> cancelReason = const Value.absent(),
            Value<DateTime?> cancelledAt = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalSalesCompanion.insert(
            id: id,
            deviceId: deviceId,
            clientSeq: clientSeq,
            totalAmount: totalAmount,
            paymentMethod: paymentMethod,
            status: status,
            cancelReason: cancelReason,
            cancelledAt: cancelledAt,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$LocalSalesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {localSaleItemsRefs = false, localRefundsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (localSaleItemsRefs) db.localSaleItems,
                if (localRefundsRefs) db.localRefunds
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (localSaleItemsRefs)
                    await $_getPrefetchedData<LocalSale, $LocalSalesTable,
                            LocalSaleItem>(
                        currentTable: table,
                        referencedTable: $$LocalSalesTableReferences
                            ._localSaleItemsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$LocalSalesTableReferences(db, table, p0)
                                .localSaleItemsRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.saleId == item.id),
                        typedResults: items),
                  if (localRefundsRefs)
                    await $_getPrefetchedData<LocalSale, $LocalSalesTable,
                            LocalRefund>(
                        currentTable: table,
                        referencedTable: $$LocalSalesTableReferences
                            ._localRefundsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$LocalSalesTableReferences(db, table, p0)
                                .localRefundsRefs,
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

typedef $$LocalSalesTableProcessedTableManager = ProcessedTableManager<
    _$ClientDatabase,
    $LocalSalesTable,
    LocalSale,
    $$LocalSalesTableFilterComposer,
    $$LocalSalesTableOrderingComposer,
    $$LocalSalesTableAnnotationComposer,
    $$LocalSalesTableCreateCompanionBuilder,
    $$LocalSalesTableUpdateCompanionBuilder,
    (LocalSale, $$LocalSalesTableReferences),
    LocalSale,
    PrefetchHooks Function({bool localSaleItemsRefs, bool localRefundsRefs})>;
typedef $$LocalSaleItemsTableCreateCompanionBuilder = LocalSaleItemsCompanion
    Function({
  required String id,
  required String saleId,
  required String productId,
  required String productNameSnapshot,
  Value<String> unitSnapshot,
  Value<String> priceVersionId,
  required int unitPrice,
  required int quantity,
  required int totalPrice,
  Value<int> rowid,
});
typedef $$LocalSaleItemsTableUpdateCompanionBuilder = LocalSaleItemsCompanion
    Function({
  Value<String> id,
  Value<String> saleId,
  Value<String> productId,
  Value<String> productNameSnapshot,
  Value<String> unitSnapshot,
  Value<String> priceVersionId,
  Value<int> unitPrice,
  Value<int> quantity,
  Value<int> totalPrice,
  Value<int> rowid,
});

final class $$LocalSaleItemsTableReferences extends BaseReferences<
    _$ClientDatabase, $LocalSaleItemsTable, LocalSaleItem> {
  $$LocalSaleItemsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $LocalSalesTable _saleIdTable(_$ClientDatabase db) =>
      db.localSales.createAlias('local_sale_items__sale_id__local_sales__id');

  $$LocalSalesTableProcessedTableManager get saleId {
    final $_column = $_itemColumn<String>('sale_id')!;

    final manager = $$LocalSalesTableTableManager($_db, $_db.localSales)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_saleIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $LocalProductsTable _productIdTable(_$ClientDatabase db) =>
      db.localProducts
          .createAlias('local_sale_items__product_id__local_products__id');

  $$LocalProductsTableProcessedTableManager get productId {
    final $_column = $_itemColumn<String>('product_id')!;

    final manager = $$LocalProductsTableTableManager($_db, $_db.localProducts)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$LocalRefundItemsTable, List<LocalRefundItem>>
      _localRefundItemsRefsTable(_$ClientDatabase db) =>
          MultiTypedResultKey.fromTable(db.localRefundItems,
              aliasName:
                  'local_sale_items__id__local_refund_items__sale_item_id');

  $$LocalRefundItemsTableProcessedTableManager get localRefundItemsRefs {
    final manager = $$LocalRefundItemsTableTableManager(
            $_db, $_db.localRefundItems)
        .filter((f) => f.saleItemId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_localRefundItemsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$LocalSaleItemsTableFilterComposer
    extends Composer<_$ClientDatabase, $LocalSaleItemsTable> {
  $$LocalSaleItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productNameSnapshot => $composableBuilder(
      column: $table.productNameSnapshot,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get unitSnapshot => $composableBuilder(
      column: $table.unitSnapshot, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get priceVersionId => $composableBuilder(
      column: $table.priceVersionId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get unitPrice => $composableBuilder(
      column: $table.unitPrice, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get quantity => $composableBuilder(
      column: $table.quantity, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get totalPrice => $composableBuilder(
      column: $table.totalPrice, builder: (column) => ColumnFilters(column));

  $$LocalSalesTableFilterComposer get saleId {
    final $$LocalSalesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.saleId,
        referencedTable: $db.localSales,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalSalesTableFilterComposer(
              $db: $db,
              $table: $db.localSales,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$LocalProductsTableFilterComposer get productId {
    final $$LocalProductsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.localProducts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalProductsTableFilterComposer(
              $db: $db,
              $table: $db.localProducts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> localRefundItemsRefs(
      Expression<bool> Function($$LocalRefundItemsTableFilterComposer f) f) {
    final $$LocalRefundItemsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.localRefundItems,
        getReferencedColumn: (t) => t.saleItemId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalRefundItemsTableFilterComposer(
              $db: $db,
              $table: $db.localRefundItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$LocalSaleItemsTableOrderingComposer
    extends Composer<_$ClientDatabase, $LocalSaleItemsTable> {
  $$LocalSaleItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productNameSnapshot => $composableBuilder(
      column: $table.productNameSnapshot,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get unitSnapshot => $composableBuilder(
      column: $table.unitSnapshot,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get priceVersionId => $composableBuilder(
      column: $table.priceVersionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get unitPrice => $composableBuilder(
      column: $table.unitPrice, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get quantity => $composableBuilder(
      column: $table.quantity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get totalPrice => $composableBuilder(
      column: $table.totalPrice, builder: (column) => ColumnOrderings(column));

  $$LocalSalesTableOrderingComposer get saleId {
    final $$LocalSalesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.saleId,
        referencedTable: $db.localSales,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalSalesTableOrderingComposer(
              $db: $db,
              $table: $db.localSales,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$LocalProductsTableOrderingComposer get productId {
    final $$LocalProductsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.localProducts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalProductsTableOrderingComposer(
              $db: $db,
              $table: $db.localProducts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LocalSaleItemsTableAnnotationComposer
    extends Composer<_$ClientDatabase, $LocalSaleItemsTable> {
  $$LocalSaleItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get productNameSnapshot => $composableBuilder(
      column: $table.productNameSnapshot, builder: (column) => column);

  GeneratedColumn<String> get unitSnapshot => $composableBuilder(
      column: $table.unitSnapshot, builder: (column) => column);

  GeneratedColumn<String> get priceVersionId => $composableBuilder(
      column: $table.priceVersionId, builder: (column) => column);

  GeneratedColumn<int> get unitPrice =>
      $composableBuilder(column: $table.unitPrice, builder: (column) => column);

  GeneratedColumn<int> get quantity =>
      $composableBuilder(column: $table.quantity, builder: (column) => column);

  GeneratedColumn<int> get totalPrice => $composableBuilder(
      column: $table.totalPrice, builder: (column) => column);

  $$LocalSalesTableAnnotationComposer get saleId {
    final $$LocalSalesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.saleId,
        referencedTable: $db.localSales,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalSalesTableAnnotationComposer(
              $db: $db,
              $table: $db.localSales,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$LocalProductsTableAnnotationComposer get productId {
    final $$LocalProductsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.localProducts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalProductsTableAnnotationComposer(
              $db: $db,
              $table: $db.localProducts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> localRefundItemsRefs<T extends Object>(
      Expression<T> Function($$LocalRefundItemsTableAnnotationComposer a) f) {
    final $$LocalRefundItemsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.localRefundItems,
        getReferencedColumn: (t) => t.saleItemId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalRefundItemsTableAnnotationComposer(
              $db: $db,
              $table: $db.localRefundItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$LocalSaleItemsTableTableManager extends RootTableManager<
    _$ClientDatabase,
    $LocalSaleItemsTable,
    LocalSaleItem,
    $$LocalSaleItemsTableFilterComposer,
    $$LocalSaleItemsTableOrderingComposer,
    $$LocalSaleItemsTableAnnotationComposer,
    $$LocalSaleItemsTableCreateCompanionBuilder,
    $$LocalSaleItemsTableUpdateCompanionBuilder,
    (LocalSaleItem, $$LocalSaleItemsTableReferences),
    LocalSaleItem,
    PrefetchHooks Function(
        {bool saleId, bool productId, bool localRefundItemsRefs})> {
  $$LocalSaleItemsTableTableManager(
      _$ClientDatabase db, $LocalSaleItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalSaleItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalSaleItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalSaleItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> saleId = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<String> productNameSnapshot = const Value.absent(),
            Value<String> unitSnapshot = const Value.absent(),
            Value<String> priceVersionId = const Value.absent(),
            Value<int> unitPrice = const Value.absent(),
            Value<int> quantity = const Value.absent(),
            Value<int> totalPrice = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalSaleItemsCompanion(
            id: id,
            saleId: saleId,
            productId: productId,
            productNameSnapshot: productNameSnapshot,
            unitSnapshot: unitSnapshot,
            priceVersionId: priceVersionId,
            unitPrice: unitPrice,
            quantity: quantity,
            totalPrice: totalPrice,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String saleId,
            required String productId,
            required String productNameSnapshot,
            Value<String> unitSnapshot = const Value.absent(),
            Value<String> priceVersionId = const Value.absent(),
            required int unitPrice,
            required int quantity,
            required int totalPrice,
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalSaleItemsCompanion.insert(
            id: id,
            saleId: saleId,
            productId: productId,
            productNameSnapshot: productNameSnapshot,
            unitSnapshot: unitSnapshot,
            priceVersionId: priceVersionId,
            unitPrice: unitPrice,
            quantity: quantity,
            totalPrice: totalPrice,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$LocalSaleItemsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {saleId = false,
              productId = false,
              localRefundItemsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (localRefundItemsRefs) db.localRefundItems
              ],
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
                        $$LocalSaleItemsTableReferences._saleIdTable(db),
                    referencedColumn:
                        $$LocalSaleItemsTableReferences._saleIdTable(db).id,
                  ) as T;
                }
                if (productId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.productId,
                    referencedTable:
                        $$LocalSaleItemsTableReferences._productIdTable(db),
                    referencedColumn:
                        $$LocalSaleItemsTableReferences._productIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (localRefundItemsRefs)
                    await $_getPrefetchedData<LocalSaleItem,
                            $LocalSaleItemsTable, LocalRefundItem>(
                        currentTable: table,
                        referencedTable: $$LocalSaleItemsTableReferences
                            ._localRefundItemsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$LocalSaleItemsTableReferences(db, table, p0)
                                .localRefundItemsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.saleItemId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$LocalSaleItemsTableProcessedTableManager = ProcessedTableManager<
    _$ClientDatabase,
    $LocalSaleItemsTable,
    LocalSaleItem,
    $$LocalSaleItemsTableFilterComposer,
    $$LocalSaleItemsTableOrderingComposer,
    $$LocalSaleItemsTableAnnotationComposer,
    $$LocalSaleItemsTableCreateCompanionBuilder,
    $$LocalSaleItemsTableUpdateCompanionBuilder,
    (LocalSaleItem, $$LocalSaleItemsTableReferences),
    LocalSaleItem,
    PrefetchHooks Function(
        {bool saleId, bool productId, bool localRefundItemsRefs})>;
typedef $$LocalStockMovementsTableCreateCompanionBuilder
    = LocalStockMovementsCompanion Function({
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
typedef $$LocalStockMovementsTableUpdateCompanionBuilder
    = LocalStockMovementsCompanion Function({
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

final class $$LocalStockMovementsTableReferences extends BaseReferences<
    _$ClientDatabase, $LocalStockMovementsTable, LocalStockMovement> {
  $$LocalStockMovementsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $LocalProductsTable _productIdTable(_$ClientDatabase db) =>
      db.localProducts
          .createAlias('local_stock_movements__product_id__local_products__id');

  $$LocalProductsTableProcessedTableManager get productId {
    final $_column = $_itemColumn<String>('product_id')!;

    final manager = $$LocalProductsTableTableManager($_db, $_db.localProducts)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$LocalStockMovementsTableFilterComposer
    extends Composer<_$ClientDatabase, $LocalStockMovementsTable> {
  $$LocalStockMovementsTableFilterComposer({
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

  $$LocalProductsTableFilterComposer get productId {
    final $$LocalProductsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.localProducts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalProductsTableFilterComposer(
              $db: $db,
              $table: $db.localProducts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LocalStockMovementsTableOrderingComposer
    extends Composer<_$ClientDatabase, $LocalStockMovementsTable> {
  $$LocalStockMovementsTableOrderingComposer({
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

  $$LocalProductsTableOrderingComposer get productId {
    final $$LocalProductsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.localProducts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalProductsTableOrderingComposer(
              $db: $db,
              $table: $db.localProducts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LocalStockMovementsTableAnnotationComposer
    extends Composer<_$ClientDatabase, $LocalStockMovementsTable> {
  $$LocalStockMovementsTableAnnotationComposer({
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

  $$LocalProductsTableAnnotationComposer get productId {
    final $$LocalProductsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.localProducts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalProductsTableAnnotationComposer(
              $db: $db,
              $table: $db.localProducts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LocalStockMovementsTableTableManager extends RootTableManager<
    _$ClientDatabase,
    $LocalStockMovementsTable,
    LocalStockMovement,
    $$LocalStockMovementsTableFilterComposer,
    $$LocalStockMovementsTableOrderingComposer,
    $$LocalStockMovementsTableAnnotationComposer,
    $$LocalStockMovementsTableCreateCompanionBuilder,
    $$LocalStockMovementsTableUpdateCompanionBuilder,
    (LocalStockMovement, $$LocalStockMovementsTableReferences),
    LocalStockMovement,
    PrefetchHooks Function({bool productId})> {
  $$LocalStockMovementsTableTableManager(
      _$ClientDatabase db, $LocalStockMovementsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalStockMovementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalStockMovementsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalStockMovementsTableAnnotationComposer(
                  $db: db, $table: table),
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
              LocalStockMovementsCompanion(
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
              LocalStockMovementsCompanion.insert(
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
                    $$LocalStockMovementsTableReferences(db, table, e)
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
                    referencedTable: $$LocalStockMovementsTableReferences
                        ._productIdTable(db),
                    referencedColumn: $$LocalStockMovementsTableReferences
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

typedef $$LocalStockMovementsTableProcessedTableManager = ProcessedTableManager<
    _$ClientDatabase,
    $LocalStockMovementsTable,
    LocalStockMovement,
    $$LocalStockMovementsTableFilterComposer,
    $$LocalStockMovementsTableOrderingComposer,
    $$LocalStockMovementsTableAnnotationComposer,
    $$LocalStockMovementsTableCreateCompanionBuilder,
    $$LocalStockMovementsTableUpdateCompanionBuilder,
    (LocalStockMovement, $$LocalStockMovementsTableReferences),
    LocalStockMovement,
    PrefetchHooks Function({bool productId})>;
typedef $$LocalRefundsTableCreateCompanionBuilder = LocalRefundsCompanion
    Function({
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
typedef $$LocalRefundsTableUpdateCompanionBuilder = LocalRefundsCompanion
    Function({
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

final class $$LocalRefundsTableReferences
    extends BaseReferences<_$ClientDatabase, $LocalRefundsTable, LocalRefund> {
  $$LocalRefundsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $LocalSalesTable _saleIdTable(_$ClientDatabase db) =>
      db.localSales.createAlias('local_refunds__sale_id__local_sales__id');

  $$LocalSalesTableProcessedTableManager get saleId {
    final $_column = $_itemColumn<String>('sale_id')!;

    final manager = $$LocalSalesTableTableManager($_db, $_db.localSales)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_saleIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$LocalRefundItemsTable, List<LocalRefundItem>>
      _localRefundItemsRefsTable(_$ClientDatabase db) =>
          MultiTypedResultKey.fromTable(db.localRefundItems,
              aliasName: 'local_refunds__id__local_refund_items__refund_id');

  $$LocalRefundItemsTableProcessedTableManager get localRefundItemsRefs {
    final manager = $$LocalRefundItemsTableTableManager(
            $_db, $_db.localRefundItems)
        .filter((f) => f.refundId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_localRefundItemsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$LocalRefundsTableFilterComposer
    extends Composer<_$ClientDatabase, $LocalRefundsTable> {
  $$LocalRefundsTableFilterComposer({
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

  $$LocalSalesTableFilterComposer get saleId {
    final $$LocalSalesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.saleId,
        referencedTable: $db.localSales,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalSalesTableFilterComposer(
              $db: $db,
              $table: $db.localSales,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> localRefundItemsRefs(
      Expression<bool> Function($$LocalRefundItemsTableFilterComposer f) f) {
    final $$LocalRefundItemsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.localRefundItems,
        getReferencedColumn: (t) => t.refundId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalRefundItemsTableFilterComposer(
              $db: $db,
              $table: $db.localRefundItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$LocalRefundsTableOrderingComposer
    extends Composer<_$ClientDatabase, $LocalRefundsTable> {
  $$LocalRefundsTableOrderingComposer({
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

  $$LocalSalesTableOrderingComposer get saleId {
    final $$LocalSalesTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.saleId,
        referencedTable: $db.localSales,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalSalesTableOrderingComposer(
              $db: $db,
              $table: $db.localSales,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LocalRefundsTableAnnotationComposer
    extends Composer<_$ClientDatabase, $LocalRefundsTable> {
  $$LocalRefundsTableAnnotationComposer({
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

  $$LocalSalesTableAnnotationComposer get saleId {
    final $$LocalSalesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.saleId,
        referencedTable: $db.localSales,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalSalesTableAnnotationComposer(
              $db: $db,
              $table: $db.localSales,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> localRefundItemsRefs<T extends Object>(
      Expression<T> Function($$LocalRefundItemsTableAnnotationComposer a) f) {
    final $$LocalRefundItemsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.localRefundItems,
        getReferencedColumn: (t) => t.refundId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalRefundItemsTableAnnotationComposer(
              $db: $db,
              $table: $db.localRefundItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$LocalRefundsTableTableManager extends RootTableManager<
    _$ClientDatabase,
    $LocalRefundsTable,
    LocalRefund,
    $$LocalRefundsTableFilterComposer,
    $$LocalRefundsTableOrderingComposer,
    $$LocalRefundsTableAnnotationComposer,
    $$LocalRefundsTableCreateCompanionBuilder,
    $$LocalRefundsTableUpdateCompanionBuilder,
    (LocalRefund, $$LocalRefundsTableReferences),
    LocalRefund,
    PrefetchHooks Function({bool saleId, bool localRefundItemsRefs})> {
  $$LocalRefundsTableTableManager(_$ClientDatabase db, $LocalRefundsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalRefundsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalRefundsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalRefundsTableAnnotationComposer($db: db, $table: table),
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
              LocalRefundsCompanion(
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
              LocalRefundsCompanion.insert(
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
              .map((e) => (
                    e.readTable(table),
                    $$LocalRefundsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {saleId = false, localRefundItemsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (localRefundItemsRefs) db.localRefundItems
              ],
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
                        $$LocalRefundsTableReferences._saleIdTable(db),
                    referencedColumn:
                        $$LocalRefundsTableReferences._saleIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (localRefundItemsRefs)
                    await $_getPrefetchedData<LocalRefund, $LocalRefundsTable,
                            LocalRefundItem>(
                        currentTable: table,
                        referencedTable: $$LocalRefundsTableReferences
                            ._localRefundItemsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$LocalRefundsTableReferences(db, table, p0)
                                .localRefundItemsRefs,
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

typedef $$LocalRefundsTableProcessedTableManager = ProcessedTableManager<
    _$ClientDatabase,
    $LocalRefundsTable,
    LocalRefund,
    $$LocalRefundsTableFilterComposer,
    $$LocalRefundsTableOrderingComposer,
    $$LocalRefundsTableAnnotationComposer,
    $$LocalRefundsTableCreateCompanionBuilder,
    $$LocalRefundsTableUpdateCompanionBuilder,
    (LocalRefund, $$LocalRefundsTableReferences),
    LocalRefund,
    PrefetchHooks Function({bool saleId, bool localRefundItemsRefs})>;
typedef $$LocalRefundItemsTableCreateCompanionBuilder
    = LocalRefundItemsCompanion Function({
  required String id,
  required String refundId,
  required String saleItemId,
  required String productId,
  required int quantity,
  required int unitPrice,
  required int refundAmount,
  Value<String> productCondition,
  Value<DateTime> createdAt,
  Value<int> rowid,
});
typedef $$LocalRefundItemsTableUpdateCompanionBuilder
    = LocalRefundItemsCompanion Function({
  Value<String> id,
  Value<String> refundId,
  Value<String> saleItemId,
  Value<String> productId,
  Value<int> quantity,
  Value<int> unitPrice,
  Value<int> refundAmount,
  Value<String> productCondition,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

final class $$LocalRefundItemsTableReferences extends BaseReferences<
    _$ClientDatabase, $LocalRefundItemsTable, LocalRefundItem> {
  $$LocalRefundItemsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $LocalRefundsTable _refundIdTable(_$ClientDatabase db) =>
      db.localRefunds
          .createAlias('local_refund_items__refund_id__local_refunds__id');

  $$LocalRefundsTableProcessedTableManager get refundId {
    final $_column = $_itemColumn<String>('refund_id')!;

    final manager = $$LocalRefundsTableTableManager($_db, $_db.localRefunds)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_refundIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $LocalSaleItemsTable _saleItemIdTable(_$ClientDatabase db) => db
      .localSaleItems
      .createAlias('local_refund_items__sale_item_id__local_sale_items__id');

  $$LocalSaleItemsTableProcessedTableManager get saleItemId {
    final $_column = $_itemColumn<String>('sale_item_id')!;

    final manager = $$LocalSaleItemsTableTableManager($_db, $_db.localSaleItems)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_saleItemIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $LocalProductsTable _productIdTable(_$ClientDatabase db) =>
      db.localProducts
          .createAlias('local_refund_items__product_id__local_products__id');

  $$LocalProductsTableProcessedTableManager get productId {
    final $_column = $_itemColumn<String>('product_id')!;

    final manager = $$LocalProductsTableTableManager($_db, $_db.localProducts)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$LocalRefundItemsTableFilterComposer
    extends Composer<_$ClientDatabase, $LocalRefundItemsTable> {
  $$LocalRefundItemsTableFilterComposer({
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

  ColumnFilters<int> get refundAmount => $composableBuilder(
      column: $table.refundAmount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get productCondition => $composableBuilder(
      column: $table.productCondition,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  $$LocalRefundsTableFilterComposer get refundId {
    final $$LocalRefundsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.refundId,
        referencedTable: $db.localRefunds,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalRefundsTableFilterComposer(
              $db: $db,
              $table: $db.localRefunds,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$LocalSaleItemsTableFilterComposer get saleItemId {
    final $$LocalSaleItemsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.saleItemId,
        referencedTable: $db.localSaleItems,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalSaleItemsTableFilterComposer(
              $db: $db,
              $table: $db.localSaleItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$LocalProductsTableFilterComposer get productId {
    final $$LocalProductsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.localProducts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalProductsTableFilterComposer(
              $db: $db,
              $table: $db.localProducts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LocalRefundItemsTableOrderingComposer
    extends Composer<_$ClientDatabase, $LocalRefundItemsTable> {
  $$LocalRefundItemsTableOrderingComposer({
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

  ColumnOrderings<int> get refundAmount => $composableBuilder(
      column: $table.refundAmount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get productCondition => $composableBuilder(
      column: $table.productCondition,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  $$LocalRefundsTableOrderingComposer get refundId {
    final $$LocalRefundsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.refundId,
        referencedTable: $db.localRefunds,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalRefundsTableOrderingComposer(
              $db: $db,
              $table: $db.localRefunds,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$LocalSaleItemsTableOrderingComposer get saleItemId {
    final $$LocalSaleItemsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.saleItemId,
        referencedTable: $db.localSaleItems,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalSaleItemsTableOrderingComposer(
              $db: $db,
              $table: $db.localSaleItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$LocalProductsTableOrderingComposer get productId {
    final $$LocalProductsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.localProducts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalProductsTableOrderingComposer(
              $db: $db,
              $table: $db.localProducts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LocalRefundItemsTableAnnotationComposer
    extends Composer<_$ClientDatabase, $LocalRefundItemsTable> {
  $$LocalRefundItemsTableAnnotationComposer({
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

  GeneratedColumn<int> get refundAmount => $composableBuilder(
      column: $table.refundAmount, builder: (column) => column);

  GeneratedColumn<String> get productCondition => $composableBuilder(
      column: $table.productCondition, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$LocalRefundsTableAnnotationComposer get refundId {
    final $$LocalRefundsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.refundId,
        referencedTable: $db.localRefunds,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalRefundsTableAnnotationComposer(
              $db: $db,
              $table: $db.localRefunds,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$LocalSaleItemsTableAnnotationComposer get saleItemId {
    final $$LocalSaleItemsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.saleItemId,
        referencedTable: $db.localSaleItems,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalSaleItemsTableAnnotationComposer(
              $db: $db,
              $table: $db.localSaleItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$LocalProductsTableAnnotationComposer get productId {
    final $$LocalProductsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.localProducts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalProductsTableAnnotationComposer(
              $db: $db,
              $table: $db.localProducts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LocalRefundItemsTableTableManager extends RootTableManager<
    _$ClientDatabase,
    $LocalRefundItemsTable,
    LocalRefundItem,
    $$LocalRefundItemsTableFilterComposer,
    $$LocalRefundItemsTableOrderingComposer,
    $$LocalRefundItemsTableAnnotationComposer,
    $$LocalRefundItemsTableCreateCompanionBuilder,
    $$LocalRefundItemsTableUpdateCompanionBuilder,
    (LocalRefundItem, $$LocalRefundItemsTableReferences),
    LocalRefundItem,
    PrefetchHooks Function({bool refundId, bool saleItemId, bool productId})> {
  $$LocalRefundItemsTableTableManager(
      _$ClientDatabase db, $LocalRefundItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalRefundItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalRefundItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalRefundItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> refundId = const Value.absent(),
            Value<String> saleItemId = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<int> quantity = const Value.absent(),
            Value<int> unitPrice = const Value.absent(),
            Value<int> refundAmount = const Value.absent(),
            Value<String> productCondition = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalRefundItemsCompanion(
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
            required String saleItemId,
            required String productId,
            required int quantity,
            required int unitPrice,
            required int refundAmount,
            Value<String> productCondition = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalRefundItemsCompanion.insert(
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
                    $$LocalRefundItemsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {refundId = false, saleItemId = false, productId = false}) {
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
                        $$LocalRefundItemsTableReferences._refundIdTable(db),
                    referencedColumn:
                        $$LocalRefundItemsTableReferences._refundIdTable(db).id,
                  ) as T;
                }
                if (saleItemId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.saleItemId,
                    referencedTable:
                        $$LocalRefundItemsTableReferences._saleItemIdTable(db),
                    referencedColumn: $$LocalRefundItemsTableReferences
                        ._saleItemIdTable(db)
                        .id,
                  ) as T;
                }
                if (productId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.productId,
                    referencedTable:
                        $$LocalRefundItemsTableReferences._productIdTable(db),
                    referencedColumn: $$LocalRefundItemsTableReferences
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

typedef $$LocalRefundItemsTableProcessedTableManager = ProcessedTableManager<
    _$ClientDatabase,
    $LocalRefundItemsTable,
    LocalRefundItem,
    $$LocalRefundItemsTableFilterComposer,
    $$LocalRefundItemsTableOrderingComposer,
    $$LocalRefundItemsTableAnnotationComposer,
    $$LocalRefundItemsTableCreateCompanionBuilder,
    $$LocalRefundItemsTableUpdateCompanionBuilder,
    (LocalRefundItem, $$LocalRefundItemsTableReferences),
    LocalRefundItem,
    PrefetchHooks Function({bool refundId, bool saleItemId, bool productId})>;
typedef $$LocalPriceHistoryTableCreateCompanionBuilder
    = LocalPriceHistoryCompanion Function({
  required String id,
  required String productId,
  required int oldPrice,
  required int newPrice,
  required String priceVersionId,
  Value<String> source,
  Value<String?> reason,
  Value<DateTime> changedAt,
  Value<int> rowid,
});
typedef $$LocalPriceHistoryTableUpdateCompanionBuilder
    = LocalPriceHistoryCompanion Function({
  Value<String> id,
  Value<String> productId,
  Value<int> oldPrice,
  Value<int> newPrice,
  Value<String> priceVersionId,
  Value<String> source,
  Value<String?> reason,
  Value<DateTime> changedAt,
  Value<int> rowid,
});

final class $$LocalPriceHistoryTableReferences extends BaseReferences<
    _$ClientDatabase, $LocalPriceHistoryTable, LocalPriceHistoryData> {
  $$LocalPriceHistoryTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $LocalProductsTable _productIdTable(_$ClientDatabase db) =>
      db.localProducts
          .createAlias('local_price_history__product_id__local_products__id');

  $$LocalProductsTableProcessedTableManager get productId {
    final $_column = $_itemColumn<String>('product_id')!;

    final manager = $$LocalProductsTableTableManager($_db, $_db.localProducts)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$LocalPriceHistoryTableFilterComposer
    extends Composer<_$ClientDatabase, $LocalPriceHistoryTable> {
  $$LocalPriceHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get oldPrice => $composableBuilder(
      column: $table.oldPrice, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get newPrice => $composableBuilder(
      column: $table.newPrice, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get priceVersionId => $composableBuilder(
      column: $table.priceVersionId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get reason => $composableBuilder(
      column: $table.reason, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get changedAt => $composableBuilder(
      column: $table.changedAt, builder: (column) => ColumnFilters(column));

  $$LocalProductsTableFilterComposer get productId {
    final $$LocalProductsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.localProducts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalProductsTableFilterComposer(
              $db: $db,
              $table: $db.localProducts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LocalPriceHistoryTableOrderingComposer
    extends Composer<_$ClientDatabase, $LocalPriceHistoryTable> {
  $$LocalPriceHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get oldPrice => $composableBuilder(
      column: $table.oldPrice, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get newPrice => $composableBuilder(
      column: $table.newPrice, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get priceVersionId => $composableBuilder(
      column: $table.priceVersionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get reason => $composableBuilder(
      column: $table.reason, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get changedAt => $composableBuilder(
      column: $table.changedAt, builder: (column) => ColumnOrderings(column));

  $$LocalProductsTableOrderingComposer get productId {
    final $$LocalProductsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.localProducts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalProductsTableOrderingComposer(
              $db: $db,
              $table: $db.localProducts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LocalPriceHistoryTableAnnotationComposer
    extends Composer<_$ClientDatabase, $LocalPriceHistoryTable> {
  $$LocalPriceHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get oldPrice =>
      $composableBuilder(column: $table.oldPrice, builder: (column) => column);

  GeneratedColumn<int> get newPrice =>
      $composableBuilder(column: $table.newPrice, builder: (column) => column);

  GeneratedColumn<String> get priceVersionId => $composableBuilder(
      column: $table.priceVersionId, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<DateTime> get changedAt =>
      $composableBuilder(column: $table.changedAt, builder: (column) => column);

  $$LocalProductsTableAnnotationComposer get productId {
    final $$LocalProductsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.productId,
        referencedTable: $db.localProducts,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$LocalProductsTableAnnotationComposer(
              $db: $db,
              $table: $db.localProducts,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$LocalPriceHistoryTableTableManager extends RootTableManager<
    _$ClientDatabase,
    $LocalPriceHistoryTable,
    LocalPriceHistoryData,
    $$LocalPriceHistoryTableFilterComposer,
    $$LocalPriceHistoryTableOrderingComposer,
    $$LocalPriceHistoryTableAnnotationComposer,
    $$LocalPriceHistoryTableCreateCompanionBuilder,
    $$LocalPriceHistoryTableUpdateCompanionBuilder,
    (LocalPriceHistoryData, $$LocalPriceHistoryTableReferences),
    LocalPriceHistoryData,
    PrefetchHooks Function({bool productId})> {
  $$LocalPriceHistoryTableTableManager(
      _$ClientDatabase db, $LocalPriceHistoryTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalPriceHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalPriceHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalPriceHistoryTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> productId = const Value.absent(),
            Value<int> oldPrice = const Value.absent(),
            Value<int> newPrice = const Value.absent(),
            Value<String> priceVersionId = const Value.absent(),
            Value<String> source = const Value.absent(),
            Value<String?> reason = const Value.absent(),
            Value<DateTime> changedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalPriceHistoryCompanion(
            id: id,
            productId: productId,
            oldPrice: oldPrice,
            newPrice: newPrice,
            priceVersionId: priceVersionId,
            source: source,
            reason: reason,
            changedAt: changedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String productId,
            required int oldPrice,
            required int newPrice,
            required String priceVersionId,
            Value<String> source = const Value.absent(),
            Value<String?> reason = const Value.absent(),
            Value<DateTime> changedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalPriceHistoryCompanion.insert(
            id: id,
            productId: productId,
            oldPrice: oldPrice,
            newPrice: newPrice,
            priceVersionId: priceVersionId,
            source: source,
            reason: reason,
            changedAt: changedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$LocalPriceHistoryTableReferences(db, table, e)
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
                        $$LocalPriceHistoryTableReferences._productIdTable(db),
                    referencedColumn: $$LocalPriceHistoryTableReferences
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

typedef $$LocalPriceHistoryTableProcessedTableManager = ProcessedTableManager<
    _$ClientDatabase,
    $LocalPriceHistoryTable,
    LocalPriceHistoryData,
    $$LocalPriceHistoryTableFilterComposer,
    $$LocalPriceHistoryTableOrderingComposer,
    $$LocalPriceHistoryTableAnnotationComposer,
    $$LocalPriceHistoryTableCreateCompanionBuilder,
    $$LocalPriceHistoryTableUpdateCompanionBuilder,
    (LocalPriceHistoryData, $$LocalPriceHistoryTableReferences),
    LocalPriceHistoryData,
    PrefetchHooks Function({bool productId})>;
typedef $$OutboxOperationsTableCreateCompanionBuilder
    = OutboxOperationsCompanion Function({
  required String operationId,
  required String deviceId,
  required int clientSeq,
  required String operationType,
  required String payload,
  required String payloadHash,
  required DateTime occurredAt,
  Value<String> status,
  Value<int> attemptCount,
  Value<DateTime?> nextRetryAt,
  Value<String?> lastError,
  Value<DateTime?> acknowledgedAt,
  Value<DateTime> createdAt,
  Value<int> rowid,
});
typedef $$OutboxOperationsTableUpdateCompanionBuilder
    = OutboxOperationsCompanion Function({
  Value<String> operationId,
  Value<String> deviceId,
  Value<int> clientSeq,
  Value<String> operationType,
  Value<String> payload,
  Value<String> payloadHash,
  Value<DateTime> occurredAt,
  Value<String> status,
  Value<int> attemptCount,
  Value<DateTime?> nextRetryAt,
  Value<String?> lastError,
  Value<DateTime?> acknowledgedAt,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$OutboxOperationsTableFilterComposer
    extends Composer<_$ClientDatabase, $OutboxOperationsTable> {
  $$OutboxOperationsTableFilterComposer({
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

  ColumnFilters<int> get clientSeq => $composableBuilder(
      column: $table.clientSeq, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get operationType => $composableBuilder(
      column: $table.operationType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payloadHash => $composableBuilder(
      column: $table.payloadHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
      column: $table.occurredAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get attemptCount => $composableBuilder(
      column: $table.attemptCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get nextRetryAt => $composableBuilder(
      column: $table.nextRetryAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get acknowledgedAt => $composableBuilder(
      column: $table.acknowledgedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$OutboxOperationsTableOrderingComposer
    extends Composer<_$ClientDatabase, $OutboxOperationsTable> {
  $$OutboxOperationsTableOrderingComposer({
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

  ColumnOrderings<int> get clientSeq => $composableBuilder(
      column: $table.clientSeq, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get operationType => $composableBuilder(
      column: $table.operationType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payloadHash => $composableBuilder(
      column: $table.payloadHash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
      column: $table.occurredAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attemptCount => $composableBuilder(
      column: $table.attemptCount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get nextRetryAt => $composableBuilder(
      column: $table.nextRetryAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get acknowledgedAt => $composableBuilder(
      column: $table.acknowledgedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$OutboxOperationsTableAnnotationComposer
    extends Composer<_$ClientDatabase, $OutboxOperationsTable> {
  $$OutboxOperationsTableAnnotationComposer({
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

  GeneratedColumn<int> get clientSeq =>
      $composableBuilder(column: $table.clientSeq, builder: (column) => column);

  GeneratedColumn<String> get operationType => $composableBuilder(
      column: $table.operationType, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get payloadHash => $composableBuilder(
      column: $table.payloadHash, builder: (column) => column);

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
      column: $table.occurredAt, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
      column: $table.attemptCount, builder: (column) => column);

  GeneratedColumn<DateTime> get nextRetryAt => $composableBuilder(
      column: $table.nextRetryAt, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get acknowledgedAt => $composableBuilder(
      column: $table.acknowledgedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$OutboxOperationsTableTableManager extends RootTableManager<
    _$ClientDatabase,
    $OutboxOperationsTable,
    OutboxOperation,
    $$OutboxOperationsTableFilterComposer,
    $$OutboxOperationsTableOrderingComposer,
    $$OutboxOperationsTableAnnotationComposer,
    $$OutboxOperationsTableCreateCompanionBuilder,
    $$OutboxOperationsTableUpdateCompanionBuilder,
    (
      OutboxOperation,
      BaseReferences<_$ClientDatabase, $OutboxOperationsTable, OutboxOperation>
    ),
    OutboxOperation,
    PrefetchHooks Function()> {
  $$OutboxOperationsTableTableManager(
      _$ClientDatabase db, $OutboxOperationsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxOperationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxOperationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxOperationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> operationId = const Value.absent(),
            Value<String> deviceId = const Value.absent(),
            Value<int> clientSeq = const Value.absent(),
            Value<String> operationType = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<String> payloadHash = const Value.absent(),
            Value<DateTime> occurredAt = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<int> attemptCount = const Value.absent(),
            Value<DateTime?> nextRetryAt = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            Value<DateTime?> acknowledgedAt = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              OutboxOperationsCompanion(
            operationId: operationId,
            deviceId: deviceId,
            clientSeq: clientSeq,
            operationType: operationType,
            payload: payload,
            payloadHash: payloadHash,
            occurredAt: occurredAt,
            status: status,
            attemptCount: attemptCount,
            nextRetryAt: nextRetryAt,
            lastError: lastError,
            acknowledgedAt: acknowledgedAt,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String operationId,
            required String deviceId,
            required int clientSeq,
            required String operationType,
            required String payload,
            required String payloadHash,
            required DateTime occurredAt,
            Value<String> status = const Value.absent(),
            Value<int> attemptCount = const Value.absent(),
            Value<DateTime?> nextRetryAt = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            Value<DateTime?> acknowledgedAt = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              OutboxOperationsCompanion.insert(
            operationId: operationId,
            deviceId: deviceId,
            clientSeq: clientSeq,
            operationType: operationType,
            payload: payload,
            payloadHash: payloadHash,
            occurredAt: occurredAt,
            status: status,
            attemptCount: attemptCount,
            nextRetryAt: nextRetryAt,
            lastError: lastError,
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

typedef $$OutboxOperationsTableProcessedTableManager = ProcessedTableManager<
    _$ClientDatabase,
    $OutboxOperationsTable,
    OutboxOperation,
    $$OutboxOperationsTableFilterComposer,
    $$OutboxOperationsTableOrderingComposer,
    $$OutboxOperationsTableAnnotationComposer,
    $$OutboxOperationsTableCreateCompanionBuilder,
    $$OutboxOperationsTableUpdateCompanionBuilder,
    (
      OutboxOperation,
      BaseReferences<_$ClientDatabase, $OutboxOperationsTable, OutboxOperation>
    ),
    OutboxOperation,
    PrefetchHooks Function()>;
typedef $$ClientSyncStatesTableCreateCompanionBuilder
    = ClientSyncStatesCompanion Function({
  required String deviceId,
  Value<int> currentClientSeq,
  Value<int> lastSyncedSeq,
  Value<int> lastServerSaleSeq,
  Value<DateTime?> lastProductSyncAt,
  Value<DateTime?> lastSalesSyncAt,
  Value<String?> pendingSyncSessionId,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});
typedef $$ClientSyncStatesTableUpdateCompanionBuilder
    = ClientSyncStatesCompanion Function({
  Value<String> deviceId,
  Value<int> currentClientSeq,
  Value<int> lastSyncedSeq,
  Value<int> lastServerSaleSeq,
  Value<DateTime?> lastProductSyncAt,
  Value<DateTime?> lastSalesSyncAt,
  Value<String?> pendingSyncSessionId,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$ClientSyncStatesTableFilterComposer
    extends Composer<_$ClientDatabase, $ClientSyncStatesTable> {
  $$ClientSyncStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get currentClientSeq => $composableBuilder(
      column: $table.currentClientSeq,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastSyncedSeq => $composableBuilder(
      column: $table.lastSyncedSeq, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastServerSaleSeq => $composableBuilder(
      column: $table.lastServerSaleSeq,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastProductSyncAt => $composableBuilder(
      column: $table.lastProductSyncAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastSalesSyncAt => $composableBuilder(
      column: $table.lastSalesSyncAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pendingSyncSessionId => $composableBuilder(
      column: $table.pendingSyncSessionId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$ClientSyncStatesTableOrderingComposer
    extends Composer<_$ClientDatabase, $ClientSyncStatesTable> {
  $$ClientSyncStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get deviceId => $composableBuilder(
      column: $table.deviceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get currentClientSeq => $composableBuilder(
      column: $table.currentClientSeq,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastSyncedSeq => $composableBuilder(
      column: $table.lastSyncedSeq,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastServerSaleSeq => $composableBuilder(
      column: $table.lastServerSaleSeq,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastProductSyncAt => $composableBuilder(
      column: $table.lastProductSyncAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastSalesSyncAt => $composableBuilder(
      column: $table.lastSalesSyncAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pendingSyncSessionId => $composableBuilder(
      column: $table.pendingSyncSessionId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$ClientSyncStatesTableAnnotationComposer
    extends Composer<_$ClientDatabase, $ClientSyncStatesTable> {
  $$ClientSyncStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get currentClientSeq => $composableBuilder(
      column: $table.currentClientSeq, builder: (column) => column);

  GeneratedColumn<int> get lastSyncedSeq => $composableBuilder(
      column: $table.lastSyncedSeq, builder: (column) => column);

  GeneratedColumn<int> get lastServerSaleSeq => $composableBuilder(
      column: $table.lastServerSaleSeq, builder: (column) => column);

  GeneratedColumn<DateTime> get lastProductSyncAt => $composableBuilder(
      column: $table.lastProductSyncAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSalesSyncAt => $composableBuilder(
      column: $table.lastSalesSyncAt, builder: (column) => column);

  GeneratedColumn<String> get pendingSyncSessionId => $composableBuilder(
      column: $table.pendingSyncSessionId, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ClientSyncStatesTableTableManager extends RootTableManager<
    _$ClientDatabase,
    $ClientSyncStatesTable,
    ClientSyncState,
    $$ClientSyncStatesTableFilterComposer,
    $$ClientSyncStatesTableOrderingComposer,
    $$ClientSyncStatesTableAnnotationComposer,
    $$ClientSyncStatesTableCreateCompanionBuilder,
    $$ClientSyncStatesTableUpdateCompanionBuilder,
    (
      ClientSyncState,
      BaseReferences<_$ClientDatabase, $ClientSyncStatesTable, ClientSyncState>
    ),
    ClientSyncState,
    PrefetchHooks Function()> {
  $$ClientSyncStatesTableTableManager(
      _$ClientDatabase db, $ClientSyncStatesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClientSyncStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClientSyncStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClientSyncStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> deviceId = const Value.absent(),
            Value<int> currentClientSeq = const Value.absent(),
            Value<int> lastSyncedSeq = const Value.absent(),
            Value<int> lastServerSaleSeq = const Value.absent(),
            Value<DateTime?> lastProductSyncAt = const Value.absent(),
            Value<DateTime?> lastSalesSyncAt = const Value.absent(),
            Value<String?> pendingSyncSessionId = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ClientSyncStatesCompanion(
            deviceId: deviceId,
            currentClientSeq: currentClientSeq,
            lastSyncedSeq: lastSyncedSeq,
            lastServerSaleSeq: lastServerSaleSeq,
            lastProductSyncAt: lastProductSyncAt,
            lastSalesSyncAt: lastSalesSyncAt,
            pendingSyncSessionId: pendingSyncSessionId,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String deviceId,
            Value<int> currentClientSeq = const Value.absent(),
            Value<int> lastSyncedSeq = const Value.absent(),
            Value<int> lastServerSaleSeq = const Value.absent(),
            Value<DateTime?> lastProductSyncAt = const Value.absent(),
            Value<DateTime?> lastSalesSyncAt = const Value.absent(),
            Value<String?> pendingSyncSessionId = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ClientSyncStatesCompanion.insert(
            deviceId: deviceId,
            currentClientSeq: currentClientSeq,
            lastSyncedSeq: lastSyncedSeq,
            lastServerSaleSeq: lastServerSaleSeq,
            lastProductSyncAt: lastProductSyncAt,
            lastSalesSyncAt: lastSalesSyncAt,
            pendingSyncSessionId: pendingSyncSessionId,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ClientSyncStatesTableProcessedTableManager = ProcessedTableManager<
    _$ClientDatabase,
    $ClientSyncStatesTable,
    ClientSyncState,
    $$ClientSyncStatesTableFilterComposer,
    $$ClientSyncStatesTableOrderingComposer,
    $$ClientSyncStatesTableAnnotationComposer,
    $$ClientSyncStatesTableCreateCompanionBuilder,
    $$ClientSyncStatesTableUpdateCompanionBuilder,
    (
      ClientSyncState,
      BaseReferences<_$ClientDatabase, $ClientSyncStatesTable, ClientSyncState>
    ),
    ClientSyncState,
    PrefetchHooks Function()>;
typedef $$LocalClientSettingsTableCreateCompanionBuilder
    = LocalClientSettingsCompanion Function({
  required String settingKey,
  Value<String?> hubUrl,
  Value<String?> hubId,
  Value<String?> source,
  Value<DateTime?> lastVerifiedAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$LocalClientSettingsTableUpdateCompanionBuilder
    = LocalClientSettingsCompanion Function({
  Value<String> settingKey,
  Value<String?> hubUrl,
  Value<String?> hubId,
  Value<String?> source,
  Value<DateTime?> lastVerifiedAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$LocalClientSettingsTableFilterComposer
    extends Composer<_$ClientDatabase, $LocalClientSettingsTable> {
  $$LocalClientSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get settingKey => $composableBuilder(
      column: $table.settingKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get hubUrl => $composableBuilder(
      column: $table.hubUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get hubId => $composableBuilder(
      column: $table.hubId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastVerifiedAt => $composableBuilder(
      column: $table.lastVerifiedAt,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$LocalClientSettingsTableOrderingComposer
    extends Composer<_$ClientDatabase, $LocalClientSettingsTable> {
  $$LocalClientSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get settingKey => $composableBuilder(
      column: $table.settingKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get hubUrl => $composableBuilder(
      column: $table.hubUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get hubId => $composableBuilder(
      column: $table.hubId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get source => $composableBuilder(
      column: $table.source, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastVerifiedAt => $composableBuilder(
      column: $table.lastVerifiedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$LocalClientSettingsTableAnnotationComposer
    extends Composer<_$ClientDatabase, $LocalClientSettingsTable> {
  $$LocalClientSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get settingKey => $composableBuilder(
      column: $table.settingKey, builder: (column) => column);

  GeneratedColumn<String> get hubUrl =>
      $composableBuilder(column: $table.hubUrl, builder: (column) => column);

  GeneratedColumn<String> get hubId =>
      $composableBuilder(column: $table.hubId, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<DateTime> get lastVerifiedAt => $composableBuilder(
      column: $table.lastVerifiedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$LocalClientSettingsTableTableManager extends RootTableManager<
    _$ClientDatabase,
    $LocalClientSettingsTable,
    LocalClientSetting,
    $$LocalClientSettingsTableFilterComposer,
    $$LocalClientSettingsTableOrderingComposer,
    $$LocalClientSettingsTableAnnotationComposer,
    $$LocalClientSettingsTableCreateCompanionBuilder,
    $$LocalClientSettingsTableUpdateCompanionBuilder,
    (
      LocalClientSetting,
      BaseReferences<_$ClientDatabase, $LocalClientSettingsTable,
          LocalClientSetting>
    ),
    LocalClientSetting,
    PrefetchHooks Function()> {
  $$LocalClientSettingsTableTableManager(
      _$ClientDatabase db, $LocalClientSettingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalClientSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalClientSettingsTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalClientSettingsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> settingKey = const Value.absent(),
            Value<String?> hubUrl = const Value.absent(),
            Value<String?> hubId = const Value.absent(),
            Value<String?> source = const Value.absent(),
            Value<DateTime?> lastVerifiedAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalClientSettingsCompanion(
            settingKey: settingKey,
            hubUrl: hubUrl,
            hubId: hubId,
            source: source,
            lastVerifiedAt: lastVerifiedAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String settingKey,
            Value<String?> hubUrl = const Value.absent(),
            Value<String?> hubId = const Value.absent(),
            Value<String?> source = const Value.absent(),
            Value<DateTime?> lastVerifiedAt = const Value.absent(),
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              LocalClientSettingsCompanion.insert(
            settingKey: settingKey,
            hubUrl: hubUrl,
            hubId: hubId,
            source: source,
            lastVerifiedAt: lastVerifiedAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$LocalClientSettingsTableProcessedTableManager = ProcessedTableManager<
    _$ClientDatabase,
    $LocalClientSettingsTable,
    LocalClientSetting,
    $$LocalClientSettingsTableFilterComposer,
    $$LocalClientSettingsTableOrderingComposer,
    $$LocalClientSettingsTableAnnotationComposer,
    $$LocalClientSettingsTableCreateCompanionBuilder,
    $$LocalClientSettingsTableUpdateCompanionBuilder,
    (
      LocalClientSetting,
      BaseReferences<_$ClientDatabase, $LocalClientSettingsTable,
          LocalClientSetting>
    ),
    LocalClientSetting,
    PrefetchHooks Function()>;

class $ClientDatabaseManager {
  final _$ClientDatabase _db;
  $ClientDatabaseManager(this._db);
  $$LocalCategoriesTableTableManager get localCategories =>
      $$LocalCategoriesTableTableManager(_db, _db.localCategories);
  $$LocalProductsTableTableManager get localProducts =>
      $$LocalProductsTableTableManager(_db, _db.localProducts);
  $$LocalProductBarcodesTableTableManager get localProductBarcodes =>
      $$LocalProductBarcodesTableTableManager(_db, _db.localProductBarcodes);
  $$LocalSalesTableTableManager get localSales =>
      $$LocalSalesTableTableManager(_db, _db.localSales);
  $$LocalSaleItemsTableTableManager get localSaleItems =>
      $$LocalSaleItemsTableTableManager(_db, _db.localSaleItems);
  $$LocalStockMovementsTableTableManager get localStockMovements =>
      $$LocalStockMovementsTableTableManager(_db, _db.localStockMovements);
  $$LocalRefundsTableTableManager get localRefunds =>
      $$LocalRefundsTableTableManager(_db, _db.localRefunds);
  $$LocalRefundItemsTableTableManager get localRefundItems =>
      $$LocalRefundItemsTableTableManager(_db, _db.localRefundItems);
  $$LocalPriceHistoryTableTableManager get localPriceHistory =>
      $$LocalPriceHistoryTableTableManager(_db, _db.localPriceHistory);
  $$OutboxOperationsTableTableManager get outboxOperations =>
      $$OutboxOperationsTableTableManager(_db, _db.outboxOperations);
  $$ClientSyncStatesTableTableManager get clientSyncStates =>
      $$ClientSyncStatesTableTableManager(_db, _db.clientSyncStates);
  $$LocalClientSettingsTableTableManager get localClientSettings =>
      $$LocalClientSettingsTableTableManager(_db, _db.localClientSettings);
}
