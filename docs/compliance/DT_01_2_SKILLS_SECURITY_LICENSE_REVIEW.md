# DT-01.2: Skills Security & License Review Raporu

**Belge Kodu:** `DT_01_2_SKILLS_SECURITY_LICENSE_REVIEW.md`  
**Tarih:** 6 Kasım 2026  
**Aşama:** Faz 1 — Uyumluluk, Güvenlik ve Lisans Denetimi (DT-01.2)  
**Denetlenen Dizin:** `.agents/skills/` ve `.agents/registry/`  
**Denetim Türü:** Statik Güvenlik Analizi, Kaynak Doğrulaması ve Açık Kaynak Lisans İncelemesi  
**Yasal Uyarı:** *Bu rapor yalnızca teknik ve operasyonel bir danışmanlık incelemesidir; resmi hukuki mütalaa niteliği taşımaz. Becerilerin kabulü, reddi, yetkilendirilmesi veya muafiyeti konusundaki nihai karar münhasıran proje sahibine aittir.*

---

## 1. Executive Summary (Yönetici Özeti)

Market Management System (MMS) projesinde `.agents/skills/` dizini altında bulunan 5 adet yapay zekâ becerisi (`code-quality`, `test-first`, `systematic-debugging`, `flutter-ui-standards`, `documentation`) statik güvenlik analizi, kaynak doğrulaması ve lisans uyumluluğu açısından kapsamlı bir denetimden geçirilmiştir.

### Temel Bulgular:
1. **Güvenlik Durumu (Birinci Öncelik — Temiz):**
   - İncelenen 5 becerinin tamamı **saf Markdown (`.md`) formatında yönerge metinleridir**.
   - Becerilerin hiçbirinde derlenmiş ikili (binary) dosya, kabuk (shell/bash/PowerShell) betiği, Python/JavaScript scripti, ağ bağlantı isteği, gizli anahtar/token erişimi veya yetki yükseltme çağrısı **bulunmamaktadır**.
   - Doğrudan gözlemlenen güvenlik riski **EN DÜŞÜK (LOW / INFO)** seviyededir.
2. **Kaynak Güvenilirliği (Kısmi Doğrulandı):**
   - 3 becerinin (`test-first`, `systematic-debugging`, `flutter-ui-standards`) orijinal açık kaynak üst depoları (`obra/superpowers`, `nextlevelbuilder/ui-ux-pro-max-skill`) doğrulanmıştır.
   - 2 becerinin (`code-quality`, `documentation`) doğrudan harici bir üst Git deposuna bağlanamadığı, MMS projesine özgü iç kurallardan derlendiği görülmüştür.
3. **Lisans ve Telif Uyumluluğu (İkinci Öncelik — Eksik):**
   - `.agents/` dizini altında veya hiçbir beceri klasöründe resmi bir `LICENSE`, `COPYRIGHT` veya `NOTICE` dosyası **mevcut değildir**.
   - `test-first`, `systematic-debugging` ve `flutter-ui-standards` becerilerinde metin içi tek satırlık anma bulunmakla birlikte, MIT lisansının zorunlu kıldığı resmi telif hakkı bildirimi (`Copyright (c) <Yıl> <Yazar>`) ve tam izin metni dosyalarda yer almamaktadır.
   - Bu hukuki eksiklik giderilene kadar becerilerin repoda **ertelenmiş (DEFER)** statüsünde tutulması önerilmiş; nihai karar proje sahibine bırakılmıştır.

---

## 2. Skill Inventory (Beceri Envanteri)

`.agents/` dizininde tespit edilen tüm dosya ve klasörlerin tam dökümü:

```text
.agents/
├── registry/
│   └── SKILL_REGISTRY.md (3,533 bayt - Merkezi beceri kayıt defteri)
└── skills/
    ├── code-quality/
    │   └── SKILL.md (3,356 bayt - Clean Architecture ve saf Domain kuralları)
    ├── documentation/
    │   └── SKILL.md (2,351 bayt - ADR ve faz kabul yönetişimi)
    ├── flutter-ui-standards/
    │   └── SKILL.md (2,834 bayt - Kasa ekranı ve POS ergonomi kuralları)
    ├── systematic-debugging/
    │   └── SKILL.md (2,988 bayt - 4 fazlı Kök Neden Analizi - RCA)
    └── test-first/
        └── SKILL.md (2,880 bayt - TDD Red-Green-Refactor döngüsü)
```

### 2.1. Beceri Detay Kartları

#### 1. `code-quality`
- **Konum:** `.agents/skills/code-quality/SKILL.md`
- **Dosya Listesi:** Yalnızca `SKILL.md` (Alt dizin veya script yoktur).
- **Beyan Edilen Kaynak:** `SKILL_REGISTRY.md` içinde "MMS İlkeleri & Matt Pocock", Sürüm: `v1.0 (Curated)`.
- **Doğrulanabilir Kaynak URL:** **Doğrulanamadı.** (Matt Pocock TypeScript üzerine odaklıdır; dosya içeriği MMS için özel olarak Dart Clean Architecture, saf Domain ve Riverpod kurallarına uyarlanmıştır).
- **Telif / Lisans Dosyası:** **YOK**.

#### 2. `test-first`
- **Konum:** `.agents/skills/test-first/SKILL.md`
- **Dosya Listesi:** Yalnızca `SKILL.md`.
- **Beyan Edilen Kaynak:** `obra/superpowers` (Jesse Vincent).
- **Geliştirici / Yayıncı:** Jesse Vincent (`obra`).
- **Doğrulanabilir Kaynak URL:** `https://github.com/obra/superpowers` (Doğrulandı).
- **Sürüm / Commit:** `e9c3a1b` (Doğrulandı).
- **Telif / Lisans Dosyası:** **EKSİK**. (`SKILL.md` satır 8'de atıf vardır; resmi `LICENSE` dosyası yoktur).

#### 3. `systematic-debugging`
- **Konum:** `.agents/skills/systematic-debugging/SKILL.md`
- **Dosya Listesi:** Yalnızca `SKILL.md`.
- **Beyan Edilen Kaynak:** `obra/superpowers` (Jesse Vincent).
- **Geliştirici / Yayıncı:** Jesse Vincent (`obra`).
- **Doğrulanabilir Kaynak URL:** `https://github.com/obra/superpowers` (Doğrulandı).
- **Sürüm / Commit:** `e9c3a1b` (Doğrulandı).
- **Telif / Lisans Dosyası:** **EKSİK**. (`SKILL.md` satır 8'de atıf vardır; resmi `LICENSE` dosyası yoktur).

#### 4. `flutter-ui-standards`
- **Konum:** `.agents/skills/flutter-ui-standards/SKILL.md`
- **Dosya Listesi:** Yalnızca `SKILL.md`.
- **Beyan Edilen Kaynak:** `nextlevelbuilder/ui-ux-pro-max-skill`.
- **Geliştirici / Yayıncı:** NextLevelBuilder.
- **Doğrulanabilir Kaynak URL:** `https://github.com/nextlevelbuilder/ui-ux-pro-max-skill` (Doğrulandı).
- **Sürüm / Commit:** `3b8d14e` (Doğrulandı).
- **Telif / Lisans Dosyası:** **EKSİK**. (`SKILL.md` satır 8'de atıf vardır; resmi `LICENSE` dosyası yoktur).

#### 5. `documentation`
- **Konum:** `.agents/skills/documentation/SKILL.md`
- **Dosya Listesi:** Yalnızca `SKILL.md`.
- **Beyan Edilen Kaynak:** `SKILL_REGISTRY.md` içinde "Universal Project Template", Sürüm: `v1.0-balanced`.
- **Doğrulanabilir Kaynak URL:** **Doğrulanamadı.** (MMS'e özgü dokümantasyon hiyerarşisi ve ADR standartlarıdır).
- **Telif / Lisans Dosyası:** **YOK**.

---

## 3. Security Review (Statik Güvenlik İncelemesi)

Tüm beceri dosyaları potansiyel güvenlik vektörleri açısından statik olarak taranmıştır.

### 3.1. Denetim Vektörleri ve Bulgular

| Güvenlik Vektörü | Durum | Gözlem ve Bulgular | Risk Seviyesi |
| :--- | :---: | :--- | :---: |
| **Yürütülebilir Betikler** (Shell, Python, JS, vb.) | **TEMİZ** | Hiçbir beceri klasöründe `.sh`, `.ps1`, `.py`, `.js`, `.bat` veya binary dosya bulunmamaktadır. | **INFO** |
| **Kullanıcı / Sistem Dosyalarına Erişim** | **TEMİZ** | Kullanıcı ev dizini (`~`), işletim sistemi dizinleri veya proje kökünün dışına erişim talimatı yoktur. | **INFO** |
| **Ortam Değişkenleri & Secret Erişimi** | **TEMİZ** | `.env`, API key, token veya özel şifreleme anahtarlarına erişim talimatı içermez. | **INFO** |
| **Ağ ve Harici Veri Aktarımı** | **TEMİZ** | Harici IP/domain bağlantısı, soket açma, `curl`/`wget` ile indirme veya telemetri gönderimi yoktur. | **INFO** |
| **Yetki Yükseltme & Sudo / Admin** | **TEMİZ** | `sudo`, `runas`, Administrator yetkisi veya UAC bypass çağrısı bulunmamaktadır. | **INFO** |
| **Yıkıcı Dosya İşlemleri** (`rm -rf`, DROP) | **TEMİZ** | `SKILL_REGISTRY.md` Bölüm 3 madde 2 gereğince yıkıcı komutlar açıkça yasaklanmıştır. | **INFO** |
| **Otomatik Git Commit / Push** | **TEMİZ** | Beceriler arka planda bağımsız `git commit` veya `git push` çalıştırmaz. | **INFO** |
| **Prompt Injection Vektörleri** | **DÜŞÜK** | Beceriler harici web içeriği okuyup yürütmez; kurallar kapalı devre yazılım standartlarıdır. | **LOW** |

### 3.2. Dosya Bazında Spesifik İnceleme ve Satır Bulguları

#### A. `test-first/SKILL.md` (Satır 34 ve 39)
- **Talimat:** `flutter test test/path/to/test.dart`
- **Açıklama:** TDD Red-Green adımlarında testin çalıştırılmasını önerir.
- **Doğrudan Davranış:** Yalnızca metinsel öneridir; arka planda sessiz komut tetiklemez.
- **Teorik Risk:** Eğer projeye kötü niyetli bir test eklenirse `flutter test` çalıştırıldığında bu kod yerel kullanıcı yetkisiyle icra edilebilir.
- **Risk Seviyesi:** **LOW**.
- **Önlem:** Model, test çalıştırma araçlarını (`run_command`) daima proje güvenlik sandbox'ı içinde ve kullanıcı bilgisi dahilinde kullanmalıdır.

#### B. `systematic-debugging/SKILL.md` (Satır 24, 44, 45)
- **Talimat:** `PRAGMA integrity_check;`, `PRAGMA journal_mode;`, `PRAGMA busy_timeout;`
- **Açıklama:** SQLite WAL modu ve kilitlenme durumunu doğrulamak için salt-okunur teşhis sorguları önerir.
- **Doğrudan Davranış:** Salt-okunur SQL pragmalarıdır; veri silme veya değiştirme yetkisi taşımaz.
- **Risk Seviyesi:** **INFO**.
- **Önlem:** Yıkıcı DDL/DML komutları (`DROP TABLE`, `DELETE FROM`) içermediği doğrulanmıştır.

#### C. `code-quality/SKILL.md` (Satır 19)
- **Talimat:** `Must NEVER import Flutter framework (package:flutter/...), Drift database...`
- **Açıklama:** Domain katmanı için saf Dart izolasyonu kuralı.
- **Güvenlik Etkisi:** Domain katmanına platform bağımlılığı sızmasını engelleyerek saldırı yüzeyini daraltır (Olumlu güvenlik kuralı).
- **Risk Seviyesi:** **INFO**.

---

## 4. Source Verification (Kaynak Doğrulaması)

| Skill Adı | Beyan Edilen Kaynak | Doğrulanabilir Upstream Depo | Doğrulama Yöntemi | Güvenilirlik Durumu |
| :--- | :--- | :--- | :--- | :---: |
| **`test-first`** | `obra/superpowers` | `https://github.com/obra/superpowers` | GitHub API ve açık web doğrulaması | **DOĞRULANDI** (Yüksek Güvenilirlik) |
| **`systematic-debugging`**| `obra/superpowers` | `https://github.com/obra/superpowers` | GitHub API ve açık web doğrulaması | **DOĞRULANDI** (Yüksek Güvenilirlik) |
| **`flutter-ui-standards`**| `ui-ux-pro-max-skill`| `https://github.com/nextlevelbuilder/ui-ux-pro-max-skill` | GitHub API ve açık web doğrulaması | **DOĞRULANDI** (Yüksek Güvenilirlik) |
| **`code-quality`** | MMS & Matt Pocock | Harici doğrudan repo URL'si bulunamadı | Web araması ve yerel metin analizi | **İÇ DERLEME / DOĞRULANAMADI** |
| **`documentation`** | Universal Template | Harici doğrudan repo URL'si bulunamadı | Web araması ve yerel metin analizi | **İÇ DERLEME / DOĞRULANAMADI** |

*Not:* `code-quality` ve `documentation` becerileri, harici bir açık kaynak depodan birebir kopyalanmamış; projenin mimari ihtiyaçlarına göre sıfırdan derlenmiş MMS iç çalışma standartlarıdır.

---

## 5. License Review (Lisans İncelemesi)

### 5.1. Orijinal Depo Lisansları

1. **`obra/superpowers` (Tedarikçi Depo):**
   - **Lisans:** **MIT License** (Doğrulandı).
   - **Telif Sahibi:** Jesse Vincent (`obra`).
   - **Ticari Kullanım:** İzin verilmektedir (Ticari, özel, dağıtım serbest).
   - **Koşul:** Orijinal telif hakkı bildiriminin ve izin metninin tüm kopyalarda yer alması zorunludur.
2. **`nextlevelbuilder/ui-ux-pro-max-skill` (Tedarikçi Depo):**
   - **Lisans:** **MIT License** (Doğrulandı).
   - **Telif Sahibi:** NextLevelBuilder.
   - **Ticari Kullanım:** İzin verilmektedir.
   - **Koşul:** Orijinal telif hakkı ve lisans bildiriminin korunması zorunludur.

### 5.2. Hukuki Durum ve Tespit Edilen Eksiklikler

Mevcut depoda:
- `.agents/skills/test-first/` ve `systematic-debugging/` klasörlerinde Jesse Vincent adına bir `LICENSE` dosyası veya `Copyright (c) Jesse Vincent` bildirimi **bulunmamaktadır**.
- `.agents/skills/flutter-ui-standards/` klasöründe NextLevelBuilder adına bir `LICENSE` dosyası **bulunmamaktadır**.
- `SKILL.md` dosyalarındaki *"adapted from obra/superpowers"* ifadeleri nezaket atfı olmakla birlikte, MIT lisansının lafzı olan *"The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software"* şartını biçimsel olarak tam karşılamayabilir.

### 5.3. Olası Hukuki Riskler ve Çözüm Yolları

- **Olası Etki:** Telif hakkı sahibinin lisans şartlarına uyulmadığı gerekçesiyle attribution talep etmesi (MIT ihlali iddiası).
- **Alternatif Çözüm Yolları:**
  1. **Seçenek A (Resmi Attribution Ekleme):** İlgili beceri klasörlerine resmi MIT `LICENSE` dosyalarının eklenmesi ve orijinal yazarların telif satırlarının konulması.
  2. **Seçenek B (Özgünleştirme / Yeniden Yazım):** Harici depolardan esinlenilen kısımların MMS ekibi tarafından tamamen özgün cümlelerle baştan yazılması ve projenin kendi telifine (Proprietary / MMS Copyright) alınması.
  3. **Seçenek C (Kök AGENTS.md İçine Entegrasyon):** Bağımsız `.agents/skills/` klasörleri yerine bu kuralların doğrudan kök `AGENTS.md` ve `docs/ai/rules/` içine genel mühendislik prensipleri olarak yedirilmesi ve harici skill bağımlılığının kaldırılması.

---

## 6. Third-Party Dependencies (Üçüncü Taraf Bağımlılıkları)

- `.agents/skills/` altındaki hiçbir beceri harici bir npm paketi, pip kütüphanesi, rubygem veya harici API anahtarına bağımlı değildir.
- Çalışmak için yalnızca projenin mevcut **Flutter SDK** (`flutter test`) ortamına ihtiyaç duyarlar.
- Tedarik zinciri (supply chain poisoning, malicious package injection) riski **YOKTUR**.

---

## 7. Risk Matrix (Değerlendirme Matrisi)

Aşağıdaki tabloda her skill için güvenlik, kaynak ve lisans kriterleri özetlenmiş; sonuç sütununda **yalnızca teknik risk seviyesi** belirtilmiştir:

| Skill | Source Verified | Security Risk | License Verified | Commercial Use | Required Attribution | Recommended Restrictions | Technical Assessment |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- | :---: |
| **`code-quality`** | Hayır (İç derleme) | **DÜŞÜK (LOW)** | Doğrulanamadı (Belge yok) | İzinli (MMS mülkiyeti) | Netleştirilmeli | Shell/ağ erişimi verilmemeli | **LOW RISK** |
| **`test-first`** | **Evet** (`obra/superpowers`) | **DÜŞÜK (LOW)** | **Evet** (Üst repo MIT) | İzinli (MIT) | **Zorunlu** (Jesse Vincent telif metni) | `flutter test` kontrollü çalıştırılmalı | **ACCEPTABLE WITH RESTRICTIONS** |
| **`systematic-debugging`**| **Evet** (`obra/superpowers`) | **DÜŞÜK (LOW)** | **Evet** (Üst repo MIT) | İzinli (MIT) | **Zorunlu** (Jesse Vincent telif metni) | Yalnızca salt-okunur teşhis için kullanılmalı | **ACCEPTABLE WITH RESTRICTIONS** |
| **`flutter-ui-standards`**| **Evet** (`ui-ux-pro-max`) | **DÜŞÜK (LOW)** | **Evet** (Üst repo MIT) | İzinli (MIT) | **Zorunlu** (NextLevelBuilder telif metni) | Yalnızca Flutter/POS UI kapsamı uygulanmalı | **ACCEPTABLE WITH RESTRICTIONS** |
| **`documentation`** | Hayır (İç derleme) | **DÜŞÜK (LOW)** | Doğrulanamadı (Belge yok) | İzinli (MMS mülkiyeti) | Netleştirilmeli | Dosya silme yetkisi verilmemeli | **LOW RISK** |

> [!IMPORTANT]
> Tablodaki değerlendirmeler purely teknik risk tespitidir. **Hiçbir skill için otomatik APPROVED veya REJECTED kararı verilmemiştir.**

---

## 8. Mitigation Recommendations (Önlem Önerileri)

1. **Güvenlik Önlemi (No-Execution Policy):** Becerilerin içine gelecekte de hiçbir yürütülebilir script (`.bat`, `.sh`, `.ps1`, `.py`) eklenmemeli; kurallar daima saf Markdown metinleri olarak tutulmalıdır.
2. **Lisans Hijyeni Önlemi:** Becerilerin depoya (`git add` ile) dahil edilmesinden önce Bölüm 5.3'te listelenen çözüm yollarından biri (tercihen Seçenek A veya C) uygulanarak telif/lisans durumu yasal kesinliğe kavuşturulmalıdır.
3. **Rol Ayrımı Önlemi:** `systematic-debugging` becerisi kullanılırken modelin veritabanı dosyaları üzerinde yıkıcı işlem yapması `accidental-data-loss-prevention` kuralları ile engellenmeye devam edilmelidir.

---

## 9. Project Owner Decision Register (Proje Sahibi Karar Defteri)

*Bu bölüm, proje sahibinin becerilere ilişkin nihai onay/ret ve kullanım tercihlerini kaydetmesi için ayrılmıştır:*

### 1. `code-quality`
- **Proje Sahibi Kararı:** `[    ]` *(ONAYLANDI / REDDEDİLDİ / ŞARTLI ONAY / ERTELENDİ)*
- **Kullanım Koşulları:** __________________________________________________
- **Ek Güvenlik Önlemleri:** ______________________________________________
- **Karar Tarihi:** _____ / _____ / 2026

### 2. `test-first`
- **Proje Sahibi Kararı:** `[    ]` *(ONAYLANDI / REDDEDİLDİ / ŞARTLI ONAY / ERTELENDİ)*
- **Kullanım Koşulları:** __________________________________________________
- **Ek Güvenlik Önlemleri:** ______________________________________________
- **Karar Tarihi:** _____ / _____ / 2026

### 3. `systematic-debugging`
- **Proje Sahibi Kararı:** `[    ]` *(ONAYLANDI / REDDEDİLDİ / ŞARTLI ONAY / ERTELENDİ)*
- **Kullanım Koşulları:** __________________________________________________
- **Ek Güvenlik Önlemleri:** ______________________________________________
- **Karar Tarihi:** _____ / _____ / 2026

### 4. `flutter-ui-standards`
- **Proje Sahibi Kararı:** `[    ]` *(ONAYLANDI / REDDEDİLDİ / ŞARTLI ONAY / ERTELENDİ)*
- **Kullanım Koşulları:** __________________________________________________
- **Ek Güvenlik Önlemleri:** ______________________________________________
- **Karar Tarihi:** _____ / _____ / 2026

### 5. `documentation`
- **Proje Sahibi Kararı:** `[    ]` *(ONAYLANDI / REDDEDİLDİ / ŞARTLI ONAY / ERTELENDİ)*
- **Kullanım Koşulları:** __________________________________________________
- **Ek Güvenlik Önlemleri:** ______________________________________________
- **Karar Tarihi:** _____ / _____ / 2026

