import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FolderAccess {
  static const _channel = MethodChannel('io.tutu/bookmarks');
  static const _prefsKey = 'tutu.root.path';

  /// 选择根目录（iOS 走原生，其他平台走 file_selector）
  static Future<String?> pickRoot() async {
    if (Platform.isIOS) {
      final res = await _channel.invokeMethod<dynamic>('pickFolder');
      if (res is Map && res['path'] is String) {
        final path = res['path'] as String;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, path);
        return path;
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

  /// 恢复持久授权并返回路径（iOS）；其他平台直接读缓存路径
  static Future<String?> restoreRoot() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_prefsKey);
    if (Platform.isIOS) {
      final restored = await _channel.invokeMethod<String?>('restoreBookmark');
      // 若失败则回落到缓存路径（可能已失效，UI 层会提示重新选择）
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
