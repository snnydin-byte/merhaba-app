/// Küçük ekran-yerel async işlemlerde geç kalan sonuçların state veya ağ
/// işlemi üretmesini engelleyen generation tabanlı koruma.
class AsyncOperationGuard {
  int _generation = 0;
  bool _closed = false;

  int begin() {
    if (_closed) return -1;
    return ++_generation;
  }

  bool isActive(int generation) =>
      !_closed && generation > 0 && generation == _generation;

  void cancelCurrent() {
    if (_closed) return;
    _generation++;
  }

  void close() {
    _closed = true;
    _generation++;
  }
}
