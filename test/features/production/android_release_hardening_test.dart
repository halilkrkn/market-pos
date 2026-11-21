import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Faz 7C / SEC-ABK — Android üretim yapılandırmasının depo düzeyinde doğrulanması.
///
/// Android'in otomatik yedekleme (Google bulut yedeği ve cihazdan cihaza aktarım)
/// özelliği varsayılan olarak AÇIKTIR. Açık kalırsa:
///  * şifresiz yerel SQLite (satışlar, Outbox) ve kurulum dosyaları ADR-010/011
///    dışında Google hesabına kopyalanır (Drive yalnızca şifreli `.mmsbak` içindir);
///  * yeni bir cihaza geri yüklendiğinde aynı `device_id` ve `client_seq` sayacı iki
///    cihazda birden yaşar → Hub'da `ERR_IDEMPOTENCY_CONFLICT` / sıra çakışması.
/// Bu nedenle manifest yedeklemeyi kapatmalı ve API 31+ kurallarıyla tüm alanları
/// hariç tutmalıdır.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml');
  final gradle = File('android/app/build.gradle.kts');

  String applicationTag(String xml) =>
      RegExp(r'<application\b[^>]*>', dotAll: true).firstMatch(xml)!.group(0)!;

  test('Android otomatik yedekleme kapalı (allowBackup=false, fullBackupContent=false)', () {
    final app = applicationTag(manifest.readAsStringSync());
    expect(app, contains('android:allowBackup="false"'));
    expect(app, contains('android:fullBackupContent="false"'));
    expect(app, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
  });

  test('API 31+ veri çıkarma kuralları bulut yedeği ve cihaz aktarımında tüm alanları hariç tutar', () {
    expect(rules.existsSync(), isTrue, reason: 'res/xml/data_extraction_rules.xml eksik');
    final xml = rules.readAsStringSync();
    for (final section in ['cloud-backup', 'device-transfer']) {
      final body = RegExp('<$section>(.*?)</$section>', dotAll: true).firstMatch(xml)?.group(1);
      expect(body, isNotNull, reason: '<$section> bölümü yok');
      for (final domain in ['root', 'file', 'database', 'sharedpref', 'external']) {
        expect(body, contains('<exclude domain="$domain" path="."'),
            reason: '$section içinde $domain alanı hariç tutulmalı');
      }
      expect(body, isNot(contains('<include')), reason: '$section hiçbir alanı dahil etmemeli');
    }
  });

  test('Release: cleartext kapalı ve key.properties yoksa derleme durur (debug imzaya sessiz düşüş yok)', () {
    final g = gradle.readAsStringSync();
    expect(g, contains('manifestPlaceholders["usesCleartextTraffic"] = if (allowReleaseCleartext) "true" else "false"'));
    expect(g, contains('throw GradleException('));
    expect(g, contains('!hasReleaseKeystore && !allowDebugSigning'));
    expect(manifest.readAsStringSync(), contains(r'android:usesCleartextTraffic="${usesCleartextTraffic}"'));
  });

  test('key.properties ve keystore dosyaları Git dışında tutulur', () {
    final gitignore = File('.gitignore').readAsStringSync();
    expect(gitignore, contains('key.properties'));
    expect(gitignore, anyOf(contains('*.jks'), contains('*.keystore')));
  });
}
