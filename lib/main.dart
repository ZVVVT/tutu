import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

void main() {
  runApp(const FolderGalleryApp());
}

class FolderGalleryApp extends StatelessWidget {
  const FolderGalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tutu',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF7C4DFF),
        useMaterial3: true,
      ),
      home: const GalleryHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class GalleryHomePage extends StatefulWidget {
  const GalleryHomePage({super.key});

  @override
  State<GalleryHomePage> createState() => _GalleryHomePageState();
}

class _GalleryHomePageState extends State<GalleryHomePage> {
  List<XFile> _files = [];

  Future<void> _pickImages() async {
    final images = XTypeGroup(
      label: 'images',
      extensions: ['jpg', 'jpeg', 'png', 'heic', 'heif', 'gif', 'bmp', 'webp'],
    );

    final result = await openFiles(
      acceptedTypeGroups: [images], // ← 保留这一行
    );

    if (!mounted) return;
    setState(() => _files = result);
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('图图 → 选择图片'),
        actions: [
          if (_files.isNotEmpty)
            IconButton(
              tooltip: '清空',
              onPressed: () => setState(() => _files = []),
              icon: const Icon(Icons.clear_all),
            ),
        ],
      ),
      body: _files.isEmpty
          ? const _EmptyHint()
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: _files.length,
              itemBuilder: (context, index) {
                final xf = _files[index];
                return _ImageTile(file: xf);
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickImages,
        label: const Text('选择图片'),
        icon: const Icon(Icons.add_photo_alternate_outlined),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '点右下角“选择图片”\n从“文件”App 选择多张图片预览',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _ImageTile extends StatelessWidget {
  const _ImageTile({required this.file});
  final XFile file;

  Future<Uint8List> _bytes() => file.readAsBytes();

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
          if (!snap.hasData) {
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
