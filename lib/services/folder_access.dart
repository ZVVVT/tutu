import 'dart:io';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FolderAccess {
  static const _channel = MethodChannel('io.tutu/bookmarks');
  static const _prefsKey = 'tutu.root.path';

  static Future<String?> pickRoot() async {
    if (Platform.isIOS) {
      final res = await _channel.invokeMethod<dynamic>('pickFolder');
      if (res is Map && res['path'] is String) {
        final path = res['path'] as String;

        // 记住路径
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, path);

        // 关键：当次会话立刻恢复书签，真正开启安全域访问
        final restored = await _channel.invokeMethod<String?>('restoreBookmark');
        return restored ?? path;
      }
      return null;
    } else {
      final path = await getDirectoryPath(confirmButtonText: '选择文件夹');
      if (path != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, path);
      }
      return path;
    }
  }

  static Future<String?> restoreRoot() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefsKey);
    if (Platform.isIOS) {
      final restored = await _channel.invokeMethod<String?>('restoreBookmark');
      return restored ?? cached;
    }
    return cached;
  }

  static Future<void> releaseAccess() async {
    if (Platform.isIOS) {
      await _channel.invokeMethod('releaseBookmark');
    }
  }
}
