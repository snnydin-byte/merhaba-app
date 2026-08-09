import 'package:flutter/material.dart';

/// Uygulama genelinde, herhangi bir ekranın kendi BuildContext'ine ihtiyaç
/// duymadan diyalog açmak/ekran değiştirmek/SnackBar göstermek için
/// kullanılan global navigator anahtarı.
///
/// Bu, mesajlaşma ve arama bağlantılarının artık uygulama boyunca kalıcı
/// olmasıyla (bkz. messaging_service.dart, call_service.dart) ortaya çıkan
/// bir ihtiyaç: gelen bir arama daveti ya da mesaj bildirimi, kullanıcı o an
/// hangi ekranda olursa olsun (Ana Sayfa, Profil, Ayarlar, hatta rastgele
/// eşleşme ekranı) gösterilebilmeli - artık bunun için "doğru" ekranın açık
/// olmasını beklemiyoruz. main.dart'ta MaterialApp'e verilir.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Uygulama genelindeki snackbar ve MaterialBanner katmanlarını BuildContext
/// taşımadan güvenli biçimde temizlemek/göstermek için kullanılır. Oturum
/// kapanırken eski ekrana ait mesajların LoginScreen üzerinde kalmasını önler.
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// O an gösterilebilecek güncel bir BuildContext döner (varsa). Uygulama
/// henüz hiç build edilmediyse ya da navigator hazır değilse null döner -
/// çağıran taraf bu durumda sessizce vazgeçmeli (ör. uygulama daha açılışta
/// splash ekranındayken bir soket olayı gelirse).
BuildContext? get currentAppContext =>
    navigatorKey.currentState?.overlay?.context;
