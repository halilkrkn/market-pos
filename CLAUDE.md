# CLAUDE.md — Claude Code Çalışma Yönergeleri (Gelecek Entegrasyon)

> [!WARNING]
> Claude Code bu sistemde henüz kurulu veya aktif değildir. Bu belge, gelecekte Claude Code CLI ortamının projeye dahil edilmesi durumunda tutarlı ve standart bir çalışma protokolü sağlamak amacıyla hazırlanmıştır.

---

## 1. Ortak Kurallara Erişim

Claude Code kullanıldığında proje kuralları tek doğruluk kaynağı olan [`AGENTS.md`](./AGENTS.md) ve [`MARKET_POS_AI_STUDIO_BUILD_PLANI.md`](./MARKET_POS_AI_STUDIO_BUILD_PLANI.md) belgeleri üzerinden yürütülür.

Claude Code, repo kök dizinindeki `CLAUDE.md` ve `AGENTS.md` dosyalarını otomatik olarak oturum açılışında yükleme yeteneğine sahiptir.

---

## 2. Claude Code İçin Temel Protokol

1. **Önce Durum Kontrolü:** Her oturum başında [`docs/PROJECT_STATUS.md`](./docs/PROJECT_STATUS.md) okunarak projenin hangi fazda olduğu doğrulanır.
2. **Kod Yazım Kısıtı:** Faz 0 tamamlanmadan ve kullanıcı onayı alınmadan Flutter/Dart kaynak kodu oluşturulamaz.
3. **Katman Sınırlarına Uyum:** Feature-first ve Clean Architecture kuralları (`presentation` $\rightarrow$ `domain` $\leftarrow$ `data`) tavizsiz uygulanır.
4. **Detaylı Kurallara Referans:**
   - Proje İlkeleri: [`docs/ai/rules/project-principles.md`](./docs/ai/rules/project-principles.md)
   - Mimari: [`docs/ai/rules/clean-architecture.md`](./docs/ai/rules/clean-architecture.md)
   - Kod Kalitesi: [`docs/ai/rules/clean-code.md`](./docs/ai/rules/clean-code.md)
   - Güvenlik: [`docs/ai/rules/security.md`](./docs/ai/rules/security.md)
   - Offline-First: [`docs/ai/rules/offline-first.md`](./docs/ai/rules/offline-first.md)

---

## 3. Doğrulanmamış Noktalar

- Claude Code yerel makinede kurulu olmadığından, CLI komutları (`claude ...`) ve `.claude/rules/*.md` hiyerarşisi bu aşamada test edilememiştir.
- Claude Code ile çalışılırken Antigravity'ye özgü araç ve komutlar kullanılmamalıdır.

