import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'media_scanner.dart';
import 'dart:convert';

class ThumbnailCache {
  static Future<Directory> _dir() async {
    final base = await getTemporaryDirectory();
    final d = Directory(p.join(base.path, 'tutu_thumbs'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  static Future<File?> getThumb(MediaItem item, {int maxSize = 400}) async {
    final d = await _dir();
    final key = sha1.convert(utf8.encode('${item.path}:${item.modified.millisecondsSinceEpoch}:${item.size}')).toString();
    final out = File(p.join(d.path, '$key.jpg'));
    if (out.existsSync()) return out;

    if (item.isVideo) {
      final thumbPath = await VideoThumbnail.thumbnailFile(
        video: item.path,
        thumbnailPath: d.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: maxSize,
        quality: 75,
      );
      return thumbPath == null ? null : File(thumbPath);
    } else {
      final ext = p.extension(item.path).toLowerCase();
      // image 包暂不直接解 HEIC；先跳过，UI 用原文件 + cacheWidth 显示
      if (ext == '.heic' || ext == '.heif') return null;

      try {
        final bytes = await File(item.path).readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) return null;
        final resized = img.copyResize(decoded, width: maxSize);
        final jpg = img.encodeJpg(resized, quality: 80);
        await out.writeAsBytes(jpg, flush: false);
        return out;
      } catch (_) {
        return null;
      }
    }
  }
}
