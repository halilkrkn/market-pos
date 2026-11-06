import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../application/system_status_notifier.dart';
import '../../domain/system_status.dart';
import '../widgets/status_badge.dart';

/// MARKET MMS - Sistem Durumu ve Tanılama Ekranı (Faz 1.1)
class DiagnosticsView extends ConsumerWidget {
  const DiagnosticsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(systemStatusProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sistem Durumu ve Altyapı Tanılama',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Faz 1.1: Windows Client Foundation — Hub API ve Drift Yerel Depolama Entegrasyonu',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                key: const Key('refresh_button'),
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('Durumu Yenile'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  ref.read(systemStatusProvider.notifier).refreshStatus();
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 1. Kart: Merkezi Shelf Backend (Hub) Durumu
          _buildHubCard(context, status),
          const SizedBox(height: 16),

          // 2. Kart: İstemci Yerel Veritabanı (client_local.db) Durumu
          _buildLocalStorageCard(context, status),
          const SizedBox(height: 16),

          // 3. Kart: Mimari Güvenlik ve Uyumluluk Notları
          _buildArchitectureSafetyCard(context),
        ],
      ),
    );
  }

  Widget _buildHubCard(BuildContext context, SystemStatus status) {
    final bool isOnline = status.backendState == BackendConnectionState.online;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.dns_outlined,
                  color: isOnline ? AppTheme.statusOnline : AppTheme.statusOffline,
                  size: 28,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Merkezi Shelf HTTPS/HTTP Sunucusu (Master Hub)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMainLight,
                        ),
                      ),
                      Text(
                        status.backendUrl,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textMutedLight,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusBadge(state: status.backendState),
              ],
            ),
            const Divider(height: 28),
            Wrap(
              spacing: 32,
              runSpacing: 12,
              children: [
                _buildMetric(
                  'Gecikme (Latency)',
                  '${status.backendLatencyMs} ms',
                  icon: Icons.speed,
                  isMonospace: true,
                ),
                _buildMetric(
                  'Merkezi SQLite Sürümü',
                  status.backendSqliteVersion,
                  icon: Icons.storage,
                ),
                _buildMetric(
                  'Kasa Cihaz Kimliği',
                  status.deviceId,
                  icon: Icons.computer,
                ),
                _buildMetric(
                  'Son Denetim',
                  '${status.lastChecked.hour.toString().padLeft(2, '0')}:${status.lastChecked.minute.toString().padLeft(2, '0')}:${status.lastChecked.second.toString().padLeft(2, '0')}',
                  icon: Icons.access_time,
                  isMonospace: true,
                ),
              ],
            ),
            if (status.errorMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppTheme.statusOffline, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        status.errorMessage!,
                        style: const TextStyle(
                          color: AppTheme.statusOffline,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocalStorageCard(BuildContext context, SystemStatus status) {
    final bool isReady = status.localDbState == LocalDatabaseState.ready;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_special_outlined,
                  color: isReady ? AppTheme.primaryBlue : AppTheme.statusOffline,
                  size: 28,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'İstemci Yerel Depolaması (client_local.db)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textMainLight,
                        ),
                      ),
                      Text(
                        status.localDbPath.isNotEmpty
                            ? status.localDbPath
                            : 'Varsayılan Uygulama Dizini',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textMutedLight,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isReady ? const Color(0xFFEFF6FF) : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isReady ? AppTheme.primaryBlue : AppTheme.statusOffline,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    isReady ? 'DRIFT HAZIR (WAL)' : 'BAŞLATILAMADI',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isReady ? AppTheme.primaryBlue : AppTheme.statusOffline,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            Wrap(
              spacing: 32,
              runSpacing: 12,
              children: [
                _buildMetric(
                  'Bekleyen Outbox Kaydı',
                  '${status.pendingOutboxCount}',
                  icon: Icons.outbox,
                  isMonospace: true,
                  highlightColor: status.pendingOutboxCount > 0 ? AppTheme.statusWarning : null,
                ),
                _buildMetric(
                  'Yerel Satış Kaydı',
                  '${status.localSalesCount}',
                  icon: Icons.receipt_long,
                  isMonospace: true,
                ),
                _buildMetric(
                  'Önbellek Ürün Sayısı',
                  '${status.localProductsCount}',
                  icon: Icons.inventory_2_outlined,
                  isMonospace: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArchitectureSafetyCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9), // Slate 100
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: AppTheme.primaryBlue, size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mimari Sınır ve Güvenlik Güvencesi',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textMainLight,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '• Windows Masaüstü UI doğrudan merkezi master veritabanına (market_master.db) KESİNLİKLE bağlanmaz.\n'
                  '• Tüm veri okuma ve yazma işlemleri yalnızca yerel Drift (client_local.db) ve merkezi Shelf API istemcisi üzerinden yürütülür.\n'
                  '• Ağ kopsa dahi çevrimdışı satışlar yerel kuyruğa yazılır ve bağlantı sağlandığında idempotent olarak Hub\'a aktarılır.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textMutedLight,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(
    String label,
    String value, {
    required IconData icon,
    bool isMonospace = false,
    Color? highlightColor,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: AppTheme.textMutedLight),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppTheme.textMutedLight,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: highlightColor ?? AppTheme.textMainLight,
                fontFeatures: isMonospace ? AppTheme.tabularFiguresFeature : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
