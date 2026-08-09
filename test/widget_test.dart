// Bu, Flutter'ın varsayılan "counter" şablon testinin yerini alan gerçek bir
// duman (smoke) testidir. Eski test var olmayan bir `MyApp` sınıfına ve
// paket adına (`merhaba`) atıfta bulunuyordu; gerçek uygulama sınıfı
// `MerhabaApp` ve paket adı `merhaba_app` (bkz. pubspec.yaml) olduğundan bu
// test hiç derlenemiyordu.
//
// Ana ekrana geçiş bir Timer'a bağlı olduğu için burada pumpAndSettle
// kullanmıyoruz; sadece açılış ekranının doğru göründüğünü kontrol ediyoruz.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:merhaba_app/main.dart';

void main() {
  testWidgets(
    'Açılış ekranı marka adını ve yükleniyor göstergesini gösterir',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MerhabaApp());
      await tester.pump();

      expect(find.text('MERHABA'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Açılış ekranındaki 1600ms'lik minimum gösterim süresi bir
      // Future.delayed (dolayısıyla bir Timer) kullanıyor - yukarıdaki tek
      // pump() bunu bitirmeden test biterse, widget ağacı dispose
      // edildiğinde flutter_test "A Timer is still pending" diye test'i
      // BAŞARISIZ sayıyor (asıl kontrol ettiğimiz şeyle - açılış ekranının
      // doğru görünmesiyle - ilgisi yok, sadece temizlik). Süreyi ileri
      // alıp bekleyen Timer'ın/Future zincirinin tamamlanmasına izin
      // veriyoruz; bu noktada ekran zaten değişmiş olabilir ama yukarıdaki
      // asıl assertion'lar ondan ÖNCE zaten çalıştı.
      await tester.pump(const Duration(milliseconds: 1700));
    },
  );
}
