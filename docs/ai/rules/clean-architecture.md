# Clean Architecture Kuralları

Bu belge, **Market POS** projesinin katmanlı mimarisini ve bağımlılık sınırlarını belirler.

---

## 1. Katman Yapısı ve Bağımlılık Yönü

Proje, **Feature-first + Clean Architecture** yaklaşımını benimser.

Bağımlılık kuralı esastır: **Dış katmanlar iç katmanlara bağımlı olabilir; iç katmanlar dış katmanlardan tamamen habersizdir.**

```text
       ┌──────────────┐
       │ presentation │
       └──────┬───────┘
              │ (bağımlıdır)
              ▼
       ┌──────────────┐          ┌──────────────┐
       │    domain    │ ◄────────┤     data     │
       └──────────────┘          └──────────────┘
         (saf iş mantığı)          (bağımlıdır)
```

---

## 2. Katmanların Sorumlulukları

### 2.1 Domain Katmanı (İç Katman)
- **İçerik:** Entity'ler, value object'ler, repository **arayüzleri (contracts)**, use case'ler / interactor'lar.
- **Kural:** Saf Dart ile yazılır. Kesinlikle `flutter/material.dart`, Drift, SQLite veya Supabase kütüphanelerine bağımlı olamaz.
- **İş Kuralları:** Fiyat hesaplamaları, sepet doğrulama, stok hareket kuralları burada tanımlanır.

### 2.2 Data Katmanı (Dış Katman)
- **İçerik:** Domain repository arayüzlerinin somut sınıfları (implementations), yerel veri kaynakları (Drift DAO / tabloları), uzaktan veri kaynakları (Supabase istemcisi), DTO ve JSON/Entity eşleyicileri (mappers).
- **Kural:** Domain katmanındaki sözleşmeleri (interface) uygular. Domain katmanına bağımlıdır.

### 2.3 Presentation Katmanı (Dış Katman)
- **İçerik:** Ekranlar (Pages), bileşenler (Widgets), durum yönetimi (Riverpod Notifiers/Providers).
- **Kural:** UI doğrudan SQL, Drift veritabanı veya Supabase API çağrısı yapamaz. Tüm işlemler domain repository arayüzleri veya use case'ler üzerinden yürütülür.

---

## 3. Bağımlılık Sınırları ve İzolasyon

- **Flutter Framework:** Yalnızca `presentation` katmanında ve `app` bootstrap/router alanında kullanılmalıdır.
- **Drift + SQLite:** Yalnızca `data/datasources/local` ve `infrastructure/database` içinde izole edilir.
- **Supabase İstemcisi:** Yalnızca `data/datasources/remote` ve `infrastructure/supabase` içinde tutulur.

