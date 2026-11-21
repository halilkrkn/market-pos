import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/design_system/design_system.dart';
import '../../../../core/logging/diagnostics_report_exporter.dart';
import '../../../../core/security/security_providers.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/user_friendly_error_mapper.dart';
import '../../../setup/setup_providers.dart';
import '../../../sync/application/hub_connection_notifier.dart';
import '../../../sync/sync_providers.dart';
import '../../application/system_status_notifier.dart';
import 'diagnostics_card_helpers.dart';

/// Sırlar maskelenerek JSON tanı raporu dışa aktarım kartı.
class DiagnosticsExportCard extends ConsumerStatefulWidget {
  const DiagnosticsExportCard({super.key});

  @override
  ConsumerState<DiagnosticsExportCard> createState() =>
      _DiagnosticsExportCardState();
}

class _DiagnosticsExportCardState extends ConsumerState<DiagnosticsExportCard> {
  bool _isExporting = false;
  String? _statusMessage;
  AppBadgeTone _tone = AppBadgeTone.info;

  Future<void> _exportReport() async {
    setState(() {
      _isExporting = true;
      _statusMessage = null;
    });

    try {
      final dbService = ref.read(localDatabaseServiceProvider);
      final logger = ref.read(redactingLoggerProvider);
      final setup = ref.read(setupConfigProvider);
      final auth = ref.read(deviceAuthProvider);
      final status = ref.read(systemStatusProvider);
      final hubState = ref.read(hubConnectionProvider);
      final syncState = ref.read(backgroundSyncCoordinatorProvider);

      final outboxSummary = dbService.isClosed
          ? null
          : await dbService.getOutboxSummary(deviceId: setup.deviceId);
      final logsDir = Directory(p.join(dbService.dataDirectoryPath, 'logs'));

      final exported = await DiagnosticsReportExporter.exportToDirectory(
        outputDir: logsDir,
        logger: logger,
        setupConfig: setup,
        systemStatus: status,
        hubState: hubState,
        syncState: syncState,
        outboxSummary: outboxSummary,
        tokenBackendLabel: auth.backendLabel,
        hasStoredToken: auth.hasStoredToken,
      );

      if (!mounted) return;
      setState(() {
        _tone = AppBadgeTone.success;
        _statusMessage =
            'Maskeli tanı raporu kaydedildi: ${exported.path} (parola/token/anahtar içermez).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _tone = AppBadgeTone.danger;
        _statusMessage = UserFriendlyErrorMapper.map(
          e,
          fallback: 'Tanı raporu dışa aktarılamadı.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DiagnosticsSectionCard(
      key: const Key('diagnostics_export_card'),
      title: 'Maskeli Tanı ve Destek Dışa Aktarımı',
      subtitle: 'Sırlar ([REDACTED]) temizlenerek yerel logs/ klasörüne yazılır',
      children: [
        Wrap(
          spacing: MmsSpacing.sm,
          runSpacing: MmsSpacing.sm,
          children: [
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                key: const Key('diagnostics_export_logs_button'),
                onPressed: _isExporting ? null : _exportReport,
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  _isExporting
                      ? 'Dışa Aktarılıyor...'
                      : 'Maskeli Tanı Raporunu Dışa Aktar',
                ),
              ),
            ),
          ],
        ),
        if (_statusMessage != null) ...[
          const SizedBox(height: MmsSpacing.sm),
          DiagnosticsInlineBanner(
            key: const Key('diagnostics_export_banner'),
            tone: _tone,
            message: _statusMessage!,
          ),
        ],
      ],
    );
  }
}
