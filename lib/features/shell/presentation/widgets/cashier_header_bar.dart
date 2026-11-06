import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../diagnostics/application/system_status_notifier.dart';
import '../../../diagnostics/presentation/widgets/status_badge.dart';

/// Windows Masaüstü Üst Kasa Başlık Çubuğu
class CashierHeaderBar extends ConsumerWidget {
  const CashierHeaderBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(systemStatusProvider);

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: AppTheme.cardBgLight,
        border: Border(
          bottom: BorderSide(color: AppTheme.borderSubtle, width: 1.5),
        ),
      ),
      child: Row(
        children: [
          // Sol: Logo & Sistem Başlığı
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.point_of_sale,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MARKET MANAGEMENT SYSTEM',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textMainLight,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                'Windows Masaüstü Kasa İstemcisi • ${status.deviceId}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textMutedLight,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),

          // Sağ: Hub Bağlantı Rozeti ve Yenileme Butonu
          StatusBadge(state: status.backendState),
          const SizedBox(width: 16),
          IconButton(
            tooltip: 'Sistem Durumunu Yenile',
            icon: const Icon(Icons.refresh, color: AppTheme.textMutedLight),
            onPressed: () {
              ref.read(systemStatusProvider.notifier).refreshStatus();
            },
          ),
        ],
      ),
    );
  }
}
