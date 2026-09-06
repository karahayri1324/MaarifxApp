import 'dart:async';

/// Yüksek frekanslı akış güncellemelerini demetler (throttle).
///
/// Akış token'ları saniyede ~150 geliyor ve her biri tek tek `notifyListeners`
/// çağırıyordu. Flutter bunları kareye indirse bile ekran saniyede 60 kez
/// yeniden kuruluyor: büyüyen cevabın markdown+LaTeX'i her karede BAŞTAN
/// ayrıştırılıyor (kare başına O(n) → akış boyunca O(n²)) ve aynı Consumer
/// altındaki composer da her karede yeniden kuruluyordu.
///
/// Demetlenen şey yalnız BİLDİRİMDİR; model nesneleri her token'da anında
/// güncellenmeye devam eder. Dolayısıyla araya giren herhangi bir olay
/// (`request_complete`, hata, sunucu bildirimi) kendi `notifyListeners`'ı ile
/// zaten en güncel hâli yayımlar — hiçbir token görüntülenmeden kaybolmaz.
///
/// Davranış: ilk istek ANINDA yayımlanır (leading edge), pencere içindeki
/// istekler tek bir yayına indirgenir, pencere kapanırken bekleyen varsa
/// yeniden yayımlanır (trailing edge) — yani SON token daima görünür.
class AkisBildirimi {
  AkisBildirimi(
    this._yayinla, {
    Duration aralik = const Duration(milliseconds: 50),
  }) : _aralik = aralik;

  final void Function() _yayinla;
  final Duration _aralik;

  Timer? _timer;
  bool _bekleyen = false;
  bool _durdu = false;

  /// Test/teşhis için: şu an bekleyen (henüz yayımlanmamış) bir güncelleme var mı?
  bool get bekleyenVar => _bekleyen;

  void iste() {
    if (_durdu) return;
    if (_timer != null) {
      _bekleyen = true;
      return;
    }
    _yayinla();
    _timer = Timer(_aralik, _pencereBitti);
  }

  void _pencereBitti() {
    _timer = null;
    if (_bekleyen) {
      _bekleyen = false;
      iste();
    }
  }

  /// Bekleyen yayını iptal eder (ör. sohbet temizlendi — o mesajlar artık yok).
  void temizle() {
    _timer?.cancel();
    _timer = null;
    _bekleyen = false;
  }

  /// Kalıcı olarak durdurur. `dispose` sonrası ateşleyen bir zamanlayıcı
  /// `notifyListeners`'ı "used after disposed" ile patlatır.
  void durdur() {
    _durdu = true;
    temizle();
  }
}
