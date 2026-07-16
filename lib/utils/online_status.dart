/// Ana ekranda gösterilen "çevrimiçi kullanıcı sayısı" metnini üreten
/// saf (side-effect'siz) yardımcı fonksiyon. Ağ/soket bağımlılığı olmadığı
/// için birim testte kolayca doğrulanabilir (bkz. test/online_status_test.dart).
///
/// Önceden bu sayı ekranda sabit/uydurma bir değerdi ("3,482 kişi çevrimiçi").
/// Artık sinyalleşme sunucusundan gelen gerçek sayı kullanılıyor; sunucuya
/// henüz ulaşılamadıysa (örn. sunucu kapalı, ağ hatası) sahte bir rakam
/// göstermek yerine durumu dürüstçe yansıtan bir metin döndürüyoruz.
String onlineCountLabel(int? count) {
  if (count == null) return 'Çevrimiçi sayısı alınamıyor';
  if (count == 1) return '1 kişi çevrimiçi';
  return '$count kişi çevrimiçi';
}

/// Arkadaş listesindeki bir kişi için çevrimiçi/son görülme metnini üretir
/// (bkz. friends_screen.dart). [now] test edilebilirlik için dışarıdan
/// verilir - gerçek kullanımda DateTime.now() geçilir (bkz. çağıran taraf).
///
/// [online] true ise kişinin o an açık bir bağlantısı var demektir (bkz.
/// server.js isUserOnline()) - "son görülme" bu durumda anlamsız olduğu
/// için gösterilmez. [lastSeen] hiç ayarlanmamışsa (ör. hesap hiç
/// bağlanmadı, ya da eski bir kayıt) "Çevrimdışı" gösterilir.
String lastSeenLabel({required bool online, required DateTime? lastSeen, required DateTime now}) {
  if (online) return 'Çevrimiçi';
  if (lastSeen == null) return 'Çevrimdışı';

  final diff = now.difference(lastSeen);
  if (diff.isNegative || diff.inMinutes < 1) return 'Az önce çevrimiçiydi';
  if (diff.inMinutes < 60) return '${diff.inMinutes} dakika önce çevrimiçiydi';
  if (diff.inHours < 24) return '${diff.inHours} saat önce çevrimiçiydi';
  if (diff.inDays < 7) return '${diff.inDays} gün önce çevrimiçiydi';
  return 'Uzun süredir çevrimdışı';
}
