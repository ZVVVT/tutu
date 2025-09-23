import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class TutuFolderBridge {
  static const MethodChannel _m = MethodChannel('tutu/folder');
  static const EventChannel _e = EventChannel('tutu/folderChanges');

  static bool get _isIOS => !kIsWeb && Platform.isIOS;

  static Future<Map<String, dynamic>?> pickDirectory() async {
    if (!_isIOS) return null;
    final Map<Object?, Object?>? res = await _m.invokeMethod<Map<Object?, Object?>>('pickDirectory');
    if (res == null) return null;
    return Map<String, dynamic>.from(res);
  }

  static Future<Map<String, dynamic>?> openDirectory(String path) async {
    if (!_isIOS) return null;
    final Map<Object?, Object?>? res = await _m.invokeMethod<Map<Object?, Object?>>(
      'openDirectory',
      {'path': path},
    );
    if (res == null) return null;
    return Map<String, dynamic>.from(res);
  }

  static Future<bool> revokeAccess(String identifier) async {
    if (!_isIOS) return false;
    final bool? res = await _m.invokeMethod<bool>('revokeAccess', {'id': identifier});
    return res ?? false;
  }

  static Future<List<Map<String, dynamic>>> listBookmarks() async {
    if (!_isIOS) return const [];
    final List<Object?>? res = await _m.invokeMethod<List<Object?>>('listBookmarks');
    if (res == null) return const [];
    return res
        .whereType<Map>()
        .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Stream<Map<String, dynamic>> get folderChanges => _isIOS
      ? _e
          .receiveBroadcastStream()
          .where((e) => e != null)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
      : const Stream<Map<String, dynamic>>.empty();
}
