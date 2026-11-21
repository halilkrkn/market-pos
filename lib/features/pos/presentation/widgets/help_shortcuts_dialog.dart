import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';

/// `F1` Yardım ve Onaylı Klavye Kısayolları penceresi.
class HelpShortcutsDialog extends StatelessWidget {
  const HelpShortcutsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: AppDialog(
        key: const Key('help_shortcuts_dialog'),
        title: 'Kasa Kısayolları ve İş Kuralları',
        icon: Icons.help_outline_rounded,
        iconColor: colors.emerald,
        maxWidth: 500,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _HelpRow('F1', 'Bu yardım penceresini açar'),
              const _HelpRow('F2', 'Seçili sepet satırının miktarını düzenler'),
              const _HelpRow('F9', 'Kredi Kartı ile ödeme penceresini açar'),
              const _HelpRow('F10', 'Nakit ödeme penceresini açar'),
              const _HelpRow(
                'Esc',
                'Açık modalı kapatır / barkod girişini temizler',
              ),
              Divider(height: MmsSpacing.xl, color: colors.border),
              Text(
                '• USB HID barkod okuyucu ile okutulan aktif ürünler otomatik sepete eklenir ve aynı ürün tek satırda birleşir.\n'
                '• Yerel veritabanında bulunmayan barkod çevrimdışı eklenemez veya oluşturulamaz (Master Hub bağlantısı gerekir).\n'
                '• Eksi stokta satışa izin verilir ve uyarı gösterilir.\n'
                '• Kredi kartında harici POS terminaline tutar elle girilir.',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        actions: [
          AppButton(
            label: 'Kapat [Esc]',
            variant: AppButtonVariant.primary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _HelpRow extends StatelessWidget {
  final String keyBadge;
  final String description;

  const _HelpRow(this.keyBadge, this.description);

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surfaceSubtle,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.borderStrong),
            ),
            child: Text(
              keyBadge,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: colors.textPrimary,
                fontFeatures: MmsTypography.tabularFigures,
              ),
            ),
          ),
          const SizedBox(width: MmsSpacing.sm),
          Expanded(
            child: Text(
              description,
              style: TextStyle(
                fontSize: 13.5,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
