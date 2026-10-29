# Test ve Doğrulama Stratejisi (Testing Strategy)

Bu belge, **Market POS** projesinde kalite güvencesi, test seviyeleri ve test edilebilirlik standartlarını belirler.

---

## 1. Risk Temelli Test Yaklaşımı

Sabit ve yapay bir "yüzde X test kapsamı" kuralı yerine, projenin en kritik ve finansal risk taşıyan alanlarına odaklanan risk temelli bir test stratejisi uygulanır.

Öncelikli test alanları:
1. **Finansal Doğruluk:** Para hesaplamaları, sepet ara toplamı, indirim, vergi ve genel toplam hesapları.
2. **Atomik Veri Yazımı:** Satış, stok düşümü ve senkronizasyon kuyruğu yazımının aynı transaction içinde tamamlanması.
3. **Senkronizasyon ve Idempotency:** Tekrarlanan isteklerin mükerrer satış oluşturmaması, ağ kesintisi sonrası veri tutarlılığı.
4. **Çoklu Kiracı İzolasyonu:** Supabase RLS politikalarının farklı marketlerin verisini kesin olarak izole ettiğinin doğrulanması.

---

## 2. Test Seviyeleri

### 2.1 Birim Testleri (Unit Tests)
- `domain` katmanındaki entity, value object ve saf Dart iş kuralları için yazılır.
- Dış bağımlılıklar (repository arayüzleri) mock'lanır.
- Hızlı çalışmalı ve dış servislere/veritabanına ihtiyaç duymamalıdır.

### 2.2 Entegrasyon Testleri (Integration Tests)
- Drift yerel veritabanı DAO sorguları ve şema migration testleri.
- Kalıcı senkronizasyon kuyruğunun veri ekleme/çıkarma davranışı.
- Supabase veri erişim katmanı ve RLS politikalarının testleri.

### 2.3 Widget ve UI Testleri (Gerektiğinde)
- Kritik kullanıcı akışları: Barkod okuma sonrası sepetin güncellenmesi, hata mesajlarının doğru gösterimi.

### 2.4 Uçtan Uca (E2E) ve Senaryo Testleri
- Barkod okuma $\rightarrow$ Sepete ekleme $\rightarrow$ Satışı tamamlama $\rightarrow$ Stok hareketi kontrolü.
- İnternet bağlantısını kesme $\rightarrow$ Çevrimdışı satış yapma $\rightarrow$ Bağlantıyı açma $\rightarrow$ Merkezi veritabanında satışı doğrulama.
- Yedekleme oluşturma ve yedekten başarıyla geri yükleme testi.

---

## 3. Test Edilebilirlik Kuralları

- Kod yazılırken bağımlılık enjeksiyonuna (Dependency Injection / Riverpod) uygun olarak tasarlanmalıdır.
- Testlerde rastgele zaman veya donanım bağımlılıklarından kaçınılmalı, zaman ve cihaz kimlikleri mock'lanabilir olmalıdır.

