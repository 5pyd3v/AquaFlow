import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../errors/exceptions.dart';

/// Two-tier local persistence:
///  - `SharedPreferences` for small key/value flags (onboarding seen,
///    theme mode, last selected role).
///  - `Hive` boxes for structured offline caches (orders, products)
///    that need to survive app restarts and support pagination.
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  late SharedPreferences _prefs;
  late Box<String> _ordersBox;
  late Box<String> _productsBox;
  late Box<String> _userBox;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await Hive.initFlutter();
    _ordersBox = await Hive.openBox<String>(AppConfig.hiveOrdersBox);
    _productsBox = await Hive.openBox<String>(AppConfig.hiveProductsBox);
    _userBox = await Hive.openBox<String>(AppConfig.hiveUserBox);
  }

  // ---- SharedPreferences: simple flags ----
  bool get hasSeenOnboarding => _prefs.getBool('has_seen_onboarding') ?? false;
  Future<void> setSeenOnboarding() => _prefs.setBool('has_seen_onboarding', true);

  String? get activeRole => _prefs.getString('active_role');
  Future<void> setActiveRole(String role) => _prefs.setString('active_role', role);
  Future<void> clearActiveRole() => _prefs.remove('active_role');

  String get themeMode => _prefs.getString('theme_mode') ?? 'system';
  Future<void> setThemeMode(String mode) => _prefs.setString('theme_mode', mode);

  Future<void> clearAll() async {
    await _prefs.clear();
    await _ordersBox.clear();
    await _productsBox.clear();
    await _userBox.clear();
  }

  // ---- Hive: structured JSON caches ----
  Future<void> cacheJson(Box<String> box, String key, Map<String, dynamic> json) async {
    try {
      await box.put(key, jsonEncode(json));
    } catch (e) {
      throw CacheException('Failed to cache $key: $e');
    }
  }

  Map<String, dynamic>? readJson(Box<String> box, String key) {
    final raw = box.get(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> readAllJson(Box<String> box) {
    return box.values
        .map((raw) {
          try {
            return jsonDecode(raw) as Map<String, dynamic>;
          } catch (_) {
            return null;
          }
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  Box<String> get ordersBox => _ordersBox;
  Box<String> get productsBox => _productsBox;
  Box<String> get userBox => _userBox;
}
