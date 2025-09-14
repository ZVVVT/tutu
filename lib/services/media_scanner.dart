import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;

class MediaItem {
  final String path;
  final bool isVideo;
  final int size;
  final DateTime modified;

  MediaItem({required this.path, required this.isVideo, required this.size, required this.modified});
}

const _imageExt = {
  '.jpg','.jpeg','.png','.webp','.gif','.bmp','.tiff','.tif','.jxl','.raw','.dng','.cr2','.cr3','.arw','.nef','.raf','.nrw','.heic','.heif'
};
const _videoExt = {'.mp4','.mov','.m4v','.mkv','.avi','.webm','.3gp'};

Future<List<MediaItem>> scanMediaRecursively(String root) async {
  return Isolate.run(() {
    final items = <MediaItem>[];
    final dir = Directory(root);
    if (!dir.existsSync()) return items;
    final lister = dir.listSync(recursive: true, followLinks: false);
    for (final e in lister) {
      if (e is File) {
        final ext = p.extension(e.path).toLowerCase();
        final isImg = _imageExt.contains(ext);
        final isVid = _videoExt.contains(ext);
        if (!isImg && !isVid) continue;
        final stat = e.statSync();
        items.add(MediaItem(
          path: e.path,
          isVideo: isVid,
          size: stat.size,
          modified: stat.modified,
        ));
      }
    }
    items.sort((a, b) => b.modified.compareTo(a.modified));
    return items;
  });
}
