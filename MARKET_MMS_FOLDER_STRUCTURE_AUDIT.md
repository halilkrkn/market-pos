# MARKET MANAGEMENT SYSTEM (MMS) — Klasör ve Dokümantasyon Yapısı Denetim Raporu

**Rapor Kodu:** `MARKET_MMS_FOLDER_STRUCTURE_AUDIT.md`  
**Tarih:** 4 Kasım 2026  
**Aşama:** Faz 0 — Proje Organizasyonu ve Geliştirme Altyapısı  
**Hazırlayan:** Google Antigravity / Gemini 3.8 Flash (High)  
**Kapsam:** Mevcut Klasör Yapısı Envanteri, Hedef Mimari Karşılaştırması, Boşluk (Gap) Analizi ve Koruma Politikası  
**İlgili Talimat:** `MARKET MMS — KLASÖR YAPISI, UNIVERSAL PROJECT TEMPLATE VE SKILL EKOSİSTEMİ ENTEGRASYONU`

---

## 1. Giriş ve Amaç

Bu rapor, **Market Management System (MMS)** projesinin mevcut fiziksel klasör ve dosya organizasyonunu eksiksiz bir envanterle belgelemek; kullanıcının sunduğu **Hedef Proje Klasör Yapısı** ile karşılaştırarak eksik, fazlalık veya format farklılıklarını tespit etmek ve projenin mevcut doğrulanmış kazanımlarını (v1.2 iş kuralları, v1.1 sertleştirilmiş veri modeli, senkronizasyon ve yedekleme protokolleri) bozmadan sürdürülebilir bir geçiş planı sunmak amacıyla hazırlanmıştır.

---

## 2. Mevcut Proje Klasör Yapısı Envanteri

Proje kök dizini (`c:\Users\halil\Github\market-pos`) ve alt klasörleri fiziksel olarak incelenmiş ve aşağıdaki aktif envanter çıkarılmıştır:

```text
market-pos/
├── .git/                                         # Git yerel deposu (Branch: main)
├── .gitignore                                    # Flutter ve işletim sistemi yoksayma kuralları (2.6 KB)
├── AGENTS.md                                     # Ortak yapay zekâ kuralları ve ilkeleri (6.0 KB)
├── CLAUDE.md                                     # Claude Code geleceğe dönük yönergeleri (1.9 KB)
├── GEMINI.md                                     # Google Antigravity / Gemini özel yönergeleri (2.5 KB)
├── MARKET_POS_AI_STUDIO_BUILD_PLANI.md           # Bağlayıcı ana proje planı (v1.2.2 değiştirilmiş) (18.1 KB)
├── MARKET_MMS_ANTIGRAVITY_INITIAL_AUDIT.md       # İlk denetim ve mimari uyumsuzluk raporu (14.2 KB)
│
├── docs/
│   ├── ARCHITECTURE.md                           # Teknik mimari özeti (v1.2) (4.9 KB)
│   ├── PROJECT_STATUS.md                         # Faz 0 durum takibi ve bir sonraki görev (7.1 KB)
│   ├── ROADMAP.md                                # 9 fazlık geliştirme yol haritası (3.7 KB)
│   │
│   ├── ai/rules/                                 # Özel yapay zekâ disiplin kuralları
│   │   ├── clean-architecture.md                 # Katman kuralları (2.5 KB)
│   │   ├── clean-code.md                         # Kod standartları (2.5 KB)
│   │   ├── offline-first.md                      # Çevrimdışı işlem ve senkronizasyon kuralları (2.5 KB)
│   │   ├── project-principles.md                 # Temel proje ilkeleri (1.5 KB)
│   │   ├── security.md                           # Güvenlik, gizlilik ve RLS kuralları (2.8 KB)
│   │   ├── solid.md                              # SOLID prensipleri (2.3 KB)
│   │   └── testing.md                            # Test piramidi ve kabul kriterleri (2.7 KB)
│   │
│   ├── architecture/                             # Ayrıntılı mimari ve protokol dokümanları
│   │   ├── DATA_MODEL.md                         # Mantıksal veri modeli v1.1 (42.9 KB - 25 tablo)
│   │   ├── DATA_MODEL_DECISIONS.md               # Veri modeli mimari karar kayıtları (15.6 KB)
│   │   ├── DATA_MODEL_REVIEW.md                  # Veri modeli teknik denetim raporu (33.7 KB)
│   │   ├── DATA_MODEL_REVISION_REPORT.md         # Veri modeli revizyon raporu v1.1 (7.3 KB)
│   │   ├── DATA_MODEL_V1_1_TECHNICAL_VALIDATION.md# Veri modeli v1.1 teknik doğrulama raporu (14.2 KB)
│   │   ├── LOCAL_STORAGE_TECHNICAL_VALIDATION.md # Windows, Android, iOS, Web depolama raporu (25.4 KB)
│   │   ├── OFFLINE_SYNC_PROTOCOL.md              # Offline senkronizasyon ve Outbox şartnamesi (34.3 KB)
│   │   ├── OFFLINE_SYNC_DECISIONS.md             # Senkronizasyon karar kayıtları (8.8 KB)
│   │   ├── OFFLINE_SYNC_TECHNICAL_VALIDATION.md  # Senkronizasyon teknik doğrulama raporu (14.6 KB)
│   │   ├── BACKUP_RESTORE_PROTOCOL.md            # Yedekleme ve geri yükleme protokolü (29.2 KB)
│   │   ├── BACKUP_RESTORE_DECISIONS.md           # Yedekleme karar kayıtları (10.8 KB)
│   │   └── BACKUP_RESTORE_TECHNICAL_VALIDATION.md# Yedekleme teknik doğrulama raporu (9.4 KB)
│   │
│   ├── archive/                                  # Eski plan arşivleri
│   │   ├── MARKET_POS_AI_STUDIO_BUILD_PLANI_v1.0.md (17.2 KB)
│   │   └── MARKET_POS_AI_STUDIO_BUILD_PLANI_v1.1.md (25.5 KB)
│   │
│   ├── decisions/                                # Mimari karar kayıtları (ADR)
│   │   └── ADR_TEMPLATE.md                       # Standart mimari karar şablonu (1.5 KB)
│   │
│   └── requirements/                             # İş gereksinimleri ve şartnameler
│       ├── BUSINESS_RULES_SPEC.md                # Bağlayıcı iş kuralları şartnamesi (v1.2) (54.7 KB)
│       └── PHASE_0_BUSINESS_DISCOVERY.md         # Faz 0 keşif ve analiz dokümanı (v1.3) (31.4 KB)
```

---

## 3. Hedef Yapı ile Mevcut Yapının Karşılaştırması

Aşağıdaki tablo, kullanıcının önerdiği hedef yapı ile depodaki mevcut durumun birebir eşleşme ve boşluk analizini göstermektedir:

| Hedef Yapı Öğesi | Mevcut Projedeki Karşılığı | Durum | Değerlendirme ve Eylem Önerisi |
| :--- | :--- | :--- | :--- |
| `AGENTS.md` | `AGENTS.md` | **MEVCUT** | Korunacak. Projenin tek doğruluk kaynağıdır; üzerine genel şablon yazılmamalıdır. |
| `README.md` | *Mevcut değil* | **EKSİK** | Eklenmeli. Projenin ürün vizyonunu, mimari özetini ve dokümantasyon haritasını içeren bir ana `README.md` oluşturulmalıdır. |
| `.gitignore` | `.gitignore` | **MEVCUT** | Korunacak. Flutter, Dart, Windows, Android, iOS kuralları eksiksizdir. |
| `docs/PROJECT_OVERVIEW.md` | `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` | **FARKLI İSİM** | Ana plan dokümanı şu an kök dizinde `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` olarak yaşamaktadır. `docs/PROJECT_OVERVIEW.md` oluşturulup ana plana bağlantı verilebilir veya bu dosyadan türetilebilir. |
| `docs/REQUIREMENTS.md` | `docs/requirements/` | **FARKLI KONUM** | Mevcut yapıda gereksinimler iki derin dokümanda toplanmıştır (`BUSINESS_RULES_SPEC.md` ve `PHASE_0_BUSINESS_DISCOVERY.md`). `docs/REQUIREMENTS.md` bir indeks ve özet giriş kapısı olarak eklenebilir. |
| `docs/ARCHITECTURE.md` | `docs/ARCHITECTURE.md` | **MEVCUT** | Korunacak ve Windows Service / Yerel Hub modeline göre güncellenecektir. |
| `docs/ROADMAP.md` | `docs/ROADMAP.md` | **MEVCUT** | Korunacak. Faz 0–8 aşamalarını içerir. |
| `docs/PROJECT_STATUS.md` | `docs/PROJECT_STATUS.md` | **MEVCUT** | Korunacak. Her oturumda canlı güncellenmektedir. |
| `docs/DEVELOPMENT_GUIDE.md`| *Mevcut değil* | **EKSİK** | Eklenmeli. Geliştirici ortamı kurulumu, FFI/SQLite hazırlığı, branch stratejisi ve test kılavuzunu içermelidir. |
| `docs/architecture/DATA_MODEL.md` | `docs/architecture/DATA_MODEL.md` | **MEVCUT** | Korunacak (v1.1 Sertleştirilmiş - 25 tablo). |
| `docs/architecture/SYSTEM_ARCHITECTURE.md`| `docs/ARCHITECTURE.md` & `LOCAL_STORAGE_TECHNICAL_VALIDATION.md` | **BÖLÜNMÜŞ** | Sistem mimarisi ve yerel depolama iki ayrı belgededir. `SYSTEM_ARCHITECTURE.md` bu belgelerin konsolide görünümü olarak konumlandırılabilir. |
| `docs/architecture/SYNC_ARCHITECTURE.md` | `docs/architecture/OFFLINE_SYNC_PROTOCOL.md` | **FARKLI İSİM** | `OFFLINE_SYNC_PROTOCOL.md` (34 KB) oldukça kapsamlıdır; dosya adı korunmalı veya sembolik/bağlantısal olarak ilişkilendirilmelidir. |
| `docs/architecture/BACKUP_ARCHITECTURE.md`| `docs/architecture/BACKUP_RESTORE_PROTOCOL.md` | **FARKLI İSİM** | `BACKUP_RESTORE_PROTOCOL.md` (29 KB) hazır durumdadır; hedefteki isimle eşdeğerdir. |
| `docs/requirements/BUSINESS_REQUIREMENTS.md`| `docs/requirements/BUSINESS_RULES_SPEC.md` | **FARKLI İSİM** | 159 kural içeren `BUSINESS_RULES_SPEC.md` projenin omurgasıdır. Silinmemeli ve taşınmamalıdır. |
| `docs/requirements/NON_FUNCTIONAL_REQUIREMENTS.md`| `BUSINESS_RULES_SPEC.md` (Bölüm 12) | **BİRLEŞİK** | 21 NFR maddesi `BUSINESS_RULES_SPEC.md` içindedir; ihtiyaç duyulursa ayrı bir görünüm sunulabilir. |
| `docs/requirements/ACCEPTANCE_CRITERIA.md`| `BUSINESS_RULES_SPEC.md` (İzlenebilirlik Matrisi) | **BİRLEŞİK** | Kabul kriterleri her kuralın altında mevcuttur. |
| `docs/decisions/README.md` | *Mevcut değil* | **EKSİK** | Eklenmeli. Karar kayıtlarının indeksini sunan bir rehber dosya olmalıdır. |
| `docs/decisions/ADR-TEMPLATE.md`| `docs/decisions/ADR_TEMPLATE.md` | **MEVCUT (Tire/Alt Tire)**| İsim standardı `ADR_TEMPLATE.md`'dir. |
| `docs/phases/PHASE-TEMPLATE.md` | *Mevcut değil* | **EKSİK** | Eklenmeli. Faz açılış ve kapanış raporları için standart şablon oluşturulmalıdır. |
| `docs/reports/README.md` | *Mevcut değil* | **EKSİK** | Eklenmeli. Oturum denetim ve QA raporlarının arşivleneceği dizin indeksi. |
| `.agents/` | *Mevcut değil* | **EKSİK** | Google Antigravity'nin resmi workspace keşif dizinidir. Eklenmesi önerilir. |
| `lib/`, `test/`, `windows/`.. | *Mevcut değil* | **FAZ 1 KONUSU** | Faz 0 kodsuz aşama olduğu için henüz yoktur. `flutter create` Faz 1'de çalıştırılacaktır. |

---

## 4. Antigravity Açısından `.agents/` Klasörünün Doğrulanması

Google Antigravity'nin yerel `agy-customizations` ve `antigravity-guide` belgeleri resmi olarak taranmış ve şu kesin tespitler yapılmıştır:

1. **Desteklenen Konum:** Antigravity, proje kök dizinindeki `.agents/` (veya alternatif olarak `.agent/`, `_agents/`, `_agent/`) dizinini **otomatik olarak keşfeder** (`Workspace Customizations`).
2. **Alt Klasör Standartları:**
   - `.agents/skills/<skill_name>/SKILL.md`: Çalıştırılabilir ve slash-command (`/<skill_name>`) uyumlu modern beceriler.
   - `.agents/rules/*.md`: Dizin bazlı veya kural tetiklemeli yönergeler.
   - `.agents/registry/`: Becerilerin kaydedildiği `SKILL_REGISTRY.md` için en temiz ve modüler yerel konfigürasyon dizinidir.
3. **Workflows Durumu:** Antigravity'de `.agents/workflows/*.md` biçimi **kullanımdan kaldırılmıştır (deprecated)**. Modern Antigravity, tüm iş akışlarını doğrudan `skills/<name>/SKILL.md` formatında birinci sınıf slash-command ve progressive disclosure yetenekleriyle çalıştırmaktadır.

---

## 5. Koruma Politikası (Değiştirilmeyecek ve Korunacak Dosyalar)

Mevcut projede binlerce satırlık iş kuralı, teknik denetim ve veri modeli doğrulaması bulunmaktadır. Aşağıdaki dosyalar **kesinlikle silinmeyecek, üzerine genel şablon yazılmayacak ve bozulmayacaktır**:

1. `AGENTS.md` (Ortak bağlayıcı kurallar dizini)
2. `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` (Bağlayıcı ana plan)
3. `docs/requirements/BUSINESS_RULES_SPEC.md` (v1.2 - 159 kural)
4. `docs/requirements/PHASE_0_BUSINESS_DISCOVERY.md` (v1.3 keşif kararları)
5. `docs/architecture/DATA_MODEL.md` (v1.1 sertleştirilmiş veri modeli)
6. `docs/architecture/OFFLINE_SYNC_PROTOCOL.md` (v1.1 senkronizasyon protokolü)
7. `docs/architecture/LOCAL_STORAGE_TECHNICAL_VALIDATION.md` (v1.0 yerel depolama raporu)
8. `docs/architecture/BACKUP_RESTORE_PROTOCOL.md` (v1.0 yedekleme protokolü)
9. `docs/PROJECT_STATUS.md` ve `docs/ROADMAP.md`

---

## 6. Önerilen Geçiş ve Klasör Düzenleme Stratejisi

Mevcut yapıyı bozmadan hedef yapıya ulaşmak için **3 Aşamalı Yumuşak Geçiş (Soft Alignment)** önerilmektedir:

1. **Aşama A (Dokümantasyon Boşluklarının Kapatılması):**
   - Kök dizine kapsamlı bir `README.md` eklenmesi.
   - `docs/DEVELOPMENT_GUIDE.md`, `docs/decisions/README.md`, `docs/phases/PHASE-TEMPLATE.md` ve `docs/reports/README.md` dosyalarının açılması.
2. **Aşama B (Giriş Kapısı İndekslerinin Eklenmesi):**
   - `docs/PROJECT_OVERVIEW.md` ve `docs/REQUIREMENTS.md` dosyalarının mevcut zengin dokümanları işaret eden yönetici özetleri olarak kurgulanması.
3. **Aşama C (Antigravity `.agents/` Dizin Mimarisi):**
   - `.agents/registry/SKILL_REGISTRY.md` dosyasının açılması.
   - `.agents/skills/` altına onaylanan becerilerin yapılandırılması.

*Bu denetim raporu, mevcut yapının sağlam temeller üzerinde olduğunu ve gereksiz yeniden adlandırmalara girmeden hedef yapıya kusursuz biçimde genişletilebileceğini doğrulamaktadır.*

