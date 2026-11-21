import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../catalog_providers.dart';

class CategoryEditDialog extends ConsumerStatefulWidget {
  final LocalCategory? category;
  final List<LocalCategory> existingCategories;

  const CategoryEditDialog({
    super.key,
    this.category,
    required this.existingCategories,
  });

  @override
  ConsumerState<CategoryEditDialog> createState() => _CategoryEditDialogState();
}

class _CategoryEditDialogState extends ConsumerState<CategoryEditDialog> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _selectedParentId;
  bool _isSubmitting = false;

  bool get isEditing => widget.category != null;

  @override
  void initState() {
    super.initState();
    if (widget.category != null) {
      _nameController.text = widget.category!.name;
      _selectedParentId = widget.category!.parentId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    bool success;
    if (isEditing) {
      success = await ref.read(catalogProvider.notifier).updateCategory(
            id: widget.category!.id,
            name: _nameController.text.trim(),
            parentId: _selectedParentId,
          );
    } else {
      success = await ref.read(catalogProvider.notifier).createCategory(
            name: _nameController.text.trim(),
            parentId: _selectedParentId,
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
    final eligibleParents = widget.existingCategories.where((c) {
      if (isEditing && c.id == widget.category!.id) return false;
      return c.parentId == null;
    }).toList();

    return AppDialog(
      title: isEditing ? 'Kategoriyi Düzenle' : 'Yeni Kategori Ekle',
      icon: Icons.category_outlined,
      iconColor: colors.emerald,
      maxWidth: 480,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Kategori Adı (Zorunlu)',
                hintText: 'Örn: İçecekler, Temel Gıda',
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Kategori adı boş olamaz.';
                }
                return null;
              },
            ),
            const SizedBox(height: MmsSpacing.md),
            DropdownButtonFormField<String?>(
              initialValue: _selectedParentId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Üst Kategori (İsteğe Bağlı)',
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Yok (Ana Kategori)'),
                ),
                ...eligibleParents.map(
                  (cat) => DropdownMenuItem<String?>(
                    value: cat.id,
                    child: Text(cat.name),
                  ),
                ),
              ],
              onChanged: (val) => setState(() => _selectedParentId = val),
            ),
          ],
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
