# Clean Code Standartları

Bu belge, **Market POS** projesinde kod okunabilirliğini, bakım kolaylığını ve tutarlılığını sağlamak için uyulacak standartları belirler.

---

## 1. Anlaşılır ve Açık İsimlendirme

- Değişkenler, fonksiyonlar ve sınıflar ne yaptıklarını açıkça ifade etmelidir. Kısaltmalardan (ör. `p`, `btn`, `calc`) kaçınılmalıdır.
- Finansal veya stok alanlarında birim açıkça belirtilmelidir: `priceInCents` / `priceInKurus`, `quantityInGrams`, `stockLevel`.
- Boolean değişkenler soru kalıbı taşımalıdır: `isActive`, `hasPendingSync`, `isOffline`.

---

## 2. Fonksiyon Tasarımı ve Sorumluluk

- Her fonksiyon tek bir işi yapmalı ve onu iyi yapmalıdır.
- **Keyfî Satır Sayısı Sınırı Yoktur:** Fonksiyonlar için "kesin 30 satır" gibi yapay ve kodu anlamsız parçalara bölen kısıtlamalar uygulanmaz. Fonksiyon, üstlendiği sorumluluğu eksiksiz ve okunabilir şekilde ifade edecek uzunlukta olmalıdır; ancak birden fazla sorumluluk üstleniyorsa alt mantıksal fonksiyonlara ayrılmalıdır.

---

## 3. Finansal Hesaplamalar ve Sayısal Tipler

- **Para ve Sayısal Hesaplamalar:** Para değerleri kesinlik kaybını önleyen uygun veri tipleriyle tutulmalıdır; para hesaplamalarında floating-point aritmetiği kullanılmamalıdır. Gerektiğinde para değerleri kuruş bazlı integer (`int`) veya fixed-point tiplerle saklanabilir. Diğer sayısal alanlarda (gramaj, ağırlık, oran, ölçüm ve istatistik gibi) problem alanına uygun veri tipleri ayrıca belirlenmelidir. Uygulamanın tamamında genel bir `double` yasağı yoktur; kısıtlama yalnızca finansal kesinlik kaybı oluşturabilecek floating-point hesaplamalarını kapsar.
- Yuvarlama kuralları iş kuralı olarak açıkça tanımlanır ve test edilir.

---

## 4. Hata Yönetimi (Error Handling)

- Hatalar sessizce yutulmamalı (`catch (e) {}` yasaktır).
- UI'a yansıyan hatalar anlaşılır, kullanıcı dostu Türkçe mesajlar içermelidir; ham veritabanı veya stack trace hataları doğrudan kullanıcıya gösterilmez.
- Hata tipleri `core/errors/` altında tanımlı etki alanına özel sınıflarla (`DomainException`, `SyncException`, `StorageException`) yönetilir.

---

## 5. Tekrarlanan Kodların Yönetimi (DRY)

- Gerçekten aynı iş mantığını yürüten kodlar ortak yardımcılar veya extension'lar ile birleştirilir.
- Ancak tesadüfi benzerlikler yüzünden birbirinden bağımsız iş kuralları yapay olarak ortaklaştırılmamalıdır (premature abstraction).

