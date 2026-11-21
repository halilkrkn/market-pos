import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/platform/mms_ui_profile.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../core/utils/user_friendly_error_mapper.dart';
import '../../../diagnostics/application/system_status_notifier.dart';
import '../../../diagnostics/domain/system_status.dart';
import '../../../diagnostics/presentation/widgets/outbox_status_badge.dart';
import '../../../diagnostics/presentation/widgets/status_badge.dart';
import '../../../sync/application/hub_connection_notifier.dart';
import '../../../sync/domain/hub_connection_state.dart';
import '../../../sync/domain/sync_coordinator_state.dart';
import '../../../sync/sync_providers.dart';

/// MARKET MMS — Adaptif Üst Başlık Çubuğu (Windows Masaüstü & Android Mobil)
class CashierHeaderBar extends ConsumerWidget {
  final VoidCallback? onOpenDiagnostics;
  final bool showBrandLogo;
  final bool isDiagnosticsSelected;

  const CashierHeaderBar({
    super.key,
    this.onOpenDiagnostics,
    this.showBrandLogo = true,
    this.isDiagnosticsSelected = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(systemStatusProvider);
    final uiProfile = ref.watch(mmsUiProfileProvider);
    final colors = context.mmsColors;
    final windowClass = context.windowClass;
    final isCompact = windowClass == MmsWindowClass.compact;
    final isUltraNarrow = MediaQuery.sizeOf(context).width < 360;
    final iconButtonSize = (isCompact || uiProfile.isMobile) ? 48.0 : 42.0;

    // Arka plan senkronizasyon koordinatörü ile Hub keşif/bağlantı yöneticisinin
    // uygulama açılışında erken başlatılmasını ve yaşam döngüsünün aktif kalmasını sağlar.
    final hubConnection = ref.watch(hubConnectionProvider);
    final syncState = ref.watch(backgroundSyncCoordinatorProvider);

    final platformLabel = uiProfile.isMobile
        ? 'Mobil Kasa İstemcisi'
        : 'Masaüstü Kasa İstemcisi';

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border, width: 1)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: isCompact ? 60 : 62,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isUltraNarrow
                  ? MmsSpacing.xxs
                  : isCompact
                      ? MmsSpacing.sm
                      : MmsSpacing.lg,
            ),
            child: Row(
              children: [
                // Sol: Orijinal Logo + Başlık
                if (showBrandLogo) ...[
                  AppBrandLogo.mark(
                    size: isUltraNarrow
                        ? 24
                        : isCompact
                            ? 30
                            : 34,
                  ),
                  SizedBox(
                    width: isUltraNarrow
                        ? MmsSpacing.xxs
                        : isCompact
                            ? MmsSpacing.xs
                            : MmsSpacing.sm,
                  ),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isCompact ? 'MARKET MMS' : 'MARKET MANAGEMENT SYSTEM',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: MmsTypography.fontFamily,
                          fontSize: isUltraNarrow
                              ? 13.5
                              : isCompact
                                  ? 14.5
                                  : 15,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                          letterSpacing: 0.2,
                        ),
                      ),
                      Text(
                        isCompact
                            ? (uiProfile.isMobile ? 'Mobil Kasa' : 'Kasa')
                            : '$platformLabel • ${status.deviceId}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),

                // Sağ: Geniş ekranda tam Hub + Outbox rozetleri; mobilde kesintisiz kompakt durum göstergesi
                if (!isCompact) ...[
                  Flexible(
                    fit: FlexFit.loose,
                    child: StatusBadge(
                      state: status.backendState,
                      compact: false,
                    ),
                  ),
                  const SizedBox(width: MmsSpacing.xs),
                  Flexible(
                    fit: FlexFit.loose,
                    child: OutboxStatusBadge(
                      summary: status.outboxSummary,
                      isDatabaseError:
                          status.localDbState == LocalDatabaseState.error,
                      compact: false,
                    ),
                  ),
                ] else ...[
                  Flexible(
                    fit: FlexFit.loose,
                    child: _CompactStatusPill(
                      status: status,
                      syncState: syncState,
                      onTap: () => _showConnectionSummarySheet(
                        context: context,
                        ref: ref,
                        status: status,
                        hubConnection: hubConnection,
                        syncState: syncState,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 4),

                // Hızlı Tema Değiştirici (Light / Dark)
                AppIconButton(
                  key: const Key('header_theme_toggle'),
                  tooltip: context.isDarkMode
                      ? 'Açık Temaya Geç'
                      : 'Koyu Temaya Geç',
                  icon: context.isDarkMode
                      ? Icons.light_mode_rounded
                      : Icons.dark_mode_rounded,
                  size: iconButtonSize,
                  onPressed: () {
                    ref
                        .read(themeModeProvider.notifier)
                        .toggleLightDark(
                          MediaQuery.platformBrightnessOf(context),
                        );
                  },
                ),

                // Mobilde Sistem & Tanı ekranına hızlı erişim (>= 48dp hedef)
                if (isCompact && onOpenDiagnostics != null)
                  AppIconButton(
                    key: const Key('header_diagnostics_button'),
                    tooltip: 'Sistem & Tanı',
                    icon: Icons.tune_rounded,
                    size: iconButtonSize,
                    color: isDiagnosticsSelected ? colors.emerald : null,
                    backgroundColor:
                        isDiagnosticsSelected ? colors.successBg : null,
                    bordered: isDiagnosticsSelected,
                    onPressed: onOpenDiagnostics,
                  ),

                // Sistem Durumunu Yenile
                if (!isCompact)
                  AppIconButton(
                    tooltip: 'Sistem Durumunu Yenile',
                    icon: Icons.refresh_rounded,
                    size: iconButtonSize,
                    onPressed: () {
                      ref.read(systemStatusProvider.notifier).refreshStatus();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  void _showConnectionSummarySheet({
    required BuildContext context,
    required WidgetRef ref,
    required SystemStatus status,
    required HubConnectionState hubConnection,
    required SyncCoordinatorState syncState,
  }) {
    final colors = context.mmsColors;
    final rawError = syncState.errorMessage ?? status.errorMessage;
    final friendlyError =
        rawError != null && rawError.trim().isNotEmpty
            ? UserFriendlyErrorMapper.map(rawError)
            : null;
    final activeUrl = hubConnection.activeHubUrl?.trim().isNotEmpty == true
        ? hubConnection.activeHubUrl!
        : (status.backendUrl.isNotEmpty
            ? status.backendUrl
            : 'Henüz yapılandırılmadı');

    AppBottomSheet.show<void>(
      context: context,
      title: 'Bağlantı ve Senkronizasyon Özeti',
      builder: (sheetContext) => Column(
        key: const Key('mobile_connection_summary_sheet'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: MmsSpacing.xs,
            runSpacing: MmsSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusBadge(state: status.backendState),
              OutboxStatusBadge(
                summary: status.outboxSummary,
                isDatabaseError:
                    status.localDbState == LocalDatabaseState.error,
              ),
            ],
          ),
          const SizedBox(height: MmsSpacing.md),
          Text(
            'Master Hub: $activeUrl',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
              fontFeatures: MmsTypography.tabularFigures,
            ),
          ),
          const SizedBox(height: MmsSpacing.xs),
          Text(
            'Bekleyen: ${status.outboxSummary.pending} • Tekrar: ${status.outboxSummary.retry} • Kalıcı Hata: ${status.outboxSummary.failedPermanent}',
            style: TextStyle(
              fontSize: 12.5,
              color: colors.textSecondary,
              fontFeatures: MmsTypography.tabularFigures,
            ),
          ),
          if (friendlyError != null) ...[
            const SizedBox(height: MmsSpacing.sm),
            AppErrorState(message: friendlyError, inline: true),
          ],
          const SizedBox(height: MmsSpacing.md),
          AppButton(
            key: const Key('summary_sheet_sync_now_button'),
            label: 'Şimdi Senkronize Et',
            icon: Icons.sync_rounded,
            variant: AppButtonVariant.emerald,
            minHeight: 48,
            expand: true,
            onPressed: () {
              Navigator.of(sheetContext).pop();
              ref
                  .read(backgroundSyncCoordinatorProvider.notifier)
                  .triggerSync(reason: SyncTriggerReason.manual);
              ref.read(systemStatusProvider.notifier).refreshStatus();
            },
          ),
          const SizedBox(height: MmsSpacing.xs),
          AppButton(
            key: const Key('summary_sheet_rediscover_button'),
            label: 'Hub\'ı Yeniden Ara',
            icon: Icons.wifi_tethering_rounded,
            variant: AppButtonVariant.secondary,
            minHeight: 48,
            expand: true,
            onPressed: () {
              Navigator.of(sheetContext).pop();
              ref.read(hubConnectionProvider.notifier).discoverAndConnect();
            },
          ),
          if (onOpenDiagnostics != null) ...[
            const SizedBox(height: MmsSpacing.xs),
            AppButton(
              key: const Key('summary_sheet_open_diagnostics_button'),
              label: 'Sistem ve Tanı Ekranını Aç',
              icon: Icons.tune_rounded,
              variant: AppButtonVariant.secondary,
              minHeight: 48,
              expand: true,
              onPressed: () {
                Navigator.of(sheetContext).pop();
                onOpenDiagnostics!();
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactStatusPill extends StatelessWidget {
  final SystemStatus status;
  final SyncCoordinatorState syncState;
  final VoidCallback? onTap;

  const _CompactStatusPill({
    required this.status,
    required this.syncState,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;

    final int unsynced = status.outboxSummary.totalUnsynced;
    final int failed = status.outboxSummary.failedPermanent;

    final (bg, border, fg, label, icon) = (syncState.status ==
                SyncCoordinatorStatus.tlsPinMismatch ||
            status.backendState == BackendConnectionState.tlsPinMismatch)
        // Faz 7B: Güvenlik hatası sıradan "Çevrimdışı" gibi gösterilmez.
        ? (
            colors.dangerBg,
            colors.danger.withValues(alpha: 0.45),
            colors.dangerText,
            'Sertifika Uyuşmuyor',
            Icons.gpp_bad_rounded,
          )
        : (syncState.status == SyncCoordinatorStatus.tlsCertError ||
                status.backendState == BackendConnectionState.tlsCertError)
        // ADR-017: SAN/IP/hostname/süre hatası pin uyuşmazlığından ayrılır.
        ? (
            colors.warningBg,
            colors.warning.withValues(alpha: 0.45),
            colors.warningText,
            'Sertifika Hatası',
            Icons.verified_user_outlined,
          )
        : switch (status.backendState) {
      BackendConnectionState.online => failed > 0 ||
              syncState.status == SyncCoordinatorStatus.permanentError
          ? (
              colors.dangerBg,
              colors.danger.withValues(alpha: 0.45),
              colors.dangerText,
              '${failed > 0 ? failed : 1} Hata',
              Icons.error_outline_rounded,
            )
          : syncState.status == SyncCoordinatorStatus.authRequired
          ? (
              colors.warningBg,
              colors.warning.withValues(alpha: 0.45),
              colors.warningText,
              'Yetki Gerekli',
              Icons.lock_outline_rounded,
            )
          : syncState.isSyncing
          ? (
              colors.infoBg,
              colors.info.withValues(alpha: 0.45),
              colors.infoText,
              'Senkronize...',
              Icons.sync_rounded,
            )
          : (
              colors.successBg,
              colors.emerald.withValues(alpha: 0.4),
              colors.successText,
              unsynced > 0 ? 'Bekleyen $unsynced' : 'Çevrimiçi',
              Icons.cloud_done_rounded,
            ),
      BackendConnectionState.draining => (
        colors.warningBg,
        colors.warning.withValues(alpha: 0.45),
        colors.warningText,
        'Bakım',
        Icons.sync_rounded,
      ),
      BackendConnectionState.offline => (
        colors.dangerBg,
        colors.danger.withValues(alpha: 0.45),
        colors.dangerText,
        unsynced > 0 ? 'Çevrimdışı • $unsynced' : 'Çevrimdışı',
        Icons.cloud_off_rounded,
      ),
      BackendConnectionState.checking => (
        colors.infoBg,
        colors.info.withValues(alpha: 0.4),
        colors.infoText,
        'Kontrol',
        Icons.sync_rounded,
      ),
      BackendConnectionState.tlsPinMismatch => (
        colors.dangerBg,
        colors.danger.withValues(alpha: 0.45),
        colors.dangerText,
        'Sertifika Uyuşmuyor',
        Icons.gpp_bad_rounded,
      ),
      BackendConnectionState.tlsCertError => (
        colors.warningBg,
        colors.warning.withValues(alpha: 0.45),
        colors.warningText,
        'Sertifika Hatası',
        Icons.verified_user_outlined,
      ),
    };

    return InkWell(
      key: const Key('mobile_status_pill'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(MmsRadius.pill),
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(MmsRadius.pill),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
