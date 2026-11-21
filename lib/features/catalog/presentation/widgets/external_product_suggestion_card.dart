import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';
import '../../../../core/theme/design_tokens.dart';
import '../../domain/external_product_suggestion.dart';

/// Open Food Facts ürün önerisini kullanıcı onayına ve düzenlemesine sunan kart.
///
/// Kural (`MASTER_ROADMAP.md` Faz 5):
/// - Yalnızca öneri sunar; kullanıcı onaylamadan kalıcı ürün bilgisi sayılmaz.
/// - Satış fiyatı, maliyet ve stok bilgilerini ASLA otomatik doldurmaz.
class ExternalProductSuggestionCard extends StatelessWidget {
  final ExternalProductSuggestion suggestion;
  final bool isApplied;
  final VoidCallback onApply;
  final VoidCallback onDismiss;
  final Widget Function(BuildContext context, String imageUrl)? imageBuilder;

  const ExternalProductSuggestionCard({
    super.key,
    required this.suggestion,
    required this.isApplied,
    required this.onApply,
    required this.onDismiss,
    this.imageBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.mmsColors;
    final nutritionEntries = _buildNutritionEntries(suggestion.nutrition);

    return Container(
      key: const Key('off_suggestion_card'),
      padding: const EdgeInsets.all(MmsSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(MmsRadius.md),
        border: Border.all(
          color: isApplied ? colors.emerald : colors.info,
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (suggestion.imageUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(MmsRadius.sm),
                  child: Container(
                    width: 60,
                    height: 60,
                    color: colors.surface,
                    child: imageBuilder != null
                        ? imageBuilder!(context, suggestion.imageUrl!)
                        : Image.network(
                            suggestion.imageUrl!,
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.image_not_supported_outlined,
                              color: colors.textTertiary,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: MmsSpacing.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: MmsSpacing.xs,
                      runSpacing: MmsSpacing.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AppBadge(
                          label: suggestion.sourceLabel,
                          tone: isApplied
                              ? AppBadgeTone.success
                              : AppBadgeTone.info,
                          compact: true,
                        ),
                        if (suggestion.brand != null &&
                            suggestion.brand!.isNotEmpty)
                          AppBadge(
                            label: 'Marka: ${suggestion.brand}',
                            tone: AppBadgeTone.neutral,
                            compact: true,
                          ),
                        if (suggestion.quantityText != null &&
                            suggestion.quantityText!.isNotEmpty)
                          AppBadge(
                            label: suggestion.quantityText!,
                            tone: AppBadgeTone.neutral,
                            compact: true,
                          ),
                      ],
                    ),
                    const SizedBox(height: MmsSpacing.xxs),
                    Text(
                      suggestion.suggestedDisplayName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const Key('off_dismiss_suggestion_button'),
                tooltip: 'Öneriyi Kapat',
                onPressed: onDismiss,
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: colors.textSecondary,
                ),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),

          if (suggestion.categories.isNotEmpty) ...[
            const SizedBox(height: MmsSpacing.xs),
            Text(
              'Kategoriler: ${suggestion.categories.take(4).join(' • ')}',
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ],

          if (suggestion.ingredientsText != null &&
              suggestion.ingredientsText!.isNotEmpty) ...[
            const SizedBox(height: MmsSpacing.xs),
            Text(
              'İçindekiler: ${suggestion.ingredientsText!}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ],

          if (nutritionEntries.isNotEmpty) ...[
            const SizedBox(height: MmsSpacing.xs),
            Wrap(
              spacing: MmsSpacing.xs,
              runSpacing: MmsSpacing.xxs,
              children: nutritionEntries
                  .map(
                    (entry) => AppBadge(
                      label: entry,
                      tone: AppBadgeTone.neutral,
                      compact: true,
                    ),
                  )
                  .toList(),
            ),
          ],

          const SizedBox(height: MmsSpacing.sm),
          Text(
            'Open Food Facts önerisi: Satış fiyatı, maliyet ve stok otomatik doldurulmaz. Bilgileri kontrol edip düzenleyerek onaylayın.',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: colors.warningText,
            ),
          ),
          const SizedBox(height: MmsSpacing.sm),
          Wrap(
            spacing: MmsSpacing.xs,
            runSpacing: MmsSpacing.xs,
            children: [
              AppButton(
                key: const Key('off_apply_suggestion_button'),
                label: isApplied
                    ? 'Öneri Form\'a Aktarıldı (Tekrar Aktar)'
                    : 'Öneriyi Form\'a Aktar',
                icon: Icons.auto_fix_high_rounded,
                variant: isApplied
                    ? AppButtonVariant.emerald
                    : AppButtonVariant.primary,
                minHeight: 48,
                onPressed: onApply,
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _buildNutritionEntries(NutritionFactsSummary? nutrition) {
    if (nutrition == null || nutrition.isEmpty) return const [];
    return [
      if (nutrition.energyKcal100g != null)
        'Enerji: ${nutrition.energyKcal100g}',
      if (nutrition.proteins100g != null)
        'Protein: ${nutrition.proteins100g}',
      if (nutrition.carbohydrates100g != null)
        'Karb: ${nutrition.carbohydrates100g}',
      if (nutrition.sugars100g != null) 'Şeker: ${nutrition.sugars100g}',
      if (nutrition.fat100g != null) 'Yağ: ${nutrition.fat100g}',
      if (nutrition.salt100g != null) 'Tuz: ${nutrition.salt100g}',
    ];
  }
}
