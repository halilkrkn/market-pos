/**
 * MARKET MMS — WCAG 2.1 AA / AAA Color Contrast Verification Script (Node.js)
 * Standart: WCAG 2.1 Bağıl Parlaklık (Relative Luminance) ve Kontrast Algoritması
 * Formül: IEC 61966-2-1:1999 resmi sRGB doğrusal dönüşüm eşiği (0.04045)
 */

const fs = require('fs');

function hexToRgb(hex) {
  hex = hex.replace('#', '');
  if (hex.length === 3) hex = hex.split('').map(c => c + c).join('');
  return [parseInt(hex.substr(0, 2), 16), parseInt(hex.substr(2, 2), 16), parseInt(hex.substr(4, 2), 16)];
}

// IEC 61966-2-1:1999 sRGB to Linear conversion with official 0.04045 threshold
function sRGBtoLin(c) {
  c = c / 255;
  return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

function luminance(rgb) {
  return 0.2126 * sRGBtoLin(rgb[0]) + 0.7152 * sRGBtoLin(rgb[1]) + 0.0722 * sRGBtoLin(rgb[2]);
}

function blend(fgHex, alpha, bgHex) {
  const fg = hexToRgb(fgHex);
  const bg = hexToRgb(bgHex);
  return [
    Math.round(fg[0] * alpha + bg[0] * (1 - alpha)),
    Math.round(fg[1] * alpha + bg[1] * (1 - alpha)),
    Math.round(fg[2] * alpha + bg[2] * (1 - alpha))
  ];
}

function contrast(c1, c2) {
  const rgb1 = typeof c1 === 'string' ? hexToRgb(c1) : c1;
  const rgb2 = typeof c2 === 'string' ? hexToRgb(c2) : c2;
  const l1 = luminance(rgb1);
  const l2 = luminance(rgb2);
  return (Math.max(l1, l2) + 0.05) / (Math.min(l1, l2) + 0.05);
}

// Blended surfaces in Dark mode
const darkOnlineBg = blend('#047857', 0.2, '#1E293B');
const darkOfflineBg = blend('#B45309', 0.2, '#1E293B');
const darkOutboxBg = blend('#1D4ED8', 0.25, '#1E293B');
const darkDangerBg = blend('#B91C1C', 0.2, '#1E293B');

const darkOnlineBgSubtle = blend('#047857', 0.2, '#0F172A');
const darkOfflineBgSubtle = blend('#B45309', 0.2, '#0F172A');
const darkOutboxBgSubtle = blend('#1D4ED8', 0.25, '#0F172A');
const darkDangerBgSubtle = blend('#B91C1C', 0.2, '#0F172A');

// Blended surfaces over --bg-app (#090D16) for elements directly on app canvas in Dark mode
const darkWarningBgApp = blend('#B45309', 0.2, '#090D16');
const darkDangerBgApp = blend('#B91C1C', 0.2, '#090D16');
const darkOutboxBgApp = blend('#1D4ED8', 0.25, '#090D16');

// Blended overlay text in mob-02 camera viewport (#020617)
const mobScannerHintFg = blend('#FFFFFF', 0.7, '#020617');

const tableHoverBgLight = blend('#94A3B8', 0.05, '#FFFFFF');
const tableHoverBgDark = blend('#94A3B8', 0.05, '#1E293B');

const checks = [
  // LIGHT THEME — Metin ve Temel Bileşenler (Light --text-muted: #475569)
  { theme: 'Light', el: 'Gövde Metni (.text-main)', fg: '#0F172A', bg: '#FFFFFF', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'İkincil Metin (.text-muted / --bg-surface)', fg: '#475569', bg: '#FFFFFF', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'İkincil Metin (.text-muted / --bg-app)', fg: '#475569', bg: '#F8FAFC', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'İkincil Metin (.text-muted / --bg-surface-subtle)', fg: '#475569', bg: '#F1F5F9', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Input Placeholder (.input-text::placeholder)', fg: '#475569', bg: '#FFFFFF', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Aktif Menü Linki (.nav-link.active)', fg: '#1E40AF', bg: '#F1F5F9', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Aktif Mobil Sekme (.mob-nav-item.active)', fg: '#1E40AF', bg: '#FFFFFF', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Tablo Başlığı (table.mms-table th)', fg: '#475569', bg: '#F1F5F9', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Tablo Satır Hover Metni (.mms-table tr:hover td)', fg: '#0F172A', bg: tableHoverBgLight, req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Modal Başlık Metni (.modal-header)', fg: '#0F172A', bg: '#F1F5F9', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Modal Banknot Butonu (.banknote-btn)', fg: '#0F172A', bg: '#F1F5F9', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Modal Banknot Hover (.banknote-btn:hover)', fg: '#0F172A', bg: '#FFFFFF', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Numpad :active (.numpad-btn:active)', fg: '#0F172A', bg: '#E2E8F0', req: 4.5, type: 'Normal Text' },

  // LIGHT THEME — Butonlar (Normal ve Hover)
  { theme: 'Light', el: 'Birincil Buton (.btn-primary)', fg: '#FFFFFF', bg: '#0F172A', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Birincil Buton Hover (.btn-primary:hover)', fg: '#FFFFFF', bg: '#1E293B', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Nakit Butonu (.btn-cash)', fg: '#FFFFFF', bg: '#047857', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Nakit Butonu Hover (.btn-cash:hover)', fg: '#FFFFFF', bg: '#065F46', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Kredi Kartı Butonu (.btn-card)', fg: '#FFFFFF', bg: '#2563EB', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Kredi Kartı Butonu Hover (.btn-card:hover)', fg: '#FFFFFF', bg: '#1D4ED8', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'İptal / Sil Butonu (.btn-danger)', fg: '#FFFFFF', bg: '#B91C1C', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'İptal / Sil Hover (.btn-danger:hover)', fg: '#FFFFFF', bg: '#991B1B', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'İkincil Buton (.btn-secondary)', fg: '#0F172A', bg: '#FFFFFF', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'İkincil Buton Hover (.btn-secondary:hover)', fg: '#0F172A', bg: '#F1F5F9', req: 4.5, type: 'Normal Text' },

  // LIGHT THEME — Rozetler, Inline Durum Metinleri, Uyarılar ve Girdiler
  { theme: 'Light', el: 'Online Rozeti (.badge-online)', fg: '#166534', bg: '#DCFCE7', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Offline / Eksi Stok Rozeti (.badge-offline)', fg: '#92400E', bg: '#FEF3C7', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Outbox Rozeti (.badge-outbox)', fg: '#1E40AF', bg: '#DBEAFE', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Tehlike Rozeti (.badge-danger)', fg: '#991B1B', bg: '#FEE2E2', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Inline Semantik Başarı (--success-text / Yüzey)', fg: '#166534', bg: '#FFFFFF', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Inline Semantik Uyarı (--warning-text / Subtle)', fg: '#92400E', bg: '#F1F5F9', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Inline Semantik Hata (--danger-text / Yüzey)', fg: '#991B1B', bg: '#FFFFFF', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Form Hata Mesajı (.input-error-msg)', fg: '#991B1B', bg: '#FFFFFF', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Demo Uyarı Çubuğu (.demo-disclaimer-bar)', fg: '#B45309', bg: '#FFFBEB', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Para Üstü Kutusu (.change-display-box)', fg: '#166534', bg: '#DCFCE7', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Para Üstü Hata Kutusu (.change-display-box.is-error)', fg: '#991B1B', bg: '#FEE2E2', req: 4.5, type: 'Normal Text' },
  { theme: 'Light', el: 'Input Çerçeve Sınırı (.input-text)', fg: '#64748B', bg: '#FFFFFF', req: 3.0, type: 'UI Component' },
  { theme: 'Light', el: 'Input Hata Çerçevesi (.input-error)', fg: '#B91C1C', bg: '#FFFFFF', req: 3.0, type: 'UI Component' },
  { theme: 'Light', el: 'Odak Halkası (:focus-visible)', fg: '#2563EB', bg: '#FFFFFF', req: 3.0, type: 'UI Component' },

  // DARK THEME — Metin ve Temel Bileşenler
  { theme: 'Dark', el: 'Gövde Metni (.text-main)', fg: '#F8FAFC', bg: '#1E293B', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'İkincil Metin (.text-muted / --bg-surface)', fg: '#94A3B8', bg: '#1E293B', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'İkincil Metin (.text-muted / --bg-surface-subtle)', fg: '#94A3B8', bg: '#0F172A', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Input Placeholder (.input-text::placeholder)', fg: '#94A3B8', bg: '#1E293B', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Aktif Menü Linki (.nav-link.active)', fg: '#60A5FA', bg: '#0F172A', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Aktif Mobil Sekme (.mob-nav-item.active)', fg: '#60A5FA', bg: '#1E293B', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Tablo Başlığı (table.mms-table th)', fg: '#94A3B8', bg: '#0F172A', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Tablo Satır Hover Metni (.mms-table tr:hover td)', fg: '#F8FAFC', bg: tableHoverBgDark, req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Modal Başlık Metni (.modal-header)', fg: '#F8FAFC', bg: '#0F172A', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Modal Banknot Butonu (.banknote-btn)', fg: '#F8FAFC', bg: '#0F172A', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Modal Banknot Hover (.banknote-btn:hover)', fg: '#F8FAFC', bg: '#1E293B', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Numpad :active (.numpad-btn:active)', fg: '#F8FAFC', bg: '#334155', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Numpad C Butonu (App RGBA Blend)', fg: '#F87171', bg: darkDangerBgApp, req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Numpad OK Butonu (App RGBA Blend)', fg: '#60A5FA', bg: darkOutboxBgApp, req: 4.5, type: 'Normal Text' },

  // DARK THEME — Butonlar (Normal ve Hover)
  { theme: 'Dark', el: 'Birincil Buton (.btn-primary)', fg: '#0F172A', bg: '#F8FAFC', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Birincil Buton Hover (.btn-primary:hover)', fg: '#0F172A', bg: '#E2E8F0', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Nakit Butonu (.btn-cash)', fg: '#FFFFFF', bg: '#047857', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Nakit Butonu Hover (.btn-cash:hover)', fg: '#FFFFFF', bg: '#065F46', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Kredi Kartı Butonu (.btn-card)', fg: '#FFFFFF', bg: '#1D4ED8', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Kredi Kartı Butonu Hover (.btn-card:hover)', fg: '#FFFFFF', bg: '#1E40AF', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'İptal / Sil Butonu (.btn-danger)', fg: '#FFFFFF', bg: '#B91C1C', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'İptal / Sil Hover (.btn-danger:hover)', fg: '#FFFFFF', bg: '#991B1B', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'İkincil Buton (.btn-secondary)', fg: '#F8FAFC', bg: '#1E293B', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'İkincil Buton Hover (.btn-secondary:hover)', fg: '#F8FAFC', bg: '#0F172A', req: 4.5, type: 'Normal Text' },

  // DARK THEME — Rozetler, Inline Durum Metinleri, Uyarılar ve Girdiler
  { theme: 'Dark', el: 'Online Rozeti (Surface-800 RGBA Blend)', fg: '#34D399', bg: darkOnlineBg, req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Online Rozeti (Surface-900 RGBA Blend)', fg: '#34D399', bg: darkOnlineBgSubtle, req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Offline Rozeti (Surface-800 RGBA Blend)', fg: '#FBBF24', bg: darkOfflineBg, req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Offline Rozeti (Surface-900 RGBA Blend)', fg: '#FBBF24', bg: darkOfflineBgSubtle, req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Outbox Rozeti (Surface-800 RGBA Blend)', fg: '#60A5FA', bg: darkOutboxBg, req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Outbox Rozeti (Surface-900 RGBA Blend)', fg: '#60A5FA', bg: darkOutboxBgSubtle, req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Tehlike Rozeti (Surface-800 RGBA Blend)', fg: '#F87171', bg: darkDangerBg, req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Tehlike Rozeti (Surface-900 RGBA Blend)', fg: '#F87171', bg: darkDangerBgSubtle, req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'win-06 Uyarı Kartı (App RGBA Blend)', fg: '#FBBF24', bg: darkWarningBgApp, req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Inline Semantik Başarı (--success-text / Surface-800)', fg: '#34D399', bg: '#1E293B', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Inline Semantik Başarı (--success-text / Subtle-900)', fg: '#34D399', bg: '#0F172A', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Inline Semantik Uyarı (--warning-text / Surface-800)', fg: '#FBBF24', bg: '#1E293B', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Inline Semantik Uyarı (--warning-text / Subtle-900)', fg: '#FBBF24', bg: '#0F172A', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Inline Semantik Hata (--danger-text / Surface-800)', fg: '#F87171', bg: '#1E293B', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Form Hata Mesajı (.input-error-msg)', fg: '#F87171', bg: '#1E293B', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Demo Uyarı Çubuğu (.demo-disclaimer-bar)', fg: '#FBBF24', bg: '#1C1917', req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Para Üstü Kutusu (.change-display-box RGBA Blend)', fg: '#34D399', bg: darkOnlineBg, req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Para Üstü Hata Kutusu (.change-display-box.is-error RGBA Blend)', fg: '#F87171', bg: darkDangerBg, req: 4.5, type: 'Normal Text' },
  { theme: 'Dark', el: 'Input Çerçeve Sınırı (.input-text)', fg: '#64748B', bg: '#1E293B', req: 3.0, type: 'UI Component' },
  { theme: 'Dark', el: 'Input Hata Çerçevesi (.input-error)', fg: '#F87171', bg: '#1E293B', req: 3.0, type: 'UI Component' },
  { theme: 'Dark', el: 'Odak Halkası (:focus-visible)', fg: '#60A5FA', bg: '#1E293B', req: 3.0, type: 'UI Component' },
  { theme: 'Mob-02', el: 'Kamera Vizörü İpucu (70% White over #020617)', fg: mobScannerHintFg, bg: '#020617', req: 4.5, type: 'Normal Text' }
];

console.log('====================================================================================================');
console.log(' MARKET MMS — WCAG 2.1 RENK KONTRAST DOĞRULAMA RAPORU (IEC 61966-2-1 sRGB Eşik: 0.04045)');
console.log(' KAPSAM NOTU: Bu betik YALNIZCA renk kontrast oranlarını (SC 1.4.3 / 1.4.11) ölçer; tam WCAG 2.1');
console.log(' erişilebilirlik uygunluğu beyanı değildir. Devre dışı (.btn:disabled, opacity: 0.45) öğeler');
console.log(' WCAG 2.1 SC 1.4.3 istisnası (Inactive UI) gereği test kapsamı dışında bırakılmıştır (PASS sayılmaz).');
console.log('====================================================================================================\n');
console.log('| Tema | Bileşen / Kullanım Durumu | Ön Plan (FG) | Arka Plan (BG) | Kontrast | Kriter | Değerlendirme |');
console.log('|---|---|---|---|:---:|:---:|:---:|');

let passCount = 0;
let failCount = 0;

function formatColor(c) {
  if (typeof c === 'string') return c;
  return `rgb(${c[0]},${c[1]},${c[2]})`;
}

checks.forEach(c => {
  const cr = contrast(c.fg, c.bg);
  const pass = cr >= c.req;
  if (pass) passCount++; else failCount++;
  const level = cr >= 7.0 ? 'PASS AAA' : (pass ? 'PASS AA' : 'FAIL');
  console.log(`| ${c.theme} | ${c.el} | \`${formatColor(c.fg)}\` | \`${formatColor(c.bg)}\` | **${cr.toFixed(2)}:1** | ≥ ${c.req}:1 | ${pass ? '✅ ' + level : '❌ FAIL'} |`);
});

console.log('\n====================================================================================================');
console.log(` TOPLAM RENK KONTRAST KONTROLÜ: ${checks.length} | BAŞARILI: ${passCount} | BAŞARISIZ: ${failCount}`);
console.log(' MUAF / TEST EDİLMEYEN DURUM: .btn:disabled (opacity: 0.45 — WCAG 2.1 SC 1.4.3 Inactive Muafiyeti)');
console.log('====================================================================================================');

if (failCount > 0) process.exit(1); else process.exit(0);
