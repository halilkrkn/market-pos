import '../../../../core/design_system/design_system.dart';

/// Stok hareket türlerinin kullanıcıya gösterilen Türkçe etiketi ve rozet tonu.
(String, AppBadgeTone) stockMovementLabel(String type) {
  switch (type) {
    case 'SATIS':
      return ('SATIŞ', AppBadgeTone.info);
    case 'SATIS_IPTALI':
      return ('İPTAL İADESİ', AppBadgeTone.success);
    case 'MUSTERI_IADESI':
      return ('MÜŞTERİ İADESİ', AppBadgeTone.success);
    case 'FIRE_KAYIP':
      return ('FİRE / HASAR', AppBadgeTone.warning);
    case 'GIRIS':
      return ('STOK GİRİŞİ', AppBadgeTone.success);
    case 'BASLANGIC_STOK':
      return ('BAŞLANGIÇ STOĞU', AppBadgeTone.neutral);
    default:
      return (type, AppBadgeTone.neutral);
  }
}
