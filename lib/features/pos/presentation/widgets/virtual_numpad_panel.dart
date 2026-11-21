import 'package:flutter/material.dart';

import '../../../../core/theme/design_tokens.dart';

/// Opsiyonel masaüstü sanal numpad paneli (`OD-04`: varsayılan kapalı).
class VirtualNumpadPanel extends StatelessWidget {
  final ValueChanged<String> onDigitOrChar;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSubmit;

  const VirtualNumpadPanel({
    super.key,
    required this.onDigitOrChar,
    required this.onBackspace,
    required this.onClear,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;

    return Container(
      key: const Key('virtual_numpad_panel'),
      padding: const EdgeInsets.all(MmsSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(MmsRadius.md),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: MmsSpacing.xs),
            child: Text(
              'SANAL NUMPAD (BARKOD / GİRİŞ)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          _buildRow(context, [
            _NumpadButtonSpec('7', onTap: () => onDigitOrChar('7')),
            _NumpadButtonSpec('8', onTap: () => onDigitOrChar('8')),
            _NumpadButtonSpec('9', onTap: () => onDigitOrChar('9')),
            _NumpadButtonSpec(
              'Sil',
              onTap: onBackspace,
              bgColor: colors.warningBg,
              fgColor: colors.warningText,
            ),
          ]),
          const SizedBox(height: 6),
          _buildRow(context, [
            _NumpadButtonSpec('4', onTap: () => onDigitOrChar('4')),
            _NumpadButtonSpec('5', onTap: () => onDigitOrChar('5')),
            _NumpadButtonSpec('6', onTap: () => onDigitOrChar('6')),
            _NumpadButtonSpec(
              'C',
              onTap: onClear,
              bgColor: colors.dangerBg,
              fgColor: colors.dangerText,
            ),
          ]),
          const SizedBox(height: 6),
          _buildRow(context, [
            _NumpadButtonSpec('1', onTap: () => onDigitOrChar('1')),
            _NumpadButtonSpec('2', onTap: () => onDigitOrChar('2')),
            _NumpadButtonSpec('3', onTap: () => onDigitOrChar('3')),
            _NumpadButtonSpec('.', onTap: () => onDigitOrChar('.')),
          ]),
          const SizedBox(height: 6),
          _buildRow(context, [
            _NumpadButtonSpec('0', onTap: () => onDigitOrChar('0')),
            _NumpadButtonSpec('00', onTap: () => onDigitOrChar('00')),
            _NumpadButtonSpec(
              'Ekle',
              flex: 2,
              onTap: onSubmit,
              bgColor: colors.emerald,
              fgColor: colors.onEmerald,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, List<_NumpadButtonSpec> specs) {
    final colors = context.mmsColors;

    return Row(
      children: [
        for (var i = 0; i < specs.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            flex: specs[i].flex,
            child: OutlinedButton(
              key: Key('numpad_btn_${specs[i].label}'),
              onPressed: specs[i].onTap,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: specs[i].bgColor ?? colors.surfaceSubtle,
                foregroundColor: specs[i].fgColor ?? colors.textPrimary,
                side: BorderSide(color: colors.borderStrong),
                padding: EdgeInsets.zero,
              ),
              child: Text(
                specs[i].label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFeatures: MmsTypography.tabularFigures,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _NumpadButtonSpec {
  final String label;
  final VoidCallback onTap;
  final int flex;
  final Color? bgColor;
  final Color? fgColor;

  const _NumpadButtonSpec(
    this.label, {
    required this.onTap,
    this.flex = 1,
    this.bgColor,
    this.fgColor,
  });
}
