import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// NIST P-256 (secp256r1) Elips Noktası.
class ClientEcPoint {
  final BigInt? x;
  final BigInt? y;
  final bool isInfinity;

  const ClientEcPoint(BigInt this.x, BigInt this.y) : isInfinity = false;

  const ClientEcPoint.infinity()
      : x = null,
        y = null,
        isInfinity = true;

  static const ClientEcPoint infinityPoint = ClientEcPoint.infinity();
}

/// S-4 İstemci Tarafı ECDSA P-256 / SHA-256 Anahtar Çifti ve Low-S İmza Üreticisi.
///
/// Hub backend (`EcdsaSignatureValidator`) ile %100 byte-uyumlu:
/// - 91 baytlık SPKI DER açık anahtar kodlaması
/// - 6 alanlı POLL / 7 alanlı Token-Bound ACK uzunluk önekli ikili çerçeve
/// - Tekil SHA-256 özetleme + Low-S (`s <= (n-1)/2`) katı ASN.1 DER imza
class ClientEcdsaP256KeyPair {
  static final BigInt _p = BigInt.parse(
    'FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF',
    radix: 16,
  );
  static final BigInt _a = _p - BigInt.from(3);
  static final BigInt _b = BigInt.parse(
    '5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B',
    radix: 16,
  );
  static final BigInt _n = BigInt.parse(
    'FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551',
    radix: 16,
  );
  static final BigInt _halfN = (_n - BigInt.one) ~/ BigInt.two;
  static final BigInt _gx = BigInt.parse(
    '6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296',
    radix: 16,
  );
  static final BigInt _gy = BigInt.parse(
    '4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5',
    radix: 16,
  );
  static final ClientEcPoint _g = ClientEcPoint(_gx, _gy);

  static const String domainTag = 'MMS-AUTH-P256-V1';
  static const List<int> _spkiHeader = <int>[
    0x30, 0x59,
    0x30, 0x13,
    0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
    0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07,
    0x03, 0x42, 0x00,
  ];

  final BigInt privateKey;
  final Uint8List publicKeySpkiBytes;

  ClientEcdsaP256KeyPair._({
    required this.privateKey,
    required this.publicKeySpkiBytes,
  });

  factory ClientEcdsaP256KeyPair.generate([Random? random]) {
    final rng = random ?? Random.secure();
    BigInt d;
    do {
      final raw = List<int>.generate(32, (_) => rng.nextInt(256));
      d = _bytesToBigInt(raw);
    } while (d < BigInt.one || d >= _n);
    return ClientEcdsaP256KeyPair.fromPrivateKey(d);
  }

  factory ClientEcdsaP256KeyPair.fromPrivateKey(BigInt d) {
    if (d < BigInt.one || d >= _n) {
      throw ArgumentError('Geçersiz ECDSA P-256 özel anahtarı.');
    }
    final pt = _scalarMult(d, _g);
    if (pt.isInfinity || !_isOnCurve(pt)) {
      throw StateError('Açık anahtar noktası P-256 eğrisi üzerinde değil.');
    }
    final uncompressed = Uint8List.fromList(<int>[
      0x04,
      ..._bigIntToBytes(pt.x!, 32),
      ..._bigIntToBytes(pt.y!, 32),
    ]);
    final spki = Uint8List.fromList(<int>[..._spkiHeader, ...uncompressed]);
    return ClientEcdsaP256KeyPair._(
      privateKey: d,
      publicKeySpkiBytes: spki,
    );
  }

  factory ClientEcdsaP256KeyPair.fromPrivateKeyHex(String hex) {
    final clean = hex.trim();
    return ClientEcdsaP256KeyPair.fromPrivateKey(BigInt.parse(clean, radix: 16));
  }

  String toPrivateKeyHex() => privateKey.toRadixString(16).padLeft(64, '0');

  String get publicKeySpkiBase64 => base64Encode(publicKeySpkiBytes);

  Uint8List get publicKeyFingerprintBytes =>
      Uint8List.fromList(sha256.convert(publicKeySpkiBytes).bytes);

  String get publicKeyFingerprintHex => publicKeyFingerprintBytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(':');

  Uint8List buildPollPayload({
    required String sessionId,
    required String challengeId,
    required List<int> challengeNonce,
    String protocolVersion = '1',
  }) {
    return _buildFraming(
      operationType: 'POLL',
      protocolVersion: protocolVersion,
      sessionId: sessionId,
      challengeId: challengeId,
      challengeNonce: challengeNonce,
      tokenHashBytes: null,
    );
  }

  Uint8List buildAckPayload({
    required String sessionId,
    required String challengeId,
    required List<int> challengeNonce,
    required String rawToken,
    String protocolVersion = '1',
  }) {
    final tokenHash = sha256.convert(utf8.encode(rawToken)).bytes;
    return _buildFraming(
      operationType: 'ACK',
      protocolVersion: protocolVersion,
      sessionId: sessionId,
      challengeId: challengeId,
      challengeNonce: challengeNonce,
      tokenHashBytes: tokenHash,
    );
  }

  Uint8List signCanonicalPayload(List<int> canonicalPayload, [Random? random]) {
    final digest = sha256.convert(canonicalPayload).bytes;
    final e = _bytesToBigInt(digest);
    final rng = random ?? Random.secure();

    BigInt r = BigInt.zero;
    BigInt s = BigInt.zero;
    do {
      BigInt k;
      do {
        final kBytes = List<int>.generate(32, (_) => rng.nextInt(256));
        k = _bytesToBigInt(kBytes);
      } while (k < BigInt.one || k >= _n);

      final pt = _scalarMult(k, _g);
      if (pt.isInfinity) continue;
      r = _mod(pt.x!, _n);
      if (r == BigInt.zero) continue;

      final kInv = k.modInverse(_n);
      s = _mod(kInv * (e + r * privateKey), _n);
    } while (r == BigInt.zero || s == BigInt.zero);

    if (s > _halfN) {
      s = _n - s;
    }

    final rDer = _encodeDerInteger(r);
    final sDer = _encodeDerInteger(s);
    return Uint8List.fromList(<int>[
      0x30,
      rDer.length + sDer.length,
      ...rDer,
      ...sDer,
    ]);
  }

  Uint8List _buildFraming({
    required String operationType,
    required String protocolVersion,
    required String sessionId,
    required String challengeId,
    required List<int> challengeNonce,
    required List<int>? tokenHashBytes,
  }) {
    final bb = BytesBuilder();
    bb.add(utf8.encode(domainTag));
    _addField(bb, utf8.encode(protocolVersion));
    _addField(bb, utf8.encode(sessionId));
    _addField(bb, publicKeyFingerprintBytes);
    _addField(bb, utf8.encode(operationType));
    _addField(bb, utf8.encode(challengeId));
    _addField(bb, challengeNonce);
    if (tokenHashBytes != null) {
      _addField(bb, tokenHashBytes);
    }
    return bb.toBytes();
  }

  static void _addField(BytesBuilder bb, List<int> data) {
    bb.addByte((data.length >> 8) & 0xFF);
    bb.addByte(data.length & 0xFF);
    bb.add(data);
  }

  static BigInt _mod(BigInt v, BigInt m) {
    final r = v % m;
    return r < BigInt.zero ? r + m : r;
  }

  static bool _isOnCurve(ClientEcPoint pt) {
    if (pt.isInfinity) return false;
    final x = pt.x!;
    final y = pt.y!;
    return _mod(y * y, _p) == _mod(x * x * x + _a * x + _b, _p);
  }

  static ClientEcPoint _addPoints(ClientEcPoint p1, ClientEcPoint p2) {
    if (p1.isInfinity) return p2;
    if (p2.isInfinity) return p1;

    final x1 = p1.x!;
    final y1 = p1.y!;
    final x2 = p2.x!;
    final y2 = p2.y!;

    if (x1 == x2) {
      if (y1 != y2 || y1 == BigInt.zero) {
        return ClientEcPoint.infinityPoint;
      }
      final num = _mod(BigInt.from(3) * x1 * x1 + _a, _p);
      final den = _mod(BigInt.two * y1, _p);
      final lambda = _mod(num * den.modInverse(_p), _p);
      final x3 = _mod(lambda * lambda - BigInt.two * x1, _p);
      final y3 = _mod(lambda * (x1 - x3) - y1, _p);
      return ClientEcPoint(x3, y3);
    }

    final num = _mod(y2 - y1, _p);
    final den = _mod(x2 - x1, _p);
    final lambda = _mod(num * den.modInverse(_p), _p);
    final x3 = _mod(lambda * lambda - x1 - x2, _p);
    final y3 = _mod(lambda * (x1 - x3) - y1, _p);
    return ClientEcPoint(x3, y3);
  }

  static ClientEcPoint _scalarMult(BigInt k, ClientEcPoint point) {
    if (point.isInfinity) return ClientEcPoint.infinityPoint;
    var s = _mod(k, _n);
    if (s == BigInt.zero) return ClientEcPoint.infinityPoint;

    var result = ClientEcPoint.infinityPoint;
    var addend = point;
    while (s > BigInt.zero) {
      if ((s & BigInt.one) == BigInt.one) {
        result = _addPoints(result, addend);
      }
      addend = _addPoints(addend, addend);
      s >>= 1;
    }
    return result;
  }

  static List<int> _encodeDerInteger(BigInt value) {
    var raw = _bigIntToMinimalBytes(value);
    if ((raw[0] & 0x80) != 0) {
      raw = <int>[0x00, ...raw];
    }
    return <int>[0x02, raw.length, ...raw];
  }

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
    if (val == BigInt.zero) return <int>[0];
    final bytes = <int>[];
    var curr = val;
    while (curr > BigInt.zero) {
      bytes.add((curr & BigInt.from(0xFF)).toInt());
      curr >>= 8;
    }
    return bytes.reversed.toList();
  }
}
