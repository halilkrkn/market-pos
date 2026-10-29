# SOLID Prensipleri Kılavuzu

Bu belge, **Market POS** projesinde SOLID ilkelerinin pratik ve aşırılıktan uzak uygulanmasını açıklar.

---

## 1. Single Responsibility Principle (SRP — Tek Sorumluluk İlkesi)
- Her sınıfın, fonksiyonun ve modülün yalnızca tek bir değişme sebebi olmalıdır.
- *Örnek:* Bir `ProductRepository` hem ürün verilerini veritabanından çekip hem de barkod formatı doğrulaması yapmamalıdır. Sepet toplamını hesaplayan sınıf, fiş yazdırma işlemini üstlenmemelidir.

---

## 2. Open/Closed Principle (OCP — Açık/Kapalı İlkesi)
- Yazılım varlıkları geliştirmeye açık, ancak mevcut davranışları değiştirmeye kapalı olmalıdır.
- *Örnek:* Yeni bir ödeme yöntemi (nakit, kart, veresiye) eklendiğinde mevcut satış tamamlama metodundaki uzun `switch-case` bloklarını baştan yazmak yerine, ödeme arayüzünü uygulayan yeni sınıflar eklenmelidir.

---

## 3. Liskov Substitution Principle (LSP — Liskov Yerine Geçme İlkesi)
- Alt sınıflar, üst sınıflarının veya arayüzlerinin yerine geçebilmeli ve sözleşmeyi bozmamalıdır.
- *Örnek:* `ProductRepository` arayüzünü uygulayan `LocalProductRepository` (Drift) veya `MockProductRepository`, arayüzün tanımladığı dönüş tiplerini ve hata fırlatma davranışını ihlal etmemelidir.

---

## 4. Interface Segregation Principle (ISP — Arayüz Ayrımı İlkesi)
- İstemciler kullanmadıkları metotlara bağımlı olmaya zorlanmamalıdır.
- *Örnek:* Tek bir devasa `DatabaseService` yerine, `ProductReader`, `ProductWriter` veya `StockMovementRecorder` gibi odaklanmış küçük arayüzler tercih edilmelidir.

---

## 5. Dependency Inversion Principle (DIP — Bağımlılıkların Tersine Çevrilmesi)
- Yüksek seviyeli modüller (Domain/Use Cases), düşük seviyeli modüllere (Drift/Supabase) bağımlı olmamalıdır; her ikisi de soyutlamalara (Repository Arayüzleri) bağımlı olmalıdır.
- *Örnek:* `CompleteSaleUseCase`, somut bir `DriftSaleDao` yerine `ISaleRepository` arayüzüne bağımlıdır.

---

## 6. Sınır: Gereksiz Soyutlamadan Kaçınma
- Basit bir veri aktarımı veya tek satırlık yönlendirme için 3 farklı soyutlama katmanı (ör. gereksiz 1 satırlık UseCase sınıfları) üretilmemelidir. Soyutlama gerçek bir iş kuralı veya test ihtiyacı olduğunda eklenir.

