/// Sticker paketi (#65 anket maddesi) - gerçek çizim/ikon varlıkları yerine
/// bilinçli olarak büyük-boy emoji kullanılıyor (WhatsApp'ın "emoji sticker"
/// tarzı) - hem ücretsiz hem yeni bir binary asset/CDN bağımlılığı
/// gerektirmiyor. Bu liste signaling_server/server.js'deki STICKER_CATALOG
/// ile BİREBİR aynı id'leri kullanmalı - sunucu yalnızca oradaki listede
/// olan bir stickerId'yi kabul eder.
class StickerDef {
  final String id;
  final String emoji;
  final String label;
  const StickerDef(this.id, this.emoji, this.label);
}

const List<StickerDef> kStickerCatalog = [
  StickerDef('klasik:kalp', '❤️', 'Kalp'),
  StickerDef('klasik:gulen', '😄', 'Gülen'),
  StickerDef('klasik:agliyor', '😭', 'Ağlıyor'),
  StickerDef('klasik:sok', '😱', 'Şok'),
  StickerDef('klasik:alkis', '👏', 'Alkış'),
  StickerDef('klasik:basparmak', '👍', 'Beğendim'),
  StickerDef('klasik:ates', '🔥', 'Ateş'),
  StickerDef('klasik:parti', '🎉', 'Parti'),
  StickerDef('klasik:uyku', '😴', 'Uyku'),
  StickerDef('klasik:selam', '👋', 'Selam'),
  StickerDef('klasik:gozkirp', '😉', 'Göz kırp'),
  StickerDef('klasik:kahkaha', '🤣', 'Kahkaha'),
];

String stickerEmojiFor(String stickerId) {
  for (final s in kStickerCatalog) {
    if (s.id == stickerId) return s.emoji;
  }
  return '❓';
}
