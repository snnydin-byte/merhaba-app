/// Socket.IO bağlantılarının bütün istemci servislerinde aynı retry/backoff
/// davranışını kullanmasını sağlar. Ham option map kullanmak, socket_io_client
/// sürümleri arasında OptionBuilder yardımcı adlarının değişmesine karşı daha
/// az kırılgandır.
Map<String, dynamic> buildSocketClientOptions({String? authToken}) {
  return <String, dynamic>{
    // socket_io_client'ın Dart VM/Flutter uygulaması WebSocket transportuyla
    // çalışır. Polling'i ikinci transport olarak eklemek Android'de bazı yeni
    // Manager örneklerini "Sunucuya bağlanılıyor" durumunda bırakabiliyor.
    'transports': <String>['websocket'],
    'autoConnect': false,
    'forceNew': true,
    'reconnection': true,
    'reconnectionDelay': 1000,
    // Paket varsayımı sınırsız denemedir. Mobil ağ uzun süre kapalı kalsa bile
    // servisleri kalıcı olarak çevrimdışı bırakmayız; üst gecikme ve jitter aynı
    // anda binlerce istemcinin yeniden bağlanma fırtınasını sınırlar.
    'reconnectionDelayMax': 30000,
    'randomizationFactor': 0.5,
    'timeout': 20000,
    if (authToken != null && authToken.isNotEmpty)
      'auth': <String, dynamic>{'token': authToken},
  };
}
