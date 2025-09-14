import 'dart:io';
import 'package:flutter/material.dart';
import 'services/folder_access.dart';
import 'services/media_scanner.dart';
import 'services/thumbnail_cache.dart';

void main() {
  runApp(const TutuApp());
}

class TutuApp extends StatelessWidget {
  const TutuApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tutu',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const GalleryPage(),
    );
  }
}

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});
  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  String? rootPath;
  List<MediaItem> items = [];
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final path = await FolderAccess.restoreRoot();
    if (path != null && Directory(path).existsSync()) {
      setState(() => rootPath = path);
      await _scan();
    }
  }

  Future<void> _pickFolder() async {
    final path = await FolderAccess.pickRoot();
    if (path != null) {
      setState(() => rootPath = path);
      await _scan();
    }
  }

  Future<void> _scan() async {
    final root = rootPath;
    if (root == null) return;
    setState(() => loading = true);
    try {
      final result = await scanMediaRecursively(root);
      if (!mounted) return;
      setState(() {
        items = result;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('读取失败：$e')),
      );
    }
  }


  @override
  void dispose() {
    FolderAccess.releaseAccess();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRoot = rootPath != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(hasRoot ? (rootPath!.split('/').last.isEmpty ? rootPath! : rootPath!.split('/').last) : '选择根目录'),
        actions: [
          if (hasRoot) IconButton(onPressed: _scan, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _pickFolder, icon: const Icon(Icons.folder_open)),
        ],
      ),
      body: !hasRoot
          ? Center(
              child: FilledButton.icon(
                onPressed: _pickFolder,
                icon: const Icon(Icons.folder_open),
                label: const Text('选择照片根目录'),
              ),
            )
          : loading
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? const Center(child: Text('空空如也，换个目录试试～'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(6),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) => _GridTile(item: items[i]),
                    ),
    );
  }
}

class _GridTile extends StatelessWidget {
  final MediaItem item;
  const _GridTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File?>(
      future: ThumbnailCache.getThumb(item, maxSize: 480),
      builder: (context, snap) {
        Widget child;

        if (snap.hasData && snap.data != null) {
          child = Image.file(snap.data!, fit: BoxFit.cover);
        } else {
          // 缩略图尚无：用原图/视频占位（图像：用cacheWidth减压；视频：图标）
          if (!item.isVideo) {
            child = Image.file(
              File(item.path),
              fit: BoxFit.cover,
              // 重要：降低原图解码尺寸，避免巨图卡顿/爆内存
              cacheWidth: 480,
            );
          } else {
            child = const ColoredBox(color: Colors.black12);
          }
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (item.isVideo)
              const Align(
                alignment: Alignment.center,
                child: Icon(Icons.play_circle_outline, size: 36),
              ),
          ],
        );
      },
    );
  }
}
