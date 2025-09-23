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
    final res = await _m.invokeMethod<Map>('pickDirectory');
    if (res == null) return null;
    return Map<String, dynamic>.from(res);
  }

  static Future<Map<String, dynamic>?> openDirectory(String path) async {
    if (!_isIOS) return null;
    final res = await _m.invokeMethod<Map>('openDirectory', {'path': path});
    if (res == null) return null;
    return Map<String, dynamic>.from(res);
  }

  static Future<bool> revokeAccess(String identifier) async {
    if (!_isIOS) return false;
    final res = await _m.invokeMethod<bool>('revokeAccess', {'id': identifier});
    return res ?? false;
  }

  static Future<List<Map<String, dynamic>>> listBookmarks() async {
    if (!_isIOS) return const [];
    final res = await _m.invokeMethod<List>('listBookmarks');
    if (res == null) return const [];
    return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Stream<Map<String, dynamic>> get folderChanges =>
      _isIOS ? _e.receiveBroadcastStream() : const Stream.empty();
}
