import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';
import '../models/user_model.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final AuthService _authService;

  AuthStatus _status = AuthStatus.unknown;
  UserModel? _user;
  String? _token;
  String? _error;
  bool _isLoading = false;
  bool _isGuest = false;
  String? _deviceId;
  // Misafirin cihaza yazılmış sınıf seviyesi. Kayıtlı kullanıcıda seviye
  // HESABIN kendisidir (sunucu users.class_level'i kullanır, istemciyi yok sayar);
  // misafirde sunucu tarafında kayıt olmadığı için kaynak burasıdır.
  String? _guestClassLevel;

  AuthProvider({AuthService? authService})
      : _authService = authService ?? AuthService() {
    _init();
  }

  AuthStatus get status => _status;
  UserModel? get user => _user;
  String? get token => _token;
  String? get error => _error;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isGuest => _isGuest;
  String? get deviceId => _deviceId;
  String? get guestClassLevel => _guestClassLevel;

  void _init() {
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
    try {
      // Misafir sinif seviyesi: auto-login sonucundan BAGIMSIZ okunur (token
      // alinamasa bile cihazdaki secim bilinsin, kullaniciya tekrar sorulmasin).
      _guestClassLevel = await _authService.getGuestClassLevel();
    } catch (e) {
      debugPrint('[AuthProvider] Misafir sinif seviyesi okunamadi: $e');
    }
    try {
      // Oncelik: normal kullanici auto-login
      final result = await _authService.tryAutoLogin();
      if (result != null) {
        // Guest oturumu mu kontrol et
        final isGuestSession = await _authService.isGuestSession();
        if (isGuestSession) {
          _deviceId = await _authService.getSavedDeviceId();
          // Guest token suresi dolmus olabilir, yenile
          if (_deviceId != null) {
            try {
              final guestResult = await _authService.getGuestToken(_deviceId!);
              // Cihazdaki seviye kullaniciya islenir → user.classLevel okuyan
              // tum cagri noktalari (chat_screen gonderimleri) degismeden calisir.
              _user = _guestClassLevel == null
                  ? guestResult.user
                  : guestResult.user.copyWith(classLevel: _guestClassLevel);
              _token = guestResult.token;
              _isGuest = true;
              _status = AuthStatus.authenticated;
            } catch (e) {
              // Token yenilenemedi, misafir oturumunu temizle
              _status = AuthStatus.unauthenticated;
            }
          } else {
            _status = AuthStatus.unauthenticated;
          }
        } else {
          _user = result.user;
          _token = result.token;
          _isGuest = false;
          _status = AuthStatus.authenticated;
        }
      } else {
        _status = AuthStatus.unauthenticated;
      }
    } catch (e) {
      debugPrint('[AuthProvider] Auto-login error: $e');
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _authService.signInWithEmail(email, password);
      _user = result.user;
      _token = result.token;
      _isGuest = false;
      _status = AuthStatus.authenticated;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(String email, String password, String displayName, {String? classLevel}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _authService.registerWithEmail(email, password, displayName, classLevel: classLevel);
      _user = result.user;
      _token = result.token;
      _isGuest = false;
      _status = AuthStatus.authenticated;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> continueAsGuest(String deviceId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _authService.getGuestToken(deviceId);
      _guestClassLevel ??= await _authService.getGuestClassLevel();
      _user = _guestClassLevel == null
          ? result.user
          : result.user.copyWith(classLevel: _guestClassLevel);
      _token = result.token;
      _isGuest = true;
      _deviceId = deviceId;
      _status = AuthStatus.authenticated;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future<bool> resetPassword(String email) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    _error = 'Şifre sıfırlama şu anda desteklenmiyor. Lütfen yöneticiyle iletişime geçin.';
    _isLoading = false;
    notifyListeners();
    return false;
  }

  /// Misafirin sınıf seviyesini cihaza yaz + oturumdaki kullanıcıya işle.
  /// Kayıtlı kullanıcıda ÇAĞRILMAZ: orada seviye hesabın kendisidir ve ayarlardan
  /// (updateProfile) değişir; sunucu kayıtlı istekte istemcinin gönderdiğini
  /// yok sayıp users.class_level'i kullanır.
  Future<void> setGuestClassLevel(String classLevel) async {
    _guestClassLevel = classLevel;
    if (_user != null) {
      _user = _user!.copyWith(classLevel: classLevel);
    }
    notifyListeners();
    // Yazma en sona: hata olsa bile oturum içinde seçim geçerli kalır.
    try {
      await _authService.saveGuestClassLevel(classLevel);
    } catch (e) {
      debugPrint('[AuthProvider] Misafir sinif seviyesi yazilamadi: $e');
    }
  }

  void updateUser(UserModel updatedUser) {
    _user = updatedUser;
    notifyListeners();
  }

  Future<void> signOut() async {
    await _authService.signOut();
    _user = null;
    _token = null;
    _isGuest = false;
    _deviceId = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
