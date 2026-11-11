/**
 * MARKET MMS — Currency Engine Test Runner (Node.js)
 * Bağımsız Kuruş Tamsayı ve String Ayrıştırma Test Süiti
 * Kapsam: parseToCents, formatKurus, formatCentsToInput
 */

const { parseToCents, formatKurus, formatCentsToInput } = require('./shared.js');

console.log('================================================================');
console.log(' MARKET MMS — JAVASCRIPT KURUŞ PARA MOTORU DOĞRULAMA TESTLERİ');
console.log(' Standart: 12.50 TL | Kuruş Tamsayı Standardı [INV-01]');
console.log('================================================================\n');

let totalTests = 0;
let passedTests = 0;
let failedTests = 0;

function assert(description, actual, expected) {
  totalTests++;
  const isMatch = JSON.stringify(actual) === JSON.stringify(expected);
  if (isMatch) {
    passedTests++;
    console.log(`  [PASS] Test #${totalTests}: ${description}`);
  } else {
    failedTests++;
    console.error(`  [FAIL] Test #${totalTests}: ${description}`);
    console.error(`         Beklenen: ${JSON.stringify(expected)}`);
    console.error(`         Alınan:   ${JSON.stringify(actual)}`);
  }
}

function assertThrows(description, fn, expectedErrorType) {
  totalTests++;
  try {
    fn();
    failedTests++;
    console.error(`  [FAIL] Test #${totalTests}: ${description} (Hata fırlatılmadı!)`);
  } catch (err) {
    if (err instanceof expectedErrorType) {
      passedTests++;
      console.log(`  [PASS] Test #${totalTests}: ${description} -> ${err.name}: ${err.message}`);
    } else {
      failedTests++;
      console.error(`  [FAIL] Test #${totalTests}: ${description} (Beklenmeyen hata tipi: ${err})`);
    }
  }
}

console.log('--- 1. BÖLÜM: parseToCents() Ayrıştırma Testleri (13 Test) ---');

// Test 1: Standart iki basamaklı pozitif tutar
assert('parseToCents("12.50") standart iki basamaklı kuruş',
  parseToCents('12.50'),
  { valid: true, cents: 1250 });

// Test 2: Tek basamaklı kuruş (ondalık tamamlanmalı: 12.5 -> 1250 kuruş)
assert('parseToCents("12.5") tek basamaklı kuruş (12.50 TL karşılığı)',
  parseToCents('12.5'),
  { valid: true, cents: 1250 });

// Test 3: Ondalıksız tam lira (12 -> 1200 kuruş)
assert('parseToCents("12") tamsayı lira',
  parseToCents('12'),
  { valid: true, cents: 1200 });

// Test 4: Bir liradan küçük tutar (0.50 -> 50 kuruş)
assert('parseToCents("0.50") alt lira standart',
  parseToCents('0.50'),
  { valid: true, cents: 50 });

// Test 5: Bir liradan küçük tek basamaklı tutar (0.5 -> 50 kuruş)
assert('parseToCents("0.5") alt lira tek basamak',
  parseToCents('0.5'),
  { valid: true, cents: 50 });

// Test 6: Sıfır lira (0 -> 0 kuruş)
assert('parseToCents("0") sıfır tutar',
  parseToCents('0'),
  { valid: true, cents: 0 });

// Test 7: TL soneki içeren girdi ("12.50 TL" -> 1250 kuruş)
assert('parseToCents("12.50 TL") TL para birimi eki içeren metin',
  parseToCents('12.50 TL'),
  { valid: true, cents: 1250 });

// Test 8: Boş girdi (reddedilmeli)
assert('parseToCents("") boş metin girişi',
  parseToCents(''),
  { valid: false, error: 'Boş giriş' });

// Test 9: Sayısal olmayan karakter içeren girdi (reddedilmeli)
assert('parseToCents("abc") geçersiz harfli metin',
  parseToCents('abc'),
  { valid: false, error: 'Geçersiz sayısal format veya yabancı karakter' });

// Test 10: Varsayılan modda negatif girdi (reddedilmeli)
assert('parseToCents("-5") negatif tutar (allowNegative=false)',
  parseToCents('-5'),
  { valid: false, error: 'Negatif değerlere izin verilmez' });

// Test 11: İzin verilen modda negatif girdi (allowNegative=true -> -500 kuruş)
assert('parseToCents("-5", true) negatif tutar (allowNegative=true)',
  parseToCents('-5', true),
  { valid: true, cents: -500 });

// Test 12: İkiden fazla ondalık basamak (reddedilmeli, alt kuruş kabul edilmez)
assert('parseToCents("12.345") 3 ondalık basamaklı girdi',
  parseToCents('12.345'),
  { valid: false, error: 'En fazla iki ondalık basamak girilebilir (Örn: 12.50)' });

// Test 13: Birden fazla ondalık nokta (reddedilmeli)
assert('parseToCents("12..50") çoklu ondalık nokta',
  parseToCents('12..50'),
  { valid: false, error: 'Birden fazla ondalık nokta ayırıcı içeremez' });

console.log('\n--- 2. BÖLÜM: formatKurus() Formatlama & Hata Yönetimi Testleri ---');

// Test 14: Standart formatlama
assert('formatKurus(1250) -> "12.50 TL"',
  formatKurus(1250),
  '12.50 TL');

// Test 15: Bir liradan küçük formatlama
assert('formatKurus(99) -> "0.99 TL"',
  formatKurus(99),
  '0.99 TL');

// Test 16: Binlik virgüllü formatlama
assert('formatKurus(125000) -> "1,250.00 TL"',
  formatKurus(125000),
  '1,250.00 TL');

// Test 17: Sıfır kuruş formatlama
assert('formatKurus(0) -> "0.00 TL"',
  formatKurus(0),
  '0.00 TL');

// Test 18: Negatif kuruş formatlama
assert('formatKurus(-500) -> "-5.00 TL"',
  formatKurus(-500),
  '-5.00 TL');

// Test 19: Hatalı değer sessizce 0.00 TL olmamalı; TypeError fırlatmalı (NaN)
assertThrows('formatKurus(NaN) TypeError fırlatmalı (sessizce yutulamaz)',
  () => formatKurus(NaN),
  TypeError);

// Test 20: Hatalı değer sessizce 0.00 TL olmamalı; TypeError fırlatmalı (null)
assertThrows('formatKurus(null) TypeError fırlatmalı (sessizce yutulamaz)',
  () => formatKurus(null),
  TypeError);

// Test 21: Float / ondalıklı sayı girişi engellenmeli (yalnızca tamsayı kuruş)
assertThrows('formatKurus(12.5) float kuruş girişi reddedilmeli',
  () => formatKurus(12.5),
  TypeError);

console.log('\n--- 3. BÖLÜM: formatCentsToInput() İnput Formatlayıcı Testleri ---');

// Test 22: Standart input formatı
assert('formatCentsToInput(1250) -> "12.50"',
  formatCentsToInput(1250),
  '12.50');

// Test 23: Alt lira input formatı
assert('formatCentsToInput(50) -> "0.50"',
  formatCentsToInput(50),
  '0.50');

// Test 24: Sıfır input formatı
assert('formatCentsToInput(0) -> "0.00"',
  formatCentsToInput(0),
  '0.00');

// Test 25: Hatalı input değeri TypeError fırlatmalı
assertThrows('formatCentsToInput(undefined) TypeError fırlatmalı',
  () => formatCentsToInput(undefined),
  TypeError);

console.log('\n--- 4. BÖLÜM: Yeni Zorunlu Sınır & Ayırıcı Doğrulama Testleri ---');

// Test 26: Türkçe tek virgül ondalık (12,50 -> 1250 kuruş)
assert('parseToCents("12,50") Türkçe tek virgül ondalık',
  parseToCents('12,50'),
  { valid: true, cents: 1250 });

// Test 27: Standart binlik virgüllü ondalık (1,250.00 -> 125000 kuruş)
assert('parseToCents("1,250.00") standart 3 basamaklı binlik virgüllü',
  parseToCents('1,250.00'),
  { valid: true, cents: 125000 });

// Test 28: Türkçe noktalı binlik, virgüllü ondalık (1.250,00 -> 125000 kuruş)
assert('parseToCents("1.250,00") Türkçe noktalı binlik virgüllü ondalık',
  parseToCents('1.250,00'),
  { valid: true, cents: 125000 });

// Test 29: Hatalı 2 basamaklı binlik ayırıcı (1,25.00 -> reddedilmeli)
assert('parseToCents("1,25.00") hatalı 2 basamaklı binlik ayırıcı',
  parseToCents('1,25.00'),
  { valid: false, error: 'Geçersiz binlik ayırıcı formatı (Örn: 1,250.00)' });

// Test 30: Ardışık çift virgül (1,,250.00 -> reddedilmeli)
assert('parseToCents("1,,250.00") ardışık çift virgüllü girdi',
  parseToCents('1,,250.00'),
  { valid: false, error: 'Geçersiz binlik ayırıcı formatı (Örn: 1,250.00)' });

// Test 31: Hint sayı sistemi / hatalı basamak gruplama (12,34,567.89 -> reddedilmeli)
assert('parseToCents("12,34,567.89") hatalı basamak gruplama',
  parseToCents('12,34,567.89'),
  { valid: false, error: 'Geçersiz binlik ayırıcı formatı (Örn: 1,250.00)' });

// Test 32: Mixed-case TL soneki (12 Tl -> 1200 kuruş)
assert('parseToCents("12 Tl") mixed-case TL soneki',
  parseToCents('12 Tl'),
  { valid: true, cents: 1200 });

// Test 33: Mixed-case tL soneki (12 tL -> 1200 kuruş)
assert('parseToCents("12 tL") mixed-case tL soneki',
  parseToCents('12 tL'),
  { valid: true, cents: 1200 });

// Test 34: Negatif alt lira varsayılanda ret (-0.50 -> reddedilmeli)
assert('parseToCents("-0.50") varsayılanda ret (allowNegative=false)',
  parseToCents('-0.50'),
  { valid: false, error: 'Negatif değerlere izin verilmez' });

// Test 35: Negatif alt lira izinli modda (-0.50, true -> -50 kuruş)
assert('parseToCents("-0.50", true) izinli negatif alt lira',
  parseToCents('-0.50', true),
  { valid: true, cents: -50 });

// Test 36: Maksimum güvenli tamsayı sınırı (90071992547409.91 -> 9007199254740991 kuruş)
assert('parseToCents("90071992547409.91") MAX_SAFE_INTEGER sınırında tam kuruş',
  parseToCents('90071992547409.91'),
  { valid: true, cents: 9007199254740991 });

// Test 37: Güvenli tamsayı sınırı aşımı (90071992547409.92 -> reddedilmeli)
assert('parseToCents("90071992547409.92") MAX_SAFE_INTEGER sınır aşımı',
  parseToCents('90071992547409.92'),
  { valid: false, error: 'Güvenli kuruş tamsayı sınırı aşıldı' });

function assertPositiveZeroCents(description, result) {
  totalTests++;
  const isOk = result && result.valid === true && Object.is(result.cents, 0) && !Object.is(result.cents, -0);
  if (isOk) {
    passedTests++;
    console.log(`  [PASS] Test #${totalTests}: ${description}`);
  } else {
    failedTests++;
    console.error(`  [FAIL] Test #${totalTests}: ${description}`);
    console.error('         Beklenen: { valid: true, cents: +0 (Object.is === 0) }');
    console.error(`         Alınan:   valid=${result && result.valid}, Object.is(-0)=${result && Object.is(result.cents, -0)}, value=${result && result.cents}`);
  }
}

// Test 38-43: Negatif sıfır (-0 / -0.00) normalizasyon testleri
assert('parseToCents("-0") varsayılanda ret (allowNegative=false)',
  parseToCents('-0'),
  { valid: false, error: 'Negatif değerlere izin verilmez' });

assert('parseToCents("-0.00") varsayılanda ret (allowNegative=false)',
  parseToCents('-0.00'),
  { valid: false, error: 'Negatif değerlere izin verilmez' });

assertPositiveZeroCents('parseToCents("-0", true) +0 döndürmeli (-0 değil, Object.is kontrolü)',
  parseToCents('-0', true));

assertPositiveZeroCents('parseToCents("-0.00", true) +0 döndürmeli (-0 değil, Object.is kontrolü)',
  parseToCents('-0.00', true));

assertPositiveZeroCents('parseToCents("-0,00 TL", true) +0 döndürmeli (-0 değil, Object.is kontrolü)',
  parseToCents('-0,00 TL', true));

assert('formatKurus(-0) ve formatCentsToInput(-0) pozitif sıfır metni döndürmeli',
  { display: formatKurus(-0), input: formatCentsToInput(-0) },
  { display: '0.00 TL', input: '0.00' });

console.log('\n================================================================');
console.log(` TEST RAPORU: Toplam: ${totalTests} | Başarılı: ${passedTests} | Başarısız: ${failedTests}`);
console.log('================================================================');

if (failedTests > 0) {
  process.exit(1);
} else {
  process.exit(0);
}
