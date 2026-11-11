/* ====================================================================
   MARKET MMS — Paylaşılan JavaScript Yardımcı Fonksiyonları
   Dosya: shared.js
   Sürüm: v1.1 (Zorunlu Para Standardı ve Kuruş Tamsayı Doğrulama)
   Tasarım Sistemi: UX_03_DESIGN_SYSTEM.md v1.1
   Kuruş Tamsayı Standardı (INV-01) — Format: "12.50 TL"
   ==================================================================== */

// 1. Tema Yönetimi (Light / Dark)
function initTheme() {
  const saved = localStorage.getItem('mms_theme');
  if (saved === 'dark' || (!saved && window.matchMedia('(prefers-color-scheme: dark)').matches)) {
    document.body.classList.add('dark');
  } else {
    document.body.classList.remove('dark');
  }
}

function toggleTheme() {
  document.body.classList.toggle('dark');
  const isDark = document.body.classList.contains('dark');
  localStorage.setItem('mms_theme', isDark ? 'dark' : 'light');
}

// 2. Kuruş Tamsayı Para Formatlayıcı (INV-01 Standardı)
// - Görsel gösterim: "12.50 TL"
// - Ondalık ayırıcı: nokta (.)
// - Her zaman iki ondalık basamak
// - Binlik ayırıcı: virgül (,)
// - Para birimi: tutardan sonra " TL"
// - Float / kayan noktalı bölme hesabı KULLANILMAZ (tamsayı bölme ve kalan kullanılır)
// - Hatalı değerler sessizce "0.00 TL" dönmez; TypeError fırlatır.
function formatKurus(cents) {
  if (typeof cents !== 'number' || !Number.isSafeInteger(cents)) {
    throw new TypeError(`Geçersiz kuruş değeri: "${cents}". Değer güvenli bir tamsayı (int) olmalıdır.`);
  }
  const isNegative = cents < 0;
  const absCents = Math.abs(cents);
  const liras = Math.floor(absCents / 100);
  const kurus = absCents % 100;
  const kurusStr = kurus < 10 ? '0' + kurus : '' + kurus;
  const liraStr = liras.toLocaleString('en-US'); // Binlik virgül: 1,250
  const sign = isNegative ? '-' : '';
  return sign + liraStr + '.' + kurusStr + ' TL';
}

// Kuruş tamsayısını form girdi kutusu için metne dönüştürür (toFixed kullanılmaz)
// Hatalı değerler sessizce "0.00" dönmez; TypeError fırlatır.
function formatCentsToInput(cents) {
  if (typeof cents !== 'number' || !Number.isSafeInteger(cents)) {
    throw new TypeError(`Geçersiz kuruş değeri: "${cents}". Değer güvenli bir tamsayı (int) olmalıdır.`);
  }
  const isNegative = cents < 0;
  const absCents = Math.abs(cents);
  const liras = Math.floor(absCents / 100);
  const kurus = absCents % 100;
  const kurusStr = kurus < 10 ? '0' + kurus : '' + kurus;
  const sign = isNegative ? '-' : '';
  return sign + liras + '.' + kurusStr;
}

// 3. Güvenli Metin Girdisinden Kuruş Tamsayı Dönüştürücü (String Parsing)
// - parseFloat ve Math.round(val * 100) KULLANILMAZ.
// - Float üzerinden para hesabı yapılmaz.
// - Doğrulama sonucu üretir: { valid: boolean, cents?: number, error?: string }
// - Birden fazla ondalık ayırıcıyı reddeder.
// - İki ondalık basamaktan fazlasını reddeder ("12.345" -> validation error).
// - Güvenli integer sınırlarını kontrol eder.
function parseToCents(textInput, allowNegative = false) {
  if (textInput === null || textInput === undefined) {
    return { valid: false, error: 'Boş giriş' };
  }
  const str = String(textInput).trim();
  if (str === '') {
    return { valid: false, error: 'Boş giriş' };
  }

  // 1. Boşlukları temizle ve büyük/küçük harf duyarsız TL sonekini ayıkla (12 TL, 12TL, 12 Tl, 12 tL)
  let cleaned = str.replace(/\s+/g, '');
  if (/tl$/i.test(cleaned)) {
    cleaned = cleaned.replace(/tl$/i, '').trim();
  }
  if (cleaned === '') {
    return { valid: false, error: 'Boş giriş' };
  }

  // 2. Negatif kontrolü
  let isNegative = false;
  if (cleaned.startsWith('-')) {
    if (!allowNegative) {
      return { valid: false, error: 'Negatif değerlere izin verilmez' };
    }
    isNegative = true;
    cleaned = cleaned.slice(1);
  }
  if (cleaned === '') {
    return { valid: false, error: 'Geçersiz sayısal format veya yabancı karakter' };
  }

  // 3. Ayırıcı sayıları ve format doğrulama
  const dotCount = (cleaned.match(/\./g) || []).length;
  const commaCount = (cleaned.match(/,/g) || []).length;

  let normalized = cleaned;

  if (commaCount === 0 && dotCount === 0) {
    // Tam tamsayı (Örn: "12")
    if (!/^\d+$/.test(cleaned)) {
      return { valid: false, error: 'Geçersiz sayısal format veya yabancı karakter' };
    }
    normalized = cleaned;
  } else if (commaCount === 0 && dotCount === 1) {
    // Yalnızca tek nokta ondalık (Örn: "12.50", "12.5")
    if (/^\d+\.\d{3,}$/.test(cleaned)) {
      return { valid: false, error: 'En fazla iki ondalık basamak girilebilir (Örn: 12.50)' };
    }
    if (!/^\d+\.\d{1,2}$/.test(cleaned)) {
      return { valid: false, error: 'Geçersiz sayısal format veya yabancı karakter' };
    }
    normalized = cleaned;
  } else if (commaCount === 1 && dotCount === 0) {
    // Yalnızca tek virgül ondalık (Türkçe tek virgül alışkanlığı: Örn: "12,50", "12,5")
    if (/^\d+,\d{3,}$/.test(cleaned)) {
      return { valid: false, error: 'En fazla iki ondalık basamak girilebilir (Örn: 12.50)' };
    }
    if (!/^\d+,\d{1,2}$/.test(cleaned)) {
      return { valid: false, error: 'Geçersiz sayısal format veya yabancı karakter' };
    }
    normalized = cleaned.replace(',', '.');
  } else if (commaCount >= 1 && dotCount >= 1) {
    const lastDot = cleaned.lastIndexOf('.');
    const lastComma = cleaned.lastIndexOf(',');
    if (lastDot > lastComma) {
      // Nokta en sonda: Virgüller binlik, nokta ondalık (Örn: "1,250.00", "1,250,000.00")
      if (!/^\d{1,3}(,\d{3})+(\.\d{1,2})?$/.test(cleaned)) {
        return { valid: false, error: 'Geçersiz binlik ayırıcı formatı (Örn: 1,250.00)' };
      }
      normalized = cleaned.replace(/,/g, '');
    } else {
      // Virgül en sonda: Noktalar binlik, virgül ondalık (Örn: "1.250,00", "1.250.000,00")
      if (!/^\d{1,3}(\.\d{3})+(,\d{1,2})?$/.test(cleaned)) {
        return { valid: false, error: 'Geçersiz binlik ayırıcı formatı (Örn: 1.250,00)' };
      }
      normalized = cleaned.replace(/\./g, '').replace(',', '.');
    }
  } else if (dotCount > 1 && commaCount === 0) {
    // Yalnızca noktalı binlik ayırıcılar (Örn: "1.250.000") veya çoklu nokta hatası ("12..50")
    if (/^\d{1,3}(\.\d{3})+$/.test(cleaned)) {
      normalized = cleaned.replace(/\./g, '');
    } else {
      return { valid: false, error: 'Birden fazla ondalık nokta ayırıcı içeremez' };
    }
  } else if (commaCount > 1 && dotCount === 0) {
    // Yalnızca virgüllü binlik ayırıcılar (Örn: "1,250,000") veya çoklu virgül hatası ("12,,50")
    if (/^\d{1,3}(,\d{3})+$/.test(cleaned)) {
      normalized = cleaned.replace(/,/g, '');
    } else {
      return { valid: false, error: 'Birden fazla virgül ayırıcı içeremez' };
    }
  } else {
    return { valid: false, error: 'Geçersiz sayısal format veya yabancı karakter' };
  }

  // 4. Parçalara ayır ve tamsayı kuruş hesabı yap
  const parts = normalized.split('.');
  const intPartStr = parts[0];
  const decPartStr = parts.length > 1 ? parts[1] : '';

  if (decPartStr.length > 2) {
    return { valid: false, error: 'En fazla iki ondalık basamak girilebilir (Örn: 12.50)' };
  }

  let decKurus = 0;
  if (decPartStr.length === 1) {
    decKurus = parseInt(decPartStr, 10) * 10;
  } else if (decPartStr.length === 2) {
    decKurus = parseInt(decPartStr, 10);
  }

  // 5. BigInt ile sınır kontrolü (IEEE-754 mantissa taşmasını ve precision kaybını engeller)
  try {
    const totalCentsBig = BigInt(intPartStr) * 100n + BigInt(decKurus);
    if (totalCentsBig > BigInt(Number.MAX_SAFE_INTEGER)) {
      return { valid: false, error: 'Güvenli kuruş tamsayı sınırı aşıldı' };
    }
    const totalCents = Number(totalCentsBig);
    const signedCents = totalCents === 0 ? 0 : (isNegative ? -totalCents : totalCents);
    return { valid: true, cents: signedCents };
  } catch (err) {
    return { valid: false, error: 'Güvenli kuruş tamsayı sınırı aşıldı' };
  }
}

// 4. Doğrulama Test Süiti (Doğrulama ve Tanı İçin)
function runCurrencyTests() {
  const tests = [
    { type: 'format', input: 1250, expected: '12.50 TL' },
    { type: 'format', input: 99, expected: '0.99 TL' },
    { type: 'format', input: 125000, expected: '1,250.00 TL' },
    { type: 'parse', input: '12.50', expectedValid: true, expectedCents: 1250 },
    { type: 'parse', input: '0.99', expectedValid: true, expectedCents: 99 },
    { type: 'parse', input: '1250.00', expectedValid: true, expectedCents: 125000 },
    { type: 'parse', input: '1,250.00', expectedValid: true, expectedCents: 125000 },
    { type: 'parse', input: '12,50', expectedValid: true, expectedCents: 1250 },
    { type: 'parse', input: '1.250,00', expectedValid: true, expectedCents: 125000 },
    { type: 'parse', input: '1,25.00', expectedValid: false },
    { type: 'parse', input: '1,,250.00', expectedValid: false },
    { type: 'parse', input: '12,34,567.89', expectedValid: false },
    { type: 'parse', input: '12 Tl', expectedValid: true, expectedCents: 1200 },
    { type: 'parse', input: '12.345', expectedValid: false },
    { type: 'parse', input: '12.5.0', expectedValid: false },
    { type: 'parse', input: '', expectedValid: false },
  ];

  let passed = 0;
  tests.forEach((t) => {
    if (t.type === 'format') {
      const res = formatKurus(t.input);
      if (res === t.expected) passed++;
      else console.error(`Format Test Failed for ${t.input}: got ${res}, expected ${t.expected}`);
    } else {
      const res = parseToCents(t.input);
      if (res.valid === t.expectedValid && (!t.expectedValid || res.cents === t.expectedCents)) passed++;
      else console.error(`Parse Test Failed for "${t.input}": got ${JSON.stringify(res)}`);
    }
  });
  return { total: tests.length, passed };
}

// DOM Hazır Olduğunda Başlat
if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', () => {
    initTheme();
  });
}

// Node.js ortamı için export
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { formatKurus, formatCentsToInput, parseToCents, runCurrencyTests };
}
