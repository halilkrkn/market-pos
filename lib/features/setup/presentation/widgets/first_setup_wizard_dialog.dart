import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../../core/utils/user_friendly_error_mapper.dart';
import '../../../diagnostics/presentation/widgets/diagnostics_card_helpers.dart';
import '../../../sync/application/hub_connection_notifier.dart';
import '../../setup_providers.dart';

/// MARKET MMS — İlk Kurulum ve Şube / İşletme Yapılandırma Sihirbazı.
class FirstSetupWizardDialog extends ConsumerStatefulWidget {
  const FirstSetupWizardDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const FirstSetupWizardDialog(),
    );
  }

  @override
  ConsumerState<FirstSetupWizardDialog> createState() =>
      _FirstSetupWizardDialogState();
}

class _FirstSetupWizardDialogState
    extends ConsumerState<FirstSetupWizardDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tenantController;
  late final TextEditingController _storeController;
  late final TextEditingController _storeNameController;
  late final TextEditingController _deviceIdController;
  late final TextEditingController _deviceNameController;
  late final TextEditingController _hubUrlController;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final setup = ref.read(setupConfigProvider);
    final hubState = ref.read(hubConnectionProvider);
    _tenantController = TextEditingController(text: setup.tenantId);
    _storeController = TextEditingController(text: setup.storeId);
    _storeNameController = TextEditingController(text: setup.storeName);
    _deviceIdController = TextEditingController(text: setup.deviceId);
    _deviceNameController = TextEditingController(text: setup.deviceName);
    _hubUrlController = TextEditingController(
      text: hubState.activeHubUrl ?? '',
    );
  }

  @override
  void dispose() {
    _tenantController.dispose();
    _storeController.dispose();
    _storeNameController.dispose();
    _deviceIdController.dispose();
    _deviceNameController.dispose();
    _hubUrlController.dispose();
    super.dispose();
  }

  String? _requiredField(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return '$label boş bırakılamaz';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(setupConfigProvider.notifier).completeInitialSetup(
            tenantId: _tenantController.text,
            storeId: _storeController.text,
            storeName: _storeNameController.text,
            deviceId: _deviceIdController.text,
            deviceName: _deviceNameController.text,
          );

      final hubInput = _hubUrlController.text.trim();
      final currentHubUrl =
          (ref.read(hubConnectionProvider).activeHubUrl ?? '').trim();
      if (hubInput.isNotEmpty && hubInput != currentHubUrl) {
        await ref
            .read(hubConnectionProvider.notifier)
            .connectToManualAddress(hubInput);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = UserFriendlyErrorMapper.map(
          e,
          fallback: 'Kurulum kaydedilemedi. Girilen bilgileri kontrol edip tekrar deneyin.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    return AppDialog(
      title: 'Mağaza ve Cihaz Kurulumu',
      subtitle: 'Şube, işletme ve Hub bağlantı profili',
      icon: Icons.storefront_rounded,
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Şube kimliği, işletme bilgisi ve cihaz ayarları yedekleme ve Hub eşleştirme işlemlerinde kullanılır.',
                style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
              ),
              const SizedBox(height: MmsSpacing.md),
              TextFormField(
                key: const Key('setup_tenant_id_field'),
                controller: _tenantController,
                decoration: const InputDecoration(
                  labelText: 'İşletme / Tenant ID',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => _requiredField(v, 'Tenant ID'),
              ),
              const SizedBox(height: MmsSpacing.sm),
              TextFormField(
                key: const Key('setup_store_id_field'),
                controller: _storeController,
                decoration: const InputDecoration(
                  labelText: 'Şube / Store ID',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => _requiredField(v, 'Store ID'),
              ),
              const SizedBox(height: MmsSpacing.sm),
              TextFormField(
                key: const Key('setup_store_name_field'),
                controller: _storeNameController,
                decoration: const InputDecoration(
                  labelText: 'Şube Adı',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => _requiredField(v, 'Şube Adı'),
              ),
              const SizedBox(height: MmsSpacing.sm),
              TextFormField(
                key: const Key('setup_device_id_field'),
                controller: _deviceIdController,
                decoration: const InputDecoration(
                  labelText: 'Cihaz ID',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => _requiredField(v, 'Cihaz ID'),
              ),
              const SizedBox(height: MmsSpacing.sm),
              TextFormField(
                key: const Key('setup_device_name_field'),
                controller: _deviceNameController,
                decoration: const InputDecoration(
                  labelText: 'Cihaz Adı',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => _requiredField(v, 'Cihaz Adı'),
              ),
              const SizedBox(height: MmsSpacing.sm),
              TextFormField(
                key: const Key('setup_hub_url_field'),
                controller: _hubUrlController,
                decoration: const InputDecoration(
                  labelText: 'Master Hub Adresi (Opsiyonel)',
                  hintText: 'Örn: https://192.168.1.50:8945',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: MmsSpacing.sm),
                DiagnosticsInlineBanner(
                  tone: AppBadgeTone.danger,
                  message: _errorMessage!,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        SizedBox(
          height: 48,
          child: TextButton(
            key: const Key('setup_wizard_later_button'),
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Daha Sonra'),
          ),
        ),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            key: const Key('setup_wizard_save_button'),
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_isSaving ? 'Kaydediliyor...' : 'Kurulumu Kaydet'),
          ),
        ),
      ],
    );
  }
}
