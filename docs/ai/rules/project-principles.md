# Proje İlkeleri (Project Principles)

Bu belge, **Market POS (MMS)** projesinin geliştirilmesinde izlenecek felsefi ve yönetsel ilkeleri tanımlar.

---

## 1. Ana Dokümanın Bağlayıcılığı

Projenin tek ve nihai gerçeği [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../../../MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (**v1.4**) belgesidir. 
- Yapay zekâ asistanları veya geliştiriciler ana belgede bulunmayan özellikleri projeye kendiliğinden ekleyemez.
- İhtiyaç duyulan değişiklikler önce ana belgede tartışılır ve onaylanır.

---

## 2. Faz Bazlı İlerleme

Geliştirme süreci, ana planda belirtilen **Faz 0 ile Faz 8** arasındaki sıralı yol haritasına göre yürütülür:
- Bir fazın kabul kriterleri eksiksiz karşılanmadan ve kullanıcıdan açık onay alınmadan sonraki aşamaya geçilmez.
- **Faz 0 (Planlama ve Mimari Kararlar)** ve **Faz 1.1 (Windows Client Foundation)** başarıyla tamamlanmıştır.
- Faz 1.2 (Kasa Satış Ekranı & Sepet Yönetimi) uygulamasına geçmeden önce aktif DT-01 alt aşamalarının tamamlanması ve kullanıcıdan açık onay alınması zorunludur.

---

## 3. Kullanıcı Onayı İlkesi

- Mimari kararların değiştirilmesi,
- Dosya silinmesi veya yeniden adlandırılması,
- Faz geçişlerinin onaylanması,
mutlaka kullanıcının açık onayı ile gerçekleştirilir.

---

## 4. Gereksiz Karmaşıklıktan Kaçınma (KISS & YAGNI)

- İlk pilot tek bir markette gerçek kullanım içindir. Bu nedenle aşırı karmaşık mikroservis mimarileri, prematüre soyutlamalar ve kullanılmayan genel geçer kütüphanelerden kaçınılır.
- Ancak veri modeli, en baştan çoklu market SaaS vizyonunu destekleyecek şekilde (tenant, store ayrımı ile) tasarlanır.
