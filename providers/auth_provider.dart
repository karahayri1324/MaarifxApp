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

  void _init() {
    _tryAutoLogin();
  }

  Future<void> _tryAutoLogin() async {
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
              _user = guestResult.user;
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
      _user = result.user;
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
