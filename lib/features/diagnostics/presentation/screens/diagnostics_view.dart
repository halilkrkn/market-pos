import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/platform/mms_ui_profile.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../backup/presentation/widgets/backup_management_card.dart';
import '../../../security/presentation/widgets/device_security_card.dart';
import '../../../security/presentation/widgets/pairing_approval_panel.dart';
import '../../../setup/presentation/widgets/store_setup_card.dart';
import '../../../sync/application/hub_connection_notifier.dart';
import '../../../sync/domain/hub_connection_state.dart';
import '../../../sync/domain/sync_coordinator_state.dart';
import '../../../sync/sync_providers.dart';
import '../../../updates/presentation/widgets/app_update_card.dart';
import '../../application/system_status_notifier.dart';
import '../../domain/system_status.dart';
import '../widgets/diagnostics_card_helpers.dart';
import '../widgets/diagnostics_export_card.dart';
import '../widgets/hub_connection_controls.dart';
import '../widgets/outbox_status_badge.dart';
import '../widgets/status_badge.dart';

/// MARKET MMS — Sistem Durumu, Senkronizasyon ve Görünüm Ayarları Ekranı
class DiagnosticsView extends ConsumerWidget {
  const DiagnosticsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(systemStatusProvider);
    final hubConnection = ref.watch(hubConnectionProvider);
    final syncState = ref.watch(backgroundSyncCoordinatorProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isCompact = context.windowClass == MmsWindowClass.compact;

    return RefreshIndicator(
      onRefresh: () => ref.read(systemStatusProvider.notifier).refreshStatus(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isCompact ? MmsSpacing.md : MmsSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPageHeader(
              title: 'Sistem Durumu ve Altyapı Tanılama',
              subtitle: 'Master Hub bağlantısı, yerel Drift SQLite depolaması, senkronizasyon ve tema tercihleri',
              actions: [
                AppButton(
                  key: const Key('refresh_button'),
                  label: 'Durumu Yenile',
                  icon: Icons.refresh_rounded,
                  variant: AppButtonVariant.primary,
                  minHeight: 48,
                  onPressed: () {
                    ref.read(systemStatusProvider.notifier).refreshStatus();
                  },
                ),
              ],
            ),
          const SizedBox(height: MmsSpacing.lg),

          // 1. Kart: Görünüm ve Tema Ayarları (Light / Dark / System)
          _buildAppearanceCard(context, ref, themeMode),
          const SizedBox(height: MmsSpacing.md),

          // 2. Kart: Merkezi Shelf Backend (Hub) Durumu
          _buildHubCard(context, status, hubConnection),
          const SizedBox(height: MmsSpacing.md),

          // 3. Kart: Arka Plan Senkronizasyon Koordinatörü
          _buildSyncCoordinatorCard(context, ref, syncState, status),
          const SizedBox(height: MmsSpacing.md),

          // 4. Kart: İstemci Yerel Veritabanı (client_local.db) Durumu
          _buildLocalStorageCard(context, status),
          const SizedBox(height: MmsSpacing.md),

          // 5. Kart: Mağaza, Şube ve Cihaz Kurulumu
          const StoreSetupCard(),
          const SizedBox(height: MmsSpacing.md),

          // 6. Kart: Şifreli Yedekleme ve Kurtarma (S5A-4)
          const BackupManagementCard(),
          const SizedBox(height: MmsSpacing.md),

          // 7. Kart: Cihaz Güvenliği, TLS Pinning (B-2) & Token Deposu (B-3)
          const DeviceSecurityCard(),
          const SizedBox(height: MmsSpacing.md),

          // 7.1 Kart (yalnızca Windows/Hub bilgisayarı): Owner eşleştirme onay/red
          if (ref.watch(mmsUiProfileProvider).isDesktop) ...[
            const PairingApprovalPanel(),
            const SizedBox(height: MmsSpacing.md),
          ],

          // 8. Kart: Uygulama Sürümü ve Güncelleme Kontrolü
          const AppUpdateCard(),
          const SizedBox(height: MmsSpacing.md),

          // 9. Kart: Maskeli Tanı ve Destek Dışa Aktarımı
          const DiagnosticsExportCard(),
          const SizedBox(height: MmsSpacing.md),

          // 10. Kart: Mimari Güvenlik ve Uyumluluk Notları
          _buildArchitectureSafetyCard(context),
        ],
      ),
      ),
    );
  }

  Widget _buildAppearanceCard(
    BuildContext context,
    WidgetRef ref,
    ThemeMode themeMode,
  ) {
    final colors = context.mmsColors;

    return AppCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.limeAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(MmsRadius.md),
                ),
                child: Icon(
                  Icons.palette_outlined,
                  color: colors.primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: MmsSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Görünüm ve Tema Tercihi',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      'Modern Emerald — Açık, Koyu veya Sistem teması seçimi',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: MmsSpacing.md),
          Wrap(
            spacing: MmsSpacing.xs,
            runSpacing: MmsSpacing.xs,
            children: [
              _themeChip(
                context: context,
                key: const Key('theme_mode_light'),
                label: 'Açık Tema',
                icon: Icons.light_mode_rounded,
                selected: themeMode == ThemeMode.light,
                onTap: () => ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(ThemeMode.light),
              ),
              _themeChip(
                context: context,
                key: const Key('theme_mode_dark'),
                label: 'Koyu Tema',
                icon: Icons.dark_mode_rounded,
                selected: themeMode == ThemeMode.dark,
                onTap: () => ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(ThemeMode.dark),
              ),
              _themeChip(
                context: context,
                key: const Key('theme_mode_system'),
                label: 'Sistem',
                icon: Icons.brightness_auto_rounded,
                selected: themeMode == ThemeMode.system,
                onTap: () => ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(ThemeMode.system),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _themeChip({
    required BuildContext context,
    required Key key,
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = context.mmsColors;
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(MmsRadius.sm),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(
          horizontal: MmsSpacing.md,
          vertical: MmsSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.surfaceSubtle,
          borderRadius: BorderRadius.circular(MmsRadius.sm),
          border: Border.all(
            color: selected ? colors.primary : colors.borderStrong,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? colors.onPrimary : colors.textSecondary,
            ),
            const SizedBox(width: MmsSpacing.xs),
            Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: selected ? colors.onPrimary : colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHubCard(
    BuildContext context,
    SystemStatus status,
    HubConnectionState hubConnection,
  ) {
    final colors = context.mmsColors;
    final bool isOnline = status.backendState == BackendConnectionState.online;
    final rawUrl = hubConnection.activeHubUrl ?? status.backendUrl;
    final displayedUrl = rawUrl.trim().isNotEmpty
        ? rawUrl
        : 'Henüz yapılandırılmadı';
    final (String phaseLabel, AppBadgeTone phaseTone) =
        switch (hubConnection.phase) {
      HubConnectionPhase.unconfigured => (
        'Yapılandırılmadı',
        AppBadgeTone.neutral,
      ),
      HubConnectionPhase.discovering => (
        'Hub Aranıyor (UDP 8946)',
        AppBadgeTone.info,
      ),
      HubConnectionPhase.verifying => ('Doğrulanıyor', AppBadgeTone.info),
      HubConnectionPhase.connected => ('Bağlı', AppBadgeTone.success),
      HubConnectionPhase.offline => (
        'Kayıtlı Adres (Çevrimdışı)',
        AppBadgeTone.warning,
      ),
      HubConnectionPhase.needsDiscovery => (
        'Keşif Gerekli',
        AppBadgeTone.warning,
      ),
    };
    final String? sourceLabel = switch (hubConnection.source) {
      HubUrlSource.discovered => 'Otomatik Keşif',
      HubUrlSource.lastVerified => 'Son Doğrulanan',
      HubUrlSource.manual => 'Manuel',
      HubUrlSource.configured => 'Yapılandırma',
      HubUrlSource.localhostFallback => 'Yerel Masaüstü',
      null => null,
    };

    return AppCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isOnline ? colors.successBg : colors.dangerBg,
                  borderRadius: BorderRadius.circular(MmsRadius.md),
                ),
                child: Icon(
                  Icons.dns_rounded,
                  color: isOnline ? colors.successText : colors.dangerText,
                  size: 21,
                ),
              ),
              const SizedBox(width: MmsSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Merkezi Shelf HTTPS/HTTP Sunucusu (Master Hub)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayedUrl,
                      key: const Key('diagnostics_hub_url'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.textSecondary,
                        fontFeatures: MmsTypography.tabularFigures,
                      ),
                    ),
                    const SizedBox(height: MmsSpacing.xs),
                    Wrap(
                      spacing: MmsSpacing.xs,
                      runSpacing: MmsSpacing.xs,
                      children: [
                        StatusBadge(state: status.backendState),
                        AppBadge(
                          label: phaseLabel,
                          tone: phaseTone,
                          compact: true,
                        ),
                        if (sourceLabel != null)
                          AppBadge(
                            label: 'Kaynak: $sourceLabel',
                            tone: AppBadgeTone.info,
                            compact: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          Divider(height: MmsSpacing.xl, color: colors.border),
          Wrap(
            spacing: MmsSpacing.xl,
            runSpacing: MmsSpacing.sm,
            children: [
              _buildMetric(
                context,
                'Gecikme (Latency)',
                '${status.backendLatencyMs} ms',
                icon: Icons.speed_rounded,
                isMonospace: true,
              ),
              _buildMetric(
                context,
                'Merkezi SQLite Sürümü',
                status.backendSqliteVersion,
                icon: Icons.storage_rounded,
              ),
              _buildMetric(
                context,
                'Kasa Cihaz Kimliği',
                status.deviceId,
                icon: Icons.computer_rounded,
              ),
              if (hubConnection.hubId != null &&
                  hubConnection.hubId!.isNotEmpty)
                _buildMetric(
                  context,
                  'Hub Kimliği',
                  hubConnection.hubId!,
                  icon: Icons.hub_rounded,
                ),
              _buildMetric(
                context,
                'Son Denetim',
                '${status.lastChecked.hour.toString().padLeft(2, '0')}:${status.lastChecked.minute.toString().padLeft(2, '0')}:${status.lastChecked.second.toString().padLeft(2, '0')}',
                icon: Icons.access_time_rounded,
                isMonospace: true,
              ),
            ],
          ),
          if (status.errorMessage != null) ...[
            const SizedBox(height: MmsSpacing.md),
            AppErrorState(message: status.errorMessage!, inline: true),
          ],
          const SizedBox(height: MmsSpacing.md),
          const HubConnectionControls(),
        ],
      ),
    );
  }

  @visibleForTesting
  Widget buildSyncCoordinatorCardForTest(
    BuildContext context,
    WidgetRef ref,
    SyncCoordinatorState syncState,
    SystemStatus status,
  ) =>
      _buildSyncCoordinatorCard(context, ref, syncState, status);

  Widget _buildSyncCoordinatorCard(
    BuildContext context,
    WidgetRef ref,
    SyncCoordinatorState syncState,
    SystemStatus status,
  ) {
    final colors = context.mmsColors;
    final (String stateText, AppBadgeTone tone) = switch (syncState.status) {
      SyncCoordinatorStatus.syncing => (
        'SENKRONİZE EDİLİYOR',
        AppBadgeTone.info,
      ),
      SyncCoordinatorStatus.idle => ('BEKLEMEDE (HAZIR)', AppBadgeTone.success),
      SyncCoordinatorStatus.networkError => (
        'AĞ / BAĞLANTI HATASI',
        AppBadgeTone.warning,
      ),
      SyncCoordinatorStatus.permanentError => (
        'KALICI KUYRUK HATASI',
        AppBadgeTone.danger,
      ),
      SyncCoordinatorStatus.authRequired => (
        'CİHAZ YETKİSİ GEREKLİ',
        AppBadgeTone.warning,
      ),
      SyncCoordinatorStatus.error => (
        'SENKRONİZASYON HATASI',
        AppBadgeTone.danger,
      ),
      SyncCoordinatorStatus.paused => (
        'DURAKLATILDI (BAKIM / GERİ YÜKLEME)',
        AppBadgeTone.info,
      ),
      SyncCoordinatorStatus.tlsPinMismatch => (
        'GÜVENLİK: HUB SERTİFİKASI UYUŞMUYOR',
        AppBadgeTone.danger,
      ),
      SyncCoordinatorStatus.tlsCertError => (
        'SERTİFİKA HATASI (SAN / TARİH)',
        AppBadgeTone.warning,
      ),
    };

    return AppCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.infoBg,
                  borderRadius: BorderRadius.circular(MmsRadius.md),
                ),
                child: Icon(
                  Icons.sync_rounded,
                  color: colors.infoText,
                  size: 21,
                ),
              ),
              const SizedBox(width: MmsSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Arka Plan Senkronizasyon Koordinatörü',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'FIFO Outbox aktarımı, 30sn periyodik tarama ve idempotency',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: MmsSpacing.xs),
                    Wrap(
                      spacing: MmsSpacing.xs,
                      runSpacing: MmsSpacing.xs,
                      children: [
                        AppBadge(label: stateText, tone: tone, compact: true),
                        OutboxStatusBadge(
                          summary: status.outboxSummary,
                          isDatabaseError:
                              status.localDbState == LocalDatabaseState.error,
                          compact: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          Divider(height: MmsSpacing.xl, color: colors.border),
          Wrap(
            spacing: MmsSpacing.xl,
            runSpacing: MmsSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildMetric(
                context,
                'Bekleyen (PENDING)',
                '${status.outboxSummary.pending}',
                icon: Icons.schedule_rounded,
                isMonospace: true,
              ),
              _buildMetric(
                context,
                'Tekrar (RETRY)',
                '${status.outboxSummary.retry}',
                icon: Icons.replay_rounded,
                isMonospace: true,
              ),
              _buildMetric(
                context,
                'Kalıcı Hata',
                '${status.outboxSummary.failedPermanent}',
                icon: Icons.error_outline_rounded,
                isMonospace: true,
                highlightColor: status.outboxSummary.failedPermanent > 0
                    ? colors.dangerText
                    : null,
              ),
              AppButton(
                label: 'Şimdi Senkronize Et',
                icon: Icons.sync_rounded,
                variant: AppButtonVariant.secondary,
                minHeight: 42,
                isLoading: syncState.isSyncing,
                onPressed: () {
                  ref
                      .read(backgroundSyncCoordinatorProvider.notifier)
                      .triggerSync(reason: SyncTriggerReason.manual);
                },
              ),
            ],
          ),
          if (syncState.errorMessage != null) ...[
            const SizedBox(height: MmsSpacing.sm),
            AppErrorState(message: syncState.errorMessage!, inline: true),
          ],
          // Faz 7A: Hub'dan indirme hataları görünür (sessizce yutulmaz).
          if (syncState.downlinkError != null) ...[
            const SizedBox(height: MmsSpacing.sm),
            AppErrorState(
              key: const Key('diagnostics_downlink_error'),
              message: syncState.downlinkError!,
              inline: true,
            ),
          ],
          const SizedBox(height: MmsSpacing.xs),
          DiagnosticsKeyValueRow(
            key: const Key('diagnostics_drive_live_sync_row'),
            label: 'Hibrit / Drive Canlı Senkron',
            value: syncState.driveSyncUiStatus.label,
          ),
          if (syncState.driveConflictCount > 0) ...[
            const SizedBox(height: MmsSpacing.xs),
            AppErrorState(
              key: const Key('diagnostics_drive_conflict_banner'),
              message:
                  '${syncState.driveConflictCount} adet Drive ürün/fiyat çakışması tespit edildi; Master Hub bağlantısı bekleniyor.',
              inline: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLocalStorageCard(BuildContext context, SystemStatus status) {
    final colors = context.mmsColors;
    final bool isReady = status.localDbState == LocalDatabaseState.ready;

    return AppCard(
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isReady ? colors.successBg : colors.dangerBg,
                  borderRadius: BorderRadius.circular(MmsRadius.md),
                ),
                child: Icon(
                  Icons.folder_special_rounded,
                  color: isReady ? colors.successText : colors.dangerText,
                  size: 21,
                ),
              ),
              const SizedBox(width: MmsSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'İstemci Yerel Depolaması (client_local.db)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status.localDbPath.isNotEmpty
                          ? status.localDbPath
                          : 'Varsayılan Uygulama Dizini',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: MmsSpacing.xs),
                    AppBadge(
                      label: isReady ? 'DRIFT HAZIR (WAL)' : 'BAŞLATILAMADI',
                      tone: isReady
                          ? AppBadgeTone.success
                          : AppBadgeTone.danger,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          Divider(height: MmsSpacing.xl, color: colors.border),
          Wrap(
            spacing: MmsSpacing.xl,
            runSpacing: MmsSpacing.sm,
            children: [
              _buildMetric(
                context,
                'Bekleyen Outbox Kaydı',
                '${status.pendingOutboxCount}',
                icon: Icons.outbox_rounded,
                isMonospace: true,
                highlightColor: status.pendingOutboxCount > 0
                    ? colors.warningText
                    : null,
              ),
              _buildMetric(
                context,
                'Yerel Satış Kaydı',
                '${status.localSalesCount}',
                icon: Icons.receipt_long_rounded,
                isMonospace: true,
              ),
              _buildMetric(
                context,
                'Önbellek Ürün Sayısı',
                '${status.localProductsCount}',
                icon: Icons.inventory_2_rounded,
                isMonospace: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildArchitectureSafetyCard(BuildContext context) {
    final colors = context.mmsColors;

    return AppCard(
      backgroundColor: colors.surfaceSubtle,
      padding: const EdgeInsets.all(MmsSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_rounded, color: colors.emerald, size: 22),
          const SizedBox(width: MmsSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mimari Sınır ve Güvenlik Güvencesi',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '• İstemci arayüzü doğrudan merkezi master veritabanına (market_master.db) KESİNLİKLE bağlanmaz.\n'
                  '• Tüm veri okuma ve yazma işlemleri yalnızca yerel Drift (client_local.db) ve merkezi Shelf API istemcisi üzerinden yürütülür.\n'
                  '• Ağ kopsa dahi çevrimdışı satışlar yerel kuyruğa yazılır ve bağlantı sağlandığında idempotent olarak Hub\'a aktarılır.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colors.textSecondary,
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
    BuildContext context,
    String label,
    String value, {
    required IconData icon,
    bool isMonospace = false,
    Color? highlightColor,
  }) {
    final colors = context.mmsColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19, color: colors.textTertiary),
          const SizedBox(width: MmsSpacing.xs),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: highlightColor ?? colors.textPrimary,
                    fontFeatures: isMonospace
                        ? MmsTypography.tabularFigures
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
