# SKILL_REGISTRY.md — MARKET MMS Beceri Kayıt Defteri

**Proje:** Market Management System (MMS)  
**Tarih:** 6 Kasım 2026  
**Aşama:** Faz 1 — DT-01.2 Final Beceri Aktivasyonu ve Entegrasyonu  
**Standart:** Google Antigravity Skill Ecosystem v1.0  
**Yönetim Kuralı:** Proje sahibi tarafından onaylanmamış ve kayıt altına alınmamış hiçbir harici beceri projede kullanılamaz.  
**Proje Sahibi Kararı:** `.agents/skills/` altındaki 5 çekirdek becerinin tamamı **ONAYLANMIŞ VE ETKİNLEŞTİRİLMİŞTİR**.

---

## 1. Etkinleştirilmiş Çekirdek Beceriler Envanteri

| Skill Adı | Kaynak / Yazar | Upstream Repo URL & Commit | Lisans Durumu | Amaç ve Katkı | Tetiklenme Senaryosu (Ne Zaman Kullanılır?) | Kurulum Konumu | Durum |
| :--- | :--- | :--- | :---: | :--- | :--- | :--- | :---: |
| **`code-quality`** | MMS İlkeleri & Matt Pocock kavramsal ilhamı | Doğrudan harici repo yok (İç derleme) | Doğrulanamadı (Proje Sahibi Onaylı) | Clean Architecture katman sınırları, saf Dart Domain, immutability, kuruş tamsayı ve anti-overengineering (YAGNI/KISS). | Dart/Flutter kodu yazılırken, domain entity/use case tasarlanırken, refactoring ve kod inceleme yapılırken. | `.agents/skills/code-quality/SKILL.md` | **ACTIVE** |
| **`test-first`** | Jesse Vincent (`obra`) | `https://github.com/obra/superpowers`<br/>`e9c3a1b` | MIT License (`LICENSE` & `NOTICE` mevcut) | TDD Red-Green-Refactor döngüsü, para hesabı hassasiyeti, eksi stok serbestliği, transaction atomikliği ve idempotency testleri. | İş kuralları, sepet hesaplamaları, stok hareketleri, para matematiği veya outbox senkronizasyonu kodlanırken. | `.agents/skills/test-first/SKILL.md` | **ACTIVE** |
| **`systematic-debugging`**| Jesse Vincent (`obra`) | `https://github.com/obra/superpowers`<br/>`e9c3a1b` | MIT License (`LICENSE` & `NOTICE` mevcut) | 4 fazlı Kök Neden Analizi (RCA), SQLite WAL kilitlenme teşhisi (`busy_timeout >= 5000`), Outbox takılma analizi. | Beklenmeyen bir hata, test başarısızlığı, SQLite kilitlenmesi veya senkronizasyon duraklaması incelenirken. | `.agents/skills/systematic-debugging/SKILL.md` | **ACTIVE** |
| **`flutter-ui-standards`**| nextlevelbuilder | `https://github.com/nextlevelbuilder/ui-ux-pro-max-skill`<br/>`3b8d14e` | MIT License (`LICENSE` & `NOTICE` mevcut) | Dokunmatik kasa buton boyutları ($\ge 48\times 48\text{ dp}$), tabular monospace para hizalama, USB HID barkod odak yönetimi, WCAG AAA kontrast. | Flutter ekranları, widget'ları, kasa satış arayüzü veya masaüstü/mobil responsive düzenler geliştirilirken. | `.agents/skills/flutter-ui-standards/SKILL.md` | **ACTIVE** |
| **`documentation`** | Universal Project Template kavramsal uyarlaması | Doğrudan harici repo yok (İç şablon) | Doğrulanamadı (Proje Sahibi Onaylı) | Kanonik dokümantasyon hiyerarşisi, Architecture Decision Record (ADR) yazımı, faz açılış/kapanış raporlaması. | Mimari kararlar belgelenirken, ADR açılırken, faz durum raporları veya kabul raporları hazırlanırken. | `.agents/skills/documentation/SKILL.md` | **ACTIVE** |

---

## 2. Kapsam ve Progressive Disclosure (Kademeli Yükleme) Kuralı

Antigravity ortamında token ve bağlam israfını önlemek amacıyla:
1. **Seçici Yükleme:** Beceriler her istekte körlemesine bağlama yüklenmez. Yalnızca ilgili görev başladığında (ör. test yazılırken `test-first`, hata ayıklanırken `systematic-debugging`) ilgili `SKILL.md` dosyası taranır.
2. **Kural Üstünlüğü:** Hiçbir beceri projenin kök `AGENTS.md` belgesindeki, `MARKET_POS_AI_STUDIO_BUILD_PLANI.md` şartnamesindeki veya `PROJECT_STATUS.md` içindeki kuralları ezemez.
3. **Rol İzolasyonu:** Beceriler yürütülebilir script içermez; saf Markdown rehberleridir.

---

## 3. Bağlayıcı Güvenlik Sınırları

Tüm becerilerin kullanımı sırasında aşağıdaki güvenlik kuralları tavizsiz işletilir:
1. **Kör Komut Yasağı:** Beceriler kullanıcı onayı olmadan yıkıcı shell betikleri (`rm -rf`, `DROP TABLE`, `git reset`) veya kontrolsüz terminal komutları çalıştıramaz.
2. **Gizlilik:** API anahtarları, şifreler, Google Drive OAuth token'ları veya Windows DPAPI anahtarları (`pepper.dpapi`) asla beceri metinlerine yazılamaz veya bu beceriler üzerinden dışarı sızdırılamaz.
3. **Kullanıcı Onayı İlkesi:** Kod değişikliği, faz kabulü, dosya silme veya commit/push işlemleri yalnızca kullanıcının açık onayı ile yürütülür.
4. **Git Bütünlüğü:** Force push (`--force`) ve commit geçmişini değiştirme kesinlikle yasaktır.

---

## 4. Kapsam Dışı Bırakılan Beceriler Envanteri

- **`affaan-m/ECC`:** Kullanıcı talimatı gereği incelenmemiş ve kesinlikle kapsam dışı bırakılmıştır.
- **`safe-edit` (Bağımsız Skill):** Projenin kök `AGENTS.md` ve Antigravity built-in `accidental-data-loss-prevention` kuralları tarafından doğrudan uygulandığı için ayrı kurulmamıştır.
- **`domain-modeling` (Bağımsız Skill):** `code-quality` becerisinin içine entegre edilmiştir.
- **`pbakaus/impeccable` (CLI Araçları):** Denetimsiz harici npm komutları çalıştırmamak için bağımsız kurulmamış; arayüz prensipleri `flutter-ui-standards` becerisine aktarılmıştır.
- **UI UX Pro Max Web/React Bileşenleri:** MMS bir Flutter projesi olduğundan web/react bileşenleri tamamen ayıklanmıştır.
