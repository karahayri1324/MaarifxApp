import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../chat/chat_screen.dart';
import 'package:flutter/gestures.dart';
import '../../widgets/common/form_bits.dart';
import '../settings/privacy_policy_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _selectedClassLevel;
  bool _privacyAccepted = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _politikaTap.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_privacyAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Devam etmek için gizlilik politikasını kabul et'),
        ),
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.register(
      _emailController.text,
      _passwordController.text,
      _nameController.text,
      classLevel: _selectedClassLevel,
    );

    if (success && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ChatScreen()),
        (route) => false,
      );
    }
  }

  late final TapGestureRecognizer _politikaTap = TapGestureRecognizer()
    ..onTap = () {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
      );
    };

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
            baslik: 'Kayıt ol',
            alt: AltBaglanti(
              soru: 'Zaten hesabın var mı?',
              eylem: 'Giriş yap',
              onTap: () => Navigator.of(context).pop(),
            ),
            children: [
              Consumer<AuthProvider>(
                builder: (context, auth, child) {
                  if (auth.error == null) return const SizedBox.shrink();
                  return FormHata(metin: auth.error!, onKapat: auth.clearError);
                },
              ),
              const AlanEtiketi('Ad soyad'),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'Adın ve soyadın'),
                validator: (value) {
                  if (value == null || value.trim().length < 2) {
                    return 'Adını yaz';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
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
                decoration: InputDecoration(
                  hintText: 'En az 6 karakter',
                  suffixIcon: GozDugmesi(
                    gizli: _obscurePassword,
                    onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Şifre gerekli';
                  if (value.length < 6) return 'Şifre en az 6 karakter olmalı';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              const AlanEtiketi('Sınıf'),
              SinifSeridi(
                secili: _selectedClassLevel,
                onChanged: (v) => setState(() => _selectedClassLevel = v),
              ),
              const SizedBox(height: 14),

              // Gizlilik onayı: tek satır, politika adı dokununca açılır
              InkWell(
                onTap: () => setState(() => _privacyAccepted = !_privacyAccepted),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _privacyAccepted,
                        onChanged: (value) {
                          setState(() => _privacyAccepted = value ?? false);
                        },
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(
                            fontSize: 12.5,
                            color: context.textSecondary,
                            height: 1.45,
                          ),
                          children: [
                            TextSpan(
                              text: 'Gizlilik Politikası',
                              style: TextStyle(
                                color: context.blue,
                                decoration: TextDecoration.underline,
                              ),
                              recognizer: _politikaTap,
                            ),
                            const TextSpan(text: '\'nı okudum, kabul ediyorum.'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Consumer<AuthProvider>(
                builder: (context, auth, child) {
                  return ElevatedButton(
                    onPressed: auth.isLoading ? null : _handleRegister,
                    child: auth.isLoading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: context.onBlue),
                          )
                        : const Text('Kayıt ol'),
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
