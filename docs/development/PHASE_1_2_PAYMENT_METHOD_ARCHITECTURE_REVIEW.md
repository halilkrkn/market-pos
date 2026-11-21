# MARKET MMS — PaymentMethod Mimari Bağımlılık İnceleme Raporu

- **Tarih:** 2026-11-13
- **İnceleme Türü:** Salt Okunur (Read-Only) Mimari Bağımlılık ve Clean Architecture Denetimi
- **Konu:** `lib/features/pos/domain/pos_repository.dart` içerisindeki `import 'package:mms_client_storage/payment_method.dart';` ifadesinin mimari değerlendirmesi
- **Bağlayıcı Referanslar:** `AGENTS.md` (§3 Mimari ve Bağımlılık Yönü İlkesi), `GEMINI.md`, `DATA_MODEL_DECISIONS.md`, Commit `b069d5b`
- **Yürütme Sınırı:** Kod değişikliği yapılmadı. Staging alanına müdahale edilmedi. Staged diff (%100) korundu.
- **Nihai Karar:** **NO ARCHITECTURE ISSUE (BLOCKING DEĞİL — MEVCUT FAZ İÇİN KABUL EDİLEBİLİR)**

---

## 1. Giriş ve İncelemenin Amacı

Faz 1.2 POS staged diff denetiminde, POS Domain katmanında yer alan [`pos_repository.dart`](file:///c:/Users/halil/Github/market-pos/lib/features/pos/domain/pos_repository.dart#L1) dosyasının harici bir paket olan `mms_client_storage`'a ait bir kütüphaneyi içe aktardığı tespit edilmiştir:

```dart
// lib/features/pos/domain/pos_repository.dart:1
import 'package:mms_client_storage/payment_method.dart';
```

Bu inceleme, söz konusu ithalatın Clean Architecture bağımlılık kurallarını ihlal edip etmediğini, domain saflığını bozup bozmadığını ve Faz 1.2 POS teslimatını bloke eden bir mimari hata oluşturup oluşturmadığını objektif kriterlerle ortaya koymak amacıyla hazırlanmıştır.

---

## 2. `PaymentMethod` Enum'unun Repository Genelindeki Kullanım Haritası

Yapılan statik kod analizinde (`git grep -n "PaymentMethod"`), `PaymentMethod` sözleşmesinin katmanlar arası dağılımı şu şekildedir:

### 2.1. Tanım ve Kaynak Katmanı
- **`packages/mms_client_storage/lib/src/models/payment_method.dart`:** Kanonik `enum PaymentMethod { cash('CASH'), card('CARD') }` tanımı, `parse()`, `tryParse()`, `isCanonical()` ve `tryParseLegacyReadOnly()` metotları.
- **`packages/mms_client_storage/lib/payment_method.dart`:** Saf Dart giriş noktası (`library mms_payment_method; export 'src/models/payment_method.dart';`).

### 2.2. Katman Bazlı Bağımlılıklar

| Katman | Dosya / Modül | İçe Aktarma Yolu | Kullanım Amacı |
|---|---|---|---|
| **Storage / Data** | `client_storage_repository.dart:8` | `../models/payment_method.dart` | `createOfflineSale()` içinde `PaymentMethod.parse()` ile satış doğrulama ve Outbox payload üretimi |
| **Backend API** | `spike_01_backend/bin/server.dart:26` | `package:mms_client_storage/mms_client_storage.dart` | `POST /api/v1/sales` uç noktasında gelen `payment_method` alanının `PaymentMethod.isCanonical()` ve `.parse()` ile doğrulanması |
| **POS Domain** | `pos_repository.dart:1` | `package:mms_client_storage/payment_method.dart` | `PosCompletedSale.paymentMethod` alanı ve `PosRepository.completeOfflineSale()` sözleşmesi |
| **POS Application** | `cart_notifier.dart:8` | `../domain/pos_repository.dart` (re-export) | `completeSale(paymentMethod: PaymentMethod.cash / .card)` durum yönetimi ve kuralları |
| **POS Presentation** | `payment_dialog.dart:6` | `../../domain/pos_repository.dart` (re-export) | F9 (`CARD`) / F10 (`CASH`) tuş eşlemesi, harici POS teyit kutusu ve nakit para üstü hesaplama |
| **POS Presentation** | `pos_screen.dart:14` | Riverpod üzerinden | Ödeme dialogunu `PaymentMethod.cash` veya `PaymentMethod.card` ile açma |

---

## 3. POS Domain'in `payment_method.dart` Bağımlılığının Mimari Analizi

### 3.1. Kütüphane İzolasyonu (Library-Level Encapsulation)
`pos_repository.dart` dosyası, `mms_client_storage` paketinin tamamını veya veritabanı altyapısını (`package:mms_client_storage/mms_client_storage.dart`) **içe aktarmamaktadır**.

Yalnızca Commit `b069d5b` ile bilinçli olarak izole edilmiş olan **`package:mms_client_storage/payment_method.dart`** kütüphanesini içe aktarmaktadır:

```dart
// packages/mms_client_storage/lib/payment_method.dart
/// Pure-Dart kanonik ödeme yöntemi sözleşmesi (`flutter` / `drift` bağımlılığı içermez).
library mms_payment_method;

export 'src/models/payment_method.dart';
```

Bu kütüphane:
- Sıfır (0) Flutter bağımlılığı,
- Sıfır (0) Drift bağımlılığı,
- Sıfır (0) SQLite veya platform bağımlılığı,
- Sıfır (0) HTTP veya Shelf bağımlılığı içerir.
Tamamen saf Dart SDK üzerinde çalışan, değişmez (immutable) iki üyeli (`cash`, `card`) bir Value Object / Enum'dır.

### 3.2. Paket Seviyesinde Bağımlılık Yönü
Teorik Clean Architecture'da:
$$\text{presentation} \longrightarrow \text{application} \longrightarrow \text{domain} \longleftarrow \text{data}$$
Burada kavramsal soru şudur: *"İsmi `mms_client_storage` olan bir paket, mimari olarak yalnızca 'Data' katmanı mıdır, yoksa ortak bir sözleşme paketi rolü de üstlenmekte midir?"*

Mevcut monorepo yapısında `mms_client_storage`, ilk fazlarda istemci yerel depolamasını ve senkronizasyon modellerini barındıran temel paket olarak konumlandırılmıştır. `spike_01_backend` ve `market_pos` istemcisi, aynı kanonik tel ve Outbox sözleşmesini (`PaymentMethod`) paylaşmak zorunda olduğu için bu enum söz konusu pakette tekilleştirilmiştir.

Dolayısıyla, `pos_repository.dart` bu enum'ı kullandığında çalışma zamanında veya tip sisteminde hiçbir altyapı sızıntısı yaşanmamakta; yalnızca paket adlandırması düzeyinde kavramsal bir örtüşme görülmektedir.

---

## 4. `AGENTS.md` ve `GEMINI.md` Kurallarıyla Karşılaştırma

`AGENTS.md` §3 (Mimari Kurallar) anayasasındaki amir hüküm:
> *"Domain Katmanı: Saf Dart ile yazılır. Kesinlikle `flutter/material.dart`, Drift, SQLite, Shelf veya Supabase kütüphanelerine bağımlı olamaz. Entity, value object ve repository sözleşmelerini (ports) barındırır."*

- **Değerlendirme:**
  1. `pos_repository.dart` veya `payment_method.dart`, `flutter/material.dart` içeriyor mu? **HAYIR (0).**
  2. Drift veya SQLite içeriyor mu? **HAYIR (0).**
  3. Shelf veya Supabase içeriyor mu? **HAYIR (0).**
  4. Repository sözleşmesi ve Value Object mi barındırıyor? **EVET.**

Aynı anayasanın YAGNI ve KISS ilkesi (§3):
> *"YAGNI ve KISS: Erken optimizasyonlardan, premature soyutlamalardan, yapay mikroservislerden ve kullanılmayan sınıf/paket enflasyonundan kesinlikle kaçınılır."*

- **Değerlendirme:**
  Henüz merkezi bir `mms_contracts` veya `mms_domain` paketi projenin önceki aşamalarında kurulmamışken, tek bir iki elemanlı enum için yapay paket enflasyonu yaratılmamış; mevcut `b069d5b` sözleşmesi doğrudan tüketilmiştir.

---

## 5. Üç Çözüm Alternatifinin Karşılaştırmalı Değerlendirmesi

### Seçenek A: `PaymentMethod` Enum'unu POS Domain'e Taşımak
- **Nasıl Yapılır:** `lib/features/pos/domain/payment_method.dart` oluşturulur. POS katmanı bunu kullanır.
- **Sakıncaları:**
  1. `mms_client_storage` paketi, kök Flutter uygulamasının (`market-pos`) domain klasörüne **bağımlı olamaz** (döngüsel bağımlılık ve paket hiyerarşisi ihlali).
  2. `spike_01_backend`, Flutter istemcisinin `lib/` klasörüne bağımlı olamaz.
  3. Bu durumda iki ayrı `PaymentMethod` tanımlamak gerekir (`PosPaymentMethod` vs `StoragePaymentMethod`).
  4. `LocalPosRepository` adaptöründe her işlemde gereksiz tip dönüşümü (`switch-map`) yazılması gerekir.
  5. Tip güvenliği azalır, kod tabanında yapay kopya enflasyonu (DRY ihlali) doğar.
- **Değerlendirme:** **ÖNERİLMEZ.**

---

### Seçenek B: `PaymentMethod` Enum'unu Ortak Bir Sözleşme Paketine Taşımak (`packages/mms_contracts` veya `packages/mms_domain`)
- **Nasıl Yapılır:** Bağımsız, saf Dart bir `packages/mms_contracts` paketi açılır. `PaymentMethod`, `Money`, tel DTO'ları buraya alınır. `market-pos`, `mms_client_storage` ve `spike_01_backend` bu paketi tüketir.
- **Avantajları:**
  - Clean Architecture bağımlılık yönü açısından kusursuz ve nihai hedef mimaridir.
- **Sakıncaları ve Mevcut Kapsam Maliyeti:**
  1. Kullanıcı talimatı: *"Yeni paket oluşturmayı otomatik olarak önerme. Mevcut paket yapısını ve gelecekteki mms_domain / mms_contracts planını dikkate al."*
  2. Yeni paket açılması; `pubspec.yaml` zincirinin kırılması, backend referanslarının değişmesi, kabul edilmiş `b069d5b` testlerinin refactor edilmesi anlamına gelir.
  3. Faz 1.2 POS ekranı kapsamını aşan, sistem çapında bir altyapı refactoring'idir.
- **Değerlendirme:** **GELECEK HEDEF MİMARİ OLARAK PLANLANMALI; FAZ 1.2'DE UYGULANMAMALIDIR.**

---

### Seçenek C: Mevcut Konumu Korumak (`package:mms_client_storage/payment_method.dart`)
- **Nasıl Yapılır:** Mevcut staged durum aynen korunur. `PaymentMethod`, `mms_client_storage/payment_method.dart` saf Dart giriş noktasından tüketilir.
- **Avantajları:**
  1. **Sıfır Değişiklik Riski:** 274 test %100 yeşildir, hiçbir paket bağımlılığı kırılmaz.
  2. **İzole Sözleşme:** `payment_method.dart` zaten Drift ve altyapıdan tamamen izole edilmiş saf bir kütüphanedir.
  3. **YAGNI ve KISS ile Uyumlu:** Proje Sahibinin 12 Kasım 2026 tarihli `b069d5b` kararıyla birebir örtüşür.
  4. **Geriye Dönük Uyumluluk:** Backend, storage ve Flutter istemcisi tam mutabakat içindedir.
- **Değerlendirme:** **EN SAĞLIKLI VE ÖNERİLEN SEÇENEK.**

---

## 6. Karşılaştırma Matrisi

| Kriter | Seçenek A (Domain'e Taşıma) | Seçenek B (Ortak Sözleşme Paketi) | Seçenek C (Mevcut Durum — Önerilen) |
|---|:---:|:---:|:---:|
| **Bağımlılık Yönü Temizliği** | Zayıf (Çift enum / mapping) | Kusursuz (Merkezi sözleşme) | İyi (Saf Dart kütüphane izolasyonu) |
| **Paket Sorumluluğu (SRP)** | Zayıf (Domain izole ama backend kopuk) | Kusursuz (Dedicated Contracts) | Kabul Edilebilir (Storage çok rollü) |
| **Geriye Dönük Uyumluluk** | Kırılgan (Mapping hataları riski) | Yeniden bağlantı gerektirir | **%100 Tam Uyumlu (`b069d5b`)** |
| **Değişiklik ve Risk Kapsamı** | Yüksek (POS katmanı değişir) | Çok Yüksek (Tüm repo etkilenir) | **Sıfır Risk (Staged diff korunur)** |
| **Faz 1.2 Zamanlaması** | Gereksiz refactoring | Erken optimizasyon (Premature) | **Tam Faz Hedefine Uygun** |

---

## 7. Gelecek Yol Haritası Önerisi (Roadmap Recommendation)

Bu durum bir kod veya derleme hatası değil, projenin büyüme aşamasında ortaya çıkan doğal bir **mimari evrim adımıdır**:

1. **Faz 1.2 Kapanışı:** Mevcut staged durum (Seçenek C) ile Faz 1.2 POS commit ve push işlemleri güvenle tamamlanmalıdır.
2. **Gelecek Fazlarda Refactoring (Multi-Package / SaaS Hazırlığı):**
   - Gelecekte Android/iOS mobil paketleri veya SaaS Supabase istemcisi eklendiğinde, `packages/mms_contracts` (veya `mms_domain`) adında saf Dart bir ortak sözleşme paketi oluşturulmalıdır.
   - `PaymentMethod`, `Money`, DTO'lar ve ortak hata sınıfları bu pakete taşınmalı; hem backend, hem storage hem de istemci domain katmanları bu pakete bağlanmalıdır.

---

## 8. Nihai Sonuç ve Karar

- **Karar:** **NO ARCHITECTURE ISSUE (BLOCKING DEĞİL — KABUL EDİLEBİLİR)**
- **Gerekçe:**
  1. `package:mms_client_storage/payment_method.dart` kütüphanesi saf Dart'tır; `pos_repository.dart` içerisine hiçbir Flutter, Drift, SQLite veya altyapı bağımlılığı taşımamaktadır.
  2. `PaymentMethod`, 12 Kasım 2026 tarihinde Proje Sahibi onayıyla `b069d5b` commit'inde tam olarak bu amaçla standartlaştırılmış ve merkezi API ile yerel istemci arasında paylaşımlı sözleşme olarak belirlenmiştir.
  3. Ayrı bir domain paketi (`mms_contracts`) açılması doğru bir uzun vadeli hedeftir ancak Faz 1.2 POS teslimatını durdurmayı gerektiren engelleyici bir hata (blocker) değildir; YAGNI prensibi gereği bir sonraki refactoring aşamasına bırakılmalıdır.
- **Sonraki Adım:** Staged 35 dosya üzerinde hiçbir geri alma (unstage) veya değişiklik yapılmadan, doğrudan Proje Sahibinin commit onayına geçilebilir.

