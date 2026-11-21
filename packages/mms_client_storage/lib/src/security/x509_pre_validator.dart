import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Katman 1 ve Katman 2 X.509 sertifika ön-doğrulama hatası (fail-closed).
class X509ValidationException implements Exception {
  final String code;
  final String message;

  const X509ValidationException(this.code, this.message);

  @override
  String toString() => 'X509ValidationException($code): $message';
}

/// Kanonik tek-sertifika DER ayrıştırma sonucu.
class CanonicalCertDerResult {
  final Uint8List derBytes;
  final String sha256Hex;
  final bool wasPem;

  const CanonicalCertDerResult({
    required this.derBytes,
    required this.sha256Hex,
    required this.wasPem,
  });

  /// BoringSSL / Dart `SecurityContext.setTrustedCertificatesBytes` için kanonik PEM çıktısı.
  String toPem() => encodeDerCertificateAsPem(derBytes);

  Uint8List toPemBytes() => Uint8List.fromList(ascii.encode(toPem()));
}

class _DerTlv {
  final int tag;
  final int startOffset;
  final int contentOffset;
  final int contentLength;
  final int totalLength;

  const _DerTlv({
    required this.tag,
    required this.startOffset,
    required this.contentOffset,
    required this.contentLength,
    required this.totalLength,
  });

  int get endOffset => startOffset + totalLength;

  Uint8List sliceBytes(Uint8List source) =>
      Uint8List.sublistView(source, startOffset, endOffset);

  Uint8List contentBytes(Uint8List source) =>
      Uint8List.sublistView(source, contentOffset, contentOffset + contentLength);
}

class _DerReader {
  static const int maxAllowedDepth = 8;

  final Uint8List bytes;
  int offset;
  final int endOffset;
  final int depth;

  _DerReader(this.bytes, {this.offset = 0, int? endOffset, this.depth = 0})
      : endOffset = endOffset ?? bytes.length {
    if (depth > maxAllowedDepth) {
      throw const X509ValidationException(
        'INVALID_CA_CERT',
        'ASN.1/DER sertifika derinliği güvenli sınırı (8) aşıyor.',
      );
    }
  }

  bool get hasNext => offset < endOffset;

  _DerTlv nextTlv({String invalidCode = 'INVALID_CA_CERT'}) {
    if (offset >= endOffset) {
      throw X509ValidationException(invalidCode, 'Beklenmeyen ASN.1 DER veri sonu.');
    }
    final start = offset;
    final tag = bytes[offset++];
    // Yüksek tag numarası (0x1F) X.509 çekirdek yapılarında beklenmez; uzunluğu kontrolsüz taşmaları önle.
    if ((tag & 0x1F) == 0x1F || tag == 0x00) {
      throw X509ValidationException(invalidCode, 'Geçersiz ASN.1 DER etiketi: 0x${tag.toRadixString(16)}.');
    }
    if (offset >= endOffset) {
      throw X509ValidationException(invalidCode, 'Eksik ASN.1 DER uzunluk baytı.');
    }
    final lenByte = bytes[offset++];
    if (lenByte == 0x80) {
      throw X509ValidationException(
        invalidCode,
        'Belirsiz uzunluklu (indefinite length 0x80) BER kodlaması DER modunda reddedilir.',
      );
    }

    int contentLen;
    if ((lenByte & 0x80) == 0) {
      contentLen = lenByte;
    } else {
      final numLenBytes = lenByte & 0x7F;
      if (numLenBytes == 0 || numLenBytes > 3 || offset + numLenBytes > endOffset) {
        throw X509ValidationException(invalidCode, 'Geçersiz ASN.1 DER uzunluk başlığı.');
      }
      if (bytes[offset] == 0x00) {
        throw X509ValidationException(
          invalidCode,
          'Kanonik olmayan DER uzunluk kodlaması (gereksiz baştaki 0x00 baytı).',
        );
      }
      contentLen = 0;
      for (var i = 0; i < numLenBytes; i++) {
        contentLen = (contentLen << 8) | bytes[offset++];
      }
      if (contentLen < 128) {
        throw X509ValidationException(
          invalidCode,
          'Kanonik olmayan DER long-form uzunluğu (128\'den küçük uzunluk kısa form olmalıdır).',
        );
      }
    }

    final contentOffset = offset;
    if (contentOffset + contentLen > endOffset) {
      throw X509ValidationException(invalidCode, 'ASN.1 DER içerik uzunluğu konteyner sınırını aşıyor.');
    }
    offset = contentOffset + contentLen;
    return _DerTlv(
      tag: tag,
      startOffset: start,
      contentOffset: contentOffset,
      contentLength: contentLen,
      totalLength: offset - start,
    );
  }

  _DerTlv expectTag(int expectedTag, {String invalidCode = 'INVALID_CA_CERT'}) {
    final tlv = nextTlv(invalidCode: invalidCode);
    if (tlv.tag != expectedTag) {
      throw X509ValidationException(
        invalidCode,
        'Beklenen ASN.1 etiket 0x${expectedTag.toRadixString(16)}, gelen 0x${tlv.tag.toRadixString(16)}.',
      );
    }
    return tlv;
  }

  _DerReader enter(_DerTlv tlv) {
    return _DerReader(
      bytes,
      offset: tlv.contentOffset,
      endOffset: tlv.contentOffset + tlv.contentLength,
      depth: depth + 1,
    );
  }

  void ensureConsumed({String invalidCode = 'INVALID_CA_CERT'}) {
    if (offset != endOffset) {
      throw X509ValidationException(
        invalidCode,
        'ASN.1 DER konteyner sonunda beklenmeyen artık baytlar (trailing bytes) tespit edildi.',
      );
    }
  }
}

/// Sabit zamanlı bayt karşılaştırması.
bool constantTimeEqualsBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Sabit zamanlı ASCII/hex karşılaştırması.
bool constantTimeEqualsAscii(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// 64 haneli kanonik SHA-256 hex özetini üretir (büyük harf, ayracısız).
String computeCanonicalSha256Hex(List<int> derBytes) {
  return sha256
      .convert(derBytes)
      .bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join();
}

/// Kanonik DER baytlarını 64 sütunluk PEM sertifikasına dönüştürür.
String encodeDerCertificateAsPem(Uint8List derBytes) {
  final b64 = base64Encode(derBytes);
  final buffer = StringBuffer()..writeln('-----BEGIN CERTIFICATE-----');
  for (var i = 0; i < b64.length; i += 64) {
    final end = i + 64 < b64.length ? i + 64 : b64.length;
    buffer.writeln(b64.substring(i, end));
  }
  buffer.writeln('-----END CERTIFICATE-----');
  return buffer.toString();
}

const List<int> _asciiBeginPrefix = <int>[
  0x2D, 0x2D, 0x2D, 0x2D, 0x2D, // -----
  0x42, 0x45, 0x47, 0x49, 0x4E, 0x20, // BEGIN SP
];

const List<int> _asciiEndPrefix = <int>[
  0x2D, 0x2D, 0x2D, 0x2D, 0x2D, // -----
  0x45, 0x4E, 0x44, 0x20, // END SP
];

bool _containsSubsequence(Uint8List haystack, List<int> needle) {
  if (haystack.length < needle.length) return false;
  final limit = haystack.length - needle.length;
  for (var i = 0; i <= limit; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

bool _isPemInput(Uint8List rawBytes) {
  final hasBom = rawBytes.length >= 3 &&
      rawBytes[0] == 0xEF &&
      rawBytes[1] == 0xBB &&
      rawBytes[2] == 0xBF;
  if (hasBom) return true;
  return _containsSubsequence(rawBytes, _asciiBeginPrefix) ||
      _containsSubsequence(rawBytes, _asciiEndPrefix);
}

/// Katman 1 (`P-BLOCK-1`): UTF-8 çözümlemesinden bağımsız olarak PEM ve binary DER
/// girişlerini ayırır, yalnızca **tekil** kanonik X.509 sertifika DER gövdesini çıkarır
/// ve canonical SHA-256 parmak izini hesaplar.
CanonicalCertDerResult extractCanonicalSingleCertDer(
  Uint8List rawBytes, {
  String invalidCode = 'INVALID_CA_CERT',
}) {
  if (rawBytes.length < 4 || rawBytes.length > 65536) {
    throw X509ValidationException(
      invalidCode,
      'Sertifika boyutu geçersiz (${rawBytes.length} bayt; beklenen 4..65536).',
    );
  }

  final Uint8List derBytes;
  final bool wasPem;

  if (_isPemInput(rawBytes)) {
    wasPem = true;
    final String decodedText;
    try {
      decodedText = utf8.decode(rawBytes, allowMalformed: false);
    } on FormatException {
      throw X509ValidationException(
        invalidCode,
        'PEM sertifika dosyası geçerli UTF-8 değil.',
      );
    }
    final cleanText =
        decodedText.startsWith('\uFEFF') ? decodedText.substring(1) : decodedText;

    const beginMarker = '-----BEGIN CERTIFICATE-----';
    const endMarker = '-----END CERTIFICATE-----';

    final allMarkers = RegExp(r'-----(BEGIN|END) ([A-Z0-9 _-]+)-----')
        .allMatches(cleanText)
        .toList(growable: false);
    if (allMarkers.length != 2) {
      throw X509ValidationException(
        invalidCode,
        'Sertifika PEM dosyasında tam olarak 1 sertifika bloğu olmalıdır (bulunan işaretçi sayısı: ${allMarkers.length}).',
      );
    }
    final m0 = allMarkers[0];
    final m1 = allMarkers[1];
    if (m0.group(1) != 'BEGIN' ||
        m0.group(2) != 'CERTIFICATE' ||
        m1.group(1) != 'END' ||
        m1.group(2) != 'CERTIFICATE') {
      throw X509ValidationException(
        invalidCode,
        'PEM bloğu yalnızca -----BEGIN CERTIFICATE----- / -----END CERTIFICATE----- olabilir.',
      );
    }

    final prefix = cleanText.substring(0, m0.start);
    final suffix = cleanText.substring(m1.end);
    if (prefix.trim().isNotEmpty || suffix.trim().isNotEmpty) {
      throw X509ValidationException(
        invalidCode,
        'PEM sertifika bloğu dışında beklenmeyen veri bulundu.',
      );
    }

    final beginEndIdx = m0.end;
    final endStartIdx = m1.start;
    if (beginEndIdx >= endStartIdx) {
      throw X509ValidationException(invalidCode, 'PEM blok sırası geçersiz.');
    }

    // İşaretçilerin satır içinde ekstra veriyle bitiştirilmediğini doğrula.
    final rawBodySection = cleanText.substring(beginEndIdx, endStartIdx);
    final stripped = rawBodySection.replaceAll(RegExp(r'[\r\n\t ]+'), '');
    if (stripped.isEmpty ||
        stripped.length % 4 != 0 ||
        !RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(stripped)) {
      throw X509ValidationException(
        invalidCode,
        'PEM Base64 sertifika gövdesi boş veya bozuk.',
      );
    }
    if (beginMarker.length + endMarker.length > rawBytes.length) {
      throw X509ValidationException(invalidCode, 'PEM uzunluğu tutarsız.');
    }

    try {
      derBytes = Uint8List.fromList(base64.decode(stripped));
    } on FormatException {
      throw X509ValidationException(
        invalidCode,
        'PEM Base64 sertifika gövdesi çözümlenemedi.',
      );
    }
  } else {
    // Binary DER yolu: asla utf8.decode çağrılmaz.
    wasPem = false;
    derBytes = Uint8List.fromList(rawBytes);
  }

  if (derBytes.length < 4 || derBytes.length > 65536) {
    throw X509ValidationException(
      invalidCode,
      'DER sertifika boyutu geçersiz (${derBytes.length} bayt).',
    );
  }

  final outerReader = _DerReader(derBytes);
  final outerSeq = outerReader.expectTag(0x30, invalidCode: invalidCode);
  outerReader.ensureConsumed(invalidCode: invalidCode);
  if (outerSeq.totalLength != derBytes.length) {
    throw X509ValidationException(
      invalidCode,
      'DER sertifika uzunluğu girdi boyutuyla uyuşmuyor.',
    );
  }

  return CanonicalCertDerResult(
    derBytes: derBytes,
    sha256Hex: computeCanonicalSha256Hex(derBytes),
    wasPem: wasPem,
  );
}

/// `P-BLOCK-1` (`DEC-REV-1`) Dar Kapsamlı Saf Dart X.509 Ön-Doğrulayıcı.
///
/// Kriptografik imza/zincir doğrulaması yapmaz (gerçek TLS doğrulaması BoringSSL'e
/// bırakılır). Yalnızca 3 onaylı görevi yerine getirir:
/// 1) Root CA sertifikası için X.509v3 yapısal/tarih/`CA:TRUE`/`keyCertSign` ön-kontrolü;
/// 2) Bootstrap (`B-CB-5`) için `subjectDer` & `issuerDer` hızlı isim ön-filtresi;
/// 3) Hub `server.crt` üzerinden IPv4 SAN (`iPAddress [7]`) çıkarımı.
class MmsX509PreValidator {
  static const String _oidBasicConstraints = '2.5.29.19';
  static const String _oidKeyUsage = '2.5.29.15';
  static const String _oidSubjectAltName = '2.5.29.17';

  /// Görev 1: Root CA sertifikasının X.509v3 Root CA ölçütlerini doğrular.
  static void validateRootCaDer(
    Uint8List canonicalDer, {
    DateTime? nowUtc,
  }) {
    final top = _DerReader(canonicalDer);
    final certSeq = top.expectTag(0x30);
    top.ensureConsumed();

    final certChildren = top.enter(certSeq);
    final tbsTlv = certChildren.expectTag(0x30);
    final outerSigAlgTlv = certChildren.expectTag(0x30);
    final outerSigValTlv = certChildren.expectTag(0x03);
    certChildren.ensureConsumed();

    _validateBitStringCanonical(outerSigValTlv.contentBytes(canonicalDer), requireZeroUnusedBits: true);

    final tbs = certChildren.enter(tbsTlv);

    // 1. [0] EXPLICIT Version (v3 == 2 zorunlu)
    if (!tbs.hasNext) {
      throw const X509ValidationException('CA_CERT_NOT_V3', 'Root CA TBSCertificate boş.');
    }
    final versionWrapper = tbs.nextTlv();
    if (versionWrapper.tag != 0xA0) {
      throw const X509ValidationException(
        'CA_CERT_NOT_V3',
        'Root CA X.509 v3 olmalıdır (X.509 v1/v2 sertifikalar reddedilir).',
      );
    }
    final verInner = tbs.enter(versionWrapper);
    final verInt = verInner.expectTag(0x02);
    verInner.ensureConsumed();
    final verVal = _parseCanonicalNonNegativeInt(
      verInt.contentBytes(canonicalDer),
      invalidCode: 'CA_CERT_NOT_V3',
    );
    if (verVal != BigInt.from(2)) {
      throw X509ValidationException(
        'CA_CERT_NOT_V3',
        'Root CA X.509 v3 (sürüm=2) olmalıdır; gelen sürüm=$verVal.',
      );
    }

    // 2. serialNumber (INTEGER, pozitif canonical 1..20 bayt)
    final serialTlv = tbs.expectTag(0x02);
    final serialVal = _parseCanonicalNonNegativeInt(
      serialTlv.contentBytes(canonicalDer),
      maxBytes: 20,
    );
    if (serialVal <= BigInt.zero) {
      throw const X509ValidationException(
        'INVALID_CA_CERT',
        'Root CA seri numarası pozitif olmalıdır.',
      );
    }

    // 3. tbs.signatureAlgorithm == outer.signatureAlgorithm
    final tbsSigAlgTlv = tbs.expectTag(0x30);
    if (!constantTimeEqualsBytes(
      tbsSigAlgTlv.sliceBytes(canonicalDer),
      outerSigAlgTlv.sliceBytes(canonicalDer),
    )) {
      throw const X509ValidationException(
        'INVALID_CA_CERT',
        'TBSCertificate imza algoritması dış sertifika imza algoritmasıyla uyuşmuyor.',
      );
    }

    // 4. issuer Name (boş olmayan SEQUENCE)
    final issuerTlv = tbs.expectTag(0x30);
    if (issuerTlv.contentLength == 0) {
      throw const X509ValidationException('INVALID_CA_CERT', 'Root CA issuer alanı boş.');
    }

    // 5. validity SEQUENCE (notBefore, notAfter)
    final validityTlv = tbs.expectTag(0x30);
    final validityReader = tbs.enter(validityTlv);
    final notBefore = _parseX509Time(validityReader.nextTlv(), canonicalDer);
    final notAfter = _parseX509Time(validityReader.nextTlv(), canonicalDer);
    validityReader.ensureConsumed();
    if (notAfter.isBefore(notBefore)) {
      throw const X509ValidationException(
        'INVALID_CA_CERT',
        'Root CA geçerlilik bitiş tarihi başlangıç tarihinden önce olamaz.',
      );
    }
    final now = (nowUtc ?? DateTime.now()).toUtc();
    if (now.isBefore(notBefore)) {
      throw X509ValidationException(
        'CA_CERT_NOT_YET_VALID',
        'Root CA sertifikası henüz geçerli değil (notBefore=${notBefore.toIso8601String()}).',
      );
    }
    if (now.isAfter(notAfter)) {
      throw X509ValidationException(
        'CA_CERT_EXPIRED',
        'Root CA sertifikasının geçerlilik süresi dolmuş (notAfter=${notAfter.toIso8601String()}).',
      );
    }

    // 6. subject Name (Root CA öz-yayınlı olmalıdır: issuerDer == subjectDer; imza kanıtı DEĞİLDİR)
    final subjectTlv = tbs.expectTag(0x30);
    if (subjectTlv.contentLength == 0) {
      throw const X509ValidationException('INVALID_CA_CERT', 'Root CA subject alanı boş.');
    }
    if (!constantTimeEqualsBytes(
      issuerTlv.sliceBytes(canonicalDer),
      subjectTlv.sliceBytes(canonicalDer),
    )) {
      throw const X509ValidationException(
        'CA_CERT_NOT_SELF_ISSUED',
        'Root CA issuer ve subject alanları birebir aynı olmalıdır.',
      );
    }

    // 7. subjectPublicKeyInfo SEQUENCE
    final spkiTlv = tbs.expectTag(0x30);
    final spkiReader = tbs.enter(spkiTlv);
    spkiReader.expectTag(0x30); // algorithm
    final pubKeyBits = spkiReader.expectTag(0x03);
    spkiReader.ensureConsumed();
    if (pubKeyBits.contentLength < 32) {
      throw const X509ValidationException('INVALID_CA_CERT', 'SubjectPublicKeyInfo anahtar uzunluğu yetersiz.');
    }
    _validateBitStringCanonical(pubKeyBits.contentBytes(canonicalDer), requireZeroUnusedBits: true);

    // 8. Opsiyonel issuerUniqueID [1], subjectUniqueID [2] -> Zorunlu [3] extensions
    _DerTlv? extensionsWrapper;
    var seenUnique1 = false;
    var seenUnique2 = false;
    while (tbs.hasNext) {
      final next = tbs.nextTlv();
      if ((next.tag == 0x81 || next.tag == 0xA1) && !seenUnique1 && !seenUnique2 && extensionsWrapper == null) {
        seenUnique1 = true;
        continue;
      }
      if ((next.tag == 0x82 || next.tag == 0xA2) && !seenUnique2 && extensionsWrapper == null) {
        seenUnique2 = true;
        continue;
      }
      if (next.tag == 0xA3 && extensionsWrapper == null) {
        extensionsWrapper = next;
        continue;
      }
      throw const X509ValidationException(
        'INVALID_CA_CERT',
        'TBSCertificate içinde beklenmeyen alan veya hatalı sıraya sahip uzantı bulundu.',
      );
    }
    tbs.ensureConsumed();

    if (extensionsWrapper == null) {
      throw const X509ValidationException(
        'CA_CERT_NOT_CA',
        'Root CA sertifikasında X.509v3 Extensions bloğu bulunamadı.',
      );
    }

    final extWrapReader = tbs.enter(extensionsWrapper);
    final extSeqTlv = extWrapReader.expectTag(0x30);
    extWrapReader.ensureConsumed();
    final extListReader = extWrapReader.enter(extSeqTlv);

    final seenOids = <String>{};
    var hasBasicConstraintsCaTrue = false;
    var hasKeyCertSign = false;
    var hasSubjectAltName = false;

    while (extListReader.hasNext) {
      final extTlv = extListReader.expectTag(0x30);
      final extReader = extListReader.enter(extTlv);
      final oidTlv = extReader.expectTag(0x06);
      final oid = _decodeOid(oidTlv.contentBytes(canonicalDer));
      if (!seenOids.add(oid)) {
        throw X509ValidationException(
          'INVALID_CA_CERT',
          'Sertifikada tekrarlı X.509 extension OID tespit edildi: $oid.',
        );
      }

      _DerTlv valueOctetTlv;
      final second = extReader.nextTlv();
      if (second.tag == 0x01) {
        // DER kuralı: BOOLEAN DEFAULT FALSE için açıkça FALSE (0x00) kodlanamaz.
        final critBytes = second.contentBytes(canonicalDer);
        if (critBytes.length != 1 || critBytes[0] != 0xFF) {
          throw const X509ValidationException(
            'INVALID_CA_CERT',
            'X.509 extension critical bayrağı kanonik DER kuralını ihlal ediyor (FALSE açık kodlanamaz).',
          );
        }
        valueOctetTlv = extReader.expectTag(0x04);
      } else if (second.tag == 0x04) {
        valueOctetTlv = second;
      } else {
        throw const X509ValidationException(
          'INVALID_CA_CERT',
          'Geçersiz X.509 extension alanı.',
        );
      }
      extReader.ensureConsumed();

      final extValueBytes = valueOctetTlv.contentBytes(canonicalDer);
      if (oid == _oidBasicConstraints) {
        hasBasicConstraintsCaTrue = _parseBasicConstraintsIsCa(extValueBytes);
      } else if (oid == _oidKeyUsage) {
        hasKeyCertSign = _parseKeyUsageHasKeyCertSign(extValueBytes);
      } else if (oid == _oidSubjectAltName) {
        hasSubjectAltName = true;
      }
    }
    extListReader.ensureConsumed();

    if (hasSubjectAltName) {
      throw const X509ValidationException(
        'CA_CERT_IS_LEAF_CERT',
        'Sunucu/yaprak sertifikası (SubjectAltName içeriyor) Root CA yerine verilmiş.',
      );
    }
    if (!hasBasicConstraintsCaTrue) {
      throw const X509ValidationException(
        'CA_CERT_NOT_CA',
        'Sertifika BasicConstraints CA:TRUE taşımıyorsa Root CA olarak kullanılamaz.',
      );
    }
    if (!hasKeyCertSign) {
      throw const X509ValidationException(
        'CA_CERT_MISSING_KEY_CERT_SIGN',
        'Root CA sertifikasında KeyUsage keyCertSign yetkisi zorunludur.',
      );
    }
  }

  /// Görev 2: Bootstrap (`B-CB-5`) hızlı ön-filtresi için `issuerDer` ve `subjectDer` döner.
  static ({Uint8List issuerDer, Uint8List subjectDer}) extractSubjectAndIssuerDer(
    Uint8List certDer,
  ) {
    final top = _DerReader(certDer);
    final certSeq = top.expectTag(0x30);
    top.ensureConsumed();
    final certChildren = top.enter(certSeq);
    final tbsTlv = certChildren.expectTag(0x30);
    certChildren.expectTag(0x30); // outerSigAlg
    certChildren.expectTag(0x03); // signatureValue
    certChildren.ensureConsumed();

    final tbs = certChildren.enter(tbsTlv);
    if (!tbs.hasNext) {
      throw const X509ValidationException('INVALID_CA_CERT', 'TBSCertificate boş.');
    }
    var cur = tbs.nextTlv();
    if (cur.tag == 0xA0) {
      cur = tbs.nextTlv(); // serialNumber
    }
    if (cur.tag != 0x02) {
      throw const X509ValidationException('INVALID_CA_CERT', 'Geçersiz seri numarası.');
    }
    tbs.expectTag(0x30); // sigAlg
    final issuerTlv = tbs.expectTag(0x30);
    tbs.expectTag(0x30); // validity
    final subjectTlv = tbs.expectTag(0x30);
    return (
      issuerDer: Uint8List.fromList(issuerTlv.sliceBytes(certDer)),
      subjectDer: Uint8List.fromList(subjectTlv.sliceBytes(certDer)),
    );
  }

  /// Görev 3: `server.crt` üzerinden SubjectAltName (`2.5.29.17`) `iPAddress [7]` IPv4 adreslerini okur.
  static Set<String> extractServerSanIpv4s(Uint8List serverCertDer) {
    final top = _DerReader(serverCertDer);
    final certSeq = top.expectTag(0x30, invalidCode: 'INVALID_SERVER_CERT');
    top.ensureConsumed(invalidCode: 'INVALID_SERVER_CERT');

    final certChildren = top.enter(certSeq);
    final tbsTlv = certChildren.expectTag(0x30, invalidCode: 'INVALID_SERVER_CERT');
    certChildren.expectTag(0x30, invalidCode: 'INVALID_SERVER_CERT');
    certChildren.expectTag(0x03, invalidCode: 'INVALID_SERVER_CERT');
    certChildren.ensureConsumed(invalidCode: 'INVALID_SERVER_CERT');

    final tbs = certChildren.enter(tbsTlv);
    if (!tbs.hasNext) {
      throw const X509ValidationException('INVALID_SERVER_CERT', 'TBSCertificate boş.');
    }
    var cur = tbs.nextTlv(invalidCode: 'INVALID_SERVER_CERT');
    if (cur.tag == 0xA0) {
      cur = tbs.nextTlv(invalidCode: 'INVALID_SERVER_CERT');
    }
    if (cur.tag != 0x02) {
      throw const X509ValidationException('INVALID_SERVER_CERT', 'Seri numarası geçersiz.');
    }
    tbs.expectTag(0x30, invalidCode: 'INVALID_SERVER_CERT'); // signature
    tbs.expectTag(0x30, invalidCode: 'INVALID_SERVER_CERT'); // issuer
    tbs.expectTag(0x30, invalidCode: 'INVALID_SERVER_CERT'); // validity
    tbs.expectTag(0x30, invalidCode: 'INVALID_SERVER_CERT'); // subject
    tbs.expectTag(0x30, invalidCode: 'INVALID_SERVER_CERT'); // spki

    _DerTlv? extensionsWrapper;
    while (tbs.hasNext) {
      final next = tbs.nextTlv(invalidCode: 'INVALID_SERVER_CERT');
      if (next.tag == 0xA3) {
        extensionsWrapper = next;
      }
    }
    tbs.ensureConsumed(invalidCode: 'INVALID_SERVER_CERT');

    final ips = <String>{};
    if (extensionsWrapper == null) return ips;

    final extWrapReader = tbs.enter(extensionsWrapper);
    final extSeqTlv = extWrapReader.expectTag(0x30, invalidCode: 'INVALID_SERVER_CERT');
    extWrapReader.ensureConsumed(invalidCode: 'INVALID_SERVER_CERT');
    final extListReader = extWrapReader.enter(extSeqTlv);
    final seenOids = <String>{};

    while (extListReader.hasNext) {
      final extTlv = extListReader.expectTag(0x30, invalidCode: 'INVALID_SERVER_CERT');
      final extReader = extListReader.enter(extTlv);
      final oidTlv = extReader.expectTag(0x06, invalidCode: 'INVALID_SERVER_CERT');
      final oid = _decodeOid(oidTlv.contentBytes(serverCertDer), invalidCode: 'INVALID_SERVER_CERT');
      if (!seenOids.add(oid)) {
        throw X509ValidationException(
          'INVALID_SERVER_CERT',
          'Sunucu sertifikasında tekrarlı extension OID tespit edildi: $oid.',
        );
      }
      _DerTlv valueOctetTlv;
      final second = extReader.nextTlv(invalidCode: 'INVALID_SERVER_CERT');
      if (second.tag == 0x01) {
        final critBytes = second.contentBytes(serverCertDer);
        if (critBytes.length != 1 || critBytes[0] != 0xFF) {
          throw const X509ValidationException(
            'INVALID_SERVER_CERT',
            'Sunucu sertifikasında geçersiz DER critical boolean.',
          );
        }
        valueOctetTlv = extReader.expectTag(0x04, invalidCode: 'INVALID_SERVER_CERT');
      } else if (second.tag == 0x04) {
        valueOctetTlv = second;
      } else {
        throw const X509ValidationException('INVALID_SERVER_CERT', 'Geçersiz sunucu uzantı yapısı.');
      }
      extReader.ensureConsumed(invalidCode: 'INVALID_SERVER_CERT');

      if (oid != _oidSubjectAltName) continue;

      final sanBytes = valueOctetTlv.contentBytes(serverCertDer);
      final sanReader = _DerReader(sanBytes);
      final gnSeq = sanReader.expectTag(0x30, invalidCode: 'INVALID_SERVER_CERT');
      sanReader.ensureConsumed(invalidCode: 'INVALID_SERVER_CERT');
      final gnReader = sanReader.enter(gnSeq);
      while (gnReader.hasNext) {
        final gn = gnReader.nextTlv(invalidCode: 'INVALID_SERVER_CERT');
        // GeneralName [7] IMPLICIT OCTET STRING => context-specific primitive tag 0x87
        if (gn.tag == 0x87) {
          final ipBytes = gn.contentBytes(sanBytes);
          if (ipBytes.length == 4) {
            ips.add('${ipBytes[0]}.${ipBytes[1]}.${ipBytes[2]}.${ipBytes[3]}');
          } else if (ipBytes.length != 16) {
            throw X509ValidationException(
              'INVALID_SERVER_CERT',
              'Geçersiz SAN iPAddress uzunluğu: ${ipBytes.length} bayt.',
            );
          }
        }
      }
      gnReader.ensureConsumed(invalidCode: 'INVALID_SERVER_CERT');
    }
    extListReader.ensureConsumed(invalidCode: 'INVALID_SERVER_CERT');
    return ips;
  }

  static bool _parseBasicConstraintsIsCa(Uint8List extValueBytes) {
    final reader = _DerReader(extValueBytes);
    final seq = reader.expectTag(0x30);
    reader.ensureConsumed();
    final inner = reader.enter(seq);
    if (!inner.hasNext) {
      return false; // Boş BasicConstraints -> cA varsayılan FALSE
    }
    final first = inner.nextTlv();
    var isCa = false;
    if (first.tag == 0x01) {
      final b = first.contentBytes(extValueBytes);
      if (b.length != 1 || b[0] != 0xFF) {
        throw const X509ValidationException(
          'INVALID_CA_CERT',
          'BasicConstraints cA alanı kanonik DER BOOLEAN olmalıdır.',
        );
      }
      isCa = true;
      if (inner.hasNext) {
        final pathLen = inner.expectTag(0x02);
        _parseCanonicalNonNegativeInt(pathLen.contentBytes(extValueBytes));
      }
    } else if (first.tag == 0x02) {
      _parseCanonicalNonNegativeInt(first.contentBytes(extValueBytes));
      isCa = false;
    } else {
      throw const X509ValidationException('INVALID_CA_CERT', 'BasicConstraints yapısı geçersiz.');
    }
    inner.ensureConsumed();
    return isCa;
  }

  static bool _parseKeyUsageHasKeyCertSign(Uint8List extValueBytes) {
    final reader = _DerReader(extValueBytes);
    final bitStringTlv = reader.expectTag(0x03);
    reader.ensureConsumed();
    final bits = bitStringTlv.contentBytes(extValueBytes);
    _validateBitStringCanonical(bits, requireZeroUnusedBits: false);
    if (bits.length < 2) {
      return false;
    }
    // RFC 5280 KeyUsage bit 5 = keyCertSign -> ilk içerik baytında MSB'den 5. bit (0x04)
    return (bits[1] & 0x04) != 0;
  }

  static void _validateBitStringCanonical(
    Uint8List content, {
    required bool requireZeroUnusedBits,
  }) {
    if (content.length < 2) {
      throw const X509ValidationException('INVALID_CA_CERT', 'Boş ASN.1 DER BIT STRING.');
    }
    final unused = content[0];
    if (unused > 7 || (requireZeroUnusedBits && unused != 0)) {
      throw const X509ValidationException('INVALID_CA_CERT', 'Geçersiz ASN.1 DER BIT STRING kullanılmayan bit sayısı.');
    }
    final mask = (1 << unused) - 1;
    if ((content.last & mask) != 0) {
      throw const X509ValidationException(
        'INVALID_CA_CERT',
        'ASN.1 DER BIT STRING kullanılmayan son bitler 0 olmalıdır.',
      );
    }
  }

  static BigInt _parseCanonicalNonNegativeInt(
    Uint8List bytes, {
    int? maxBytes,
    String invalidCode = 'INVALID_CA_CERT',
  }) {
    if (bytes.isEmpty || (maxBytes != null && bytes.length > maxBytes)) {
      throw X509ValidationException(invalidCode, 'Geçersiz ASN.1 DER tamsayı uzunluğu.');
    }
    if ((bytes[0] & 0x80) != 0) {
      throw X509ValidationException(invalidCode, 'Negatif ASN.1 DER tamsayı kabul edilmez.');
    }
    if (bytes.length > 1 && bytes[0] == 0x00 && (bytes[1] & 0x80) == 0) {
      throw X509ValidationException(invalidCode, 'ASN.1 DER tamsayıda gereksiz baştaki 0x00 baytı.');
    }
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  static String _decodeOid(Uint8List bytes, {String invalidCode = 'INVALID_CA_CERT'}) {
    if (bytes.isEmpty) {
      throw X509ValidationException(invalidCode, 'Boş X.509 OID.');
    }
    final firstByte = bytes[0];
    final first = firstByte >= 80 ? 2 : firstByte ~/ 40;
    final second = firstByte >= 80 ? firstByte - 80 : firstByte % 40;
    final parts = <int>[first, second];

    var current = 0;
    var inComponent = false;
    for (var i = 1; i < bytes.length; i++) {
      final b = bytes[i];
      if (!inComponent && b == 0x80) {
        throw X509ValidationException(invalidCode, 'Kanonik olmayan DER OID (baştaki 0x80).');
      }
      inComponent = true;
      current = (current << 7) | (b & 0x7F);
      if (current > 0x3FFFFFFF) {
        throw X509ValidationException(invalidCode, 'OID bileşeni güvenli tamsayı sınırını aşıyor.');
      }
      if ((b & 0x80) == 0) {
        parts.add(current);
        current = 0;
        inComponent = false;
      }
    }
    if (inComponent) {
      throw X509ValidationException(invalidCode, 'Eksik ASN.1 DER OID baytı.');
    }
    return parts.join('.');
  }

  static DateTime _parseX509Time(_DerTlv tlv, Uint8List source) {
    final rawBytes = tlv.contentBytes(source);
    final str = String.fromCharCodes(rawBytes);
    final int year;
    final String rest;
    if (tlv.tag == 0x17) {
      // UTCTime: YYMMDDHHMMSSZ (13 ASCII chars)
      if (!RegExp(r'^[0-9]{12}Z$').hasMatch(str)) {
        throw const X509ValidationException('INVALID_CA_CERT', 'Geçersiz X.509 UTCTime formatı.');
      }
      final yy = int.parse(str.substring(0, 2));
      year = yy >= 50 ? 1900 + yy : 2000 + yy;
      rest = str.substring(2, 12);
    } else if (tlv.tag == 0x18) {
      // GeneralizedTime: YYYYMMDDHHMMSSZ (15 ASCII chars)
      if (!RegExp(r'^[0-9]{14}Z$').hasMatch(str)) {
        throw const X509ValidationException('INVALID_CA_CERT', 'Geçersiz X.509 GeneralizedTime formatı.');
      }
      year = int.parse(str.substring(0, 4));
      rest = str.substring(4, 14);
    } else {
      throw const X509ValidationException('INVALID_CA_CERT', 'Geçersiz X.509 geçerlilik zaman etiketi.');
    }

    final month = int.parse(rest.substring(0, 2));
    final day = int.parse(rest.substring(2, 4));
    final hour = int.parse(rest.substring(4, 6));
    final minute = int.parse(rest.substring(6, 8));
    final second = int.parse(rest.substring(8, 10));

    if (month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59) {
      throw const X509ValidationException('INVALID_CA_CERT', 'Geçersiz X.509 takvim/saat değeri.');
    }
    final dt = DateTime.utc(year, month, day, hour, minute, second);
    if (dt.year != year ||
        dt.month != month ||
        dt.day != day ||
        dt.hour != hour ||
        dt.minute != minute ||
        dt.second != second) {
      throw const X509ValidationException('INVALID_CA_CERT', 'Geçersiz X.509 takvim günü.');
    }
    return dt;
  }
}

/// Ortak OpenSSL üretimi geçerli X.509v3 Test Root CA sertifikası (Yalnızca GENEL CA; özel anahtar içermez).
const String kSharedTestRootCaPem = '''-----BEGIN CERTIFICATE-----
MIIDNTCCAh2gAwIBAgIUC46h867BkzwiUq0xlx7QIUMGIhMwDQYJKoZIhvcNAQEL
BQAwIjEgMB4GA1UEAwwXTWFya2V0IE1NUyBUZXN0IFJvb3QgQ0EwHhcNMjYxMTIx
MTY0NzM3WhcNMzYxMTE4MTY0NzM3WjAiMSAwHgYDVQQDDBdNYXJrZXQgTU1TIFRl
c3QgUm9vdCBDQTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMTNw4Wy
5M9CM0Z0aRuBdO860JJH7fH5souP0qbNUWNY38WDhQ7G6azsrs7vorOgMvlza5sV
JIoZCOEU0aNJU2VcNYaz34raS9WZ/vqXeCqZrdF/0djeO8aajCGQbwviMAflu0HJ
yU6chyjbPXOpihbkNLL0ER4dP6I3SRh2SyDEib5G7jY7hrFwnFz0H4ERBgiRTSA9
hPvgz0qdhfdQH8eBwJzWs+DHpnPtbxryj3mPf+epePRDhgEteED3A/r3rY/MjP11
u2Jt4gQkZa3g8yz+V2XcjiTU9hVytu0tnYhsWYBs/D1adz8aatvQyyeWrrGsFANO
Jl6RfCE3JFtxQMkCAwEAAaNjMGEwHQYDVR0OBBYEFMP3gNcWn3Qd4fiLAg2NKBNg
afEoMB8GA1UdIwQYMBaAFMP3gNcWn3Qd4fiLAg2NKBNgafEoMA8GA1UdEwEB/wQF
MAMBAf8wDgYDVR0PAQH/BAQDAgEGMA0GCSqGSIb3DQEBCwUAA4IBAQCfLJ83QLFT
RIw8cJRduCA+dRDSZhU4bHp7+/Gbq5K2OTwiRoouZ+Kmp/QUgKzI45QhDXunyGqf
Cfdl0BcZvih//YsdzvscqdVaDQSx4WTjJ+jwdqQ7lLYXsvkPcUeNoqFHa94Wv083
5b0r3N6UaKaNTr/Tlw6Rm3h71g72UHqzT/isN6VZzg28X+7Obd9cjAnkPSJt8+Tp
JBo29Yo0JD/AAosz0PESRP59aq8C6bPB7l8N73MBN3AgxObvjRd0G79DldVp7pSX
3aPeS9ExVZkrz8zo6prl5kyq7DRH7tYgVW4dUdYZhNhJzE8oKDWjQrvdJYF82jqW
iGSdwe/VX7Pq
-----END CERTIFICATE-----''';

const String kSharedTestRootCaSha256Hex =
    'AF207554E5EB8EB3BF8D2303BA1CD6B51C251B9BA0C27FCE7BCAD5AEBFA676BD';

Uint8List get kSharedTestRootCaDerBytes =>
    extractCanonicalSingleCertDer(Uint8List.fromList(utf8.encode(kSharedTestRootCaPem))).derBytes;
