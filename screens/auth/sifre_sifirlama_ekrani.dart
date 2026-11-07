import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/common/form_bits.dart';
import '../../widgets/common/ui_bits.dart';
import '../chat/chat_screen.dart';

/// ŞİFREMİ UNUTTUM (2026-11-08) — iki adım, tek ekran:
///  1) e-posta → "Kod gönder" (sunucu 6 haneli kodu e-postalar, 15 dk geçerli)
///  2) kod + yeni şifre (iki kez) → şifre değişir, kullanıcı yeni şifreyle
///     otomatik giriş yapar ve sohbete geçer.
class SifreSifirlamaEkrani extends StatefulWidget {
  final String baslangicEposta;
  final AuthService? servis; // testler sahte servis verir

  const SifreSifirlamaEkrani({super.key, this.baslangicEposta = '', this.servis});

  @override
  State<SifreSifirlamaEkrani> createState() => _SifreSifirlamaEkraniState();
}

class _SifreSifirlamaEkraniState extends State<SifreSifirlamaEkrani> {
  static const int _bekleme = 60; // "Kodu tekrar gönder" için saniye

  late final AuthService _servis = widget.servis ?? AuthService();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _eposta = TextEditingController(text: widget.baslangicEposta.trim());
  final _kod = TextEditingController();
  final _sifre = TextEditingController();
  final _sifre2 = TextEditingController();

  bool _kodGonderildi = false;
  bool _mesgul = false;
  bool _gizli = true;
  String? _hata;
  int _geriSayim = 0;
  Timer? _sayac;

  @override
  void dispose() {
    _sayac?.cancel();
    _eposta.dispose();
    _kod.dispose();
    _sifre.dispose();
    _sifre2.dispose();
    super.dispose();
  }

  void _sayaciBaslat() {
    _sayac?.cancel();
    setState(() => _geriSayim = _bekleme);
    _sayac = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _geriSayim = (_geriSayim - 1).clamp(0, _bekleme));
      if (_geriSayim == 0) t.cancel();
    });
  }

  String? _epostaDogrula(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'E-posta adresi gerekli';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s)) return 'Geçerli bir e-posta adresi yaz';
    return null;
  }

  Future<void> _kodGonder() async {
    if (_epostaDogrula(_eposta.text) != null) {
      _formKey.currentState!.validate();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    final r = await _servis.sifreKoduIste(_eposta.text);
    if (!mounted) return;
    setState(() {
      _mesgul = false;
      if (r.ok) {
        _kodGonderildi = true;
      } else {
        _hata = r.mesaj;
      }
    });
    if (r.ok) _sayaciBaslat();
  }

  Future<void> _sifirla() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _mesgul = true;
      _hata = null;
    });
    final r = await _servis.sifreSifirla(_eposta.text, _kod.text, _sifre.text);
    if (!mounted) return;
    if (!r.ok) {
      setState(() {
        _mesgul = false;
        _hata = r.mesaj;
      });
      return;
    }
    // Şifre değişti → yeni şifreyle giriş yap.
    final auth = context.read<AuthProvider>();
    final girdi = await auth.signIn(_eposta.text.trim(), _sifre.text);
    if (!mounted) return;
    if (girdi) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ChatScreen()),
        (route) => false,
      );
    } else {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şifren değişti. Yeni şifrenle giriş yapabilirsin.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgSecondary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: AuthIskelet(
            baslik: 'Şifreni sıfırla',
            alt: AltBaglanti(
              soru: 'Şifreni hatırladın mı?',
              eylem: 'Giriş yap',
              onTap: () => Navigator.of(context).pop(),
            ),
            children: _kodGonderildi ? _ikinciAdim(context) : _birinciAdim(context),
          ),
        ),
      ),
    );
  }

  Widget _gonderDugmesi(String yazi, VoidCallback onTap, {Key? key}) => ElevatedButton(
        key: key,
        onPressed: _mesgul ? null : onTap,
        child: _mesgul
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: context.onBlue),
              )
            : Text(yazi),
      );

  List<Widget> _birinciAdim(BuildContext context) => [
        Text(
          'Hesabının e-posta adresini yaz. Sana 6 haneli bir doğrulama kodu gönderelim.',
          style: TextStyle(fontSize: 13.5, height: 1.5, color: context.textSecondary),
        ),
        const SizedBox(height: 18),
        if (_hata != null) FormHata(metin: _hata!, onKapat: () => setState(() => _hata = null)),
        const AlanEtiketi('E-posta'),
        TextFormField(
          key: const ValueKey('sifre_eposta'),
          controller: _eposta,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          onFieldSubmitted: (_) => _kodGonder(),
          decoration: const InputDecoration(hintText: 'ornek@eposta.com'),
          validator: _epostaDogrula,
        ),
        const SizedBox(height: 20),
        _gonderDugmesi('Kod gönder', _kodGonder, key: const ValueKey('sifre_kod_gonder')),
      ];

  List<Widget> _ikinciAdim(BuildContext context) => [
        SolCizgiSatiri(
          renk: context.blue,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: _eposta.text.trim(), style: const TextStyle(fontWeight: FontWeight.w600)),
                  const TextSpan(text: ' adresine bir kod gönderdik. Gelmediyse gereksiz (spam) klasörüne de bak.'),
                ]),
                style: TextStyle(fontSize: 13.5, height: 1.5, color: context.textSecondary),
              ),
              TextButton(
                onPressed: _mesgul
                    ? null
                    : () => setState(() {
                          _kodGonderildi = false;
                          _hata = null;
                          _kod.clear();
                        }),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: context.blue,
                  textStyle: const TextStyle(fontFamily: AppTheme.fontSans, fontSize: 13),
                ),
                child: const Text('E-postayı değiştir'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (_hata != null) FormHata(metin: _hata!, onKapat: () => setState(() => _hata = null)),
        const AlanEtiketi('Doğrulama kodu'),
        TextFormField(
          key: const ValueKey('sifre_kod'),
          controller: _kod,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          style: context.mono(fontSize: 20, color: context.textPrimary).copyWith(letterSpacing: 8),
          decoration: const InputDecoration(hintText: '······'),
          validator: (v) => (v ?? '').length == 6 ? null : '6 haneli kodu yaz',
        ),
        const SizedBox(height: 12),
        const AlanEtiketi('Yeni şifre'),
        TextFormField(
          key: const ValueKey('sifre_yeni'),
          controller: _sifre,
          obscureText: _gizli,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: 'En az 6 karakter',
            suffixIcon: GozDugmesi(gizli: _gizli, onTap: () => setState(() => _gizli = !_gizli)),
          ),
          validator: (v) => (v ?? '').length >= 6 ? null : 'Şifre en az 6 karakter olmalı',
        ),
        const SizedBox(height: 12),
        const AlanEtiketi('Yeni şifre (tekrar)'),
        TextFormField(
          key: const ValueKey('sifre_yeni2'),
          controller: _sifre2,
          obscureText: _gizli,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _sifirla(),
          decoration: const InputDecoration(hintText: 'Yeni şifreni tekrar yaz'),
          validator: (v) => v == _sifre.text ? null : 'Şifreler aynı değil',
        ),
        const SizedBox(height: 20),
        _gonderDugmesi('Şifreyi değiştir', _sifirla, key: const ValueKey('sifre_degistir')),
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            key: const ValueKey('sifre_tekrar_gonder'),
            onPressed: (_mesgul || _geriSayim > 0) ? null : _kodGonder,
            style: TextButton.styleFrom(
              foregroundColor: context.textSecondary,
              textStyle: const TextStyle(fontFamily: AppTheme.fontSans, fontSize: 13),
            ),
            child: Text(_geriSayim > 0 ? 'Kodu tekrar gönder (${_geriSayim}s)' : 'Kodu tekrar gönder'),
          ),
        ),
      ];
}
