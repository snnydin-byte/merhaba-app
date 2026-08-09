// lib/utils/online_status.dart içindeki onlineCountLabel fonksiyonu için
// birim testleri. Bu fonksiyon ağ/soket bağımlılığı olmayan saf bir
// yardımcı olduğu için hızlı ve güvenilir bir şekilde test edilebiliyor.

import 'package:flutter_test/flutter_test.dart';
import 'package:merhaba_app/utils/online_status.dart';

void main() {
  group('onlineCountLabel', () {
    test('sayı bilinmiyorsa sahte bir rakam göstermez, dürüst bir metin döner',
        () {
      expect(onlineCountLabel(null), 'Çevrimiçi sayısı alınamıyor');
    });

    test('tekil durumda doğru çekim kullanır', () {
      expect(onlineCountLabel(1), '1 kişi çevrimiçi');
    });

    test('çoğul durumda sayıyı doğru biçimlendirir', () {
      expect(onlineCountLabel(3482), '3482 kişi çevrimiçi');
    });

    test('sıfır kullanıcıda da doğru mesajı gösterir', () {
      expect(onlineCountLabel(0), '0 kişi çevrimiçi');
    });
  });

  group('lastSeenLabel', () {
    final now = DateTime(2026, 1, 1, 12, 0, 0);

    test('çevrimiçiyse son görülme yerine "Çevrimiçi" döner', () {
      expect(
        lastSeenLabel(
            online: true,
            lastSeen: now.subtract(const Duration(days: 5)),
            now: now),
        'Çevrimiçi',
      );
    });

    test('hiç son görülme kaydı yoksa "Çevrimdışı" döner', () {
      expect(
          lastSeenLabel(online: false, lastSeen: null, now: now), 'Çevrimdışı');
    });

    test('1 dakikadan az önce ise "Az önce çevrimiçiydi" döner', () {
      expect(
        lastSeenLabel(
            online: false,
            lastSeen: now.subtract(const Duration(seconds: 30)),
            now: now),
        'Az önce çevrimiçiydi',
      );
    });

    test('dakikalar içinde doğru sayıyı gösterir', () {
      expect(
        lastSeenLabel(
            online: false,
            lastSeen: now.subtract(const Duration(minutes: 15)),
            now: now),
        '15 dakika önce çevrimiçiydi',
      );
    });

    test('saatler içinde doğru sayıyı gösterir', () {
      expect(
        lastSeenLabel(
            online: false,
            lastSeen: now.subtract(const Duration(hours: 3)),
            now: now),
        '3 saat önce çevrimiçiydi',
      );
    });

    test('günler içinde doğru sayıyı gösterir', () {
      expect(
        lastSeenLabel(
            online: false,
            lastSeen: now.subtract(const Duration(days: 2)),
            now: now),
        '2 gün önce çevrimiçiydi',
      );
    });

    test('bir haftadan uzun süredir çevrimdışıysa genel bir mesaj döner', () {
      expect(
        lastSeenLabel(
            online: false,
            lastSeen: now.subtract(const Duration(days: 30)),
            now: now),
        'Uzun süredir çevrimdışı',
      );
    });
  });
}
