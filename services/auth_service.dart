import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/user_model.dart';

class AuthResult {
  final UserModel user;
  final String token;

  AuthResult({required this.user, required this.token});
}

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user';
  static const String _guestKey = 'is_guest';
  static const String _deviceIdKey = 'guest_device_id';

  String get _baseUrl => AppConfig.apiUrl;

  /// SharedPreferences'tan kayitli token'i oku
  Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// Token ve user bilgisini kaydet (guest flag'leri temizle)
  Future<void> _saveAuth(String token, UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode({
      'uid': user.uid,
      'email': user.email,
      'displayName': user.displayName,
      'schoolName': user.schoolName,
      'classLevel': user.classLevel,
      'role': user.role,
    }));
    // Guest oturumunu temizle - yoksa auto-login guest sanip token'i bozar
    await prefs.remove(_guestKey);
    await prefs.remove(_deviceIdKey);
  }

  /// Kayitli auth bilgisini sil
  Future<void> _clearAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_guestKey);
    await prefs.remove(_deviceIdKey);
  }

  /// Lokal olarak kayitli user bilgisini oku (offline fallback)
  Future<UserModel?> _getSavedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);
    if (userJson == null) return null;
    try {
      final data = jsonDecode(userJson) as Map<String, dynamic>;
      return UserModel(
        uid: data['uid'] as String,
        email: data['email'] as String,
        displayName: data['displayName'] as String?,
        schoolName: data['schoolName'] as String?,
        classLevel: data['classLevel'] as String?,
        role: data['role'] as String? ?? 'user',
      );
    } catch (e) {
      return null;
    }
  }

  /// Auto-login: Kayitli token ile /api/auth/me kontrol et
  Future<AuthResult?> tryAutoLogin() async {
    final token = await getSavedToken();
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/auth/me'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(AppConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final user = UserModel(
          uid: data['userId'] as String,
          email: data['email'] as String,
          displayName: data['displayName'] as String?,
          schoolName: data['schoolName'] as String?,
          classLevel: data['classLevel'] as String?,
          role: data['role'] as String? ?? 'user',
        );
        await _saveAuth(token, user);
        return AuthResult(user: user, token: token);
      } else {
        // Token gecersiz, temizle
        await _clearAuth();
        return null;
      }
    } catch (e) {
      // Network hatasi - offline fallback: lokal user bilgisini kullan
      debugPrint('[AuthService] Auto-login network error, trying offline: $e');
      final savedUser = await _getSavedUser();
      if (savedUser != null) {
        return AuthResult(user: savedUser, token: token);
      }
      return null;
    }
  }

  /// Email + password ile giris
  Future<AuthResult> signInWithEmail(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'password': password,
        }),
      ).timeout(AppConfig.connectionTimeout);

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        final user = UserModel(
          uid: data['userId'] as String,
          email: data['email'] as String,
          displayName: data['displayName'] as String?,
          schoolName: data['schoolName'] as String?,
          classLevel: data['classLevel'] as String?,
          role: data['role'] as String? ?? 'user',
        );
        final token = data['token'] as String;
        await _saveAuth(token, user);
        return AuthResult(user: user, token: token);
      } else {
        throw _handleApiError(response.statusCode, data);
      }
    } on http.ClientException {
      throw 'Bağlantı hatası. İnternet bağlantınızı kontrol edin.';
    } catch (e) {
      if (e is String) rethrow;
      throw 'Bağlantı hatası. İnternet bağlantınızı kontrol edin.';
    }
  }

  /// Yeni hesap olustur
  Future<AuthResult> registerWithEmail(
    String email,
    String password,
    String displayName, {
    String? classLevel,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email.trim(),
          'password': password,
          'displayName': displayName.trim(),
          if (classLevel != null) 'classLevel': classLevel,
        }),
      ).timeout(AppConfig.connectionTimeout);

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 201) {
        final user = UserModel(
          uid: data['userId'] as String,
          email: data['email'] as String,
          displayName: data['displayName'] as String?,
          schoolName: data['schoolName'] as String?,
          classLevel: data['classLevel'] as String?,
          role: data['role'] as String? ?? 'user',
        );
        final token = data['token'] as String;
        await _saveAuth(token, user);
        return AuthResult(user: user, token: token);
      } else {
        throw _handleApiError(response.statusCode, data);
      }
    } on http.ClientException {
      throw 'Bağlantı hatası. İnternet bağlantınızı kontrol edin.';
    } catch (e) {
      if (e is String) rethrow;
      throw 'Bağlantı hatası. İnternet bağlantınızı kontrol edin.';
    }
  }

  /// Misafir token al
  Future<AuthResult> getGuestToken(String deviceId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl${AppConfig.guestTokenEndpoint}'),
        headers: {
          'Content-Type': 'application/json',
          'x-device-id': deviceId,
        },
      ).timeout(AppConfig.connectionTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token = data['token'] as String;
        final userId = data['userId'] as String;
        final user = UserModel(
          uid: userId,
          email: 'guest@maarifx.com',
          displayName: 'Misafir',
          role: 'guest',
        );
        await _saveGuestAuth(token, deviceId);
        return AuthResult(user: user, token: token);
      } else {
        throw 'Misafir girişi başarısız oldu.';
      }
    } catch (e) {
      if (e is String) rethrow;
      throw 'Bağlantı hatası. İnternet bağlantınızı kontrol edin.';
    }
  }

  /// Misafir auth bilgisini kaydet
  Future<void> _saveGuestAuth(String token, String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setBool(_guestKey, true);
    await prefs.setString(_deviceIdKey, deviceId);
  }

  /// Kayitli misafir oturumu var mi?
  Future<bool> isGuestSession() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_guestKey) ?? false;
  }

  /// Kayitli device ID'yi oku
  Future<String?> getSavedDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_deviceIdKey);
  }

  /// Cikis yap
  Future<void> signOut() async {
    await _clearAuth();
  }

  /// API hata mesajlarini Turkce'ye cevir
  String _handleApiError(int statusCode, Map<String, dynamic> data) {
    final error = data['error'] as String? ?? '';

    if (statusCode == 401) {
      if (error.contains('Invalid password') || error.contains('password')) {
        return 'Hatalı şifre girdiniz.';
      }
      if (error.contains('not found') || error.contains('No user')) {
        return 'Bu e-posta adresiyle kayıtlı kullanıcı bulunamadı.';
      }
      return 'E-posta veya şifre hatalı.';
    }

    if (statusCode == 409) {
      return 'Bu e-posta adresi zaten kullanımda.';
    }

    if (statusCode == 400) {
      if (error.contains('password') && error.contains('6')) {
        return 'Şifre çok zayıf. En az 6 karakter kullanın.';
      }
      return 'Geçersiz bilgi girdiniz.';
    }

    if (statusCode == 429) {
      return 'Çok fazla deneme yaptınız. Lütfen daha sonra tekrar deneyin.';
    }

    return 'Bir hata oluştu: $error';
  }
}
