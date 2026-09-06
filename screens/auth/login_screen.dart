import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/form_bits.dart';
import '../chat/chat_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.signIn(
      _emailController.text,
      _passwordController.text,
    );

    if (success && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ChatScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce e-posta adresini yaz')),
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.resetPassword(email);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Şifre sıfırlama e-postası gönderildi'
                : authProvider.error ?? 'Bir hata oluştu',
          ),
        ),
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
            baslik: 'Giriş yap',
            alt: AltBaglanti(
              soru: 'Hesabın yok mu?',
              eylem: 'Kayıt ol',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RegisterScreen()),
                );
              },
            ),
            children: [
              Consumer<AuthProvider>(
                builder: (context, auth, child) {
                  if (auth.error == null) return const SizedBox.shrink();
                  return FormHata(metin: auth.error!, onKapat: auth.clearError);
                },
              ),
              const AlanEtiketi('E-posta'),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: const InputDecoration(hintText: 'ornek@eposta.com'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'E-posta adresi gerekli';
                  }
                  if (!value.contains('@')) {
                    return 'Geçerli bir e-posta adresi yaz';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              const AlanEtiketi('Şifre'),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _handleLogin(),
                decoration: InputDecoration(
                  hintText: 'Şifren',
                  suffixIcon: GozDugmesi(
                    gizli: _obscurePassword,
                    onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Şifre gerekli';
                  return null;
                },
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _handleForgotPassword,
                  style: TextButton.styleFrom(
                    foregroundColor: context.textSecondary,
                    textStyle: const TextStyle(fontFamily: AppTheme.fontSans, fontSize: 13, fontWeight: FontWeight.w400),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Şifremi unuttum'),
                ),
              ),
              const SizedBox(height: 8),
              Consumer<AuthProvider>(
                builder: (context, auth, child) {
                  return ElevatedButton(
                    onPressed: auth.isLoading ? null : _handleLogin,
                    child: auth.isLoading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: context.onBlue),
                          )
                        : const Text('Giriş yap'),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
