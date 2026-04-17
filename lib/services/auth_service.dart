import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class AuthService extends ChangeNotifier {
  String? _token;
  String? _refreshToken;
  Map<String, dynamic>? _user;
  bool _initialized = false;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get isLoggedIn => _token != null;
  bool get initialized => _initialized;
  int? get userId => _user?['id'];
  String? get nickname => _user?['nickname'];
  String? get avatarUrl => _user?['avatarUrl'];

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('im_token');
    _refreshToken = prefs.getString('im_refresh_token');
    final userStr = prefs.getString('im_user');
    if (userStr != null) {
      _user = jsonDecode(userStr);
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> setAuth(Map<String, dynamic> data) async {
    _token = data['token']['accessToken'];
    _refreshToken = data['token']['refreshToken'];
    _user = data['user'];

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('im_token', _token!);
    await prefs.setString('im_refresh_token', _refreshToken!);
    await prefs.setString('im_user', jsonEncode(_user));
    notifyListeners();
  }

  Future<void> updateUser(Map<String, dynamic> userData) async {
    _user = userData;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('im_user', jsonEncode(_user));
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _refreshToken = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('im_token');
    await prefs.remove('im_refresh_token');
    await prefs.remove('im_user');
    notifyListeners();
  }
}
