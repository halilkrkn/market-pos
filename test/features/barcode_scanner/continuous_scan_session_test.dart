import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:market_pos/features/barcode_scanner/domain/camera_barcode_debounce.dart';
import 'package:market_pos/features/barcode_scanner/domain/continuous_scan_session.dart';

/// Faz 2 §4.1.7–8: Sürekli kamera taraması — debounce, eşzamanlı kare kilidi ve hata dayanımı.
void main() {
  late DateTime now;
  late List<String> handled;

  ContinuousScanSession buildSession({
    Future<ScanFeedback> Function(String barcode)? onBarcode,
  }) {
    return ContinuousScanSession(
      debounce: CameraBarcodeDebounce(
        cooldown: const Duration(milliseconds: 1500),
        clock: () => now,
      ),
      onBarcode: onBarcode ??
          (barcode) async {
            handled.add(barcode);
            return ScanFeedback.success('Eklendi: $barcode');
          },
    );
  }

  setUp(() {
    now = DateTime(2026, 11, 21, 10);
    handled = [];
  });

  test('Geçerli barkod işlenir ve geri bildirim döner', () async {
    final session = buildSession();
    final feedback = await session.handleRaw(' 8690123456789\n');
    expect(handled, ['8690123456789']);
    expect(feedback?.kind, ScanFeedbackKind.success);
    expect(session.lastFeedback, feedback);
    expect(session.processedCount, 1);
  });

  test('Aynı barkodun ardışık kameraları soğuma süresinde tekrar eklenmez', () async {
    final session = buildSession();
    await session.handleRaw('8690123456789');
    now = now.add(const Duration(milliseconds: 300));
    expect(await session.handleRaw('8690123456789'), isNull);
    expect(handled, hasLength(1));
  });

  test('Soğuma süresi dolunca aynı ürün tekrar okutulabilir (miktar artışı için)', () async {
    final session = buildSession();
    await session.handleRaw('8690123456789');
    now = now.add(const Duration(milliseconds: 1600));
    await session.handleRaw('8690123456789');
    expect(handled, ['8690123456789', '8690123456789']);
  });

  test('Bir barkod işlenirken gelen başka kareler bırakılır (çift ekleme yok)', () async {
    final gate = Completer<ScanFeedback>();
    final session = buildSession(onBarcode: (b) {
      handled.add(b);
      return gate.future;
    });

    final first = session.handleRaw('8690123456789');
    expect(session.isProcessing, isTrue);
    expect(await session.handleRaw('8691111111116'), isNull);
    gate.complete(ScanFeedback.success('ok'));
    await first;

    expect(handled, ['8690123456789']);
    expect(session.isProcessing, isFalse);
  });

  test('Geçersiz/boş kareler yok sayılır', () async {
    final session = buildSession();
    expect(await session.handleRaw(null), isNull);
    expect(await session.handleRaw('   '), isNull);
    expect(handled, isEmpty);
  });

  test('İşleyici hata fırlatırsa oturum kilitlenmez ve hata geri bildirimi verilir', () async {
    var shouldFail = true;
    final session = buildSession(onBarcode: (b) async {
      if (shouldFail) throw StateError('db kilitli');
      handled.add(b);
      return ScanFeedback.success('ok');
    });

    final failed = await session.handleRaw('8690123456789');
    expect(failed?.kind, ScanFeedbackKind.error);
    expect(session.isProcessing, isFalse);

    shouldFail = false;
    await session.handleRaw('8691111111116');
    expect(handled, ['8691111111116']);
  });
}
