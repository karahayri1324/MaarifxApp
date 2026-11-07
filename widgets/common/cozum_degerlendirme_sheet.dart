import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';
import '../../config/log.dart';
import '../../config/theme.dart';
import 'ui_bits.dart';

/// Çözüm değerlendirmesi (2026-11-08): öğrenci çözümü izleyip oynatıcıdan
/// ÇIKARKEN 1-5 puan + isteğe bağlı yorum. Oynatıcı (canvas.html) DEĞİŞMEDİ —
/// panel native; tetik PlayerScreen'in geri butonu / sistem geri hareketi.
///
/// Dönüş:
///  * `null`                      → panel kapatıldı (geri / aşağı kaydırma / dışarı
///                                  dokunma): kullanıcı oynatıcıda KALIR.
///  * `CozumPuani(gecildi: true)` → "Puanlamadan çık".
///  * `CozumPuani(puan: 1..5)`    → "Gönder ve çık".
class CozumPuani {
  final int puan;
  final String yorum;
  final bool gecildi;

  const CozumPuani({this.puan = 0, this.yorum = '', this.gecildi = false});
}

Future<CozumPuani?> showCozumDegerlendirmeSheet(BuildContext context) {
  return showModalBottomSheet<CozumPuani>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _DegerlendirmeSheet(),
  );
}

/// Kayıt + gönderim. Her istek için panel EN FAZLA BİR KEZ sorulur (gönderilse de
/// geçilse de işaretlenir); "vazgeç" (null) işaretlemez → sonraki çıkışta yine sorulur.
class CozumDegerlendirme {
  static const String _anahtar = 'cozum_degerlendirilen';
  static const int _tavan = 300; // en son N istek tutulur (prefs şişmesin)

  static Future<bool> sorulmaliMi(String requestId) async {
    if (requestId.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getStringList(_anahtar) ?? const []).contains(requestId);
    } catch (_) {
      return false; // prefs okunamıyorsa çıkışı engelleme
    }
  }

  static Future<void> isaretle(String requestId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final liste = List<String>.from(prefs.getStringList(_anahtar) ?? const []);
      liste.remove(requestId);
      liste.add(requestId);
      if (liste.length > _tavan) liste.removeRange(0, liste.length - _tavan);
      await prefs.setStringList(_anahtar, liste);
    } catch (_) {}
  }

  /// Arka planda gönderilir — çıkış ağı BEKLEMEZ (ekran kapanırken sürer).
  static Future<bool> gonder({
    required String token,
    required String requestId,
    required int puan,
    String yorum = '',
    bool canli = false,
  }) async {
    try {
      final r = await http
          .post(
            Uri.parse('${AppConfig.apiUrl}/api/ratings'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'requestId': requestId,
              'score': puan,
              'comment': yorum,
              'isLive': canli,
              'platform': Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : 'diger'),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) logD('[Puan] sunucu ${r.statusCode}: ${r.body}');
      return r.statusCode == 200;
    } catch (e) {
      logD('[Puan] gönderilemedi: $e');
      return false;
    }
  }
}

const List<String> _puanEtiketleri = ['Çok kötü', 'Kötü', 'İdare eder', 'İyi', 'Harika'];
const Color _yildizRengi = Color(0xFFF2B01E);

class _DegerlendirmeSheet extends StatefulWidget {
  const _DegerlendirmeSheet();

  @override
  State<_DegerlendirmeSheet> createState() => _DegerlendirmeSheetState();
}

class _DegerlendirmeSheetState extends State<_DegerlendirmeSheet> {
  int _puan = 0;
  final TextEditingController _yorum = TextEditingController();

  @override
  void dispose() {
    _yorum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Klavye açılınca panel yukarı kayar; yatay (landscape) oynatıcıda alan dar
    // olduğundan içerik kaydırılabilir.
    final klavye = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: klavye),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: SheetTutamac()),
              const SizedBox(height: 18),
              Text(
                'Çözümü nasıl buldun?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.2,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '1 ile 5 arasında puan ver.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: context.textSecondary),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 1; i <= 5; i++)
                    Semantics(
                      button: true,
                      selected: _puan == i,
                      label: '$i puan, ${_puanEtiketleri[i - 1]}',
                      child: InkResponse(
                        key: ValueKey('puan_$i'),
                        onTap: () => setState(() => _puan = i),
                        radius: 28,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            i <= _puan ? Icons.star_rounded : Icons.star_outline_rounded,
                            size: 40,
                            color: i <= _puan ? _yildizRengi : context.textMuted,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(
                height: 22,
                child: Center(
                  child: Text(
                    _puan == 0 ? '' : '$_puan · ${_puanEtiketleri[_puan - 1]}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('puan_yorum'),
                controller: _yorum,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Eklemek istediğin bir şey var mı? (isteğe bağlı)',
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                key: const ValueKey('puan_gonder'),
                onPressed: _puan == 0
                    ? null
                    : () => Navigator.of(context).pop(
                          CozumPuani(puan: _puan, yorum: _yorum.text.trim()),
                        ),
                child: const Text('Gönder ve çık'),
              ),
              const SizedBox(height: 4),
              TextButton(
                key: const ValueKey('puan_gec'),
                onPressed: () => Navigator.of(context).pop(const CozumPuani(gecildi: true)),
                child: const Text('Puanlamadan çık'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
