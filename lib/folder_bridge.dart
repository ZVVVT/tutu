import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class TutuFolderBridge {
  static const MethodChannel _m = MethodChannel('tutu/folder');
  static const EventChannel _e = EventChannel('tutu/folderChanges');

  static bool get _isIOS => !kIsWeb && Platform.isIOS;

  static Future<Map<String, dynamic>?> selectFolder() async {
    if (!_isIOS) return null;
    final res = await _m.invokeMethod('selectFolder');
    return (res is Map) ? Map<String, dynamic>.from(res) : null;
  }

  static Future<Map<String, dynamic>?> currentFolder() async {
    if (!_isIOS) return null;
    final res = await _m.invokeMethod('currentFolder');
    return (res is Map) ? Map<String, dynamic>.from(res) : null;
  }

  static Future<List<Map<String, dynamic>>> listImages() async {
    if (!_isIOS) return <Map<String, dynamic>>[];
    final res = await _m.invokeMethod('listImages');
    if (res is List) {
      return res.cast<Map>().map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  static Stream<dynamic> changes() => _isIOS ? _e.receiveBroadcastStream() : const Stream.empty();
}
