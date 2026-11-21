import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../../diagnostics/presentation/widgets/diagnostics_card_helpers.dart';
import '../../setup_providers.dart';
import 'first_setup_wizard_dialog.dart';

/// Tanı ekranında İşletme, Şube ve Cihaz Kurulum kartı.
class StoreSetupCard extends ConsumerWidget {
  const StoreSetupCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setup = ref.watch(setupConfigProvider);

    return DiagnosticsSectionCard(
      key: const Key('diagnostics_store_setup_card'),
      title: 'Mağaza, Şube ve Cihaz Kurulumu',
      subtitle: 'Çoklu şube izolasyonu ve ilk kurulum profili',
      trailing: AppBadge(
        label: setup.isSetupCompleted ? 'Tamamlandı' : 'Bekliyor',
        tone: setup.isSetupCompleted
            ? AppBadgeTone.success
            : AppBadgeTone.warning,
        icon: setup.isSetupCompleted
            ? Icons.verified_rounded
            : Icons.pending_actions_rounded,
        compact: true,
      ),
      children: [
        DiagnosticsKeyValueRow(
          label: 'İşletme (Tenant ID)',
          value: setup.tenantId,
          monospace: true,
        ),
        DiagnosticsKeyValueRow(
          label: 'Şube (Store ID / Ad)',
          value: '${setup.storeId} (${setup.storeName})',
        ),
        DiagnosticsKeyValueRow(
          label: 'Cihaz Kimliği / Adı',
          value: '${setup.deviceId} · ${setup.deviceName}',
        ),
        const SizedBox(height: MmsSpacing.md),
        Wrap(
          spacing: MmsSpacing.sm,
          runSpacing: MmsSpacing.sm,
          children: [
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                key: const Key('open_setup_wizard_button'),
                onPressed: () async {
                  final saved = await FirstSetupWizardDialog.show(context);
                  if (saved == true && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Mağaza ve cihaz kurulumu kaydedildi.'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.tune_rounded),
                label: Text(
                  setup.isSetupCompleted
                      ? 'Kurulumu Düzenle'
                      : 'Kurulum Sihirbazını Aç',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
