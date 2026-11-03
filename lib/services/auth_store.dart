import 'package:flutter/foundation.dart';
import 'backend_api.dart';

class AuthStore extends ChangeNotifier {
  AuthStore._() {
    _api.onUnauthorized = () {
      user = null;
      notifyListeners();
    };
  }

  static final AuthStore instance = AuthStore._();
  final BackendApi _api = BackendApi.instance;
  Map<String, dynamic>? user;

  bool get isAuthenticated => _api.isAuthenticated;
  bool get isAdmin => user?['role'] == 'admin';

  Future<void> login(String email, String password) async {
    user = await _api.login(email, password);
    notifyListeners();
  }

  Future<void> register(String email, String password) async {
    user = await _api.register(email, password);
    notifyListeners();
  }

  void logout() {
    _api.logout();
    user = null;
    notifyListeners();
  }
}
