import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// NIST P-256 (secp256r1) eliptik eğri noktası.
class ECPoint {
  final BigInt? x;
  final BigInt? y;
  final bool isInfinity;

  ECPoint(BigInt this.x, BigInt this.y) : isInfinity = false;
  ECPoint.infinity()
      : x = null,
        y = null,
        isInfinity = true;

  static final ECPoint infinityPoint = ECPoint.infinity();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ECPoint) return false;
    if (isInfinity && other.isInfinity) return true;
    if (isInfinity != other.isInfinity) return false;
    return x == other.x && y == other.y;
  }

  @override
  int get hashCode => isInfinity ? 0 : Object.hash(x, y);

  @override
  String toString() => isInfinity ? 'ECPoint.infinity' : 'ECPoint($x, $y)';
}

/// S-4: ECDSA P-256 / SHA-256 İmza Doğrulama, Format Normalizasyonu (P1363 <-> DER),
/// Katı ASN.1 DER Ayrıştırma ve Low-S Kanonikalizasyon Motoru.
class EcdsaSignatureValidator {
  // NIST P-256 (secp256r1) Eliptik Eğri Sabitleri
  static final BigInt p = BigInt.parse(
    'FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF',
    radix: 16,
  );

  static final BigInt a = p - BigInt.from(3);

  static final BigInt b = BigInt.parse(
    '5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B',
    radix: 16,
  );

  static final BigInt n = BigInt.parse(
    'FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551',
    radix: 16,
  );

  static final BigInt halfN = (n - BigInt.one) ~/ BigInt.two;

  static final BigInt gx = BigInt.parse(
    '6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296',
    radix: 16,
  );

  static final BigInt gy = BigInt.parse(
    '4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5',
    radix: 16,
  );

  static final ECPoint G = ECPoint(gx, gy);

  static const String domainTag = 'MMS-AUTH-P256-V1';

  // --- Eliptik Eğri Aritmetiği ---

  /// Pozitif modülo işlemi
  static BigInt mod(BigInt v, BigInt m) {
    final r = v % m;
    return r < BigInt.zero ? r + m : r;
  }

  /// İki eğri noktasını toplar (Affine Koordinatlarda)
  static ECPoint addPoints(ECPoint p1, ECPoint p2) {
    if (p1.isInfinity) return p2;
    if (p2.isInfinity) return p1;

    final x1 = p1.x!;
    final y1 = p1.y!;
    final x2 = p2.x!;
    final y2 = p2.y!;

    if (x1 == x2) {
      if (y1 != y2 || y1 == BigInt.zero) {
        return ECPoint.infinityPoint;
      }
      // Nokta ikiye katlama (Doubling): lambda = (3*x1^2 + a) / (2*y1) mod p
      final num = mod(BigInt.from(3) * x1 * x1 + a, p);
      final den = mod(BigInt.two * y1, p);
      final lambda = mod(num * den.modInverse(p), p);

      final x3 = mod(lambda * lambda - BigInt.two * x1, p);
      final y3 = mod(lambda * (x1 - x3) - y1, p);
      return ECPoint(x3, y3);
    } else {
      // Farklı noktaları toplama: lambda = (y2 - y1) / (x2 - x1) mod p
      final num = mod(y2 - y1, p);
      final den = mod(x2 - x1, p);
      final lambda = mod(num * den.modInverse(p), p);

      final x3 = mod(lambda * lambda - x1 - x2, p);
      final y3 = mod(lambda * (x1 - x3) - y1, p);
      return ECPoint(x3, y3);
    }
  }

  /// Skaler çarpım: k * P (Double-and-Add)
  static ECPoint scalarMult(BigInt k, ECPoint point) {
    if (point.isInfinity) return ECPoint.infinityPoint;
    var s = mod(k, n);
    if (s == BigInt.zero) return ECPoint.infinityPoint;

    var result = ECPoint.infinityPoint;
    var addend = point;

    while (s > BigInt.zero) {
      if ((s & BigInt.one) == BigInt.one) {
        result = addPoints(result, addend);
      }
      addend = addPoints(addend, addend);
      s >>= 1;
    }
    return result;
  }

  /// Noktanın P-256 eğrisi üzerinde olup olmadığını denetler: y^2 = x^3 + a*x + b (mod p)
  static bool isOnCurve(ECPoint pt) {
    if (pt.isInfinity) return false;
    final x = pt.x!;
    final y = pt.y!;
    final lhs = mod(y * y, p);
    final rhs = mod(x * x * x + a * x + b, p);
    return lhs == rhs;
  }

  // --- Public Key Ayrıştırma ---

  /// Standart NIST P-256 SPKI DER 26 baytlık ASN.1 başlığı:
  /// SEQUENCE(89) -> SEQUENCE(19) -> OID id-ecPublicKey (1.2.840.10045.2.1) -> OID secp256r1 (1.2.840.10045.3.1.7) -> BIT STRING(66) -> 0x00 unused bits
  static const List<int> p256SpkiHeader = [
    0x30, 0x59, // SEQUENCE
    0x30, 0x13, // SEQUENCE (AlgorithmIdentifier)
    0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, // OID 1.2.840.10045.2.1 (id-ecPublicKey)
    0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, // OID 1.2.840.10045.3.1.7 (secp256r1)
    0x03, 0x42, 0x00, // BIT STRING (66 bayt, 0 unused bit)
  ];

  /// 65 baytlık ham uncompressed noktayı 91 baytlık standart SPKI DER açık anahtarına çevirir.
  static Uint8List toSpki(List<int> uncompressed65Bytes) {
    if (uncompressed65Bytes.length != 65 || uncompressed65Bytes[0] != 0x04) {
      throw FormatException('Geçersiz uncompressed nokta boyutu veya başlığı');
    }
    return Uint8List.fromList([...p256SpkiHeader, ...uncompressed65Bytes]);
  }

  /// SPKI DER veya ANSI X9.62 uncompressed (04 || X || Y) açık anahtarını ayrıştırır.
  static ECPoint parsePublicKey(List<int> bytes) {
    // 1. SPKI DER (Tam 91 bayt ve katı ASN.1 OID başlığı doğrulaması)
    if (bytes.length == 91) {
      if (!_listEquals(bytes.sublist(0, 26), p256SpkiHeader)) {
        throw FormatException(
          'Geçersiz SPKI başlığı veya OID uyuşmazlığı (Beklenen: id-ecPublicKey ve secp256r1 OID)',
        );
      }
      final pubBytes = bytes.sublist(26);
      return _parseUncompressedPoint(pubBytes);
    }
    // 2. Uncompressed Point (65 bayt: 0x04 || X (32) || Y (32))
    if (bytes.length == 65 && bytes[0] == 0x04) {
      return _parseUncompressedPoint(bytes);
    }
    // 3. Geçersiz format
    throw FormatException(
      'Geçersiz P-256 açık anahtar formatı (Beklenen: 91 bayt SPKI DER veya 65 bayt uncompressed, Alınan: ${bytes.length} bayt)',
    );
  }

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static ECPoint _parseUncompressedPoint(List<int> bytes) {
    if (bytes.length != 65 || bytes[0] != 0x04) {
      throw FormatException('Geçersiz uncompressed point başlığı');
    }
    final xBytes = bytes.sublist(1, 33);
    final yBytes = bytes.sublist(33, 65);

    final x = _bytesToBigInt(xBytes);
    final y = _bytesToBigInt(yBytes);

    final pt = ECPoint(x, y);
    if (!isOnCurve(pt)) {
      throw FormatException('Açık anahtar koordinatları P-256 eğrisi üzerinde değildir');
    }
    return pt;
  }

  /// Açık anahtarın SHA-256 parmak izini iki nokta ayraçlı hex string olarak hesaplar.
  static String computePublicKeyFingerprint(List<int> publicKeyBytes) {
    final digest = sha256.convert(publicKeyBytes).bytes;
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
  }

  // --- Deterministik İkili Çerçeveleme (Length-Prefixed Framing) ---

  /// 6 alanlı Poll Kanonik Çerçevesi oluşturur.
  static Uint8List buildCanonicalPollPayload({
    required String protocolVersion,
    required String pairingSessionId,
    required List<int> publicKeyFingerprintBytes,
    required String challengeId,
    required List<int> challengeNonce,
  }) {
    return _buildBinaryFraming(
      operationType: 'POLL',
      protocolVersion: protocolVersion,
      pairingSessionId: pairingSessionId,
      publicKeyFingerprintBytes: publicKeyFingerprintBytes,
      challengeId: challengeId,
      challengeNonce: challengeNonce,
      tokenHashBytes: null,
    );
  }

  /// 7 alanlı Token-Bound ACK Kanonik Çerçevesi oluşturur.
  static Uint8List buildCanonicalAckPayload({
    required String protocolVersion,
    required String pairingSessionId,
    required List<int> publicKeyFingerprintBytes,
    required String challengeId,
    required List<int> challengeNonce,
    required List<int> tokenHashBytes,
  }) {
    if (tokenHashBytes.length != 32) {
      throw ArgumentError('tokenHashBytes tam 32 bayt olmalıdır');
    }
    return _buildBinaryFraming(
      operationType: 'ACK',
      protocolVersion: protocolVersion,
      pairingSessionId: pairingSessionId,
      publicKeyFingerprintBytes: publicKeyFingerprintBytes,
      challengeId: challengeId,
      challengeNonce: challengeNonce,
      tokenHashBytes: tokenHashBytes,
    );
  }

  static Uint8List _buildBinaryFraming({
    required String operationType,
    required String protocolVersion,
    required String pairingSessionId,
    required List<int> publicKeyFingerprintBytes,
    required String challengeId,
    required List<int> challengeNonce,
    required List<int>? tokenHashBytes,
  }) {
    final bb = BytesBuilder();

    // Domain Tag (16 bayt ASCII sabit)
    bb.add(utf8.encode(domainTag));

    // Field 1: ProtocolVersion
    _addField(bb, utf8.encode(protocolVersion));

    // Field 2: PairingSessionId
    _addField(bb, utf8.encode(pairingSessionId));

    // Field 3: PublicKeyFingerprint (32 bayt ham)
    _addField(bb, publicKeyFingerprintBytes);

    // Field 4: OperationType ("POLL" veya "ACK")
    _addField(bb, utf8.encode(operationType));

    // Field 5: ChallengeId
    _addField(bb, utf8.encode(challengeId));

    // Field 6: ChallengeNonce (32 bayt ham)
    _addField(bb, challengeNonce);

    // Field 7 (Opsiyonel / Yalnızca ACK): token_sha256 (32 bayt ham)
    if (tokenHashBytes != null) {
      _addField(bb, tokenHashBytes);
    }

    return bb.toBytes();
  }

  static void _addField(BytesBuilder bb, List<int> data) {
    if (data.length > 65535) {
      throw ArgumentError('Alan boyutu 65535 baytı aşamaz');
    }
    // 2-byte Big-Endian uint16
    bb.addByte((data.length >> 8) & 0xFF);
    bb.addByte(data.length & 0xFF);
    bb.add(data);
  }

  // --- Katı (Strict) ASN.1 DER Ayrıştırma ve Format Dönüşümleri ---

  /// ASN.1 DER formatındaki imzayı (r, s) olarak ayrıştırır ve katı kuralları denetler.
  static (BigInt, BigInt) parseStrictDer(List<int> der) {
    if (der.length < 8 || der.length > 72) {
      throw FormatException('Geçersiz DER imza boyutu: ${der.length}');
    }

    // 1. SEQUENCE başlığı
    if (der[0] != 0x30) {
      throw FormatException('DER imza 0x30 (SEQUENCE) ile başlamalıdır');
    }

    final seqLen = der[1];
    if (der.length != seqLen + 2) {
      throw FormatException(
        'Sonda artık bayt (trailing bytes) tespit edildi! (Beklenen: ${seqLen + 2}, Alınan: ${der.length})',
      );
    }

    var offset = 2;

    // 2. INTEGER r
    if (offset >= der.length || der[offset] != 0x02) {
      throw FormatException('r bileşeni 0x02 INTEGER ile başlamalıdır');
    }
    offset++;
    final rLen = der[offset++];
    if (rLen == 0 || rLen > 33 || offset + rLen > der.length) {
      throw FormatException('Geçersiz r uzunluğu: $rLen');
    }
    final rBytes = der.sublist(offset, offset + rLen);
    offset += rLen;

    _validateDerInteger(rBytes, 'r');
    final r = _bytesToBigInt(rBytes);

    // 3. INTEGER s
    if (offset >= der.length || der[offset] != 0x02) {
      throw FormatException('s bileşeni 0x02 INTEGER ile başlamalıdır');
    }
    offset++;
    final sLen = der[offset++];
    if (sLen == 0 || sLen > 33 || offset + sLen != der.length) {
      throw FormatException('Geçersiz s uzunluğu veya dizi sonu uyuşmazlığı');
    }
    final sBytes = der.sublist(offset, offset + sLen);

    _validateDerInteger(sBytes, 's');
    final s = _bytesToBigInt(sBytes);

    // 4. Aralık Denetimi: 1 <= r, s < n
    if (r < BigInt.one || r >= n) {
      throw FormatException('r mertebe sınırları dışındadır (1 <= r < n ihlali)');
    }
    if (s < BigInt.one || s >= n) {
      throw FormatException('s mertebe sınırları dışındadır (1 <= s < n ihlali)');
    }

    // 5. Low-S Kanonikalizasyonu Denetimi: s <= (n - 1) / 2
    if (s > halfN) {
      throw FormatException(
        'High-S tespit edildi! İmza kanonik değildir (Signature Malleability koruması: s <= (n-1)/2 ihlali)',
      );
    }

    return (r, s);
  }

  static void _validateDerInteger(List<int> bytes, String name) {
    if (bytes.isEmpty) {
      throw FormatException('$name tamsayısı boş olamaz');
    }
    // Negatif sayı denetimi (en yüksek bit 1 ve 0x00 öneki yoksa negatif sayılır)
    if ((bytes[0] & 0x80) != 0) {
      throw FormatException('$name negatif bir tamsayı olarak kodlanamaz');
    }
    // Gereksiz 0x00 önekleri denetimi
    if (bytes.length > 1 && bytes[0] == 0x00) {
      // Eğer ikinci baytın en yüksek biti 0 ise, baştaki 0x00 gereksizdir!
      if ((bytes[1] & 0x80) == 0) {
        throw FormatException('$name bileşeninde gereksiz 0x00 öneki (redundant zero) bulundu');
      }
    }
  }

  /// IEEE P1363 (64 bayt: 32 bayt r || 32 bayt s) formatını standart Low-S ASN.1 DER formatına dönüştürür.
  static Uint8List p1363ToDer(List<int> p1363Bytes, {bool normalizeHighS = false}) {
    if (p1363Bytes.length != 64) {
      throw FormatException('P1363 formatı tam 64 bayt olmalıdır (Alınan: ${p1363Bytes.length})');
    }

    final rBytes = p1363Bytes.sublist(0, 32);
    final sBytes = p1363Bytes.sublist(32, 64);

    final r = _bytesToBigInt(rBytes);
    var s = _bytesToBigInt(sBytes);

    if (r < BigInt.one || r >= n || s < BigInt.one || s >= n) {
      throw FormatException('İmza bileşenleri P-256 eğri mertebesi dışındadır');
    }

    // High-S normalizasyonu
    if (s > halfN) {
      if (normalizeHighS) {
        s = n - s;
      } else {
        throw FormatException('High-S tespit edildi ve normalizeHighS=false');
      }
    }

    final rDer = _encodeDerInteger(r);
    final sDer = _encodeDerInteger(s);
    final totalLen = rDer.length + sDer.length;

    return Uint8List.fromList([0x30, totalLen, ...rDer, ...sDer]);
  }

  /// ASN.1 DER imzasını 64 baytlık IEEE P1363 (r || s) formatına dönüştürür.
  static Uint8List derToP1363(List<int> derBytes) {
    final (r, s) = parseStrictDer(derBytes);
    final rBytes = _bigIntToBytes(r, 32);
    final sBytes = _bigIntToBytes(s, 32);

    return Uint8List.fromList([...rBytes, ...sBytes]);
  }

  static List<int> _encodeDerInteger(BigInt value) {
    var raw = _bigIntToMinimalBytes(value);
    if ((raw[0] & 0x80) != 0) {
      raw = [0x00, ...raw];
    }
    return [0x02, raw.length, ...raw];
  }

  // --- İmza Doğrulama (Tekil SHA-256 Hashing) ---

  /// Kanonik ikili çerçeve ve açık anahtar üzerinden ECDSA P-256 imzasını doğrular.
  /// Kural: canonicalPayload kesinlikle yalnızca BİR KEZ SHA-256 ile özetlenir (asla double hashing yapılmaz).
  static bool verifySignature({
    required List<int> publicKeyBytes,
    required List<int> canonicalPayload,
    required List<int> signatureBytes,
  }) {
    try {
      final pubKey = parsePublicKey(publicKeyBytes);

      // İmzayı DER olarak ayrıştır (Eğer 64 bayt ise önce P1363'ten DER'e çevir)
      List<int> derBytes;
      if (signatureBytes.length == 64 && signatureBytes[0] != 0x30) {
        derBytes = p1363ToDer(signatureBytes, normalizeHighS: false);
      } else {
        derBytes = signatureBytes;
      }

      final (r, s) = parseStrictDer(derBytes);

      // Tekil SHA-256 Hashing
      final digestBytes = sha256.convert(canonicalPayload).bytes;
      final e = _bytesToBigInt(digestBytes);

      // w = s^-1 mod n
      final w = s.modInverse(n);

      // u1 = e * w mod n
      final u1 = mod(e * w, n);

      // u2 = r * w mod n
      final u2 = mod(r * w, n);

      // P = u1*G + u2*Q
      final p1 = scalarMult(u1, G);
      final p2 = scalarMult(u2, pubKey);
      final pt = addPoints(p1, p2);

      if (pt.isInfinity) return false;

      // r == pt.x mod n
      final v = mod(pt.x!, n);
      return v == r;
    } catch (_) {
      return false;
    }
  }

  // --- İstemci / Test Amaçlı İmzalama Yardımcısı ---

  /// Test senaryolarında deterministik/standart kanonik Low-S imza üretir.
  static Uint8List signPayload({
    required BigInt privateKey,
    required List<int> canonicalPayload,
    bool forceHighS = false,
  }) {
    if (privateKey < BigInt.one || privateKey >= n) {
      throw ArgumentError('Geçersiz private key');
    }

    final digestBytes = sha256.convert(canonicalPayload).bytes;
    final e = _bytesToBigInt(digestBytes);

    final rng = Random.secure();
    BigInt k;
    BigInt r = BigInt.zero;
    BigInt s = BigInt.zero;

    do {
      do {
        final kBytes = List<int>.generate(32, (_) => rng.nextInt(256));
        k = _bytesToBigInt(kBytes);
      } while (k < BigInt.one || k >= n);

      final p1 = scalarMult(k, G);
      if (p1.isInfinity) continue;
      r = mod(p1.x!, n);
      if (r == BigInt.zero) continue;

      final kInv = k.modInverse(n);
      s = mod(kInv * (e + r * privateKey), n);
    } while (r == BigInt.zero || s == BigInt.zero);

    // Low-S Kuralı
    if (s > halfN && !forceHighS) {
      s = n - s;
    } else if (s <= halfN && forceHighS) {
      s = n - s;
    }

    final rDer = _encodeDerInteger(r);
    final sDer = _encodeDerInteger(s);
    final totalLen = rDer.length + sDer.length;

    return Uint8List.fromList([0x30, totalLen, ...rDer, ...sDer]);
  }

  /// Private key'den açık anahtar (uncompressed 65 bayt: 04 || X || Y) türetir.
  static Uint8List getPublicKeyBytes(BigInt privateKey) {
    final pt = scalarMult(privateKey, G);
    final xBytes = _bigIntToBytes(pt.x!, 32);
    final yBytes = _bigIntToBytes(pt.y!, 32);
    return Uint8List.fromList([0x04, ...xBytes, ...yBytes]);
  }

  // --- Yardımcı Sayısal Fonksiyonlar ---

  static BigInt _bytesToBigInt(List<int> bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  static List<int> _bigIntToBytes(BigInt val, int length) {
    final res = List<int>.filled(length, 0);
    var curr = val;
    for (var i = length - 1; i >= 0; i--) {
      res[i] = (curr & BigInt.from(0xFF)).toInt();
      curr >>= 8;
    }
    return res;
  }

  static List<int> _bigIntToMinimalBytes(BigInt val) {
    if (val == BigInt.zero) return [0];
    final bytes = <int>[];
    var curr = val;
    while (curr > BigInt.zero) {
      bytes.add((curr & BigInt.from(0xFF)).toInt());
      curr >>= 8;
    }
    return bytes.reversed.toList();
  }
}
