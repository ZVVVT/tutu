import 'dart:async';
import 'dart:typed_data';
import 'dart:io' as io show File; // 仅在非 Web 平台会实际使用
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'folder_bridge.dart';

void main() => runApp(const TutuApp());

class TutuApp extends StatelessWidget {
  const TutuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tutu',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF7C4DFF),
        useMaterial3: true,
      ),
      home: const FolderGalleryPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class FolderGalleryPage extends StatefulWidget {
  const FolderGalleryPage({super.key});

  @override
  State<FolderGalleryPage> createState() => _FolderGalleryPageState();
}

class _FolderGalleryPageState extends State<FolderGalleryPage> {
  String? _folderName;
  String? _folderPath;
  List<String> _paths = [];
  StreamSubscription? _sub;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _restore();
    // iOS 下监听原生目录变化；Web/其他平台返回空流
    _sub = TutuFolderBridge.changes().listen((_) => _reload());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _restore() async {
    final f = await TutuFolderBridge.currentFolder();
    if (f != null) {
      setState(() {
        _folderName = f['name'];
        _folderPath = f['path'];
      });
      _reload();
    }
  }

  Future<void> _pickFolder() async {
    final f = await TutuFolderBridge.selectFolder();
    if (f == null) return; // Web/非 iOS 会直接返回 null
    setState(() {
      _folderName = f['name'];
      _folderPath = f['path'];
    });
    await _reload();
  }

  Future<void> _reload() async {
    if (_folderPath == null) return;
    if (_loading) return;
    setState(() => _loading = true);
    final rows = await TutuFolderBridge.listImages(); // Web/非 iOS 返回 []
    setState(() {
      _paths = rows.map((e) => e['path'] as String).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = _folderName == null ? '图图 · 选择文件夹' : '图图 · $_folderName';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: '选择文件夹',
            onPressed: _pickFolder,
            icon: const Icon(Icons.folder_open),
          ),
          if (_folderPath != null)
            IconButton(
              tooltip: '刷新',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: _folderPath == null
          ? const _EmptyHint()
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _paths.isEmpty
                  ? const _EmptyFolderHint()
                  : GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemCount: _paths.length,
                      itemBuilder: (context, i) => _ImageTile(path: _paths[i]),
                    ),
      floatingActionButton: _folderPath == null
          ? FloatingActionButton.extended(
              onPressed: _pickFolder,
              label: const Text('选择文件夹'),
              icon: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '点右上角“选择文件夹”\n像系统照片一样预览该文件夹中的图片',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _EmptyFolderHint extends StatelessWidget {
  const _EmptyFolderHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '这个文件夹里没有可预览的图片\n支持：jpg/jpeg/png/gif/webp/bmp/heic/heif',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.path});
  final String path;

  Future<Uint8List> _bytes() async {
    if (kIsWeb) return Uint8List(0); // Web：不读取本地文件，返回空占位
    return io.File(path).readAsBytes();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FutureBuilder<Uint8List>(
        future: _bytes(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const ColoredBox(color: Color(0x11000000));
          }
          if (!snap.hasData || snap.data!.isEmpty) {
            return const Center(child: Icon(Icons.broken_image_outlined));
          }
          return Image.memory(
            snap.data!,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.low,
          );
        },
      ),
    );
  }
}
