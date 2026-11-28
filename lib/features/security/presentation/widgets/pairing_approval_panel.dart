import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/security/security_providers.dart';
import '../../../../core/security/tls_pinned_client_factory.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../diagnostics/presentation/widgets/diagnostics_card_helpers.dart';
import '../../../setup/setup_providers.dart';
import '../../../sync/application/hub_connection_notifier.dart';
import '../../data/hub_pairing_admin_client.dart';

/// Hub yönetim uçları yalnızca loopback'ten kabul edilir: aktif Hub adresinin portu
/// korunarak host 127.0.0.1'e çevrilir.
final hubPairingAdminClientProvider = Provider<HubPairingAdminClient>((ref) {
  final active = ref.watch(hubConnectionProvider.select((s) => s.activeHubUrl));
  final parsed = Uri.tryParse(active ?? '');
  final pinned = ref.watch(pinnedTlsConfigProvider);
  final port = (parsed != null && parsed.hasPort) ? parsed.port : 8945;
  final base = 'https://127.0.0.1:$port';
  final client = pinned != null ? MmsPinnedTlsClientFactory.createClient(pinned) : http.Client();
  ref.onDispose(client.close);
  return HubPairingAdminClient(hubBaseUrl: base, httpClient: client);
});

/// Faz 7B — Windows Owner: yeni cihaz eşleştirme oturumu açma ve bekleyen talepleri
/// onaylama/reddetme. Admin secret yalnızca bu ekranın belleğinde tutulur.
class PairingApprovalPanel extends ConsumerStatefulWidget {
  const PairingApprovalPanel({super.key});

  @override
  ConsumerState<PairingApprovalPanel> createState() => _PairingApprovalPanelState();
}

class _PairingApprovalPanelState extends ConsumerState<PairingApprovalPanel> {
  final _secretController = TextEditingController();
  List<PendingPairingRequest> _pending = const [];
  PairingSessionInfo? _session;
  HubReadinessSummary? _readiness;
  String? _message;
  AppBadgeTone _tone = AppBadgeTone.info;
  bool _busy = false;

  @override
  void dispose() {
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function(HubPairingAdminClient c, String secret) action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final msg = await action(ref.read(hubPairingAdminClientProvider), _secretController.text);
      if (!mounted) return;
      setState(() {
        _tone = AppBadgeTone.success;
        _message = msg;
      });
    } on HubPairingAdminException catch (e) {
      if (!mounted) return;
      setState(() {
        _tone = AppBadgeTone.danger;
        _message = e.message;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _refresh(HubPairingAdminClient c, String secret) async {
    final list = await c.listPendingRequests(adminSecret: secret);
    HubReadinessSummary? readiness;
    try {
      readiness = await c.fetchHubReadiness();
    } catch (e) {
      ref.read(redactingLoggerProvider).warning(
            'pairing',
            'Hub sağlık özeti yenilenemedi: ${e.runtimeType}',
          );
    }
    if (mounted) {
      setState(() {
        _pending = list;
        if (readiness != null) _readiness = readiness;
      });
    }
    return list.isEmpty ? 'Onay bekleyen eşleştirme talebi yok.' : null;
  }

  Future<String?> _bootstrapOwner(HubPairingAdminClient c, String secret) async {
    final setup = ref.read(setupConfigProvider);
    final res = await c.bootstrapOwner(
      adminSecret: secret,
      deviceId: setup.deviceId,
      deviceName: setup.deviceName,
      registerIfMissing: true,
    );
    if (res.token != null && res.token!.isNotEmpty) {
      await ref.read(deviceAuthProvider.notifier).setStoredToken(res.deviceId, res.token!);
      await ref.read(deviceRoleProvider.notifier).refreshRole(force: true);
    }
    HubReadinessSummary? readiness;
    try {
      readiness = await c.fetchHubReadiness();
    } catch (e) {
      ref.read(redactingLoggerProvider).warning(
            'pairing',
            'Bootstrap sonrası Hub sağlık özeti yenilenemedi: ${e.runtimeType}',
          );
    }
    if (mounted && readiness != null) {
      setState(() => _readiness = readiness);
    }
    return 'İlk OWNER kurulumu (${res.deviceId}) tamamlandı ve mühürlendi.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    return DiagnosticsSectionCard(
      key: const Key('pairing_approval_panel'),
      title: 'Cihaz Eşleştirme Onayları (Owner)',
      subtitle: 'Yeni Android cihazları yalnızca bu bilgisayardan onaylayın',
      trailing: const AppBadge(label: 'Loopback + Admin', tone: AppBadgeTone.info, compact: true),
      children: [
        TextField(
          key: const Key('pairing_admin_secret_field'),
          controller: _secretController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Hub yönetici anahtarı (admin secret)',
            helperText: 'Kaydedilmez; ekran kapanınca bellekten silinir.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: MmsSpacing.sm),
        Wrap(spacing: MmsSpacing.sm, runSpacing: MmsSpacing.sm, children: [
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              key: const Key('owner_bootstrap_button'),
              onPressed: _busy ? null : () => _run(_bootstrapOwner),
              icon: const Icon(Icons.admin_panel_settings_rounded),
              label: const Text('İlk OWNER Kurulumu (Bootstrap)'),
            ),
          ),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              key: const Key('pairing_create_session_button'),
              onPressed: _busy
                  ? null
                  : () => _run((c, s) async {
                        final session = await c.createSession(adminSecret: s);
                        if (mounted) setState(() => _session = session);
                        return 'Eşleştirme oturumu açıldı. Kodu Android cihazdaki "Eşleştir" alanına aktarın.';
                      }),
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('Yeni Eşleştirme Oturumu'),
            ),
          ),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              key: const Key('pairing_refresh_button'),
              onPressed: _busy ? null : () => _run(_refresh),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Bekleyen Talepler'),
            ),
          ),
        ]),
        if (_readiness != null) ...[
          const SizedBox(height: MmsSpacing.xs),
          AppBadge(
            key: const Key('hub_recovery_key_health_badge'),
            label: _readiness!.recoveryKeyConfigured
                ? 'Kurtarma Parolası: Yapılandırıldı'
                : 'Kurtarma Parolası: Tanımsız (Yedek Fail-Closed)',
            tone: _readiness!.recoveryKeyConfigured
                ? AppBadgeTone.success
                : AppBadgeTone.warning,
            compact: true,
          ),
        ],
        if (_session != null) ...[
          const SizedBox(height: MmsSpacing.sm),
          if (_session!.qrPayload.trim().isNotEmpty) ...[
            Center(
              child: Container(
                key: const Key('pairing_qr_image_container'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(MmsRadius.md),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QrImageView(
                      key: const Key('pairing_qr_image'),
                      data: _session!.qrPayload,
                      version: QrVersions.auto,
                      size: 220,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tek kullanımlık eşleştirme kodu — ekran görüntüsünü paylaşmayın.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: MmsSpacing.sm),
          ],
          Row(children: [
            Expanded(
              child: Text(
                'Oturum ${_session!.sessionId} · son geçerlilik: ${_session!.expiresAt?.toLocal() ?? '-'}',
                style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
              ),
            ),
            TextButton.icon(
              key: const Key('pairing_copy_payload_button'),
              onPressed: () => Clipboard.setData(ClipboardData(text: _session!.qrPayload)),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Eşleştirme kodunu kopyala'),
            ),
          ]),
        ],
        if (_message != null) ...[
          const SizedBox(height: MmsSpacing.sm),
          DiagnosticsInlineBanner(key: const Key('pairing_admin_status_banner'), tone: _tone, message: _message!),
        ],
        for (final r in _pending)
          Padding(
            padding: const EdgeInsets.only(top: MmsSpacing.sm),
            child: Row(children: [
              Expanded(
                child: Text(
                  '${r.deviceName} (${r.platform}) · ${r.deviceId}\nAnahtar parmak izi: ${r.publicKeyFingerprint}',
                  style: TextStyle(fontSize: 12.5, color: colors.textPrimary),
                ),
              ),
              SizedBox(
                height: 48,
                child: FilledButton(
                  key: Key('pairing_approve_${r.sessionId}'),
                  onPressed: _busy
                      ? null
                      : () => _run((c, s) async {
                            await c.approve(sessionId: r.sessionId, adminSecret: s);
                            await _refresh(c, s);
                            return '${r.deviceName} onaylandı. Cihaz eşleştirmeyi tamamlayacak.';
                          }),
                  child: const Text('Onayla'),
                ),
              ),
              const SizedBox(width: MmsSpacing.xs),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  key: Key('pairing_reject_${r.sessionId}'),
                  onPressed: _busy
                      ? null
                      : () => _run((c, s) async {
                            await c.reject(sessionId: r.sessionId, adminSecret: s);
                            await _refresh(c, s);
                            return '${r.deviceName} reddedildi.';
                          }),
                  child: const Text('Reddet'),
                ),
              ),
            ]),
          ),
      ],
    );
  }
}
