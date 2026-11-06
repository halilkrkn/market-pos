import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:spike_01_backend/security/ecdsa_signature_validator.dart';
import 'package:spike_01_backend/security/windows_cng.dart';
import 'package:test/test.dart';

void main() {
  group('S4-1: Kriptografik Altyapı ve İmza Doğrulama Testleri', () {
    late BigInt testPrivateKey;
    late Uint8List testPublicKey;
    late Uint8List canonicalPollPayload;
    late Uint8List canonicalAckPayload;

    setUpAll(() {
      // Bilinen test anahtarı (1..n arası rastgele geçerli skaler)
      testPrivateKey = BigInt.parse(
        'E28639527D60D6BFA09B424D04C2216518DF62C690E8F95F3AF194B15783A16A',
        radix: 16,
      );
      testPublicKey = EcdsaSignatureValidator.getPublicKeyBytes(testPrivateKey);
      final testFingerprint = EcdsaSignatureValidator.computePublicKeyFingerprint(testPublicKey);
      expect(testFingerprint, isNotEmpty);

      final nonce = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final tokenBytes = utf8.encode('mms_dt_test_token_sample_1234567890');
      final tokenHash = Uint8List.fromList(sha256.convert(tokenBytes).bytes);

      canonicalPollPayload = EcdsaSignatureValidator.buildCanonicalPollPayload(
        protocolVersion: '1',
        pairingSessionId: 'sess_test123',
        publicKeyFingerprintBytes: sha256.convert(testPublicKey).bytes,
        challengeId: 'ch_poll_001',
        challengeNonce: nonce,
      );

      canonicalAckPayload = EcdsaSignatureValidator.buildCanonicalAckPayload(
        protocolVersion: '1',
        pairingSessionId: 'sess_test123',
        publicKeyFingerprintBytes: sha256.convert(testPublicKey).bytes,
        challengeId: 'ch_ack_001',
        challengeNonce: nonce,
        tokenHashBytes: tokenHash,
      );
    });

    test('1. Deterministik İkili Çerçeveleme (Length-Prefixed Framing): Alan sınırları ve Domain Tag', () {
      // Domain tag kontrolü (ilk 16 bayt)
      final domainTagBytes = canonicalPollPayload.sublist(0, 16);
      expect(utf8.decode(domainTagBytes), equals('MMS-AUTH-P256-V1'));

      // Poll 6 alan içermeli
      expect(canonicalPollPayload.length, greaterThan(16 + 2 * 6));

      // ACK 7 alan içermeli ve son 32 bayt token_sha256 olmalı
      final ackLen = canonicalAckPayload.length;
      final ackTokenHashField = canonicalAckPayload.sublist(ackLen - 32, ackLen);
      final expectedTokenHash = sha256.convert(utf8.encode('mms_dt_test_token_sample_1234567890')).bytes;
      expect(ackTokenHashField, equals(expectedTokenHash));
    });

    test('2. Standart DER İmza Doğrulaması (Android / iOS Çıktısı Simülasyonu)', () {
      final sigDer = EcdsaSignatureValidator.signPayload(
        privateKey: testPrivateKey,
        canonicalPayload: canonicalPollPayload,
        forceHighS: false,
      );

      // DER formatı denetimi (0x30 ile başlamalı, boyutu 70-72 bayt)
      expect(sigDer[0], equals(0x30));
      expect(sigDer.length, inInclusiveRange(68, 72));

      final isValid = EcdsaSignatureValidator.verifySignature(
        publicKeyBytes: testPublicKey,
        canonicalPayload: canonicalPollPayload,
        signatureBytes: sigDer,
      );
      expect(isValid, isTrue);
    });

    test('3. Signature Malleability Koruması: High-S İmzasının Kesin Olarak Reddedilmesi', () {
      // Kasıtlı olarak High-S (s > (n-1)/2) üret
      final highSigDer = EcdsaSignatureValidator.signPayload(
        privateKey: testPrivateKey,
        canonicalPayload: canonicalPollPayload,
        forceHighS: true,
      );

      // Backend High-S imzayı reddetmeli (verify false dönmeli)
      final isValid = EcdsaSignatureValidator.verifySignature(
        publicKeyBytes: testPublicKey,
        canonicalPayload: canonicalPollPayload,
        signatureBytes: highSigDer,
      );
      expect(isValid, isFalse, reason: 'High-S imzası Low-S kanonikalizasyonu kuralı gereği reddedilmelidir.');
    });

    test('4. Katı (Strict) ASN.1 DER Ayrıştırma: Artık baytlar ve geçersiz sıfır önekleri reddedilmeli', () {
      final validSig = EcdsaSignatureValidator.signPayload(
        privateKey: testPrivateKey,
        canonicalPayload: canonicalPollPayload,
      );

      // Sona çöp bayt ekle (Trailing bytes)
      final tamperedSig = Uint8List.fromList([...validSig, 0xAA, 0xBB]);

      final isValid = EcdsaSignatureValidator.verifySignature(
        publicKeyBytes: testPublicKey,
        canonicalPayload: canonicalPollPayload,
        signatureBytes: tamperedSig,
      );
      expect(isValid, isFalse, reason: 'Sonda artık bayt bulunan imza katı DER ayrıştırmasında reddedilmelidir.');
    });

    test('5. P1363 (64 bayt) <-> ASN.1 DER Çift Yönlü Dönüşüm ve Doğrulama', () {
      final validDer = EcdsaSignatureValidator.signPayload(
        privateKey: testPrivateKey,
        canonicalPayload: canonicalPollPayload,
      );

      // DER -> P1363
      final p1363 = EcdsaSignatureValidator.derToP1363(validDer);
      expect(p1363.length, equals(64));

      // P1363 -> DER
      final recoveredDer = EcdsaSignatureValidator.p1363ToDer(p1363);
      expect(recoveredDer, equals(validDer));

      // 64-byte P1363 doğrudan verifySignature fonksiyonuna verildiğinde de doğrulanmalı
      final isValid = EcdsaSignatureValidator.verifySignature(
        publicKeyBytes: testPublicKey,
        canonicalPayload: canonicalPollPayload,
        signatureBytes: p1363,
      );
      expect(isValid, isTrue);
    });

    test('6. Gerçek Windows CNG (KSP) İmza Formatı ve Kabul Kriteri Doğrulaması', () {
      if (!Platform.isWindows) {
        print('[SKIP] Windows dışı platformda Windows CNG testi atlandı.');
        return;
      }

      final cngResult = WindowsCngSigner.testCngSigning(
        canonicalPayload: canonicalAckPayload,
        tryTpmFirst: true,
      );

      print('================ WINDOWS CNG DOĞRULAMA RAPORU ================');
      print('Sağlayıcı: ${cngResult.providerName}');
      print('Donanımsal TPM mi: ${cngResult.isHardwareTpm}');
      print('Ham İmza Boyutu: ${cngResult.rawSignatureLength} bayt');
      print('Hata Mesajı: ${cngResult.errorMessage ?? "Yok"}');
      print('===============================================================');

      expect(cngResult.isSuccess, isTrue, reason: 'Windows CNG anahtar üretimi ve imzalama başarılı olmalıdır');
      
      // KABUL KRİTERİ: Windows NCryptSignHash çıktısı tam 64 bayt (IEEE P1363) olmalıdır
      expect(cngResult.rawSignatureLength, equals(64), reason: 'Windows CNG çıktısı 64 bayt IEEE P1363 (r || s) olmalıdır');

      // Canonical DER formatına dönüştürülebilmeli ve backend tarafından doğrulanabilmeli
      expect(cngResult.canonicalDerSignature.length, inInclusiveRange(68, 72));

      final isValid = EcdsaSignatureValidator.verifySignature(
        publicKeyBytes: cngResult.publicKeyBytes,
        canonicalPayload: canonicalAckPayload,
        signatureBytes: cngResult.canonicalDerSignature,
      );
      expect(isValid, isTrue, reason: 'Windows CNG ile üretilen imza backend EcdsaSignatureValidator ile doğrulanmalıdır');
    });

    test('7. Double Hashing Olmadığının Kanıtlanması (Tekil SHA-256 Doğrulaması)', () {
      // Kanonik payload üzerinde imza üret
      final sig = EcdsaSignatureValidator.signPayload(
        privateKey: testPrivateKey,
        canonicalPayload: canonicalPollPayload,
      );

      // 1. Doğru doğrulama (Tekil SHA-256): geçerli
      final ok = EcdsaSignatureValidator.verifySignature(
        publicKeyBytes: testPublicKey,
        canonicalPayload: canonicalPollPayload,
        signatureBytes: sig,
      );
      expect(ok, isTrue);

      // 2. Çifte hashlenmiş payload ile doğrulama (payload yerine hash'i verilirse): geçersiz olmalı
      final doubleHashedPayload = Uint8List.fromList(sha256.convert(canonicalPollPayload).bytes);
      final fail = EcdsaSignatureValidator.verifySignature(
        publicKeyBytes: testPublicKey,
        canonicalPayload: doubleHashedPayload,
        signatureBytes: sig,
      );
      expect(fail, isFalse, reason: 'Çifte hash uygulandığında imza doğrulaması kesinlikle başarısız olmalıdır');
    });

    test('8. SPKI Başlık Doğrulaması (id-ecPublicKey, secp256r1 OID ve Biçimsel Katılık - FINDING-6)', () {
      // 1. Geçerli 91 bayt P-256 SPKI DER üretimi ve kabulü
      final validSpki = EcdsaSignatureValidator.toSpki(testPublicKey);
      expect(validSpki.length, equals(91));
      final parsedPt = EcdsaSignatureValidator.parsePublicKey(validSpki);
      expect(parsedPt.isInfinity, isFalse);
      expect(EcdsaSignatureValidator.isOnCurve(parsedPt), isTrue);

      // 2. Yanlış OID (secp256r1 OID değiştirilmiş) reddedilmeli
      final wrongOidSpki = Uint8List.fromList(validSpki);
      wrongOidSpki[19] = 0x08; // 1.2.840.10045.3.1.7 -> 1.2.840.10045.3.1.8
      expect(
        () => EcdsaSignatureValidator.parsePublicKey(wrongOidSpki),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Geçersiz SPKI başlığı veya OID uyuşmazlığı'),
        )),
      );

      // 3. Bozuk ASN.1 uzunluğu veya SEQUENCE başlığı reddedilmeli
      final malformedSeqSpki = Uint8List.fromList(validSpki);
      malformedSeqSpki[0] = 0x31; // SET yerine SEQUENCE
      expect(
        () => EcdsaSignatureValidator.parsePublicKey(malformedSeqSpki),
        throwsA(isA<FormatException>()),
      );

      // 4. Fazladan bayt içeren SPKI (92 bayt) reddedilmeli
      final trailingSpki = Uint8List.fromList([...validSpki, 0x00]);
      expect(
        () => EcdsaSignatureValidator.parsePublicKey(trailingSpki),
        throwsA(isA<FormatException>()),
      );

      // 5. Eğri üzerinde olmayan geçersiz koordinat içeren SPKI reddedilmeli
      final invalidCurveSpki = Uint8List.fromList(validSpki);
      invalidCurveSpki[90] ^= 0xFF; // Y koordinatını boz
      expect(
        () => EcdsaSignatureValidator.parsePublicKey(invalidCurveSpki),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('eğrisi üzerinde değildir'),
        )),
      );
    });
  });
}
