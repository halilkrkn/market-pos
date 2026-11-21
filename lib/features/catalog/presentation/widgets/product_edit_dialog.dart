import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/platform/mms_ui_profile.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../barcode_scanner/barcode_scanner_providers.dart';
import '../../../barcode_scanner/domain/camera_scan_result.dart';
import '../../../pos/domain/barcode_input_sanitizer.dart';
import '../../../pos/domain/money.dart';
import '../../catalog_providers.dart';
import '../../domain/external_product_suggestion.dart';
import 'external_product_suggestion_card.dart';

class ProductEditDialog extends ConsumerStatefulWidget {
  final LocalProduct? product;
  final List<LocalCategory> categories;
  final String? initialBarcode;
  final bool autoLookupExternal;

  const ProductEditDialog({
    super.key,
    this.product,
    required this.categories,
    this.initialBarcode,
    this.autoLookupExternal = false,
  });

  @override
  ConsumerState<ProductEditDialog> createState() => _ProductEditDialogState();
}

class _ProductEditDialogState extends ConsumerState<ProductEditDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _stockController;
  late final TextEditingController _purchasePriceController;
  late final TextEditingController _priceChangeReasonController;

  String? _selectedCategoryId;
  String _selectedStockUnit = 'adet';
  int _selectedVatRate = 20;
  bool _isSubmitting = false;
  bool _isLookingUpExternal = false;
  LocalProduct? _existingBarcodeProduct;
  ExternalProductSuggestion? _externalSuggestion;
  String? _externalLookupMessage;
  bool _suggestionApplied = false;

  static const Set<String> _supportedUnits = {
    'adet',
    'kg',
    'g',
    'l',
    'ml',
    'paket',
    'kutu',
  };

  bool get isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(text: p?.name ?? '');
    _priceController = TextEditingController(
      text: p != null ? Money.formatCentsInput(p.price) : '',
    );
    final sanitizedInitialBarcode = widget.initialBarcode != null
        ? BarcodeInputSanitizer.sanitize(widget.initialBarcode!)
        : null;
    final resolvedInitialBarcode = p?.barcode ??
        ((sanitizedInitialBarcode?.isValid ?? false)
            ? sanitizedInitialBarcode!.normalized
            : '');
    _barcodeController = TextEditingController(text: resolvedInitialBarcode);
    _stockController = TextEditingController(
      text: p != null ? '${p.stock ~/ 1000}' : '0',
    );
    _priceChangeReasonController = TextEditingController();
    _purchasePriceController = TextEditingController();

    if (p != null) {
      _selectedCategoryId = p.categoryId;
      _selectedStockUnit = p.stockUnit;
      _selectedVatRate = p.vatRate;
    }

    if (!isEditing && resolvedInitialBarcode.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _checkLocalProductByBarcode(resolvedInitialBarcode);
        if (mounted &&
            widget.autoLookupExternal &&
            _existingBarcodeProduct == null) {
          await _lookupExternalProduct();
        }
      });
    }
  }

  Future<void> _lookupExternalProduct() async {
    final sanitized = BarcodeInputSanitizer.sanitize(_barcodeController.text);
    if (!sanitized.isValid) {
      setState(() {
        _externalSuggestion = null;
        _externalLookupMessage =
            sanitized.errorMessage ?? 'Harici sorgu için geçerli bir barkod giriniz.';
      });
      return;
    }

    setState(() {
      _isLookingUpExternal = true;
      _externalLookupMessage = null;
      _suggestionApplied = false;
    });

    final result = await ref
        .read(externalProductLookupServiceProvider)
        .lookupByBarcode(sanitized.normalized);
    if (!mounted) return;

    setState(() {
      _isLookingUpExternal = false;
      if (result.isFound) {
        _externalSuggestion = result.suggestion;
        _externalLookupMessage = null;
      } else {
        _externalSuggestion = null;
        _externalLookupMessage = result.message;
      }
    });
  }

  void _applyExternalSuggestion(ExternalProductSuggestion suggestion) {
    final activeCategories = widget.categories.where((c) => c.isActive).toList();
    String? matchedCategoryId = _selectedCategoryId;
    for (final extCat in suggestion.categories) {
      final lowerExt = extCat.toLowerCase();
      for (final localCat in activeCategories) {
        final lowerLocal = localCat.name.toLowerCase();
        if (lowerLocal == lowerExt ||
            lowerExt.contains(lowerLocal) ||
            lowerLocal.contains(lowerExt)) {
          matchedCategoryId = localCat.id;
          break;
        }
      }
      if (matchedCategoryId != _selectedCategoryId) break;
    }

    final nextUnit = (suggestion.suggestedUnit != null &&
            _supportedUnits.contains(suggestion.suggestedUnit))
        ? suggestion.suggestedUnit!
        : _selectedStockUnit;

    // Satış fiyatı, maliyet ve stok alanlarına KESİNLİKLE dokunulmaz (Faz 5 Kuralı).
    setState(() {
      _nameController.text = suggestion.suggestedDisplayName;
      _selectedCategoryId = matchedCategoryId;
      _selectedStockUnit = nextUnit;
      _suggestionApplied = true;
    });
  }

  Future<void> _checkLocalProductByBarcode(String barcode) async {
    try {
      final existing = await ref
          .read(catalogRepositoryProvider)
          .getProductByBarcode(barcode);
      if (!mounted) return;
      setState(() {
        if (existing != null && existing.id != widget.product?.id) {
          _existingBarcodeProduct = existing;
        } else {
          _existingBarcodeProduct = null;
        }
      });
    } catch (_) {}
  }

  Future<void> _handleCameraBarcodeScan() async {
    final scanResult = await ref.read(cameraBarcodeScannerProvider).scanBarcode(
      context,
      title: 'Ürün Barkodu Tara',
      subtitle: 'Ürüne atanacak barkodu kamera çerçevesine hizalayın',
    );
    if (!mounted) return;

    switch (scanResult.status) {
      case CameraScanStatus.scanned:
        final raw = scanResult.barcode;
        if (raw == null) return;
        final sanitized = BarcodeInputSanitizer.sanitize(raw);
        if (!sanitized.isValid) {
          AppSnackbar.show(
            context,
            message: sanitized.errorMessage ?? 'Geçersiz barkod biçimi.',
            tone: AppBadgeTone.warning,
          );
          return;
        }
        _barcodeController.text = sanitized.normalized;
        await _checkLocalProductByBarcode(sanitized.normalized);
        if (mounted && !isEditing && _existingBarcodeProduct == null) {
          await _lookupExternalProduct();
        }
        break;
      case CameraScanStatus.permissionDenied:
      case CameraScanStatus.error:
      case CameraScanStatus.unsupportedPlatform:
        AppSnackbar.show(
          context,
          message:
              scanResult.errorMessage ?? 'Kamera ile barkod okunamadı.',
          tone: AppBadgeTone.warning,
        );
        break;
      case CameraScanStatus.cancelled:
        break;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _barcodeController.dispose();
    _stockController.dispose();
    _purchasePriceController.dispose();
    _priceChangeReasonController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final parsedPriceCents = Money.tryParseLiraToCents(_priceController.text);
    if (parsedPriceCents == null || parsedPriceCents <= 0) {
      AppSnackbar.show(
        context,
        message: 'Lütfen geçerli ve sıfırdan büyük bir satış fiyatı giriniz.',
        tone: AppBadgeTone.danger,
      );
      return;
    }

    final parsedStockInt = int.tryParse(_stockController.text.trim()) ?? 0;
    final initialStockMilli = parsedStockInt * 1000;

    // Faz 2 §4.2: Opsiyonel birim alış fiyatı (başlangıç stok hareketine yazılır)
    int? purchasePriceCents;
    final purchaseText = _purchasePriceController.text.trim();
    if (!isEditing && purchaseText.isNotEmpty) {
      purchasePriceCents = Money.tryParseLiraToCents(purchaseText);
      if (purchasePriceCents == null || purchasePriceCents < 0) {
        AppSnackbar.show(
          context,
          message: 'Alış fiyatı geçersiz. Örnek: 7,50',
          tone: AppBadgeTone.danger,
        );
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
    });

    bool success;
    if (isEditing) {
      success = await ref.read(catalogProvider.notifier).updateProduct(
            id: widget.product!.id,
            name: _nameController.text.trim(),
            price: parsedPriceCents,
            categoryId: _selectedCategoryId,
            barcode: _barcodeController.text.trim().isEmpty
                ? null
                : _barcodeController.text.trim(),
            stockUnit: _selectedStockUnit,
            pricingUnit: _selectedStockUnit,
            vatRate: _selectedVatRate,
            priceChangeReason:
                _priceChangeReasonController.text.trim().isNotEmpty
                    ? _priceChangeReasonController.text.trim()
                    : null,
          );
    } else {
      success = await ref.read(catalogProvider.notifier).createProduct(
            name: _nameController.text.trim(),
            price: parsedPriceCents,
            barcode: _barcodeController.text.trim().isEmpty
                ? null
                : _barcodeController.text.trim(),
            categoryId: _selectedCategoryId,
            initialStock: initialStockMilli,
            stockUnit: _selectedStockUnit,
            pricingUnit: _selectedStockUnit,
            vatRate: _selectedVatRate,
            initialPurchasePrice: purchasePriceCents,
          );
    }

    if (mounted) {
      setState(() {
        _isSubmitting = false;
      });
      if (success) {
        Navigator.of(context).pop(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final uiProfile = ref.watch(mmsUiProfileProvider);
    final activeCategories =
        widget.categories.where((c) => c.isActive).toList();
    final isNarrow = MediaQuery.sizeOf(context).width < 520;

    final nameField = TextFormField(
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: 'Ürün Adı (Zorunlu)',
        hintText: 'Örn: Çay 1kg, Süt 1L, Ekmek 200g',
      ),
      validator: (val) {
        if (val == null || val.trim().isEmpty) {
          return 'Ürün adı boş olamaz (BR-PROD-01).';
        }
        return null;
      },
    );

    final priceField = TextFormField(
      controller: _priceController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(
        color: colors.textPrimary,
        fontFeatures: MmsTypography.tabularFigures,
      ),
      decoration: const InputDecoration(
        labelText: 'Satış Fiyatı (TL, Zorunlu)',
        hintText: 'Örn: 25.50',
        suffixText: 'TL',
      ),
      validator: (val) {
        if (val == null || val.trim().isEmpty) {
          return 'Fiyat giriniz.';
        }
        final cents = Money.tryParseLiraToCents(val);
        if (cents == null || cents <= 0) {
          return 'Geçerli bir tutar (> 0) giriniz.';
        }
        return null;
      },
    );

    final unitDropdown = DropdownButtonFormField<String>(
      initialValue: _selectedStockUnit,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Birim'),
      items: const [
        DropdownMenuItem(value: 'adet', child: Text('Adet')),
        DropdownMenuItem(value: 'kg', child: Text('Kilogram (kg)')),
        DropdownMenuItem(value: 'g', child: Text('Gram (g)')),
        DropdownMenuItem(value: 'l', child: Text('Litre (L)')),
        DropdownMenuItem(value: 'ml', child: Text('Mililitre (ml)')),
        DropdownMenuItem(value: 'paket', child: Text('Paket')),
        DropdownMenuItem(value: 'kutu', child: Text('Kutu')),
      ],
      onChanged: (val) {
        if (val != null) setState(() => _selectedStockUnit = val);
      },
    );

    final categoryDropdown = DropdownButtonFormField<String?>(
      initialValue: _selectedCategoryId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Kategori (BR-PROD-01)'),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Kategori Yok / Genel'),
        ),
        ...activeCategories.map(
          (c) => DropdownMenuItem<String?>(
            value: c.id,
            child: Text(c.name),
          ),
        ),
      ],
      onChanged: (val) => setState(() => _selectedCategoryId = val),
    );

    final barcodeField = TextFormField(
      controller: _barcodeController,
      style: TextStyle(
        color: colors.textPrimary,
        fontFeatures: MmsTypography.tabularFigures,
      ),
      onChanged: (val) {
        final sanitized = BarcodeInputSanitizer.sanitize(val);
        if (sanitized.isValid) {
          _checkLocalProductByBarcode(sanitized.normalized);
        } else if (_existingBarcodeProduct != null) {
          setState(() => _existingBarcodeProduct = null);
        }
      },
      decoration: const InputDecoration(
        labelText: 'Barkod (İsteğe Bağlı)',
        hintText: 'Barkod okutun veya yazın',
      ),
    );

    final imageBuilder = ref.watch(externalProductImageBuilderProvider);

    final lookupButton = AppButton(
      key: const Key('product_off_lookup_button'),
      label: _isLookingUpExternal ? 'Aranıyor...' : 'Bilgi Getir',
      icon: Icons.travel_explore_rounded,
      variant: AppButtonVariant.secondary,
      isLoading: _isLookingUpExternal,
      minHeight: 48,
      expand: true,
      onPressed: _isSubmitting ? null : _lookupExternalProduct,
    );

    final Widget? cameraBarcodeButton = uiProfile.supportsCameraBarcodeScanning
        ? AppButton(
            key: const Key('product_barcode_camera_button'),
            label: 'Kamera ile Tara',
            icon: Icons.qr_code_scanner_rounded,
            variant: AppButtonVariant.secondary,
            minHeight: 48,
            expand: true,
            onPressed: _isSubmitting ? null : _handleCameraBarcodeScan,
          )
        : null;

    final Widget barcodeActionRow = cameraBarcodeButton != null
        ? (isNarrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  cameraBarcodeButton,
                  const SizedBox(height: MmsSpacing.xs),
                  lookupButton,
                ],
              )
            : Row(
                children: [
                  Expanded(child: cameraBarcodeButton),
                  const SizedBox(width: MmsSpacing.sm),
                  Expanded(child: lookupButton),
                ],
              ))
        : lookupButton;

    final Widget? existingBarcodeNotice = _existingBarcodeProduct != null
        ? Container(
            key: const Key('product_existing_barcode_notice'),
            padding: const EdgeInsets.all(MmsSpacing.sm),
            decoration: BoxDecoration(
              color: colors.warningBg,
              borderRadius: BorderRadius.circular(MmsRadius.sm),
              border: Border.all(color: colors.warning),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 18,
                  color: colors.warningText,
                ),
                const SizedBox(width: MmsSpacing.xs),
                Expanded(
                  child: Text(
                    'Bu barkod yerel katalogda kayıtlı: ${_existingBarcodeProduct!.name}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: colors.warningText,
                    ),
                  ),
                ),
              ],
            ),
          )
        : null;

    final stockField = TextFormField(
      controller: _stockController,
      keyboardType: TextInputType.number,
      style: TextStyle(
        color: colors.textPrimary,
        fontFeatures: MmsTypography.tabularFigures,
      ),
      decoration: const InputDecoration(
        labelText: 'Başlangıç Stoğu (Tam Sayı)',
        hintText: 'Örn: 50',
      ),
    );

    final purchasePriceField = TextFormField(
      key: const Key('product_purchase_price_field'),
      controller: _purchasePriceController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(
        color: colors.textPrimary,
        fontFeatures: MmsTypography.tabularFigures,
      ),
      decoration: const InputDecoration(
        labelText: 'Birim Alış Fiyatı (TL, opsiyonel)',
        hintText: 'Örn: 7,50',
      ),
    );

    final vatDropdown = DropdownButtonFormField<int>(
      initialValue: _selectedVatRate,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'KDV Oranı (%)'),
      items: const [
        DropdownMenuItem(value: 1, child: Text('%1')),
        DropdownMenuItem(value: 10, child: Text('%10')),
        DropdownMenuItem(value: 20, child: Text('%20')),
      ],
      onChanged: (val) {
        if (val != null) setState(() => _selectedVatRate = val);
      },
    );

    return AppDialog(
      title: isEditing ? 'Ürün Bilgilerini Düzenle' : 'Yeni Ürün Tanımla',
      icon: isEditing ? Icons.edit_note_rounded : Icons.add_box_outlined,
      iconColor: colors.emerald,
      maxWidth: 640,
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              nameField,
              const SizedBox(height: MmsSpacing.md),
              if (isNarrow) ...[
                priceField,
                const SizedBox(height: MmsSpacing.md),
                unitDropdown,
              ] else
                Row(
                  children: [
                    Expanded(flex: 2, child: priceField),
                    const SizedBox(width: MmsSpacing.sm),
                    Expanded(flex: 1, child: unitDropdown),
                  ],
                ),
              const SizedBox(height: MmsSpacing.md),
              if (isNarrow) ...[
                categoryDropdown,
                const SizedBox(height: MmsSpacing.md),
                barcodeField,
              ] else
                Row(
                  children: [
                    Expanded(child: categoryDropdown),
                    const SizedBox(width: MmsSpacing.sm),
                    Expanded(child: barcodeField),
                  ],
                ),
              const SizedBox(height: MmsSpacing.sm),
              barcodeActionRow,
              if (_externalSuggestion != null) ...[
                const SizedBox(height: MmsSpacing.sm),
                ExternalProductSuggestionCard(
                  suggestion: _externalSuggestion!,
                  isApplied: _suggestionApplied,
                  imageBuilder: imageBuilder,
                  onApply: () => _applyExternalSuggestion(_externalSuggestion!),
                  onDismiss: () {
                    setState(() {
                      _externalSuggestion = null;
                      _suggestionApplied = false;
                    });
                  },
                ),
              ],
              if (_externalLookupMessage != null) ...[
                const SizedBox(height: MmsSpacing.sm),
                Container(
                  key: const Key('off_lookup_status_banner'),
                  padding: const EdgeInsets.all(MmsSpacing.sm),
                  decoration: BoxDecoration(
                    color: colors.infoBg,
                    borderRadius: BorderRadius.circular(MmsRadius.sm),
                    border: Border.all(color: colors.info),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: colors.infoText,
                      ),
                      const SizedBox(width: MmsSpacing.xs),
                      Expanded(
                        child: Text(
                          _externalLookupMessage!,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: colors.infoText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (existingBarcodeNotice != null) ...[
                const SizedBox(height: MmsSpacing.sm),
                existingBarcodeNotice,
              ],
              const SizedBox(height: MmsSpacing.md),
              if (isNarrow) ...[
                if (!isEditing) ...[
                  stockField,
                  const SizedBox(height: MmsSpacing.md),
                  purchasePriceField,
                  const SizedBox(height: MmsSpacing.md),
                ],
                vatDropdown,
              ] else ...[
                Row(
                  children: [
                    if (!isEditing) ...[
                      Expanded(child: stockField),
                      const SizedBox(width: MmsSpacing.sm),
                    ],
                    Expanded(child: vatDropdown),
                  ],
                ),
                if (!isEditing) ...[
                  const SizedBox(height: MmsSpacing.md),
                  purchasePriceField,
                ],
              ],
              if (isEditing) ...[
                const SizedBox(height: MmsSpacing.md),
                TextFormField(
                  controller: _priceChangeReasonController,
                  decoration: const InputDecoration(
                    labelText: 'Fiyat Değişiklik Gerekçesi (Fiyat değiştiyse)',
                    hintText: 'Örn: Tedarikçi zam yaptı, kampanya bitti',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        AppButton(
          label: 'Vazgeç',
          variant: AppButtonVariant.secondary,
          onPressed:
              _isSubmitting ? null : () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: _isSubmitting ? 'Kaydediliyor...' : 'Kaydet',
          variant: AppButtonVariant.emerald,
          isLoading: _isSubmitting,
          onPressed: _handleSave,
        ),
      ],
    );
  }
}
