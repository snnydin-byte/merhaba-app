/// Socket.IO mobil istemcisi tek bir nesne argümanını bazı transport/adapter
/// yollarında doğrudan Map, bazılarında ise tek elemanlı List olarak teslim
/// edebilir. Map sözleşmeli eventlerin tamamı bu yardımcıdan geçirilmelidir.
Map<String, dynamic> socketEventMap(dynamic payload) {
  Map<String, dynamic>? findMap(dynamic value, int depth) {
    if (depth > 4) return null;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List) {
      for (final item in value) {
        final map = findMap(item, depth + 1);
        if (map != null) return map;
      }
    }
    return null;
  }

  final map = findMap(payload, 0);
  if (map != null) return map;
  throw FormatException(
    'Socket event nesne bekliyordu, ${payload.runtimeType} aldı.',
  );
}
