// Gönderim öncesi uyarılar (Batch F, güvenlik/gizlilik) - HİÇBİRİ mesajı
// ENGELLEMİYOR, yalnızca "emin misin?" diye bir kez sorup kullanıcı isterse
// aynen gönderiyor. Sunucu tarafında bir karşılığı YOK (bilerek - bu saf bir
// istemci tarafı nezaket uyarısı, sunucunun mesaj içeriğine göre engelleme
// yapması ayrı ve çok daha riskli bir karar olurdu - yanlış pozitifler
// meşru mesajları engelleyebilir).

/// Kişisel bilgi paylaşımı uyarısı (madde "kişisel bilgi paylaşımı uyarısı,
/// regex tabanlı, telefon/adres deseni") - Türkiye telefon numarası
/// desenlerini (05XX XXX XX XX, +90 5XX..., 0XXX XXX XXXX gibi yaygın
/// yazımlar) ve basit bir "adres" ipucunu (mahalle/sokak/cadde + sayı)
/// yakalar. Tam bir NLP/adres ayrıştırıcı DEĞİL - kasıtlı olarak basit,
/// amaç mükemmel tespit değil, dikkat çekmek.
final RegExp _phonePattern = RegExp(
  r'(\+?\d[\d\s().-]{8,}\d)',
);
final RegExp _addressHintPattern = RegExp(
  r'\b(mahalle(si)?|sokak|sk\.?|cadde(si)?|cd\.?|apartman|daire|no\s*:?\s*\d+)\b',
  caseSensitive: false,
);

bool containsPersonalInfo(String text) {
  return _phonePattern.hasMatch(text) || _addressHintPattern.hasMatch(text);
}

/// Saldırgan mesaj öncesi uyarı (madde "basit anahtar kelime listesi") -
/// gerçek bir küfür/hakaret filtresi DEĞİL (dil işleme kapsamı dışı),
/// yalnızca en yaygın birkaç kalıbı yakalayan kaba bir liste - amaç
/// göndereni bir an durup düşünmeye teşvik etmek.
const List<String> _offensiveKeywords = [
  'aptal', 'gerizekalı', 'salak', 'ahmak', 'geri zekalı',
  'nefret ediyorum', 'seni öldür', 'geber',
];

bool containsOffensiveLanguage(String text) {
  final lower = text.toLowerCase();
  return _offensiveKeywords.any((word) => lower.contains(word));
}
