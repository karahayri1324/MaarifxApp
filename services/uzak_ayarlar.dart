import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../config/log.dart';

/// UZAKTAN YÖNETİLEN AYARLAR (2026-11-08) — admin panelinden değişir, uygulama
/// açılışta ve öne gelince çeker (VDS: uygulama_yonetimi.js).
///
///  * [modelAdi]   : model çipinde görünen ad ("3.5"). Son bilinen değer cihazda
///                   saklanır → açılışta eski adın bir an görünmesi (titreme) olmaz.
///  * [guncelleme] : zorunlu / isteğe bağlı güncelleme kararı. Sunucu kararı
///                   build numarasına göre verir; AĞ YOKSA ASLA KİLİTLEMEZ
///                   (yanlışlıkla bütün öğrencileri dışarıda bırakmamak için).
///  * Duyurular da buradan alınır. (Gizlilik politikası: maarifx.com/Gizlilik — tarayıcı.)
///
/// Hiçbir hata uygulamayı durdurmaz: her yolun bir varsayılanı var.
class UzakAyarlar extends ChangeNotifier {
  static const String varsayilanModelAdi = '3.5';
  static const String _kModelAdi = 'uzak_model_adi';
  static const String _kGorulenDuyurular = 'gorulen_duyurular';
  static const String _kErtelenenSurum = 'guncelleme_ertelenen_build';

  /// Testler sahte istemci/build verebilsin diye.
  UzakAyarlar({http.Client? istemci, Future<int?> Function()? buildOkuyucu, String? platform})
      : _istemci = istemci ?? http.Client(),
        _buildOkuyucu = buildOkuyucu ?? _paketBuild,
        _platform = platform ?? (Platform.isIOS ? 'ios' : 'android');

  final http.Client _istemci;
  final Future<int?> Function() _buildOkuyucu;
  final String _platform;

  String _modelAdi = varsayilanModelAdi;
  String get modelAdi => _modelAdi;

  GuncellemeBilgisi? _guncelleme;
  GuncellemeBilgisi? get guncelleme => _guncelleme;

  /// İsteğe bağlı güncelleme kartı kullanıcı "Sonra" deyince bu build için gizlenir.
  bool _istegeBagliGizli = false;
  bool get istegeBagliGoster =>
      _guncelleme != null && !_guncelleme!.zorunlu && _guncelleme!.yeniVar && !_istegeBagliGizli;

  int? _build;
  int? get build => _build;
  String _surumAdi = '';
  String get surumAdi => _surumAdi;

  bool _yukleniyor = false;
  DateTime? _sonYukleme;

  static Future<int?> _paketBuild() async {
    try {
      final p = await PackageInfo.fromPlatform();
      return int.tryParse(p.buildNumber);
    } catch (_) {
      return null;
    }
  }

  Future<void> _surumBilgisi() async {
    if (_build != null) return;
    _build = await _buildOkuyucu();
    try {
      final p = await PackageInfo.fromPlatform();
      _surumAdi = p.version;
    } catch (_) {}
  }

  /// Açılışta bir kez + öne gelince (en sık 10 dk'da bir) çağrılır.
  Future<void> yukle({bool zorla = false}) async {
    if (_yukleniyor) return;
    if (!zorla && _sonYukleme != null &&
        DateTime.now().difference(_sonYukleme!) < const Duration(minutes: 10)) {
      return;
    }
    _yukleniyor = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final onbellek = prefs.getString(_kModelAdi);
      if (onbellek != null && onbellek.isNotEmpty && onbellek != _modelAdi) {
        _modelAdi = onbellek;
        notifyListeners();
      }
      await _surumBilgisi();
      final uri = Uri.parse('${AppConfig.apiUrl}/api/uygulama/ayarlar').replace(
        queryParameters: {'platform': _platform, if (_build != null) 'build': '$_build'},
      );
      final r = await _istemci.get(uri).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final ad = (j['modelAdi'] as String?)?.trim() ?? '';
      if (ad.isNotEmpty && ad.length <= 20) {
        _modelAdi = ad;
        await prefs.setString(_kModelAdi, ad);
      }
      final g = j['guncelleme'];
      if (g is Map<String, dynamic>) {
        _guncelleme = GuncellemeBilgisi.fromJson(g);
        final ertelenen = prefs.getInt(_kErtelenenSurum) ?? -1;
        _istegeBagliGizli = ertelenen >= _guncelleme!.sonBuild && _guncelleme!.sonBuild > 0;
      }
      _sonYukleme = DateTime.now();
      notifyListeners();
    } catch (e) {
      logD('[Uzak] ayarlar alınamadı: $e');
    } finally {
      _yukleniyor = false;
    }
  }

  /// İsteğe bağlı güncelleme kartında "Sonra": bu sürüm için bir daha önerme.
  Future<void> istegeBagliErtele() async {
    _istegeBagliGizli = true;
    notifyListeners();
    final sb = _guncelleme?.sonBuild ?? 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kErtelenenSurum, sb);
    } catch (_) {}
  }

  // ─── Duyurular ─────────────────────────────────────────────────────────

  /// Henüz gösterilmemiş en yeni duyuru (yoksa null). Gösterilince [duyuruGoruldu].
  Future<Duyuru?> siradakiDuyuru({String? token}) async {
    try {
      final r = await _istemci.get(
        Uri.parse('${AppConfig.apiUrl}/api/uygulama/duyurular'),
        headers: {if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final liste = (j['duyurular'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Duyuru.fromJson)
          .whereType<Duyuru>()
          .toList();
      if (liste.isEmpty) return null;
      final prefs = await SharedPreferences.getInstance();
      final gorulen = prefs.getStringList(_kGorulenDuyurular) ?? const [];
      for (final d in liste) {
        if (!gorulen.contains('${d.id}')) return d;
      }
    } catch (e) {
      logD('[Uzak] duyurular alınamadı: $e');
    }
    return null;
  }

  Future<void> duyuruGoruldu(int id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final l = List<String>.from(prefs.getStringList(_kGorulenDuyurular) ?? const []);
      if (!l.contains('$id')) l.add('$id');
      if (l.length > 200) l.removeRange(0, l.length - 200);
      await prefs.setStringList(_kGorulenDuyurular, l);
    } catch (_) {}
  }
}

class GuncellemeBilgisi {
  final bool zorunlu;
  final bool yeniVar;
  final int minBuild;
  final int sonBuild;
  final String magazaUrl;
  final String mesaj;

  const GuncellemeBilgisi({
    required this.zorunlu,
    required this.yeniVar,
    this.minBuild = 0,
    this.sonBuild = 0,
    this.magazaUrl = '',
    this.mesaj = '',
  });

  factory GuncellemeBilgisi.fromJson(Map<String, dynamic> j) => GuncellemeBilgisi(
        zorunlu: j['zorunlu'] == true,
        yeniVar: j['yeniVar'] == true,
        minBuild: (j['minBuild'] as num?)?.toInt() ?? 0,
        sonBuild: (j['sonBuild'] as num?)?.toInt() ?? 0,
        magazaUrl: j['magazaUrl'] as String? ?? '',
        mesaj: j['mesaj'] as String? ?? '',
      );
}

class Duyuru {
  final int id;
  final String baslik;
  final String metin;
  final String? gorselUrl;
  final String? butonEtiket;
  final String? butonUrl;
  final DateTime? tarih;

  const Duyuru({
    required this.id,
    required this.baslik,
    required this.metin,
    this.gorselUrl,
    this.butonEtiket,
    this.butonUrl,
    this.tarih,
  });

  static Duyuru? fromJson(Map<String, dynamic> j) {
    final id = (j['id'] as num?)?.toInt();
    final b = j['baslik'] as String?;
    final m = j['metin'] as String?;
    if (id == null || b == null || b.isEmpty || m == null) return null;
    String? https(Object? v) {
      if (v is! String || v.isEmpty) return null;
      final u = Uri.tryParse(v);
      return (u != null && u.scheme == 'https') ? v : null;
    }

    return Duyuru(
      id: id,
      baslik: b,
      metin: m,
      gorselUrl: https(j['gorselUrl']),
      butonEtiket: (j['butonEtiket'] as String?)?.isNotEmpty == true ? j['butonEtiket'] as String : null,
      butonUrl: https(j['butonUrl']),
      // Sunucu: SQLite "YYYY-MM-DD HH:MM:SS" (UTC).
      tarih: j['tarih'] is String ? DateTime.tryParse('${(j['tarih'] as String).replaceFirst(' ', 'T')}Z')?.toLocal() : null,
    );
  }
}
