import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/platform/mms_ui_profile.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/utils/user_friendly_error_mapper.dart';
import '../../../backup/presentation/widgets/hub_central_backup_card.dart';
import '../../../security/data/windows_zero_touch_bootstrapper.dart';
import '../../../security/presentation/widgets/device_security_card.dart';
import '../../../security/presentation/widgets/pairing_approval_panel.dart';
import '../../../setup/presentation/widgets/store_setup_card.dart';
import '../../../shell/presentation/windows/windows_desktop_settings_card.dart';
import '../../../sync/application/hub_connection_notifier.dart';
import '../../../sync/domain/hub_connection_state.dart';
import '../../../sync/domain/sync_coordinator_state.dart';
import '../../../sync/sync_providers.dart';
import '../../../updates/presentation/widgets/app_update_card.dart';
import '../../application/failed_outbox_controller.dart';
import '../../application/system_status_notifier.dart';
import '../../domain/failed_outbox_item.dart';
import '../../domain/system_status.dart';
import '../widgets/diagnostics_card_helpers.dart';
import '../widgets/diagnostics_export_card.dart';
import '../widgets/hub_connection_controls.dart';
import '../widgets/outbox_status_badge.dart';
import '../widgets/status_badge.dart';

/// MARKET MMS — Ayarlar ve Sistem Ekranı (Tek Kullanıcı / Market Sahibi Modu)
class DiagnosticsView extends ConsumerWidget {
  const DiagnosticsView({super.key});

  Future<void> _handleRefresh(WidgetRef ref) async {
    if (ref.read(windowsZeroTouchAutoBootstrapEnabledProvider)) {
      try {
        await ref.read(windowsZeroTouchRunnerProvider)();
      } catch (_) {
        // Bağlantı hatasında durum yenileme yine çalışmaya devam eder.
      }
    }
    await ref.read(systemStatusProvider.notifier).refreshStatus();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(systemStatusProvider);
    final hubConnection = ref.watch(hubConnectionProvider);
    final syncState = ref.watch(backgroundSyncCoordinatorProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDesktop = ref.watch(mmsUiProfileProvider).isDesktop;
    final isCompact = context.windowClass == MmsWindowClass.compact;

    return RefreshIndicator(
      onRefresh: () => _handleRefresh(ref),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(isCompact ? MmsSpacing.md : MmsSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPageHeader(
              title: 'Ayarlar ve Sistem',
              subtitle: isDesktop
                  ? 'Bağlantı, telefon eşleştirme, Google Drive yedekleme ve genel ayarlar'
                  : 'Bağlantı, senkronizasyon, bilgisayar eşleştirme ve görünüm ayarları',
              actions: [
                AppButton(
                  key: const Key('refresh_button'),
                  label: 'Durumu Yenile',
                  icon: Icons.refresh_rounded,
                  variant: AppButtonVariant.primary,
                  minHeight: 48,
                  onPressed: () {
                    _handleRefresh(ref);
                  },
                ),
              ],
            ),
            const SizedBox(height: MmsSpacing.lg),

            if (isDesktop) ...[
              // Windows 1. Kart: Bağlantı & Senkronizasyon Durumu
              _buildConnectionAndSyncCard(
                context,
                ref,
                syncState,
                status,
                hubConnection: hubConnection,
              ),
              const SizedBox(height: MmsSpacing.md),

              // Windows 2. Kart: Telefon Bağla
              const PairingApprovalPanel(),
              const SizedBox(height: MmsSpacing.md),

              // Windows 3. Kart: Google Drive Yedekleme
              const HubCentralBackupCard(),
              const SizedBox(height: MmsSpacing.md),

              // Windows 4. Kart: Genel Ayarlar (Mağaza Adı, Tema, Sistem Tepsisi & Otomatik Başlatma)
              _buildWindowsGeneralSettingsCard(context, ref, themeMode),
              const SizedBox(height: MmsSpacing.md),
            ] else ...[
              // Android 1. Kart: Bağlantı & Senkronizasyon Durumu
              _buildConnectionAndSyncCard(
                context,
                ref,
                syncState,
                status,
                hubConnection: hubConnection,
              ),
              const SizedBox(height: MmsSpacing.md),

              // Android 2. Kart: Bilgisayara Bağlan (Sade Mod)
              const DeviceSecurityCard(mode: DeviceSecurityCardMode.simple),
              const SizedBox(height: MmsSpacing.md),

              // Android 3. Kart: Görünüm (Tema: Açık / Koyu / Sistem)
              _buildAppearanceCard(context, ref, themeMode),
              const SizedBox(height: MmsSpacing.md),
            ],

            // Her iki platformda en altta varsayılanı kapalı teknik destek bölümü
            _buildAdvancedSupportSection(context, status),
          ],
        ),
      ),
    );
  }

  Widget _buildWindowsGeneralSettingsCard(
    BuildContext context,
    WidgetRef ref,
    ThemeMode themeMode,
  ) {
    final colors = context.mmsColors;

    return AppCard(
      key: const Key('windows_general_settings_card'),
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
                  Icons.tune_rounded,
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
                      'Genel Ayarlar',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      'Mağaza adı, tema tercihi ve Windows masaüstü ayarları',
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
          const StoreSetupCard(),
          const SizedBox(height: MmsSpacing.md),
          _buildAppearanceCard(context, ref, themeMode),
          const SizedBox(height: MmsSpacing.md),
          const WindowsDesktopSettingsCard(),
        ],
      ),
    );
  }

  Widget _buildAdvancedSupportSection(
    BuildContext context,
    SystemStatus status,
  ) {
    final colors = context.mmsColors;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const Key('advanced_support_expansion_tile'),
            initiallyExpanded: false,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: MmsSpacing.md,
              vertical: MmsSpacing.xs,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              MmsSpacing.md,
              0,
              MmsSpacing.md,
              MmsSpacing.md,
            ),
            leading: Icon(
              Icons.build_circle_outlined,
              color: colors.textSecondary,
            ),
            title: Text(
              'Gelişmiş ve Teknik Destek',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            subtitle: Text(
              'Yerel veritabanı, manuel adres, sertifika sabitleme, sürüm ve destek raporu',
              style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
            ),
            children: [
              _buildLocalStorageCard(context, status),
              const SizedBox(height: MmsSpacing.md),
              const HubConnectionControls(),
              const SizedBox(height: MmsSpacing.md),
              const DeviceSecurityCard(mode: DeviceSecurityCardMode.advanced),
              const SizedBox(height: MmsSpacing.md),
              const AppUpdateCard(),
              const SizedBox(height: MmsSpacing.md),
              const DiagnosticsExportCard(),
            ],
          ),
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
                      'Görünüm',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      'Açık, Koyu veya Sistem teması seçimi',
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
        constraints: const BoxConstraints(minHeight: 48),
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

  @visibleForTesting
  Widget buildSyncCoordinatorCardForTest(
    BuildContext context,
    WidgetRef ref,
    SyncCoordinatorState syncState,
    SystemStatus status, {
    HubConnectionState? hubConnection,
  }) => _buildConnectionAndSyncCard(
    context,
    ref,
    syncState,
    status,
    hubConnection: hubConnection,
  );

  Widget _buildConnectionAndSyncCard(
    BuildContext context,
    WidgetRef ref,
    SyncCoordinatorState syncState,
    SystemStatus status, {
    HubConnectionState? hubConnection,
  }) {
    final colors = context.mmsColors;
    final bool isOnline = status.backendState == BackendConnectionState.online;
    final rawUrl = hubConnection?.activeHubUrl ?? status.backendUrl;
    final displayedUrl = rawUrl.trim().isNotEmpty
        ? rawUrl
        : 'Henüz yapılandırılmadı';

    final (
      String? phaseLabel,
      AppBadgeTone phaseTone,
    ) = switch (hubConnection?.phase) {
      HubConnectionPhase.unconfigured => (
        'Yapılandırılmadı',
        AppBadgeTone.neutral,
      ),
      HubConnectionPhase.discovering => ('Aranıyor', AppBadgeTone.info),
      HubConnectionPhase.verifying => ('Doğrulanıyor', AppBadgeTone.info),
      HubConnectionPhase.connected => ('Bağlı', AppBadgeTone.success),
      HubConnectionPhase.offline => ('Çevrimdışı', AppBadgeTone.warning),
      HubConnectionPhase.needsDiscovery => (
        'Bağlantı Gerekli',
        AppBadgeTone.warning,
      ),
      null => (null, AppBadgeTone.neutral),
    };
    final String? sourceLabel = hubConnection?.sourceDisplayLabel;

    final (String stateText, AppBadgeTone tone) = switch (syncState.status) {
      SyncCoordinatorStatus.syncing => (
        'Senkronize Ediliyor',
        AppBadgeTone.info,
      ),
      SyncCoordinatorStatus.idle => ('Hazır', AppBadgeTone.success),
      SyncCoordinatorStatus.networkError => (
        'Bağlantı Hatası',
        AppBadgeTone.warning,
      ),
      SyncCoordinatorStatus.permanentError => (
        'Onarım Gerekiyor',
        AppBadgeTone.danger,
      ),
      SyncCoordinatorStatus.authRequired => (
        'Cihaz Bağlantısı Gerekli',
        AppBadgeTone.warning,
      ),
      SyncCoordinatorStatus.error => (
        'Senkronizasyon Hatası',
        AppBadgeTone.danger,
      ),
      SyncCoordinatorStatus.paused => ('Duraklatıldı', AppBadgeTone.info),
      SyncCoordinatorStatus.tlsPinMismatch => (
        'Sertifika Uyuşmuyor',
        AppBadgeTone.danger,
      ),
      SyncCoordinatorStatus.tlsCertError => (
        'Sertifika Hatası',
        AppBadgeTone.warning,
      ),
    };

    final totalPending =
        status.outboxSummary.pending + status.outboxSummary.retry;

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
                  color: isOnline ? colors.successBg : colors.warningBg,
                  borderRadius: BorderRadius.circular(MmsRadius.md),
                ),
                child: Icon(
                  isOnline ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  color: isOnline ? colors.successText : colors.warningText,
                  size: 21,
                ),
              ),
              const SizedBox(width: MmsSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bağlantı & Senkronizasyon Durumu',
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
                        if (phaseLabel != null)
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
                'Bekleyen İşlem',
                '$totalPending',
                icon: Icons.schedule_rounded,
                isMonospace: true,
                highlightColor: totalPending > 0 ? colors.warningText : null,
              ),
              if (status.outboxSummary.failedPermanent > 0)
                _buildMetric(
                  context,
                  'Hatalı İşlem',
                  '${status.outboxSummary.failedPermanent}',
                  icon: Icons.error_outline_rounded,
                  isMonospace: true,
                  highlightColor: colors.dangerText,
                ),
              if (hubConnection?.hubId != null &&
                  hubConnection!.hubId!.isNotEmpty)
                _buildMetric(
                  context,
                  'Bilgisayar Kimliği',
                  hubConnection.hubId!,
                  icon: Icons.computer_rounded,
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
          if (status.errorMessage != null) ...[
            const SizedBox(height: MmsSpacing.sm),
            AppErrorState(message: status.errorMessage!, inline: true),
          ],
          if (syncState.errorMessage != null) ...[
            const SizedBox(height: MmsSpacing.sm),
            AppErrorState(message: syncState.errorMessage!, inline: true),
          ],
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
            label: 'Bulut Senkron Durumu',
            value: syncState.driveSyncUiStatus.label,
          ),
          if (syncState.driveConflictCount > 0) ...[
            const SizedBox(height: MmsSpacing.xs),
            AppErrorState(
              key: const Key('diagnostics_drive_conflict_banner'),
              message:
                  '${syncState.driveConflictCount} adet ürün/fiyat çakışması tespit edildi; ana bilgisayar bağlantısı bekleniyor.',
              inline: true,
            ),
          ],
          if (status.outboxSummary.failedPermanent > 0) ...[
            const SizedBox(height: MmsSpacing.sm),
            _FailedPermanentOutboxSection(
              deviceId: status.deviceId,
              revision: status.localMetricsRevision,
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
                      'Yerel Veritabanı',
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
                      label: isReady ? 'Hazır' : 'Başlatılamadı',
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
                'Bekleyen İşlem',
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
                'Yerel Ürün Sayısı',
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

class _FailedPermanentOutboxSection extends ConsumerStatefulWidget {
  final String deviceId;
  final int revision;

  const _FailedPermanentOutboxSection({
    required this.deviceId,
    required this.revision,
  });

  @override
  ConsumerState<_FailedPermanentOutboxSection> createState() =>
      _FailedPermanentOutboxSectionState();
}

class _FailedPermanentOutboxSectionState
    extends ConsumerState<_FailedPermanentOutboxSection> {
  Future<List<FailedOutboxItem>?>? _opsFuture;
  bool _retrying = false;

  void _reload() {
    if (widget.deviceId.trim().isEmpty) {
      _opsFuture = null;
      return;
    }
    _opsFuture = ref
        .read(failedOutboxServiceProvider)
        .loadFailedOperations(widget.deviceId);
  }

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant _FailedPermanentOutboxSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deviceId != widget.deviceId ||
        oldWidget.revision != widget.revision) {
      _reload();
    }
  }

  Future<void> _retryOperation(String operationId) async {
    setState(() => _retrying = true);
    try {
      await ref.read(failedOutboxServiceProvider).retryOperation(operationId);
      if (mounted) {
        setState(() {
          _reload();
        });
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(
          context,
          message: UserFriendlyErrorMapper.map(
            e,
            fallback: 'Bu kalıcı hata doğrudan yeniden denenemez.',
          ),
          tone: AppBadgeTone.danger,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _retrying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final future = _opsFuture;
    if (future == null) {
      return const AppErrorState(
        key: Key('diagnostics_failed_permanent_list'),
        message: 'Senkronizasyon hatası bulunan işlemler var; katalog veya satış detayından düzeltip yeniden deneyin.',
        inline: true,
      );
    }

    return FutureBuilder<List<FailedOutboxItem>?>(
      future: future,
      builder: (context, snapshot) {
        final ops = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting &&
            (ops == null || ops.isEmpty)) {
          return const SizedBox.shrink();
        }
        if (ops == null || ops.isEmpty) {
          return const AppErrorState(
            key: Key('diagnostics_failed_permanent_list'),
            message: 'Onarım gerektiren senkronizasyon kaydı bulundu.',
            inline: true,
          );
        }

        return Container(
          key: const Key('diagnostics_failed_permanent_list'),
          padding: const EdgeInsets.all(MmsSpacing.sm),
          decoration: BoxDecoration(
            color: colors.dangerBg,
            borderRadius: BorderRadius.circular(MmsRadius.md),
            border: Border.all(
              color: colors.dangerText.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Onarım Gerektiren İşlemler (${ops.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.dangerText,
                ),
              ),
              const SizedBox(height: MmsSpacing.xs),
              for (final op in ops) ...[
                Padding(
                  padding: const EdgeInsets.only(top: MmsSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${op.operationType} #${op.clientSeq}: ${UserFriendlyErrorMapper.map(op.lastError ?? "Senkronizasyon hatası")}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: MmsSpacing.xs),
                      SizedBox(
                        height: 36,
                        child: OutlinedButton(
                          key: Key('retry_failed_op_${op.operationId}'),
                          onPressed:
                              (_retrying || op.isProtocolConflictNonRetryable)
                              ? null
                              : () => _retryOperation(op.operationId),
                          child: const Text('Yeniden Dene'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
