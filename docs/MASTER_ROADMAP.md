# MASTER_ROADMAP.md — MARKET MMS 7 Fazlı Ana Geliştirme Yol Haritası

Bu belge, **MARKET MANAGEMENT SYSTEM (MMS)** ürünü için kabul edilmiş ve bağlayıcı **7 Fazlı Ana Geliştirme Yol Haritasını** tanımlar.

> [!IMPORTANT]
> **Tarihsel MVP Planından Ayrım:** Bu belge, erken dönem çekirdek MVP kuruluşunu (15 Kasım 2026 öncesi `Faz 0–8` numaralandırması; [`docs/ROADMAP.md`](./ROADMAP.md) ve [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../MARKET_POS_AI_STUDIO_BUILD_PLANI.md) v1.4) yöneten tarihsel kayıtlardan **ayrıdır ve onlarla karıştırılmamalıdır**. Çekirdek MVP temeli tamamlandıktan sonra ürünleştirme ve çok cihazlı saha hazırlığı bu belgedeki **Faz 1–7** sırasıyla yürütülür.

> [!NOTE]
> **21 Kasım 2026 — Release 1.0 Teknik Tamamlama Durumu (Faz Kabulü Henüz Verilmemiştir):** Onaylanan `DEC-REV-1..5` (`P-BLOCK-1..3`), `ADR-020` (Android `JobScheduler` + arka plan `FlutterEngine` yedekleme), Google Drive uzak yedek listeleme/indirme/pre-verified geri yükleme ve `ADR-021` (Hub öncelikli Google Drive canlı senkronizasyon fallback) yazılımları uygulanmış; son kod temizliği sonrası **4 pakette 772/772 otomatik test** ve Android `:app:compileDebugKotlin` derlemesi geçmiştir. Ancak fiziksel cihaz/servis kabul testleri (`PAT-01…18`), üretim imza/sertifika/OAuth hazırlıkları (`OWNER_ACTION_CHECKLIST.md`) tamamlanmadan ve Owner açık kabul vermeden aşağıdaki fazların hiçbiri kabul edilmiş sayılmaz (`TECHNICALLY COMPLETE — PHYSICAL VALIDATION REQUIRED`). Ayrıntılar: [`LIVE_PROJECT_STATUS.md`](./LIVE_PROJECT_STATUS.md) ve [`RELEASE_1_0_FINAL_DELIVERY_REPORT.md`](./RELEASE_1_0_FINAL_DELIVERY_REPORT.md).

---

## 1. Ürün Vizyonu ve Kapsam Sınırı

- **Resmi Ürün Adı:** **MARKET MANAGEMENT SYSTEM (MMS)** *(Repository dizin adı teknik uyumluluk için `market-pos` olarak korunmaktadır).*
- **Vizyon:** Küçük ve orta ölçekli marketlerin günlük operasyonlarını yönetmek üzere geliştirilen **offline-first, çok cihazlı, veri kaybına karşı dayanıklı, güvenli ve sürdürülebilir bir market yönetim SaaS sistemi**.
- **Temel İşlevler:**
  - Barkod okuyarak ürünleri sepete ekleme.
  - Satış oluşturma ve satış geçmişini yönetme.
  - Ürün ve kategori yönetimi.
  - Stok takibi ve stok hareketleri.
  - Dashboard ve raporlama.
  - Kullanıcı ve cihaz yönetimi.
  - Windows ve Android cihazlar arasında senkronizasyon.
  - İnternet veya Hub bağlantısı olmadığında offline çalışma.
  - Veri bütünlüğünü koruyan senkronizasyon.
  - Yedekleme ve geri yükleme.
  - İlerleyen fazlarda kamera ile barkod/ürün tanımlama.
  - İlerleyen fazlarda Open Food Facts ürün bilgisi entegrasyonu.
- **Kesin Kapsam Sınırı:** MMS bir **banka POS terminali değildir**. Banka POS terminali entegrasyonu mevcut geliştirme kapsamının dışındadır; kullanıcı açıkça kapsamı değiştirmediği sürece geliştirilmez.

---

## 2. Kritik Mimari Değişmezler Özeti

Tüm fazlar boyunca aşağıdaki kuralların korunması zorunludur (ayrıntılar için [`AGENTS.md`](../AGENTS.md) ve [`GEMINI.md`](../GEMINI.md) Bölüm 6):

1. Windows Local Master Hub merkezi katalog ve satış otoritesidir.
2. Windows ve Android istemcileri yerel SQLite/Drift üzerinde offline çalışabilmelidir.
3. Senkronizasyon FIFO Outbox mantığını korumalıdır.
4. Idempotency mekanizması korunmalıdır.
5. Single-writer SQLite yaklaşımı gözetilmelidir.
6. Tenant ve store izolasyonu korunmalıdır.
7. Senkronizasyon tekrar çalıştırıldığında mükerrer kayıt oluşturmamalıdır; başarısız senkronizasyonlarda veri kaybı olmamalıdır.
8. Yerel transaction bütünlüğü korunmalıdır.
9. Para değerleri kuruş cinsinden integer (`int` / `BIGINT`) olarak tutulmalı ve para hesaplamalarında **Half-Up rounding** (`OD-01`) kullanılmalıdır.
10. Gerçekleşmiş satışlar keyfî olarak silinmemelidir.
11. Hub'dan indirilen veriler tekrar Outbox'a eklenerek sonsuz senkronizasyon döngüsü oluşturmamalıdır (echo loop engeli).
12. Cursor ve ACK ilerlemesi ancak ilgili veri işlemi başarılı olduğunda yapılmalıdır.
13. Mevcut cihaz kimliği, token ve eşleştirme mekanizmaları korunmalıdır.

> [!CAUTION]
> FIFO Outbox, idempotency, `client_seq`, satış senkronizasyonu ve veri bütünlüğü mekanizmalarını etkileyen değişiklikler **kritik mimari değişiklik** kabul edilir; uygulamadan önce durulup kullanıcıya **Kritik Karar Raporu** sunulur.

---

## 3. Faz Bağımlılıkları ve İlerleme Özeti

| Faz | Başlık | Ön Bağımlılık | Mevcut Durum |
|---|---|---|---|
| **Faz 1** | Otomatik Hub Keşfi ve Bağlantı Yönetimi | Çekirdek MVP temeli (Senkronizasyon, Satış Uplink/Downlink, Ürün Sync) | 🔄 **DEVAM EDİYOR** (`1.1` Windows tamamlandı, `1.2` henüz başlamadı) |
| **Faz 2** | Android ve Windows UI Ayrıştırması | Faz 1 tamamlanması ve kullanıcı kabulü | ⏳ **Bekliyor** |
| **Faz 3** | Platform Özel Klavye ve Barkod İşlemleri | Faz 2 tamamlanması ve kullanıcı kabulü | ⏳ **Bekliyor** |
| **Faz 4** | Kamera ile Ürün Tanımlama | Faz 3 tamamlanması ve kullanıcı kabulü | ⏳ **Bekliyor** |
| **Faz 5** | Open Food Facts Entegrasyonu | Faz 4 tamamlanması ve kullanıcı kabulü | ⏳ **Bekliyor** |
| **Faz 6** | Mobil Kullanılabilirlik ve Offline Deneyimi | Faz 5 tamamlanması ve kullanıcı kabulü | ⏳ **Bekliyor** |
| **Faz 7** | Üretim, Kurulum ve Dağıtım Hazırlığı | Faz 6 tamamlanması + pilot öncesi açık teknik koşullar (`B-2`, `B-3`, `SCM`, `ACL`) | ⏳ **Bekliyor** |

> [!NOTE]
> **Kod Durumu Notu (21 Kasım 2026 — faz başlıkları/kapsamı değiştirilmedi):** Yukarıdaki "Mevcut Durum" sütunu Owner **kabul** durumunu gösterir ve değiştirilmemiştir. Kod tabanında Faz 1–6'nın yazılım kapsamı uygulanmış ve otomatik testlidir; Faz 7 yazılım olarak büyük ölçüde tamamlanmıştır (kalan: gerçek SCM/ACL, üretim imza/sertifika, Google OAuth hesabı). Hiçbir faz için fiziksel cihaz kabul testi yapılmamıştır. Ek teknik tamamlama çalışmaları 7A (backup/restore & sync bütünlüğü), 7B (TLS/token/pairing), 7C (Windows servis & Android release), 7D (Google Drive & USB) olarak izlenir. Ayrıntı: [`FINAL_COMPLETION_REPORT.md`](./FINAL_COMPLETION_REPORT.md).
>
> **21 Kasım 2026 (3. oturum — Son Tamamlama ve Saha Kabulü Hazırlığı; faz başlıkları/kapsamı değiştirilmedi):** 7A–7D kapsamında 10 ek bulgu düzeltildi (üretim eşleştirmesinde CA parmak izinin hiç verilmemesi (PAIR-CA), Android otomatik yedek kapatıldı, restore koruyucu kopyası şifrelendi, yedek/restore kilidi, Drive'a yalnızca şifreli paket, eşleştirmede keşfin HTTPS kullanması, PowerShell 5.1 ayrıştırma hatası, kurulum betiğinin güncelleme sırası + otomatik geri dönüş, firewall alt ağ kısıtı, güncelleme manifesti bütünlüğü). Otomatik testler: 700 geçti / 0 başarısız. Fiziksel kabul planı: [`PHYSICAL_ACCEPTANCE_TEST_PLAN.md`](../PHYSICAL_ACCEPTANCE_TEST_PLAN.md); Owner işlemleri: [`OWNER_ACTION_CHECKLIST.md`](../OWNER_ACTION_CHECKLIST.md). Hiçbir faz Owner tarafından kabul edilmiş sayılmaz.
>
> **21 Kasım 2026 (Bütünleşik Teknik Düzeltme, ADR-015…020 Uygulaması ve Pilot Hazırlığı; faz başlıkları/kapsamı değiştirilmedi):** Owner kararları doğrultusunda ADR-015 env fallback / `/devices/revoke` loopback sertleştirmesi, ADR-016 `BackupOperationLock` heartbeat/60 sn kurtarma/TOCTOU koruması ve tam Hub+istemci kilit kapsamı, ADR-017 TLS CA/SAN/IP/Hostname/Tarih/MITM sınıflandırması ve UI/sync yüzeyi, ADR-018 `PairingQrPayload` uyumu + `P-BLOCK-1..3` tespiti, ADR-019 %20 KDV geçici pilot kısıtlarının dokümantasyonu ve ADR-020 `AndroidKeystoreTokenStore` hata eşlemesi + `minSdk 24` düzeltmesi tamamlandı. Güncel sıralı test doğrulaması: **730 geçti / 0 başarısız / 0 atlanan** (statik analizde 0 yeni hata/uyarı). Fiziksel testler (`PAT-01…15`) hâlâ **BLOCKED**; ayrıntılar için bkz.: [`PILOT_TECHNICAL_REMEDIATION_REPORT.md`](./PILOT_TECHNICAL_REMEDIATION_REPORT.md).

---

## 4. Yedi Fazlı Ana Geliştirme Yol Haritası (Faz 1 – Faz 7)

### FAZ 1 — OTOMATİK HUB KEŞFİ VE BAĞLANTI YÖNETİMİ
**Durum:** 🔄 **DEVAM EDİYOR**  
**Hedef:** Android cihazın Windows Hub'ı manuel IP girişi olmadan yerel ağda otomatik bulabilmesi ve bağlantıyı kesintisiz yönetebilmesi.

**Kapsam:**
- Windows Hub IP adresinin otomatik tespiti.
- UDP Broadcast ve uygun görülürse mDNS tabanlı keşif.
- Android cihazın aynı yerel ağdaki Hub'ı otomatik bulması.
- Birden fazla ağ arayüzü ve IP adresinin doğru değerlendirilmesi.
- Keşfedilen adresler için HTTP health doğrulaması.
- Otomatik bağlantı kurma.
- Bağlantı kopması durumunda yeniden keşif ve reconnect.
- Son başarılı Hub adresini saklama.
- Son adres kullanılamıyorsa yeniden keşif.
- Manuel IP girme seçeneği.
- Bağlantı durumunun kullanıcıya gösterilmesi.
- Mevcut cihaz eşleştirme ve kimlik doğrulama bilgilerinin korunması.

**Önemli Kurallar:**
- Android'de `127.0.0.1` varsayılan Hub adresi olarak kullanılmamalıdır.
- Hub bulunamazsa uygulama offline modda çalışabilmelidir.
- Birden fazla IP dönerse yalnızca HTTP health doğrulaması başarılı olan uygun adres seçilmelidir.
- VirtualBox, Hyper-V veya diğer sanal ağ arayüzleri yanlış Hub adresi seçimine neden olmamalıdır.
- Güvenlik ve mevcut pairing/token mekanizması korunmalıdır.
- İlk sürümde gereksiz karmaşık subnet taraması yapılmamalıdır. Gerçek ihtiyaç ortaya çıkarsa ayrıca değerlendirilmelidir.
- Faz 1 sırasında satış oluşturma, iptal/iade, FIFO Outbox, `client_seq` üretimi, ürün senkronizasyonu ve satış downlink mekanizmaları değiştirilmemelidir.

**Kabul Kriteri:**
Android cihaz, aynı Wi-Fi ağındaki Windows Hub'ı otomatik bulmalı ve bağlantı kurabilmelidir. Hub'ın IP adresi değiştiğinde yeniden keşif yapabilmelidir.

**Alt Faz Durumu:**
- **1.1 Hub-side UDP Discovery Responder:** Windows Hub tarafı uygulandı ve Windows üzerinde doğrulandı; gerçek Android cihaz ağ testi henüz yapılmadı.
- **1.2 Client Storage ve Hub Adresi Saklama:** ⏳ **HENÜZ BAŞLAMADI** *(Sıradaki görev — kullanıcı onayı bekliyor)*.
- **1.3 Android Discovery ve Bağlantı Yönetimi:** ⏳ **HENÜZ BAŞLAMADI**.
- **1.4 Gerçek Android–Windows Kabul Testleri:** ⏳ **BEKLİYOR**.

---

### FAZ 2 — ANDROID VE WINDOWS UI AYRIŞTIRMASI
**Durum:** ⏳ **Bekliyor** *(Ön Bağımlılık: Faz 1 kabulü)*  
**Hedef:** Her platformun kullanım ergonomisine uygun, bağımsız kullanıcı deneyimi oluşturmak.

**Kapsam:**
- Android ve Windows arayüzlerinin ayrıştırılması *(Android ekranları Windows ekranlarının küçültülmüş kopyası olmayacaktır)*.
- Mobil navigasyon yapısı *(`go_router` entegrasyonu bu faz kapsamında değerlendirilir)*.
- Responsive mobil ekranlar.
- Büyük dokunma alanları.
- Tek elle satış işlemi.
- Telefon ve tablet desteği.
- Windows masaüstü kullanımının korunması.
- Platforma uygun menü ve etkileşimler.

**Kabul Kriteri:**
Temel işlevler her iki platformda da çalışmalı; ancak kullanıcı deneyimi platforma uygun olmalıdır.

---

### FAZ 3 — PLATFORM ÖZEL KLAVYE VE BARKOD İŞLEMLERİ
**Durum:** ⏳ **Bekliyor** *(Ön Bağımlılık: Faz 2 kabulü)*  
**Hedef:** Android ve Windows barkod kullanımını platform donanımına uygun hale getirmek.

**Kapsam:**
- Android'de masaüstü klavye kısayollarının kaldırılması veya uygun hale getirilmesi.
- Windows klavye kısayollarının korunması.
- Android kamera ile barkod tarama.
- Barkod okutulduğunda ürünün doğrudan sepete eklenmesi.
- Fiziksel barkod okuyucu (USB HID) desteğinin korunması.
- Hatalı veya bulunamayan barkodların yönetilmesi.

**Kabul Kriteri:**
Android kamerayla okutulan ürün doğrudan sepete eklenmeli; fiziksel okuyucular da desteklenmeye devam etmelidir.

---

### FAZ 4 — KAMERA İLE ÜRÜN TANIMLAMA
**Durum:** ⏳ **Bekliyor** *(Ön Bağımlılık: Faz 3 kabulü)*  
**Hedef:** Ürün oluşturma sürecini mobil kamera üzerinden hızlandırmak ve kolaylaştırmak.

**Kapsam:**
- Ürün formundan kamera açılması.
- Barkod tarama.
- Barkod üzerinden ürün bilgisi arama.
- Bulunan bilgilerin ürün formuna aktarılması.
- Kullanıcının bilgileri düzenleyebilmesi.
- Ürün bulunamazsa manuel giriş yapılabilmesi.

**Kabul Kriteri:**
Kamera ile okutulan barkod doğru ürün formuna aktarılmalı ve kullanıcı bilgileri düzenleyerek kaydedebilmelidir.

---

### FAZ 5 — OPEN FOOD FACTS ENTEGRASYONU
**Durum:** ⏳ **Bekliyor** *(Ön Bağımlılık: Faz 4 kabulü)*  
**Hedef:** Barkod üzerinden harici ürün bilgilerini otomatik önermek.

**Kapsam:**
- Open Food Facts API entegrasyonu.
- Ürün adı, marka, kategori, ürün görseli, içindekiler ve besin değerlerinin çekilmesi.
- API verilerinin kullanıcı tarafından düzenlenebilmesi.
- Bulunamayan ürünlerde manuel giriş.

**Önemli Kurallar:**
- Satış fiyatı API'den otomatik belirlenmemelidir.
- Maliyet, stok ve minimum stok bilgileri kullanıcı tarafından girilmelidir.
- API'den gelen hiçbir veri kullanıcı onayı olmadan kesin ürün bilgisi olarak kabul edilmemelidir.
- Harici API hataları temel ürün oluşturma işlevini engellememelidir.

**Kabul Kriteri:**
Bilinen bir barkod okutulduğunda ürün bilgileri doldurulmalı, kullanıcı bilgileri düzenleyebilmeli ve ürünü kaydedebilmelidir.

---

### FAZ 6 — MOBİL KULLANILABİLİRLİK VE OFFLINE DENEYİMİ
**Durum:** ⏳ **Bekliyor** *(Ön Bağımlılık: Faz 5 kabulü)*  
**Hedef:** Android uygulamasının gerçek market koşullarında kesintisiz ve güvenilir şekilde çalışmasını sağlamak.

**Kapsam:**
- Bağlantı durumunun açık gösterilmesi.
- Bekleyen senkronizasyon sayısının gösterilmesi.
- Senkronizasyon hatalarının anlaşılır gösterilmesi.
- Offline satış deneyiminin iyileştirilmesi.
- Düşük donanımlı cihazlarda performans iyileştirmesi.
- Katalog ve satış ekranı performansı.
- Telefon ve tablet uyumluluğu.
- Uygulama yeniden açıldığında veri tutarlılığı.
- Bağlantı geldiğinde kayıpsız senkronizasyon.

**Kabul Kriteri:**
Hub bağlantısı kesildiğinde Android satış yapmaya devam etmeli; bağlantı geldiğinde işlemler kayıpsız ve mükerrer kayıt oluşturmadan senkronize edilmelidir.

---

### FAZ 7 — ÜRETİM, KURULUM VE DAĞITIM HAZIRLIĞI
**Durum:** ⏳ **Bekliyor** *(Ön Bağımlılık: Faz 6 kabulü ve pilot öncesi açık teknik koşulların tamamlanması)*  
**Hedef:** MMS'nin teknik bilgisi olmayan market sahipleri tarafından kurulup yönetilebilmesini sağlamak.

**Kapsam:**
- Windows Hub installer ve otomatik başlatma (Windows Service / WinSW SCM doğrulaması dahil).
- Android APK dağıtımı.
- İlk kurulum sihirbazı, market/mağaza tanımlama ve cihaz eşleştirme (`B-2` Certificate Pinning, `B-3` güvenli token depolama ve route-specific pairing token restriction dahil).
- Yedekleme ve geri yükleme (S5A-4 AES-256-CBC + PBKDF2 600.000 iterasyon + HMAC-SHA256 standardı).
- Loglama ve hata raporlama.
- Güvenlik ve kimlik doğrulama değerlendirmesi (non-admin ACL dahil).
- Güncelleme mekanizması.
- Birden fazla market kurulumunun desteklenmesi (gelecek SaaS uyumluluğu).

**Kabul Kriteri:**
Teknik bilgisi olmayan bir market sahibi Windows Hub'ı kurabilmeli, Android cihazı eşleştirebilmeli ve temel market operasyonlarını kullanabilmelidir.

---

## 5. Faz Geçiş ve Kabul Prosedürü

1. **Faz İçi 14 Adımlı Geliştirme Döngüsü:** Kod tabanı analizi → Kapsam/bağımlılık tespiti → Uygulama planı → Risk değerlendirmesi → Geliştirme → Unit test → Integration test → Regresyon testi → Static analysis → Platform build'leri → Hata giderme → Test tekrarı → Doğrulama → Faz Tamamlama Raporu.
2. **Kritik Karar Durakları:** Mimari değişiklik, şema/migration riski, veri kaybı riski, güvenlik/pairing değişimi, FIFO Outbox / `client_seq` / senkronizasyon etkisi veya kapsam genişlemesi gerekiyorsa uygulamadan önce durulup **7 başlıklı Kritik Karar Raporu** sunulur.
3. **Tamamlama Kriterleri:** Teknik geliştirme + uygun test katmanları + regresyon testleri + static analysis + platform build'leri + **14 başlıklı Faz Tamamlama Raporu** + gereken fiziksel cihaz kabul testleri.
4. **Gerçek Cihaz Kabul Testi Kuralı:** Kullanıcıya tek seferde **bir test adımı** verilir ve sonucu beklenir; kullanıcı sonucu bildirmeden test başarılı kabul edilmez.
5. **Kullanıcı Onayı Şartı:** Kullanıcı bir fazı açıkça kabul etmeden sonraki faza geçilemez.

---

## 6. Tarihsel MVP Planıyla (`docs/ROADMAP.md` — Faz 0–8) İlişki

- [`docs/ROADMAP.md`](./ROADMAP.md) ve [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](../MARKET_POS_AI_STUDIO_BUILD_PLANI.md) (v1.4) içinde yer alan `Faz 0–8` planlaması, projenin başlangıçından **15 Kasım 2026**'ya kadar yürütülen **çekirdek MVP kuruluş dönemini** (Faz 0 Planlama & SPIKE-01, eski Faz 1.1 Windows Client Foundation, DT-01, UI/UX Prototip Programı `OD-01..04`, PaymentMethod standardizasyonu, eski Faz 1.2 POS/Sepet ve eski Faz 1.3.1.1 Outbox Diagnostics) kapsayan tarihsel referanstır.
- Güncel ürünleştirme, çok cihazlı bağlantı, platform ayrıştırması, kamera/Open Food Facts ve mağaza kurulum süreçleri bu belgede yer alan **7 Fazlı Ana Yol Haritası (`Faz 1 – Faz 7`)** üzerinden yönetilir; eski ve yeni faz numaraları birbiriyle karıştırılmaz.
