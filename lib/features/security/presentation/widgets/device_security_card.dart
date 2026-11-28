import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mms_client_storage/mms_client_storage.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/platform/mms_ui_profile.dart';
import '../../../../core/security/security_providers.dart';
import '../../../../core/security/tls_pinned_client_factory.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/user_friendly_error_mapper.dart';
import '../../../barcode_scanner/barcode_scanner_providers.dart';
import '../../../diagnostics/application/system_status_notifier.dart';
import '../../../diagnostics/presentation/widgets/diagnostics_card_helpers.dart';
import '../../../setup/setup_providers.dart';
import '../../../sync/application/hub_connection_notifier.dart';
import '../../data/device_pairing_client.dart';
import '../../domain/pairing_qr_payload.dart';

/// B-2 Sertifika Sabitleme, B-3 Güvenli Token Depolama ve S-4 Cihaz Eşleştirme Kartı.
class DeviceSecurityCard extends ConsumerStatefulWidget {
  const DeviceSecurityCard({super.key});

  @override
  ConsumerState<DeviceSecurityCard> createState() =>
      _DeviceSecurityCardState();
}

class _DeviceSecurityCardState extends ConsumerState<DeviceSecurityCard> {
  final _pinController = TextEditingController();
  final _pairingInputController = TextEditingController();
  bool _isPairing = false;
  String? _statusMessage;
  AppBadgeTone _statusTone = AppBadgeTone.info;
  String? _syncedPinValue;

  @override
  void dispose() {
    _pinController.dispose();
    _pairingInputController.dispose();
    super.dispose();
  }

  Future<void> _saveTlsPin() async {
    try {
      final currentSetup = ref.read(setupConfigProvider);
      final enteredNorm = PinnedTlsConfig.normalizeHex(_pinController.text);
      String? matchingCaPem;
      final existingPem = currentSetup.pinnedCaPem;
      if (existingPem != null && existingPem.trim().isNotEmpty) {
        try {
          final parsed = extractCanonicalSingleCertDer(
            Uint8List.fromList(utf8.encode(existingPem)),
          );
          if (constantTimeEqualsAscii(parsed.sha256Hex, enteredNorm)) {
            matchingCaPem = existingPem;
          }
        } on X509ValidationException {
          matchingCaPem = null;
        }
      }
      await ref.read(setupConfigProvider.notifier).updateTlsPinning(
            enabled: true,
            sha256Hex: _pinController.text,
            caCertPem: matchingCaPem,
          );
      if (!mounted) return;
      setState(() {
        _statusTone = AppBadgeTone.success;
        _statusMessage = matchingCaPem != null
            ? 'TLS SHA-256 ve Kök CA sertifikası doğrulandı ve aktif edildi.'
            : 'TLS SHA-256 sertifika sabitleme kaydedildi (Kök CA PEM indirmek için "Kök CA İndir ve Sabitle" kullanabilirsiniz).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusTone = AppBadgeTone.danger;
        _statusMessage = e is FormatException
            ? e.message
            : UserFriendlyErrorMapper.map(e);
      });
    }
  }

  Future<void> _bootstrapRootCaAndPin() async {
    setState(() {
      _isPairing = true;
      _statusMessage = null;
    });
    try {
      final rawActive = ref.read(hubConnectionProvider).activeHubUrl;
      String? targetUrl;
      if (rawActive != null && rawActive.trim().isNotEmpty) {
        final parsed = Uri.tryParse(rawActive.trim());
        if (parsed != null && parsed.host.isNotEmpty) {
          final port = parsed.hasPort ? parsed.port : 8945;
          targetUrl = 'https://${parsed.host}:$port';
        }
      }
      if (targetUrl == null && Platform.isWindows) {
        targetUrl = 'https://127.0.0.1:8945';
      }
      if (targetUrl == null) {
        throw const FormatException(
          'Önce Hub adresini belirleyin veya QR ile eşleştirin.',
        );
      }

      final pairingClient = DevicePairingClient(
        tokenStore: ref.read(secureTokenStoreProvider),
        logger: ref.read(redactingLoggerProvider),
      );
      final canonical = await pairingClient.fetchAndVerifyRootCaCert(
        hubBaseUrl: targetUrl,
        expectedCaSha256Hex: _pinController.text,
      );

      await ref.read(setupConfigProvider.notifier).updateTlsPinning(
            enabled: true,
            sha256Hex: canonical.sha256Hex,
            caCertPem: canonical.toPem(),
          );
      _pinController.text = canonical.sha256Hex;
      _syncedPinValue = canonical.sha256Hex;

      await ref.read(hubConnectionProvider.notifier).connectToManualAddress(targetUrl);
      await ref.read(systemStatusProvider.notifier).refreshStatus();

      if (!mounted) return;
      setState(() {
        _statusTone = AppBadgeTone.success;
        _statusMessage =
            'Hub Kök CA sertifikası SHA-256 ve TLS el sıkışmasıyla doğrulandı ve sabitlendi.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusTone = AppBadgeTone.danger;
        _statusMessage = e is DevicePairingException
            ? e.message
            : (e is FormatException
                ? e.message
                : UserFriendlyErrorMapper.map(
                    e,
                    fallback: 'Kök CA indirilemedi veya doğrulanamadı.',
                  ));
      });
    } finally {
      if (mounted) {
        setState(() => _isPairing = false);
      }
    }
  }

  Future<void> _clearTlsPin() async {
    await ref.read(setupConfigProvider.notifier).clearTlsPinning();
    _pinController.clear();
    _syncedPinValue = '';
    if (!mounted) return;
    setState(() {
      _statusTone = AppBadgeTone.info;
      _statusMessage = 'TLS sertifika sabitleme devre dışı bırakıldı.';
    });
  }

  Future<void> _scanPairingQr() async {
    final scanned = await ref.read(cameraBarcodeScannerProvider).scanBarcode(
          context,
          title: 'Hub Eşleştirme QR Tara',
          subtitle: 'Hub QR kodunu çerçeve içerisine yerleştirin',
        );
    if (!mounted || !scanned.isScanned || scanned.barcode == null) return;
    _pairingInputController.text = scanned.barcode!;
    await _executePairing();
  }

  Future<void> _executePairing() async {
    setState(() {
      _isPairing = true;
      _statusMessage = null;
    });

    try {
      final qr = PairingQrPayload.parse(_pairingInputController.text);
      final setup = ref.read(setupConfigProvider);
      final hubUrl = qr.hubUrl ?? ref.read(hubConnectionProvider).activeHubUrl;
      if (hubUrl == null || hubUrl.trim().isEmpty) {
        throw const FormatException(
          'Eşleştirme için QR kodunda veya Hub ayarlarında geçerli Hub adresi bulunamadı.',
        );
      }

      final pairingClient = DevicePairingClient(
        tokenStore: ref.read(secureTokenStoreProvider),
        logger: ref.read(redactingLoggerProvider),
      );

      final manualPin = PinnedTlsConfig.normalizeHex(_pinController.text);
      final expectedCaPin = qr.normalizedCaSha256 ??
          (manualPin.isNotEmpty ? manualPin : setup.normalizedPinSha256);

      // F-5 / F-7: CA değiştiyse eski setup.pinnedCaPem yeni CA yerine enjekte edilmez.
      final isSamePinAsSetup = expectedCaPin != null &&
          setup.normalizedPinSha256 != null &&
          expectedCaPin == setup.normalizedPinSha256;
      final initialCaPem = qr.caPem ?? (isSamePinAsSetup ? setup.pinnedCaPem : null);

      final result = await pairingClient.pairDevice(
        hubBaseUrl: hubUrl,
        sessionId: qr.sessionId,
        pairingSecret: qr.pairingSecret,
        deviceId: setup.deviceId,
        deviceName: setup.deviceName,
        platformName: Platform.operatingSystem,
        expectedCaSha256: expectedCaPin,
        payloadCaSha256: qr.normalizedCaSha256,
        initialCaPem: initialCaPem,
        existingPinnedCaSha256: setup.normalizedPinSha256,
        onConfirmCaChange: (oldSha, newSha) async {
          if (!mounted) return false;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Kök CA Değişikliği Onayı'),
              content: Text(
                'Bu cihaz daha önce farklı bir Hub Kök CA sertifikasına ($oldSha) sabitlenmiş. '
                'Yeni Kök CA ($newSha) ile yeniden eşleştirmeye devam edilsin mi?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Onayla ve Devam Et'),
                ),
              ],
            ),
          );
          return confirmed ?? false;
        },
        onPromoteTlsPinning: (sha, pem) async {
          await ref.read(setupConfigProvider.notifier).updateTlsPinning(
                enabled: true,
                sha256Hex: sha,
                caCertPem: pem,
              );
        },
        onPromoteHubUrl: (url) async {
          await ref.read(hubConnectionProvider.notifier).connectToManualAddress(url);
        },
      );

      await ref.read(deviceAuthProvider.notifier).loadForDevice(setup.deviceId);
      await ref.read(deviceRoleProvider.notifier).refreshRole(force: true);
      // Not: P1..P4 başarılıysa pin + Hub URL zaten terfi edilmiştir; backward compatibility için güvenli sync:
      if (result.caSha256 != null && result.caSha256!.isNotEmpty) {
        _pinController.text = result.caSha256!;
        _syncedPinValue = result.caSha256!;
      }

      if (!mounted) return;
      setState(() {
        _statusTone = AppBadgeTone.success;
        _statusMessage =
            'Cihaz eşleştirildi ve token güvenli depoya (${ref.read(deviceAuthProvider).backendLabel}) yazıldı.';
      });
    } catch (e) {
      if (!mounted) return;
      final logger = ref.read(redactingLoggerProvider);
      logger.error('pairing', 'Cihaz eşleştirme hatası: $e');
      setState(() {
        _statusTone = AppBadgeTone.danger;
        _statusMessage = e is DevicePairingException
            ? e.message
            : (e is FormatException
                ? e.message
                : UserFriendlyErrorMapper.map(
                    e,
                    fallback: 'Cihaz eşleştirme tamamlanamadı.',
                  ));
      });
    } finally {
      if (mounted) {
        setState(() => _isPairing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(setupConfigProvider);
    final auth = ref.watch(deviceAuthProvider);
    final uiProfile = ref.watch(mmsUiProfileProvider);
    final targetPin = setup.pinnedCaSha256 ?? '';
    if (_syncedPinValue != targetPin && _pinController.text.isEmpty) {
      _pinController.text = targetPin;
      _syncedPinValue = targetPin;
    }

    return DiagnosticsSectionCard(
      key: const Key('diagnostics_security_card'),
      title: 'Cihaz Güvenliği, TLS Pinning (B-2) ve Token Deposu (B-3)',
      subtitle: 'S-4 ECDSA P-256 eşleştirme ve OS/Donanım korumalı token depolama',
      trailing: AppBadge(
        label: setup.hasPinnedCertificate ? 'TLS Pin Aktif' : 'Standart',
        tone: setup.hasPinnedCertificate
            ? AppBadgeTone.success
            : AppBadgeTone.info,
        icon: Icons.security_rounded,
        compact: true,
      ),
      children: [
        DiagnosticsKeyValueRow(
          label: 'Token Güvenli Deposu',
          value: auth.backendLabel,
        ),
        DiagnosticsKeyValueRow(
          label: 'Kayıtlı Cihaz Token Durumu',
          value: auth.hasStoredToken
              ? 'Güvenli depoda mevcut (Maskeli)'
              : 'Henüz eşleştirilmedi (Varsayılan / Bekleniyor)',
        ),
        const SizedBox(height: MmsSpacing.sm),
        TextField(
          key: const Key('tls_pin_sha256_field'),
          controller: _pinController,
          decoration: const InputDecoration(
            labelText: 'Sabitlenmiş CA / Sertifika SHA-256 (64 hex)',
            hintText: 'Örn: A1B2C3... (HTTPS TLS sabitlemesi için)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: MmsSpacing.sm),
        Wrap(
          spacing: MmsSpacing.sm,
          runSpacing: MmsSpacing.sm,
          children: [
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                key: const Key('save_tls_pin_button'),
                onPressed: _isPairing ? null : _saveTlsPin,
                icon: const Icon(Icons.verified_user_rounded),
                label: const Text('TLS Pin Kaydet'),
              ),
            ),
            SizedBox(
              height: 48,
              child: FilledButton.tonalIcon(
                key: const Key('bootstrap_ca_pin_button'),
                onPressed: _isPairing ? null : _bootstrapRootCaAndPin,
                icon: const Icon(Icons.security_rounded),
                label: const Text('Kök CA İndir ve Sabitle'),
              ),
            ),
            if (setup.tlsPinningEnabled)
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  key: const Key('clear_tls_pin_button'),
                  onPressed: _clearTlsPin,
                  child: const Text('TLS Pin Kaldır'),
                ),
              ),
          ],
        ),
        const SizedBox(height: MmsSpacing.md),
        TextField(
          key: const Key('pairing_payload_field'),
          controller: _pairingInputController,
          decoration: const InputDecoration(
            labelText: 'Hub Eşleştirme Kodu (JSON veya marketmms://pair)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: MmsSpacing.sm),
        Wrap(
          spacing: MmsSpacing.sm,
          runSpacing: MmsSpacing.sm,
          children: [
            if (uiProfile.supportsCameraBarcodeScanning)
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  key: const Key('pairing_scan_qr_button'),
                  onPressed: _isPairing ? null : _scanPairingQr,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('QR ile Eşleştir'),
                ),
              ),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                key: const Key('start_pairing_button'),
                onPressed: _isPairing ? null : _executePairing,
                icon: const Icon(Icons.link_rounded),
                label: Text(
                  _isPairing ? 'Eşleştiriliyor...' : 'Eşleştirmeyi Başlat',
                ),
              ),
            ),
          ],
        ),
        if (_statusMessage != null) ...[
          const SizedBox(height: MmsSpacing.sm),
          DiagnosticsInlineBanner(
            key: const Key('security_status_banner'),
            tone: _statusTone,
            message: _statusMessage!,
          ),
        ],
      ],
    );
  }
}
