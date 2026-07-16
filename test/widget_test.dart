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

      expect(find.text('Merhaba'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );
}
