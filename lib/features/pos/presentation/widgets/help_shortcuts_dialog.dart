import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';

/// `F1` Yardım ve Onaylı Klavye Kısayolları penceresi.
class HelpShortcutsDialog extends StatelessWidget {
  const HelpShortcutsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: AlertDialog(
        key: const Key('help_shortcuts_dialog'),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: AppTheme.primaryBlue),
            SizedBox(width: 8),
            Text('Kasa Kısayolları ve İş Kuralları'),
          ],
        ),
        content: const SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HelpRow('F1', 'Bu yardım penceresini açar'),
              _HelpRow('F2', 'Seçili sepet satırının miktarını düzenler'),
              _HelpRow('F9', 'Kredi Kartı ile ödeme penceresini açar'),
              _HelpRow('F10', 'Nakit ödeme penceresini açar'),
              _HelpRow('Esc', 'Açık modalı kapatır / barkod girişini temizler'),
              Divider(height: 24),
              Text(
                '• USB HID barkod okuyucu ile okutulan aktif ürünler otomatik sepete eklenir ve aynı ürün tek satırda birleşir.\n'
                '• Yerel veritabanında bulunmayan barkod çevrimdışı eklenemez veya oluşturulamaz (Master Hub bağlantısı gerekir).\n'
                '• Eksi stokta satışa izin verilir ve uyarı gösterilir.\n'
                '• Kredi kartında harici POS terminaline tutar elle girilir.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textMutedLight,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Kapat [Esc]'),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: Text(
              keyBadge,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppTheme.textMainLight,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              description,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppTheme.textMainLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

