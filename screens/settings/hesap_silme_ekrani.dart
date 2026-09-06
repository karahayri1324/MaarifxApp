import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/theme.dart';
import '../../widgets/common/form_bits.dart';

/// Hesap silme onayı — ÜÇ AYRI KAPI.
///
/// Eskiden ayarlardaki satıra dokunup tek bir "Sil" düğmesine basmak yetiyordu;
/// yanlışlıkla silinen hesabın geri dönüşü yok. Burada kullanıcı sırasıyla
/// (1) hesabının e-postasını, (2) şifresini yazar ve (3) onay cümlesini
/// harfi harfine kopyalar. Üçü de tamam olmadan düğme açılmaz.
///
/// ÖNEMLİ: bu yalnız arayüz freni değil — e-posta ve şifre sunucuya gider,
/// `DELETE /api/auth/delete-account` ikisini de doğrular. Yani eski bir
/// istemciyle ya da doğrudan istek atarak bu adım atlanamaz.
///
/// Geri döndürdüğü değer: onaylandıysa (eposta, şifre); iptalde null.
class HesapSilmeEkrani extends StatefulWidget {
  final String hesapEpostasi;
  const HesapSilmeEkrani({super.key, required this.hesapEpostasi});

  /// Kullanıcının harfi harfine yazması gereken cümle.
  static const String onayCumlesi = 'HESABIMI SİL';

  @override
  State<HesapSilmeEkrani> createState() => _HesapSilmeEkraniState();
}

class _HesapSilmeEkraniState extends State<HesapSilmeEkrani> {
  final _eposta = TextEditingController();
  final _sifre = TextEditingController();
  final _onay = TextEditingController();
  bool _sifreGizli = true;
  bool _calisiyor = false;

  @override
  void dispose() {
    _eposta.dispose();
    _sifre.dispose();
    _onay.dispose();
    super.dispose();
  }

  bool get _epostaTamam =>
      _eposta.text.trim().toLowerCase() ==
      widget.hesapEpostasi.trim().toLowerCase();
  bool get _sifreTamam => _sifre.text.isNotEmpty;
  bool get _onayTamam =>
      _onay.text.trim() == HesapSilmeEkrani.onayCumlesi;
  bool get _hazir => _epostaTamam && _sifreTamam && _onayTamam && !_calisiyor;

  void _sil() {
    if (!_hazir) return;
    setState(() => _calisiyor = true);
    Navigator.of(context).pop((
      eposta: _eposta.text.trim(),
      sifre: _sifre.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgSecondary,
      appBar: AppBar(
        backgroundColor: context.bgSecondary,
        elevation: 0,
        title: const Text('Hesabı sil'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            // Ne kaybedileceği açıkça yazılı olsun.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: context.pen),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bu işlem geri alınamaz',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.pen,
                      )),
                  const SizedBox(height: 8),
                  Text(
                    'Hesabın, bütün sohbetlerin, çizimli çözümlerin ve '
                    'yüklediğin fotoğraflar kalıcı olarak silinir. '
                    'Geri getirmenin bir yolu yok; aynı e-postayla yeniden '
                    'kayıt olsan bile eski içeriğin gelmez.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: context.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),

            const AlanEtiketi('Hesabının e-postası'),
            const SizedBox(height: 6),
            TextField(
              controller: _eposta,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() {}),
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              decoration: InputDecoration(
                hintText: widget.hesapEpostasi,
                errorText: _eposta.text.isEmpty || _epostaTamam
                    ? null
                    : 'Bu, hesabının e-postası değil',
              ),
            ),
            const SizedBox(height: 18),

            const AlanEtiketi('Şifren'),
            const SizedBox(height: 6),
            TextField(
              controller: _sifre,
              obscureText: _sifreGizli,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => setState(() {}),
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              decoration: InputDecoration(
                hintText: 'Şifreni gir',
                suffixIcon: GozDugmesi(
                  gizli: _sifreGizli,
                  onTap: () => setState(() => _sifreGizli = !_sifreGizli),
                ),
              ),
            ),
            const SizedBox(height: 18),

            const AlanEtiketi('Onay'),
            const SizedBox(height: 6),
            Text(
              'Silmek istediğinden eminsen aşağıya '
              '“${HesapSilmeEkrani.onayCumlesi}” yaz.',
              style: TextStyle(fontSize: 13, color: context.textSecondary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _onay,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [LengthLimitingTextInputFormatter(24)],
              onChanged: (_) => setState(() {}),
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              decoration: const InputDecoration(
                hintText: HesapSilmeEkrani.onayCumlesi,
              ),
            ),
            const SizedBox(height: 28),

            FilledButton(
              onPressed: _hazir ? _sil : null,
              style: FilledButton.styleFrom(
                backgroundColor: context.pen,
                foregroundColor: Colors.white,
                disabledBackgroundColor: context.bgTertiary,
                disabledForegroundColor: context.textMuted,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                textStyle: const TextStyle(
                  fontFamily: AppTheme.fontSans,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Hesabımı kalıcı olarak sil'),
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Vazgeç',
                    style: TextStyle(
                      fontFamily: AppTheme.fontSans,
                      fontSize: 14,
                      color: context.textSecondary,
                    )),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
